// Package products owns a store's products: the admin CRUD, image upload and the
// public catalog read side (only available products, never another store's).
package products

import (
	"errors"
	"strings"
	"time"
	"unicode/utf8"
)

// MaxPriceMinor is ₡1.000.000.000 expressed in céntimos.
const MaxPriceMinor int64 = 100_000_000_000

var (
	// ErrNotFound means the product does not exist in the caller's store.
	ErrNotFound = errors.New("product not found")
	// ErrStoreNotFound means the public slug does not exist.
	ErrStoreNotFound = errors.New("store not found")
)

// Product is the stored record.
type Product struct {
	ID          string
	StoreID     string
	Name        string
	Description string
	PriceMinor  int64
	Currency    string
	ImageKey    string
	Available   bool
	CreatedAt   time.Time
}

// AdminDTO is what the store admin sees.
type AdminDTO struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	PriceMinor  int64     `json:"price_minor"`
	Currency    string    `json:"currency"`
	ImageURL    *string   `json:"image_url"`
	Available   bool      `json:"available"`
	CreatedAt   time.Time `json:"created_at"`
}

// PublicDTO is what shoppers see (no store id, no availability flag, no timestamps).
type PublicDTO struct {
	ID          string  `json:"id"`
	Name        string  `json:"name"`
	Description string  `json:"description"`
	PriceMinor  int64   `json:"price_minor"`
	Currency    string  `json:"currency"`
	ImageURL    *string `json:"image_url"`
}

// ImagePath is the public URL path for a stored image key.
func ImagePath(key string) *string {
	if key == "" {
		return nil
	}
	p := "/api/v1/public/images/" + key
	return &p
}

// Admin converts to the admin DTO.
func (p Product) Admin() AdminDTO {
	return AdminDTO{ID: p.ID, Name: p.Name, Description: p.Description, PriceMinor: p.PriceMinor,
		Currency: p.Currency, ImageURL: ImagePath(p.ImageKey), Available: p.Available, CreatedAt: p.CreatedAt}
}

// Public converts to the public DTO.
func (p Product) Public() PublicDTO {
	return PublicDTO{ID: p.ID, Name: p.Name, Description: p.Description, PriceMinor: p.PriceMinor,
		Currency: p.Currency, ImageURL: ImagePath(p.ImageKey)}
}

// CreateInput is the body of POST /api/v1/admin/products.
type CreateInput struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	PriceMinor  int64  `json:"price_minor"`
	Available   *bool  `json:"available"`
}

// Validate normalises and validates.
func (in *CreateInput) Validate() map[string]string {
	errs := map[string]string{}
	in.Name = strings.Join(strings.Fields(in.Name), " ")
	in.Description = strings.TrimSpace(in.Description)
	validateName(in.Name, errs)
	validateDescription(in.Description, errs)
	validatePrice(in.PriceMinor, errs)
	return errs
}

// PatchInput is the body of PATCH /api/v1/admin/products/{id}; nil = unchanged.
type PatchInput struct {
	Name        *string `json:"name"`
	Description *string `json:"description"`
	PriceMinor  *int64  `json:"price_minor"`
	Available   *bool   `json:"available"`
}

// Validate normalises and validates present fields.
func (in *PatchInput) Validate() map[string]string {
	errs := map[string]string{}
	if in.Name == nil && in.Description == nil && in.PriceMinor == nil && in.Available == nil {
		errs["body"] = "No hay cambios para guardar."
	}
	if in.Name != nil {
		n := strings.Join(strings.Fields(*in.Name), " ")
		in.Name = &n
		validateName(n, errs)
	}
	if in.Description != nil {
		d := strings.TrimSpace(*in.Description)
		in.Description = &d
		validateDescription(d, errs)
	}
	if in.PriceMinor != nil {
		validatePrice(*in.PriceMinor, errs)
	}
	return errs
}

func validateName(n string, errs map[string]string) {
	if c := utf8.RuneCountInString(n); c < 1 || c > 80 {
		errs["name"] = "El nombre debe tener entre 1 y 80 caracteres."
	}
}

func validateDescription(d string, errs map[string]string) {
	if utf8.RuneCountInString(d) > 600 {
		errs["description"] = "La descripción admite hasta 600 caracteres."
	}
}

func validatePrice(p int64, errs map[string]string) {
	if p <= 0 || p > MaxPriceMinor {
		errs["price_minor"] = "El precio debe ser mayor que cero."
	}
}
