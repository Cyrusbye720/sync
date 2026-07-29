import type { SupabaseClient } from '@supabase/supabase-js';

// ─── Cloudflare Bindings ──────────────────────────────────────────────────────

export interface Env {
  // D1 database for sessions, OAuth state, login codes
  DB: D1Database;
  // KV for fast session lookups (optional cache layer)
  SESSIONS: KVNamespace;

  // Secrets — set via `wrangler secret put`
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
  FIREBASE_SERVICE_ACCOUNT_JSON: string;
  SESSION_ENCRYPTION_KEY: string; // 64 hex chars (256-bit)
  ADMIN_SECRET: string;
}

// ─── Firebase Service Account ─────────────────────────────────────────────────

export interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
  token_uri: string;
}

// ─── D1 Row Types ─────────────────────────────────────────────────────────────

export interface SessionRow {
  token_hash: string;
  user_id: string;
  sb_access: string;   // encrypted
  sb_refresh: string;  // encrypted
  created_at: number;
  expires_at: number;
}

export interface OAuthStateRow {
  state: string;
  provider: string;
  created_at: number;
  expires_at: number;
}

export interface LoginCodeRow {
  code: string;
  token_hash: string;
  created_at: number;
  expires_at: number;
}

// ─── Request Context ──────────────────────────────────────────────────────────

export interface UserContext {
  userId: string;
  supabase: SupabaseClient;
}

// ─── Hono Variables ───────────────────────────────────────────────────────────

export type HonoEnv = {
  Bindings: Env;
  Variables: {
    userId: string;
    supabase: SupabaseClient;
  };
};
