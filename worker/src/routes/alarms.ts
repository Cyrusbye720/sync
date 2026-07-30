/**
 * Alarm routes: CRUD for alarms and alarm logs.
 * RLS on the Supabase side ensures users only see alarms they own or created.
 */

import { Hono } from 'hono';
import { createClient } from '@supabase/supabase-js';
import type { HonoEnv, ServiceAccount } from '../types.js';
import {
  AlarmCreateSchema,
  AlarmUpdateSchema,
  AlarmLogCreateSchema,
  AlarmLogUpdateSchema,
} from '../schema.js';
import { sendFcmNotification } from '../fcm.js';
import { logError } from '../logger.js';
import { authenticate } from '../middleware.js';

const alarms = new Hono<HonoEnv>();

alarms.use('*', authenticate);

// ─── Alarms ───────────────────────────────────────────────────────────────────

// GET /v1/alarms — list alarms for user (owner or creator)
alarms.get('/', async (c) => {
  const userId = c.get('userId');
  const supabase = c.get('supabase');

  const { data, error } = await supabase
    .from('alarms')
    .select('*')
    .or(`owner_id.eq.${userId},created_by.eq.${userId}`)
    .order('hour')
    .order('minute');

  if (error) return c.json({ error: error.message }, 500);
  return c.json(data ?? []);
});

// POST /v1/alarms — create alarm
alarms.post('/', async (c) => {
  const userId = c.get('userId');
  const supabase = c.get('supabase');

  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON' }, 400);
  }

  const parsed = AlarmCreateSchema.safeParse(body);
  if (!parsed.success) {
    return c.json({ error: 'Invalid body', details: parsed.error.issues }, 400);
  }

  // RLS insert policy requires created_by = auth.uid() and valid pairing
  const { data, error } = await supabase
    .from('alarms')
    .insert({ ...parsed.data, created_by: userId })
    .select()
    .single();

  if (error) {
    await logError(c.env, 'POST /v1/alarms', error.message, { userId, owner_id: parsed.data.owner_id }, userId, c.req.header('cf-connecting-ip') ?? undefined);
    return c.json({ error: error.message }, 500);
  }

  // Send FCM to partner so their device schedules the alarm locally
  try {
    const partnerId = data.owner_id === userId ? data.created_by : data.owner_id;
    if (partnerId && partnerId !== userId) {
      const adminClient = createClient(
        c.env.SUPABASE_URL,
        c.env.SUPABASE_SERVICE_ROLE_KEY,
        { auth: { persistSession: false } },
      );
      const { data: partnerProfile } = await adminClient
        .from('profiles')
        .select('fcm_token')
        .eq('id', partnerId)
        .single();
      if (partnerProfile?.fcm_token) {
        let sa: ServiceAccount;
        try {
          sa = JSON.parse(c.env.FIREBASE_SERVICE_ACCOUNT_JSON) as ServiceAccount;
        } catch { return c.json(data, 201); }
        await sendFcmNotification(
          c.env, partnerId, sa, partnerProfile.fcm_token,
          'New Alarm', `${data.label} at ${String(data.hour).padStart(2,'0')}:${String(data.minute).padStart(2,'0')}`,
          {
            type: 'alarm',
            action: 'create',
            alarm_id: data.id,
            label: data.label,
            message: data.message ?? 'Wake up!',
            hour: String(data.hour),
            minute: String(data.minute),
            days_of_week: JSON.stringify(data.days_of_week ?? []),
            is_active: String(data.is_active ?? true),
            vibrate: String(data.vibrate ?? true),
            snooze_minutes: String(data.snooze_minutes ?? 5),
          },
        );
      }
    }
  } catch (_) { /* best-effort */ }

  return c.json(data, 201);
});

// PATCH /v1/alarms/:id — update alarm
alarms.patch('/:id', async (c) => {
  const supabase = c.get('supabase');
  const alarmId = c.req.param('id');

  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON' }, 400);
  }

  const parsed = AlarmUpdateSchema.safeParse(body);
  if (!parsed.success) {
    return c.json({ error: 'Invalid body', details: parsed.error.issues }, 400);
  }

  // RLS update policy ensures only owner/creator can update
  const { data, error } = await supabase
    .from('alarms')
    .update(parsed.data)
    .eq('id', alarmId)
    .select()
    .single();

  if (error) return c.json({ error: error.message }, 500);

  // Notify partner about alarm change so they can reschedule/cancel locally
  try {
    const userId = c.get('userId');
    const partnerId = data.owner_id === userId ? data.created_by : data.owner_id;
    if (partnerId && partnerId !== userId) {
      const adminClient = createClient(
        c.env.SUPABASE_URL,
        c.env.SUPABASE_SERVICE_ROLE_KEY,
        { auth: { persistSession: false } },
      );
      const { data: partnerProfile } = await adminClient
        .from('profiles')
        .select('fcm_token')
        .eq('id', partnerId)
        .single();
      if (partnerProfile?.fcm_token) {
        let sa: ServiceAccount;
        try {
          sa = JSON.parse(c.env.FIREBASE_SERVICE_ACCOUNT_JSON) as ServiceAccount;
        } catch { return c.json(data); }
        await sendFcmNotification(
          c.env, partnerId, sa, partnerProfile.fcm_token,
          'Alarm Updated', `${data.label} at ${String(data.hour).padStart(2,'0')}:${String(data.minute).padStart(2,'0')}`,
          {
            type: 'alarm',
            action: 'update',
            alarm_id: data.id,
            label: data.label,
            message: data.message ?? 'Wake up!',
            hour: String(data.hour),
            minute: String(data.minute),
            days_of_week: JSON.stringify(data.days_of_week ?? []),
            is_active: String(data.is_active ?? true),
            vibrate: String(data.vibrate ?? true),
            snooze_minutes: String(data.snooze_minutes ?? 5),
          },
        );
      }
    }
  } catch (_) { /* best-effort */ }

  return c.json(data);
});

// DELETE /v1/alarms/:id — delete alarm
alarms.delete('/:id', async (c) => {
  const supabase = c.get('supabase');
  const alarmId = c.req.param('id');

  // Fetch alarm details before deleting (need partner info for FCM)
  const { data: alarm } = await supabase
    .from('alarms')
    .select('*')
    .eq('id', alarmId)
    .single();

  // RLS delete policy ensures only owner/creator can delete
  const { error } = await supabase.from('alarms').delete().eq('id', alarmId);

  if (error) return c.json({ error: error.message }, 500);

  // Notify partner to cancel the local alarm
  if (alarm) {
    try {
      const userId = c.get('userId');
      const partnerId = alarm.owner_id === userId ? alarm.created_by : alarm.owner_id;
      if (partnerId && partnerId !== userId) {
        const adminClient = createClient(
          c.env.SUPABASE_URL,
          c.env.SUPABASE_SERVICE_ROLE_KEY,
          { auth: { persistSession: false } },
        );
        const { data: partnerProfile } = await adminClient
          .from('profiles')
          .select('fcm_token')
          .eq('id', partnerId)
          .single();
        if (partnerProfile?.fcm_token) {
          let sa: ServiceAccount;
          try {
            sa = JSON.parse(c.env.FIREBASE_SERVICE_ACCOUNT_JSON) as ServiceAccount;
          } catch { return c.json({ ok: true }); }
          await sendFcmNotification(
            c.env, partnerId, sa, partnerProfile.fcm_token,
            'Alarm Deleted', alarm.label,
            {
              type: 'alarm',
              action: 'delete',
              alarm_id: alarm.id,
            },
          );
        }
      }
    } catch (_) { /* best-effort */ }
  }

  return c.json({ ok: true });
});

// ─── Alarm Logs ───────────────────────────────────────────────────────────────

// GET /v1/alarms/logs?alarm_ids=id1,id2&limit=100
alarms.get('/logs', async (c) => {
  const supabase = c.get('supabase');
  const alarmIds = c.req.query('alarm_ids');
  const limit = Math.min(parseInt(c.req.query('limit') ?? '100', 10), 500);

  if (!alarmIds) {
    return c.json({ error: 'alarm_ids query parameter required' }, 400);
  }

  const ids = alarmIds.split(',').filter(Boolean);
  if (ids.length === 0) return c.json([]);

  // RLS on alarm_logs checks that the alarm belongs to the user
  const { data, error } = await supabase
    .from('alarm_logs')
    .select('*')
    .in('alarm_id', ids)
    .order('created_at', { ascending: false })
    .limit(limit);

  if (error) return c.json({ error: error.message }, 500);
  return c.json(data ?? []);
});

// POST /v1/alarms/logs — insert alarm log
alarms.post('/logs', async (c) => {
  const supabase = c.get('supabase');
  const userId = c.get('userId');

  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON' }, 400);
  }

  const parsed = AlarmLogCreateSchema.safeParse(body);
  if (!parsed.success) {
    return c.json({ error: 'Invalid body', details: parsed.error.issues }, 400);
  }

  const insertData = {
    ...parsed.data,
    acted_by: parsed.data.acted_by ?? userId,
  };

  const { data, error } = await supabase
    .from('alarm_logs')
    .insert(insertData)
    .select()
    .single();

  if (error) return c.json({ error: error.message }, 500);
  return c.json(data, 201);
});

// PATCH /v1/alarms/logs/:id — update alarm log reaction
alarms.patch('/logs/:id', async (c) => {
  const supabase = c.get('supabase');
  const logId = c.req.param('id');

  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON' }, 400);
  }

  const parsed = AlarmLogUpdateSchema.safeParse(body);
  if (!parsed.success) {
    return c.json({ error: 'Invalid body', details: parsed.error.issues }, 400);
  }

  const { data, error } = await supabase
    .from('alarm_logs')
    .update(parsed.data)
    .eq('id', logId)
    .select()
    .single();

  if (error) return c.json({ error: error.message }, 500);
  return c.json(data);
});

export default alarms;
