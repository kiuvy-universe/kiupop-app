package identity

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

// claims are the Firebase ID token fields we rely on.
type claims struct {
	Iss           string  `json:"iss"`
	Aud           string  `json:"aud"`
	Sub           string  `json:"sub"`
	Iat           float64 `json:"iat"`
	Exp           float64 `json:"exp"`
	AuthTime      float64 `json:"auth_time"`
	Email         string  `json:"email"`
	EmailVerified bool    `json:"email_verified"`
	Name          string  `json:"name"`
	Firebase      struct {
		SignInProvider string `json:"sign_in_provider"`
	} `json:"firebase"`
}

type header struct {
	Alg string `json:"alg"`
	Kid string `json:"kid"`
	Typ string `json:"typ"`
}

func decodeSegment(seg string, dst any) error {
	b, err := base64.RawURLEncoding.DecodeString(strings.TrimRight(seg, "="))
	if err != nil {
		return err
	}
	return json.Unmarshal(b, dst)
}

// skew tolerates small clock differences between issuer and server.
const skew = 2 * time.Minute

// validate checks the standard Firebase ID token rules for projectID.
func (c claims) validate(projectID string, now time.Time) error {
	if c.Aud != projectID {
		return fmt.Errorf("aud mismatch")
	}
	if c.Iss != "https://securetoken.google.com/"+projectID {
		return fmt.Errorf("iss mismatch")
	}
	if c.Sub == "" || len(c.Sub) > 128 {
		return fmt.Errorf("bad sub")
	}
	exp := time.Unix(int64(c.Exp), 0)
	iat := time.Unix(int64(c.Iat), 0)
	if now.After(exp.Add(skew)) {
		return fmt.Errorf("expired")
	}
	if iat.After(now.Add(skew)) {
		return fmt.Errorf("issued in the future")
	}
	if c.AuthTime > 0 && time.Unix(int64(c.AuthTime), 0).After(now.Add(skew)) {
		return fmt.Errorf("auth_time in the future")
	}
	return nil
}

func (c claims) identity() Identity {
	p := c.Firebase.SignInProvider
	if p == "" {
		p = "unknown"
	}
	return Identity{
		UID: c.Sub, Email: c.Email, EmailVerified: c.EmailVerified, Name: c.Name,
		Provider: p, AuthTime: time.Unix(int64(c.AuthTime), 0),
	}
}
