/**
 * Request body validation schemas using Zod.
 */

import { z } from 'zod';

const uuid = z.string().uuid();

// ─── Profile ──────────────────────────────────────────────────────────────────

export const ProfileUpdateSchema = z
  .object({
    timezone: z.string().max(64).optional(),
    battery_percent: z.number().int().min(0).max(100).optional(),
    sleep_status: z.enum(['awake', 'asleep']).optional(),
    fcm_token: z.string().max(512).optional(),
    username: z.string().min(1).max(64).optional(),
    avatar_url: z.string().url().max(1024).nullable().optional(),
  })
  .strict();

// ─── Pairings ─────────────────────────────────────────────────────────────────

export const PairingClaimSchema = z
  .object({
    code: z.string().min(4).max(10),
  })
  .strict();

// ─── Alarms ───────────────────────────────────────────────────────────────────

export const AlarmCreateSchema = z
  .object({
    owner_id: uuid,
    created_by: uuid.optional(),
    label: z.string().min(1).max(128).default('Alarm'),
    message: z.string().max(256).default('Wake up!'),
    hour: z.number().int().min(0).max(23),
    minute: z.number().int().min(0).max(59),
    days_of_week: z.array(z.number().int().min(1).max(7)).default([]),
    is_active: z.boolean().default(true),
    vibrate: z.boolean().default(true),
    sound_name: z.string().max(64).default('default'),
    snooze_minutes: z.number().int().min(1).max(60).default(5),
  })
  .strict();

export const AlarmUpdateSchema = z
  .object({
    label: z.string().min(1).max(128).optional(),
    message: z.string().max(256).optional(),
    hour: z.number().int().min(0).max(23).optional(),
    minute: z.number().int().min(0).max(59).optional(),
    days_of_week: z.array(z.number().int().min(1).max(7)).optional(),
    is_active: z.boolean().optional(),
    vibrate: z.boolean().optional(),
    sound_name: z.string().max(64).optional(),
    snooze_minutes: z.number().int().min(1).max(60).optional(),
  })
  .strict();

// ─── Alarm Logs ───────────────────────────────────────────────────────────────

export const AlarmLogCreateSchema = z
  .object({
    alarm_id: uuid,
    action: z.enum(['fired', 'snoozed', 'dismissed']),
    reaction: z.string().max(256).nullable().optional(),
    acted_by: uuid.nullable().optional(),
  })
  .strict();

export const AlarmLogUpdateSchema = z
  .object({
    reaction: z.string().max(256),
  })
  .strict();

// ─── Nudges ───────────────────────────────────────────────────────────────────

export const NudgeCreateSchema = z
  .object({
    to_user_id: uuid,
  })
  .strict();

// ─── Auth ─────────────────────────────────────────────────────────────────────

export const CodeExchangeSchema = z
  .object({
    code: z.string().min(4).max(16),
  })
  .strict();
