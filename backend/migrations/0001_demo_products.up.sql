-- Demo-only table used to prove Flutter -> Go -> PostgreSQL end to end.
-- Not the real product model; replace when the catalog module is designed.
CREATE TABLE IF NOT EXISTS demo_products (
    id           text PRIMARY KEY,
    name         text        NOT NULL,
    description  text        NOT NULL DEFAULT '',
    price_minor  bigint      NOT NULL CHECK (price_minor >= 0),
    currency     char(3)     NOT NULL DEFAULT 'CRC',
    sort_order   integer     NOT NULL DEFAULT 0,
    created_at   timestamptz NOT NULL DEFAULT now()
);
