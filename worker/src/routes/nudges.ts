/**
 * Nudge routes: send nudge (+ FCM push), list, mark read.
 *
 * The nudge insert uses the user's session (RLS validates the pairing).
 * The FCM token lookup uses the service-role key (narrowly scoped read).
 */

import { Hono } from 'hono';
import { createClient } from '@supabase/supabase-js';
import type { HonoEnv, ServiceAccount } from '../types.js';
import { NudgeCreateSchema } from '../schema.js';
import { sendFcmNotification } from '../fcm.js';
import { fanOutNudge } from '../websocket.js';
import { logError } from '../logger.js';

const nudges = new Hono<HonoEnv>();

// POST /v1/nudges — send a nudge to partner
nudges.post('/', async (c) => {
  const userId = c.get('userId');
  const supabase = c.get('supabase');

  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON' }, 400);
  }

  const parsed = NudgeCreateSchema.safeParse(body);
  if (!parsed.success) {
    return c.json({ error: 'Invalid body', details: parsed.error.issues }, 400);
  }

  const toUserId = parsed.data.to_user_id;

  // 1. Insert nudge row via user session (RLS validates pairing)
  const { data: nudge, error: insertErr } = await supabase
    .from('nudges')
    .insert({ from_user: userId, to_user: toUserId })
    .select()
    .single();

  if (insertErr) {
    await logError(c.env, 'POST /v1/nudges', insertErr.message, { userId, toUserId }, userId, c.req.header('cf-connecting-ip') ?? undefined);
    return c.json({ error: insertErr.message }, 500);
  }

  // 2. Fan out to connected WebSocket clients
  fanOutNudge(toUserId, nudge);

  // 3. Look up target's FCM token (service-role, narrowly scoped read)
  let fcmResult = { success: false, error: 'no token' };
  try {
    const adminClient = createClient(
      c.env.SUPABASE_URL,
      c.env.SUPABASE_SERVICE_ROLE_KEY,
      { auth: { persistSession: false } },
    );

    const { data: targetProfile } = await adminClient
      .from('profiles')
      .select('fcm_token, username')
      .eq('id', toUserId)
      .single();

    const fcmToken = targetProfile?.fcm_token;

    if (fcmToken) {
      // 4. Send FCM push
      let sa: ServiceAccount;
      try {
        sa = JSON.parse(c.env.FIREBASE_SERVICE_ACCOUNT_JSON) as ServiceAccount;
      } catch {
        fcmResult = { success: false, error: 'Invalid service account JSON' };
        return c.json({ ok: true, nudge_id: nudge.id, fcm: fcmResult });
      }

      // Get sender's username for the notification (use admin client for reliability)
      const { data: senderProfile } = await adminClient
        .from('profiles')
        .select('username')
        .eq('id', userId)
        .single();

      const senderName = senderProfile?.username ?? 'Your partner';
      fcmResult = await sendFcmNotification(
        sa,
        fcmToken,
        'NUDGE',
        `${senderName} is trying to wake you up`,
      );
    }
  } catch {
    // FCM is best-effort — the nudge row + WebSocket already delivered
  }

  return c.json({
    ok: true,
    nudge_id: nudge.id,
    fcm: fcmResult.success ? 'sent' : 'skipped',
  });
});

// GET /v1/nudges — list incoming nudges
nudges.get('/', async (c) => {
  const userId = c.get('userId');
  const supabase = c.get('supabase');

  const { data, error } = await supabase
    .from('nudges')
    .select('*')
    .eq('to_user', userId)
    .order('created_at', { ascending: false })
    .limit(50);

  if (error) return c.json({ error: error.message }, 500);
  return c.json(data ?? []);
});

// PATCH /v1/nudges/:id/read — mark nudge as read
nudges.patch('/:id/read', async (c) => {
  const supabase = c.get('supabase');
  const nudgeId = c.req.param('id');

  // RLS update policy: only to_user can update
  const { error } = await supabase
    .from('nudges')
    .update({ read_at: new Date().toISOString() })
    .eq('id', nudgeId);

  if (error) return c.json({ error: error.message }, 500);
  return c.json({ ok: true });
});

export default nudges;
