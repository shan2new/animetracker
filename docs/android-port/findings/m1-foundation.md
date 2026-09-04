# Foundation audit findings (M1) — 2026-09-04

Three adversarial critics reviewed the ported foundation layer. **Majors were remediated inside the
workflow**; the minors below are recorded so they are neither lost nor silently accepted. Each is a
real observation — several are deliberate re-tunes under `research/fidelity-line.md` and are noted
as such, and the rest are genuine follow-ups.

## Critic 1 — verdict: drifted

### [major] `android/app/src/main/kotlin/com/anitrack/app/design/Theme.kt`

MATERIAL DEFAULT LEAK (line 72-84): PreviouslyTheme never provides LocalTextStyle. Type.kt:391-401 documents `appDefault` as "the scene-wide inherited style, installed once at the theme root as LocalTextStyle" — it is declared and never installed. The provider chain supplies only LocalThemeColors/Space/Radius/Metrics, LocalControlInk and LocalDensity. Any Text without an explicit style therefore falls through to material3's LocalTextStyle default (TextStyle.Default = platform face, unspecified size), i.e. Roboto — the exact fallback iOS's root `.font(.custom("Outfit-Regular", size: 17, relativeTo: .body))` (spec §4.5) exists to prevent. Fix: add `LocalTextStyle provides ThemeType.appDefault` to the CompositionLocalProvider at Theme.kt:74-82. Secondary nit: appDefault = body carries tracking -0.10, where the iOS root font carries none.

### [major] `android/app/src/main/kotlin/com/anitrack/app/design/Theme.kt`

MATERIAL DEFAULT LEAK (line 72-84): PreviouslyTheme never provides LocalContentColor. Verified against the cached material3 1.4.0 artifact (androidx/compose/material3/ContentColorKt$LocalContentColor$1 → Color.Companion.getBlack): the default is Color.Black. Outside PreviouslyMaterialBridge — i.e. everywhere in the app, since the bridge is only meant to wrap borrowed components — a material3 Text or Icon with no explicit colour paints #000000 on the #09090B canvas. Fix: provide `LocalContentColor provides ThemeColor.textPrimary` alongside the token locals.

### [major] `android/app/src/main/kotlin/com/anitrack/app/design/Theme.kt`

MATERIAL TYPOGRAPHY LEAK (lines 217-233): PreviouslyMaterialBridge passes `colorScheme` and `shapes` but deliberately leaves `typography` at Material's default (justified in the KDoc at lines 220-224). Type.kt:32-33 states "NOT Material typography… no screen may see an M3 type." The bridge breaks that for every borrowed component that sets its own text style internally rather than taking one as a parameter — AlertDialog's title/text (ProvideContentColorTextStyle with typography.headlineSmall/bodyMedium), ModalBottomSheet, DropdownMenuItem, Snackbar, NavigationBarItem's label. A caller-supplied `Text(style = …)` wins, but nothing enforces that and no wrapper exists yet to prove the discipline. Fix: pass a `Typography(...)` mapped onto ThemeType into MaterialTheme at line 228.

### [minor] `android/app/src/main/kotlin/com/anitrack/app/design/Theme.kt`

Colour-role map is not exhaustive for the pinned material3 version (lines 149-197; claim of exhaustiveness at lines 136-137). Verified against the cached 1.4.0 ColorScheme class: it carries twelve `*Fixed` roles — primaryFixed, primaryFixedDim, onPrimaryFixed, onPrimaryFixedVariant and the secondary/tertiary equivalents — none of which are mapped here, so they fall through to darkColorScheme()'s baseline Material lavender. Low blast radius for the current closed component set (sheet/dialog/popup/bottom-bar/switch), but it is a Material default sitting inside the bridge.

### [minor] `android/app/src/main/kotlin/com/anitrack/app/design/Type.kt`

Weight deviation from spec §4.3, on four annotating roles: metadataEmphasis (line 239), sectionLabel (line 253), time (line 263) and rowMetaLead (line 339) are spec'd SF **semibold** and ported as FontWeight.Medium. Documented and technically defensible (note 5, lines 66-74: W600 has no real Roboto master, resolves ambiguously on API 28+ and cannot be expressed below 28), but it is a real difference against the spec table and needs a design sign-off rather than only a code comment. Sizes and tracking on all four are exact (13/11/15/13; +1.0 on sectionLabel).

### [minor] `android/app/src/main/kotlin/com/anitrack/app/design/Type.kt`

tabLabel (line 377) and tabLabelSelected (line 380) are 12sp where the iOS UITabBarItem proxy is Outfit Medium/SemiBold **10** (spec §4.7). Documented re-tune to Android's 12sp navigation label (lines 369-376) under the fidelity line; recorded so it is not mistaken for a transcription slip. Weight, family and the medium→semibold selected step are correct.

### [minor] `android/app/src/main/kotlin/com/anitrack/app/design/Type.kt`

AppTypeScale.MAX_FONT_SCALE = 2.0f (line 135) contradicts spec §4.8, which instructs "clamp fontScale to the AX2-equivalent (~1.6×)". The code's own arithmetic (AX2 ≈ 1.94×; iOS body 17pt → 33pt at accessibility2) is the more accurate reading, so the spec line is probably the wrong one — but the two documents currently disagree and one should be corrected. Note the clamp as written effectively never fires on a stock device, which is stated as intentional (lines 115-131).

### [minor] `android/app/src/main/kotlin/com/anitrack/app/design/Elevation.kt`

ShadowToken (lines 56-75) replaces iOS's (colour, blur radius, y offset) triples with dp elevations: None 0, Art 4, Card 8, Floating 14, ArtHero 18. Documented as a deliberate re-tune (lines 26-54) and the iOS values are recorded as history at lines 40-44, so no number is lost. One ordering change rides along and is worth a look on device: iOS gives `.artHero` and `.floating` identical geometry (black 60%/50%, blur 26, y 14), while Android now puts ArtHero a full 4dp above Floating.

### [minor] `android/app/src/main/kotlin/com/anitrack/app/design/Elevation.kt`

ArtGround.neutralWarm = Color(0xFF1C1A17) (line 168) is a colour declared outside ThemeColor, against the rule stated at Color.kt:15 ("If a colour is needed and is not here, it is added here"). The value itself is correct — it is spec §7.2's `PaletteCache.fallback = 0x1C1A17` — but its own comment (lines 164-167) admits it duplicates the palette layer's fallback and that "the two must not drift". Move it into ThemeColor and have both readers point at it.

### [minor] `android/app/src/main/kotlin/com/anitrack/app/MainActivity.kt`

The Bootstrap placeholder (lines 34-42) hard-codes Color(0xFF09090B) at line 37 and Color(0xFFF4F1EC) at line 40 instead of ThemeColor.canvas / ThemeColor.textPrimary, and never wraps its content in PreviouslyTheme — so the token layer is currently installed nowhere in the app. It also uses material3 Text outside any MaterialTheme, which is the exposure described in the LocalContentColor finding (survivable here only because it passes an explicit colour). Labelled a placeholder for M1 at line 33; flagged so it is not carried forward.

### [minor] `android/app/src/main/kotlin/com/anitrack/app/design/Dimens.kt`

ContinuousCornerShape (lines 452-457) returns a plain circular RoundedCornerShape below minVisibleCornerRadius = 12.dp, so ThemeRadius.episodeStill (8) and ThemeRadius.poster (10), plus the PosterSize radii for Focus (10), Row (10), TodayQueue (9), Queue (8) and Beat (6), are not squircles. Spec §2.2 is absolute: "All corners are style: .continuous (squircle) wherever a RoundedRectangle is constructed in the design system." The threshold is documented and almost certainly imperceptible; recorded only because the spec admits no exception.

## Critic 2 — verdict: faithful

### [minor] `android/model/src/main/kotlin/com/anitrack/model/copy/Copy.kt`

EmptyStateCopy symbol names diverge from copy.md §17.2's hand-mapping table. Spec says rectangle.stack -> video_library; Kotlin uses "layers" (emptyAccount). Spec says exclamationmark.circle -> error_outline; Kotlin uses "error" (serverNoCache, searchUnavailable). The Kotlin followed docs/android-port/spec/icon-mapping.md (rows 34 and 20) and documents the choice in-source, so this is a conflict BETWEEN two spec docs rather than a port defect — but copy.md §17.2 and icon-mapping.md must be reconciled or the next audit re-raises it. No user-facing string is affected.

### [minor] `android/model/src/main/kotlin/com/anitrack/model/copy/Copy.kt`

The three user-facing strings in copy.md §9.4 (APIError.failureReason) — "Rate limited", "Timed out", "Server error" — plus errorDescription's "You’re signed out. Sign in again to continue." variant, exist nowhere in the Android tree. They belong to the networking layer (docs/android-port/spec/networking-auth.md, table at line 343), which is not yet ported, so this is an unfilled gap rather than a drift. Risk: when APIError lands they are the strings most likely to be inlined at the exception site instead of entering the catalogue — Copy.State.signedOut already exists and must be reused for the .unauthorized case.

### [minor] `android/model/src/main/kotlin/com/anitrack/model/Formatting.kt`

Line 228 writes a raw NUL byte directly into a string literal: `private const val FORCE_REFRESH = "<U+0000>"` instead of the escape " ". The single NUL makes the whole file binary to grep, git diff and most review tooling — `file` reports it as "data", and a plain `grep` over it returns nothing at all with no error. Failure scenario: a straight apostrophe or a straightened ellipsis introduced into any string in Formatting.kt is invisible to exactly the audit tooling that would catch it (my own first grep pass over this file silently returned zero lines). Escape it.

### [minor] `android/model/src/main/kotlin/com/anitrack/model/copy/Copy.kt`

The `Copy.Empty` object (lines ~880-897) is an Android-only second home for eight EmptyStateCopy values already reachable on EmptyStateCopy's companion, and it renames one of them (`emptyAccount` -> `Copy.Empty.account`). There is no Swift equivalent. It is partial (8 of 21 values), so call sites will split between `Copy.Empty.*` and `EmptyStateCopy.*` for no rule a reader can infer — the same "one string, two homes" shape the catalogue exists to prevent, even though both names currently resolve to the same object. Either complete it or drop it before the UI layer starts consuming it.

### [minor] `android/model/src/main/kotlin/com/anitrack/model/copy/Copy.kt`

Notice.transportReason (lines ~581-600) walks the cause chain for SocketTimeoutException/UnknownHostException/SocketException/InterruptedIOException. copy.md §9.3's Android mapping table also lists "SSLException caused by a dead network" and "ConnectivityManager reporting no validated network" under noConnection. A bare SSLException whose cause chain carries no socket-level exception falls through to serverError, and connectivity state is never consulted. The cause-chain walk satisfies the table's literal "caused by" wording and the in-source comment argues it deliberately (matching NSURLErrorSecureConnectionFailed on iOS), so this is a documented judgement call — but it is the one place the ladder can word a captive-portal or dead-network failure as "Something went wrong" where iOS says "No connection".

## Critic 3 — verdict: faithful

### [minor] `android/model/src/main/kotlin/com/anitrack/model/Derived.kt`

hasArrived() (~line 789) resolves the yyyymmdd key with strict LocalDate.of(...) inside a try/catch, but Swift resolves it through Calendar.date(from: DateComponents), which is LENIENT and rolls over. The port already knows this — Formatting.utcTimestamp deliberately reproduces the rollover with `LocalDate.of(y, mo, 1).plusDays(d - 1)` and says so in its comment — so the module contradicts itself. Concretely: sortKey 20260230 with precision DAY gives iOS Mar 2 2026 (Feb 30 rolls over) and therefore hasArrived == true against a Sep 2026 `now`; Kotlin throws DateTimeException and returns false. DerivedTest.hasArrived_isFalseForAnImpossibleKeyRatherThanThrowing asserts the Kotlin answer, so the divergence is codified rather than caught. Fix: use the same plusDays construction as Formatting.utcTimestamp (or call it directly).

### [minor] `android/model/src/main/kotlin/com/anitrack/model/Derived.kt`

Whitespace-set mismatch at four sites. Kotlin's String.trim() / isBlank() use Char.isWhitespace(), which excludes the non-breaking space separators U+00A0, U+2007 and U+202F; Swift's .whitespacesAndNewlines / .whitespaces include them. Affected: canonicalLabel (line 312, Swift trims .whitespacesAndNewlines), shelfShortened step 1 (line 894), displayRelease's isBlank() guard (line 748, Swift trims .whitespaces), and Formatting.prettyReleaseString's leading trim (Formatting.kt line 553). Observable results: a title ending "…- " never has its "-…-" subtitle wrapper stripped on Android but does on iOS; a release of " " yields displayRelease == " " instead of "". The module already carries the correct predicate — nonEmptyOrNull in Models.kt trims tab + Character.SPACE_SEPARATOR, and Formatting.stripHtml trims U+00A0 explicitly with a comment — so these four sites are simply inconsistent with it. No test covers any of them.

### [minor] `android/model/src/test/kotlin/com/anitrack/model/DerivedTest.kt`

The watch-context rule is untested except for the movie branch. FranchisePart.watchContext(episode) (Derived.kt line 326) deliberately diverges from iOS — Swift's part-local sibling concatenates canonicalLabel RAW ("Season 5: Hashira Training Arc · Episode 1") while Kotlin routes through Copy.watchContext, which compacts to "Season 5 · Episode 1" — and nothing pins that choice. Franchise.watchContext(part, episode), documented as "THE watch-context rule" ("Season 7 · Episode 5" on a multi-part franchise, "Episode 5" on a single one, the fix for "one fact, three grammars"), has no test for either branch; watchContext_forAMovieIsJustItsLabel covers only kind == MOVIE. A regression to the raw-concatenation spelling, or to always printing the season, would pass the whole suite.

### [minor] `android/model/src/main/kotlin/com/anitrack/model/Derived.kt`

EPISODE_AIR_DATE_ANCHOR (line 61) is private and announcedDateLabel (line 338) — its second consumer, and one of the few actively-used derivations on iOS (3 refs) — has no test. Nothing in the suite asserts that an episode airDate is read in UTC rather than in source.timeAnchor, so collapsing it to the franchise's anchor (the exact bug rule 2 of the file header exists to prevent) breaks no test. Because the constant is private and iOS's Episode.airDateLabel / airDayLabel(now:) were not ported, the Compose layer has no sanctioned accessor for an episode air date and will repeat DetailSupport.swift:489's workaround of hard-coding `source: .tmdb` at the call site — precisely the "never branch on source at a call site" pattern this file forbids. Also untested: the TMDB fallback path itself (premiereAt null while the season is dated through its first episode).

### [minor] `android/model/src/main/kotlin/com/anitrack/model/Derived.kt`

passedAirings (line 177) is `internal` with an `anchor: TimeAnchor = LOCAL` default, where Swift makes it `private func passedAirings(now:anchor:)` with no default. Swift's visibility is what guarantees the anchor-aware predicate can only be reached through airedByNow / behind / lastAired; in Kotlin any code in :model can now write `part.passedAirings(now)` and silently get the device calendar for a TMDB part — the day-ahead bug the two-calendar system exists to prevent. It was widened only so DerivedTest could call it; making it private and testing it through airedByNow/lastAired would restore the compiler guard.

### [minor] `android/model/src/test/kotlin/com/anitrack/model/DerivedTest.kt`

Remaining uncovered public derivations. Live ones: Franchise.allVideos (2 refs on iOS) has no test for its featured-then-show-then-parts order or its site/id de-duplication; scheduleAirings' `airedEpisodes > 0` guard on the legacy last-aired slot is never exercised on its own (only via the both-zero-timestamps case); progressCeiling with totalEpisodes == 0 && airedEpisodes > 0 (returns airedEpisodes, not MAX_VALUE) is untested; the Franchise calendar wrappers dayKey / dayDiff / whenLabel are untested (only nextAiring and lastAired are). Lower risk because they are unreferenced on iOS too (spec models.md §8 lists them as dead): isFinished, isBehind, cardBadge, tag, isConcluded, episodeLabel, kindWord.

---

# M2 (components + data) — integrator notes, 2026-09-04

**Green in 4 rounds. 162 tests passing (138 model + 24 ProgressLane).**

Notable fixes the integrator made:

- **Inverted-polarity call site.** `ArtHeader`'s `HeroArt` passed `placeholderHidden = true` where the
  image pipeline's parameter is `placeholder: Boolean` with the opposite sense. A silent visual bug,
  not a compile error — it only surfaced because the parameter name did not exist.
- **Missing auth/transport seam.** `ApiClient` imported `TokenProvider`/`TokenRefreshOutcome` from
  `data.auth` while `AuthManager` declared them elsewhere; the contract now lives in
  `data/api/TokenProvider.kt`.
- **4 `ProgressLaneTest` failures were the TEST's fault, not the lane's** — the tests built the lane
  on `backgroundScope`, and `advanceUntilIdle()` does not drive background work to completion. The
  agent verified this with an isolated probe rather than assuming. Watch for the same trap in any
  future test that uses `backgroundScope`.

## Open items carried forward

| Item | Status |
|---|---|
| **R8 / release build** — flagged as "a likely breakage" on the Clerk/Coil/Retrofit+kotlinx-serialization surface | ✅ **`:app:assembleRelease` succeeds** (verified 2026-09-04, 1m15s, `minifyReleaseWithR8` green). **But**: R8 failures usually appear at *runtime* through reflection, and this was built while `MainActivity` was still a stub, so no serialization path ran. **Re-test the release build end-to-end once screens fetch real data.** |
| **Nothing has been rendered** — the whole component library, chrome and image pipeline are compile-verified only | Unblocked by M3 (screens). This is what `docs/android-port/qa/capture.sh` exists for. |
| No Compose UI or instrumentation tests | Deferred; the screenshot loop is the first real render check. |
