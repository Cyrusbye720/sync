/**
 * Alarm routes: CRUD for alarms and alarm logs.
 * RLS on the Supabase side ensures users only see alarms they own or created.
 */

import { Hono } from 'hono';
import type { HonoEnv } from '../types.js';
import {
  AlarmCreateSchema,
  AlarmUpdateSchema,
  AlarmLogCreateSchema,
  AlarmLogUpdateSchema,
} from '../schema.js';
import { logError } from '../logger.js';

const alarms = new Hono<HonoEnv>();

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
  return c.json(data);
});

// DELETE /v1/alarms/:id — delete alarm
alarms.delete('/:id', async (c) => {
  const supabase = c.get('supabase');
  const alarmId = c.req.param('id');

  // RLS delete policy ensures only owner/creator can delete
  const { error } = await supabase.from('alarms').delete().eq('id', alarmId);

  if (error) return c.json({ error: error.message }, 500);
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
