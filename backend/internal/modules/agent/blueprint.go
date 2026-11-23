// Package agent is Kiu, KiuPop's store-building agent. It keeps a structured,
// versioned StoreBlueprint per conversation, asks a few adaptive questions,
// and builds the store in parallel through typed, validated tools.
//
// The language model only proposes values (Extraction). Every change goes
// through a Go tool that validates it against the merchant's own words; the
// model never writes to PostgreSQL, never sets a price the merchant did not
// say, and never publishes or enables payments.
package agent

import (
	"slices"
	"strings"

	"github.com/kiuvy-universe/kiupop/backend/internal/platform/storefront"
)

// SchemaVersion of StoreBlueprint. Bump with a migration path in decodeBlueprint.
const SchemaVersion = 1

// Limits keep the blueprint small enough to send to a model as context.
const (
	MaxProducts = 24
	MaxZones    = 8
)

// Blueprint is the agent's structured understanding of the store (StoreBlueprint).
type Blueprint struct {
	SchemaVersion int                  `json:"schema_version"`
	Business      BusinessProfile      `json:"business"`
	Contact       ContactChannels      `json:"contact"`
	Products      []DraftProduct       `json:"products"`
	Delivery      DeliveryOptions      `json:"delivery"`
	Branding      BrandingPreferences  `json:"branding"`
	Template      TemplateSelection    `json:"template"`
	Theme         storefront.Theme     `json:"theme"`
	Payment       PaymentConfiguration `json:"payment"`
	Publication   PublicationState     `json:"publication"`
	Asked         []string             `json:"asked"`   // question fields already asked (in order)
	Skipped       []string             `json:"skipped"` // fields the merchant chose to skip
	Pending       *Question            `json:"pending,omitempty"`
	// Discovery is the diagnosis Kiu runs before building (nil = original flow).
	Discovery *Discovery `json:"discovery,omitempty"`
}

// BusinessProfile describes the business.
type BusinessProfile struct {
	Name        string   `json:"name"`
	Category    string   `json:"category"`
	Tagline     string   `json:"tagline"`
	Description string   `json:"description"`
	Zones       []string `json:"zones"`
	Currency    string   `json:"currency"`
	CoverKey    string   `json:"cover_key,omitempty"` // a merchant photo used as the store cover
}

// ContactChannels the merchant gave.
type ContactChannels struct {
	WhatsApp  string `json:"whatsapp"` // E.164 digits, no '+'
	Instagram string `json:"instagram"`
	Facebook  string `json:"facebook"`
}

// DraftProduct is a product in the draft catalog. PriceMinor 0 means "unknown":
// such products are never published.
type DraftProduct struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	PriceMinor  int64  `json:"price_minor"`
	Featured    bool   `json:"featured"`
	CopyStatus  string `json:"copy_status"` // pending | done | skipped | user
	CopyKey     string `json:"copy_key"`    // name hash the description was generated for
	ImageKey    string `json:"image_key,omitempty"`
}

// DeliveryOptions holds only what the merchant stated.
type DeliveryOptions struct {
	Modes []string `json:"modes"` // delivery | pickup
	Zones []string `json:"zones"`
	Notes string   `json:"notes"`
}

// BrandingPreferences are the merchant's words about look and feel.
type BrandingPreferences struct {
	Styles []string `json:"styles"` // elegante, romantico, moderno, ...
	Colors []string `json:"colors"` // rosado, verde, durazno, ...
}

// TemplateSelection records the chosen template and why.
type TemplateSelection struct {
	ID       string `json:"id"`
	Reason   string `json:"reason"`
	ByUser   bool   `json:"by_user"`
	InputKey string `json:"input_key"` // branding hash the theme was computed for
}

// PaymentConfiguration never enables real money in this phase.
type PaymentConfiguration struct {
	Checkout            string   `json:"checkout"` // none | test
	RealPaymentsEnabled bool     `json:"real_payments_enabled"`
	PendingActivation   bool     `json:"pending_activation"`
	MethodsToCoordinate []string `json:"methods_to_coordinate"` // only methods the merchant named
}

// PublicationState mirrors the lifecycle.
type PublicationState struct {
	Status  string `json:"status"` // draft | published
	Version int    `json:"version"`
	Slug    string `json:"slug"`
}

// Question is what Kiu is currently asking.
type Question struct {
	Field        string       `json:"field"`
	Text         string       `json:"text"`
	Reason       string       `json:"reason"`
	Essential    bool         `json:"essential"`
	QuickReplies []QuickReply `json:"quick_replies"`
	// AllowUpload offers "upload your catalog" (Excel, CSV or text). Only set
	// when the merchant is getting an online store; other channels get a guide.
	AllowUpload bool `json:"allow_upload"`
}

// QuickReply is a tappable answer.
type QuickReply struct {
	Label string `json:"label"`
	Value string `json:"value"`
}

// NewBlueprint returns an empty v1 blueprint.
func NewBlueprint() Blueprint {
	return Blueprint{
		SchemaVersion: SchemaVersion,
		Business:      BusinessProfile{Currency: "CRC"},
		Products:      []DraftProduct{},
		Payment:       PaymentConfiguration{Checkout: "none"},
		Publication:   PublicationState{Status: "draft"},
		Asked:         []string{},
		Skipped:       []string{},
	}
}

// PricedProducts returns products with a merchant-stated price.
func (b Blueprint) PricedProducts() []DraftProduct {
	var out []DraftProduct
	for _, p := range b.Products {
		if p.PriceMinor > 0 {
			out = append(out, p)
		}
	}
	return out
}

func (b Blueprint) skipped(field string) bool { return slices.Contains(b.Skipped, field) }

// Known reports whether a question field is already answered (or skipped).
func (b Blueprint) Known(field string) bool {
	switch field {
	case FieldName:
		return b.Business.Name != ""
	case FieldProducts:
		return len(b.Products) > 0
	case FieldPrices:
		return len(b.PricedProducts()) > 0
	case FieldWhatsApp:
		return b.Contact.WhatsApp != ""
	case FieldDelivery:
		return len(b.Delivery.Modes) > 0 || b.skipped(FieldDelivery)
	case FieldStyle:
		return len(b.Branding.Styles) > 0 || len(b.Branding.Colors) > 0 || b.skipped(FieldStyle) || b.Template.ByUser
	}
	return false
}

// Question fields, in the order Kiu considers them.
const (
	FieldName     = "name"
	FieldProducts = "products"
	FieldPrices   = "prices"
	FieldWhatsApp = "whatsapp"
	FieldDelivery = "delivery"
	FieldStyle    = "style"
)

// QuestionFields is the planner's priority order.
var QuestionFields = []string{FieldName, FieldProducts, FieldPrices, FieldWhatsApp, FieldDelivery, FieldStyle}

// Essential fields block publication; the rest are optional and skippable.
func Essential(field string) bool {
	return field == FieldName || field == FieldProducts || field == FieldPrices || field == FieldWhatsApp
}

// Missing explains what blocks publication.
type Missing struct {
	Field   string `json:"field"`
	Message string `json:"message"`
}

// Readiness lists everything that blocks publication (empty = publishable).
func (b Blueprint) Readiness() []Missing {
	var m []Missing
	if strings.TrimSpace(b.Business.Name) == "" {
		m = append(m, Missing{FieldName, "Falta el nombre de tu negocio."})
	}
	if len(b.PricedProducts()) == 0 {
		m = append(m, Missing{FieldPrices, "Necesito al menos un producto con su precio."})
	}
	if b.Contact.WhatsApp == "" {
		m = append(m, Missing{FieldWhatsApp, "Falta el WhatsApp donde recibís los pedidos."})
	}
	if !storefront.ValidTemplate(b.Theme.Template) {
		m = append(m, Missing{"theme", "Todavía estoy eligiendo el estilo de tu tienda."})
	}
	return m
}
