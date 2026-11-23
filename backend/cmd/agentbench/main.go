// Command agentbench measures the agentic flow end to end against a running
// stack (make up): sign-up in the Auth emulator → conversation with Kiu →
// readiness (POP) → publication. It reports p50/p95 per phase and AI cost.
//
//	go run ./cmd/agentbench -n 20
//
// Local only: it refuses non-loopback URLs. User think-time is NOT simulated;
// these are system times (what Kiu adds on top of the merchant typing).
package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strings"
	"time"
)

var (
	api      = flag.String("api", "http://localhost:8080", "KiuPop API")
	emulator = flag.String("emulator", "http://localhost:9199", "Firebase Auth emulator")
	n        = flag.Int("n", 20, "runs")
	client   = &http.Client{Timeout: 30 * time.Second}
)

var script = []string{
	"Soy Florería Bella %d, vendo flores, arreglos y regalos. Quiero algo elegante y romántico, con colores rosados. Entrego en Naranjo y San Ramón.",
	"Ramo de rosas 15000, arreglo de girasoles 18 mil y caja de regalo con chocolates ₡12.500",
	"Mi WhatsApp es 8888-1234",
}

type run struct {
	signup, conversation, toReady, publish, total time.Duration
	turns                                         []time.Duration
	questions                                     int
	costMicros                                    int64
	aiCalls                                       int
	mode                                          string
}

func main() {
	flag.Parse()
	for _, u := range []string{*api, *emulator} {
		p, err := url.Parse(u)
		if err != nil || (p.Hostname() != "localhost" && p.Hostname() != "127.0.0.1") {
			fmt.Fprintln(os.Stderr, "agentbench only runs against a local stack")
			os.Exit(2)
		}
	}
	var runs []run
	for i := 0; i < *n; i++ {
		r, err := once(i)
		if err != nil {
			fmt.Fprintf(os.Stderr, "run %d: %v\n", i, err)
			os.Exit(1)
		}
		runs = append(runs, r)
	}
	report(runs)
}

func once(i int) (run, error) {
	var r run
	start := time.Now()
	email := fmt.Sprintf("bench-%d-%d@example.test", time.Now().UnixNano(), i)
	var signup struct {
		IDToken string `json:"idToken"`
	}
	if err := call("POST", *emulator+"/identitytoolkit.googleapis.com/v1/accounts:signUp?key=bench", "",
		map[string]any{"email": email, "password": "bench-secret", "returnSecureToken": true}, &signup); err != nil {
		return r, fmt.Errorf("signup: %w", err)
	}
	tok := signup.IDToken
	var s session
	if err := call("POST", *api+"/api/v1/agent/sessions", tok, nil, &s); err != nil {
		return r, fmt.Errorf("start: %w", err)
	}
	r.signup = time.Since(start)

	conv := time.Now()
	for k, msg := range script {
		if strings.Contains(msg, "%d") {
			msg = fmt.Sprintf(msg, i)
		}
		t0 := time.Now()
		if err := call("POST", *api+"/api/v1/agent/sessions/"+s.ID+"/messages", tok,
			map[string]any{"text": msg, "client_message_id": fmt.Sprintf("bench-%d-%d", i, k)}, &s); err != nil {
			return r, fmt.Errorf("turn %d: %w", k, err)
		}
		r.turns = append(r.turns, time.Since(t0))
	}
	r.conversation = time.Since(conv)

	readyStart := time.Now()
	for s.Status != "ready" {
		if time.Since(readyStart) > 60*time.Second {
			return r, errors.New("not ready after 60s")
		}
		time.Sleep(50 * time.Millisecond)
		if err := call("GET", *api+"/api/v1/agent/sessions/"+s.ID, tok, nil, &s); err != nil {
			return r, err
		}
	}
	r.toReady = time.Since(readyStart)

	p0 := time.Now()
	var pub map[string]any
	if err := call("POST", *api+"/api/v1/agent/sessions/"+s.ID+"/publish", tok, map[string]any{"confirm": true}, &pub); err != nil {
		return r, fmt.Errorf("publish: %w", err)
	}
	r.publish = time.Since(p0)
	if err := call("GET", *api+"/api/v1/agent/sessions/"+s.ID, tok, nil, &s); err != nil {
		return r, err
	}
	r.total = time.Since(start)
	r.questions = s.Summary.QuestionsAsked
	r.costMicros, r.aiCalls, r.mode = s.AI.CostMicros, s.AI.Calls, s.AI.Mode
	return r, nil
}

type session struct {
	ID      string `json:"id"`
	Status  string `json:"status"`
	Summary struct {
		QuestionsAsked int `json:"questions_asked"`
	} `json:"summary"`
	AI struct {
		Mode       string `json:"mode"`
		Calls      int    `json:"calls"`
		CostMicros int64  `json:"cost_micros"`
	} `json:"ai"`
}

func call(method, u, token string, body, out any) error {
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req, err := http.NewRequest(method, u, rd)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	res, err := client.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	raw, _ := io.ReadAll(res.Body)
	if res.StatusCode >= 300 {
		return fmt.Errorf("%s %s: %d %s", method, u, res.StatusCode, raw)
	}
	return json.Unmarshal(raw, out)
}

func pct(ds []time.Duration, p float64) time.Duration {
	s := append([]time.Duration(nil), ds...)
	sort.Slice(s, func(i, j int) bool { return s[i] < s[j] })
	idx := int(p*float64(len(s)-1) + 0.5)
	return s[idx]
}

func report(runs []run) {
	col := func(f func(run) time.Duration) []time.Duration {
		var out []time.Duration
		for _, r := range runs {
			out = append(out, f(r))
		}
		return out
	}
	var turns []time.Duration
	var cost int64
	maxQ := 0
	for _, r := range runs {
		turns = append(turns, r.turns...)
		cost += r.costMicros
		maxQ = max(maxQ, r.questions)
	}
	ms := func(d time.Duration) string { return fmt.Sprintf("%d ms", d.Milliseconds()) }
	fmt.Printf("KiuPop agentbench · %d runs · brain=%s · %s\n\n", len(runs), runs[0].mode, time.Now().Format(time.RFC3339))
	fmt.Println("| Fase | p50 | p95 |")
	fmt.Println("|---|---|---|")
	rows := []struct {
		name string
		ds   []time.Duration
	}{
		{"Registro (emulador) + sesión", col(func(r run) time.Duration { return r.signup })},
		{"Turno de conversación (cada mensaje)", turns},
		{"Conversación (3 mensajes, sin tiempo de tipeo)", col(func(r run) time.Duration { return r.conversation })},
		{"Último mensaje → POP (readiness)", col(func(r run) time.Duration { return r.toReady })},
		{"Publicación", col(func(r run) time.Duration { return r.publish })},
		{"Total de sistema (registro → publicada)", col(func(r run) time.Duration { return r.total })},
	}
	for _, row := range rows {
		fmt.Printf("| %s | %s | %s |\n", row.name, ms(pct(row.ds, 0.5)), ms(pct(row.ds, 0.95)))
	}
	fmt.Printf("\nPreguntas máximas por tienda: %d · costo IA promedio por tienda: US$%.5f\n", maxQ, float64(cost)/float64(len(runs))/1e6)
}
