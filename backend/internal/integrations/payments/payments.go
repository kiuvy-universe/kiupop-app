// Package payments is the PaymentGateway port. KiuPop prices every order on the
// server; a gateway only collects an amount we already computed.
//
// Only MockPaymentGateway exists in this phase. It never moves money and can
// never report a real payment: its statuses are prefixed "test_". A future
// QPayments (or other) adapter must use a sandbox account dedicated to KiuPop,
// least-privilege credentials, and verify webhook signatures before any status
// change — see docs/architecture/AGENTIC_STORE_BUILDER.md.
package payments

import (
	"context"
	"errors"
)

// Request is a server-priced payment request.
type Request struct {
	PaymentID   string // our id (also the idempotency anchor)
	StoreID     string
	AmountMinor int64
	Currency    string
}

// Created is the gateway's answer.
type Created struct {
	ProviderRef string
	Status      string // pending
}

// Gateway is the contract every provider adapter implements (versioned with ContractVersion).
type Gateway interface {
	Name() string
	Mode() string // "test" only, until a live adapter is authorised
	Create(ctx context.Context, r Request) (Created, error)
	// Simulate exists only on test gateways; live gateways return ErrNotSupported.
	Simulate(ctx context.Context, providerRef, outcome string) (string, error)
}

// ContractVersion of the Gateway interface.
const ContractVersion = "1"

var (
	// ErrNotSupported means the operation does not exist for this gateway.
	ErrNotSupported = errors.New("not supported")
	// ErrInvalidOutcome means a simulated outcome is unknown.
	ErrInvalidOutcome = errors.New("invalid outcome")
)

// Mock is MockPaymentGateway: test mode only, no network, no money.
type Mock struct{}

// Name implements Gateway.
func (Mock) Name() string { return "mock" }

// Mode implements Gateway.
func (Mock) Mode() string { return "test" }

// Create implements Gateway.
func (Mock) Create(_ context.Context, r Request) (Created, error) {
	if r.AmountMinor <= 0 || r.Currency != "CRC" {
		return Created{}, errors.New("invalid amount")
	}
	return Created{ProviderRef: "mock_" + r.PaymentID, Status: "pending"}, nil
}

// Simulate implements Gateway: the outcome is always a *test* status.
func (Mock) Simulate(_ context.Context, _ string, outcome string) (string, error) {
	switch outcome {
	case "approved":
		return "test_approved", nil
	case "declined":
		return "test_declined", nil
	}
	return "", ErrInvalidOutcome
}
