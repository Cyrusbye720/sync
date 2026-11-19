import { Hono } from 'hono';
import type { HonoEnv } from '../types.js';
import { NudgeCreateSchema } from '../schema.js';
import { authenticate } from '../middleware.js';
import { fanOutNudge } from '../websocket.js';

const nudges = new Hono<HonoEnv>();
nudges.use('*', authenticate);

nudges.post('/', async (c) => {
  let body: unknown;
  try { body = await c.req.json(); } catch { return c.json({ error: 'Invalid JSON' }, 400); }
  const parsed = NudgeCreateSchema.safeParse(body);
  if (!parsed.success) return c.json({ error: 'Invalid body' }, 400);
  const userId = c.get('userId');
  const pairing = await c.env.DB.prepare(
    `SELECT * FROM pairings
     WHERE status = 'accepted' AND (user_a = ? OR user_b = ?) LIMIT 1`,
  ).bind(userId, userId).first<{ user_a: string; user_b: string }>();
  if (!pairing) return c.json({ error: 'Pairing required' }, 403);
  if (parsed.data.to_user_id !== (pairing.user_a === userId ? pairing.user_b : pairing.user_a)) {
    return c.json({ error: 'Nudge recipient must be your partner' }, 403);
  }
  const idempotencyKey = c.req.header('x-sync-idempotency-key');
  if (idempotencyKey) {
    const existing = await c.env.DB.prepare(
      'SELECT nudge_id FROM delivery_events WHERE idempotency_key = ?',
    ).bind(idempotencyKey).first<{ nudge_id: string }>();
    if (existing) return c.json({ ok: true, nudge_id: existing.nudge_id, delivered: 'deduplicated' });
  }
  const id = crypto.randomUUID();
  const now = Math.floor(Date.now() / 1000);
  await c.env.DB.prepare(
    'INSERT INTO nudges (id, from_user, to_user, created_at) VALUES (?, ?, ?, ?)',
  ).bind(id, userId, parsed.data.to_user_id, now).run();
  const nudge = await c.env.DB.prepare('SELECT * FROM nudges WHERE id = ?').bind(id).first();
  fanOutNudge(parsed.data.to_user_id, nudge);
  if (idempotencyKey) {
    await c.env.DB.prepare(
      `INSERT OR IGNORE INTO delivery_events
       (idempotency_key,nudge_id,recipient_id,sender_id,created_at)
       VALUES (?, ?, ?, ?, ?)`,
    ).bind(idempotencyKey, id, parsed.data.to_user_id, userId, now).run();
  }
  return c.json({ ok: true, nudge_id: id, delivered: 'websocket-or-poll' });
});

nudges.get('/', async (c) => {
  const limit = Math.min(parseInt(c.req.query('limit') ?? '50', 10), 50);
  const rows = await c.env.DB.prepare(
    `SELECT * FROM nudges WHERE to_user = ?
     ORDER BY created_at DESC LIMIT ?`,
  ).bind(c.get('userId'), limit).all();
  return c.json(rows.results ?? []);
});

nudges.patch('/:id/read', async (c) => {
  const now = Math.floor(Date.now() / 1000);
  await c.env.DB.prepare(
    'UPDATE nudges SET read_at = ? WHERE id = ? AND to_user = ?',
  ).bind(now, c.req.param('id'), c.get('userId')).run();
  return c.json({ ok: true });
});

export default nudges;
