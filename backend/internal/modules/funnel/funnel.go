// Package funnel records the demo's conversion milestones (KPOP-WOW-001).
//
// Privacy: actors are HMAC-SHA256(user id, salt) truncated to 128 bits; meta
// only accepts whitelisted keys with integer values. Nothing a merchant typed,
// said or uploaded is ever stored here.
package funnel

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"log/slog"
	"regexp"
	"sort"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Events the funnel accepts (mirrors the CHECK in migration 0008).
var Events = map[string]bool{
	"signup_completed": true, "intake_method_selected": true, "audio_recorded": true,
	"transcription_completed": true, "files_uploaded": true, "blueprint_ready": true,
	"store_ready": true, "store_preview_opened": true, "paywall_viewed": true,
	"demo_activation_completed": true, "catalog_shared": true, "error": true,
}

// ClientEvents are the milestones only the app can observe.
var ClientEvents = map[string]bool{
	"intake_method_selected": true, "audio_recorded": true,
	"store_preview_opened": true, "paywall_viewed": true, "catalog_shared": true, "error": true,
}

var metaKeyRe = regexp.MustCompile(`^[a-z][a-z0-9_]{0,39}$`)

const maxMetaKeys = 12

// CleanMeta keeps only well-formed keys with non-negative bounded integers.
func CleanMeta(in map[string]int64) map[string]int64 {
	out := map[string]int64{}
	keys := make([]string, 0, len(in))
	for k := range in {
		keys = append(keys, k)
	}
	sort.Strings(keys) // deterministic when there are more keys than allowed
	for _, k := range keys {
		v := in[k]
		if len(out) >= maxMetaKeys {
			break
		}
		if metaKeyRe.MatchString(k) && v >= 0 && v <= 1<<40 {
			out[k] = v
		}
	}
	return out
}

// Actor pseudonymises a user id.
func Actor(salt, userID string) string {
	m := hmac.New(sha256.New, []byte(salt))
	m.Write([]byte(userID))
	return hex.EncodeToString(m.Sum(nil))[:32]
}

// Recorder writes events; failures are logged, never surfaced to the user.
type Recorder struct {
	pool *pgxpool.Pool
	salt string
	log  *slog.Logger
}

// NewRecorder builds a recorder.
func NewRecorder(pool *pgxpool.Pool, salt string, log *slog.Logger) *Recorder {
	return &Recorder{pool: pool, salt: salt, log: log}
}

var uuidRe = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

// Record stores one milestone for userID (pseudonymised).
func (r *Recorder) Record(ctx context.Context, userID, sessionID, event string, meta map[string]int64) {
	if r == nil || userID == "" || !Events[event] {
		return
	}
	raw, _ := json.Marshal(CleanMeta(meta))
	var sid any
	if uuidRe.MatchString(sessionID) {
		sid = sessionID
	}
	if _, err := r.pool.Exec(context.WithoutCancel(ctx),
		`INSERT INTO funnel_events (actor, session_id, event, meta) VALUES ($1, $2, $3, $4)`,
		Actor(r.salt, userID), sid, event, raw); err != nil {
		r.log.WarnContext(ctx, "funnel event not recorded", "event", event, "err", err)
	}
}
