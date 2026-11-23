package storage

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"github.com/kiuvy-universe/kiupop/backend/internal/platform/gcp"
)

// fakeGCS emulates the three JSON API calls the adapter uses.
type fakeGCS struct {
	mu      sync.Mutex
	objects map[string][]byte
	types   map[string]string
	auth    []string
	queries []string
}

func (f *fakeGCS) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.auth = append(f.auth, r.Header.Get("Authorization"))
	f.queries = append(f.queries, r.URL.RawQuery)
	switch {
	case r.Method == http.MethodPost && r.URL.Path == "/upload/storage/v1/b/kiupop-demo-files/o":
		name := r.URL.Query().Get("name")
		if r.URL.Query().Get("ifGenerationMatch") != "0" {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		if _, ok := f.objects[name]; ok {
			w.WriteHeader(http.StatusPreconditionFailed)
			return
		}
		data, _ := io.ReadAll(r.Body)
		f.objects[name], f.types[name] = data, r.Header.Get("Content-Type")
		_, _ = io.WriteString(w, `{}`)
	case strings.HasPrefix(r.URL.Path, "/storage/v1/b/kiupop-demo-files/o/"):
		name := strings.TrimPrefix(r.URL.Path, "/storage/v1/b/kiupop-demo-files/o/")
		data, ok := f.objects[name]
		switch {
		case !ok:
			w.WriteHeader(http.StatusNotFound)
		case r.Method == http.MethodDelete:
			delete(f.objects, name)
			w.WriteHeader(http.StatusNoContent)
		default:
			_, _ = w.Write(data)
		}
	default:
		w.WriteHeader(http.StatusTeapot)
	}
}

func newFake(t *testing.T) (*fakeGCS, GCS) {
	f := &fakeGCS{objects: map[string][]byte{}, types: map[string]string{}}
	srv := httptest.NewServer(f)
	t.Cleanup(srv.Close)
	return f, GCS{Bucket: "kiupop-demo-files", Tokens: gcp.Static("svc-token"), Endpoint: srv.URL}
}

func TestBucketImagesAndDocs(t *testing.T) {
	f, g := newFake(t)
	imgs := BucketImages{B: g}
	key, err := imgs.Save(pngBytes(t))
	if err != nil || !ValidKey(key) {
		t.Fatalf("save: %q %v", key, err)
	}
	if f.types[PrefixImages+key] != "image/png" {
		t.Fatalf("content type %q", f.types[PrefixImages+key])
	}
	r, err := imgs.Open(key)
	if err != nil {
		t.Fatal(err)
	}
	got, _ := io.ReadAll(r)
	_ = r.Close()
	if string(got) != string(pngBytes(t)) {
		t.Fatal("round trip")
	}
	if _, err := imgs.Save([]byte("not an image")); !errors.Is(err, ErrUnsupportedImage) {
		t.Fatalf("validation: %v", err)
	}
	if _, err := imgs.Open("../../etc/passwd"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("path traversal: %v", err)
	}
	imgs.Delete(key)
	if _, err := imgs.Open(key); !errors.Is(err, ErrNotFound) {
		t.Fatalf("deleted: %v", err)
	}
	imgs.Delete("bad key") // ignored

	docs := BucketDocs{B: g}
	dk, err := docs.Save([]byte("nombre,precio\nrosas,15000\n"), "csv")
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := f.objects[PrefixDocs+dk]; !ok {
		t.Fatalf("catalogs must live under %s (lifecycle 1 day)", PrefixDocs)
	}
	if data, err := docs.Read(dk, 1<<20); err != nil || !strings.Contains(string(data), "rosas") {
		t.Fatalf("read: %v", err)
	}
	if _, err := docs.Read(dk, 4); err == nil {
		t.Fatal("size limit not enforced")
	}
	if _, err := docs.Save([]byte("x"), "exe"); !errors.Is(err, ErrInvalidDocKey) {
		t.Fatalf("ext: %v", err)
	}
	if _, err := docs.Read("../x.pdf", 10); !errors.Is(err, ErrInvalidDocKey) {
		t.Fatalf("doc key: %v", err)
	}
	pk, _ := docs.Save([]byte("%PDF-1.7"), "pdf")
	if f.types[PrefixDocs+pk] != "application/pdf" {
		t.Fatal("pdf type")
	}
	docs.Delete(pk)
	docs.Delete("nope")
	if _, ok := f.objects[PrefixDocs+pk]; ok {
		t.Fatal("doc not deleted")
	}
	for _, a := range f.auth {
		if a != "Bearer svc-token" {
			t.Fatalf("auth header %q", a)
		}
	}
}

func TestGCSRejectsForeignNamesAndErrors(t *testing.T) {
	_, g := newFake(t)
	ctx := context.Background()
	for _, name := range []string{"x.jpg", "images/../secret", "public/abc.png", "images/" + strings.Repeat("a", 36) + ".jpg"} {
		if err := g.Put(ctx, name, []byte("x"), "image/png"); !errors.Is(err, ErrInvalidObject) {
			t.Errorf("put %q: %v", name, err)
		}
		if err := g.Delete(ctx, name); !errors.Is(err, ErrInvalidObject) {
			t.Errorf("delete %q: %v", name, err)
		}
		if _, err := g.Get(ctx, name, 10); !errors.Is(err, ErrNotFound) {
			t.Errorf("get %q: %v", name, err)
		}
	}
	name := PrefixImages + "6f1d2c3b-4a59-4e8f-9a0b-1c2d3e4f5a6b.png"
	if err := g.Put(ctx, name, []byte("a"), "image/png"); err != nil {
		t.Fatal(err)
	}
	if err := g.Put(ctx, name, []byte("b"), "image/png"); err == nil {
		t.Fatal("overwrite allowed")
	}
	bad := GCS{Bucket: "other", Tokens: g.Tokens, Endpoint: g.Endpoint}
	if _, err := bad.Get(ctx, name, 10); err == nil || errors.Is(err, ErrNotFound) {
		t.Fatalf("unexpected status should be an error: %v", err)
	}
	if err := bad.Delete(ctx, name); err == nil {
		t.Fatal("delete on wrong bucket should fail")
	}
	down := GCS{Bucket: "kiupop-demo-files", Tokens: g.Tokens, Endpoint: "http://127.0.0.1:1"}
	if err := down.Put(ctx, name, []byte("a"), "image/png"); err == nil {
		t.Fatal("unreachable")
	}
	if (GCS{}).endpoint() != "https://storage.googleapis.com" || (GCS{}).client() == nil {
		t.Fatal("defaults")
	}
}

func TestLocalDocsDelete(t *testing.T) {
	d := Docs{Dir: t.TempDir()}
	k, err := d.Save([]byte("a,b"), "csv")
	if err != nil {
		t.Fatal(err)
	}
	d.Delete(k)
	if _, err := d.Read(k); err == nil {
		t.Fatal("not deleted")
	}
}
