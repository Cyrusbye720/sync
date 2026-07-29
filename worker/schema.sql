-- D1 schema for the SYNC Cloudflare Worker.
-- Applied via: wrangler d1 execute sync-sessions --file=schema.sql

CREATE TABLE IF NOT EXISTS sessions (
  token_hash  TEXT    PRIMARY KEY,
  user_id     TEXT    NOT NULL,
  sb_access   TEXT    NOT NULL,  -- AES-256-GCM encrypted Supabase access token
  sb_refresh  TEXT    NOT NULL,  -- AES-256-GCM encrypted Supabase refresh token
  created_at  INTEGER NOT NULL,
  expires_at  INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions (user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_expires ON sessions (expires_at);

CREATE TABLE IF NOT EXISTS oauth_state (
  state       TEXT    PRIMARY KEY,
  provider    TEXT    NOT NULL,
  created_at  INTEGER NOT NULL,
  expires_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS login_codes (
  code        TEXT    PRIMARY KEY,
  token_hash  TEXT    NOT NULL,
  created_at  INTEGER NOT NULL,
  expires_at  INTEGER NOT NULL
);
