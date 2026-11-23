package speech

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/kiuvy-universe/kiupop/backend/internal/platform/httpserver"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/identity"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/ratelimit"
)

// Funnel receives the transcription milestone (numbers only).
type Funnel interface {
	Record(ctx context.Context, userID, sessionID, event string, meta map[string]int64)
}

// Limits bound abuse and cost.
type Limits struct {
	MaxBytes            int64
	MaxSeconds          int
	UserDailySeconds    int
	GlobalDailySeconds  int
	USDMicrosPerMinute  int64
	RequestsPerUserHour int
}

// Handler serves POST /api/v1/speech/transcriptions.
type Handler struct {
	t      Transcriber
	lim    Limits
	funnel Funnel
	log    *slog.Logger
	rate   *ratelimit.Limiter
	now    func() time.Time

	mu     sync.Mutex
	day    string
	user   map[string]int
	global int
}

// NewHandler builds the handler.
func NewHandler(t Transcriber, lim Limits, funnel Funnel, log *slog.Logger) *Handler {
	if lim.RequestsPerUserHour == 0 {
		lim.RequestsPerUserHour = 20
	}
	return &Handler{t: t, lim: lim, funnel: funnel, log: log, rate: ratelimit.New(lim.RequestsPerUserHour, time.Hour),
		now: time.Now, user: map[string]int{}}
}

// Register mounts the route for signed-in users.
func (h *Handler) Register(mux *http.ServeMux, requireUser func(http.Handler) http.Handler) {
	mux.Handle("POST /api/v1/speech/transcriptions", requireUser(http.HandlerFunc(h.transcribe)))
	mux.Handle("GET /api/v1/speech/status", requireUser(http.HandlerFunc(h.status)))
}

type statusOut struct {
	Enabled    bool   `json:"enabled"`
	Provider   string `json:"provider"`
	MaxSeconds int    `json:"max_seconds"`
	MaxBytes   int64  `json:"max_bytes"`
}

func (h *Handler) status(w http.ResponseWriter, _ *http.Request) {
	httpserver.WriteJSON(w, http.StatusOK, statusOut{Enabled: h.t.Provider() != "disabled", Provider: h.t.Provider(),
		MaxSeconds: h.lim.MaxSeconds, MaxBytes: h.lim.MaxBytes})
}

// Out is what the app shows for review before sending it to Kiu.
type Out struct {
	Text          string  `json:"text"`
	Provider      string  `json:"provider"`
	Language      string  `json:"language"`
	Confidence    float64 `json:"confidence"`
	DurationMs    int64   `json:"duration_ms"`
	LatencyMs     int64   `json:"latency_ms"`
	BilledSeconds int     `json:"billed_seconds"`
}

// reserve books seconds against the daily quotas (in memory: one instance).
func (h *Handler) reserve(userID string, secs int) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	if d := h.now().UTC().Format("2006-01-02"); d != h.day {
		h.day, h.user, h.global = d, map[string]int{}, 0
	}
	if h.user[userID]+secs > h.lim.UserDailySeconds || h.global+secs > h.lim.GlobalDailySeconds {
		return false
	}
	h.user[userID] += secs
	h.global += secs
	return true
}

func (h *Handler) transcribe(w http.ResponseWriter, r *http.Request) {
	u, _ := identity.FromContext(r.Context())
	if h.t.Provider() == "disabled" {
		httpserver.WriteError(w, http.StatusServiceUnavailable, "speech_unavailable",
			"La transcripción de audio no está disponible ahora. Podés escribirle a Kiu.")
		return
	}
	if !h.rate.Allow(u.ID) {
		httpserver.WriteError(w, http.StatusTooManyRequests, "rate_limited", "Enviaste muchos audios seguidos. Probá en un rato o escribile a Kiu.")
		return
	}
	data, err := io.ReadAll(http.MaxBytesReader(w, r.Body, h.lim.MaxBytes))
	if err != nil {
		httpserver.WriteError(w, http.StatusRequestEntityTooLarge, "audio_too_large", "El audio es muy largo. Grabá hasta un minuto.")
		return
	}
	a, err := Inspect(data, time.Duration(h.lim.MaxSeconds)*time.Second)
	if err != nil {
		h.fail(w, err)
		return
	}
	secs := int(a.Duration/time.Second) + 1
	if a.Duration == 0 { // opus: bound by size (about 4 KB/s at the app's bitrate)
		secs = int(len(data)/4096) + 1
		if secs > h.lim.MaxSeconds {
			h.fail(w, ErrTooLong)
			return
		}
	}
	if !h.reserve(u.ID, secs) {
		httpserver.WriteError(w, http.StatusTooManyRequests, "speech_quota",
			"Llegamos al límite de audio por hoy en la demo. Podés escribirle a Kiu.")
		return
	}
	_ = http.NewResponseController(w).SetWriteDeadline(time.Now().Add(45 * time.Second))
	ctx, cancel := context.WithTimeout(r.Context(), 40*time.Second)
	defer cancel()
	start := h.now()
	res, err := h.t.Transcribe(ctx, a)
	latency := h.now().Sub(start)
	billed := res.BilledSeconds
	if billed == 0 {
		billed = secs
	}
	cost := int64(billed) * h.lim.USDMicrosPerMinute / 60
	h.log.InfoContext(r.Context(), "speech transcribed", "provider", h.t.Provider(), "format", a.Format,
		"duration_ms", a.Duration.Milliseconds(), "latency_ms", latency.Milliseconds(), "billed_seconds", billed,
		"cost_micros", cost, "chars", utf8.RuneCountInString(res.Text), "ok", err == nil)
	if err != nil {
		h.fail(w, err)
		return
	}
	if h.funnel != nil {
		h.funnel.Record(r.Context(), u.ID, r.URL.Query().Get("session_id"), "transcription_completed", map[string]int64{
			"duration_ms": a.Duration.Milliseconds(), "latency_ms": latency.Milliseconds(),
			"billed_seconds": int64(billed), "cost_micros": cost})
	}
	httpserver.WriteJSON(w, http.StatusOK, Out{Text: res.Text, Provider: res.Provider, Language: res.Language,
		Confidence: res.Confidence, DurationMs: a.Duration.Milliseconds(), LatencyMs: latency.Milliseconds(),
		BilledSeconds: billed})
}

func (h *Handler) fail(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrUnsupported):
		httpserver.WriteError(w, http.StatusUnsupportedMediaType, "unsupported_audio", "No pude leer ese audio. Grabalo de nuevo desde KiuPop.")
	case errors.Is(err, ErrTooShort):
		httpserver.WriteError(w, http.StatusUnprocessableEntity, "audio_too_short", "El audio quedó muy corto. Contame un poco más.")
	case errors.Is(err, ErrTooLong):
		httpserver.WriteError(w, http.StatusRequestEntityTooLarge, "audio_too_long", "El audio es muy largo. Grabá hasta un minuto.")
	case errors.Is(err, ErrSilent):
		httpserver.WriteError(w, http.StatusUnprocessableEntity, "audio_silent", "No te escuché. Revisá el micrófono y probá de nuevo.")
	case errors.Is(err, ErrNoSpeech):
		httpserver.WriteError(w, http.StatusUnprocessableEntity, "speech_empty", "No entendí palabras en el audio. Probá hablar más cerca o escribime.")
	default:
		httpserver.WriteError(w, http.StatusBadGateway, "speech_failed", "No pude transcribir el audio. Probá otra vez o escribime.")
	}
}
