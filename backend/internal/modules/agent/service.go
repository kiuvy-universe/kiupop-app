package agent

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5/pgconn"

	"github.com/kiuvy-universe/kiupop/backend/internal/platform/storefront"
)

// Greeting is Kiu's first message. It only promises inputs that work today.
const Greeting = "¡Hola! Soy Kiu. Contame qué hace tu negocio y yo me encargo de crear tu tienda. Escribime con tus palabras —qué vendés, cómo se llama y cómo te gustaría que se vea— y, si querés, compartime fotos de tus productos o tu catálogo."

// DiscoveryGreeting replaces Greeting when discovery is on: Kiu listens first.
const DiscoveryGreeting = "¡Hola! Soy Kiu. Antes de crear nada quiero entender tu negocio, para recomendarte lo que de verdad te ayude a vender. Contame con tus palabras qué vendés y cómo se llama tu negocio."

// buildStartAck is Kiu's answer when the merchant accepts the plan (or skips it).
const buildStartAck = "¡Manos a la obra! Ya empecé a armar tu tienda con lo que me contaste."

var (
	// ErrSessionClosed means the session was already published.
	ErrSessionClosed = errors.New("session closed")
	// ErrConfirmationRequired means publish was called without explicit confirmation.
	ErrConfirmationRequired = errors.New("confirmation required")
	// ErrInvalidMessage means the text is empty or too long.
	ErrInvalidMessage = errors.New("invalid message")
	// ErrPlanRequired means the paywall is on and the store has no active plan.
	ErrPlanRequired = errors.New("plan required")
	// ErrPaymentsUnavailable means no (test) payment method is enabled here.
	ErrPaymentsUnavailable = errors.New("payments unavailable")
)

// NotReadyError lists what blocks publication.
type NotReadyError struct{ Missing []Missing }

func (e *NotReadyError) Error() string { return "store not ready" }

// MaxMessageRunes bounds a merchant message.
const MaxMessageRunes = 1000

// StoreRef identifies the store row backing a session.
type StoreRef = storefront.StoreRef

// Publication is the result of publishing a snapshot.
type Publication = storefront.Publication

// StoreDrafts is the port to the storefront module (modules never import each other).
type StoreDrafts interface {
	CreateDraft(ctx context.Context, ownerUserID, name string) (StoreRef, error)
	SyncDraft(ctx context.Context, storeID, ownerUserID string, d storefront.DraftData) (StoreRef, error)
	Publish(ctx context.Context, storeID, ownerUserID string, s storefront.Snapshot) (Publication, error)
	// Paywall (quiz funnel): a store publishes only with an active plan.
	ActivateTestPlan(ctx context.Context, storeID, ownerUserID string, now time.Time) (storefront.Plan, error)
	ActivePlan(ctx context.Context, storeID, ownerUserID string, now time.Time) (storefront.Plan, bool, error)
}

// Config tunes the service.
type Config struct {
	TestCheckout      bool          // offer the mock (test-mode) checkout
	ShareBase         string        // origin serving /p/{slug} (Open Graph pages)
	AIBudgetMicros    int64         // per-session AI cost cap (micro-USD)
	UserDailyMicros   int64         // per-user daily AI cost cap across sessions (0 = off)
	GlobalDailyMicros int64         // whole-service daily AI cost cap (0 = off)
	AICallLimit       int           // per-session AI call cap
	TurnTimeout       time.Duration // max wait for the model in a turn
	// Discovery asks filter questions and proposes a plan before building
	// (KIU_DISCOVERY_ENABLED). Off = the original flow, unchanged.
	Discovery bool
	// Paywall gates publication behind an active US$5/month plan
	// (PAYWALL_ENABLED). Off = publishing is free, as before.
	Paywall bool
	// MaxFiles / MaxFilesBytes bound attachments per session (0 = defaults:
	// MaxAttachments files, MaxAttachmentsBytes in total).
	MaxFiles      int
	MaxFilesBytes int64
	// Funnel records pseudonymous conversion events (nil = off).
	Funnel FunnelRecorder
}

// FunnelRecorder receives conversion milestones. Implementations must not
// store message text or file contents: only the event and small numbers.
type FunnelRecorder interface {
	Record(ctx context.Context, userID, sessionID, event string, meta map[string]int64)
}

func (c Config) maxFiles() int {
	if c.MaxFiles > 0 {
		return c.MaxFiles
	}
	return MaxAttachments
}

func (c Config) maxFilesBytes() int64 {
	if c.MaxFilesBytes > 0 {
		return c.MaxFilesBytes
	}
	return MaxAttachmentsBytes
}

// funnel records a milestone when analytics are on.
func (s *Service) funnel(ctx context.Context, userID, sessionID, event string, meta map[string]int64) {
	if s.cfg.Funnel != nil {
		s.cfg.Funnel.Record(ctx, userID, sessionID, event, meta)
	}
}

// Service orchestrates Kiu.
type Service struct {
	repo   *Repo
	brain  Brain
	copy   Copywriter
	reader Reader
	files  Files
	stores StoreDrafts
	bus    *Bus
	log    *slog.Logger
	cfg    Config
	newID  func() string
	now    func() time.Time
}

// NewService builds the service.
func NewService(repo *Repo, brain Brain, copy Copywriter, stores StoreDrafts, bus *Bus, log *slog.Logger, cfg Config, newID func() string) *Service {
	if cfg.TurnTimeout == 0 {
		cfg.TurnTimeout = 12 * time.Second
	}
	if cfg.AICallLimit == 0 {
		cfg.AICallLimit = 40
	}
	return &Service{repo: repo, brain: brain, copy: copy, reader: NoReader{}, stores: stores, bus: bus, log: log, cfg: cfg, newID: newID, now: time.Now}
}

// WithAttachments enables files shared with Kiu (reader = AI or NoReader).
func (s *Service) WithAttachments(files Files, reader Reader) *Service {
	s.files, s.reader = files, reader
	return s
}

func (s *Service) aiCopy() bool { _, off := s.copy.(NoCopy); return !off }

// withinBudget gates every model call: per session, per user per day (across
// sessions, so new sessions don't reset it) and globally per day. Checks are
// best-effort (concurrent calls may overshoot by one call each), which bounds
// the overshoot to cents. Over budget, Kiu keeps working with local rules.
func (s *Service) withinBudget(ctx context.Context, sess Session) bool {
	if sess.AICostMicros >= s.cfg.AIBudgetMicros || sess.AICalls >= s.cfg.AICallLimit {
		return false
	}
	if s.cfg.UserDailyMicros <= 0 && s.cfg.GlobalDailyMicros <= 0 {
		return true
	}
	user, global, err := s.repo.SpendToday(ctx, sess.UserID)
	if err != nil {
		return false // fail closed on spend
	}
	return (s.cfg.UserDailyMicros <= 0 || user < s.cfg.UserDailyMicros) &&
		(s.cfg.GlobalDailyMicros <= 0 || global < s.cfg.GlobalDailyMicros)
}

// Start returns the user's live session, creating it (with Kiu's greeting) if needed.
func (s *Service) Start(ctx context.Context, userID string) (SessionView, error) {
	sess, created, err := s.repo.LiveOrCreate(ctx, userID)
	if err != nil {
		return SessionView{}, err
	}
	if created {
		if _, err := s.repo.Update(ctx, sess.ID, func(t *Tx) error {
			greeting := Greeting
			if s.cfg.Discovery {
				greeting = DiscoveryGreeting
				t.S.Blueprint.Discovery = newDiscovery()
				t.Touch()
			}
			m, err := t.AddMessage(ctx, "kiu", greeting, MessageMeta{Kind: "greeting", BrainMode: s.brain.Mode()}, "")
			if err != nil {
				return err
			}
			_, err = t.Emit(ctx, "message.created", m, "")
			return err
		}); err != nil {
			return SessionView{}, err
		}
	}
	return s.View(ctx, userID, sess.ID)
}

// MessageInput is a merchant message.
type MessageInput struct {
	Text            string `json:"text"`
	ClientMessageID string `json:"client_message_id"`
}

// PostMessage runs one conversational turn: understand → typed tools → plan →
// enqueue parallel jobs. Retries with the same client_message_id are no-ops.
func (s *Service) PostMessage(ctx context.Context, userID, sessionID string, in MessageInput) (SessionView, error) {
	text := strings.TrimSpace(in.Text)
	if n := utf8.RuneCountInString(text); n < 1 || n > MaxMessageRunes || (in.ClientMessageID != "" && (len(in.ClientMessageID) < 8 || len(in.ClientMessageID) > 64)) {
		return SessionView{}, ErrInvalidMessage
	}
	sess, err := s.repo.Get(ctx, sessionID, userID)
	if err != nil {
		return SessionView{}, err
	}
	if sess.Status == "published" {
		return SessionView{}, ErrSessionClosed
	}
	if in.ClientMessageID != "" {
		if dup, err := s.repo.HasClientMessage(ctx, sessionID, in.ClientMessageID); err != nil {
			return SessionView{}, err
		} else if dup {
			return s.View(ctx, userID, sessionID)
		}
	}

	// 1. Understand (outside any lock; the model may take seconds).
	turn := TurnInput{SessionID: sessionID, Blueprint: sess.Blueprint, Pending: sess.Blueprint.Pending, Text: text,
		First: sess.FirstMessageAt == nil, Missing: missingFields(sess.Blueprint)}
	brain := s.brain
	if !s.withinBudget(ctx, sess) {
		brain = LocalBrain{}
	}
	tctx, cancel := context.WithTimeout(ctx, s.cfg.TurnTimeout)
	ex, usages, err := brain.Understand(tctx, turn)
	cancel()
	for _, u := range usages {
		s.repo.RecordUsage(ctx, sessionID, u)
	}
	mode := brain.Mode()
	if err != nil {
		s.log.WarnContext(ctx, "brain failed, using local extractor", "session_id", sessionID, "err", err)
		ex, _, _ = LocalBrain{}.Understand(ctx, turn)
		mode = "local"
	}

	// 3. Apply tools, plan the next question, enqueue only the affected work.
	var results []ToolResult
	start := s.now()
	_, err = s.repo.Update(ctx, sessionID, func(t *Tx) error {
		if t.S.Status == "published" {
			return ErrSessionClosed
		}
		um, err := t.AddMessage(ctx, "user", text, MessageMeta{}, in.ClientMessageID)
		if err != nil {
			return err
		}
		if _, err := t.Emit(ctx, "message.created", um, ""); err != nil {
			return err
		}
		first := t.S.FirstMessageAt == nil
		if first {
			now := s.now()
			t.S.FirstMessageAt = &now
		}
		bp := &t.S.Blueprint
		if first && s.cfg.Discovery && bp.Discovery == nil && t.S.StoreID == "" {
			bp.Discovery = newDiscovery() // session created before the flag was on
		}
		pending := ""
		if bp.Pending != nil {
			pending = bp.Pending.Field
		}
		ch := Apply(bp, ex, text, pending, s.cfg.TestCheckout, s.newID)
		results = append(results, ch.Results...)
		t.Touch()

		// Discovery: understand the need and recommend before building anything.
		buildStarts := false
		if bp.Discovery.Active() {
			if stepDiscovery(bp, text, pending) == discoveryContinue {
				ack := discoveryAck(*bp, first)
				if ex.SkipPending && pending != "" {
					ack = "¡Sin problema! Seguimos."
				}
				if err := s.say(ctx, t, ack, MessageMeta{Kind: "ack", BrainMode: mode}); err != nil {
					return err
				}
				bp.Pending = nil
				return s.discover(ctx, t, mode)
			}
			// Accepted (or "ya sé lo que quiero"): build everything gathered so far.
			buildStarts = true
			ch = rebuildAll(bp, ch)
			results = append(results, ToolResult{Tool: "accept_discovery_plan", Outcome: "ok", Summary: map[string]any{"status": bp.Discovery.Status}})
		}

		if t.S.StoreID == "" {
			// Created under the session lock: concurrent first messages make one draft.
			ref, err := s.stores.CreateDraft(ctx, userID, "")
			if err != nil {
				return fmt.Errorf("create draft: %w", err)
			}
			t.S.StoreID = ref.ID
			results = append(results, ToolResult{Tool: "create_store_draft", Outcome: "ok", Summary: map[string]any{"slug": ref.Slug}})
		}

		themeJob, err := s.enqueueAffected(ctx, t, ch)
		if err != nil {
			return err
		}

		ack := Ack(*bp, ch, first, ex.Reply)
		meta := MessageMeta{Kind: "ack", BrainMode: mode}
		if ex.SkipPending && pending != "" {
			ack = "¡Sin problema! Lo dejo así por ahora."
		}
		if buildStarts {
			ack = buildStartAck
		}
		if err := s.say(ctx, t, ack, meta); err != nil {
			return err
		}
		bp.Pending = nil // the merchant's turn consumes the question; the planner decides again
		return s.advance(ctx, t, ex.NextQuestion, mode, themeJob)
	})
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" { // concurrent retry with the same client id
		return s.View(ctx, userID, sessionID)
	}
	if err != nil {
		return SessionView{}, err
	}
	for _, r := range results {
		if r.Outcome != "noop" {
			s.repo.RecordAction(ctx, sessionID, "agent", r, s.now().Sub(start))
		}
	}
	s.bus.WakeWorkers()
	s.emitProgress(ctx, sessionID)
	return s.View(ctx, userID, sessionID)
}

// enqueueAffected queues only the work a change affects (theme, copy per new product).
func (s *Service) enqueueAffected(ctx context.Context, t *Tx, ch Changes) (string, error) {
	bp := &t.S.Blueprint
	if bp.Discovery.Active() {
		return "", nil // nothing is built before the merchant accepts the plan (rebuildAll catches up)
	}
	var themeJob string
	var err error
	if ch.Branding || ch.Template || ch.Profile || ch.Images || !storefront.ValidTemplate(bp.Theme.Template) {
		if themeJob, err = t.Enqueue(ctx, "theme", fmt.Sprintf("theme:%s:%s:%d", t.S.ID, brandingKey(*bp), t.S.Revision+1), nil, nil, 3); err != nil {
			return "", err
		}
	}
	for _, pid := range ch.NewProducts {
		if p := productByID(*bp, pid); p != nil && s.aiCopy() {
			if _, err := t.Enqueue(ctx, "copy", fmt.Sprintf("copy:%s:%s:%s:%d", t.S.ID, pid, shortHash(p.Name), t.S.Revision+1), copyInput{ProductID: pid, Name: p.Name}, nil, 2); err != nil {
				return "", err
			}
		} else if p != nil {
			p.CopyStatus = "skipped"
		}
	}
	return themeJob, nil
}

// advance asks the next question (if any), or announces the build, then queues
// the preview for the new revision. Shared by chat turns and attachment jobs.
func (s *Service) advance(ctx context.Context, t *Tx, proposed *ProposedQuestion, mode, themeJob string) error {
	bp := &t.S.Blueprint
	t.Touch()
	if bp.Discovery.Active() {
		return s.discover(ctx, t, mode) // e.g. photos shared during the diagnosis: keep diagnosing
	}
	if bp.Pending != nil && bp.Known(bp.Pending.Field) {
		bp.Pending = nil // answered by this change (e.g. prices from a CSV)
	}
	if bp.Pending == nil {
		if field := NextField(*bp, t.S.QuestionsAsked); field != "" {
			q := BuildQuestion(*bp, field, t.S.ID, proposed)
			bp.Pending = &q
			bp.Asked = append(bp.Asked, field)
			t.S.QuestionsAsked++
			if err := s.say(ctx, t, q.Text, MessageMeta{Kind: "question", Question: &q, QuickReplies: q.QuickReplies, BrainMode: mode}); err != nil {
				return err
			}
		} else if missing := bp.Readiness(); len(missing) > 0 && !onlyTheme(missing) {
			// Question budget spent but publishing is still blocked: ask ONE
			// concrete question about the first blocker, with new help each retry.
			field := firstBlocker(*bp)
			q := BlockerQuestion(*bp, field, count(bp.Asked, field))
			bp.Pending = &q
			bp.Asked = append(bp.Asked, field)
			if err := s.say(ctx, t, q.Text, MessageMeta{Kind: "question", Question: &q, QuickReplies: q.QuickReplies, BrainMode: mode}); err != nil {
				return err
			}
		} else if t.S.ReadyAt != nil {
			// Already POPped: keep offering publish and the other styles.
			if err := s.say(ctx, t, "Tu vista previa se actualiza en un momento.", MessageMeta{Kind: "notice", QuickReplies: readyReplies(*bp)}); err != nil {
				return err
			}
		} else if t.S.Status == "collecting" {
			t.S.Status = "building"
			if err := s.say(ctx, t, "¡Ya tengo todo lo que necesito! Estoy terminando tu tienda…", MessageMeta{Kind: "building"}); err != nil {
				return err
			}
		}
	}
	var deps []string
	if themeJob != "" {
		deps = []string{themeJob}
	}
	rev := t.S.Revision + 1
	_, err := t.Enqueue(ctx, "preview", fmt.Sprintf("preview:%s:%d", t.S.ID, rev), previewInput{Revision: rev}, deps, 3)
	return err
}

func onlyTheme(m []Missing) bool { return len(m) == 1 && m[0].Field == "theme" }

func (s *Service) say(ctx context.Context, t *Tx, text string, meta MessageMeta) error {
	m, err := t.AddMessage(ctx, "kiu", text, meta, "")
	if err != nil {
		return err
	}
	_, err = t.Emit(ctx, "message.created", m, "")
	return err
}

func productByID(bp Blueprint, id string) *DraftProduct {
	for i := range bp.Products {
		if bp.Products[i].ID == id {
			return &bp.Products[i]
		}
	}
	return nil
}

type copyInput struct {
	ProductID string `json:"product_id"`
	Name      string `json:"name"`
}

type previewInput struct {
	Revision int `json:"revision"`
}

func (s *Service) emitProgress(ctx context.Context, sessionID string) {
	sess, err := s.repo.GetSystem(ctx, sessionID)
	if err != nil {
		return
	}
	jobs, err := s.repo.JobStates(ctx, sessionID)
	if err != nil {
		return
	}
	_, _ = s.repo.Emit(ctx, sessionID, "progress", ComputeProgress(sess, jobs, s.aiCopy()), "")
	s.bus.Notify(sessionID)
}

// PublishResult is returned after publication.
type PublishResult struct {
	Slug       string `json:"slug"`
	Version    int    `json:"version"`
	PublicPath string `json:"public_path"`
	ShareURL   string `json:"share_url"`
}

// Publish publishes the validated snapshot. It needs explicit confirmation and
// is idempotent: publishing an already-published session returns the same result.
func (s *Service) Publish(ctx context.Context, userID, sessionID string, confirm bool) (PublishResult, error) {
	if !confirm {
		return PublishResult{}, ErrConfirmationRequired
	}
	if _, err := s.repo.Get(ctx, sessionID, userID); err != nil {
		return PublishResult{}, err // ownership check before taking the lock
	}
	start := s.now()
	var res PublishResult
	_, err := s.repo.Update(ctx, sessionID, func(t *Tx) error {
		if t.S.Status == "published" { // concurrent or retried publish: same answer
			res = s.publishResult(t.S.Blueprint.Publication.Slug, t.S.Blueprint.Publication.Version)
			return nil
		}
		if missing := t.S.Blueprint.Readiness(); len(missing) > 0 || t.S.StoreID == "" {
			return &NotReadyError{Missing: missing}
		}
		if s.cfg.Paywall { // server-enforced: the client cannot skip the paywall
			if _, ok, err := s.stores.ActivePlan(ctx, t.S.StoreID, userID, s.now()); err != nil {
				return err
			} else if !ok {
				return ErrPlanRequired
			}
		}
		// Snapshot of the locked, current blueprint: no edit can slip in between.
		pub, err := s.stores.Publish(ctx, t.S.StoreID, userID, Snapshot(t.S.Blueprint))
		if err != nil {
			return err
		}
		res = s.publishResult(pub.Slug, pub.Version)
		now := s.now()
		t.S.Status = "published"
		t.S.PublishedAt = &now
		t.S.Blueprint.Publication = PublicationState{Status: "published", Version: pub.Version, Slug: pub.Slug}
		t.S.Blueprint.Pending = nil
		if ok, err := t.Emit(ctx, "store.published", res, "published"); err != nil || !ok {
			return err
		}
		if err := s.say(ctx, t, "¡Tu tienda ya está publicada! Compartí el enlace por WhatsApp, Facebook o donde quieras.", MessageMeta{Kind: "published"}); err != nil {
			return err
		}
		if kit := KitText(t.S.Blueprint, res.ShareURL); kit != "" {
			return s.say(ctx, t, kit, MessageMeta{Kind: "kit"})
		}
		return nil
	})
	outcome := "ok"
	if err != nil {
		outcome = "error"
	}
	s.repo.RecordAction(ctx, sessionID, "user", ToolResult{Tool: "publish_store", Outcome: outcome, Summary: map[string]any{"version": res.Version}}, s.now().Sub(start))
	if err != nil {
		return PublishResult{}, err
	}
	_ = s.repo.CancelSessionJobs(ctx, sessionID)
	s.emitProgress(ctx, sessionID)
	return res, nil
}

// PlanView is the paywall state the client shows before publishing.
type PlanView struct {
	Required   bool             `json:"required"`
	Active     bool             `json:"active"`
	PriceMinor int64            `json:"price_minor"`
	Currency   string           `json:"currency"`
	Interval   string           `json:"interval"`
	Mode       string           `json:"mode"` // test: no money moves
	Plan       *storefront.Plan `json:"plan"`
	Notice     string           `json:"notice"`
}

const planNotice = "Modo prueba: no se cobra dinero real."

func (s *Service) planView(ctx context.Context, storeID, userID string) (PlanView, error) {
	v := PlanView{Required: s.cfg.Paywall, PriceMinor: storefront.PlanPriceMinor, Currency: storefront.PlanCurrency,
		Interval: "month", Mode: "test", Notice: planNotice}
	if storeID == "" {
		return v, nil
	}
	p, ok, err := s.stores.ActivePlan(ctx, storeID, userID, s.now())
	if err != nil {
		return PlanView{}, err
	}
	if ok {
		v.Active, v.Plan = true, &p
	}
	return v, nil
}

// ActivatePlan runs the TEST payment for the paywall and activates the store's
// plan. Only available where test checkout is allowed (local/dev); idempotent.
func (s *Service) ActivatePlan(ctx context.Context, userID, sessionID string, confirm bool) (PlanView, error) {
	if !confirm {
		return PlanView{}, ErrConfirmationRequired
	}
	if !s.cfg.TestCheckout {
		return PlanView{}, ErrPaymentsUnavailable
	}
	sess, err := s.repo.Get(ctx, sessionID, userID)
	if err != nil {
		return PlanView{}, err
	}
	if sess.StoreID == "" {
		return PlanView{}, &NotReadyError{Missing: sess.Blueprint.Readiness()}
	}
	start := s.now()
	_, err = s.stores.ActivateTestPlan(ctx, sess.StoreID, userID, start)
	outcome := "ok"
	if err != nil {
		outcome = "error"
	}
	s.repo.RecordAction(ctx, sessionID, "user", ToolResult{Tool: "activate_plan", Outcome: outcome,
		Summary: map[string]any{"plan": storefront.PlanMonthly, "mode": "test"}}, s.now().Sub(start))
	if err != nil {
		return PlanView{}, err
	}
	s.funnel(ctx, userID, sessionID, "demo_activation_completed", nil)
	return s.planView(ctx, sess.StoreID, userID)
}

func (s *Service) publishResult(slug string, version int) PublishResult {
	return PublishResult{Slug: slug, Version: version, PublicPath: "/s/" + slug, ShareURL: s.shareURL(slug)}
}

func (s *Service) shareURL(slug string) string {
	if slug == "" {
		return ""
	}
	return strings.TrimRight(s.cfg.ShareBase, "/") + "/p/" + slug
}
