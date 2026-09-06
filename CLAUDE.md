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
change `TMDB_ID_OFFSET`. JP animation belongs to AniList, so its TMDB twin is suppressed — enforced
inside `ensureTvFranchise` (the only thing that creates a TMDB franchise), *not* in its callers, so
`npm run tv` and any future call site inherit the rule. Search/trending pre-filter too, to skip the
`/tv/{id}` fetch.
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

- **The deployment target is iOS 18.0, and every iOS 26 API is GATED, never removed** (3 Sep).
  iOS 17 and iOS 18 support the identical iPhone set (XR/XS and later, A12+ — Apple kept 17's
  device list for 18), while iOS 26 needs an iPhone 11, so 18 already reaches every phone 26
  excludes and going to 17 would buy nothing while costing the `onGeometryChange` scroll probes
  (18 sites), the `Tab { }` builder and Schedule's `onScrollTargetVisibilityChange`. **Never call
  an iOS 26 symbol directly from a screen** — route it through the gated shim in
  `DesignSystem/GlassHelpers.swift`, which is the one home for "iOS 26 flourish, graceful fallback":
  `glassChrome` (→ `.ultraThinMaterial`), `chromeScrollEdgeHidden(_:)` / `chromeScrollEdgeHard(_:)`
  (no-ops below 26 — there is no system scroll-edge effect to suppress or harden),
  `chromeTabBarMinimizeOnScroll()`, `chromeSharedBackgroundHidden()` (a `ToolbarContent` extension:
  below 26 a toolbar item has no shared glass capsule to drop) and `chromeNavigationSubtitle(_:)`.
  `ToolbarSpacer` is gated inline in Detail's toolbar because it is a `ToolbarContent` *value*, not
  a modifier. The shims take a local `ChromeEdge` enum rather than Apple's edge set: a signature
  that names an iOS 26 type will not compile against an 18 target even when every call is inside
  `if #available`. The Icon Composer `AppIcon.icon` needs no fallback work — actool already emits
  `AppIcon60x60@2x.png` + `CFBundleIcons` for pre-26 alongside the layered asset.
- Presentation is **derived, not stored**: `Models.swift` computes display fields (`displayRelease`,
  `releaseSortKey`, `isFutureInstallment`, sort keys like `nextAiringSortKey`/`lastAiredSortKey`)
  from the raw API status/release fields. Keep this logic in the model layer, not the views, and
  reuse the existing sort-key accessors instead of re-inlining `?? .max` / `?? 0` sentinels.
- **Cohesion rules (2026-08-30 pass, header/hero/veil rules revised 2026-09-02):** one ambient-wash
  spec app-wide (`ThemeMetrics.rootWashHeight/rootWashIntensity` — never a private height/intensity
  pair); **one section-header family: `SectionHeaderRow`** — `ThemeType.sectionTitle` (Outfit
  SemiBold 20, mixed case) with the count on its baseline and a trailing chevron when the header
  navigates (the title IS the button; no "See all" word — the Apple TV / Netflix shelf grammar);
  `inlineAction: true` keeps a trailing text link for a command on the section ("Clear"). Small-caps
  `SectionLabel` is an EYEBROW only now (`OverArtLabel` over art, grouped-list headers, sheet
  labels) — never a shelf header. Schedule's day headers ("TODAY · THU 3 SEP") and its Earlier row
  ARE eyebrows (`sectionLabel`, 3 Sep — they were `sectionTitle` while the rows were `MediaRow`s):
  the airing card under a day names its show at `rowTitle` ten points down, and a day set in
  Outfit SemiBold 20 was the same shape in the same ink, so "Tomorrow" and "Mushoku Tensei" read
  as two rows of one list; a label over a title is the hierarchy every grouped list draws. One wide art card (`BannerCard`, radius `ThemeRadius.card`) instead of
  per-screen landscape cards — and the two lead surfaces are landscape too (3 Sep): Library's
  **Continue watching is an Up Next shelf** (`LibraryContinueShelf`/`LibraryContinueCard`: four
  fifths of the content width, `ProgressBanner` — the ONE 16:9 art-with-progress card, the bar
  inset on the art over a short scrim; the season screen's header is the same view — with the
  next episode named beneath; the centred cover-flow spotlight is gone), and **Schedule's rows
  are COMPACT, and since 7 Sep the DATE RIDES THEM** (`ScheduleDateRow`: a 38-pt date column, an
  88×50 tile, the show, "Episode 16 · 6:30 PM" — no day bands. It was `ScheduleAiringRow` from
  6 Sep, a 104×59 tile under a full-width day band: "6:30 PM · Season 4 ·
  Episode 16", the state ladder's slot — five or six per screen). They were gutter-to-gutter 16:9
  `AiringCard`s from 3 to 6 Sep, at which density only two fit on a screen and no two states could
  be compared; the clock was an `OverArtLabel` pill on the art before that, the least legible place
  for the fact a schedule exists to give. The day BANDS went on 7 Sep (the date rides the row), the
  day rail went the way of the calendar strip on 6 Sep — see the Schedule bullet. **Profile is an account
  sheet** in the App Store's order: a leading identity row (56-pt disc, name, provenance, one
  quiet line "635 episodes · 5 watching · 13 watched" — no plate of numerals), the Watching
  shelf, then Settings (Notifications · Haptics · Export), a footnote "Up to date · Checked just
  now" (the Sync plate only exists while a change failed), Account, Sign out, colophon, Delete.
  **Landscape frames never `.fill` a portrait cover**: pass
  `portraitSource:` (`BannerCard`, `LandscapeArt` in the Search tiles) so a show with no banner is
  composited whole on its own blurred ground. One brand lockup (`Wordmark`, period in text ink —
  Profile's colophon uses `Wordmark(colophon: true)`). **One billboard hero grammar** on Today AND
  Detail: `ArtHeader(portraitSource:)` on `billboardArt` (portrait-first — see the artwork bullet) at 0.68–0.72 × screen, `HeroTopVeil` over the
  chrome band, `HeroCopyScrim` sized to the measured copy (no fractional `ArtScrim` on a billboard),
  title + one identity line ("Anime · 2018 · Action · Adventure") over the foot; Detail docks the
  title into the bar from a `.principal` toolbar item once `scrolledUnderBar`, and its state block
  carries `Copy.Progress.newEpisode(when:)` ("New episode Friday at 7:30 PM"). **Bars are MATERIAL to
  their bottom edge (3 Sep):** the soft top veil hardens when content passes under the BAR (not the
  clock) via `scrollEdgeChromeBody(topRaised:topHold:)` — `topHold` = `ThemeMetrics.inlineBarBottom`
  (+ `searchDrawerHeight` under a search drawer), then `barEdgeRamp` (28) — and "hardened" means
  `ThemeMetrics.chromeBarOpacity` (0.74) canvas over the full-strength blur, NEVER opaque canvas
  (only Reduce Transparency, which has no blur, gets the opaque bar): at 1.0 the top ~100 pt of
  every scrolled screen was a flat #09090B slab ("pure black", 3 Sep) with the material under it
  painted for nothing. Today's wordmark band and Detail's floating toolbar hold through their own
  band the same way, and Detail hardens — and docks its title — the moment the hero's COPY reaches
  the toolbar's bottom edge (`copyTop − band` in the scroll probe, not a flat 130 pt: the title
  used to slide half-lit under the glass capsules for ~80 pt before the bar caught it). **Detail's hardened bar is the show's GLASS, not canvas (4 Sep):**
  `DetailVeils` passes `DetailTint.chrome(heroTint ?? tint)` — the art colour kept as a hue, OKLab
  L 0.26–0.32, chroma ≤ 0.085 — into `ScrollEdgeChrome(color:)`, which paints it at
  `ThemeMetrics.chromeBarTintedOpacity` (0.62; canvas veils keep 0.74) over the full-strength
  blur ("the header colour should match the series colour… too blackish, should be glassish",
  user). The first cut came out the ember's warm grey on every show: `PaletteCache` answered a
  second concurrent resolve of the SAME URL with nil — and `resolve` turned nil into the fallback
  for good — and Detail asks for the poster twice (`tint` and `heroTint`, the billboard being
  portrait-first); `resolveIfAvailable` keeps a `Task` per in-flight URL and the second caller
  awaits it. **A trailer is a STAGE (4 Sep):** `VideoSheet` is a `fullScreenCover` the tapped
  `TrailerCard` zooms into (`matchedTransitionSource` / `navigationTransition(.zoom)`, iOS 18):
  the show's art blurred and breathing across the screen (`ambientArt`, lit a beat after the zoom
  lands), the billboard lockup (`HeroBadge` "TRAILER", `displayXL` title, one line), the trailer's
  still at the screen's width with a glow in the show's colour (`tint`), close and provider glyphs
  in glass circles. `VideoEmbed` sets `allowsInlineMediaPlayback = false`, so the moment YouTube
  autoplays the SYSTEM presents its own full-screen player (transport, scrubbing, AirPlay); the
  still stays ON TOP of the page until then (the provider's loading chrome never shows), a refused
  autoplay uncovers the inline player after 5 s, and `fullscreenState` (KVO) dismisses the stage
  when the viewer leaves the player. The half sheet with a small embed at its top and nothing
  under it was "utter trash"; the black cover "better but not quite there"; the brief was
  "surreal according to 2026 standards. Immersive… absolute bliss to watch" (user). **The app is
  portrait; only the system player rotates (5 Sep):** `project.yml` lists the landscape
  orientations so WebKit's full-screen video controller may rotate, and `App/OrientationGate.swift`
  (an `AppDelegate` reached through `@UIApplicationDelegateAdaptor`, one delegate method) answers
  `.portrait` everywhere except while the trailer stage is up — `VideoSheet` opens the gate on
  appear and closes it on disappear, and the gate calls
  `setNeedsUpdateOfSupportedInterfaceOrientations()` so a phone left on its side comes back upright.
  After `xcodegen generate`, pass BOTH `API_BASE_URL=` and `CLERK_PUBLISHABLE_KEY=` on the
  `xcodebuild` line for a production capture build and check the built `Info.plist`
  (`PlistBuddy -c "Print :APIBaseURL" -c "Print :ClerkPublishableKey"`) — a build came out with
  `localhost:8787` + `REPLACE_ME` on 5 Sep and the sim quietly opened a developer session. Scroll probes are
  `Color.clear.onGeometryChange` on the scroll content, because `onScrollGeometryChange` never fires
  on the iOS 27 sim (Today, Detail, Library, Search all use the probe). **Prose is rationed
  (2026-09-02):** a hero says the state (eyebrow), the episode (fact) and at most one more thing;
  where-you-are is a `ProgressBar` (`MediaRow(progress:)`, the season header), never "11 of 24
  watched" in words; a finished thing is a tick, not "Watched". **Today is never without a
  billboard:** on a calm day the hero is `nextUp` (else the first Watching show) in the waiting
  grammar — no action row, tap opens — over up to three Upcoming rows; there is no headline-only
  calm state. **Episodes are ON the show page** (Apple TV / Netflix), in the streaming apps'
  grammar (4 Sep, "the seasons section is utterly confusing" — the user picked "Episodes + season
  pill" over season chips and a repaired title-as-picker): the section title is "Episodes"
  (`episodesHeader`), the season is a trailing `SeasonPill` capsule menu ("Season 4 ⌄", the bar's
  status-menu family on the canvas) that lists `Franchise.seasonPartsInOrder` — `.season` parts
  that are not spin-offs (`FranchisePart.isSpinOff`, from the server's `relationship`) — NEVER the
  whole episodic catalogue (Slime's picker listed nine entries with OVAs and specials interleaved);
  a `ProgressBar` under the header is where-you-are (the old "18 of 24" numerals beside a window
  that began at Episode 18 read as "showing 18 of 24"). **The list OPENS WHERE YOU ARE (6 Sep, two rounds):** `EpisodeList`
  (DetailSupport — the ONE episode row anatomy, shared with `SeasonEpisodesView`, which now exists
  only for the run an extra opens) draws a season of `wholeBelow` (12) rows or fewer WHOLE; a
  longer one opens on the NEXT episode with `windowBefore` (3) watched rows above it for context
  and `windowAfter` (8) ahead, and everything earlier is one in-place tap up ("Show earlier
  episodes" / "Show more episodes", `InlineLinkButtonStyle` centred, `growBy` 12 a tap — Mail's
  "Load Earlier Messages"; the section header holds its place and the revealed rows fill in under
  it). The first cut of the rebuild drew every season whole and put the row you came for 1,842 pt
  down on Slime S4 (21 of 24 watched — 2.2 screens of watched rows, 3.1 from the top of the page):
  "what about the most recent episode? … otherwise it's a bigger scroll" (user). Three directions
  were built behind `-episodeDirection` and photographed on Slime and Mushoku; the user chose
  ANCHORED, and anchored on the NEXT episode rather than the newest aired. Rejected with reasons
  in `EpisodeList`'s doc: a whole season from Episode 1 with an in-page "Jump to episode 22" link
  (NN/g's in-page link — but the season's first twenty rows are still what the screen opens on),
  and newest-first (Apple Podcasts' EPISODIC order, while Apple itself puts the first episode at
  the top for SERIAL shows — the numbers counted down as you read). Plex users file the same thing
  as a bug when a long season fails to advance to the on-deck episode (plex-media-player #914).
  A finished season anchors at Episode 1: nothing to continue, so it is a browse.
  **The newest AIRED episode you have not watched wears an amber `NEW` tag** on its eyebrow
  (`Copy.Label.newTag`, `onAccent` on `accent`, beside the episode number) — the streaming apps'
  NEW on a tile, and the answer to "how should we highlight the most recent episode": the ring and
  "Next up" stay on the episode you resume from, the tag says which one is news. Amber is STATE
  here, never an action. The 4–6 Sep six-row window with an "All 24 episodes ›" door to a second
  screen was "a complete tangent… a broken experience" (user); it and the overflow's "View
  episodes" are gone, and a Schedule card lands on its row through
  `FranchiseDetailView.landOnFocus` (ONE push; `proxy.scrollTo("ep-n")` at 0.45 s and 1.2 s —
  the list is an eager `VStack` so the row exists to scroll to) instead of the root appending the
  season screen (`DetailRoute.focusPushed` is gone). **The row opens, the ring marks (6 Sep):**
  tapping a row never writes progress — Apple TV's tile plays and its description opens the
  episode, Podcasts keeps "Mark as Played" off the row, Reminders completes on the circle alone
  ("people sometimes are curious to see what the episode details are and unintentionally might
  mark it as completed", user); a row with an overview (or a withheld title) expands in place on
  `uiSnappy` to "55 min · 14 Apr 2019" (`Copy.minutes`; the date only on a watched row, whose
  second line is empty by rule) and the overview under the title column, clear of the ring; a
  bare "Episode 12" row is inert (a tap that does nothing is honest; a tap that marks is a trap).
  **The control is the receipt:** `MarkRing(style: .settled, fill:, committing:)` — history is a
  DISC in the show's quiet colour (`DetailTint.quiet(heroTint ?? tint)` — the BILLBOARD's
  palette, the page's; Reminders fills the circle with the list's colour) with a `textPrimary`
  check, the next episode the ONE accent ring with "Next up" in accent beneath its title, the
  rest idle rings, and NO numeral in the list (the row states the episode 14 pt away — "why does
  it need to show the episode number on the CTA?"; Schedule's and Today's rings keep theirs). A
  mark fills its own ring accent with the check drawing and one pulse (`uiMilestone`, 0.84 → 1),
  holds 0.55 s (`beginCommit`), then settles into the disc on `uiSettle` while the accent ring and
  "Next up" move to the next row; there is NO `ReceiptLine` under a row ("it shows an inline
  response again showing Episode 7 … what is this trashy UX?") — the last watched disc toggles
  back with one tap (its undo), a later ring confirms a batch with its exact count and plays a
  CASCADE (`cascade(from:through:)`: a disc every ~42 ms, ≤ 14 beats, the accent beat travelling
  down the column), an earlier disc confirms a batch unmark, and batch undos ride the LANE
  (`presentUndo` without `.placed`; the lane's fact is `Copy.Toast.batchWatched`, "4 episodes
  watched" — the long form truncated beside the poster). The one single-mark receipt left is
  the series-finishing "Series finished · Moved to Watched", in the lane. The bare tertiary
  check ("the tick mark feels cheap") and `ReceiptHost.episodes` are retired. **The show page
  sits in the show's colour (6 Sep):** `showGround` behind the scroll view —
  `DetailTint.ground(heroTint ?? tint, lightness:)` from `groundTopLightness` 0.19 (about
  `surfaceFlat`'s depth) under the hero to `groundFootLightness` 0.155 at the foot (canvas is
  ≈ 0.14 in OKLab, so the bottom chrome's canvas veil lands on it without a step), chroma ≤ 0.06,
  plus one `plusLighter` pool of the tint at 0.14 — two gradients, no image, nothing per frame;
  `HeroCopyScrim(landing:)` lands on `groundTop`, so the hero has no seam ("the details screen
  should have the theme color veil over the entire screen to make the experience more
  immersive", user; a blurred wash behind the header was tried on 30 Aug and stepped 14 levels at
  the seam because the scrim landed on canvas over it). **Android mirrors this** (6 Sep):
  `WHOLE_BELOW`/`WINDOW_BEFORE`/`WINDOW_AFTER`/`GROW_BY`, `episodeAnchor`, `episodeWindow`,
  `freshEpisode`, the controller's `expanded`/`committing`/`cascadeThrough`/`shown`, `NewTag`,
  `EpisodeDetails`, the expanders, `MarkRingStyle.Settled` with `fill` + `committing`, and the
  "All N episodes ›" door deleted. **`EpisodeRow`'s container had to become a `Column`** — left a
  `Row`, the details laid out BESIDE the row and the list collapsed to a single row on the first
  tap (caught on the emulator, invisible in the source). The remaining iOS-only work is Today's
  6 Sep pass and the iOS-specific keyboard warm-up. Detail's toolbar Add is a bare `plus` glyph (17 semibold,
  `interactive`, 44 pt) — no word in the bar. EVERY episode row carries a 120×68 tile
  (`EpisodeArtwork.slot`): the still, else a TRUE 16:9 landscape (the season's, else the show's —
  `FranchisePart.stillLandscape(within:)`, which skips `ultraWide` AniList banners: a 4.75:1
  banner's middle third in a 120×68 tile was a pair of eyes eighteen times down the list on
  production, 4 Sep), else the season cover under the episode's number
  (`EpisodeStill(landscape:poster:number:)`) — never a bare text row, never a glyph. Profile = disc + name + provenance, a plate of EPISODES (Σ progress) ·
  WATCHING · WATCHED, then a Watching `ShelfCard` shelf that dismisses and opens the show
  (`ProfileView(onOpenDetail:)`), then the grouped settings. **Search has one browse anatomy:** a 3-column `ShelfCard` poster grid at
  rest AND focused (recents rows above it once focused), scopes appear `.onTextEntry`, results
  are `MediaRow`s only (no top-match card, no headers, `.row` slot everywhere); the hardened bar
  hold follows focus (`searchChromeBottom` — the title collapses when the field has focus, so the
  hold shrinks to the drawer; All titles does the same). Profile is disc + name + provenance and
  verb-only settings rows (no poster fan, no subtitles). **States are consumer, not SaaS
  (2026-09-02):** `EmptyState` is `ContentUnavailableView`'s anatomy on the canvas — a 44-pt
  tertiary symbol, a title, one sentence, ONE hugging button (a recovery like "Try again" is the
  quiet capsule; a next step like "Add a show" is the amber one) — no plate, no glyph tile, no
  bloom, no `ambient:`; `InlineNotice` is a footnote line (glyph + metadata + "Retry" link), never
  an alert box; `SyncBanner` wears the toast's glass capsule. State copy says "Couldn't load your
  library" / "You're offline" / "Something went wrong", never "server". **The library has an
  offline copy** (`AppModel.start()` loads `library-cache.json` from Application Support, stamped
  with its real `savedAt` so `StaleStrip`/`InlineNotice` tell the truth; written after every
  successful `reload()`, removed on `teardown()`), so a launch without a network opens on the
  shows, not on an error. To photograph the non-happy states, build with
  `API_BASE_URL=http://localhost:8799` and run the scratchpad `proxy.py` (mode file: pass / down /
  refuse / slow / empty / searcherr / detailfail / writefail); never capture while xcodebuild is
  running — a CPU-starved sim shows a black launch screen for 10 s and it looks like a hang (the
  same happens on the first launch after a reinstall at an accessibility text size; wait 12 s).
  Today's hero carries ONE action — the mark capsule; the block itself opens the show. **The
  hero is a billboard LOCKUP (4 Sep — the 2–3 Sep "slate" with its capsule pill and 34-pt amber
  clock read "like a 3rd grade app" on the device):** state → show → moment → episode, top to
  bottom, in THREE rows (direction B of three photographed side by side, picked 4 Sep after the
  four-row eyebrow/title/moment/episode lockup read "text heavy and cognitively overloaded").
  The BADGE is `HeroBadge` — a filled amber tag, `heroBadge` (SF 11 bold +0.6) in `onAccent`, a
  4-pt corner, the streaming apps' "NEW EPISODE" (Prime Video overlays one on cover art, Disney+
  tags tiles "Season Finale") — and says the STATE only: "NEW EPISODE", "4 EPISODES BEHIND",
  "13 EPISODES LEFT", "CAUGHT UP", "TRENDING", "WHILE YOU WERE AWAY" (Detail's state block and
  the recap wear the same badge; `OverArtLabel` is only the pill for a moment or an episode on
  CARD art). The TITLE is `displayTitle` at `displayXL`, two lines with a 0.82 scale floor — a
  short name gets the full 34, a long one lands on Detail's 28. Then ONE LINE (`heroMeta`,
  secondary): the moment in the app's one temporal ladder, then the episode — "Today at 7:30 PM ·
  Season 4 · Episode 21", "Aired 29 min ago · Season 4 · Episode 12", a backlog's "Season 2 ·
  Episode 7" alone (`momentText`); no countdown, no dot, no fourth line. The bar under it is
  where-you-are; the capsule reads "Mark as watched". `HeroCopyScrim` is lighter and
  longer (lead 132: 0.56 at the copy's top, 0.72 at the title, full canvas 40 pt above the frame's
  bottom) so the copy sits ON the picture and the frame still lands on canvas. Never let the
  reason someone opened the app be the smallest text on it, and never say in words what a
  numeral beside them already says. **Under the hero is ONE shelf, not two lists (4 Sep):** the
  Up next shelf (`upNextShelf` / `upNextCard` — the rest of the queue with its rings, then the
  upcoming airings) in the Library Continue card's geometry (`ProgressBanner`, 4/5 of the content
  width, `.viewAligned`), headed `nextUp` while a card can be marked and `upcoming` when nothing
  has aired; rows only at accessibility sizes. **Today's Up next card wears ONE pill, the
  episode:** `ProgressBanner` draws an "EPISODE 21" `OverArtLabel` bottom-leading, above the bar
  when there is one (top-leading covered faces, which live in the upper part of a crop), and the caption
  beneath is the rows' two-colour grammar (`upNextCaption`): a forward-looking TIME in amber
  ("Sunday at 8:30 PM", today's "Aired 2h ago"), else a count in grey ("9 episodes behind" — Today
  is the urgency room), else the season. A second pill for the moment on the art over a caption
  saying only "Season 5" put the fact that matters in the least readable place ("the Upcoming
  card just feels wrong", user, 4 Sep). **Schedule keeps its own anatomy** — the day in the
  header, the clock leading the caption, "Season 4 · Episode 21" after it; an episode pill on the
  art was tried and reverted the same day, and the art itself went to a 104×59 tile on 6 Sep. **AniList banners decode at their
  native 1900 px** (`WideArt.ultraWide`, decided by the URL `/anime/banner/`, never by `source`
  — an enriched anime franchise may carry a TMDB backdrop, and that IS 16:9; read by
  `LandscapeArt`): a 16:9 frame shows the middle ~37 % of a 4.75:1 banner, so a decode budgeted
  for the frame's edge was drawn at 2.5× and every anime card was soft. The crop itself is fine
  (user, 4 Sep — compositing the cover on the blurred banner was tried and reverted). The anime
  BILLBOARD stays soft because AniList's `/cover/large/` is 460×639 px (measured 4 Sep) drawn at
  1179 px wide; TMDB posters are 2000×3000 — the fix is server-side art enrichment from the TMDB
  twin, not the client.
  **The scroll offset is never screen state.** Today and Detail hold a `ScrollOffset`
  (`@Observable`, Primitives.swift) in `@State` and only their small veil views (`TodayVeils`,
  `DetailVeils`) and `StretchingHeroArt` read `.y` in a body — so a scroll frame invalidates those
  views, never the screen. `set` clamps through `ThemeMetrics.scrollSample` and de-duplicates.
  Bool probes (`raisedTop`, `scrolledUnderBar`) are guarded with `if new != old`. Today has NO
  mask on its scroll view any more (an offscreen pass per frame); the opaque bar covers what
  passes under the wordmark band. Veils are mounted only while on, never held at opacity 0. The
  raw offset as `@State` re-ran Today's entire body at 60–120 Hz on the first swipe ("Today lags",
  2 Sep, twice). Amber selection is legal
  STATE except where amber already means something else in the same control (Schedule's ticker —
  see `ThemeColor.interactive` docs).
- Shared design system lives in `Sources/DesignSystem/` — reuse it, never re-invent:
  `ThemeTokens.swift` (`ThemeColor` / `ThemeSpace` / `ThemeRadius` / `ThemeType` + `.type(_:)` /
  `ThemeMotion` + `pick(_:reduceMotion:)` / `FeedbackCoordinator` — **every haptic goes through it,
  at most one per transaction**), `Copy.swift` (the only place a user-facing string lives — statuses,
  "Episode N" never "E19", confirmations, toasts), `Primitives.swift` + `Primitives+States.swift`
  (`PosterSlot`, button styles, `GroupedList`/`GroupedRow`, `EmptyState`, `InlineNotice`,
  `StaleStrip`, `SyncBanner`, skeletons behind `SkeletonGate`), `Palette.swift` (art-adaptive
  ground), `Util/TemporalCopy.swift` (one temporal expression per item; TMDB date-only never shows
  a clock). No literal colours/sizes in screens. `Thumb`/`RemoteImageView` for cover art (pass a
  `maxPixel` sized to the display); `ImageLoader`/`CachedAsyncImage` is the single image pipeline.
- **Amber is not an action colour.** `ThemeColor.accent` is rationed to MEANING (a real next step —
  "Returns Oct 2", a future air time) and STATE (today, owned, selected, an active filter, a
  committed mark), plus brand and GROUNDS (`PrimaryButtonStyle2`'s capsule, `MarkRing`'s fill,
  `accentSoft` discs — there the ink on top is `onAccent`, so no amber *word* is drawn). Every bare
  tappable word or glyph — "See all", "Read more", "Clear", "Sync now", "Details", "Add", "Done" —
  uses **`ThemeColor.interactive`**, and carries its affordance by position, semibold weight, a
  44-pt target and a chevron where the row has one. One hue cannot mean "this is what's coming" and
  "press this": Detail drew an amber "+ Add" directly above an amber "Episode 14 next", and Library
  put an amber "See all" over amber "Returns Oct 2" captions. This diverges from iOS deliberately —
  Apple tints "See All"; here amber is spent on the fact. Settled 2 Sep (polish pass): the root is
  `.tint(ThemeColor.interactive)`, the `TabView` re-tints `.accent` (a selected tab is state) and
  every tab's `NavigationStack` re-tints `.interactive` again — so back chevrons, alert buttons,
  the search field's Cancel and caret are ink, and only toggles/pickers that mean state carry an
  explicit `.tint(ThemeColor.accent)`.
- **Write rules** (`AppModel`, `AppModel+Writes.swift`): a progress mark never rolls back — a failure
  goes to `SyncCenter.record` and the SyncBanner; membership/status writes roll back. Remove is
  immediate with Undo (`removeWithUndo`), batch marks and season resets confirm with the exact
  count; single marks present their Undo toast when the card's handoff settles (`presentUndo`).
  **Every progress write goes through `AppModel.sendProgress`** (2 Sep polish pass): one PUT in
  flight per part, the newest target waits behind it and superseded targets are dropped, so the
  server always ends on the user's last word (two bare `Task`s could settle it on the older mark).
  `setProgress`/`markCaughtUp`/`performUndo` share that policy — no red "couldn't save" toast, no
  rollback. A failed change carries a `WriteIntent` (progress/status/subscribe/unsubscribe), so a
  row restored from a previous launch retries the write itself (`SyncCenter.replay`, installed in
  `start()`); `teardown()` calls `SyncCenter.teardown()` so the next account inherits nothing.
  `setStatus` presents "Moved to Watching · Undo" (`present: false` inside a transaction such as a
  rewatch); a status write on a pending add records its failure like any other. A neutral receipt
  with no action is `showNotice` (`ToastView(message:)`), e.g. "Episode alerts on".
- Navigation: Detail is a PLAIN PUSH on the active tab's `NavigationPath` (`DetailRoute`,
  `RootView`) — the `.zoom` transition was tried (2 Sep) and retired (3 Sep): it scales the whole
  page into the tapped poster, so the show page opened as a miniature of itself inflating; the
  `zoomSource` registrations stay but nothing consumes them (see `detailDestinations`);
  re-selecting the active tab pops to root — Library also drops its All-titles item destination
  (`LibraryView.popSignal`). A tapped episode alert opens its show: `EpisodeNotifications.onOpen`
  → `AppModel.pendingOpen` → `MainTabView` selects Today and pushes `DetailRoute` (verified with
  `xcrun simctl push` + a banner tap). Alerts: three per watching anime show from `part.airings`,
  round-robin so every show keeps its soonest before any gets its second, armed the moment the
  primer's Allow lands (`alertsWereAllowed`). A Schedule-routed `focus` pushes the season list
  once (`focusConsumed`) — it used to re-push on every pop and trap the user. The tab bar
  minimises on scroll (`tabBarMinimizeBehavior(.onScrollDown)`); docked bar titles (Today, Detail,
  Season, History) use `displayTitle`. Watch sessions live in `RewatchStore` (device-local JSON).
- **Auth hand-off:** `AuthManager.bootstrap()` waits (≤3 s) for `Clerk.shared.isLoaded`, then
  follows `Clerk.shared.auth.events` for session changes; the splash leaves only when both its
  timeline and `auth.bootstrapped` are done (`RootView.handOffIfReady`) — never sign-in for a
  signed-in user. `signOut()` returns whether the session actually ended; Profile alerts if not.
- **A cancelled request is not a failure** (`Error.isCancellation`, APIClient.swift): `reload()`
  and Detail's `load()` ignore it, and `loadError` flips inside `withAnimation(uiGentle)` so every
  "couldn't refresh" footnote fades in instead of shoving the content under it.
- `API_BASE_URL` is a build setting in `project.yml` → `Info.plist` → `AppConfig.apiBaseURL`.
- **Schedule is an agenda** (reworked 2026-08-24, unfolded 2026-09-04, rebuilt 2026-09-06): a plain
  sectioned `LazyVStack`, one section per day that carries something, empty days omitted, the aired
  days simply ABOVE today (the "Earlier" fold and its "3 to watch" row are gone; the feed lands on
  today via `land(proxy)`, twice, because the first pass can run before the lazy sections above
  today have laid out). **Today is the exception — its section is always drawn, empty or not** (it
  prints "Nothing scheduled" as a ROW under its header, at every size), and "today" in this screen always means day 0, never "the first day that
  carries something": with the empty section skipped the feed opened on a future day, the "Today"
  button hid itself (`selectedDay == landing` — by its own test you were already there), and a
  row's bare clock read as tonight.
  **AT REST THE SCREEN HAS NO DATE CHROME (6 Sep, second rebuild — "the calendar part is utterly
  confusing and poorly executed", user).** The feed's day headers ARE the calendar; the bar's
  "Today" button is the way back once you have scrolled away. Four headers × three densities were
  built behind launch arguments and photographed on the real account, and the user chose the MONTH
  GRID on COMPACT rows. What the photographs settled, and must not be re-litigated:
  the DAY RAIL that shipped that morning (capsules for the days that carry something, plus today)
  was **pointing at days the reader was not looking at** — in the capture the feed sat on Wednesday
  2 Sep and Friday 4 Sep and neither day was on the rail, both having scrolled off its left edge
  while the selected capsule said "TODAY" (NN/g's eye-tracking puts ~1 % of attention past the edge
  of a horizontal strip); it named every day twice ("WED 9" in the rail, "WEDNESDAY · 9 SEP" in the
  feed a hundred points below — the same defect that killed the eight-day strip before it); it wore
  the app's own filter-chip shape in the band where filter chips appear; and its jump saved ONE
  flick on a six-airing feed. **A list of only the non-empty days cannot show a month's SHAPE by
  construction** — which weeks are busy, which are spent, which are empty — and that is the one
  thing a calendar is for. Both rejected directions and the rail are deleted, not flagged off.
  **The calendar is `ScheduleMonthGrid`, behind the bar's `calendar` glyph**, and it OVERLAYS the
  feed (Google Calendar's month dropdown) rather than pushing it: 500 pt of grid inserted above a
  lazy stack threw the reader's place three screens down and back on every toggle. ONE glyph in
  both states, tinted accent while the grid is down (a control that changes its symbol on press
  reads as a different control). A tap anywhere off the grid closes it; a tap ON a day closes it
  and scrolls the feed there — leaving it down over the day it just took you to hides the answer
  behind the question. Sunday-first, stated by the app.
  **Its anatomy is Apple Calendar's, because that is the one every reader already knows** (rebuilt
  6 Sep — "Calendar view is utter trash", user, of the first cut): the month NAMED in
  `bodyEmphasis` primary ink ("September 2026", not an 11-pt grey "SEP 2026" eyebrow — the month is
  the one fact a calendar panel exists to state); every numeral at `ThemeType.time`, ONE weight and
  size, with TONE carrying the hierarchy (accent for today, primary for a day that carries
  something, secondary for an empty one, 0.4 outside the window) because a grid of mixed weights
  reads as a grid of mistakes; the SELECTED day a filled `surfaceFloating` circle behind its
  numeral; the day's content a 6-pt dot beneath it, amber while something on it is still to come or
  to watch and quiet once it is spent. **A hairline rule above every week row but the first**
  (`ThemeColor.hairline`, white at 0.055) — the user's ask, and the fault it fixes is real: five
  rows of loose numerals in one field have nothing telling the eye where a week ends, so a date and
  the date below it read as neighbours. The panel is GLASS (`glassChrome` over a `canvas` veil at
  0.62), not a `surfaceRaised` slab: it is chrome that floats, like every other floating surface in
  the app, and #242428 filling a third of the screen read as a debug view.
  **`discSize` is capped at 44** — seven columns share ~353 pt, so a cell is ~50 wide, and uncapped
  the disc reached ~78 at the accessibility sizes and forced the panel 180 pt wider than the
  screen, arrows and both weekend columns off the edges. A grid's cell cannot be wider than a
  seventh of its grid, whatever the text size says. **The grid only
  answers for days the feed actually holds** (`AppModel.scheduleBack…scheduleAhead`, 22 days): days
  outside the window are drawn at 0.3 and are `.disabled`, and the month arrows stop at the window's
  own months — an out-of-window cell used to be an ordinary target that landed on "Nothing
  scheduled", which is a lie, since the truth is that nothing is KNOWN about 25 September
  (`Copy.Schedule.beyondHorizon`). Its weeks are a `ScrollView` at a STATED height —
  `min(naturalWeeksH, weeksBudget)`, the budget measured from the panel's own header — because a
  scroll view is greedy and both `maxHeight` forms padded the panel out to the cap and centred
  September inside a hand's width of nothing, while an uncapped six-row month at the accessibility
  sizes ran under the tab bar.
  **THE DATE RIDES THE ROW; there are no day bands (7 Sep — "ultra dense and extremely
  confusing", user).** `ScheduleDateRow` is the feed's only anatomy: a 38-pt DATE COLUMN
  (`ScheduleDateColumn` — "WED" as `sectionLabel` over the numeral at `ThemeType.time`, both accent
  on today, blank on the second and later airings of one day, as every agenda prints a date once),
  an 88×50 tile, the show, "Episode 16 · 6:30 PM", the state ladder's slot. What the measurement
  showed on the production account (5 airings, 2 shows, 22 days): SIX full-width bands for FIVE
  rows, a band ~48 pt (24 `dayGap` + label + 10 `labelGap`) against a 59–80 pt row — **~40 % of the
  feed's height was a banner introducing one row**; and of "7:30 PM · Season 4 · Episode 22" TWO
  facts are constant for that show across the window (a weekly show cannot leave Season 4 in 22
  days, and it airs at the same minute every week), so only the episode varied — and it sat LAST on
  the line. Fifteen middot-joined fragments on one screen, ~five of them news. **The season is
  dropped here** (`episodeText`, not `watchContext`) and the EPISODE leads the caption. Three shapes
  were built behind `-scheduleShape` and photographed side by side; the user picked this one. The
  losers are deleted, not flagged off: **B** kept the bands and only fixed the caption (left the
  40 %); **C** grouped by show, which killed every repetition but took today off the screen entirely
  and ran the dates 2, 9, 16, 4, 11, 18 down the page.
  **THE WIDTH BUDGET is what every question about this row comes back to** (`RowMetrics`). On a
  393-pt screen: 16 gutter + date + tile + lane + 44 ladder + 16 gutter, 8–12 between.
  "Reincarnated as a Slime" measures **184 pt** in Outfit SemiBold 17 (measured against the bundled
  face, not guessed), so the title needs a ≥184-pt lane to hold a two-line break — which leaves
  ~95 pt for the date column AND the tile together. Hence 38 + 88, not the 104×59 the band-and-row
  shape carried, and hence three title lines for the longest names. A PORTRAIT poster was built and
  photographed against it and lost ("A is good but without image it looks too bland" → landscape,
  portrait and no-art frames): at 48×72 an AniList cover is its own logotype shrunk to mush twelve
  points from the title that already says it, and the landscape frame also fits the whole window on
  one screen where the portrait one does not. An art-free row is lighter still (~70 pt an event) and
  is what the shape spike photographed; it was rejected as bland.
  **At ACCESSIBILITY sizes the row UNFOLDS** (`stacked`): the date, the tile and the ladder keep one
  line and the words take the full width beneath them. Four columns cannot survive that type —
  measured at AX-XL the words were left a ~112-pt lane against a ~28-pt face, and the row printed
  "Re:ZER / O" broken inside the word, truncated "That Time I Got Reinc…" (a row may grow at these
  sizes; it may not lie about which show it is) and pushed the ladder off the screen. Same fault,
  same answer, as the clock column this row replaced.
  Days are `ThemeSpace.x5` (20) apart — the break belongs to the day's FIRST row, and the feed's
  first day drops it to x3. An empty today keeps its date column and says "Nothing scheduled" beside
  it (`emptyDateRow`), so the one day with no body has the same shape as every day that has one.
  The scroll targets did not move: a day's first row (or its empty row) carries `AgendaID.day(id)`,
  so `land`, the "Today" button and the month grid's day-tap are unchanged.
  The band-and-row shape this replaced — `ScheduleAiringRow`, `dayHeader`, `daySection`, `metaLine`,
  and with them the 6 Sep "nothing in the feed is right-aligned" rule about the header's inline
  count — is deleted. It had been gutter-to-gutter 16:9 `AiringCard`s from 3 to 6 Sep before that,
  at which density an airing plus its day header was ~305 pt and exactly two fit between the chrome
  and the tab bar ("the quick scanability is terrible", user). The caption is still ONE concatenated
  `Text`, never an `HStack` of two runs: as a stack one run holds `layoutPriority` and the other
  carries `lineLimit(1)`, so at the accessibility sizes the row printed a bare clock and never said
  which episode.
  **The state ladder (`AiringState`, `AiringStateControl`) — the second complaint, and it is
  independent of every direction above:** "there is no instant visual distinction between an
  episode that has been marked as completed, not seen, and upcoming. Everything feels of the same
  weight" (user). The card put the three signals in three corners — the clock's colour at the
  leading edge, the ring's presence at the trailing edge, a 26-pt check on the art's top-right —
  and drew "watched" as `opacity(0.72)` over a photograph on black, which is not a state, it is a
  haze; and the trailing slot could not tell watched from upcoming, since both drew nothing there.
  Jellyfin's #706 is the same bug with better contrast. Now ONE column at a fixed x, which every
  row reserves whether or not it has a control: `upcoming` an empty slot with the clock in accent;
  `toWatch` the accent `MarkRing(style: .quiet, lead: true)` with its episode numeral, the only lit
  thing in the column; `watched` a settled disc with the check, the title a step quieter and the
  tile under a flat `canvas` veil (a veil, never `.saturation`/`.blur` — those are per-frame passes
  on a scrolling list). The urgency stops being inverted: the accent buys the RING on an aired row,
  not the clock on one you can do nothing about.
  The chrome band survives as a 1-pt sentinel whose only job is the ground behind the navigation
  bar (this screen hides the system's). **Its ground is drawn at a STATED height, bottom-aligned to
  the band** — with the band's intrinsic height doing the work, a band with nothing in it drew a
  zero-height ground and the feed printed through the status bar and the word "Schedule". That was
  blamed on the header-less direction on 6 Sep and killed it; it was never that direction's bug, it
  was this background's. Nothing in the band changes size any more, so the load path is five
  identical frames — the collapsing-band faults of 6 Sep (a `0 ↔ nil` height animation slicing the
  cells, a fold mid-refresh, a follow firing during layout) cannot recur.
  Section headers must NOT paint a ground — an opaque plate cuts a hard step across the root wash.
  There is no timeline rail, no pinned header and no hand-rolled scroll tracking:
  `onScrollTargetVisibilityChange` records the top day and the calendar's selection catches up at
  `onScrollPhaseChange == .idle` — never live, because every automatic movement of a date control
  while the feed was moving was read as "bouncing" (five rounds of it, 6 Sep, and the axis turned
  out to be VERTICAL: a horizontal `ScrollView` whose content is a hair taller than its frame
  becomes vertically scrollable). The feed walks `FranchisePart.airings` (every dated episode in the
  window) via `AppModel.scheduleDays`; `scheduleAirings` falls back to the next/last slots against a
  server that predates the field, which shows each weekly show once.
  **Android mirrors all of it** (6 Sep, and the 7 Sep date row with it): `ui/schedule/ScheduleParts.kt`
  (`AiringState`, `AiringStateControl`, `ScheduleDateColumn`, `ScheduleDateRow`, `ScheduleMonthGrid`;
  `ScheduleAiringRow` and the `DayHeader` composable deleted, `FeedItem.DayHeader` gone and a day's
  FIRST card carrying the `day:` scroll key), the ticker and `AiringCard.kt`
  deleted, `MarkRingStyle.Settled` moved to the disc-with-`fill` form, `receiptIsLive` added beside
  `ReceiptLine` (which self-hides there, so a caller that must SWAP its own line has to ask), the
  overlay mounted inside the feed's box rather than the screen root (as a root child it drew over
  the word "Schedule"), and `JvmDateTimePatterns.best` given an `"MMMMy"` entry — it treats an
  unknown skeleton AS a pattern, so the header read "September2026". Both platforms pass the same
  skeleton now so they cannot drift.
  DEBUG launch arguments: `-scheduleFilter anime|tv`, `-scheduleHideWatched 1`, `-scheduleMonthOpen 1`
  (open with the calendar down) and `-scheduleDemoStates 1` (draw the most recent aired airing as
  unwatched — the test account has no aired-and-unwatched slot, so the ladder cannot otherwise be
  photographed with all three rungs). `-scheduleDemoCounts` and `-scheduleEarlier` are gone with the
  rail and the fold.
- **`planned` shows are not on the calendar.** `Franchise.tracksAirings` gates both Schedule
  (`buildScheduleDays`) and Today (`airingFranchises` → Out now / Airing soon / Now Bar); episode
  notifications and the Live Activity gate harder (`watching` only). A shelved mid-broadcast show
  otherwise arrived as "20 episodes behind" with a "Mark 20 episodes as watched" ring — an
  obligation invented out of a bookmark. Every other status keeps its airings.
- **Freshness is derived from `airings`, never from the catalogue's counts.** `airedEpisodes`,
  `lastAiredAt` and `nextAiringAt` are the server's hourly-cron fields; a slot in the part's own
  `airings` list that has struck IS an aired episode. Every "is it out / when is the next one"
  question reads `FranchisePart.airedByNow` / `behind` / `lastAired` / `upcomingAiring` (anchor-aware:
  a timed slot counts once `at <= now`, a date-only slot the day after) or `Franchise.lastAired(now:)`
  / `nextAiring(now:)` — `outNow`, `soon`, `nextUp`, the Now Bar, `shelfState`, Today's `kind(of:)`
  and stack order, Detail's next-up block and `provenAiredCount` (the mark target). Reading the raw
  fields made the one show that had just aired (Re:ZERO, 6:30 PM, 2 Sep) the one show Today could
  not see for an hour, and `lastAiredSortKey` (still the raw field — fine for the Library's calm
  shelves) handed the hero to a days-old drop. Hero pill: a drop that struck today leads with its
  recency ("AIRED 29 MIN AGO") whatever the count, the count moves to the support line, and the
  pill's dot belongs only to today's drop or a later-today airing. The hero's fact line is
  `heroMeta` in `textSecondary`, so the title and "Season 4 · Episode 12" never read as one line.
  The curated `FranchiseUpcoming` note goes stale the same way (its `checked` date is weeks old):
  a day-dated release that has passed (`hasArrived(now:)`) no longer files a show under the
  Library's Returning shelf — Mushoku Tensei read "Returns today" two months into its season.
- **First contact (2 Sep, evening pass).** The hero names the show by `displayTitle` ("Re:ZERO"),
  as every row and shelf does; the full title is Detail's. Where-you-are on the hero is the one
  `ProgressBar` under the fact (watched ÷ aired-by-now for a fresh drop, ÷ available for a
  backlog; VoiceOver reads the count) — "4 episodes behind" in words only when nothing is watched
  yet and the pill spent itself on the recency. Queue rows draw amber only for TODAY's drop; an
  older one is a plain row. The billboard art BREATHES: `ArtHeader(drift: true)` scales the sharp
  layer ~7 % over 24 s, eased and reversing, off under Reduce Motion, one transform on one layer
  (Today and Detail both; nothing else drifts). **An empty account opens on television:** when the
  chart has loaded, Today's top block is the chart's #1 show on the same billboard — pill
  "TRENDING", `shelfShortened` title, "Anime · 1999", one capsule "Add to Library"
  (`addToLibrary`'s optimistic path; the real hero takes over when the library lands) — with the
  rest of the chart on a `.todayShelf` `ShelfCard` shelf whose header walks to Search; the
  skeleton holds while the chart loads (`trendingLoading`), and `EmptyState(.emptyToday)` is only
  the offline / no-chart fallback.
- **Catalogue enrichment (3 Sep, the backend's `feat: enrich catalog discovery` hand-off).**
  `Models+Enrichment.swift` holds the contract's deep metadata — `ArtworkSet`, `FranchiseVideo`,
  `AudienceInfo`, `FranchisePeople`/`CatalogPerson`, `RelatedTitle`, `ContinueWatching`,
  `WatchAvailability` — every one decoding LENIENTLY (an older server or a row the server's
  stale-while-revalidate pass has not reached reads as EMPTY, never as a decode failure), and the
  screens hide an empty section. **Art is read through `portraitArt` / `landscapeArt` / `wideArt`
  / `billboardArt` (`WideArt` = url + `portraitSource` + `ultraWide`), never `cover`/`banner` in a
  view**: `images.landscape` is honest (nil = composite the cover), and the legacy `banner` is
  trusted only when it differs from the cover (older writers copied the poster into it). **The
  server selects artwork (4 Sep, server 518430b):** `images.portrait`/`images.landscape` are its
  best per orientation, `artwork.portraits/landscapes/logos` (`ArtworkGallery` of `ArtworkImage` —
  url, source, width, height, language, score) are its ranked alternatives, and `cover`/`banner`
  mirror the selection. The order is authoritative: a view reads `images.*`, then the gallery's
  FIRST entry, then the legacy field — never re-sorted by score, size or provider, and a URL is used
  as sent. Both galleries decode leniently (a malformed entry drops itself, a missing list is
  empty) and ride through every optimistic copy (`Franchise(copying:)`, `withProgress`, `with(…)`,
  `grafting`). **Heroes are PORTRAIT-first** (`billboardArt` = `WideArt.billboard(portrait:
  landscape:)`, Today's billboard, Detail's, the trending billboard): the selected poster,
  composited whole through `ArtHeader(portraitSource:)`, and the landscape only when the
  catalogue has no poster. The billboard frame is ~0.64 w/h — within 4 % of a 2:3 poster — so a
  16:9 backdrop filled into it shows its middle ~36 %. The artwork hand-off's "heroes use
  images.landscape first" was implemented for a few hours on 4 Sep; on production every show had
  a TMDB backdrop and every billboard was a zoomed slice ("supposed to be portrait", "everything
  so zoomed", user) — the rule is wrong for a tall frame, and Android had never left cover-first.
  Landscape stays the choice of every 16:9 surface (`ProgressBanner`, `BannerCard`,
  `ScheduleDateRow`'s tile, the Up next cards, episode tiles). Grids, rows and shelves stay `portraitArt`-first. **The
  billboard's NAME is the show's LOGO, and the lockup is CENTRED (5 Sep, settled by a placement
  spike):** `HeroTitle` draws `billboardLogo` (`artwork.logos.first`, the server's rank) inside a
  box of ≤ 88 % of the copy run × ≤ 120 pt — EVERY logo, circular emblems (Slime, Demon Slayer)
  and stacked marks (Solo Leveling) included — with an 8-pt optical gap beneath its ink
  (`HeroTitle.logoBox`, `ThemeMetrics.billboardCopyWidth`); the name in type only where a show has
  no logo. A "headline-mass" rule that dropped emblems for type lasted a few hours on 5 Sep: the
  user liked the show's own logotype as the headline ("I really liked the previous series based
  font image") and disliked only its placement — "you could've done a /spike instead of sloppy
  replacement". Three placements were then photographed on Slime, Thrones and Solo Leveling
  (foot-left, centred, on the art — the last landed on a face on every show) and the user chose
  CENTRED: `HeroLockup` puts the badge, the name, the one line (with the reveal glyph riding beside
  it as part of the group), the bar and the support lines on the billboard's axis, the capsule
  full width beneath; `TrendingFocus` and the not-in-library name follow; the identity line, the
  synopsis and every row keep the page's left axis. `billboardArt` prefers `textlessPortrait` — the
  first ranked poster with no `language`, trusted ONLY when the gallery is tagged at all
  (`ArtworkGallery.textlessPortrait`: at least one portrait carries a language; the older untagged
  shape passed Bleach's titled poster as textless) — and asks TMDB for the `original`
  (`WideArt.billboardResolution`; the server's `w780` was drawn 1179 px wide, a 1.5× upscale;
  cards keep the size they were sent). **A name is ALWAYS drawn.** `BillboardName` is `.logo` or
  `.type` — the 4 Sep "art carries the name" case is gone: it assumed the poster's logotype sits
  where the copy does, Re:ZERO's sits in the top band under the back button and the status
  capsule, and on Today the wordmark band covers the same zone. Where the selected poster is
  titled and no textless one exists the name is set in TYPE, never as a logo (the user's pick);
  the real fix for those four shows and for Bleach is textless posters from the server's
  enrichment (fetch `include_image_language=null`, tag galleries) — a server ticket. Accessibility
  sizes always set the name in type. **Both billboards are ONE view, `HeroLockup`
  (DesignSystem/HeroLockup.swift, 5 Sep):** badge → name → one line (moment · fact, with an
  optional trailing ACCESSORY — Detail's reveal-title eye glyph in a 44-pt target that shares the
  row without growing it; the labelled toggle used to take half the fact's row and "Season 3 ·
  Episode 8" wrapped mid-phrase) → season bar → support → third line → actions. Today's
  `HeroFocus` is a thin adapter; Detail's `heroLockup(_:state:)` feeds it from `NextUp` (which
  gained `moment` — Today's grammar verbatim: a drop that struck today is "NEW EPISODE" on the
  badge with "Aired 2h ago" leading the line; a caught-up show's next airing leads the line).
  **The show page's state block is GONE:** the badge, the fact, the capsule and "Start rewatch"
  live in the billboard's lockup over the art's foot (`heroFraction` 0.72, Today's), and the
  identity line ("Anime · 2018 · TV-14 · Action · Adventure") heads the synopsis at `metadata`
  size, `ThemeSpace.x5` under the hero; the watch-history row follows the synopsis. `HeroCopyScrim`
  now LANDS for any copy height (its ramp marks are bounded by shares of `h − 40`; clamped only to
  `h`, a one-line copy put 0.72 at 92 % and never reached canvas — Re:ZERO's copyright line printed
  through and the hero ended on a hard step, luminance 45 → 27 in one row). The bar docks the title
  when the NAME reaches it (`badgeToName` = 20 + x3 above the copy's top). Android mirrors all of it
  (5 Sep): `ArtworkImage`/`ArtworkGallery` (lenient, `SafeListSerializer` drops url-less
  entries), `artwork` on the three classes, `textlessPortrait`/`billboardLogo`/`billboardName`,
  `ui/hero/HeroTitle.kt` (`HeroLogo.box`), `ui/hero/HeroLockup.kt` (`HeroLockupDefaults`, centred),
  `DetailHeroCopy`, `billboardResolution`, `Billboard.detail` 0.72; verified on the emulator
  against production as the Clerk test user (build with
  `-PapiBaseUrl=https://anime.cognipin.com` and NO `-PclerkKey=`; the FIRST screenshot after an
  `am start` needs ~15 s — at 8 s the emulator still shows the ident).
- **The world-class loop (5 Sep, five iterations of adversarial review → fix, all pages).** The
  reviewer is a subagent fed the full capture set (`scratchpad/loop/capture_ios.sh`: Today ×5
  states, Schedule, Library, All titles, Search, Profile, four show pages, three Detail anchors,
  the trailer stage, both receipts) plus frame sheets of a cold launch, a push and a receipt
  (`record_motion.sh`, 8 fps), the iOS-conventions section of this file and the code; it verifies
  the previous iteration's findings first. Rules that came out of iteration 1: the in-place
  receipt is an OVERLAY hanging under the capsule (`HeroLockup(receiptHost:)` → `ReceiptLine`
  offset by its own 28-pt height; a layout child pushed the lockup 48 pt a second after the tap;
  Today's recap mask extends 44 pt below the hero for it); the band under a billboard is x4 on
  both screens (capsule → next header ≈ 38 pt, was 66); a `.fresh` hero shows the drop's recency
  as the MOMENT only when `behind == 1` — with a backlog "Aired yesterday · Season 4 · Episode 19"
  bound episode 21's drop to episode 19, so the line is the episode alone and the support line
  says "Episode 21 aired yesterday"; the recap strip carries no numeral under a badge that has
  one; Today's bar docks the show's title only while the lockup PASSES under the wordmark band
  (`heroCopyUnderBand` = the copy's frame straddles the band + 12) and gives the wordmark back
  once it has left; Detail's docked title scales to 0.85 before it ellipsizes; a 3-column GRID
  reserves two title lines (`ShelfCard(reserveTitleLines: true)` on Search's grid and More like
  this) so captions share a baseline — shelves keep the unreserved form; `PersonCard` roles are
  one line; `FranchisePeople.ordered` is CAST first (10), then creators, then only real directors
  (the server files camera and AD crew under `directors`), capped at 16; the finished show's
  lockup is "Watched once · 95 episodes" + ONE more line; `Copy.Library.rumored` strips a curated
  "(rumored)" then says it once; All titles states "Watched · Returns 3 Oct" on ONE line with the
  date in accent (`MediaRow(metaLead:)`, `LibraryRowFacts.metaLead`); Profile's identity line is
  three numerals on one line, no "Signed in" when it names nothing, and its Watching captions
  carry the badge's count ("3 episodes behind"); a shelf of ONE runs gutter to gutter (span 5);
  the ident holds 0.82 s and exits in 0.28; NO haptic on a tab switch, the Haptics toggle or
  Schedule's toggles — a haptic is a signature for a write. The trailer stage: ambient lit (0.22,
  stops 0/0.08, 720 px, blur 44), the lockup + x8 + picture floated to the centre, a glass play
  disc that becomes a spinner at 0.9 s, the video's title without the show's name
  (`FranchiseVideo.title(cleanedFor:)`). **Iteration 2:** Today's bar stays hard once the lockup has passed the ramp
  (`heroUnderBand`), the ident waits for the first billboard's art (`LaunchHandoff.artReady`,
  `artPatience` 1.6 s) and has a 2.4-s WALL ceiling from its first frame (`wallCeiling` — live
  seconds cut stalls out, so a starved sim held it for six), `onFinished` also sets `emerged`
  (the app must never rest at 0.96); docked names go through `FranchiseDetailView.dockedName`
  (budget 19 in Detail's bar, 28 in Today's band — fit, shortened, or the WORDMARK stays, never
  the full name); the hero bloom is centred under the lockup (0.5, 0.26, r 88); the drop line
  under a backlog badge is `Copy.Progress.dropAired` ("Episode 21 aired yesterday"). **Iteration
  3:** a name set in TYPE starts its cover under the wordmark band (`ArtHeader(topInset:)`,
  blended over 56 pt — the mask exists ONLY on that branch, see the lag rule below); a logo keeps
  the full bleed; `HeroTopVeil` 0.72/0.66/0.52, ramp 100; the receipt hangs 24 pt; shelf titles
  are budgeted (`shelfShortened(fitting:)` 24 free / 26 reserved / 30 lane) and a reserved card
  runs 2…3 lines (a floor, never a cap — `lineLimit(2...3)`); Today's Watching shelf excludes
  the Up next shows; the stage's exposure follows the art's OKLab L (dark art lit, bright art
  veiled); the certificate is an outlined TAG after the year with air on both sides and no
  middot against it; the add disc sits on the POSTER's foot (an overlay anchored at the card's
  top, offset by the poster height, outside the card's button). **Iteration 4:** copy has one
  voice — "In Library" (capitalised only in a destination phrase), "rumoured" (UK, as
  "catalogue"), one offline line ("Showing what was saved on this device. Changes sync when you
  reconnect."), "Mark as caught up", "Your schedule couldn’t refresh", "Removed from Library ·
  Watch history kept", Library's shelf is "Next up" (Today's name; `airingSoon` is gone);
  Schedule's filtered-out state is its own (`noScheduleMatches`); a behind count on a Watching
  shelf is amber only while the drop struck inside `nowBarLiveWindow`; "Read more" is drawn only
  when a hidden full-height measure exceeds the clamped paragraph; **a finished series moves to
  Watched on its last mark** (`AppModel.settleCompletion` in `applyLocalProgress`, keyed on
  `Franchise.isWatchedThrough` — every episodic part complete and nothing releasing or upcoming; a
  curated RUMOUR does not hold a show in Watching — undone with the mark, and
  `settleCompletedSeries` once per session for rows the server still files under Watching); the
  "30 titles ›" door is `interactive` with a chevron; trailer captions drop the kind when the name
  says it and print the provider as written (`FranchiseVideo.providerName`), names lose a
  trailing "(Provider)" and straight quotes; Schedule's clock column runs the whole feed (a
  date-only airing keeps an empty column). **The lag rule (5 Sep, "unusable", then "halts
  halfway"):** nothing on the billboard's sharp layer may be an offscreen pass — `.mask { … }` is
  one even when its body is `Color.black`, and under the 24-s drift it ran once per frame on a
  2048-px layer; the blurred ground decodes at 1024; and scroll-driven facts
  (`heroCopyUnderBand`, `heroUnderBand`) live on `ScrollOffset` (`setCopyUnderBand`), read only
  by `TodayHeaderBar` and `TodayVeils` — as `@State` on TodayView each flip re-ran the whole
  screen at the moment the veils were also swapping; the veils keep ONE `ScrollEdgeChrome`
  mounted and switch its height/hold/opacity. **Iteration 5 (the last):** no scale on the app tree at launch (the ident's ground IS the
  reveal; `IdentClock` cuts stalls only while holding, the ground lags the composition by
  0.05 s); the recap row names the EPISODES ("Season 4 · Episodes 19–21") under a headline that
  carries the count; shelves are unreserved, grids reserved (for good this time); cast names one
  size, two lines, cards top-aligned; the stage's ambient has a FLOOR (dark art lifted, a pool of
  the show's hue with light); the synopsis clamps at a word; "Stop this rewatch" is the one verb;
  `plural` groups thousands; a themes line needs two themes; outside the 60-day horizon a
  Returning caption is the window alone in grey; both skeletons are the centred lockup the page
  arrives with; `markNext` signs the series-finishing mark `.success` itself and its receipt
  says "Series finished · Moved to Watched"; the lane's title is one line; **"today" is the
  calendar day the temporal ladder uses** (`FranchisePart.airedToday`), never a 24-hour window —
  a badge, a moment or an amber lead may not call "yesterday" today. Not done: centring Detail's
  docked title (the editor role leading-aligns it; the iOS-18-safe alternatives cost the roots'
  titles or the swipe-back gesture). The five-item backlog after the loop is server/device work:
  textless posters + logos for AniList-only shows, `contentRating`/`partCounts` on the list
  payload, anime billboard art from the TMDB twin, cold-start measured on a device, a motion
  harness (`-motionDemo`) that reaches the push and the mark. **The interactive pass (5 Sep, "let the UX reviewer use the app… like a real user"):** the
  reviewer drove the QA sim through fb-idb (`DEVELOPER_DIR=/Applications/Xcode.app` — the
  simulator MCP had died) and the rules that came out of real use: every scrolling root adds
  bottom clearance while a receipt lane is up (`laneClearance`, `ReceiptLane.height`) — a lane
  over a row's disc turned its Undo spot into a "+" six seconds later; a Schedule card opens the
  show page and the episode list in ONE push (`DetailRoute.focusPushed`) and the list's focus
  scroll retries after layout; "Most left to watch" sorts Watching/Paused by backlog first;
  the capsule's range item exists only as a strict subset of "all"; the hero's receipt lands at
  the TAP and list receipts take the row's OWN second line (`ReceiptLine(inline:)`,
  `ReceiptLine.isLive`) (retired 6 Sep: the list's ring is its own receipt) — a receipt is never a layout child that moves the page; a zero-hit search
  is an empty state, not an error; the alerts primer sits below the results; Schedule confirms a
  batch with an alert that has Cancel and lands on yesterday's unwatched drop when today is
  empty; "Next up ›" opens the queue sorted as one; removing a show keeps its face
  (`Franchise.keepingArt(of:)`); Profile's Notifications row always shows its state and asks
  in-app before it ever sends anyone to Settings; a Planned show's lockup waits (no capsule).
  Still open: the same-picture slide from Today's hero into Detail, the Clerk dev instance's
  name and password-first step on the sign-in sheet, the share sheet's placeholder icon. Per-iteration notes: `scratchpad/loop/log.md`.
- **Receipts, not toasts (5 Sep, "the toasts are archaic according to 2026 standards" → a spike of
  four directions photographed on the sim, B + C chosen).** A transient confirmation is drawn in
  ONE of two places, decided at the WRITE (`UndoState.placement`, `ReceiptPlacement`, `Receipts.swift`):
  **IN PLACE** — `ReceiptLine`, one quiet line "✓ Episode 19 watched · Undo" under the control that
  was pressed, when that control stays on screen: Today's hero capsule (`ReceiptHost.todayHero`),
  the Up next cards' rings (`todayQueue`), the show page's capsule (`detailHero`), Schedule's cards (`schedule(mediaId,
  episode)`, under the caption) — the write site calls `.placed(at:)` (`presentUndo(_:host:)` on
  Android); a season reset stays on the lane (every ring clears, no row can hold it). The episode LIST has had no receipt since 6 Sep — its ring is the receipt (see the Episodes bullet). **THE LANE**
  — `ReceiptLane` (poster or glyph, the fact, the show, Undo/none) as the tab bar's bottom accessory
  on iOS 26.1 (`chromeBottomAccessory(isEnabled:)` → `tabViewBottomAccessory(isEnabled:)`, the lane
  Music's mini player lives in; a conditionally EMPTY accessory still reserves its lane, Apple
  forums 803428, so the enabled flag is the switch) and `LaneFallback` attached above the bar below
  26.1 / on Android (`LaneHost` in `Toast.kt`): a removal, a move, an add from Search, a caught-up
  from a context menu, the two-second notices ("Episode alerts on") and the write failures — one
  `LaneItem` at a time (`AppModel.laneItem`: error, else a lane-placed undo, else the notice). The
  fact is `UndoState.receipt` ("Episode 19 watched", "Removed from Library" — `Copy.Toast.removedShort`;
  the full sentence stays in `message` for VoiceOver), never the show's name in the fact when the
  poster or the line beneath already says it. `ErrorToast`/`UndoToast` are retired; `ToastHost`
  keeps the persistent `SyncBanner` and, below 26.1, the lane. Capture with `-toastDemo mark|lane|notice`
  (`-toastDemoFranchise <id>`): a receipt that writes nothing. The shipped toast was one grey capsule
  for all of these, fading in with a 4-pt rise, 330 pt below the capsule it confirmed and over the
  shelf, spending two lines on the show's full name under a hero that already said it. Detail fetches `?country=AppRegion.current`
  (the device region, "US" fallback), reads `/watch-providers` separately (a failure is a missing
  section, never an error), grafts the detail read onto the live library copy field by field
  (`Franchise.grafting` — the library payload was read at launch, before enrichment may have run)
  and re-reads once after 6 s when the row `looksUnenriched`. Its sections, after Movies & extras,
  in Apple TV's order: **Trailers** (`TrailerCard` → `VideoSheet`, a WKWebView `<iframe>` of the
  YouTube embed inside a page with a neutral base URL — a bare embed URL gets "Video player
  configuration error", a youtube.com base URL gets "unavailable · 152-4"; the bar's `arrow.up.right`
  opens the provider), **Cast & crew** (`PersonCard`: 72-pt disc, name, role — not a control),
  **More like this** (`ShelfCard`s; `franchiseId` → `push(.detail)`, else an exact-title search
  materialises it or `Copy.Notice.notInCatalogue`), **Where to watch** (drawn only for
  `status == .available`: provider marks, the header opens `link`, the JustWatch attribution as a
  footnote — a section that says "not here" is not a section). All four share `DetailShelf`. The
  market's rating sits in the identity line after the year ("Anime · 2016 · U/A 16+ · Action");
  themes the genres do not already say run under the synopsis in `metadata`; a rumour is labelled
  one everywhere the curated fact appears ("Season 3 rumored" — `ReturnFact` / `Copy.Library.rumored`,
  never a date, never amber) and Detail's COMPLETE block carries the curated next installment
  ("Season 3 · Returns Oct 2026") so the show page cannot contradict the Library shelf. The Continue
  card names the next episode from `continueWatching` ("Season 4 · Episode 12 · The Lion and the
  Sea"); `EpisodeStill` falls back still → landscape art → cover under the number. Every optimistic
  progress copy goes through `FranchisePart.withProgress` — the hand-built copy it replaced dropped
  `airings`, so one local mark took a show off the calendar until the next reload.
- **The launch is the icon's ribbon, drawn by light, then the app coming through it (4 Sep
  rebuild, settled 5 Sep).** The launch screen is the bare canvas (`UILaunchScreen` =
  `LaunchBackground` = `ThemeColor.canvas`, no image: an asset-catalogue `UIImageName` still never
  rendered on the iOS 27 sim, so nothing may depend on one). `App/LaunchIdent.swift` owns the
  entrance: on the first live frame a travelling light draws the ribbon (120 pt, a third of the
  screen, centre 0.44 × height, `PreviouslyMark`'s `lit` material — ramp, rim, near/far edges)
  head to foot; its pool of warm light (`RibbonFill(castShadow:)`, a static blurred layer) arrives
  as it completes; the coral full stop lands with one pulse; the composition HOLDS, COMPLETE AND
  STILL; once `LaunchHandoff.authReady` the ident pushes through — the composition grows to 1.10
  and dissolves over 0.22 s, the ground dissolving off the app beneath over 0.40 s. The app is
  never scaled or faded (review i5): a transform or an opacity ramp over the whole tree is a
  full-screen offscreen pass started in the frame the ident begins leaving, and it froze the exit
  at 80 % for half a second — **the ident's GROUND is the reveal**, so its curve is a smoothstep,
  never the ease-in the composition uses (an ease-in ground holds full canvas for two thirds of
  its run and then drops, which is a CUT to the app with a smear on the front of it).
  `phase == .leaving` sets `surfaceReady` (the
  launch tab's page-in only rises — `pageInTransition(fadeIn: launch.finished)` — and the floating
  tab bar, which the system composites above any overlay, waits on `launch.emerging`). Nothing
  flies into the header; the header draws its own `Wordmark` from the first frame. No stage
  light, tagline, flash, grain or haptic; the full stop is `ThemeColor.brandPeriod` everywhere the
  name is set (`BrandWord`). **Every value is a pure function of live time** (`IdentClock`: frames
  actually presented, stalls > 250 ms cut out — a merely slow frame is not, or the motion plays in
  stepped slow motion; `IdentFrame`: the spring step-response, a smoothstep and an ease-in as
  functions): an implicit animation started in `onAppear` is folded into the first frame and never
  plays, and a `Task.sleep` counts wall time while the main thread is still busy. **But the cut is
  BUDGETED at 0.40 s total (`stallBudget`, 7 Sep)** — the clock protects the MOTION from a stall,
  it may not hold the PICTURE hostage to one. Unbudgeted, a launch whose first second is all
  stall (the app builds its whole tree under the ident, which is what the hold is FOR) froze the
  ribbon at nothing drawn and showed a bare canvas until the wall ceiling fired. Past the budget
  wall time drives, so a starved launch plays the drawing in chunky steps instead of not playing.
  **Nothing heavy runs per frame:** the ribbon is rasterised once (the reveal is a canvas-coloured
  cover sliding off it, not a mask; the light is one gradient band), and every exit is a layer
  opacity or a transform. **A blurred layer handed to `drawingGroup()` must be PADDED first**
  (`.blur(r).padding(3r).drawingGroup().padding(-3r)`, `PreviouslyMark`): the group rasterises the
  view's BOUNDS, so an unpadded blur is cut off square — the 5 Sep perf pass's shadow rule drew
  the ribbon's pool of light as a rectangle of lifted canvas with visible edges and put a glowing
  BOX behind the brand's full stop (seen at full resolution, 7 Sep; invisible in a thumbnail).
  Beats (live s): preroll 0.14, draw 0.60 (ease-in-out), cast +0.45→0.85, stop at 0.52 (0.40/0.72)
  with a 0.45 pulse, then `stillFor` 0.20 — **the hold is stated as `preroll + beadAt + bloomFor +
  stillFor` (1.31) so the mark always stands FINISHED before anything moves**; review passes had
  shaved it to 0.96, which is 140 ms before the pulse ends, and the exit read as a cut away from
  something still arriving. `artGrace` 0.15 is all the extra the hero's picture gets (`artReady`
  never lands inside a cold launch — the art is a network away — and a flat 1.6 s patience made
  every warm launch 0.96 and every cold one 1.6, no two the same length). Exit 0.40 (composition
  0.55 of it, ground lagging 0.06); `wallCeiling` 2.8. The in-app mark is the icon's own
  geometry (`MarkGeometry`: 800/376 aspect, 0.40 notch, tangent-arc corners; header 11 pt,
  colophon 9 pt, gate 56 pt lit); the old bookmark-with-slot, `finish: .hero`, the Metal shaders
  and the flight-to-header (tried and retired the same day: a small object shrinking into a corner
  reads as a window minimising) are gone. Reduce Motion: fade in, hold, crossfade, and NO art wait.
  **The ident cannot be filmed (7 Sep).** `simctl io recordVideo` records a black screen through
  the whole ident while the app's own clock reports a clean 60 fps draw — two instruments against
  one, and the frame-identical black in the recording is the recorder, not the app; a screenshot
  costs the app ~0.5 s of stall, so a burst photographs a launch it is itself deforming (that is
  also why `capture.sh` was reporting a "black launch" this whole time). Photograph it instead:
  `-identFreeze <seconds>` holds the clock at one moment of the ident (past the hold it clears the
  ident to leave and stops a hair short of `.done`, so the exit stands still with the app emerging
  beneath), `-identTrace 1` prints one line per presented frame (wall, gap, live t, reveal, the
  gates) — and `scratchpad/launch/beats.py <name> <t,…>` is one cold launch per beat, one exact
  frame each. `capture.sh` and the burst are kept only for what happens AFTER the ident.
- Debug-only launch args: `-identTrace 1` / `-identFreeze <s>` instrument and photograph the launch
  ident (see the launch bullet — it cannot be filmed); `-openDetail <franchiseId>` lands on a show page (the alert-tap route);
  on it, `-detailAnchor trailers|people|related|watch` scrolls to a catalogue shelf,
  `-detailTrailer 1` opens the first trailer's sheet and `-detailOpenRelated N` opens the Nth
  related title — the way to photograph the show page when the simulator cannot be touched (on
  3 Sep System Events saw no Simulator window and `screencapture` was refused, so cliclick had
  nothing to hit; `xcrun simctl io screenshot` still works). `-recapDemo 1` forces the full Previously Recap on Today; `-calmDemo 1`
  empties Today's focus stack so the calm (caught-up) open renders on a library with backlog;
  `-todayAnchor upnext|watching` scrolls the loaded Today to a shelf (the input MCP dies between
  sessions and `simctl` cannot scroll);
  `-scheduleFilter anime|tv`, `-scheduleHideWatched 1`, `-scheduleMonthOpen 1` (open with the
  calendar down) and `-scheduleDemoStates 1` (draw the most recent aired airing as unwatched — the
  test account has no aired-and-unwatched slot, so the state ladder cannot otherwise be
  photographed with all three rungs) open Schedule in those states (`-scheduleEarlier` went with
  the Earlier fold on 4 Sep, `-scheduleDemoCounts` with the day rail on 6 Sep); `-openTab
  today|schedule|library|discover`, `-openAllTitles 1` (one-shot) and
  `-openProfile 1` land on a screen for a capture. When the simulator MCP tool is dead, the sim can
  be driven from the desktop: open it with `open -a Simulator --args -CurrentDeviceUDID <udid>`,
  read the device frame from the window's `AXGroup` via System Events, and click with `cliclick`
  (a plain click hits rings, rows and the tab bar; SwiftUI buttons outside the scroll view — the
  avatar, a toast's Undo, a system alert's Allow — need a ~150 ms press; a 1 s press opens context
  menus). Never type unless a capture proves the field has focus.

- **Smoothness is measured, not felt (5 Sep, "butter smooth… lags are not acceptable").**
  Instruments cannot attach to the iOS 27 QA sim (xctrace records an empty trace from either
  Xcode; Animation Hitches refuses simulators), so the app carries its own instruments:
  `App/PerfProbe.swift` (DEBUG, or `-D PERFPROBE`; launched with `-perfProbe 1`) is a
  `CADisplayLink` hitch logger (every frame gap ≥ 34 ms → `Documents/perf.jsonl`, with the screen
  from the `.perfScreen("…")` hooks in `RootView`) and a watchdog thread that samples the MAIN
  THREAD'S STACK while it is stalled (suspend, copy the frame-pointer chain into a preallocated
  buffer, resume, then `dladdr` — the app's code lives in `AniTrack.debug.dylib`). The scripted
  flow, the scorer, the stack aggregator and the A/B switches (`-perfNoShelfMask 1`,
  `-perfNoMaterial 1`, `-perfNoDrift 1`) live in `ios/Tools/perf/` (README
  there). Rules that came out of the pass, each one measured:
  **a blur is a property of the image, never of a layer** — `BlurredArt` renders the blur once,
  off-main, from the SAME decode the sharp layer draws (one fetch), into a 160-px bitmap cached
  beside the decodes (`ImageCache.derived`); the billboard ground, every root wash
  (`ArtBackdrop`), every composited card ground (`LandscapeArt`) and the trailer stage (its
  saturation and lift baked in) use it, because `.blur(radius:)` on a composited layer is a
  Gaussian pass over that layer on EVERY frame it is on screen — every scroll frame, every frame
  of the drift, every frame of the stage's breath; a static blurred SHAPE gets `.drawingGroup()`
  (the ident's cast shadow, the sign-in bloom, the recap fan).
  **A card's shadow is drawn by its ground shape** (`cardShadow(_:shape:)` — `fill.shadow(.drop)`
  rasterised with the shape) — never `.shadow` on the composited card, which renders the card
  offscreen to find its silhouette on every frame; a fitted poster's contact shadow is a shape
  the size of the fitted picture (`CachedAsyncImage(fitShadow:)`). `.shadow(_:)` remains for
  things that are not cards (a toast, the brand mark).
  **Derived collections are memoised** (`AppModel.memo`: `outNow`, `soon`, `nextUp`,
  `keepWatching`, `watchingShelf`, `libraryShelves`, keyed on library version + minute +
  celebration, like `scheduleDays`; the memo reads `library` once so a body that only reads a
  derived collection still observes it) — they were filtered and sorted on every read, and
  Today read them ten times per body. **The clock ticks ON the minute** (`startClock`), not every
  20 s: every fact it feeds is minute-grained, and each tick re-evaluates every body that reads
  `now`. **The scroll offset is never screen state** — Profile joined Today and Detail
  (`ScrollOffset`, `ProfileWashTravel`); as `@State` every sample re-ran the sheet's body with
  its library counts. **The library's offline copy decodes off the main actor**
  (`AppModel.start()`); it was the first thing sampled under the ident.
  **The show page's shelves are LAZY** (`DetailShelf`, the extras row — `LazyHStack`): a page
  carries up to 13 trailers, 16 people and 12 related titles, and an eager row built every one
  of them on the push, for cards three screens off to the right. **A billboard's protection
  follows the art's lightness** (`HeroProtection`, the same 5 Sep: "the overlay on hero is too
  dark as the new images are themselves dark"): `PaletteCache` now also remembers each
  picture's mean OKLab L (`lightness(for:)`, filled by the tint's own extraction), and
  `HeroTopVeil(strength:)`, `HeroCopyScrim(strength:)` and `ArtHeader(groundDim:)` scale with it
  — full over a bright cover, 0.35 over a dark one (L 0.30 → 0.35, L 0.60 → full; OKLab
  compresses the darks, Thrones measures ≈ 0.28, Wednesday ≈ 0.35, a bright poster ≥ 0.6). The
  copy scrim's ramp scales above per-stop FLOORS so the frame still eases onto canvas; the
  landing never scales. **Search's rows are EQUATABLE** (`SearchResultsList` + `SearchRow`, 5 Sep, "the search bar
  experience is lagging AF"): typed at human speed with the stall sampler on, every keystroke
  re-ran the screen's body, and a row's closures (its action, its trailing control) mean SwiftUI
  cannot prove a row unchanged — so every result row was rebuilt on every letter, button style,
  context menu and all (300 ms per key on the sim, most of it in the rows' `makeBody`). The list
  compares its data (ids, ownership, statuses, the minute) and each row compares what it shows
  (`SearchRowKey`), so typing costs the field and the keyboard only, and an answer landing builds
  only the rows that are new — and only the rows ON SCREEN (`LazyVStack`: "o" and "on" answer
  with thirty rows, all of which a plain stack built under the next keystroke); the
  duplicate-title scan (a regex per row) is memoised on the result ids. The add control's
  erased `AnyButtonStyle` is gone (a concrete style per placement): the `AnyView` it boxed every
  `makeBody` in was the leaf of the typing stalls; and an UNOWNED add control is a plain
  `Button`, a `Menu` only once owned — one `Menu` per result row was 40 % of an answer landing
  (a UIKit menu interaction per row that would never open), so the ownership flip crossfades the
  control instead of morphing the glyph. `Tools/perf/typing_test.py` +
  `typing_report.py` are the measurement (an answer landing: 340 → ~160 ms on the sim in Debug
  after the list changes; the rest is the keyboard's). **Search's launchpad stays MOUNTED under the results** (5 Sep, "it lags when I click
  on the Search bar… it lags to revert back to the original state"): the browse grid and the
  recents used to be one tree swapped for the results tree through `.id(query.isEmpty)`, so the
  first letter tore down fifteen cards (poster, palette, add control each) and Cancel rebuilt
  them from nothing — under the system's own field and keyboard animations. The grid is an
  eager `Grid` built once per chart; the query fades the launchpad and folds its height to zero
  (`frame(maxHeight: 0)` + `clipped`), Cancel unfolds it; the recents are mounted whenever there
  are any and folded until the field has focus. `Tools/perf/focus_test.py` measures the three
  moments. The FIRST focus of a process is the text-input stack coming in — dyld, `read`,
  `open`, class loading, 1.7 s on the sim in one stall, 80 ms for the second focus — so
  `App/KeyboardWarmup.swift` takes and drops focus on a zero-size field once, 1.8 s after the
  app has emerged, only while the app is still at rest on the tab it launched on (a tab
  switched or a page pushed means the moment has passed). The recents rows and the chart's cards are equatable like
  the results (`SearchRow`): the focus flips `fieldPresented`, the launchpad's body re-runs, and
  they were rebuilt under the field's own animation — each card asking `AppModel.franchise(id:)`
  twice, which was a linear scan with a struct copy and is now an index lookup
  (`libraryIndex`). What is left of the first focus (~400 ms on the sim, ~80 ms for every
  later one) is the text-input session starting: `liblangid`, `TIInputModeController`, the
  keyboard's image cache, IPC to the keyboard process — none of it ours (superseded 6 Sep by the unseen real-keyboard warm-up in "The search field's focus", above). **Search's busy flag stays at the KEYSTROKE** (`AppModel.scheduleSearch`):
  raising it only when the request goes out was tried and filmed (5 Sep) — the 300 ms between
  the last letter and the request drew "No results for …" over the trending grid, then the
  skeleton, then the answer. The "extremely glitchy" Search the user saw was two intermediate
  builds' one-frame deferral re-fading the trending grid on every return to the launchpad (gone
  with the deferral) plus the keyboard's first-use freeze (~0.7 s on the sim, the system's). The
  film of a query (`Tools/perf/hero_check.sh`: `simctl io recordVideo` + `idb ui text`, frames
  at 12 fps) is how a "glitch" is diagnosed.
  **The search field's focus (6 Sep, "the search bar click, keyboard are so unreliably
  glitching"; filmed at 60 fps with every tap verified on screen and every latency read from the
  app's own clock — `Tools/perf/focus_film.py`, `touch-down` / `search-presented` /
  `keyboard-will-show` marks in `PerfProbe`).** What the films showed: in the steady state the
  field presents ~50 ms after the finger lands and the keyboard's own animation (0.38 s on iOS 26,
  reported by its notification) starts ~175 ms after it — UIKit's presentation work, none of it
  ours; the FIRST focus of a process added 300–750 ms of freeze before anything moved (the text
  input session, the search keyboard's layout and key images, the search controller's view), and
  under that freeze one tap rendered as three beats: the field jumped to the top, then the
  keyboard rose, then the recents popped in. Rules that came out of it. **A keyboard cannot be
  warmed unseen on iOS 26+:** the keyboard is composited from outside the app — the only window
  a presentation adds to our scene is `UITextEffectsWindow` at level 10 — so a warm-up that lets
  a real keyboard present SHOWS it (filmed over Today for 0.7 s; `Tools/perf/warmup_check.py
  --film` scans every frame of a launch and is the gate for any change to `App/KeyboardWarmup.swift`).
  What the warm-up does instead is start the text-input SESSION: a `UISearchTextField` with the
  searchable field's traits and an EMPTY input view takes first responder (the session starts,
  the frameworks load, `keyboardWillShow` reports a zero height), holds 0.5 s, resigns — a beat
  after emergence, only at rest on the launch tab, only after 0.8 s without a touch
  (`KeyboardWarmup.install()` timestamps touches), never over a banner or lane, never in Low
  Power Mode, `-perfNoWarm 1` off. **What moves with the keyboard moves ON the keyboard's
  clock** (`ThemeMotion.keyboard`, duration from `KeyboardMotion`, the keyboard's curve): the
  launchpad's recents unfolding and the grid making room were on `uiGentle` (0.22 s) and had
  settled while the keyboard was still rising. **Never score the simulator's keyboard without
  seeing it:** the sim drops into a hardware-keyboard mode on its own — after `idb ui text`, and
  after typing on the Mac while the Simulator window has focus — and then every focus shows a
  caret and NO keyboard, across relaunches, until `simctl shutdown` + `boot` (or ⌘K in
  Simulator.app). That is what a person watching the QA sim sees after typing into it; it is not
  the app. Left where it is: the keyboard's own first build (`TextInputUI`, `CoreUI`) and the
  search controller's first presentation are the system's, and device numbers were never taken.
  `/Applications/Xcode.app` left the machine mid-session; `Tools/perf/simkit_shadow.sh` builds
  the shadow bundle idb needs.
  Measured and REJECTED (all on the sim, Debug): pre-rendering the other roots and the hero's
  show page off-screen after launch (a "warm-up") made no tab faster — a first render's cost is
  per-instance SwiftUI construction, not one-time metadata — and cost ~700 ms of stalls after
  every launch, and worse wherever it landed if the person had already moved on; a keyboard
  pre-warm run at the END of a warm-up sequence cost 440–870 ms wherever it landed and made no
  keystroke faster — but see `KeyboardWarmup`, below, for the form that stayed; a one-frame
  DEFERRAL of a root's content (chrome first, content on the next frame with a crossfade) was
  filmed at 60 fps with and without: the tab bar's highlight and the new screen's chrome landed
  in the same frame either way and the content followed ~130 ms later either way — it bought
  nothing and added a second commit; the shelf fade mask and the bars' masked material measured
  within noise — both stay. Two things the
  numbers are NOT: `idb ui describe-all` switches accessibility on in the process until the sim
  reboots (AX bundles load, every layout is taxed) — a measured run never asks the tree; and a
  Debug build's first render of a root is 250–400 ms of SwiftUI/AttributeGraph/Swift-runtime
  work under `$main`, and an optimised build (`Tools/perf/build.sh <tag> opt`: the Debug
  configuration at `-O` whole-module) is NOT much faster on the sim — the work is the
  framework's, not ours; a device is the only honest clock for those. Say which build a number
  came from. Where the pass ended (Debug, sim, the scripted flow): hitches 119 → 83, dropped frames
  1255 → 409, the worst gap in the whole app 2.1 s → 0.41 s (the launch, under the ident),
  stalls over 100 ms 49 → 20; typing into Search 975 → 336 ms of gaps for a nine-letter query;
  every vertical scroll's worst gap under 70 ms (Today 46, Schedule 66, Library 67, Detail 39);
  horizontal shelves and the stage's idle at zero. Search's moments (`focus_test`): the first
  focus 1.67 s → 0.33 s, every later focus 55–70 ms, Cancel 0 ms, the first letter 736 → 313 ms.
  What is left is first renders (a tab's first visit 230–370 ms, a push ~350 ms, the Profile
  sheet ~330 ms on the sim) and the text-input session's own start.

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
