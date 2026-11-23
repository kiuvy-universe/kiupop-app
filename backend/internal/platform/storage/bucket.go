package storage

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"

	"github.com/kiuvy-universe/kiupop/backend/internal/platform/gcp"
)

// Bucket is object storage for photos and catalogs. Names are always
// server-generated (prefix + validated key); callers never pass user paths.
type Bucket interface {
	Put(ctx context.Context, name string, data []byte, contentType string) error
	Get(ctx context.Context, name string, max int64) ([]byte, error)
	Delete(ctx context.Context, name string) error
}

// Object prefixes. tmp/ has a bucket lifecycle rule that deletes objects
// after 1 day; images/ holds catalog photos that published stores use.
const (
	PrefixImages = "images/"
	PrefixDocs   = "tmp/docs/"
)

var objectNameRe = regexp.MustCompile(`^(images/|tmp/docs/)[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|png|webp|pdf|csv)$`)

// ErrInvalidObject means a name that the server did not generate.
var ErrInvalidObject = errors.New("invalid object name")

// GCS talks to the Cloud Storage JSON API of one private bucket using the
// service identity (no key files, no signed URLs handed to clients).
type GCS struct {
	Bucket string
	Tokens gcp.TokenSource
	Client *http.Client
	// Endpoint overrides https://storage.googleapis.com (tests).
	Endpoint string
}

func (g GCS) endpoint() string {
	if g.Endpoint != "" {
		return strings.TrimRight(g.Endpoint, "/")
	}
	return "https://storage.googleapis.com"
}

func (g GCS) client() *http.Client {
	if g.Client != nil {
		return g.Client
	}
	return &http.Client{Timeout: 30 * time.Second}
}

func (g GCS) do(ctx context.Context, method, u, contentType string, body io.Reader) (*http.Response, error) {
	tok, err := g.Tokens.Token()
	if err != nil {
		return nil, fmt.Errorf("storage token: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, method, u, body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+tok.AccessToken)
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}
	return g.client().Do(req)
}

// Put uploads a new object; it never overwrites (ifGenerationMatch=0).
func (g GCS) Put(ctx context.Context, name string, data []byte, contentType string) error {
	if !objectNameRe.MatchString(name) {
		return ErrInvalidObject
	}
	u := fmt.Sprintf("%s/upload/storage/v1/b/%s/o?uploadType=media&ifGenerationMatch=0&name=%s",
		g.endpoint(), url.PathEscape(g.Bucket), url.QueryEscape(name))
	resp, err := g.do(ctx, http.MethodPost, u, contentType, bytes.NewReader(data))
	if err != nil {
		return fmt.Errorf("storage put: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("storage put: status %d", resp.StatusCode)
	}
	return nil
}

// Get downloads an object, refusing anything larger than max bytes.
func (g GCS) Get(ctx context.Context, name string, max int64) ([]byte, error) {
	if !objectNameRe.MatchString(name) {
		return nil, ErrNotFound
	}
	u := fmt.Sprintf("%s/storage/v1/b/%s/o/%s?alt=media", g.endpoint(), url.PathEscape(g.Bucket), url.PathEscape(name))
	resp, err := g.do(ctx, http.MethodGet, u, "", nil)
	if err != nil {
		return nil, fmt.Errorf("storage get: %w", err)
	}
	defer resp.Body.Close()
	switch {
	case resp.StatusCode == http.StatusNotFound:
		return nil, ErrNotFound
	case resp.StatusCode != http.StatusOK:
		return nil, fmt.Errorf("storage get: status %d", resp.StatusCode)
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, max+1))
	if err != nil {
		return nil, fmt.Errorf("storage get: %w", err)
	}
	if int64(len(data)) > max {
		return nil, fmt.Errorf("storage get: object larger than %d bytes", max)
	}
	return data, nil
}

// Delete removes an object (missing objects are not an error).
func (g GCS) Delete(ctx context.Context, name string) error {
	if !objectNameRe.MatchString(name) {
		return ErrInvalidObject
	}
	u := fmt.Sprintf("%s/storage/v1/b/%s/o/%s", g.endpoint(), url.PathEscape(g.Bucket), url.PathEscape(name))
	resp, err := g.do(ctx, http.MethodDelete, u, "", nil)
	if err != nil {
		return fmt.Errorf("storage delete: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent && resp.StatusCode != http.StatusNotFound && resp.StatusCode != http.StatusOK {
		return fmt.Errorf("storage delete: status %d", resp.StatusCode)
	}
	return nil
}

const opTimeout = 30 * time.Second

// BucketImages stores validated product photos under images/.
type BucketImages struct{ B Bucket }

// Save validates data (real JPEG/PNG/WebP) and stores it under a new key.
func (s BucketImages) Save(data []byte) (string, error) {
	ext, err := Sniff(data)
	if err != nil {
		return "", err
	}
	key := newUUID() + "." + ext
	ctx, cancel := context.WithTimeout(context.Background(), opTimeout)
	defer cancel()
	if err := s.B.Put(ctx, PrefixImages+key, data, ContentTypeFor(key)); err != nil {
		return "", err
	}
	return key, nil
}

// Open returns the photo bytes as a seekable reader.
func (s BucketImages) Open(key string) (io.ReadSeekCloser, error) {
	if !ValidKey(key) {
		return nil, ErrNotFound
	}
	ctx, cancel := context.WithTimeout(context.Background(), opTimeout)
	defer cancel()
	data, err := s.B.Get(ctx, PrefixImages+key, MaxImageBytes)
	if err != nil {
		return nil, err
	}
	return nopSeekCloser{bytes.NewReader(data)}, nil
}

// Delete removes a photo (best effort).
func (s BucketImages) Delete(key string) {
	if !ValidKey(key) {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), opTimeout)
	defer cancel()
	_ = s.B.Delete(ctx, PrefixImages+key)
}

// BucketDocs stores catalogs (PDF/CSV) under tmp/: deleted by lifecycle in 24 h.
type BucketDocs struct{ B Bucket }

// Save stores a document with a fresh key.
func (d BucketDocs) Save(data []byte, ext string) (string, error) {
	if ext != "pdf" && ext != "csv" {
		return "", ErrInvalidDocKey
	}
	key := newUUID() + "." + ext
	ctype := "text/csv"
	if ext == "pdf" {
		ctype = "application/pdf"
	}
	ctx, cancel := context.WithTimeout(context.Background(), opTimeout)
	defer cancel()
	if err := d.B.Put(ctx, PrefixDocs+key, data, ctype); err != nil {
		return "", err
	}
	return key, nil
}

// Read returns a stored document (bounded).
func (d BucketDocs) Read(key string, max int64) ([]byte, error) {
	if !docKeyRe.MatchString(key) {
		return nil, ErrInvalidDocKey
	}
	ctx, cancel := context.WithTimeout(context.Background(), opTimeout)
	defer cancel()
	return d.B.Get(ctx, PrefixDocs+key, max)
}

// Delete removes a document (best effort; lifecycle deletes it anyway).
func (d BucketDocs) Delete(key string) {
	if !docKeyRe.MatchString(key) {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), opTimeout)
	defer cancel()
	_ = d.B.Delete(ctx, PrefixDocs+key)
}

type nopSeekCloser struct{ *bytes.Reader }

func (nopSeekCloser) Close() error { return nil }
