DROP TABLE IF EXISTS payment_requests;
DROP TABLE IF EXISTS ai_usage;
DROP TABLE IF EXISTS agent_actions;
DROP TABLE IF EXISTS agent_events;
DROP TABLE IF EXISTS agent_jobs;
DROP TABLE IF EXISTS agent_messages;
DROP TABLE IF EXISTS agent_sessions;
DROP TABLE IF EXISTS store_publications;
DROP INDEX IF EXISTS stores_owner_idx;
ALTER TABLE stores DROP CONSTRAINT IF EXISTS stores_published_needs_whatsapp;
DELETE FROM stores WHERE whatsapp_e164 IS NULL;
ALTER TABLE stores ALTER COLUMN whatsapp_e164 SET NOT NULL;
ALTER TABLE stores
    DROP COLUMN IF EXISTS published_at,
    DROP COLUMN IF EXISTS published_version,
    DROP COLUMN IF EXISTS profile,
    DROP COLUMN IF EXISTS theme,
    DROP COLUMN IF EXISTS template,
    DROP COLUMN IF EXISTS status,
    DROP COLUMN IF EXISTS owner_user_id;
DROP TABLE IF EXISTS users;
