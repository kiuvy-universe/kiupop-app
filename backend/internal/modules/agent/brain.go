package agent

import (
	"context"
	"errors"
)

// Extraction is what a Brain proposes from one merchant message. Nothing here
// is trusted: Apply validates and grounds every value in the merchant's text.
type Extraction struct {
	BusinessName   string             `json:"business_name"`
	Category       string             `json:"category"`
	Tagline        string             `json:"tagline"`
	Description    string             `json:"description"`
	Products       []ExtractedProduct `json:"products"`
	WhatsApp       string             `json:"whatsapp"`
	DeliveryModes  []string           `json:"delivery_modes"`
	Zones          []string           `json:"zones"`
	Styles         []string           `json:"styles"`
	Colors         []string           `json:"colors"`
	PaymentMethods []string           `json:"payment_methods"`
	Instagram      string             `json:"instagram"`
	TemplateChoice string             `json:"template_choice"` // explicit user choice only
	SkipPending    bool               `json:"skip_pending"`
	WantsPublish   bool               `json:"wants_publish"`
	Reply          string             `json:"reply"`
	NextQuestion   *ProposedQuestion  `json:"next_question"`
}

// ExtractedProduct is a product the merchant mentioned. PriceColones is only
// kept if that amount literally appears in the merchant's message.
type ExtractedProduct struct {
	Name         string `json:"name"`
	PriceColones int64  `json:"price_colones"` // 0 = not stated
}

// ProposedQuestion is the model's phrasing for the planner's next field. The
// planner decides the field; the model only suggests words for it.
type ProposedQuestion struct {
	Field  string `json:"field"`
	Text   string `json:"text"`
	Reason string `json:"reason"`
}

// TurnInput is what a Brain sees for one turn.
type TurnInput struct {
	SessionID string
	Blueprint Blueprint
	Pending   *Question
	Text      string
	First     bool
	// Missing lists the question fields still open, so the model can phrase one.
	Missing []string
}

// Usage reports one model call for budgets and the cost report.
type Usage struct {
	Purpose          string
	Model            string
	InputTokens      int64
	OutputTokens     int64
	CacheReadTokens  int64
	CacheWriteTokens int64
	LatencyMs        int64
	CostMicros       int64
	Outcome          string // ok | invalid | refused | error | timeout
}

// Brain understands a merchant message.
type Brain interface {
	Understand(ctx context.Context, in TurnInput) (Extraction, []Usage, error)
	Mode() string // "claude" | "local"
}

// CopyInput asks for a product description.
type CopyInput struct {
	SessionID    string
	BusinessName string
	Category     string
	ProductName  string
	Context      string // merchant's own words about the business
}

// Copywriter drafts short product descriptions.
type Copywriter interface {
	Describe(ctx context.Context, in CopyInput) (string, Usage, error)
}

var (
	// ErrBrainUnavailable means the model failed; callers fall back to the local brain.
	ErrBrainUnavailable = errors.New("brain unavailable")
	// ErrNoCopywriter means descriptions are not generated (no AI configured).
	ErrNoCopywriter = errors.New("no copywriter")
)

// NoCopy is the Copywriter when AI is off: descriptions stay empty (never invented).
type NoCopy struct{}

// Describe always returns ErrNoCopywriter.
func (NoCopy) Describe(context.Context, CopyInput) (string, Usage, error) {
	return "", Usage{}, ErrNoCopywriter
}
