package storage

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
)

// Docs keeps merchant documents (CSV/PDF catalogs) for processing. Names are
// server-generated; documents are never served publicly nor executed.
type Docs struct{ Dir string }

var docKeyRe = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(pdf|csv)$`)

// ErrInvalidDocKey means the key does not have the server-generated shape.
var ErrInvalidDocKey = errors.New("invalid document key")

func (d Docs) dir() string { return filepath.Join(d.Dir, "docs") }

// Save writes data with a fresh key and the given extension (pdf|csv).
func (d Docs) Save(data []byte, ext string) (string, error) {
	if ext != "pdf" && ext != "csv" {
		return "", ErrInvalidDocKey
	}
	if err := os.MkdirAll(d.dir(), 0o750); err != nil {
		return "", err
	}
	key := newUUID() + "." + ext
	if err := os.WriteFile(filepath.Join(d.dir(), key), data, 0o640); err != nil {
		return "", fmt.Errorf("write document: %w", err)
	}
	return key, nil
}

// Read returns a stored document.
func (d Docs) Read(key string) ([]byte, error) {
	if !docKeyRe.MatchString(key) {
		return nil, ErrInvalidDocKey
	}
	return os.ReadFile(filepath.Join(d.dir(), key))
}

// Delete removes a stored document (best effort).
func (d Docs) Delete(key string) {
	if docKeyRe.MatchString(key) {
		_ = os.Remove(filepath.Join(d.dir(), key))
	}
}
