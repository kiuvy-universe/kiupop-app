package demo

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

// PostgresRepo reads demo products from the demo_products table.
type PostgresRepo struct{ pool *pgxpool.Pool }

// NewPostgresRepo returns a repository backed by pool.
func NewPostgresRepo(pool *pgxpool.Pool) *PostgresRepo { return &PostgresRepo{pool: pool} }

// ListProducts returns all demo products ordered for display.
func (r *PostgresRepo) ListProducts(ctx context.Context) ([]Product, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, name, description, price_minor, currency
		FROM demo_products
		ORDER BY sort_order, id
		LIMIT 100`)
	if err != nil {
		return nil, fmt.Errorf("query demo_products: %w", err)
	}
	defer rows.Close()

	products := make([]Product, 0, 8)
	for rows.Next() {
		var p Product
		if err := rows.Scan(&p.ID, &p.Name, &p.Description, &p.PriceMinor, &p.Currency); err != nil {
			return nil, err
		}
		products = append(products, p)
	}
	return products, rows.Err()
}
