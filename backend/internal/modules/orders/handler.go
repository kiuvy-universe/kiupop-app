package orders

import (
	"errors"
	"log/slog"
	"net/http"

	"github.com/kiuvy-universe/kiupop/backend/internal/platform/httpserver"
)

// Handler serves the order preview.
type Handler struct {
	repo Repository
	log  *slog.Logger
}

// NewHandler builds the handler.
func NewHandler(repo Repository, log *slog.Logger) *Handler { return &Handler{repo: repo, log: log} }

// Register mounts the route.
func (h *Handler) Register(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/public/stores/{slug}/orders/preview", h.preview)
}

type lineErrorBody struct {
	Error LineError `json:"error"`
}

func (h *Handler) preview(w http.ResponseWriter, r *http.Request) {
	var req Request
	if !httpserver.DecodeJSON(w, r, &req) { // unknown fields (e.g. "price") are rejected
		return
	}
	items, lerr := Normalize(req)
	if lerr != nil {
		httpserver.WriteJSON(w, http.StatusUnprocessableEntity, lineErrorBody{Error: *lerr})
		return
	}
	ids := make([]string, len(items))
	for i, it := range items {
		ids[i] = it.ProductID
	}
	store, stored, err := h.repo.Load(r.Context(), r.PathValue("slug"), ids)
	if errors.Is(err, ErrStoreNotFound) {
		httpserver.WriteError(w, http.StatusNotFound, "store_not_found", "No encontramos esta tienda.")
		return
	}
	if err != nil {
		h.log.ErrorContext(r.Context(), "order preview", "err", err)
		httpserver.WriteError(w, http.StatusInternalServerError, "internal_error", "Ocurrió un error inesperado. Intenta de nuevo.")
		return
	}
	p, lerr := Build(store, items, stored)
	if lerr != nil {
		httpserver.WriteJSON(w, http.StatusUnprocessableEntity, lineErrorBody{Error: *lerr})
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, p)
}
