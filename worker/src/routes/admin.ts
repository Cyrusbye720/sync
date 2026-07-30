/**
 * Admin routes — query error logs, manage announcements.
 *
 * GET  /v1/admin/logs         — list error logs (with filters)
 * GET  /v1/admin/logs/stats   — error counts by route and level
 * GET  /v1/admin/logs/cleanup — delete logs older than 30 days
 *
 * Protected by x-admin-secret header.
 */

import { Hono } from 'hono';
import type { HonoEnv } from '../types.js';
import { logEvent } from '../logger.js';

const admin = new Hono<HonoEnv>();

// Middleware: require admin secret
admin.use('*', async (c, next) => {
  const secret = c.req.header('x-admin-secret');
  if (secret !== c.env.ADMIN_SECRET) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  await next();
});

// GET /v1/admin/logs — query logs with filters
admin.get('/logs', async (c) => {
  const limit = Math.min(parseInt(c.req.query('limit') ?? '100', 10) || 100, 500);
  const offset = Math.max(parseInt(c.req.query('offset') ?? '0', 10) || 0, 0);
  const level = c.req.query('level');
  const route = c.req.query('route');
  const userId = c.req.query('user_id');
  const since = c.req.query('since');

  let query = 'SELECT * FROM error_logs WHERE 1=1';
  const params: unknown[] = [];

  if (level) {
    query += ' AND level = ?';
    params.push(level);
  }
  if (route) {
    query += ' AND route = ?';
    params.push(route);
  }
  if (userId) {
    query += ' AND user_id = ?';
    params.push(userId);
  }
  if (since) {
    query += ' AND created_at > ?';
    params.push(since);
  }

  query += ' ORDER BY created_at DESC LIMIT ? OFFSET ?';
  params.push(limit, offset);

  const { results, error } = await c.env.DB.prepare(query)
    .bind(...params)
    .all();

  if (error) return c.json({ error: (error as any).message }, 500);
  return c.json(results ?? []);
});

// GET /v1/admin/logs/stats — error counts by route and level
admin.get('/logs/stats', async (c) => {
  const { results, error } = await c.env.DB.prepare(
    `SELECT route, level, COUNT(*) as count
     FROM error_logs
     WHERE created_at > datetime('now', '-7 days')
     GROUP BY route, level
     ORDER BY count DESC`,
  ).all();

  if (error) return c.json({ error: (error as any).message }, 500);
  return c.json(results ?? []);
});

// DELETE /v1/admin/logs/cleanup — remove logs older than 30 days
admin.delete('/logs/cleanup', async (c) => {
  const { error } = await c.env.DB.prepare(
    `DELETE FROM error_logs WHERE created_at < datetime('now', '-30 days')`,
  ).run();

  if (error) return c.json({ error: (error as any).message }, 500);
  return c.json({ ok: true });
});

// POST /v1/admin/test-log — write a test log entry
admin.post('/test-log', async (c) => {
  await logEvent(c.env, {
    level: 'info',
    route: 'POST /v1/admin/test-log',
    message: 'Test log entry',
    details: { timestamp: new Date().toISOString() },
  });
  return c.json({ ok: true });
});

// POST /v1/admin/migrate — create D1 tables (one-time)
admin.post('/migrate', async (c) => {
  const results: string[] = [];
  const stmts = [
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
    `CREATE INDEX IF NOT EXISTS error_logs_created_at_idx ON error_logs (created_at DESC)`,
    `CREATE INDEX IF NOT EXISTS error_logs_level_idx ON error_logs (level)`,
    `CREATE INDEX IF NOT EXISTS error_logs_route_idx ON error_logs (route)`,
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
    `CREATE INDEX IF NOT EXISTS announcements_sent_at_idx ON announcements (sent_at DESC)`,
  ];

  for (const sql of stmts) {
    try {
      await c.env.DB.prepare(sql).run();
      results.push(`OK: ${sql.substring(0, 60)}...`);
    } catch (e) {
      results.push(`FAIL: ${e instanceof Error ? e.message : e}`);
    }
  }

  return c.json({ ok: true, results });
});

export default admin;
