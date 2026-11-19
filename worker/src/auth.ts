import { hashToken, generateToken, generateCode } from './crypto.js';
import type { Env, SessionRow } from './types.js';

const SESSION_TTL = 30 * 24 * 60 * 60;
const OAUTH_STATE_TTL = 600;
const LOGIN_CODE_TTL = 300;

export async function startOAuth(
  provider: 'discord' | 'github',
  env: Env,
  workerOrigin: string,
): Promise<Response> {
  const state = generateToken();
  const now = Math.floor(Date.now() / 1000);
  await env.DB.prepare(
    'INSERT INTO oauth_state (state, provider, created_at, expires_at) VALUES (?, ?, ?, ?)',
  ).bind(state, provider, now, now + OAUTH_STATE_TTL).run();

  const redirectUri = `${workerOrigin}/v1/auth/callback`;
  let authorizeUrl: URL;
  if (provider === 'github') {
    if (!env.GITHUB_CLIENT_ID) throw new Error('GITHUB_CLIENT_ID secret is not configured');
    authorizeUrl = new URL('https://github.com/login/oauth/authorize');
    authorizeUrl.searchParams.set('client_id', env.GITHUB_CLIENT_ID);
    authorizeUrl.searchParams.set('redirect_uri', redirectUri);
    authorizeUrl.searchParams.set('scope', 'read:user user:email');
    authorizeUrl.searchParams.set('state', state);
  } else {
    if (!env.DISCORD_CLIENT_ID) throw new Error('DISCORD_CLIENT_ID secret is not configured');
    authorizeUrl = new URL('https://discord.com/oauth2/authorize');
    authorizeUrl.searchParams.set('client_id', env.DISCORD_CLIENT_ID);
    authorizeUrl.searchParams.set('redirect_uri', redirectUri);
    authorizeUrl.searchParams.set('response_type', 'code');
    authorizeUrl.searchParams.set('scope', 'identify email');
    authorizeUrl.searchParams.set('state', state);
  }
  return Response.redirect(authorizeUrl.toString(), 302);
}

async function exchangeProviderProfile(
  provider: 'discord' | 'github',
  code: string,
  redirectUri: string,
  env: Env,
): Promise<{ id: string; username: string; avatarUrl: string | null }> {
  if (provider === 'github') {
    if (!env.GITHUB_CLIENT_ID || !env.GITHUB_CLIENT_SECRET) {
      throw new Error('GitHub OAuth secrets are not configured');
    }
    const tokenRes = await fetch('https://github.com/login/oauth/access_token', {
      method: 'POST',
      headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
      body: JSON.stringify({
        client_id: env.GITHUB_CLIENT_ID,
        client_secret: env.GITHUB_CLIENT_SECRET,
        code,
        redirect_uri: redirectUri,
      }),
    });
    const token = await tokenRes.json() as { access_token?: string; error?: string };
    if (!token.access_token) throw new Error(token.error ?? 'GitHub OAuth failed');
    const headers = { Authorization: `Bearer ${token.access_token}`, 'User-Agent': 'SYNC-App' };
    const user = await (await fetch('https://api.github.com/user', { headers })).json() as {
      id: number; login?: string; name?: string; avatar_url?: string;
    };
    return {
      id: `github:${user.id}`,
      username: user.name || user.login || `GitHub ${user.id}`,
      avatarUrl: user.avatar_url ?? null,
    };
  }

  if (!env.DISCORD_CLIENT_ID || !env.DISCORD_CLIENT_SECRET) {
    throw new Error('Discord OAuth secrets are not configured');
  }
  const tokenRes = await fetch('https://discord.com/api/oauth2/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: env.DISCORD_CLIENT_ID,
      client_secret: env.DISCORD_CLIENT_SECRET,
      grant_type: 'authorization_code',
      code,
      redirect_uri: redirectUri,
    }),
  });
  const token = await tokenRes.json() as { access_token?: string; error?: string };
  if (!token.access_token) throw new Error(token.error ?? 'Discord OAuth failed');
  const user = await (await fetch('https://discord.com/api/users/@me', {
    headers: { Authorization: `Bearer ${token.access_token}` },
  })).json() as { id: string; username?: string; global_name?: string; avatar?: string };
  const avatarUrl = user.avatar
    ? `https://cdn.discordapp.com/avatars/${user.id}/${user.avatar}.png`
    : null;
  return {
    id: `discord:${user.id}`,
    username: user.global_name || user.username || 'Discord User',
    avatarUrl,
  };
}

export async function handleCallback(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const code = url.searchParams.get('code');
  const state = url.searchParams.get('state');
  const errorRedirect = (message: string) => Response.redirect(
    `syncalarm://auth-callback/?error=oauth&error_description=${encodeURIComponent(message)}`,
    302,
  );
  if (!code || !state) return errorRedirect('OAuth callback was incomplete');

  const now = Math.floor(Date.now() / 1000);
  const stateRow = await env.DB.prepare(
    'SELECT provider FROM oauth_state WHERE state = ? AND expires_at > ?',
  ).bind(state, now).first<{ provider: 'discord' | 'github' }>();
  if (!stateRow) return errorRedirect('Sign-in state is invalid or expired');
  await env.DB.prepare('DELETE FROM oauth_state WHERE state = ?').bind(state).run();

  try {
    const redirectUri = `${url.origin}/v1/auth/callback`;
    const profile = await exchangeProviderProfile(stateRow.provider, code, redirectUri, env);
    const existing = await env.DB.prepare(
      'SELECT id FROM users WHERE provider = ? AND provider_id = ?',
    ).bind(stateRow.provider, profile.id).first<{ id: string }>();
    let userId = existing?.id;
    if (!userId) {
      userId = generateToken();
      await env.DB.prepare(
        `INSERT INTO users (id, provider, provider_id, username, avatar_url, timezone, battery_percent, sleep_status, created_at)
         VALUES (?, ?, ?, ?, ?, 'Asia/Kolkata', 100, 'awake', ?)`,
      ).bind(userId, stateRow.provider, profile.id, profile.username, profile.avatarUrl, now).run();
      await env.DB.prepare(
        `INSERT INTO profiles (id, username, avatar_url, timezone, battery_percent, sleep_status, created_at)
         VALUES (?, ?, ?, 'Asia/Kolkata', 100, 'awake', ?)`,
      ).bind(userId, profile.username, profile.avatarUrl, now).run();
    }

    const sessionToken = generateToken();
    const tokenHash = await hashToken(sessionToken);
    await env.DB.prepare(
      `INSERT INTO sessions (token_hash, user_id, sb_access, sb_refresh, created_at, expires_at)
       VALUES (?, ?, '', '', ?, ?)`,
    ).bind(tokenHash, userId, now, now + SESSION_TTL).run();
    await env.SESSIONS.put(tokenHash, JSON.stringify({ user_id: userId }), {
      expirationTtl: SESSION_TTL,
    });

    const loginCode = generateCode();
    await env.DB.prepare(
      'INSERT INTO login_codes (code, token_hash, created_at, expires_at) VALUES (?, ?, ?, ?)',
    ).bind(loginCode, tokenHash, now, now + LOGIN_CODE_TTL).run();

    const deepLink = `syncalarm://auth-callback/?code=${loginCode}`;
    const intentUri = `intent://auth-callback/?code=${loginCode}#Intent;scheme=syncalarm;package=com.sync.alarm;end;`;
    const html = `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>SYNC - Signed in</title></head><body style="background:#FFF8EF;color:#3B2F2A;font-family:system-ui;text-align:center;padding:48px"><h1>You're signed in</h1><p>Opening SYNC...</p><a href="${intentUri}" style="display:inline-block;padding:16px 24px;border-radius:18px;background:#E78372;color:white;text-decoration:none;font-weight:700">Open SYNC</a><script>location.href="${intentUri}";setTimeout(()=>location.href="${deepLink}",250);</script></body></html>`;
    return new Response(html, { headers: { 'Content-Type': 'text/html' } });
  } catch (error) {
    return errorRedirect(error instanceof Error ? error.message : 'OAuth failed');
  }
}

export async function exchangeCode(
  code: string,
  env: Env,
): Promise<{ token: string; userId: string; profile: unknown }> {
  const now = Math.floor(Date.now() / 1000);
  const codeRow = await env.DB.prepare(
    'SELECT token_hash FROM login_codes WHERE code = ? AND expires_at > ?',
  ).bind(code, now).first<{ token_hash: string }>();
  if (!codeRow) throw new Error('Invalid or expired code');
  await env.DB.prepare('DELETE FROM login_codes WHERE code = ?').bind(code).run();
  const session = await env.DB.prepare(
    'SELECT * FROM sessions WHERE token_hash = ? AND expires_at > ?',
  ).bind(codeRow.token_hash, now).first<SessionRow>();
  if (!session) throw new Error('Session not found');
  const newToken = generateToken();
  const newHash = await hashToken(newToken);
  await env.DB.prepare('UPDATE sessions SET token_hash = ? WHERE token_hash = ?')
    .bind(newHash, codeRow.token_hash).run();
  await env.SESSIONS.delete(codeRow.token_hash);
  await env.SESSIONS.put(newHash, JSON.stringify({ user_id: session.user_id }), {
    expirationTtl: SESSION_TTL,
  });
  const profile = await env.DB.prepare(
    'SELECT * FROM profiles WHERE id = ?',
  ).bind(session.user_id).first();
  return { token: newToken, userId: session.user_id, profile };
}

export async function resolveSession(
  token: string,
  env: Env,
): Promise<{ userId: string }> {
  const tokenHash = await hashToken(token);
  const now = Math.floor(Date.now() / 1000);
  const cached = await env.SESSIONS.get(tokenHash);
  if (cached) {
    const data = JSON.parse(cached) as { user_id: string };
    return { userId: data.user_id };
  }
  const row = await env.DB.prepare(
    'SELECT user_id FROM sessions WHERE token_hash = ? AND expires_at > ?',
  ).bind(tokenHash, now).first<{ user_id: string }>();
  if (!row) throw new Error('Invalid session');
  await env.SESSIONS.put(tokenHash, JSON.stringify({ user_id: row.user_id }), {
    expirationTtl: SESSION_TTL,
  });
  return { userId: row.user_id };
}

export async function destroySession(token: string, env: Env): Promise<void> {
  const tokenHash = await hashToken(token);
  await env.DB.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(tokenHash).run();
  await env.SESSIONS.delete(tokenHash);
}

export async function cleanupExpired(env: Env): Promise<void> {
  const now = Math.floor(Date.now() / 1000);
  await env.DB.prepare('DELETE FROM sessions WHERE expires_at < ?').bind(now).run();
  await env.DB.prepare('DELETE FROM oauth_state WHERE expires_at < ?').bind(now).run();
  await env.DB.prepare('DELETE FROM login_codes WHERE expires_at < ?').bind(now).run();
  await env.DB.prepare(
    "DELETE FROM error_logs WHERE created_at < datetime('now', '-30 days')",
  ).run();
}
