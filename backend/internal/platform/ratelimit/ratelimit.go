// Package ratelimit is a small in-memory fixed-window limiter. Good enough for a
// single-instance POC; a multi-instance deployment needs a shared store.
package ratelimit

import (
	"sync"
	"time"
)

// Limiter allows at most Max events per key within each Window.
type Limiter struct {
	Max    int
	Window time.Duration
	now    func() time.Time

	mu      sync.Mutex
	windows map[string]window
}

type window struct {
	start time.Time
	count int
}

// New returns a limiter.
func New(max int, per time.Duration) *Limiter {
	return &Limiter{Max: max, Window: per, now: time.Now, windows: map[string]window{}}
}

// Allow records an event for key and reports whether it is within the limit.
func (l *Limiter) Allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	w := l.windows[key]
	if now.Sub(w.start) >= l.Window {
		w = window{start: now}
	}
	if w.count >= l.Max {
		l.windows[key] = w
		return false
	}
	w.count++
	l.windows[key] = w
	if len(l.windows) > 10_000 { // bound memory
		for k, v := range l.windows {
			if now.Sub(v.start) >= l.Window {
				delete(l.windows, k)
			}
		}
	}
	return true
}
