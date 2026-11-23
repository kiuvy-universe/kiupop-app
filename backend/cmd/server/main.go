// Command server runs the KiuPop API (single binary, modular monolith).
//
//	server              start the HTTP server
//	server migrate      apply pending migrations and exit
//	server healthcheck  probe /healthz (used by the container HEALTHCHECK)
package main

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/kiuvy-universe/kiupop/backend/internal/app"
	"github.com/kiuvy-universe/kiupop/backend/internal/integrations/kiuvy"
	"github.com/kiuvy-universe/kiupop/backend/internal/integrations/payments"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/agent"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/ai"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/demo"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/funnel"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/orders"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/products"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/speech"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/storefront"
	"github.com/kiuvy-universe/kiupop/backend/internal/modules/stores"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/config"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/database"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/gcp"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/identity"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/observability"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/storage"
	"github.com/kiuvy-universe/kiupop/backend/migrations"
)

func main() {
	cmd := ""
	if len(os.Args) > 1 {
		cmd = os.Args[1]
	}
	if cmd == "healthcheck" {
		os.Exit(healthcheck())
	}

	cfg, err := config.Load()
	if err != nil {
		fmt.Fprintf(os.Stderr, "invalid configuration:\n%v\n", err)
		os.Exit(2)
	}
	log := observability.NewLogger(os.Stdout, string(cfg.Env), cfg.Version)

	if err := run(cmd, cfg, log); err != nil {
		log.Error("fatal", "err", err)
		os.Exit(1)
	}
}

func run(cmd string, cfg config.Config, log *slog.Logger) error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	pool, err := database.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer pool.Close()

	if cmd == "migrate" || cfg.MigrateOnStart {
		n, err := database.Migrate(ctx, pool, migrations.FS, log)
		if err != nil {
			return err
		}
		log.Info("migrations up to date", "applied", n)
		if cmd == "migrate" {
			return nil
		}
	}
	if cmd == "funnel-report" {
		rep, err := funnel.Summarise(ctx, pool, 24*30)
		if err != nil {
			return err
		}
		return json.NewEncoder(os.Stdout).Encode(rep)
	}
	if cmd != "" {
		return fmt.Errorf("unknown command %q", cmd)
	}
	if cfg.MockMode {
		if err := demo.SeedStore(ctx, pool); err != nil {
			return fmt.Errorf("seed demo store: %w", err)
		}
	}

	var gen ai.ProductDescriptionGenerator = ai.Disabled{}
	if cfg.AIEnabled() {
		gen = ai.NewAnthropic(ai.AnthropicConfig{APIKey: cfg.AnthropicAPIKey, Model: cfg.AnthropicModel}, log)
	} else if cfg.AIRequested {
		log.Warn("AI_ENABLED=true but ANTHROPIC_API_KEY is empty: KiuPop AI disabled")
	}

	storeRepo := stores.NewRepo(pool)

	// Kiu agent: brain + copywriter behind the ModelRouter, or the local extractor.
	var brain agent.Brain = agent.LocalBrain{}
	var copywriter agent.Copywriter = agent.NoCopy{}
	var reader agent.Reader = agent.NoReader{}
	if cfg.AIEnabled() {
		claude := agent.NewClaude(agent.ClaudeConfig{APIKey: cfg.AnthropicAPIKey,
			Router: agent.ModelRouter{Fast: cfg.AIModelFast, Smart: cfg.AIModelSmart, Premium: cfg.AIModelPremium,
				First: cfg.AIModelFirst}}, log)
		brain, copywriter, reader = claude, claude, claude
	}
	var verifier identity.Verifier = identity.Disabled{}
	switch cfg.AuthProvider {
	case "emulator":
		verifier = identity.NewEmulator(cfg.FirebaseProjectID, cfg.AuthEmulatorHost)
	case "firebase":
		verifier = identity.NewFirebase(cfg.FirebaseProjectID)
	}
	// Photos and catalogs: the local volume in development, the private bucket in the demo.
	var images products.ImageStore = products.LocalImages{Images: storage.Images{Dir: cfg.UploadDir}}
	var files agent.Files = agent.LocalFiles{Dir: cfg.UploadDir}
	var tokens gcp.TokenSource
	if cfg.StorageBackend == "gcs" || cfg.SpeechProvider == "google" {
		if tokens, err = gcp.Default(ctx); err != nil {
			return err
		}
	}
	if cfg.StorageBackend == "gcs" {
		b := storage.GCS{Bucket: cfg.GCSBucket, Tokens: tokens}
		images = storage.BucketImages{B: b}
		files = agent.BucketFiles{Images: storage.BucketImages{B: b}, Docs: storage.BucketDocs{B: b}}
	}
	var stt speech.Transcriber = speech.Disabled{}
	if cfg.SpeechProvider == "dev-echo" {
		stt = speech.DevEcho{}
	}
	if cfg.SpeechProvider == "google" {
		stt = speech.Google{Project: cfg.SpeechGoogleProject, Language: cfg.SpeechLanguage, Tokens: tokens}
	}
	funnelRec := funnel.NewRecorder(pool, cfg.FunnelSalt, log)

	sfRepo := storefront.NewRepo(pool)
	agentSvc := agent.NewService(agent.NewRepo(pool), brain, copywriter, sfRepo, agent.NewBus(), log, agent.Config{
		TestCheckout: cfg.PaymentsTestCheckout, ShareBase: cfg.PublicAPIBase, AIBudgetMicros: cfg.AISessionBudgetMicros,
		UserDailyMicros: cfg.AIUserDailyBudgetMicros, GlobalDailyMicros: cfg.AIGlobalDailyBudgetMicros,
		Discovery: cfg.KiuDiscoveryEnabled, Paywall: cfg.PaywallEnabled,
		MaxFiles: cfg.MaxAttachments, MaxFilesBytes: cfg.MaxAttachmentsBytes, Funnel: funnelRec,
	}, newUUID).WithAttachments(files, reader)
	go agentSvc.RunWorkers(ctx, cfg.AgentWorkers)

	handler := app.NewRouter(cfg, app.Deps{
		DB:          pool,
		Products:    demo.NewPostgresRepo(pool),
		Kiuvy:       kiuvy.Disabled{},
		Log:         log,
		Auth:        storeRepo,
		StoreRepo:   storeRepo,
		ProductRepo: products.NewRepo(pool),
		Images:      images,
		OrderRepo:   orders.NewRepo(pool),
		AI:          gen,
		Verifier:    verifier,
		Users: identity.NewRepo(pool).OnSignup(func(ctx context.Context, userID, provider string) {
			funnelRec.Record(ctx, userID, "", "signup_completed", map[string]int64{"provider_" + providerKey(provider): 1})
		}),
		Owners:     storeRepo,
		Agent:      agentSvc,
		Storefront: sfRepo,
		CheckoutDB: orders.NewRepo(pool),
		Payments:   payments.Mock{},
		Speech:     stt,
		Funnel:     funnelRec,
	})

	srv := &http.Server{
		Addr:              cfg.Addr(),
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		log.Info("listening", "addr", srv.Addr, "mock_mode", cfg.MockMode, "kiuvy_integration", "disabled",
			"store_signup", cfg.StoreSignupEnabled, "ai_enabled", cfg.AIEnabled(), "ai_model", cfg.AnthropicModel,
			"kiu_brain", brain.Mode(), "ai_model_first", cfg.AIModelFirst, "auth", verifier.Mode(), "test_checkout", cfg.PaymentsTestCheckout, "paywall", cfg.PaywallEnabled,
			"speech", stt.Provider(), "storage", cfg.StorageBackend)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
		close(errCh)
	}()

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
	}

	log.Info("shutting down")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
	defer cancel()
	return srv.Shutdown(shutdownCtx)
}

func healthcheck() int {
	port := os.Getenv("API_PORT")
	if port == "" {
		port = "8080"
	}
	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get("http://127.0.0.1:" + port + "/healthz")
	if err != nil {
		return 1
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return 1
	}
	return 0
}

func newUUID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:])
}

// providerKey maps a Firebase sign-in provider to a funnel meta key.
func providerKey(p string) string {
	switch p {
	case "google.com":
		return "google"
	case "facebook.com":
		return "facebook"
	case "password":
		return "email"
	}
	return "other"
}
