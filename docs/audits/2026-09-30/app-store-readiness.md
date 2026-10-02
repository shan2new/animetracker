# Previously App Store readiness audit

**Second pass added:** read the [second-pass findings and coverage ledger](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/second-pass-audit.md) alongside this backlog. It adds 12 specific findings, a successful Release simulator build, broader real-DB verification and corrections to public availability/TMDB attribution. The feature and original release gates below remain open unless explicitly supported by new evidence.

Previously has a substantial tracking product already: anime and TV franchises, five library statuses, episode progress with undo and replay, Home, Schedule, a news feed, recommendations, trailers, streaming availability, social controls, account export, and an in-app deletion entry point. It is **not ready for a public App Store release yet**. The immediate gates are production authentication, reliable account erasure and account-local storage, final legal disclosures, public API availability, and verification of the submitted build. The requested content mode and onboarding are the next shared product foundations.

Audited on 30 September 2026 against commit `572cb857d73222f5a1b16a4025a24fe1566387c8` on `spike/today-feed`. App configuration is version 1.0, build 5, iPhone, iOS 18 or later. This report is an audit and proposed backlog; no production credentials, user data, feature flags, deployment, or App Store settings were changed.

## Evidence and verification boundaries

| Area | Evidence obtained | Boundary |
| --- | --- | --- |
| Source | SwiftUI app, authentication, persistence, export/deletion, notifications, Fastify routes/services/schema, deployment configuration | Findings refer to the checked-out source; deployed source parity was not independently established |
| Native build | Debug simulator build succeeded with normal simulator signing; separate fixture configuration also built. Second pass: normal signed Release simulator build succeeded | No new distribution archive, physical-device execution, or App Store validation was performed |
| Native rendering | Current-run iPhone 18 Pro, iOS 27 captures listed below; sign-in used the normal configured key, other captures used loopback synthetic fixtures | No real account was created or modified; fixture dates/counts are invented and artwork is intentionally absent |
| Native interaction | App launched through existing DEBUG capture routes | Device Hub UI automation repeatedly returned a timeout, so tapping, keyboard, OAuth, VoiceOver, and destructive flows are not claimed as tested |
| Server checks | TypeScript typecheck passed; 61 test files and 972 tests passed in 5.33 seconds | Isolated mocked tests, with an invalid dedicated test DB URL; this does not prove real database transactions, restoration, or provider behavior |
| Real database probes | All repository migrations applied to newly owned isolated PostgreSQL databases. First pass: deletion/recreation and moderation `Date` binding. Second pass: validation/count/overflow/bulk rollback, selected ownership/export controls and deletion/preservation across 17 seeded tables | Synthetic development identities, no Clerk/upstream calls. The hold was cleared through its test hook to model restart. Not exhaustive erasure/retention or concurrency coverage. Owned test DBs were removed after clients exited |
| Swift persistence probe | Compiled the actual `RewatchStore.swift` with presentation-only copy stubs; reset wrote an empty primary, retained two old sessions in backup, and backup recovery reloaded both | Synthetic temporary directory only; missing primary was explicitly induced. Cross-account UI and detached-write races were not exercised |
| Dependency inventory | Read-only `npm audit --omit=dev`: 10 entries, four high and six moderate; installed/locked versions and selected maintainer advisories inspected | Advisory counts are not proof of exploitability; affected-path review and controlled updates remain pending. No dependency changes applied |
| Public service | First pass: native-style health 200 then 530; generic user agent 403; local health 200 and anonymous library 401. Second pass at 07:30 UTC: public and local health both 200 | Availability changed during the audit; diagnostic requests are not a real authenticated iPhone session or sustained external uptime proof |
| Local deployment | AniTrack launchd service and local port 8787 running; tunnel logs show QUIC connection and DNS failures | The local service being up does not establish public availability |
| Legal pages | Live privacy page read in browser, with terms/deletion/support also checked earlier | Pages were available earlier; fresh browser navigation later failed during network problems |
| Clerk | Current official documentation/changelog researched; local package lock resolves Clerk iOS 1.5.7 | Dashboard, production provider credentials, DNS verification, limits, and production identities were not inspected |
| App Store Connect | Repository release configuration and documentation inspected | Submitted build status, tester access, current metadata, age rating, privacy answers, agreements, and review credentials remain unverified |

Xcode 27's simulator host is **Device Hub**, installed at `/Applications/Xcode.app/Contents/Applications/DeviceHub.app`. An earlier statement that Simulator was absent was incorrect. The simulator booted and the app ran. The first unsigned audit build hit Clerk's keychain entitlement error; a normally signed simulator build resolved it. That diagnostic failure is not presented as an app release defect. [Apple Device Hub documentation](https://developer.apple.com/documentation/xcode/device-hub).

Build and test logs, screenshots, and the loopback-only fixture server are in [the evidence directory](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/evidence). The harness does not connect to a database or upstream service and refuses account deletion. Historical screenshots were not used as current proof.

At completion the fixture server was stopped and the normally configured signed Debug build was reinstalled; its [signed-out screen](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/evidence/12-restored-normal-config.png) was captured. The restored bundle points to the public API and configured development Clerk key, rather than the loopback harness. Product/server source and production account data were not changed.

## Native flow walkthrough

These are independent entry-state captures reached through debug routes, not a claim that the complete journey was driven interactively. “Healthy” below means the visible state is coherent at this size.

| Step | Screen and evidence | General health and pending work |
| --- | --- | --- |
| 1 | [Signed-out entry](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/evidence/01-sign-in.png) | Clear identity and one sign-in action. No introduction to TV/anime scope, import, or personalization. The provider sheet itself was not exercised |
| 2 | [Home with an empty library](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/evidence/02-home-empty.png) | Good single “Add a show” recovery. First value depends on manual setup; no onboarding or import entry. Large empty area is a product activation issue, not a broken render |
| 3 | [Empty Schedule](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/evidence/03-schedule-empty.png) | Clear explanation and recovery. Repeats the setup burden across a second tab; filter is local to Schedule |
| 4 | [Empty Following feed with synthetic trending](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/evidence/04-feed-empty.png) | Clear CTA and an alternative discovery route. “Nothing to watch yet” describes the library better than a news feed; mode-specific feed relevance remains pending |
| 5 | [Empty Library](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/evidence/05-library-empty.png) | Healthy empty state. Needs import, and later a distinction between truly empty and “no titles in this mode” |
| 6 | [Discover with synthetic titles](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/evidence/06-discover.png) | Search, trending, genres, and add affordances exist. Search copy explicitly combines anime and TV; filter is not an account preference. Placeholder rendering is legible; real artwork/loading was not validated |
| 7 | [Profile](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/evidence/07-profile.png) | Saved/muted content, notification status, haptics, export, and legal links are discoverable. Content mode, market/providers, import, and account security controls are missing. DEBUG-only developer/demo rows are expected in this fixture build |
| 8 | [Home with a populated synthetic library](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/evidence/08-home-populated.png) | New episode and next action render coherently. Needs cross-mode consistency. Missing fixture artwork intentionally leaves a large neutral hero; this is not evidence of production art failure |
| 9 | [Show detail](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/evidence/09-detail.png) | Status, release information, progress and Posts/Episodes/Media/About exist. Real season grouping, provider links, source quality, trailers, and action behavior remain release checks |
| 10 | [Episodes tab](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/evidence/11-episodes.png) | Episode rows and watched state render. Counting progress is not a model for arbitrary watched episodes or multiple dated watches; importer work must address this |

![Current first-run Home capture using an empty local fixture](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/evidence/02-home-empty.png)

![Current Profile capture using a local developer session](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/evidence/07-profile.png)

Accessibility cannot be certified from these captures. The app already contains accessibility labels and Reduce Motion branches, but globally caps Dynamic Type at `accessibility2` in [AniTrackApp.swift](/Users/shan2new/Projects/animetracker/ios/Sources/App/AniTrackApp.swift:73). Verify the largest system sizes through reflow, VoiceOver focus/order and announcements, contrast over real artwork, keyboard avoidance, and touch targets on a small iPhone. Icon-only bottom navigation also needs a tested accessible label/selected state and a clear first-use explanation.

## Priorities

**P0:** Gate submission/public availability. **P1:** Complete before the intended public product launch, or explicitly remove the corresponding promise. **P2:** Useful later; does not inherently prevent submission. A conditional gate applies only if that feature is enabled or advertised. An unverified gate means evidence is pending, not that the feature is certainly broken.

## Release gates

### R1 Production Clerk and provider configuration

**P0 — confirmed configuration gap.** The shared build settings in [project.yml](/Users/shan2new/Projects/animetracker/ios/project.yml:132) use a `pk_test_` key for Release as well as Debug. This is a publishable development key, not a leaked server secret. Production backend configuration has a JWT verification key but no `CLERK_SECRET_KEY`. No Apple sign-in entitlement or native callback configuration was found in the project source. The current `AuthView` delegates provider availability to Clerk; seeing its wrapper in code does not prove Google/Apple are configured.

Required work:

1. Separate Debug, staging, and Release configuration, with build-time checks that Release uses the intended production API and `pk_live_` instance.
2. Configure production Clerk domain/DNS, native application registration/Native API, allowed callback schemes, Google production OAuth credentials/consent, and native Apple configuration/capability for the real bundle identifier.
3. Supply the matching server secret and verification configuration through deployment secrets. Verify issuer/instance restrictions and any audience/authorized-party policy appropriate to native tokens; test that development or unrelated-instance tokens are rejected.
4. Test Apple real email and private relay, Google, a fallback such as email OTP, cancellation, returning sessions, expiry, offline recovery, account linking, and provider revocation on a signed physical build.
5. Preserve the existing production dev-bypass rejection and the Debug-plus-localhost UI gate.

Acceptance: clean install and returning launch work with the intended production providers; all backend writes use the same app account; release configuration fails early when miswired; no provider cancellation strands the app.

Clerk requires production configuration and custom provider credentials; its development environment is unsuitable for public use. Apple guideline 4.8 makes an equivalent privacy-preserving login relevant when Google is used; native Sign in with Apple is the appropriate planned option here. [Clerk environments](https://clerk.com/docs/guides/development/managing-environments), [native social setup](https://clerk.com/docs/ios/guides/configure/auth-strategies/social-connections/overview), [Clerk Apple entry point](https://clerk.com/docs/guides/configure/auth-strategies/sign-in-with-apple), [Apple review guidelines](https://developer.apple.com/app-store/review/guidelines/).

### R2 Preserve existing app accounts during the production cutover

**P0 — required migration design.** App records are tied to Clerk IDs through the internal `users` UUID. Changing instances creates a new identity context and can make an existing library appear lost.

Clerk explicitly says development users cannot be migrated into its production instance. Plan a **new production sign-in plus verified reassociation of existing app data**, preserving internal UUIDs and relationships. Do not infer ownership from a submitted or unverified email, and do not assume Apple relay and Google email identify the same account. [Clerk migration limitations](https://clerk.com/docs/guides/development/migrating/overview).

Acceptance: backed-up, dry-run mapping; authenticated proof of old/new ownership; test library, progress, social references and bans; duplicate-account/conflict handling; documented rollback. Resetting beta data is a separate product decision requiring explicit user agreement, not a default cutover strategy.

### R3 Complete account erasure durably

**P0 — confirmed implementation and deployment gap.** [DELETE /me](/Users/shan2new/Projects/animetracker/server/src/routes/me.ts:257) correctly deletes application-owned records in a transaction. It then returns `{deleted:true}` even when Clerk deletion was skipped or failed. [erasure.ts](/Users/shan2new/Projects/animetracker/server/src/services/erasure.ts:92) skips the provider call without the secret; that secret is absent from the server environment loaded by the current launchd service. The anti-recreation hold is process memory for 15 minutes, so restart loses it. A surviving Clerk identity can later obtain a new token and be upserted again.

The [real-DB probe results](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/evidence/real-db-probe-results.json) reproduce the application side: deletion returned 200/`deleted:true` with provider deletion skipped; seeded user/preferences/progress rows were gone; the same synthetic identity was initially refused with 401, then recreated under a new internal UUID after the memory hold was cleared. This does not claim a real Clerk identity was deleted or a real session survived a provider deletion.

Required work: durable erasure job/outbox and identity tombstone; idempotent retries and provider completion state; monitoring of unfinished erasure; protection against late writes after restart; signed, deduplicated Clerk deletion-event reconciliation for deletion initiated outside the app. Preserve the existing transaction and write-drain behavior.

Suspended accounts currently call Clerk `banUser` instead of `deleteUser`. That retains a provider identity, not just a minimal moderation marker. Define the exact lawful retention basis and minimum fields, or change this behavior; the UI/policy must not promise complete erasure while retaining a whole identity without justification. Verify Apple authorization-token revocation is handled by Clerk or implement the required provider lifecycle. Do not assume deleting a Clerk user proves Apple revocation. [Apple account deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app/), [Apple token revocation guidance](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple).

Acceptance: deletion removes live application data and completes provider cleanup; provider timeout, restart, duplicate deletion, suspended account, upstream deletion, and stale JWT cannot resurrect the account. Retained exceptions and backups match published policy.

### R4 Make deletion failures truthful and reconcilable

**P0 — confirmed copy/state defect.** [AccountDeletion.swift](/Users/shan2new/Projects/animetracker/ios/Sources/Features/Profile/AccountDeletion.swift:27) says “Your account wasn't deleted” after a transport failure and “Nothing was changed” for refusal. A response can be lost after the server commits. That certainty is unsafe; `abortErasure()` can resume old writes when deletion actually happened.

Required work: an idempotent request identifier and a reconciliation/status protocol that survives an ended session; represent pending/unknown separately from rejected/not-started/completed. Hold replay while the outcome is unknown and tell the user what is actually known. Design ownership checks so a status endpoint leaks no account information.

Acceptance: drop the response after commit, kill the app, reopen, and recover the correct state without recreating records or falsely saying nothing changed.

### R5 Isolate and erase device-local account data

**P0 — confirmed persistence defects.** The main teardown already clears SyncCenter, feed/social state, notifications, and Live Activities; those should not be reported as missing. Remaining gaps:

| Finding | Evidence | Required correction |
| --- | --- | --- |
| A cleared rewatch store preserves the previous generation in a backup | [RewatchStore reset and persist](/Users/shan2new/Projects/animetracker/ios/Sources/App/RewatchStore.swift:132) writes empty sessions after copying the old file into `sessions.backup.json`; load falls back to that backup | Account-owned storage, serialized/cancellable writes, and an erasure operation that removes both generations |
| A late library write can recreate a removed cache | [AppModel persistence](/Users/shan2new/Projects/animetracker/ios/Sources/App/AppModel.swift:400) uses an untracked detached writer; teardown removes a single unscoped file | Scope cache to owner, include owner in payload, serialize writes, and reject obsolete account epochs |
| Recent titles/searches survive teardown | [Recent keys](/Users/shan2new/Projects/animetracker/ios/Sources/App/AppModel.swift:25), [teardown](/Users/shan2new/Projects/animetracker/ios/Sources/App/AppModel.swift:551) | Clear in-memory and persisted recents on account change/erasure, or store safely per owner |
| Temporary exports have no explicit lifecycle cleanup | [LibraryExport](/Users/shan2new/Projects/animetracker/ios/Sources/Features/Profile/LibraryExport.swift:114) creates `export-UUID` directories | Remove app-owned temporary export files after transfer/expiry and on erasure; do not claim deletion of copies the user saved elsewhere |

The [actual-source Swift probe](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/evidence/rewatch-probe.log) confirmed reset leaves two old synthetic sessions in the backup and reloads them after an induced missing-primary recovery. This strengthens the backup-removal finding; it does not prove the separately identified detached-write race occurred during this audit.

Acceptance: account A → sign out → account B, with delayed writes and offline relaunch; B never sees A's titles/history. Full erasure leaves no app-owned account files, backup generations or queued writes. Inspect image/network caches and device backup inclusion as part of that check.

### R6 Publish final truthful legal and privacy information

**P0 — confirmed publication gap.** The live [privacy policy](https://landing-ten-theta-55.vercel.app/privacy), [terms](https://landing-ten-theta-55.vercel.app/terms) and [account deletion page](https://landing-ten-theta-55.vercel.app/delete-account) still label themselves “Working draft · not yet effective.” Contact/support exists, but a reachable draft is not a finished store policy.

Finalize operator/contact, effective date, launch regions/audience, retention of logs/backups/support/moderation exceptions, erasure completion, public replies/handles/ratings/social activity, authentication processors, image/video hosts, hosting and AI search processing. Reconcile stale statements: current JSON export is broader than a library-only export, and Clerk erasure code exists but is not reliably deployed/completed. Do not replace unknown retention with invented deadlines.

An app privacy manifest exists, including required-reason UserDefaults and collected-data declarations. Generate the final archive's combined SDK privacy report, reconcile it to actual behavior and App Store Connect privacy answers, and check current third-party SDK requirements. ATT is not automatically required merely because the app uses authentication; determine tracking from actual SDK behavior. [Apple privacy guidance](https://developer.apple.com/app-store/app-privacy-details/), [SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/).

A permanent branded domain is desirable and already contemplated in source, but a stable valid Vercel URL is not itself an Apple prohibition. Finality, accessibility and accuracy are the actual gates.

### R7 Public availability and recovery

**P0 — reliability proof pending after an observed interruption.** During the first pass's later check, the native-style request returned Cloudflare 530 while the local API remained healthy. Tunnel logs at approximately 04:36 UTC showed `no route to host` for edge QUIC connections and DNS lookup timeouts. The generic user agent's 403 is a separate ingress behavior, not proof of invalid credentials.

The [first pass's final check](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/evidence/final-health-check.json), at 04:58 UTC, returned 530/Cloudflare 1033 publicly and 200 locally. The [second pass recheck](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/round-2-evidence/health-recheck.json), at 07:30 UTC / 13:00 IST, returned **200 for both**. The public route recovered without an audit deployment change. These are point-in-time checks from the Mac's network, not continuous or external-network availability proof.

Required work: verify sustained public access and recovery; investigate tunnel network/DNS behavior and WAF/native access; monitoring from outside the Mac; alerts for tunnel/public API/DB/freshness failures; documented restart and rollback; reliable hosting and power/network recovery. Do not weaken protection based only on a user-agent probe. The app already classifies infrastructure 403 separately from session-ending 401; preserve that.

Acceptance: signed app works on Wi-Fi and cellular, from launch markets and reviewer-like networks; backend and Clerk are reachable throughout review; an outage recovers without losing progress or logging everyone out. `/health` currently reports process health only, so add dependency/freshness diagnostics without exposing sensitive information.

### R8 Operate moderation before enabling public comments

**Conditional P0 — substantial controls exist, operations are incomplete.** Reporting, blocking, filtering, rate limits, auto-hiding, community terms/profile gating, suspension and moderation CLI are implemented. Comments are currently default-off in production. Keep them off until the full operational path is verified.

Two concrete gaps: `MODERATION_ALERT_WEBHOOK_URL` is absent, and current server stderr repeatedly records `stale report alert failed ... Received an instance of Date`. [staleOpenReports](/Users/shan2new/Projects/animetracker/server/src/services/moderation.ts:388) interpolates a raw `Date` into SQL; the postgres-js path needs a correctly encoded timestamp. The mock tests passing does not exercise that real parameter binding.

The same error was [reproduced against the migrated isolated PostgreSQL database](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/evidence/real-db-probe-results.json), even with no reports. The repair needs a real-DB regression check, including stale and resolved reports; another mocked query assertion would miss this boundary.

Required work: repair and exercise the query against a dedicated real test database; route alerts to an authorized operator channel; prove first-report/auto-hide/stale-report visibility, response and closure; handle moderation dependency failures safely; test spam, evasion, brigading, blocked-user interactions, suspended deletion/export and terms upgrades. The ban loader can fail open when it has never loaded; public comment posting needs a deliberate safe failure policy.

Apple requires filtering, reporting with timely response, blocking and contact information. A 24-hour response target can be our operational SLA; it should not be presented as a verbatim universal deadline in guideline 1.2. [Apple UGC rules](https://developer.apple.com/app-store/review/guidelines/).

### R9 Submitted build and store configuration

**P0 — evidence pending.** Assemble and verify the actual Release archive after the preceding gates. Repository build number 5 or a historical upload message does not prove current App Store Connect processing, distribution or review eligibility.

Checklist: final name/bundle identity, icons on supported OS versions, launch screens, screenshots for required device sizes, description/subtitle/keywords/category, accurate feature promises, current age-rating questionnaire, content rights/attribution, privacy/support/marketing URLs, export compliance, developer agreements and any tax/banking requirements if paid, review contact, production reviewer login/access instructions, release method, signing/provisioning, and final archive SDK/privacy validation. No iPad-specific release is implied by the current iPhone-only target.

TMDB's notice text already exists in Profile, but the second pass found its required approved logo asset is not rendered in native source; complete the attribution rather than duplicating the notice. The trailer crop/referrer also needs repair against YouTube requirements (N01). Check catalogue/artwork/trailer and commercial-use rights before monetization. Adult filters already exist for catalogue discovery; also inspect mature artwork/trailers and complete ratings based on actual content.

Acceptance: install the exact candidate via TestFlight on a physical iPhone; independently verify every declared feature and account deletion; provide a functioning reviewer path without requiring access to the operator's personal account. [Apple completeness/review requirements](https://developer.apple.com/app-store/review/guidelines/).

### R10 Review and patch the production dependency graph

**P1 — release hardening with a concrete inventory.** [Read-only npm audit output](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/evidence/npm-audit.json) reports ten production dependency entries: four high and six moderate. High entries are Drizzle ORM, fast-uri, find-my-way and ip-address. These are dependency entries, not ten independently proven app vulnerabilities.

| Dependency/path | Current evidence | Action |
| --- | --- | --- |
| Drizzle ORM 0.38.4 | Identifier-escaping advisory; the reviewed code uses static schema identifiers and static `excluded` column names, with no request-derived `sql.identifier()` found | Move to a patched compatible release with migration/query checks; no SQL-injection exploit is established by this audit. [Maintainer advisory](https://github.com/drizzle-team/drizzle-orm/security/advisories/GHSA-gpj5-g38j-94v9) |
| Fastify 5.8.5 / find-my-way 9.6.0 / fast-uri 3.1.2 | Router advisory requires Node HTTP/2; current `buildServer()` creates the normal HTTP/1 server. Fastify's root-primitive coercion advisory is not the reviewed Zod-in-handler object validation path. fast-uri has several normalization advisories requiring separate call-path review | Update the compatible Fastify graph and verify API schemas/proxy behavior; do not equate the tunnel's edge protocol with Node HTTP/2. [Router advisory](https://github.com/delvedor/find-my-way/security/advisories/GHSA-c96f-x56v-gq3h), [Fastify advisory](https://github.com/fastify/fastify/security/advisories/GHSA-w2qp-rph6-63g4) |
| Agent SDK → MCP/Express/Hono dependency subtree | ip-address, Hono, Hono's Node adapter and qs appear through the announcement-agent dependency tree, rather than the app's main Fastify request server | Assess actual agent transports and URL/proxy/body handling; update the upstream subtree. Windows-only Hono static-serving impact is not automatically applicable to this Mac deployment |
| node-cron 3.0.3 → uuid 8.3.2 | Transitive moderate advisory; a proposed major cron upgrade changes runtime APIs | Upgrade deliberately and verify scheduling/catch-up; do not run a blanket forced audit fix |

The [version inventory](/Users/shan2new/Projects/animetracker/docs/audits/2026-09-30/evidence/dependency-versions.json) also shows Clerk backend 1.34.0, while the registry currently reports 3.21.0. That version gap is distinct from the currently resolved iOS 1.5.7. Review Clerk's applicable upgrade guides and test JWT verification, deletion/ban calls and webhooks before a backend major upgrade; a newer version alone is not evidence of an exploitable auth defect. [Clerk Core 3 upgrade guide](https://clerk.com/docs/guides/development/upgrading/upgrade-guides/core-3).

Acceptance: documented affected-path disposition; patched or explicitly justified remaining entries; clean lockfile/reproducible deployment; typecheck, relevant route/real-DB checks and scheduled-job checks pass. No dependencies were changed during this audit.

## Product features needed for the intended launch

### F1 A persisted TV Anime Both mode

**P1 — absent as an account setting.** [AppModel.mediaFilter](/Users/shan2new/Projects/animetracker/ios/Sources/App/AppModel.swift:235) is explicitly a browsing/search filter and resets to All on teardown. Schedule uses an independent local filter. Neither is a cross-app persisted user mode. [user_preferences](/Users/shan2new/Projects/animetracker/server/src/db/schema.ts:222) currently stores country, language and provider IDs, with no content mode or onboarding state.

Add `contentMode = anime | tv | both` to server preferences, API models and account-owned local state. Keep transient screen filters as narrower choices within that mode. For migration, default existing users to Both; ask new users during onboarding. Mode describes interest, not deletion of subscriptions.

Recommended behavior: primary content and counts follow the selected mode; preserve the whole library underneath; show “N other titles hidden by your mode” and a deliberate Show all escape in Library. An explicit deep link to an out-of-mode title still opens it and explains the context. Export/deletion always cover the whole account. TV means the current TMDB television catalogue; general live-action movies are not currently a supported catalogue, while anime film/OVA parts belong to Anime.

| Surface | Required effect |
| --- | --- |
| Home | Stage, up-next, backlog, release counts, completion/empty states and recommendations derive from the scoped library |
| Schedule | Episodes, day counts, calendar, hide-watched and source chips share the account mode; preserve date-only TV semantics |
| Feed | Following/For you, stories, trending, reminders and recommendation modules use consistent scope; apply before ranking/limits, not by removing results after pagination |
| Library | Status shelves, totals, search/sort, bulk marks and artwork stacks reflect scope; safe access to hidden retained titles |
| Discover | Search parameter, trending, genres, recommendations, copy and unavailable-source messages align; Both needs useful representation of both catalogues |
| Detail and related titles | Explicit out-of-mode opening works; related/recommendation scope is clear; no progress is lost when switching |
| Profile/onboarding | Persisted preference, explanatory copy, optional setup restart and pending-save/offline state |
| Notifications and Live Activities | Disclosed policy for out-of-mode followed shows; recommended default is align alerts with mode, with an explicit option to keep all followed-show reminders |
| Backend/cache | Preference contract/schema, query scope, ranker inputs, cache keys, expiry and response generations; invalidate old-mode requests and disk snapshots |
| Export/import | Whole-account export; preview hidden imported titles and preserve them regardless of mode |

The backend already accepts source-scoped search/trending and genres in parts of the API. [APIClient.search](/Users/shan2new/Projects/animetracker/ios/Sources/Networking/APIClient.swift:326) does not send source today. Extend existing boundaries rather than adding unrelated parallel catalogues. Store product preferences in the app database; Clerk should remain responsible for identity/security.

Reuse the existing [Japanese-animation boundary](/Users/shan2new/Projects/animetracker/server/src/tmdb/mapping.ts:134), which suppresses TMDB anime twins in favor of AniList and also guards full-show materialization. Content mode must not be derived from media format `TV` alone: an anime series is still Anime, and Western animation can still belong to the general TV catalogue. Verify the existing boundary for imported and deep-linked titles as well as search.

Acceptance: switch Anime → TV → Both in every tab, reload/relaunch and sign in on another device; content, counts, search and alerts remain consistent, while hidden titles/progress remain recoverable. A mode-filtered empty state must not imply an empty account.

### F2 Resumable onboarding that reaches useful content

**P1 — absent.** Root moves directly from authentication into the main app. The current empty states are good recovery affordances, but three largely empty tabs do not customize the product.

Recommended short flow:

1. Choose Anime, TV or Both, with examples of what each covers.
2. Confirm viewing country and optional streaming providers; allow skip. Device locale is a suggestion, not the user's definitive market.
3. Choose import an existing file or select a few shows. Offer search immediately and curated suggestions appropriate to mode.
4. Ask current season/episode or “not started / caught up / finished” for active shows, so a new subscription does not accidentally create hundreds of episodes of backlog.
5. Explain episode alerts when there is an actual followed show/reminder; request notification permission contextually and support denial without a dead end.
6. Land on a populated Home with one clear next action; offer a small explanation of navigation and where progress is recorded.

Persist a versioned completion/checkpoint record; make onboarding skippable, resumable and restartable from Settings. Returning users should not repeat it after upgrades. Keep the existing progressive public handle/terms setup for the first reply; a tracker should not require a community identity to track privately.

Acceptance: first meaningful title/progress appears without exploring multiple tabs; interruption, denied notifications, import failure and skipped setup all leave a usable app. Measure activation with privacy-minimized events only if analytics is intentionally introduced and disclosed.

### F3 Country and streaming-provider settings

**P1 — backend exists, native controls are missing.** `/me/preferences` and provider prioritization exist; the native client does not expose that account preference contract. [AppRegion.current](/Users/shan2new/Projects/animetracker/ios/Sources/Models/Models+Enrichment.swift:760) uses device region, with US fallback. That can show availability/rating information for the wrong market.

Add Settings/onboarding market and providers; fetch/save/retry preferences; prefer the chosen market over locale for catalogue availability and age labels; account-scope/invalidate country caches. Explain “no availability found” versus a failed lookup. A `language` database field does not establish translated UI, so localize only when ready and do not imply existing localization.

Acceptance: changing country affects availability and ratings consistently; unavailable providers and regions have truthful fallbacks; settings synchronize across devices.

### F4 TV Time import from saved exports

**P1 for the requested migration experience — feasible file import, not a verified working importer.** TV Time shut down on 15 July 2026. Its current official site is a farewell page. Plan around **previously downloaded GDPR ZIP/CSV files**, with extracted-file support where practical; do not promise an active TV Time account connection or export endpoint. [Official TV Time site](https://www.tvtime.com/), [shutdown report](https://www.macrumors.com/2026/07/02/show-tracking-app-tv-time-shutting-down/).

Existing open-source parsers demonstrate saved export formats with TheTVDB identifiers for shows/episodes and title/year for movies, plus watch/check-in data. Use their schemas as implementation research and review any reused code/licenses; their instructions for requesting a fresh export predate shutdown. [TV Time Time Machine](https://github.com/SteadfastKnight/tvtime-time-machine), [TV Time to SIMKL converter](https://github.com/CaptainRatax/tvtime-to-SIMKL-import-file-convertor).

The major blocker is our data model. [progress](/Users/shan2new/Projects/animetracker/server/src/db/schema.ts:182) stores one episode count per user/media, not an arbitrary watched set with original watch dates. Watching episodes 1 and 3 cannot safely become count 2; that would incorrectly mark episode 2 and omit 3. Local `WatchSession` entries represent whole/part rewatch sessions, not individual imported episode events.

Required importer stages:

| Stage | Requirement |
| --- | --- |
| Read | Allowlisted tracking files only; limits on archive expansion/entries/size, safe paths and encoding, explicit supported encryption or extracted CSV fallback; exclude account/login/IP/token files |
| Normalize | Preserve original source IDs, episode identity, original dates, status and rewatch evidence; version the normalized format |
| Match | TheTVDB → compatible TV/season identity via verified external IDs; anime mapping into AniList franchise/season/OVA/cour structure; title/year only as a review candidate |
| Review | Matched, ambiguous, unmatched and unsupported counts; manual mapping; clear explanation of movies/specials and data that cannot be represented |
| Merge | Preserve existing records, define conflict handling, never reduce progress silently, retain sparse watches and repeats accurately |
| Apply | Durable resumable job, idempotent import hash, per-record receipts, bounded catalogue lookups, safe rollback of only that job's writes |
| Finish | Summary and downloadable exception report; remove staged private files on a stated schedule; available from onboarding and Profile later |

Choose one honest first version: extend server watch-event storage for fidelity, or explicitly support limited contiguous progress and disclose omitted dates/gaps/rewatches before applying. Do not advertise “full watch-history import” for a lossy count converter. General TV Time movies are unsupported by the current TV-only TMDB path; anime franchise movies may map, but all unmatched/unsupported items need explicit reporting.

Acceptance: a real representative export, plus encrypted/extracted variants, split anime seasons/cours, specials, duplicate entries, sparse episodes, rewatches, malformed archive and existing-library conflicts. Measure match precision and review all ambiguous matches. No user's export was supplied in this audit, so accuracy is unmeasured. A “recover TV Time data without an existing export” promise needs separate evidence and is not justified now.

### F5 Durable watch history and a restore format

**P1 for durable tracking; prerequisite for faithful import.** Rewatch history is device-local and is reset even on ordinary sign-out. Reinstall loses it. Server JSON export already includes extensive server-held account/social data; CSV is library-only, and local rewatch sessions are outside the server export.

Move watch sessions/events to account-owned server storage, or explicitly label local-only history and provide an export/restore path. Prefer one event model supporting actual episode watches, optional unknown dates, repeats, corrections and import provenance; derive “current progress” rather than inventing dates from `updatedAt`. Version our export schema and implement validated restore separately from third-party import. “Export library” should clearly distinguish CSV library data from the broader JSON account copy.

Acceptance: sign-out/in, reinstall and second device retain promised history; a round-trip export/restore preserves supported data without duplicates or fabricated timestamps.

### F6 Reliable notifications and precision

**P1 if timely ongoing alerts are a launch promise.** Local scheduling exists, with 48 pending alerts and three episode slots per show. Exact anime episode alerts, TV date-only premiere reminders at 9 AM local, and feed reminders already exist. Live Activities are currently exact-time anime oriented. It would be incorrect to say TV has no notifications at all.

The finite local schedule refreshes when the app loads/synchronizes. There is no demonstrated APNs token/backend delivery path or background-refresh guarantee, so a user who stops opening the app can miss later or changed releases. Add server push/update handling if this is a core promise, or state the finite local behavior accurately. Provide useful per-type preferences, denied-permission recovery and mode-aware behavior. Never turn a synthesized TV date into a supposedly exact broadcast countdown.

Acceptance: app closed for longer than the lookahead, premiere changed/cancelled, permission denied/changed, timezone/DST crossing, bulk episode drop, app reinstall, notification tap and duplicate scheduling. Test delivery and Live Activity lifecycle on a physical device; simulator rendering alone is insufficient.

### F7 Consistent catalogue and news quality

**P1 — release verification and operational hardening.** Both catalogue sources, relation-based franchise assembly, partial-source search notices, spell-correction escape, release precision and recommendation ranking exist. The pending work is proof on representative titles and durable freshness.

Test long-running anime, split cours, films/OVAs/spin-offs, finished vs returning TV, zero/unknown counts, batch drops, undated premieres, missing artwork/provider metadata and duplicate Japanese-anime results. Verify source-specific failures are distinguished from no matches. Ensure generated/news-derived claims show source, date, confidence and rumor status; never promote an inferred date into a firm schedule. Allow a catalogue error report/contact path, since provider metadata errors are inevitable.

Acceptance: representative catalogue checklist and freshness alerts; no false exact TV time; no stale rumor presented as confirmed release; recommendations continue gracefully when one source fails.

## Engineering and operational backlog

| Item | Priority | Current finding | Definition of done |
| --- | --- | --- | --- |
| E1 Reproducible builds and CI | P1 | Server checks exist and pass. No repository CI or native XCTest target found. Package declaration is `from: 1.2.4`, while ignored generated `Package.resolved` currently selects 1.5.7 | Track/pin the intended package resolution through the XcodeGen workflow; CI server checks and native build; explicit Release configuration validation; retain useful DEBUG regression hooks |
| E2 Real database integration | P1, P0 for erasure/moderation fixes | Existing mock suites miss live SQL binding and transactional/constraint behavior; isolated audit probes now reproduce concrete failures | Maintain a guarded real-DB regression suite; test deletion/retention/import/conflicts; verify migration rollback and backups without touching production |
| E3 Backup and restore | P1, required before account cutover | No verified off-host backup/restore procedure found | Encrypted backups, retention schedule, tested restore into a disposable DB, documented recovery objective and deletion treatment of backups |
| E4 Durable sync jobs | P1 | In-process cron, isolated errors and sync bookkeeping exist; durable catch-up and overlap protection not established | Detect missed jobs after downtime, lock/serialize expensive work, record success/failure/freshness, retry safely; prove recovery after restart |
| E5 Public resource and cost controls | P1 | Social rate limits exist; a broad budget for expensive search/resolve/AI/catalogue paths was not demonstrated | Per-user/IP and concurrency limits, bounded queues, upstream timeout/backoff, provider/LLM spend limits, abuse tests and actionable alerts |
| E6 Offline and multiple devices | P1 | Cache, optimistic writes, replay and undo are implemented | Two-device conflict cases, network loss during mark/undo/add/remove, app kill/reinstall, expired auth, account switch and duplicate replay tested on real storage; explicit conflict rules |
| E7 Accessibility and performance | P1 | Existing accessibility/reduced-motion work, globally capped large text; fresh full accessibility/performance proof absent | Small iPhone + iOS 18/current iOS, largest text, VoiceOver, contrast, Reduce Motion/Transparency; measure cold launch, scrolling, image memory and hitches on device |
| E8 Security/session lifecycle | P1 | Token refresh/infrastructure classification exist; sensitive app actions accept ordinary valid sessions | Fresh-auth enforcement for deletion/account reassociation, server-side ownership checks, signed webhook replay protection, revocation/account-linking checks; review log redaction |
| E9 Operational support | P1 | Public support email exists; fresh moderation alerts and outage visibility incomplete | Tested support path, incident and account-recovery runbooks, authorized operator coverage, meaningful error diagnostics with no token/OTP leakage |
| E10 Documentation and branding | P2, P0 for misleading store copy | Internal AniTrack vs display Previously; older READMEs/readiness notes describe older tabs/deployment/deletion/export | One current release checklist and accurate store/site feature text; distinguish shipped code from pending proof |

Do not add tests that merely restate implementation. Prioritize live storage/SQL, identity transitions, lost responses, importer fidelity and actual device behavior—the boundaries the current tests do not establish.

## Clerk capabilities worth using

The local app already resolves **Clerk iOS 1.5.7**, so the work is configuration, integration and reproducibility, not blindly upgrading from the stale `1.2.4` lower-bound comment. Recent September releases included biometric/reverification and privacy-manifest improvements; check the exact locked release in the candidate archive. [Clerk iOS releases](https://github.com/clerk/clerk-ios/releases).

| Capability | Fit for Previously | Recommendation |
| --- | --- | --- |
| Native Apple + Google OAuth | Essential planned production login | Configure and exercise the existing native auth surface before designing a new custom login. Google OAuth/browser callbacks and native Apple require their appropriate platform setup; do not confuse the Apple web Services ID path with native bundle configuration |
| Biometric sign-in | Helpful returning-user recovery | Clerk's mobile biometric sign-in creates a real session using an installation-scoped credential. Add optional enrollment after ordinary login, Face ID usage text and a fallback. Auth-flow completion must gate dismissal; current session-presence-only dismissal can skip enrollment. P2 after production auth is stable. [Biometric guide](https://clerk.com/docs/ios/guides/development/custom-flows/authentication/biometric-sign-in) |
| Sensitive-action reverification | Strong fit for deletion and identity changes | Recent configurable 1–10 minute windows protect Clerk actions. Our own `DELETE /me` needs its own server-enforced recent-auth rule; a client prompt alone is insufficient. Include biometric reverification where supported. [Clerk reverification update](https://clerk.com/changelog) |
| Native account/security UI | Useful missing Settings surface | Use `UserProfileView` or selected native APIs for linked accounts, email/security and sessions. Preserve app-specific preferences/community profile. Ensure any Clerk-only delete affordance cannot bypass application erasure. [Native views](https://clerk.com/docs/ios/reference/views/overview) |
| Passkeys | Useful alternative credential | Evaluate after provider login and recovery are solid; test platform association/credential recovery and fallback. Separate from installation-bound biometrics. [Native authentication APIs](https://clerk.com/docs/ios/reference/native-mobile/auth) |
| Transactional Email Logs | Good support tool for OTP | June 2026 public beta exposes production delivery diagnostics. Use to investigate delivery/bounce issues; restrict operator access and avoid copying OTPs or private payloads into logs. [Email Logs announcement](https://clerk.com/changelog/2026-06-01-email-logs-public-beta) |
| User lifecycle webhooks | Necessary consistency integration | Verify signed `user.updated`/`user.deleted` events, deduplicate, retry and reconcile identity changes/deletion. App privacy promises need application DB cleanup, not only provider deletion |
| Native attack protection/session tasks | Important configuration checks | Native API is required and changes bot-protection behavior. Test additional steps/pending sessions instead of assuming `session != nil` always means the whole flow finished. Preserve reliable email/provider fallback |
| Enterprise SSO, Organizations, OAuth/MCP features | Low fit now | Recent enterprise and agent authorization features do not improve the core consumer tracker. Do not expand v1 scope simply because Clerk recently shipped them |
| Clerk Billing | Future web billing option, not a native shortcut | App has no implemented premium purchase flow. If paid digital features are introduced, separately evaluate Apple purchase requirements and build/verify the appropriate native purchase/restore/entitlement path |

Store content mode, market, provider selection, onboarding and tracking history in our application data model. Clerk user metadata can assist identity integration, but should not become a second authoritative product-preference store.

## Later features that should not delay a sound v1

P2 candidates: Home Screen widgets, richer stats/diary, custom lists and sharing, more import formats such as AniList/MAL/Trakt/SIMKL, localization, optional guest browsing, passkeys/biometric polish, and native premium features. Choose them from user value and retention evidence. None substitutes for correct identity, privacy, data durability and onboarding. A free release does not need subscriptions or StoreKit merely to be App Store ready.

## Recommended implementation order

1. **Account and service foundation:** R3–R5 erasure/local ownership, R7 availability, real DB checks and R10 dependency review; configure production credentials as a reviewed cutover with R2 ownership preservation. Repair moderation query now; keep public comments disabled pending R8.
2. **Shared product preferences:** F1 content mode and F3 market/providers; implement APIs, scoped derivations/cache keys and all-account escape/export semantics together.
3. **Durable watch data and migration:** F5 model/export versioning, then F4 importer preview/matching/merge. Validate with representative files before claiming supported fidelity.
4. **Activation:** F2 onboarding uses the real preference/import APIs, current-progress setup and contextual alert permission; verify empty and skipped paths.
5. **Launch reliability:** F6 alerts, F7 catalogue/news checks, CI/backup/cost controls, multiple-device/offline and accessibility/device verification. Optional Clerk security/biometric work can follow the stable production login.
6. **Submission:** publish reconciled legal pages, complete R9 store fields, archive the production-configured candidate, install via TestFlight and run the release checklist on the exact build.

## Final candidate acceptance checklist

- [ ] Production Apple, Google and fallback login; returning/offline/expired/cancelled flows; correct app-account ownership.
- [ ] Existing beta library and social/history data preserved or a separately agreed reset communicated.
- [ ] Durable full deletion, truthful unknown outcomes, upstream deletion, suspended account policy, and Apple authorization lifecycle verified.
- [ ] No account A data on account B after delayed writes, sign-out or offline relaunch.
- [ ] Anime/TV/Both persisted and consistent across Home, Schedule, Feed, Library, Discover, deep links and alerts.
- [ ] Resumable/skippable onboarding reaches useful shows/progress; country/providers honored.
- [ ] Import supports its advertised fidelity, with real-file matching proof and explicit unsupported/unmatched report.
- [ ] Rewatch/history durability and versioned export coverage/restore policy are truthful.
- [ ] Public service stays available and recovers from tunnel/host/network failure; dependency/freshness alerts verified.
- [ ] Production dependency advisories patched or documented with verified affected-path reasoning; backend SDK upgrades validated separately from iOS resolution.
- [ ] Comments remain off, or moderation/report/block/terms/operator workflow passes real-DB and adversarial checks.
- [ ] Privacy/terms/deletion pages final and current; archive manifest and store disclosures match behavior.
- [ ] Actual Release/TestFlight build tested on physical iPhone, small screen, minimum/current iOS, large text and VoiceOver.
- [ ] Correct store assets, age rating, rights, support, agreements, review access, signing and release configuration.
- [ ] Second-pass N01–N11 acceptance: compliant trailers, conditional AI permission, durable retries, restarted reachability, consistent request validation and canonical write responses, atomic compound marks, identity-scoped state, ordered ambient tasks, complete TMDB credits and redacted diagnostics. N12 compiler warnings triaged.

The app is ready to enter this release-hardening sequence. It is not yet justified to describe it as ready for submission, and passing source tests or rendering fixture screenshots should not be used as a substitute for the remaining production, provider, storage, device and App Store evidence.
