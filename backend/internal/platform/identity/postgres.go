package identity

import (
	"context"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Repo stores users in PostgreSQL. A short in-memory cache avoids one write
// per request (event polling hits the API every second).
type Repo struct {
	pool     *pgxpool.Pool
	mu       sync.Mutex
	cache    map[string]cached
	onSignup func(ctx context.Context, userID, provider string)
}

type cached struct {
	id string
	at time.Time
}

// OnSignup, when set, is called once when a user row is created (first
// sign-in): the funnel's signup_completed. Never receives email or name.
func (r *Repo) OnSignup(f func(ctx context.Context, userID, provider string)) *Repo {
	r.onSignup = f
	return r
}

// NewRepo returns a repo.
func NewRepo(pool *pgxpool.Pool) *Repo { return &Repo{pool: pool, cache: map[string]cached{}} }

// Upsert implements Users. The provider uid is the only key; email may change.
func (r *Repo) Upsert(ctx context.Context, id Identity) (string, error) {
	r.mu.Lock()
	if c, ok := r.cache[id.UID]; ok && time.Since(c.at) < 5*time.Minute {
		r.mu.Unlock()
		return c.id, nil
	}
	r.mu.Unlock()
	uid, created, err := r.upsert(ctx, id)
	if err == nil && created && r.onSignup != nil {
		r.onSignup(ctx, uid, id.Provider)
	}
	if err == nil {
		r.mu.Lock()
		if len(r.cache) > 10000 {
			r.cache = map[string]cached{}
		}
		r.cache[id.UID] = cached{id: uid, at: time.Now()}
		r.mu.Unlock()
	}
	return uid, err
}

func (r *Repo) upsert(ctx context.Context, id Identity) (string, bool, error) {
	var uid string
	var created bool
	err := r.pool.QueryRow(ctx, `
		INSERT INTO users (auth_uid, email, email_verified, display_name, sign_in_provider)
		VALUES ($1, NULLIF($2, ''), $3, NULLIF($4, ''), $5)
		ON CONFLICT (auth_uid) DO UPDATE SET
			email = EXCLUDED.email, email_verified = EXCLUDED.email_verified,
			display_name = COALESCE(EXCLUDED.display_name, users.display_name),
			sign_in_provider = EXCLUDED.sign_in_provider, last_seen_at = now()
		RETURNING id::text, (xmax = 0)`,
		id.UID, trim(id.Email, 320), id.EmailVerified, trim(id.Name, 120), trim(id.Provider, 40)).Scan(&uid, &created)
	return uid, created, err
}

func trim(s string, n int) string {
	s = strings.TrimSpace(s)
	if r := []rune(s); len(r) > n {
		return string(r[:n])
	}
	return s
}
