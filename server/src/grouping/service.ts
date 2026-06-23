import { inArray } from 'drizzle-orm'
import type { AniListMedia } from '../anilist/types.js'
import { db } from '../db/index.js'
import { franchise, franchiseMember, media } from '../db/schema.js'
import { makeAniListFetcher, upsertMedia } from '../services/mediaStore.js'
import { stripHtml } from '../util/text.js'
import { expandComponent, type MediaFetcher } from './graph.js'
import { makeGrouper, type GroupingInput, type LlmGrouper } from './llm.js'
import { partKindForFormat } from './partKind.js'

export interface GroupOptions {
  grouper?: LlmGrouper
  fetcher?: MediaFetcher
  model?: string
}

export interface GroupOutcome {
  franchiseId: string
  created: boolean
  attached: number // how many new members attached to an existing franchise
}

// Either the pool handle or a transaction handle — lets the persistence helpers run inside
// the create transaction or standalone.
type Executor = typeof db | Parameters<Parameters<typeof db.transaction>[0]>[0]

/**
 * Build (or extend) the canonical franchise that contains `seedId`.
 * - Expands the relation-graph component (caching media as it goes).
 * - If any member already belongs to a franchise, attach the rest as new parts.
 * - Otherwise run the grouper (LLM or deterministic) and persist new franchise(s).
 * Returns the franchise that ends up containing `seedId`.
 */
export async function groupFromSeed(seedId: number, opts: GroupOptions = {}): Promise<GroupOutcome> {
  const fetcher = opts.fetcher ?? makeAniListFetcher()
  const component = await expandComponent(seedId, fetcher)
  if (component.size === 0) throw new Error(`media ${seedId} not found on AniList`)
  return groupKnownComponent(component, seedId, opts)
}

/**
 * Group an already-expanded relation component (skips the network BFS). Lets callers that
 * have expanded many seeds up front dedupe overlapping components and group each one once.
 */
export async function groupKnownComponent(
  component: Map<number, AniListMedia>,
  seedId: number,
  opts: GroupOptions = {},
): Promise<GroupOutcome> {
  const ids = [...component.keys()]

  // Already grouped? Attach any ungrouped members to the existing franchise.
  const existing = await db.select().from(franchiseMember).where(inArray(franchiseMember.mediaId, ids))
  if (existing.length > 0) return attachToExisting(existing, component, seedId)

  // Fresh grouping. The grouper (LLM/deterministic) can take seconds, so it runs OUTSIDE the
  // transaction — we must not pin a DB connection for its duration.
  const grouper = opts.grouper ?? makeGrouper(opts.model)
  const input = buildInput(component)
  const result = await grouper.group(input)

  try {
    return await db.transaction(async (tx) => {
      // Re-check inside the tx: a concurrent request may have grouped this component while the
      // grouper ran. If so, attach onto the winner rather than creating a duplicate franchise.
      const raced = await tx.select().from(franchiseMember).where(inArray(franchiseMember.mediaId, ids))
      if (raced.length > 0) return attachToExisting(raced, component, seedId, tx)

      let seedFranchiseId: string | null = null
      for (const f of result.franchises) {
        const memberIds = f.parts.map((p) => p.id)
        const primary = pickPrimary(memberIds, component)
        const [row] = await tx
          .insert(franchise)
          .values({
            title: f.canonicalName,
            primaryMediaId: primary?.id ?? null,
            cover: primary?.coverImage.extraLarge ?? primary?.coverImage.large ?? null,
            banner: primary?.bannerImage ?? primary?.coverImage.extraLarge ?? null,
            description: stripHtml(primary?.description ?? null),
            genres: dedupeGenres(memberIds, component),
            groupingSource: result.model ? 'llm' : 'relations',
            groupingModel: result.model,
            confidence: result.confidence,
          })
          .returning({ id: franchise.id })

        const fid = row!.id
        // No onConflictDoNothing: a PK collision here means we lost a create race, and we want
        // the whole transaction to roll back (no orphan franchise row) and fall to the catch.
        // Insert in ascending mediaId order so concurrent creates acquire the franchiseMember PK
        // row locks in the same order — removes the lock-cycle deadlock window.
        await tx.insert(franchiseMember).values(
          [...f.parts]
            .sort((a, b) => a.id - b.id)
            .map((p) => ({
              mediaId: p.id,
              franchiseId: fid,
              partKind: p.partKind,
              sequence: p.sequence,
              label: p.label,
            })),
        )
        if (f.parts.some((p) => p.id === seedId)) seedFranchiseId = fid
      }

      if (!seedFranchiseId) throw new Error('grouper did not place the seed media into any franchise')
      return { franchiseId: seedFranchiseId, created: true, attached: 0 }
    })
  } catch (err) {
    // Only a unique-violation (lost create race) is recoverable: another request grouped this
    // component concurrently and our transaction rolled back cleanly (no orphan). Resolve and
    // return the winner. Any other error — including a genuine "seed not placed" bug — is real
    // and must surface, so we rethrow it rather than masking it behind a re-read.
    if ((err as { code?: string })?.code !== '23505') throw err
    const winners = await db.select().from(franchiseMember).where(inArray(franchiseMember.mediaId, ids))
    if (winners.length > 0) {
      const fid = winners.find((m) => m.mediaId === seedId)?.franchiseId ?? mostCommon(winners.map((m) => m.franchiseId))
      if (fid) return { franchiseId: fid, created: false, attached: 0 }
    }
    throw err
  }
}

/** Resolve the franchise that already owns part of `component` and attach the rest onto it. */
async function attachToExisting(
  existing: { mediaId: number; franchiseId: string }[],
  component: Map<number, AniListMedia>,
  seedId: number,
  exec: Executor = db,
): Promise<GroupOutcome> {
  const seedFranchise = existing.find((m) => m.mediaId === seedId)?.franchiseId
  const targetFranchiseId = seedFranchise ?? mostCommon(existing.map((m) => m.franchiseId))!
  const attached = await attachNewMembers(targetFranchiseId, component, new Set(existing.map((m) => m.mediaId)), exec)
  return { franchiseId: targetFranchiseId, created: false, attached }
}

/** Attach component members not yet grouped onto an existing franchise (new seasons/episodes). */
async function attachNewMembers(
  franchiseId: string,
  component: Map<number, AniListMedia>,
  alreadyMembers: Set<number>,
  exec: Executor = db,
): Promise<number> {
  const fresh = [...component.values()].filter((m) => !alreadyMembers.has(m.id))
  if (fresh.length === 0) return 0

  // Determine next sequence per kind from existing members.
  const existingParts = await exec.select().from(franchiseMember).where(inArray(franchiseMember.franchiseId, [franchiseId]))
  const nextSeq = new Map<string, number>()
  for (const p of existingParts) nextSeq.set(p.partKind, Math.max(nextSeq.get(p.partKind) ?? 0, p.sequence))

  const values = fresh.map((m) => {
    const kind = partKindForFormat(m.format)
    const seq = (nextSeq.get(kind) ?? 0) + 1
    nextSeq.set(kind, seq)
    const label = kind === 'season' ? `Season ${seq}` : `${kind[0]!.toUpperCase()}${kind.slice(1)} ${seq}`
    return { mediaId: m.id, franchiseId, partKind: kind, sequence: seq, label }
  })
  await exec.insert(franchiseMember).values(values).onConflictDoNothing()
  await exec.update(franchise).set({ updatedAt: new Date() }).where(inArray(franchise.id, [franchiseId]))
  return values.length
}

function buildInput(component: Map<number, AniListMedia>): GroupingInput {
  const candidates = [...component.values()].map((m) => ({
    id: m.id,
    title: m.title.english || m.title.romaji || `Anime #${m.id}`,
    format: m.format,
    status: m.status,
    seasonYear: m.seasonYear,
    episodes: m.episodes,
    synopsis: stripHtml(m.description),
  }))
  const ids = new Set(component.keys())
  const edges = [...component.values()].flatMap((m) =>
    (m.relations?.edges ?? [])
      .filter((e) => e.node.type === 'ANIME' && ids.has(e.node.id))
      .map((e) => ({ from: m.id, to: e.node.id, type: e.relationType })),
  )
  return { candidates, edges }
}

function pickPrimary(ids: number[], component: Map<number, AniListMedia>): AniListMedia | undefined {
  const members = ids.map((id) => component.get(id)).filter((m): m is AniListMedia => !!m)
  // Prefer the earliest TV season; else most popular.
  const seasons = members
    .filter((m) => partKindForFormat(m.format) === 'season')
    .sort((a, b) => (a.seasonYear ?? 9999) - (b.seasonYear ?? 9999))
  if (seasons[0]) return seasons[0]
  return members.sort((a, b) => (b.popularity ?? 0) - (a.popularity ?? 0))[0]
}

function dedupeGenres(ids: number[], component: Map<number, AniListMedia>): string[] {
  const set = new Set<string>()
  for (const id of ids) for (const g of component.get(id)?.genres ?? []) set.add(g)
  return [...set].slice(0, 6)
}

function mostCommon<T>(arr: T[]): T | undefined {
  const counts = new Map<T, number>()
  let best: T | undefined
  let bestN = 0
  for (const x of arr) {
    const n = (counts.get(x) ?? 0) + 1
    counts.set(x, n)
    if (n > bestN) {
      bestN = n
      best = x
    }
  }
  return best
}

/** Persist freshly-fetched media (used by sync/seed before grouping). */
export async function cacheMedia(items: AniListMedia[]): Promise<void> {
  await upsertMedia(items)
}

// keep `media` import referenced for type-only inference symmetry
export type { AniListMedia }
void media
