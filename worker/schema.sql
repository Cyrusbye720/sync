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

CREATE TABLE IF NOT EXISTS error_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  level TEXT NOT NULL,
  route TEXT,
  message TEXT NOT NULL,
  details TEXT,
  user_id TEXT,
  ip TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS error_logs_created_at_idx ON error_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS error_logs_level_idx ON error_logs (level);
CREATE INDEX IF NOT EXISTS error_logs_route_idx ON error_logs (route);

CREATE TABLE IF NOT EXISTS announcements (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'info',
  target TEXT NOT NULL DEFAULT 'all',
  created_by TEXT,
  sent_at TEXT DEFAULT (datetime('now')),
  expires_at TEXT
);
CREATE INDEX IF NOT EXISTS announcements_sent_at_idx ON announcements (sent_at DESC);
