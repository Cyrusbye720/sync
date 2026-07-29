-- Error log table for persistent error tracking
CREATE TABLE IF NOT EXISTS error_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  level TEXT NOT NULL CHECK (level IN ('error', 'warn', 'info')),
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

-- Announcements table for broadcast notifications
CREATE TABLE IF NOT EXISTS announcements (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'info' CHECK (type IN ('info', 'warning', 'update', 'alert')),
  target TEXT NOT NULL DEFAULT 'all' CHECK (target IN ('all', 'paired', 'single')),
  created_by TEXT,
  sent_at TEXT DEFAULT (datetime('now')),
  expires_at TEXT
);

CREATE INDEX IF NOT EXISTS announcements_sent_at_idx ON announcements (sent_at DESC);
