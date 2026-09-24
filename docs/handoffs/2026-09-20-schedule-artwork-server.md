# Cancelled: artwork-enrichment handoff

**Do not execute this handoff.** The user identified a duplicate-identity issue and
explicitly asked to ignore this investigation. No server fix or deployment was made.
The current task is landscape-logo placement in iOS.

The unimplemented regression-test scaffold is preserved as
`docs/handoffs/cancelled-artwork-persistence-test.ts.txt`, outside the active test
suite. The notes below are historical context, not current deployment instructions.

## Historical authorization and scope

The user requested: **“Fix the bug and deploy then verify.”** They then requested
handover to the Mac mini agent. Complete the server fix and deployment on the actual
AniTrack/Previously backend, not a laptop development server.

Repository: `git@github.com:shan2new/animetracker.git`.
Production API: `https://anime.cognipin.com`.

Preserve unrelated work. The laptop has substantial uncommitted iOS design changes;
they are not part of this server deployment. Do not reset, overwrite, or deploy them.
Do not change subscriptions, watched progress, authentication, or provider identity.

## Exact status at handoff

- The server persistence bug is identified but **not fixed or deployed yet**.
- A new local, uncommitted test file exists:
  `server/src/services/catalogEnrichment.artwork.test.ts`.
- Running `npm test -- src/services/catalogEnrichment.artwork.test.ts` from `server/`
  gives **4 failing / 1 passing**: the write has no `artwork` field. These are intentional
  reproduction failures, not a verified implementation.
- No server source, production records, or remote Git state has been changed.
- The test file is local to the laptop; do not assume it is on the Mac mini or in Git.
  Recreate the regression cases below if it is not supplied separately.
- This app exposes only local tasks/projects. No Mac mini task was dispatched.

## Confirmed evidence

The app's cached server library payload was inspected on 20 September 2026:

| Series | Catalogue owner | Main landscape | Graphic logos returned |
| --- | --- | --- | --- |
| Bleach: Thousand-Year Blood War | TMDB | TMDB | 0 |
| Re:ZERO -Starting Life in Another World- | AniList | TMDB | 4, from TMDB |
| The Witcher | TMDB | TMDB | 6, from TMDB |

Bleach franchise UUID: `1cff170d-c39c-4c11-b746-fdd6253a2c4c`.
Bleach's selected landscape is
`https://image.tmdb.org/t/p/w1280/jWiN3i73wPzHjbEHxtHwIrBTMF5.jpg`.
The cached franchise and all four season galleries contain no logos. The landscape
itself has no embedded series name. Query the live record again before any repair;
its external TMDB show ID has not been resolved on the laptop.

This is not evidence that all artwork comes from AniList. The project uses TMDB,
not TheTVDB. Upstream availability of a Bleach logo is **not yet verified**: the
laptop's server environment has no TMDB token. Use the Mini's existing configured
provider access without printing or copying secrets.

## Root cause and implementation

In `server/src/services/catalogEnrichment.ts`, `refreshFranchiseEnrichment`:

1. The TMDB branch calls `getShow(externalId, { enrichment: true })`.
2. `server/src/tmdb/client.ts` includes `images` in that enriched request.
3. The branch only persists `{ enrichment: value, updatedAt: new Date() }`.
   It discards the fetched artwork gallery.

`tmdbArtwork(show)` in `server/src/tmdb/mapping.ts` already maps portrait, landscape,
and logo URLs, dimensions, language, and score. Persist that gallery alongside the
metadata. Preserve existing alternatives when the provider response is sparse,
deduplicate URLs, and retain the project's orientation-specific ranking via
`rankArtwork` in `server/src/util/artwork.ts`.

Do not change the selected `cover`/`banner`, catalogue owner, or user progress as a
side effect of this metadata repair. No schema or API-contract change is needed.

Fresh full metadata is skipped for seven days by `stillFresh`. Therefore shipping
the write alone does not immediately repair an already-fresh row. Use the existing
`force: true` refresh option for the explicitly identified affected record after
deployment. Avoid an unbounded catalogue-wide backfill.

## Regression cases

Mock DB reads/writes, `getShow`, and `syncRecommendationEdges`; no live DB required.

1. Enriched TMDB response persists all three artwork orientations, including logo
   dimensions/language needed by the iOS renderer.
2. A response missing its images payload preserves stored artwork/logos.
3. Existing alternatives survive; a repeated URL with newly known dimensions is
   upgraded and appears once, following `rankArtwork` order.
4. Fresh metadata normally skips fetching, but `force: true` repairs its missing
   artwork gallery.
5. A null/404 show response performs no database write or recommendation update.

Also assert the enrichment write does not include `cover`, `banner`, `source`, or
`externalId`. Run `npm run typecheck` and the complete `npm test` suite in `server/`.

## Deployment and live verification

1. Inspect the Mini's real checkout, branch, dirty state, deployed revision, and
   service supervisor. Follow its existing deployment process; keep a rollback
   path. `docs/beta-release.md` confirms this backend is self-hosted on the Mini.
2. Deploy only the scoped server change and tests, then restart the AniTrack service.
   No migration is required. Do not restart unrelated apps/services.
3. Check `/health` and run the existing production auth smoke test:
   `npm run auth:smoke -- https://anime.cognipin.com`.
   Production must continue rejecting the development bearer with 401.
4. Read the live Bleach record to establish its exact external ID and old gallery.
   Fetch upstream TMDB artwork to establish whether a usable logo exists.
5. Force the corrected enrichment for that UUID, then read the persisted gallery
   and authenticated `/me/library` and `/franchises/:id` responses. Report actual
   before/after counts, selected landscape, logo dimensions, and source.
6. If TMDB has no valid logo for that exact record, report that truthfully; do not
   invent a logo or reassign the series to a different catalogue entry.
7. Verify the signed-in iOS app after refreshing from production: Schedule should
   show the real landscape and graphic logo together. Check a TMDB show with an
   existing logo and Re:ZERO as regressions. Do not mutate watched progress merely
   to test artwork. API proof and rendered UI proof are separate requirements.

## Laptop simulator context, if verification returns here

- UDID: `C2AED006-C1A7-49DF-B7B4-764B35373C11`, iOS 27 / iPhone 14 Pro.
- Bundle: `com.anitrack.app`; already authenticated. Do not uninstall or sign out.
- Existing signed app: `/tmp/animetracker-today-signed/Build/Products/Debug-iphonesimulator/AniTrack.app`.
- Launch for deterministic, non-writing visual fixtures:
  `-demoBusy 1 -todayDemo multiple -openTab schedule`.
  These rewrite episode/progress display data only; artwork is from the server.
- The shared landscape-selection bug was already corrected locally: a missing
  graphic logo no longer makes `ArtworkScene` discard an available landscape.
- Previous evidence: `/tmp/previously-today-qa/schedule-landscape-final.png`.
- DeviceInteraction/touch tools were unavailable; screenshot checks must not be
  described as interaction or persistence verification.
- Existing large-text calendar clipping is separate from this server fix.

## Access caveat

The laptop's `aura-prod` SSH alias is a forced, **read-only Aura** command interface,
not an AniTrack deployment route. Do not attempt to bypass that restriction. The
Mac mini agent should use its existing local AniTrack checkout and supervisor.

## Completion report

Keep the user update concise: deployed revision, tests/health result, Bleach's real
before/after logo count, and screenshot or explicit UI-verification limitation.
Do not call a local patch or passing build a completed production deployment.
