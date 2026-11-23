package kiuvy

import (
	"context"
	"errors"
	"testing"
)

func TestDisabledFailsClosed(t *testing.T) {
	var c Client = Disabled{}
	if c.Status() != "disabled" {
		t.Fatalf("status = %q", c.Status())
	}
	if _, err := c.LookupBusiness(context.Background(), "any"); !errors.Is(err, ErrDisabled) {
		t.Fatalf("err = %v", err)
	}
}
