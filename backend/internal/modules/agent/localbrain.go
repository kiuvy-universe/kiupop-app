package agent

import (
	"context"
	"regexp"
	"strings"
	"unicode"
	"unicode/utf8"
)

// LocalBrain is Kiu's deterministic Spanish (es-CR) extractor. It runs when no
// AI provider is configured, when the AI budget is spent, or when the model
// fails. It is labelled "local" in the UI: it never pretends to be the model.
type LocalBrain struct{}

// Mode implements Brain.
func (LocalBrain) Mode() string { return "local" }

var (
	nameRe = regexp.MustCompile(`(?i)(?:^|[.!¡,;]\s*|\b)(?:soy|somos|me llamo|mi (?:negocio|tienda|emprendimiento|marca) (?:se llama|es)|se llama|nos llamamos)\s+([^,.;:!?\n]{2,60})`)
	sellRe = regexp.MustCompile(`(?i)\b(?:vendo|vendemos|ofrezco|ofrecemos|hago|hacemos|preparo|preparamos|tengo|tenemos|elaboro|elaboramos|fabrico|fabricamos|dise[nñ]o|dise[nñ]amos|me dedico a|nos dedicamos a|trabajo con|trabajamos con|(?:mi|nuestro) (?:negocio|emprendimiento) es de)\s+([^.;:!?\n]{2,200})`)
	// "Bisutería Luna: aretes, collares…" — a short name followed by a colon and the list.
	colonRe = regexp.MustCompile(`^\s*((?:\p{Lu}[\p{L}'&]*\.?)(?:\s+\p{Lu}?[\p{L}'&]+){0,4})\s*:\s*([^.;!?\n]{2,200})`)
	// "tengo una floristería que se llama…": the noun is not a product.
	ownsRe = regexp.MustCompile(`(?i)^(?:un|una|mi)\s+[\p{L} ]{2,40}?\s+(?:que se llama|llamad[oa])\b`)
	// "atiendo en Escazú", "estamos en Heredia": operating area without delivery words.
	placeRe       = regexp.MustCompile(`(?i)\b(?:atiendo|atendemos|estoy|estamos|ubicad[oa]s?|trabajo|trabajamos|eventos)\s+en\s+`)
	colorPastelRe = regexp.MustCompile(`(?i)\b(?:colores|tonos|tono|color)\s+pastel(?:es)?\b`)
	// Numbers with an explicit country code ("+57 300 123 4567", "0057…").
	// Without "+" or "00" a non-Costa-Rican number is ambiguous, so it is not guessed.
	intlPhoneRe = regexp.MustCompile(`(?:\+|\b00)\s?\d[\d\s\-().]{7,20}\d`)
	phoneRe     = regexp.MustCompile(`(?:\+?\s?506[\s-]?)?\b[2-8]\d{3}[\s-]?\d{4}\b`)
	igRe        = regexp.MustCompile(`(?i)(?:instagram\.com/|@)([a-z0-9._]{2,30})`)
	zonesRe     = regexp.MustCompile(`(?:^|\s)(?:en|a|por|hasta)\s+((?:\p{Lu}[\p{L}]+)(?:(?:\s+(?:de|del|la|las|los|y|e)\s+|\s+|,\s*)\p{Lu}[\p{L}]+)*)`)
	stopAfter   = regexp.MustCompile(`(?i)\s+(?:quiero|quisiera|me gustar[ií]a|entrego|entregamos|envio|envío|enviamos|hago entregas|hacemos entregas|con colores|en colores|colores|estilo|y quiero|para que|que se vea|me llamo|nos llamamos|se llama|mi whatsapp|whatsapp|atiendo|atendemos|estamos en|ubicad[oa])\b.*$`)
	splitList   = regexp.MustCompile(`\s*(?:,|;|\s+y\s+|\s+e\s+|\s+o\s+|\s+/\s+)\s*`)
	leadFiller  = regexp.MustCompile(`(?i)^(?:(?:el|la|los|las|un|una|unos|unas|mis|nuestros|nuestras|todo tipo de|de todo tipo|cada|también|tambien|y)\s+)+`)
	skipRe      = regexp.MustCompile(`(?i)^\s*(?:omitir|saltar|después|despues|luego|más tarde|mas tarde|no s[eé]|ninguno|ninguna|no tengo|paso|no importa|da igual|como quieras|vos eleg[ií]|elig[ei] vos)\s*[.!]*\s*$`)
)

var deliveryWords = []string{"entrego", "entregamos", "entrega", "envio", "envios", "enviamos", "express", "domicilio", "delivery", "llevamos", "llevo", "a la casa"}
var pickupWords = []string{"retiro", "retiran", "retirar", "recoger", "recogen", "pasar a traer", "pasan por", "en el local", "en la tienda", "en tienda"}
var bothWords = []string{"ambas", "ambos", "las dos", "los dos", "las 2", "ambas opciones"}

var styleWords = map[string]string{
	"elegante": "elegante", "romantic": "romantico", "moderno": "moderno", "moderna": "moderno",
	"minimalista": "minimalista", "divertid": "divertido", "natural": "natural", "fresc": "fresco",
	"juvenil": "juvenil", "rustic": "rustico", "lujos": "lujoso", "colorid": "colorido",
	"delicad": "delicado", "sencill": "minimalista", "alegre": "divertido", "tierno": "delicado",
}
var colorWords = map[string]string{
	"rosad": "rosado", "rosa ": "rosado", "pink": "rosado", "fucsia": "rosado", "chicle": "rosado",
	"verde": "verde", "menta": "verde", "durazno": "durazno", "melocoton": "durazno", "coral": "durazno",
	"naranja": "durazno", "anaranjad": "durazno", "salmon": "durazno", "peach": "durazno",
	"morad": "lila", "lila": "lila", "lavanda": "lila", "azul": "celeste", "celeste": "celeste",
	"amarill": "amarillo", "dorad": "dorado", "blanco": "blanco", "negro": "negro",
}
var categoryWords = []struct {
	cat   string
	words []string
}{
	{"flores", []string{"flor", "ramo", "arreglo", "girasol", "rosas", "orquidea"}},
	{"reposteria", []string{"pastel", "queque", "reposter", "galleta", "postre", "cupcake", "brownie", "dulce"}},
	{"comida", []string{"comida", "almuerzo", "casado", "soda", "empanada", "tamal", "pizza", "hamburguesa", "cafe", "restaurante", "bocadillo"}},
	{"ropa", []string{"ropa", "blusa", "vestido", "camisa", "zapato", "moda", "boutique", "tenis"}},
	{"belleza", []string{"maquillaje", "unas", "belleza", "cosmetic", "skincare", "pestana", "cabello", "jabon"}},
	{"artesania", []string{"artesan", "bisuter", "joya", "arete", "pulsera", "collar", "tejid", "velas"}},
	{"mascotas", []string{"mascota", "perro", "gato", "veterinari"}},
	{"plantas", []string{"planta", "suculenta", "vivero", "jardin", "macetas"}},
	{"tecnologia", []string{"celular", "tecnolog", "computadora", "laptop", "audifono", "cargador"}},
}
var paymentWords = map[string]string{"sinpe": "SINPE Móvil", "efectivo": "Efectivo", "transferencia": "Transferencia bancaria", "tarjeta": "Tarjeta"}

// Understand implements Brain.
func (LocalBrain) Understand(_ context.Context, in TurnInput) (Extraction, []Usage, error) {
	text := strings.TrimSpace(in.Text)
	ft := " " + fold(text) + " "
	var ex Extraction
	pending := ""
	if in.Pending != nil {
		pending = in.Pending.Field
	}

	if skipRe.MatchString(text) {
		ex.SkipPending = true
		return ex, nil, nil
	}
	if strings.Contains(ft, "publica") {
		ex.WantsPublish = true
	}

	// Phones first, so their digits are never read as prices.
	priceText := text
	for _, m := range phoneRe.FindAllString(text, -1) {
		if ex.WhatsApp == "" {
			ex.WhatsApp = m
		}
		priceText = strings.Replace(priceText, m, " ", 1)
	}

	if ex.WhatsApp == "" {
		if m := intlPhoneRe.FindString(text); m != "" {
			if _, ok := NormalizeWhatsApp(m); ok {
				ex.WhatsApp = m
				priceText = strings.Replace(priceText, m, " ", 1)
			}
		}
	}

	// Name. Digits inside the name ("Pulpería 2000") are never prices.
	for _, m := range nameRe.FindAllStringSubmatch(text, -1) {
		if ex.BusinessName = cleanName(m[1]); ex.BusinessName != "" {
			break
		}
	}
	colon := colonRe.FindStringSubmatch(text)
	if ex.BusinessName == "" && colon != nil {
		ex.BusinessName = cleanName(colon[1])
	}
	if ex.BusinessName != "" {
		priceText = strings.Replace(priceText, ex.BusinessName, " ", 1)
	}
	if ex.BusinessName == "" && pending == FieldName {
		ex.BusinessName = cleanName(text)
	}

	// Products (names) and prices. Button/command replies are never products.
	if isCommandReply(text) {
		return ex, nil, nil
	}
	if list := sellList(text); list != "" {
		ex.Products = append(ex.Products, listProducts(list)...)
	} else if colon != nil && len(MentionedAmounts(colon[2])) == 0 {
		ex.Products = append(ex.Products, listProducts(stopAfter.ReplaceAllString(colon[2], ""))...)
	} else if pending == FieldProducts && len(MentionedAmounts(priceText)) == 0 {
		ex.Products = append(ex.Products, listProducts(text)...)
	}
	ex.Products = mergeExtracted(ex.Products, pricedProducts(priceText, pending == FieldPrices))

	// Delivery.
	d, p, both := containsAny(ft, deliveryWords), containsAny(ft, pickupWords), containsAny(ft, bothWords)
	switch {
	case both && pending == FieldDelivery, d && p:
		ex.DeliveryModes = []string{"delivery", "pickup"}
	case d:
		ex.DeliveryModes = []string{"delivery"}
	case p:
		ex.DeliveryModes = []string{"pickup"}
	}
	if len(ex.DeliveryModes) > 0 || pending == FieldDelivery || placeRe.MatchString(text) {
		ex.Zones = zones(deliverySentences(text, pending == FieldDelivery))
	}

	// Branding.
	ex.Styles = matchWords(ft, styleWords)
	ex.Colors = matchWords(ft, colorWords)
	if colorPastelRe.MatchString(text) {
		ex.Colors = append(ex.Colors, "pastel")
	}
	for _, t := range []struct{ word, id string }{{"bubblegum", "bubblegum_pink"}, {"mint", "mint_fresh"}, {"peach", "peach_pop"}} {
		if strings.Contains(ft, t.word) {
			ex.TemplateChoice = t.id
		}
	}

	// Category, payments, socials.
	ex.Category = category(" " + fold(colorPastelRe.ReplaceAllString(text, " ")) + " ")
	for k, v := range paymentWords {
		if strings.Contains(ft, k) {
			ex.PaymentMethods = append(ex.PaymentMethods, v)
		}
	}
	if m := igRe.FindStringSubmatch(text); m != nil && (strings.Contains(ft, "instagram") || strings.Contains(text, "@")) {
		ex.Instagram = m[1]
	}
	return ex, nil, nil
}

// sellList returns the product list after the last selling verb of its sentence
// ("tengo una floristería…, hacemos ramos y arreglos" → "ramos y arreglos").
func sellList(text string) string {
	for _, sentence := range regexp.MustCompile(`[.;!?\n]+`).Split(text, -1) {
		ms := sellRe.FindAllStringSubmatchIndex(sentence, -1)
		for i := len(ms) - 1; i >= 0; i-- {
			list := sentence[ms[i][2]:ms[i][3]]
			// A later clause may hold the real list: "…, hacemos ramos y arreglos".
			for _, clause := range strings.Split(list, ",")[1:] {
				if inner := sellRe.FindStringSubmatch(clause); inner != nil {
					list = inner[1]
					break
				}
			}
			if ownsRe.MatchString(list) {
				continue // "tengo una floristería que se llama…"
			}
			list = stopAfter.ReplaceAllString(list, "")
			list = regexp.MustCompile(`\s+(?:en|para eventos en)\s+\p{Lu}.*$`).ReplaceAllString(list, "")
			if strings.TrimSpace(list) != "" {
				return list
			}
		}
	}
	return ""
}

func cleanName(s string) string {
	s = stopAfter.ReplaceAllString(s, "")
	s = regexp.MustCompile(`(?i)\s+y\s+(?:vendo|vendemos|hago|hacemos|ofrezco|ofrecemos|tengo|tenemos)\b.*$`).ReplaceAllString(s, "")
	s = strings.Trim(strings.TrimSpace(s), `"'«»“”.!¡`)
	low := fold(s)
	for _, bad := range []string{"de ", "un ", "una ", "el ", "la ", "yo ", "muy ", "nuevo", "nueva", "emprendedor", "emprendedora", "duen"} {
		if strings.HasPrefix(low, bad) {
			return ""
		}
	}
	words := strings.Fields(s)
	if len(words) == 0 || len(words) > 6 || utf8.RuneCountInString(s) > 60 {
		return ""
	}
	return titleIfLower(strings.Join(words, " "))
}

func titleIfLower(s string) string {
	if s != strings.ToLower(s) {
		return s
	}
	words := strings.Fields(s)
	for i, w := range words {
		if i > 0 && (w == "de" || w == "del" || w == "la" || w == "las" || w == "los" || w == "y") {
			continue
		}
		r := []rune(w)
		r[0] = unicode.ToUpper(r[0])
		words[i] = string(r)
	}
	return strings.Join(words, " ")
}

func capFirst(s string) string {
	r := []rune(strings.TrimSpace(s))
	if len(r) == 0 {
		return ""
	}
	r[0] = unicode.ToUpper(r[0])
	return string(r)
}

func listProducts(s string) []ExtractedProduct {
	var out []ExtractedProduct
	var parts []string
	for _, part := range splitList.Split(s, -1) {
		// "corte para perros y gatos": a single word right after "para/de X" belongs to it.
		if n := len(parts); n > 0 && len(strings.Fields(part)) == 1 &&
			regexp.MustCompile(`(?i)\s(?:para|de|con)\s+\S+$`).MatchString(parts[n-1]) {
			parts[n-1] += " y " + strings.TrimSpace(part)
			continue
		}
		parts = append(parts, part)
	}
	for _, part := range parts {
		part = strings.TrimSpace(leadFiller.ReplaceAllString(strings.TrimSpace(part), ""))
		part = strings.Trim(part, ".!¡?¿\"'")
		n := utf8.RuneCountInString(part)
		if n < 2 || n > 60 || len(strings.Fields(part)) > 7 {
			continue
		}
		out = append(out, ExtractedProduct{Name: capFirst(part)})
	}
	return out
}

var priceFiller = regexp.MustCompile(`(?i)(?:\s*(?:a|en|por|de|cuesta|cuestan|vale|valen|sale|salen|precio|₡|c|colones|:|-|=|\$))+\s*$`)
var segmentCut = regexp.MustCompile(`(?i)(?:,|;|\n|\.\s|\s+y\s+|\s+e\s+)`)

// pricedProducts reads "Ramo de rosas 15000, arreglo 18 mil y caja ₡12.500".
func pricedProducts(text string, expectingPrices bool) []ExtractedProduct {
	var out []ExtractedProduct
	matches := amountRe.FindAllStringSubmatchIndex(text, -1)
	prev := 0
	for _, m := range matches {
		v, ok := parseAmount(text[m[2]:m[3]], substr(text, m[4], m[5]))
		seg := text[prev:m[0]]
		prev = m[1]
		if !ok || v < 100 {
			continue
		}
		if locs := segmentCut.FindAllStringIndex(seg, -1); len(locs) > 0 {
			seg = seg[locs[len(locs)-1][1]:]
		}
		seg = strings.TrimSpace(priceFiller.ReplaceAllString(seg, ""))
		seg = strings.TrimSpace(leadFiller.ReplaceAllString(seg, ""))
		if utf8.RuneCountInString(seg) < 2 || len(strings.Fields(seg)) > 7 {
			if expectingPrices {
				out = append(out, ExtractedProduct{PriceColones: v}) // unnamed: may fill a single unpriced product
			}
			continue
		}
		out = append(out, ExtractedProduct{Name: capFirst(seg), PriceColones: v})
	}
	return out
}

func substr(s string, a, b int) string {
	if a < 0 || b < 0 {
		return ""
	}
	return s[a:b]
}

// mergeExtracted combines named products with priced mentions of the same product.
func mergeExtracted(names, priced []ExtractedProduct) []ExtractedProduct {
	out := append([]ExtractedProduct(nil), names...)
	for _, p := range priced {
		merged := false
		for i := range out {
			if p.Name != "" && sameProduct(out[i].Name, p.Name) {
				if out[i].PriceColones == 0 {
					out[i].PriceColones = p.PriceColones
				}
				merged = true
				break
			}
		}
		if !merged {
			out = append(out, p)
		}
	}
	return out
}

func containsAny(ft string, words []string) bool {
	for _, w := range words {
		if strings.Contains(ft, " "+w) {
			return true
		}
	}
	return false
}

func matchWords(ft string, dict map[string]string) []string {
	seen := map[string]bool{}
	var out []string
	for k, v := range dict {
		if strings.Contains(ft, " "+k) && !seen[v] {
			seen[v] = true
			out = append(out, v)
		}
	}
	sortStrings(out)
	return out
}

func category(ft string) string {
	for _, c := range categoryWords {
		for _, w := range c.words {
			if strings.Contains(ft, w) {
				return c.cat
			}
		}
	}
	return ""
}

func zones(text string) []string {
	var out []string
	seen := map[string]bool{}
	for _, m := range zonesRe.FindAllStringSubmatch(text, -1) {
		for _, z := range splitList.Split(m[1], -1) {
			z = strings.TrimSpace(z)
			if z == "" || len(strings.Fields(z)) > 4 || seen[fold(z)] || isNonPlace(z) {
				continue
			}
			seen[fold(z)] = true
			out = append(out, z)
		}
	}
	if len(out) > MaxZones {
		out = out[:MaxZones]
	}
	return out
}

// deliverySentences keeps only the sentences that talk about delivery or pickup.
func deliverySentences(text string, all bool) string {
	if all {
		return text
	}
	var keep []string
	for _, s := range regexp.MustCompile(`[.!?;\n]+`).Split(text, -1) {
		fs := " " + fold(s) + " "
		if containsAny(fs, deliveryWords) || containsAny(fs, pickupWords) || placeRe.MatchString(s) {
			keep = append(keep, s)
		}
	}
	return strings.Join(keep, ". ")
}

func isNonPlace(z string) bool {
	switch fold(z) {
	case "whatsapp", "instagram", "facebook", "sinpe", "costa rica", "kiu", "kiupop", "correos", "correos de costa rica":
		return true
	}
	return false
}
