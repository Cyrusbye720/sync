/**
 * Hono middleware: authentication, rate limiting, security headers.
 */

import { createMiddleware } from 'hono/factory';
import type { HonoEnv } from './types.js';
import { resolveSession } from './auth.js';
import { logError } from './logger.js';

// ─── Authentication Middleware ────────────────────────────────────────────────

/**
 * Extracts Bearer token from Authorization header, resolves session,
 * and injects userId + supabase client into Hono context.
 */
export const authenticate = createMiddleware<HonoEnv>(async (c, next) => {
  const auth = c.req.header('authorization');
  if (!auth || !auth.startsWith('Bearer ')) {
    return c.json({ error: 'Missing authorization' }, 401);
  }

  const token = auth.substring(7);
  if (!token || token.length < 32) {
    return c.json({ error: 'Invalid token format' }, 401);
  }

  try {
    const { userId, supabase } = await resolveSession(token, c.env);
    c.set('userId', userId);
    c.set('supabase', supabase);
  } catch (e) {
    await logError(c.env, 'authenticate', e instanceof Error ? e.message : 'Auth failed', undefined, undefined, c.req.header('cf-connecting-ip') ?? undefined);
    return c.json({ error: 'Invalid or expired session' }, 401);
  }

  await next();
});

// ─── Rate Limiting ────────────────────────────────────────────────────────────

/**
 * Simple in-memory sliding window rate limiter.
 * Resets when the Worker isolate recycles (acceptable for edge rate limiting).
 */
const rateBuckets = new Map<string, { count: number; resetAt: number }>();

export function rateLimit(maxRequests: number, windowSeconds: number) {
  return createMiddleware<HonoEnv>(async (c, next) => {
    // Use token hash or IP as key
    const auth = c.req.header('authorization') ?? '';
    const ip = c.req.header('cf-connecting-ip') ?? 'unknown';
    const key = auth ? auth.substring(0, 40) : ip;

    const now = Date.now();
    const bucket = rateBuckets.get(key);

    if (!bucket || now > bucket.resetAt) {
      rateBuckets.set(key, {
        count: 1,
        resetAt: now + windowSeconds * 1000,
      });
    } else {
      bucket.count++;
      if (bucket.count > maxRequests) {
        return c.json(
          { error: 'Rate limit exceeded' },
          { status: 429, headers: { 'Retry-After': String(windowSeconds) } },
        );
      }
    }

    // Periodically evict expired entries (every ~100 requests)
    if (rateBuckets.size > 100 && Math.random() < 0.01) {
      for (const [k, v] of rateBuckets) {
        if (now > v.resetAt) rateBuckets.delete(k);
      }
    }

    await next();
  });
}

// ─── Security Headers ─────────────────────────────────────────────────────────

export const secureHeaders = createMiddleware<HonoEnv>(async (c, next) => {
  // Enforce request size limit (1MB)
  const contentLength = c.req.header('content-length');
  if (contentLength && parseInt(contentLength, 10) > 1_048_576) {
    return c.json({ error: 'Request too large' }, 413);
  }

  await next();

  // Add security headers to response
  c.res.headers.set('X-Content-Type-Options', 'nosniff');
  c.res.headers.set('X-Frame-Options', 'DENY');
  c.res.headers.set('X-XSS-Protection', '0');
  c.res.headers.set(
    'Strict-Transport-Security',
    'max-age=63072000; includeSubDomains; preload',
  );
  c.res.headers.set('Referrer-Policy', 'strict-origin-when-cross-origin');
  c.res.headers.set(
    'Content-Security-Policy',
    "default-src 'none'; frame-ancestors 'none'",
  );
});
