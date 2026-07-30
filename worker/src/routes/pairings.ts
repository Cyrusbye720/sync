/**
 * Pairing routes: invite, claim, list, delete.
 * Uses Supabase RPCs for atomic invite/claim operations.
 */

import { Hono } from 'hono';
import type { HonoEnv } from '../types.js';
import { PairingClaimSchema } from '../schema.js';
import { authenticate } from '../middleware.js';

const pairings = new Hono<HonoEnv>();

pairings.use('*', authenticate);

// GET /v1/pairings — get user's current pairing
pairings.get('/', async (c) => {
  const userId = c.get('userId');
  const supabase = c.get('supabase');

  const { data, error } = await supabase
    .from('pairings')
    .select('*')
    .or(`user_a.eq.${userId},user_b.eq.${userId}`)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) return c.json({ error: error.message }, 500);
  return c.json(data); // null if no pairing
});

// POST /v1/pairings/invite — generate a new invite code
pairings.post('/invite', async (c) => {
  const userId = c.get('userId');
  const supabase = c.get('supabase');

  const { data, error } = await supabase.rpc('create_pairing_invite', {
    p_inviter: userId,
  });

  if (error) {
    const msg = error.message;
    if (msg.includes('already has an active pairing')) {
      return c.json({ error: 'Already paired' }, 409);
    }
    return c.json({ error: msg }, 500);
  }

  return c.json(data);
});

// POST /v1/pairings/claim — claim an invite code
pairings.post('/claim', async (c) => {
  const userId = c.get('userId');
  const supabase = c.get('supabase');

  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON' }, 400);
  }

  const parsed = PairingClaimSchema.safeParse(body);
  if (!parsed.success) {
    return c.json({ error: 'Invalid body', details: parsed.error.issues }, 400);
  }

  const { data, error } = await supabase.rpc('claim_pairing_by_code', {
    p_user_id: userId,
    p_code: parsed.data.code,
  });

  if (error) {
    const msg = error.message;
    if (msg.includes('already paired')) {
      return c.json({ error: 'Already paired' }, 409);
    }
    if (msg.includes('Invalid pairing code')) {
      return c.json({ error: 'Invalid code' }, 404);
    }
    return c.json({ error: msg }, 500);
  }

  return c.json(data);
});

// DELETE /v1/pairings/:id — unpair
pairings.delete('/:id', async (c) => {
  const userId = c.get('userId');
  const supabase = c.get('supabase');
  const pairingId = c.req.param('id');

  // RLS ensures only participants can delete
  const { error } = await supabase
    .from('pairings')
    .delete()
    .eq('id', pairingId);

  if (error) return c.json({ error: error.message }, 500);
  return c.json({ ok: true });
});

export default pairings;
