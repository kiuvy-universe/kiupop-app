package agent

import (
	"bytes"
	"fmt"
	"runtime"
	"testing"
	"time"

	"github.com/xuri/excelize/v2"
)

func names(p []ExtractedProduct) map[string]int64 {
	m := map[string]int64{}
	for _, x := range p {
		m[x.Name] = x.PriceColones
	}
	return m
}

func TestParseCatalogXLSX(t *testing.T) {
	f := excelize.NewFile()
	rows := [][]any{{"Producto", "Precio"}, {"Ramo de rosas", 15000}, {"Girasoles", "₡8.500"}, {"Sin precio", ""}, {"Ramo de rosas", 99999}}
	for i, r := range rows {
		cell, _ := excelize.CoordinatesToCellName(1, i+1)
		if err := f.SetSheetRow("Sheet1", cell, &r); err != nil {
			t.Fatal(err)
		}
	}
	var buf bytes.Buffer
	if err := f.Write(&buf); err != nil {
		t.Fatal(err)
	}
	got, text := ParseCatalogFile("catalogo.xlsx", buf.Bytes())
	m := names(got)
	if len(got) != 2 || m["Ramo de rosas"] != 15000 || m["Girasoles"] != 8500 {
		t.Fatalf("xlsx: %+v", got)
	}
	if text == "" {
		t.Fatal("grounding text empty")
	}
}

func TestParseCatalogText(t *testing.T) {
	in := "Mis productos:\n- Ramo de rosas - ₡15.000\n2) Girasoles: 8500\nCajita sorpresa, 12 000\nSolo un nombre\n"
	got, _ := ParseCatalogFile("lista.txt", []byte(in))
	m := names(got)
	if len(got) != 3 || m["Ramo de rosas"] != 15000 || m["Girasoles"] != 8500 || m["Cajita sorpresa"] != 12000 {
		t.Fatalf("txt: %+v", got)
	}
}

func TestParseCatalogCSVStillWorks(t *testing.T) {
	got, _ := ParseCatalogFile("c.csv", []byte("nombre;precio\nTorta;12000\nGalletas;3500\n"))
	if len(got) != 2 {
		t.Fatalf("csv: %+v", got)
	}
}

func TestDetectKindCatalogs(t *testing.T) {
	for _, tc := range []struct {
		name string
		data []byte
		ok   bool
	}{
		{"a.txt", []byte("Torta 12000"), true},
		{"a.csv", []byte("a,b"), true},
		{"a.exe", []byte("Torta 12000"), false},
		{"a.xlsx", []byte("PK\x03\x04junk"), true},
		{"a.txt", []byte("PK\x03\x04junk"), false}, // zip content with a text name
	} {
		k, err := DetectKind(tc.name, tc.data)
		if (err == nil) != tc.ok || (tc.ok && k != "csv") {
			t.Errorf("%s: kind=%q err=%v", tc.name, k, err)
		}
	}
}

// A cell in the last column (XFD) must not make every row 16 384 cells wide.
func TestParseCatalogXLSXWideSheetStaysBounded(t *testing.T) {
	f := excelize.NewFile()
	_ = f.SetCellValue("Sheet1", "A1", "Producto")
	_ = f.SetCellValue("Sheet1", "B1", "Precio")
	_ = f.SetCellValue("Sheet1", "A2", "Rosa roja")
	_ = f.SetCellValue("Sheet1", "B2", 1500)
	for r := 3; r < 1203; r++ {
		_ = f.SetCellValue("Sheet1", fmt.Sprintf("XFD%d", r), "x")
	}
	buf, err := f.WriteToBuffer()
	if err != nil {
		t.Fatal(err)
	}
	_ = f.Close()
	f = nil // the writer itself holds every padded row
	runtime.GC()
	var base runtime.MemStats
	runtime.ReadMemStats(&base)
	// Rows are still padded one at a time by excelize, but nothing keeps them:
	// the live heap must stay small (the old GetRows kept every padded row).
	done, peakc := make(chan struct{}), make(chan uint64)
	go func() {
		var m runtime.MemStats
		var peak uint64
		for {
			select {
			case <-done:
				peakc <- peak
				return
			case <-time.After(5 * time.Millisecond):
				runtime.ReadMemStats(&m)
				if m.HeapInuse > peak {
					peak = m.HeapInuse
				}
			}
		}
	}()
	products, _ := ParseCatalogXLSX(buf.Bytes())
	close(done)
	peak := <-peakc
	if len(products) != 1 || products[0].Name != "Rosa roja" {
		t.Fatalf("products = %+v, want only Rosa roja", products)
	}
	if peak > base.HeapInuse+256<<20 {
		t.Fatalf("live heap grew %d MB parsing a tiny wide sheet", (peak-base.HeapInuse)>>20)
	}
}
