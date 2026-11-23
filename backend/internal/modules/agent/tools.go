package agent

import (
	"regexp"
	"slices"
	"strings"
	"unicode/utf8"

	"github.com/kiuvy-universe/kiupop/backend/internal/platform/storefront"
)

// ToolResult is one audited tool execution (stored in agent_actions).
type ToolResult struct {
	Tool    string         `json:"tool"`
	Outcome string         `json:"outcome"` // ok | rejected | noop
	Summary map[string]any `json:"summary"`
}

// Changes says which parts of the blueprint a turn touched, so only those are rebuilt.
type Changes struct {
	Profile, Contact, Delivery, Branding, Payment, Template, Images bool
	NewProducts                                                     []string // product ids needing copy
	PricedProducts                                                  int
	Results                                                         []ToolResult
}

// Any reports whether anything changed.
func (c Changes) Any() bool {
	return c.Profile || c.Contact || c.Delivery || c.Branding || c.Payment || c.Template || len(c.NewProducts) > 0 || c.PricedProducts > 0
}

var validCategories = []string{"flores", "reposteria", "comida", "ropa", "belleza", "artesania", "mascotas", "plantas", "tecnologia", "servicios", "otro"}
var validStyles = []string{"elegante", "romantico", "moderno", "minimalista", "divertido", "natural", "fresco", "juvenil", "rustico", "lujoso", "colorido", "delicado"}
var validColors = []string{"rosado", "verde", "durazno", "lila", "celeste", "amarillo", "dorado", "blanco", "negro", "pastel"}

// claimRe flags commercial claims the agent must never invent in copy.
var claimRe = regexp.MustCompile(`(?i)(₡|\$|€|\bcolones?\b|\bprecio|\bdescuento|\boferta|\bpromo|\bgratis\b|\d+\s*%|\bgarant[ií]a|\bcertificad|\b100\s*%|\bel mejor\b|\bla mejor\b|\bn[uú]mero uno\b)`)
var urlRe = regexp.MustCompile(`(?i)(https?://|www\.|\.com\b)`)

// Apply runs the typed tools over a proposal. text is the merchant's message;
// every factual value must be grounded in it. newID mints product ids.
func Apply(bp *Blueprint, ex Extraction, text string, pending string, testCheckout bool, newID func() string) Changes {
	var ch Changes
	ch.Results = append(ch.Results, updateBusinessProfile(bp, ex, text, pending, &ch))
	ch.Results = append(ch.Results, upsertDraftProducts(bp, ex.Products, text, pending, newID, &ch))
	ch.Results = append(ch.Results, updateContact(bp, ex, text, &ch))
	ch.Results = append(ch.Results, updateDelivery(bp, ex, text, pending, &ch))
	ch.Results = append(ch.Results, updateBranding(bp, ex, &ch))
	ch.Results = append(ch.Results, preparePaymentConfiguration(bp, ex.PaymentMethods, testCheckout, &ch))
	if ex.SkipPending && pending != "" && !Essential(pending) {
		bp.Skipped = addUnique(bp.Skipped, pending)
	}
	return ch
}

// update_business_profile
func updateBusinessProfile(bp *Blueprint, ex Extraction, text, pending string, ch *Changes) ToolResult {
	r := ToolResult{Tool: "update_business_profile", Outcome: "noop", Summary: map[string]any{}}
	if name := strings.Join(strings.Fields(ex.BusinessName), " "); name != "" {
		n := utf8.RuneCountInString(name)
		switch {
		case n < 2 || n > 80 || urlRe.MatchString(name):
			r.Outcome, r.Summary["name"] = "rejected", "invalid"
		case !TextGrounded(text, name) && pending != FieldName:
			r.Outcome, r.Summary["name"] = "rejected", "not_in_message"
		case name != bp.Business.Name:
			bp.Business.Name = name
			r.Outcome, r.Summary["name"] = "ok", "set"
			ch.Profile = true
		}
	}
	if c := strings.ToLower(strings.TrimSpace(ex.Category)); c != "" && c != bp.Business.Category {
		if slices.Contains(validCategories, c) {
			bp.Business.Category = c
			r.Summary["category"] = c
			r.Outcome = "ok"
			ch.Profile = true
		}
	}
	if t := cleanCopy(ex.Tagline, 80); t != "" && t != bp.Business.Tagline {
		bp.Business.Tagline = t
		r.Outcome, r.Summary["tagline"] = "ok", "set"
		ch.Profile = true
	}
	if d := cleanCopy(ex.Description, 240); d != "" && d != bp.Business.Description {
		bp.Business.Description = d
		r.Outcome, r.Summary["description"] = "ok", "set"
		ch.Profile = true
	}
	return r
}

// cleanCopy strips commercial claims and URLs from model-written copy.
func cleanCopy(s string, max int) string {
	s = strings.Join(strings.Fields(s), " ")
	if s == "" {
		return ""
	}
	var kept []string
	for _, sentence := range splitSentences(s) {
		if strings.TrimSpace(sentence) != "" && !claimRe.MatchString(sentence) && !urlRe.MatchString(sentence) {
			kept = append(kept, strings.TrimSpace(sentence))
		}
	}
	return truncate(strings.Join(kept, " "), max)
}

func splitSentences(text string) []string {
	var out []string
	r := []rune(text)
	start := 0
	for i, c := range r {
		if strings.ContainsRune(".!?", c) && (i+1 == len(r) || r[i+1] == ' ') {
			out = append(out, string(r[start:i+1]))
			start = i + 1
		}
	}
	if start < len(r) {
		out = append(out, string(r[start:]))
	}
	return out
}

// upsert_draft_products
func upsertDraftProducts(bp *Blueprint, in []ExtractedProduct, text, pending string, newID func() string, ch *Changes) ToolResult {
	r := ToolResult{Tool: "upsert_draft_products", Outcome: "noop", Summary: map[string]any{}}
	added, priced, rejected := 0, 0, 0
	for _, p := range in {
		name := strings.Join(strings.Fields(p.Name), " ")
		price := int64(0)
		if p.PriceColones > 0 {
			if p.PriceColones >= 100 && PriceGrounded(text, p.PriceColones) && p.PriceColones <= 100_000_000 {
				price = p.PriceColones * 100 // minor units (céntimos)
			} else {
				rejected++ // never accept a price the merchant did not write
			}
		}
		if name == "" {
			// "15 mil" as the answer to "¿cuánto cuesta X?" with exactly one unpriced product.
			if price > 0 && pending == FieldPrices {
				if idx := singleUnpriced(bp); idx >= 0 {
					bp.Products[idx].PriceMinor = price
					priced++
				}
			}
			continue
		}
		n := utf8.RuneCountInString(name)
		if isCommandReply(name) {
			rejected++ // "Ya sé lo que quiero" is a button, not a product
			continue
		}
		if n < 2 || n > 60 || urlRe.MatchString(name) || claimRe.MatchString(stripCurrency(name)) {
			rejected++
			continue
		}
		if !AnyWordGrounded(text, name) && !TextGrounded(text, name) {
			rejected++
			continue
		}
		if idx := findProduct(bp, name); idx >= 0 {
			pp := &bp.Products[idx]
			if price > 0 && pp.PriceMinor != price {
				// A specific priced product refines a generic one ("Arreglos" -> "Arreglo de girasoles").
				if pp.PriceMinor == 0 && fold(pp.Name) != fold(name) && len(strings.Fields(name)) > len(strings.Fields(pp.Name)) {
					pp.Name = name
					pp.CopyStatus = "pending"
					ch.NewProducts = append(ch.NewProducts, pp.ID)
				}
				pp.PriceMinor = price
				priced++
			}
			continue
		}
		if len(bp.Products) >= MaxProducts {
			rejected++
			continue
		}
		id := newID()
		bp.Products = append(bp.Products, DraftProduct{ID: id, Name: capFirst(name), PriceMinor: price, CopyStatus: "pending"})
		ch.NewProducts = append(ch.NewProducts, id)
		added++
		if price > 0 {
			priced++
		}
	}
	markFeatured(bp)
	ch.PricedProducts += priced
	if added+priced > 0 {
		r.Outcome = "ok"
	} else if rejected > 0 {
		r.Outcome = "rejected"
	}
	r.Summary["added"], r.Summary["priced"], r.Summary["rejected"] = added, priced, rejected
	return r
}

func stripCurrency(s string) string { return strings.NewReplacer("₡", "", "$", "").Replace(s) }

func singleUnpriced(bp *Blueprint) int {
	idx := -1
	for i, p := range bp.Products {
		if p.PriceMinor == 0 {
			if idx >= 0 {
				return -1
			}
			idx = i
		}
	}
	return idx
}

func findProduct(bp *Blueprint, name string) int {
	for i, p := range bp.Products {
		if fold(p.Name) == fold(name) {
			return i
		}
	}
	for i, p := range bp.Products {
		if sameProduct(p.Name, name) {
			return i
		}
	}
	return -1
}

// markFeatured highlights up to three priced products (first mentioned first).
func markFeatured(bp *Blueprint) {
	n := 0
	for i := range bp.Products {
		bp.Products[i].Featured = bp.Products[i].PriceMinor > 0 && n < 3
		if bp.Products[i].Featured {
			n++
		}
	}
}

// update_contact_channels
func updateContact(bp *Blueprint, ex Extraction, text string, ch *Changes) ToolResult {
	r := ToolResult{Tool: "update_contact_channels", Outcome: "noop", Summary: map[string]any{}}
	if ex.WhatsApp != "" {
		phone, ok := NormalizeWhatsApp(ex.WhatsApp)
		switch {
		case !ok:
			r.Outcome, r.Summary["whatsapp"] = "rejected", "invalid"
		case !PhoneGrounded(text, phone):
			r.Outcome, r.Summary["whatsapp"] = "rejected", "not_in_message"
		case phone != bp.Contact.WhatsApp:
			bp.Contact.WhatsApp = phone
			r.Outcome, r.Summary["whatsapp"] = "ok", "set"
			ch.Contact = true
		}
	}
	if ig := strings.TrimPrefix(strings.TrimSpace(ex.Instagram), "@"); ig != "" && regexp.MustCompile(`^[A-Za-z0-9._]{2,30}$`).MatchString(ig) && strings.Contains(fold(text), fold(ig)) {
		if ig != bp.Contact.Instagram {
			bp.Contact.Instagram = ig
			r.Outcome, r.Summary["instagram"] = "ok", "set"
			ch.Contact = true
		}
	}
	return r
}

// update_delivery_options
func updateDelivery(bp *Blueprint, ex Extraction, text, pending string, ch *Changes) ToolResult {
	r := ToolResult{Tool: "update_delivery_options", Outcome: "noop", Summary: map[string]any{}}
	var modes []string
	for _, m := range ex.DeliveryModes {
		if (m == "delivery" || m == "pickup") && !slices.Contains(modes, m) {
			modes = append(modes, m)
		}
	}
	if len(modes) > 0 {
		sortStrings(modes)
		if !slices.Equal(modes, bp.Delivery.Modes) {
			bp.Delivery.Modes = modes
			r.Outcome, r.Summary["modes"] = "ok", modes
			ch.Delivery = true
		}
	}
	var zones []string
	for _, z := range ex.Zones {
		z = strings.Join(strings.Fields(z), " ")
		if z != "" && utf8.RuneCountInString(z) <= 40 && TextGrounded(text, z) && len(zones) < MaxZones {
			zones = append(zones, z)
		}
	}
	if len(zones) > 0 {
		for _, z := range zones {
			bp.Delivery.Zones = addUnique(bp.Delivery.Zones, z)
		}
		if len(bp.Delivery.Zones) > MaxZones {
			bp.Delivery.Zones = bp.Delivery.Zones[:MaxZones]
		}
		bp.Business.Zones = bp.Delivery.Zones
		r.Outcome, r.Summary["zones"] = "ok", len(bp.Delivery.Zones)
		ch.Delivery = true
	}
	return r
}

// update_branding_preferences
func updateBranding(bp *Blueprint, ex Extraction, ch *Changes) ToolResult {
	r := ToolResult{Tool: "update_branding_preferences", Outcome: "noop", Summary: map[string]any{}}
	for _, s := range ex.Styles {
		if s = fold(strings.TrimSpace(s)); slices.Contains(validStyles, s) && !slices.Contains(bp.Branding.Styles, s) {
			bp.Branding.Styles = append(bp.Branding.Styles, s)
			ch.Branding = true
		}
	}
	for _, c := range ex.Colors {
		if c = fold(strings.TrimSpace(c)); slices.Contains(validColors, c) && !slices.Contains(bp.Branding.Colors, c) {
			bp.Branding.Colors = append(bp.Branding.Colors, c)
			ch.Branding = true
		}
	}
	if storefront.ValidTemplate(ex.TemplateChoice) && (bp.Template.ID != ex.TemplateChoice || !bp.Template.ByUser) {
		bp.Template = TemplateSelection{ID: ex.TemplateChoice, Reason: "Lo elegiste vos.", ByUser: true}
		ch.Template = true
		r.Summary["template"] = ex.TemplateChoice
	}
	if ch.Branding || ch.Template {
		r.Outcome = "ok"
		r.Summary["styles"], r.Summary["colors"] = bp.Branding.Styles, bp.Branding.Colors
	}
	return r
}

// prepare_payment_configuration: only ever test mode; real payments stay off.
func preparePaymentConfiguration(bp *Blueprint, methods []string, testCheckout bool, ch *Changes) ToolResult {
	r := ToolResult{Tool: "prepare_payment_configuration", Outcome: "noop", Summary: map[string]any{}}
	want := "none"
	if testCheckout {
		want = "test"
	}
	if bp.Payment.Checkout != want {
		bp.Payment.Checkout = want
		bp.Payment.PendingActivation = true
		ch.Payment = true
	}
	bp.Payment.RealPaymentsEnabled = false
	for _, m := range methods {
		if slices.Contains([]string{"SINPE Móvil", "Efectivo", "Transferencia bancaria", "Tarjeta"}, m) && !slices.Contains(bp.Payment.MethodsToCoordinate, m) {
			bp.Payment.MethodsToCoordinate = append(bp.Payment.MethodsToCoordinate, m)
			ch.Payment = true
		}
	}
	if ch.Payment {
		r.Outcome = "ok"
		r.Summary["checkout"], r.Summary["real_payments_enabled"] = bp.Payment.Checkout, false
	}
	return r
}
