// Package demo exposes fictitious data that proves the local stack works
// end to end (Flutter -> Go -> PostgreSQL). It is mounted only in mock mode.
package demo

import "context"

// Product is a demo product. Amounts are integer minor units (never floats).
type Product struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	PriceMinor  int64  `json:"price_minor"`
	Currency    string `json:"currency"`
}

// Info describes the running environment. It must never include secrets.
type Info struct {
	Service          string `json:"service"`
	Version          string `json:"version"`
	Environment      string `json:"environment"`
	MockMode         bool   `json:"mock_mode"`
	KiuvyIntegration string `json:"kiuvy_integration"`
	Message          string `json:"message"`
}

// ProductLister is the port the demo handlers depend on.
type ProductLister interface {
	ListProducts(ctx context.Context) ([]Product, error)
}
