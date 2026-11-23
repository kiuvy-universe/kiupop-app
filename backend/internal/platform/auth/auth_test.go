package auth

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

type resolver map[string]string

func (r resolver) ResolveStoreID(_ context.Context, h []byte) (string, error) {
	for tok, id := range r {
		if bytes.Equal(HashToken(tok), h) {
			return id, nil
		}
	}
	return "", ErrInvalidToken
}

func TestNewTokenIsRandomAndHashed(t *testing.T) {
	a, ha, err := NewToken()
	if err != nil {
		t.Fatal(err)
	}
	b, _, _ := NewToken()
	if a == b {
		t.Fatal("tokens must differ")
	}
	if !strings.HasPrefix(a, TokenPrefix) || len(a) != len(TokenPrefix)+43 {
		t.Fatalf("unexpected token shape len=%d", len(a))
	}
	if len(ha) != 32 || bytes.Contains(ha, []byte(a)) {
		t.Fatal("hash must be 32 bytes and not contain the token")
	}
}

func TestRequireStoreAdmin(t *testing.T) {
	tok, _, _ := NewToken()
	h := RequireStoreAdmin(resolver{tok: "store-1"}, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(StoreID(r.Context())))
	}))
	for name, tc := range map[string]struct {
		header string
		code   int
	}{
		"ok":          {"Bearer " + tok, 200},
		"missing":     {"", 401},
		"wrong token": {"Bearer kp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", 401},
		"no prefix":   {"Bearer " + strings.TrimPrefix(tok, TokenPrefix), 401},
		"basic":       {"Basic abc", 401},
	} {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		if tc.header != "" {
			req.Header.Set("Authorization", tc.header)
		}
		h.ServeHTTP(rec, req)
		if rec.Code != tc.code {
			t.Errorf("%s: code=%d want %d", name, rec.Code, tc.code)
		}
		if tc.code == 200 && rec.Body.String() != "store-1" {
			t.Errorf("%s: store id not propagated", name)
		}
	}
}
