import { eq } from 'drizzle-orm'
import { db } from '../db/index.js'
import { userProfiles } from '../db/schema.js'
import { env } from '../env.js'
import { checkHandle, normalizeHandle } from '../social/identity.js'
import type { HandleAvailability, ProfileResponse } from '../types/api.js'

// The public identity row (user_profiles): the handle, the confirmed first name and the
// community-rules acceptance. The rules for what a handle or a name may be live in
// social/identity.ts; this file only reads and writes the row.

/** The stored row, as far as the profile view needs it. */
export interface ProfileRow {
  handle: string | null
  displayName: string | null
  termsAcceptedAt: Date | null
  termsVersion: string | null
}

export interface ProfilePolicy {
  /** SOCIAL_TERMS_VERSION: the community-rules version a poster must have accepted. */
  currentTermsVersion: string
  /** SOCIAL_COMMENTS_ENABLED. */
  commentsEnabled: boolean
}

function policyFromEnv(): ProfilePolicy {
  return { currentTermsVersion: env.SOCIAL_TERMS_VERSION, commentsEnabled: env.SOCIAL_COMMENTS_ENABLED }
}

/**
 * The wire view of a profile row (null = the user has never touched their profile). `canComment`
 * is exactly the gate POST /social/comments applies (handle, name, the current rules) plus the
 * capability switch, so the client can route straight to the composer or to the missing step.
 */
export function toProfileResponse(userId: string, row: ProfileRow | null, policy: ProfilePolicy): ProfileResponse {
  const handle = row?.handle ?? null
  const displayName = row?.displayName ?? null
  const termsVersion = row?.termsVersion ?? null
  return {
    userId,
    handle,
    displayName,
    termsAcceptedAt: row?.termsAcceptedAt ? row.termsAcceptedAt.getTime() : null,
    termsVersion,
    currentTermsVersion: policy.currentTermsVersion,
    canComment:
      handle != null && displayName != null && termsVersion === policy.currentTermsVersion && policy.commentsEnabled,
  }
}

const HANDLE_CONSTRAINT = 'user_profiles_handle_uq'

/**
 * True when `err` is Postgres refusing a second owner of a handle (23505 on the handle's unique
 * index). A user_profiles upsert can only trip that one unique index — the user_id primary key is
 * the conflict target — so a 23505 that names no constraint is read the same way. drizzle 0.38
 * passes postgres.js errors through; a wrapped one carries it as `cause`.
 */
export function isHandleTakenError(err: unknown): boolean {
  for (let e: unknown = err, depth = 0; e != null && typeof e === 'object' && depth < 4; depth++) {
    const { code, constraint_name: constraint } = e as { code?: unknown; constraint_name?: unknown }
    if (code === '23505') return constraint == null || constraint === HANDLE_CONSTRAINT
    e = (e as { cause?: unknown }).cause
  }
  return false
}

async function readRow(userId: string): Promise<ProfileRow | null> {
  const [row] = await db
    .select({
      handle: userProfiles.handle,
      displayName: userProfiles.displayName,
      termsAcceptedAt: userProfiles.termsAcceptedAt,
      termsVersion: userProfiles.termsVersion,
    })
    .from(userProfiles)
    .where(eq(userProfiles.userId, userId))
    .limit(1)
  return row ?? null
}

export async function getProfile(userId: string): Promise<ProfileResponse> {
  return toProfileResponse(userId, await readRow(userId), policyFromEnv())
}

/** The user who holds `handle` (already normalised), or null when it is free. */
export async function findHandleOwner(handle: string): Promise<string | null> {
  const [row] = await db
    .select({ userId: userProfiles.userId })
    .from(userProfiles)
    .where(eq(userProfiles.handle, handle))
    .limit(1)
  return row?.userId ?? null
}

/**
 * Set the handle and first name (both already checked and normalised by social/identity.ts). An
 * upsert on user_id; the handle's unique index is the arbiter of a race, so a caller must map
 * `isHandleTakenError` to 409 `handle_taken`.
 */
export async function saveProfile(
  userId: string,
  value: { handle: string; displayName: string },
): Promise<ProfileResponse> {
  const now = new Date()
  const [row] = await db
    .insert(userProfiles)
    .values({ userId, handle: value.handle, displayName: value.displayName, createdAt: now, updatedAt: now })
    .onConflictDoUpdate({
      target: userProfiles.userId,
      set: { handle: value.handle, displayName: value.displayName, updatedAt: now },
    })
    .returning({
      handle: userProfiles.handle,
      displayName: userProfiles.displayName,
      termsAcceptedAt: userProfiles.termsAcceptedAt,
      termsVersion: userProfiles.termsVersion,
    })
  return toProfileResponse(userId, row ?? null, policyFromEnv())
}

/**
 * Stamp acceptance of the community rules. The caller has already held `version` to the current
 * one. Repeating it re-stamps the time (the contract's upsert), and a profile row with no handle
 * yet is created — the rules sheet may come before the handle picker.
 */
export async function acceptTerms(userId: string, version: string): Promise<ProfileResponse> {
  const now = new Date()
  const [row] = await db
    .insert(userProfiles)
    .values({ userId, termsAcceptedAt: now, termsVersion: version, createdAt: now, updatedAt: now })
    .onConflictDoUpdate({
      target: userProfiles.userId,
      set: { termsAcceptedAt: now, termsVersion: version, updatedAt: now },
    })
    .returning({
      handle: userProfiles.handle,
      displayName: userProfiles.displayName,
      termsAcceptedAt: userProfiles.termsAcceptedAt,
      termsVersion: userProfiles.termsVersion,
    })
  return toProfileResponse(userId, row ?? null, policyFromEnv())
}

/**
 * As-you-type availability. A handle the rules refuse answers with the rule's reason and never
 * reaches the database; one the caller already holds is available to them.
 */
export async function handleAvailability(userId: string, raw: string): Promise<HandleAvailability> {
  const checked = checkHandle(raw)
  if (!checked.ok) return { handle: normalizeHandle(raw), available: false, reason: checked.reason }
  const owner = await findHandleOwner(checked.handle)
  if (owner != null && owner !== userId) return { handle: checked.handle, available: false, reason: 'taken' }
  return { handle: checked.handle, available: true, reason: null }
}
