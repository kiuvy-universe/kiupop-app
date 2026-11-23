package storefront

import "testing"

func TestDefaultsPassContrast(t *testing.T) {
	for _, id := range Templates {
		if err := CheckContrast(Default(id).Colors); err != nil {
			t.Errorf("%s: %v", id, err)
		}
	}
}

func TestNormalizeRejectsBadTokens(t *testing.T) {
	in := Default(MintFresh)
	in.Colors.Text = "#EEEEEE" // unreadable on light background
	in.Radius = 99
	in.Sections = []string{"catalog", "hero"}
	in.Typography.Style = "comic-sans"
	out := Normalize(in)
	def := Default(MintFresh)
	if out.Colors != def.Colors || out.Radius != def.Radius || out.Typography.Style != def.Typography.Style {
		t.Fatalf("expected defaults, got %+v", out)
	}
	if out.Sections[0] != "hero" {
		t.Fatalf("sections not normalised: %v", out.Sections)
	}
}

func TestNormalizeKeepsValidVariation(t *testing.T) {
	in := Default(PeachPop)
	in.Radius = 12
	in.Spacing = "compact"
	in.Sections = []string{"hero", "catalog", "contact"}
	in.Colors.Accent = "#ff0000"
	out := Normalize(in)
	if out.Radius != 12 || out.Spacing != "compact" || len(out.Sections) != 3 || out.Colors.Accent != "#FF0000" {
		t.Fatalf("valid variation lost: %+v", out)
	}
	if Normalize(Theme{Template: "evil<script>"}).Template != BubblegumPink {
		t.Fatal("unknown template must fall back")
	}
}

func TestContrastRatio(t *testing.T) {
	if r := ContrastRatio("#000000", "#FFFFFF"); r < 20.9 || r > 21.1 {
		t.Fatalf("black/white = %v", r)
	}
}
