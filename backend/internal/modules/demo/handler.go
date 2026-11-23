package demo

import (
	"log/slog"
	"net/http"

	"github.com/kiuvy-universe/kiupop/backend/internal/platform/httpserver"
)

// Handler serves the /api/v1/demo endpoints.
type Handler struct {
	products ProductLister
	info     Info
	log      *slog.Logger
}

// NewHandler wires the demo endpoints.
func NewHandler(products ProductLister, info Info, log *slog.Logger) *Handler {
	return &Handler{products: products, info: info, log: log}
}

// Register mounts the demo routes on mux.
func (h *Handler) Register(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/demo/info", h.getInfo)
	mux.HandleFunc("GET /api/v1/demo/products", h.listProducts)
}

func (h *Handler) getInfo(w http.ResponseWriter, _ *http.Request) {
	httpserver.WriteJSON(w, http.StatusOK, h.info)
}

// ProductsResponse is the envelope for GET /api/v1/demo/products.
type ProductsResponse struct {
	Data   []Product `json:"data"`
	Source string    `json:"source"`
}

func (h *Handler) listProducts(w http.ResponseWriter, r *http.Request) {
	products, err := h.products.ListProducts(r.Context())
	if err != nil {
		h.log.ErrorContext(r.Context(), "list demo products", "err", err)
		httpserver.WriteError(w, http.StatusServiceUnavailable, "database_unavailable", "No se pudieron leer los productos de demostración.")
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, ProductsResponse{Data: products, Source: "postgres"})
}
