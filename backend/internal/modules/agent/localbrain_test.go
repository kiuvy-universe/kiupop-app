package agent

import (
	"context"
	"slices"
	"testing"
)

func understand(t *testing.T, text string, pending string) Extraction {
	t.Helper()
	in := TurnInput{Text: text}
	if pending != "" {
		in.Pending = &Question{Field: pending}
	}
	ex, _, err := LocalBrain{}.Understand(context.Background(), in)
	if err != nil {
		t.Fatal(err)
	}
	return ex
}

func TestLocalBrainFreeDescription(t *testing.T) {
	ex := understand(t, "Soy Florería Bella, vendo flores, arreglos y regalos. Quiero algo elegante y romántico, con colores rosados. Entrego en Naranjo y San Ramón.", "")
	if ex.BusinessName != "Florería Bella" {
		t.Errorf("name = %q", ex.BusinessName)
	}
	var names []string
	for _, p := range ex.Products {
		names = append(names, p.Name)
		if p.PriceColones != 0 {
			t.Errorf("invented price for %q", p.Name)
		}
	}
	if !slices.Equal(names, []string{"Flores", "Arreglos", "Regalos"}) {
		t.Errorf("products = %v", names)
	}
	if ex.Category != "flores" || !slices.Equal(ex.DeliveryModes, []string{"delivery"}) {
		t.Errorf("category=%q delivery=%v", ex.Category, ex.DeliveryModes)
	}
	if !slices.Equal(ex.Zones, []string{"Naranjo", "San Ramón"}) {
		t.Errorf("zones = %v", ex.Zones)
	}
	if !slices.Contains(ex.Styles, "elegante") || !slices.Contains(ex.Styles, "romantico") || !slices.Equal(ex.Colors, []string{"rosado"}) {
		t.Errorf("styles=%v colors=%v", ex.Styles, ex.Colors)
	}
}

func TestLocalBrainPrices(t *testing.T) {
	ex := understand(t, "Ramo de rosas 15000, arreglo de girasoles 18 mil y caja de regalo con chocolates ₡12.500", FieldPrices)
	want := map[string]int64{"Ramo de rosas": 15000, "Arreglo de girasoles": 18000, "Caja de regalo con chocolates": 12500}
	if len(ex.Products) != 3 {
		t.Fatalf("products = %+v", ex.Products)
	}
	for _, p := range ex.Products {
		if want[p.Name] != p.PriceColones {
			t.Errorf("%q = %d", p.Name, p.PriceColones)
		}
	}
}

func TestLocalBrainPhoneIsNotAPrice(t *testing.T) {
	ex := understand(t, "Mi WhatsApp es 8888-1234", FieldWhatsApp)
	if ex.WhatsApp == "" || len(ex.Products) != 0 {
		t.Fatalf("whatsapp=%q products=%v", ex.WhatsApp, ex.Products)
	}
}

func TestLocalBrainSkipAndQuickAnswers(t *testing.T) {
	if !understand(t, "omitir", FieldStyle).SkipPending {
		t.Error("omitir should skip")
	}
	if ex := understand(t, "Ambas opciones", FieldDelivery); !slices.Equal(ex.DeliveryModes, []string{"delivery", "pickup"}) {
		t.Errorf("both = %v", ex.DeliveryModes)
	}
	if ex := understand(t, "dulce tentación", FieldName); ex.BusinessName != "Dulce Tentación" {
		t.Errorf("name answer = %q", ex.BusinessName)
	}
}

func TestGrounding(t *testing.T) {
	if !PriceGrounded("el ramo vale 15 mil", 15000) || PriceGrounded("el ramo es bonito", 15000) {
		t.Error("price grounding")
	}
	if !PhoneGrounded("escribime al 8888 1234", "50688881234") || PhoneGrounded("hola", "50688881234") {
		t.Error("phone grounding")
	}
	if !TextGrounded("Entrego en San Ramón", "San Ramon") || TextGrounded("Entrego en Naranjo", "Grecia") {
		t.Error("text grounding")
	}
	for in, want := range map[string]int64{"15.000": 15000, "2,5 mil": 2500, "₡12,500": 12500, "18k": 18000} {
		got := MentionedAmounts(in)
		if len(got) != 1 || got[0] != want {
			t.Errorf("%q -> %v", in, got)
		}
	}
}

func TestLocalBrainNumberInNameIsNotAPrice(t *testing.T) {
	ex := understand(t, "Soy Pulpería 2000, vendo abarrotes y frutas.", "")
	if ex.BusinessName != "Pulpería 2000" {
		t.Fatalf("name = %q", ex.BusinessName)
	}
	for _, p := range ex.Products {
		if p.PriceColones != 0 {
			t.Fatalf("name digits read as price: %+v", ex.Products)
		}
	}
}

func TestStemPairs(t *testing.T) {
	for a, b := range map[string]string{"arreglos": "arreglo", "rosas": "rosa", "flores": "flor", "regalos": "regalo", "queques": "queque"} {
		if stem(a) != stem(b) {
			t.Errorf("stem(%q)=%q stem(%q)=%q", a, stem(a), b, stem(b))
		}
	}
	if !sameProduct("Arreglos", "Arreglo de girasoles") {
		t.Error("generic product should merge with its priced variant")
	}
}

// Natural ways merchants describe a business (regression table for the local extractor).
func TestLocalBrainNaturalDescriptions(t *testing.T) {
	cases := []struct {
		text, name, cat string
		products, zones []string
		colors          []string
	}{
		{"Tengo una floristería que se llama Flores del Valle, hacemos ramos y arreglos para eventos en Cartago",
			"Flores del Valle", "flores", []string{"Ramos", "Arreglos"}, []string{"Cartago"}, nil},
		{"Nos llamamos Pet Lovers CR, ofrecemos baño y corte para perros y gatos. Nuestro WhatsApp es 8899-0011",
			"Pet Lovers CR", "mascotas", []string{"Baño", "Corte para perros y gatos"}, nil, nil},
		{"vendo ropa de bebé tejida a mano, me llamo Crochet de Abuela, colores pastel, entrego por Correos de Costa Rica",
			"Crochet de Abuela", "ropa", []string{"Ropa de bebé tejida a mano"}, nil, []string{"pastel"}},
		{"Bisutería Luna: aretes, collares y pulseras artesanales. Estilo minimalista y moderno.",
			"Bisutería Luna", "artesania", []string{"Aretes", "Collares", "Pulseras artesanales"}, nil, nil},
		{"Mi negocio es de uñas acrílicas y pestañas, se llama Glam Nails, atiendo en Escazú",
			"Glam Nails", "belleza", []string{"Uñas acrílicas", "Pestañas"}, []string{"Escazú"}, nil},
		{"Hago pasteles personalizados para cumpleaños",
			"", "reposteria", []string{"Pasteles personalizados para cumpleaños"}, nil, nil},
	}
	for _, c := range cases {
		ex := understand(t, c.text, "")
		var names []string
		for _, p := range ex.Products {
			names = append(names, p.Name)
		}
		if ex.BusinessName != c.name || ex.Category != c.cat || !slices.Equal(names, c.products) ||
			!slices.Equal(ex.Zones, c.zones) || !slices.Equal(ex.Colors, c.colors) {
			t.Errorf("%q\n got name=%q cat=%q products=%v zones=%v colors=%v", c.text, ex.BusinessName, ex.Category, names, ex.Zones, ex.Colors)
		}
	}
}
