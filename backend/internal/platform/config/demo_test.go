package config

import (
	"strings"
	"testing"
)

func demoEnv() map[string]string {
	return map[string]string{
		"DATABASE_URL": "postgres://u:p@db.example/kiupop", "APP_ENV": "demo",
		"AUTH_PROVIDER": "firebase", "FIREBASE_PROJECT_ID": "kiupop-demo",
		"STORAGE_BACKEND": "gcs", "GCS_BUCKET": "kiupop-demo-files",
		"SPEECH_PROVIDER": "google", "SPEECH_GOOGLE_PROJECT": "kiupop-demo",
		"FUNNEL_SALT":     strings.Repeat("s", 40),
		"PUBLIC_API_BASE": "https://api.example", "CORS_ALLOWED_ORIGINS": "https://kiupop-demo.web.app",
	}
}

func TestDemoIsIsolatedAndSimulatedOnly(t *testing.T) {
	cfg, err := LoadFrom(lookupFrom(demoEnv()))
	if err != nil {
		t.Fatal(err)
	}
	if !cfg.PaymentsTestCheckout || !cfg.Env.AllowsSimulation() || cfg.Env.IsDev() || cfg.MigrateOnStart {
		t.Fatalf("demo: %+v", cfg)
	}
	if cfg.SpeechLanguage != "es-CR" || cfg.AudioMaxSeconds != 60 || cfg.MaxAttachments != 5 || cfg.MaxAttachmentsBytes != 50<<20 {
		t.Fatalf("defaults: %+v", cfg)
	}
	for _, env := range []Env{EnvStaging, EnvProduction} {
		if env.AllowsSimulation() {
			t.Fatalf("%s must never simulate payments", env)
		}
	}
	for name, mutate := range map[string]func(map[string]string){
		"mock mode": func(m map[string]string) { m["MOCK_MODE"] = "true" },
		"emulator": func(m map[string]string) {
			m["AUTH_PROVIDER"] = "emulator"
			m["FIREBASE_AUTH_EMULATOR_HOST"] = "localhost:9099"
		},
		"no auth":         func(m map[string]string) { m["AUTH_PROVIDER"] = "disabled" },
		"demo project id": func(m map[string]string) { m["FIREBASE_PROJECT_ID"] = "demo-kiupop" },
		"local disk":      func(m map[string]string) { m["STORAGE_BACKEND"] = "local" },
		"no salt":         func(m map[string]string) { delete(m, "FUNNEL_SALT") },
		"kiuvy":           func(m map[string]string) { m["KIUVY_INTEGRATION_ENABLED"] = "true" },
		"anon signup":     func(m map[string]string) { m["STORE_SIGNUP_ENABLED"] = "true" },
		"cors wildcard":   func(m map[string]string) { m["CORS_ALLOWED_ORIGINS"] = "*" },
		"dev echo speech": func(m map[string]string) { m["SPEECH_PROVIDER"] = "dev-echo" },
	} {
		m := demoEnv()
		mutate(m)
		if _, err := LoadFrom(lookupFrom(m)); err == nil {
			t.Errorf("%s: demo must refuse to start", name)
		}
	}
}

func TestSpeechStorageAndLimitValidation(t *testing.T) {
	for name, kv := range map[string][2]string{
		"unknown speech":   {"SPEECH_PROVIDER", "whisper-local"},
		"google no proj":   {"SPEECH_PROVIDER", "google"},
		"unknown storage":  {"STORAGE_BACKEND", "s3"},
		"gcs no bucket":    {"STORAGE_BACKEND", "gcs"},
		"audio too long":   {"AUDIO_MAX_SECONDS", "600"},
		"bad bytes":        {"AUDIO_MAX_BYTES", "lots"},
		"too many files":   {"MAX_ATTACHMENTS", "500"},
		"bad env":          {"APP_ENV", "prod"},
		"negative minutes": {"SPEECH_USD_MICROS_PER_MINUTE", "-1"},
	} {
		m := base()
		m[kv[0]] = kv[1]
		if _, err := LoadFrom(lookupFrom(m)); err == nil {
			t.Errorf("%s: accepted %s=%s", name, kv[0], kv[1])
		}
	}
	m := base()
	m["MAX_ATTACHMENTS"], m["MAX_ATTACHMENTS_BYTES"] = "3", "2097152"
	cfg, err := LoadFrom(lookupFrom(m))
	if err != nil || cfg.MaxAttachments != 3 || cfg.MaxAttachmentsBytes != 2<<20 || cfg.FunnelSalt == "" {
		t.Fatalf("limits: %+v %v", cfg, err)
	}
	m["PAYMENTS_TEST_CHECKOUT"], m["APP_ENV"] = "true", "production"
	if _, err := LoadFrom(lookupFrom(m)); err == nil || !strings.Contains(err.Error(), "PAYMENTS_TEST_CHECKOUT") {
		t.Fatalf("production test checkout: %v", err)
	}
}
