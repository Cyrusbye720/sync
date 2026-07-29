/**
 * Cryptographic utilities for session token management.
 *
 * - Opaque session tokens: 256-bit random, hex-encoded
 * - Token storage: SHA-256 hashed (never store plaintext)
 * - Refresh token encryption: AES-256-GCM with SESSION_ENCRYPTION_KEY
 * - One-time codes: 6-char alphanumeric
 */

/** SHA-256 hash a string, return hex. */
export async function hashToken(token: string): Promise<string> {
  const data = new TextEncoder().encode(token);
  const hash = await crypto.subtle.digest('SHA-256', data);
  return hexEncode(new Uint8Array(hash));
}

/** Generate a 256-bit random session token as hex (64 chars). */
export function generateToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return hexEncode(bytes);
}

/** Generate a 6-character alphanumeric one-time code. */
export function generateCode(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
  const bytes = new Uint8Array(6);
  crypto.getRandomValues(bytes);
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += chars[bytes[i]! % chars.length];
  }
  return code;
}

/**
 * Encrypt plaintext with AES-256-GCM.
 * @param plaintext - The string to encrypt
 * @param keyHex   - 64-char hex string (256-bit key)
 * @returns Hex-encoded string: iv(24):ciphertext:tag (tag appended by GCM)
 */
export async function encryptToken(
  plaintext: string,
  keyHex: string,
): Promise<string> {
  const keyBytes = hexDecode(keyHex);
  const key = await crypto.subtle.importKey(
    'raw',
    keyBytes,
    { name: 'AES-GCM' },
    false,
    ['encrypt'],
  );

  const iv = new Uint8Array(12);
  crypto.getRandomValues(iv);

  const encoded = new TextEncoder().encode(plaintext);
  const ciphertext = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv },
    key,
    encoded,
  );

  return hexEncode(iv) + ':' + hexEncode(new Uint8Array(ciphertext));
}

/**
 * Decrypt AES-256-GCM ciphertext.
 * @param encrypted - Hex string from encryptToken: iv:ciphertext+tag
 * @param keyHex    - 64-char hex string (256-bit key)
 */
export async function decryptToken(
  encrypted: string,
  keyHex: string,
): Promise<string> {
  const parts = encrypted.split(':');
  if (parts.length !== 2) throw new Error('Invalid encrypted format');

  const iv = hexDecode(parts[0]!);
  const ciphertext = hexDecode(parts[1]!);

  const keyBytes = hexDecode(keyHex);
  const key = await crypto.subtle.importKey(
    'raw',
    keyBytes,
    { name: 'AES-GCM' },
    false,
    ['decrypt'],
  );

  const decrypted = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv },
    key,
    ciphertext,
  );

  return new TextDecoder().decode(decrypted);
}

// ─── Hex Helpers ──────────────────────────────────────────────────────────────

function hexEncode(bytes: Uint8Array): string {
  let hex = '';
  for (let i = 0; i < bytes.length; i++) {
    hex += bytes[i]!.toString(16).padStart(2, '0');
  }
  return hex;
}

function hexDecode(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

// ─── PKCE Helpers ─────────────────────────────────────────────────────────────

/** Generate a random PKCE code verifier (43-128 chars, URL-safe). */
export function generateCodeVerifier(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return base64UrlEncode(bytes);
}

/** SHA-256 hash of the code verifier, base64url-encoded. */
export async function generateCodeChallenge(verifier: string): Promise<string> {
  const data = new TextEncoder().encode(verifier);
  const hash = await crypto.subtle.digest('SHA-256', data);
  return base64UrlEncode(new Uint8Array(hash));
}

function base64UrlEncode(bytes: Uint8Array): string {
  let str = '';
  for (let i = 0; i < bytes.length; i++) {
    str += String.fromCharCode(bytes[i]!);
  }
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}
