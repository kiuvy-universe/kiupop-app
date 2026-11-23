package storefront

import (
	"bytes"
	"errors"
	"fmt"
	"html/template"
	"image"
	"image/color"
	"image/png"
	"log/slog"
	"math"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"sync"

	"github.com/kiuvy-universe/kiupop/backend/internal/platform/httpserver"
	sf "github.com/kiuvy-universe/kiupop/backend/internal/platform/storefront"
)

// Links are the public origins used to build shareable URLs.
type Links struct {
	APIBase string // serves /p/{slug} and /og/{slug}.png
	WebBase string // serves the Flutter app (/#/s/{slug})
}

// Handler serves the public storefront and share pages.
type Handler struct {
	covers sync.Map // palette → rendered PNG
	repo   *Repo
	links  Links
	log    *slog.Logger
}

// NewHandler builds the handler.
func NewHandler(repo *Repo, links Links, log *slog.Logger) *Handler {
	return &Handler{repo: repo, links: links, log: log}
}

// Register mounts public routes.
func (h *Handler) Register(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/public/stores/{slug}/storefront", h.view)
	mux.HandleFunc("GET /p/{slug}", h.sharePage)
	mux.HandleFunc("GET /og/{file}", h.ogImage)
}

var slugRe = regexp.MustCompile(`^[a-z0-9]+(-[a-z0-9]+)*$`)

func validSlug(s string) bool { return len(s) >= 3 && len(s) <= 60 && slugRe.MatchString(s) }

// Build assembles the public view of a published store.
func (h *Handler) Build(r *http.Request, slug string) (sf.View, error) {
	if !validSlug(slug) {
		return sf.View{}, ErrNotFound
	}
	st, err := h.repo.BySlug(r.Context(), slug)
	if err != nil {
		return sf.View{}, err
	}
	rows, err := h.repo.Products(r.Context(), st.ID)
	if err != nil {
		return sf.View{}, err
	}
	featured := map[string]bool{}
	for _, id := range st.Profile.Featured {
		featured[id] = true
	}
	v := sf.View{
		Store: sf.StoreInfo{Slug: st.Slug, Name: st.Name, Tagline: st.Profile.Tagline, Description: st.Description,
			Category: st.Profile.Category, Status: "published", CoverURL: imageURL(st.Profile.CoverKey)},
		Theme:    st.Theme,
		Products: []sf.ProductView{},
		Delivery: sf.Delivery{Modes: nonNil(st.Profile.Delivery.Modes), Zones: nonNil(st.Profile.Delivery.Zones), Notes: st.Profile.Delivery.Notes},
		Contact:  sf.Contact{Instagram: st.Profile.Instagram},
		Payments: sf.Payments{Checkout: orNone(st.Profile.Payments.Checkout), RealPaymentsEnabled: false,
			MethodsToCoordinate: nonNil(st.Profile.Payments.MethodsToCoordinate)},
		Share: sf.Share{URL: h.shareURL(st.Slug), Title: st.Name, Text: fmt.Sprintf("Mirá la tienda de %s en KiuPop", st.Name)},
	}
	if st.WhatsApp != "" {
		v.Contact.WhatsAppURL = "https://wa.me/" + st.WhatsApp
	}
	for _, p := range rows {
		pv := sf.ProductView{ID: p.ID, Name: p.Name, Description: p.Description, PriceMinor: p.PriceMinor, Currency: "CRC", Featured: featured[p.ID]}
		if p.ImageKey != "" {
			u := "/api/v1/public/images/" + p.ImageKey
			pv.ImageURL = &u
		}
		v.Products = append(v.Products, pv)
	}
	return v, nil
}

var imageKeyRe = regexp.MustCompile(`^[0-9a-f-]{36}\.(jpg|png|webp)$`)

func imageURL(key string) *string {
	if !imageKeyRe.MatchString(key) {
		return nil
	}
	u := "/api/v1/public/images/" + key
	return &u
}

func orNone(s string) string {
	if s == "test" {
		return s
	}
	return "none"
}

func nonNil(s []string) []string {
	if s == nil {
		return []string{}
	}
	return s
}

func (h *Handler) shareURL(slug string) string {
	return strings.TrimRight(h.links.APIBase, "/") + "/p/" + slug
}

func (h *Handler) view(w http.ResponseWriter, r *http.Request) {
	v, err := h.Build(r, r.PathValue("slug"))
	switch {
	case errors.Is(err, ErrNotFound):
		httpserver.WriteError(w, http.StatusNotFound, "store_not_found", "No encontramos esta tienda.")
	case err != nil:
		h.log.ErrorContext(r.Context(), "storefront", "err", err)
		httpserver.WriteError(w, http.StatusInternalServerError, "internal_error", "Ocurrió un error inesperado. Intenta de nuevo.")
	default:
		httpserver.WriteJSON(w, http.StatusOK, v)
	}
}

// sharePage is what WhatsApp/Facebook crawlers read (they do not run the SPA).
// Humans are redirected to the Flutter catalog.
var shareTpl = template.Must(template.New("share").Parse(`<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{{.Title}}</title>
<meta name="description" content="{{.Description}}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="KiuPop">
<meta property="og:title" content="{{.Title}}">
<meta property="og:description" content="{{.Description}}">
<meta property="og:url" content="{{.URL}}">
<meta property="og:image" content="{{.Image}}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:locale" content="es_CR">
<meta name="twitter:card" content="summary_large_image">
<meta http-equiv="refresh" content="0; url={{.Target}}">
<link rel="canonical" href="{{.URL}}">
<style>body{font-family:system-ui,sans-serif;background:{{.Bg}};color:{{.Text}};display:grid;place-items:center;min-height:100vh;margin:0}a{color:{{.Primary}}}</style>
</head><body><p>Abriendo <a href="{{.Target}}">{{.Title}}</a>…</p></body></html>`))

func (h *Handler) sharePage(w http.ResponseWriter, r *http.Request) {
	v, err := h.Build(r, r.PathValue("slug"))
	if err != nil {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.WriteHeader(http.StatusNotFound)
		fmt.Fprint(w, `<!doctype html><meta charset="utf-8"><title>Tienda no encontrada</title><p>No encontramos esta tienda.</p>`)
		return
	}
	desc := v.Store.Tagline
	if v.Store.Description != "" {
		desc = v.Store.Description
	}
	img := strings.TrimRight(h.links.APIBase, "/") + "/og/" + v.Store.Slug + ".png"
	if v.Store.CoverURL != nil {
		img = strings.TrimRight(h.links.APIBase, "/") + *v.Store.CoverURL
	}
	for _, p := range v.Products {
		if v.Store.CoverURL != nil {
			break
		}
		if p.ImageURL != nil {
			img = strings.TrimRight(h.links.APIBase, "/") + *p.ImageURL
			break
		}
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "public, max-age=300")
	w.Header().Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; img-src *")
	_ = shareTpl.Execute(w, map[string]string{
		"Title": v.Store.Name + " · KiuPop", "Description": desc, "URL": v.Share.URL, "Image": img,
		"Target": strings.TrimRight(h.links.WebBase, "/") + "/#/s/" + v.Store.Slug,
		"Bg":     v.Theme.Colors.Bg, "Text": v.Theme.Colors.Text, "Primary": v.Theme.Colors.Primary,
	})
}

// ogImage draws a 1200x630 bubblegum cover in the store's palette (no text, no fonts).
func (h *Handler) ogImage(w http.ResponseWriter, r *http.Request) {
	slug, ok := strings.CutSuffix(r.PathValue("file"), ".png")
	if !ok {
		http.NotFound(w, r)
		return
	}
	v, err := h.Build(r, slug)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	key := v.Theme.Colors
	cached, ok := h.covers.Load(key)
	if !ok {
		var buf bytes.Buffer
		if err := png.Encode(&buf, Cover(v.Theme.Colors, 1200, 630)); err != nil {
			http.Error(w, "error", http.StatusInternalServerError)
			return
		}
		cached, _ = h.covers.LoadOrStore(key, buf.Bytes()) // ≤ a few palettes: bounded by templates × colours
	}
	png := cached.([]byte)
	w.Header().Set("Content-Type", "image/png")
	w.Header().Set("Cache-Control", "public, max-age=3600")
	w.Header().Set("Content-Length", strconv.Itoa(len(png)))
	_, _ = w.Write(png)
}

// Cover renders a gradient with three glossy bubbles.
func Cover(c sf.Colors, wd, ht int) image.Image {
	img := image.NewRGBA(image.Rect(0, 0, wd, ht))
	bg, sec, pri, acc := hexColor(c.Bg), hexColor(c.Secondary), hexColor(c.Primary), hexColor(c.Accent)
	bubbles := []struct {
		x, y, r float64
		col     color.RGBA
	}{{0.72, 0.48, 0.34, acc}, {0.24, 0.70, 0.16, pri}, {0.40, 0.22, 0.09, sec}}
	for y := 0; y < ht; y++ {
		for x := 0; x < wd; x++ {
			t := (float64(x)/float64(wd) + float64(y)/float64(ht)) / 2
			px := mix(bg, sec, t)
			for _, b := range bubbles {
				dx, dy := float64(x)/float64(ht)-b.x*float64(wd)/float64(ht), float64(y)/float64(ht)-b.y
				d := math.Hypot(dx, dy) / b.r
				if d < 1 {
					px = mix(px, b.col, 0.55+0.25*(1-d))
					hx, hy := dx/b.r+0.35, dy/b.r+0.35
					if hl := math.Hypot(hx, hy); hl < 0.28 {
						px = mix(px, color.RGBA{255, 255, 255, 255}, 0.7*(1-hl/0.28))
					}
				}
			}
			img.SetRGBA(x, y, px)
		}
	}
	return img
}

func hexColor(s string) color.RGBA {
	v, err := strconv.ParseUint(strings.TrimPrefix(s, "#"), 16, 32)
	if err != nil || len(s) != 7 {
		return color.RGBA{255, 255, 255, 255}
	}
	return color.RGBA{uint8(v >> 16), uint8(v >> 8), uint8(v), 255}
}

func mix(a, b color.RGBA, t float64) color.RGBA {
	t = math.Max(0, math.Min(1, t))
	l := func(x, y uint8) uint8 { return uint8(float64(x)*(1-t) + float64(y)*t + 0.5) }
	return color.RGBA{l(a.R, b.R), l(a.G, b.G), l(a.B, b.B), 255}
}
