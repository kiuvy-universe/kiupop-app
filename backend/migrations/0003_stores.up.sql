-- KPOP-POC-001: stores and their admin credentials (hash only).
CREATE TABLE stores (
    id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    slug           text        NOT NULL UNIQUE
                               CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND length(slug) BETWEEN 3 AND 60),
    name           text        NOT NULL CHECK (char_length(btrim(name)) BETWEEN 2 AND 80),
    description    text        NOT NULL DEFAULT '' CHECK (char_length(description) <= 500),
    whatsapp_e164  text        NOT NULL CHECK (whatsapp_e164 ~ '^[1-9][0-9]{7,14}$'),
    created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE store_admin_credentials (
    id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id     uuid        NOT NULL REFERENCES stores (id) ON DELETE CASCADE,
    token_hash   bytea       NOT NULL UNIQUE CHECK (octet_length(token_hash) = 32),
    created_at   timestamptz NOT NULL DEFAULT now(),
    revoked_at   timestamptz
);
CREATE INDEX store_admin_credentials_store_id_idx ON store_admin_credentials (store_id);
