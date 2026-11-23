// Package auth implements the POC store-admin credential: a high-entropy random
// token shown once, stored only as a SHA-256 hash, sent as "Authorization: Bearer".
//
// This is a hackathon-POC mechanism, not a full identity system: there is no
// recovery, rotation UI or rate-limited login. See docs/decisions/ADR-002.
package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"net/http"
	"strings"

	"github.com/kiuvy-universe/kiupop/backend/internal/platform/httpserver"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/identity"
)

// TokenPrefix makes tokens recognisable by secret scanners and humans.
const TokenPrefix = "kp_"

// ErrInvalidToken means the token is unknown or revoked.
var ErrInvalidToken = errors.New("invalid admin token")

// NewToken returns a fresh token (256 bits of entropy) and its hash.
func NewToken() (token string, hash []byte, err error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", nil, err
	}
	token = TokenPrefix + base64.RawURLEncoding.EncodeToString(b)
	return token, HashToken(token), nil
}

// HashToken hashes a token. SHA-256 is sufficient because tokens are random
// 256-bit values (no dictionary to brute force), unlike human passwords.
func HashToken(token string) []byte {
	sum := sha256.Sum256([]byte(token))
	return sum[:]
}

// Resolver maps a token hash to the store it administers.
type Resolver interface {
	ResolveStoreID(ctx context.Context, tokenHash []byte) (string, error)
}

type ctxKey struct{}

// StoreID returns the authenticated store id, or "" if none.
func StoreID(ctx context.Context) string {
	id, _ := ctx.Value(ctxKey{}).(string)
	return id
}

// WithStoreID is exported for tests of handlers that sit behind RequireStoreAdmin.
func WithStoreID(ctx context.Context, id string) context.Context {
	return context.WithValue(ctx, ctxKey{}, id)
}

// RequireStoreAdmin rejects requests without a valid admin token (401).
func RequireStoreAdmin(r Resolver, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		token, ok := bearer(req.Header.Get("Authorization"))
		if !ok {
			httpserver.WriteError(w, http.StatusUnauthorized, "unauthorized", "Ingresa tu clave de administrador.")
			return
		}
		storeID, err := r.ResolveStoreID(req.Context(), HashToken(token))
		if err != nil {
			httpserver.WriteError(w, http.StatusUnauthorized, "unauthorized", "La clave de administrador no es válida.")
			return
		}
		next.ServeHTTP(w, req.WithContext(WithStoreID(req.Context(), storeID)))
	})
}

func bearer(h string) (string, bool) {
	const p = "Bearer "
	if len(h) <= len(p) || !strings.EqualFold(h[:len(p)], p) {
		return "", false
	}
	t := strings.TrimSpace(h[len(p):])
	if !strings.HasPrefix(t, TokenPrefix) || len(t) < 20 || len(t) > 100 {
		return "", false
	}
	return t, true
}

// OwnedStores resolves the store a signed-in KiuPop user administers.
type OwnedStores interface {
	OwnedStoreID(ctx context.Context, userID string) (string, error)
}

// RequireStoreAdminOrUser accepts either a legacy POC "kp_" credential or a
// verified KiuPop ID token. With an ID token the store is always the one the
// user owns (resolved server-side), so a client can never pick another store.
func RequireStoreAdminOrUser(legacy Resolver, v identity.Verifier, users identity.Users, owned OwnedStores, next http.Handler) http.Handler {
	legacyMW := RequireStoreAdmin(legacy, next)
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		if _, ok := bearer(req.Header.Get("Authorization")); ok {
			legacyMW.ServeHTTP(w, req)
			return
		}
		u, present, err := identity.Authenticate(req.Context(), v, users, req)
		if !present || err != nil {
			httpserver.WriteError(w, http.StatusUnauthorized, "unauthorized", "Iniciá sesión para administrar tu tienda.")
			return
		}
		storeID, err := owned.OwnedStoreID(req.Context(), u.ID)
		if err != nil {
			httpserver.WriteError(w, http.StatusNotFound, "store_not_found", "Todavía no tenés una tienda. Creala con Kiu.")
			return
		}
		ctx := identity.WithUser(WithStoreID(req.Context(), storeID), u)
		next.ServeHTTP(w, req.WithContext(ctx))
	})
}
