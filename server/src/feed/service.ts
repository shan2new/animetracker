import { asc, desc, eq } from 'drizzle-orm'
import { db } from '../db/index.js'
import { announcements, franchiseMember, reminders, saves, subscriptions } from '../db/schema.js'
import { env } from '../env.js'
import { announcementForPart } from '../news/installment.js'
import { getFeedFranchises, getSummaries, trendingFranchiseIds } from '../services/franchiseView.js'
import { clientAnchor, readVisitAnchors } from '../services/visits.js'
import { formatSubject, parseSubject } from '../social/subjects.js'
import type {
  FeedCapabilities,
  FeedFranchise,
  FeedPost,
  FeedPostDetailResponse,
  FeedResponse,
  FeedTab,
  Franchise,
  FranchiseSummary,
  RemindersResponse,
  SavedResponse,
  WatchStatus,
} from '../types/api.js'
import {
  composePostById,
  composePosts,
  orderPosts,
  toFeedFranchise,
  type ComposeByIdOptions,
  type ComposedPost,
  type ComposeInput,
} from './compose.js'
import { loadResearchHistory } from './history.js'
import { storyline, threadSources } from './storyline.js'
import { emptyPostSocial, firstActivityAt, loadHides, loadPostSocial, type PostSocial } from './viewerState.js'

// The Today feed's IO (docs/api-contract.md, "Today feed"): load, compose (feed/compose.ts, pure),
// apply the viewer's hides and social state. The feed never enqueues research (D15): research runs
// on a personal subscription, so feed traffic must not spend it.

/** Feed sizes are code constants, not env (spec §8). */
export const FEED_LIMITS = {
  following: 200,
  forYou: 50,
  /** Trending franchises For you composes from. */
  forYouCandidates: 150,
  /** How long one For you composition serves every viewer. */
  forYouTtlMs: 10 * 60_000,
  /** The Trending module under For you. */
  trendingModule: 8,
} as const

function feedCapabilities(): FeedCapabilities {
  return { comments: env.SOCIAL_COMMENTS_ENABLED }
}

/** The wire post: the composed post without its internal thread, plus the viewer's state. */
function toFeedPost(post: ComposedPost, fresh: boolean, social: PostSocial | undefined): FeedPost {
  const { thread: _thread, ...rest } = post
  const state = social ?? emptyPostSocial()
  return { ...rest, fresh, viewer: state.viewer, counts: state.counts }
}

const isFresh = (discoveredAt: number, prevOpenedAt: number): boolean => prevOpenedAt > 0 && discoveredAt > prevOpenedAt

/** The author rows for exactly the franchises `posts` reference, in first-reference order. */
function referencedFranchises(
  posts: readonly { franchiseId: string }[],
  byId: ReadonlyMap<string, Franchise>,
  statusOf: (id: string) => WatchStatus | null,
): FeedFranchise[] {
  const out: FeedFranchise[] = []
  const seen = new Set<string>()
  for (const post of posts) {
    if (seen.has(post.franchiseId)) continue
    seen.add(post.franchiseId)
    const f = byId.get(post.franchiseId)
    if (f) out.push(toFeedFranchise(f, statusOf(post.franchiseId)))
  }
  return out
}

async function subscribedFranchiseIds(userId: string): Promise<string[]> {
  const rows = await db
    .select({ franchiseId: subscriptions.franchiseId })
    .from(subscriptions)
    .where(eq(subscriptions.userId, userId))
    .orderBy(asc(subscriptions.createdAt), asc(subscriptions.franchiseId))
  return rows.map((row) => row.franchiseId)
}

// ---------- For you: one user-independent composition per process, refreshed every 10 minutes ----------

interface ForYouSnapshot {
  posts: ComposedPost[]
  franchisesById: Map<string, Franchise>
  /** Trending summaries, rank order. */
  summaries: FranchiseSummary[]
}

let forYouCache: { builtAt: number; snapshot: ForYouSnapshot } | null = null
let forYouInFlight: Promise<ForYouSnapshot> | null = null

async function buildForYou(nowMs: number): Promise<ForYouSnapshot> {
  const ids = await trendingFranchiseIds(FEED_LIMITS.forYouCandidates)
  const [loaded, history, summaries] = await Promise.all([
    getFeedFranchises(ids, null),
    loadResearchHistory(ids),
    getSummaries(ids),
  ])
  const posts = composePosts({
    franchises: loaded.franchises,
    observations: history.observations,
    announcements: history.announcements,
    memberAddedAt: loaded.memberAddedAt,
    externalIds: loaded.externalIdById,
    nowMs,
  })
  return { posts, franchisesById: new Map(loaded.franchises.map((f) => [f.id, f])), summaries }
}

/** Single-flight: concurrent callers share one build. A failed refresh serves the last snapshot. */
function forYouSnapshot(nowMs: number): Promise<ForYouSnapshot> {
  if (forYouCache && nowMs - forYouCache.builtAt < FEED_LIMITS.forYouTtlMs) return Promise.resolve(forYouCache.snapshot)
  if (!forYouInFlight) {
    forYouInFlight = buildForYou(nowMs)
      .then((snapshot) => {
        forYouCache = { builtAt: nowMs, snapshot }
        return snapshot
      })
      .catch((err: unknown) => {
        if (!forYouCache) throw err
        console.warn('[feed] For you refresh failed; serving the previous snapshot:', (err as Error).message)
        return forYouCache.snapshot
      })
      .finally(() => {
        forYouInFlight = null
      })
  }
  return forYouInFlight
}

// ---------- GET /me/feed ----------

/**
 * `since` is the client's anchor (`?since=`): the `prevOpenedAt` its own `POST /me/opened` answered
 * this session. When it is a real past instant (`clientAnchor`) it is THE anchor — `fresh`, the
 * order and the echoed `prevOpenedAt` all use it — because the stored one moves under the client
 * when that stamp failed or another device stamped a visit. Otherwise the stored anchor is read.
 */
export async function getFeed(
  userId: string,
  tab: FeedTab,
  nowMs: number = Date.now(),
  since: number | null = null,
): Promise<FeedResponse> {
  const anchor = clientAnchor(since, nowMs)
  const [prevOpenedAt, hides, owned] = await Promise.all([
    anchor ?? readVisitAnchors(userId).then((anchors) => anchors.prevOpenedAt),
    loadHides(userId),
    subscribedFranchiseIds(userId),
  ])

  let composed: ComposedPost[]
  let franchisesById: Map<string, Franchise>
  let statusOf: (id: string) => WatchStatus | null
  let trending: FranchiseSummary[] = []
  let cap: number

  if (tab === 'following') {
    // Every library status (spike parity), minus muted shows.
    const ids = owned.filter((id) => !hides.shows.has(id))
    const [loaded, history] = await Promise.all([getFeedFranchises(ids, userId), loadResearchHistory(ids)])
    composed = composePosts({
      franchises: loaded.franchises,
      observations: history.observations,
      announcements: history.announcements,
      memberAddedAt: loaded.memberAddedAt,
      externalIds: loaded.externalIdById,
      nowMs,
    })
    franchisesById = new Map(loaded.franchises.map((f) => [f.id, f]))
    statusOf = (id) => loaded.statusById.get(id) ?? null
    cap = FEED_LIMITS.following
  } else {
    // News about trending shows the viewer does not track and has not muted.
    const snapshot = await forYouSnapshot(nowMs)
    const excluded = new Set([...owned, ...hides.shows])
    composed = snapshot.posts.filter((post) => !excluded.has(post.franchiseId))
    trending = snapshot.summaries.filter((s) => !excluded.has(s.id)).slice(0, FEED_LIMITS.trendingModule)
    franchisesById = snapshot.franchisesById
    statusOf = () => null
    cap = FEED_LIMITS.forYou
  }

  // Following puts what arrived since the previous visit first (D8). For you is news about shows
  // the viewer does not follow, composed for everyone at once: nothing in it is "new since your
  // visit" (the client never marks it so), and a fresh-first block there only reads as a shuffled
  // timeline — so it is ordered by time alone, with no post fresh.
  const ordered = orderPosts(
    composed.filter((post) => !hides.posts.has(post.id)),
    tab === 'following' ? prevOpenedAt : 0,
  ).slice(0, cap)
  const social = await loadPostSocial(userId, ordered.map((post) => post.id))
  const posts = ordered.map((post) => toFeedPost(post, post.fresh, social.get(post.id)))

  return {
    tab,
    generatedAt: nowMs,
    prevOpenedAt,
    capabilities: feedCapabilities(),
    franchises: referencedFranchises(posts, franchisesById, statusOf),
    posts,
    trending,
  }
}

// ---------- One post: detail, Saved, Reminders ----------

/** The franchise a post id belongs to, from the database (announcement row, member row, or the id). */
async function franchiseIdForPost(postId: string): Promise<string | null> {
  const parsed = parseSubject(postId)
  if (!parsed) return null
  switch (parsed.kind) {
    case 'news': {
      const [row] = await db
        .select({ franchiseId: announcements.franchiseId })
        .from(announcements)
        .where(eq(announcements.id, parsed.announcementId))
        .limit(1)
      return row?.franchiseId ?? null
    }
    case 'catalog': {
      const [row] = await db
        .select({ franchiseId: franchiseMember.franchiseId })
        .from(franchiseMember)
        .where(eq(franchiseMember.mediaId, parsed.mediaId))
        .limit(1)
      return row?.franchiseId ?? null
    }
    case 'trailer':
      return parsed.franchiseId
    case 'episode':
      return null
  }
}

/**
 * `composePostById`, canonicalised: a `catalog:<mediaId>` whose part an announcement of the same
 * franchise already names (`announcementForPart`, the rule adoption and every write share) is served
 * as that announcement's `news:<id>` post (the id the feed and the thread use since adoption). Falls
 * back to the catalogue post when the news post cannot be composed.
 */
function composeCanonical(
  input: ComposeInput,
  postId: string,
  opts: ComposeByIdOptions = {},
): { post: ComposedPost; live: boolean } | null {
  const parsed = parseSubject(postId)
  if (parsed?.kind === 'catalog') {
    for (const f of input.franchises) {
      const part = f.parts.find((p) => p.mediaId === parsed.mediaId)
      if (!part) continue
      const match = announcementForPart(part, input.announcements.get(f.id) ?? [], f.parts)
      if (match) {
        const aliased = composePostById(input, formatSubject({ kind: 'news', announcementId: match.id }))
        if (aliased) return aliased
      }
      break
    }
  }
  return composePostById(input, postId, opts)
}

/**
 * The trailer ids among `postIds` that did not compose, mapped to their thread's first activity —
 * only those somebody still holds a row on. A delisted trailer nobody touched stays gone.
 */
async function orphanTrailerTimes(postIds: readonly string[]): Promise<Map<string, number>> {
  const trailers = postIds.filter((id) => parseSubject(id)?.kind === 'trailer')
  return trailers.length > 0 ? firstActivityAt(trailers) : new Map()
}

/** Everything `composePostById` needs for a set of franchises, loaded in one batch. */
async function loadComposeInput(franchiseIds: string[], userId: string, nowMs: number): Promise<{
  input: ComposeInput
  franchisesById: Map<string, Franchise>
  statusById: Map<string, WatchStatus>
}> {
  const [loaded, history] = await Promise.all([getFeedFranchises(franchiseIds, userId), loadResearchHistory(franchiseIds)])
  return {
    input: {
      franchises: loaded.franchises,
      observations: history.observations,
      announcements: history.announcements,
      memberAddedAt: loaded.memberAddedAt,
      externalIds: loaded.externalIdById,
      nowMs,
    },
    franchisesById: new Map(loaded.franchises.map((f) => [f.id, f])),
    statusById: loaded.statusById,
  }
}

/**
 * `GET /feed/posts/:id`: the post (composed even when the feed no longer carries it, D16), its
 * author row, the storyline and the thread's sources. A post the viewer hid is still served — they
 * followed a link to it. Null when the id names nothing that can be composed.
 */
export async function getPostDetail(userId: string, postId: string, nowMs: number = Date.now()): Promise<FeedPostDetailResponse | null> {
  const franchiseId = await franchiseIdForPost(postId)
  if (!franchiseId) return null
  const [{ input, franchisesById, statusById }, anchors] = await Promise.all([
    loadComposeInput([franchiseId], userId, nowMs),
    readVisitAnchors(userId),
  ])
  const f = franchisesById.get(franchiseId)
  if (!f) return null
  let composed = composeCanonical(input, postId)
  if (!composed) {
    // A trailer whose video was delisted keeps its thread while anyone holds a row on it.
    const orphanTrailerAt = (await orphanTrailerTimes([postId])).get(postId)
    if (orphanTrailerAt != null) composed = composeCanonical(input, postId, { orphanTrailerAt })
  }
  if (!composed) return null
  const { post, live } = composed
  const social = await loadPostSocial(userId, [post.id])
  return {
    post: toFeedPost(post, isFresh(post.discoveredAt, anchors.prevOpenedAt), social.get(post.id)),
    franchise: toFeedFranchise(f, statusById.get(f.id) ?? null),
    live,
    storyline: storyline(post.thread, nowMs),
    threadSources: threadSources(post.thread, nowMs),
    capabilities: feedCapabilities(),
  }
}

/** A viewer's saved or reminded posts, newest first, each composed from its own franchise. */
async function postCollection(
  rows: readonly { postId: string; franchiseId: string; createdAt: Date }[],
  userId: string,
  nowMs: number,
): Promise<{ items: { postId: string; at: number; post: FeedPost | null }[]; franchises: FeedFranchise[] }> {
  if (rows.length === 0) return { items: [], franchises: [] }
  const franchiseIds = [...new Set(rows.map((row) => row.franchiseId))]
  const [{ input, franchisesById, statusById }, anchors] = await Promise.all([
    loadComposeInput(franchiseIds, userId, nowMs),
    readVisitAnchors(userId),
  ])
  const composed = rows.map((row) => composeCanonical(input, row.postId)?.post ?? null)
  // A saved or reminded trailer whose video was delisted: the viewer's own row keeps it composable.
  const orphans = await orphanTrailerTimes(rows.flatMap((row, i) => (composed[i] ? [] : [row.postId])))
  if (orphans.size > 0) {
    rows.forEach((row, i) => {
      const orphanTrailerAt = composed[i] ? null : orphans.get(row.postId)
      if (orphanTrailerAt != null) composed[i] = composeCanonical(input, row.postId, { orphanTrailerAt })?.post ?? null
    })
  }
  const social = await loadPostSocial(
    userId,
    composed.flatMap((post) => (post ? [post.id] : [])),
  )
  const items = rows.map((row, i) => {
    const post = composed[i] ?? null
    return {
      postId: row.postId,
      at: row.createdAt.getTime(),
      post: post ? toFeedPost(post, isFresh(post.discoveredAt, anchors.prevOpenedAt), social.get(post.id)) : null,
    }
  })
  const franchises = referencedFranchises(
    items.flatMap((item) => (item.post ? [item.post] : [])),
    franchisesById,
    (id) => statusById.get(id) ?? null,
  )
  return { items, franchises }
}

/** `GET /me/saved`. `post: null` = the post can no longer be composed (its part or show is gone). */
export async function getSaved(userId: string, nowMs: number = Date.now()): Promise<SavedResponse> {
  const rows = await db
    .select({ postId: saves.postId, franchiseId: saves.franchiseId, createdAt: saves.createdAt })
    .from(saves)
    .where(eq(saves.userId, userId))
    .orderBy(desc(saves.createdAt), asc(saves.postId))
  const { items, franchises } = await postCollection(rows, userId, nowMs)
  return { items: items.map(({ postId, at, post }) => ({ postId, savedAt: at, post })), franchises }
}

/** `GET /me/reminders`, the same shape. */
export async function getReminders(userId: string, nowMs: number = Date.now()): Promise<RemindersResponse> {
  const rows = await db
    .select({ postId: reminders.postId, franchiseId: reminders.franchiseId, createdAt: reminders.createdAt })
    .from(reminders)
    .where(eq(reminders.userId, userId))
    .orderBy(desc(reminders.createdAt), asc(reminders.postId))
  const { items, franchises } = await postCollection(rows, userId, nowMs)
  return { items: items.map(({ postId, at, post }) => ({ postId, remindedAt: at, post })), franchises }
}
