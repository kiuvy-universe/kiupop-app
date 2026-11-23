package app

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

const contractDir = "../../../packages/api_contracts"

type operation struct{ method, path string }

// operations parses "  /path:" and the "    get:/post:/patch:" keys beneath it.
func operations(t *testing.T) []operation {
	t.Helper()
	spec, err := os.ReadFile(filepath.Join(contractDir, "openapi.yaml"))
	if err != nil {
		t.Fatalf("read contract: %v", err)
	}
	pathRe := regexp.MustCompile(`^  (/\S+):\s*$`)
	methodRe := regexp.MustCompile(`^    (get|post|put|patch|delete):\s*$`)
	var ops []operation
	current := ""
	for _, line := range strings.Split(string(spec), "\n") {
		if m := pathRe.FindStringSubmatch(line); m != nil {
			current = m[1]
		} else if m := methodRe.FindStringSubmatch(line); m != nil && current != "" {
			ops = append(ops, operation{strings.ToUpper(m[1]), current})
		} else if strings.HasPrefix(line, "components:") {
			break
		}
	}
	if len(ops) < 14 {
		t.Fatalf("parsed only %d operations", len(ops))
	}
	return ops
}

var paramValues = strings.NewReplacer(
	"{slug}", "flores-de-occidente",
	"{id}", "11111111-1111-4111-8111-111111111111",
	"{key}", "0b1c2d3e-4f5a-4b6c-8d7e-8f9a0b1c2d3e.jpg",
)

// Every operation declared in openapi.yaml is routed (contract -> code).
func TestEveryContractOperationIsRouted(t *testing.T) {
	h := fakeRouter(t, true)
	for _, op := range operations(t) {
		req := httptest.NewRequest(op.method, paramValues.Replace(op.path), strings.NewReader("{}"))
		req.Header.Set("Authorization", "Bearer "+fakeToken)
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		if rec.Code == http.StatusMethodNotAllowed || strings.Contains(rec.Body.String(), `"code":"not_found"`) {
			t.Errorf("%s %s is in the contract but not routed (%d)", op.method, op.path, rec.Code)
		}
	}
}

// Responses carry exactly the keys of the shared examples (code -> contract).
func TestResponsesMatchContractExamples(t *testing.T) {
	cases := []struct {
		method, path, body, fixture string
		auth                        bool
	}{
		{"GET", "/healthz", "", "healthz.json", false},
		{"GET", "/api/v1/demo/info", "", "demo_info.json", false},
		{"GET", "/api/v1/demo/products", "", "demo_products.json", false},
		{"POST", "/api/v1/stores", example(t, "store_create_request.json"), "store_create_response.json", false},
		{"GET", "/api/v1/stores/flores-de-occidente", "", "store_public.json", false},
		{"GET", "/api/v1/admin/stores/current", "", "admin_store_current.json", true},
		{"POST", "/api/v1/admin/products", example(t, "product_create_request.json"), "product_admin.json", true},
		{"GET", "/api/v1/admin/products", "", "products_admin_list.json", true},
		{"GET", "/api/v1/public/stores/flores-de-occidente/products", "", "products_public_list.json", false},
		{"POST", "/api/v1/public/stores/flores-de-occidente/orders/preview", example(t, "order_preview_request.json"), "order_preview_response.json", false},
		{"POST", "/api/v1/admin/ai/product-description", example(t, "ai_request.json"), "ai_response.json", true},
	}
	h := fakeRouter(t, true)
	for _, c := range cases {
		req := httptest.NewRequest(c.method, c.path, strings.NewReader(c.body))
		if c.auth {
			req.Header.Set("Authorization", "Bearer "+fakeToken)
		}
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		if rec.Code >= 300 {
			t.Errorf("%s %s = %d %s", c.method, c.path, rec.Code, rec.Body)
			continue
		}
		var want, got map[string]any
		_ = json.Unmarshal([]byte(example(t, c.fixture)), &want)
		if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
			t.Fatalf("%s: invalid JSON: %v", c.path, err)
		}
		assertSameKeys(t, c.path, want, got)
		if c.fixture == "order_preview_response.json" {
			for _, k := range []string{"message", "whatsapp_url", "total_minor"} {
				if want[k] != got[k] {
					t.Errorf("order preview %s differs from contract example:\n got %v\nwant %v", k, got[k], want[k])
				}
			}
		}
	}
}

func example(t *testing.T, name string) string {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join(contractDir, "examples", name))
	if err != nil {
		t.Fatalf("read %s: %v", name, err)
	}
	return string(raw)
}

func assertSameKeys(t *testing.T, where string, want, got map[string]any) {
	t.Helper()
	for k, wv := range want {
		gv, ok := got[k]
		if !ok {
			t.Errorf("%s: missing key %q", where, k)
			continue
		}
		if wm, ok := wv.(map[string]any); ok {
			gm, _ := gv.(map[string]any)
			assertSameKeys(t, where+"."+k, wm, gm)
		}
		if wa, ok := wv.([]any); ok && len(wa) > 0 {
			ga, _ := gv.([]any)
			if len(ga) == 0 {
				t.Errorf("%s.%s: expected non-empty array", where, k)
				continue
			}
			if wm, ok := wa[0].(map[string]any); ok {
				gm, _ := ga[0].(map[string]any)
				assertSameKeys(t, where+"."+k+"[0]", wm, gm)
			}
		}
	}
	for k := range got {
		if _, ok := want[k]; !ok {
			t.Errorf("%s: key %q not in contract example", where, k)
		}
	}
}

func TestDemoRoutesAbsentWithoutMockMode(t *testing.T) {
	rec := httptest.NewRecorder()
	fakeRouter(t, false).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/v1/demo/products", nil))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("demo route must not exist without mock mode, got %d", rec.Code)
	}
}

func TestAdminRoutesRequireCredential(t *testing.T) {
	h := fakeRouter(t, true)
	for _, op := range operations(t) {
		if !strings.Contains(op.path, "/admin/") {
			continue
		}
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(op.method, paramValues.Replace(op.path), strings.NewReader("{}")))
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("%s %s without credential = %d, want 401", op.method, op.path, rec.Code)
		}
	}
}
