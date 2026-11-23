package agent

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	// ErrSessionNotFound means no session with that id belongs to the caller.
	ErrSessionNotFound = errors.New("session not found")
)

// Session is the persisted conversation state.
type Session struct {
	ID              string
	UserID          string
	StoreID         string
	Status          string
	Blueprint       Blueprint
	Revision        int
	PreviewRevision int
	ReadyRevision   int
	QuestionsAsked  int
	AICalls         int
	AICostMicros    int64
	CreatedAt       time.Time
	FirstMessageAt  *time.Time
	ReadyAt         *time.Time
	PublishedAt     *time.Time
}

// Message is one chat bubble.
type Message struct {
	ID        int64       `json:"id"`
	Role      string      `json:"role"`
	Text      string      `json:"text"`
	Meta      MessageMeta `json:"meta"`
	CreatedAt time.Time   `json:"created_at"`
}

// MessageMeta carries structured extras for the UI.
type MessageMeta struct {
	Question     *Question    `json:"question,omitempty"`
	QuickReplies []QuickReply `json:"quick_replies,omitempty"`
	Kind         string       `json:"kind,omitempty"` // greeting | ack | question | building | ready | published | notice | plan | kit
	BrainMode    string       `json:"brain_mode,omitempty"`
}

// Job is a unit of background work.
type Job struct {
	ID          string
	SessionID   string
	Kind        string
	Key         string
	Status      string
	Input       json.RawMessage
	Attempts    int
	MaxAttempts int
}

// Event is one progress event.
type Event struct {
	ID        int64           `json:"id"`
	Type      string          `json:"type"`
	Payload   json.RawMessage `json:"payload"`
	CreatedAt time.Time       `json:"created_at"`
}

type querier interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// Repo persists agent state.
type Repo struct{ pool *pgxpool.Pool }

// NewRepo returns a repo.
func NewRepo(pool *pgxpool.Pool) *Repo { return &Repo{pool: pool} }

const sessionCols = `id::text, user_id::text, coalesce(store_id::text, ''), status, blueprint, revision,
	preview_revision, ready_revision, questions_asked, ai_calls, ai_cost_micros, created_at,
	first_message_at, ready_at, published_at`

func scanSession(row pgx.Row) (Session, error) {
	var s Session
	var raw []byte
	err := row.Scan(&s.ID, &s.UserID, &s.StoreID, &s.Status, &raw, &s.Revision, &s.PreviewRevision,
		&s.ReadyRevision, &s.QuestionsAsked, &s.AICalls, &s.AICostMicros, &s.CreatedAt,
		&s.FirstMessageAt, &s.ReadyAt, &s.PublishedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Session{}, ErrSessionNotFound
	}
	if err != nil {
		return Session{}, err
	}
	s.Blueprint, err = decodeBlueprint(raw)
	return s, err
}

func decodeBlueprint(raw []byte) (Blueprint, error) {
	bp := NewBlueprint()
	if err := json.Unmarshal(raw, &bp); err != nil {
		return Blueprint{}, fmt.Errorf("decode blueprint: %w", err)
	}
	if bp.SchemaVersion != SchemaVersion {
		return Blueprint{}, fmt.Errorf("unsupported blueprint schema %d", bp.SchemaVersion)
	}
	return bp, nil
}

// LiveOrCreate returns the user's live session, creating one if needed.
func (r *Repo) LiveOrCreate(ctx context.Context, userID string) (Session, bool, error) {
	if s, err := r.Live(ctx, userID); err == nil {
		return s, false, nil
	} else if !errors.Is(err, ErrSessionNotFound) {
		return Session{}, false, err
	}
	raw, _ := json.Marshal(NewBlueprint())
	s, err := scanSession(r.pool.QueryRow(ctx, `
		INSERT INTO agent_sessions (user_id, blueprint) VALUES ($1, $2)
		ON CONFLICT (user_id) WHERE status IN ('collecting', 'building', 'ready') DO NOTHING
		RETURNING `+sessionCols, userID, raw))
	if errors.Is(err, ErrSessionNotFound) { // lost a race with another tab
		s, err = r.Live(ctx, userID)
		return s, false, err
	}
	return s, err == nil, err
}

// Live returns the user's live session.
func (r *Repo) Live(ctx context.Context, userID string) (Session, error) {
	return scanSession(r.pool.QueryRow(ctx, `SELECT `+sessionCols+` FROM agent_sessions
		WHERE user_id = $1 AND status IN ('collecting', 'building', 'ready')`, userID))
}

// Latest returns the session to show on reload: the newest one the user
// actually talked in (live or published), else an untouched live one.
func (r *Repo) Latest(ctx context.Context, userID string) (Session, error) {
	return scanSession(r.pool.QueryRow(ctx, `SELECT `+sessionCols+` FROM agent_sessions
		WHERE user_id = $1 AND status <> 'abandoned'
		ORDER BY (first_message_at IS NOT NULL) DESC, created_at DESC LIMIT 1`, userID))
}

// GetSystem returns any session (workers and internal bookkeeping only; never from a handler).
func (r *Repo) GetSystem(ctx context.Context, id string) (Session, error) {
	if !validUUID(id) {
		return Session{}, ErrSessionNotFound
	}
	return scanSession(r.pool.QueryRow(ctx, `SELECT `+sessionCols+` FROM agent_sessions WHERE id = $1`, id))
}

// Get returns a session owned by userID. An empty userID never matches.
func (r *Repo) Get(ctx context.Context, id, userID string) (Session, error) {
	if !validUUID(id) || userID == "" {
		return Session{}, ErrSessionNotFound
	}
	return scanSession(r.pool.QueryRow(ctx, `SELECT `+sessionCols+` FROM agent_sessions WHERE id = $1 AND user_id = $2`, id, userID))
}

// Tx is a locked session inside a transaction.
type Tx struct {
	tx      pgx.Tx
	S       Session
	changed bool
	events  int
}

// Touch marks the blueprint as changed (bumps revision on commit).
func (t *Tx) Touch() { t.changed = true }

// Update runs fn with the session row locked. Blueprint changes bump the revision.
func (r *Repo) Update(ctx context.Context, id string, fn func(t *Tx) error) (Session, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return Session{}, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	s, err := scanSession(tx.QueryRow(ctx, `SELECT `+sessionCols+` FROM agent_sessions WHERE id = $1 FOR UPDATE`, id))
	if err != nil {
		return Session{}, err
	}
	t := &Tx{tx: tx, S: s}
	if err := fn(t); err != nil {
		return Session{}, err
	}
	if t.changed {
		t.S.Revision++
	}
	raw, err := json.Marshal(t.S.Blueprint)
	if err != nil {
		return Session{}, err
	}
	if _, err := tx.Exec(ctx, `UPDATE agent_sessions SET blueprint = $2, revision = $3, status = $4,
		store_id = NULLIF($5, '')::uuid, preview_revision = $6, ready_revision = $7, questions_asked = $8,
		first_message_at = $9, ready_at = $10, published_at = $11, updated_at = now() WHERE id = $1`,
		id, raw, t.S.Revision, t.S.Status, t.S.StoreID, t.S.PreviewRevision, t.S.ReadyRevision,
		t.S.QuestionsAsked, t.S.FirstMessageAt, t.S.ReadyAt, t.S.PublishedAt); err != nil {
		return Session{}, fmt.Errorf("save session: %w", err)
	}
	return t.S, tx.Commit(ctx)
}

// AddMessage appends a chat message inside the session transaction.
func (t *Tx) AddMessage(ctx context.Context, role, text string, meta MessageMeta, clientID string) (Message, error) {
	return insertMessage(ctx, t.tx, t.S.ID, role, text, meta, clientID)
}

func insertMessage(ctx context.Context, q querier, sessionID, role, text string, meta MessageMeta, clientID string) (Message, error) {
	raw, _ := json.Marshal(meta)
	m := Message{Role: role, Text: truncate(text, 2000), Meta: meta}
	var cid any
	if clientID != "" {
		cid = clientID
	}
	err := q.QueryRow(ctx, `INSERT INTO agent_messages (session_id, role, body, meta, client_message_id)
		VALUES ($1, $2, $3, $4, $5) RETURNING id, created_at`, sessionID, role, m.Text, raw, cid).Scan(&m.ID, &m.CreatedAt)
	return m, err
}

// HasClientMessage reports whether a client message id was already accepted (idempotent retries).
func (r *Repo) HasClientMessage(ctx context.Context, sessionID, clientID string) (bool, error) {
	var ok bool
	err := r.pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM agent_messages WHERE session_id = $1 AND client_message_id = $2)`,
		sessionID, clientID).Scan(&ok)
	return ok, err
}

// Messages lists a session's messages (oldest first).
func (r *Repo) Messages(ctx context.Context, sessionID string) ([]Message, error) {
	rows, err := r.pool.Query(ctx, `SELECT id, role, body, meta, created_at FROM agent_messages
		WHERE session_id = $1 ORDER BY id LIMIT 300`, sessionID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Message{}
	for rows.Next() {
		var m Message
		var raw []byte
		if err := rows.Scan(&m.ID, &m.Role, &m.Text, &raw, &m.CreatedAt); err != nil {
			return nil, err
		}
		_ = json.Unmarshal(raw, &m.Meta)
		out = append(out, m)
	}
	return out, rows.Err()
}

// Enqueue adds a job once per idempotency key and returns its id.
func (t *Tx) Enqueue(ctx context.Context, kind, key string, input any, dependsOn []string, maxAttempts int) (string, error) {
	return enqueue(ctx, t.tx, t.S.ID, kind, key, input, dependsOn, maxAttempts)
}

func enqueue(ctx context.Context, q querier, sessionID, kind, key string, input any, dependsOn []string, maxAttempts int) (string, error) {
	raw, _ := json.Marshal(input)
	if dependsOn == nil {
		dependsOn = []string{}
	}
	var id string
	err := q.QueryRow(ctx, `INSERT INTO agent_jobs (session_id, kind, idempotency_key, input, depends_on, max_attempts)
		VALUES ($1, $2, $3, $4, $5::uuid[], $6) ON CONFLICT (idempotency_key) DO NOTHING RETURNING id::text`,
		sessionID, kind, key, raw, dependsOn, maxAttempts).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		err = q.QueryRow(ctx, `SELECT id::text FROM agent_jobs WHERE idempotency_key = $1`, key).Scan(&id)
	}
	return id, err
}

// ActiveJobIDs returns ids of non-terminal jobs of the given kinds (for dependencies).
func (t *Tx) ActiveJobIDs(ctx context.Context, kinds ...string) ([]string, error) {
	rows, err := t.tx.Query(ctx, `SELECT id::text FROM agent_jobs WHERE session_id = $1 AND kind = ANY($2)
		AND status IN ('queued', 'running')`, t.S.ID, kinds)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowTo[string])
}

// Emit records an event inside the transaction. A non-empty dedupe key makes it once-only.
func (t *Tx) Emit(ctx context.Context, typ string, payload any, dedupe string) (bool, error) {
	t.events++
	return emit(ctx, t.tx, t.S.ID, typ, payload, dedupe)
}

func emit(ctx context.Context, q querier, sessionID, typ string, payload any, dedupe string) (bool, error) {
	raw, _ := json.Marshal(payload)
	var d any
	if dedupe != "" {
		d = dedupe
	}
	tag, err := q.Exec(ctx, `INSERT INTO agent_events (session_id, type, payload, dedupe_key) VALUES ($1, $2, $3, $4)
		ON CONFLICT (session_id, dedupe_key) DO NOTHING`, sessionID, typ, raw, d)
	return tag.RowsAffected() == 1, err
}

// Emit records an event outside a session transaction. It takes the session
// row lock first, so ids are committed in order and a client reading "after N"
// can never skip an event that was still being written.
func (r *Repo) Emit(ctx context.Context, sessionID, typ string, payload any, dedupe string) (bool, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return false, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	if _, err := tx.Exec(ctx, `SELECT 1 FROM agent_sessions WHERE id = $1 FOR UPDATE`, sessionID); err != nil {
		return false, err
	}
	ok, err := emit(ctx, tx, sessionID, typ, payload, dedupe)
	if err != nil {
		return false, err
	}
	return ok, tx.Commit(ctx)
}

// EventsAfter returns events with id > after (oldest first).
func (r *Repo) EventsAfter(ctx context.Context, sessionID string, after int64, limit int) ([]Event, error) {
	rows, err := r.pool.Query(ctx, `SELECT id, type, payload, created_at FROM agent_events
		WHERE session_id = $1 AND id > $2 ORDER BY id LIMIT $3`, sessionID, after, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Event{}
	for rows.Next() {
		var e Event
		if err := rows.Scan(&e.ID, &e.Type, &e.Payload, &e.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

// LastEventID returns the newest event id of a session (0 if none).
func (r *Repo) LastEventID(ctx context.Context, sessionID string) (int64, error) {
	var id int64
	err := r.pool.QueryRow(ctx, `SELECT coalesce(max(id), 0) FROM agent_events WHERE session_id = $1`, sessionID).Scan(&id)
	return id, err
}

// Claim leases the oldest runnable job whose dependencies are all terminal.
func (r *Repo) Claim(ctx context.Context, lease time.Duration) (*Job, error) {
	var j Job
	err := r.pool.QueryRow(ctx, `
		UPDATE agent_jobs SET status = 'running', attempts = attempts + 1, started_at = now(),
			lease_until = now() + $1::interval
		WHERE id = (
			SELECT j.id FROM agent_jobs j
			WHERE j.status = 'queued' AND j.run_after <= now()
			  AND NOT EXISTS (SELECT 1 FROM agent_jobs d WHERE d.id = ANY(j.depends_on) AND d.status IN ('queued', 'running'))
			ORDER BY j.created_at FOR UPDATE SKIP LOCKED LIMIT 1)
		RETURNING id::text, session_id::text, kind, idempotency_key, status, input, attempts, max_attempts`,
		fmt.Sprintf("%d milliseconds", lease.Milliseconds())).
		Scan(&j.ID, &j.SessionID, &j.Kind, &j.Key, &j.Status, &j.Input, &j.Attempts, &j.MaxAttempts)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	return &j, err
}

// Finish marks a job succeeded with an optional result.
func (r *Repo) Finish(ctx context.Context, id string, result any) error {
	raw, _ := json.Marshal(result)
	_, err := r.pool.Exec(ctx, `UPDATE agent_jobs SET status = 'succeeded', result = $2, finished_at = now(), lease_until = NULL
		WHERE id = $1 AND status = 'running'`, id, raw)
	return err
}

// Fail retries with backoff until max_attempts, then marks the job failed.
func (r *Repo) Fail(ctx context.Context, id string, reason string) (final bool, err error) {
	err = r.pool.QueryRow(ctx, `UPDATE agent_jobs SET
		status = CASE WHEN attempts >= max_attempts THEN 'failed' ELSE 'queued' END,
		run_after = now() + (attempts * interval '1 second'),
		last_error = left($2, 300), lease_until = NULL,
		finished_at = CASE WHEN attempts >= max_attempts THEN now() END
		WHERE id = $1 AND status = 'running' RETURNING status = 'failed'`, id, reason).Scan(&final)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil // lease already recovered by the sweeper
	}
	return final, err
}

// RecoverExpired requeues jobs whose worker died (lease expired). Returns count.
func (r *Repo) RecoverExpired(ctx context.Context) (int64, error) {
	tag, err := r.pool.Exec(ctx, `UPDATE agent_jobs SET
		status = CASE WHEN attempts >= max_attempts THEN 'failed' ELSE 'queued' END,
		last_error = 'lease expired', lease_until = NULL,
		finished_at = CASE WHEN attempts >= max_attempts THEN now() END
		WHERE status = 'running' AND lease_until < now()`)
	return tag.RowsAffected(), err
}

// CancelSessionJobs cancels queued work (e.g. after publication).
func (r *Repo) CancelSessionJobs(ctx context.Context, sessionID string) error {
	_, err := r.pool.Exec(ctx, `UPDATE agent_jobs SET status = 'cancelled', finished_at = now()
		WHERE session_id = $1 AND status = 'queued'`, sessionID)
	return err
}

// JobState is a compact job status for progress.
type JobState struct {
	Kind   string
	Status string
}

// JobStates lists a session's jobs.
func (r *Repo) JobStates(ctx context.Context, sessionID string) ([]JobState, error) {
	rows, err := r.pool.Query(ctx, `SELECT kind, status FROM agent_jobs WHERE session_id = $1`, sessionID)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(row pgx.CollectableRow) (JobState, error) {
		var j JobState
		return j, row.Scan(&j.Kind, &j.Status)
	})
}

// RecordAction audits one tool execution.
func (r *Repo) RecordAction(ctx context.Context, sessionID, actor string, res ToolResult, d time.Duration) {
	raw, _ := json.Marshal(res.Summary)
	_, _ = r.pool.Exec(ctx, `INSERT INTO agent_actions (session_id, tool, actor, summary, outcome, duration_ms)
		VALUES ($1, $2, $3, $4, $5, $6)`, sessionID, res.Tool, actor, raw, res.Outcome, d.Milliseconds())
}

// RecordUsage stores one model call and adds it to the session budget.
func (r *Repo) RecordUsage(ctx context.Context, sessionID string, u Usage) {
	var sid any
	if sessionID != "" {
		sid = sessionID
	}
	_, _ = r.pool.Exec(ctx, `INSERT INTO ai_usage (session_id, purpose, model, input_tokens, output_tokens,
		cache_read_tokens, cache_write_tokens, latency_ms, cost_micros, outcome)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`, sid, u.Purpose, u.Model, u.InputTokens, u.OutputTokens,
		u.CacheReadTokens, u.CacheWriteTokens, u.LatencyMs, u.CostMicros, u.Outcome)
	if sessionID != "" {
		_, _ = r.pool.Exec(ctx, `UPDATE agent_sessions SET ai_calls = ai_calls + 1, ai_cost_micros = ai_cost_micros + $2
			WHERE id = $1`, sessionID, u.CostMicros)
	}
}

// UsageTotals summarises a session's model usage.
type UsageTotals struct {
	Calls        int   `json:"calls"`
	InputTokens  int64 `json:"input_tokens"`
	OutputTokens int64 `json:"output_tokens"`
	CacheRead    int64 `json:"cache_read_tokens"`
	CostMicros   int64 `json:"cost_micros"`
}

// Usage returns totals for a session.
func (r *Repo) Usage(ctx context.Context, sessionID string) (UsageTotals, error) {
	var u UsageTotals
	err := r.pool.QueryRow(ctx, `SELECT count(*), coalesce(sum(input_tokens), 0), coalesce(sum(output_tokens), 0),
		coalesce(sum(cache_read_tokens), 0), coalesce(sum(cost_micros), 0) FROM ai_usage WHERE session_id = $1`, sessionID).
		Scan(&u.Calls, &u.InputTokens, &u.OutputTokens, &u.CacheRead, &u.CostMicros)
	return u, err
}

func validUUID(s string) bool {
	if len(s) != 36 {
		return false
	}
	for i, c := range s {
		switch i {
		case 8, 13, 18, 23:
			if c != '-' {
				return false
			}
		default:
			if !(c >= '0' && c <= '9' || c >= 'a' && c <= 'f' || c >= 'A' && c <= 'F') {
				return false
			}
		}
	}
	return true
}

// SpendToday returns today's AI cost (micro-USD, UTC day) for one user and for everyone.
func (r *Repo) SpendToday(ctx context.Context, userID string) (user, global int64, err error) {
	err = r.pool.QueryRow(ctx, `SELECT
		coalesce(sum(u.cost_micros) FILTER (WHERE s.user_id = $1), 0), coalesce(sum(u.cost_micros), 0)
		FROM ai_usage u LEFT JOIN agent_sessions s ON s.id = u.session_id
		WHERE u.created_at >= date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'`, userID).Scan(&user, &global)
	return user, global, err
}
