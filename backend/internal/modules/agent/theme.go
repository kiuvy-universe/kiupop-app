package agent

import (
	"fmt"
	"slices"
	"strings"

	"github.com/kiuvy-universe/kiupop/backend/internal/platform/storefront"
)

// SuggestTheme is the suggest_store_theme tool: a deterministic, explainable
// choice among approved templates plus controlled token variations.
func SuggestTheme(bp Blueprint, hasImages bool) (TemplateSelection, storefront.Theme) {
	hasImages = hasImages || bp.Business.CoverKey != ""
	sel := bp.Template
	key := brandingKey(bp)
	if !sel.ByUser {
		id, why := pickTemplate(bp)
		sel = TemplateSelection{ID: id, Reason: why}
	}
	sel.InputKey = key
	t := storefront.Default(sel.ID)
	styles := bp.Branding.Styles
	has := func(s ...string) bool {
		for _, x := range s {
			if slices.Contains(styles, x) {
				return true
			}
		}
		return false
	}
	switch {
	case has("elegante", "lujoso", "romantico", "delicado"):
		t.Typography.Style, t.Typography.HeadingWeight = "elegant", 700
	case has("divertido", "juvenil", "colorido"):
		t.Typography.Style, t.Typography.HeadingWeight = "playful", 900
	case has("moderno", "minimalista"):
		t.Typography.Style = "modern"
	}
	switch {
	case has("minimalista", "moderno"):
		t.Radius, t.CardStyle = 12, "outlined"
	case has("divertido", "juvenil"):
		t.Radius = 28
	}
	if len(bp.Products) > 8 {
		t.Spacing = "compact"
	}
	if hasImages {
		t.Hero.Style = "image"
	}
	if bp.Business.Category == "comida" || bp.Business.Category == "reposteria" {
		t.Sections = []string{"hero", "featured", "catalog", "delivery", "contact"}
	} else if len(bp.PricedProducts()) < 4 {
		t.Sections = []string{"hero", "catalog", "delivery", "contact"}
	}
	return sel, storefront.Normalize(t)
}

func brandingKey(bp Blueprint) string {
	return shortHash(bp.Template.ID, fmt.Sprint(bp.Template.ByUser), strings.Join(bp.Branding.Styles, ","),
		strings.Join(bp.Branding.Colors, ","), bp.Business.Category, bp.Business.CoverKey)
}

func pickTemplate(bp Blueprint) (string, string) {
	colors, styles := bp.Branding.Colors, bp.Branding.Styles
	in := func(list []string, s ...string) string {
		for _, x := range s {
			if slices.Contains(list, x) {
				return x
			}
		}
		return ""
	}
	if c := in(colors, "rosado", "lila", "pastel"); c != "" {
		return storefront.BubblegumPink, fmt.Sprintf("Elegí Bubblegum Pink porque mencionaste el color %s.", c)
	}
	if c := in(colors, "verde", "celeste"); c != "" {
		return storefront.MintFresh, fmt.Sprintf("Elegí Mint Fresh porque mencionaste el color %s.", c)
	}
	if c := in(colors, "durazno", "amarillo", "dorado"); c != "" {
		return storefront.PeachPop, fmt.Sprintf("Elegí Peach Pop porque mencionaste el color %s.", c)
	}
	if s := in(styles, "elegante", "romantico", "delicado", "lujoso"); s != "" {
		return storefront.BubblegumPink, "Elegí Bubblegum Pink porque buscás un estilo " + styleLabel(s) + "."
	}
	if s := in(styles, "fresco", "natural", "minimalista"); s != "" {
		return storefront.MintFresh, "Elegí Mint Fresh porque buscás un estilo " + styleLabel(s) + "."
	}
	if s := in(styles, "divertido", "colorido", "juvenil"); s != "" {
		return storefront.PeachPop, "Elegí Peach Pop porque buscás un estilo " + styleLabel(s) + "."
	}
	switch bp.Business.Category {
	case "plantas", "mascotas", "tecnologia", "servicios":
		return storefront.MintFresh, "Elegí Mint Fresh: limpio y fresco para tu tipo de negocio."
	case "comida", "reposteria", "artesania", "ropa":
		return storefront.PeachPop, "Elegí Peach Pop: cálido y antojado para tu tipo de negocio."
	}
	return storefront.BubblegumPink, "Elegí Bubblegum Pink, el estilo insignia de KiuPop."
}

func styleLabel(s string) string {
	switch s {
	case "romantico":
		return "romántico"
	case "rustico":
		return "rústico"
	}
	return s
}

func templateLabel(id string) string { return storefront.TemplateName(id) }
