// Package observability configures structured logging.
package observability

import (
	"io"
	"log/slog"
)

// NewLogger returns a JSON slog logger tagged with service metadata.
func NewLogger(w io.Writer, env, version string) *slog.Logger {
	h := slog.NewJSONHandler(w, &slog.HandlerOptions{Level: slog.LevelInfo})
	return slog.New(h).With("service", "kiupop-api", "env", env, "version", version)
}
