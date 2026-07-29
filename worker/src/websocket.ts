/**
 * WebSocket handler for realtime nudge delivery.
 *
 * Clients connect to /v1/events?token=<session_token>.
 * On connection, the token is validated and the WebSocket is registered
 * under the user's ID. When a nudge is created, fanOutNudge() sends
 * the nudge payload to all connected WebSockets for the target user.
 *
 * Ping/pong keepalive is handled automatically by the runtime.
 */

import { resolveSession } from './auth.js';
import type { Env } from './types.js';

// In-memory registry of connected clients per user ID.
// Resets when the Worker isolate recycles — acceptable for edge WebSockets.
const connections = new Map<string, Set<WebSocket>>();

/**
 * Handle WebSocket upgrade at /v1/events.
 * Authenticates via query param token, then registers the connection.
 */
export async function handleWebSocketUpgrade(
  request: Request,
  env: Env,
): Promise<Response> {
  const upgradeHeader = request.headers.get('upgrade');
  if (upgradeHeader !== 'websocket') {
    return new Response('Expected WebSocket upgrade', { status: 426 });
  }

  const url = new URL(request.url);
  const token = url.searchParams.get('token');
  if (!token) {
    return new Response('Missing token query parameter', { status: 401 });
  }

  // Validate session
  let userId: string;
  try {
    const session = await resolveSession(token, env);
    userId = session.userId;
  } catch {
    return new Response('Invalid session', { status: 401 });
  }

  // Create WebSocket pair
  const pair = new WebSocketPair();
  const [client, server] = [pair[0], pair[1]];

  // Accept the server side
  server.accept();

  // Register connection
  let userConns = connections.get(userId);
  if (!userConns) {
    userConns = new Set();
    connections.set(userId, userConns);
  }
  userConns.add(server);

  // Send initial connected message
  server.send(JSON.stringify({ type: 'connected', userId }));

  // Handle close/error — unregister
  server.addEventListener('close', () => {
    userConns?.delete(server);
    if (userConns?.size === 0) {
      connections.delete(userId);
    }
  });

  server.addEventListener('error', () => {
    userConns?.delete(server);
    if (userConns?.size === 0) {
      connections.delete(userId);
    }
  });

  // Handle incoming messages (ping/pong, future extensibility)
  server.addEventListener('message', (event) => {
    try {
      const msg = JSON.parse(event.data as string);
      if (msg.type === 'ping') {
        server.send(JSON.stringify({ type: 'pong' }));
      }
    } catch {
      // Ignore malformed messages
    }
  });

  return new Response(null, { status: 101, webSocket: client });
}

/**
 * Fan out a nudge event to all WebSocket connections for a target user.
 * Called from the nudge route after inserting the nudge row.
 */
export function fanOutNudge(targetUserId: string, nudgeData: unknown): void {
  const userConns = connections.get(targetUserId);
  if (!userConns || userConns.size === 0) return;

  const payload = JSON.stringify({ type: 'nudge', data: nudgeData });

  for (const ws of userConns) {
    try {
      ws.send(payload);
    } catch {
      // Connection dead — will be cleaned up on close event
      userConns.delete(ws);
    }
  }
}

/**
 * Fan out an announcement to ALL connected WebSocket clients.
 */
export function fanOutAnnouncement(announcementData: unknown): void {
  const payload = JSON.stringify({ type: 'announcement', data: announcementData });

  for (const [, userConns] of connections) {
    for (const ws of userConns) {
      try {
        ws.send(payload);
      } catch {
        userConns.delete(ws);
      }
    }
  }
}

/**
 * Get the count of active WebSocket connections (for health check).
 */
export function getConnectionCount(): number {
  let count = 0;
  for (const conns of connections.values()) {
    count += conns.size;
  }
  return count;
}
