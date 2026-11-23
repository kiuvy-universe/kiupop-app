package app

import (
	"bytes"
	"context"
	"encoding/json"
	"image"
	"image/png"
	"io"
	"log/slog"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/kiuvy-universe/kiupop/backend/internal/integrations/kiuvy"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/ai"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/demo"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/orders"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/products"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/stores"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/config"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/database"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/storage"
	"github.com/kiuvy-universe/kiupop/backend/migrations"
)

type client struct {
	t *testing.T
	h http.Handler
}

func (c client) do(method, path, token string, body any) (int, map[string]any, string) {
	c.t.Helper()
	var r io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		r = bytes.NewReader(b)
	}
	req := httptest.NewRequest(method, path, r)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	c.h.ServeHTTP(rec, req)
	var out map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	return rec.Code, out, rec.Body.String()
}

// End-to-end POC flow against a real PostgreSQL (make test-integration / CI).
func TestPOCFlowAgainstPostgres(t *testing.T) {
	url := os.Getenv("KIUPOP_TEST_DATABASE_URL")
	if url == "" {
		t.Skip("KIUPOP_TEST_DATABASE_URL not set")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	pool, err := database.Open(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	quiet := slog.New(slog.NewTextHandler(io.Discard, nil))
	if _, err := database.Migrate(ctx, pool, migrations.FS, quiet); err != nil {
		t.Fatal(err)
	}
	if err := demo.SeedStore(ctx, pool); err != nil {
		t.Fatal(err)
	}
	if err := demo.SeedStore(ctx, pool); err != nil { // idempotent
		t.Fatal(err)
	}

	storeRepo := stores.NewRepo(pool)
	cfg := config.Config{Env: config.EnvLocal, MockMode: true, StoreSignupEnabled: true, CORSAllowedOrigins: []string{"http://localhost:3000"}}
	h := NewRouter(cfg, Deps{
		DB: pool, Products: demo.NewPostgresRepo(pool), Kiuvy: kiuvy.Disabled{}, Log: quiet,
		Auth: storeRepo, StoreRepo: storeRepo, ProductRepo: products.NewRepo(pool),
		Images:    products.LocalImages{Images: storage.Images{Dir: t.TempDir()}},
		OrderRepo: orders.NewRepo(pool), AI: ai.Disabled{},
	})
	c := client{t, h}
	suffix := time.Now().Format("150405.000000")
	nameA := "Flores de Occidente " + suffix

	// --- stores ---------------------------------------------------------------
	code, a, raw := c.do("POST", "/api/v1/stores", "", map[string]any{"name": nameA, "whatsapp": "+506 0000 0001"})
	if code != 201 {
		t.Fatalf("create store: %d %s", code, raw)
	}
	tokA := a["admin_token"].(string)
	slugA := a["store"].(map[string]any)["slug"].(string)

	code, dup, _ := c.do("POST", "/api/v1/stores", "", map[string]any{"name": nameA, "whatsapp": "+506 0000 0002"})
	if code != 201 || dup["store"].(map[string]any)["slug"] == slugA {
		t.Fatalf("duplicate name must get a different slug: %v", dup["store"])
	}
	tokB := dup["admin_token"].(string)
	slugB := dup["store"].(map[string]any)["slug"].(string)
	if tokA == tokB {
		t.Fatal("tokens must be unique per store")
	}

	if code, _, _ := c.do("POST", "/api/v1/stores", "", map[string]any{"name": "x", "whatsapp": "12"}); code != 422 {
		t.Fatalf("invalid store must be 422, got %d", code)
	}

	// Token is stored hashed, never in clear.
	var clear int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM store_admin_credentials WHERE token_hash = convert_to($1, 'UTF8')`, tokA).Scan(&clear); err != nil || clear != 0 {
		t.Fatalf("token stored in clear? count=%d err=%v", clear, err)
	}

	// Public store hides private data.
	code, _, raw = c.do("GET", "/api/v1/stores/"+slugA, "", nil)
	if code != 200 || strings.Contains(raw, "admin_token") || strings.Contains(raw, "50600000001") || strings.Contains(raw, `"id"`) {
		t.Fatalf("public store leaks data: %d %s", code, raw)
	}
	if code, _, _ := c.do("GET", "/api/v1/stores/no-existe-"+strings.ReplaceAll(suffix, ".", ""), "", nil); code != 404 {
		t.Fatalf("missing store: %d", code)
	}

	// --- products -------------------------------------------------------------
	mk := func(tok, name string, price int) string {
		code, p, raw := c.do("POST", "/api/v1/admin/products", tok, map[string]any{"name": name, "price_minor": price})
		if code != 201 {
			t.Fatalf("create product %s: %d %s", name, code, raw)
		}
		return p["id"].(string)
	}
	rosa := mk(tokA, "Rosa roja", 100000)
	arreglo := mk(tokA, "Arreglo pequeño", 500000)
	girasol := mk(tokA, "Girasol", 90000)
	ajeno := mk(tokB, "Producto de B", 300000)

	if code, _, _ := c.do("POST", "/api/v1/admin/products", tokA, map[string]any{"name": "Gratis", "price_minor": 0}); code != 422 {
		t.Fatalf("price 0 must be 422, got %d", code)
	}
	if code, _, _ := c.do("POST", "/api/v1/admin/products", "", map[string]any{"name": "x", "price_minor": 1}); code != 401 {
		t.Fatalf("no credential must be 401, got %d", code)
	}

	// Edit + disable.
	code, p, _ := c.do("PATCH", "/api/v1/admin/products/"+rosa, tokA, map[string]any{"description": "Rosa natural de tallo largo."})
	if code != 200 || p["description"] != "Rosa natural de tallo largo." || p["price_minor"].(float64) != 100000 {
		t.Fatalf("patch: %d %v", code, p)
	}
	if code, p, _ := c.do("PATCH", "/api/v1/admin/products/"+girasol, tokA, map[string]any{"available": false}); code != 200 || p["available"] != false {
		t.Fatalf("disable: %d %v", code, p)
	}

	// Cross-store isolation: B cannot read or edit A's products.
	if code, _, _ := c.do("PATCH", "/api/v1/admin/products/"+rosa, tokB, map[string]any{"price_minor": 1}); code != 404 {
		t.Fatalf("B editing A's product must be 404, got %d", code)
	}
	_, listB, _ := c.do("GET", "/api/v1/admin/products", tokB, nil)
	if n := len(listB["data"].([]any)); n != 1 {
		t.Fatalf("B must only see its own product, got %d", n)
	}

	// Image upload (real PNG) and serving.
	var img bytes.Buffer
	_ = png.Encode(&img, image.NewRGBA(image.Rect(0, 0, 4, 4)))
	var form bytes.Buffer
	mw := multipart.NewWriter(&form)
	fw, _ := mw.CreateFormFile("image", "rosa.png")
	_, _ = fw.Write(img.Bytes())
	_ = mw.Close()
	req := httptest.NewRequest("POST", "/api/v1/admin/products/"+rosa+"/image", &form)
	req.Header.Set("Content-Type", mw.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+tokA)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != 200 {
		t.Fatalf("upload: %d %s", rec.Code, rec.Body)
	}
	var withImg map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &withImg)
	imgURL, _ := withImg["image_url"].(string)
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("GET", imgURL, nil))
	if rec.Code != 200 || rec.Header().Get("Content-Type") != "image/png" {
		t.Fatalf("serve image: %d %s", rec.Code, rec.Header().Get("Content-Type"))
	}

	// --- public catalog -------------------------------------------------------
	code, cat, raw := c.do("GET", "/api/v1/public/stores/"+slugA+"/products", "", nil)
	if code != 200 {
		t.Fatalf("catalog: %d", code)
	}
	names := map[string]bool{}
	for _, it := range cat["data"].([]any) {
		names[it.(map[string]any)["name"].(string)] = true
	}
	if len(names) != 2 || !names["Rosa roja"] || !names["Arreglo pequeño"] || names["Girasol"] || names["Producto de B"] {
		t.Fatalf("catalog must show only A's available products: %v", names)
	}
	if strings.Contains(raw, "store_id") || strings.Contains(raw, "available") {
		t.Fatalf("catalog leaks internals: %s", raw)
	}
	_, catB, _ := c.do("GET", "/api/v1/public/stores/"+slugB+"/products", "", nil)
	if n := len(catB["data"].([]any)); n != 1 {
		t.Fatalf("B catalog must have 1 product, got %d", n)
	}
	if code, _, _ := c.do("GET", "/api/v1/public/stores/no-existe-xyz/products", "", nil); code != 404 {
		t.Fatalf("missing store catalog: %d", code)
	}

	// --- orders ---------------------------------------------------------------
	order := func(items ...map[string]any) (int, map[string]any) {
		code, out, _ := c.do("POST", "/api/v1/public/stores/"+slugA+"/orders/preview", "", map[string]any{"items": items})
		return code, out
	}
	item := func(id string, q int) map[string]any { return map[string]any{"product_id": id, "quantity": q} }

	code, prev := order(item(rosa, 2), item(arreglo, 1))
	if code != 200 || prev["total_minor"].(float64) != 700000 {
		t.Fatalf("preview: %d %v", code, prev)
	}
	if !strings.HasPrefix(prev["whatsapp_url"].(string), "https://wa.me/50600000001?text=") ||
		!strings.Contains(prev["message"].(string), "2 × Rosa roja — ₡2.000") {
		t.Fatalf("preview message/url: %v", prev)
	}
	if code, out := order(item(girasol, 1)); code != 422 || out["error"].(map[string]any)["code"] != "product_unavailable" {
		t.Fatalf("disabled product: %d %v", code, out)
	}
	if code, out := order(item(ajeno, 1)); code != 422 || out["error"].(map[string]any)["code"] != "product_not_found" {
		t.Fatalf("foreign product: %d %v", code, out)
	}
	if code, _ := order(item(rosa, 0)); code != 422 {
		t.Fatalf("qty 0: %d", code)
	}
	code, _, _ = c.do("POST", "/api/v1/public/stores/"+slugA+"/orders/preview", "",
		map[string]any{"items": []any{map[string]any{"product_id": rosa, "quantity": 1, "unit_price_minor": 1}}})
	if code != 400 {
		t.Fatalf("client-supplied price must be rejected: %d", code)
	}

	// Demo store is reachable read-only.
	if code, _, _ := c.do("GET", "/api/v1/public/stores/"+demo.DemoStoreSlug+"/products", "", nil); code != 200 {
		t.Fatalf("demo store: %d", code)
	}
}
