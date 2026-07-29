/**
 * Announcements route — broadcast notifications to users.
 *
 * POST /v1/announcements — send an announcement (admin-only via shared secret)
 * GET  /v1/announcements — list recent announcements (authenticated users)
 *
 * Announcements are delivered via:
 * 1. Stored in D1 so users can fetch them on app open
 * 2. WebSocket broadcast to all connected clients
 * 3. FCM push to all paired users (best-effort)
 */

import { Hono } from 'hono';
import { createClient } from '@supabase/supabase-js';
import type { HonoEnv, ServiceAccount } from '../types.js';
import { fanOutAnnouncement } from '../websocket.js';
import { sendFcmNotification } from '../fcm.js';
import { logEvent } from '../logger.js';

const announcements = new Hono<HonoEnv>();

// POST /v1/announcements — send an announcement
announcements.post('/', async (c) => {
  const authHeader = c.req.header('authorization');
  const secret = c.req.header('x-admin-secret');

  // Allow either bearer token (authenticated user) or admin secret
  const isAdmin = secret === c.env.ADMIN_SECRET;
  let userId: string | null = null;

  if (!isAdmin) {
    // If no admin secret, require auth
    if (!authHeader?.startsWith('Bearer ')) {
      return c.json({ error: 'Unauthorized' }, 401);
    }
    try {
      userId = c.get('userId') as string | undefined ?? null;
    } catch {
      // Not authenticated
    }
    if (!userId) {
      return c.json({ error: 'Unauthorized' }, 401);
    }
  }

  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON' }, 400);
  }

  const { title, body: content, type = 'info', target = 'all', expires_at } = (body ?? {}) as {
    title?: string;
    body?: string;
    type?: string;
    target?: string;
    expires_at?: string;
  };

  if (!title || !content) {
    return c.json({ error: 'title and body are required' }, 400);
  }

  if (!['info', 'warning', 'update', 'alert'].includes(type)) {
    return c.json({ error: 'Invalid type' }, 400);
  }

  if (!['all', 'paired', 'single'].includes(target)) {
    return c.json({ error: 'Invalid target' }, 400);
  }

  // Store announcement in D1
  let announcementId: number;
  try {
    const result = await c.env.DB.prepare(
      `INSERT INTO announcements (title, body, type, target, created_by, expires_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    )
      .bind(title, content, type, target, userId, expires_at ?? null)
      .run();

    announcementId = result.meta.last_row_id as number;
  } catch (e) {
    await logEvent(c.env, {
      level: 'error',
      route: 'POST /v1/announcements',
      message: 'Failed to store announcement',
      details: e instanceof Error ? e.message : e,
      userId: userId ?? undefined,
    });
    return c.json({ error: 'Failed to store announcement' }, 500);
  }

  // Fan out via WebSocket to all connected clients
  const announcementData = {
    id: announcementId,
    title,
    body: content,
    type,
    target,
    sent_at: new Date().toISOString(),
    expires_at: expires_at ?? null,
  };

  fanOutAnnouncement(announcementData);

  // Best-effort FCM push to paired users
  let fcmResult = 'skipped';
  try {
    const adminClient = createClient(
      c.env.SUPABASE_URL,
      c.env.SUPABASE_SERVICE_ROLE_KEY,
      { auth: { persistSession: false } },
    );

    // Get all profiles with FCM tokens
    const { data: profiles } = await adminClient
      .from('profiles')
      .select('fcm_token')
      .not('fcm_token', 'is', null);

    if (profiles && profiles.length > 0) {
      let sa: ServiceAccount;
      try {
        sa = JSON.parse(c.env.FIREBASE_SERVICE_ACCOUNT_JSON) as ServiceAccount;
      } catch {
        fcmResult = 'invalid_sa';
        return c.json({
          ok: true,
          announcement_id: announcementId,
          fcm: fcmResult,
        });
      }

      let sent = 0;
      for (const p of profiles) {
        if (p.fcm_token) {
          const result = await sendFcmNotification(
            sa,
            p.fcm_token,
            title,
            content,
          );
          if (result.success) sent++;
        }
      }
      fcmResult = `sent_${sent}_of_${profiles.length}`;
    }
  } catch {
    // FCM is best-effort
  }

  await logEvent(c.env, {
    level: 'info',
    route: 'POST /v1/announcements',
    message: `Announcement sent: ${title}`,
    details: { id: announcementId, fcm: fcmResult },
    userId: userId ?? undefined,
  });

  return c.json({
    ok: true,
    announcement_id: announcementId,
    fcm: fcmResult,
  });
});

// GET /v1/announcements — list recent announcements
announcements.get('/', async (c) => {
  const limit = Math.min(parseInt(c.req.query('limit') ?? '20', 10) || 20, 100);
  const now = new Date().toISOString();

  const { results, error } = await c.env.DB.prepare(
    `SELECT * FROM announcements
     WHERE expires_at IS NULL OR expires_at > ?
     ORDER BY sent_at DESC
     LIMIT ?`,
  )
    .bind(now, limit)
    .all();

  if (error) {
    return c.json({ error: error.message }, 500);
  }

  return c.json(results ?? []);
});

// DELETE /v1/announcements/:id — delete an announcement (admin only)
announcements.delete('/:id', async (c) => {
  const secret = c.req.header('x-admin-secret');
  if (secret !== c.env.ADMIN_SECRET) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const id = c.req.param('id');
  const { error } = await c.env.DB.prepare(
    'DELETE FROM announcements WHERE id = ?',
  )
    .bind(id)
    .run();

  if (error) return c.json({ error: error.message }, 500);
  return c.json({ ok: true });
});

export default announcements;
