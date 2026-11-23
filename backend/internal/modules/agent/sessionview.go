package agent

import (
	"context"
	"time"

	"github.com/kiuvy-universe/kiupop/backend/internal/platform/storefront"
)

// SessionView is the API representation of a session (resumable after reload).
type SessionView struct {
	ID          string         `json:"id"`
	Status      string         `json:"status"`
	Revision    int            `json:"revision"`
	Store       *StoreBrief    `json:"store"`
	Messages    []Message      `json:"messages"`
	Pending     *Question      `json:"pending_question"`
	Progress    Progress       `json:"progress"`
	Readiness   ReadinessView  `json:"readiness"`
	Summary     BlueprintBrief `json:"summary"`
	AI          AIView         `json:"ai"`
	LastEventID int64          `json:"last_event_id"`
	Timing      Timing         `json:"timing"`
	Publication *PublishResult `json:"publication"`
	Attachments []Attachment   `json:"attachments"`
	Limits      Limits         `json:"limits"`
	Paywall     PlanView       `json:"paywall"`
}

// Limits tells the client what it may upload (the server enforces them anyway).
type Limits struct {
	MaxAttachments      int   `json:"max_attachments"`
	MaxAttachmentsBytes int64 `json:"max_attachments_bytes"`
	Enabled             bool  `json:"attachments_enabled"`
}

// StoreBrief identifies the backing store.
type StoreBrief struct {
	Slug string `json:"slug"`
}

// ReadinessView says whether the store can be published.
type ReadinessView struct {
	Ready   bool      `json:"ready"`
	Missing []Missing `json:"missing"`
}

// BlueprintBrief is a compact, public summary of what Kiu understood.
type BlueprintBrief struct {
	BusinessName   string   `json:"business_name"`
	Category       string   `json:"category"`
	Template       string   `json:"template"`
	TemplateReason string   `json:"template_reason"`
	Products       int      `json:"products"`
	PricedProducts int      `json:"priced_products"`
	DeliveryModes  []string `json:"delivery_modes"`
	Zones          []string `json:"zones"`
	HasWhatsApp    bool     `json:"has_whatsapp"`
	QuestionsAsked int      `json:"questions_asked"`
	CheckoutMode   string   `json:"checkout_mode"`
	RealPayments   bool     `json:"real_payments_enabled"`
}

// AIView reports which brain is active and what it cost.
type AIView struct {
	Mode       string `json:"mode"` // claude | local
	Calls      int    `json:"calls"`
	CostMicros int64  `json:"cost_micros"`
}

// Timing reports measured durations (ms) for the 5-minute goal.
type Timing struct {
	StartedAt             time.Time `json:"started_at"`
	ToReadyMs             *int64    `json:"to_ready_ms"`
	ToPublishedMs         *int64    `json:"to_published_ms"`
	FirstMessageToReadyMs *int64    `json:"first_message_to_ready_ms"`
}

func ms(a time.Time, b *time.Time) *int64 {
	if b == nil {
		return nil
	}
	v := b.Sub(a).Milliseconds()
	return &v
}

// View loads the full session view for its owner.
func (s *Service) View(ctx context.Context, userID, sessionID string) (SessionView, error) {
	sess, err := s.repo.Get(ctx, sessionID, userID)
	if err != nil {
		return SessionView{}, err
	}
	msgs, err := s.repo.Messages(ctx, sessionID)
	if err != nil {
		return SessionView{}, err
	}
	jobs, err := s.repo.JobStates(ctx, sessionID)
	if err != nil {
		return SessionView{}, err
	}
	atts, err := s.repo.Attachments(ctx, sessionID)
	if err != nil {
		return SessionView{}, err
	}
	last, err := s.repo.LastEventID(ctx, sessionID)
	if err != nil {
		return SessionView{}, err
	}
	bp := sess.Blueprint
	missing := bp.Readiness()
	if missing == nil {
		missing = []Missing{}
	}
	mode := s.brain.Mode()
	if !s.withinBudget(ctx, sess) {
		mode = "local"
	}
	v := SessionView{
		ID: sess.ID, Status: sess.Status, Revision: sess.Revision, Messages: msgs, Pending: bp.Pending,
		Progress:  ComputeProgress(sess, jobs, s.aiCopy()),
		Readiness: ReadinessView{Ready: len(missing) == 0, Missing: missing},
		Summary: BlueprintBrief{
			BusinessName: bp.Business.Name, Category: bp.Business.Category, Template: bp.Theme.Template,
			TemplateReason: bp.Template.Reason, Products: len(bp.Products), PricedProducts: len(bp.PricedProducts()),
			DeliveryModes: nonNil(bp.Delivery.Modes), Zones: nonNil(bp.Delivery.Zones), HasWhatsApp: bp.Contact.WhatsApp != "",
			QuestionsAsked: sess.QuestionsAsked, CheckoutMode: bp.Payment.Checkout, RealPayments: false,
		},
		AI:          AIView{Mode: mode, Calls: sess.AICalls, CostMicros: sess.AICostMicros},
		LastEventID: last,
		Attachments: atts,
		Limits:      Limits{MaxAttachments: s.cfg.maxFiles(), MaxAttachmentsBytes: s.cfg.maxFilesBytes(), Enabled: s.files != nil},
		Timing:      Timing{StartedAt: sess.CreatedAt, ToReadyMs: ms(sess.CreatedAt, sess.ReadyAt), ToPublishedMs: ms(sess.CreatedAt, sess.PublishedAt)},
	}
	if sess.FirstMessageAt != nil {
		v.Timing.FirstMessageToReadyMs = ms(*sess.FirstMessageAt, sess.ReadyAt)
	}
	if slug := bp.Publication.Slug; slug != "" {
		v.Store = &StoreBrief{Slug: slug}
	}
	if sess.Status == "published" {
		r := s.publishResult(bp.Publication.Slug, bp.Publication.Version)
		v.Publication = &r
	}
	if v.Paywall, err = s.planView(ctx, sess.StoreID, userID); err != nil {
		return SessionView{}, err
	}
	return v, nil
}

// Preview renders the owner's draft with the same view the public store uses.
func (s *Service) Preview(ctx context.Context, userID, sessionID string) (storefront.View, error) {
	sess, err := s.repo.Get(ctx, sessionID, userID)
	if err != nil {
		return storefront.View{}, err
	}
	bp := sess.Blueprint
	if !storefront.ValidTemplate(bp.Theme.Template) {
		_, bp.Theme = SuggestTheme(bp, false)
	}
	v := PreviewView(bp, bp.Publication.Slug, imagePath, s.shareURL(bp.Publication.Slug))
	if sess.Status == "published" {
		v.Store.Status = "published"
	}
	return v, nil
}
