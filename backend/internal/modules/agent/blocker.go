package agent

import (
	"fmt"
	"strings"
)

// Blockers: when the essential data for publishing is still missing and the
// normal question budget is spent, Kiu does NOT repeat a generic "me falta…"
// notice. It asks ONE concrete question about the first blocker, and every
// retry changes the help it gives (reason → example → shortest path), so the
// merchant always has a clear next step toward selling.

// firstBlocker returns the first missing essential field ("" if none).
func firstBlocker(bp Blueprint) string {
	for _, m := range bp.Readiness() {
		if m.Field != "theme" {
			return m.Field
		}
	}
	return ""
}

// BlockerQuestion phrases the question for a blocking field. attempt is how
// many times that field was already asked (0 = first time).
func BlockerQuestion(bp Blueprint, field string, attempt int) Question {
	q := Question{Field: field, Essential: true}
	pick := func(opts ...string) string { return pickLevel(opts, attempt) }
	switch field {
	case FieldName:
		q.Text = pick(
			"¿Cómo se llama tu negocio? Así tus clientes lo reconocen cuando les mandés tu enlace.",
			"Solo el nombre, por ejemplo «Flores Ana».",
			"Escribí el nombre con el que te conocen tus clientes. Si no tenés uno, usá tu nombre y lo que vendés (ej. «Ana – Postres»).")
		q.Reason = "Es lo primero que ve un cliente en tu tienda."
	case FieldPrices:
		if len(bp.Products) == 0 {
			q.Text = pick(
				"Para que tus clientes vean qué vendés y dejen de preguntar precios uno por uno, necesito tu primer producto con su precio. Ej: «Ramo de rosas ₡15.000».",
				"Escribilo en una sola línea: nombre y precio. Ej: «Torta de chocolate 12000». Con uno alcanza, después agregamos más.",
				"Probemos con tu producto más vendido: ¿cómo se llama y cuánto cuesta? Si tenés varios, mandá uno por línea.")
		} else if n := len(bp.Products); n >= ImportThreshold && attempt == 0 {
			q = bulkPricesQuestion(bp, n)
			q.Essential = true
		} else {
			first := firstName(bp)
			q.Text = pick(
				fmt.Sprintf("Ya anoté %s. ¿Cuánto cuesta cada uno? Ej: «%s 15000».", examples(bp), first),
				fmt.Sprintf("Escribime el precio de %s. Ej: «%s 15000». Los demás los vemos después.", first, first),
				fmt.Sprintf("Con el precio de uno solo ya te muestro tu tienda. ¿Cuánto cuesta %s?", first))
		}
		q.Reason = "Un catálogo con precios claros vende más y te ahorra respuestas. Nunca invento precios."
		q.AllowUpload = bp.OnlineStoreFlow()
	case FieldWhatsApp:
		q.Text = pick(
			"¿A qué WhatsApp te llegan los pedidos? Cada cliente te escribe directo a ese número. "+whatsappTip,
			"Escribí solo el número, sin letras. "+whatsappTip,
			"Pegá el número tal cual lo tenés en WhatsApp, con o sin espacios o guiones. "+whatsappTip,
			"Todavía no me llega un número válido. Revisá que no tenga letras y que cumpla el formato: Costa Rica, 8 dígitos; otro país, con + y código de país.",
			"Probemos de nuevo: mandame solo el número en un mensaje. Costa Rica, 8 dígitos (8888 8888); otro país, con + y código de país (+57 300 123 4567).")
		q.Reason = "Cada pedido de tu tienda llega ahí, listo para que cerrés la venta."
	default:
		q.Text = "¿Me contás un poco más?"
	}
	if attempt == 0 {
		if p := progressLine(bp); p != "" {
			q.Text = p + " " + q.Text
		}
	}
	return q
}

// whatsappTip is the format advice shown with every WhatsApp question.
const whatsappTip = "Costa Rica: 8 dígitos (ej. 8888 8888). Otro país: con + y código de país (ej. +57 300 123 4567)."

// pickLevel returns the text for the attempt; past the last level it alternates
// the last two so the same sentence never comes twice in a row.
func pickLevel(opts []string, attempt int) string {
	n := len(opts)
	if attempt < n {
		return opts[attempt]
	}
	return opts[n-2+(attempt-n)%2]
}

// progressLine says what Kiu already has, so the merchant sees advance.
func progressLine(bp Blueprint) string {
	var have []string
	if bp.Business.Name != "" {
		have = append(have, "tu negocio ("+bp.Business.Name+")")
	}
	if n := len(bp.PricedProducts()); n > 0 {
		have = append(have, fmt.Sprintf("%d %s con precio", n, plural(n, "producto", "productos")))
	}
	if bp.Contact.WhatsApp != "" {
		have = append(have, "tu WhatsApp")
	}
	if len(have) == 0 {
		return ""
	}
	return "Ya tengo " + strings.Join(have, ", ") + "."
}
