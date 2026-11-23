package agent

import (
	"regexp"
	"strconv"
	"strings"
	"unicode"

	"golang.org/x/text/runes"
	"golang.org/x/text/transform"
	"golang.org/x/text/unicode/norm"
)

// fold lowercases and strips accents so "Ramón" matches "ramon".
func fold(s string) string {
	t := transform.Chain(norm.NFD, runes.Remove(runes.In(unicode.Mn)), norm.NFC)
	out, _, err := transform.String(t, strings.ToLower(s))
	if err != nil {
		return strings.ToLower(s)
	}
	return out
}

// amountRe finds money-like amounts: 15000, 15.000, 15 000, ₡15,000, 15 mil, 15k, 2,5 mil.
var amountRe = regexp.MustCompile(`(?i)(\d{1,3}(?:[.,\s]\d{3})+|\d+(?:[.,]\d{1,2})?)\s*(mil\b|k\b|lucas?\b|rojos?\b)?`)

// MentionedAmounts returns every amount (in colones) written in text.
func MentionedAmounts(text string) []int64 {
	var out []int64
	for _, m := range amountRe.FindAllStringSubmatch(text, -1) {
		if v, ok := parseAmount(m[1], m[2]); ok {
			out = append(out, v)
		}
	}
	return out
}

func parseAmount(num, unit string) (int64, bool) {
	unit = strings.ToLower(unit)
	thousands := unit == "mil" || unit == "k" || strings.HasPrefix(unit, "luca") || strings.HasPrefix(unit, "rojo")
	n := strings.ReplaceAll(num, " ", "")
	// "15.000" / "15,000" are thousands separators; "2,5" / "2.5" are decimals.
	if g := regexp.MustCompile(`^\d{1,3}([.,]\d{3})+$`); g.MatchString(n) {
		n = strings.NewReplacer(".", "", ",", "").Replace(n)
		v, err := strconv.ParseInt(n, 10, 64)
		if err != nil {
			return 0, false
		}
		if thousands {
			v *= 1000
		}
		return v, v > 0
	}
	n = strings.ReplaceAll(n, ",", ".")
	f, err := strconv.ParseFloat(n, 64)
	if err != nil || f <= 0 {
		return 0, false
	}
	if thousands {
		f *= 1000
	}
	return int64(f + 0.5), true
}

// PriceGrounded reports whether colones literally appears in the merchant's text.
func PriceGrounded(text string, colones int64) bool {
	if colones <= 0 {
		return false
	}
	for _, v := range MentionedAmounts(text) {
		if v == colones {
			return true
		}
	}
	return false
}

// PhoneGrounded reports whether the digits of e164 were written by the merchant.
func PhoneGrounded(text, e164 string) bool {
	digits := strings.Map(func(r rune) rune {
		if r >= '0' && r <= '9' {
			return r
		}
		return -1
	}, text)
	local := strings.TrimPrefix(e164, "506")
	return e164 != "" && (strings.Contains(digits, e164) || (len(local) == 8 && strings.Contains(digits, local)))
}

// TextGrounded reports whether every significant word of value appears in text.
func TextGrounded(text, value string) bool {
	ft := fold(text)
	words := strings.FieldsFunc(fold(value), func(r rune) bool { return !unicode.IsLetter(r) && !unicode.IsDigit(r) })
	n := 0
	for _, w := range words {
		if len([]rune(w)) < 3 {
			continue
		}
		n++
		if !strings.Contains(ft, stem(w)) {
			return false
		}
	}
	return n > 0
}

// AnyWordGrounded reports whether at least one significant word of value is in text
// (used for product names, which the model may normalise: "arreglos" → "Arreglos florales").
func AnyWordGrounded(text, value string) bool {
	ft := fold(text)
	for _, w := range strings.FieldsFunc(fold(value), func(r rune) bool { return !unicode.IsLetter(r) }) {
		if len([]rune(w)) >= 4 && strings.Contains(ft, stem(w)) {
			return true
		}
	}
	return false
}

// stem trims one plural ending, then one gender vowel, so "arreglos",
// "arreglo" and "arreglito"-free variants share a stem ("arregl"). It is
// idempotent on singular/plural pairs: stem("rosas") == stem("rosa").
func stem(w string) string {
	if len([]rune(w)) > 4 {
		if strings.HasSuffix(w, "es") && !strings.HasSuffix(w, "ces") {
			w = strings.TrimSuffix(w, "es")
		} else {
			w = strings.TrimSuffix(w, "s")
		}
	}
	if len([]rune(w)) > 3 && (strings.HasSuffix(w, "a") || strings.HasSuffix(w, "o") || strings.HasSuffix(w, "e")) {
		w = w[:len(w)-1]
	}
	return w
}
