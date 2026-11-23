package agent

import (
	"bytes"
	"context"
	"encoding/csv"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"path/filepath"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"

	"github.com/kiuvy-universe/kiupop/backend/internal/platform/storage"
)

// Attachment limits (provisional; tune with performance and cost tests).
const (
	MaxAttachments      = 5
	MaxAttachmentsBytes = 50 << 20
	MaxCSVBytes         = 1 << 20
	MaxPDFBytes         = 20 << 20
	MaxCSVRows          = 200
)

var (
	// ErrUnsupportedFile means the bytes are not a JPEG/PNG/WebP photo, an Excel/CSV/text catalog or a PDF.
	ErrUnsupportedFile = errors.New("unsupported file")
	// ErrAttachmentLimit means the session already has the maximum files or bytes.
	ErrAttachmentLimit = errors.New("attachment limit")
	// ErrNoReader means photo recognition / PDF reading needs AI that is not configured.
	ErrNoReader = errors.New("no reader")
)

// Attachment is one file the merchant shared, with its own status.
type Attachment struct {
	ID        string    `json:"id"`
	Kind      string    `json:"kind"` // image | csv (Excel, CSV or text catalog) | pdf
	Filename  string    `json:"filename"`
	SizeBytes int64     `json:"size_bytes"`
	Status    string    `json:"status"` // received | processing | processed | needs_review | error
	Note      string    `json:"note"`
	ImageURL  *string   `json:"image_url"`
	CreatedAt time.Time `json:"created_at"`
	key       string
	sessionID string
}

// Files stores attachment bytes under server-generated keys (never user paths).
type Files interface {
	SaveImage(data []byte) (string, error)
	SaveDoc(data []byte, ext string) (string, error)
	Read(key string) ([]byte, error)
	// Delete removes a file whose upload could not be recorded (best effort).
	Delete(key string)
}

// LocalFiles keeps files in the uploads volume. Photos reuse the product image
// store (validated by content); documents get their own subdirectory.
type LocalFiles struct{ Dir string }

// SaveImage implements Files.
func (f LocalFiles) SaveImage(data []byte) (string, error) {
	return storage.Images{Dir: f.Dir}.Save(data)
}

// SaveDoc implements Files.
func (f LocalFiles) SaveDoc(data []byte, ext string) (string, error) {
	return storage.Docs{Dir: f.Dir}.Save(data, ext)
}

// Delete implements Files.
func (f LocalFiles) Delete(key string) {
	if storage.ValidKey(key) {
		storage.Images{Dir: f.Dir}.Delete(key)
		return
	}
	storage.Docs{Dir: f.Dir}.Delete(key)
}

// Read implements Files.
func (f LocalFiles) Read(key string) ([]byte, error) {
	if storage.ValidKey(key) {
		file, err := storage.Images{Dir: f.Dir}.Open(key)
		if err != nil {
			return nil, err
		}
		defer file.Close()
		return io.ReadAll(io.LimitReader(file, MaxPDFBytes+1))
	}
	return storage.Docs{Dir: f.Dir}.Read(key)
}

// BucketFiles keeps attachments in the private bucket: photos under images/
// (they can become catalog photos), catalogs under tmp/ (deleted in 24 h).
type BucketFiles struct {
	Images storage.BucketImages
	Docs   storage.BucketDocs
}

// SaveImage implements Files.
func (f BucketFiles) SaveImage(data []byte) (string, error) { return f.Images.Save(data) }

// SaveDoc implements Files.
func (f BucketFiles) SaveDoc(data []byte, ext string) (string, error) { return f.Docs.Save(data, ext) }

// Delete implements Files.
func (f BucketFiles) Delete(key string) {
	if storage.ValidKey(key) {
		f.Images.Delete(key)
		return
	}
	f.Docs.Delete(key)
}

// Read implements Files.
func (f BucketFiles) Read(key string) ([]byte, error) {
	if storage.ValidKey(key) {
		r, err := f.Images.Open(key)
		if err != nil {
			return nil, err
		}
		defer r.Close()
		return io.ReadAll(io.LimitReader(r, MaxPDFBytes+1))
	}
	return f.Docs.Read(key, MaxPDFBytes)
}

// PhotoResult is what a reader sees in a product photo. It never contains prices.
type PhotoResult struct {
	IsProduct   bool   `json:"is_product"`
	MatchesName string `json:"matches_name"` // one of the known product names, or ""
	ProductName string `json:"product_name"` // short name if it is a new product
}

// Reader recognises products in photos and catalogs (AI). NoReader when AI is off.
type Reader interface {
	Photo(ctx context.Context, img []byte, mediaType string, known []string) (PhotoResult, Usage, error)
	Catalog(ctx context.Context, pdf []byte) ([]ExtractedProduct, Usage, error)
}

// NoReader is used without AI: photos are assigned deterministically, PDFs need review.
type NoReader struct{}

// Photo implements Reader.
func (NoReader) Photo(context.Context, []byte, string, []string) (PhotoResult, Usage, error) {
	return PhotoResult{}, Usage{}, ErrNoReader
}

// Catalog implements Reader.
func (NoReader) Catalog(context.Context, []byte) ([]ExtractedProduct, Usage, error) {
	return nil, Usage{}, ErrNoReader
}

var unsafeName = regexp.MustCompile(`[^\p{L}\p{N} ._()-]+`)

func cleanFilename(name string) string {
	name = filepath.Base(strings.ReplaceAll(name, "\\", "/"))
	name = strings.TrimSpace(unsafeName.ReplaceAllString(name, ""))
	if name == "" || name == "." {
		name = "archivo"
	}
	return truncate(name, 120)
}

// DetectKind classifies by content (never by the client's MIME type).
func DetectKind(filename string, data []byte) (string, error) {
	if len(data) == 0 {
		return "", ErrUnsupportedFile
	}
	if _, err := storage.Sniff(data); err == nil {
		return "image", nil
	}
	if bytes.HasPrefix(data, []byte("%PDF-")) {
		if len(data) > MaxPDFBytes {
			return "", ErrUnsupportedFile
		}
		return "pdf", nil
	}
	lower := strings.ToLower(filename)
	if isXLSX(data) {
		if len(data) <= MaxXLSXBytes && strings.HasSuffix(lower, ".xlsx") {
			return "csv", nil // tabular catalog; the format is read from the content
		}
		return "", ErrUnsupportedFile
	}
	ct := http.DetectContentType(data)
	if len(data) <= MaxCSVBytes && utf8.Valid(data) && !bytes.ContainsRune(data, 0) &&
		strings.HasPrefix(ct, "text/plain") && (strings.HasSuffix(lower, ".csv") || strings.HasSuffix(lower, ".txt")) {
		return "csv", nil
	}
	return "", ErrUnsupportedFile
}

// Upload validates and stores one file, then queues its processing.
func (s *Service) Upload(ctx context.Context, userID, sessionID, filename string, data []byte) (Attachment, error) {
	sess, err := s.repo.Get(ctx, sessionID, userID)
	if err != nil {
		return Attachment{}, err
	}
	if sess.Status == "published" {
		return Attachment{}, ErrSessionClosed
	}
	kind, err := DetectKind(filename, data)
	if err != nil {
		return Attachment{}, err
	}
	count, total, err := s.repo.AttachmentUsage(ctx, sessionID)
	if err != nil {
		return Attachment{}, err
	}
	if count >= s.cfg.maxFiles() || total+int64(len(data)) > s.cfg.maxFilesBytes() {
		return Attachment{}, ErrAttachmentLimit
	}
	var key string
	switch kind {
	case "image":
		key, err = s.files.SaveImage(data)
	default:
		key, err = s.files.SaveDoc(data, kind)
	}
	if err != nil {
		return Attachment{}, fmt.Errorf("save attachment: %w", err)
	}
	var a Attachment
	_, err = s.repo.Update(ctx, sessionID, func(t *Tx) error {
		// Re-check under the session lock so parallel uploads cannot exceed the limits.
		n, sum, err := attachmentUsage(ctx, t.tx, sessionID)
		if err != nil {
			return err
		}
		if n >= s.cfg.maxFiles() || sum+int64(len(data)) > s.cfg.maxFilesBytes() {
			return ErrAttachmentLimit
		}
		a, err = insertAttachment(ctx, t.tx, sessionID, kind, cleanFilename(filename), int64(len(data)), key)
		if err != nil {
			return err
		}
		if _, err := t.Enqueue(ctx, "attachment", "attach:"+a.ID, map[string]string{"attachment_id": a.ID}, nil, 2); err != nil {
			return err
		}
		_, err = t.Emit(ctx, "attachment.updated", a, "")
		return err
	})
	if err != nil {
		s.files.Delete(key) // nothing references it: do not leave orphans behind
		return Attachment{}, err
	}
	s.funnel(ctx, userID, sessionID, "files_uploaded", map[string]int64{"bytes": int64(len(data)),
		"is_" + kind: 1})
	s.repo.RecordAction(ctx, sessionID, "user", ToolResult{Tool: "receive_attachment", Outcome: "ok", Summary: map[string]any{"kind": kind, "bytes": len(data)}}, 0)
	s.bus.WakeWorkers()
	s.emitProgress(ctx, sessionID)
	return a, nil
}

// jobAttachment processes one file: photo → product image or cover; CSV → priced
// products; PDF → proposal the merchant confirms (AI only).
func (s *Service) jobAttachment(ctx context.Context, j *Job) error {
	var in struct {
		AttachmentID string `json:"attachment_id"`
	}
	if err := json.Unmarshal(j.Input, &in); err != nil {
		return err
	}
	a, err := s.repo.Attachment(ctx, in.AttachmentID)
	if err != nil {
		return err
	}
	if a.Status == "processed" || a.Status == "needs_review" {
		return errNoop
	}
	_ = s.repo.SetAttachment(ctx, j.SessionID, a.ID, "processing", "")
	s.bus.Notify(j.SessionID)
	sess, err := s.repo.GetSystem(ctx, j.SessionID)
	if err != nil {
		return err
	}
	if sess.Status == "published" {
		return errNoop
	}
	data, err := s.files.Read(a.key)
	if err != nil {
		_ = s.repo.SetAttachment(ctx, j.SessionID, a.ID, "error", "No pudimos leer el archivo.")
		return errNoop
	}
	switch a.Kind {
	case "image":
		return s.attachPhoto(ctx, sess, a, data)
	case "csv":
		return s.attachCSV(ctx, a, data)
	default:
		return s.attachPDF(ctx, sess, a, data)
	}
}

func (s *Service) attachPhoto(ctx context.Context, sess Session, a Attachment, data []byte) error {
	var known []string
	for _, p := range sess.Blueprint.Products {
		known = append(known, p.Name)
	}
	var ai PhotoResult
	aiOK := false
	if s.withinBudget(ctx, sess) {
		ext, _ := storage.Sniff(data)
		res, u, err := s.reader.Photo(ctx, data, storage.ContentTypeFor("x."+ext), known)
		if u.Model != "" {
			s.repo.RecordUsage(ctx, sess.ID, u)
		}
		aiOK = err == nil
		ai = res
	}
	note := ""
	_, err := s.repo.Update(ctx, sess.ID, func(t *Tx) error {
		bp := &t.S.Blueprint
		ch := Changes{Images: true}
		target := -1
		if aiOK && ai.IsProduct && ai.MatchesName != "" {
			target = findProduct(bp, ai.MatchesName)
		}
		if target < 0 && (!aiOK || ai.IsProduct) {
			for i, p := range bp.Products { // local rule: photos follow the order products were mentioned
				if p.ImageKey == "" && (!aiOK || ai.ProductName == "") {
					target = i
					break
				}
			}
		}
		switch {
		case target >= 0:
			bp.Products[target].ImageKey = a.key
			note = "Foto de «" + bp.Products[target].Name + "»."
		case aiOK && ai.IsProduct && validProductName(ai.ProductName) && len(bp.Products) < MaxProducts:
			id := s.newID()
			bp.Products = append(bp.Products, DraftProduct{ID: id, Name: capFirst(ai.ProductName), CopyStatus: "pending", ImageKey: a.key})
			ch.NewProducts = append(ch.NewProducts, id)
			note = "Nuevo producto «" + capFirst(ai.ProductName) + "» (sin precio todavía)."
		default:
			bp.Business.CoverKey = a.key
			note = "La usé como portada de tu tienda."
		}
		if err := setAttachment(ctx, t.tx, a.ID, "processed", note); err != nil {
			return err
		}
		if _, err := t.Emit(ctx, "attachment.updated", map[string]string{"id": a.ID}, ""); err != nil {
			return err
		}
		if err := s.say(ctx, t, "Recibí tu foto: "+lowerFirst(note), MessageMeta{Kind: "notice"}); err != nil {
			return err
		}
		themeJob, err := s.enqueueAffected(ctx, t, ch)
		if err != nil {
			return err
		}
		return s.advance(ctx, t, nil, s.brain.Mode(), themeJob)
	})
	return err
}

func validProductName(n string) bool {
	n = strings.TrimSpace(n)
	return !isCommandReply(n) && utf8.RuneCountInString(n) >= 2 && utf8.RuneCountInString(n) <= 60 && !claimRe.MatchString(n) && !urlRe.MatchString(n)
}

// ParseCatalogCSV reads "producto,precio" rows (header optional; ',' or ';').
// It returns the products and a normalised text the grounding rules can check.
func ParseCatalogCSV(data []byte) ([]ExtractedProduct, string) {
	data = bytes.TrimPrefix(data, []byte("\xef\xbb\xbf"))
	sep := ','
	if first, _, _ := bytes.Cut(data, []byte("\n")); bytes.Count(first, []byte(";")) > bytes.Count(first, []byte(",")) {
		sep = ';'
	}
	r := csv.NewReader(bytes.NewReader(data))
	r.Comma, r.FieldsPerRecord, r.LazyQuotes = sep, -1, true
	rows, err := r.ReadAll()
	if err != nil || len(rows) == 0 {
		return nil, ""
	}
	return catalogFromRows(rows)
}

func (s *Service) attachCSV(ctx context.Context, a Attachment, data []byte) error {
	products, text := ParseCatalogFile(a.Filename, data)
	_, err := s.repo.Update(ctx, a.sessionID, func(t *Tx) error {
		bp := &t.S.Blueprint
		if len(products) == 0 {
			if err := setAttachment(ctx, t.tx, a.ID, "needs_review", "No encontré productos con precio. Usá una columna de producto y otra de precio, o una línea por producto («Ramo rosas ₡15.000»)."); err != nil {
				return err
			}
			_, err := t.Emit(ctx, "attachment.updated", map[string]string{"id": a.ID}, "")
			return err
		}
		var ch Changes
		ch.Results = append(ch.Results, upsertDraftProducts(bp, products, text, FieldPrices, s.newID, &ch))
		note := fmt.Sprintf("Leí %d %s con precio de tu catálogo.", ch.PricedProducts, plural(ch.PricedProducts, "producto", "productos"))
		if err := setAttachment(ctx, t.tx, a.ID, "processed", note); err != nil {
			return err
		}
		if _, err := t.Emit(ctx, "attachment.updated", map[string]string{"id": a.ID}, ""); err != nil {
			return err
		}
		if err := s.say(ctx, t, note, MessageMeta{Kind: "notice"}); err != nil {
			return err
		}
		themeJob, err := s.enqueueAffected(ctx, t, ch)
		if err != nil {
			return err
		}
		return s.advance(ctx, t, nil, s.brain.Mode(), themeJob)
	})
	return err
}

// attachPDF never sets prices directly: it proposes, and the merchant confirms
// with one tap (the confirmation message itself is what grounds the prices).
func (s *Service) attachPDF(ctx context.Context, sess Session, a Attachment, data []byte) error {
	var products []ExtractedProduct
	var rerr error = ErrNoReader
	if s.withinBudget(ctx, sess) {
		var u Usage
		products, u, rerr = s.reader.Catalog(ctx, data)
		if u.Model != "" {
			s.repo.RecordUsage(ctx, sess.ID, u)
		}
	}
	_, err := s.repo.Update(ctx, sess.ID, func(t *Tx) error {
		var lines, labels []string
		for _, p := range products {
			if validProductName(p.Name) && p.PriceColones >= 100 && len(lines) < MaxProducts {
				lines = append(lines, fmt.Sprintf("%s %d", strings.Join(strings.Fields(p.Name), " "), p.PriceColones))
				labels = append(labels, fmt.Sprintf("%s ₡%s", p.Name, thousands(p.PriceColones)))
			}
		}
		status, note := "processed", ""
		switch {
		case errors.Is(rerr, ErrNoReader):
			status, note = "needs_review", "Para leer PDFs necesito la IA. Escribime tus productos con su precio."
		case rerr != nil || len(lines) == 0:
			status, note = "needs_review", "No pude leer productos con precio en este PDF. Escribímelos y los agrego."
		default:
			note = fmt.Sprintf("Encontré %d productos en tu catálogo.", len(lines))
		}
		if err := setAttachment(ctx, t.tx, a.ID, status, note); err != nil {
			return err
		}
		if _, err := t.Emit(ctx, "attachment.updated", map[string]string{"id": a.ID}, ""); err != nil {
			return err
		}
		if status != "processed" {
			return s.say(ctx, t, note, MessageMeta{Kind: "notice"})
		}
		confirm := strings.Join(lines, ", ")
		return s.say(ctx, t, note+" ¿Uso estos precios? "+strings.Join(labels, " · "), MessageMeta{Kind: "notice",
			QuickReplies: []QuickReply{{Label: "Sí, usá esos precios", Value: confirm}, {Label: "No, te los escribo", Value: "omitir"}}})
	})
	return err
}

func thousands(n int64) string {
	s := fmt.Sprint(n)
	var b strings.Builder
	for i, c := range s {
		if i > 0 && (len(s)-i)%3 == 0 {
			b.WriteByte('.')
		}
		b.WriteRune(c)
	}
	return b.String()
}

// --- persistence -------------------------------------------------------------

const attachmentCols = `id::text, session_id::text, kind, filename, size_bytes, coalesce(storage_key, ''), status, note, created_at`

func scanAttachment(row pgx.Row) (Attachment, error) {
	var a Attachment
	err := row.Scan(&a.ID, &a.sessionID, &a.Kind, &a.Filename, &a.SizeBytes, &a.key, &a.Status, &a.Note, &a.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Attachment{}, ErrSessionNotFound
	}
	if a.Kind == "image" && storage.ValidKey(a.key) {
		u := "/api/v1/public/images/" + a.key
		a.ImageURL = &u
	}
	return a, err
}

func insertAttachment(ctx context.Context, q querier, sessionID, kind, filename string, size int64, key string) (Attachment, error) {
	return scanAttachment(q.QueryRow(ctx, `INSERT INTO agent_attachments (session_id, kind, filename, size_bytes, storage_key)
		VALUES ($1, $2, $3, $4, $5) RETURNING `+attachmentCols, sessionID, kind, filename, size, key))
}

func attachmentUsage(ctx context.Context, q querier, sessionID string) (int, int64, error) {
	var n int
	var total int64
	err := q.QueryRow(ctx, `SELECT count(*), coalesce(sum(size_bytes), 0) FROM agent_attachments WHERE session_id = $1`, sessionID).Scan(&n, &total)
	return n, total, err
}

func setAttachment(ctx context.Context, q querier, id, status, note string) error {
	_, err := q.Exec(ctx, `UPDATE agent_attachments SET status = $2, note = left($3, 300), updated_at = now() WHERE id = $1`, id, status, note)
	return err
}

// AttachmentUsage returns how many files and bytes a session already holds.
func (r *Repo) AttachmentUsage(ctx context.Context, sessionID string) (int, int64, error) {
	return attachmentUsage(ctx, r.pool, sessionID)
}

// Attachment loads one attachment (workers only).
func (r *Repo) Attachment(ctx context.Context, id string) (Attachment, error) {
	if !validUUID(id) {
		return Attachment{}, ErrSessionNotFound
	}
	return scanAttachment(r.pool.QueryRow(ctx, `SELECT `+attachmentCols+` FROM agent_attachments WHERE id = $1`, id))
}

// SetAttachment updates status and emits an event.
func (r *Repo) SetAttachment(ctx context.Context, sessionID, id, status, note string) error {
	if err := setAttachment(ctx, r.pool, id, status, note); err != nil {
		return err
	}
	_, err := r.Emit(ctx, sessionID, "attachment.updated", map[string]string{"id": id}, "")
	return err
}

// Attachments lists a session's files (oldest first).
func (r *Repo) Attachments(ctx context.Context, sessionID string) ([]Attachment, error) {
	rows, err := r.pool.Query(ctx, `SELECT `+attachmentCols+` FROM agent_attachments WHERE session_id = $1 ORDER BY created_at, id`, sessionID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Attachment{}
	for rows.Next() {
		a, err := scanAttachment(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}
