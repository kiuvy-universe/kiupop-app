// Package config loads and validates runtime configuration from the environment.
//
// Unsafe development features (mock mode, demo endpoints) fail closed: they are
// rejected at startup when APP_ENV is anything other than "local" or "development".
// APP_ENV=demo is a public, isolated showcase: real identity (Firebase), no mock
// mode, no emulator, and only simulated payments (test gateway).
package config

import (
	"errors"
	"fmt"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

// Env is the deployment environment name.
type Env string

const (
	EnvLocal       Env = "local"
	EnvDevelopment Env = "development"
	EnvStaging     Env = "staging"
	EnvProduction  Env = "production"
	// EnvDemo is the public KiuPop demo: isolated from Kiuvy, simulated payments only.
	EnvDemo Env = "demo"
)

// IsDev reports whether the environment allows development-only features.
func (e Env) IsDev() bool { return e == EnvLocal || e == EnvDevelopment }

// AllowsSimulation reports whether simulated (test-gateway) payments may be
// offered: development, or the isolated public demo. Never staging/production.
func (e Env) AllowsSimulation() bool { return e.IsDev() || e == EnvDemo }

// Config is the validated application configuration.
type Config struct {
	Env                     Env
	Host                    string
	Port                    int
	DatabaseURL             string
	MockMode                bool
	KiuvyIntegrationEnabled bool
	CORSAllowedOrigins      []string
	MigrateOnStart          bool
	ShutdownTimeout         time.Duration
	Version                 string

	// StoreSignupEnabled allows anonymous store creation (POC credential model).
	// Only permitted in local/development until real identity + abuse controls exist.
	StoreSignupEnabled bool
	// UploadDir is where product images are stored (a Docker volume in Compose).
	UploadDir string

	// AI (KiuPop AI). The key is never logged; see String().
	AIRequested     bool
	AnthropicAPIKey string
	AnthropicModel  string
	// ModelRouter tiers for Kiu (fast extraction/copy, smart understanding, premium escalation).
	AIModelFast, AIModelSmart, AIModelPremium string
	// AIModelFirst understands the business on the first turn (demo: Opus).
	AIModelFirst              string
	AISessionBudgetMicros     int64
	AIUserDailyBudgetMicros   int64
	AIGlobalDailyBudgetMicros int64

	// Identity (KiuPop-dedicated provider, never Kiuvy's).
	AuthProvider        string // disabled | emulator | firebase
	FirebaseProjectID   string
	AuthEmulatorHost    string
	FacebookAuthEnabled bool

	// Public origins for share links and Open Graph pages.
	PublicAPIBase string
	PublicWebBase string

	// PaymentsTestCheckout offers the mock (test-mode) checkout. Dev only.
	PaymentsTestCheckout bool
	AgentWorkers         int
	// KiuDiscoveryEnabled: Kiu diagnoses the need and proposes a plan before
	// building (default on). false restores the original flow.
	KiuDiscoveryEnabled bool
	// PaywallEnabled: publishing a store needs an active US$5/month plan
	// (quiz funnel paywall, test mode only). Default on; an invalid value
	// fails startup instead of silently opening publication.
	PaywallEnabled bool

	// Speech-to-text (KPOP-WOW-001). Provider: disabled | google. Audio is never
	// stored; only metrics (duration, latency, billed seconds) are logged.
	SpeechProvider           string
	SpeechLanguage           string
	SpeechGoogleProject      string // quota/billing project for Speech-to-Text
	AudioMaxBytes            int64
	AudioMaxSeconds          int
	SpeechUserDailySeconds   int
	SpeechGlobalDailySecs    int
	SpeechUSDMicrosPerMinute int64

	// Storage backend for photos and catalogs: local (UPLOAD_DIR) | gcs (private bucket).
	StorageBackend string
	GCSBucket      string

	// Attachment limits per session (provisional, configurable).
	MaxAttachments      int
	MaxAttachmentsBytes int64

	// FunnelSalt pseudonymises user ids in funnel analytics (HMAC). Required in demo.
	FunnelSalt string
}

// AIEnabled reports whether real AI calls can be made (flag on AND key present).
func (c Config) AIEnabled() bool { return c.AIRequested && c.AnthropicAPIKey != "" }

// String never includes secrets, so accidental %v logging is safe.
func (c Config) String() string {
	return fmt.Sprintf("Config{env=%s addr=%s mock=%t signup=%t ai=%t model=%s auth=%s}",
		c.Env, c.Addr(), c.MockMode, c.StoreSignupEnabled, c.AIEnabled(), c.AnthropicModel, c.AuthProvider)
}

// Addr returns the listen address.
func (c Config) Addr() string { return fmt.Sprintf("%s:%d", c.Host, c.Port) }

// Load reads configuration from the process environment.
func Load() (Config, error) { return LoadFrom(os.LookupEnv) }

// LoadFrom reads configuration through lookup (injectable for tests).
func LoadFrom(lookup func(string) (string, bool)) (Config, error) {
	get := func(key, def string) string {
		if v, ok := lookup(key); ok && strings.TrimSpace(v) != "" {
			return strings.TrimSpace(v)
		}
		return def
	}
	var errs []error
	parseBool := func(key string, def bool) bool {
		raw := get(key, strconv.FormatBool(def))
		b, err := strconv.ParseBool(raw)
		if err != nil {
			errs = append(errs, fmt.Errorf("%s: invalid boolean %q", key, raw))
			return def
		}
		return b
	}

	cfg := Config{
		Env:             Env(strings.ToLower(get("APP_ENV", ""))),
		Host:            get("API_HOST", "127.0.0.1"),
		DatabaseURL:     get("DATABASE_URL", ""),
		ShutdownTimeout: 10 * time.Second,
		Version:         get("APP_VERSION", "dev"),
	}

	switch cfg.Env {
	case EnvLocal, EnvDevelopment, EnvStaging, EnvProduction, EnvDemo:
	case "":
		// Required: a deploy that forgets it must not silently get dev-only features.
		errs = append(errs, errors.New("APP_ENV: required (local | development | demo | staging | production)"))
	default:
		errs = append(errs, fmt.Errorf("APP_ENV: unknown environment %q", cfg.Env))
	}

	port, err := strconv.Atoi(get("API_PORT", "8080"))
	if err != nil || port < 1 || port > 65535 {
		errs = append(errs, fmt.Errorf("API_PORT: invalid port %q", get("API_PORT", "")))
	}
	cfg.Port = port

	if cfg.DatabaseURL == "" {
		errs = append(errs, errors.New("DATABASE_URL: required"))
	}

	cfg.MockMode = parseBool("MOCK_MODE", false)
	cfg.KiuvyIntegrationEnabled = parseBool("KIUVY_INTEGRATION_ENABLED", false)
	cfg.MigrateOnStart = parseBool("MIGRATE_ON_START", cfg.Env.IsDev())

	cfg.StoreSignupEnabled = parseBool("STORE_SIGNUP_ENABLED", cfg.Env.IsDev())
	if cfg.StoreSignupEnabled && !cfg.Env.IsDev() {
		errs = append(errs, fmt.Errorf("STORE_SIGNUP_ENABLED=true is not allowed when APP_ENV=%s (needs identity + abuse controls)", cfg.Env))
	}
	cfg.UploadDir = get("UPLOAD_DIR", "./data/uploads")
	cfg.AIRequested = parseBool("AI_ENABLED", false)
	cfg.AnthropicAPIKey = get("ANTHROPIC_API_KEY", "")
	cfg.AnthropicModel = get("ANTHROPIC_MODEL", "claude-opus-5-5")

	cfg.AIModelFast = get("AI_MODEL_FAST", "claude-haiku-5-5")
	cfg.AIModelSmart = get("AI_MODEL_SMART", "claude-sonnet-5-5")
	cfg.AIModelPremium = get("AI_MODEL_PREMIUM", "claude-opus-5-5")
	cfg.AIModelFirst = get("AI_MODEL_FIRST", cfg.AIModelSmart)
	if b, err := strconv.ParseInt(get("AI_SESSION_BUDGET_MICROS", "60000"), 10, 64); err != nil || b < 0 {
		errs = append(errs, errors.New("AI_SESSION_BUDGET_MICROS: invalid integer"))
	} else {
		cfg.AISessionBudgetMicros = b
	}

	for _, b := range []struct {
		key string
		def string
		dst *int64
	}{{"AI_USER_DAILY_BUDGET_MICROS", "300000", &cfg.AIUserDailyBudgetMicros}, {"AI_GLOBAL_DAILY_BUDGET_MICROS", "5000000", &cfg.AIGlobalDailyBudgetMicros}} {
		v, err := strconv.ParseInt(get(b.key, b.def), 10, 64)
		if err != nil || v < 0 {
			errs = append(errs, fmt.Errorf("%s: invalid integer", b.key))
		}
		*b.dst = v
	}

	cfg.AuthProvider = strings.ToLower(get("AUTH_PROVIDER", "disabled"))
	cfg.FirebaseProjectID = get("FIREBASE_PROJECT_ID", "demo-kiupop")
	cfg.AuthEmulatorHost = get("FIREBASE_AUTH_EMULATOR_HOST", "")
	cfg.FacebookAuthEnabled = parseBool("FACEBOOK_AUTH_ENABLED", false)
	switch cfg.AuthProvider {
	case "disabled", "firebase":
	case "emulator":
		if !cfg.Env.IsDev() {
			errs = append(errs, fmt.Errorf("AUTH_PROVIDER=emulator is not allowed when APP_ENV=%s (unsigned tokens)", cfg.Env))
		}
		if cfg.AuthEmulatorHost == "" {
			errs = append(errs, errors.New("AUTH_PROVIDER=emulator requires FIREBASE_AUTH_EMULATOR_HOST"))
		}
	default:
		errs = append(errs, fmt.Errorf("AUTH_PROVIDER: unknown provider %q", cfg.AuthProvider))
	}
	if cfg.AuthProvider == "emulator" && !isLoopbackURL(cfg.PublicAPIBaseRaw(get)) {
		errs = append(errs, errors.New("AUTH_PROVIDER=emulator only runs on a local stack (PUBLIC_API_BASE must be localhost)"))
	}
	if cfg.AuthProvider == "firebase" && strings.HasPrefix(cfg.FirebaseProjectID, "demo-") {
		errs = append(errs, errors.New("AUTH_PROVIDER=firebase needs a real KiuPop Firebase project (not demo-*)"))
	}

	cfg.PublicAPIBase = strings.TrimRight(get("PUBLIC_API_BASE", "http://localhost:8080"), "/")
	cfg.PublicWebBase = strings.TrimRight(get("PUBLIC_WEB_BASE", "http://localhost:3000"), "/")
	cfg.PaymentsTestCheckout = parseBool("PAYMENTS_TEST_CHECKOUT", cfg.Env.AllowsSimulation())
	if cfg.PaymentsTestCheckout && !cfg.Env.AllowsSimulation() {
		errs = append(errs, fmt.Errorf("PAYMENTS_TEST_CHECKOUT=true is not allowed when APP_ENV=%s", cfg.Env))
	}
	cfg.KiuDiscoveryEnabled = parseBool("KIU_DISCOVERY_ENABLED", true)
	cfg.PaywallEnabled = parseBool("PAYWALL_ENABLED", true)
	if n, err := strconv.Atoi(get("AGENT_WORKERS", "4")); err != nil || n < 1 || n > 32 {
		errs = append(errs, errors.New("AGENT_WORKERS: must be 1..32"))
	} else {
		cfg.AgentWorkers = n
	}

	cfg.SpeechProvider = strings.ToLower(get("SPEECH_PROVIDER", "disabled"))
	cfg.SpeechLanguage = get("SPEECH_LANGUAGE", "es-CR")
	cfg.SpeechGoogleProject = get("SPEECH_GOOGLE_PROJECT", "")
	switch cfg.SpeechProvider {
	case "disabled":
	case "dev-echo":
		if !cfg.Env.IsDev() {
			errs = append(errs, fmt.Errorf("SPEECH_PROVIDER=dev-echo is only for local/development (APP_ENV=%s)", cfg.Env))
		}
	case "google":
		if cfg.SpeechGoogleProject == "" {
			errs = append(errs, errors.New("SPEECH_PROVIDER=google requires SPEECH_GOOGLE_PROJECT"))
		}
	default:
		errs = append(errs, fmt.Errorf("SPEECH_PROVIDER: unknown provider %q", cfg.SpeechProvider))
	}
	for _, n := range []struct {
		key      string
		def, min int64
		max      int64
		dst      func(int64)
	}{
		{"AUDIO_MAX_BYTES", 4 << 20, 64 << 10, 10 << 20, func(v int64) { cfg.AudioMaxBytes = v }},
		{"AUDIO_MAX_SECONDS", 60, 5, 60, func(v int64) { cfg.AudioMaxSeconds = int(v) }},
		{"SPEECH_USER_DAILY_SECONDS", 600, 0, 86400, func(v int64) { cfg.SpeechUserDailySeconds = int(v) }},
		{"SPEECH_GLOBAL_DAILY_SECONDS", 3600, 0, 864000, func(v int64) { cfg.SpeechGlobalDailySecs = int(v) }},
		{"SPEECH_USD_MICROS_PER_MINUTE", 24000, 0, 10_000_000, func(v int64) { cfg.SpeechUSDMicrosPerMinute = v }},
		{"MAX_ATTACHMENTS", 5, 1, 20, func(v int64) { cfg.MaxAttachments = int(v) }},
		{"MAX_ATTACHMENTS_BYTES", 50 << 20, 1 << 20, 200 << 20, func(v int64) { cfg.MaxAttachmentsBytes = v }},
	} {
		raw := get(n.key, strconv.FormatInt(n.def, 10))
		v, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || v < n.min || v > n.max {
			errs = append(errs, fmt.Errorf("%s: must be %d..%d", n.key, n.min, n.max))
			v = n.def
		}
		n.dst(v)
	}
	cfg.StorageBackend = strings.ToLower(get("STORAGE_BACKEND", "local"))
	cfg.GCSBucket = get("GCS_BUCKET", "")
	switch cfg.StorageBackend {
	case "local":
	case "gcs":
		if cfg.GCSBucket == "" {
			errs = append(errs, errors.New("STORAGE_BACKEND=gcs requires GCS_BUCKET"))
		}
	default:
		errs = append(errs, fmt.Errorf("STORAGE_BACKEND: unknown backend %q", cfg.StorageBackend))
	}
	cfg.FunnelSalt = get("FUNNEL_SALT", "")

	// The public demo is real-identity, isolated and simulated-payments only.
	if cfg.Env == EnvDemo {
		if cfg.AuthProvider != "firebase" {
			errs = append(errs, errors.New("APP_ENV=demo requires AUTH_PROVIDER=firebase (real KiuPop identity)"))
		}
		if len(cfg.FunnelSalt) < 32 {
			errs = append(errs, errors.New("APP_ENV=demo requires FUNNEL_SALT (32+ chars) to pseudonymise analytics"))
		}
		if cfg.StorageBackend != "gcs" {
			errs = append(errs, errors.New("APP_ENV=demo requires STORAGE_BACKEND=gcs (instances are ephemeral)"))
		}
	}
	if cfg.FunnelSalt == "" && cfg.Env.IsDev() {
		cfg.FunnelSalt = "kiupop-local-development-salt-not-secret"
	}

	// Fail closed: simulation only exists in local/development (and the demo, via the test gateway).
	if cfg.MockMode && !cfg.Env.IsDev() {
		errs = append(errs, fmt.Errorf("MOCK_MODE=true is not allowed when APP_ENV=%s", cfg.Env))
	}
	// No Kiuvy adapter exists yet; refuse to pretend one is enabled.
	if cfg.KiuvyIntegrationEnabled {
		errs = append(errs, errors.New("KIUVY_INTEGRATION_ENABLED=true: no Kiuvy adapter is available in this phase"))
	}

	origins, oerr := parseOrigins(get("CORS_ALLOWED_ORIGINS", "http://localhost:3000,http://127.0.0.1:3000"))
	if oerr != nil {
		errs = append(errs, oerr)
	}
	cfg.CORSAllowedOrigins = origins

	return cfg, errors.Join(errs...)
}

func parseOrigins(raw string) ([]string, error) {
	var out []string
	for _, o := range strings.Split(raw, ",") {
		o = strings.TrimRight(strings.TrimSpace(o), "/")
		if o == "" {
			continue
		}
		if o == "*" {
			return nil, errors.New("CORS_ALLOWED_ORIGINS: wildcard '*' is not allowed; list explicit origins")
		}
		u, err := url.Parse(o)
		if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" || u.Path != "" {
			return nil, fmt.Errorf("CORS_ALLOWED_ORIGINS: invalid origin %q", o)
		}
		out = append(out, o)
	}
	return out, nil
}

// PublicAPIBaseRaw reads PUBLIC_API_BASE before it is normalised (used by early checks).
func (c Config) PublicAPIBaseRaw(get func(string, string) string) string {
	return get("PUBLIC_API_BASE", "http://localhost:8080")
}

func isLoopbackURL(raw string) bool {
	u, err := url.Parse(raw)
	if err != nil {
		return false
	}
	h := u.Hostname()
	return h == "localhost" || h == "127.0.0.1" || h == "::1"
}
