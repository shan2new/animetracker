import { relations, sql } from 'drizzle-orm'
import {
  bigint,
  index,
  integer,
  jsonb,
  pgTable,
  primaryKey,
  real,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from 'drizzle-orm/pg-core'
import type { FranchiseUpcoming } from '../types/api.js'

// ---------- Cached AniList catalogue ----------

// One trackable installment (a single season / movie / OVA / special), cached locally.
// source 'anilist': id = AniList media id, externalId null.
// source 'tmdb': id = TMDB_ID_OFFSET + TMDB season id (see tmdb/mapping.ts), externalId = TMDB season id.
export const media = pgTable(
  'media',
  {
    id: integer('id').primaryKey(),
    source: text('source').notNull().default('anilist'), // anilist | tmdb
    externalId: integer('external_id'), // provider-native id for non-anilist rows
    titleRomaji: text('title_romaji'),
    titleEnglish: text('title_english'),
    format: text('format'), // TV | TV_SHORT | MOVIE | OVA | ONA | SPECIAL | MUSIC
    status: text('status'), // FINISHED | RELEASING | NOT_YET_RELEASED | CANCELLED | HIATUS
    episodes: integer('episodes'),
    cover: text('cover'),
    banner: text('banner'),
    description: text('description'),
    genres: jsonb('genres').$type<string[]>().default([]),
    // nextAiringEpisode snapshot: { episode, airingAt(seconds) } | null
    nextAiringEpisode: jsonb('next_airing_episode').$type<{ episode: number; airingAt: number } | null>(),
    seasonYear: integer('season_year'),
    season: text('season'),
    popularity: integer('popularity'),
    trending: integer('trending'),
    // Exact last-aired time (ms epoch) from airingSchedules, kept fresh by the sync job.
    lastAiredAt: bigint('last_aired_at', { mode: 'number' }),
    fetchedAt: timestamp('fetched_at', { withTimezone: true }).defaultNow().notNull(),
  },
  (t) => [
    uniqueIndex('media_source_external_uq')
      .on(t.source, t.externalId)
      .where(sql`${t.source} = 'tmdb'`),
  ],
)

// Directed relation edges between media (PREQUEL, SEQUEL, SIDE_STORY, PARENT, ALTERNATIVE, ...).
export const mediaRelations = pgTable(
  'media_relations',
  {
    mediaId: integer('media_id').notNull(),
    relatedId: integer('related_id').notNull(),
    relationType: text('relation_type').notNull(),
  },
  (t) => [
    primaryKey({ columns: [t.mediaId, t.relatedId, t.relationType] }),
    index('media_relations_media_idx').on(t.mediaId),
  ],
)

// ---------- Canonical franchises ----------

export const franchise = pgTable(
  'franchise',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    source: text('source').notNull().default('anilist'), // anilist | tmdb
    externalId: integer('external_id'), // TMDB show id for tmdb franchises
    title: text('title').notNull(),
    primaryMediaId: integer('primary_media_id'),
    cover: text('cover'),
    banner: text('banner'),
    description: text('description'),
    genres: jsonb('genres').$type<string[]>().default([]),
    groupingSource: text('grouping_source').notNull().default('relations'), // relations | llm | manual | tmdb
    groupingModel: text('grouping_model'),
    confidence: real('confidence'),
    // Web-sourced "what's next" news (announced/airing seasons & films). See FranchiseUpcoming.
    upcoming: jsonb('upcoming').$type<FranchiseUpcoming>(),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
  },
  (t) => [
    // One TMDB show can never become two franchises.
    uniqueIndex('franchise_source_external_uq')
      .on(t.source, t.externalId)
      .where(sql`${t.source} = 'tmdb'`),
  ],
)

// A media belongs to exactly one franchise (media_id is the PK).
export const franchiseMember = pgTable(
  'franchise_member',
  {
    mediaId: integer('media_id').primaryKey(),
    franchiseId: uuid('franchise_id')
      .notNull()
      .references(() => franchise.id, { onDelete: 'cascade' }),
    partKind: text('part_kind').notNull(), // season | movie | ova | ona | special | music
    sequence: integer('sequence').notNull().default(0),
    label: text('label'),
    addedAt: timestamp('added_at', { withTimezone: true }).defaultNow().notNull(),
  },
  (t) => [index('franchise_member_franchise_idx').on(t.franchiseId)],
)

// ---------- Users & their library ----------

export const users = pgTable('users', {
  id: uuid('id').primaryKey().defaultRandom(),
  clerkId: text('clerk_id').notNull().unique(),
  email: text('email'),
  lastOpenedAt: bigint('last_opened_at', { mode: 'number' }).default(0).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
})

export const subscriptions = pgTable(
  'subscriptions',
  {
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    franchiseId: uuid('franchise_id')
      .notNull()
      .references(() => franchise.id, { onDelete: 'cascade' }),
    status: text('status').notNull().default('planned'), // watching | completed | planned
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  },
  (t) => [primaryKey({ columns: [t.userId, t.franchiseId] })],
)

// Per-user, per-part watched-episode count.
export const progress = pgTable(
  'progress',
  {
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    mediaId: integer('media_id').notNull(),
    episodesWatched: integer('episodes_watched').notNull().default(0),
    updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
  },
  (t) => [primaryKey({ columns: [t.userId, t.mediaId] })],
)

// ---------- Announcements & notifications ----------

// One row per distinct piece of upcoming-installment news for a franchise ("Season 4",
// "Infinity Castle Part 2"), written by the news agent. Re-observations of the same news
// bump lastSeenAt; a status upgrade (rumored → announced → dated) or a release window
// materially changing is what triggers notifications, not the row's existence.
export const announcements = pgTable(
  'announcements',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    franchiseId: uuid('franchise_id')
      .notNull()
      .references(() => franchise.id, { onDelete: 'cascade' }),
    // Normalized form of `next` ("season 4") so the same installment reported with varying
    // wording across runs maps to one row. Unique per franchise.
    dedupeKey: text('dedupe_key').notNull(),
    status: text('status').notNull(), // rumored | announced_no_date | announced | upcoming_dated | airing | recently_aired | concluded
    next: text('next').notNull(), // e.g. "Season 4", "Infinity Castle - Part 2 (movie)"
    release: text('release').notNull(), // human-readable window: "2026-10", "January 2027", "TBA"
    note: text('note'),
    source: text('source'),
    firstSeenAt: timestamp('first_seen_at', { withTimezone: true }).defaultNow().notNull(),
    lastSeenAt: timestamp('last_seen_at', { withTimezone: true }).defaultNow().notNull(),
  },
  (t) => [uniqueIndex('announcements_franchise_dedupe_idx').on(t.franchiseId, t.dedupeKey)],
)

// Per-user notification inbox. Fanned out from announcements to subscribers at detection time
// so reads are a single indexed scan; readAt is null until the client acknowledges.
export const notifications = pgTable(
  'notifications',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    franchiseId: uuid('franchise_id')
      .notNull()
      .references(() => franchise.id, { onDelete: 'cascade' }),
    announcementId: uuid('announcement_id').references(() => announcements.id, { onDelete: 'cascade' }),
    kind: text('kind').notNull(), // news_rumored | news_announced | news_dated
    title: text('title').notNull(), // franchise title, e.g. "Jujutsu Kaisen"
    body: text('body').notNull(), // e.g. "Season 4 announced — release TBA"
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
    readAt: timestamp('read_at', { withTimezone: true }),
  },
  (t) => [index('notifications_user_created_idx').on(t.userId, t.createdAt)],
)

// Cron / sync bookkeeping (single-row keyed values).
export const syncState = pgTable('sync_state', {
  key: text('key').primaryKey(),
  value: jsonb('value').$type<Record<string, unknown>>(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
})

// ---------- ORM relations (for query convenience) ----------

export const franchiseRel = relations(franchise, ({ many }) => ({
  members: many(franchiseMember),
}))

export const franchiseMemberRel = relations(franchiseMember, ({ one }) => ({
  franchise: one(franchise, { fields: [franchiseMember.franchiseId], references: [franchise.id] }),
  media: one(media, { fields: [franchiseMember.mediaId], references: [media.id] }),
}))
