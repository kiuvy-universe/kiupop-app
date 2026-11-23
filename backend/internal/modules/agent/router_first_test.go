package agent

import "testing"

func TestRouterFirstTurnCanUsePremium(t *testing.T) {
	r := DefaultRouter()
	if r.For(PurposeTurnFirst) != r.Smart || r.For(PurposeTurn) != r.Fast || r.For(PurposeEscalation) != r.Premium {
		t.Fatalf("default routing changed: %+v", r)
	}
	r.First = "claude-opus-5-5"
	if r.For(PurposeTurnFirst) != "claude-opus-5-5" || r.For(PurposeTurn) != r.Fast || r.For(PurposeCopy) != r.Fast {
		t.Fatal("only the first understanding goes premium; auxiliary work stays cheap")
	}
	if c := CostMicros("claude-opus-5-5", 5000, 1500, 0, 0); c != 50000 {
		t.Fatalf("opus cost estimate = %d", c)
	}
}
