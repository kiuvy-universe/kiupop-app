// Package ai is KiuPop AI: it drafts a product name and copy from a merchant's
// short note. The merchant always reviews and edits before saving. The model
// never sees or sets prices, and its output is validated before it is returned.
package ai

import (
	"context"
	"errors"
	"regexp"
	"strings"
	"unicode/utf8"
)

// MaxInputRunes bounds the merchant note.
const MaxInputRunes = 500

var (
	// ErrDisabled means no provider is configured (AI_ENABLED off or no key).
	ErrDisabled = errors.New("ai disabled")
	// ErrUnavailable means the provider failed or timed out.
	ErrUnavailable = errors.New("ai provider unavailable")
	// ErrInvalidOutput means the provider answered but the answer failed validation.
	ErrInvalidOutput = errors.New("ai output invalid")
	// ErrRefused means the provider declined the request.
	ErrRefused = errors.New("ai refused")
)

// Suggestion is the structured proposal shown to the merchant.
type Suggestion struct {
	Name             string `json:"name"`
	ShortDescription string `json:"short_description"`
	MarketingText    string `json:"marketing_text"`
}

// ProductDescriptionGenerator is the domain port. Swap providers by implementing it.
type ProductDescriptionGenerator interface {
	Generate(ctx context.Context, merchantNote string) (Suggestion, error)
}

// Disabled is used when AI is not configured. It never pretends to generate.
type Disabled struct{}

// Generate always returns ErrDisabled.
func (Disabled) Generate(context.Context, string) (Suggestion, error) {
	return Suggestion{}, ErrDisabled
}

// Commercial claims the model must not invent: prices, currency, discounts, promos.
var claimRe = regexp.MustCompile(`(?i)(₡|\$|€|\bcolones?\b|\bprecio|\bdescuento|\boferta|\bpromo|\bgratis\b|\d+\s*%|\d[\d.,]*\s*(mil|k)\b)`)

// Validate enforces lengths and strips any invented commercial claims. It
// returns ErrInvalidOutput when the result is unusable.
func Validate(s Suggestion) (Suggestion, error) {
	s.Name = strings.Join(strings.Fields(s.Name), " ")
	if n := utf8.RuneCountInString(s.Name); n < 2 || n > 80 || claimRe.MatchString(s.Name) {
		return Suggestion{}, ErrInvalidOutput
	}
	s.ShortDescription = stripClaims(s.ShortDescription)
	s.MarketingText = stripClaims(s.MarketingText)
	if s.ShortDescription == "" {
		return Suggestion{}, ErrInvalidOutput
	}
	s.ShortDescription = truncateRunes(s.ShortDescription, 200)
	s.MarketingText = truncateRunes(s.MarketingText, 400)
	return s, nil
}

func stripClaims(text string) string {
	text = strings.Join(strings.Fields(text), " ")
	var kept []string
	for _, sentence := range sentences(text) {
		sentence = strings.TrimSpace(sentence)
		if sentence != "" && !claimRe.MatchString(sentence) {
			kept = append(kept, sentence)
		}
	}
	return strings.Join(kept, " ")
}

func truncateRunes(s string, max int) string {
	if utf8.RuneCountInString(s) <= max {
		return s
	}
	r := []rune(s)
	return strings.TrimSpace(string(r[:max-1])) + "…"
}

// sentences splits on . ! ? followed by a space or the end (so "₡1.500" stays whole).
func sentences(text string) []string {
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
