import { and, eq, inArray } from 'drizzle-orm'
import { db } from '../db/index.js'
import { catalogLinks } from '../db/schema.js'
import type { CatalogLinkView, CatalogMediaType, CatalogProvider } from '../types/api.js'

export interface CatalogLinkInput {
  franchiseId: string
  provider: CatalogProvider
  mediaType: CatalogMediaType
  externalId: number | null
  status?: 'matched' | 'unmatched' | 'rejected'
  matchMethod: string
  confidence?: number | null
  evidence?: Record<string, unknown>
  checkedAt?: Date
}

/**
 * Persist a cross-catalogue identity without ever stealing a provider work from another franchise.
 * The unique provider/media/id key is the final guard against accidental duplicate identities.
 */
export async function upsertCatalogLink(input: CatalogLinkInput): Promise<boolean> {
  const checkedAt = input.checkedAt ?? new Date()
  try {
    await db
      .insert(catalogLinks)
      .values({
        franchiseId: input.franchiseId,
        provider: input.provider,
        mediaType: input.mediaType,
        externalId: input.externalId,
        status: input.status ?? (input.externalId == null ? 'unmatched' : 'matched'),
        matchMethod: input.matchMethod,
        confidence: input.confidence ?? null,
        evidence: input.evidence ?? {},
        checkedAt,
        updatedAt: checkedAt,
      })
      .onConflictDoUpdate({
        target: [catalogLinks.franchiseId, catalogLinks.provider],
        set: {
          mediaType: input.mediaType,
          externalId: input.externalId,
          status: input.status ?? (input.externalId == null ? 'unmatched' : 'matched'),
          matchMethod: input.matchMethod,
          confidence: input.confidence ?? null,
          evidence: input.evidence ?? {},
          checkedAt,
          updatedAt: checkedAt,
        },
      })
    return true
  } catch (error) {
    // Another franchise already owns this provider id. Keeping the existing link is safer than
    // making availability/artwork disagree about identity; operators can resolve it explicitly.
    if ((error as { code?: string })?.code === '23505') return false
    throw error
  }
}

export async function getCatalogLink(
  franchiseId: string,
  provider: CatalogProvider,
): Promise<typeof catalogLinks.$inferSelect | null> {
  const [row] = await db
    .select()
    .from(catalogLinks)
    .where(and(eq(catalogLinks.franchiseId, franchiseId), eq(catalogLinks.provider, provider)))
    .limit(1)
  return row ?? null
}

export async function catalogLinkViews(franchiseIds: string[]): Promise<Map<string, CatalogLinkView[]>> {
  const out = new Map<string, CatalogLinkView[]>()
  if (franchiseIds.length === 0) return out
  const rows = await db
    .select()
    .from(catalogLinks)
    .where(and(inArray(catalogLinks.franchiseId, franchiseIds), eq(catalogLinks.status, 'matched')))
  for (const row of rows) {
    if (row.externalId == null) continue
    const value: CatalogLinkView = {
      provider: row.provider as CatalogProvider,
      mediaType: row.mediaType as CatalogMediaType,
      externalId: row.externalId,
      matchMethod: row.matchMethod,
      confidence: row.confidence,
      checkedAt: row.checkedAt.toISOString(),
    }
    out.set(row.franchiseId, [...(out.get(row.franchiseId) ?? []), value])
  }
  return out
}
