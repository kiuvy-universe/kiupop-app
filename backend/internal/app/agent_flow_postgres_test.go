package app

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"image"
	"image/png"
	"io"
	"log/slog"
	"mime/multipart"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/kiuvy-universe/kiupop/backend/internal/integrations/kiuvy"
	"github.com/kiuvy-universe/kiupop/backend/internal/integrations/payments"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/agent"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/ai"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/demo"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/orders"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/products"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/speech"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/storefront"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/stores"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/config"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/database"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/identity"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/storage"
	"github.com/kiuvy-universe/kiupop/backend/migrations"
)

// fakeVerifier accepts "fake.<anything>.<uid>" tokens (tests only).
type fakeVerifier struct{}

func (fakeVerifier) Mode() string { return "emulator" }
func (fakeVerifier) Verify(_ context.Context, tok string) (identity.Identity, error) {
	parts := strings.Split(tok, ".")
	if len(parts) != 3 || parts[0] != "fakeheader" {
		return identity.Identity{}, identity.ErrInvalidToken
	}
	return identity.Identity{UID: parts[2], Email: parts[2] + "@example.test", Provider: "password"}, nil
}

func token(uid string) string { return "fakeheader.payload." + uid }

func randomID() string {
	b := make([]byte, 6)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

type agentEnv struct {
	c    client
	svc  *agent.Service
	pool *pgxpool.Pool
	ctx  context.Context
}

func newAgentEnv(t *testing.T) agentEnv {
	return newAgentEnvWith(t, agent.Config{TestCheckout: true, ShareBase: "http://localhost:8080"})
}

func newAgentEnvWith(t *testing.T, agentCfg agent.Config) agentEnv {
	url := os.Getenv("KIUPOP_TEST_DATABASE_URL")
	if url == "" {
		t.Skip("KIUPOP_TEST_DATABASE_URL not set")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	t.Cleanup(cancel)
	pool, err := database.Open(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	quiet := slog.New(slog.NewTextHandler(io.Discard, nil))
	if _, err := database.Migrate(ctx, pool, migrations.FS, quiet); err != nil {
		t.Fatal(err)
	}
	if err := demo.SeedStore(ctx, pool); err != nil {
		t.Fatal(err)
	}
	storeRepo := stores.NewRepo(pool)
	sf := storefront.NewRepo(pool)
	svc := agent.NewService(agent.NewRepo(pool), agent.LocalBrain{}, agent.NoCopy{}, sf, agent.NewBus(), quiet,
		agentCfg, func() string {
			var id string
			_ = pool.QueryRow(ctx, `SELECT gen_random_uuid()::text`).Scan(&id)
			return id
		}).WithAttachments(agent.LocalFiles{Dir: t.TempDir()}, agent.NoReader{})
	cfg := config.Config{Env: config.EnvLocal, MockMode: true, StoreSignupEnabled: true, PaymentsTestCheckout: true,
		CORSAllowedOrigins: []string{"http://localhost:3000"}, PublicAPIBase: "http://localhost:8080", PublicWebBase: "http://localhost:3000"}
	h := NewRouter(cfg, Deps{
		DB: pool, Products: demo.NewPostgresRepo(pool), Kiuvy: kiuvy.Disabled{}, Log: quiet,
		Auth: storeRepo, StoreRepo: storeRepo, ProductRepo: products.NewRepo(pool),
		Images: products.LocalImages{Images: storage.Images{Dir: t.TempDir()}}, OrderRepo: orders.NewRepo(pool), AI: ai.Disabled{},
		Verifier: fakeVerifier{}, Users: usersWithSignup(pool, agentCfg), Owners: storeRepo, Agent: svc, Storefront: sf,
		CheckoutDB: orders.NewRepo(pool), Payments: payments.Mock{}, Speech: speech.Disabled{}, Funnel: funnelSink(agentCfg),
	})
	return agentEnv{c: client{t, h}, svc: svc, pool: pool, ctx: ctx}
}

// drain runs queued jobs until none is runnable (deterministic, no goroutines).
func (e agentEnv) drain(t *testing.T) int {
	t.Helper()
	n := 0
	for i := 0; i < 200; i++ {
		ran, err := e.svc.RunOnce(e.ctx)
		if err != nil {
			t.Fatal(err)
		}
		if !ran {
			return n
		}
		n++
	}
	t.Fatal("jobs never drained")
	return n
}

func pendingField(v map[string]any) string {
	q, _ := v["pending_question"].(map[string]any)
	if q == nil {
		return ""
	}
	return q["field"].(string)
}

func countEvents(t *testing.T, e agentEnv, session, typ string) int {
	var n int
	if err := e.pool.QueryRow(e.ctx, `SELECT count(*) FROM agent_events WHERE session_id = $1 AND type = $2`, session, typ).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

// Registrarse → contarle a Kiu → pocas preguntas → la tienda se construye → POP → publicar → compartir.
func TestAgenticStoreFlowAgainstPostgres(t *testing.T) {
	e := newAgentEnv(t)
	c := e.c
	uid := "u" + randomID()
	tok := token(uid)
	name := "Florería Bella " + randomID()[:4]

	if code, _, _ := c.do("POST", "/api/v1/agent/sessions", "", nil); code != 401 {
		t.Fatalf("anonymous session must be 401, got %d", code)
	}
	code, s, raw := c.do("POST", "/api/v1/agent/sessions", tok, nil)
	if code != 200 || s["status"] != "collecting" {
		t.Fatalf("start: %d %s", code, raw)
	}
	sid := s["id"].(string)
	if msgs := s["messages"].([]any); len(msgs) != 1 || !strings.Contains(msgs[0].(map[string]any)["text"].(string), "Soy Kiu") {
		t.Fatalf("greeting missing: %v", msgs)
	}
	// Starting again resumes the same live session (reload).
	if _, again, _ := c.do("POST", "/api/v1/agent/sessions", tok, nil); again["id"] != sid {
		t.Fatal("start must resume the live session")
	}

	msg := func(text, clientID string) map[string]any {
		t.Helper()
		code, v, raw := c.do("POST", "/api/v1/agent/sessions/"+sid+"/messages", tok, map[string]any{"text": text, "client_message_id": clientID})
		if code != 200 {
			t.Fatalf("message %q: %d %s", text, code, raw)
		}
		return v
	}

	// 1. Free description: Kiu understands and asks only for what is missing (prices).
	v := msg("Soy "+name+", vendo flores, arreglos y regalos. Quiero algo elegante y romántico, con colores rosados. Entrego en Naranjo y San Ramón.", "client-msg-0001")
	if got := pendingField(v); got != agent.FieldPrices {
		t.Fatalf("first question should be prices, got %q", got)
	}
	sum := v["summary"].(map[string]any)
	if sum["business_name"] != name || sum["products"].(float64) != 3 || sum["priced_products"].(float64) != 0 {
		t.Fatalf("summary after first message: %v", sum)
	}
	// Retrying the same client message is a no-op (idempotent).
	before := len(v["messages"].([]any))
	if again := msg("Soy "+name+", vendo flores.", "client-msg-0001"); len(again["messages"].([]any)) != before {
		t.Fatal("duplicate client_message_id must not add messages")
	}
	// The draft exists immediately and is not public.
	e.drain(t)
	var draftSlug, draftStatus string
	if err := e.pool.QueryRow(e.ctx, `SELECT s.slug, s.status FROM stores s JOIN agent_sessions a ON a.store_id = s.id WHERE a.id = $1`, sid).
		Scan(&draftSlug, &draftStatus); err != nil || draftStatus != "draft" {
		t.Fatalf("draft not created: %v %s", err, draftStatus)
	}
	if code, _, _ := c.do("GET", "/api/v1/stores/"+draftSlug, "", nil); code != 404 {
		t.Fatalf("draft must not be public, got %d", code)
	}
	if code, _, _ := c.do("GET", "/api/v1/public/stores/"+draftSlug+"/storefront", "", nil); code != 404 {
		t.Fatalf("draft storefront must not be public, got %d", code)
	}

	if code, _ := upload(t, e, tok, sid, "ramo.png", tinyPNG(t)); code != 201 {
		t.Fatalf("photo upload: %d", code)
	}

	// 2. Prices: grounded in the merchant's words; then WhatsApp is asked (delivery and style are known).
	v = msg("Ramo de rosas 15000, arreglo de girasoles 18 mil y caja de regalo con chocolates ₡12.500", "client-msg-0002")
	if got := pendingField(v); got != agent.FieldWhatsApp {
		t.Fatalf("second question should be whatsapp, got %q", got)
	}
	if v["summary"].(map[string]any)["priced_products"].(float64) != 3 {
		t.Fatalf("prices not applied: %v", v["summary"])
	}
	// POP must not fire before readiness.
	e.drain(t)
	if n := countEvents(t, e, sid, "store.ready"); n != 0 {
		t.Fatalf("store.ready before readiness: %d", n)
	}

	// 3. WhatsApp: no more questions; Kiu builds.
	v = msg("Mi WhatsApp es 8888-1234", "client-msg-0003")
	if got := pendingField(v); got != "" {
		t.Fatalf("no more questions expected, got %q", got)
	}
	if asked := v["summary"].(map[string]any)["questions_asked"].(float64); asked > 3 {
		t.Fatalf("asked %v questions, budget is 3", asked)
	}
	e.drain(t)

	// 4. Ready exactly once, with a POP message.
	code, v, raw = c.do("GET", "/api/v1/agent/sessions/current", tok, nil)
	if code != 200 || v["status"] != "ready" || v["progress"].(map[string]any)["percent"].(float64) != 100 {
		t.Fatalf("not ready: %d %s", code, raw)
	}
	if n := countEvents(t, e, sid, "store.ready"); n != 1 {
		t.Fatalf("store.ready emitted %d times", n)
	}
	if !strings.Contains(raw, "¡POP!") || !strings.Contains(raw, "__publish__") {
		t.Fatal("ready message with publish quick reply missing")
	}
	assertSameKeys(t, "agent_session", exampleMap(t, "agent_session.json"), v)
	_, evs, _ := c.do("GET", "/api/v1/agent/sessions/"+sid+"/events?after=0", tok, nil)
	assertSameKeys(t, "agent_events", exampleMap(t, "agent_events.json"), evs)
	_, me, _ := c.do("GET", "/api/v1/me", tok, nil)
	assertSameKeys(t, "me", exampleMap(t, "me.json"), me)
	_, tk, _ := c.do("POST", "/api/v1/agent/sessions/"+sid+"/stream-ticket", tok, nil)
	assertSameKeys(t, "stream_ticket", exampleMap(t, "agent_stream_ticket.json"), tk)
	// A later change does not POP again.
	msg("Probar Mint Fresh", "client-msg-0004")
	e.drain(t)
	if n := countEvents(t, e, sid, "store.ready"); n != 1 {
		t.Fatalf("store.ready re-emitted: %d", n)
	}
	code, pv, raw := c.do("GET", "/api/v1/agent/sessions/"+sid+"/preview", tok, nil)
	if code != 200 || pv["theme"].(map[string]any)["template"] != "mint_fresh" || len(pv["products"].([]any)) != 3 {
		t.Fatalf("preview: %d %s", code, raw)
	}

	// 5. Isolation: another user can't read, post to or publish this session.
	other := token("u" + randomID())
	for _, path := range []string{"/api/v1/agent/sessions/" + sid, "/api/v1/agent/sessions/" + sid + "/preview"} {
		if code, _, _ := c.do("GET", path, other, nil); code != 404 {
			t.Fatalf("cross-user GET %s = %d", path, code)
		}
	}
	if code, _, _ := c.do("POST", "/api/v1/agent/sessions/"+sid+"/publish", other, map[string]any{"confirm": true}); code != 404 {
		t.Fatalf("cross-user publish = %d", code)
	}

	// 6. Publication needs explicit confirmation, happens once, and is idempotent.
	if code, _, _ := c.do("POST", "/api/v1/agent/sessions/"+sid+"/publish", tok, map[string]any{"confirm": false}); code != 400 {
		t.Fatalf("publish without confirm = %d", code)
	}
	code, p1, raw := c.do("POST", "/api/v1/agent/sessions/"+sid+"/publish", tok, map[string]any{"confirm": true})
	if code != 200 || p1["version"].(float64) != 1 || !strings.HasSuffix(p1["share_url"].(string), "/p/"+p1["slug"].(string)) {
		t.Fatalf("publish: %d %s", code, raw)
	}
	_, p2, _ := c.do("POST", "/api/v1/agent/sessions/"+sid+"/publish", tok, map[string]any{"confirm": true})
	if p2["version"] != p1["version"] || countEvents(t, e, sid, "store.published") != 1 {
		t.Fatal("publish must be idempotent and emit store.published once")
	}
	slug := p1["slug"].(string)
	assertSameKeys(t, "publish", exampleMap(t, "agent_publish_response.json"), p1)
	if code, _, _ := c.do("POST", "/api/v1/agent/sessions/"+sid+"/messages", tok, map[string]any{"text": "hola"}); code != 409 {
		t.Fatalf("published session must be closed, got %d", code)
	}

	// 7. Public storefront: only validated data; no invented prices; delivery as stated.
	code, view, raw := c.do("GET", "/api/v1/public/stores/"+slug+"/storefront", "", nil)
	if code != 200 {
		t.Fatalf("storefront: %d %s", code, raw)
	}
	assertSameKeys(t, "storefront", exampleMap(t, "storefront_view.json"), view)
	prices := map[string]float64{}
	for _, it := range view["products"].([]any) {
		p := it.(map[string]any)
		prices[p["name"].(string)] = p["price_minor"].(float64)
	}
	if prices["Ramo de rosas"] != 1_500_000 || prices["Arreglo de girasoles"] != 1_800_000 || prices["Caja de regalo con chocolates"] != 1_250_000 || len(prices) != 3 {
		t.Fatalf("published prices: %v", prices)
	}
	if view["payments"].(map[string]any)["real_payments_enabled"] != false || !strings.Contains(raw, "San Ramón") {
		t.Fatalf("storefront payments/delivery: %s", raw)
	}
	if code, _, _ := c.do("GET", "/api/v1/stores/"+slug, "", nil); code != 200 {
		t.Fatalf("published store must be public, got %d", code)
	}

	// 8. Owner can use the admin endpoints with the same login (no kp_ key).
	if code, cur, raw := c.do("GET", "/api/v1/admin/stores/current", tok, nil); code != 200 || cur["store"].(map[string]any)["slug"] != slug {
		t.Fatalf("admin with id token: %d %s", code, raw)
	}

	// 9. Test-mode checkout: server-priced, never real money, settles once.
	pid := view["products"].([]any)[0].(map[string]any)["id"].(string)
	code, pay, raw := c.do("POST", "/api/v1/public/stores/"+slug+"/checkout", "", map[string]any{
		"items": []map[string]any{{"product_id": pid, "quantity": 2}}, "idempotency_key": "chk-" + randomID()})
	if code != 201 || pay["mode"] != "test" || pay["status"] != "pending" || pay["amount_minor"].(float64) <= 0 {
		t.Fatalf("checkout: %d %s", code, raw)
	}
	assertSameKeys(t, "payment", exampleMap(t, "payment.json"), pay)
	payID := pay["id"].(string)
	if code, _, _ := c.do("POST", "/api/v1/public/stores/"+slug+"/checkout", "", map[string]any{
		"items": []map[string]any{{"product_id": pid, "quantity": 1, "price_minor": 1}}, "idempotency_key": "chk-" + randomID()}); code != 400 {
		t.Fatalf("client price must be rejected, got %d", code)
	}
	_, settled, _ := c.do("POST", "/api/v1/public/payments/"+payID+"/test-outcome", "", map[string]any{"outcome": "approved"})
	_, again, _ := c.do("POST", "/api/v1/public/payments/"+payID+"/test-outcome", "", map[string]any{"outcome": "declined"})
	if settled["status"] != "test_approved" || again["status"] != "test_approved" {
		t.Fatalf("settle once: %v %v", settled["status"], again["status"])
	}

	// 10. Social preview page for crawlers.
	if code, _, raw := c.do("GET", "/p/"+slug, "", nil); code != 200 || !strings.Contains(raw, `property="og:title"`) || !strings.Contains(raw, "/#/s/"+slug) {
		t.Fatalf("share page: %d %s", code, raw)
	}

	// 11. Audit trail recorded the tools, without secrets.
	var tools int
	_ = e.pool.QueryRow(e.ctx, `SELECT count(DISTINCT tool) FROM agent_actions WHERE session_id = $1`, sid).Scan(&tools)
	if tools < 6 {
		t.Fatalf("expected tool audit rows, got %d distinct tools", tools)
	}
}

// Kiu does not re-ask what it knows and stops when it has enough.
func TestAgentAsksOnlyMissingAgainstPostgres(t *testing.T) {
	e := newAgentEnv(t)
	tok := token("u" + randomID())
	_, s, _ := e.c.do("POST", "/api/v1/agent/sessions", tok, nil)
	sid := s["id"].(string)
	code, v, raw := e.c.do("POST", "/api/v1/agent/sessions/"+sid+"/messages", tok, map[string]any{
		"text": "Somos Dulce Antojo " + randomID()[:4] + ", vendemos queque de zanahoria a 9500 y galletas a 3000. Hacemos envíos a domicilio y también retiran. Nuestro WhatsApp es 8777 6655. Estilo divertido."})
	if code != 200 {
		t.Fatalf("%d %s", code, raw)
	}
	if f := pendingField(v); f != "" {
		t.Fatalf("everything was given; Kiu asked %q", f)
	}
	e.drain(t)
	_, v, _ = e.c.do("GET", "/api/v1/agent/sessions/"+sid, tok, nil)
	if v["status"] != "ready" || v["summary"].(map[string]any)["template"] != "peach_pop" {
		t.Fatalf("status=%v template=%v", v["status"], v["summary"].(map[string]any)["template"])
	}
}

// Interrupted jobs are recovered after a restart (expired lease → queued).
func TestAgentJobRecoveryAgainstPostgres(t *testing.T) {
	e := newAgentEnv(t)
	tok := token("u" + randomID())
	_, s, _ := e.c.do("POST", "/api/v1/agent/sessions", tok, nil)
	sid := s["id"].(string)
	e.c.do("POST", "/api/v1/agent/sessions/"+sid+"/messages", tok, map[string]any{"text": "Soy Vivero Luna, vendo suculentas a 2500"})
	// Simulate a crash: the job was claimed but its worker died.
	if _, err := e.pool.Exec(e.ctx, `UPDATE agent_jobs SET status = 'running', attempts = 1, lease_until = now() - interval '1 second'
		WHERE session_id = $1 AND status = 'queued'`, sid); err != nil {
		t.Fatal(err)
	}
	if n := e.drain(t); n != 0 {
		t.Fatalf("running jobs must not be claimed twice, ran %d", n)
	}
	repo := agent.NewRepo(e.pool)
	if k, err := repo.RecoverExpired(e.ctx); err != nil || k == 0 {
		t.Fatalf("recover: %d %v", k, err)
	}
	if n := e.drain(t); n == 0 {
		t.Fatal("recovered jobs did not run")
	}
	var open int
	_ = e.pool.QueryRow(e.ctx, `SELECT count(*) FROM agent_jobs WHERE session_id = $1 AND status IN ('queued','running')`, sid).Scan(&open)
	if open != 0 {
		t.Fatalf("%d jobs still open", open)
	}
	fmt.Fprint(io.Discard, sid)
}

func exampleMap(t *testing.T, name string) map[string]any {
	t.Helper()
	var m map[string]any
	if err := json.Unmarshal([]byte(example(t, name)), &m); err != nil {
		t.Fatalf("%s: %v", name, err)
	}
	return m
}

func upload(t *testing.T, e agentEnv, tok, sid, name string, data []byte) (int, map[string]any) {
	t.Helper()
	var body bytes.Buffer
	mw := multipart.NewWriter(&body)
	fw, _ := mw.CreateFormFile("file", name)
	_, _ = fw.Write(data)
	_ = mw.Close()
	req := httptest.NewRequest("POST", "/api/v1/agent/sessions/"+sid+"/attachments", &body)
	req.Header.Set("Content-Type", mw.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+tok)
	rec := httptest.NewRecorder()
	e.c.h.ServeHTTP(rec, req)
	var out map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	return rec.Code, out
}

func tinyPNG(t *testing.T) []byte {
	t.Helper()
	var b bytes.Buffer
	img := image.NewRGBA(image.Rect(0, 0, 4, 4))
	if err := png.Encode(&b, img); err != nil {
		t.Fatal(err)
	}
	return b.Bytes()
}

// Files are untrusted: validated by content, limited, processed one by one.
func TestAgentAttachmentsAgainstPostgres(t *testing.T) {
	e := newAgentEnv(t)
	tok := token("u" + randomID())
	_, s, _ := e.c.do("POST", "/api/v1/agent/sessions", tok, nil)
	sid := s["id"].(string)
	e.c.do("POST", "/api/v1/agent/sessions/"+sid+"/messages", tok, map[string]any{"text": "Soy Panadería Luz, vendo pan casero y empanadas."})

	// CSV catalog: prices come from the merchant's own file.
	csv := []byte("producto;precio\nPan casero;1.500\nEmpanada de queso;₡900\nSin precio;\n")
	if code, a := upload(t, e, tok, sid, "catalogo.csv", csv); code != 201 || a["kind"] != "csv" || a["status"] != "received" {
		t.Fatalf("csv upload: %d %v", code, a)
	}
	// Photo: becomes the first product without a photo (no AI configured).
	if code, a := upload(t, e, tok, sid, "foto.png", tinyPNG(t)); code != 201 || a["kind"] != "image" {
		t.Fatalf("photo upload: %d %v", code, a)
	}
	// A script disguised as a CSV, and an HTML "image", are rejected by content.
	if code, _ := upload(t, e, tok, sid, "malo.csv", []byte("\x00\x01binary")); code != 415 {
		t.Fatalf("binary csv accepted: %d", code)
	}
	if code, _ := upload(t, e, tok, sid, "foto.jpg", []byte("<html><script>alert(1)</script></html>")); code != 415 {
		t.Fatalf("html as image accepted: %d", code)
	}
	// PDF without AI: honest needs_review.
	if code, _ := upload(t, e, tok, sid, "catalogo.pdf", []byte("%PDF-1.4\n%fake\n")); code != 201 {
		t.Fatalf("pdf upload: %d", code)
	}
	e.drain(t)
	_, v, raw := e.c.do("GET", "/api/v1/agent/sessions/"+sid, tok, nil)
	atts := v["attachments"].([]any)
	status := map[string]string{}
	for _, a := range atts {
		m := a.(map[string]any)
		status[m["kind"].(string)] = m["status"].(string)
	}
	if status["csv"] != "processed" || status["image"] != "processed" || status["pdf"] != "needs_review" {
		t.Fatalf("attachment states: %v", status)
	}
	if v["summary"].(map[string]any)["priced_products"].(float64) != 2 {
		t.Fatalf("csv prices not applied: %s", raw)
	}
	if f := pendingField(v); f == agent.FieldPrices {
		t.Fatal("prices were answered by the CSV; Kiu must not ask again")
	}
	_, pv, _ := e.c.do("GET", "/api/v1/agent/sessions/"+sid+"/preview", tok, nil)
	withPhoto := 0
	for _, p := range pv["products"].([]any) {
		if p.(map[string]any)["image_url"] != nil {
			withPhoto++
		}
	}
	if withPhoto != 1 {
		t.Fatalf("photo not attached to a product: %v", pv["products"])
	}
	// Limits: 5 files per session.
	upload(t, e, tok, sid, "b.png", tinyPNG(t)) // 4th
	upload(t, e, tok, sid, "c.png", tinyPNG(t)) // 5th
	if code, _ := upload(t, e, tok, sid, "d.png", tinyPNG(t)); code != 409 {
		t.Fatalf("sixth file accepted: %d", code)
	}
	// Another user cannot upload into this session.
	if code, _ := upload(t, e, token("u"+randomID()), sid, "x.png", tinyPNG(t)); code != 404 {
		t.Fatalf("cross-user upload: %d", code)
	}
}

// Concurrency: double first message → one draft; double publish → one version and one event.
func TestAgentConcurrencyAgainstPostgres(t *testing.T) {
	e := newAgentEnv(t)
	tok := token("u" + randomID())
	_, s, _ := e.c.do("POST", "/api/v1/agent/sessions", tok, nil)
	sid := s["id"].(string)
	var wg sync.WaitGroup
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			e.c.do("POST", "/api/v1/agent/sessions/"+sid+"/messages", tok, map[string]any{
				"text": fmt.Sprintf("Soy Vivero Sol, vendo suculentas a 2500 y cactus a 3000. WhatsApp 8777 112%d", i)})
		}(i)
	}
	wg.Wait()
	var drafts int
	_ = e.pool.QueryRow(e.ctx, `SELECT count(*) FROM stores s JOIN users u ON u.id = s.owner_user_id
		JOIN agent_sessions a ON a.user_id = u.id WHERE a.id = $1`, sid).Scan(&drafts)
	if drafts != 1 {
		t.Fatalf("concurrent first messages created %d drafts", drafts)
	}
	e.drain(t)
	results := make(chan float64, 4)
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, p, _ := e.c.do("POST", "/api/v1/agent/sessions/"+sid+"/publish", tok, map[string]any{"confirm": true})
			if v, ok := p["version"].(float64); ok {
				results <- v
			}
		}()
	}
	wg.Wait()
	close(results)
	for v := range results {
		if v != 1 {
			t.Fatalf("concurrent publish produced version %v", v)
		}
	}
	if n := countEvents(t, e, sid, "store.published"); n != 1 {
		t.Fatalf("store.published emitted %d times", n)
	}
}
