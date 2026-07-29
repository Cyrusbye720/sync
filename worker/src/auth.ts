/**
 * OAuth flow + session management.
 *
 * Flow:
 * 1. App opens browser → GET /v1/auth/discord (or github)
 * 2. Worker generates random state, stores in D1, redirects to Supabase OAuth
 * 3. Supabase → Provider → back to Worker: GET /v1/auth/callback?code=...&state=...
 * 4. Worker validates state, exchanges code with Supabase for session tokens
 * 5. Worker encrypts Supabase tokens, generates opaque session token, stores hash in D1
 * 6. Worker generates one-time code, redirects to syncalarm://auth-callback/?code=XXX
 * 7. App intercepts deep link, POSTs code to /v1/auth/exchange
 * 8. Worker validates code, returns opaque session token + userId + profile
 */

import { createClient } from '@supabase/supabase-js';
import {
  hashToken,
  generateToken,
  generateCode,
  generateCodeVerifier,
  generateCodeChallenge,
  encryptToken,
  decryptToken,
} from './crypto.js';
import type { Env, SessionRow } from './types.js';

// ─── JWT Helpers ──────────────────────────────────────────────────────────────

/**
 * Decode a JWT payload without verifying the signature.
 * Returns null if the token is malformed.
 */
function decodeJwtPayload(token: string): Record<string, unknown> | null {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    const payload = parts[1]!.replace(/-/g, '+').replace(/_/g, '/');
    const decoded = atob(payload);
    return JSON.parse(decoded) as Record<string, unknown>;
  } catch {
    return null;
  }
}

/**
 * Check if a Supabase JWT is expired (or will expire within 60 seconds).
 */
function isTokenExpired(accessToken: string): boolean {
  const payload = decodeJwtPayload(accessToken);
  if (!payload || typeof payload.exp !== 'number') return true;
  // Refresh 60 seconds before expiry to avoid race conditions
  return payload.exp <= Math.floor(Date.now() / 1000) + 60;
}

/**
 * Refresh a Supabase access token using the refresh token.
 * Returns new access and refresh tokens, or null on failure.
 */
async function refreshSupabaseToken(
  env: Env,
  refreshToken: string,
): Promise<{ access_token: string; refresh_token: string } | null> {
  const res = await fetch(`${env.SUPABASE_URL}/auth/v1/token?grant_type=refresh_token`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: env.SUPABASE_ANON_KEY,
    },
    body: JSON.stringify({ refresh_token: refreshToken }),
  });

  if (!res.ok) return null;
  const data = (await res.json()) as { access_token?: string; refresh_token?: string };
  if (!data.access_token || !data.refresh_token) return null;
  return { access_token: data.access_token, refresh_token: data.refresh_token };
}

const SESSION_TTL = 30 * 24 * 60 * 60; // 30 days in seconds
const OAUTH_STATE_TTL = 600;            // 10 minutes
const LOGIN_CODE_TTL = 300;             // 5 minutes

/**
 * Start OAuth flow: generate state, redirect to Supabase OAuth URL.
 */
export async function startOAuth(
  provider: 'discord' | 'github',
  env: Env,
  workerOrigin: string,
): Promise<Response> {
  const state = generateToken(); // random 256-bit
  const codeVerifier = generateCodeVerifier();
  const codeChallenge = await generateCodeChallenge(codeVerifier);
  const now = Math.floor(Date.now() / 1000);

  await env.DB.prepare(
    'INSERT INTO oauth_state (state, provider, created_at, expires_at) VALUES (?, ?, ?, ?)',
  )
    .bind(state, provider, now, now + OAUTH_STATE_TTL)
    .run();

  // Store code verifier alongside state for PKCE exchange
  await env.DB.prepare(
    'INSERT INTO oauth_state (state, provider, created_at, expires_at) VALUES (?, ?, ?, ?)',
  )
    .bind(`pkce:${codeVerifier}`, provider, now, now + OAUTH_STATE_TTL)
    .run();

  const callbackUrl = `${workerOrigin}/v1/auth/callback?app_state=${state}&cv=${codeVerifier}`;
  const supabaseAuthUrl =
    `${env.SUPABASE_URL}/auth/v1/authorize?` +
    new URLSearchParams({
      provider,
      redirect_to: callbackUrl,
      code_challenge: codeChallenge,
      code_challenge_method: 'S256',
    }).toString();

  return Response.redirect(supabaseAuthUrl, 302);
}

/**
 * Handle OAuth callback from Supabase.
 * Validates state, exchanges code for session, creates Worker session.
 */
export async function handleCallback(
  request: Request,
  env: Env,
): Promise<Response> {
  const url = new URL(request.url);
  const code = url.searchParams.get('code');
  const state = url.searchParams.get('app_state');
  const codeVerifier = url.searchParams.get('cv');

  if (!code || !state) {
    return new Response('Missing code or state', { status: 400 });
  }

  // Validate and consume OAuth state (one-time use)
  const now = Math.floor(Date.now() / 1000);
  const stateRow = await env.DB.prepare(
    'SELECT * FROM oauth_state WHERE state = ? AND expires_at > ?',
  )
    .bind(state, now)
    .first();

  if (!stateRow) {
    return new Response('Invalid or expired OAuth state', { status: 400 });
  }

  // Delete state immediately (replay protection)
  await env.DB.prepare('DELETE FROM oauth_state WHERE state = ?')
    .bind(state)
    .run();

  // Exchange code with Supabase for session using PKCE
  const tokenRes = await fetch(
    `${env.SUPABASE_URL}/auth/v1/token?grant_type=pkce`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: env.SUPABASE_ANON_KEY,
      },
      body: JSON.stringify({
        auth_code: code,
        code_verifier: codeVerifier,
      }),
    },
  );

  const tokenData = await tokenRes.json() as {
    access_token?: string;
    refresh_token?: string;
    user?: { id: string };
    error?: string;
  };

  if (!tokenRes.ok || !tokenData.access_token || !tokenData.user) {
    return new Response(
      `Failed to exchange OAuth code: ${tokenData.error || 'unknown'}`,
      { status: 401 },
    );
  }

  const userId = tokenData.user.id;

  // Generate opaque session token and encrypt Supabase tokens
  const sessionToken = generateToken();
  const tokenHash = await hashToken(sessionToken);
  const encAccess = await encryptToken(
    tokenData.access_token,
    env.SESSION_ENCRYPTION_KEY,
  );
  const encRefresh = await encryptToken(
    tokenData.refresh_token ?? '',
    env.SESSION_ENCRYPTION_KEY,
  );

  // Store session in D1
  await env.DB.prepare(
    `INSERT INTO sessions (token_hash, user_id, sb_access, sb_refresh, created_at, expires_at)
     VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT(token_hash) DO UPDATE SET
       sb_access = excluded.sb_access,
       sb_refresh = excluded.sb_refresh,
       expires_at = excluded.expires_at`,
  )
    .bind(tokenHash, userId, encAccess, encRefresh, now, now + SESSION_TTL)
    .run();

  // Also cache in KV for fast lookups
  await env.SESSIONS.put(
    tokenHash,
    JSON.stringify({ user_id: userId, sb_access: encAccess, sb_refresh: encRefresh }),
    { expirationTtl: SESSION_TTL },
  );

  // Generate one-time login code
  const loginCode = generateCode();
  await env.DB.prepare(
    'INSERT INTO login_codes (code, token_hash, created_at, expires_at) VALUES (?, ?, ?, ?)',
  )
    .bind(loginCode, tokenHash, now, now + LOGIN_CODE_TTL)
    .run();

  // Redirect to app deep link with one-time code.
  // Browsers cannot follow 302 redirects to custom schemes (syncalarm://),
  // so we serve an HTML page that triggers the deep link via JavaScript.
  const deepLink = `syncalarm://auth-callback/?code=${loginCode}`;
  const html = `<!DOCTYPE html>
<html><head><title>SYNC</title></head>
<body style="background:#000;color:#fff;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0">
<script>window.location=${JSON.stringify(deepLink)};</script>
<div style="text-align:center">
<p style="font-size:24px;margin-bottom:24px">Redirecting to SYNC app...</p>
<a href="${deepLink}" style="display:inline-block;padding:16px 48px;background:#fff;color:#000;font-size:20px;font-weight:bold;border-radius:4px;text-decoration:none">Open SYNC</a>
<p style="margin-top:16px;font-size:14px;color:#888">If the app doesn't open, tap the button above</p>
</div>
</body></html>`;
  return new Response(html, {
    status: 200,
    headers: { 'Content-Type': 'text/html' },
  });
}

/**
 * Exchange one-time code for opaque session token.
 * Returns { token, userId, profile }.
 */
export async function exchangeCode(
  code: string,
  env: Env,
): Promise<{ token: string; userId: string; profile: unknown }> {
  const now = Math.floor(Date.now() / 1000);

  // Validate and consume login code (one-time use)
  const codeRow = await env.DB.prepare(
    'SELECT * FROM login_codes WHERE code = ? AND expires_at > ?',
  )
    .bind(code, now)
    .first<{ code: string; token_hash: string }>();

  if (!codeRow) {
    throw new Error('Invalid or expired code');
  }

  // Delete code immediately (replay protection)
  await env.DB.prepare('DELETE FROM login_codes WHERE code = ?')
    .bind(code)
    .run();

  // Look up session by token hash
  const session = await env.DB.prepare(
    'SELECT * FROM sessions WHERE token_hash = ? AND expires_at > ?',
  )
    .bind(codeRow.token_hash, now)
    .first<SessionRow>();

  if (!session) {
    throw new Error('Session not found');
  }

  // Decrypt Supabase access token to fetch profile
  const sbAccess = await decryptToken(session.sb_access, env.SESSION_ENCRYPTION_KEY);
  const supabase = createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${sbAccess}` } },
  });

  const { data: profile } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', session.user_id)
    .single();

  // Reverse the hash to find the original token — we can't, so we regenerate
  // and update. Actually, we need to return a token the client can use.
  // The token_hash in D1 is the hash of the real token. We need to return
  // the real token. Since we can't reverse the hash, we generate a new token
  // and update the session record.
  const newToken = generateToken();
  const newHash = await hashToken(newToken);

  await env.DB.prepare(
    `UPDATE sessions SET token_hash = ? WHERE token_hash = ?`,
  )
    .bind(newHash, codeRow.token_hash)
    .run();

  // Update KV cache
  await env.SESSIONS.delete(codeRow.token_hash);
  await env.SESSIONS.put(
    newHash,
    JSON.stringify({
      user_id: session.user_id,
      sb_access: session.sb_access,
      sb_refresh: session.sb_refresh,
    }),
    { expirationTtl: SESSION_TTL },
  );

  // Update login_codes references if any remain
  await env.DB.prepare(
    'UPDATE login_codes SET token_hash = ? WHERE token_hash = ?',
  )
    .bind(newHash, codeRow.token_hash)
    .run();

  return {
    token: newToken,
    userId: session.user_id,
    profile,
  };
}

/**
 * Resolve an opaque session token into a user context with a
 * Supabase client authenticated as that user (for RLS).
 *
 * If the stored Supabase access token is expired, automatically
 * refreshes it using the stored refresh token and persists the
 * new tokens in D1 + KV.
 */
export async function resolveSession(
  token: string,
  env: Env,
): Promise<{ userId: string; supabase: ReturnType<typeof createClient> }> {
  const tokenHash = await hashToken(token);
  const now = Math.floor(Date.now() / 1000);

  // Try KV cache first
  const cached = await env.SESSIONS.get(tokenHash);
  let sessionData: { user_id: string; sb_access: string; sb_refresh: string };

  if (cached) {
    sessionData = JSON.parse(cached);
  } else {
    // Fall back to D1
    const row = await env.DB.prepare(
      'SELECT * FROM sessions WHERE token_hash = ? AND expires_at > ?',
    )
      .bind(tokenHash, now)
      .first<SessionRow>();

    if (!row) {
      throw new Error('Invalid session');
    }

    sessionData = {
      user_id: row.user_id,
      sb_access: row.sb_access,
      sb_refresh: row.sb_refresh,
    };

    // Re-cache in KV
    await env.SESSIONS.put(tokenHash, JSON.stringify(sessionData), {
      expirationTtl: SESSION_TTL,
    });
  }

  // Decrypt the Supabase access token
  let sbAccess = await decryptToken(
    sessionData.sb_access,
    env.SESSION_ENCRYPTION_KEY,
  );

  // If the Supabase access token is expired, refresh it
  if (isTokenExpired(sbAccess)) {
    const sbRefresh = await decryptToken(
      sessionData.sb_refresh,
      env.SESSION_ENCRYPTION_KEY,
    );

    if (sbRefresh) {
      const refreshed = await refreshSupabaseToken(env, sbRefresh);
      if (refreshed) {
        sbAccess = refreshed.access_token;

        // Re-encrypt and persist the new tokens
        const newEncAccess = await encryptToken(
          refreshed.access_token,
          env.SESSION_ENCRYPTION_KEY,
        );
        const newEncRefresh = await encryptToken(
          refreshed.refresh_token,
          env.SESSION_ENCRYPTION_KEY,
        );

        sessionData.sb_access = newEncAccess;
        sessionData.sb_refresh = newEncRefresh;

        // Update D1
        await env.DB.prepare(
          'UPDATE sessions SET sb_access = ?, sb_refresh = ? WHERE token_hash = ?',
        )
          .bind(newEncAccess, newEncRefresh, tokenHash)
          .run();

        // Update KV cache
        await env.SESSIONS.put(tokenHash, JSON.stringify(sessionData), {
          expirationTtl: SESSION_TTL,
        });
      }
    }
  }

  // Create a Supabase client authenticated as this user
  const supabase = createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${sbAccess}` } },
  });

  return { userId: sessionData.user_id, supabase };
}

/**
 * Destroy a session (logout).
 */
export async function destroySession(
  token: string,
  env: Env,
): Promise<void> {
  const tokenHash = await hashToken(token);
  await env.DB.prepare('DELETE FROM sessions WHERE token_hash = ?')
    .bind(tokenHash)
    .run();
  await env.SESSIONS.delete(tokenHash);
}

/**
 * Clean up expired rows (call periodically via cron or on request).
 */
export async function cleanupExpired(env: Env): Promise<void> {
  const now = Math.floor(Date.now() / 1000);
  await env.DB.prepare('DELETE FROM sessions WHERE expires_at < ?')
    .bind(now)
    .run();
  await env.DB.prepare('DELETE FROM oauth_state WHERE expires_at < ?')
    .bind(now)
    .run();
  await env.DB.prepare('DELETE FROM login_codes WHERE expires_at < ?')
    .bind(now)
    .run();
}
