/**
 * Firebase Cloud Messaging HTTP v1 sender.
 *
 * Mints a Google OAuth2 access token using a service account's RSA
 * private key (RS256), then sends a notification via FCM HTTP v1.
 * Tokens are cached until ~5 minutes before expiry.
 *
 * Uses only the Web Crypto API — no external auth libraries.
 */

import type { Env, ServiceAccount } from './types.js';
import { createClient } from '@supabase/supabase-js';

// ─── Base64-URL Encoding ──────────────────────────────────────────────────────

function base64UrlEncode(bytes: Uint8Array): string {
  let str = '';
  for (let i = 0; i < bytes.length; i++) {
    str += String.fromCharCode(bytes[i]!);
  }
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

// ─── RS256 Signing ────────────────────────────────────────────────────────────

async function signRs256(
  privateKeyPem: string,
  input: string,
): Promise<string> {
  const pemBody = privateKeyPem
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(input),
  );
  return base64UrlEncode(new Uint8Array(signature));
}

// ─── OAuth2 Token Cache ───────────────────────────────────────────────────────

interface CachedToken {
  accessToken: string;
  expiresAt: number;
}

let cachedToken: CachedToken | null = null;

/**
 * Mint a Google OAuth2 access token for the service account.
 * Caches until ~5 minutes before expiry.
 */
export async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt - now > 300) {
    return cachedToken.accessToken;
  }

  const header = { alg: 'RS256', typ: 'JWT' };
  const claim = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: sa.token_uri,
    iat: now,
    exp: now + 3600,
  };

  const enc = (obj: unknown) =>
    base64UrlEncode(new TextEncoder().encode(JSON.stringify(obj)));
  const signingInput = enc(header) + '.' + enc(claim);
  const jwt =
    signingInput + '.' + (await signRs256(sa.private_key, signingInput));

  const res = await fetch(sa.token_uri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body:
      'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=' +
      encodeURIComponent(jwt),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`OAuth2 token request failed: ${res.status} ${text}`);
  }

  const body = (await res.json()) as {
    access_token: string;
    expires_in: number;
  };
  cachedToken = {
    accessToken: body.access_token,
    expiresAt: now + body.expires_in,
  };
  return body.access_token;
}

// ─── FCM HTTP v1 Sender ──────────────────────────────────────────────────────

/**
 * Send a notification-style FCM message to a device.
 * Non-fatal errors are thrown — callers decide whether to surface them.
 */
export async function sendFcmNotification(
  env: Env,
  targetUserId: string,
  sa: ServiceAccount,
  fcmToken: string,
  title: string,
  body: string,
  data?: Record<string, string>,
): Promise<{ success: boolean; error?: string }> {
  try {
    const accessToken = await getAccessToken(sa);
    const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

    const res = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token: fcmToken,
          notification: { title, body },
          android: {
            priority: 'high',
            notification: {
              channel_id: 'sync_default',
              click_action: 'FLUTTER_NOTIFICATION_CLICK',
            },
          },
          data: { type: 'nudge', ...data },
        },
      }),
    });

    if (!res.ok) {
      const text = await res.text();
      if (res.status === 404 || text.includes('UNREGISTERED') || text.includes('NOT_FOUND')) {
        try {
          const adminClient = createClient(
            env.SUPABASE_URL,
            env.SUPABASE_SERVICE_ROLE_KEY,
            { auth: { persistSession: false } },
          );
          await adminClient
            .from('profiles')
            .update({ fcm_token: null })
            .eq('id', targetUserId);
        } catch (e) {
          console.warn('[FCM] Failed to clear stale token:', e);
        }
      }
      return { success: false, error: `FCM ${res.status}: ${text}` };
    }

    return { success: true };
  } catch (e) {
    return {
      success: false,
      error: e instanceof Error ? e.message : 'Unknown FCM error',
    };
  }
}
