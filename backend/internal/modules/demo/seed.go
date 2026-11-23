package demo

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

// DemoStoreSlug is a fictitious store seeded in mock mode so the public catalog
// can be opened without creating anything. It has no admin credential.
const DemoStoreSlug = "tienda-demo"

// SeedStore inserts the demo store and products once (idempotent).
func SeedStore(ctx context.Context, pool *pgxpool.Pool) error {
	_, err := pool.Exec(ctx, `
WITH s AS (
    INSERT INTO stores (slug, name, description, whatsapp_e164)
    VALUES ($1, 'Floristería Demo KiuPop', 'Tienda de demostración con datos ficticios.', '50600000000')
    ON CONFLICT (slug) DO NOTHING
    RETURNING id
)
INSERT INTO products (store_id, name, description, price_minor)
SELECT s.id, p.name, p.description, p.price_minor FROM s,
  (VALUES ('Rosa roja',       'Rosa natural de tallo largo. Producto ficticio.', 200000),
          ('Arreglo pequeño', 'Arreglo de temporada. Producto ficticio.',      500000),
          ('Girasol',         'Girasol fresco. Producto ficticio.',             150000)) AS p(name, description, price_minor)`,
		DemoStoreSlug)
	return err
}
