-- KPOP-WOW-001: conversion funnel. Pseudonymous: actor is an HMAC of the user id
-- (never the id, email or name); meta holds only small numbers (durations,
-- counts, bytes, cost). No message text, transcripts or file contents.
CREATE TABLE funnel_events (
    id         bigserial   PRIMARY KEY,
    actor      text        NOT NULL CHECK (actor ~ '^[0-9a-f]{32}$'),
    session_id uuid,
    event      text        NOT NULL CHECK (event IN (
        'signup_completed', 'intake_method_selected', 'audio_recorded', 'transcription_completed',
        'files_uploaded', 'blueprint_ready', 'store_ready', 'store_preview_opened', 'paywall_viewed',
        'demo_activation_completed', 'catalog_shared', 'error')),
    meta       jsonb       NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(meta) = 'object'),
    at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX funnel_events_event_at ON funnel_events (event, at);
CREATE INDEX funnel_events_actor_at ON funnel_events (actor, at);
