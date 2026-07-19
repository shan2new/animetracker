# CLAUDE.md

Working notes for agents. **`README.md` covers the architecture, what each top-level dir is, and
how to run the backend + iOS app — read it first; this file does not repeat it.** Below is only the
stuff that isn't obvious from reading the code: conventions, workflows, and gotchas.

## Where things live

- `server/` — Fastify + Drizzle + Postgres backend. The only part with automated tests.
- `ios/` — SwiftUI app (XcodeGen-generated project). `ios/README.md` has the iOS-specific setup.
- `docs/api-contract.md` — the REST contract both sides build against. **Change this whenever a
  route's request/response shape changes**; the iOS models (`ios/Sources/Models/Models.swift`) and
  server view-models (`server/src/services/franchiseView.ts`, `types/api.ts`) must stay in sync with it.
- `legacy-web/` — the retired React/Vite app. Reference only; do not extend it.

## Commands (run from `server/`)

```bash
npm run typecheck      # tsc --noEmit — run after any server edit
npm test               # vitest (grouping logic). Fast, no DB needed.
npm run dev            # tsx watch, http://localhost:8787
npm run db:generate    # regenerate SQL migration after editing src/db/schema.ts
npm run db:migrate     # apply migrations to DATABASE_URL
npm run seed -- 60     # seed N trending franchises (hits AniList + LLM)
npm run group -- 16498 # group one franchise by AniList media id
npm run tv -- 95396    # materialize one TV franchise by TMDB show id (needs TMDB_ACCESS_TOKEN)
```

iOS has no CLI test/build flow here — after editing `project.yml` run `cd ios && xcodegen generate`,
then build in Xcode (or `xcodebuild -scheme AniTrack` — a shared scheme exists for CLI builds).
**Never hand-edit `AniTrack.xcodeproj`** (gitignored, regenerated).

## Two sources: AniList (anime) + TMDB (general TV)

Franchises carry `source` (`anilist` | `tmdb`); a franchise never mixes sources.
TV is deterministic — one TMDB show = one franchise, seasons as members (`sequence` =
season_number), **zero LLM**; all mapping lives in `src/tmdb/mapping.ts` (pure, unit-tested).
TMDB media rows share the integer `media.id` keyspace via `id = 1e9 + tmdb season id` — never
change `TMDB_ID_OFFSET`. Search suppresses TMDB hits that are JP animation (AniList owns those).
TMDB air dates are **date-only**; `airingAt` is synthesized at 17:00 UTC, so iOS gates episode
notifications/Live Activities to `source == .anilist`. `TMDB_ACCESS_TOKEN` unset = TV disabled
(anime-only mode; everything still works). Sync jobs must stay source-filtered — never feed
offset ids to AniList (`refreshAiring`/`attachNewSeasons` filter on `source='anilist'`).

## Server conventions

- **ESM with explicit `.js` import extensions.** `verbatimModuleSyntax` + `moduleResolution:
  Bundler` are on, so imports of local `.ts` files must be written `from './foo.js'` and
  type-only imports must use `import type`. Match the existing style or `tsc` fails.
- **Env is validated through Zod** in `src/env.ts` — never read `process.env` directly elsewhere.
  Booleans use the `envBool` helper (`z.coerce.boolean()` is wrong for `"0"`; the comment explains).
  Every key with a default must also appear in `.env.example` (they drifted once — keep them synced).
- **One shared Postgres pool** (`src/db/index.ts`, `postgres(..., { max: 10 })`). Import `db`/`sql`
  from there; don't open new connections. Long-running work (the LLM grouper) runs **outside**
  transactions on purpose so it doesn't pin a pooled connection — see `grouping/service.ts`.
- **Auth**: routes that need a user call `app.addHook('preHandler', app.authenticate)` (see
  `routes/me.ts`). `authenticate` (`auth/clerk.ts`) attaches `req.user`; access it as `req.user!`.
  Locally, `DEV_AUTH_BYPASS=1` accepts `Authorization: Bearer dev:<clerkId>` with no real Clerk JWT.
- **Routes** are Fastify plugins (`FastifyPluginAsync`) registered in `server.ts`. Validate bodies
  with Zod inline (`z.object({...}).parse(req.body)`), as the existing routes do.
- **Schema → migration flow**: edit `src/db/schema.ts`, then `npm run db:generate` (writes a new
  file under `server/drizzle/` + updates `meta/_journal.json`). **Never edit generated SQL or the
  journal by hand.** Apply with `npm run db:migrate`.

## Grouping / LLM cost (the part most likely to confuse)

`grouping/service.ts` builds canonical franchises by expanding AniList relation components, then
grouping. The LLM is only worth spending on when a `SIDE_STORY` might actually be a separate work.

- `groupingTier()` (`grouping/llm.ts`) is the **cost lever**: single-member or no-side-story
  components return `deterministic` (zero LLM tokens); one side-story → `standard` (cheap model);
  ≥2 distinct side-story targets → `escalate` (stronger model).
- `pickGrouper()` (`grouping/service.ts`): the **escalate tier intentionally ignores the
  `modelOverride`** (the bulk-cron model) and always uses `OPENROUTER_MODEL_ESCALATE` — so the
  nightly bulk cron can't downgrade the genuinely ambiguous cases. This is by design (see the
  comment there); don't "simplify" the `||` chain away.
- Provider selection (`makeGrouper`): **Cerebras wins when `CEREBRAS_API_KEY` is set** (cheap/fast,
  the `model` arg then doesn't apply); else OpenRouter; else deterministic. The shared
  OpenAI-compatible Cerebras request lives in `util/cerebras.ts` (`cerebrasChat`) — reused by both
  franchise grouping and zero-result search correction (`services/queryCorrect.ts`).
- `GROUPING_LLM_DISABLED=1` forces deterministic grouping (no key / offline dev).

## Scheduled sync

`startCron()` (`sync/cron.ts`) is started in `index.ts` at boot: hourly `refreshAiring` (airing
schedules / "out now"), daily 03:30 `seedTrending` + `attachNewSeasons`. It runs in-process — there
is no separate worker. A restart re-arms the schedules; it does not replay missed runs.

## iOS conventions

- Presentation is **derived, not stored**: `Models.swift` computes display fields (`displayRelease`,
  `releaseSortKey`, `isFutureInstallment`, sort keys like `nextAiringSortKey`/`lastAiredSortKey`)
  from the raw API status/release fields. Keep this logic in the model layer, not the views, and
  reuse the existing sort-key accessors instead of re-inlining `?? .max` / `?? 0` sentinels.
- Shared design system lives in `Sources/DesignSystem/` — reuse it: `Theme` (colors/metrics),
  `scaledFont` (Dynamic Type; don't add `.font(.system(size:))`), `Thumb`/`RemoteImageView` for
  cover art (pass a `maxPixel` sized to the display, not the 700px grid default), `CardModel` for
  derived card state. `ImageLoader`/`CachedAsyncImage` is the single image pipeline.
- `API_BASE_URL` is a build setting in `project.yml` → `Info.plist` → `AppConfig.apiBaseURL`.

## Don't commit

- `ios/build/` (Xcode DerivedData + SwiftPM checkouts — gitignored via `ios/.gitignore`).
- `server/.env` and any **DB dump** (`*.dump` / `*.sql` snapshots contain user emails + Clerk ids).

## Moving the backend (DB migration)

Code moves via git. The data does not — take a dump and restore it on the new host (e.g. Mac mini):

```bash
# On the current machine (Postgres 16, db name `anitrack`):
pg_dump anitrack -Fc --no-owner --no-privileges -f anitrack.dump   # custom format (recommended)
# or plain SQL: pg_dump anitrack --no-owner --no-privileges -f anitrack.sql

# On the Mac mini (after installing Postgres + cloning the repo):
createdb anitrack
pg_restore --no-owner --no-privileges -d anitrack anitrack.dump    # or: psql anitrack < anitrack.sql
```

The dump includes the `drizzle.__drizzle_migrations` bookkeeping table, so a restored DB is already
at the current migration — `npm run db:migrate` against it is a no-op (don't `createdb` + migrate
*instead* of restoring, or you'll get an empty schema with none of the data).
Then set `server/.env` (`DATABASE_URL`, Clerk + OpenRouter/Cerebras keys) and `npm run dev`.
A dump taken on 2026-06-24 lives at `../anitrack-2026-06-24.{dump,sql}` (one level above the repo).
