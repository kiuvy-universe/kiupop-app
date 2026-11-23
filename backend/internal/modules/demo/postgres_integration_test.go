package demo_test

import (
	"context"
	"io"
	"log/slog"
	"os"
	"testing"
	"time"

	"github.com/kiuvy-universe/kiupop/backend/internal/modules/demo"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/database"
	"github.com/kiuvy-universe/kiupop/backend/migrations"
)

// Runs only when KIUPOP_TEST_DATABASE_URL points at a disposable local database
// (`make test-integration` sets it to the Compose PostgreSQL).
func TestPostgresRepoAgainstRealDatabase(t *testing.T) {
	url := os.Getenv("KIUPOP_TEST_DATABASE_URL")
	if url == "" {
		t.Skip("KIUPOP_TEST_DATABASE_URL not set")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	pool, err := database.Open(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()

	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	if _, err := database.Migrate(ctx, pool, migrations.FS, log); err != nil {
		t.Fatalf("first migrate: %v", err)
	}
	n, err := database.Migrate(ctx, pool, migrations.FS, log)
	if err != nil || n != 0 {
		t.Fatalf("second migrate must be a no-op, applied=%d err=%v", n, err)
	}

	products, err := demo.NewPostgresRepo(pool).ListProducts(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(products) < 3 {
		t.Fatalf("expected seeded demo products, got %d", len(products))
	}
	for _, p := range products {
		if p.PriceMinor < 0 || len(p.Currency) != 3 {
			t.Fatalf("invalid product %+v", p)
		}
	}
}
