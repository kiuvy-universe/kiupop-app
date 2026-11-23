package agent

import (
	"bytes"
	"fmt"
	"regexp"
	"strings"

	"github.com/xuri/excelize/v2"
)

// Tabular catalogs. A merchant can share a spreadsheet (.xlsx), a CSV or a
// plain-text list ("Ramo rosas - ₡15.000" per line). All three are stored with
// the existing attachment kind "csv" (no migration) and told apart by content.
// Prices are only taken from the file's own cells/lines and still pass the
// grounding rules: nothing is invented.

const (
	// MaxXLSXBytes caps the compressed workbook; MaxXLSXUnzipBytes caps what it
	// may expand to (zip-bomb guard).
	MaxXLSXBytes      = 5 << 20
	MaxXLSXUnzipBytes = 20 << 20
	MaxTextCatalogLen = 1 << 20
)

var (
	zipMagic     = []byte("PK\x03\x04")
	listMarkerRe = regexp.MustCompile(`^(?:[-•*·]|\d{1,2}[.)])\s+`)
)

func isXLSX(data []byte) bool { return bytes.HasPrefix(data, zipMagic) }

// ParseCatalogFile dispatches on content: workbook, CSV table or plain-text list.
func ParseCatalogFile(filename string, data []byte) ([]ExtractedProduct, string) {
	switch {
	case isXLSX(data):
		return ParseCatalogXLSX(data)
	case strings.HasSuffix(strings.ToLower(filename), ".txt"):
		return ParseCatalogText(data)
	}
	if p, text := ParseCatalogCSV(data); len(p) > 0 {
		return p, text
	}
	return ParseCatalogText(data) // a ".csv" that is really "name - price" lines
}

// ParseCatalogXLSX reads the first non-empty sheet as "producto, precio" rows.
func ParseCatalogXLSX(data []byte) ([]ExtractedProduct, string) {
	f, err := excelize.OpenReader(bytes.NewReader(data), excelize.Options{
		UnzipSizeLimit:    MaxXLSXUnzipBytes,
		UnzipXMLSizeLimit: MaxXLSXUnzipBytes / 4,
	})
	if err != nil {
		return nil, ""
	}
	defer f.Close()
	// Stream rows: GetRows pads every row to its last used column, so a 16 KB
	// file with cells in column XFD would allocate gigabytes. Only the first
	// sheets, rows and columns can hold a product list anyway.
	for i, sheet := range f.GetSheetList() {
		if i >= maxXLSXSheets {
			break
		}
		if p, text := catalogFromRows(readSheetRows(f, sheet)); len(p) > 0 {
			return p, text
		}
	}
	return nil, ""
}

const (
	maxXLSXSheets  = 2
	maxXLSXColumns = 20
)

// readSheetRows returns at most MaxCSVRows*5 rows of at most maxXLSXColumns cells.
func readSheetRows(f *excelize.File, sheet string) [][]string {
	it, err := f.Rows(sheet)
	if err != nil {
		return nil
	}
	defer it.Close()
	var rows [][]string
	for n := 0; n < MaxCSVRows*5 && it.Next(); n++ {
		cols, err := it.Columns()
		if err != nil {
			break
		}
		if len(cols) > maxXLSXColumns {
			cols = append([]string(nil), cols[:maxXLSXColumns]...) // drop the padded backing array
		}
		rows = append(rows, cols)
	}
	return rows
}

// ParseCatalogText reads one product per line: "Nombre - ₡1.500", "Nombre: 1500",
// "Nombre, 1500" or "Nombre 1500". The last amount on the line is the price.
func ParseCatalogText(data []byte) ([]ExtractedProduct, string) {
	data = bytes.TrimPrefix(data, []byte("\xef\xbb\xbf"))
	if len(data) > MaxTextCatalogLen {
		return nil, ""
	}
	var rows [][]string
	for _, line := range strings.Split(strings.ReplaceAll(string(data), "\r", ""), "\n") {
		line = strings.TrimSpace(listMarkerRe.ReplaceAllString(strings.TrimSpace(line), ""))
		if line == "" {
			continue
		}
		name, price := splitNamePrice(line)
		rows = append(rows, []string{name, price})
	}
	return catalogFromRows(rows)
}

// splitNamePrice separates the trailing price from the product name.
func splitNamePrice(line string) (name, price string) {
	loc := amountRe.FindAllStringIndex(line, -1)
	if len(loc) == 0 {
		return line, ""
	}
	last := loc[len(loc)-1]
	name = strings.TrimSpace(strings.Trim(line[:last[0]], " \t-–—:,;|=₡¢$"))
	if len(name) > 3 && strings.EqualFold(name[len(name)-3:], "crc") {
		name = strings.TrimSpace(name[:len(name)-3])
	}
	return name, line[last[0]:last[1]]
}

// catalogFromRows turns rows (optional header row) into priced products plus
// the normalised text the grounding rules check prices against.
func catalogFromRows(rows [][]string) ([]ExtractedProduct, string) {
	if len(rows) == 0 {
		return nil, ""
	}
	nameCol, priceCol, start := 0, 1, 0
	for i, h := range rows[0] {
		f := fold(strings.TrimSpace(h))
		switch {
		case strings.Contains(f, "nombre") || strings.Contains(f, "producto") || f == "name" || f == "item" || f == "articulo":
			nameCol, start = i, 1
		case strings.Contains(f, "precio") || f == "price" || strings.Contains(f, "costo") || f == "valor":
			priceCol, start = i, 1
		}
	}
	var out []ExtractedProduct
	var lines []string
	seen := map[string]bool{}
	for _, row := range rows[start:] {
		if len(out) >= MaxCSVRows || nameCol >= len(row) || priceCol >= len(row) {
			continue
		}
		name := strings.Join(strings.Fields(row[nameCol]), " ")
		amounts := MentionedAmounts(row[priceCol])
		if !validProductName(name) || len(amounts) != 1 || amounts[0] < 100 || seen[fold(name)] {
			continue
		}
		seen[fold(name)] = true
		out = append(out, ExtractedProduct{Name: name, PriceColones: amounts[0]})
		lines = append(lines, fmt.Sprintf("%s %d", name, amounts[0]))
	}
	return out, strings.Join(lines, "\n")
}
