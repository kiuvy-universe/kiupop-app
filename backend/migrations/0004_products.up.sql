-- KPOP-POC-001: products per store. Money in integer minor units (céntimos).
CREATE TABLE products (
    id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id     uuid        NOT NULL REFERENCES stores (id) ON DELETE CASCADE,
    name         text        NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 80),
    description  text        NOT NULL DEFAULT '' CHECK (char_length(description) <= 600),
    price_minor  bigint      NOT NULL CHECK (price_minor > 0 AND price_minor <= 100000000000),
    currency     char(3)     NOT NULL DEFAULT 'CRC' CHECK (currency = 'CRC'),
    image_key    text        CHECK (image_key ~ '^[0-9a-f-]{36}\.(jpg|png|webp)$'),
    available    boolean     NOT NULL DEFAULT true,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX products_store_created_idx ON products (store_id, created_at);
CREATE INDEX products_store_available_idx ON products (store_id) WHERE available;
