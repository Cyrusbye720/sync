import { Hono } from 'hono';
import type { HonoEnv } from '../types.js';
import { AlarmCreateSchema, AlarmUpdateSchema, AlarmLogCreateSchema, AlarmLogUpdateSchema } from '../schema.js';
import { authenticate } from '../middleware.js';

const alarms = new Hono<HonoEnv>();
alarms.use('*', authenticate);

function deserializeAlarm(row: any) {
  if (!row) return row;
  return {
    ...row,
    days_of_week: JSON.parse(row.days_of_week || '[]'),
    is_active: Boolean(row.is_active),
    vibrate: Boolean(row.vibrate),
  };
}

alarms.get('/', async (c) => {
  const userId = c.get('userId');
  const rows = await c.env.DB.prepare(
    `SELECT * FROM alarms
     WHERE owner_id = ? OR created_by = ?
     ORDER BY hour, minute`,
  ).bind(userId, userId).all();
  return c.json((rows.results ?? []).map(deserializeAlarm));
});

alarms.post('/', async (c) => {
  let body: unknown;
  try { body = await c.req.json(); } catch { return c.json({ error: 'Invalid JSON' }, 400); }
  const parsed = AlarmCreateSchema.safeParse(body);
  if (!parsed.success) return c.json({ error: 'Invalid body', details: parsed.error.issues }, 400);
  const userId = c.get('userId');
  const pairing = await c.env.DB.prepare(
    `SELECT * FROM pairings
     WHERE status = 'accepted' AND (user_a = ? OR user_b = ?) LIMIT 1`,
  ).bind(userId, userId).first<{ user_a: string; user_b: string }>();
  if (!pairing) return c.json({ error: 'Pairing required' }, 403);
  if (parsed.data.owner_id !== userId &&
      parsed.data.owner_id !== (pairing.user_a === userId ? pairing.user_b : pairing.user_a)) {
    return c.json({ error: 'Owner must be you or your partner' }, 403);
  }
  const id = crypto.randomUUID();
  const now = Math.floor(Date.now() / 1000);
  await c.env.DB.prepare(
    `INSERT INTO alarms
     (id, owner_id, created_by, label, message, hour, minute, days_of_week,
      is_active, vibrate, sound_name, snooze_minutes, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  ).bind(
    id, parsed.data.owner_id, userId, parsed.data.label, parsed.data.message,
    parsed.data.hour, parsed.data.minute, JSON.stringify(parsed.data.days_of_week),
    parsed.data.is_active ? 1 : 0, parsed.data.vibrate ? 1 : 0,
    parsed.data.sound_name, parsed.data.snooze_minutes, now,
  ).run();
  const row = await c.env.DB.prepare('SELECT * FROM alarms WHERE id = ?').bind(id).first();
  return c.json(deserializeAlarm(row), 201);
});

alarms.patch('/:id', async (c) => {
  let body: unknown;
  try { body = await c.req.json(); } catch { return c.json({ error: 'Invalid JSON' }, 400); }
  const parsed = AlarmUpdateSchema.safeParse(body);
  if (!parsed.success) return c.json({ error: 'Invalid body' }, 400);
  const userId = c.get('userId');
  const alarm = await c.env.DB.prepare(
    'SELECT * FROM alarms WHERE id = ? AND (owner_id = ? OR created_by = ?)',
  ).bind(c.req.param('id'), userId, userId).first();
  if (!alarm) return c.json({ error: 'Alarm not found' }, 404);
  const assignments: string[] = [];
  const values: unknown[] = [];
  for (const [key, value] of Object.entries(parsed.data)) {
    if (value === undefined) continue;
    assignments.push(`${key} = ?`);
    values.push(key === 'days_of_week' ? JSON.stringify(value) : typeof value === 'boolean' ? (value ? 1 : 0) : value);
  }
  if (assignments.length) {
    values.push(c.req.param('id'));
    await c.env.DB.prepare(`UPDATE alarms SET ${assignments.join(', ')} WHERE id = ?`)
      .bind(...values).run();
  }
  const row = await c.env.DB.prepare('SELECT * FROM alarms WHERE id = ?').bind(c.req.param('id')).first();
  return c.json(deserializeAlarm(row));
});

alarms.delete('/:id', async (c) => {
  const userId = c.get('userId');
  const alarm = await c.env.DB.prepare(
    'SELECT id FROM alarms WHERE id = ? AND (owner_id = ? OR created_by = ?)',
  ).bind(c.req.param('id'), userId, userId).first();
  if (!alarm) return c.json({ error: 'Alarm not found' }, 404);
  await c.env.DB.prepare('DELETE FROM alarms WHERE id = ?').bind(c.req.param('id')).run();
  return c.json({ ok: true });
});

alarms.get('/logs', async (c) => {
  const alarmIds = (c.req.query('alarm_ids') ?? '').split(',').filter(Boolean);
  if (!alarmIds.length) return c.json([]);
  const limit = Math.min(parseInt(c.req.query('limit') ?? '100', 10), 500);
  const placeholders = alarmIds.map(() => '?').join(',');
  const rows = await c.env.DB.prepare(
    `SELECT * FROM alarm_logs WHERE alarm_id IN (${placeholders})
     ORDER BY created_at DESC LIMIT ?`,
  ).bind(...alarmIds, limit).all();
  return c.json(rows.results ?? []);
});

alarms.post('/logs', async (c) => {
  let body: unknown;
  try { body = await c.req.json(); } catch { return c.json({ error: 'Invalid JSON' }, 400); }
  const parsed = AlarmLogCreateSchema.safeParse(body);
  if (!parsed.success) return c.json({ error: 'Invalid body' }, 400);
  const id = crypto.randomUUID();
  const now = Math.floor(Date.now() / 1000);
  await c.env.DB.prepare(
    `INSERT INTO alarm_logs (id, alarm_id, action, reaction, acted_by, created_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  ).bind(id, parsed.data.alarm_id, parsed.data.action, parsed.data.reaction ?? null,
    parsed.data.acted_by ?? c.get('userId'), now).run();
  const row = await c.env.DB.prepare('SELECT * FROM alarm_logs WHERE id = ?').bind(id).first();
  return c.json(row, 201);
});

alarms.patch('/logs/:id', async (c) => {
  let body: unknown;
  try { body = await c.req.json(); } catch { return c.json({ error: 'Invalid JSON' }, 400); }
  const parsed = AlarmLogUpdateSchema.safeParse(body);
  if (!parsed.success) return c.json({ error: 'Invalid body' }, 400);
  await c.env.DB.prepare('UPDATE alarm_logs SET reaction = ? WHERE id = ?')
    .bind(parsed.data.reaction, c.req.param('id')).run();
  const row = await c.env.DB.prepare('SELECT * FROM alarm_logs WHERE id = ?')
    .bind(c.req.param('id')).first();
  return c.json(row);
});

export default alarms;
