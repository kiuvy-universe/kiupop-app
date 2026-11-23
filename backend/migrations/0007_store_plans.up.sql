-- KPOP-PAYWALL: quiz funnel paywall. One plan per store: US$5/month per active
-- store. Every row is a TEST plan in this phase (no money moves); the CHECKs pin
-- the only terms the app sells so a client can never choose its own price.
CREATE TABLE store_plans (
    store_id           uuid        PRIMARY KEY REFERENCES stores (id) ON DELETE CASCADE,
    plan               text        NOT NULL CHECK (plan = 'kiupop_monthly'),
    price_minor        integer     NOT NULL CHECK (price_minor = 500),
    currency           text        NOT NULL CHECK (currency = 'USD'),
    status             text        NOT NULL CHECK (status IN ('active', 'canceled')),
    test               boolean     NOT NULL DEFAULT true CHECK (test),
    activated_at       timestamptz NOT NULL DEFAULT now(),
    current_period_end timestamptz NOT NULL
);
