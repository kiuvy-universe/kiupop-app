// Package storage keeps uploaded product images on a local directory (a Docker
// volume in Compose), separate from the database. Names are server-generated.
package storage

import (
	"bytes"
	"crypto/rand"
	"errors"
	"fmt"
	"image"
	_ "image/jpeg" // register decoders for DecodeConfig
	_ "image/png"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
)

// MaxImageBytes bounds uploads (5 MiB).
const MaxImageBytes = 5 << 20

// ErrUnsupportedImage is returned for anything that is not a real JPEG, PNG or WebP.
var ErrUnsupportedImage = errors.New("unsupported image")

// ErrNotFound is returned when the key does not exist.
var ErrNotFound = errors.New("image not found")

var keyRe = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|png|webp)$`)

// ValidKey reports whether key has the server-generated shape (no paths).
func ValidKey(key string) bool { return keyRe.MatchString(key) }

// ContentTypeFor returns the MIME type for a valid key.
func ContentTypeFor(key string) string {
	switch filepath.Ext(key) {
	case ".jpg":
		return "image/jpeg"
	case ".png":
		return "image/png"
	default:
		return "image/webp"
	}
}

// Sniff validates the bytes and returns the extension to use.
func Sniff(data []byte) (string, error) {
	if len(data) == 0 || len(data) > MaxImageBytes {
		return "", ErrUnsupportedImage
	}
	switch http.DetectContentType(data) {
	case "image/jpeg":
		if _, _, err := image.DecodeConfig(bytes.NewReader(data)); err != nil {
			return "", ErrUnsupportedImage
		}
		return "jpg", nil
	case "image/png":
		if _, _, err := image.DecodeConfig(bytes.NewReader(data)); err != nil {
			return "", ErrUnsupportedImage
		}
		return "png", nil
	case "image/webp":
		// RIFF....WEBP + a VP8/VP8L/VP8X chunk; stdlib has no WebP decoder.
		if len(data) < 16 || string(data[12:15]) != "VP8" {
			return "", ErrUnsupportedImage
		}
		return "webp", nil
	}
	return "", ErrUnsupportedImage
}

// Images stores files under Dir.
type Images struct{ Dir string }

// Save validates data and writes it under a new random key.
func (s Images) Save(data []byte) (string, error) {
	ext, err := Sniff(data)
	if err != nil {
		return "", err
	}
	key := newUUID() + "." + ext
	if err := os.MkdirAll(s.Dir, 0o750); err != nil {
		return "", err
	}
	tmp, err := os.CreateTemp(s.Dir, ".upload-*")
	if err != nil {
		return "", err
	}
	defer os.Remove(tmp.Name()) //nolint:errcheck // no-op after rename
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return "", err
	}
	if err := tmp.Close(); err != nil {
		return "", err
	}
	if err := os.Rename(tmp.Name(), filepath.Join(s.Dir, key)); err != nil {
		return "", err
	}
	return key, nil
}

// Open returns the file for a valid key.
func (s Images) Open(key string) (*os.File, error) {
	if !ValidKey(key) {
		return nil, ErrNotFound
	}
	f, err := os.Open(filepath.Join(s.Dir, key))
	if errors.Is(err, os.ErrNotExist) {
		return nil, ErrNotFound
	}
	return f, err
}

// Delete removes a stored image (best effort).
func (s Images) Delete(key string) {
	if ValidKey(key) {
		_ = os.Remove(filepath.Join(s.Dir, key))
	}
}

func newUUID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}
