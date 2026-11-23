package config

import (
	"strings"
	"testing"
)

func lookupFrom(m map[string]string) func(string) (string, bool) {
	return func(k string) (string, bool) { v, ok := m[k]; return v, ok }
}

func base() map[string]string {
	return map[string]string{"DATABASE_URL": "postgres://u:p@localhost:5433/db", "APP_ENV": "local"}
}

func TestLoadDefaults(t *testing.T) {
	cfg, err := LoadFrom(lookupFrom(base()))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.Env != EnvLocal || cfg.Port != 8080 || cfg.Host != "127.0.0.1" {
		t.Fatalf("unexpected defaults: %+v", cfg)
	}
	if !cfg.MigrateOnStart {
		t.Fatal("local env should migrate on start by default")
	}
	if len(cfg.CORSAllowedOrigins) != 2 {
		t.Fatalf("default origins: %v", cfg.CORSAllowedOrigins)
	}
}

func TestMockModeFailsClosedOutsideDev(t *testing.T) {
	for _, env := range []string{"staging", "production"} {
		m := base()
		m["APP_ENV"] = env
		m["MOCK_MODE"] = "true"
		if _, err := LoadFrom(lookupFrom(m)); err == nil || !strings.Contains(err.Error(), "MOCK_MODE") {
			t.Fatalf("%s: expected MOCK_MODE rejection, got %v", env, err)
		}
	}
	m := base()
	m["APP_ENV"] = "development"
	m["MOCK_MODE"] = "true"
	if _, err := LoadFrom(lookupFrom(m)); err != nil {
		t.Fatalf("development should allow mock mode: %v", err)
	}
}

func TestKiuvyIntegrationRefused(t *testing.T) {
	m := base()
	m["KIUVY_INTEGRATION_ENABLED"] = "true"
	if _, err := LoadFrom(lookupFrom(m)); err == nil {
		t.Fatal("expected integration to be refused")
	}
}

func TestRejectsBadInput(t *testing.T) {
	cases := map[string]map[string]string{
		"missing db":    {},
		"wildcard cors": {"DATABASE_URL": "x", "CORS_ALLOWED_ORIGINS": "*"},
		"path in cors":  {"DATABASE_URL": "x", "CORS_ALLOWED_ORIGINS": "http://localhost:3000/app"},
		"bad port":      {"DATABASE_URL": "x", "API_PORT": "99999"},
		"bad env":       {"DATABASE_URL": "x", "APP_ENV": "prod"},
		"bad bool":      {"DATABASE_URL": "x", "MOCK_MODE": "yes please"},
	}
	for name, m := range cases {
		if _, err := LoadFrom(lookupFrom(m)); err == nil {
			t.Errorf("%s: expected error", name)
		}
	}
}

func TestSignupFailsClosedOutsideDev(t *testing.T) {
	m := base()
	m["APP_ENV"] = "production"
	m["STORE_SIGNUP_ENABLED"] = "true"
	if _, err := LoadFrom(lookupFrom(m)); err == nil {
		t.Fatal("anonymous signup must be refused in production")
	}
	m = base()
	m["APP_ENV"] = "production"
	cfg, err := LoadFrom(lookupFrom(m))
	if err != nil || cfg.StoreSignupEnabled {
		t.Fatalf("production default must disable signup: %v %+v", err, cfg)
	}
}

func TestAIEnabledNeedsKeyAndStringHidesIt(t *testing.T) {
	m := base()
	m["AI_ENABLED"] = "true"
	cfg, _ := LoadFrom(lookupFrom(m))
	if cfg.AIEnabled() {
		t.Fatal("AI must be disabled without a key")
	}
	m["ANTHROPIC_API_KEY"] = "sk-ant-test-SECRET"
	cfg, _ = LoadFrom(lookupFrom(m))
	if !cfg.AIEnabled() || cfg.AnthropicModel != "claude-opus-5-5" {
		t.Fatalf("unexpected: %v", cfg)
	}
	if strings.Contains(cfg.String(), "SECRET") {
		t.Fatal("String() leaks the API key")
	}
}

func TestAgentSettingsFailClosedOutsideDev(t *testing.T) {
	base := map[string]string{"DATABASE_URL": "postgres://x", "APP_ENV": "production"}
	for name, extra := range map[string]map[string]string{
		"emulator auth in production": {"AUTH_PROVIDER": "emulator", "FIREBASE_AUTH_EMULATOR_HOST": "x:1"},
		"test checkout in production": {"PAYMENTS_TEST_CHECKOUT": "true"},
		"demo project with firebase":  {"AUTH_PROVIDER": "firebase", "FIREBASE_PROJECT_ID": "demo-kiupop"},
	} {
		env := map[string]string{"STORE_SIGNUP_ENABLED": "false"}
		for k, v := range base {
			env[k] = v
		}
		for k, v := range extra {
			env[k] = v
		}
		if _, err := LoadFrom(func(k string) (string, bool) { v, ok := env[k]; return v, ok }); err == nil {
			t.Errorf("%s: expected a configuration error", name)
		}
	}
}

func TestAppEnvIsRequired(t *testing.T) {
	if _, err := LoadFrom(lookupFrom(map[string]string{"DATABASE_URL": "postgres://x"})); err == nil || !strings.Contains(err.Error(), "APP_ENV") {
		t.Fatalf("missing APP_ENV must fail: %v", err)
	}
}

func TestEmulatorRefusesPublicHost(t *testing.T) {
	m := base()
	m["AUTH_PROVIDER"], m["FIREBASE_AUTH_EMULATOR_HOST"], m["PUBLIC_API_BASE"] = "emulator", "x:1", "https://kiupop.example"
	if _, err := LoadFrom(lookupFrom(m)); err == nil {
		t.Fatal("emulator on a public host must fail")
	}
}

func TestPaywallDefaultsOnAndFailsClosed(t *testing.T) {
	cfg, err := LoadFrom(lookupFrom(base()))
	if err != nil || !cfg.PaywallEnabled {
		t.Fatalf("paywall must default on: %v %v", cfg.PaywallEnabled, err)
	}
	m := base()
	m["PAYWALL_ENABLED"] = "false"
	if cfg, err := LoadFrom(lookupFrom(m)); err != nil || cfg.PaywallEnabled {
		t.Fatalf("PAYWALL_ENABLED=false must turn it off: %v", err)
	}
	m["PAYWALL_ENABLED"] = "maybe"
	if _, err := LoadFrom(lookupFrom(m)); err == nil {
		t.Fatal("an invalid PAYWALL_ENABLED must fail startup, not open publication")
	}
}
