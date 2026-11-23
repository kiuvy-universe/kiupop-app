package orders

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/kiuvy-universe/kiupop/backend/internal/integrations/payments"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/httpserver"
	"github.com/kiuvy-universe/kiupop/backend/internal/platform/ratelimit"
)

func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// CheckoutRequest is a cart plus a client idempotency key. No prices.
type CheckoutRequest struct {
	Items          []Item `json:"items"`
	IdempotencyKey string `json:"idempotency_key"`
}

// Payment is the public view of a payment request.
type Payment struct {
	ID          string `json:"id"`
	Status      string `json:"status"` // pending | test_approved | test_declined | expired
	Mode        string `json:"mode"`   // test
	Gateway     string `json:"gateway"`
	AmountMinor int64  `json:"amount_minor"`
	Currency    string `json:"currency"`
	Lines       []Line `json:"lines"`
	Notice      string `json:"notice"`
}

const testNotice = "Pago de prueba: no se cobra dinero real. Los pagos reales se activan cuando el comercio conecte un proveedor autorizado."

// CheckoutHandler serves the test-mode checkout.
type CheckoutHandler struct {
	limit    *ratelimit.Limiter
	repo     *Repo
	gateway  payments.Gateway
	simulate bool // only in APP_ENV=local|development
	log      *slog.Logger
}

// NewCheckoutHandler builds the handler.
func NewCheckoutHandler(repo *Repo, gw payments.Gateway, allowSimulation bool, log *slog.Logger) *CheckoutHandler {
	return &CheckoutHandler{repo: repo, gateway: gw, simulate: allowSimulation && gw.Mode() == "test", log: log,
		limit: ratelimit.New(30, time.Hour)}
}

// Register mounts routes.
func (h *CheckoutHandler) Register(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/public/stores/{slug}/checkout", h.create)
	mux.HandleFunc("GET /api/v1/public/payments/{id}", h.get)
	mux.HandleFunc("POST /api/v1/public/payments/{id}/test-outcome", h.outcome)
}

func (h *CheckoutHandler) create(w http.ResponseWriter, r *http.Request) {
	var req CheckoutRequest
	if !httpserver.DecodeJSON(w, r, &req) {
		return
	}
	if n := len(req.IdempotencyKey); n < 8 || n > 64 {
		httpserver.WriteValidation(w, map[string]string{"idempotency_key": "Falta la clave de idempotencia."})
		return
	}
	if !h.limit.Allow(clientIP(r)) {
		httpserver.WriteError(w, http.StatusTooManyRequests, "rate_limited", "Demasiados intentos de pago. Esperá un momento.")
		return
	}
	items, lerr := Normalize(Request{Items: req.Items})
	if lerr != nil {
		httpserver.WriteJSON(w, http.StatusUnprocessableEntity, lineErrorBody{Error: *lerr})
		return
	}
	ids := make([]string, len(items))
	for i, it := range items {
		ids[i] = it.ProductID
	}
	store, stored, err := h.repo.Load(r.Context(), r.PathValue("slug"), ids)
	if errors.Is(err, ErrStoreNotFound) {
		httpserver.WriteError(w, http.StatusNotFound, "store_not_found", "No encontramos esta tienda.")
		return
	}
	if err != nil {
		h.internal(w, r, err)
		return
	}
	mode, storeID, err := h.repo.CheckoutMode(r.Context(), store.Slug)
	if err != nil {
		h.internal(w, r, err)
		return
	}
	// Idempotency is scoped to the store: a key from another store is a conflict, never a leak.
	if p, owner, err := h.repo.PaymentByKey(r.Context(), req.IdempotencyKey); err == nil {
		if owner != storeID {
			httpserver.WriteError(w, http.StatusConflict, "idempotency_conflict", "Esa clave de pago ya se usó.")
			return
		}
		httpserver.WriteJSON(w, http.StatusOK, p) // retry of the same checkout
		return
	}
	if mode != "test" {
		httpserver.WriteError(w, http.StatusConflict, "checkout_disabled", "Esta tienda recibe pedidos por WhatsApp; todavía no tiene pagos en línea.")
		return
	}
	p, lerr := Build(store, items, stored)
	if lerr != nil {
		httpserver.WriteJSON(w, http.StatusUnprocessableEntity, lineErrorBody{Error: *lerr})
		return
	}
	pay, err := h.repo.CreatePayment(r.Context(), storeID, h.gateway, p, req.IdempotencyKey)
	if err != nil {
		h.internal(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusCreated, pay)
}

func (h *CheckoutHandler) get(w http.ResponseWriter, r *http.Request) {
	p, err := h.repo.Payment(r.Context(), r.PathValue("id"))
	if errors.Is(err, pgx.ErrNoRows) || errors.Is(err, errBadID) {
		httpserver.WriteError(w, http.StatusNotFound, "payment_not_found", "No encontramos ese pago.")
		return
	}
	if err != nil {
		h.internal(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, p)
}

func (h *CheckoutHandler) outcome(w http.ResponseWriter, r *http.Request) {
	if !h.simulate {
		httpserver.WriteError(w, http.StatusForbidden, "simulation_disabled", "La simulación de pagos no está disponible en este entorno.")
		return
	}
	var in struct {
		Outcome string `json:"outcome"`
	}
	if !httpserver.DecodeJSON(w, r, &in) {
		return
	}
	p, err := h.repo.Payment(r.Context(), r.PathValue("id"))
	if err != nil {
		httpserver.WriteError(w, http.StatusNotFound, "payment_not_found", "No encontramos ese pago.")
		return
	}
	if p.Status != "pending" {
		httpserver.WriteJSON(w, http.StatusOK, p) // idempotent: a payment settles once
		return
	}
	st, err := h.gateway.Simulate(r.Context(), "mock_"+p.ID, in.Outcome)
	if err != nil {
		httpserver.WriteValidation(w, map[string]string{"outcome": "Usá approved o declined."})
		return
	}
	if p, err = h.repo.SetPaymentStatus(r.Context(), p.ID, st); err != nil {
		h.internal(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, p)
}

func (h *CheckoutHandler) internal(w http.ResponseWriter, r *http.Request, err error) {
	h.log.ErrorContext(r.Context(), "checkout", "err", err)
	httpserver.WriteError(w, http.StatusInternalServerError, "internal_error", "Ocurrió un error inesperado. Intenta de nuevo.")
}

var errBadID = errors.New("bad id")

// CheckoutMode returns the store's checkout mode from its published profile.
func (r *Repo) CheckoutMode(ctx context.Context, slug string) (string, string, error) {
	var mode, id string
	err := r.pool.QueryRow(ctx, `SELECT coalesce(profile->'payments'->>'checkout', 'none'), id::text FROM stores
		WHERE slug = $1 AND status = 'published'`, slug).Scan(&mode, &id)
	return mode, id, err
}

// CreatePayment asks the gateway and records the request (amounts from Build only).
func (r *Repo) CreatePayment(ctx context.Context, storeID string, gw payments.Gateway, p Preview, key string) (Payment, error) {
	var id string
	if err := r.pool.QueryRow(ctx, `SELECT gen_random_uuid()::text`).Scan(&id); err != nil {
		return Payment{}, err
	}
	if _, err := gw.Create(ctx, payments.Request{PaymentID: id, StoreID: storeID, AmountMinor: p.TotalMinor, Currency: p.Currency}); err != nil {
		return Payment{}, err
	}
	lines, _ := json.Marshal(p.Lines)
	_, err := r.pool.Exec(ctx, `INSERT INTO payment_requests (id, store_id, gateway, mode, amount_minor, currency, lines, idempotency_key)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8) ON CONFLICT (idempotency_key) DO NOTHING`,
		id, storeID, gw.Name(), gw.Mode(), p.TotalMinor, p.Currency, lines, key)
	if err != nil {
		return Payment{}, err
	}
	pay, owner, err := r.PaymentByKey(ctx, key)
	if err == nil && owner != storeID {
		return Payment{}, errors.New("idempotency key belongs to another store")
	}
	return pay, err
}

const paymentCols = `id::text, status, mode, gateway, amount_minor, currency, lines`

func scanPayment(row pgx.Row) (Payment, error) {
	var p Payment
	var lines []byte
	if err := row.Scan(&p.ID, &p.Status, &p.Mode, &p.Gateway, &p.AmountMinor, &p.Currency, &lines); err != nil {
		return Payment{}, err
	}
	_ = json.Unmarshal(lines, &p.Lines)
	p.Notice = testNotice
	return p, nil
}

// PaymentByKey finds a payment by idempotency key and returns its store id.
func (r *Repo) PaymentByKey(ctx context.Context, key string) (Payment, string, error) {
	var owner string
	if err := r.pool.QueryRow(ctx, `SELECT store_id::text FROM payment_requests WHERE idempotency_key = $1`, key).Scan(&owner); err != nil {
		return Payment{}, "", err
	}
	p, err := scanPayment(r.pool.QueryRow(ctx, `SELECT `+paymentCols+` FROM payment_requests WHERE idempotency_key = $1`, key))
	return p, owner, err
}

// Payment finds a payment by id.
func (r *Repo) Payment(ctx context.Context, id string) (Payment, error) {
	if !validUUID(id) {
		return Payment{}, errBadID
	}
	return scanPayment(r.pool.QueryRow(ctx, `SELECT `+paymentCols+` FROM payment_requests WHERE id = $1`, id))
}

// SetPaymentStatus settles a pending test payment exactly once.
func (r *Repo) SetPaymentStatus(ctx context.Context, id, status string) (Payment, error) {
	_, err := r.pool.Exec(ctx, `UPDATE payment_requests SET status = $2, updated_at = now() WHERE id = $1 AND status = 'pending'`, id, status)
	if err != nil {
		return Payment{}, err
	}
	return r.Payment(ctx, id)
}
