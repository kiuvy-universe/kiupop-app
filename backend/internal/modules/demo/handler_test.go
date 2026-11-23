package demo

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
)

type fakeLister struct {
	products []Product
	err      error
}

func (f fakeLister) ListProducts(context.Context) ([]Product, error) { return f.products, f.err }

func newMux(l ProductLister) *http.ServeMux {
	mux := http.NewServeMux()
	NewHandler(l, Info{Service: "kiupop-api", KiuvyIntegration: "disabled"}, slog.New(slog.NewTextHandler(io.Discard, nil))).Register(mux)
	return mux
}

func TestListProducts(t *testing.T) {
	mux := newMux(fakeLister{products: []Product{{ID: "p1", Name: "Pan", PriceMinor: 150000, Currency: "CRC"}}})
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/v1/demo/products", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	var body ProductsResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Source != "postgres" || len(body.Data) != 1 || body.Data[0].PriceMinor != 150000 {
		t.Fatalf("unexpected body: %+v", body)
	}
}

func TestListProductsEmptyIsArray(t *testing.T) {
	mux := newMux(fakeLister{products: []Product{}})
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/v1/demo/products", nil))
	if got := rec.Body.String(); got != "{\"data\":[],\"source\":\"postgres\"}\n" {
		t.Fatalf("body = %q", got)
	}
}

func TestListProductsDatabaseError(t *testing.T) {
	mux := newMux(fakeLister{err: errors.New("boom")})
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/v1/demo/products", nil))
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d", rec.Code)
	}
	var body map[string]map[string]string
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body["error"]["code"] != "database_unavailable" {
		t.Fatalf("body = %s", rec.Body.String())
	}
	if want := "boom"; contains(rec.Body.String(), want) {
		t.Fatal("internal error leaked to client")
	}
}

func TestInfoHasNoSecrets(t *testing.T) {
	mux := newMux(fakeLister{})
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/v1/demo/info", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	for _, banned := range []string{"postgres://", "password", "DATABASE_URL"} {
		if contains(rec.Body.String(), banned) {
			t.Fatalf("info leaks %q", banned)
		}
	}
}

func contains(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
