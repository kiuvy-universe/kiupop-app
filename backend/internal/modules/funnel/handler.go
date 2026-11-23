package funnel

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/kiuvy-universe/kiupop/backend/internal/platform/httpserver"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/identity"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/ratelimit"
)

// Sink is what the handler needs (Recorder in production, fake in tests).
type Sink interface {
	Record(ctx context.Context, userID, sessionID, event string, meta map[string]int64)
}

// Handler accepts the milestones only the app can observe.
type Handler struct {
	sink  Sink
	limit *ratelimit.Limiter
	log   *slog.Logger
}

// NewHandler builds the handler.
func NewHandler(sink Sink, log *slog.Logger) *Handler {
	return &Handler{sink: sink, limit: ratelimit.New(300, time.Hour), log: log}
}

// Register mounts POST /api/v1/funnel/events (signed-in users only).
func (h *Handler) Register(mux *http.ServeMux, requireUser func(http.Handler) http.Handler) {
	mux.Handle("POST /api/v1/funnel/events", requireUser(http.HandlerFunc(h.record)))
}

type eventIn struct {
	Event     string           `json:"event"`
	SessionID string           `json:"session_id"`
	Meta      map[string]int64 `json:"meta"`
}

func (h *Handler) record(w http.ResponseWriter, r *http.Request) {
	u, _ := identity.FromContext(r.Context())
	if !h.limit.Allow(u.ID) {
		httpserver.WriteError(w, http.StatusTooManyRequests, "rate_limited", "Demasiados eventos. Intenta más tarde.")
		return
	}
	var in eventIn
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4<<10))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&in); err != nil || !ClientEvents[in.Event] {
		httpserver.WriteError(w, http.StatusBadRequest, "invalid_event", "Evento no reconocido.")
		return
	}
	h.sink.Record(r.Context(), u.ID, in.SessionID, in.Event, in.Meta)
	w.WriteHeader(http.StatusNoContent)
}
