// Package kiuvy is the port for a future, explicitly configured integration
// with the Kiuvy platform. In this phase only a disabled adapter exists:
// KiuPop never calls Kiuvy and never holds Kiuvy credentials.
//
// See docs/architecture/OVERVIEW.md ("Integración futura con Kiuvy").
package kiuvy

import (
	"context"
	"errors"
)

// ErrDisabled is returned by every call while the integration is off.
var ErrDisabled = errors.New("kiuvy integration disabled")

// BusinessRef is the minimal identity KiuPop would ever need from Kiuvy.
type BusinessRef struct {
	ID   string
	Name string
}

// Client is the port. A real adapter (HTTP, scoped token, least privilege)
// will implement it behind KIUVY_INTEGRATION_ENABLED.
type Client interface {
	Status() string
	LookupBusiness(ctx context.Context, handle string) (BusinessRef, error)
}

// Disabled is the default adapter: it never performs network calls.
type Disabled struct{}

// Status reports the adapter state for diagnostics.
func (Disabled) Status() string { return "disabled" }

// LookupBusiness always fails closed.
func (Disabled) LookupBusiness(context.Context, string) (BusinessRef, error) {
	return BusinessRef{}, ErrDisabled
}
