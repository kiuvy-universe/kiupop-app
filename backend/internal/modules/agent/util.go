package agent

import (
	"crypto/sha256"
	"encoding/hex"
	"sort"
	"strings"
)

func sortStrings(s []string) { sort.Strings(s) }

// sameProduct matches "Arreglos" with "arreglo de girasoles" (shared stem of the head word).
func sameProduct(a, b string) bool {
	fa, fb := fold(strings.TrimSpace(a)), fold(strings.TrimSpace(b))
	if fa == "" || fb == "" {
		return false
	}
	if fa == fb {
		return true
	}
	ha, hb := strings.Fields(fa), strings.Fields(fb)
	return len(ha) > 0 && len(hb) > 0 && stem(ha[0]) == stem(hb[0]) && (len(ha) == 1 || len(hb) == 1)
}

func shortHash(parts ...string) string {
	h := sha256.Sum256([]byte(strings.Join(parts, "\x1f")))
	return hex.EncodeToString(h[:6])
}

func addUnique(list []string, v string) []string {
	for _, x := range list {
		if x == v {
			return list
		}
	}
	return append(list, v)
}

func truncate(s string, n int) string {
	r := []rune(strings.TrimSpace(s))
	if len(r) <= n {
		return string(r)
	}
	return strings.TrimSpace(string(r[:n-1])) + "…"
}

func lowerFirst(s string) string {
	r := []rune(s)
	if len(r) == 0 {
		return s
	}
	r[0] = []rune(strings.ToLower(string(r[0])))[0]
	return string(r)
}
