package ai

import (
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"unicode/utf8"

	"github.com/kiuvy-universe/kiupop/backend/internal/platform/auth"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/httpserver"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/ratelimit"
)

// Handler serves POST /api/v1/admin/ai/product-description.
type Handler struct {
	gen      ProductDescriptionGenerator
	perStore *ratelimit.Limiter
	global   *ratelimit.Limiter
	log      *slog.Logger
}

// NewHandler builds the handler. perStore and global cap cost.
func NewHandler(gen ProductDescriptionGenerator, perStore, global *ratelimit.Limiter, log *slog.Logger) *Handler {
	return &Handler{gen: gen, perStore: perStore, global: global, log: log}
}

// Register mounts the admin route.
func (h *Handler) Register(mux *http.ServeMux, requireAdmin func(http.Handler) http.Handler) {
	mux.Handle("POST /api/v1/admin/ai/product-description", requireAdmin(http.HandlerFunc(h.generate)))
}

type request struct {
	Text string `json:"text"`
}

// Response labels the source honestly; provider internals are not exposed.
type Response struct {
	Suggestion
	GeneratedBy string `json:"generated_by"`
}

func (h *Handler) generate(w http.ResponseWriter, r *http.Request) {
	var req request
	if !httpserver.DecodeJSON(w, r, &req) {
		return
	}
	req.Text = strings.TrimSpace(req.Text)
	if n := utf8.RuneCountInString(req.Text); n < 3 || n > MaxInputRunes {
		httpserver.WriteValidation(w, map[string]string{"text": "Describe tu producto en 3 a 500 caracteres."})
		return
	}
	if _, disabled := h.gen.(Disabled); disabled {
		writeDisabled(w)
		return
	}
	storeID := auth.StoreID(r.Context())
	if !h.perStore.Allow(storeID) || !h.global.Allow("global") {
		httpserver.WriteError(w, http.StatusTooManyRequests, "ai_rate_limited", "Usaste KiuPop AI muchas veces seguidas. Espera unos minutos.")
		return
	}
	s, err := h.gen.Generate(r.Context(), req.Text)
	switch {
	case err == nil:
		httpserver.WriteJSON(w, http.StatusOK, Response{Suggestion: s, GeneratedBy: "KiuPop AI"})
	case errors.Is(err, ErrDisabled):
		writeDisabled(w)
	case errors.Is(err, ErrRefused), errors.Is(err, ErrInvalidOutput):
		httpserver.WriteError(w, http.StatusBadGateway, "ai_invalid_output", "KiuPop AI no pudo proponer un texto para esta nota. Prueba describiéndolo de otra forma.")
	default:
		httpserver.WriteError(w, http.StatusBadGateway, "ai_unavailable", "KiuPop AI no respondió. Intenta de nuevo o escribe la descripción tú mismo.")
	}
}

func writeDisabled(w http.ResponseWriter) {
	httpserver.WriteError(w, http.StatusServiceUnavailable, "ai_disabled", "KiuPop AI no está disponible en este entorno. Puedes escribir la descripción tú mismo.")
}
