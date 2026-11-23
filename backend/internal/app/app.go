// Package app composes modules into one HTTP handler (the modular monolith's
// single entry point). Modules never import each other; they meet here.
package app

import (
	"log/slog"
	"net/http"
	"time"

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
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/auth"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/config"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/httpserver"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/identity"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/ratelimit"
)

// Deps are the adapters the router needs.
type Deps struct {
	DB       httpserver.Pinger
	Products demo.ProductLister // demo endpoints (mock mode only)
	Kiuvy    kiuvy.Client
	Log      *slog.Logger

	Auth        auth.Resolver
	StoreRepo   stores.Repository
	ProductRepo products.Repository
	Images      products.ImageStore
	OrderRepo   orders.Repository
	AI          ai.ProductDescriptionGenerator

	// KPOP-AGENT-001. Optional: when Agent is nil the agentic routes are not mounted
	// (keeps the POC contract tests independent of PostgreSQL).
	Verifier   identity.Verifier
	Users      identity.Users
	Owners     stores.OwnerRepo
	Agent      *agent.Service
	Storefront *storefront.Repo
	CheckoutDB *orders.Repo
	Payments   payments.Gateway

	// KPOP-WOW-001: voice notes and the conversion funnel (optional).
	Speech speech.Transcriber
	Funnel funnel.Sink
}

// Cost and abuse limits for the POC (single instance, in memory).
var (
	SignupPerIPPerHour = 20
	AIPerStorePerHour  = 30
	AIGlobalPerDay     = 300
	AgentTurnsPerHour  = 120
)

// NewRouter builds the full middleware-wrapped handler.
func NewRouter(cfg config.Config, d Deps) http.Handler {
	mux := http.NewServeMux()
	httpserver.RegisterHealth(mux, d.DB)

	if cfg.MockMode { // config guarantees mock mode only exists in local/development
		demo.NewHandler(d.Products, demo.Info{
			Service:          "kiupop-api",
			Version:          cfg.Version,
			Environment:      string(cfg.Env),
			MockMode:         cfg.MockMode,
			KiuvyIntegration: d.Kiuvy.Status(),
			Message:          "Entorno de desarrollo listo.",
		}, d.Log).Register(mux)
	}

	requireAdmin := func(h http.Handler) http.Handler { return auth.RequireStoreAdmin(d.Auth, h) }
	registerUser := func(*stores.Handler) {}
	if d.Agent != nil {
		requireUser := func(h http.Handler) http.Handler { return identity.RequireUser(d.Verifier, d.Users, h) }
		requireAdmin = func(h http.Handler) http.Handler {
			return auth.RequireStoreAdminOrUser(d.Auth, d.Verifier, d.Users, d.Storefront, h)
		}
		agent.NewHandler(d.Agent, d.Log, ratelimit.New(AgentTurnsPerHour, time.Hour)).Register(mux, requireUser)
		storefront.NewHandler(d.Storefront, storefront.Links{APIBase: cfg.PublicAPIBase, WebBase: cfg.PublicWebBase}, d.Log).Register(mux)
		orders.NewCheckoutHandler(d.CheckoutDB, d.Payments, cfg.Env.AllowsSimulation(), d.Log).Register(mux)
		registerUser = func(h *stores.Handler) { h.RegisterUser(mux, d.Owners, d.Verifier.Mode(), requireUser) }
		if d.Speech != nil {
			speech.NewHandler(d.Speech, speech.Limits{MaxBytes: cfg.AudioMaxBytes, MaxSeconds: cfg.AudioMaxSeconds,
				UserDailySeconds: cfg.SpeechUserDailySeconds, GlobalDailySeconds: cfg.SpeechGlobalDailySecs,
				USDMicrosPerMinute: cfg.SpeechUSDMicrosPerMinute}, d.Funnel, d.Log).Register(mux, requireUser)
		}
		if d.Funnel != nil {
			funnel.NewHandler(d.Funnel, d.Log).Register(mux, requireUser)
		}
	}
	_, aiOff := d.AI.(ai.Disabled)

	storesH := stores.NewHandler(d.StoreRepo, d.Log, cfg.StoreSignupEnabled, stores.Features{AI: !aiOff},
		ratelimit.New(SignupPerIPPerHour, time.Hour))
	storesH.Register(mux, requireAdmin)
	registerUser(storesH)
	products.NewHandler(d.ProductRepo, d.Images, d.Log).Register(mux, requireAdmin)
	orders.NewHandler(d.OrderRepo, d.Log).Register(mux)
	ai.NewHandler(d.AI, ratelimit.New(AIPerStorePerHour, time.Hour), ratelimit.New(AIGlobalPerDay, 24*time.Hour), d.Log).
		Register(mux, requireAdmin)

	mux.HandleFunc("/", func(w http.ResponseWriter, _ *http.Request) {
		httpserver.WriteError(w, http.StatusNotFound, "not_found", "Recurso no encontrado.")
	})

	return httpserver.Chain(mux,
		httpserver.Recover(d.Log),
		httpserver.RequestLog(d.Log),
		httpserver.SecurityHeaders(),
		httpserver.CORS(cfg.CORSAllowedOrigins),
	)
}
