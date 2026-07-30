/**
 * Profile routes: GET/PATCH own profile, GET partner profile.
 * All calls use the server-held Supabase user session (RLS enforced).
 */

import { createClient } from '@supabase/supabase-js';
import { Hono } from 'hono';
import type { HonoEnv } from '../types.js';
import { ProfileUpdateSchema } from '../schema.js';
import { logError } from '../logger.js';

const profile = new Hono<HonoEnv>();

// GET /v1/profile — fetch own profile
profile.get('/', async (c) => {
  const userId = c.get('userId');
  const supabase = c.get('supabase');

  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', userId)
    .single();

  const adminClient = createClient(
    c.env.SUPABASE_URL,
    c.env.SUPABASE_SERVICE_ROLE_KEY,
    { auth: { persistSession: false } },
  );

  if (data) {
    if (!data.username || data.username.startsWith('user_')) {
      try {
        const { data: userRecord } = await adminClient.auth.admin.getUserById(userId);
        const meta = userRecord?.user?.user_metadata || {};
        const realName =
          meta['custom_claims']?.['global_name'] ??
          meta['full_name'] ??
          meta['name'] ??
          meta['user_name'] ??
          meta['preferred_username'];
        const avatarUrl = meta['avatar_url'] ?? data.avatar_url;

        if (realName && realName !== data.username) {
          const { data: updated } = await adminClient
            .from('profiles')
            .update({ username: realName, avatar_url: avatarUrl })
            .eq('id', userId)
            .select()
            .single();
          if (updated) return c.json(updated);
        }
      } catch (_) {}
    }
    return c.json(data);
  }

  // Profile may not exist if the signup trigger failed.
  try {
    const { data: newUser } = await adminClient.auth.admin.getUserById(userId);
    const meta = newUser?.user?.user_metadata || {};
    const username =
      meta['custom_claims']?.['global_name'] ??
      meta['full_name'] ??
      meta['name'] ??
      meta['user_name'] ??
      meta['preferred_username'] ??
      `user_${userId.substring(0, 6)}`;
    const avatarUrl = meta['avatar_url'] ?? null;

    const { data: created } = await adminClient
      .from('profiles')
      .upsert(
        { id: userId, username, avatar_url: avatarUrl, timezone: 'UTC' },
        { onConflict: 'id', ignoreDuplicates: true },
      )
      .select()
      .single();

    if (created) return c.json(created);
  } catch (e) {
    await logError(c.env, 'GET /v1/profile', 'Profile auto-create failed', e instanceof Error ? e.message : e, userId);
  }
  return c.json({ error: 'Profile not found' }, 404);
});

// PATCH /v1/profile — update own profile
profile.patch('/', async (c) => {
  const userId = c.get('userId');
  const supabase = c.get('supabase');

  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON' }, 400);
  }

  const parsed = ProfileUpdateSchema.safeParse(body);
  if (!parsed.success) {
    return c.json({ error: 'Invalid body', details: parsed.error.issues }, 400);
  }

  const { error } = await supabase
    .from('profiles')
    .update(parsed.data)
    .eq('id', userId);

  if (error) return c.json({ error: error.message }, 500);
  return c.json({ ok: true });
});

// GET /v1/profile/partner — get partner's profile
profile.get('/partner', async (c) => {
  const userId = c.get('userId');
  const supabase = c.get('supabase');

  // Find accepted pairing
  const { data: pairing } = await supabase
    .from('pairings')
    .select('*')
    .or(`user_a.eq.${userId},user_b.eq.${userId}`)
    .eq('status', 'accepted')
    .limit(1)
    .maybeSingle();

  if (!pairing) {
    return c.json({ error: 'No active pairing' }, 404);
  }

  const partnerId = pairing.user_a === userId ? pairing.user_b : pairing.user_a;
  if (!partnerId) {
    return c.json({ error: 'Partner not yet joined' }, 404);
  }

  const { data: partner, error } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', partnerId)
    .single();

  if (error || !partner) {
    return c.json({ error: 'Partner profile not found' }, 404);
  }

  return c.json(partner);
});

export default profile;
