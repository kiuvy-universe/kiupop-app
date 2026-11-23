package agent

import (
	"fmt"
	"strings"

	"github.com/kiuvy-universe/kiupop/backend/internal/platform/storefront"
)

// FactsDescription builds the store description from facts the merchant gave
// (products and zones), used when no description was provided.
func FactsDescription(bp Blueprint) string {
	var parts []string
	var names []string
	for _, p := range bp.PricedProducts() {
		if len(names) < 3 {
			names = append(names, strings.ToLower(p.Name))
		}
	}
	if len(names) > 0 {
		parts = append(parts, capFirst(joinList(names))+".")
	}
	if z := bp.Delivery.Zones; len(z) > 0 && containsMode(bp, "delivery") {
		parts = append(parts, "Entregas en "+joinList(z)+".")
	}
	return strings.Join(parts, " ")
}

func containsMode(bp Blueprint, m string) bool {
	for _, x := range bp.Delivery.Modes {
		if x == m {
			return true
		}
	}
	return false
}

func joinList(s []string) string {
	switch len(s) {
	case 0:
		return ""
	case 1:
		return s[0]
	}
	return strings.Join(s[:len(s)-1], ", ") + " y " + s[len(s)-1]
}

// Profile maps the blueprint to the public store profile.
func Profile(bp Blueprint) storefront.Profile {
	return storefront.Profile{
		Tagline:   bp.Business.Tagline,
		Category:  bp.Business.Category,
		Delivery:  storefront.Delivery{Modes: nonNil(bp.Delivery.Modes), Zones: nonNil(bp.Delivery.Zones), Notes: bp.Delivery.Notes},
		Instagram: bp.Contact.Instagram,
		CoverKey:  bp.Business.CoverKey,
		Payments: storefront.Payments{
			Checkout: bp.Payment.Checkout, RealPaymentsEnabled: false,
			MethodsToCoordinate: nonNil(bp.Payment.MethodsToCoordinate),
		},
	}
}

func nonNil(s []string) []string {
	if s == nil {
		return []string{}
	}
	return s
}

// DraftData maps the blueprint to the draft store row.
func DraftData(bp Blueprint) storefront.DraftData {
	desc := bp.Business.Description
	if desc == "" {
		desc = FactsDescription(bp)
	}
	return storefront.DraftData{
		Name: bp.Business.Name, Description: truncate(desc, 500), WhatsApp: bp.Contact.WhatsApp,
		Theme: bp.Theme, Profile: Profile(bp),
	}
}

func imagePath(key string) *string {
	if key == "" {
		return nil
	}
	u := "/api/v1/public/images/" + key
	return &u
}

// PreviewView renders the draft exactly as the public store will look.
func PreviewView(bp Blueprint, slug string, imageURL func(key string) *string, shareURL string) storefront.View {
	d := DraftData(bp)
	name := d.Name
	if name == "" {
		name = "Tu tienda"
	}
	tagline := bp.Business.Tagline
	if tagline == "" {
		tagline = FactsTagline(bp)
	}
	v := storefront.View{
		Store: storefront.StoreInfo{Slug: slug, Name: name, Tagline: tagline, Description: d.Description,
			Category: bp.Business.Category, Status: "draft", CoverURL: imageURL(bp.Business.CoverKey)},
		Theme:    storefront.Normalize(bp.Theme),
		Products: []storefront.ProductView{},
		Delivery: d.Profile.Delivery,
		Payments: d.Profile.Payments,
		Contact:  storefront.Contact{Instagram: bp.Contact.Instagram},
		Share:    storefront.Share{URL: shareURL, Title: name, Text: fmt.Sprintf("Mirá la tienda de %s en KiuPop", name)},
	}
	if bp.Contact.WhatsApp != "" {
		v.Contact.WhatsAppURL = "https://wa.me/" + bp.Contact.WhatsApp
	}
	for _, p := range bp.PricedProducts() {
		v.Products = append(v.Products, storefront.ProductView{
			ID: p.ID, Name: p.Name, Description: p.Description, PriceMinor: p.PriceMinor, Currency: "CRC",
			ImageURL: imageURL(p.ImageKey), Featured: p.Featured,
		})
	}
	return v
}

// FactsTagline is a short factual line when the merchant gave none.
func FactsTagline(bp Blueprint) string {
	if z := bp.Delivery.Zones; len(z) > 0 && containsMode(bp, "delivery") {
		return "Pedidos por WhatsApp · Entregas en " + joinList(z)
	}
	if containsMode(bp, "pickup") {
		return "Pedidos por WhatsApp · Retiro disponible"
	}
	return "Pedidos fáciles por WhatsApp"
}

// Snapshot builds the validated publication content (only priced products).
func Snapshot(bp Blueprint) storefront.Snapshot {
	d := DraftData(bp)
	s := storefront.Snapshot{Name: d.Name, Desc: d.Description, WhatsApp: d.WhatsApp, Theme: storefront.Normalize(bp.Theme), Profile: d.Profile}
	if s.Profile.Tagline == "" {
		s.Profile.Tagline = FactsTagline(bp)
	}
	for _, p := range bp.PricedProducts() {
		s.Products = append(s.Products, storefront.SnapshotProduct{ID: p.ID, Name: p.Name, Description: p.Description, PriceMinor: p.PriceMinor, Featured: p.Featured, ImageKey: p.ImageKey})
	}
	return s
}
