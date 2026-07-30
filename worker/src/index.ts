/**
 * SYNC API — Cloudflare Worker entry point.
 *
 * All Flutter app traffic flows through this Worker.
 * Supabase and Firebase credentials never leave the Worker.
 */

import { Hono } from 'hono';
import { cors } from 'hono/cors';
import type { HonoEnv } from './types.js';
import { authenticate, rateLimit, secureHeaders } from './middleware.js';
import {
  startOAuth,
  handleCallback,
  exchangeCode,
  destroySession,
  cleanupExpired,
} from './auth.js';
import { logError } from './logger.js';
import { CodeExchangeSchema } from './schema.js';
import { handleWebSocketUpgrade, getConnectionCount } from './websocket.js';
import profileRoutes from './routes/profile.js';
import pairingRoutes from './routes/pairings.js';
import alarmRoutes from './routes/alarms.js';
import nudgeRoutes from './routes/nudges.js';
import adminRoutes from './routes/admin.js';
import announcementRoutes from './routes/announcements.js';

const app = new Hono<HonoEnv>();

// ─── Global Middleware ────────────────────────────────────────────────────────

app.use('*', secureHeaders);
app.use(
  '*',
  cors({
    origin: '*', // Mobile app — no browser origin
    allowMethods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
    allowHeaders: ['Authorization', 'Content-Type', 'X-Admin-Secret'],
    maxAge: 86400,
  }),
);

// ─── Public Routes ────────────────────────────────────────────────────────────

// Health check
app.get('/v1/health', (c) =>
  c.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    connections: getConnectionCount(),
  }),
);

// OAuth start (rate-limited)
app.use('/v1/auth/*', rateLimit(30, 60));

app.get('/v1/auth/discord', (c) => {
  const origin = new URL(c.req.url).origin;
  return startOAuth('discord', c.env, origin);
});

app.get('/v1/auth/github', (c) => {
  const origin = new URL(c.req.url).origin;
  return startOAuth('github', c.env, origin);
});

// OAuth callback (from Supabase)
app.get('/v1/auth/callback', (c) => handleCallback(c.req.raw, c.env));

// Exchange one-time code for session token
app.post('/v1/auth/exchange', async (c) => {
  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON' }, 400);
  }

  const parsed = CodeExchangeSchema.safeParse(body);
  if (!parsed.success) {
    return c.json({ error: 'Invalid body', details: parsed.error.issues }, 400);
  }

  try {
    const result = await exchangeCode(parsed.data.code, c.env);
    return c.json(result);
  } catch (e) {
    await logError(c.env, 'POST /v1/auth/exchange', e instanceof Error ? e.message : 'Exchange failed');
    return c.json(
      { error: e instanceof Error ? e.message : 'Exchange failed' },
      401,
    );
  }
});

// ─── Admin Routes (no auth middleware, uses x-admin-secret) ───────────────────

app.route('/v1/admin', adminRoutes);

// Announcements (supports both admin secret and bearer token, no auth middleware)
app.route('/v1/announcements', announcementRoutes);

// ─── Authenticated Routes ─────────────────────────────────────────────────────

// Apply auth middleware to all /v1/* routes below
app.use('/v1/profile*', authenticate);
app.use('/v1/pairings*', authenticate);
app.use('/v1/alarms*', authenticate);
app.use('/v1/nudges*', authenticate);

// Apply rate limiting (high limits for realtime couple interactions)
app.use('/v1/nudges*', rateLimit(120, 60));
app.use('/v1/pairings*', rateLimit(60, 60));
app.use('/v1/alarms*', rateLimit(100, 60));
app.use('/v1/profile*', rateLimit(100, 60));

// Mount route groups
app.route('/v1/profile', profileRoutes);
app.route('/v1/pairings', pairingRoutes);
app.route('/v1/alarms', alarmRoutes);
app.route('/v1/nudges', nudgeRoutes);

// Logout
app.post('/v1/auth/logout', async (c) => {
  const auth = c.req.header('authorization');
  if (auth?.startsWith('Bearer ')) {
    const token = auth.substring(7);
    await destroySession(token, c.env);
  }
  return c.json({ ok: true });
});

// WebSocket upgrade
app.get('/v1/events', (c) => handleWebSocketUpgrade(c.req.raw, c.env));

// ─── Scheduled (Cron) ─────────────────────────────────────────────────────────

// Clean up expired sessions, OAuth state, login codes, and old logs
// Configure in wrangler.toml: [triggers] crons = ["0 */6 * * *"]

// ─── 404 Handler ──────────────────────────────────────────────────────────────

app.notFound((c) =>
  c.json({ error: 'Not found' }, 404),
);

// ─── Error Handler ────────────────────────────────────────────────────────────

app.onError(async (err, c) => {
  // Never leak internal error details
  await logError(
    c.env,
    `${c.req.method} ${new URL(c.req.url).pathname}`,
    err.message,
    { stack: err.stack },
    undefined,
    c.req.header('cf-connecting-ip') ?? undefined,
  );
  return c.json({ error: 'Internal server error' }, 500);
});

// ─── Export ───────────────────────────────────────────────────────────────────

export default {
  fetch: app.fetch,
  async scheduled(event: ScheduledEvent, env: unknown, ctx: ExecutionContext) {
    ctx.waitUntil(cleanupExpired(env as import('./types.js').Env));
  },
};
