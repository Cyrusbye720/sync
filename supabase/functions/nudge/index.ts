// Supabase Edge Function: `nudge`
// Deploy: supabase functions deploy nudge --project-ref <ref>
// Required secrets:
//   FCM_SERVER_KEY (legacy FCM API, see REAME)
//
// Invoke from the Flutter client via:
//   supabase.functions.invoke('nudge', { body: { targetUserId, fromUsername } })

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

interface Payload {
  targetUserId: string
  fromUsername: string
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }

  let body: Payload
  try {
    body = await req.json()
  } catch {
    return new Response('Invalid JSON', { status: 400 })
  }

  if (!body?.targetUserId || !body?.fromUsername) {
    return new Response('Missing fields', { status: 400 })
  }

  const url = Deno.env.get('SUPABASE_URL')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const fcmKey = Deno.env.get('FCM_SERVER_KEY')

  if (!url || !serviceKey) {
    return new Response('Server not configured', { status: 500 })
  }

  if (!fcmKey) {
    // Surface the misconfiguration as a hard failure so the client does
    // not silently report success (reviewer issue 8).
    return new Response(
      JSON.stringify({ ok: false, reason: 'FCM_SERVER_KEY missing' }),
      {
        status: 503,
        headers: { 'content-type': 'application/json' },
      },
    )
  }

  const supabase = createClient(url, serviceKey, {
    auth: { persistSession: false },
  })

  const { data: profile, error: profileError } = await supabase
    .from('profiles')
    .select('fcm_token')
    .eq('id', body.targetUserId)
    .single()

  if (profileError) {
    return new Response(`Profile lookup failed: ${profileError.message}`, {
      status: 500,
    })
  }
  if (!profile?.fcm_token) {
    return new Response('No FCM token registered for target user.', {
      status: 400,
    })
  }

  const notification = {
    to: profile.fcm_token,
    priority: 'high',
    data: {
      type: 'nudge',
      from: body.fromUsername,
    },
    notification: {
      title: 'NUDGE',
      body: `${body.fromUsername} is trying to wake you up.`,
      sound: 'default',
      channel_id: 'sync_ring',
    },
  }

  const fcmRes = await fetch('https://fcm.googleapis.com/fcm/send', {
    method: 'POST',
    headers: {
      Authorization: `key=${fcmKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(notification),
  })

  const text = await fcmRes.text()
  return new Response(text, {
    status: fcmRes.status,
    headers: { 'content-type': 'application/json' },
  })
})
