package ratelimit

import (
	"testing"
	"time"
)

func TestLimiter(t *testing.T) {
	now := time.Unix(0, 0)
	l := New(2, time.Minute)
	l.now = func() time.Time { return now }
	if !l.Allow("a") || !l.Allow("a") || l.Allow("a") {
		t.Fatal("expected 2 allowed then blocked")
	}
	if !l.Allow("b") {
		t.Fatal("keys are independent")
	}
	now = now.Add(time.Minute)
	if !l.Allow("a") {
		t.Fatal("window should reset")
	}
}
