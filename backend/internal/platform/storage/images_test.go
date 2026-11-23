package storage

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"testing"
)

func pngBytes(t *testing.T) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 2, 2))
	img.Set(0, 0, color.White)
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func TestSaveAndOpen(t *testing.T) {
	s := Images{Dir: t.TempDir()}
	key, err := s.Save(pngBytes(t))
	if err != nil {
		t.Fatal(err)
	}
	if !ValidKey(key) || ContentTypeFor(key) != "image/png" {
		t.Fatalf("bad key %q", key)
	}
	f, err := s.Open(key)
	if err != nil {
		t.Fatal(err)
	}
	f.Close()
}

func TestRejectsNonImagesAndPaths(t *testing.T) {
	for name, data := range map[string][]byte{
		"svg":       []byte(`<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>`),
		"html":      []byte("<html><body>x</body></html>"),
		"fake png":  append([]byte("\x89PNG\r\n\x1a\n"), []byte("garbage")...),
		"fake webp": []byte("RIFF\x00\x00\x00\x00WEBPXXXX"),
		"empty":     {},
		"too large": make([]byte, MaxImageBytes+1),
	} {
		if _, err := Sniff(data); err == nil {
			t.Errorf("%s: expected rejection", name)
		}
	}
	s := Images{Dir: t.TempDir()}
	for _, key := range []string{"../etc/passwd", "a.png", "/tmp/x.jpg", "00000000-0000-4000-8000-000000000000.svg"} {
		if _, err := s.Open(key); err == nil {
			t.Errorf("Open(%q) should fail", key)
		}
	}
}

func TestAcceptsWebPHeader(t *testing.T) {
	data := append([]byte("RIFF\x10\x00\x00\x00WEBPVP8 "), make([]byte, 16)...)
	if ext, err := Sniff(data); err != nil || ext != "webp" {
		t.Fatalf("ext=%q err=%v", ext, err)
	}
}
