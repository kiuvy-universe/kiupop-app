package orders

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Repo reads stores and products for previews.
type Repo struct{ pool *pgxpool.Pool }

// NewRepo returns a repo.
func NewRepo(pool *pgxpool.Pool) *Repo { return &Repo{pool: pool} }

// Load returns the store and those of ids that belong to it (others are absent).
func (r *Repo) Load(ctx context.Context, slug string, ids []string) (StoreInfo, map[string]StoredProduct, error) {
	var s StoreInfo
	var storeID string
	err := r.pool.QueryRow(ctx, `SELECT id::text, slug, name, whatsapp_e164 FROM stores WHERE slug = $1 AND status = 'published' AND whatsapp_e164 IS NOT NULL`, slug).
		Scan(&storeID, &s.Slug, &s.Name, &s.WhatsApp)
	if errors.Is(err, pgx.ErrNoRows) {
		return StoreInfo{}, nil, ErrStoreNotFound
	}
	if err != nil {
		return StoreInfo{}, nil, err
	}
	rows, err := r.pool.Query(ctx, `
		SELECT id::text, name, price_minor, currency, available
		FROM products WHERE store_id = $1 AND id = ANY($2::uuid[])`, storeID, ids)
	if err != nil {
		return StoreInfo{}, nil, err
	}
	defer rows.Close()
	out := make(map[string]StoredProduct, len(ids))
	for rows.Next() {
		var p StoredProduct
		if err := rows.Scan(&p.ID, &p.Name, &p.PriceMinor, &p.Currency, &p.Available); err != nil {
			return StoreInfo{}, nil, err
		}
		out[p.ID] = p
	}
	return s, out, rows.Err()
}
