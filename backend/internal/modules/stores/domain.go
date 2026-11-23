// Package stores owns merchants' stores and their admin credentials.
package stores

import (
	"errors"
	"regexp"
	"strings"
	"unicode"
	"unicode/utf8"
)

var (
	// ErrNotFound means no store matches.
	ErrNotFound = errors.New("store not found")
	// ErrSlugExhausted means no free slug could be found (practically unreachable).
	ErrSlugExhausted = errors.New("could not allocate slug")
)

// Store is the full record (admin view).
type Store struct {
	ID          string `json:"id"`
	Slug        string `json:"slug"`
	Name        string `json:"name"`
	Description string `json:"description"`
	WhatsApp    string `json:"whatsapp"`
}

// Public is what anyone can see. No id, no phone, no credentials.
type Public struct {
	Slug        string `json:"slug"`
	Name        string `json:"name"`
	Description string `json:"description"`
}

// ToPublic strips private fields.
func (s Store) ToPublic() Public {
	return Public{Slug: s.Slug, Name: s.Name, Description: s.Description}
}

// CreateInput is the request body for POST /api/v1/stores.
type CreateInput struct {
	Name        string `json:"name"`
	WhatsApp    string `json:"whatsapp"`
	Description string `json:"description"`
}

// Validate normalises the input in place and returns field errors (es-CR).
func (in *CreateInput) Validate() map[string]string {
	errs := map[string]string{}
	in.Name = strings.Join(strings.Fields(in.Name), " ")
	in.Description = strings.TrimSpace(in.Description)
	if n := utf8.RuneCountInString(in.Name); n < 2 || n > 80 {
		errs["name"] = "El nombre debe tener entre 2 y 80 caracteres."
	}
	if utf8.RuneCountInString(in.Description) > 500 {
		errs["description"] = "La descripción admite hasta 500 caracteres."
	}
	phone, ok := NormalizeWhatsApp(in.WhatsApp)
	if !ok {
		errs["whatsapp"] = "Escribe un número de WhatsApp válido, por ejemplo 8888 8888 o +506 8888 8888."
	}
	in.WhatsApp = phone
	return errs
}

var nonDigit = regexp.MustCompile(`\D`)

// NormalizeWhatsApp returns the number as E.164 digits without '+', as wa.me expects.
// Costa Rica is the default country: 8-digit local numbers get the 506 prefix.
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
	d := nonDigit.ReplaceAllString(s, "")
	d = strings.TrimPrefix(d, "00")
	if len(d) == 8 && strings.ContainsRune("245678", rune(d[0])) {
		d = "506" + d
	}
	if strings.HasPrefix(d, "506") && len(d) != 11 {
		return "", false
	}
	// International numbers need country code + subscriber number (>= 10 digits).
	if len(d) < 10 || len(d) > 15 || d[0] == '0' {
		return "", false
	}
	return d, true
}

var accents = strings.NewReplacer(
	"á", "a", "é", "e", "í", "i", "ó", "o", "ú", "u", "ü", "u", "ñ", "n",
	"à", "a", "è", "e", "ì", "i", "ò", "o", "ù", "u", "ç", "c",
)

var nonSlug = regexp.MustCompile(`[^a-z0-9]+`)

// Slugify builds a URL-safe slug ("Flores de Occidente" -> "flores-de-occidente").
func Slugify(name string) string {
	s := accents.Replace(strings.ToLower(name))
	s = strings.Trim(nonSlug.ReplaceAllString(s, "-"), "-")
	if len(s) > 50 {
		s = strings.TrimRight(s[:50], "-")
	}
	if len(s) < 3 {
		s = strings.Trim("tienda-"+s, "-")
	}
	return s
}

var slugRe = regexp.MustCompile(`^[a-z0-9]+(-[a-z0-9]+)*$`)

// ValidSlug reports whether s could be a stored slug (cheap pre-check before SQL).
func ValidSlug(s string) bool { return len(s) >= 3 && len(s) <= 60 && slugRe.MatchString(s) }
