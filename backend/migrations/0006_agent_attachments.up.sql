-- KPOP-AGENT-001 P1: attachments shared with Kiu (photos, CSV/PDF catalogs).
-- Files are untrusted data: validated by content, stored under server-generated
-- keys, never executed, and processed one by one by the agent job queue.
CREATE TABLE agent_attachments (
    id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id   uuid        NOT NULL REFERENCES agent_sessions (id) ON DELETE CASCADE,
    kind         text        NOT NULL CHECK (kind IN ('image', 'csv', 'pdf')),
    filename     text        NOT NULL CHECK (char_length(filename) BETWEEN 1 AND 120),
    size_bytes   bigint      NOT NULL CHECK (size_bytes > 0),
    storage_key  text        CHECK (storage_key IS NULL OR storage_key ~ '^[0-9a-f-]{36}\.(jpg|png|webp|pdf|csv)$'),
    status       text        NOT NULL DEFAULT 'received'
                             CHECK (status IN ('received', 'processing', 'processed', 'needs_review', 'error')),
    note         text        NOT NULL DEFAULT '' CHECK (char_length(note) <= 300),
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX agent_attachments_session_idx ON agent_attachments (session_id, created_at);
