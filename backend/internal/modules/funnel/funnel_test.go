package funnel

import (
	"context"
	"strings"
	"testing"
)

func TestCleanMetaKeepsOnlySmallNumbers(t *testing.T) {
	in := map[string]int64{"duration_ms": 1200, "Bad-Key": 1, "negative": -5, "huge": 1 << 50, "ok_2": 0}
	for i := 0; i < 20; i++ {
		in["k"+strings.Repeat("x", i)] = int64(i)
	}
	out := CleanMeta(in)
	if out["duration_ms"] != 1200 || len(out) > maxMetaKeys {
		t.Fatalf("clean: %v", out)
	}
	for _, k := range []string{"Bad-Key", "negative", "huge"} {
		if _, ok := out[k]; ok {
			t.Fatalf("%s kept", k)
		}
	}
}

func TestActorIsStablePseudonym(t *testing.T) {
	a := Actor("salt-one", "user-123")
	if len(a) != 32 || a != Actor("salt-one", "user-123") || a == Actor("salt-two", "user-123") || strings.Contains(a, "user") {
		t.Fatalf("actor %q", a)
	}
	for e := range ClientEvents {
		if !Events[e] {
			t.Fatalf("client event %s not in Events", e)
		}
	}
	if len(Order) != len(Events)-1 { // every event but "error" has a funnel position
		t.Fatalf("order covers %d of %d events", len(Order), len(Events))
	}
}

func TestRecordIgnoresNoise(t *testing.T) {
	var r *Recorder
	r.Record(context.Background(), "u", "s", "store_ready", nil) // nil recorder: no panic
	r = &Recorder{}
	r.Record(context.Background(), "", "s", "store_ready", nil) // anonymous: ignored before touching the pool
	r.Record(context.Background(), "u", "s", "unknown", nil)    // unknown: ignored
}
