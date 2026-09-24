# Library redesign QA

## Comparison target

- Source visual truth, selected art-first direction: `/Users/shantanusinha/.codex/generated_images/01a03259-d9ff-78a3-b9f1-e0502256abc8/exec-a057d130-5a68-4055-8a4b-5ea38ab9c3c2.png`
- Source visual truth, supplied tab/header crop: `/var/folders/5r/t6767z_96m5990yczng8_rj80000gn/T/codex-clipboard-795bf022-68fc-4f6f-a5d6-b05cda980446.png`
- Rejected implementation baseline: `/Users/shantanusinha/Documents/Codex/2026-08-24/the-x20/outputs/library-audit-current/01-overview.png`
- Revised Overview: `/Users/shantanusinha/Documents/Codex/2026-08-24/the-x20/outputs/library-redesign-final/01-overview.png`
- Revised Watching: `/Users/shantanusinha/Documents/Codex/2026-08-24/the-x20/outputs/library-redesign-final/02-watching.png`
- Revised Planned: `/Users/shantanusinha/Documents/Codex/2026-08-24/the-x20/outputs/library-redesign-final/03-planned.png`
- Revised Watched: `/Users/shantanusinha/Documents/Codex/2026-08-24/the-x20/outputs/library-redesign-final/04-watched.png`
- Device: `Aura QA iPhone 14 Pro iOS 27` (`33B810D6-1EA6-409B-B24D-B776549EC72A`)
- Viewport: 393 x 852 pt at 3x.
- Source art-first mock: 853 x 1844 px. It is a visual direction rather than a calibrated 393 x 852 capture.
- Source header crop: 1450 x 402 px. It is a focused crop rather than a full device viewport.
- Implementation captures: 1179 x 2556 px, exactly 393 x 852 pt at 3x.
- Density normalization: geometry was judged in points after dividing implementation pixels by 3. The two source images were treated as compositional references, so no false pixel-for-point precision was claimed.
- State: dark appearance, real cached library content, Library root.

## Full-view comparison evidence

The selected art-first mock, rejected implementation, and revised Overview were opened together in one comparison input. The revised screen retains the mock's editorial cover carousel, aligned title/progress block, Returning shelf, four-tab Library index, and near-black/amber language. The redundant `Mark watched` CTA is intentionally absent per product direction. Compared with the rejected implementation, the revised screen removes the heavy full-width rule and oversized heading treatment, restores breathing room, and lets artwork lead.

No actionable P0, P1, or P2 differences remain.

- Fonts and typography: Outfit remains reserved for identity and title hierarchy while SF carries metadata. The tab count is visually tertiary, the selected label is semibold amber, and long franchise names wrap or truncate within their intended roles without clipping.
- Spacing and layout rhythm: the header uses the 16 pt screen gutter, four equal 44 pt targets, a compact 22 x 2 pt selection mark, a 192 pt hero aligned to a 192 pt information column, and full-width status rows after one featured landscape card. The prior spreadsheet-like baseline and ragged two-column grid are gone.
- Colors and visual tokens: the shared near-black, amber, primary, secondary, and tertiary tokens are preserved. A 380 pt artwork-derived wash is visible through the header on Overview and filtered tabs instead of flattening the top third to black.
- Image quality and asset fidelity: all visible covers and backdrops use the app's existing high-resolution franchise artwork and native masks. No placeholder, generated substitute, CSS drawing, emoji, or custom approximation was introduced.
- Copy and content: `Library`, the dynamic title total, four live tab counts, `CONTINUE WATCHING`, Returning, status metadata, and the quiet Planned zero-state all reflect the loaded account. The empty state contains no redundant navigation CTA.

## Focused-region comparison evidence

The supplied header crop and the revised header were reviewed at native detail. All four labels and counts remain readable on one line, their 44 pt button frames are contiguous, and the short selected indicator is centered under the active label. No additional derived crop was required because the region is already legible in the 1179 px implementation capture and in the focused source crop.

## Comparison history

1. Rejected baseline: P1 — the Library read as a dashboard assembled from a tab rail, oversized `Continue watching` heading, full-width rule, large card block, and grid/plate patterns. The backdrop wash was too weak, and the visual hierarchy did not reach the selected art-first direction.
2. Fix: rewrote the root as an editorial index; separated labels from tertiary counts; replaced the full-width rule with a short indicator; restored the artwork wash; aligned the hero's art, title, metadata, and progress; removed the redundant watched CTA; and replaced filtered grids with one feature plus compact rows. Post-fix evidence: `01-overview.png`, `02-watching.png`, and `04-watched.png` in the revised output folder.
3. Empty-state fix: P2 — the prior plate and `Browse overview` action repeated navigation already provided by the tabs. It was replaced with a quiet icon, title, and supporting sentence. Post-fix evidence: `03-planned.png`.
4. Post-fix comparison: the source mock, rejected baseline, and revised Overview were opened together again. No actionable P0/P1/P2 mismatch remained across typography, spacing, tokens, image fidelity, or copy.

## Interaction and accessibility checks

- Accessibility hierarchy exposes four enabled tab buttons at approximately 90 x 44 pt, meeting the 44 pt minimum hit target.
- Overview, Watching, Planned, and Watched were independently launched and captured on the same pinned simulator. Watching shows five filtered titles, Planned shows its zero-state, and Watched shows thirteen filtered titles.
- Each tab remains a native SwiftUI `Button` bound to the same selection state; selected styling and content are derived from that single state.
- The installed `idb` could read the iOS 27 hierarchy but could not inject HID because it expects SimulatorKit at an older Xcode path. No Xcode or simulator files were altered to bypass that tool mismatch. This is a residual automation gap, not a visible or code-level blocker.
- Only the requested iPhone 14 Pro/iOS 27 simulator was booted. Both iPhone 17 Pro Max devices and all AuraShot devices remained shut down.

## Build checks

- Exact iPhone 14 Pro / iOS 27 simulator build: `BUILD SUCCEEDED`.
- The temporary local-cache QA bridge used only to render the existing simulator account was removed from source after capture.
- Final clean-source build: `BUILD SUCCEEDED` using an isolated DerivedData directory.
- Swift parse check: passed.
- `git diff --check`: passed.

## Follow-up polish

- P3: run a dedicated larger-Dynamic-Type pass later; the present controls already use native text styles and full-height targets.

final result: passed

---

# Today redesign QA

> Superseded visual pass: the poster-safe framing review below found that the original crop and
> scrims could obscure native poster lettering. The earlier `passed` result did not cover title
> placement across different artwork compositions and must not be treated as approval of that framing.

## Comparison target

- Product references supplied for principles, not replication:
  - `/var/folders/5r/t6767z_96m5990yczng8_rj80000gn/T/codex-clipboard-42ad001e-35ce-475e-af67-55334a421ded.png`
  - `/var/folders/5r/t6767z_96m5990yczng8_rj80000gn/T/codex-clipboard-f25a3893-a736-4563-b91b-2f8676bb25bb.png`
- Selected Today state directions:
  - `/Users/shantanusinha/.codex/generated_images/01a0baad-4f98-7a83-a123-7248eabbac2b/exec-73e6cb25-3fcf-43f2-9f59-de330a5c1ea1.png`
  - `/Users/shantanusinha/.codex/generated_images/01a0baad-4f98-7a83-a123-7248eabbac2b/exec-ab4a6b08-3f89-453d-92c4-6b43bc5ceb3e.png`
  - `/Users/shantanusinha/.codex/generated_images/01a0baad-4f98-7a83-a123-7248eabbac2b/exec-88a7c6e5-9ad6-4a7f-9e8d-c0b88ddf8a67.png`
  - `/Users/shantanusinha/.codex/generated_images/01a0baad-4f98-7a83-a123-7248eabbac2b/exec-5b65a942-aa7d-4e60-9816-da37a31b9182.png`
  - `/Users/shantanusinha/.codex/generated_images/01a0baad-4f98-7a83-a123-7248eabbac2b/exec-523ceab8-d4ff-4fbc-a988-2bb73009a177.png`
- Final simulator captures:
  - `/tmp/previously-today-qa/empty-poster-grammar.png`
  - `/tmp/previously-today-qa/inactive-recommended-final.png`
  - `/tmp/previously-today-qa/single-poster-grammar.png`
  - `/tmp/previously-today-qa/watched-poster-grammar.png`
  - `/tmp/previously-today-qa/multiple-poster-grammar.png`
  - `/tmp/previously-today-qa/caught-poster-grammar.png`
- Device: `Previously QA 14 Pro`, iOS 27, 393 x 852 pt at 3x.

## Full-view comparison evidence

The references were used for three product rules: artwork owns series identity, state and playback facts stay inside the artwork, and horizontal rails keep a sparse account visually alive. AniTrack keeps its own full-screen single-release hero, centered fact lockup, bottom-right watched toggle, large 2–3 release deck, wordmark, and floating four-tab navigation.

- Logo-backed catalog entries render their actual logo over textless art.
- Entries without a logo asset use the selected titled poster and do not duplicate the name in type.
- Recommendation rails are poster-only and contain planned library titles only.
- Empty, inactive-library, single-release, watched, multiple-release, and caught-up states were independently launched and captured.
- The caught-up state expands to a full-screen poster when no recommendations exist; it no longer leaves a half-screen black void.
- Gold is limited to brand identity. State badges, actions, page facts, and navigation remain monochrome.

## Comparison history

1. P1: inactive state used a portrait composited inside a landscape card, then overlaid logo, episode count, and CTA in one collision. Replaced with a true full-bleed portrait feature and one centered CTA.
2. P1: caught-up state ended after a 438 pt hero and left the lower half empty. Made hero height depend on whether a real recommendation rail follows; no rail means full viewport art.
3. P1: typed franchise names duplicated poster identity. Today now uses titled poster art or a catalog logo image, never a typed franchise-name overlay on active surfaces.
4. P2: title and caption rows under recommendation posters repeated information and added text density. Removed; the rail is now image-led with equivalent accessibility labels.
5. P2: two-release carousel underused the viewport. Increased it responsively while preserving the next-card peek and pager dots.

## Interaction and accessibility checks

- Watched and unwatched visual states were captured separately. The same 52 x 52 pt bottom-right control changes from an outlined white check to a filled selected check without inserting a toast or shifting layout.
- The control remains a native button with selected state and explicit episode-specific accessibility labels.
- Poster-only recommendations retain full spoken franchise names and `Start watching` accessibility values.
- Direct HID injection was unavailable in the current iOS 27 DeviceHub session, so the committed state was made deterministic with the DEBUG `-todayDemo watched` capture state. Production mark/unmark callbacks remain wired to `markNext` and `setProgress`.

## Build checks

- Signed iPhone 14 Pro simulator build: succeeded.
- All six Today states launched without a crash.
- `git diff --check`: passed.
- Existing unrelated compiler warnings remain; no new build error was introduced.

final result: passed

---

# Today poster-safe framing review — 20 September 2026

## Defect and correction

- Titled artwork was being treated as a crop-safe backdrop. The single-release path could fill,
  drift and mask the image; release cards assumed a native logo lived below a hard-coded overlay.
- Active Today features now share `TodayPosterSurface`: aspect-fit artwork, no masks or gradients
  over a native title, and a self-sizing control area within the same card. The entire selected
  source remains visible whether its title is at the top, middle or bottom.
- A separate graphic logo is composed only when both a verified textless poster and a logo with
  valid dimensions are available. Otherwise the selected titled poster supplies identity.
- The wordmark has its own clearance above the card. The watched toggle remains bottom-right,
  with an independent 52 pt hit target. Facts wrap vertically rather than being clipped to a
  fixed card height. Floating navigation and planned-only recommendation filtering are unchanged.
- Scope: Today layout only. No account progress, Schedule implementation, or remote Git state changed.

## Checks

- Final signed iPhone 14 Pro / iOS 27 build succeeded. Only the pre-existing `BlurredArt` warning
  appeared in the final incremental build.
- Swift parse and `git diff --check` passed.
- Initial multiple-release capture: `/tmp/previously-today-qa/full-poster-multiple.png`.
- Independent reviewer confirmed the unobstructed multiple-release capture shows the full Bleach
  bottom title, readable facts, bottom-right toggle and floating-navigation clearance.
- `/tmp/previously-today-qa/full-poster-single-rezero.png` confirms the top-positioned Re:ZERO title
  and footer remain visible. An unrelated Aura microphone-permission alert obscures its centre;
  that capture is only partial evidence, not a clean full-screen pass.
- Clean remaining-state and larger-text checks were blocked by that system alert. Permission was
  left unanswered. The reviewer terminated the unrelated Aura simulator process once before being
  instructed to stop recovery attempts; the alert persisted. No permission or app data changed.
- Content size was confirmed restored to `medium`; AniTrack was left on multiple releases.
- DEBUG fixtures represent visual states only. Mark/unmark persistence and navigation were not
  exercised, and no account progress was changed.

Status: build and targeted framing checks passed; full-state and larger-text visual QA blocked.

---

# Shared artwork and actions — 20 September 2026

Supersedes the Today-only framing and corner-checkbox treatment above.

## Implemented

- `ArtworkPoster`, `ArtworkScene`, `ArtworkSceneCard`, `ArtworkLogo`,
  `ArtworkActionStyle` and `WatchedArtworkButton` are shared by Today, Schedule,
  Library and Search. Screen-specific data, date navigation and tracking callbacks remain.
- Posters use their actual image aspect and measured card width: no fit-induced top
  letterbox or narrow image inside a wider card. Genuine logo plus textless art keeps
  its facts/action inside the image. Native titled posters retain their lettering.
- Today and Schedule use a centered, labeled watched/unwatched action, with no success toast.
- Search's trending grid is artwork-only. No Add/Added rows, caption titles or duplicate
  overlaid logos. Positively language-tagged posters are preferred for catalogue tiles.
- Library shelves/grid use the same poster composition; continue-watching and list
  facts are contained inside shared artwork cards. Progress/actions are neutral white.
- Floating navigation is retained.

## Corrections caught during verification

- Rejected the first scanline-extension implementation: it visibly striped several cards.
  The code was removed; the fallback uses the existing preblurred artwork pipeline.
- Corrected the compressed Black Clover poster by sizing its frame from actual card width.
- Removed Search's extra Add row following user feedback.
- Replaced inappropriate/duplicated Search logo overlays with authored titled posters.
- Integrated Black Clover's logo and Start watching action into the poster, removing
  the separate colored footer.

## Evidence and limits

- Signed iPhone 14 Pro / iOS 27 build succeeded; final Swift parse and `git diff --check` passed.
- Independent simulator review, with primary-agent image inspection:
  - `/tmp/previously-today-qa/shared-final-inactive.png`
  - `/tmp/previously-today-qa/shared-final-caught.png`
  - `/tmp/previously-today-qa/shared-v3-discover.png`
  - `/tmp/previously-today-qa/shared-v3-today.png`
  - `/tmp/previously-today-qa/shared-v2-schedule.png`
  - `/tmp/previously-today-qa/shared-v2-library.png`
- Re:ZERO's top-positioned native title was checked at normal and accessibility-extra-large
  text sizes: `/tmp/previously-today-qa/shared-v3-single-rezero-ax.png`. Labels and action wrap
  without truncation; content remains scrollable above the floating navigation.
- Empty and watched states were reviewed in the first pass; those screenshots predate
  the final shared-rendering corrections and are not final-state evidence.
- Native poster aspect ratios intentionally remain intact, so carousel card heights can differ.
- No DeviceInteraction hierarchy/touch tool was available. No account progress, additions,
  authentication, permissions or external Git state were changed. This is visual/layout
  verification, not live mark/unmark persistence or full VoiceOver verification.

Status: build and targeted visual checks passed; account-writing interactions untested.

---

# Schedule landscape selection — 20 September 2026

- Corrected `ArtworkScene`: an available landscape fills the card independently of
  whether a separate graphic logo exists. Missing logos no longer select the portrait
  panel and ambient background instead of the supplied landscape.
- Corrected the matching metadata inset in Schedule and `ArtworkSceneCard`. Facts
  and actions are centered on landscape cards; only a genuine portrait fallback
  reserves the leading column. Existing watched callbacks and navigation are unchanged.
- Confirmed in the app's cached catalogue that Bleach, Re:ZERO and The Witcher each
  have a TMDB landscape. This was a client selection bug, not missing landscapes.
- Signed simulator build, Swift parse and `git diff --check` passed.
- Independent screenshot review and primary-agent inspection confirmed landscape
  rendering on Schedule and the shared Library scene cards:
  - `/tmp/previously-today-qa/schedule-landscape-final.png`
  - `/tmp/previously-today-qa/schedule-landscape-anime.png`
  - `/tmp/previously-today-qa/schedule-landscape-library-regression.png`
- Unresolved identity issue: Bleach's landscape is textless and its catalogue record
  supplies no graphic logo. The card therefore currently has no visible series name.
  Opening detail for the normal metadata refresh did not supply a logo. No fabricated
  logo, manually rewritten cache or replacement typed title was introduced.
- At accessibility-extra-large, the existing weekday rail truncates/crowds labels;
  initial agenda positioning also shows part of an earlier card under the pinned
  calendar. Evidence: `/tmp/previously-today-qa/schedule-landscape-anime-ax.png`.
- Simulator restored to medium text and left on Schedule. No touch/hierarchy tool
  was available; screenshots do not establish mark/unmark persistence. No account
  progress, authentication, permissions or remote Git state was changed.

Status: landscape-selection fix verified; missing-logo identity and large-text rail
issues remain. This is not a full visual/accessibility pass.

---

# Landscape logo placement and size — 20 September 2026

- Replaced the scene's independent center-offset logo with shared `ArtworkSceneCaption`.
  The graphic logo sits bottom-leading beside the episode/action group in Schedule
  and the shared Library/Search landscape cards. Portrait compositions are unchanged.
- Increased the landscape logo box from 36 to 56 points high, with a width cap of
  224 instead of 180 points. Real logo artwork retains its aspect ratio.
- Signed iPhone 14 Pro simulator build, Swift parse and `git diff --check` passed.
  Independent screenshots and primary-agent inspection verified readable logos and
  separated metadata/actions on aired Schedule and Library cards:
  - `/tmp/previously-today-qa/landscape-logo-loweredge-aired.png`
  - `/tmp/previously-today-qa/landscape-logo-loweredge-library.png`
- Rejected the initial vertical caption: a watched action pushed the larger logo
  over faces again. The final side-by-side lower band clears the pictured faces.
  Library's narrower shelf uses two readable lines for season/episode metadata.
- The user identified the previous missing-logo issue as a duplicate identity and
  cancelled that investigation. The unused server handoff/test were archived; no
  backend implementation, deployment or catalogue mutation was performed.
- Added DEBUG-only `-scheduleCaptureDay` for read-only capture of an existing day.
  Negative offsets are parsed directly because UserDefaults treats `-1` as a flag.
  No live tracking interactions or account-writing QA were performed.

---

# Neutral tab headers — 20 September 2026

- Removed the poster-derived `ArtBackdrop` color wash from Today, Schedule, Library,
  All titles and Search. Root backgrounds use the same neutral canvas; actual poster
  and landscape artwork remains in the content.
- Schedule retains measured opaque coverage behind its status/title/calendar area.
  Other screens retain scroll-edge protection. Native floating navigation is unchanged.
- Signed simulator build, Swift parse and `git diff --check` passed. Independent
  capture and primary-agent image inspection confirmed the colored header haze is gone:
  - `/tmp/previously-today-qa/clean-header-schedule-aired.png`
  - `/tmp/previously-today-qa/clean-header-library.png`
  - `/tmp/previously-today-qa/clean-header-search.png`
  - `/tmp/previously-today-qa/clean-header-today.png`
- These captures verify the header change. The first Schedule sizing and large-text
  checks exposed further caption layout issues, tracked in the follow-up below.

## Final caption verification

- Bounded Schedule's scene to an aspect-ratio sizing box with an explicitly bottom-aligned
  stack. This prevents the larger caption from widening the card or floating at its center.
- Split shared caption facts and actions into separate slots. At accessibility text sizes,
  the action gets its own full-width row, avoiding the narrow, mid-word-wrapped button.
- Fresh signed-build screenshots independently reviewed and inspected by the primary agent:
  - `/tmp/previously-today-qa/clean-header-verified-schedule-aired.png`
  - `/tmp/previously-today-qa/clean-header-verified-schedule-aired-ax.png`
- Medium: equal outer gutters, larger bottom-leading logos, readable episode/action groups,
  no pictured face coverage or clipped controls. Accessibility-extra-large: the action is
  readable on one line and the caption stays separated from the scene's faces.
- The pre-existing large-text weekday rail issue remains (for example, Monday truncates).
  This pass does not establish full accessibility or mark/unmark persistence.
- Simulator restored to medium text and left on yesterday's aired Schedule cards.
  No account progress, backend data, authentication or remote Git state was changed.

---

# Announced seasons and full-bleed Today — 20 September 2026

- Confirmed Wednesday's cached Season 3 is `NOT_YET_RELEASED`, with zero listed
  episodes and no air date. The UI forced at least one episode row and selected
  the first unfinished season, incorrectly making the announcement an Episode 1.
- Removed the forced row. Upcoming seasons show only explicitly listed episode
  numbers, not a season-order count; empty announcements get an honest explanation.
  Upcoming episodes cannot be marked watched. Dated season-only metadata no longer
  fabricates Episode 1 for Schedule.
- Detail defaults to the last released season when the viewer has completed it.
  An upcoming season remains selectable. Hero facts explicitly say "Season 3
  announced" and retain the supplied release window without inventing a day.
- Restored a full-width Today hero behind the status/header area for single,
  multiple, inactive and caught-up states. Multiple releases are full-width pages.
  Removed the rounded-card sizing and detached multi-release headings; retained
  the shared artwork logo, watch toggle and native floating navigation.
- The first rendered pass caught the full app wordmark colliding with authored
  Re:ZERO lettering. Over hero artwork it now uses the small brand mark; the full
  wordmark returns over the scrolling header. No blurred top cap was introduced.
- Added opt-in DEBUG `-verifyAnnouncements 1` regressions and read-only
  `-openFranchise ID`, `-detailAnchor episodes`, `-detailSeason LABEL` capture routes.
  These do not change account progress or season status.
- Real-account review found two cases the demo-only pass missed: Avatar's detail
  response contains 13 dated but otherwise empty `Episode N` placeholders, and a
  populated recommendation shelf compressed the horizontal hero's layout height.
  Upcoming detail lists now require substantive episode metadata; known dates
  remain on the season and Schedule. The hero pager reserves its measured height,
  including large-text growth, so the next shelf cannot overlap the watched action.
- Final signed build, Swift parse and `git diff --check` passed. The on-device DEBUG
  runner printed `ANNOUNCEMENT_REGRESSIONS_PASS 22` through a filtered console.
- Independent screenshot QA and primary-agent inspection confirmed:
  - `/tmp/previously-today-qa/announcement-wednesday-hero.png`: explicit announcement
    plus the supplied release window, with no episode action.
  - `/tmp/previously-today-qa/announcement-wednesday-episodes-default.png`: real
    released Season 2 episodes remain available to browse.
  - `/tmp/previously-today-qa/announcement-wednesday-season3-verified.png`
  - `/tmp/previously-today-qa/announcement-avatar-episodes-verified.png`: both
    upcoming sections show the explanatory empty state, no generic episode rows.
  - `/tmp/previously-today-qa/fullbleed-final-live-verified.png`
  - `/tmp/previously-today-qa/fullbleed-final-live-ax-verified.png`: sharp full-bleed
    art, readable hero facts/action, pager and recommendations in separate layout
    regions, native floating nav retained. At AX the shelf continues below the fold.
- Screenshot-only verification: touch, VoiceOver hierarchy and mark/unmark
  persistence were not exercised. Left the simulator at medium text on real Today
  (`-demoBusy 0`), without synthetic progress or detail-capture routes active.
  No server, account or remote Git changes were made.

## Detail news and bulk progress — 20 September 2026

- Root cause: the off-library hero rendered only the title, while release facts lived in
  progress-dependent `NextUp` states. Public `ReleaseNews` now derives only from catalogue
  facts and is shown before adding, while planned/behind, and after completion. Release
  windows retain their stated precision. The fresh detail catalogue also brings newly
  added seasons without overwriting live progress or the selected artwork.
- Visible `Mark series watched` beneath hero actions and `Mark season watched` beside the
  episode section replace the overflow-only discovery path. Each uses one confirmation
  naming the exact released episode count; announced seasons and unaired episodes are
  excluded. Marking from Search adds membership in the same server transaction.
- Wired the existing atomic franchise-progress endpoint instead of firing one request per
  season. One Undo restores the previous progress/status and, for a newly added show,
  previous membership. Controls show saving state; failures remain retryable via SyncCenter.
  The client waits for the canonical response before claiming success, serializes behind
  pending episode writes, and rejects late responses after account teardown.
- Neutral artwork actions retained. Independent device-skill QA found large-text episode
  numbers truncating; accessibility rows now stack art above the full episode identity/date.
- Regression runner `-verifyDetailProgress 1`: 28 assertions passed for progress-independent
  news, fresh catalogue merging, released-only plans, exact counts, atomic writes, new
  membership, season isolation, Undo, failure and persistent retry encoding. Network tests
  use an ephemeral in-memory URLProtocol at a `.invalid` host, a dummy token, a separate
  AppModel and disabled cache writes. Existing announcement runner: 22 passed. Backend
  `src/services/library.test.ts`: 3 tests passed. No real-account writes were used for QA.
- Read-only screenshots: `news-untracked.png`, `news-behind.png`,
  `news-series-confirmation.png` under `/tmp/previously-today-qa/`. Confirmation correctly
  states 16 episodes across two seasons, not the announced third season. Captures exercise
  the real renderer, not touch/VoiceOver interaction or live-server write persistence.
- Percy Jackson follow-up diagnosis: the cached API gallery supplies six English titled
  portraits and no textless portrait. Its selected portrait is not in that gallery, so the
  client fails to identify the embedded title and draws a second graphic logo. Confirmed
  in `news-percy-hero.png`. A hero should use textless key art plus one separate logo; a
  catalogue poster tile may retain its baked-in title. This artwork issue is not fixed in
  this news/progress change, and no backend/catalogue deployment has been performed.
- Final signed build and `git diff --check` passed; both client regression runners passed
  again on the installed final build. Independent and primary-agent screenshot review:
  `news-final-untracked.png` (neutral white Add and visible series action),
  `news-final-season-medium.png` (visible season header/action), and
  `news-final-season-ax.png` (full episode numbers and dates, no clipping).
  Simulator restored to real Wednesday at medium text without preview flags.

## Artwork identity and authored-poster fallback — 20 September 2026

- Root cause: the detail fallback deliberately repeated a titled poster's name in type.
  When the selected poster was missing from the capped gallery, it instead assumed clean
  artwork and overlaid a second graphic logo. Seven Havens and Percy demonstrate both paths.
- Added an explicit embedded-identity treatment shared by franchise/summary presentation.
  A measured TMDB image with no language is eligible for a separate logo; a URL-only
  fallback is not. Clean-only galleries no longer require an English-titled sibling.
  Embedded posters receive neither a second logo nor a plain-text title. VoiceOver's
  combined lockup retains the full title, release news and progress facts.
- Independent device-skill QA caught two first-pass collisions: Percy's announcement
  covered its printed logo, and Re:ZERO's wide status pill covered its upper logo.
  Status choices remain directly in the overflow menu for this fallback;
  the episode/season/series watched actions remain separate and visible as applicable.
- The user rejected BOTH intermediate footer versions: first the hard/blurred bands, then
  even the seamless version because the information was still beneath the poster. Neither
  is the accepted direction, and captures labelled `artwork-*-final.png` were that rejected
  intermediate build, not approval evidence.
- `AuthoredHeroArt` now uses the complete native-aspect image at regular sizes. Announcement/date
  and actions are overlays WITHIN that image. A cached, on-device Vision pass locates the
  existing printed wordmark so `PosterLockupLayout` can use the space around it. Percy
  splits news above the wordmark and the watched action below; upper-title posters can
  keep the overlay together at the bottom. No source artwork is edited, no poster height
  is added for a footer, and there is no second visual title. At large accessibility sizes,
  measured controls can grow the full-bleed artwork surface itself instead of overflowing
  into the synopsis; the image fills that taller surface. Only the image's final edge fades
  into the existing page ground. Re:ZERO's pale artwork also gets a local, soft neutral
  legibility scrim behind its controls, with white episode facts rather than gray-on-pale ink.
  Planned/caught-up announcement states no longer mix in an unrelated progress pointer;
  an episode fact remains when it identifies an actionable watched control.
- Server mapping, catalogue merging and API gallery capping now retain a measured clean-art
  alternative within the six-entry limit. Highest-ranked poster and logo ordering remain
  intact. A duplicate URL-only entry can gain actual dimensions/language from its enriched
  counterpart. Documented these semantics without changing the JSON shape.
- `npm run typecheck` and all 176 backend tests passed. The final installed iOS regression runners
  reported 24 artwork identity, 22 announcement and 28 isolated/mock progress assertions.
  Signed simulator builds and `git diff --check` passed. No account writes or Git push.
- Backend changes are local only, not deployed. The laptop has no configured TMDB token
  or authorized AniTrack deployment route to the Mac mini. The live payloads inspected for
  Percy and Seven contain no clean portraits; upstream availability has not been established.
  The client fallback works with those actual payloads without claiming that new clean
  artwork has been fetched or that the cancelled earlier deployment was resumed.

### Today poster taps and logo language

- The user then reported that 3 Body Problem and The Beginning After the End would not open
  from Today. Both real detail routes rendered through direct links; those checks alone did
  not prove the card-tap path. The shared poster's decorative logo/gradient layer was above
  its open button. It now opts out of hit testing when the poster has no detail controls.
- Beginning's live gallery contains a larger untagged Arabic wordmark ahead of five English
  alternatives. Franchise and summary artwork now share an English-first logo choice;
  explicitly foreign-language logos are not substituted when no English/untagged option exists.
- Native simulator interaction is available using the installed idb entry point through
  `/usr/bin/python3` and this repository's Xcode-shadow `DEVELOPER_DIR`. Its old executable
  shebang references a removed Xcode-beta. The accessibility hierarchy is read before taps;
  direct routes are not counted as proof of card opening.
- Actual tap on the 3 Body Problem logo in Today's recommendation shelf opened its detail:
  `/tmp/previously-today-qa/today-tap-check-current.png`, confirmed with the native hierarchy.
- Actual tap on Beginning's graphic logo in that shelf also opened its detail, confirmed by
  the native heading and episode hierarchy plus `beginning-today-actual-tap-release-check.png`.
  Simulator returned to normal Today at medium text after both navigation checks.
- Final release-candidate screenshot review confirmed Beginning's English graphic logo
  (`beginning-english-release-check.png`), Percy's accessibility-extra-large controls stay
  within the artwork without overlapping the synopsis (`percy-behind-ax-release-check.png`),
  and Re:ZERO's facts/actions remain readable on pale art (`rezero-contrast-release-check.png`).
  These captures are under `/tmp/previously-today-qa/`; no watched/library state was changed.
- Remaining catalogue-art limitation: Beginning's selected source portrait itself contains
  faint baked-in Arabic lettering underneath the now-English separate graphic logo. The
  language-priority fix corrects the selected logo but does not erase lettering in source art.
  Visible in `beginning-before-tap-release-check.png`; not counted as a clean-art pass.

## TestFlight upload — 20 September 2026

- Bumped `ios/project.yml` to version 1.0, build 2 for both app and widget; regenerated
  the Xcode project. Preserved all existing working-tree changes, without commit or push.
- Release archive succeeded using Xcode 27.0 (27A266a), arm64, team YLPZXZS2F4:
  `ios/build/Previously-1.0-2-20260920.xcarchive`.
- First upload failed before transfer with an App Store Connect connection error (-1004).
  A connection check reached the endpoint; retrying the same archive succeeded.
- Xcode reported `Upload succeeded` and `EXPORT SUCCEEDED` at 10:08:42 IST. Apple's last
  returned state was `Uploaded package is processing`. This is upload proof, not proof of
  completed TestFlight processing or availability to testers.
- Successful distribution logs:
  `/var/folders/5r/t6767z_96m5990yczng8_rj80000gn/T/AniTrack_2026-09-20_10-06-55.850.xcdistributionlogs`.
- App Store Connect browser is at the sign-in page. Requested user sign-in to inspect the
  existing tester group and complete/verify distribution. No groups, testers, public links,
  App Store release settings, backend deployment or legal agreements were changed.
- Follow-up verification through the user's signed-in **Codex in-app browser** completed:
  upload processing is `Complete`; the existing internal `Friends & Family` group has
  3 testers and build `1.0 (2)` is explicitly `Testing`. It was assigned automatically;
  no additional testers or group permissions were needed. App Store Connect also records
  an installation of build 2. Saved the build's What to Test notes, including the known
  provider-poster lettering limitation, and verified the `Saved` state.
- Internal TestFlight release is confirmed. External review/distribution was not changed.
  Verified group builds page:
  https://appstoreconnect.apple.com/teams/ed70022a-b3ca-4ff2-b4ab-1947652610e7/apps/6809458022/testflight/groups/d2f5a857-9daa-4622-8970-f0e742519630/builds
