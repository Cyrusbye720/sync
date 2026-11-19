import { Hono } from 'hono';
import type { HonoEnv } from '../types.js';
import { ProfileUpdateSchema } from '../schema.js';
import { authenticate } from '../middleware.js';

const profile = new Hono<HonoEnv>();
profile.use('*', authenticate);

profile.get('/', async (c) => {
  const row = await c.env.DB.prepare(
    'SELECT * FROM profiles WHERE id = ?',
  ).bind(c.get('userId')).first();
  if (!row) return c.json({ error: 'Profile not found' }, 404);
  return c.json(row);
});

profile.patch('/', async (c) => {
  let body: unknown;
  try { body = await c.req.json(); } catch { return c.json({ error: 'Invalid JSON' }, 400); }
  const parsed = ProfileUpdateSchema.safeParse(body);
  if (!parsed.success) return c.json({ error: 'Invalid body', details: parsed.error.issues }, 400);
  const fields = parsed.data;
  const assignments: string[] = [];
  const values: unknown[] = [];
  for (const [key, value] of Object.entries(fields)) {
    if (value === undefined) continue;
    assignments.push(`${key} = ?`);
    values.push(value);
  }
  if (assignments.length === 0) return c.json({ ok: true });
  values.push(c.get('userId'));
  await c.env.DB.prepare(
    `UPDATE profiles SET ${assignments.join(', ')} WHERE id = ?`,
  ).bind(...values).run();
  await c.env.DB.prepare(
    `UPDATE users SET ${assignments.join(', ')} WHERE id = ?`,
  ).bind(...values).run();
  return c.json({ ok: true });
});

profile.delete('/account', async (c) => {
  const userId = c.get('userId');
  await c.env.DB.prepare('DELETE FROM users WHERE id = ?').bind(userId).run();
  await c.env.DB.prepare('DELETE FROM sessions WHERE user_id = ?').bind(userId).run();
  return c.json({ ok: true });
});

profile.get('/partner', async (c) => {
  const userId = c.get('userId');
  const pairing = await c.env.DB.prepare(
    `SELECT * FROM pairings
     WHERE status = 'accepted'
       AND (user_a = ? OR user_b = ?) LIMIT 1`,
  ).bind(userId, userId).first<{ user_a: string; user_b: string }>();
  if (!pairing) return c.json({ error: 'No active pairing' }, 404);
  const partnerId = pairing.user_a === userId ? pairing.user_b : pairing.user_a;
  const partner = await c.env.DB.prepare(
    'SELECT * FROM profiles WHERE id = ?',
  ).bind(partnerId).first();
  if (!partner) return c.json({ error: 'Partner profile not found' }, 404);
  return c.json(partner);
});

export default profile;
