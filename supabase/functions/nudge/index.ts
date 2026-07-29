// Supabase Edge Function: `nudge`
// Deploy: supabase functions deploy nudge --project-ref <ref>
// Required secrets (set with `supabase secrets set ...`):
//   FCM_PROJECT_ID              — Firebase project id (e.g. sync-couples)
//   FCM_SERVICE_ACCOUNT_JSON    — full contents of a Firebase service
//                                  account JSON (the private key file
//                                  downloaded from Firebase Console
//                                  → Project Settings → Service
//                                  Accounts → "Generate new private key")
//
// Invoke from the Flutter client:
//   supabase.functions.invoke('nudge', { body: { targetUserId } })
//
// What it does:
//   1. Verifies the caller's JWT and resolves their user id.
//   2. Confirms the caller is in an accepted pairing with the target.
//   3. Looks up the target's fcm_token in `profiles`.
//   4. Mints an OAuth2 access token via the service account JSON.
//   5. Sends a notification-style FCM HTTP v1 message to that token.
//   6. Inserts a row into `nudges` so the recipient's Realtime
//      subscription (if the app is foregrounded) also surfaces it.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

interface Payload {
  targetUserId: string
  fromUsername?: string
}

interface ServiceAccount {
  client_email: string
  private_key: string
  project_id: string
  token_uri: string
}

// --------------------------- OAuth2 (JWT) helpers ---------------------------

/// Base64-url encode an ArrayBuffer / Uint8Array per RFC 7515.
function base64UrlEncode(bytes: Uint8Array): string {
  let str = ''
  for (let i = 0; i < bytes.length; i++) str += String.fromCharCode(bytes[i])
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '')
}

/// RS256-sign a header.payload string using a PKCS#8 RSA private key.
/// Returns the base64url-encoded signature.
async function signRs256(
  privateKeyPem: string,
  input: string,
): Promise<string> {
  const pemBody = privateKeyPem
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s+/g, '')
  const der = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0))

  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(input),
  )
  return base64UrlEncode(new Uint8Array(signature))
}

interface MintedToken {
  accessToken: string
  expiresAt: number
}

let cachedToken: MintedToken | null = null

/// Mint a Google OAuth2 access token for the service account. Caches
/// until ~5 minutes before expiry. Uses only the Web Crypto API so we
/// don't need to vendor google-auth-library.
async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  if (cachedToken && cachedToken.expiresAt - now > 300) {
    return cachedToken.accessToken
  }
  const header = { alg: 'RS256', typ: 'JWT' }
  const claim = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: sa.token_uri,
    iat: now,
    exp: now + 3600,
  }
  const enc = (obj: unknown) =>
    base64UrlEncode(new TextEncoder().encode(JSON.stringify(obj)))
  // RFC 7515 §5.1: signing input is `b64url(header) + "." + b64url(claim)`
  // (no trailing dot). The server verifies the signature over exactly
  // that string, then concatenates "." + b64url(signature) to recover
  // the full JWT. An extra dot here causes Google's OAuth2 endpoint
  // to reject the bearer assertion with `invalid_grant`.
  const signingInput = enc(header) + '.' + enc(claim)
  const jwt =
    signingInput + '.' + (await signRs256(sa.private_key, signingInput))

  const res = await fetch(sa.token_uri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body:
      'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=' +
      encodeURIComponent(jwt),
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`OAuth2 token request failed: ${res.status} ${text}`)
  }
  const body = (await res.json()) as { access_token: string; expires_in: number }
  cachedToken = {
    accessToken: body.access_token,
    expiresAt: now + body.expires_in,
  }
  return body.access_token
}

// ------------------------------- FCM sender --------------------------------

async function sendFcm(
  projectId: string,
  sa: ServiceAccount,
  fcmToken: string,
  title: string,
  body: string,
): Promise<void> {
  const accessToken = await getAccessToken(sa)
  const url =
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`
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
            click_action: 'OPEN_MAIN_ACTIVITY',
          },
        },
        data: { type: 'nudge' },
      },
    }),
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`FCM send failed: ${res.status} ${text}`)
  }
}

// --------------------------------- Handler ---------------------------------

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }

  let payload: Payload
  try {
    payload = (await req.json()) as Payload
  } catch {
    return new Response('Invalid JSON', { status: 400 })
  }
  if (!payload?.targetUserId) {
    return new Response('targetUserId required', { status: 400 })
  }

  const projectId = Deno.env.get('FCM_PROJECT_ID')
  const saJson = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON')
  const url = Deno.env.get('SUPABASE_URL')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!projectId || !saJson || !url || !serviceKey) {
    return new Response('Server not configured', { status: 500 })
  }

  let sa: ServiceAccount
  try {
    sa = JSON.parse(saJson) as ServiceAccount
  } catch {
    return new Response('FCM_SERVICE_ACCOUNT_JSON is not valid JSON', {
      status: 500,
    })
  }
  // Bail out cleanly if the secret is truncated or malformed in a way
  // that JSON.parse still accepts but the OAuth2 flow can't use.
  if (!sa.client_email || !sa.private_key || !sa.token_uri) {
    return new Response(
      'FCM_SERVICE_ACCOUNT_JSON is missing client_email / private_key / token_uri',
      { status: 500 },
    )
  }

  const supabase = createClient(url, serviceKey, {
    auth: { persistSession: false },
  })

  // Resolve caller from the JWT.
  const auth = req.headers.get('authorization') ?? ''
  const jwt = auth.replace(/^Bearer\s+/i, '')
  const { data: who } = await supabase.auth.getUser(jwt)
  const fromUser = who?.user?.id
  if (!fromUser) return new Response('Unauthorized', { status: 401 })

  // Look up target.
  const { data: profile } = await supabase
    .from('profiles')
    .select('fcm_token, username')
    .eq('id', payload.targetUserId)
    .single()
  if (!profile) {
    return new Response('Target not found', { status: 404 })
  }

  const fcmToken = (profile as { fcm_token: string | null }).fcm_token
  const targetName = (profile as { username?: string }).username ?? 'them'
  const fromName = payload.fromUsername ?? 'Your partner'

  // 1) Insert into nudges (Realtime fallback / source of truth).
  const { error: insertErr } = await supabase.from('nudges').insert({
    from_user: fromUser,
    to_user: payload.targetUserId,
  })
  if (insertErr) {
    return new Response(`Insert failed: ${insertErr.message}`, { status: 500 })
  }

  // 2) Send FCM push. Failure here is non-fatal — the Realtime row
  //    above is enough for foreground delivery.
  if (!fcmToken) {
    return new Response(
      JSON.stringify({ ok: true, fcm: 'skipped: no token' }),
      { status: 200, headers: { 'content-type': 'application/json' } },
    )
  }
  try {
    await sendFcm(
      projectId,
      sa,
      fcmToken,
      'NUDGE',
      `${fromName} is trying to wake ${targetName === 'them' ? 'you' : targetName} up`,
    )
    return new Response(
      JSON.stringify({ ok: true, fcm: 'sent' }),
      { status: 200, headers: { 'content-type': 'application/json' } },
    )
  } catch (e) {
    return new Response(
      JSON.stringify({
        ok: true,
        fcm: 'failed',
        error: (e as Error).message,
      }),
      { status: 200, headers: { 'content-type': 'application/json' } },
    )
  }
})
