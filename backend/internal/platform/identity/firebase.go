package identity

import (
	"context"
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

// GoogleCertsURL publishes the keys that sign Firebase ID tokens.
const GoogleCertsURL = "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com"

// Firebase verifies real Firebase Auth ID tokens (RS256, Google-published keys).
type Firebase struct {
	ProjectID string
	CertsURL  string
	HTTP      *http.Client
	Now       func() time.Time

	mu      sync.Mutex
	keys    map[string]*rsa.PublicKey
	expires time.Time
	failed  time.Time // last failed refresh: back off instead of hammering Google
}

// NewFirebase returns a verifier for a KiuPop-dedicated Firebase project.
func NewFirebase(projectID string) *Firebase {
	return &Firebase{ProjectID: projectID, CertsURL: GoogleCertsURL, HTTP: &http.Client{Timeout: 5 * time.Second}, Now: time.Now}
}

// Mode implements Verifier.
func (f *Firebase) Mode() string { return "firebase" }

// Verify implements Verifier.
func (f *Firebase) Verify(ctx context.Context, tok string) (Identity, error) {
	parts := strings.Split(tok, ".")
	if len(parts) != 3 {
		return Identity{}, ErrInvalidToken
	}
	var h header
	var c claims
	if decodeSegment(parts[0], &h) != nil || decodeSegment(parts[1], &c) != nil {
		return Identity{}, ErrInvalidToken
	}
	if h.Alg != "RS256" || h.Kid == "" { // never accept "none" or HMAC here
		return Identity{}, ErrInvalidToken
	}
	key, err := f.key(ctx, h.Kid)
	if err != nil {
		return Identity{}, err
	}
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return Identity{}, ErrInvalidToken
	}
	sum := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	if rsa.VerifyPKCS1v15(key, crypto.SHA256, sum[:], sig) != nil {
		return Identity{}, ErrInvalidToken
	}
	if c.validate(f.ProjectID, f.Now()) != nil {
		return Identity{}, ErrInvalidToken
	}
	return c.identity(), nil
}

func (f *Firebase) key(ctx context.Context, kid string) (*rsa.PublicKey, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.keys == nil || f.Now().After(f.expires) {
		if f.keys == nil && f.Now().Sub(f.failed) < 10*time.Second {
			return nil, fmt.Errorf("%w: certificate fetch backing off", ErrUnavailable)
		}
		if err := f.refresh(ctx); err != nil {
			f.failed = f.Now()
			if f.keys != nil { // keep serving with the previous keys while Google recovers
				f.expires = f.Now().Add(time.Minute)
				return f.lookup(kid)
			}
			return nil, fmt.Errorf("%w: %v", ErrUnavailable, err)
		}
	}
	return f.lookup(kid)
}

func (f *Firebase) lookup(kid string) (*rsa.PublicKey, error) {
	k, ok := f.keys[kid]
	if !ok {
		return nil, ErrInvalidToken
	}
	return k, nil
}

func (f *Firebase) refresh(ctx context.Context) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, f.CertsURL, nil)
	if err != nil {
		return err
	}
	res, err := f.HTTP.Do(req)
	if err != nil {
		return fmt.Errorf("fetch certs: %w", err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return fmt.Errorf("fetch certs: status %d", res.StatusCode)
	}
	var raw map[string]string
	if err := json.NewDecoder(res.Body).Decode(&raw); err != nil {
		return fmt.Errorf("decode certs: %w", err)
	}
	keys := map[string]*rsa.PublicKey{}
	for kid, certPEM := range raw {
		block, _ := pem.Decode([]byte(certPEM))
		if block == nil {
			continue
		}
		cert, err := x509.ParseCertificate(block.Bytes)
		if err != nil {
			continue
		}
		if pk, ok := cert.PublicKey.(*rsa.PublicKey); ok {
			keys[kid] = pk
		}
	}
	if len(keys) == 0 {
		return fmt.Errorf("no usable certs")
	}
	f.keys = keys
	f.expires = f.Now().Add(maxAge(res.Header.Get("Cache-Control")))
	return nil
}

func maxAge(cc string) time.Duration {
	for _, part := range strings.Split(cc, ",") {
		part = strings.TrimSpace(part)
		if v, ok := strings.CutPrefix(part, "max-age="); ok {
			if n, err := strconv.Atoi(v); err == nil && n > 0 {
				return time.Duration(n) * time.Second
			}
		}
	}
	return time.Hour
}
