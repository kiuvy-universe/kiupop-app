package payments

import (
	"context"
	"strings"
	"testing"
)

func TestMockNeverReportsRealPayment(t *testing.T) {
	var g Gateway = Mock{}
	if g.Mode() != "test" {
		t.Fatal("mock must be test mode")
	}
	if _, err := g.Create(context.Background(), Request{PaymentID: "x", AmountMinor: 0, Currency: "CRC"}); err == nil {
		t.Fatal("zero amount must fail")
	}
	for _, o := range []string{"approved", "declined"} {
		st, err := g.Simulate(context.Background(), "ref", o)
		if err != nil || !strings.HasPrefix(st, "test_") {
			t.Fatalf("%s -> %q %v", o, st, err)
		}
	}
	if _, err := g.Simulate(context.Background(), "ref", "paid"); err == nil {
		t.Fatal("unknown outcome must fail")
	}
}
