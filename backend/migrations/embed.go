// Package migrations embeds the SQL migrations so the binary is self-contained.
package migrations

import "embed"

// FS holds every migration file (NNNN_name.up.sql / .down.sql).
//
//go:embed *.sql
var FS embed.FS
