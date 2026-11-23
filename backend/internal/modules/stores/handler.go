package stores

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"strings"

	"github.com/kiuvy-universe/kiupop/backend/internal/platform/auth"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/httpserver"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/identity"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/ratelimit"
)

// Repository is the persistence port used by the handlers.
type Repository interface {
	Create(ctx context.Context, in CreateInput, tokenHash []byte) (Store, error)
	BySlug(ctx context.Context, slug string) (Store, error)
	ByID(ctx context.Context, id string) (Store, error)
}

// Features tells the admin UI which optional capabilities are on.
type Features struct {
	AI bool `json:"ai"`
}

// Handler serves the stores endpoints.
type Handler struct {
	repo          Repository
	log           *slog.Logger
	signupEnabled bool
	features      Features
	signupLimit   *ratelimit.Limiter
}

// NewHandler builds the handler. signupLimit bounds store creation per client IP.
func NewHandler(repo Repository, log *slog.Logger, signupEnabled bool, features Features, signupLimit *ratelimit.Limiter) *Handler {
	return &Handler{repo: repo, log: log, signupEnabled: signupEnabled, features: features, signupLimit: signupLimit}
}

// Register mounts public routes on mux and admin routes behind requireAdmin.
func (h *Handler) Register(mux *http.ServeMux, requireAdmin func(http.Handler) http.Handler) {
	mux.HandleFunc("POST /api/v1/stores", h.create)
	mux.HandleFunc("GET /api/v1/stores/{slug}", h.getPublic)
	mux.Handle("GET /api/v1/admin/stores/current", requireAdmin(http.HandlerFunc(h.current)))
}

// OwnerRepo is what the signed-in-user endpoints need.
type OwnerRepo interface {
	Claim(ctx context.Context, tokenHash []byte, userID string) (Store, error)
	ListOwned(ctx context.Context, userID string) ([]OwnedBrief, error)
}

// RegisterUser mounts /api/v1/me routes behind requireUser.
func (h *Handler) RegisterUser(mux *http.ServeMux, owners OwnerRepo, authMode string, requireUser func(http.Handler) http.Handler) {
	mux.Handle("GET /api/v1/me", requireUser(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		u, _ := identity.FromContext(r.Context())
		list, err := owners.ListOwned(r.Context(), u.ID)
		if err != nil {
			h.internal(w, r, "list owned", err)
			return
		}
		if list == nil {
			list = []OwnedBrief{}
		}
		httpserver.WriteJSON(w, http.StatusOK, map[string]any{
			"user":   map[string]any{"email": u.Email, "name": u.Name, "provider": u.Provider},
			"stores": list, "auth_mode": authMode, "features": h.features,
		})
	})))
	mux.Handle("POST /api/v1/me/stores/claim", requireUser(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			AdminToken string `json:"admin_token"`
		}
		if !httpserver.DecodeJSON(w, r, &in) {
			return
		}
		u, _ := identity.FromContext(r.Context())
		if !strings.HasPrefix(in.AdminToken, auth.TokenPrefix) || len(in.AdminToken) > 100 {
			httpserver.WriteValidation(w, map[string]string{"admin_token": "Pegá la clave kp_ de tu tienda."})
			return
		}
		s, err := owners.Claim(r.Context(), auth.HashToken(in.AdminToken), u.ID)
		switch {
		case errors.Is(err, auth.ErrInvalidToken):
			httpserver.WriteError(w, http.StatusUnauthorized, "invalid_admin_token", "Esa clave no es válida o ya se usó.")
		case errors.Is(err, ErrOwnedByOther):
			httpserver.WriteError(w, http.StatusConflict, "store_owned", "Esa tienda ya pertenece a otra cuenta.")
		case err != nil:
			h.internal(w, r, "claim store", err)
		default:
			h.log.InfoContext(r.Context(), "legacy store claimed", "store_id", s.ID)
			httpserver.WriteJSON(w, http.StatusOK, map[string]any{"store": s})
		}
	})))
}

// CreateResponse is returned once; admin_token is never retrievable again.
type CreateResponse struct {
	Store      Store    `json:"store"`
	AdminToken string   `json:"admin_token"`
	PublicPath string   `json:"public_path"`
	Features   Features `json:"features"`
}

func (h *Handler) create(w http.ResponseWriter, r *http.Request) {
	if !h.signupEnabled {
		httpserver.WriteError(w, http.StatusForbidden, "signup_disabled", "La creación de tiendas no está habilitada en este entorno.")
		return
	}
	if !h.signupLimit.Allow(clientIP(r)) {
		httpserver.WriteError(w, http.StatusTooManyRequests, "rate_limited", "Creaste muchas tiendas seguidas. Espera un momento.")
		return
	}
	var in CreateInput
	if !httpserver.DecodeJSON(w, r, &in) {
		return
	}
	if errs := in.Validate(); len(errs) > 0 {
		httpserver.WriteValidation(w, errs)
		return
	}
	token, hash, err := auth.NewToken()
	if err != nil {
		h.internal(w, r, "generate token", err)
		return
	}
	s, err := h.repo.Create(r.Context(), in, hash)
	if err != nil {
		h.internal(w, r, "create store", err)
		return
	}
	h.log.InfoContext(r.Context(), "store created", "store_id", s.ID, "slug", s.Slug) // never log the token
	httpserver.WriteJSON(w, http.StatusCreated, CreateResponse{
		Store: s, AdminToken: token, PublicPath: "/s/" + s.Slug, Features: h.features,
	})
}

func (h *Handler) getPublic(w http.ResponseWriter, r *http.Request) {
	slug := r.PathValue("slug")
	if !ValidSlug(slug) {
		writeNotFound(w)
		return
	}
	s, err := h.repo.BySlug(r.Context(), slug)
	if errors.Is(err, ErrNotFound) {
		writeNotFound(w)
		return
	}
	if err != nil {
		h.internal(w, r, "get store", err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, s.ToPublic())
}

// CurrentResponse is the admin's view of their store.
type CurrentResponse struct {
	Store    Store    `json:"store"`
	Features Features `json:"features"`
}

func (h *Handler) current(w http.ResponseWriter, r *http.Request) {
	s, err := h.repo.ByID(r.Context(), auth.StoreID(r.Context()))
	if err != nil {
		h.internal(w, r, "current store", err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, CurrentResponse{Store: s, Features: h.features})
}

func (h *Handler) internal(w http.ResponseWriter, r *http.Request, what string, err error) {
	h.log.ErrorContext(r.Context(), what, "err", err)
	httpserver.WriteError(w, http.StatusInternalServerError, "internal_error", "Ocurrió un error inesperado. Intenta de nuevo.")
}

func writeNotFound(w http.ResponseWriter) {
	httpserver.WriteError(w, http.StatusNotFound, "store_not_found", "No encontramos esta tienda.")
}

func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
