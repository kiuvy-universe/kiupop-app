package storefront

import "time"

// View is everything a storefront renderer needs. The same shape serves the
// owner's draft preview and the public published store.
type View struct {
	Store    StoreInfo     `json:"store"`
	Theme    Theme         `json:"theme"`
	Products []ProductView `json:"products"`
	Delivery Delivery      `json:"delivery"`
	Contact  Contact       `json:"contact"`
	Payments Payments      `json:"payments"`
	Share    Share         `json:"share"`
}

// StoreInfo is the public identity.
type StoreInfo struct {
	Slug        string  `json:"slug"`
	Name        string  `json:"name"`
	Tagline     string  `json:"tagline"`
	Description string  `json:"description"`
	Category    string  `json:"category"`
	Status      string  `json:"status"` // draft | published
	CoverURL    *string `json:"cover_url"`
}

// ProductView is a public product card.
type ProductView struct {
	ID          string  `json:"id"`
	Name        string  `json:"name"`
	Description string  `json:"description"`
	PriceMinor  int64   `json:"price_minor"`
	Currency    string  `json:"currency"`
	ImageURL    *string `json:"image_url"`
	Featured    bool    `json:"featured"`
}

// Delivery lists only what the merchant stated. Empty modes means "coordinate by WhatsApp".
type Delivery struct {
	Modes []string `json:"modes"` // delivery | pickup
	Zones []string `json:"zones"`
	Notes string   `json:"notes"`
}

// Contact channels the merchant chose to publish.
type Contact struct {
	WhatsAppURL string `json:"whatsapp_url"`
	Instagram   string `json:"instagram"`
	Facebook    string `json:"facebook"`
}

// Payments states honestly what works. RealPaymentsEnabled is always false in this phase.
type Payments struct {
	Checkout            string   `json:"checkout"` // none | test
	RealPaymentsEnabled bool     `json:"real_payments_enabled"`
	MethodsToCoordinate []string `json:"methods_to_coordinate"`
}

// Share carries the link that renders social previews (Open Graph).
type Share struct {
	URL   string `json:"url"`
	Title string `json:"title"`
	Text  string `json:"text"`
}

// Profile is the public profile stored with the store (JSONB).
type Profile struct {
	Tagline   string   `json:"tagline"`
	Category  string   `json:"category"`
	Delivery  Delivery `json:"delivery"`
	Instagram string   `json:"instagram"`
	Facebook  string   `json:"facebook"`
	Payments  Payments `json:"payments"`
	Featured  []string `json:"featured"`
	CoverKey  string   `json:"cover_key,omitempty"`
}

// DraftData is what the agent syncs into the draft store row.
type DraftData struct {
	Name        string
	Description string
	WhatsApp    string // E.164 digits or ""
	Theme       Theme
	Profile     Profile
}

// SnapshotProduct is a validated, priced product being published.
type SnapshotProduct struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	PriceMinor  int64  `json:"price_minor"`
	ImageKey    string `json:"image_key,omitempty"`
	Featured    bool   `json:"featured"`
}

// Snapshot is the immutable, validated content of one publication.
type Snapshot struct {
	Name     string            `json:"name"`
	Desc     string            `json:"description"`
	WhatsApp string            `json:"whatsapp"`
	Theme    Theme             `json:"theme"`
	Profile  Profile           `json:"profile"`
	Products []SnapshotProduct `json:"products"`
}

// StoreRef identifies the store row backing an agent session.
type StoreRef struct {
	ID   string
	Slug string
}

// Publication is the result of publishing a snapshot.
type Publication struct {
	Slug    string
	Version int
}

// Plan is a store's KiuPop subscription (quiz funnel paywall). In this phase
// every plan is a test plan: no money moves.
type Plan struct {
	Plan       string    `json:"plan"`        // kiupop_monthly
	Status     string    `json:"status"`      // active | canceled
	PriceMinor int64     `json:"price_minor"` // 500 = US$5.00
	Currency   string    `json:"currency"`    // USD
	Test       bool      `json:"test"`
	PeriodEnd  time.Time `json:"current_period_end"`
}

// Paywall terms: one active store costs US$5 per month.
const (
	PlanMonthly      = "kiupop_monthly"
	PlanPriceMinor   = 500
	PlanCurrency     = "USD"
	PlanPeriodLength = 30 * 24 * time.Hour
)
