package agent

import "sync"

// Bus wakes in-process listeners (SSE streams, long polls, workers) when a
// session has new events. The source of truth is always agent_events in
// PostgreSQL; a missed wake-up only delays delivery until the next poll.
type Bus struct {
	mu   sync.Mutex
	subs map[string]map[chan struct{}]struct{}
	work chan struct{}
}

// NewBus returns a bus.
func NewBus() *Bus {
	return &Bus{subs: map[string]map[chan struct{}]struct{}{}, work: make(chan struct{}, 1)}
}

// Subscribe returns a channel signalled on new session events, and a cancel func.
func (b *Bus) Subscribe(sessionID string) (<-chan struct{}, func()) {
	ch := make(chan struct{}, 1)
	b.mu.Lock()
	if b.subs[sessionID] == nil {
		b.subs[sessionID] = map[chan struct{}]struct{}{}
	}
	b.subs[sessionID][ch] = struct{}{}
	b.mu.Unlock()
	return ch, func() {
		b.mu.Lock()
		delete(b.subs[sessionID], ch)
		if len(b.subs[sessionID]) == 0 {
			delete(b.subs, sessionID)
		}
		b.mu.Unlock()
	}
}

// Notify signals a session's listeners (non-blocking).
func (b *Bus) Notify(sessionID string) {
	b.mu.Lock()
	defer b.mu.Unlock()
	for ch := range b.subs[sessionID] {
		select {
		case ch <- struct{}{}:
		default:
		}
	}
}

// WakeWorkers signals that jobs were enqueued.
func (b *Bus) WakeWorkers() {
	select {
	case b.work <- struct{}{}:
	default:
	}
}
