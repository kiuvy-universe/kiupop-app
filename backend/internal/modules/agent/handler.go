package agent

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/kiuvy-universe/kiupop/backend/internal/platform/httpserver"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/identity"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/ratelimit"
)

// Handler serves /api/v1/agent/*.
type Handler struct {
	svc         *Service
	log         *slog.Logger
	turns       *ratelimit.Limiter
	ticketLimit *ratelimit.Limiter
	tickets     *tickets
}

// NewHandler builds the handler. turns bounds messages per user (abuse and AI cost).
func NewHandler(svc *Service, log *slog.Logger, turns *ratelimit.Limiter) *Handler {
	return &Handler{svc: svc, log: log, turns: turns, tickets: &tickets{m: map[string]ticket{}, streams: map[string]int{}},
		ticketLimit: ratelimit.New(120, time.Hour)}
}

// Register mounts routes; requireUser verifies the KiuPop ID token.
func (h *Handler) Register(mux *http.ServeMux, requireUser func(http.Handler) http.Handler) {
	u := func(f http.HandlerFunc) http.Handler { return requireUser(f) }
	mux.Handle("POST /api/v1/agent/sessions", u(h.start))
	mux.Handle("GET /api/v1/agent/sessions/current", u(h.current))
	mux.Handle("GET /api/v1/agent/sessions/{id}", u(h.get))
	mux.Handle("POST /api/v1/agent/sessions/{id}/messages", u(h.message))
	mux.Handle("GET /api/v1/agent/sessions/{id}/events", u(h.events))
	mux.Handle("POST /api/v1/agent/sessions/{id}/stream-ticket", u(h.ticket))
	mux.Handle("GET /api/v1/agent/sessions/{id}/preview", u(h.preview))
	mux.Handle("POST /api/v1/agent/sessions/{id}/publish", u(h.publish))
	mux.Handle("POST /api/v1/agent/sessions/{id}/plan", u(h.plan))
	mux.Handle("POST /api/v1/agent/sessions/{id}/attachments", u(h.upload))
	mux.HandleFunc("GET /api/v1/agent/stream", h.stream) // auth = short-lived ticket bound to user+session
}

func user(r *http.Request) string {
	u, _ := identity.FromContext(r.Context())
	return u.ID
}

func (h *Handler) start(w http.ResponseWriter, r *http.Request) {
	v, err := h.svc.Start(r.Context(), user(r))
	h.reply(w, r, http.StatusOK, v, err)
}

func (h *Handler) current(w http.ResponseWriter, r *http.Request) {
	s, err := h.svc.repo.Latest(r.Context(), user(r))
	if err != nil {
		h.reply(w, r, 0, nil, err)
		return
	}
	v, err := h.svc.View(r.Context(), user(r), s.ID)
	h.reply(w, r, http.StatusOK, v, err)
}

func (h *Handler) get(w http.ResponseWriter, r *http.Request) {
	v, err := h.svc.View(r.Context(), user(r), r.PathValue("id"))
	h.reply(w, r, http.StatusOK, v, err)
}

func (h *Handler) message(w http.ResponseWriter, r *http.Request) {
	var in MessageInput
	if !httpserver.DecodeJSON(w, r, &in) {
		return
	}
	if !h.turns.Allow(user(r)) {
		httpserver.WriteError(w, http.StatusTooManyRequests, "rate_limited", "Vas muy rápido. Esperá un momento y seguimos.")
		return
	}
	v, err := h.svc.PostMessage(r.Context(), user(r), r.PathValue("id"), in)
	h.reply(w, r, http.StatusOK, v, err)
}

func (h *Handler) preview(w http.ResponseWriter, r *http.Request) {
	v, err := h.svc.Preview(r.Context(), user(r), r.PathValue("id"))
	h.reply(w, r, http.StatusOK, v, err)
}

type publishRequest struct {
	Confirm bool `json:"confirm"`
}

func (h *Handler) publish(w http.ResponseWriter, r *http.Request) {
	var in publishRequest
	if !httpserver.DecodeJSON(w, r, &in) {
		return
	}
	res, err := h.svc.Publish(r.Context(), user(r), r.PathValue("id"), in.Confirm)
	h.reply(w, r, http.StatusOK, res, err)
}

// plan runs the test-mode paywall payment and activates the store's plan.
func (h *Handler) plan(w http.ResponseWriter, r *http.Request) {
	var in publishRequest
	if !httpserver.DecodeJSON(w, r, &in) {
		return
	}
	v, err := h.svc.ActivatePlan(r.Context(), user(r), r.PathValue("id"), in.Confirm)
	h.reply(w, r, http.StatusOK, v, err)
}

// upload receives one file per request (multipart field "file"); clients upload in parallel.
func (h *Handler) upload(w http.ResponseWriter, r *http.Request) {
	if h.svc.files == nil {
		httpserver.WriteError(w, http.StatusServiceUnavailable, "attachments_disabled", "Los archivos no están disponibles en este entorno.")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, MaxPDFBytes+64<<10)
	file, header, err := r.FormFile("file")
	if err != nil {
		var tooBig *http.MaxBytesError
		if errors.As(err, &tooBig) {
			httpserver.WriteError(w, http.StatusRequestEntityTooLarge, "file_too_large", "El archivo es demasiado grande (máximo 20 MB).")
			return
		}
		httpserver.WriteValidation(w, map[string]string{"file": "Adjuntá una foto, un CSV o un PDF."})
		return
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, MaxPDFBytes+1))
	if err != nil || len(data) > MaxPDFBytes {
		httpserver.WriteError(w, http.StatusRequestEntityTooLarge, "file_too_large", "El archivo es demasiado grande (máximo 20 MB).")
		return
	}
	a, err := h.svc.Upload(r.Context(), user(r), r.PathValue("id"), header.Filename, data)
	h.reply(w, r, http.StatusCreated, a, err)
}

// events is the polling fallback: ?after=<id>&wait=<seconds, max 10>.
func (h *Handler) events(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if _, err := h.svc.repo.Get(r.Context(), id, user(r)); err != nil {
		h.reply(w, r, 0, nil, err)
		return
	}
	after, _ := strconv.ParseInt(r.URL.Query().Get("after"), 10, 64)
	wait, _ := strconv.Atoi(r.URL.Query().Get("wait"))
	wait = max(0, min(wait, 10))
	var sub <-chan struct{}
	if wait > 0 {
		ch, cancel := h.svc.bus.Subscribe(id)
		defer cancel()
		sub = ch
	}
	deadline := time.After(time.Duration(wait) * time.Second)
	for {
		evs, err := h.svc.repo.EventsAfter(r.Context(), id, after, 200)
		if err != nil {
			h.reply(w, r, 0, nil, err)
			return
		}
		if len(evs) > 0 || wait == 0 {
			httpserver.WriteJSON(w, http.StatusOK, map[string]any{"events": evs})
			return
		}
		select {
		case <-sub:
		case <-time.After(time.Second):
		case <-deadline:
			httpserver.WriteJSON(w, http.StatusOK, map[string]any{"events": evs})
			return
		case <-r.Context().Done():
			return
		}
	}
}

func (h *Handler) ticket(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if _, err := h.svc.repo.Get(r.Context(), id, user(r)); err != nil {
		h.reply(w, r, 0, nil, err)
		return
	}
	if !h.ticketLimit.Allow(user(r)) {
		httpserver.WriteError(w, http.StatusTooManyRequests, "rate_limited", "Demasiadas conexiones. Esperá un momento.")
		return
	}
	t, err := h.tickets.issue(id, user(r))
	if err != nil {
		h.reply(w, r, 0, nil, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"ticket": t, "expires_in": int(ticketTTL.Seconds())})
}

// stream serves Server-Sent Events. Reconnects resume from Last-Event-ID.
func (h *Handler) stream(w http.ResponseWriter, r *http.Request) {
	id := r.URL.Query().Get("ticket")
	t, ok := h.tickets.check(id)
	if !ok {
		httpserver.WriteError(w, http.StatusUnauthorized, "unauthorized", "El enlace de eventos venció.")
		return
	}
	if !h.tickets.acquire(id) {
		httpserver.WriteError(w, http.StatusTooManyRequests, "too_many_streams", "Ya hay una conexión abierta.")
		return
	}
	defer h.tickets.release(id)
	rc := http.NewResponseController(w)
	_ = rc.SetWriteDeadline(time.Now().Add(2 * time.Minute))
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Accel-Buffering", "no")
	after, _ := strconv.ParseInt(r.Header.Get("Last-Event-ID"), 10, 64)
	if q := r.URL.Query().Get("after"); after == 0 && q != "" {
		after, _ = strconv.ParseInt(q, 10, 64)
	}
	sub, cancel := h.svc.bus.Subscribe(t.session)
	defer cancel()
	fmt.Fprint(w, "retry: 1500\n\n")
	_ = rc.Flush()
	end := time.After(90 * time.Second) // clients reconnect with Last-Event-ID
	for {
		evs, err := h.svc.repo.EventsAfter(r.Context(), t.session, after, 200)
		if err != nil {
			return
		}
		for _, e := range evs {
			b, _ := json.Marshal(e)
			fmt.Fprintf(w, "id: %d\nevent: %s\ndata: %s\n\n", e.ID, e.Type, b)
			after = e.ID
		}
		if len(evs) > 0 {
			if rc.Flush() != nil {
				return
			}
		}
		select {
		case <-sub:
		case <-time.After(2 * time.Second):
			fmt.Fprint(w, ": ping\n\n")
			if rc.Flush() != nil {
				return
			}
		case <-end:
			return
		case <-r.Context().Done():
			return
		}
	}
}

func (h *Handler) reply(w http.ResponseWriter, r *http.Request, status int, v any, err error) {
	var nr *NotReadyError
	switch {
	case err == nil:
		httpserver.WriteJSON(w, status, v)
	case errors.Is(err, ErrSessionNotFound):
		httpserver.WriteError(w, http.StatusNotFound, "session_not_found", "No encontramos esa conversación.")
	case errors.Is(err, ErrSessionClosed):
		httpserver.WriteError(w, http.StatusConflict, "session_closed", "Esta tienda ya está publicada. Editála desde «Mi tienda».")
	case errors.Is(err, ErrInvalidMessage):
		httpserver.WriteValidation(w, map[string]string{"text": "Escribí un mensaje de hasta 1000 caracteres."})
	case errors.Is(err, ErrUnsupportedFile):
		httpserver.WriteError(w, http.StatusUnsupportedMediaType, "unsupported_file", "Solo puedo leer fotos (JPG, PNG, WebP de hasta 5 MB), catálogos CSV (hasta 1 MB) o PDF (hasta 20 MB).")
	case errors.Is(err, ErrAttachmentLimit):
		httpserver.WriteError(w, http.StatusConflict, "attachment_limit", "Ya compartiste 5 archivos (o 50 MB). Seguimos con lo que tenemos.")
	case errors.Is(err, ErrConfirmationRequired):
		httpserver.WriteError(w, http.StatusBadRequest, "confirmation_required", "Confirmá que querés publicar tu tienda.")
	case errors.Is(err, ErrPlanRequired):
		httpserver.WriteError(w, http.StatusPaymentRequired, "plan_required", "Para publicar tu tienda activá el plan de US$5 al mes por tienda activa.")
	case errors.Is(err, ErrPaymentsUnavailable):
		httpserver.WriteError(w, http.StatusServiceUnavailable, "payments_unavailable", "Los pagos no están disponibles en este entorno.")
	case errors.As(err, &nr):
		httpserver.WriteJSON(w, http.StatusConflict, map[string]any{"error": map[string]any{
			"code": "store_not_ready", "message": "Tu tienda todavía no está lista para publicarse.", "missing": nr.Missing}})
	default:
		h.log.ErrorContext(r.Context(), "agent request failed", "err", err)
		httpserver.WriteError(w, http.StatusInternalServerError, "internal_error", "Ocurrió un error inesperado. Intenta de nuevo.")
	}
}

const ticketTTL = 10 * time.Minute

type ticket struct {
	session, user string
	exp           time.Time
}

// Ticket bounds: per user, overall, and concurrent streams per ticket.
const (
	maxTicketsPerUser   = 5
	maxTickets          = 10000
	maxStreamsPerTicket = 2
)

// errTooManyTickets means the in-memory ticket table is full.
var errTooManyTickets = errors.New("too many stream tickets")

// tickets are opaque, random, short-lived, bound to one user and session.
// They live in memory (one instance); see ADR-003.
type tickets struct {
	mu      sync.Mutex
	m       map[string]ticket
	streams map[string]int
}

func (t *tickets) acquire(id string) bool {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.streams[id] >= maxStreamsPerTicket {
		return false
	}
	t.streams[id]++
	return true
}

func (t *tickets) release(id string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.streams[id]--; t.streams[id] <= 0 {
		delete(t.streams, id)
	}
}

func (t *tickets) issue(session, user string) (string, error) {
	b := make([]byte, 24)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	id := base64.RawURLEncoding.EncodeToString(b)
	t.mu.Lock()
	defer t.mu.Unlock()
	now := time.Now()
	var mine []string
	for k, v := range t.m {
		if now.After(v.exp) {
			delete(t.m, k)
		} else if v.user == user {
			mine = append(mine, k)
		}
	}
	if len(mine) >= maxTicketsPerUser { // keep the newest few per user
		oldest := mine[0]
		for _, k := range mine {
			if t.m[k].exp.Before(t.m[oldest].exp) {
				oldest = k
			}
		}
		delete(t.m, oldest)
	}
	if len(t.m) >= maxTickets {
		return "", errTooManyTickets
	}
	t.m[id] = ticket{session: session, user: user, exp: now.Add(ticketTTL)}
	return id, nil
}

func (t *tickets) check(id string) (ticket, bool) {
	t.mu.Lock()
	defer t.mu.Unlock()
	v, ok := t.m[id]
	if !ok || time.Now().After(v.exp) {
		return ticket{}, false
	}
	return v, true
}
