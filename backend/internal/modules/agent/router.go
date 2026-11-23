package agent

// ModelRouter maps a purpose to a model tier. Deterministic work (validation,
// planning, theme tokens, readiness, publication) never calls a model.
//
// Prices verified 2026-11-22 (USD per million tokens, input/output):
// Haiku 5.5 0.10/0.50 · Sonnet 5.5 2/10 (cache read 0.10) · Opus 5.5 4/20 (cache read 0.20).
type ModelRouter struct {
	Fast    string // classification, extraction of short answers, product copy
	Smart   string // first deep understanding of the business, ambiguity
	Premium string // exceptional escalation (invalid output from the tier below)
	// First is the model for the decisive first understanding of the business
	// (the demo uses Opus here). Empty = Smart.
	First string
}

// DefaultRouter is the production routing.
func DefaultRouter() ModelRouter {
	return ModelRouter{Fast: "claude-haiku-5-5", Smart: "claude-sonnet-5-5", Premium: "claude-opus-5-5"}
}

// Purposes.
const (
	PurposeTurnFirst  = "turn_first"
	PurposeTurn       = "turn"
	PurposeCopy       = "product_copy"
	PurposeEscalation = "escalation"
	PurposePhoto      = "photo"
	PurposeCatalog    = "catalog_pdf"
)

// For returns the model for a purpose.
func (r ModelRouter) For(purpose string) string {
	switch purpose {
	case PurposeTurnFirst:
		if r.First != "" {
			return r.First
		}
		return r.Smart
	case PurposeEscalation:
		return r.Premium
	case PurposeCatalog:
		return r.Smart // long documents: better reading of tables
	default:
		return r.Fast
	}
}

// price is micro-USD per token.
type price struct{ in, out, cacheRead, cacheWrite float64 }

var prices = map[string]price{
	"claude-haiku-5-5":  {in: 0.10, out: 0.50, cacheRead: 0.01, cacheWrite: 0.125},
	"claude-sonnet-5-5": {in: 2, out: 10, cacheRead: 0.10, cacheWrite: 2.5},
	"claude-opus-5-5":   {in: 4, out: 20, cacheRead: 0.20, cacheWrite: 5},
}

// CostMicros estimates the cost of a call. Unknown models are priced as Opus (conservative).
func CostMicros(model string, in, out, cacheRead, cacheWrite int64) int64 {
	p, ok := prices[model]
	if !ok {
		p = prices["claude-opus-5-5"]
	}
	return int64(p.in*float64(in) + p.out*float64(out) + p.cacheRead*float64(cacheRead) + p.cacheWrite*float64(cacheWrite) + 0.5)
}

// SupportsServerFallback reports whether the model accepts `fallbacks: "default"`.
func SupportsServerFallback(model string) bool {
	return model == "claude-sonnet-5-5" || model == "claude-opus-5-5"
}
