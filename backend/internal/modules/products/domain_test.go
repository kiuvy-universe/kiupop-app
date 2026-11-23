package products

import "testing"

func TestCreateValidate(t *testing.T) {
	in := CreateInput{Name: "  Rosa   roja ", PriceMinor: 200000}
	if errs := in.Validate(); len(errs) != 0 || in.Name != "Rosa roja" {
		t.Fatalf("errs=%v name=%q", errs, in.Name)
	}
	for _, price := range []int64{0, -1, MaxPriceMinor + 1} {
		bad := CreateInput{Name: "x", PriceMinor: price}
		if bad.Validate()["price_minor"] == "" {
			t.Errorf("price %d must be rejected", price)
		}
	}
}

func TestPatchValidate(t *testing.T) {
	var empty PatchInput
	if empty.Validate()["body"] == "" {
		t.Fatal("empty patch must be rejected")
	}
	off := false
	p := PatchInput{Available: &off}
	if errs := p.Validate(); len(errs) != 0 {
		t.Fatalf("availability-only patch: %v", errs)
	}
}

func TestPublicDTOHidesInternals(t *testing.T) {
	p := Product{ID: "id", StoreID: "secret-store", Name: "n", PriceMinor: 1, Currency: "CRC", ImageKey: "k.png"}
	pub := p.Public()
	if pub.ImageURL == nil || *pub.ImageURL != "/api/v1/public/images/k.png" {
		t.Fatalf("image url %v", pub.ImageURL)
	}
	if (Product{}).Public().ImageURL != nil {
		t.Fatal("no image must be null")
	}
}
