package agent

import (
	"context"
	"fmt"
	"regexp"
	"slices"
	"strings"
	"unicode"
)

// Discovery (KIU_DISCOVERY_ENABLED): before building anything Kiu asks a few
// filter questions (what you sell, where customers buy today, what hurts most),
// recommends how to sell with a deterministic rules matrix and only starts
// building once the merchant accepts the plan ("Sí, armemos esto") or says they
// already know what they want. The model never decides the recommendation: it
// is a pure function of the merchant's answers (see RecommendPlan).
//
// Discovery lives inside the blueprint JSONB: no migration, and a nil
// Discovery behaves exactly like the original flow (sessions started with the
// flag off, or before it existed).

// Discovery states.
const (
	DiscoveryAsking   = "asking"   // collecting the filter answers
	DiscoveryProposed = "proposed" // plan shown, waiting for the merchant's OK
	DiscoveryAccepted = "accepted" // merchant accepted the plan: build
	DiscoverySkipped  = "skipped"  // "Ya sé lo que quiero": build right away
)

// Discovery question fields (FieldProducts doubles as "what do you sell?").
const (
	FieldChannels = "channels"
	FieldPain     = "pain"
)

// Sales channels a merchant can use today (closed list).
const (
	ChannelWhatsApp  = "whatsapp"
	ChannelInstagram = "instagram"
	ChannelFacebook  = "facebook"
	ChannelInPerson  = "presencial"
	ChannelNone      = "ninguno"
)

// Main pains (closed list).
const (
	PainPrices   = "precios"     // answering prices one by one
	PainReach    = "visibilidad" // new customers don't find me
	PainOrders   = "pedidos"     // orders arrive messy
	PainPayments = "cobros"      // collecting payments
	PainStarting = "empezar"     // just starting
)

// Quick-reply values that drive the discovery state machine.
const (
	ReplyAcceptPlan = "Sí, armemos esto"
	ReplyChangePlan = "Quiero cambiar algo"
	ReplyKnowWhat   = "Ya sé lo que quiero, armá mi tienda"
)

// Discovery is the merchant's diagnosis, stored in the blueprint.
type Discovery struct {
	Status   string   `json:"status"`
	Channels []string `json:"channels"` // where customers buy today
	Pain     string   `json:"pain"`     // what hurts most
	Asked    []string `json:"asked"`    // discovery fields already asked (each at most once)
	Plan     *Plan    `json:"plan,omitempty"`
	Nudged   bool     `json:"nudged,omitempty"` // «Cuando quieras…» already said since the merchant's last turn
}

// Plan is Kiu's recommendation. Every sentence comes from the rules matrix;
// nothing about the merchant is invented (only the business name is used).
type Plan struct {
	Problem        string   `json:"problem"`
	Recommendation string   `json:"recommendation"`
	Reason         string   `json:"reason"`
	Note           string   `json:"note,omitempty"` // honest caveat
	Actions        []string `json:"actions"`        // first week
	Goal           string   `json:"goal"`
	KitChannels    []string `json:"kit_channels"`    // which ready-to-paste texts to hand over at publish
	Guide          []string `json:"guide,omitempty"` // how to set up the catalog in the merchant's channel
}

// OnlineStoreFlow reports whether the merchant is getting an online store as
// the main thing: no diagnosis (flag off / old session), "Ya sé lo que quiero",
// or no channel yet. Merchants who already sell on WhatsApp, Instagram,
// Facebook or in person get a recommendation and a how-to guide instead of a
// catalog upload.
func (b Blueprint) OnlineStoreFlow() bool {
	d := b.Discovery
	if d == nil || d.Status == DiscoverySkipped {
		return true
	}
	for _, c := range d.Channels {
		if c != ChannelNone {
			return false
		}
	}
	return true
}

// Active reports whether Kiu is still diagnosing (nothing may be built yet).
func (d *Discovery) Active() bool {
	return d != nil && (d.Status == DiscoveryAsking || d.Status == DiscoveryProposed)
}

func (d *Discovery) known(bp Blueprint, field string) bool {
	switch field {
	case FieldProducts:
		return len(bp.Products) > 0 || bp.Business.Category != ""
	case FieldChannels:
		return len(d.Channels) > 0
	case FieldPain:
		return d.Pain != ""
	}
	return true
}

// nextDiscoveryField returns the next filter question, or "" when Kiu can
// recommend. Each field is asked at most once: unclear answers never loop.
func nextDiscoveryField(bp Blueprint) string {
	d := bp.Discovery
	for _, f := range []string{FieldProducts, FieldChannels, FieldPain} {
		if !d.known(bp, f) && !slices.Contains(d.Asked, f) {
			return f
		}
	}
	return ""
}

// notProductRe matches button/command replies and bare yes/no answers: they
// steer the conversation and must never become a product name.
var notProductRe = regexp.MustCompile(`(?i)^\s*¡?(s[ií]|no|ok|okay|dale|listo|omitir|despu[eé]s|ya s[eé] lo que quiero.*|s[ií],? armemos esto|quiero cambiar algo|cambiar algo|arm[aá] (mi|la) tienda.*)[\s.!¡]*$`)

// isCommandReply reports whether text is a conversation command, not content.
func isCommandReply(text string) bool {
	t := strings.TrimSpace(text)
	return knowWhatOnlyRe.MatchString(t) || notProductRe.MatchString(t) || t == ReplyAcceptPlan || t == ReplyChangePlan
}

var knowWhatRe = regexp.MustCompile(`(?i)\b(ya s[eé] lo que quiero|arm[aá] (mi|la) tienda (ya|de una)|sin preguntas|directo a la tienda)\b`)

// knowWhatOnlyRe is the same command as the whole message: «Vendo velas, ya
// sé lo que quiero» still carries content that must be extracted.
var knowWhatOnlyRe = regexp.MustCompile(`(?i)^\s*[¡!]?\s*(ya s[eé] lo que quiero|arm[aá] (mi|la) tienda (ya|de una)|sin preguntas|directo a la tienda)\s*[.!]*\s*$`)
var acceptRe = regexp.MustCompile(`(?i)^\s*¡?(s[ií]|dale|de una|listo|okay|ok|va|claro|perfecto|acepto|me parece|me gusta|armemos|arm[aá]la|hag[aá]moslo|vamos|adelante)(?:[\s,.!¡]|$)`)

// changeRe is checked before acceptRe, so «Sí, pero cambiá el canal» is a change.
// RE2's \b is ASCII-only, hence the explicit letter classes around voseo forms.
var changeRe = regexp.MustCompile(`(?i)(^|[^\p{L}])(cambi\p{L}*|correg\p{L}*|no me convence|otra cosa|pero|mejor)([^\p{L}]|$)`)

var channelWords = []struct {
	channel string
	words   []string
}{
	{ChannelWhatsApp, []string{"whatsapp", "whats", "wasap", "guasap", "wpp"}},
	{ChannelInstagram, []string{"instagram", "insta", " ig "}},
	{ChannelFacebook, []string{"facebook", " fb ", "face ", "marketplace"}},
	{ChannelInPerson, []string{"en persona", "presencial", "local", "feria", "puesto", "mostrador", "tienda fisica", "vecino", "conocido", "boca a boca", "puerta a puerta", "en la calle"}},
	{ChannelNone, []string{"todavia no vendo", "aun no vendo", "no vendo", "todavia no", "aun no", "apenas empiezo", "estoy empezando", "voy empezando", "no he empezado"}},
}

var painWords = []struct {
	pain  string
	words []string
}{
	{PainPrices, []string{"precio", "lo mismo", "uno por uno", "preguntan", "cotiz", "responder"}},
	{PainReach, []string{"encuentr", "conoce", "clientes nuevos", "nuevos clientes", "visibil", "vender mas", "llegar a mas", "alcance"}},
	{PainOrders, []string{"pedido", "orden", "desorden", "anotar", "organiz", "se me pasan"}},
	{PainPayments, []string{"cobr", "pago", "sinpe", "transfer"}},
	{PainStarting, []string{"empez", "inici", "no se por donde", "arrancando"}},
}

// ParseChannels reads where the merchant sells today (closed list).
// words folds text into space-separated letter/digit tokens padded with spaces,
// so phrases match whole words: «insta» never matches «instalación».
func words(text string) string {
	return " " + strings.Join(strings.FieldsFunc(fold(text), func(r rune) bool {
		return !unicode.IsLetter(r) && !unicode.IsDigit(r)
	}), " ") + " "
}

// hasWord reports whether phrase w (or its plural) appears as whole words in ft.
func hasWord(ft, w string) bool {
	w = strings.TrimSpace(w)
	return strings.Contains(ft, " "+w+" ") || strings.Contains(ft, " "+w+"s ")
}

func ParseChannels(text string) []string {
	ft := words(text)
	var out []string
	for _, c := range channelWords {
		for _, w := range c.words {
			if hasWord(ft, w) {
				out = append(out, c.channel)
				break
			}
		}
	}
	if len(out) > 1 { // "todavía no" next to a real channel is not "none"
		out = slices.DeleteFunc(out, func(c string) bool { return c == ChannelNone })
	}
	return out
}

// ParsePain reads the merchant's main pain (first match wins, closed list).
func ParsePain(text string) string {
	ft := words(text)
	for _, p := range painWords {
		for _, w := range p.words {
			if strings.Contains(ft, w) { // pain words are stems («cobr», «empez»)
				return p.pain
			}
		}
	}
	return ""
}

// discoveryOutcome says what a turn did to the diagnosis.
type discoveryOutcome int

const (
	discoveryContinue discoveryOutcome = iota // still asking or proposing
	discoveryBuild                            // accepted or skipped: start building now
)

// stepDiscovery updates the diagnosis from one merchant turn. pending is the
// field Kiu had asked. Channels and pain are only read when Kiu asked for them
// (or while reviewing the plan): "mi WhatsApp es 8888…" in the first message is
// a contact, not a sales channel. An omitted question is not asked again.
func stepDiscovery(bp *Blueprint, text, pending string) discoveryOutcome {
	d := bp.Discovery
	d.Nudged = false
	if knowWhatRe.MatchString(text) {
		d.Status = DiscoverySkipped
		return discoveryBuild
	}
	if d.Status == DiscoveryProposed {
		switch {
		case changeRe.MatchString(text):
			d.Channels, d.Pain, d.Plan = nil, "", nil
			d.Asked = slices.DeleteFunc(d.Asked, func(f string) bool { return f == FieldChannels || f == FieldPain })
			d.Status = DiscoveryAsking
			return discoveryContinue
		case acceptRe.MatchString(text):
			d.Status = DiscoveryAccepted
			return discoveryBuild
		}
	}
	changed := false
	reviewing := d.Status == DiscoveryProposed
	if ch := ParseChannels(text); len(ch) > 0 && (pending == FieldChannels || reviewing) {
		for _, c := range ch {
			if !slices.Contains(d.Channels, c) {
				d.Channels = append(d.Channels, c)
				changed = true
			}
		}
		if len(d.Channels) > 1 {
			d.Channels = slices.DeleteFunc(d.Channels, func(c string) bool { return c == ChannelNone })
		}
	}
	if p := ParsePain(text); p != "" && (pending == FieldPain || reviewing) && p != d.Pain {
		d.Pain = p
		changed = true
	}
	if reviewing && changed {
		d.Status = DiscoveryAsking // re-recommend with the new answer
	}
	return discoveryContinue
}

// discoveryQuestion phrases a filter question (always with its reason).
func discoveryQuestion(bp Blueprint, field string) Question {
	name := bp.Business.Name
	switch field {
	case FieldProducts:
		return Question{Field: field,
			Text:   "¿Qué vendés? Contame tus productos o servicios principales.",
			Reason: "Con eso entiendo tu negocio antes de recomendarte algo.",
			QuickReplies: []QuickReply{
				{Label: "Ya sé lo que quiero", Value: ReplyKnowWhat},
			}}
	case FieldChannels:
		who := "tus clientes"
		if name != "" {
			who = "los clientes de " + name
		}
		return Question{Field: field,
			Text:   fmt.Sprintf("¿Por dónde te compran hoy %s?", who),
			Reason: "Así te recomiendo el canal que de verdad te sirve; quizá no necesitás una página web.",
			QuickReplies: []QuickReply{
				{Label: "WhatsApp", Value: "Me compran por WhatsApp"},
				{Label: "Instagram", Value: "Me compran por Instagram"},
				{Label: "Facebook", Value: "Me compran por Facebook"},
				{Label: "En persona", Value: "Me compran en persona"},
				{Label: "Todavía no vendo", Value: "Todavía no vendo"},
				{Label: "Ya sé lo que quiero", Value: ReplyKnowWhat},
			}}
	case FieldPain:
		return Question{Field: field,
			Text:   "¿Qué es lo que más te cuesta hoy al vender?",
			Reason: "Quiero que lo que armemos resuelva tu problema principal.",
			QuickReplies: []QuickReply{
				{Label: "Responder precios uno por uno", Value: "Responder precios uno por uno"},
				{Label: "Que me encuentren clientes nuevos", Value: "Que me encuentren clientes nuevos"},
				{Label: "Ordenar los pedidos", Value: "Ordenar los pedidos"},
				{Label: "Cobrar", Value: "Cobrar"},
				{Label: "Estoy empezando", Value: "Estoy empezando"},
				{Label: "Ya sé lo que quiero", Value: ReplyKnowWhat},
			}}
	}
	return Question{Field: field, Text: "¿Me contás un poco más?"}
}

// RecommendPlan is the rules matrix: (channels × pain) → recommendation,
// first-week actions and the ready-to-paste kit. Deterministic and honest.
func RecommendPlan(bp Blueprint) Plan {
	d := bp.Discovery
	has := func(c string) bool { return slices.Contains(d.Channels, c) }
	social := has(ChannelInstagram) || has(ChannelFacebook)

	var p Plan
	switch {
	case social:
		var nets []string
		if has(ChannelInstagram) {
			nets = append(nets, "Instagram")
		}
		if has(ChannelFacebook) {
			nets = append(nets, "Facebook")
		}
		p.Recommendation = fmt.Sprintf("Un catálogo con tus precios, enlazado desde tu perfil de %s, y que los pedidos te lleguen directo a tu WhatsApp.", strings.Join(nets, " y "))
	case has(ChannelWhatsApp):
		p.Recommendation = "Un catálogo con tus precios que compartís por WhatsApp: en tus estados, como respuesta rápida y en un mensaje fijado."
	case has(ChannelInPerson):
		p.Recommendation = "Un catálogo con un enlace corto para tu mostrador o tu puesto, y que los pedidos te lleguen por WhatsApp."
	default:
		p.Recommendation = "Empezá simple: un catálogo con tus precios que compartís por WhatsApp con tus primeros clientes."
	}
	if !social {
		p.Note = "No necesitás una página web completa ni pagar publicidad: tu catálogo es un enlace que compartís donde ya hablás con tus clientes."
	}

	switch d.Pain {
	case PainPrices:
		p.Problem = "Perdés tiempo (y ventas) respondiendo precios uno por uno."
		p.Reason = "Con el catálogo cada cliente ve productos y precios solo, y te escribe ya decidido."
	case PainReach:
		p.Problem = "Tus productos no están llegando a clientes nuevos."
		p.Reason = "Un enlace corto se comparte fácil: cada persona que lo reenvía te puede traer un cliente."
	case PainOrders:
		p.Problem = "Los pedidos te llegan desordenados y se te pueden pasar."
		p.Reason = "Cada pedido te llega por WhatsApp con productos, cantidades y total, siempre en el mismo formato."
	case PainPayments:
		p.Problem = "Cobrar y confirmar pagos te quita tiempo."
		p.Reason = "Tu tienda muestra cómo coordinás el pago (por ejemplo SINPE Móvil). Te soy honesto: KiuPop todavía no cobra en línea por vos."
	case PainStarting:
		p.Problem = "Estás empezando y necesitás una forma simple de mostrar lo que vendés."
		p.Reason = "No necesitás inversión: con un enlace y tu WhatsApp ya podés recibir pedidos."
	default:
		p.Problem = "Querés que vender te cueste menos tiempo."
		p.Reason = "Tus clientes ven todo en un solo lugar y te piden por WhatsApp."
	}

	var actions []string
	add := func(a string) {
		if a != "" && !slices.Contains(actions, a) && len(actions) < 3 {
			actions = append(actions, a)
		}
	}
	switch d.Pain {
	case PainPrices:
		add("Cuando te pregunten precios, respondé con el enlace de tu catálogo.")
	case PainOrders:
		add("Pedile a tus clientes que pidan desde el catálogo, así todos los pedidos llegan igual.")
	case PainPayments:
		add("Escribime cómo cobrás (SINPE Móvil, efectivo…) para que tu tienda lo explique.")
	}
	if has(ChannelInstagram) {
		add("Poné el enlace en la bio de Instagram y compartilo en una historia.")
	}
	if has(ChannelFacebook) {
		add("Fijá una publicación con el enlace en tu página de Facebook.")
	}
	if has(ChannelWhatsApp) || !social {
		add("Guardá el enlace como respuesta rápida en WhatsApp Business.")
		add("Publicá tu catálogo en 3 estados de WhatsApp esta semana.")
	}
	if has(ChannelInPerson) {
		add("Escribí el enlace en un cartel en tu mostrador o puesto.")
	}
	add("Mandale el enlace a 10 contactos que te podrían comprar.")
	p.Actions = actions
	p.Goal = "Tus primeros 5 pedidos desde el enlace en la primera semana."

	p.Guide = channelGuide(d.Channels)
	p.KitChannels = []string{ChannelWhatsApp} // orders always arrive by WhatsApp
	for _, c := range []string{ChannelInstagram, ChannelFacebook, ChannelInPerson} {
		if has(c) {
			p.KitChannels = append(p.KitChannels, c)
		}
	}
	return p
}

// channelGuide gives short, generic how-to steps per channel. Menu names in
// third-party apps change, so the steps say what to do, not exact buttons.
func channelGuide(channels []string) []string {
	var g []string
	for _, c := range channels {
		switch c {
		case ChannelWhatsApp:
			g = append(g, "WhatsApp Business: en el menú de herramientas abrí «Catálogo» y agregá cada producto con foto, nombre y precio (la ubicación puede variar según tu versión).")
		case ChannelInstagram:
			g = append(g, "Instagram: publicá una foto por producto con nombre y precio en el texto, y guardalas en una historia destacada llamada «Catálogo».")
		case ChannelFacebook:
			g = append(g, "Facebook: creá un álbum «Catálogo» con una foto por producto (nombre y precio en la descripción) y fijá la publicación.")
		case ChannelInPerson:
			g = append(g, "En persona: imprimí una lista con nombre y precio de cada producto y pegala en tu mostrador junto al enlace.")
		}
	}
	return g
}

// PriceListText is a paste-ready price list built only from the products and
// prices the merchant gave (nothing invented).
func PriceListText(bp Blueprint) string {
	var b strings.Builder
	for _, p := range bp.PricedProducts() {
		fmt.Fprintf(&b, "• %s — ₡%s\n", p.Name, thousands(p.PriceMinor/100))
	}
	return strings.TrimRight(b.String(), "\n")
}

// PlanText renders the plan as Kiu's chat message.
func PlanText(bp Blueprint, p Plan) string {
	var b strings.Builder
	if bp.Business.Name != "" {
		fmt.Fprintf(&b, "Esto es lo que entendí de %s y lo que te recomiendo:\n\n", bp.Business.Name)
	} else {
		b.WriteString("Esto es lo que entendí y lo que te recomiendo:\n\n")
	}
	fmt.Fprintf(&b, "📌 El problema: %s\n", p.Problem)
	fmt.Fprintf(&b, "✅ Mi recomendación: %s\n", p.Recommendation)
	fmt.Fprintf(&b, "💡 Por qué: %s\n", p.Reason)
	if p.Note != "" {
		fmt.Fprintf(&b, "🙌 %s\n", p.Note)
	}
	b.WriteString("\nTu primera semana:\n")
	for i, a := range p.Actions {
		fmt.Fprintf(&b, "%d. %s\n", i+1, a)
	}
	if len(p.Guide) > 0 {
		b.WriteString("\nCómo armar tu catálogo en tu canal:\n")
		for _, g := range p.Guide {
			fmt.Fprintf(&b, "• %s\n", g)
		}
		b.WriteString("Yo te dejo la lista de precios lista para pegar cuando termines.\n")
	}
	fmt.Fprintf(&b, "🎯 Meta: %s\n\n", p.Goal)
	b.WriteString("¿Armamos esto? Recién ahí empiezo a construir.")
	return b.String()
}

func planReplies() []QuickReply {
	return []QuickReply{{Label: "Sí, armemos esto", Value: ReplyAcceptPlan}, {Label: "Cambiar algo", Value: ReplyChangePlan}}
}

// discoveryAck acknowledges a discovery turn without promising any build.
func discoveryAck(bp Blueprint, first bool) string {
	if first && bp.Business.Name != "" {
		return fmt.Sprintf("¡Qué lindo, %s! Antes de armar nada quiero entender cómo vendés, para recomendarte lo que de verdad te sirva.", bp.Business.Name)
	}
	if first {
		return "¡Genial! Antes de armar nada quiero entender cómo vendés, para recomendarte lo que de verdad te sirva."
	}
	return "¡Anotado!"
}

// KitText is the ready-to-paste kit handed over at publish (only the business
// name and the share link are filled in: nothing invented).
func KitText(bp Blueprint, shareURL string) string {
	if bp.Discovery == nil || bp.Discovery.Plan == nil || shareURL == "" {
		return ""
	}
	name := bp.Business.Name
	if name == "" {
		name = "mi negocio"
	}
	var b strings.Builder
	b.WriteString("Tu kit para vender, listo para copiar y pegar:\n")
	if list := PriceListText(bp); list != "" && len(bp.Discovery.Plan.Guide) > 0 {
		fmt.Fprintf(&b, "\n📋 Lista de precios (para tu catálogo, estados o cartel):\n%s\n", list)
	}
	for _, c := range bp.Discovery.Plan.KitChannels {
		switch c {
		case ChannelWhatsApp:
			fmt.Fprintf(&b, "\n💬 WhatsApp (respuesta rápida o estado):\n«¡Hola! Te comparto el catálogo de %s con precios: %s Pedís desde ahí y me llega por WhatsApp.»\n", name, shareURL)
		case ChannelInstagram:
			fmt.Fprintf(&b, "\n📸 Bio de Instagram:\n«Catálogo y pedidos 👇 %s»\n", shareURL)
		case ChannelFacebook:
			fmt.Fprintf(&b, "\n📘 Publicación fijada en Facebook:\n«Ya podés ver todo el catálogo de %s y pedir directo: %s»\n", name, shareURL)
		case ChannelInPerson:
			fmt.Fprintf(&b, "\n🏪 Cartel para tu mostrador:\n«Mirá el catálogo y pedí por WhatsApp: %s»\n", shareURL)
		}
	}
	return strings.TrimRight(b.String(), "\n")
}

func newDiscovery() *Discovery {
	return &Discovery{Status: DiscoveryAsking, Channels: []string{}, Asked: []string{}}
}

// discover asks the next filter question or proposes the plan. Called while
// discovery is active, after Kiu's acknowledgement.
func (s *Service) discover(ctx context.Context, t *Tx, mode string) error {
	bp := &t.S.Blueprint
	d := bp.Discovery
	if bp.Pending != nil {
		return nil // a question is already open (e.g. a photo arrived meanwhile)
	}
	if f := nextDiscoveryField(*bp); f != "" {
		q := discoveryQuestion(*bp, f)
		bp.Pending = &q
		d.Asked = append(d.Asked, f)
		return s.say(ctx, t, q.Text, MessageMeta{Kind: "question", Question: &q, QuickReplies: q.QuickReplies, BrainMode: mode})
	}
	if d.Status == DiscoveryProposed && d.Plan != nil {
		if d.Nudged {
			return nil // already reminded since the merchant's last turn (e.g. several photos arrived)
		}
		d.Nudged = true
		return s.say(ctx, t, "Cuando quieras, tocá «Sí, armemos esto» y empiezo a construir. Si algo no te convence, decime qué cambiamos.",
			MessageMeta{Kind: "notice", QuickReplies: planReplies()})
	}
	p := RecommendPlan(*bp)
	d.Plan = &p
	d.Status = DiscoveryProposed
	return s.say(ctx, t, PlanText(*bp, p), MessageMeta{Kind: "plan", QuickReplies: planReplies(), BrainMode: mode})
}

// rebuildAll marks everything gathered during the diagnosis as changed, so the
// first build turn queues the theme and the copy of every product.
func rebuildAll(bp *Blueprint, ch Changes) Changes {
	ch.Profile = true
	for _, p := range bp.Products {
		if p.CopyStatus == "pending" && !slices.Contains(ch.NewProducts, p.ID) {
			ch.NewProducts = append(ch.NewProducts, p.ID)
		}
	}
	return ch
}
