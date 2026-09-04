import { eq } from 'drizzle-orm'
import { db } from '../db/index.js'
import { userPreferences } from '../db/schema.js'
import type { UserPreferences, WatchAvailability } from '../types/api.js'

const DEFAULTS: UserPreferences = { country: null, language: 'en', providerIds: [], updatedAt: null }

export async function getUserPreferences(userId: string): Promise<UserPreferences> {
  const [row] = await db.select().from(userPreferences).where(eq(userPreferences.userId, userId)).limit(1)
  if (!row) return DEFAULTS
  return {
    country: row.country,
    language: row.language,
    providerIds: row.providerIds ?? [],
    updatedAt: row.updatedAt.toISOString(),
  }
}

export async function saveUserPreferences(
  userId: string,
  value: { country?: string | null; language?: string; providerIds?: number[] },
): Promise<UserPreferences> {
  const previous = await getUserPreferences(userId)
  const next = {
    country: value.country === undefined ? previous.country : value.country,
    language: value.language ?? previous.language,
    providerIds: value.providerIds ?? previous.providerIds,
    updatedAt: new Date(),
  }
  const [row] = await db
    .insert(userPreferences)
    .values({ userId, ...next })
    .onConflictDoUpdate({
      target: userPreferences.userId,
      set: next,
    })
    .returning()
  return {
    country: row!.country,
    language: row!.language,
    providerIds: row!.providerIds ?? [],
    updatedAt: row!.updatedAt.toISOString(),
  }
}

export async function resolveUserCountry(userId: string, override?: string | null): Promise<string | null> {
  return (await resolveUserPreferences(userId, override)).country
}

export async function resolveUserPreferences(
  userId: string,
  countryOverride?: string | null,
): Promise<UserPreferences> {
  const value = await getUserPreferences(userId)
  return countryOverride ? { ...value, country: countryOverride.toUpperCase() } : value
}

/** Put explicitly preferred services first while retaining TMDB/JustWatch order for everything else. */
export function applyProviderPreferences(
  availability: WatchAvailability,
  providerIds: number[],
): WatchAvailability {
  if (providerIds.length === 0) return availability
  const rank = new Map(providerIds.map((id, index) => [id, index]))
  return {
    ...availability,
    providers: availability.providers
      .map((provider, index) => ({ provider, index }))
      .sort((a, b) => {
        const ar = rank.get(a.provider.id)
        const br = rank.get(b.provider.id)
        if (ar != null && br != null) return ar - br
        if (ar != null) return -1
        if (br != null) return 1
        return a.index - b.index
      })
      .map(({ provider }) => ({ ...provider, ...(rank.has(provider.id) ? { preferred: true } : {}) })),
  }
}
