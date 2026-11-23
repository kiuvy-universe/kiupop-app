package app

import (
	"strings"
	"testing"

	"github.com/kiuvy-universe/kiupop/backend/internal/modules/agent"
)

// KIU_DISCOVERY_ENABLED: Kiu diagnoses first (channels, pain), recommends a
// plan, builds nothing until the merchant accepts, and hands a per-channel kit
// at publish. With the flag off the original flow is unchanged (other tests).
func TestAgentDiscoveryFlowAgainstPostgres(t *testing.T) {
	e := newAgentEnvWith(t, agent.Config{TestCheckout: true, ShareBase: "http://localhost:8080", Discovery: true})
	c := e.c
	tok := token("u" + randomID())
	name := "Flores Luna " + randomID()[:4]

	_, s, raw := c.do("POST", "/api/v1/agent/sessions", tok, nil)
	sid, _ := s["id"].(string)
	if msgs, _ := s["messages"].([]any); len(msgs) != 1 || !strings.Contains(msgs[0].(map[string]any)["text"].(string), "Antes de crear nada") {
		t.Fatalf("discovery greeting missing: %s", raw)
	}
	msg := func(text string) map[string]any {
		t.Helper()
		code, v, raw := c.do("POST", "/api/v1/agent/sessions/"+sid+"/messages", tok, map[string]any{"text": text, "client_message_id": "disc-" + randomID()})
		if code != 200 {
			t.Fatalf("message %q: %d %s", text, code, raw)
		}
		return v
	}
	jobs := func() int {
		var n int
		if err := e.pool.QueryRow(e.ctx, `SELECT count(*) FROM agent_jobs WHERE session_id = $1`, sid).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}
	hasStore := func() bool {
		var id *string
		if err := e.pool.QueryRow(e.ctx, `SELECT store_id::text FROM agent_sessions WHERE id = $1`, sid).Scan(&id); err != nil {
			t.Fatal(err)
		}
		return id != nil
	}
	lastKiu := func(v map[string]any) map[string]any {
		msgs := v["messages"].([]any)
		return msgs[len(msgs)-1].(map[string]any)
	}

	// 1. The business description (WhatsApp number included) is understood, but nothing is built.
	v := msg("Soy " + name + ", vendo ramos de rosas y arreglos de girasoles. Mi WhatsApp es 8888-1234. Entrego en Naranjo.")
	if got := pendingField(v); got != agent.FieldChannels {
		t.Fatalf("first filter question should be channels, got %q", got)
	}
	if hasStore() || jobs() != 0 {
		t.Fatalf("nothing may be built during the diagnosis (store=%v jobs=%d)", hasStore(), jobs())
	}
	if p := v["progress"].(map[string]any)["percent"].(float64); p != 0 {
		t.Fatalf("progress must stay at 0 while diagnosing, got %v", p)
	}

	// 2. Channels → pain.
	if got := pendingField(msg("Me compran por Instagram")); got != agent.FieldPain {
		t.Fatalf("second filter should be pain, got %q", got)
	}

	// 3. Pain → plan (a Kiu message, no open question), still nothing built.
	v = msg("Responder precios uno por uno")
	plan := lastKiu(v)
	meta := plan["meta"].(map[string]any)
	if pendingField(v) != "" || meta["kind"] != "plan" {
		t.Fatalf("expected the plan, got pending=%q kind=%v", pendingField(v), meta["kind"])
	}
	text := plan["text"].(string)
	for _, want := range []string{"Instagram", "precios uno por uno", "¿Armamos esto?"} {
		if !strings.Contains(text, want) {
			t.Fatalf("plan lacks %q:\n%s", want, text)
		}
	}
	if qr := meta["quick_replies"].([]any); len(qr) != 2 || qr[0].(map[string]any)["value"] != agent.ReplyAcceptPlan {
		t.Fatalf("plan quick replies: %v", qr)
	}
	if hasStore() || jobs() != 0 {
		t.Fatal("proposing the plan must not build anything")
	}

	// 4. Something unrelated → a reminder, still no build.
	v = msg("mmm déjame pensarlo")
	if lastKiu(v)["meta"].(map[string]any)["kind"] != "notice" || hasStore() {
		t.Fatalf("expected a reminder without building: %v", lastKiu(v))
	}

	// 5. Accept → the draft is created and work is queued; Kiu asks the missing essentials.
	v = msg(agent.ReplyAcceptPlan)
	if !hasStore() || jobs() == 0 {
		t.Fatalf("accepting must start the build (store=%v jobs=%d)", hasStore(), jobs())
	}
	if got := pendingField(v); got != agent.FieldPrices {
		t.Fatalf("after accepting Kiu asks prices, got %q", got)
	}
	if sum := v["summary"].(map[string]any); sum["has_whatsapp"] != true || sum["products"].(float64) != 2 {
		t.Fatalf("data from the diagnosis must be kept: %v", sum)
	}

	// 6. Prices → ready → publish → the kit (WhatsApp + Instagram, link filled in).
	msg("Ramo de rosas 15000 y arreglo de girasoles 18 mil")
	for i := 0; i < 5; i++ {
		e.drain(t)
		if _, v, _ = c.do("GET", "/api/v1/agent/sessions/"+sid, tok, nil); v["status"] == "ready" {
			break
		}
	}
	if v["status"] != "ready" {
		t.Fatalf("store not ready: %v (pending %q)", v["status"], pendingField(v))
	}
	code, pub, raw := c.do("POST", "/api/v1/agent/sessions/"+sid+"/publish", tok, map[string]any{"confirm": true})
	if code != 200 {
		t.Fatalf("publish: %d %s", code, raw)
	}
	_, v, _ = c.do("GET", "/api/v1/agent/sessions/"+sid, tok, nil)
	kit := lastKiu(v)
	kitText := kit["text"].(string)
	if kit["meta"].(map[string]any)["kind"] != "kit" || !strings.Contains(kitText, pub["share_url"].(string)) ||
		!strings.Contains(kitText, "Instagram") || strings.Contains(kitText, "Facebook") {
		t.Fatalf("kit after publishing:\n%s", kitText)
	}
}

// "Ya sé lo que quiero" skips the diagnosis and builds right away.
func TestAgentDiscoverySkipAgainstPostgres(t *testing.T) {
	e := newAgentEnvWith(t, agent.Config{TestCheckout: true, ShareBase: "http://localhost:8080", Discovery: true})
	tok := token("u" + randomID())
	_, s, _ := e.c.do("POST", "/api/v1/agent/sessions", tok, nil)
	sid := s["id"].(string)
	e.c.do("POST", "/api/v1/agent/sessions/"+sid+"/messages", tok, map[string]any{"text": "Somos Dulce Antojo " + randomID()[:4] + ", vendemos queque de zanahoria a 9500."})
	_, v, raw := e.c.do("POST", "/api/v1/agent/sessions/"+sid+"/messages", tok, map[string]any{"text": agent.ReplyKnowWhat})
	if got := pendingField(v); got != agent.FieldWhatsApp {
		t.Fatalf("skipping the diagnosis should go straight to the missing essentials (whatsapp), got %q: %s", got, raw)
	}
	var store *string
	if err := e.pool.QueryRow(e.ctx, `SELECT store_id::text FROM agent_sessions WHERE id = $1`, sid).Scan(&store); err != nil || store == nil {
		t.Fatalf("skip must create the draft: %v", err)
	}
}
