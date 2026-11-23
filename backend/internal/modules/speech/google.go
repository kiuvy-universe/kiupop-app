package speech

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/kiuvy-universe/kiupop/backend/internal/platform/gcp"
)

// Google calls Cloud Speech-to-Text v1 (synchronous recognize, up to 60 s) with
// the service identity. Data logging is off by default on v1; audio is sent
// inline and not stored by KiuPop.
type Google struct {
	Project  string // quota project (the isolated kiupop-demo project)
	Language string // es-CR
	Tokens   gcp.TokenSource
	Client   *http.Client
	Endpoint string // tests
}

// Provider implements Transcriber.
func (Google) Provider() string { return "google-stt-v1" }

func (g Google) endpoint() string {
	if g.Endpoint != "" {
		return strings.TrimRight(g.Endpoint, "/")
	}
	return "https://speech.googleapis.com"
}

// Phrases that matter to a store: currency, quantities and prices.
var phrases = []string{"colones", "mil colones", "₡", "precio", "cada uno", "por unidad", "docena",
	"WhatsApp", "Instagram", "catálogo", "tienda", "envío", "a domicilio"}

type recognizeReq struct {
	Config struct {
		Encoding                   string `json:"encoding"`
		SampleRateHertz            int    `json:"sampleRateHertz"`
		LanguageCode               string `json:"languageCode"`
		EnableAutomaticPunctuation bool   `json:"enableAutomaticPunctuation"`
		AudioChannelCount          int    `json:"audioChannelCount,omitempty"`
		SpeechContexts             []struct {
			Phrases []string `json:"phrases"`
			Boost   float64  `json:"boost"`
		} `json:"speechContexts"`
	} `json:"config"`
	Audio struct {
		Content string `json:"content"`
	} `json:"audio"`
}

type recognizeResp struct {
	Results []struct {
		Alternatives []struct {
			Transcript string  `json:"transcript"`
			Confidence float64 `json:"confidence"`
		} `json:"alternatives"`
		LanguageCode string `json:"languageCode"`
	} `json:"results"`
	TotalBilledTime string `json:"totalBilledTime"`
}

// Transcribe implements Transcriber.
func (g Google) Transcribe(ctx context.Context, a Audio) (Result, error) {
	var req recognizeReq
	switch a.Format {
	case "wav":
		req.Config.Encoding, req.Config.AudioChannelCount = "LINEAR16", 1
	case "webm":
		req.Config.Encoding = "WEBM_OPUS"
	case "ogg":
		req.Config.Encoding = "OGG_OPUS"
	default:
		return Result{}, ErrUnsupported
	}
	req.Config.SampleRateHertz = a.SampleRate
	req.Config.LanguageCode = g.Language
	req.Config.EnableAutomaticPunctuation = true
	req.Config.SpeechContexts = append(req.Config.SpeechContexts, struct {
		Phrases []string `json:"phrases"`
		Boost   float64  `json:"boost"`
	}{phrases, 8})
	req.Audio.Content = base64.StdEncoding.EncodeToString(a.Data)
	body, _ := json.Marshal(req)

	tok, err := g.Tokens.Token()
	if err != nil {
		return Result{}, fmt.Errorf("speech token: %w", err)
	}
	hreq, err := http.NewRequestWithContext(ctx, http.MethodPost, g.endpoint()+"/v1/speech:recognize", bytes.NewReader(body))
	if err != nil {
		return Result{}, err
	}
	hreq.Header.Set("Authorization", "Bearer "+tok.AccessToken)
	hreq.Header.Set("Content-Type", "application/json")
	hreq.Header.Set("x-goog-user-project", g.Project)
	client := g.Client
	if client == nil {
		client = &http.Client{Timeout: 35 * time.Second}
	}
	resp, err := client.Do(hreq)
	if err != nil {
		return Result{}, fmt.Errorf("speech request: %w", err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode != http.StatusOK {
		return Result{}, fmt.Errorf("speech: status %d", resp.StatusCode) // body may echo audio metadata: not logged
	}
	var out recognizeResp
	if err := json.Unmarshal(raw, &out); err != nil {
		return Result{}, fmt.Errorf("speech: bad response: %w", err)
	}
	var parts []string
	var conf float64
	lang := g.Language
	for _, r := range out.Results {
		if len(r.Alternatives) == 0 {
			continue
		}
		parts = append(parts, strings.TrimSpace(r.Alternatives[0].Transcript))
		conf += r.Alternatives[0].Confidence
		if r.LanguageCode != "" {
			lang = r.LanguageCode
		}
	}
	text := strings.TrimSpace(strings.Join(parts, " "))
	res := Result{Text: text, Provider: g.Provider(), Language: lang, BilledSeconds: billedSeconds(out.TotalBilledTime)}
	if len(parts) > 0 {
		res.Confidence = conf / float64(len(parts))
	}
	if text == "" {
		return res, ErrNoSpeech
	}
	return res, nil
}

// billedSeconds parses durations like "15s" or "3.500s".
func billedSeconds(s string) int {
	f, err := strconv.ParseFloat(strings.TrimSuffix(s, "s"), 64)
	if err != nil || f < 0 {
		return 0
	}
	return int(f + 0.999)
}
