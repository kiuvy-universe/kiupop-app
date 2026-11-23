// Package identity verifies KiuPop end-user ID tokens and resolves them to an
// internal user. The provider is KiuPop-dedicated (Firebase Auth, or its local
// emulator) and fully separate from any Kiuvy identity.
//
// The frontend never chooses who it is: handlers only see the user id this
// package derives from a verified token.
package identity

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/kiuvy-universe/kiupop/backend/internal/platform/httpserver"
)

var (
	// ErrInvalidToken means the token is malformed, expired, or not ours.
	ErrInvalidToken = errors.New("invalid id token")
	// ErrNotConfigured means no identity provider is configured.
	ErrNotConfigured = errors.New("identity provider not configured")
	// ErrUnavailable means the provider (keys endpoint or emulator) could not be reached.
	ErrUnavailable = errors.New("identity provider unavailable")
)

// Identity is what a verified token proves.
type Identity struct {
	UID           string
	Email         string
	EmailVerified bool
	Name          string
	Provider      string // password | google.com | facebook.com
	AuthTime      time.Time
}

// Verifier checks an ID token. Implementations: Firebase (RS256), Emulator, Disabled.
type Verifier interface {
	Verify(ctx context.Context, idToken string) (Identity, error)
	Mode() string // "firebase" | "emulator" | "disabled"
}

// Disabled is used when no provider is configured. It never authenticates anyone.
type Disabled struct{}

// Verify always fails.
func (Disabled) Verify(context.Context, string) (Identity, error) {
	return Identity{}, ErrNotConfigured
}

// Mode implements Verifier.
func (Disabled) Mode() string { return "disabled" }

// Users maps a verified identity to the internal user id (upsert).
type Users interface {
	Upsert(ctx context.Context, id Identity) (userID string, err error)
}

type ctxKey struct{}

// User is the authenticated principal stored in the request context.
type User struct {
	ID       string
	Email    string
	Name     string
	Provider string
}

// FromContext returns the authenticated user, if any.
func FromContext(ctx context.Context) (User, bool) {
	u, ok := ctx.Value(ctxKey{}).(User)
	return u, ok && u.ID != ""
}

// WithUser is exported for tests of handlers behind RequireUser.
func WithUser(ctx context.Context, u User) context.Context {
	return context.WithValue(ctx, ctxKey{}, u)
}

// Authenticate resolves "Authorization: Bearer <id token>" to a user. It returns
// (User{}, false, nil) when the header is absent or is not an ID token (e.g. a
// legacy kp_ store credential), so callers can try other schemes.
func Authenticate(ctx context.Context, v Verifier, users Users, r *http.Request) (User, bool, error) {
	tok, ok := BearerIDToken(r.Header.Get("Authorization"))
	if !ok {
		return User{}, false, nil
	}
	id, err := v.Verify(ctx, tok)
	if err != nil {
		return User{}, true, err
	}
	uid, err := users.Upsert(ctx, id)
	if err != nil {
		return User{}, true, err
	}
	return User{ID: uid, Email: id.Email, Name: id.Name, Provider: id.Provider}, true, nil
}

// RequireUser rejects requests without a valid ID token (401) and puts the
// resolved user in the context.
func RequireUser(v Verifier, users Users, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		u, present, err := Authenticate(r.Context(), v, users, r)
		switch {
		case errors.Is(err, ErrNotConfigured):
			httpserver.WriteError(w, http.StatusServiceUnavailable, "auth_not_configured", "El inicio de sesión no está configurado en este entorno.")
			return
		case !present:
			httpserver.WriteError(w, http.StatusUnauthorized, "unauthorized", "Iniciá sesión para continuar.")
			return
		case errors.Is(err, ErrInvalidToken):
			httpserver.WriteError(w, http.StatusUnauthorized, "unauthorized", "Tu sesión venció. Iniciá sesión de nuevo.")
			return
		case errors.Is(err, ErrUnavailable):
			httpserver.WriteError(w, http.StatusServiceUnavailable, "auth_unavailable", "No pudimos verificar tu sesión. Intentá de nuevo en un momento.")
			return
		case err != nil:
			httpserver.WriteError(w, http.StatusInternalServerError, "internal_error", "Ocurrió un error inesperado. Intenta de nuevo.")
			return
		}
		next.ServeHTTP(w, r.WithContext(WithUser(r.Context(), u)))
	})
}

// BearerIDToken extracts a JWT-shaped bearer token. Legacy "kp_" tokens are not ID tokens.
func BearerIDToken(h string) (string, bool) {
	const p = "Bearer "
	if len(h) <= len(p) || !strings.EqualFold(h[:len(p)], p) {
		return "", false
	}
	t := strings.TrimSpace(h[len(p):])
	if strings.HasPrefix(t, "kp_") || len(t) < 20 || len(t) > 4096 || strings.Count(t, ".") != 2 {
		return "", false
	}
	return t, true
}
