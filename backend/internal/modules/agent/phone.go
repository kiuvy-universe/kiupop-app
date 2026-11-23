package agent

import (
	"regexp"
	"strings"
	"unicode"
)

var nonDigit = regexp.MustCompile(`\D`)

// NormalizeWhatsApp mirrors stores.NormalizeWhatsApp (modules never import each
// other): E.164 digits without '+', Costa Rica (506) by default.
func NormalizeWhatsApp(raw string) (string, bool) {
	s := strings.TrimSpace(raw)
	if s == "" || len(s) > 25 {
		return "", false
	}
	for _, r := range s {
		if !(unicode.IsDigit(r) || strings.ContainsRune("+ -().", r)) {
			return "", false
		}
	}
	d := strings.TrimPrefix(nonDigit.ReplaceAllString(s, ""), "00")
	if len(d) == 8 && strings.ContainsRune("245678", rune(d[0])) {
		d = "506" + d
	}
	if strings.HasPrefix(d, "506") && len(d) != 11 {
		return "", false
	}
	if len(d) < 10 || len(d) > 15 || d[0] == '0' {
		return "", false
	}
	return d, true
}
