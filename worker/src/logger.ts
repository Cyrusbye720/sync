/**
 * Persistent error logger — stores structured error logs in D1.
 *
 * Every log entry captures: level, route, message, details (JSON), user_id, IP, timestamp.
 * Queryable via GET /v1/admin/logs (protected by admin secret).
 *
 * Also logs to console.error as a fallback for real-time debugging.
 * Auto-creates tables on first use if they don't exist.
 */

import type { Env } from './types.js';

export type LogLevel = 'error' | 'warn' | 'info';

export interface LogEntry {
  level: LogLevel;
  route?: string;
  message: string;
  details?: unknown;
  userId?: string;
  ip?: string;
}

let tablesCreated = false;

async function ensureTables(env: Env): Promise<void> {
  if (tablesCreated) return;
  try {
    await env.DB.prepare(
      `CREATE TABLE IF NOT EXISTS error_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        level TEXT NOT NULL,
        route TEXT,
        message TEXT NOT NULL,
        details TEXT,
        user_id TEXT,
        ip TEXT,
        created_at TEXT DEFAULT (datetime('now'))
      )`,
    ).run();
    await env.DB.prepare(
      `CREATE TABLE IF NOT EXISTS announcements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'info',
        target TEXT NOT NULL DEFAULT 'all',
        created_by TEXT,
        sent_at TEXT DEFAULT (datetime('now')),
        expires_at TEXT
      )`,
    ).run();
    tablesCreated = true;
  } catch {
    // Table may already exist or migration may have run
    tablesCreated = true;
  }
}

/**
 * Write a structured log entry to D1 (and console).
 * Non-blocking — errors in logging are silently swallowed.
 */
export async function logEvent(env: Env, entry: LogEntry): Promise<void> {
  const consoleFn =
    entry.level === 'error'
      ? console.error
      : entry.level === 'warn'
        ? console.warn
        : console.log;

  consoleFn(
    `[${entry.level.toUpperCase()}] ${entry.route ?? 'unknown'}: ${entry.message}`,
    entry.details ?? '',
  );

  try {
    await ensureTables(env);
    await env.DB.prepare(
      `INSERT INTO error_logs (level, route, message, details, user_id, ip)
       VALUES (?, ?, ?, ?, ?, ?)`,
    )
      .bind(
        entry.level,
        entry.route ?? null,
        entry.message,
        entry.details ? JSON.stringify(entry.details) : null,
        entry.userId ?? null,
        entry.ip ?? null,
      )
      .run();
  } catch {
    // Logging should never crash the request
  }
}

/**
 * Convenience wrappers.
 */
export async function logError(
  env: Env,
  route: string,
  message: string,
  details?: unknown,
  userId?: string,
  ip?: string,
): Promise<void> {
  return logEvent(env, {
    level: 'error',
    route,
    message,
    details,
    userId,
    ip,
  });
}

export async function logWarn(
  env: Env,
  route: string,
  message: string,
  details?: unknown,
  userId?: string,
  ip?: string,
): Promise<void> {
  return logEvent(env, {
    level: 'warn',
    route,
    message,
    details,
    userId,
    ip,
  });
}

export async function logInfo(
  env: Env,
  route: string,
  message: string,
  details?: unknown,
  userId?: string,
  ip?: string,
): Promise<void> {
  return logEvent(env, {
    level: 'info',
    route,
    message,
    details,
    userId,
    ip,
  });
}
