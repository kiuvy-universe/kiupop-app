package stores

import "testing"

func TestNormalizeWhatsApp(t *testing.T) {
	ok := map[string]string{
		"8888 8888":         "50688888888",
		"+506 8888-8888":    "50688888888",
		"(506) 6000-0000":   "50660000000",
		"0050622223333":     "50622223333",
		"+1 (415) 555 0100": "14155550100",
		"+506 0000 0001":    "50600000001", // fictitious test number shape
	}
	for in, want := range ok {
		got, valid := NormalizeWhatsApp(in)
		if !valid || got != want {
			t.Errorf("%q -> %q,%v want %q", in, got, valid, want)
		}
	}
	for _, in := range []string{"", "1234", "abc", "+506 8888 888", "1888 8888", "+0 123456789", "8888 8888 ext 2", "5068888888888"} {
		if got, valid := NormalizeWhatsApp(in); valid {
			t.Errorf("%q should be invalid, got %q", in, got)
		}
	}
}

func TestSlugify(t *testing.T) {
	cases := map[string]string{
		"Flores de Occidente":   "flores-de-occidente",
		"  Pulpería   Ñandú!! ": "pulperia-nandu",
		"Café & Té":             "cafe-te",
		"AB":                    "tienda-ab",
		"¡¡¡":                   "tienda",
	}
	for in, want := range cases {
		if got := Slugify(in); got != want {
			t.Errorf("Slugify(%q) = %q want %q", in, got, want)
		}
		if !ValidSlug(Slugify(in)) {
			t.Errorf("Slugify(%q) produced invalid slug", in)
		}
	}
}

func TestCreateInputValidate(t *testing.T) {
	in := CreateInput{Name: "  Flores   de Occidente ", WhatsApp: "8888 8888"}
	if errs := in.Validate(); len(errs) != 0 || in.Name != "Flores de Occidente" || in.WhatsApp != "50688888888" {
		t.Fatalf("errs=%v in=%+v", errs, in)
	}
	bad := CreateInput{Name: "x", WhatsApp: "12"}
	errs := bad.Validate()
	if errs["name"] == "" || errs["whatsapp"] == "" {
		t.Fatalf("expected name and whatsapp errors: %v", errs)
	}
}
