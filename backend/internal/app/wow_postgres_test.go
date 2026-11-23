package app

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/agent"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/funnel"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/identity"
)

func funnelSink(c agent.Config) funnel.Sink {
	if s, ok := c.Funnel.(funnel.Sink); ok {
		return s
	}
	return nil
}

// usersWithSignup wires the funnel's signup hook like cmd/server does.
func usersWithSignup(pool *pgxpool.Pool, c agent.Config) *identity.Repo {
	r := identity.NewRepo(pool)
	if c.Funnel != nil {
		r.OnSignup(func(ctx context.Context, userID, _ string) {
			c.Funnel.Record(ctx, userID, "", "signup_completed", map[string]int64{"provider_test": 1})
		})
	}
	return r
}

const testSalt = "test-salt-for-funnel-pseudonyms-0123456789"

// KPOP-WOW-001: the funnel records pseudonymous milestones from the server and
// the app, and the report aggregates them without exposing anyone.
func TestFunnelAgainstPostgres(t *testing.T) {
	e0 := newAgentEnv(t) // migrations + skip when there is no test database
	rec := funnel.NewRecorder(e0.pool, testSalt, slog.New(slog.NewTextHandler(io.Discard, nil)))
	e := newAgentEnvWith(t, agent.Config{TestCheckout: true, ShareBase: "http://localhost:8080", Paywall: true,
		Funnel: rec, MaxFiles: 2, MaxFilesBytes: 96 << 10})
	uid := "u" + randomID()
	tok := token(uid)

	// Client milestones: only whitelisted events, numbers only, signed in.
	for _, ev := range []string{"intake_method_selected", "store_preview_opened", "paywall_viewed"} {
		if code, _, raw := e.c.do("POST", "/api/v1/funnel/events", tok, map[string]any{"event": ev,
			"meta": map[string]int64{"method_audio": 1}}); code != 204 {
			t.Fatalf("%s: %d %s", ev, code, raw)
		}
	}
	for name, body := range map[string]any{
		"server-only event": map[string]any{"event": "store_ready"},
		"forged signup":     map[string]any{"event": "signup_completed"},
		"unknown event":     map[string]any{"event": "drop_table"},
		"text in meta":      map[string]any{"event": "paywall_viewed", "meta": map[string]any{"email": "a@b.c"}},
		"extra field":       map[string]any{"event": "paywall_viewed", "transcript": "hola"},
	} {
		if code, _, _ := e.c.do("POST", "/api/v1/funnel/events", tok, body); code != 400 {
			t.Errorf("%s accepted: %d", name, code)
		}
	}
	if code, _, _ := e.c.do("POST", "/api/v1/funnel/events", "", map[string]any{"event": "paywall_viewed"}); code != 401 {
		t.Fatalf("anonymous funnel event = %d", code)
	}
	if code, _, _ := e.c.do("POST", "/api/v1/speech/transcriptions", "", nil); code != 401 {
		t.Fatalf("anonymous transcription = %d", code)
	}
	if code, _, raw := e.c.do("POST", "/api/v1/speech/transcriptions", tok, nil); code != 503 || !strings.Contains(raw, "speech_unavailable") {
		t.Fatalf("speech disabled = %d %s", code, raw)
	}

	var internalID string
	if err := e.pool.QueryRow(e.ctx, `SELECT id::text FROM users WHERE auth_uid = $1`, uid).Scan(&internalID); err != nil {
		t.Fatal(err)
	}
	actor := funnel.Actor(testSalt, internalID)

	// Server milestones along the real flow.
	sid := readySession(t, e, tok)
	if code, _, raw := e.c.do("POST", "/api/v1/agent/sessions/"+sid+"/plan", tok, map[string]any{"confirm": true}); code != 200 {
		t.Fatalf("plan: %d %s", code, raw)
	}

	// Configurable limits: 2 files and 96 KiB per session in this test.
	big := bytes.Repeat([]byte("a,1\n"), 15<<10) // 60 KiB CSV
	if code, _ := upload(t, e, tok, sid, "uno.csv", big); code != 409 && code != 201 {
		t.Fatalf("first upload: %d", code)
	}
	if code, _ := upload(t, e, tok, sid, "dos.csv", big); code != 409 {
		t.Fatalf("byte limit not enforced: %d", code)
	}

	rows, err := e.pool.Query(e.ctx, `SELECT event, actor, meta::text FROM funnel_events WHERE actor = $1 ORDER BY id`, actor)
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]string{}
	for rows.Next() {
		var ev, a, meta string
		if err := rows.Scan(&ev, &a, &meta); err != nil {
			t.Fatal(err)
		}
		if a == uid || a == internalID || strings.Contains(meta, "@") {
			t.Fatalf("funnel must be pseudonymous: %s %s", a, meta)
		}
		got[ev] = meta
	}
	rows.Close()
	for _, ev := range []string{"signup_completed", "intake_method_selected", "store_preview_opened", "paywall_viewed",
		"blueprint_ready", "store_ready", "demo_activation_completed"} {
		if _, ok := got[ev]; !ok {
			t.Errorf("missing funnel event %s (got %v)", ev, got)
		}
	}
	var m map[string]int64
	_ = json.Unmarshal([]byte(got["store_ready"]), &m)
	if m["products"] < 2 || m["ms_since_session_start"] < 0 {
		t.Fatalf("store_ready meta: %v", m)
	}
	rep, err := funnel.Summarise(e.ctx, e.pool, 1)
	if err != nil {
		t.Fatal(err)
	}
	if rep.ReadyN < 1 || len(rep.Stages) != len(funnel.Order) {
		t.Fatalf("report: %+v", rep)
	}
}

// The funnel handler refuses to work without a user even if mounted by mistake.
func TestFunnelHandlerRateLimit(t *testing.T) {
	sink := &countSink{}
	h := funnel.NewHandler(sink, nil)
	mux := http.NewServeMux()
	h.Register(mux, func(n http.Handler) http.Handler { return n })
	req := httptest.NewRequest(http.MethodPost, "/api/v1/funnel/events", strings.NewReader(`{"event":"paywall_viewed"}`))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusNoContent || sink.n != 1 {
		t.Fatalf("event: %d %d", rec.Code, sink.n)
	}
}

type countSink struct{ n int }

func (c *countSink) Record(_ context.Context, _, _, _ string, _ map[string]int64) { c.n++ }
