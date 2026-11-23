package agent

import (
	"strings"
	"testing"
)

func newTestID() func() string {
	n := 0
	return func() string { n++; return string(rune('a'+n)) + "id" }
}

func TestBlockerQuestionEscalatesAndNeverDumpsGenericNotice(t *testing.T) {
	for _, tc := range []struct {
		name string
		bp   Blueprint
		f    string
	}{
		{"sin productos", Blueprint{Business: BusinessProfile{Name: "Ana"}}, FieldPrices},
		{"productos sin precio", Blueprint{Business: BusinessProfile{Name: "Ana"}, Products: []DraftProduct{{Name: "Ramo"}, {Name: "Caja"}}}, FieldPrices},
		{"whatsapp", Blueprint{Business: BusinessProfile{Name: "Ana"}, Products: []DraftProduct{{Name: "Ramo", PriceMinor: 1500000}}}, FieldWhatsApp},
		{"nombre", Blueprint{}, FieldName},
	} {
		seen := map[string]bool{}
		for attempt := 0; attempt < 3; attempt++ {
			q := BlockerQuestion(tc.bp, tc.f, attempt)
			if !q.Essential || q.Field != tc.f || q.Text == "" {
				t.Fatalf("%s/%d: %+v", tc.name, attempt, q)
			}
			if strings.Contains(q.Text, "todavía me falta") || strings.Contains(q.Text, "Escribímelo") {
				t.Fatalf("%s/%d: generic dead-end text: %q", tc.name, attempt, q.Text)
			}
			body := strings.TrimPrefix(q.Text, progressLine(tc.bp)+" ")
			if seen[body] {
				t.Fatalf("%s: attempt %d repeats an earlier text: %q", tc.name, attempt, body)
			}
			seen[body] = true
		}
		if firstBlocker(tc.bp) != tc.f {
			t.Fatalf("%s: firstBlocker=%q", tc.name, firstBlocker(tc.bp))
		}
	}
}

// The normal merchant answers must unblock publishing (no loop).
func TestBlockerAnswersUnblock(t *testing.T) {
	for _, tc := range []struct{ name, pending, reply string }{
		{"precio con símbolo", FieldPrices, "Ramo de rosas ₡15.000"},
		{"precio simple", FieldPrices, "Torta de chocolate 12000"},
		{"precio corto", FieldPrices, "Ramo 15000"},
	} {
		bp := Blueprint{Business: BusinessProfile{Name: "Ana"}}
		ex := understand(t, tc.reply, tc.pending)
		Apply(&bp, ex, tc.reply, tc.pending, false, newTestID())
		if len(bp.PricedProducts()) == 0 {
			t.Errorf("%s: %q did not produce a priced product: %+v", tc.name, tc.reply, bp.Products)
		}
	}
	for _, reply := range []string{"8888 8888", "88888888", "+506 8888-8888", "mi whatsapp es 8888-8888", "506 88888888"} {
		bp := Blueprint{Business: BusinessProfile{Name: "Ana"}, Products: []DraftProduct{{Name: "Ramo", PriceMinor: 1500000}}}
		ex := understand(t, reply, FieldWhatsApp)
		Apply(&bp, ex, reply, FieldWhatsApp, false, newTestID())
		if bp.Contact.WhatsApp == "" {
			t.Errorf("whatsapp %q not understood", reply)
		}
	}
}

func TestCommandRepliesAreNeverProducts(t *testing.T) {
	for _, reply := range []string{ReplyKnowWhat, "Ya sé lo que quiero", "Sí", "omitir", ReplyAcceptPlan, ReplyChangePlan} {
		for _, pending := range []string{FieldProducts, FieldPrices, ""} {
			bp := Blueprint{Business: BusinessProfile{Name: "Ana"}}
			ex := understand(t, reply, pending)
			Apply(&bp, ex, reply, pending, false, newTestID())
			if len(bp.Products) != 0 {
				t.Errorf("%q (pending %q) became a product: %+v", reply, pending, bp.Products)
			}
		}
	}
	// A real product that merely starts like a command word still works.
	bp := Blueprint{}
	ex := understand(t, "Listones de regalo 2500", FieldProducts)
	Apply(&bp, ex, "Listones de regalo 2500", FieldProducts, false, newTestID())
	if len(bp.PricedProducts()) != 1 {
		t.Errorf("real product lost: %+v", bp.Products)
	}
}

func TestManyProductsSuggestImportFewDoNot(t *testing.T) {
	few := Blueprint{Products: []DraftProduct{{Name: "Ramo"}, {Name: "Caja"}}}
	if q := BlockerQuestion(few, FieldPrices, 0); strings.Contains(q.Text, "subí una lista") {
		t.Fatalf("few products should be typed: %q", q.Text)
	}
	var many Blueprint
	for i := 0; i < ImportThreshold; i++ {
		many.Products = append(many.Products, DraftProduct{Name: "Producto " + string(rune('A'+i))})
	}
	q := BlockerQuestion(many, FieldPrices, 0)
	if !q.AllowUpload || !strings.Contains(q.Text, "subí una lista") {
		t.Fatalf("many products should suggest import: %+v", q)
	}
	social := many
	social.Discovery = &Discovery{Status: DiscoveryAccepted, Channels: []string{ChannelWhatsApp}}
	if q := BlockerQuestion(social, FieldPrices, 0); q.AllowUpload || strings.Contains(strings.ToLower(q.Text), "subí") {
		t.Fatalf("social channels paste a list, no upload: %+v", q)
	}
}

func TestWhatsAppTipAndNoRepeat(t *testing.T) {
	bp := Blueprint{Business: BusinessProfile{Name: "Ana"}, Products: []DraftProduct{{Name: "Ramo", PriceMinor: 1500000}}}
	prev := ""
	for attempt := 0; attempt < 12; attempt++ {
		q := BlockerQuestion(bp, FieldWhatsApp, attempt)
		body := strings.TrimPrefix(q.Text, progressLine(bp)+" ")
		if body == prev {
			t.Fatalf("attempt %d repeats the previous text: %q", attempt, body)
		}
		prev = body
		if !strings.Contains(q.Text, "8 dígitos") || !strings.Contains(q.Text, "+") {
			t.Fatalf("attempt %d lacks the format tip (digits / country code): %q", attempt, q.Text)
		}
	}
}

func TestInternationalWhatsApp(t *testing.T) {
	for reply, want := range map[string]string{
		"+57 300 123 4567":              "573001234567",
		"mi whatsapp es +57 3001234567": "573001234567",
		"0057 300 123 4567":             "573001234567",
		"+506 8888-8888":                "50688888888",
		"8888 8888":                     "50688888888",
	} {
		bp := Blueprint{Business: BusinessProfile{Name: "Ana"}}
		ex := understand(t, reply, FieldWhatsApp)
		Apply(&bp, ex, reply, FieldWhatsApp, false, newTestID())
		if bp.Contact.WhatsApp != want {
			t.Errorf("%q → %q, want %q", reply, bp.Contact.WhatsApp, want)
		}
	}
	// No "+": a 10-digit foreign number is not guessed (wa.me would point nowhere).
	bp := Blueprint{}
	ex := understand(t, "3001234567", FieldWhatsApp)
	Apply(&bp, ex, "3001234567", FieldWhatsApp, false, newTestID())
	if bp.Contact.WhatsApp != "" {
		t.Errorf("ambiguous number was guessed: %q", bp.Contact.WhatsApp)
	}
}
