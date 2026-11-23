package speech

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"math"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/kiuvy-universe/kiupop/backend/internal/platform/gcp"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/identity"
)

// wav builds a 16-bit mono PCM WAV with a tone of the given amplitude.
func wav(rate int, dur time.Duration, amp float64) []byte {
	n := int(dur.Seconds() * float64(rate))
	pcm := make([]byte, 2*n)
	for i := 0; i < n; i++ {
		v := int16(amp * math.Sin(2*math.Pi*220*float64(i)/float64(rate)))
		binary.LittleEndian.PutUint16(pcm[2*i:], uint16(v))
	}
	var b bytes.Buffer
	b.WriteString("RIFF")
	_ = binary.Write(&b, binary.LittleEndian, uint32(36+len(pcm)))
	b.WriteString("WAVEfmt ")
	_ = binary.Write(&b, binary.LittleEndian, uint32(16))
	_ = binary.Write(&b, binary.LittleEndian, uint16(1))
	_ = binary.Write(&b, binary.LittleEndian, uint16(1))
	_ = binary.Write(&b, binary.LittleEndian, uint32(rate))
	_ = binary.Write(&b, binary.LittleEndian, uint32(rate*2))
	_ = binary.Write(&b, binary.LittleEndian, uint16(2))
	_ = binary.Write(&b, binary.LittleEndian, uint16(16))
	b.WriteString("data")
	_ = binary.Write(&b, binary.LittleEndian, uint32(len(pcm)))
	b.Write(pcm)
	return b.Bytes()
}

func TestInspect(t *testing.T) {
	maxDur := 60 * time.Second
	a, err := Inspect(wav(16000, 3*time.Second, 6000), maxDur)
	if err != nil || a.Format != "wav" || a.SampleRate != 16000 || a.Duration != 3*time.Second {
		t.Fatalf("speech wav: %+v %v", a, err)
	}
	for name, tc := range map[string]struct {
		data []byte
		want error
	}{
		"silence":    {wav(16000, 3*time.Second, 10), ErrSilent},
		"too short":  {wav(16000, 300*time.Millisecond, 6000), ErrTooShort},
		"too long":   {wav(8000, 61*time.Second, 6000), ErrTooLong},
		"not audio":  {[]byte("<script>alert(1)</script> pretending to be audio"), ErrUnsupported},
		"png":        {append([]byte("\x89PNG\r\n\x1a\n"), make([]byte, 4096)...), ErrUnsupported},
		"tiny webm":  {[]byte{0x1A, 0x45, 0xDF, 0xA3, 1, 2, 3}, ErrTooShort},
		"stereo wav": {stereo(), ErrUnsupported},
	} {
		if _, err := Inspect(tc.data, maxDur); !errors.Is(err, tc.want) {
			t.Errorf("%s: got %v, want %v", name, err, tc.want)
		}
	}
	webm := append([]byte{0x1A, 0x45, 0xDF, 0xA3}, make([]byte, 4096)...)
	if a, err := Inspect(webm, maxDur); err != nil || a.Format != "webm" || a.SampleRate != 48000 {
		t.Fatalf("webm: %+v %v", a, err)
	}
	ogg := append([]byte("OggS"), make([]byte, 4096)...)
	if a, err := Inspect(ogg, maxDur); err != nil || a.Format != "ogg" {
		t.Fatalf("ogg: %+v %v", a, err)
	}
}

func stereo() []byte {
	b := wav(16000, 2*time.Second, 6000)
	binary.LittleEndian.PutUint16(b[22:], 2)
	return b
}

func TestGoogleRequestAndResponse(t *testing.T) {
	var got recognizeReq
	var hdr http.Header
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hdr = r.Header
		if r.URL.Path != "/v1/speech:recognize" {
			t.Errorf("path %s", r.URL.Path)
		}
		_ = json.NewDecoder(r.Body).Decode(&got)
		_, _ = io.WriteString(w, `{"results":[{"alternatives":[{"transcript":"Vendo queques de naranja a seis mil quinientos colones","confidence":0.9}],"languageCode":"es-cr"},{"alternatives":[{"transcript":"y galletas a dos mil quinientos.","confidence":0.8}]}],"totalBilledTime":"7s"}`)
	}))
	defer srv.Close()
	g := Google{Project: "kiupop-demo", Language: "es-CR", Tokens: gcp.Static("tok"), Endpoint: srv.URL}
	audio := wav(16000, 3*time.Second, 6000)
	res, err := g.Transcribe(context.Background(), Audio{Data: audio, Format: "wav", SampleRate: 16000})
	if err != nil {
		t.Fatal(err)
	}
	if res.Text != "Vendo queques de naranja a seis mil quinientos colones y galletas a dos mil quinientos." ||
		res.BilledSeconds != 7 || res.Language != "es-cr" || res.Provider != "google-stt-v1" || res.Confidence < .84 {
		t.Fatalf("result: %+v", res)
	}
	if hdr.Get("Authorization") != "Bearer tok" || hdr.Get("x-goog-user-project") != "kiupop-demo" {
		t.Fatalf("headers: %v", hdr)
	}
	raw, _ := base64.StdEncoding.DecodeString(got.Audio.Content)
	if got.Config.Encoding != "LINEAR16" || got.Config.SampleRateHertz != 16000 || got.Config.LanguageCode != "es-CR" ||
		!bytes.Equal(raw, audio) || !got.Config.EnableAutomaticPunctuation || len(got.Config.SpeechContexts) != 1 {
		t.Fatalf("request: %+v", got.Config)
	}
	for _, f := range []string{"webm", "ogg"} {
		if _, err := g.Transcribe(context.Background(), Audio{Data: audio, Format: f, SampleRate: 48000}); err != nil {
			t.Fatalf("%s: %v", f, err)
		}
	}
	if _, err := g.Transcribe(context.Background(), Audio{Format: "mp3"}); !errors.Is(err, ErrUnsupported) {
		t.Fatalf("mp3: %v", err)
	}
}

func TestGoogleEmptyAndFailure(t *testing.T) {
	status, body := http.StatusOK, `{"totalBilledTime":"3.2s"}`
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(status)
		_, _ = io.WriteString(w, body)
	}))
	defer srv.Close()
	g := Google{Project: "p", Language: "es-CR", Tokens: gcp.Static("t"), Endpoint: srv.URL}
	res, err := g.Transcribe(context.Background(), Audio{Data: []byte("x"), Format: "wav", SampleRate: 16000})
	if !errors.Is(err, ErrNoSpeech) || res.BilledSeconds != 4 {
		t.Fatalf("empty: %+v %v", res, err)
	}
	status, body = http.StatusForbidden, `{"error":{"message":"denied"}}`
	if _, err := g.Transcribe(context.Background(), Audio{Data: []byte("x"), Format: "wav", SampleRate: 16000}); err == nil ||
		!strings.Contains(err.Error(), "403") {
		t.Fatalf("403: %v", err)
	}
	status, body = http.StatusOK, `not json`
	if _, err := g.Transcribe(context.Background(), Audio{Data: []byte("x"), Format: "wav", SampleRate: 16000}); err == nil {
		t.Fatal("bad json accepted")
	}
	if billedSeconds("") != 0 || billedSeconds("12s") != 12 || billedSeconds("-1s") != 0 {
		t.Fatal("billedSeconds")
	}
}

type fakeT struct {
	res   Result
	err   error
	calls int
}

func (f *fakeT) Transcribe(context.Context, Audio) (Result, error) { f.calls++; return f.res, f.err }
func (f *fakeT) Provider() string                                  { return "fake" }

type fakeFunnel struct {
	mu     sync.Mutex
	events []string
	meta   []map[string]int64
}

func (f *fakeFunnel) Record(_ context.Context, _, _, event string, meta map[string]int64) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.events = append(f.events, event)
	f.meta = append(f.meta, meta)
}

func post(h *Handler, user string, body []byte) *httptest.ResponseRecorder {
	mux := http.NewServeMux()
	h.Register(mux, func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			next.ServeHTTP(w, r.WithContext(identity.WithUser(r.Context(), identity.User{ID: user})))
		})
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/speech/transcriptions?session_id=s1", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	return rec
}

func limits() Limits {
	return Limits{MaxBytes: 4 << 20, MaxSeconds: 60, UserDailySeconds: 20, GlobalDailySeconds: 30, USDMicrosPerMinute: 24000}
}

func TestHandler(t *testing.T) {
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	ft := &fakeT{res: Result{Text: "Rosas a quince mil", Provider: "fake", Language: "es-CR", BilledSeconds: 5}}
	fn := &fakeFunnel{}
	h := NewHandler(ft, limits(), fn, log)

	rec := post(h, "u1", wav(16000, 4*time.Second, 6000))
	if rec.Code != http.StatusOK {
		t.Fatalf("ok: %d %s", rec.Code, rec.Body)
	}
	var out Out
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	if out.Text != "Rosas a quince mil" || out.DurationMs != 4000 || out.BilledSeconds != 5 {
		t.Fatalf("out: %+v", out)
	}
	if len(fn.events) != 1 || fn.events[0] != "transcription_completed" || fn.meta[0]["cost_micros"] != 2000 {
		t.Fatalf("funnel: %v %v", fn.events, fn.meta)
	}

	for name, tc := range map[string]struct {
		body []byte
		code int
		want string
	}{
		"silent":  {wav(16000, 3*time.Second, 5), 422, "audio_silent"},
		"short":   {wav(16000, 200*time.Millisecond, 6000), 422, "audio_too_short"},
		"not wav": {[]byte("hola"), 415, "unsupported_audio"},
	} {
		rec := post(h, "u2", tc.body)
		if rec.Code != tc.code || !strings.Contains(rec.Body.String(), tc.want) {
			t.Errorf("%s: %d %s", name, rec.Code, rec.Body)
		}
	}
	if ft.calls != 1 {
		t.Fatalf("invalid audio reached the provider: %d calls", ft.calls)
	}

	// Daily quota per user (20 s) and global (30 s).
	if rec := post(h, "u1", wav(16000, 16*time.Second, 6000)); rec.Code != 429 || !strings.Contains(rec.Body.String(), "speech_quota") {
		t.Fatalf("user quota: %d %s", rec.Code, rec.Body)
	}
	if rec := post(h, "u3", wav(16000, 13*time.Second, 6000)); rec.Code != 200 { // global 5+14 = 19 s
		t.Fatalf("u3: %d", rec.Code)
	}
	if rec := post(h, "u4", wav(16000, 13*time.Second, 6000)); rec.Code != 429 { // 19+14 > 30 s

		t.Fatalf("global quota: %d", rec.Code)
	}
	h.now = func() time.Time { return time.Now().Add(48 * time.Hour) }
	if rec := post(h, "u4", wav(16000, 9*time.Second, 6000)); rec.Code != 200 {
		t.Fatalf("new day: %d", rec.Code)
	}

	// Provider failures and empty speech.
	ft.err = ErrNoSpeech
	if rec := post(h, "u5", wav(16000, 2*time.Second, 6000)); rec.Code != 422 || !strings.Contains(rec.Body.String(), "speech_empty") {
		t.Fatalf("empty: %d %s", rec.Code, rec.Body)
	}
	ft.err = errors.New("boom")
	if rec := post(h, "u6", wav(16000, 2*time.Second, 6000)); rec.Code != 502 {
		t.Fatalf("failure: %d", rec.Code)
	}
}

func TestHandlerLimitsAndDisabled(t *testing.T) {
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	if rec := post(NewHandler(Disabled{}, limits(), nil, log), "u", wav(16000, 2*time.Second, 6000)); rec.Code != 503 {
		t.Fatalf("disabled: %d", rec.Code)
	}
	lim := limits()
	lim.MaxBytes = 64 << 10
	h := NewHandler(&fakeT{res: Result{Text: "x"}}, lim, nil, log)
	if rec := post(h, "u", wav(16000, 10*time.Second, 6000)); rec.Code != 413 {
		t.Fatalf("too large: %d", rec.Code)
	}
	lim = limits()
	lim.RequestsPerUserHour = 1
	lim.UserDailySeconds, lim.GlobalDailySeconds = 600, 600
	h = NewHandler(&fakeT{res: Result{Text: "x"}}, lim, nil, log)
	_ = post(h, "u", wav(16000, 2*time.Second, 6000))
	if rec := post(h, "u", wav(16000, 2*time.Second, 6000)); rec.Code != 429 || !strings.Contains(rec.Body.String(), "rate_limited") {
		t.Fatalf("rate: %d %s", rec.Code, rec.Body)
	}
	// Opus is bounded by size when the duration is not in the header.
	lim = limits()
	lim.MaxSeconds = 5
	lim.UserDailySeconds, lim.GlobalDailySeconds = 600, 600
	h = NewHandler(&fakeT{res: Result{Text: "x"}}, lim, nil, log)
	big := append([]byte{0x1A, 0x45, 0xDF, 0xA3}, make([]byte, 40<<10)...)
	if rec := post(h, "u", big); rec.Code != 413 {
		t.Fatalf("opus too long: %d", rec.Code)
	}
	mux := http.NewServeMux()
	h.Register(mux, func(n http.Handler) http.Handler { return n })
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/v1/speech/status", nil))
	if !strings.Contains(rec.Body.String(), `"enabled":true`) || !strings.Contains(rec.Body.String(), `"max_seconds":5`) {
		t.Fatalf("status: %s", rec.Body)
	}
	if (Disabled{}).Provider() != "disabled" {
		t.Fatal("disabled provider")
	}
	if _, err := (Disabled{}).Transcribe(context.Background(), Audio{}); !errors.Is(err, ErrDisabled) {
		t.Fatal("disabled transcribe")
	}
}

func TestDevEchoSaysItDidNotTranscribe(t *testing.T) {
	res, err := DevEcho{}.Transcribe(context.Background(), Audio{Duration: 2500 * time.Millisecond})
	if err != nil || !strings.Contains(res.Text, "2.5 s") || !strings.Contains(res.Text, "Sin proveedor") || (DevEcho{}).Provider() != "dev-echo" {
		t.Fatalf("dev echo: %+v %v", res, err)
	}
}
