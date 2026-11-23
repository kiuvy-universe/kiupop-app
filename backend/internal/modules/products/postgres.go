package products

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Repo persists products. Every admin query is scoped by store_id.
type Repo struct{ pool *pgxpool.Pool }

// NewRepo returns a repo.
func NewRepo(pool *pgxpool.Pool) *Repo { return &Repo{pool: pool} }

const cols = `id::text, store_id::text, name, description, price_minor, currency, coalesce(image_key, ''), available, created_at`

func scan(row pgx.Row) (Product, error) {
	var p Product
	err := row.Scan(&p.ID, &p.StoreID, &p.Name, &p.Description, &p.PriceMinor, &p.Currency, &p.ImageKey, &p.Available, &p.CreatedAt)
	return p, err
}

// Create inserts a product for storeID.
func (r *Repo) Create(ctx context.Context, storeID string, in CreateInput) (Product, error) {
	available := true
	if in.Available != nil {
		available = *in.Available
	}
	return scan(r.pool.QueryRow(ctx, `
		INSERT INTO products (store_id, name, description, price_minor, available)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING `+cols, storeID, in.Name, in.Description, in.PriceMinor, available))
}

// ListByStore returns all products of storeID (admin view), oldest first.
func (r *Repo) ListByStore(ctx context.Context, storeID string) ([]Product, error) {
	return r.list(ctx, `SELECT `+cols+` FROM products WHERE store_id = $1 ORDER BY created_at, id LIMIT 500`, storeID)
}

// ListPublicBySlug returns only available products of the store with that slug.
func (r *Repo) ListPublicBySlug(ctx context.Context, slug string) ([]Product, error) {
	var storeID string
	err := r.pool.QueryRow(ctx, `SELECT id::text FROM stores WHERE slug = $1 AND status = 'published'`, slug).Scan(&storeID)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrStoreNotFound
	}
	if err != nil {
		return nil, err
	}
	return r.list(ctx, `SELECT `+cols+` FROM products WHERE store_id = $1 AND available ORDER BY created_at, id LIMIT 500`, storeID)
}

func (r *Repo) list(ctx context.Context, q string, arg any) ([]Product, error) {
	rows, err := r.pool.Query(ctx, q, arg)
	if err != nil {
		return nil, fmt.Errorf("list products: %w", err)
	}
	defer rows.Close()
	out := make([]Product, 0, 16)
	for rows.Next() {
		p, err := scan(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// Update applies a patch to a product of storeID.
func (r *Repo) Update(ctx context.Context, storeID, id string, in PatchInput) (Product, error) {
	p, err := scan(r.pool.QueryRow(ctx, `
		UPDATE products SET
			name        = coalesce($3, name),
			description = coalesce($4, description),
			price_minor = coalesce($5, price_minor),
			available   = coalesce($6, available),
			updated_at  = now()
		WHERE id = $1 AND store_id = $2
		RETURNING `+cols, id, storeID, in.Name, in.Description, in.PriceMinor, in.Available))
	if errors.Is(err, pgx.ErrNoRows) {
		return Product{}, ErrNotFound
	}
	return p, err
}

// SetImage stores the new image key and returns the product plus the previous key.
func (r *Repo) SetImage(ctx context.Context, storeID, id, key string) (Product, string, error) {
	var old string
	err := r.pool.QueryRow(ctx, `SELECT coalesce(image_key, '') FROM products WHERE id = $1 AND store_id = $2`, id, storeID).Scan(&old)
	if errors.Is(err, pgx.ErrNoRows) {
		return Product{}, "", ErrNotFound
	}
	if err != nil {
		return Product{}, "", err
	}
	p, err := scan(r.pool.QueryRow(ctx, `
		UPDATE products SET image_key = $3, updated_at = now()
		WHERE id = $1 AND store_id = $2 RETURNING `+cols, id, storeID, key))
	if errors.Is(err, pgx.ErrNoRows) {
		return Product{}, "", ErrNotFound
	}
	return p, old, err
}
