package funnel

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Stage is one funnel step with how many distinct actors reached it.
type Stage struct {
	Event  string `json:"event"`
	Actors int64  `json:"actors"`
	Events int64  `json:"events"`
}

// Report summarises the funnel since a time window (for evidence and tuning).
type Report struct {
	Stages []Stage `json:"stages"`
	// Time to store ready (ms) from the first message, over stores that got there.
	ReadyP50Ms int64 `json:"ready_p50_ms"`
	ReadyP95Ms int64 `json:"ready_p95_ms"`
	ReadyN     int64 `json:"ready_n"`
	// Speech-to-text latency (ms) and billed seconds.
	STTP50Ms        int64 `json:"stt_p50_ms"`
	STTP95Ms        int64 `json:"stt_p95_ms"`
	STTBilledSecs   int64 `json:"stt_billed_seconds"`
	STTCostMicros   int64 `json:"stt_cost_micros"`
	AICostMicros    int64 `json:"ai_cost_micros"`
	TranscriptionsN int64 `json:"transcriptions"`
}

// Order is the funnel's natural sequence.
var Order = []string{"signup_completed", "intake_method_selected", "audio_recorded", "transcription_completed",
	"files_uploaded", "blueprint_ready", "store_ready", "store_preview_opened", "paywall_viewed",
	"demo_activation_completed", "catalog_shared"}

// Summarise reads the aggregate (no actor-level data leaves the database).
func Summarise(ctx context.Context, pool *pgxpool.Pool, sinceHours int) (Report, error) {
	var rep Report
	rows, err := pool.Query(ctx, `SELECT event, count(DISTINCT actor), count(*) FROM funnel_events
		WHERE at > now() - make_interval(hours => $1) GROUP BY event`, sinceHours)
	if err != nil {
		return rep, fmt.Errorf("funnel stages: %w", err)
	}
	got := map[string]Stage{}
	for rows.Next() {
		var s Stage
		if err := rows.Scan(&s.Event, &s.Actors, &s.Events); err != nil {
			rows.Close()
			return rep, err
		}
		got[s.Event] = s
	}
	rows.Close()
	for _, e := range Order {
		s := got[e]
		s.Event = e
		rep.Stages = append(rep.Stages, s)
	}
	q := func(sql string, dst ...any) error {
		return pool.QueryRow(ctx, sql, sinceHours).Scan(dst...)
	}
	if err := q(`SELECT coalesce(percentile_disc(0.5) WITHIN GROUP (ORDER BY (meta->>'ms_since_first_message')::bigint), 0),
		coalesce(percentile_disc(0.95) WITHIN GROUP (ORDER BY (meta->>'ms_since_first_message')::bigint), 0), count(*),
		coalesce(sum((meta->>'ai_cost_micros')::bigint), 0)
		FROM funnel_events WHERE event = 'store_ready' AND meta ? 'ms_since_first_message'
		AND at > now() - make_interval(hours => $1)`, &rep.ReadyP50Ms, &rep.ReadyP95Ms, &rep.ReadyN, &rep.AICostMicros); err != nil {
		return rep, fmt.Errorf("funnel ready: %w", err)
	}
	if err := q(`SELECT coalesce(percentile_disc(0.5) WITHIN GROUP (ORDER BY (meta->>'latency_ms')::bigint), 0),
		coalesce(percentile_disc(0.95) WITHIN GROUP (ORDER BY (meta->>'latency_ms')::bigint), 0),
		coalesce(sum((meta->>'billed_seconds')::bigint), 0), coalesce(sum((meta->>'cost_micros')::bigint), 0), count(*)
		FROM funnel_events WHERE event = 'transcription_completed' AND at > now() - make_interval(hours => $1)`,
		&rep.STTP50Ms, &rep.STTP95Ms, &rep.STTBilledSecs, &rep.STTCostMicros, &rep.TranscriptionsN); err != nil {
		return rep, fmt.Errorf("funnel stt: %w", err)
	}
	return rep, nil
}
