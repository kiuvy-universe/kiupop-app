// Package gcp provides Google Cloud access tokens without key files: the
// Cloud Run service account (metadata server) in the demo, or Application
// Default Credentials on a developer machine. Tokens are never logged.
package gcp

import (
	"context"
	"fmt"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
)

// Scope used by KiuPop's Google adapters (Speech-to-Text and Cloud Storage).
const Scope = "https://www.googleapis.com/auth/cloud-platform"

// TokenSource is the minimal contract adapters depend on (fake in tests).
type TokenSource interface {
	Token() (*oauth2.Token, error)
}

// Default returns the ambient credentials' token source.
func Default(ctx context.Context) (TokenSource, error) {
	ts, err := google.DefaultTokenSource(ctx, Scope)
	if err != nil {
		return nil, fmt.Errorf("google credentials: %w", err)
	}
	return oauth2.ReuseTokenSource(nil, ts), nil
}

// Static is a fixed token (tests only).
type Static string

// Token implements TokenSource.
func (s Static) Token() (*oauth2.Token, error) { return &oauth2.Token{AccessToken: string(s)}, nil }
