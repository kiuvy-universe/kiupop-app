package stores

import (
	"context"
	"errors"
	"fmt"
	"strconv"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/kiuvy-universe/kiupop/backend/internal/platform/auth"
)

// Repo persists stores in PostgreSQL. It also resolves admin tokens.
type Repo struct{ pool *pgxpool.Pool }

// NewRepo returns a repo.
func NewRepo(pool *pgxpool.Pool) *Repo { return &Repo{pool: pool} }

// Create inserts the store with a unique slug and stores the token hash, atomically.
func (r *Repo) Create(ctx context.Context, in CreateInput, tokenHash []byte) (Store, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return Store{}, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	base := Slugify(in.Name)
	var s Store
	found := false
	for i := 1; i <= 50 && !found; i++ {
		slug := base
		if i > 1 {
			suffix := "-" + strconv.Itoa(i)
			if len(slug)+len(suffix) > 60 {
				slug = slug[:60-len(suffix)]
			}
			slug += suffix
		}
		err := tx.QueryRow(ctx, `
			INSERT INTO stores (slug, name, description, whatsapp_e164)
			VALUES ($1, $2, $3, $4)
			ON CONFLICT (slug) DO NOTHING
			RETURNING id::text, slug, name, description, whatsapp_e164`,
			slug, in.Name, in.Description, in.WhatsApp,
		).Scan(&s.ID, &s.Slug, &s.Name, &s.Description, &s.WhatsApp)
		switch {
		case err == nil:
			found = true
		case errors.Is(err, pgx.ErrNoRows):
			continue
		default:
			return Store{}, fmt.Errorf("insert store: %w", err)
		}
	}
	if !found {
		return Store{}, ErrSlugExhausted
	}
	if _, err := tx.Exec(ctx, `INSERT INTO store_admin_credentials (store_id, token_hash) VALUES ($1, $2)`, s.ID, tokenHash); err != nil {
		return Store{}, fmt.Errorf("insert credential: %w", err)
	}
	return s, tx.Commit(ctx)
}

// BySlug returns a store by its public slug.
func (r *Repo) BySlug(ctx context.Context, slug string) (Store, error) {
	return r.one(ctx, `SELECT id::text, slug, name, description, coalesce(whatsapp_e164, '') FROM stores WHERE slug = $1 AND status = 'published'`, slug)
}

// ByID returns a store by id.
func (r *Repo) ByID(ctx context.Context, id string) (Store, error) {
	return r.one(ctx, `SELECT id::text, slug, name, description, coalesce(whatsapp_e164, '') FROM stores WHERE id = $1`, id)
}

func (r *Repo) one(ctx context.Context, q string, arg any) (Store, error) {
	var s Store
	err := r.pool.QueryRow(ctx, q, arg).Scan(&s.ID, &s.Slug, &s.Name, &s.Description, &s.WhatsApp)
	if errors.Is(err, pgx.ErrNoRows) {
		return Store{}, ErrNotFound
	}
	return s, err
}

// ResolveStoreID implements auth.Resolver.
func (r *Repo) ResolveStoreID(ctx context.Context, tokenHash []byte) (string, error) {
	var id string
	err := r.pool.QueryRow(ctx, `
		SELECT store_id::text FROM store_admin_credentials
		WHERE token_hash = $1 AND revoked_at IS NULL`, tokenHash).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", auth.ErrInvalidToken
	}
	return id, err
}

// ErrOwnedByOther means the store already belongs to another user.
var ErrOwnedByOther = errors.New("store owned by another user")

// Claim attaches a legacy (ownerless) store to userID, proven by its kp_ token.
// The legacy credential is revoked so the store has a single owner afterwards.
func (r *Repo) Claim(ctx context.Context, tokenHash []byte, userID string) (Store, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return Store{}, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	var storeID, owner string
	err = tx.QueryRow(ctx, `SELECT c.store_id::text, coalesce(s.owner_user_id::text, '')
		FROM store_admin_credentials c JOIN stores s ON s.id = c.store_id
		WHERE c.token_hash = $1 AND c.revoked_at IS NULL FOR UPDATE OF s, c`, tokenHash).Scan(&storeID, &owner)
	if errors.Is(err, pgx.ErrNoRows) {
		return Store{}, auth.ErrInvalidToken
	}
	if err != nil {
		return Store{}, err
	}
	if owner != "" && owner != userID {
		return Store{}, ErrOwnedByOther
	}
	if _, err := tx.Exec(ctx, `UPDATE stores SET owner_user_id = $2 WHERE id = $1`, storeID, userID); err != nil {
		return Store{}, err
	}
	if _, err := tx.Exec(ctx, `UPDATE store_admin_credentials SET revoked_at = now() WHERE store_id = $1 AND revoked_at IS NULL`, storeID); err != nil {
		return Store{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return Store{}, err
	}
	return r.ByID(ctx, storeID)
}

// OwnedBrief is a store in the user's list.
type OwnedBrief struct {
	Slug   string `json:"slug"`
	Name   string `json:"name"`
	Status string `json:"status"`
}

// ListOwned lists a user's stores (newest first).
func (r *Repo) ListOwned(ctx context.Context, userID string) ([]OwnedBrief, error) {
	rows, err := r.pool.Query(ctx, `SELECT slug, name, status FROM stores WHERE owner_user_id = $1 ORDER BY created_at DESC LIMIT 20`, userID)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(row pgx.CollectableRow) (OwnedBrief, error) {
		var b OwnedBrief
		return b, row.Scan(&b.Slug, &b.Name, &b.Status)
	})
}
