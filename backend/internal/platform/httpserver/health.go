package httpserver

import (
	"context"
	"net/http"
	"time"
)

// Pinger is anything that can prove a dependency is reachable.
type Pinger interface {
	Ping(ctx context.Context) error
}

// RegisterHealth mounts /healthz (liveness) and /readyz (database readiness).
func RegisterHealth(mux *http.ServeMux, db Pinger) {
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		WriteJSON(w, http.StatusOK, map[string]string{"status": "ok", "service": "kiupop-api"})
	})
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if err := db.Ping(ctx); err != nil {
			WriteJSON(w, http.StatusServiceUnavailable, map[string]any{
				"status": "unavailable", "checks": map[string]string{"database": "down"},
			})
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{
			"status": "ready", "checks": map[string]string{"database": "up"},
		})
	})
}
