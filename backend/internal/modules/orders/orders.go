// Package orders prepares a WhatsApp order: it validates items against the
// store's stored products and computes every amount server-side. Nothing is
// persisted and nothing is confirmed — the merchant confirms in WhatsApp.
package orders

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"strconv"
	"strings"
)

// Limits for a single preview.
const (
	MaxLines    = 50
	MaxQuantity = 99
)

var (
	// ErrStoreNotFound means the slug does not exist.
	ErrStoreNotFound = errors.New("store not found")
)

// Item is one requested line. There is deliberately no price field.
type Item struct {
	ProductID string `json:"product_id"`
	Quantity  int    `json:"quantity"`
}

// Request is the body of the preview endpoint.
type Request struct {
	Items []Item `json:"items"`
}

// StoredProduct is what the repository returns for the requested ids.
type StoredProduct struct {
	ID         string
	Name       string
	PriceMinor int64
	Currency   string
	Available  bool
}

// StoreInfo is the minimum store data needed to build the message.
type StoreInfo struct {
	Slug     string
	Name     string
	WhatsApp string
}

// Line is a computed order line.
type Line struct {
	ProductID      string `json:"product_id"`
	Name           string `json:"name"`
	Quantity       int    `json:"quantity"`
	UnitPriceMinor int64  `json:"unit_price_minor"`
	SubtotalMinor  int64  `json:"subtotal_minor"`
}

// Preview is the response.
type Preview struct {
	Store       PublicStore `json:"store"`
	Lines       []Line      `json:"lines"`
	TotalMinor  int64       `json:"total_minor"`
	Currency    string      `json:"currency"`
	Message     string      `json:"message"`
	WhatsAppURL string      `json:"whatsapp_url"`
}

// PublicStore identifies the store in the preview.
type PublicStore struct {
	Slug string `json:"slug"`
	Name string `json:"name"`
}

// LineError explains why an item was rejected.
type LineError struct {
	Code      string `json:"code"`
	ProductID string `json:"product_id,omitempty"`
	Message   string `json:"message"`
}

func (e *LineError) Error() string { return e.Code }

// Normalize validates shape and merges duplicate product ids (keeps first-seen order).
func Normalize(req Request) ([]Item, *LineError) {
	if len(req.Items) == 0 {
		return nil, &LineError{Code: "empty_order", Message: "Agrega al menos un producto."}
	}
	if len(req.Items) > MaxLines {
		return nil, &LineError{Code: "too_many_items", Message: "El pedido tiene demasiados productos."}
	}
	idx := map[string]int{}
	var out []Item
	for _, it := range req.Items {
		if !validUUID(it.ProductID) {
			return nil, &LineError{Code: "invalid_product", ProductID: it.ProductID, Message: "Hay un producto que no es válido."}
		}
		if it.Quantity < 1 || it.Quantity > MaxQuantity {
			return nil, &LineError{Code: "invalid_quantity", ProductID: it.ProductID, Message: "Las cantidades deben estar entre 1 y 99."}
		}
		if i, ok := idx[it.ProductID]; ok {
			out[i].Quantity += it.Quantity
			if out[i].Quantity > MaxQuantity {
				return nil, &LineError{Code: "invalid_quantity", ProductID: it.ProductID, Message: "Las cantidades deben estar entre 1 y 99."}
			}
			continue
		}
		idx[it.ProductID] = len(out)
		out = append(out, it)
	}
	return out, nil
}

// Build computes the preview from stored products only. Client prices never exist.
func Build(store StoreInfo, items []Item, stored map[string]StoredProduct) (Preview, *LineError) {
	p := Preview{Store: PublicStore{Slug: store.Slug, Name: store.Name}, Currency: "CRC"}
	for _, it := range items {
		sp, ok := stored[it.ProductID]
		if !ok { // unknown or belongs to another store: same answer, no leak
			return Preview{}, &LineError{Code: "product_not_found", ProductID: it.ProductID, Message: "Un producto ya no está en esta tienda."}
		}
		if !sp.Available {
			return Preview{}, &LineError{Code: "product_unavailable", ProductID: it.ProductID, Message: fmt.Sprintf("«%s» no está disponible en este momento.", sp.Name)}
		}
		if sp.Currency != p.Currency {
			return Preview{}, &LineError{Code: "currency_mismatch", ProductID: it.ProductID, Message: "Moneda no soportada."}
		}
		sub := sp.PriceMinor * int64(it.Quantity) // ≤ 1e11 × 99, no overflow
		p.Lines = append(p.Lines, Line{ProductID: sp.ID, Name: sp.Name, Quantity: it.Quantity, UnitPriceMinor: sp.PriceMinor, SubtotalMinor: sub})
		p.TotalMinor += sub // ≤ 50 lines × 9.9e12, no overflow
	}
	p.Message = Message(store.Name, p.Lines, p.TotalMinor)
	p.WhatsAppURL = WhatsAppURL(store.WhatsApp, p.Message)
	return p, nil
}

// Message renders the text the shopper sends. It asks; it does not confirm.
func Message(storeName string, lines []Line, total int64) string {
	var b strings.Builder
	fmt.Fprintf(&b, "Hola, quiero realizar este pedido en %s:\n\n", storeName)
	for _, l := range lines {
		fmt.Fprintf(&b, "%d × %s — %s\n", l.Quantity, l.Name, FormatCRC(l.SubtotalMinor))
	}
	fmt.Fprintf(&b, "\nTotal: %s\n\n¿Me pueden confirmar disponibilidad?", FormatCRC(total))
	return b.String()
}

// WhatsAppURL builds https://wa.me/<digits>?text=<percent-encoded> (spaces as %20).
func WhatsAppURL(phoneDigits, text string) string {
	return "https://wa.me/" + phoneDigits + "?text=" + strings.ReplaceAll(url.QueryEscape(text), "+", "%20")
}

// FormatCRC renders céntimos as Costa Rican colones: ₡2.000 or ₡2.000,50.
func FormatCRC(minor int64) string {
	neg := minor < 0
	if neg {
		minor = -minor
	}
	whole, cents := minor/100, minor%100
	s := strconv.FormatInt(whole, 10)
	var b strings.Builder
	for i, r := range s {
		if i > 0 && (len(s)-i)%3 == 0 {
			b.WriteByte('.')
		}
		b.WriteRune(r)
	}
	out := "₡" + b.String()
	if cents != 0 {
		out += fmt.Sprintf(",%02d", cents)
	}
	if neg {
		out = "-" + out
	}
	return out
}

// Repository loads the store and the requested products scoped to that store.
type Repository interface {
	Load(ctx context.Context, slug string, ids []string) (StoreInfo, map[string]StoredProduct, error)
}

func validUUID(s string) bool {
	if len(s) != 36 {
		return false
	}
	for i, r := range s {
		switch i {
		case 8, 13, 18, 23:
			if r != '-' {
				return false
			}
		default:
			if !(r >= '0' && r <= '9' || r >= 'a' && r <= 'f') {
				return false
			}
		}
	}
	return true
}
