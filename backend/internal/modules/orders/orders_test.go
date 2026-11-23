package orders

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

const (
	rosa    = "11111111-1111-4111-8111-111111111111"
	arreglo = "22222222-2222-4222-8222-222222222222"
	off     = "33333333-3333-4333-8333-333333333333"
	foreign = "44444444-4444-4444-8444-444444444444"
)

var store = StoreInfo{Slug: "flores-de-occidente", Name: "Flores de Occidente", WhatsApp: "50600000001"}

var stored = map[string]StoredProduct{
	rosa:    {ID: rosa, Name: "Rosa roja", PriceMinor: 100000, Currency: "CRC", Available: true},
	arreglo: {ID: arreglo, Name: "Arreglo pequeño", PriceMinor: 500000, Currency: "CRC", Available: true},
	off:     {ID: off, Name: "Girasol", PriceMinor: 90000, Currency: "CRC", Available: false},
}

func TestBuildComputesFromStoredPrices(t *testing.T) {
	items, lerr := Normalize(Request{Items: []Item{{rosa, 1}, {arreglo, 1}, {rosa, 1}}})
	if lerr != nil {
		t.Fatal(lerr)
	}
	p, lerr := Build(store, items, stored)
	if lerr != nil {
		t.Fatal(lerr)
	}
	if len(p.Lines) != 2 || p.Lines[0].Quantity != 2 || p.Lines[0].SubtotalMinor != 200000 {
		t.Fatalf("lines %+v", p.Lines)
	}
	if p.TotalMinor != 700000 {
		t.Fatalf("total %d", p.TotalMinor)
	}
	want := "Hola, quiero realizar este pedido en Flores de Occidente:\n\n" +
		"2 × Rosa roja — ₡2.000\n1 × Arreglo pequeño — ₡5.000\n\nTotal: ₡7.000\n\n¿Me pueden confirmar disponibilidad?"
	if p.Message != want {
		t.Fatalf("message:\n%s", p.Message)
	}
	u, err := url.Parse(p.WhatsAppURL)
	if err != nil || u.Host != "wa.me" || u.Path != "/50600000001" {
		t.Fatalf("url %q", p.WhatsAppURL)
	}
	if strings.Contains(p.WhatsAppURL, "+") || !strings.Contains(p.WhatsAppURL, "%20") {
		t.Fatalf("spaces must be %%20: %s", p.WhatsAppURL)
	}
	if u.Query().Get("text") != want {
		t.Fatal("encoded text does not round-trip")
	}
}

func TestRejections(t *testing.T) {
	cases := map[string]struct {
		items []Item
		code  string
	}{
		"empty":       {nil, "empty_order"},
		"zero qty":    {[]Item{{rosa, 0}}, "invalid_quantity"},
		"huge qty":    {[]Item{{rosa, 100}}, "invalid_quantity"},
		"merged > 99": {[]Item{{rosa, 60}, {rosa, 40}}, "invalid_quantity"},
		"bad id":      {[]Item{{"x", 1}}, "invalid_product"},
		"other store": {[]Item{{foreign, 1}}, "product_not_found"},
		"disabled":    {[]Item{{off, 1}}, "product_unavailable"},
	}
	for name, tc := range cases {
		items, lerr := Normalize(Request{Items: tc.items})
		if lerr == nil {
			_, lerr = Build(store, items, stored)
		}
		if lerr == nil || lerr.Code != tc.code {
			t.Errorf("%s: got %v want %s", name, lerr, tc.code)
		}
	}
}

func TestFormatCRC(t *testing.T) {
	for minor, want := range map[int64]string{
		0: "₡0", 100: "₡1", 200000: "₡2.000", 123456789: "₡1.234.567,89", 100000000000: "₡1.000.000.000",
	} {
		if got := FormatCRC(minor); got != want {
			t.Errorf("FormatCRC(%d)=%q want %q", minor, got, want)
		}
	}
}

type fakeRepo struct{}

func (fakeRepo) Load(_ context.Context, slug string, ids []string) (StoreInfo, map[string]StoredProduct, error) {
	if slug != store.Slug {
		return StoreInfo{}, nil, ErrStoreNotFound
	}
	out := map[string]StoredProduct{}
	for _, id := range ids {
		if p, ok := stored[id]; ok {
			out[id] = p
		}
	}
	return store, out, nil
}

func TestHandlerRejectsClientPrices(t *testing.T) {
	mux := http.NewServeMux()
	NewHandler(fakeRepo{}, slog.New(slog.NewTextHandler(io.Discard, nil))).Register(mux)
	body := `{"items":[{"product_id":"` + rosa + `","quantity":1,"price_minor":1}]}`
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/api/v1/public/stores/flores-de-occidente/orders/preview", strings.NewReader(body)))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("client price must be rejected, got %d %s", rec.Code, rec.Body)
	}
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/api/v1/public/stores/nope/orders/preview",
		strings.NewReader(`{"items":[{"product_id":"`+rosa+`","quantity":1}]}`)))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("unknown store: %d", rec.Code)
	}
}
