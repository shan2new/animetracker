# Previously App Store readiness — second pass

30 September 2026. Source: `572cb857d73222f5a1b16a4025a24fe1566387c8`, branch `spike/today-feed`. This extends the [main release audit](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/app-store-readiness.md), which contains the native walkthrough, original R1–R10/F1–F7/E1–E10 backlog, import strategy, and Clerk research.

**Assessment: submission readiness is still unproven.** The second pass adds specific media-policy, durability, account-lifecycle and API-contract gaps. It also strengthens evidence that several existing controls work. Missing product features and mandatory store requirements have different priorities; a free app does not need purchases, every possible import source, or every optional Clerk feature to ship.

P0 means a submission/public-release gate. P1 means finish before the intended launch or narrow the product promise. P2 means later improvement. “Source-confirmed” establishes an implementation boundary; it does not establish that a particular race has occurred on a real user's phone. Conditional gates apply when the corresponding feature is enabled.

## New evidence

| Check | Result | What it does not prove |
| --- | --- | --- |
| Normal signed Release simulator build | **Succeeded.** No fixture/config overrides. [Build log](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/round-2-evidence/ios-release-simulator-build.log) | Distribution archive, signing for a physical device, minimum-iOS execution, TestFlight delivery, App Store validation |
| Actual Release bundle inspection | `com.anitrack.app`, Previously., 1.0/build 5, iOS 18 minimum, public API URL, **development Clerk key**. App, ClerkKit, ClerkKitUI and PhoneNumberKit privacy manifests present. No Face ID description or URL schemes in this bundle. [Inspection](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/round-2-evidence/release-bundle-inspection.json) | Manifests being present does not prove their completeness or store-label accuracy. Missing Face ID description becomes relevant when biometrics are enabled; missing URL schemes requires checking the chosen callback flow, rather than assuming every OAuth flow is broken |
| Real PostgreSQL API probe | All migrations; two synthetic identities; validation, canonical counts, overflow/rollback, export ownership, suspended access and social erasure exercised. [Results](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/round-2-evidence/database-probe-results.json) | Real Clerk tokens/providers, production parity, every ownership endpoint, every combination of social relationships or concurrent requests |
| Deletion across 17 seeded tables | Correct deletion and preservation for the tested relationships; surviving other-author reply becomes top-level; ban remains effective | Provider deletion, Apple token revocation, backup retention, durable erasure tombstones or local-device cleanup |
| Network monitor lifecycle | macOS platform probe: initial object delivered, canceled object did not deliver after restart, new object delivered. [Probe log](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/round-2-evidence/path-monitor-probe.log) | A full native sign-out/sign-in/offline workflow on iPhone |
| Public health recheck | Public and local API both **200 at 07:30 UTC / 13:00 IST**. [Check](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/round-2-evidence/health-recheck.json) | Sustained uptime, external-network/cellular access, authenticated usage, database/catalogue freshness |
| Native interaction | Device Hub exists; another accessibility-control attempt timed out | No new tap, OAuth, VoiceOver, trailer playback or notification-delivery proof. The first pass's current-run screenshots remain the visual evidence |

The newly owned audit database was removed after the probe closed its connections, without forced disconnection. All identity/provider/LLM credentials were blank in the probe environment. No production users, source code, dependencies, configuration, feature flags or deployments were changed. Reproduction commands and boundaries are in the [second-pass evidence README](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/round-2-evidence/README.md).

## Additional findings

### N01 — YouTube player cropping and application identity

**P0 — source-confirmed provider-policy mismatch.** [TrailerPlayback](/Users/shan2new/Projects/animetracker/ios/Sources/Features/Trailer/TrailerPlayback.swift:15) explicitly describes making the player three frames tall to hide the title/channel/logo/related UI. The HTML uses `top:-100%; height:300%`, disables interaction with the web view, and supplies `https://previously.local` as its origin/referrer. This is a deliberate implementation, rather than a hypothetical concern about using an embedded player.

YouTube prohibits obscuring attribution and player functionality; its minimum-functionality rules also prohibit obscuring overlays and require the explicit WebView referrer to identify the app using its registered application ID. The source's fabricated host is different from the Release bundle ID. Choosing supported player parameters such as `controls:0` alone is not the finding; the crop, masking and identity are. [Developer policies](https://developers.google.com/youtube/terms/developer-policies), [required minimum functionality](https://developers.google.com/youtube/terms/required-minimum-functionality).

**Work:** keep inline playback, but use a compliant player presentation with visible provider attribution and working provider affordances. Use the actual bundle identity for the documented WebView configuration; `modestbranding` is deprecated and has no effect. Restore a usable captions path. If a compliant embed cannot meet the desired experience, use an explicit provider handoff while preserving the rest of the show screen. [Supported player parameters](https://developers.google.com/youtube/player_parameters).

**Acceptance:** real embeddable, disabled-embed, removed, age/region-restricted and unavailable videos; visible attribution, captions, play/pause/seek, rotation and full-screen return; no hidden ads/links; multiple trailers without simultaneous autoplay; low-data/low-power/autoplay accessibility settings; correct referrer observed in a controlled diagnostic. Playback was not exercised in this pass.

### N02 — Consent and data handling for AI-assisted search

**Conditional P0 when raw-user-query correction is enabled.** [correctSearchQuery](/Users/shan2new/Projects/animetracker/server/src/services/queryCorrect.ts:46) sends the trimmed search string as a user message to Cerebras. The feature is disabled when its flag/key disables it, but it has no per-user permission boundary. No native AI-consent surface was found. The draft legal copy mentions AI search; a policy paragraph does not supply an explicit in-app choice before personal data is shared.

Apple 5.1.2(i) requires disclosure and explicit permission before sharing personal data with third parties, including third-party AI. User-entered search can contain personal information. This is a conditional release review gap for that raw-input path, not a claim that all AI processing of public catalogue metadata requires personal-data consent. [Apple privacy guidelines](https://developer.apple.com/app-store/review/guidelines/).

**Work:** either disable this path for launch, or offer an optional, understandable AI-search permission naming the recipient/purpose, with a literal-search fallback. Enforce consent server-side; record consent version and withdrawal. Review provider retention, training use, data location and deletion commitments before publishing the corresponding statements. Avoid sending account identifiers or unnecessary context.

**Acceptance:** denied/unset/withdrawn consent sends no query to the AI provider; literal search still works; retries and older clients cannot bypass the boundary; policy, consent and actual enabled configuration agree.

### N03 — Failed-write recovery is not a durable outbox

**P1 — source-confirmed crash window.** [SyncCenter.retry](/Users/shan2new/Projects/animetracker/ios/Sources/App/SyncCenter.swift:261), `retryAll` and `replayProgress` remove rows and persist the removal **before** awaiting the replay. A process termination in that interval loses the durable retry intent. Normal progress writes first enter an in-memory lane; their intent is saved after a caught failure rather than before dispatch. A retry that fails normally re-records itself, and restored rows without a runnable intent correctly remain visible; those safeguards do not cover termination between removal and acknowledgement.

**Work:** save owner-scoped commands before dispatch, retain pending/in-flight commands until acknowledged, and replay safely after interruption. Keep per-part ordering and coalescing so older progress does not overwrite the user's latest intent. Add operation identity/receipt semantics for compound actions; failed and in-flight are both unsynced states. A restored status/membership replay must await its actual network outcome, rather than settling merely because it scheduled a task.

**Acceptance:** terminate before sending, while sending, after server commit but before receipt, and during Retry all. Relaunch with and without connectivity. The latest operation survives, is replayed safely and cannot run under another account. This pass traced the source ordering; it did not force-kill an iPhone during a real write.

### N04 — Connectivity monitoring cannot restart after sign-out

**P1 — source and platform lifecycle confirmed.** [SyncCenter](/Users/shan2new/Projects/animetracker/ios/Sources/App/SyncCenter.swift:138) owns a single `let NWPathMonitor`. Teardown calls `cancel()`, and the next signed-in root calls `startMonitoring()` on that same object. Apple DTS explicitly says a canceled monitor must be replaced. The standalone host probe confirmed that a newly created replacement delivers while the canceled object does not. [Apple DTS explanation](https://developer.apple.com/forums/thread/124486).

**Impact:** after sign-out/sign-in, online/constrained/expensive state can remain stale, affecting notices, queued-social flushing and trailer data policy.

**Work:** recreate the monitor for a new observation lifetime or keep one app-lifetime monitor with correct subscribers. Discard callbacks from an obsolete lifetime and initialize the new account's state deliberately.

**Acceptance:** repeated sign-out/sign-in, then Wi-Fi/cellular/offline/low-data transitions update state and flush eligible writes without app restart.

### N05 — Validation errors and bulk integer limits

**P1 — reproduced against real routes and PostgreSQL.** Invalid country, subscription UUID, subscription status and search/trending limits each returned **500**. Those handlers use throwing Zod `.parse` without translating validation failure to 400. Newer progress/recommendation/social paths already use `safeParse`; the correction should target the inconsistent handlers, not rewrite working validation.

The single-progress route correctly rejects `10,000,000,000` with 400. The bulk route accepts that count for an unsized part and PostgreSQL returns **500 / integer out of range**. The bulk schema lacks the single route's INT4 upper bound. Import and malicious/older-client input make this boundary relevant even though ordinary UI controls may never send it. Search `limit` also lacks an integer constraint and `q` lacks a length limit. Search is authenticated and already has timeouts/abort handling plus a bounded enrichment queue; it is not an unprotected, infinitely queued public route.

**Work:** consistent request validation and stable 400 error payloads; matching single/bulk numeric bounds; integral pagination; bounded query size; per-user/request cost controls for upstream search and AI work. Preserve the existing execution budgets/backpressure.

**Acceptance:** malformed, fractional, oversized, empty and boundary inputs return intended client errors without writes or unnecessary upstream work. Do not retry permanent validation failures as infrastructure outages.

### N06 — Writes acknowledge less than the client needs

**P1 — two concrete response mismatches reproduced.** A releasing season with 5 aired episodes accepted a request for 12, correctly stored 5, and returned only `{ok:true}`. [PUT /me/progress](/Users/shan2new/Projects/animetracker/server/src/routes/me.ts:185) discards the service's canonical `episodes`; [putProgress](/Users/shan2new/Projects/animetracker/ios/Sources/App/AppModel.swift:1747) settles the requested value. A later library reload correctly retires a disagreeing settled overlay, so this is temporary inconsistency, not an assertion that the client pins the wrong count forever.

Separately, PATCHing a valid franchise's status without an existing subscription returned 200 with **zero subscription rows**. The update does not distinguish missing membership from a successful status change. This can arise from stale UI or a second device removing membership.

**Work:** return canonical saved progress, status/membership and a suitable revision; apply that response immediately. Decide whether missing membership is a 404/conflict or an explicit upsert; avoid success that saved nothing. Keep DELETE of an already absent subscription idempotent.

**Acceptance:** stale catalogue count, different client/server time, concurrent unfollow and multi-device writes show the confirmed result and a truthful receipt.

### N07 — Existing-library bulk marks can partially commit

**P1 — source-confirmed; atomic server capability already works.** [markWatched](/Users/shan2new/Projects/animetracker/ios/Sources/App/AppModel+Writes.swift:21) uses independent per-part progress writes plus a separate status update for a show already in Library. The same action for a new show uses the atomic franchise endpoint. Existing-library marks and their Undo therefore can persist only some parts if connectivity/termination intervenes, while presenting one batch receipt.

The real-DB probe verified the server's atomic endpoint: a later-part overflow rolled the earlier part back; a valid request returned both canonical part counts and status. This is a client integration gap, rather than a missing backend transaction.

**Work:** use the existing serialized franchise command for compound marks/Undo, coordinated with per-part lanes. Audit completion, caught-up, rewatch reset/cancel and Undo for the same multi-write boundary. Rewatch history remains a separate durable-model gap from F5.

**Acceptance:** failure on any part/status or termination mid-command cannot leave an unreported partial batch. Rapid individual marks followed by batch/Undo preserve the user's final intent.

### N08 — Account changes must be keyed by identity, not a Boolean

**P0 integration gate for account isolation; expands R5.** [AuthManager.refreshClerkSignInState](/Users/shan2new/Projects/animetracker/ios/Sources/Auth/AuthManager.swift:77) publishes session presence. [RootView](/Users/shan2new/Projects/animetracker/ios/Sources/App/RootView.swift:24) starts/tears down the app on a signed-in Boolean transition. An A-to-B active-session change that stays non-nil does not establish a new account generation. Persisted library/retry records also have no owner identity. [TokenRefresher](/Users/shan2new/Projects/animetracker/ios/Sources/Networking/APIClient.swift:155) reuses a successful token for three seconds without an account-scoped reset.

Ordinary sign-out already clears substantial state and cancels lanes; this is not a claim that teardown is absent. No A-to-B native switch was exercised, and the current UI does not expose a dedicated account switcher. The missing boundary matters when adding Clerk profile/session management, restoring externally changed sessions, or recovering after interrupted cleanup.

**Work:** make internal account identity plus session generation explicit; owner-scope caches, retries, history and tokens; drain/cancel obsolete requests; reject late responses/writes. Clear owner state before installing the new account's callbacks. Cover backups and temporary exports as R5 already requires.

**Acceptance:** A offline → restart → B; A request/token refresh delayed until B; session switch without an intermediate nil; pending export, retry, rewatch and notification work. B never sees or sends A's account data.

### N09 — Ambient tasks can outlive the account that scheduled them

**P1 — source-confirmed race risk; expands F6/R5.** [EpisodeNotifications.sync](/Users/shan2new/Projects/animetracker/ios/Sources/Notifications/EpisodeNotifications.swift:73) suspends for permission settings and individual additions. A prior sync can resume after `cancelAll()` and add captured old-library alerts. [AiringLiveActivityManager](/Users/shan2new/Projects/animetracker/ios/Sources/Notifications/AiringLiveActivityManager.swift:49) launches detached, untracked tasks for sync and end-all, so those operations are not ordered by account generation. No interleaving was induced on an iPhone in this pass.

**Work:** serialize/cancel scheduling work with owner generation and current desired revision; make teardown await a final clear or prevent older tasks from publishing afterward. Use stable franchise/episode IDs rather than only title/episode to identify an activity. Surface scheduling errors instead of swallowing every add failure.

**Acceptance:** delayed permission/add/activity calls during sign-out/deletion and rapid status/reminder changes; no obsolete pending or delivered account alerts; final activity reflects the latest account. Also test DST/time-zone changes, date-only TV premieres, 48-request budget, denied permission and long absence.

Notification routing is already implemented through typed `OpenRoute`, with cold-launch pending routes. Do not describe notification taps as wholly missing. The remaining checks include stale/deleted destinations, suspended/signed-out access, mode changes and actual OS delivery.

### N10 — TMDB notice exists; its required logo is not rendered

**P1 — corrects an incomplete first-pass conclusion.** [Profile colophon](/Users/shan2new/Projects/animetracker/ios/Sources/Features/Profile/ProfileView.swift:1128) contains the required notice. `TMDBLogo.imageset` exists, but no `TMDBLogo` use was found in native source. TMDB requires both approved logo attribution and the notice in an About/Credits-type section. [TMDB requirements](https://developer.themoviedb.org/docs/faq).

**Work:** display the existing approved asset with readable attribution in the credits surface; preserve prominence/aspect/color rules and verify the asset against the approved original. Record catalogue, artwork, trailer, fonts and icon licenses; establish permission for the intended commercial use before introducing revenue. This audit does not prove every asset is unlicensed.

**Acceptance:** credits in the Release build include readable notice and correct logo; archive/license inventory and monetization assumptions agree.

### N11 — Search terms can enter diagnostic logs

**P1 — source and isolated request-log behavior confirmed.** Fastify uses default request logging, including request URLs. Native [retry logs](/Users/shan2new/Projects/animetracker/ios/Sources/Networking/APIClient.swift:784) mark the path as public; search puts `q` in that path. Raw query text can therefore enter server logs and device unified logs during retry. The dedicated `search.profile` object itself records length/timings/counts, rather than raw query; preserve that more restrained telemetry.

**Work:** log route templates and request IDs, redact query strings/identifiers and review error bodies before logging. Set retention/access controls; inventory search processing/storage for privacy disclosures and providers. An app manifest lacking a Search History entry does not by itself establish the correct store answer; decide from the actual collection/retention and Apple's definitions. ATT is not automatically required merely because the app has diagnostics or embeds a provider.

**Acceptance:** a unique synthetic query cannot be found in ordinary production-style logs, including retry/exception paths; useful timing/error diagnostics remain. No real user searches were inspected for this audit.

### N12 — Release passes with concurrency warnings

**P2 hardening, with a release-compiler gate.** The Release log contains 28 distinct file/line warning diagnostics, including actor isolation, Sendable captures and unused shader functions. A warning-free build was not obtained. These warnings are not evidence that the current candidate fails to compile or crashes; the build succeeded.

**Work:** triage actor/capture warnings ahead of cosmetic unused-function warnings; pin the intended Swift/SDK/dependency versions in CI and verify future compiler-mode changes deliberately. See the exact diagnostics in the bundle-inspection JSON and build log.

**Acceptance:** targeted changes eliminate meaningful isolation warnings and preserve visual timing; current release CI builds from committed resolution with its intended compiler settings. Avoid unrelated cleanup during urgent release fixes.

## Strengthened checks and corrections

| Area | Second-pass conclusion |
| --- | --- |
| Public outage | Both health URLs recovered to 200. Investigate the recorded interruption, add external/dependency/freshness monitoring and test recovery; do not label the route permanently down |
| Database erasure | A broader 17-table synthetic scenario passed. Other-author reply, library, progress, likes, saves, rating and relevant inbox data survived; dependent relations to the deleted user were removed |
| Suspended identities | Ban blocks normal reads, permits export/deletion, persists after deletion; after clearing the in-memory erasure hold, normal read returns 403 and erased export 404 without account recreation |
| Export | Anonymous access returned 401, a forged `userId` progress body returned 400, the other user's export omitted the first author's comment body; export already sets `Cache-Control: no-store` |
| Bulk backend | Transactional rollback and canonical successful response were verified with actual PostgreSQL |
| Adult-source filters | AniList upstream search/trending uses `isAdult:false`; TMDB search uses `include_adult:false`; recommendations exclude adult/Hentai targets. These exist already. Cached catalogue, related/direct titles, artwork and trailers still need end-to-end review for the selected store rating |
| Trailer autoplay | Existing code honors the OS video-autoplay preference, low-data and low-power conditions, and selects one preview per surface. Keep these protections when repairing the player. User-level autoplay/cellular controls and multi-surface behavior still need verification |
| Privacy manifests | Four manifest files are in the built Release simulator bundle. The candidate archive's aggregate privacy report still needs review against all app/provider behavior |
| Test boundaries | Main mocked suite/typecheck were already green; they were not repeatedly rerun after documentation-only work. New probes cover previously missing real-SQL/platform boundaries |

## Product completeness: dependencies the implementation must cover

The original feature backlog stands. These are additional acceptance details, not a second set of duplicate “missing mode/onboarding/import” tickets.

| Product area | Work still needed and easy-to-miss boundary |
| --- | --- |
| Content mode | One account preference with a single source/classification policy; anime `TV` format remains Anime. Keep the full library; distinguish a filtered-empty view from an actually empty account |
| Home | Hero, next action, queue, caught-up counts, recommendations and milestone receipts all use the same scope |
| Schedule | Calendar/list/day counts, timezone/date precision, premieres and filters; changing mode must recompute cached derived state |
| Feed | Following, Discover/trending, posts, trailers, recommendations, muted shows and saves; define whether explicit saved content remains available outside the default mode |
| Library/detail | Shelves/search/counts, Show all escape, pushed detail, batch operations, Undo, rewatch/history and hidden-title context. Mode changes must never delete membership/progress |
| Discover | Query/source, trend/genre/year/status/provider filters, suggestion chips, corrected queries and recent searches; switching mode cannot leave stale requests/results mislabeled |
| Routes/ambient surfaces | Explicit out-of-mode title opens with context; signed-out routes resume after authentication/onboarding. Schedule alerts/activities follow the stated scope. External universal links/widget destinations remain unimplemented/unverified; typed internal notification routes already exist |
| Profile/export/delete | Preference sync and device state ownership; statistics need labeled scope. Export/delete cover the **entire account** irrespective of mode |
| Onboarding | Skip/resume/reset/versioning; TV/Anime/Both; country/providers; manual seeds or file import; mark existing progress; optional contextual permission. A returning user/reinstalled app uses saved preferences without replaying destructive setup |
| Country/providers | Expose existing server preferences natively; override device-region defaults; resolve country changes, provider availability caching, attribution and external-provider URL fallback |
| TV Time import | Saved GDPR ZIP/CSV ingestion, because the service closed. Real export fixtures are still required to establish supported schema variants. Preview matching and losses before applying; preserve dates/gaps/rewatches where advertised; distinguish unsupported general movies; make replay idempotent |
| Import safety/recovery | Bounded archive/file sizes and row counts, safe path handling, encoding/CSV variants, local parsing of unnecessary personal fields, resumable jobs, cancellation, duplicate imports, conflict policy and an undo/receipt. Treat imported text as data, including spreadsheet formula handling in subsequent CSV exports. Do not “complete” a lossy import without listing skipped/unmatched records |
| Watch history | Server-authoritative dated events/rewatch sessions and versioned restore format if those are promised. Current progress count and local rewatch files cannot reproduce arbitrary TV Time episode history |
| Notifications | Per-type preferences and permission state, meaningful TV date-only semantics, long absence, scheduling failures, account-safe lifecycle and route recovery. A server/APNs pipeline is a design choice if guaranteed continuous delivery is promised; finite local scheduling already exists |
| Media | Compliant inline playback, captions, provider failure fallback, data/autoplay preference, orientation/fullscreen recovery, screen-reader controls and foreground/background/audio-session behavior |
| Support/recovery | Reachable final support/privacy/deletion pages; actionable errors without secret detail; data/export recovery; operator moderation/erasure retry and ownership-safe account migration |

![Previously Profile from the first pass, at the same audited commit: mode, market/provider and import settings are absent](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/evidence/07-profile.png)

This capture uses the loopback synthetic developer session described in the main audit. It is reused as same-commit visual evidence, not presented as a new production-account capture. DEBUG rows and absent fixture artwork are not launch defects.

## Clerk: updated integration priorities

The first pass's feature-fit table remains applicable. The current native SDK resolves **1.5.7**, and the official releases page still identifies it as latest when checked. September 1.5.4 added UserDefaults manifests, 1.5.5 added biometric session reverification and a mismatched-token fix, 1.5.6 tightened biometric reverification, and 1.5.7 fixed a dependency URL for Xcode Cloud. Those features are already in the resolved SDK; their availability does not mean this app configured them. [Official releases](https://github.com/clerk/clerk-ios/releases).

1. **Ship production Apple/Google plus reliable recovery first.** Verify production instance/DNS/native registration, Apple capability and authorization lifecycle, callbacks, backend issuer verification and secret configuration. Preserve app UUIDs through a verified beta-to-production reassociation. Do not treat shared email strings as proof of identity, especially Apple relay addresses.
2. **Fix authentication completion and owner transitions.** Current sheet/root use `session != nil`. Clerk's views can handle post-auth tasks and biometric enrollment, but the wrapper should not close them prematurely. Distinguish active session, pending task, auth-flow completion and account identity. [AuthView](https://clerk.com/docs/ios/reference/views/authentication/auth-view), [session tasks](https://clerk.com/docs/guides/development/custom-flows/authentication/session-tasks).
3. **Use account/security UI with app erasure integrated.** Linked providers, credentials, sessions and recovery are useful. Clerk-only deletion must not leave the application DB behind; signed webhooks require replay/reconciliation. Account-switching UI must wait for N08 to be solved.
4. **Protect deletion and identity changes with recent-auth enforcement.** Reverification is useful, but our Fastify `DELETE /me` must validate recent authentication itself. Client-side biometrics alone do not secure that endpoint. Test provider cancellation, expiration and challenge failure.
5. **Optional mobile biometric sign-in after core login is stable.** It creates a real Clerk session using an installation credential, separate from passkeys. Add Face ID description, enrollment/revocation/reinstall fallback and correct auth-flow completion. The current Release plist has no Face ID description. [Biometric guide](https://clerk.com/docs/ios/guides/development/custom-flows/authentication/biometric-sign-in).
6. **Passkeys and OTP delivery diagnostics next.** The native API supports passkey sign-in; test association and account recovery rather than merely adding a button. The previously researched Email Logs can support OTP delivery investigation. [Native auth API](https://clerk.com/docs/ios/reference/native-mobile/auth).

Native API changes CAPTCHA/bot-protection assumptions; test the actual native configuration and abuse controls. Keep preferences/onboarding/history in application storage. Enterprise organizations/SSO and agent OAuth are low-value additions for this launch. Clerk Billing API availability does not establish a compliant native purchase flow; StoreKit/entitlement/restore work is conditional on adding paid digital functionality. The backend SDK's major-version gap is a separate task from the up-to-date native SDK.

## Coverage ledger and remaining proof

| Release dimension | Coverage and outstanding evidence |
| --- | --- |
| Build/configuration | Debug and Release simulator compile, actual Release settings/manifests inspected; committed dependency resolution, clean CI, physical archive and signing still pending |
| Authentication | Source and current docs/release research; production dashboard, Google/Apple first/returning/canceled/relay login, pending tasks and session revocation not exercised |
| Tracking | Count clamps/transactional bulk tested on real DB; native rapid marks, Undo, app-kill durability, partial existing-library batches and multi-device conflicts pending |
| Account ownership | Selected route/export checks passed; native A/B cache/token/history/notification boundaries and every endpoint remain broader test work |
| Erasure | Local DB breadth improved; provider retries, process restart/multiple server instances, tombstones, Apple revocation, backups and unknown client outcomes still gates |
| First-run/value | Current-run synthetic empty/populated screens inspected; preference/onboarding/import implementation absent; realistic new-user interactive validation pending |
| Catalogue/search | Existing source dedup/adult/timeouts reviewed; representative anime seasons/films/OVA, Western animation, TMDB shows, duplicates, stalled/canceled/unsized seasons and provider failure need production-quality samples |
| Feed/social | Existing comments-off configuration and moderation controls reviewed; real operator alert pipeline, stale-report repair, abuse/brigading and incident response pending before enabling comments |
| Media/links | Player source and provider rules reviewed; N01 repair, captions and real playback not verified. Universal/share/widget links have no delivered implementation proof |
| Notifications/activity | Scheduling/routing source reviewed; finite horizon known; physical OS delivery, permissions, timezone/DST, account races and activity lifecycle pending |
| Privacy/rights | Draft pages, bundle manifests, AI/logging/media/retention boundaries reviewed; final provider inventory, aggregate archive report, store labels, retention policy and approved credits/rights pending |
| Accessibility | Source/render observations; VoiceOver reading/focus, keyboard/assistive controls, contrast, large text beyond current cap, captions and reduced-motion workflows still require direct testing |
| Device/performance | iPhone 18 Pro/iOS 27 fixture rendering; minimum iOS 18, smallest supported phone, memory/thermal/battery/network cost, interrupted launch and real long-library behavior pending |
| Operations | Current health recovered; source tests green. External uptime, DB/tunnel/freshness checks, secrets/rotation, cost limits, overlapping/catch-up jobs, safe rollout/rollback and restore drills need proof |
| App Store Connect | Exact candidate processing, tester install, app metadata/assets/rating/agreements/region/privacy/review access not inspected; repository build number is not store-state evidence |

No claim is made that source review can guarantee nothing was missed. The ledger deliberately keeps inaccessible native/provider/store/operational boundaries visible rather than marking them complete.

## Revised release sequence

1. Close **R1–R6, N01/N02/N08**: production identity/migration, erasure/local ownership, final privacy commitments, compliant media and enabled-query consent. Keep comments off until R8 is satisfied.
2. Close **N03–N07/N09/N11** with durable account-safe commands, canonical write responses, consistent API validation and lifecycle tests. Reuse the atomic backend capability verified here.
3. Implement **F1–F5** together: content-mode preference/classification, resumable onboarding, country/providers, honest TV Time file import and durable history/restore. Their data contracts should precede screen-by-screen feature work.
4. Finish **F6/F7/R7/R8/R10/N10**: notification/catalogue quality, availability/recovery, moderation operation if enabled, dependency patching and correct credits/rights. Add reproducible native/server CI and restore evidence.
5. Produce one actual Release archive, review its privacy/signing/configuration, install the exact candidate through TestFlight, and finish the physical/device/accessibility/reviewer/store ledger. Store screenshots and promises must describe the delivered version.

Release acceptance must additionally include: interruption-safe retries; fresh monitoring after repeated sign-in; canonical single-progress responses; invalid requests yielding 400; compound mark/Undo consistency; no obsolete-account ambient tasks; compliant trailers with captions/referrer; AI consent or disabled correction; redacted logs; complete TMDB attribution. These augment the checklist in the main audit.
