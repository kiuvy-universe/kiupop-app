package agent

import (
	"fmt"
	"hash/fnv"
	"slices"
	"strings"
	"unicode/utf8"
)

// Question budget: three extra questions, a fourth (and more) only for data
// that blocks publication. Kiu stops as soon as the essentials are known.
// ImportThreshold: with this many products or more, typing each price is slow,
// so Kiu suggests importing a list (Excel, CSV or text) instead.
const ImportThreshold = 8

const (
	SoftQuestionLimit = 3
	HardQuestionLimit = 6
	maxAsksPerField   = 2
)

// NextField picks what to ask next, or "" when Kiu has enough to build.
func NextField(bp Blueprint, asked int) string {
	for _, f := range QuestionFields {
		if bp.Known(f) {
			continue
		}
		if count(bp.Asked, f) >= maxAsksPerField {
			continue
		}
		if Essential(f) {
			if asked >= HardQuestionLimit {
				continue
			}
		} else if asked >= SoftQuestionLimit {
			continue
		}
		return f
	}
	return ""
}

func count(list []string, v string) int {
	n := 0
	for _, x := range list {
		if x == v {
			n++
		}
	}
	return n
}

// BuildQuestion phrases a question for field. A model-proposed phrasing is used
// only if it targets the same field and passes validation.
func BuildQuestion(bp Blueprint, field, sessionID string, proposed *ProposedQuestion) Question {
	q := localQuestion(bp, field, variant(sessionID, len(bp.Asked)))
	q.Essential = Essential(field)
	if proposed != nil && proposed.Field == field {
		if t := validQuestionText(proposed.Text); t != "" {
			q.Text = t
		}
		if r := cleanCopy(proposed.Reason, 120); r != "" {
			q.Reason = r
		}
	}
	return q
}

func validQuestionText(s string) string {
	s = strings.Join(strings.Fields(s), " ")
	if n := utf8.RuneCountInString(s); n < 8 || n > 200 || !strings.Contains(s, "?") || urlRe.MatchString(s) {
		return ""
	}
	if len(MentionedAmounts(strings.ReplaceAll(s, "2 o 3", ""))) > 0 { // never suggest prices
		return ""
	}
	return s
}

func variant(sessionID string, n int) int {
	h := fnv.New32a()
	_, _ = h.Write([]byte(sessionID))
	return int(h.Sum32()%7) + n
}

// localQuestion phrases one short, self-contained question. No random variants:
// the same field always reads the same, and nothing already answered is asked again.
func localQuestion(bp Blueprint, field string, _ int) Question {
	switch field {
	case FieldName:
		return Question{Field: field,
			Text:   "¿Cómo se llama tu negocio?",
			Reason: "Es lo primero que ve un cliente en tu tienda y en tu enlace."}
	case FieldProducts:
		// One question for names AND prices. The catalog upload is optional and
		// only offered for the online-store flow; other channels get a guide.
		q := Question{Field: field,
			Text:   "¿Qué vendés y a qué precio? Si son pocos (hasta 8), escribilos uno por línea, como «Ramo de rosas ₡15.000».",
			Reason: "Un catálogo con precios claros vende más y te ahorra responder «¿cuánto cuesta?». Solo publico los precios que me das."}
		if bp.OnlineStoreFlow() {
			q.Text += " Si son más, subí tu lista (Excel, CSV o texto): es más rápido."
			q.AllowUpload = true
		} else {
			q.Text += " Si son más, pegá la lista: un producto y su precio por línea."
		}
		return q
	case FieldPrices:
		// Names are known: ask only for the missing prices, never the names again.
		if n := len(bp.Products); n >= ImportThreshold {
			return bulkPricesQuestion(bp, n)
		}
		return Question{Field: field,
			Text:        fmt.Sprintf("Me faltan los precios de %s. ¿Cuánto cuesta cada uno?", examples(bp)),
			Reason:      "Nunca invento precios: solo publico los que me das.",
			AllowUpload: bp.OnlineStoreFlow()}
	case FieldWhatsApp:
		return Question{Field: field,
			Text:   "¿A qué número de WhatsApp te llegan los pedidos? " + whatsappTip,
			Reason: "Cada pedido llega ahí, listo para que cerrés la venta."}
	case FieldDelivery:
		return Question{Field: field,
			Text:   "¿Cómo entregás: a domicilio, retiro o ambas?",
			Reason: "Tus clientes saben cómo recibir su pedido y se animan a comprar.",
			QuickReplies: []QuickReply{
				{Label: "A domicilio", Value: "Entrego a domicilio"},
				{Label: "Retiran", Value: "Los clientes retiran"},
				{Label: "Ambas", Value: "Ambas opciones"},
				{Label: "Omitir", Value: "omitir"},
			}}
	case FieldStyle:
		return Question{Field: field,
			Text:   "¿Qué estilo querés para tu tienda?",
			Reason: "Elijo colores y tipografía accesibles según tu gusto.",
			QuickReplies: []QuickReply{
				{Label: "Elegante y romántico", Value: "Elegante y romántico, en rosado"},
				{Label: "Fresco y natural", Value: "Fresco y natural, en verde menta"},
				{Label: "Divertido y colorido", Value: "Divertido y colorido, en durazno"},
				{Label: "Elegí vos", Value: "omitir"},
			}}
	}
	return Question{Field: field, Text: "¿Me contás un poco más?"}
}

// bulkPricesQuestion is asked when there are many products still unpriced:
// import a list (online store) or paste one product per line (other channels).
func bulkPricesQuestion(bp Blueprint, n int) Question {
	q := Question{Field: FieldPrices, Reason: "Con muchos productos, una lista te ahorra escribirlos uno por uno. Nunca invento precios."}
	if bp.OnlineStoreFlow() {
		q.Text = fmt.Sprintf("Anoté %d productos. Para ponerles precio más rápido, subí una lista con nombre y precio (Excel, CSV o texto).", n)
		q.AllowUpload = true
	} else {
		q.Text = fmt.Sprintf("Anoté %d productos. Pegame los precios en una lista: un producto y su precio por línea.", n)
	}
	return q
}

func firstName(bp Blueprint) string {
	for _, p := range bp.Products {
		if p.PriceMinor == 0 {
			return p.Name
		}
	}
	return "Producto"
}

func examples(bp Blueprint) string {
	var names []string
	for _, p := range bp.Products {
		if p.PriceMinor == 0 && len(names) < 3 {
			names = append(names, strings.ToLower(p.Name))
		}
	}
	switch len(names) {
	case 0:
		return "tus productos"
	case 1:
		return names[0]
	default:
		return strings.Join(names[:len(names)-1], ", ") + " y " + names[len(names)-1]
	}
}

// Ack composes Kiu's short acknowledgement from what actually changed.
func Ack(bp Blueprint, ch Changes, first bool, proposed string) string {
	if r := validReply(proposed); r != "" {
		return r
	}
	var bits []string
	if first && bp.Business.Name != "" {
		bits = append(bits, fmt.Sprintf("¡Qué lindo, %s! Ya empecé a armar tu tienda.", bp.Business.Name))
	} else if first {
		bits = append(bits, "¡Genial! Ya empecé a armar tu tienda.")
	}
	if n := len(ch.NewProducts); n > 0 && ch.PricedProducts == 0 {
		bits = append(bits, fmt.Sprintf("Anoté %d %s.", n, plural(n, "producto", "productos")))
	}
	if ch.PricedProducts > 0 {
		bits = append(bits, fmt.Sprintf("Listo, %d %s con precio.", ch.PricedProducts, plural(ch.PricedProducts, "producto", "productos")))
	}
	if ch.Contact && bp.Contact.WhatsApp != "" && !first {
		bits = append(bits, "Perfecto, los pedidos van a llegar a ese WhatsApp.")
	}
	if ch.Template && bp.Template.ByUser {
		bits = append(bits, "¡Hecho! Cambio tu tienda a "+templateLabel(bp.Template.ID)+".")
	}
	if ch.Delivery && !first && len(bp.Delivery.Modes) > 0 {
		bits = append(bits, "Anotado cómo entregás.")
	}
	if len(bits) == 0 {
		return "¡Anotado!"
	}
	return strings.Join(bits, " ")
}

func validReply(s string) string {
	s = strings.Join(strings.Fields(s), " ")
	if n := utf8.RuneCountInString(s); n < 2 || n > 240 || urlRe.MatchString(s) || strings.Contains(s, "?") {
		return ""
	}
	return s
}

func plural(n int, one, many string) string {
	if n == 1 {
		return one
	}
	return many
}

// missingFields lists open question fields for the model's context.
func missingFields(bp Blueprint) []string {
	var out []string
	for _, f := range QuestionFields {
		if !bp.Known(f) && !slices.Contains(bp.Skipped, f) {
			out = append(out, f)
		}
	}
	return out
}
