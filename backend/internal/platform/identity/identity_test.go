package identity

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"math/big"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

const project = "kiupop-test"

var now = time.Date(2026, 11, 22, 15, 0, 0, 0, time.UTC)

func seg(v any) string {
	b, _ := json.Marshal(v)
	return base64.RawURLEncoding.EncodeToString(b)
}

func goodClaims() map[string]any {
	return map[string]any{
		"iss": "https://securetoken.google.com/" + project, "aud": project, "sub": "uid-1",
		"iat": now.Add(-time.Minute).Unix(), "exp": now.Add(time.Hour).Unix(), "auth_time": now.Add(-time.Minute).Unix(),
		"email": "ana@example.test", "email_verified": true, "firebase": map[string]any{"sign_in_provider": "google.com"},
	}
}

func sign(t *testing.T, key *rsa.PrivateKey, kid string, claims map[string]any) string {
	t.Helper()
	head := seg(map[string]string{"alg": "RS256", "kid": kid, "typ": "JWT"}) + "." + seg(claims)
	sum := sha256.Sum256([]byte(head))
	sig, err := rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, sum[:])
	if err != nil {
		t.Fatal(err)
	}
	return head + "." + base64.RawURLEncoding.EncodeToString(sig)
}

func certServer(t *testing.T, key *rsa.PrivateKey, kid string) *httptest.Server {
	t.Helper()
	tmpl := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "test"},
		NotBefore: now.Add(-time.Hour), NotAfter: now.Add(time.Hour)}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	pemCert := string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}))
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Cache-Control", "public, max-age=600")
		_ = json.NewEncoder(w).Encode(map[string]string{kid: pemCert})
	}))
}

func TestFirebaseVerifier(t *testing.T) {
	key, _ := rsa.GenerateKey(rand.Reader, 2048)
	other, _ := rsa.GenerateKey(rand.Reader, 2048)
	srv := certServer(t, key, "k1")
	defer srv.Close()
	f := NewFirebase(project)
	f.CertsURL, f.Now = srv.URL, func() time.Time { return now }

	id, err := f.Verify(context.Background(), sign(t, key, "k1", goodClaims()))
	if err != nil || id.UID != "uid-1" || id.Provider != "google.com" {
		t.Fatalf("valid token rejected: %+v %v", id, err)
	}

	bad := map[string]func(map[string]any){
		"wrong audience": func(c map[string]any) { c["aud"] = "kiuvy-prod" },
		"wrong issuer":   func(c map[string]any) { c["iss"] = "https://evil.example" },
		"expired":        func(c map[string]any) { c["exp"] = now.Add(-time.Hour).Unix() },
		"future iat":     func(c map[string]any) { c["iat"] = now.Add(time.Hour).Unix() },
		"empty subject":  func(c map[string]any) { c["sub"] = "" },
	}
	for name, mutate := range bad {
		c := goodClaims()
		mutate(c)
		if _, err := f.Verify(context.Background(), sign(t, key, "k1", c)); err == nil {
			t.Errorf("%s: accepted", name)
		}
	}
	if _, err := f.Verify(context.Background(), sign(t, other, "k1", goodClaims())); err == nil {
		t.Error("token signed by another key accepted")
	}
	if _, err := f.Verify(context.Background(), sign(t, key, "unknown-kid", goodClaims())); err == nil {
		t.Error("unknown kid accepted")
	}
	unsigned := seg(map[string]string{"alg": "none"}) + "." + seg(goodClaims()) + "."
	if _, err := f.Verify(context.Background(), unsigned); err == nil {
		t.Error("alg=none accepted by the production verifier")
	}
}

func TestEmulatorVerifierAsksTheEmulator(t *testing.T) {
	known := "uid-1"
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasSuffix(r.URL.Path, "/accounts:lookup") {
			http.NotFound(w, r)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"users": []map[string]string{{"localId": known}}})
	}))
	defer srv.Close()
	e := NewEmulator(project, strings.TrimPrefix(srv.URL, "http://"))
	e.Now = func() time.Time { return now }
	tok := seg(map[string]string{"alg": "none"}) + "." + seg(goodClaims()) + "."
	if _, err := e.Verify(context.Background(), tok); err != nil {
		t.Fatalf("emulator token rejected: %v", err)
	}
	known = "someone-else"
	if _, err := e.Verify(context.Background(), tok); err == nil {
		t.Fatal("token for a user the emulator doesn't know was accepted")
	}
	c := goodClaims()
	c["aud"] = "other-project"
	if _, err := e.Verify(context.Background(), seg(map[string]string{"alg": "none"})+"."+seg(c)+"."); err == nil {
		t.Fatal("wrong project accepted")
	}
}

func TestBearerIDToken(t *testing.T) {
	if _, ok := BearerIDToken("Bearer kp_abcdefghijklmnopqrstuvwxyz"); ok {
		t.Error("legacy kp_ credential is not an ID token")
	}
	if _, ok := BearerIDToken("Bearer aaaaaaaa.bbbbbbbbbbbb.cccccccc"); !ok {
		t.Error("JWT shape rejected")
	}
	if _, ok := BearerIDToken("Basic aaaaaaaa.bbbbbbbbbbbb.cccccccc"); ok {
		t.Error("non-bearer accepted")
	}
}

type memUsers struct{}

func (memUsers) Upsert(_ context.Context, id Identity) (string, error) { return "user-" + id.UID, nil }

type staticVerifier struct{ err error }

func (s staticVerifier) Mode() string { return "test" }
func (s staticVerifier) Verify(context.Context, string) (Identity, error) {
	return Identity{UID: "x"}, s.err
}

func TestRequireUser(t *testing.T) {
	ok := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		u, _ := FromContext(r.Context())
		_, _ = w.Write([]byte(u.ID))
	})
	call := func(v Verifier, auth string) *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest("GET", "/", nil)
		if auth != "" {
			req.Header.Set("Authorization", auth)
		}
		RequireUser(v, memUsers{}, ok).ServeHTTP(rec, req)
		return rec
	}
	if rec := call(staticVerifier{}, "Bearer aaaaaaaa.bbbbbbbbbbbb.cccccccc"); rec.Code != 200 || rec.Body.String() != "user-x" {
		t.Fatalf("valid: %d %s", rec.Code, rec.Body)
	}
	if rec := call(staticVerifier{}, ""); rec.Code != 401 {
		t.Fatalf("missing: %d", rec.Code)
	}
	if rec := call(staticVerifier{err: ErrInvalidToken}, "Bearer aaaaaaaa.bbbbbbbbbbbb.cccccccc"); rec.Code != 401 {
		t.Fatalf("invalid: %d", rec.Code)
	}
	if rec := call(Disabled{}, "Bearer aaaaaaaa.bbbbbbbbbbbb.cccccccc"); rec.Code != 503 {
		t.Fatalf("disabled: %d", rec.Code)
	}
}
