// Package storefront owns the store's public read model and its publication:
// draft rows for Kiu, validated snapshots, the public storefront view, and the
// Open Graph share pages. It writes stores + products in one transaction so a
// publication is all-or-nothing.
package storefront

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	sf "github.com/kiuvy-universe/kiupop/backend/internal/platform/storefront"
)

// ErrNotFound means the store does not exist, is not published, or is not the caller's.
var ErrNotFound = errors.New("store not found")

// Repo implements the agent's StoreDrafts port and the public read model.
type Repo struct{ pool *pgxpool.Pool }

// NewRepo returns a repo.
func NewRepo(pool *pgxpool.Pool) *Repo { return &Repo{pool: pool} }

// CreateDraft implements agent.StoreDrafts with a placeholder slug and name.
func (r *Repo) CreateDraft(ctx context.Context, owner, _ string) (sf.StoreRef, error) {
	for i := 0; i < 5; i++ {
		slug := "tienda-" + randomHex(4)
		var ref sf.StoreRef
		err := r.pool.QueryRow(ctx, `INSERT INTO stores (slug, name, status, owner_user_id)
			VALUES ($1, 'Mi tienda', 'draft', $2) ON CONFLICT (slug) DO NOTHING RETURNING id::text, slug`, slug, owner).
			Scan(&ref.ID, &ref.Slug)
		if err == nil {
			return ref, nil
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return sf.StoreRef{}, err
		}
	}
	return sf.StoreRef{}, errors.New("could not allocate draft slug")
}

// SyncDraft implements agent.StoreDrafts: copies the blueprint into the draft
// row and re-slugs it from the business name while it is still a draft.
func (r *Repo) SyncDraft(ctx context.Context, storeID, owner string, d sf.DraftData) (sf.StoreRef, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return sf.StoreRef{}, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	var ref sf.StoreRef
	var status, name string
	if err := tx.QueryRow(ctx, `SELECT id::text, slug, status, name FROM stores WHERE id = $1 AND owner_user_id = $2 FOR UPDATE`,
		storeID, owner).Scan(&ref.ID, &ref.Slug, &status, &name); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return sf.StoreRef{}, ErrNotFound
		}
		return sf.StoreRef{}, err
	}
	if status != "draft" {
		return ref, tx.Commit(ctx)
	}
	if d.Name != "" && d.Name != name {
		if ref.Slug, err = reslug(ctx, tx, storeID, d.Name); err != nil {
			return sf.StoreRef{}, err
		}
		name = d.Name
	}
	theme, _ := json.Marshal(sf.Normalize(d.Theme))
	profile, _ := json.Marshal(d.Profile)
	if _, err := tx.Exec(ctx, `UPDATE stores SET name = $2, description = $3, whatsapp_e164 = NULLIF($4, ''),
		template = $5, theme = $6, profile = $7 WHERE id = $1`,
		storeID, name, d.Description, d.WhatsApp, sf.Normalize(d.Theme).Template, theme, profile); err != nil {
		return sf.StoreRef{}, fmt.Errorf("sync draft: %w", err)
	}
	return ref, tx.Commit(ctx)
}

func reslug(ctx context.Context, tx pgx.Tx, storeID, name string) (string, error) {
	base := Slugify(name)
	for i := 1; i <= 50; i++ {
		slug := base
		if i > 1 {
			suffix := "-" + strconv.Itoa(i)
			if len(slug)+len(suffix) > 60 {
				slug = slug[:60-len(suffix)]
			}
			slug += suffix
		}
		var got string
		err := tx.QueryRow(ctx, `UPDATE stores SET slug = $2 WHERE id = $1
			AND NOT EXISTS (SELECT 1 FROM stores WHERE slug = $2 AND id <> $1) RETURNING slug`, storeID, slug).Scan(&got)
		if err == nil {
			return got, nil
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return "", err
		}
	}
	return "", errors.New("could not allocate slug")
}

// Publish implements agent.StoreDrafts. It is idempotent: the same snapshot
// published twice returns the existing version.
func (r *Repo) Publish(ctx context.Context, storeID, owner string, s sf.Snapshot) (sf.Publication, error) {
	if s.Name == "" || s.WhatsApp == "" || len(s.Products) == 0 {
		return sf.Publication{}, errors.New("refusing to publish an incomplete snapshot")
	}
	s.Theme = sf.Normalize(s.Theme)
	for _, p := range s.Products {
		if p.PriceMinor <= 0 || p.Name == "" {
			return sf.Publication{}, errors.New("refusing to publish a product without a price")
		}
		if p.Featured {
			s.Profile.Featured = append(s.Profile.Featured, p.ID)
		}
	}
	raw, err := json.Marshal(s)
	if err != nil {
		return sf.Publication{}, err
	}
	sum := sha256.Sum256(raw)

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return sf.Publication{}, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	var pub sf.Publication
	if err := tx.QueryRow(ctx, `SELECT slug, published_version FROM stores WHERE id = $1 AND owner_user_id = $2 FOR UPDATE`,
		storeID, owner).Scan(&pub.Slug, &pub.Version); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return sf.Publication{}, ErrNotFound
		}
		return sf.Publication{}, err
	}
	if pub.Version > 0 {
		var last []byte
		if err := tx.QueryRow(ctx, `SELECT snapshot_hash FROM store_publications WHERE store_id = $1 AND version = $2`,
			storeID, pub.Version).Scan(&last); err == nil && string(last) == string(sum[:]) {
			return pub, nil
		}
	}
	pub.Version++
	theme, _ := json.Marshal(s.Theme)
	profile, _ := json.Marshal(s.Profile)
	if _, err := tx.Exec(ctx, `UPDATE stores SET name = $2, description = $3, whatsapp_e164 = $4, template = $5,
		theme = $6, profile = $7, status = 'published', published_version = $8, published_at = now() WHERE id = $1`,
		storeID, s.Name, truncate(s.Desc, 500), s.WhatsApp, s.Theme.Template, theme, profile, pub.Version); err != nil {
		return sf.Publication{}, fmt.Errorf("publish store: %w", err)
	}
	for i, p := range s.Products {
		// created_at keeps the merchant's order (same transaction → same now()).
		tag, err := tx.Exec(ctx, `INSERT INTO products (id, store_id, name, description, price_minor, currency, image_key, available, created_at)
			VALUES ($1, $2, $3, $4, $5, 'CRC', NULLIF($6, ''), true, now() + $7 * interval '1 millisecond')
			ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, description = EXCLUDED.description,
				price_minor = EXCLUDED.price_minor, image_key = COALESCE(EXCLUDED.image_key, products.image_key),
				available = true, updated_at = now()
			WHERE products.store_id = EXCLUDED.store_id`, p.ID, storeID, truncate(p.Name, 80), truncate(p.Description, 600), p.PriceMinor, p.ImageKey, i)
		if err != nil {
			return sf.Publication{}, fmt.Errorf("publish product: %w", err)
		}
		if tag.RowsAffected() != 1 {
			return sf.Publication{}, errors.New("product id belongs to another store")
		}
	}
	// Products dropped from the snapshot stop being sold (no stale prices).
	ids := make([]string, 0, len(s.Products))
	for _, p := range s.Products {
		ids = append(ids, p.ID)
	}
	if _, err := tx.Exec(ctx, `UPDATE products SET available = false, updated_at = now()
		WHERE store_id = $1 AND available AND NOT (id = ANY($2::uuid[]))`, storeID, ids); err != nil {
		return sf.Publication{}, fmt.Errorf("retire products: %w", err)
	}
	if _, err := tx.Exec(ctx, `INSERT INTO store_publications (store_id, version, snapshot_hash, snapshot) VALUES ($1, $2, $3, $4)`,
		storeID, pub.Version, sum[:], raw); err != nil {
		return sf.Publication{}, fmt.Errorf("record publication: %w", err)
	}
	return pub, tx.Commit(ctx)
}

// Published is a published store's row.
type Published struct {
	ID, Slug, Name, Description, WhatsApp, Template string
	Theme                                           sf.Theme
	Profile                                         sf.Profile
}

// BySlug returns a published store.
func (r *Repo) BySlug(ctx context.Context, slug string) (Published, error) {
	var p Published
	var theme, profile []byte
	err := r.pool.QueryRow(ctx, `SELECT id::text, slug, name, description, coalesce(whatsapp_e164, ''), template, theme, profile
		FROM stores WHERE slug = $1 AND status = 'published'`, slug).
		Scan(&p.ID, &p.Slug, &p.Name, &p.Description, &p.WhatsApp, &p.Template, &theme, &profile)
	if errors.Is(err, pgx.ErrNoRows) {
		return Published{}, ErrNotFound
	}
	if err != nil {
		return Published{}, err
	}
	_ = json.Unmarshal(theme, &p.Theme)
	_ = json.Unmarshal(profile, &p.Profile)
	if !sf.ValidTemplate(p.Theme.Template) {
		p.Theme = sf.Default(p.Template) // POC stores created before templates existed
	}
	p.Theme = sf.Normalize(p.Theme)
	return p, nil
}

// ProductRow is a public product.
type ProductRow struct {
	ID, Name, Description, ImageKey string
	PriceMinor                      int64
}

// Products lists a store's available products.
func (r *Repo) Products(ctx context.Context, storeID string) ([]ProductRow, error) {
	rows, err := r.pool.Query(ctx, `SELECT id::text, name, description, coalesce(image_key, ''), price_minor
		FROM products WHERE store_id = $1 AND available ORDER BY created_at, id LIMIT 500`, storeID)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(row pgx.CollectableRow) (ProductRow, error) {
		var p ProductRow
		return p, row.Scan(&p.ID, &p.Name, &p.Description, &p.ImageKey, &p.PriceMinor)
	})
}

// OwnedStoreID returns the newest store owned by a user (for admin endpoints).
func (r *Repo) OwnedStoreID(ctx context.Context, userID string) (string, error) {
	var id string
	// Published stores first: a fresh draft for a second store never hijacks the admin.
	err := r.pool.QueryRow(ctx, `SELECT id::text FROM stores WHERE owner_user_id = $1
		ORDER BY (status = 'published') DESC, created_at DESC LIMIT 1`, userID).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrNotFound
	}
	return id, err
}

func randomHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func truncate(s string, n int) string {
	if r := []rune(s); len(r) > n {
		return string(r[:n])
	}
	return s
}

var accents = strings.NewReplacer("á", "a", "é", "e", "í", "i", "ó", "o", "ú", "u", "ü", "u", "ñ", "n",
	"à", "a", "è", "e", "ì", "i", "ò", "o", "ù", "u", "ç", "c")
var nonSlug = regexp.MustCompile(`[^a-z0-9]+`)

// Slugify mirrors stores.Slugify (modules never import each other).
func Slugify(name string) string {
	s := strings.Trim(nonSlug.ReplaceAllString(accents.Replace(strings.ToLower(name)), "-"), "-")
	if len(s) > 50 {
		s = strings.TrimRight(s[:50], "-")
	}
	if len(s) < 3 {
		s = strings.Trim("tienda-"+s, "-")
	}
	return s
}

// ActivateTestPlan gives the owner's store an active TEST plan (US$5/month,
// no money moves). Idempotent: an active plan is returned unchanged; a
// canceled or expired one is renewed for a new period.
func (r *Repo) ActivateTestPlan(ctx context.Context, storeID, owner string, now time.Time) (sf.Plan, error) {
	var p sf.Plan
	err := r.pool.QueryRow(ctx, `
		INSERT INTO store_plans (store_id, plan, price_minor, currency, status, test, activated_at, current_period_end)
		SELECT s.id, $3, $4, $5, 'active', true, $6, $7
		  FROM stores s WHERE s.id = $1 AND s.owner_user_id = $2
		ON CONFLICT (store_id) DO UPDATE
		   SET status = 'active', activated_at = EXCLUDED.activated_at, current_period_end = EXCLUDED.current_period_end
		 WHERE store_plans.status <> 'active' OR store_plans.current_period_end <= $6
		RETURNING plan, status, price_minor, currency, test, current_period_end`,
		storeID, owner, sf.PlanMonthly, sf.PlanPriceMinor, sf.PlanCurrency, now, now.Add(sf.PlanPeriodLength)).
		Scan(&p.Plan, &p.Status, &p.PriceMinor, &p.Currency, &p.Test, &p.PeriodEnd)
	if errors.Is(err, pgx.ErrNoRows) {
		// Either the store is not the caller's, or an active plan already exists.
		cur, ok, err := r.activePlan(ctx, storeID, owner, now)
		if err != nil {
			return sf.Plan{}, err
		}
		if !ok {
			return sf.Plan{}, ErrNotFound
		}
		return cur, nil
	}
	return p, err
}

// ActivePlan reports the store's current plan, if it is active and unexpired.
func (r *Repo) ActivePlan(ctx context.Context, storeID, owner string, now time.Time) (sf.Plan, bool, error) {
	return r.activePlan(ctx, storeID, owner, now)
}

func (r *Repo) activePlan(ctx context.Context, storeID, owner string, now time.Time) (sf.Plan, bool, error) {
	var p sf.Plan
	err := r.pool.QueryRow(ctx, `
		SELECT p.plan, p.status, p.price_minor, p.currency, p.test, p.current_period_end
		  FROM store_plans p JOIN stores s ON s.id = p.store_id
		 WHERE p.store_id = $1 AND s.owner_user_id = $2 AND p.status = 'active' AND p.current_period_end > $3`,
		storeID, owner, now).Scan(&p.Plan, &p.Status, &p.PriceMinor, &p.Currency, &p.Test, &p.PeriodEnd)
	if errors.Is(err, pgx.ErrNoRows) {
		return sf.Plan{}, false, nil
	}
	return p, err == nil, err
}
