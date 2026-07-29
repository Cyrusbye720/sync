# SYNC — Agent Guide

## Project Overview
SYNC is a couple alarm app. Two partners pair via a 6-digit code, set alarms for each other, and send nudge/wake-up notifications.

**Stack:** Flutter (Android) + Cloudflare Worker API + Supabase (Postgres) + Firebase Cloud Messaging

## Architecture

```
Flutter App  →  Cloudflare Worker  →  Supabase (RLS)
                    ↓
               Firebase FCM (push)
               D1 (sessions, logs)
               KV (session cache)
               WebSocket (realtime nudges)
```

The Worker is the only thing that touches Supabase/Firebase. The app only talks to the Worker via opaque session tokens.

## Running Locally

### Worker
```bash
cd worker
npm install
npm run dev          # starts wrangler dev on localhost:8787
```

### Flutter
```bash
flutter pub get
flutter run
```

### Secrets (Cloudflare Worker)
Set via `wrangler secret put <NAME>`:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `FIREBASE_SERVICE_ACCOUNT_JSON`
- `SESSION_ENCRYPTION_KEY` (64 hex chars)
- `ADMIN_SECRET`

## Key Files

| File | Purpose |
|------|---------|
| `worker/src/index.ts` | Worker entry point, route registration |
| `worker/src/auth.ts` | OAuth flow, session management, token refresh |
| `worker/src/middleware.ts` | Auth, rate limiting, security headers |
| `worker/src/logger.ts` | Persistent error logging to D1 |
| `worker/src/websocket.ts` | WebSocket fan-out for nudges + announcements |
| `worker/src/fcm.ts` | Firebase Cloud Messaging push |
| `worker/src/routes/alarms.ts` | Alarm CRUD |
| `worker/src/routes/nudges.ts` | Nudge send + FCM |
| `worker/src/routes/profile.ts` | Profile get/update + auto-create |
| `worker/src/routes/pairings.ts` | Pairing invite/claim via Supabase RPCs |
| `worker/src/routes/admin.ts` | Error log viewer, migration endpoint |
| `worker/src/routes/announcements.ts` | Broadcast announcements |
| `lib/services/api_service.dart` | All API calls, WebSocket, OAuth |
| `lib/providers/nudge_provider.dart` | Realtime nudge stream |
| `lib/providers/announcement_provider.dart` | Announcement stream |
| `supabase/init.sql` | Full Supabase schema + RLS policies + triggers |

## API Endpoints

### Public
- `GET /v1/health` — health check
- `GET /v1/auth/discord` / `GET /v1/auth/github` — start OAuth
- `GET /v1/auth/callback` — OAuth callback from Supabase
- `POST /v1/auth/exchange` — exchange one-time code for session

### Authenticated (Bearer token required)
- `GET /v1/profile` — own profile (auto-creates if missing)
- `PATCH /v1/profile` — update profile
- `GET /v1/profile/partner` — partner's profile
- `GET /v1/pairings` — current pairing
- `POST /v1/pairings/invite` — generate invite code
- `POST /v1/pairings/claim` — claim invite code
- `GET /v1/alarms` — list alarms
- `POST /v1/alarms` — create alarm
- `PATCH /v1/alarms/:id` — update alarm
- `DELETE /v1/alarms/:id` — delete alarm
- `GET /v1/alarms/logs` — alarm logs
- `POST /v1/alarms/logs` — insert alarm log
- `POST /v1/nudges` — send nudge
- `GET /v1/nudges` — list incoming nudges
- `PATCH /v1/nudges/:id/read` — mark read
- `GET /v1/announcements` — list announcements

### WebSocket
- `GET /v1/events?token=<session>` — realtime nudge + announcement stream

### Admin (x-admin-secret header)
- `GET /v1/admin/logs` — query error logs
- `GET /v1/admin/logs/stats` — error counts by route
- `DELETE /v1/admin/logs/cleanup` — purge old logs
- `POST /v1/admin/migrate` — create D1 tables
- `POST /v1/announcements` — send broadcast announcement

## Supabase Schema
Tables: `profiles`, `pairings`, `alarms`, `nudges`, `alarm_logs`
All tables have RLS enabled. The Worker creates Supabase clients with user access tokens for RLS enforcement, and uses the service-role key only for admin operations (FCM token lookup, profile auto-create).

## Common Issues

### "RLS policy violation" on alarm/nudge insert
The Worker's stored Supabase access token may be expired. `resolveSession` in `auth.ts` auto-refreshes expired tokens.

### Profile not showing
The signup trigger may have failed. The profile GET route auto-creates via admin client if missing.

### Nudge not delivering
Check `SUPABASE_SERVICE_ROLE_KEY` is set. Check FCM token exists in profiles table. Check Firebase service account JSON is valid.

## Conventions
- TypeScript with strict mode in Worker
- Dart with flutter_lints in app
- Zod schemas for request validation in Worker
- No secrets in source code — use env vars / `wrangler secret put`
