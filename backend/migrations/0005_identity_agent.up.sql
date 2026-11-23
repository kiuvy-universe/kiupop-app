-- KPOP-AGENT-001: KiuPop identity, draft/published stores, Kiu agent state,
-- durable jobs, progress events, AI usage and test-mode payments.

-- Identity: users come from a KiuPop-dedicated provider (Firebase Auth / emulator).
-- The backend derives users from verified ID tokens only, never from client ids.
CREATE TABLE users (
    id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_uid          text        NOT NULL UNIQUE CHECK (char_length(auth_uid) BETWEEN 1 AND 128),
    email             text        CHECK (email IS NULL OR char_length(email) <= 320),
    email_verified    boolean     NOT NULL DEFAULT false,
    display_name      text        CHECK (display_name IS NULL OR char_length(display_name) <= 120),
    sign_in_provider  text        NOT NULL CHECK (char_length(sign_in_provider) BETWEEN 1 AND 40),
    created_at        timestamptz NOT NULL DEFAULT now(),
    last_seen_at      timestamptz NOT NULL DEFAULT now()
);

-- Stores: owner, lifecycle and the parametrised storefront (template + validated tokens).
-- Existing POC stores stay published and ownerless until claimed with their kp_ token.
ALTER TABLE stores
    ADD COLUMN owner_user_id     uuid        REFERENCES users (id) ON DELETE SET NULL,
    ADD COLUMN status            text        NOT NULL DEFAULT 'published' CHECK (status IN ('draft', 'published')),
    ADD COLUMN template          text        NOT NULL DEFAULT 'bubblegum_pink'
                                             CHECK (template IN ('bubblegum_pink', 'mint_fresh', 'peach_pop')),
    ADD COLUMN theme             jsonb       NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN profile           jsonb       NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN published_version integer     NOT NULL DEFAULT 0 CHECK (published_version >= 0),
    ADD COLUMN published_at      timestamptz;
ALTER TABLE stores ALTER COLUMN whatsapp_e164 DROP NOT NULL;
ALTER TABLE stores ADD CONSTRAINT stores_published_needs_whatsapp
    CHECK (status = 'draft' OR whatsapp_e164 IS NOT NULL);
CREATE INDEX stores_owner_idx ON stores (owner_user_id) WHERE owner_user_id IS NOT NULL;

-- Each publication is an immutable, validated snapshot.
CREATE TABLE store_publications (
    id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id       uuid        NOT NULL REFERENCES stores (id) ON DELETE CASCADE,
    version        integer     NOT NULL CHECK (version > 0),
    snapshot_hash  bytea       NOT NULL CHECK (octet_length(snapshot_hash) = 32),
    snapshot       jsonb       NOT NULL,
    created_at     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (store_id, version)
);

-- Kiu agent sessions: one structured, versioned StoreBlueprint per session.
CREATE TABLE agent_sessions (
    id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    store_id          uuid        REFERENCES stores (id) ON DELETE SET NULL,
    status            text        NOT NULL DEFAULT 'collecting'
                                  CHECK (status IN ('collecting', 'building', 'ready', 'published', 'abandoned')),
    blueprint         jsonb       NOT NULL,
    revision          integer     NOT NULL DEFAULT 1 CHECK (revision > 0),
    preview_revision  integer     NOT NULL DEFAULT 0,
    ready_revision    integer     NOT NULL DEFAULT 0,
    questions_asked   integer     NOT NULL DEFAULT 0 CHECK (questions_asked >= 0),
    ai_calls          integer     NOT NULL DEFAULT 0 CHECK (ai_calls >= 0),
    ai_cost_micros    bigint      NOT NULL DEFAULT 0 CHECK (ai_cost_micros >= 0),
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),
    first_message_at  timestamptz,
    ready_at          timestamptz,
    published_at      timestamptz
);
-- At most one live session per user: reloads resume it instead of starting over.
CREATE UNIQUE INDEX agent_sessions_one_live_per_user ON agent_sessions (user_id)
    WHERE status IN ('collecting', 'building', 'ready');

CREATE TABLE agent_messages (
    id                 bigserial   PRIMARY KEY,
    session_id         uuid        NOT NULL REFERENCES agent_sessions (id) ON DELETE CASCADE,
    role               text        NOT NULL CHECK (role IN ('user', 'kiu')),
    body               text        NOT NULL CHECK (char_length(body) BETWEEN 1 AND 2000),
    meta               jsonb       NOT NULL DEFAULT '{}'::jsonb,
    client_message_id  text        CHECK (client_message_id IS NULL OR char_length(client_message_id) BETWEEN 8 AND 64),
    created_at         timestamptz NOT NULL DEFAULT now(),
    UNIQUE (session_id, client_message_id)
);
CREATE INDEX agent_messages_session_idx ON agent_messages (session_id, id);

-- Durable job queue (PostgreSQL, SKIP LOCKED). Leases make crashed work recoverable.
CREATE TABLE agent_jobs (
    id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id       uuid        NOT NULL REFERENCES agent_sessions (id) ON DELETE CASCADE,
    kind             text        NOT NULL CHECK (char_length(kind) BETWEEN 1 AND 40),
    idempotency_key  text        NOT NULL UNIQUE CHECK (char_length(idempotency_key) BETWEEN 1 AND 200),
    status           text        NOT NULL DEFAULT 'queued'
                                 CHECK (status IN ('queued', 'running', 'succeeded', 'failed', 'cancelled')),
    input            jsonb       NOT NULL DEFAULT '{}'::jsonb,
    result           jsonb,
    depends_on       uuid[]      NOT NULL DEFAULT '{}',
    attempts         integer     NOT NULL DEFAULT 0,
    max_attempts     integer     NOT NULL DEFAULT 3 CHECK (max_attempts BETWEEN 1 AND 10),
    run_after        timestamptz NOT NULL DEFAULT now(),
    lease_until      timestamptz,
    last_error       text        CHECK (last_error IS NULL OR char_length(last_error) <= 300),
    created_at       timestamptz NOT NULL DEFAULT now(),
    started_at       timestamptz,
    finished_at      timestamptz
);
CREATE INDEX agent_jobs_ready_idx ON agent_jobs (run_after) WHERE status = 'queued';
CREATE INDEX agent_jobs_session_idx ON agent_jobs (session_id);
CREATE INDEX agent_jobs_lease_idx ON agent_jobs (lease_until) WHERE status = 'running';

-- Ordered progress events (SSE / polling). dedupe_key makes one-shot events
-- (store.ready for a revision, store.published for a version) emit exactly once.
CREATE TABLE agent_events (
    id          bigserial   PRIMARY KEY,
    session_id  uuid        NOT NULL REFERENCES agent_sessions (id) ON DELETE CASCADE,
    type        text        NOT NULL CHECK (char_length(type) BETWEEN 1 AND 60),
    payload     jsonb       NOT NULL DEFAULT '{}'::jsonb,
    dedupe_key  text        CHECK (dedupe_key IS NULL OR char_length(dedupe_key) <= 120),
    created_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (session_id, dedupe_key)
);
CREATE INDEX agent_events_session_idx ON agent_events (session_id, id);

-- Audit of every tool the agent executed (no secrets, no raw prompts).
CREATE TABLE agent_actions (
    id           bigserial   PRIMARY KEY,
    session_id   uuid        NOT NULL REFERENCES agent_sessions (id) ON DELETE CASCADE,
    tool         text        NOT NULL CHECK (char_length(tool) BETWEEN 1 AND 60),
    actor        text        NOT NULL CHECK (actor IN ('agent', 'user', 'system')),
    summary      jsonb       NOT NULL DEFAULT '{}'::jsonb,
    outcome      text        NOT NULL CHECK (outcome IN ('ok', 'rejected', 'error', 'noop')),
    duration_ms  integer     NOT NULL DEFAULT 0,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX agent_actions_session_idx ON agent_actions (session_id, id);

-- AI usage and cost per call (micro-USD), for budgets and the cost report.
CREATE TABLE ai_usage (
    id                 bigserial   PRIMARY KEY,
    session_id         uuid        REFERENCES agent_sessions (id) ON DELETE CASCADE,
    purpose            text        NOT NULL,
    model              text        NOT NULL,
    input_tokens       integer     NOT NULL DEFAULT 0,
    output_tokens      integer     NOT NULL DEFAULT 0,
    cache_read_tokens  integer     NOT NULL DEFAULT 0,
    cache_write_tokens integer     NOT NULL DEFAULT 0,
    latency_ms         integer     NOT NULL DEFAULT 0,
    cost_micros        bigint      NOT NULL DEFAULT 0,
    outcome            text        NOT NULL,
    created_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ai_usage_session_idx ON ai_usage (session_id);

-- Payment requests. Only test-mode gateways exist; real money is impossible by schema.
CREATE TABLE payment_requests (
    id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id         uuid        NOT NULL REFERENCES stores (id) ON DELETE CASCADE,
    gateway          text        NOT NULL CHECK (gateway IN ('mock')),
    mode             text        NOT NULL CHECK (mode = 'test'),
    amount_minor     bigint      NOT NULL CHECK (amount_minor > 0),
    currency         char(3)     NOT NULL CHECK (currency = 'CRC'),
    lines            jsonb       NOT NULL,
    status           text        NOT NULL DEFAULT 'pending'
                                 CHECK (status IN ('pending', 'test_approved', 'test_declined', 'expired')),
    idempotency_key  text        NOT NULL UNIQUE CHECK (char_length(idempotency_key) BETWEEN 8 AND 64),
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX payment_requests_store_idx ON payment_requests (store_id, created_at);
