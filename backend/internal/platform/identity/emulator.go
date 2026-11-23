package identity

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

// Emulator verifies tokens issued by the local Firebase Auth emulator. Emulator
// tokens are unsigned, so besides checking the claims we ask the emulator itself
// (accounts:lookup) to confirm it issued the token. Config only allows this in
// APP_ENV=local|development (fails closed elsewhere).
type Emulator struct {
	ProjectID string
	Host      string // e.g. "auth-emulator:9099"
	HTTP      *http.Client
	Now       func() time.Time
}

// NewEmulator builds the emulator verifier.
func NewEmulator(projectID, host string) *Emulator {
	return &Emulator{ProjectID: projectID, Host: host, HTTP: &http.Client{Timeout: 3 * time.Second}, Now: time.Now}
}

// Mode implements Verifier.
func (e *Emulator) Mode() string { return "emulator" }

// Verify implements Verifier.
func (e *Emulator) Verify(ctx context.Context, tok string) (Identity, error) {
	parts := strings.Split(tok, ".")
	if len(parts) != 3 {
		return Identity{}, ErrInvalidToken
	}
	var c claims
	if decodeSegment(parts[1], &c) != nil || c.validate(e.ProjectID, e.Now()) != nil {
		return Identity{}, ErrInvalidToken
	}
	body, _ := json.Marshal(map[string]string{"idToken": tok})
	url := fmt.Sprintf("http://%s/identitytoolkit.googleapis.com/v1/accounts:lookup?key=emulator", e.Host)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return Identity{}, err
	}
	req.Header.Set("Content-Type", "application/json")
	res, err := e.HTTP.Do(req)
	if err != nil {
		return Identity{}, fmt.Errorf("%w: auth emulator: %v", ErrUnavailable, err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return Identity{}, ErrInvalidToken
	}
	var out struct {
		Users []struct {
			LocalID       string `json:"localId"`
			Email         string `json:"email"`
			EmailVerified bool   `json:"emailVerified"`
			DisplayName   string `json:"displayName"`
		} `json:"users"`
	}
	if json.NewDecoder(res.Body).Decode(&out) != nil || len(out.Users) != 1 || out.Users[0].LocalID != c.Sub {
		return Identity{}, ErrInvalidToken
	}
	// Unsigned token: trust only the uid; profile data comes from the emulator itself.
	id := c.identity()
	id.Email, id.EmailVerified, id.Name = out.Users[0].Email, out.Users[0].EmailVerified, out.Users[0].DisplayName
	return id, nil
}
