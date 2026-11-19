import { Hono } from 'hono';
import type { HonoEnv } from '../types.js';
import { PairingClaimSchema } from '../schema.js';
import { authenticate } from '../middleware.js';

function randomCode(): string {
  const bytes = new Uint8Array(6);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => String(b % 10)).join('');
}

const pairings = new Hono<HonoEnv>();
pairings.use('*', authenticate);

pairings.get('/', async (c) => {
  const userId = c.get('userId');
  const row = await c.env.DB.prepare(
    `SELECT * FROM pairings
     WHERE (user_a = ? OR user_b = ?)
     ORDER BY created_at DESC LIMIT 1`,
  ).bind(userId, userId).first();
  return c.json(row ?? null);
});

pairings.post('/invite', async (c) => {
  const userId = c.get('userId');
  const active = await c.env.DB.prepare(
    `SELECT id FROM pairings
     WHERE status = 'accepted' AND (user_a = ? OR user_b = ?) LIMIT 1`,
  ).bind(userId, userId).first();
  if (active) return c.json({ error: 'Already paired' }, 409);
  const now = Math.floor(Date.now() / 1000);
  let code = '';
  for (let attempt = 0; attempt < 5; attempt++) {
    code = randomCode();
    const collision = await c.env.DB.prepare(
      'SELECT id FROM pairings WHERE invite_code = ?',
    ).bind(code).first();
    if (!collision) break;
  }
  const id = crypto.randomUUID();
  await c.env.DB.prepare(
    `INSERT INTO pairings (id,user_a,user_b,invite_code,status,created_at)
     VALUES (?, ?, NULL, ?, 'pending', ?)`,
  ).bind(id, userId, code, now).run();
  return c.json({
    id,
    user_a: userId,
    user_b: null,
    invite_code: code,
    status: 'pending',
    created_at: now,
  });
});

pairings.post('/claim', async (c) => {
  let body: unknown;
  try { body = await c.req.json(); } catch { return c.json({ error: 'Invalid JSON' }, 400); }
  const parsed = PairingClaimSchema.safeParse(body);
  if (!parsed.success) return c.json({ error: 'Invalid body' }, 400);
  const userId = c.get('userId');
  const active = await c.env.DB.prepare(
    `SELECT id FROM pairings
     WHERE status = 'accepted' AND (user_a = ? OR user_b = ?) LIMIT 1`,
  ).bind(userId, userId).first();
  if (active) return c.json({ error: 'Already paired' }, 409);
  const invite = await c.env.DB.prepare(
    `SELECT * FROM pairings
     WHERE invite_code = ? AND status = 'pending' LIMIT 1`,
  ).bind(parsed.data.code).first<{ id: string; user_a: string }>();
  if (!invite) return c.json({ error: 'Invalid pairing code' }, 404);
  if (invite.user_a === userId) return c.json({ error: 'Cannot pair with yourself' }, 400);
  const now = Math.floor(Date.now() / 1000);
  await c.env.DB.prepare(
    `UPDATE pairings SET user_b = ?, status = 'accepted', accepted_at = ?, invite_code = NULL
     WHERE id = ?`,
  ).bind(userId, now, invite.id).run();
  const pairing = await c.env.DB.prepare(
    'SELECT * FROM pairings WHERE id = ?',
  ).bind(invite.id).first();
  return c.json(pairing);
});

pairings.delete('/:id', async (c) => {
  const userId = c.get('userId');
  const pairing = await c.env.DB.prepare(
    'SELECT id FROM pairings WHERE id = ? AND (user_a = ? OR user_b = ?)',
  ).bind(c.req.param('id'), userId, userId).first();
  if (!pairing) return c.json({ error: 'Pairing not found' }, 404);
  await c.env.DB.prepare('DELETE FROM pairings WHERE id = ?')
    .bind(c.req.param('id')).run();
  return c.json({ ok: true });
});

export default pairings;
