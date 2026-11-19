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

CREATE TABLE IF NOT EXISTS delivery_events (
  idempotency_key TEXT PRIMARY KEY,
  nudge_id TEXT NOT NULL,
  recipient_id TEXT NOT NULL,
  sender_id TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS delivery_events_nudge_idx
  ON delivery_events (nudge_id);

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  provider TEXT NOT NULL,
  provider_id TEXT NOT NULL,
  username TEXT NOT NULL,
  avatar_url TEXT,
  timezone TEXT NOT NULL DEFAULT 'Asia/Kolkata',
  battery_percent INTEGER NOT NULL DEFAULT 100,
  sleep_status TEXT NOT NULL DEFAULT 'awake',
  created_at INTEGER NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS users_provider_idx
  ON users (provider, provider_id);

CREATE TABLE IF NOT EXISTS profiles (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL,
  avatar_url TEXT,
  timezone TEXT NOT NULL DEFAULT 'Asia/Kolkata',
  battery_percent INTEGER NOT NULL DEFAULT 100,
  sleep_status TEXT NOT NULL DEFAULT 'awake',
  created_at INTEGER NOT NULL,
  FOREIGN KEY (id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS pairings (
  id TEXT PRIMARY KEY,
  user_a TEXT NOT NULL,
  user_b TEXT,
  invite_code TEXT,
  status TEXT NOT NULL CHECK (status IN ('pending','accepted')),
  created_at INTEGER NOT NULL,
  accepted_at INTEGER,
  FOREIGN KEY (user_a) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (user_b) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS pairings_users_idx
  ON pairings (user_a, user_b);
CREATE UNIQUE INDEX IF NOT EXISTS pairings_invite_code_idx
  ON pairings (invite_code);

CREATE TABLE IF NOT EXISTS alarms (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  created_by TEXT NOT NULL,
  label TEXT NOT NULL,
  message TEXT NOT NULL DEFAULT 'Wake up!',
  hour INTEGER NOT NULL,
  minute INTEGER NOT NULL,
  days_of_week TEXT NOT NULL DEFAULT '[]',
  is_active INTEGER NOT NULL DEFAULT 1,
  vibrate INTEGER NOT NULL DEFAULT 1,
  sound_name TEXT NOT NULL DEFAULT 'default',
  snooze_minutes INTEGER NOT NULL DEFAULT 5,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS alarms_owner_idx ON alarms (owner_id);
CREATE INDEX IF NOT EXISTS alarms_creator_idx ON alarms (created_by);

CREATE TABLE IF NOT EXISTS nudges (
  id TEXT PRIMARY KEY,
  from_user TEXT NOT NULL,
  to_user TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  read_at INTEGER,
  FOREIGN KEY (from_user) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (to_user) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS nudges_recipient_idx
  ON nudges (to_user, created_at DESC);

CREATE TABLE IF NOT EXISTS alarm_logs (
  id TEXT PRIMARY KEY,
  alarm_id TEXT NOT NULL,
  action TEXT NOT NULL,
  reaction TEXT,
  acted_by TEXT,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (alarm_id) REFERENCES alarms(id) ON DELETE CASCADE
);
