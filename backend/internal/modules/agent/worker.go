package agent

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/kiuvy-universe/kiupop/backend/internal/platform/storefront"
)

// Worker tuning.
const (
	jobLease    = 30 * time.Second
	jobTimeout  = 20 * time.Second
	idlePoll    = 400 * time.Millisecond
	sweepPeriod = 5 * time.Second
)

// errNoop marks a job that found nothing to do (stale revision, already done).
var errNoop = errors.New("noop")

// RunWorkers starts n workers and a lease sweeper; it returns when ctx is done.
// Jobs survive restarts: on boot, expired leases are requeued.
func (s *Service) RunWorkers(ctx context.Context, n int) {
	if k, err := s.repo.RecoverExpired(ctx); err == nil && k > 0 {
		s.log.Info("recovered interrupted agent jobs", "count", k)
	}
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func() { defer wg.Done(); s.workLoop(ctx) }()
	}
	t := time.NewTicker(sweepPeriod)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			wg.Wait()
			return
		case <-t.C:
			if k, err := s.repo.RecoverExpired(ctx); err == nil && k > 0 {
				s.log.Warn("requeued expired agent jobs", "count", k)
				s.bus.WakeWorkers()
			}
		}
	}
}

func (s *Service) workLoop(ctx context.Context) {
	for ctx.Err() == nil {
		j, err := s.repo.Claim(ctx, jobLease)
		if err != nil {
			if ctx.Err() == nil {
				s.log.Error("claim job", "err", err)
			}
			sleep(ctx, time.Second, nil)
			continue
		}
		if j == nil {
			sleep(ctx, idlePoll, s.bus.work)
			continue
		}
		s.runJob(ctx, j)
	}
}

func sleep(ctx context.Context, d time.Duration, wake <-chan struct{}) {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
	case <-t.C:
	case <-wake:
	}
}

// RunOnce claims and runs a single job (tests and the bench use it). It reports whether one ran.
func (s *Service) RunOnce(ctx context.Context) (bool, error) {
	j, err := s.repo.Claim(ctx, jobLease)
	if err != nil || j == nil {
		return false, err
	}
	s.runJob(ctx, j)
	return true, nil
}

func (s *Service) runJob(parent context.Context, j *Job) {
	ctx, cancel := context.WithTimeout(parent, jobTimeout)
	defer cancel()
	start := s.now()
	err := s.dispatchJob(ctx, j)
	switch {
	case err == nil || errors.Is(err, errNoop):
		_ = s.repo.Finish(context.WithoutCancel(ctx), j.ID, map[string]any{"noop": errors.Is(err, errNoop), "ms": s.now().Sub(start).Milliseconds()})
	default:
		final, ferr := s.repo.Fail(context.WithoutCancel(ctx), j.ID, safeReason(err))
		s.log.Warn("agent job failed", "kind", j.Kind, "attempt", j.Attempts, "final", final, "err", err, "ferr", ferr)
	}
	s.bus.WakeWorkers()
	s.emitProgress(context.WithoutCancel(ctx), j.SessionID)
}

func safeReason(err error) string {
	r := err.Error()
	if len(r) > 300 {
		r = r[:300]
	}
	return r
}

// jobTheme runs suggest_store_theme for the current branding.
func (s *Service) jobTheme(ctx context.Context, j *Job) error {
	start := s.now()
	var picked string
	_, err := s.repo.Update(ctx, j.SessionID, func(t *Tx) error {
		if t.S.Status == "published" {
			return errNoop
		}
		bp := &t.S.Blueprint
		sel, theme := SuggestTheme(*bp, false)
		if bp.Template.InputKey == sel.InputKey && bp.Theme.Template == theme.Template && storefront.ValidTemplate(bp.Theme.Template) {
			return errNoop
		}
		bp.Template, bp.Theme = sel, theme
		picked = sel.ID
		t.Touch()
		rev := t.S.Revision + 1
		_, err := t.Enqueue(ctx, "preview", fmt.Sprintf("preview:%s:%d", t.S.ID, rev), previewInput{Revision: rev}, nil, 3)
		return err
	})
	if err == nil {
		s.repo.RecordAction(ctx, j.SessionID, "agent", ToolResult{Tool: "suggest_store_theme", Outcome: "ok", Summary: map[string]any{"template": picked}}, s.now().Sub(start))
	}
	return err
}

// jobCopy drafts one product description (optional work: failure never blocks POP).
func (s *Service) jobCopy(ctx context.Context, j *Job) error {
	var in copyInput
	if err := json.Unmarshal(j.Input, &in); err != nil {
		return err
	}
	sess, err := s.repo.GetSystem(ctx, j.SessionID)
	if err != nil {
		return err
	}
	p := productByID(sess.Blueprint, in.ProductID)
	if p == nil || p.Name != in.Name || p.CopyStatus != "pending" || sess.Status == "published" {
		return errNoop
	}
	desc, status := "", "done"
	if !s.withinBudget(ctx, sess) {
		status = "skipped"
	} else {
		var u Usage
		desc, u, err = s.copy.Describe(ctx, CopyInput{SessionID: j.SessionID, BusinessName: sess.Blueprint.Business.Name,
			Category: sess.Blueprint.Business.Category, ProductName: in.Name, Context: sess.Blueprint.Business.Description})
		if u.Model != "" {
			s.repo.RecordUsage(ctx, j.SessionID, u)
		}
		switch {
		case errors.Is(err, ErrNoCopywriter):
			status = "skipped"
		case err != nil:
			return err
		default:
			if desc = cleanCopy(desc, 160); desc == "" {
				status = "skipped"
			}
		}
	}
	_, err = s.repo.Update(ctx, j.SessionID, func(t *Tx) error {
		pp := productByID(t.S.Blueprint, in.ProductID)
		if pp == nil || pp.Name != in.Name || pp.CopyStatus != "pending" {
			return errNoop
		}
		pp.CopyStatus, pp.CopyKey = status, shortHash(in.Name)
		if status != "done" {
			return nil
		}
		pp.Description = desc
		t.Touch()
		rev := t.S.Revision + 1
		_, err := t.Enqueue(ctx, "preview", fmt.Sprintf("preview:%s:%d", t.S.ID, rev), previewInput{Revision: rev}, nil, 3)
		return err
	})
	if err == nil {
		s.repo.RecordAction(ctx, j.SessionID, "agent", ToolResult{Tool: "generate_product_copy", Outcome: map[bool]string{true: "ok", false: "noop"}[status == "done"], Summary: map[string]any{"status": status}}, 0)
	}
	return err
}

// jobPreview runs generate_store_preview + validate_store_readiness for one revision.
func (s *Service) jobPreview(ctx context.Context, j *Job) error {
	var in previewInput
	if err := json.Unmarshal(j.Input, &in); err != nil {
		return err
	}
	sess, err := s.repo.GetSystem(ctx, j.SessionID)
	if err != nil {
		return err
	}
	if sess.Revision != in.Revision || sess.Status == "published" || sess.StoreID == "" {
		return errNoop // a newer revision has its own preview job
	}
	became, firstDraft := false, false
	var userID string
	var readyMeta map[string]int64
	_, err = s.repo.Update(ctx, j.SessionID, func(t *Tx) error {
		if t.S.Revision != in.Revision || t.S.Status == "published" {
			return errNoop
		}
		userID, firstDraft = t.S.UserID, t.S.PreviewRevision == 0
		// Synced under the session lock, so an older revision can never overwrite a newer draft.
		ref, err := s.stores.SyncDraft(ctx, t.S.StoreID, t.S.UserID, DraftData(t.S.Blueprint))
		if err != nil {
			return err
		}
		t.S.PreviewRevision = in.Revision
		t.S.Blueprint.Publication.Slug = ref.Slug
		if _, err := t.Emit(ctx, "preview.updated", map[string]any{"revision": in.Revision, "slug": ref.Slug}, ""); err != nil {
			return err
		}
		bp := t.S.Blueprint
		if len(bp.Readiness()) > 0 {
			return nil
		}
		t.S.ReadyRevision = in.Revision
		if t.S.ReadyAt != nil {
			return nil
		}
		now := s.now()
		t.S.ReadyAt, t.S.Status = &now, "ready"
		ok, err := t.Emit(ctx, "store.ready", map[string]any{"revision": in.Revision, "slug": ref.Slug}, "ready")
		if err != nil || !ok {
			return err
		}
		became = true
		readyMeta = map[string]int64{"products": int64(len(bp.PricedProducts())), "ai_calls": int64(t.S.AICalls),
			"ai_cost_micros": t.S.AICostMicros}
		if t.S.FirstMessageAt != nil {
			readyMeta["ms_since_first_message"] = now.Sub(*t.S.FirstMessageAt).Milliseconds()
		}
		readyMeta["ms_since_session_start"] = now.Sub(t.S.CreatedAt).Milliseconds()
		return s.say(ctx, t, readyMessage(bp, s.cfg.Paywall), MessageMeta{Kind: "ready", QuickReplies: readyReplies(bp)})
	})
	if err == nil && firstDraft {
		s.funnel(ctx, userID, j.SessionID, "blueprint_ready", map[string]int64{"revision": int64(in.Revision)})
	}
	if err == nil && became {
		s.funnel(ctx, userID, j.SessionID, "store_ready", readyMeta)
	}
	if err == nil {
		s.repo.RecordAction(ctx, j.SessionID, "agent", ToolResult{Tool: "generate_store_preview", Outcome: "ok", Summary: map[string]any{"revision": in.Revision}}, 0)
		s.repo.RecordAction(ctx, j.SessionID, "agent", ToolResult{Tool: "validate_store_readiness", Outcome: map[bool]string{true: "ok", false: "noop"}[became], Summary: map[string]any{"ready": became}}, 0)
	}
	return err
}

func readyMessage(bp Blueprint, paywall bool) string {
	msg := "¡POP! Tu tienda está lista. " + bp.Template.Reason
	unpriced := len(bp.Products) - len(bp.PricedProducts())
	if unpriced > 0 {
		msg += fmt.Sprintf(" Dejé %d %s sin precio fuera del catálogo hasta que me digás cuánto cuesta%s.",
			unpriced, plural(unpriced, "producto", "productos"), map[bool]string{true: "", false: "n"}[unpriced == 1])
	}
	if paywall {
		return strings.TrimSpace(msg + " Revisala con calma: verla es gratis. Cuando quieras recibir pedidos, la publicás por US$5 al mes.")
	}
	return strings.TrimSpace(msg + " Revisala y publicala cuando quieras.")
}

func readyReplies(bp Blueprint) []QuickReply {
	out := []QuickReply{{Label: "Publicar mi tienda", Value: "__publish__"}}
	current := bp.Theme.Template
	if bp.Template.ByUser {
		current = bp.Template.ID
	}
	for _, id := range storefront.Templates {
		if id != current {
			out = append(out, QuickReply{Label: "Probar " + storefront.TemplateName(id), Value: "Probar " + storefront.TemplateName(id)})
		}
	}
	return out
}

// dispatchJob runs one job. Jobs parse untrusted files (xlsx, PDF, images), so
// a panic marks the job failed instead of killing the API process.
func (s *Service) dispatchJob(ctx context.Context, j *Job) (err error) {
	defer func() {
		if v := recover(); v != nil {
			err = fmt.Errorf("job panic: %v", v)
		}
	}()
	switch j.Kind {
	case "theme":
		return s.jobTheme(ctx, j)
	case "copy":
		return s.jobCopy(ctx, j)
	case "preview":
		return s.jobPreview(ctx, j)
	case "attachment":
		return s.jobAttachment(ctx, j)
	default:
		return fmt.Errorf("unknown job kind %q", j.Kind)
	}
}
