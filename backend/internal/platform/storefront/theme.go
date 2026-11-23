// Package storefront holds the parametrised store template system shared by the
// agent (draft previews) and the public catalog (published stores).
//
// The AI never writes CSS, HTML or Dart. It picks one approved template and may
// propose a few tokens; Normalize clamps every token to the template's allowed
// range and rejects colours that fail WCAG contrast, falling back to the
// template's audited defaults.
package storefront

import (
	"fmt"
	"math"
	"regexp"
	"strconv"
	"strings"
)

// Template ids. Adding one requires a renderer test and a contrast audit.
const (
	BubblegumPink = "bubblegum_pink"
	MintFresh     = "mint_fresh"
	PeachPop      = "peach_pop"
)

// Templates lists the approved templates in display order.
var Templates = []string{BubblegumPink, MintFresh, PeachPop}

// TemplateName is the human label (es-CR UI shows the brand names as-is).
func TemplateName(id string) string {
	switch id {
	case MintFresh:
		return "Mint Fresh"
	case PeachPop:
		return "Peach Pop"
	default:
		return "Bubblegum Pink"
	}
}

// ValidTemplate reports whether id is approved.
func ValidTemplate(id string) bool {
	for _, t := range Templates {
		if t == id {
			return true
		}
	}
	return false
}

// Colors are hex "#RRGGBB" design tokens.
type Colors struct {
	Primary   string `json:"primary"`
	OnPrimary string `json:"on_primary"`
	Secondary string `json:"secondary"`
	Bg        string `json:"background"`
	Surface   string `json:"surface"`
	Text      string `json:"text"`
	Muted     string `json:"muted"`
	Accent    string `json:"accent"`
}

// Typography is a controlled variation, not a free font choice.
type Typography struct {
	Style         string  `json:"style"`          // elegant | modern | playful
	HeadingWeight int     `json:"heading_weight"` // 600..900
	Scale         float64 `json:"scale"`          // 0.9..1.15
}

// Hero describes the cover.
type Hero struct {
	Style string `json:"style"` // gradient | image
}

// Theme is the full validated token set a renderer needs.
type Theme struct {
	Template    string     `json:"template"`
	Colors      Colors     `json:"colors"`
	Typography  Typography `json:"typography"`
	Radius      int        `json:"radius"`       // 8..28
	Spacing     string     `json:"spacing"`      // compact | comfortable
	CardStyle   string     `json:"card_style"`   // soft | outlined | elevated
	ButtonStyle string     `json:"button_style"` // pill | rounded
	Hero        Hero       `json:"hero"`
	Sections    []string   `json:"sections"`
}

// Sections a template can render. hero is always first and catalog always present.
var allowedSections = map[string]bool{"hero": true, "featured": true, "catalog": true, "delivery": true, "contact": true}

// DefaultSections is the default order.
var DefaultSections = []string{"hero", "featured", "catalog", "delivery", "contact"}

// Default returns the audited token set for a template.
func Default(template string) Theme {
	t := Theme{
		Template:    template,
		Typography:  Typography{Style: "modern", HeadingWeight: 800, Scale: 1},
		Radius:      20,
		Spacing:     "comfortable",
		CardStyle:   "soft",
		ButtonStyle: "pill",
		Hero:        Hero{Style: "gradient"},
		Sections:    append([]string(nil), DefaultSections...),
	}
	switch template {
	case MintFresh:
		t.Colors = Colors{Primary: "#0F7A5C", OnPrimary: "#FFFFFF", Secondary: "#BFF0DD", Bg: "#F3FBF7", Surface: "#FFFFFF", Text: "#10231C", Muted: "#4B6B60", Accent: "#2BB58A"}
		t.Radius = 16
		t.CardStyle = "outlined"
	case PeachPop:
		t.Colors = Colors{Primary: "#C2410C", OnPrimary: "#FFFFFF", Secondary: "#FFD9C2", Bg: "#FFF6F0", Surface: "#FFFFFF", Text: "#2A1609", Muted: "#7A4E35", Accent: "#FF8A5B"}
		t.Typography.Style = "playful"
		t.Radius = 24
		t.CardStyle = "elevated"
	default:
		t.Template = BubblegumPink
		t.Colors = Colors{Primary: "#C2185B", OnPrimary: "#FFFFFF", Secondary: "#FFD1E3", Bg: "#FFF5F9", Surface: "#FFFFFF", Text: "#2B1320", Muted: "#7A4A60", Accent: "#FF6FA5"}
	}
	return t
}

var hexRe = regexp.MustCompile(`^#[0-9A-Fa-f]{6}$`)

// Normalize returns a theme guaranteed to be renderable and accessible. Any
// token outside its allowed range is replaced by the template default; colours
// are accepted only as a complete, contrast-passing set.
func Normalize(in Theme) Theme {
	if !ValidTemplate(in.Template) {
		in.Template = BubblegumPink
	}
	def := Default(in.Template)
	out := def
	if c, ok := normalizeColors(in.Colors); ok {
		out.Colors = c
	}
	switch in.Typography.Style {
	case "elegant", "modern", "playful":
		out.Typography.Style = in.Typography.Style
	}
	if w := in.Typography.HeadingWeight; w >= 600 && w <= 900 && w%100 == 0 {
		out.Typography.HeadingWeight = w
	}
	if s := in.Typography.Scale; s >= 0.9 && s <= 1.15 {
		out.Typography.Scale = math.Round(s*100) / 100
	}
	if in.Radius >= 8 && in.Radius <= 28 {
		out.Radius = in.Radius
	}
	if in.Spacing == "compact" || in.Spacing == "comfortable" {
		out.Spacing = in.Spacing
	}
	switch in.CardStyle {
	case "soft", "outlined", "elevated":
		out.CardStyle = in.CardStyle
	}
	if in.ButtonStyle == "pill" || in.ButtonStyle == "rounded" {
		out.ButtonStyle = in.ButtonStyle
	}
	if in.Hero.Style == "gradient" || in.Hero.Style == "image" {
		out.Hero.Style = in.Hero.Style
	}
	if s, ok := normalizeSections(in.Sections); ok {
		out.Sections = s
	}
	return out
}

func normalizeSections(in []string) ([]string, bool) {
	if len(in) == 0 || len(in) > len(allowedSections) || in[0] != "hero" {
		return nil, false
	}
	seen := map[string]bool{}
	for _, s := range in {
		if !allowedSections[s] || seen[s] {
			return nil, false
		}
		seen[s] = true
	}
	if !seen["catalog"] {
		return nil, false
	}
	return append([]string(nil), in...), true
}

func normalizeColors(c Colors) (Colors, bool) {
	all := []*string{&c.Primary, &c.OnPrimary, &c.Secondary, &c.Bg, &c.Surface, &c.Text, &c.Muted, &c.Accent}
	for _, p := range all {
		if !hexRe.MatchString(*p) {
			return Colors{}, false
		}
		*p = strings.ToUpper(*p)
	}
	if CheckContrast(c) != nil {
		return Colors{}, false
	}
	return c, true
}

// CheckContrast enforces WCAG 2.1: 4.5:1 for body text, 3:1 for large/UI text.
func CheckContrast(c Colors) error {
	checks := []struct {
		name   string
		fg, bg string
		min    float64
	}{
		{"text/background", c.Text, c.Bg, 4.5},
		{"text/surface", c.Text, c.Surface, 4.5},
		{"muted/surface", c.Muted, c.Surface, 4.5},
		{"on_primary/primary", c.OnPrimary, c.Primary, 4.5},
		{"primary/surface", c.Primary, c.Surface, 3},
		{"text/secondary", c.Text, c.Secondary, 4.5},
	}
	for _, ch := range checks {
		if r := ContrastRatio(ch.fg, ch.bg); r < ch.min {
			return fmt.Errorf("%s contrast %.2f < %.1f", ch.name, r, ch.min)
		}
	}
	return nil
}

// ContrastRatio returns the WCAG contrast ratio between two hex colours.
func ContrastRatio(a, b string) float64 {
	la, lb := luminance(a), luminance(b)
	if la < lb {
		la, lb = lb, la
	}
	return (la + 0.05) / (lb + 0.05)
}

func luminance(hex string) float64 {
	if !hexRe.MatchString(hex) {
		return 0
	}
	ch := func(i int) float64 {
		v, _ := strconv.ParseUint(hex[i:i+2], 16, 8)
		s := float64(v) / 255
		if s <= 0.03928 {
			return s / 12.92
		}
		return math.Pow((s+0.055)/1.055, 2.4)
	}
	return 0.2126*ch(1) + 0.7152*ch(3) + 0.0722*ch(5)
}
