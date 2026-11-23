package products

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"regexp"

	"github.com/kiuvy-universe/kiupop/backend/internal/platform/auth"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/httpserver"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/storage"
)

// Repository is the persistence port.
type Repository interface {
	Create(ctx context.Context, storeID string, in CreateInput) (Product, error)
	ListByStore(ctx context.Context, storeID string) ([]Product, error)
	ListPublicBySlug(ctx context.Context, slug string) ([]Product, error)
	Update(ctx context.Context, storeID, id string, in PatchInput) (Product, error)
	SetImage(ctx context.Context, storeID, id, key string) (Product, string, error)
}

// ImageStore is the file storage port.
type ImageStore interface {
	Save(data []byte) (string, error)
	Open(key string) (io.ReadSeekCloser, error)
	Delete(key string)
}

// LocalImages adapts storage.Images to ImageStore.
type LocalImages struct{ storage.Images }

// Open implements ImageStore.
func (l LocalImages) Open(key string) (io.ReadSeekCloser, error) { return l.Images.Open(key) }

// Handler serves product endpoints.
type Handler struct {
	repo   Repository
	images ImageStore
	log    *slog.Logger
}

// NewHandler builds the handler.
func NewHandler(repo Repository, images ImageStore, log *slog.Logger) *Handler {
	return &Handler{repo: repo, images: images, log: log}
}

// Register mounts routes.
func (h *Handler) Register(mux *http.ServeMux, requireAdmin func(http.Handler) http.Handler) {
	mux.Handle("POST /api/v1/admin/products", requireAdmin(http.HandlerFunc(h.create)))
	mux.Handle("GET /api/v1/admin/products", requireAdmin(http.HandlerFunc(h.list)))
	mux.Handle("PATCH /api/v1/admin/products/{id}", requireAdmin(http.HandlerFunc(h.update)))
	mux.Handle("POST /api/v1/admin/products/{id}/image", requireAdmin(http.HandlerFunc(h.uploadImage)))
	mux.HandleFunc("GET /api/v1/public/stores/{slug}/products", h.publicList)
	mux.HandleFunc("GET /api/v1/public/images/{key}", h.serveImage)
}

// List envelopes.
type adminList struct {
	Data []AdminDTO `json:"data"`
}
type publicList struct {
	Data []PublicDTO `json:"data"`
}

var uuidRe = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

// ValidID reports whether s is a canonical lowercase UUID.
func ValidID(s string) bool { return uuidRe.MatchString(s) }

func (h *Handler) create(w http.ResponseWriter, r *http.Request) {
	var in CreateInput
	if !httpserver.DecodeJSON(w, r, &in) {
		return
	}
	if errs := in.Validate(); len(errs) > 0 {
		httpserver.WriteValidation(w, errs)
		return
	}
	p, err := h.repo.Create(r.Context(), auth.StoreID(r.Context()), in)
	if err != nil {
		h.internal(w, r, "create product", err)
		return
	}
	httpserver.WriteJSON(w, http.StatusCreated, p.Admin())
}

func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
	ps, err := h.repo.ListByStore(r.Context(), auth.StoreID(r.Context()))
	if err != nil {
		h.internal(w, r, "list products", err)
		return
	}
	out := make([]AdminDTO, len(ps))
	for i, p := range ps {
		out[i] = p.Admin()
	}
	httpserver.WriteJSON(w, http.StatusOK, adminList{Data: out})
}

func (h *Handler) update(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !ValidID(id) {
		writeProductNotFound(w)
		return
	}
	var in PatchInput
	if !httpserver.DecodeJSON(w, r, &in) {
		return
	}
	if errs := in.Validate(); len(errs) > 0 {
		httpserver.WriteValidation(w, errs)
		return
	}
	p, err := h.repo.Update(r.Context(), auth.StoreID(r.Context()), id, in)
	if errors.Is(err, ErrNotFound) {
		writeProductNotFound(w)
		return
	}
	if err != nil {
		h.internal(w, r, "update product", err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, p.Admin())
}

func (h *Handler) uploadImage(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !ValidID(id) {
		writeProductNotFound(w)
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, storage.MaxImageBytes+64<<10)
	file, _, err := r.FormFile("image")
	if err != nil {
		var tooBig *http.MaxBytesError
		if errors.As(err, &tooBig) {
			httpserver.WriteError(w, http.StatusRequestEntityTooLarge, "image_too_large", "La foto pesa más de 5 MB.")
			return
		}
		httpserver.WriteError(w, http.StatusBadRequest, "image_missing", "Adjunta una foto en el campo «image».")
		return
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, storage.MaxImageBytes+1))
	if err != nil {
		httpserver.WriteError(w, http.StatusBadRequest, "image_unreadable", "No pudimos leer la foto.")
		return
	}
	if len(data) > storage.MaxImageBytes {
		httpserver.WriteError(w, http.StatusRequestEntityTooLarge, "image_too_large", "La foto pesa más de 5 MB.")
		return
	}
	key, err := h.images.Save(data)
	if errors.Is(err, storage.ErrUnsupportedImage) {
		httpserver.WriteError(w, http.StatusUnsupportedMediaType, "image_unsupported", "Usa una foto JPG, PNG o WebP.")
		return
	}
	if err != nil {
		h.internal(w, r, "save image", err)
		return
	}
	p, old, err := h.repo.SetImage(r.Context(), auth.StoreID(r.Context()), id, key)
	if err != nil {
		h.images.Delete(key)
		if errors.Is(err, ErrNotFound) {
			writeProductNotFound(w)
			return
		}
		h.internal(w, r, "set image", err)
		return
	}
	if old != "" {
		h.images.Delete(old)
	}
	httpserver.WriteJSON(w, http.StatusOK, p.Admin())
}

func (h *Handler) publicList(w http.ResponseWriter, r *http.Request) {
	ps, err := h.repo.ListPublicBySlug(r.Context(), r.PathValue("slug"))
	if errors.Is(err, ErrStoreNotFound) {
		httpserver.WriteError(w, http.StatusNotFound, "store_not_found", "No encontramos esta tienda.")
		return
	}
	if err != nil {
		h.internal(w, r, "public products", err)
		return
	}
	out := make([]PublicDTO, len(ps))
	for i, p := range ps {
		out[i] = p.Public()
	}
	httpserver.WriteJSON(w, http.StatusOK, publicList{Data: out})
}

func (h *Handler) serveImage(w http.ResponseWriter, r *http.Request) {
	key := r.PathValue("key")
	f, err := h.images.Open(key)
	if err != nil {
		httpserver.WriteError(w, http.StatusNotFound, "image_not_found", "Imagen no encontrada.")
		return
	}
	defer f.Close()
	w.Header().Set("Content-Type", storage.ContentTypeFor(key))
	w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	w.Header().Set("Content-Security-Policy", "default-src 'none'; sandbox")
	w.Header().Set("Cross-Origin-Resource-Policy", "cross-origin")
	http.ServeContent(w, r, "", zeroTime, f)
}

func (h *Handler) internal(w http.ResponseWriter, r *http.Request, what string, err error) {
	h.log.ErrorContext(r.Context(), what, "err", err)
	httpserver.WriteError(w, http.StatusInternalServerError, "internal_error", "Ocurrió un error inesperado. Intenta de nuevo.")
}

func writeProductNotFound(w http.ResponseWriter) {
	httpserver.WriteError(w, http.StatusNotFound, "product_not_found", "No encontramos este producto en tu tienda.")
}
