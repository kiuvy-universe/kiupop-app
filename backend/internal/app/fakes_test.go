package app

import (
	"bytes"
	"context"
	"io"
	"log/slog"
	"net/http"
	"testing"
	"time"

	"github.com/kiuvy-universe/kiupop/backend/internal/integrations/kiuvy"
	"github.com/kiuvy-universe/kiupop/backend/internal/integrations/payments"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/agent"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/ai"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/demo"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/orders"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/products"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/speech"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/storefront"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/stores"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/auth"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/config"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/identity"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/storage"
)

const fakeToken = "kp_contract_test_token_aaaaaaaaaaaaaaaaaaaaaa"

var exampleStore = stores.Store{ID: "6f1d2c3b-4a59-4e8f-9a0b-1c2d3e4f5a6b", Slug: "flores-de-occidente",
	Name: "Flores de Occidente", Description: "Flores frescas en San Ramón.", WhatsApp: "50600000001"}

type okDB struct{}

func (okDB) Ping(context.Context) error { return nil }

type demoProducts struct{}

func (demoProducts) ListProducts(context.Context) ([]demo.Product, error) {
	return []demo.Product{{ID: "demo-pan", Name: "Pan casero", Description: "x", PriceMinor: 150000, Currency: "CRC"}}, nil
}

type fakeStores struct{}

func (fakeStores) Create(_ context.Context, in stores.CreateInput, _ []byte) (stores.Store, error) {
	s := exampleStore
	s.Name, s.Description, s.WhatsApp, s.Slug = in.Name, in.Description, in.WhatsApp, stores.Slugify(in.Name)
	return s, nil
}
func (fakeStores) BySlug(_ context.Context, slug string) (stores.Store, error) {
	if slug == exampleStore.Slug {
		return exampleStore, nil
	}
	return stores.Store{}, stores.ErrNotFound
}
func (fakeStores) ByID(context.Context, string) (stores.Store, error) { return exampleStore, nil }
func (fakeStores) ResolveStoreID(_ context.Context, h []byte) (string, error) {
	if bytes.Equal(h, auth.HashToken(fakeToken)) {
		return exampleStore.ID, nil
	}
	return "", auth.ErrInvalidToken
}

var rosa = products.Product{ID: "11111111-1111-4111-8111-111111111111", Name: "Rosa roja", Description: "Rosa natural de tallo largo.",
	PriceMinor: 200000, Currency: "CRC", ImageKey: "0b1c2d3e-4f5a-4b6c-8d7e-8f9a0b1c2d3e.jpg", Available: true,
	CreatedAt: time.Date(2026, 11, 22, 15, 4, 5, 0, time.UTC)}

type fakeProducts struct{}

func (fakeProducts) Create(context.Context, string, products.CreateInput) (products.Product, error) {
	return rosa, nil
}
func (fakeProducts) ListByStore(context.Context, string) ([]products.Product, error) {
	return []products.Product{rosa}, nil
}
func (fakeProducts) ListPublicBySlug(_ context.Context, slug string) ([]products.Product, error) {
	if slug != exampleStore.Slug {
		return nil, products.ErrStoreNotFound
	}
	return []products.Product{rosa}, nil
}
func (fakeProducts) Update(context.Context, string, string, products.PatchInput) (products.Product, error) {
	return rosa, nil
}
func (fakeProducts) SetImage(context.Context, string, string, string) (products.Product, string, error) {
	return rosa, "", nil
}

type fakeOrders struct{}

func (fakeOrders) Load(_ context.Context, slug string, _ []string) (orders.StoreInfo, map[string]orders.StoredProduct, error) {
	if slug != exampleStore.Slug {
		return orders.StoreInfo{}, nil, orders.ErrStoreNotFound
	}
	return orders.StoreInfo{Slug: exampleStore.Slug, Name: exampleStore.Name, WhatsApp: exampleStore.WhatsApp},
		map[string]orders.StoredProduct{
			"11111111-1111-4111-8111-111111111111": {ID: "11111111-1111-4111-8111-111111111111", Name: "Rosa roja", PriceMinor: 100000, Currency: "CRC", Available: true},
			"22222222-2222-4222-8222-222222222222": {ID: "22222222-2222-4222-8222-222222222222", Name: "Arreglo pequeño", PriceMinor: 500000, Currency: "CRC", Available: true},
		}, nil
}

type fakeAI struct{}

func (fakeAI) Generate(context.Context, string) (ai.Suggestion, error) {
	return ai.Suggestion{Name: "Rosa roja natural", ShortDescription: "Una rosa roja fresca, ideal para regalar en cualquier ocasión.",
		MarketingText: "Sorprende a alguien especial con una rosa roja natural."}, nil
}

func fakeRouter(t *testing.T, mock bool) http.Handler {
	t.Helper()
	cfg := config.Config{Env: config.EnvLocal, MockMode: mock, Version: "test", StoreSignupEnabled: true,
		CORSAllowedOrigins: []string{"http://localhost:3000"}}
	return NewRouter(cfg, Deps{
		DB: okDB{}, Products: demoProducts{}, Kiuvy: kiuvy.Disabled{},
		Log:  slog.New(slog.NewTextHandler(io.Discard, nil)),
		Auth: fakeStores{}, StoreRepo: fakeStores{}, ProductRepo: fakeProducts{},
		Images:    products.LocalImages{Images: storage.Images{Dir: t.TempDir()}},
		OrderRepo: fakeOrders{}, AI: fakeAI{},
		// Agentic routes are mounted with identity disabled and no database: these
		// tests only check routing and auth; their behaviour is covered against PostgreSQL.
		Verifier: identity.Disabled{}, Users: nil, Owners: storeOwners{},
		Agent: agent.NewService(agent.NewRepo(nil), agent.LocalBrain{}, agent.NoCopy{}, storefront.NewRepo(nil),
			agent.NewBus(), slog.New(slog.NewTextHandler(io.Discard, nil)), agent.Config{}, nil),
		Storefront: storefront.NewRepo(nil), CheckoutDB: orders.NewRepo(nil), Payments: payments.Mock{},
		Speech: speech.Disabled{}, Funnel: &countSink{},
	})
}

type storeOwners struct{}

func (storeOwners) Claim(context.Context, []byte, string) (stores.Store, error) {
	return stores.Store{}, auth.ErrInvalidToken
}
func (storeOwners) ListOwned(context.Context, string) ([]stores.OwnedBrief, error) { return nil, nil }
