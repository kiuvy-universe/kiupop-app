package app

import (
	"strings"
	"testing"

	"github.com/kiuvy-universe/kiupop/backend/internal/modules/agent"
)

// readySession drives Kiu to a ready (POPped) store and returns the session id.
func readySession(t *testing.T, e agentEnv, tok string) string {
	t.Helper()
	code, s, raw := e.c.do("POST", "/api/v1/agent/sessions", tok, nil)
	if code != 200 {
		t.Fatalf("start: %d %s", code, raw)
	}
	sid := s["id"].(string)
	for i, text := range []string{
		"Soy Florería Paywall " + randomID()[:4] + ", vendo flores y arreglos. Entrego en Naranjo.",
		"Ramo de rosas 15000 y arreglo de girasoles 18 mil",
		"Mi WhatsApp es 8888-1234",
	} {
		if code, _, raw := e.c.do("POST", "/api/v1/agent/sessions/"+sid+"/messages", tok,
			map[string]any{"text": text, "client_message_id": "paywall-msg-000" + string(rune('1'+i))}); code != 200 {
			t.Fatalf("message %d: %d %s", i, code, raw)
		}
		e.drain(t)
	}
	if code, v, raw := e.c.do("GET", "/api/v1/agent/sessions/"+sid, tok, nil); code != 200 || v["status"] != "ready" {
		t.Fatalf("not ready: %d %s", code, raw)
	}
	return sid
}

func TestAgentPaywallAgainstPostgres(t *testing.T) {
	e := newAgentEnvWith(t, agent.Config{TestCheckout: true, ShareBase: "http://localhost:8080", Paywall: true})
	c := e.c
	tok := token("u" + randomID())
	sid := readySession(t, e, tok)

	// The POP message leads into the paywall, and the view tells the client.
	code, v, raw := c.do("GET", "/api/v1/agent/sessions/"+sid, tok, nil)
	if code != 200 || !strings.Contains(raw, "US$5 al mes") {
		t.Fatalf("POP should mention the US$5 plan: %s", raw)
	}
	pw := v["paywall"].(map[string]any)
	if pw["required"] != true || pw["active"] != false || pw["price_minor"].(float64) != 500 || pw["currency"] != "USD" || pw["mode"] != "test" {
		t.Fatalf("paywall view: %v", pw)
	}
	assertSameKeys(t, "agent_session.paywall", exampleMap(t, "agent_session.json")["paywall"].(map[string]any), pw)

	// Publishing without a plan is refused by the server (the client cannot skip it).
	code, _, raw = c.do("POST", "/api/v1/agent/sessions/"+sid+"/publish", tok, map[string]any{"confirm": true})
	if code != 402 || !strings.Contains(raw, "plan_required") {
		t.Fatalf("publish without plan = %d %s", code, raw)
	}
	var published int
	_ = e.pool.QueryRow(e.ctx, `SELECT count(*) FROM stores s JOIN agent_sessions a ON a.store_id = s.id WHERE a.id = $1 AND s.status = 'published'`, sid).Scan(&published)
	if published != 0 {
		t.Fatal("store must stay unpublished without a plan")
	}

	// Activation needs confirmation and ownership.
	if code, _, _ := c.do("POST", "/api/v1/agent/sessions/"+sid+"/plan", tok, map[string]any{"confirm": false}); code != 400 {
		t.Fatalf("plan without confirm = %d", code)
	}
	if code, _, _ := c.do("POST", "/api/v1/agent/sessions/"+sid+"/plan", token("u"+randomID()), map[string]any{"confirm": true}); code != 404 {
		t.Fatalf("cross-user plan = %d", code)
	}

	// Test payment activates the plan; repeating it is a no-op (same period).
	code, p1, raw := c.do("POST", "/api/v1/agent/sessions/"+sid+"/plan", tok, map[string]any{"confirm": true})
	if code != 200 || p1["active"] != true {
		t.Fatalf("activate plan: %d %s", code, raw)
	}
	assertSameKeys(t, "plan", exampleMap(t, "agent_plan_response.json"), p1)
	plan := p1["plan"].(map[string]any)
	if plan["price_minor"].(float64) != 500 || plan["currency"] != "USD" || plan["test"] != true || plan["status"] != "active" {
		t.Fatalf("plan terms: %v", plan)
	}
	_, p2, _ := c.do("POST", "/api/v1/agent/sessions/"+sid+"/plan", tok, map[string]any{"confirm": true})
	if p2["plan"].(map[string]any)["current_period_end"] != plan["current_period_end"] {
		t.Fatal("activating an active plan must be idempotent")
	}
	var rows int
	_ = e.pool.QueryRow(e.ctx, `SELECT count(*) FROM store_plans p JOIN agent_sessions a ON a.store_id = p.store_id WHERE a.id = $1`, sid).Scan(&rows)
	if rows != 1 {
		t.Fatalf("store_plans rows = %d", rows)
	}

	// Now publishing works.
	if code, _, raw := c.do("POST", "/api/v1/agent/sessions/"+sid+"/publish", tok, map[string]any{"confirm": true}); code != 200 {
		t.Fatalf("publish with plan: %d %s", code, raw)
	}
}

func TestAgentPaywallOffAndNoTestPaymentsAgainstPostgres(t *testing.T) {
	// Paywall off: publishing stays free and the view says so.
	e := newAgentEnvWith(t, agent.Config{TestCheckout: false, ShareBase: "http://localhost:8080"})
	tok := token("u" + randomID())
	sid := readySession(t, e, tok)
	_, v, _ := e.c.do("GET", "/api/v1/agent/sessions/"+sid, tok, nil)
	if v["paywall"].(map[string]any)["required"] != false {
		t.Fatalf("paywall must be off: %v", v["paywall"])
	}
	// No test payments in this environment: activation is unavailable, never faked.
	if code, _, raw := e.c.do("POST", "/api/v1/agent/sessions/"+sid+"/plan", tok, map[string]any{"confirm": true}); code != 503 || !strings.Contains(raw, "payments_unavailable") {
		t.Fatalf("plan without test payments = %d %s", code, raw)
	}
	if code, _, raw := e.c.do("POST", "/api/v1/agent/sessions/"+sid+"/publish", tok, map[string]any{"confirm": true}); code != 200 {
		t.Fatalf("free publish with paywall off: %d %s", code, raw)
	}
}
