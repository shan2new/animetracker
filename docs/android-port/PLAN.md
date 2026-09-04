# Previously. — Android port: master plan

**Status:** executable plan. Written 2026-09-04. This document is the work breakdown for a
toe-to-toe Android port of the shipping SwiftUI app. It is written to be executed by other agents;
every ambiguity in it is a defect.

**Do not read this instead of the specs.** It links to them; it does not repeat them. The
behavioural contract lives in `docs/android-port/spec/`, the platform evidence in
`docs/android-port/research/`, and the machine setup in `docs/android-port/TOOLCHAIN.md`.

| Layer | Authority |
|---|---|
| **The fidelity line — who wins on RENDERING** | **`docs/android-port/research/fidelity-line.md`** |
| **Settled product decisions** | **`docs/android-port/research/product-decisions.md`** |
| Product law, iOS conventions, named bugs | `/CLAUDE.md` |
| Behaviour, per subsystem | `docs/android-port/spec/*.md` |
| Platform choices + evidence | `docs/android-port/research/*.md` |
| Pinned versions | `docs/android-port/research/verified-versions.md` |
| minSdk decision | `docs/android-port/research/minsdk-decision.md` |
| Machine, emulators, capture loop | `docs/android-port/TOOLCHAIN.md` |
| Icon substitution table (42 symbols) | `docs/android-port/spec/icon-mapping.md` |
| REST contract | `docs/api-contract.md` |

**Precedence when two documents disagree:** the shipping Swift source wins over a spec; a spec wins
over this plan; this plan wins over a research note; a research note wins over anything recalled
from memory. `research/verified-versions.md` overrides version numbers stated anywhere else.

**Override clause — which half of a spec wins.** A spec's **behavioural contract** (what the screen
does, the numbers, the copy, the state machine) wins over this plan. A spec's **"Android
reproduction" / "risk" sidebar does NOT.** Those sidebars were written during extraction, *before*
§1.3, §3.1, §3.5 and §3.6 were decided, and several of them now recommend a Material or platform
default this plan rejects. Where a sidebar conflicts with §1.3, §3.1, §3.3, §3.4, §3.5 or §3.6,
**this plan wins.** The four known conflicts are errata-patched in the spec files themselves and
listed in §9.2; if you find a fifth, patch it in place and add it there.

---

## 1. Fidelity contract

> ### ⚠ AMENDED 2026-09-04, AFTER THIS SECTION WAS WRITTEN — read `research/fidelity-line.md` first
>
> The product owner ruled on where "same look" stops and "native Android" starts:
>
> > *"I don't want the app to look like an iOS app on Android. I want the UX consistency. What can be
> > ported should be, what isn't natively possible in Android, I'd rather use native Android there
> > than do heavy Engineering to make it fit."*
>
> **Port the meaning. Render with native means. Re-tune the numbers.**
>
> | Layer | Rule |
> |---|---|
> | Semantics, hierarchy, information design | Ports **exactly** |
> | Copy | **Verbatim** |
> | Rendering mechanics | The **native Android** answer |
> | Numeric values for rendering | **Re-tuned to READ the same, not to MEASURE the same** |
>
> **Matching an iOS pixel by building machinery Android does not want is a DEFECT, not fidelity.**
> The test: *does an Android user who has never seen the iPhone app experience the same product?*
>
> **What this changes in the section below.** F1 (geometry, 1 pt = 1 dp), F2 (colour hexes),
> F3 (type), F4 (copy), F5 (derivations), F6 (timings), F8 (write policy), F9 (a11y) and F10 (the
> rationing rules) **all stand unchanged** — they are meaning, not mechanics, and dp is the natural
> counterpart of pt rather than a simulation of it. What is struck is any instruction to reach
> numeric parity on a *rendering* effect:
>
> - **Shadows** → Android **elevation** (`Modifier.shadow(elevation, shape)`). Keep `ShadowToken`'s
>   semantic names (`none`/`card`/`art`/`artHero`/`floating`) and the rule that only art large enough
>   to read as an object earns one; pick dp elevations that look right on Android. The iOS
>   `(colour, radius, y)` triples are historical notes, **not targets**. No hand-rolled Skia shadow.
> - **Blur** → native `Modifier.blur` / `RenderEffect` / Haze on API 31+, and the app's own
>   opaque-canvas reduce-transparency branch below (`research/minsdk-decision.md`). **No baked-blur
>   pipeline, no pre-blurred bitmaps, no source-pixel/upscale trick.** If native blur cannot produce
>   exactly iOS's frosting, the Android app gets Android's frosting.
> - **F2's and F7's verification by "pixel-probe diffed against the iOS capture set"** is downgraded
>   for gradients, veils, scrims and shadows to an ordinary design review on the two AVDs. Colour
>   **token** values are still asserted byte-identically by unit test; what is no longer required is
>   that a *composited, blurred, shadowed* region match an iOS screenshot numerically.
> - **§7 Q1 (blur/shadow calibration) is CANCELLED as framed** — it was a half-day exercise to reach
>   numeric parity, and it existed only because of the posture this amendment reverses.
> - **§7 Q6 (hero pull-down stretch) takes option (a)**: Android's native overscroll. Intercepting
>   `onPreScroll` to reproduce iOS's rubber-band is precisely the heavy engineering that is ruled
>   out. The billboard keeps its identity through size, art and copy hierarchy.
> - **§7 Q5** → `open_in_new`. **Q16** → `DropdownMenu`. **Q17** → accept the platform Reduce Motion
>   contract for built-ins; `pickMotion` covers only motion the app drives itself.
> - **§7 Q11 / Q21 (haptics)**: *"Haptics are not really a blocker. Different devices have different
>   ones unlike iPhones."* Map to `HapticFeedbackConstants` semantics and let the OEM decide the
>   feel; accept `.commitLight`/`.commitMedium` collapsing to one grade; **physical-device haptic
>   sign-off is no longer a release gate.** The `FeedbackCoordinator` one-per-transaction discipline
>   and its per-token floor still stand — that is about not buzzing twice for one action.
>
> **What this does NOT relax:** no `MaterialTheme` as the app theme, no dynamic colour, no Material
> typography, no FAB, no `Snackbar` for the custom toast, amber is still never an action colour, bars
> are still never transparent, every number is still a token. The *values* change; the *discipline*
> does not.
>
> **Android may look different from iOS. Android may not look arbitrary.**

### 1.1 What "toe-to-toe" means

The product thesis is that this app does not feel like a cross-platform app. The port therefore
matches **the design system, the state machines, the copy and the derivations exactly**, and matches
**the platform's reflexes** where a user's muscle memory lives. Those two sets do not overlap; §1.3
is the exhaustive list of the second.

### 1.2 Must match, and the unit it is measured in

| # | Class | Rule | How it is verified |
|---|---|---|---|
| F1 | **Geometry** | **1 iOS pt = 1 Android dp, everywhere, with no rescaling.** Every number in the specs — 16 gutter, 60×90 row poster, 104 BannerCard, 44-pt targets, 22/24 radii, 3-pt progress bar, 120×68 episode tile — is written into the token layer as `.dp` unchanged. | Token unit tests + `adb exec-out screencap` diffed against the iOS capture set. |
| F2 | **Colour** | Every `ThemeColor` hex and alpha byte-identical (`spec/design-tokens.md` §1.2). Surfaces are *lifts* (white α over whatever is beneath), never opaque fills. Gradient **stop locations and opacities** identical (`ScrollEdgeChrome`, `ArtScrim`, `HeroTopVeil`, `HeroCopyScrim`, `ArtBackdrop`, `ArtAdaptiveGround`). | A `ColorTokensTest` asserting each ARGB; a screenshot pixel-probe at the documented sample points (`chrome-images.md` §3.9). |
| F3 | **Type** | Sizes in `sp` equal to the iOS pt value; weights equal; tracking converted **once**, by the rule `letterSpacing = (tracking_pt / size_pt).em` (records the ratio, survives scaling). `monospacedDigit` → `fontFeatureSettings = "tnum"`. Outfit is the brand face; the annotating face is the platform grotesque. | Token test asserting the **26** `ThemeType` entries (16 in the enum + 10 in `extension ThemeType`, `ThemeTokens.swift:540`); a second assertion over the 15 mapped M3 `Typography` slots (§3.2); visual check of the 10 SF-set lines. |
| F4 | **Copy** | **Byte-identical strings, including U+2019, U+00B7, U+00A0, U+2060, U+2013, U+2014, U+2026, U+201C/D** (`spec/copy.md` §1.1). `Copy.plural` stays a hand-rolled function, not `getQuantityString`. `Copy.auditProblems` is re-homed as a **JVM unit test that fails CI**. | `CopyAuditTest` + a golden string corpus shared with iOS (§4.2 of this plan). |
| F5 | **Derivations** | The freshness ladder, sort keys, shelf states, schedule bucketing, `shelfShortened`, `ReturnFact`, `resumePart`, `progressCeiling`, `grafting` — identical outputs for identical inputs. | The **golden-fixture corpus** (M1): a JSON file of `(input, now, expected)` triples generated from the Swift and replayed by JVM tests. |
| F6 | **State machines & timings** | `SkeletonGate` 240/320/120/800 ms; toast 6 s / 10 s TalkBack, error 4/8 s, notice 2.5 s; handoff 650 ms + 80 ms insertion delay + 300 ms tail; retry lockout 800 ms; `directErrorWindow` 30 s; debounce 300 ms; `clockTick` 20 s; celebration 1300 ms; refresh spinner 400 ms; splash ignite 0.92 s / hand-off 1.68 s (1.2 s reduced); auth bootstrap ≤3 s @ 80 ms. | Instrumented tests with a virtual clock; `TimingConstantsTest`. |
| F7 | **Motion** | The 13 `ThemeMotion` curves, converted by `stiffness = (2π/response)²`, `dampingRatio = dampingFraction`, and cubic-béziers declared **explicitly** (never `FastOutSlowInEasing` as a stand-in for `.easeInOut`). Asymmetric `handoff` and `toast` transitions preserved. Press feedback: scale 0.985/0.992, and **opacity 0.72 not scale** under Reduce Motion. | `research/motion-haptics.md` §3; frame-capture comparison on one screen. |
| F8 | **Write policy** | A progress mark never rolls back; membership/status writes always do. One PUT in flight per `mediaId`, newest-wins, superseded dropped. `WriteIntent` replay across launches. Exactly one haptic per transaction. | Unit tests over `AppModel` with a fake `ApiClient`; a "12→13→14 rapid mark" test asserting exactly two PUTs ending on 14. |
| F9 | **Accessibility semantics** | Labels verbatim; posters/veils/scrims/glyph tiles `clearAndSetSemantics {}`; heading traits on section headers and grouped-list headers; announcements on every settling state; screen-reader-extended toast lifetimes. | TalkBack walkthrough script per screen (M14). |
| F10 | **The rationing rules** | Amber is never the ink of a tappable word (`interactive` is). One section-header family. One row anatomy. One wide art card. One episode-row anatomy. Landscape frames never `.fill` a portrait cover. Prose is rationed. Every settings **toggle** whose value means state is amber (`PreviouslySwitch`, §3.4); every other control ink is `interactive`. | Design review against `/CLAUDE.md`; **two** lint rules, because on Android the collision arrives from the other direction. (a) ban `ThemeColor.accent` inside `clickable` label scopes (best-effort — this is the iOS-shaped failure). (b) **ban any read of `MaterialTheme.colorScheme.*`, `MaterialTheme.typography.*` or `MaterialTheme.shapes.*` outside `design/theme/` and the named M3 wrapper files.** Rule (a) is blind to the whole Android class of failure — a `Switch` drawing `primary`, a `NavigationBarItem` drawing `secondaryContainer`, an `AlertDialog` button drawing `primary`, a `TopAppBar` drawing `surfaceContainer` — because none of those source lines contains the string `ThemeColor`. Rule (b) catches it by construction. Paired with the M5 pixel-probe set (§5). |

**On screen size.** The QA emulator is **427 × 952 dp** against the iPhone's **393 × 852 pt**
(`TOOLCHAIN.md`). Pixel-for-pixel equality is therefore impossible and is *not* the target. The rule
is: **every fixed dimension is identical; the extra 34 dp of width and 100 dp of height are absorbed
by the content column and the scroll length, and by nothing else.** No new element, no changed line
count, no re-tuned gutter. A layout that adds a fifth shelf card because it has room is a defect.

### 1.3 Deliberate divergences — the complete list

Each of these is a decision, not a shortfall. Anything not on this list must match.

**Rule for keeping this list exhaustive:** a §7 answer that changes anything a user can see, hear or
feel is **not** finished when it is answered — it gets a **D-number in this table at the moment it is
taken**, with the iOS behaviour it replaces written out. An accepted "recommended default" that
alters the product is a decision; leaving it only in §7 turns it into an unrecorded shortfall. §8
rule 8 restates this for the agents.

| # | Area | iOS | Android | Why |
|---|---|---|---|---|
| D1 | **Back** | Interactive edge-swipe pop from `NavigationStack`. | System predictive back, driven by `NavDisplay`'s `predictivePopTransitionSpec`. Never `enableOnBackInvokedCallback="false"`. | Platform contract; mandatory at targetSdk 36. |
| D2 | **Press feedback** | `pressFeedback` (scale/opacity), no ripple. | **Same — no Material ripple anywhere.** Every clickable passes `indication = null` and composes the app's own press style. | The app's press language is part of its identity; a ripple over artwork is the exact defect `OverArtPressStyle` exists to avoid. *(This is a divergence from Android, not from iOS — listed so nobody "fixes" it.)* |
| D3 | **Share** | `ShareLink` + `Transferable`, `square.and.arrow.up`. | `FileProvider` + `Intent.ACTION_SEND` system chooser, Material `share` glyph. | `icon-mapping.md` #36. The box-and-arrow is an iOS idiom. |
| D4 | **Context menu** | `.contextMenu` — the row lifts out of the list over a blurred backdrop. | `combinedClickable(onLongClick)` + `DropdownMenu` anchored to the card. **Contents, order, destructive role and "the menu fires no haptic of its own" are identical.** | No Android equivalent to the platter. |
| D5 | **Confirmations** | `.confirmationDialog` (action sheet). | `AlertDialog`, Android button placement. **Strings verbatim; no confirmation button ends in an ellipsis.** | Platform idiom. Note Profile's two destructive flows already use `.alert` on iOS for the same reason (`spec/networking-auth.md` §10.4). |
| D6 | **Text scaling** | Per-style Dynamic Type ramps, capped at `accessibility2`. | One global `fontScale` on Compose's non-linear curve. `isAX` is a single project-wide constant **`fontScale >= 1.3f`, and that is a deliberate divergence, not a conversion** — see D6a. The relative growth of `heroTitle` vs `metadata` will not match. | Android has no per-style ramp. `research/typography-icons.md` §4. |
| D6a | **The `isAX` threshold** | `.accessibility1` is where the AX layouts switch. iOS `.body` is **17 pt at `.large` and 28 pt at `.accessibility1`** — a ratio of **1.647×**, *not* the "≈1.35×" claimed in `spec/detail.md` §12.4 and `spec/library.md` §8.2 (both errata-patched, §9.2). | **Threshold stays `1.3f`, recorded here as a divergence.** Android's ordinary "Largest" slider is 1.3, so every user on the largest *non-accessibility* setting gets the AX layout an equivalent iOS user never sees. This is accepted deliberately: Compose's non-linear curve already lands most tokens 7–14 % below iOS at the same nominal scale, Android's own font-scale ladder has no rung between 1.3 and the accessibility range, and switching **early** degrades gracefully (looser, taller, single-column) where switching **late** clips. | The layout switches this moves, all of which fire at 1.3 on Android and at AX1 on iOS: `MediaRow`'s unpinned poster width (`Primitives.swift:812-813`), `ShelfCard`'s `1...6` line limit (`Primitives.swift:787`), the dropped shelf fade mask (`Primitives.swift:966`), `EmptyState`'s full-width buttons (`spec/discover.md` §9.7), Schedule's "Nothing scheduled" leaving the header count slot (`spec/design-tokens.md` §5.3), and `InlineNotice`'s H→V swap. **M7's exit criterion is therefore a same-scale comparison, not an iOS diff** — see §5 M7. |
| D6b | **Above 2.0 and display size** | Dynamic Type stops at `accessibility5`; there is no second scaling axis. | `Configuration.fontScale` is **not** clamped by the platform — the Pixel slider stops at 2.0 but OEM sliders differ and `adb shell settings put system font_scale 3` takes effect. The app **does not clamp either**; the F1 fixed dimensions (104 dp `BannerCard`, 60×90 row posters, 120×68 episode tiles, 286×161 Continue card, 44 dp targets) stay fixed and the **text around them is allowed to wrap and the row to grow**; nothing may clip or overlap. Separately, Settings → **Display size** changes `densityDpi` and can take the usable width well below the 393 dp iPhone reference those dimensions were tuned against. | No clamp exists to inherit. Both axes are in M14's capture matrix (largest display size at font scale 1.0; font scale 2.0 and 3.0 at default density). |
| D7 | **Notifications** | `UNUserNotificationCenter`, no permission before iOS 18's implicit grant flow, foreground presenter. | Notification **channels** (mandatory ≥ 26), `POST_NOTIFICATIONS` runtime permission (33+), one alarm per air-time bucket (≤8 buckets / 48 h) rather than one per episode. **The primer UX and the "an add never raises the OS dialog" rule are identical.** Exactness, rearming and the OEM ceiling: D7a–D7c. | `research/notifications-liveupdates.md`. |
| D7a | **Exact alarms are DENIED BY DEFAULT** | Not a concept. | `SCHEDULE_EXACT_ALARM` is declared (31+), **never `USE_EXACT_ALARM`** (Play policy limits it to alarm/timer/calendar apps). At targetSdk 36 on Android 14+ the grant is **denied by default** (`research/notifications-liveupdates.md` §2.3, citing `developer.android.com/about/versions/14/changes/schedule-exact-alarms`). So on a fresh install on any modern device there are **no exact alarms**: `setExactAndAllowWhileIdle` throws `SecurityException` and the fallback `setAndAllowWhileIdle` is Doze-rate-limited to roughly **one firing per 9 minutes**. Both branches ship: check `AlarmManager.canScheduleExactAlarms()` before every arm, catch `SecurityException` regardless (the grant can be revoked between check and arm), and **`ArmedAlertStore` records which branch armed the row so the bell never claims a precision the app does not have** (`Copy` gets one honest degraded string — spec debt §9.1 D-1). The grant ask is a Settings row: D31. | Promoted from "a UX question" (old Q13). Writing the alarm code against the granted branch alone ships alerts that are inexact on every Android 14+ device. |
| D7b | **Alarms do not survive a reboot** | Not a concept — iOS notification requests persist. | Every alarm is lost on reboot, on app update, and on a timezone or clock change. `notify/RearmReceiver.kt` re-arms from `AiringPlanStore` on `BOOT_COMPLETED` (needs **`RECEIVE_BOOT_COMPLETED`**), `MY_PACKAGE_REPLACED`, `TIME_SET`, `TIMEZONE_CHANGED` and `ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED` (the last one both re-arms *and* upgrades the armed set from inexact to exact). `research/notifications-liveupdates.md` §3.1. | Without it the alert set silently empties overnight while the UI still shows armed bells. |
| D7c | **OEM battery management is a hard ceiling** | Not a concept. | **Stated as a product fact, not a mitigation:** Samsung ships "Put unused apps to sleep" **on** by default and Xiaomi denies Autostart by default. A deep-slept app's alarms are deferred; a **force-stopped app receives no broadcasts at all**, so even `RearmReceiver` does not run and the alerts stay dead until the user next opens the app. There is no in-app fix. The only real fix is server-side FCM (Q12). | R20's mitigation column understated this as a QA problem. It is the feature's ceiling. |
| D8 | **Live Activity / Dynamic Island** | ActivityKit + Island, self-ticking `Text(timerInterval:)`. | **Feature gap.** Closest is an Android 16 (API 36) **Live Update** — ongoing notification, `POST_PROMOTED_NOTIFICATIONS` + `setRequestPromotedOngoing(true)` + `setWhen`/`setUsesChronometer`/`setChronometerCountDown`. No Island. Gated to API 36; below 36 there is no ambient surface at all. | No equivalent exists. §6 R1. |
| D9 | **Widget** | **iOS has NO home-screen widget.** `ios/Widgets/AniTrackWidgets.swift:13-18` is a `WidgetBundle` whose body is exactly one entry, `AiringLiveActivity()` — an `ActivityConfiguration`, not a `WidgetConfiguration`. The file's own header says "currently just the airing-countdown Live Activity", and `spec/profile-shell.md` §11.1 agrees: "A `WidgetBundle` containing exactly one widget, `AiringLiveActivity`. There is no home-screen widget." | **Nothing to port.** The file's real content — `LockScreenAiringView` (:67), the four Dynamic Island regions (:27-61), `CountdownText` (:96), `episodeLabel` (:116), `airLine` (:121) — is the **Live Activity's** presentation and maps to `notify/LiveUpdateNotification.kt` (§4.6), which is D8's surface, not a widget. | The plan previously asserted a "WidgetKit timeline" that does not exist, and mapped the one real file to four widget files. Corrected 2026-09-04. |
| D28 | **"Up Next" Glance widget — NEW FEATURE, not a port** | Does not exist. | A Glance 1.2.0 "Up Next" 4×2 home-screen widget: event-driven + 30-min `PeriodicWorkRequest` + one inexact alarm at each episode boundary, fixed dark colours (**never** Material You / `GlanceTheme` dynamic). | **This is net-new product, and it is scoped in §7 (Q22), not in §4.6's port table.** It is listed here so it is never presented as fidelity work. Combined with Q7 ("No" to Live Updates in v1), shipping only the widget would mean the port ships **zero** of iOS's actual ambient surface and one screen iOS has never had. Sequencing rule: the Live Update (D8) is the port; the widget is the addition, and the addition does not precede the port. `research/widgets-glance.md`. |
| D10 | **Tab bar minimise on scroll** | `tabBarMinimizeBehavior(.onScrollDown)` (iOS 26 only; already absent on the iOS 18 floor). | **Dropped.** Static `NavigationBar`. | Already a no-op on the iOS floor; a hand-rolled version is a different component. |
| D11 | **Liquid Glass** | iOS 26 `glassEffect`, toolbar capsules, search scope bar, glass tab pill. | **Never imitated.** The port implements the app's own **iOS 18 fallback** (`.ultraThinMaterial` equivalent, or the opaque Reduce-Transparency branch). | `/CLAUDE.md` and every spec say this; imitating glass is worse than the sanctioned fallback. |
| D12 | **Reduce Transparency** | System setting; drops the material and takes the bar veil 0.74 → 1.0. | **In-app toggle**, in Settings beside Haptics, default off, **OR'd with `SDK_INT < 31`**. One boolean `canUseMaterial = SDK_INT >= 31 && !reduceTransparency`, resolved once. | No Android setting. Load-bearing on pre-31 devices, not an accessibility nicety. |
| D13 | **Differentiate Without Colour** | System setting; drives `DifferentiateMark` + `differentiatingUnderline`. | **In-app toggle**, same Settings group, default off. | No Android setting. Without it every amber-only state is colour-only. |
| D14 | **Reduce Motion** | System setting. | `Settings.Global.ANIMATOR_DURATION_SCALE == 0f`, surfaced as `LocalReduceMotion`. Compose's `MotionDurationScale` will additionally **snap** built-in animations; the drift/breath infinite loops must be gated explicitly or they freeze at their end value. | `research/motion-haptics.md` §4. |
| D15 | **Zoom navigation transition** | `.zoomSource` registrations exist; **consumed by nothing** (tried 2 Sep, retired 3 Sep). | **Not ported.** No `SharedTransitionLayout` into Detail. Drop the `zoomID` parameter from every component signature. | Re-introducing it re-introduces a defect the team paid to remove. |
| D16 | **Local network** | `NSLocalNetworkUsageDescription` prompt. | No prompt. A **debug-only** `network_security_config.xml` permitting cleartext to `10.0.2.2` and the LAN dev host. | Android has no such prompt. |
| D17 | **Shelf paging physics** | `.scrollTargetBehavior(.viewAligned)`. | `LazyRow` + `rememberSnapFlingBehavior`. Snap target and deceleration will differ slightly. | No exact equivalent; the 4-of-5 span and peeking rhythm are preserved by geometry. |
| D18 | **Bottom sheets — all four** | `presentationDetents` with computed/measured heights. | `ModalBottomSheet` with a fixed content height computed by the same formulas. **The app has four sheets, not two; every one gets a presentation and a height rule here, because a sheet with no rule becomes a nav destination by accident.** ① **Arrange** (Library sort/filter): `5 × 56 × typeFactor + 130`, capped `0.92 × max`. ② **Rewatch start** (`RewatchViews.swift`): `clamp(content + 64, 260, 620)`. ③ **Profile**: `TodayView.swift:223` presents it as a `.sheet` and `spec/profile-shell.md` §6.1 records that pull-to-refresh was deliberately removed **because** it is a sheet — so it is a `ModalBottomSheet` at **near-full height** (`0.94 × max`), drag-to-dismiss on, **no pull-to-refresh**, and its destination file is **`ProfileSheet.kt`** (§4.5), not `ProfileScreen.kt`. `ExportOptionsScreen` is pushed **inside** the Profile sheet's own tiny nav host, not onto a tab stack — it must not appear behind the sheet. ④ **VideoSheet** (`FranchiseDetailView.swift:165`, the trailer): `ModalBottomSheet` at 16:9 + bar, `dragHandle = null` (a Material drag handle ripples — D2), dismiss on back and on the bar's close glyph; it does **not** go full-screen. | No arbitrary-detent API. Getting the height wrong reproduces the "sheet grew 68 pt under the user's eye" bug. `RootScaffold` mounts `ToastHost` **twice** (shell + sheet) precisely because ③ exists (§4.4). |
| D19 | **Splash shaders** | Metal `emberZoom` (10-tap radial smear + chromatic fringe) and `filmGrain`. | AGSL `RuntimeShader` at API 33+; **below 33 the dive is a plain scale and the grain is dropped**. | Grain is near-invisible by design; the loss is acceptable. |
| D20 | **Hero pull-down stretch** | `StretchingHeroArt` grows the art with the rubber band. | Open decision — see §7 Q6. Default: reproduce via `onPreScroll` interception. | Android overscroll clamps at 0 and stretches the container. |
| D21 | **`bottomUnderfill` (180 pt over-draw)** | Fights a `TabView` safe-area quirk. | Kept: Compose `Scaffold` insets content by the bottom bar identically. Verified by screenshot — no chevron legible in the gesture strip. | Same quirk, same fix. |
| D22 | **Blur radii and shadow radii** | Points into a Core Animation Gaussian. | **Re-calibrated by eye and then frozen as tokens.** Skia's blur and `setShadowLayer`'s radius are not the same scale as iOS's. | §7 Q1. The only class of number in the app allowed to change. |
| D23 | **Haptic waveforms** | 3 impact intensities + 3 notification patterns. | Approximated with `VibrationEffect.Composition` primitives (API 30+, guarded by `arePrimitivesSupported`) falling back to `HapticFeedbackConstants`. `.commitLight`/`.commitMedium` may collapse to one grade on some devices. **The per-token throttle (40 ms selection / 300 ms otherwise), the foreground gate, the app toggle and one-per-transaction are exact.** | No notification-haptic taxonomy on Android. |
| D24 | **Malformed-array decoding** | One bad element empties the **whole** array. | **Same** — a `SafeListSerializer` that drops the whole list, not the element. | Deliberate parity; see §7 Q3 if this is to be revisited. |
| D25 | **Auto-backup** | `library-cache.json` is backed up to iCloud. | The library snapshot is **excluded from BOTH backup mechanisms**. `android:fullBackupContent` is honoured only on **API ≤ 30**; from **API 31** the platform reads **`android:dataExtractionRules`** for cloud backup *and* device-to-device transfer. Authoring only the legacy attribute leaves `library-cache.json` in backups on every Android 12+ device — the majority of the install base and the entire population above the blur floor. Ship both files: `res/xml/backup_rules.xml` (`<full-backup-content>` excluding the snapshot, the rewatch store, the failed-change store and the recents) **and** `res/xml/data_extraction_rules.xml` with the same exclusions under **both** `<cloud-backup>` and `<device-transfer>`. | A restored backup on a different account showing a foreign library is a bad first frame. **Verified, not trusted:** M14 runs `adb shell bmgr backupnow <pkg>` then inspects the transport's set. |
| D26 | **System back at a tab root** | No concept — there is no system back; the tab bar is the only way between tabs. | **System back at a tab root finishes the Activity.** It does **not** switch to the previously visited tab, and it **never** removes a tab's stack or its `SaveableStateHolder` slot. The official nav3 recipe reproduced at `research/compose-architecture.md` §5.4 does exactly that (`topLevelStacks.remove(topLevelKey)` then fall back to `keys.last()`) — **do not copy that `pop()` branch.** Back inside a tab pops that tab's stack as normal (D1, predictive). | The recipe's behaviour is a real, user-visible navigation model with no iOS analogue and no design behind it: it would also delete the tab's saved scroll positions on the way out. Finishing is the Android reflex users actually have from a bottom-nav root. See §2.5. |
| D27 | **Sign-in surface** | A custom gate: `ZStack` on canvas, `PreviouslyMark(width: 58)` over a `RadialGradient([accent@0.20, accent@0.05, .clear], r 0…260)` in a 520×520 frame at blur 24 — "the screen's one light source" — the app's own buttons, 24/40 padding (`spec/profile-shell.md` §5). | **Open — this is a fidelity decision, not a cost one, and it is NOT taken by default.** See Q2(b). If Clerk's prebuilt `AuthView` + `ClerkTheme` is accepted, this row records exactly what `ClerkTheme` **can** restyle (colour roles, corner radii, typeface) and what it demonstrably **cannot** (the mark + radial-bloom composition, `PrimaryButtonStyle2`'s capsule, the press language, the field chrome), and M3 does not pass until a side-by-side capture against the iOS sign-in screen is signed off. | It is the first screen a new user ever sees and the one place a Material-looking frame most damages the "this is not a cross-platform app" thesis. Previously buried as a §7 recommended default. |
| D29 | **"Leaves the app" glyph** | `arrow.up.right` / `arrow.up.backward`. | **`open_in_new`**, not the 1:1 `arrow_outward`. Same reasoning as D3: the row genuinely opens a browser and `open_in_new` is the Android reflex for it. **`spec/icon-mapping.md` rows 2–3 are errata-patched to match** (§9.2) — they specified `arrow_outward`. | Answered as Q5's default; promoted here because it changes a glyph the user sees on Detail's provider header and the trailer bar. |
| D30 | **`RecapBeat.id`** | Embeds a **locale-formatted** date, and that id is persisted inside `digestID` — so changing device language can un-acknowledge an already-dismissed digest (R28). | **Locale-independent id** (`ISO_LOCAL_DATE` + the beat's kind + media id). Deliberately **not** byte-identical with iOS. | Answered as Q10's default with the instruction "record the divergence in this plan"; this is that record. The persisted `digestID` shape therefore differs across platforms — which is fine, it is device-local. |
| D31 | **Exact-alarm permission row** | No counterpart — iOS has no exact-alarm grant. | **One Settings row beside Notifications**, in the same group as Haptics: it states the current grant, and tapping it fires `ACTION_REQUEST_SCHEDULE_EXACT_ALARM`. Off-state copy is honest about the degraded path (D7a). It is the app's only control with no iOS twin. | Answered as Q13's default. A control the user can see and toggle is a product surface, not a UX footnote. |
| D32 | **Material's own colour, type and shape roles** | Not a concept — SwiftUI has no tonal system. | The port hand-writes a **complete** `darkColorScheme(...)` mapping **all 30+ M3 roles** onto `ThemeColor`, and maps `MaterialTheme.shapes` onto `ThemeRadius`/`Squircle`, so no sanctioned component can draw a colour, a corner or a type slot nobody chose. **Never `dynamicDarkColorScheme`/`dynamicLightColorScheme`, never `lightColorScheme`, never `isSystemInDarkTheme()`.** §3.1 carries the mapping and the banned-component list. | `MaterialTheme(...)` invoked without a `colorScheme` **defaults to `lightColorScheme()`** — the confirmation dialogs, the quick-action menu, both bottom sheets and the tab bar would arrive as light-on-white tonal slabs in a dark-only app, and the manifest guards (`isLightTheme=false`, `forceDarkAllowed=false`, no `values-night/`) do not touch Compose at all. |

### 1.4 Explicitly not ported (dead code)

`ZoomTransition.swift`, `ScaledFont.swift`, `ThemeColor.information/.separator/.focusRing/.backdropFade`,
`ThemeMotion.uiLiveBreath`, `EmptyStateCopy.calmToday` as a live state, **`FactLine` *the view*** —
**keep the `FactLine.separator` constant, it has three live call sites** (`SearchComponents.swift:233`
defines it as `" \u{00B7} "`; used at `DiscoverView.swift:541` grid-card caption join, `:583` shelf-card
meta join, `:679` result-row meta join, none of which is `cardMeta`). Only the *view* is dead: its sole
construction is inside `cardMeta` (`DiscoverView.swift:832`), which has no call sites. `spec/discover.md`
§9.3 states this precisely. Deleting the constant breaks the rule its own doc comment names — "a row
and a card never punctuate differently". Also not ported: `RankGutter`/
`cardMeta`/`fittedTitle` in Discover, `APIClient.health()` (no call site), `GET /me/notifications` +
`POST /me/notifications/read`, `PosterSize.libraryHero` (verify first — the carousel it sized is gone).
`PartCounts` is modelled as `Map<PartKind, Int>` because the struct as written cannot decode what
the server sends (`spec/models.md` §3.5).

---

## 2. Architecture

### 2.1 Stack — pinned versions

All from `research/verified-versions.md` (resolved empirically 2026-09-04 from Google Maven / Maven
Central). Put every one in `gradle/libs.versions.toml`; no version literal in a `build.gradle.kts`.

| Component | Version | Note |
|---|---|---|
| JDK toolchain | **21** | `/opt/homebrew/opt/openjdk@21`. Non-interactive shells must export `JAVA_HOME` themselves. |
| Kotlin | **2.4.10**, with **2.3.21 as the named fallback** | Compose compiler ships inside the Kotlin release. ⚠ **Kotlin and KSP are pinned from different lines and that is an M0 gate, not an assumption.** KSP `2.3.11` (published 2026-08-03, the newest KSP there is — there is no 2.4.x KSP) declares `kotlin-stdlib:2.3.20`, and **KSP2 embeds the Kotlin Analysis API**, so a KSP built on 2.3.20 driving a 2.4.10 compiler is the classic mismatch. Hilt (KSP) is on the M0 critical path. Haze 1.7.3 and Compose BOM 2026.08.00 (ui/foundation 1.12.0, material3 1.4.0) are also on the 2.3.20 line — 2.4.10 is the odd one out across the whole stack. **M0 gate (§5):** "KSP 2.3.11 + Hilt 2.60.1 codegen compiles under Kotlin 2.4.10". If it does not, **drop to Kotlin 2.3.21** and record it — do not spend time forcing it. See Q24. |
| AGP | **9.4.0** | Newest stable. Supports up to API 37. Gradle floor 9.6.0. |
| Gradle wrapper | **9.6.1**, pinned in `gradle-wrapper.properties` | Generate the wrapper once with the Homebrew Gradle (9.7.1), then never invoke system Gradle again. |
| Compose BOM | **2026.08.00** | → ui/foundation/runtime **1.12.0**, material3 **1.4.0**. |
| compileSdk | **37** | Forced by Compose 1.12. |
| targetSdk | **36** | Play floor since 2026-08-31. Keep the large-screen opt-out; portrait-locked. |
| **minSdk** | **26** | Product decision, `research/minsdk-decision.md`. Supersedes the 31 recommendation in `compose-architecture.md`. |
| Hilt | **2.60.1** (KSP) | Requires AGP 9 / Gradle 9.1+. Never 2.59.0 (broken artifact). |
| KSP | **2.3.11** | KSP2 no longer pins to the Kotlin version — **not** `2.4.10-x.y.z`. |
| Navigation 3 | **1.1.7** (`navigation3-runtime`, `navigation3-ui`) | |
| `androidx.lifecycle:lifecycle-viewmodel-navigation3` | **2.11.0** | Resolved — it has a **stable** 2.11.0 on Google Maven (alongside 2.12.0-alpha01/02); the earlier "may still be alpha" caveat is stale. Needed because `NavDisplay`'s entry decorators include the ViewModel-store decorator (§2.5). |
| `androidx.lifecycle:lifecycle-process` | **2.11.0** (same line) | `ProcessLifecycleOwner` ON_START/ON_STOP — §4.4's foreground/background wiring. |
| `androidx.datastore:datastore-preferences` | **1.2.0** | `data/disk/Prefs`, `FailedChangeStore`, the haptics key, both a11y toggles (D12/D13). Was used throughout §2.2 and §4 but never pinned. |
| `androidx.work:work-runtime-ktx` | **2.11.0** | The widget's 30-min `PeriodicWorkRequest` (§4.6). **Only if Q22 ships the widget** — otherwise omit the artifact entirely rather than shipping an unused scheduler. |
| `androidx.core:core-splashscreen` | **1.2.0** | **Mandatory, not optional.** At minSdk 26 the platform `SplashScreen` API (31+) does not exist, and both `research/typography-icons.md` §9.2 and `research/compose-architecture.md` §6.1 call `installSplashScreen()`. It is also the only way to hand off from the system splash into `SplashScreen.kt` without two splashes (§4.4). |
| Retrofit | **3.0.0** + `converter-kotlinx-serialization:3.0.0` | |
| kotlinx.serialization | **1.11.0** | |
| OkHttp | **BOM 5.5.0** | BOM-pinned over Retrofit's transitive 4.12. |
| Coil | **3.6.1** (`coil-compose`, `coil-network-okhttp`) | Not 3.0.x. |
| Clerk | **`com.clerk:clerk-android-api:1.1.5`** (+ `clerk-android-ui:1.1.5`) | Same publishable key as iOS. SDK minSdk 24 — satisfied. |
| Glance | **1.2.0** (`glance-appwidget`, `glance-material3`) | |
| Haze | **1.7.3** | **Not 2.0.0-beta02** — it drops `haze-materials` / `CupertinoMaterials.ultraThin()`. |
| androidx.core | **1.19.0** | Floor 1.17.0 for `setRequestPromotedOngoing`. |

**Verify at setup, before writing them in:** the declared `minSdk` of **Glance, Coil 3, Haze, and
the WebView/Media3 usage** against our floor of 26 — a dependency declaring 28 silently raises the
effective floor through manifest merger and quietly undoes the product decision. Also confirm
whether core-library desugaring is still wanted (at minSdk 26 `java.time` is native, so the main
reason is gone).

**Compose stability configuration — required, and it is a build-file concern.** `:model` is a plain
`org.jetbrains.kotlin.jvm` module with **no Compose dependency**, so the Compose compiler plugin never
runs over `Franchise`, `FranchisePart`, `Episode`, `Airing`, `ScheduleDay`, `LibrarySection`,
`RecapBeat`. Compose cannot read `@StabilityInferred` metadata for classes from a module compiled
without the plugin, and a class holding a `List<T>`/`Map<K,V>` — which `Franchise` does, and
`PartCounts`-as-`Map<PartKind,Int>` does by design (§1.4) — is inferred **unstable** regardless. Every
composable taking one (`MediaRow`, `ShelfCard`, `BannerCard`, `AiringCard`, `EpisodeList` rows) then
becomes **non-skippable**, and §2.3's 20 s `now` / 60 s `nowMinute` ticks recompose every row on every
tab on every tick. Do **both** of these:

1. `composeCompiler { stabilityConfigurationFile = rootProject.file("compose_stability.conf") }` in
   `app/build.gradle.kts`, with `com.anitrack.model.**` listed.
2. Annotate the wire and derive types `@Immutable`, and use **`kotlinx.collections.immutable`**
   (`ImmutableList`/`ImmutableMap`) for their collection fields. `androidx.compose.runtime` is a plain
   JVM artifact — depending on it for the annotations does **not** make `:model` Android-dependent, so
   this does not cost the module's "`android.jar` structurally out of reach" property.

Belt and braces on purpose: (1) covers types added later without an annotation, (2) survives someone
removing the config file. **M2's exit criterion is the actual test** (§5): advance `now` by 20 s with
the library unchanged and assert **zero** recompositions of `MediaRow`/`ShelfCard`/`AiringCard` using
Compose recomposition counts — not a systrace of a screen composable, which cannot see this.

**Application id:** `com.anitrack.app` by default (see §7 Q9 — it also decides the Clerk
`clerk://${applicationId}.callback` allowlist entries).

### 2.2 Module and package map

Two Gradle modules. `:model` exists for one reason: the freshness ladder is the highest-risk logic
in the port and it must be testable in a plain JVM in milliseconds, with `android.jar` structurally
out of reach.

```
android/
├── settings.gradle.kts
├── gradle/libs.versions.toml
├── model/                                  # org.jetbrains.kotlin.jvm — NO Android dependency
│   └── src/main/kotlin/com/anitrack/model/
│       ├── wire/          Franchise, FranchisePart, Episode, Airing, enrichment DTOs, envelopes
│       ├── derive/        the freshness ladder, sort keys, resumePart, sections, grafting, Patch<T>
│       ├── time/          TimeAnchor, Formatting, CalendarStore, TemporalCopy
│       ├── copy/          Copy, CopyLibrary, CopyScreens, CopySearch, StateIcon (NOT SF names)
│       ├── color/         Oklab (sRGB ⇄ OKLab, dominantTint, DetailTint.quiet)
│       ├── library/       LibrarySection, ReturnFact, LibraryRowFacts, LibraryDates
│       └── recap/         RecapBeat, RecapDigest
│   └── src/test/kotlin/   golden-fixture replay + table-driven tests
└── app/                                    # com.android.application
    └── src/main/java/com/anitrack/app/
        ├── PreviouslyApplication.kt        @HiltAndroidApp; notification channels; Coil init
        ├── MainActivity.kt                 @AndroidEntryPoint; enableEdgeToEdge; intent routing
        ├── di/                             one @Module @InstallIn(SingletonComponent)
        ├── data/
        │   ├── api/       ApiService (Retrofit), ApiClient (policy), ApiError, RetryPolicy,
        │   │              TokenRefresher, Cancellation
        │   ├── auth/      AuthRepository, TokenProvider, AccountIdentity, AccountDeletion
        │   ├── disk/      LibrarySnapshotStore, RewatchStore, FailedChangeStore, RecentsStore,
        │   │              Prefs (DataStore), ArmedAlertStore, AiringPlanStore
        │   └── export/    LibraryExport + FileProvider share
        ├── state/         AppModel (+Feeds, +Writes, +Search), SyncCenter, SurfacePhase,
        │                  SessionViewModel, LocalAppModel
        ├── design/
        │   ├── theme/     ThemeColor, ThemeSpace, ThemeRadius, ThemeMetrics, PosterSize,
        │   │              ThemeType, ThemeMotion, ShadowToken, Squircle, PreviouslyTheme
        │   ├── chrome/    ChromeSurface (the ONE blur home), ScrollEdgeChrome, ChromeGlassBox
        │   ├── image/     ImagePipeline (Coil), BucketLadder, RemoteImage, PosterSlot,
        │   │              LandscapeArt, blur transformation
        │   ├── palette/   PaletteCache, ArtAdaptiveGround, ArtBackdrop
        │   ├── brand/     PreviouslyMark, BookmarkShape, Wordmark, AccountDisc
        │   ├── control/   press styles, buttons, chips, MarkRing, MarkSplitButton, DrawnCheck,
        │   │              ProgressBar, GroupedList/Row, SectionHeaderRow, AutoSizeText
        │   ├── card/      MediaRow, ShelfCard, BannerCard, ProgressBanner, ArtHeader, scrims
        │   ├── state/     EmptyState, InlineNotice, StaleStrip, RefreshIndicator, SyncBanner,
        │   │              Announce, PassiveTick, QueryProgressBar, HistoryRail, milestones
        │   ├── skeleton/  SkeletonGate + atoms
        │   ├── toast/     ToastHost, ToastView, UndoState
        │   ├── motion/    PageInTransition, pickMotion, LocalReduceMotion
        │   ├── menu/      FranchiseQuickActions
        │   └── haptic/    Feedback (the ONE haptic path)
        ├── nav/           NavKey, TopLevelBackStack, NavGraph, DetailRoute, EpisodeFocus
        ├── ui/
        │   ├── root/      SplashScreen, RootScaffold, MainTabScaffold
        │   ├── auth/      SignInScreen, DevSignInCard
        │   ├── today/     TodayScreen, HeroSlate, TodayVeils, QueueSection, RecapViews
        │   ├── schedule/  ScheduleScreen, AiringCard, Ticker, DayHeader
        │   ├── library/   LibraryScreen, AllTitlesScreen, ContinueShelf, IndexRail, ArrangeSheet
        │   ├── discover/  DiscoverScreen, AddControl, TrendingGrid, NotificationPrimer
        │   ├── detail/    DetailScreen, HeroBlock, NextUpCard, EpisodeList, EpisodeStill,
        │   │              MoviesAndExtras, DetailShelves, VideoSheet, SeasonEpisodesScreen,
        │   │              rewatch/*, WatchHistoryScreen
        │   └── profile/   ProfileScreen, ProfileWash, SyncSection, ExportOptionsScreen
        ├── notify/        EpisodeAlerts, AlarmScheduler, AlertReceiver, ScheduleReminders,
        │                  NotificationChannels, RearmReceiver, LiveUpdateManager,
        │                  LiveUpdateNotification
        └── widget/        [Q22 — NEW FEATURE, not a port; empty unless the widget is scoped in]
                           UpNextWidget, UpNextWidgetReceiver, WidgetTheme, WidgetDataSource
```

`RearmReceiver` is not optional: it is the only thing standing between the alert set and a reboot
(D7b), and it needs `RECEIVE_BOOT_COMPLETED` in the manifest (§4.7). `LiveUpdateNotification` is the
port of `AniTrackWidgets.swift`'s lock-screen card (D9, §4.6) — it is a **notification** layout, not a
widget.

Escalate to a `:design` module only when a screenshot-test harness or a second UI surface (Wear,
Auto) needs the tokens. Feature modules for five tabs buy nothing — there is one shared `AppModel`,
so every "feature" depends on every other one's types.

### 2.3 State holder — the port of `AppModel`

`spec/appmodel.md` is the contract; `research/compose-architecture.md` §3 is the mechanism.

```kotlin
@Stable
class AppModel internal constructor(
    private val api: ApiClient,
    private val sync: SyncCenter,
    private val scope: CoroutineScope,      // SessionViewModel.viewModelScope
) {
    // observable, per field — NEVER one UiState blob
    var library: List<Franchise> by mutableStateOf(emptyList()); private set
    var loading: Boolean by mutableStateOf(true); private set
    var loadError: Boolean by mutableStateOf(false); private set
    var now: Long by mutableLongStateOf(nowMs()); private set          // 20 s tick
    var nowMinute: Long by mutableLongStateOf(floorMinute(now)); private set

    // bookkeeping — plain vars, NOT snapshot state (iOS: @ObservationIgnored)
    private var libraryVersion = 0
    private var libraryIds: Set<String> = emptySet()
    private var reloadSeq = 0
    private var searchSeq = 0
    private var scheduleCache: Pair<ScheduleFeedKey, List<ScheduleDay>>? = null

    val outNow: List<Franchise> by derivedStateOf { computeOutNow(library, now) }
}
```

**Ten rules, each of which has a named bug behind it:**

1. **One `AppModel`, one `@HiltViewModel` (`SessionViewModel`), Activity-scoped.** It constructs and
   owns `AppModel`, `SyncCenter`, `RewatchStore` and calls `AppModel.teardown()` in `onCleared()`.
   Screens take the model from `staticCompositionLocalOf<AppModel>` — the reference never changes, so
   the local itself needs no invalidation tracking. **No per-screen ViewModels.**
2. **Every user-visible field is snapshot state; every bookkeeping field is a plain `var`.** Bumping
   `libraryVersion` must invalidate nothing.
3. **Primitive-specialised builders** — `mutableLongStateOf` for `now`, `nowMinute`, `lastLoadedAt`,
   `prevOpenedAt`; `mutableIntStateOf` for counters. `now` changes every 20 s and is read by every
   countdown.
4. **`now` vs `nowMinute` are two fields.** `now`'s setter writes `nowMinute` only when the minute
   actually changes. Schedule observes `nowMinute`; a 20 s tick must not re-lay it out three times a
   minute.
5. **Derived feeds are `derivedStateOf`**, not recomputed in a composable body. `scheduleDays` is
   additionally memoised on a non-observable cache field keyed `(libraryVersion, nowMinute)` — it was
   rebuilding ~30× per body evaluation on iOS.
6. **Confined to `Dispatchers.Main.immediate`.** There is no background mutation of model state.
7. **Integer sequence tokens** (`reloadSeq`, `searchSeq`) survive; do **not** substitute
   `collectLatest`. `teardown()` bumps both, which must invalidate responses already awaiting.
8. **One conflated lane per `mediaId`** for progress writes: `Channel<ProgressWrite>(CONFLATED)` +
   a collector coroutine, held in `MutableMap<Int, Lane>`. Newest overwrites pending; the in-flight
   request is never cancelled mid-flight.
9. **`SyncCenter` and `RewatchStore` are session singletons** with the same main-thread confinement.
   `SyncCenter.signals` is a closure reading `AppModel`'s observable fields, so every view rendering
   `lastSyncedAt`/`checking` re-evaluates when the stamp moves.
10. **Every model type crossing into a composable is STABLE, or rules 3–5 buy nothing.** This is the
    rule the other nine depend on and the one with no iOS counterpart: SwiftUI re-evaluates a body and
    diffs the result, so an "unstable" struct costs nothing there. Compose **skips** — and only if it
    can prove stability. A `Franchise` inferred unstable makes `MediaRow` non-skippable, and then the
    20 s `now` tick in rule 3 and the 60 s `nowMinute` tick in rule 4 recompose **every row in every
    list on every tab, every tick** — a structurally worse version of the "Today lags" regression,
    because it is caused by the module layout rather than by a bad read site. §2.1's stability
    configuration + `@Immutable` + `kotlinx.collections.immutable` is the fix; **M2's recomposition-count
    test is the proof.** Do not rely on M11's systrace to catch it: a swipe does not move `now`, and
    that criterion watches the screen composable, not the leaves.

**Why this diverges from Google's `StateFlow<UiState>` guidance, stated out loud so nobody "fixes"
it:** that guidance describes a screen-scoped ViewModel transforming repository flows. This is one
model behind five tabs plus a 20-second tick. Collapsing it means every tick allocates a new state
object and wakes every collector, `derivedStateOf`'s equality gate becomes hand-written
`distinctUntilChanged`, and `@ObservationIgnored` has no expression at all. The sanctioned escape
hatch is `StateFlow` **per field** — behaviourally equivalent, buys nothing here.

### 2.4 Threading model

| Concern | Placement |
|---|---|
| All `AppModel` / `SyncCenter` / `RewatchStore` mutation | `Dispatchers.Main.immediate` |
| HTTP | OkHttp's own dispatcher; suspend functions resume on Main |
| Disk (library snapshot, sessions, failed changes, recents) | `Dispatchers.IO`, write-temp-then-`renameTo` for atomicity |
| Image decode + the baked blur transformation | Coil's decoder dispatcher |
| Palette extraction | `Dispatchers.Default`, off a separate 64 px `allowHardware(false)` request |
| Alarm receiver work | `goAsync()` + `Dispatchers.IO`, bounded |
| Glance widget | its own process/session — reads the app's persisted snapshot directly (same process, no App Group problem) |

**`TokenProvider` must be thread-safe, not main-confined.** On iOS every token method is a
`nonisolated` wrapper hopping to `@MainActor` because Clerk is `@MainActor`. Forcing the Kotlin
provider onto `Dispatchers.Main` would serialise the whole transport behind the UI thread. Hop to
Main only where the Clerk SDK actually demands it.

**Cancellation inverts.** iOS *swallows* cancellation at the consumer. Kotlin must rethrow
`CancellationException` and suppress only the UI effect. The predicate must additionally recognise
OkHttp's cancelled-call `IOException` (`"Canceled"`) and `InterruptedIOException`
(`spec/networking-auth.md` §6).

### 2.5 Navigation

Navigation 3 (`androidx.navigation3:navigation3-{runtime,ui}:1.1.7`), because nav3's model —
*"the back stack is a `List` you own"* — is literally the iOS model (`MainTabView` holds one
`NavigationPath` per tab).

```kotlin
sealed interface NavKey
enum class AppTab : NavKey { Today, Schedule, Library, Discover }   // rawValue order preserved
data class DetailRoute(val id: String, val focus: EpisodeFocus? = null) : NavKey
data class SeasonEpisodes(val franchiseId: String, val mediaId: Int, val focusEpisode: Int?) : NavKey
data class WatchHistory(val franchiseId: String) : NavKey
```

**Shell structure — decided, because the design system depends on the answer.** A single `NavDisplay`
over one flattened back stack composes **only the top entry**, so exactly one tab screen would be alive
at a time. That contradicts §3.4's `PageInTransition` row verbatim ("once per tab, never reset … **keep
all four tab screens composed**") and silently destroys every non-saveable `remember` in the three
inactive tabs on every switch — the `ScrollOffset` holders §3.7 requires, Today's measured
`heroCopyHeight` (which §4.5 makes responsible for the scrim stops **and** the hero height **and** the
title hand-over), the palette result, `AsyncImage` request state. Tab switching would replay page-in and
re-measure the hero every time, where SwiftUI's `TabView` keeps all four alive.

**The port takes option (a): four `NavDisplay`s, one per tab, all kept composed inside a host `Box`,
with only the selected one visible** (`Modifier.graphicsLayer { alpha = if (selected) 1f else 0f }` +
`zIndex`, not `if (selected)`, so the others keep their composition). This matches `TabView`, keeps
`PageInTransition` honest, and keeps every per-tab `remember` alive. It costs memory: four live screens,
four image request sets. That is the trade, taken deliberately. The rejected option (b) — one flattened
`NavDisplay` with all cross-switch state hoisted onto `AppModel` or a tab-keyed holder — would require
deleting "keep all four tab screens composed" from §3.4 and re-specifying page-in from scratch; if the
memory cost of (a) ever proves unacceptable, that is the shape of the retreat, not a half-measure.

- **Per-tab back stacks:** `LinkedHashMap<AppTab, SnapshotStateList<NavKey>>`, one list feeding each
  tab's own `NavDisplay`. Adapted from the official `TopLevelBackStack` recipe, with two deliberate
  departures from `research/compose-architecture.md` §5.4: it is **not flattened into one display**
  (above), and **`pop()` at a tab root never removes the tab's stack** or its `SaveableStateHolder`
  slot (D26).
- **The stack is SAVEABLE.** The recipe holds it in a plain `remember { TopLevelBackStack(TodayKey) }`
  — which survives nothing — even though the same note says the keys are `@Serializable` "so the stack
  survives process death via `rememberNavBackStack`". Use `rememberNavBackStack` per tab (or
  `rememberSaveable` with an explicit `Saver` over the serialisable keys). **This is not theoretical:**
  §2.6 declares no `android:configChanges`, portrait lock makes rotation moot, but a **font-scale change
  is a configuration change**, and TOOLCHAIN.md's QA recipe and M14's capture matrix both drive
  `adb shell settings put system font_scale 1.3` on every screen. With a plain `remember` the Activity
  is recreated and every capture bounces back to Today's root, making the entire AX half of the matrix
  uncapturable as scripted. It also makes §2.5's `pendingOpen`-survives-process-death promise vacuous:
  the stack that would consume it is not persisted at all.
- **Entry decorators — pass all three, in order, or pass none.** `NavDisplay`'s `entryDecorators`
  parameter **replaces** the default list rather than adding to it, and the skeleton at
  `research/compose-architecture.md` §5.5 passes only `rememberSaveableStateHolderNavEntryDecorator()`
  and `rememberViewModelStoreNavEntryDecorator()` — dropping **`rememberSavedStateNavEntryDecorator()`**,
  which is what gives each entry a `SavedStateRegistry` so `rememberSaveable` inside a screen survives
  recreation and process death. Under rule 1 of §2.3 ("no per-screen ViewModels") that decorator is the
  **only** mechanism carrying per-screen state at all: every screen's scroll position, sheet state,
  search text and season selection. Order: saveable-state-holder → savedstate → viewmodel-store.
- **Re-select pops to root:** truncate that tab's list to its first element. For `.library`,
  additionally bump `libraryPops` — All titles is an *item destination*, not a path entry, and
  clearing the list alone left it standing (the tap did nothing). Model All titles as a **real nav
  key** on Android and delete `libraryPops`; if that is not done, port the counter.
- **Tab change fires exactly one `.selection` haptic. Navigation is otherwise silent** — `openDetail`
  has no feedback call.
- **Detail is a plain push.** `transitionSpec`/`popTransitionSpec` = the platform forward slide.
  `predictivePopTransitionSpec` drives the gesture. **No shared element** (D15).
- **System back at a tab root finishes the Activity** (D26). Never `topLevelStacks.remove(...)`.
- **Alert-tap route:** `PendingIntent` → `MainActivity.onNewIntent` → a single-shot event channel →
  select `Today` and **replace** its list with `[DetailRoute(id)]` (never append). Consumed exactly
  once; a recreation must not re-push. `pendingOpen` survives process death via `SavedStateHandle`.
  **Two things this route silently depends on, both of which must be declared (§2.6/§4.7):**
  `android:launchMode="singleTop"` on `MainActivity`, and `PendingIntent.FLAG_IMMUTABLE` (mandatory
  from API 31). With the default `standard` launch mode a notification tap on a **warm** app creates a
  second `MainActivity` instance, `onNewIntent` never fires, and the whole route does nothing — while a
  cold-start test still passes, because a cold start reads `onCreate`'s intent. M6's exit criterion
  therefore tests the **warm** tap explicitly. `research/notifications-liveupdates.md` §3.2 says
  `singleTop`; `research/widgets-glance.md` §7.1 says `singleTask` — **`singleTop` wins**; the widget
  note is errata-patched (§9.2), since `singleTask` would additionally clear the tab stacks on every tap.
- **Schedule-routed `focus`** pushes the season list once (`focusConsumed`); it used to re-push on
  every pop and trap the user.
- **Cross-tab jumps:** `libraryRequest = AllTitlesRoute(status, unwatchedOnly)` then select Library;
  `onAddShow` sets `searchFieldRequested = true` and selects Discover. Today's "N updates" passes
  **no status** — it counts `outNow`, which is any status.
- **Pushed-screen scaffold** (`pushedScreenChrome`) is applied at the destination wrapper, not per
  screen, so every future push inherits the bottom chrome and the 76 dp content padding.

### 2.6 Build configuration

- `buildConfigField` per build type for `API_BASE_URL`, `CLERK_PUBLISHABLE_KEY`, `PRIVACY_POLICY_URL`,
  `TERMS_URL`, `SUPPORT_EMAIL`. Reproduce `AppConfig`'s validation exactly: trim; blank or containing
  `REPLACE_ME` → `null`; a URL must parse **and** have a scheme; `supportEmail` must contain `@`;
  `isClerkConfigured = key.startsWith("pk_") && !key.contains("REPLACE_ME")`. A placeholder must
  never ship as a broken legal link.
- `isLocalBackend` parses **by address, never by string prefix** — 4 dot-components, all `Int`, all
  `0..255`, then `10.*` / `192.168.*` / `172.16..31.*`; plus `localhost`, `127.0.0.1`, `::1`,
  `*.local`. `10.example.com` is an ordinary internet host and a `hasPrefix` test would release a
  `dev:` bearer toward it.
- Debug flavour default `API_BASE_URL = http://10.0.2.2:8787` (the emulator's host route) with the
  scoped `network_security_config.xml`.
- `android:screenOrientation="portrait"`, `android:isLightTheme="false"`, `forceDarkAllowed="false"`,
  no `values-night/`, never call `isSystemInDarkTheme()`. **These four guard the platform, not
  Compose** — Compose's own scheme is D32/§3.1's job.
- **`android:launchMode="singleTop"` on `MainActivity`** (§2.5 — the alert-tap route dies without it),
  and every `PendingIntent` built with **`FLAG_IMMUTABLE`** (mandatory from API 31).
- **No `android:configChanges`.** A font-scale change recreates the Activity by design; the nav stacks
  and per-screen state survive it because they are saveable (§2.5), not because recreation is suppressed.
- `composeCompiler { stabilityConfigurationFile = … }` covering `com.anitrack.model.**` (§2.1).
- Backup: **both** `android:fullBackupContent="@xml/backup_rules"` (≤30) and
  `android:dataExtractionRules="@xml/data_extraction_rules"` (31+), each excluding the library snapshot
  (D25).
- `enableEdgeToEdge(SystemBarStyle.dark(TRANSPARENT), SystemBarStyle.dark(TRANSPARENT))`; insets taken
  **per surface** (`contentPadding` for scroll containers, `windowInsetsPadding` for fixed chrome).
- Debug intent extras mirroring the iOS launch args, so one capture script drives both platforms:
  `openTab`, `openDetail`, `openAllTitles`, `openProfile`, `recapDemo`, `calmDemo`, `scheduleEarlier`,
  `scheduleFilter`, `scheduleHideWatched`, `detailAnchor`, `detailTrailer`, `detailOpenRelated`,
  `devSignInId`, `devSignInAuto`.

---

## 3. Design system port

Authority: `spec/design-tokens.md`, `spec/primitives.md`, `spec/primitives-states.md`,
`spec/chrome-images.md`, `research/typography-icons.md`, `research/motion-haptics.md`,
`research/images-palette.md`.

### 3.1 `PreviouslyTheme` — the token layer

**Do not adopt `MaterialTheme` as the app's theme.** Pull material3 in only for behavioural
components and wrap each so no screen sees an M3 type.

**The allowed set is CLOSED. These six, and nothing else:** `Scaffold` (insets only),
`ModalBottomSheet`, `AlertDialog`, `NavigationBar` **as a chassis**, `DropdownMenu` **as an anchored
popup**, and `Switch` **only through `PreviouslySwitch`** (§3.4).

**Never** `FloatingActionButton`/`ExtendedFloatingActionButton`, `BottomAppBar`,
`SearchBar`/`DockedSearchBar`, `Card`/`ElevatedCard`/`OutlinedCard`, `ListItem`, `TopAppBar`/
`CenterAlignedTopAppBar`/`MediumTopAppBar`/`TopAppBarDefaults.*ScrollBehavior`,
`SingleChoiceSegmentedButtonRow`/`SegmentedButton`, `Button`/`TextButton`/`OutlinedButton`/
`FilledTonalButton`/`IconButton`, `Snackbar`/`SnackbarHost`, `LinearProgressIndicator`/
`CircularProgressIndicator`, `Divider`/`HorizontalDivider`, `Chip`/`FilterChip`/`AssistChip`,
`DatePicker`/`DatePickerDialog` (unless Q23 says otherwise), or bare `Surface`. **A screen that
reaches for one of these needs the app's own primitive instead — §3.4 has it.** Three of these have
no named Android antagonist anywhere else in the plan and are the reflex substitutes that would
quietly dissolve the design system: a **FAB** is where an Android engineer puts Discover's and
Library's primary add action, on the two screens whose entire law is *one hugging button*; **`Card`**
is the reflex for `ShelfCard`/`BannerCard`; **`ListItem`** is the reflex for `MediaRow`. This list is
wired into the M5 review checklist.

**`TopAppBar` is banned outright**, and two specs that prescribe it (`spec/discover.md` §3.1, "a
`TopAppBar` with `title = "Search"`", and `spec/chrome-images.md` §1.2/§9.4's "two-line `TopAppBar`
title slot") are errata-patched (§9.2). Reason: M3 `TopAppBar` interpolates
`containerColor → scrolledContainerColor` (a `surfaceContainer` tonal-elevation overlay) as its scroll
behaviour progresses — **a second, uncontrolled hardening layer stacked on top of `ScrollEdgeChrome`'s
0.74-over-blur, on every screen, computed from a Material curve nobody chose**, which is exactly the
law "bars are material to their bottom edge, never opaque canvas" forbids. Its title also draws at
`MaterialTheme.typography.titleLarge` rather than a `ThemeType` token, and its `windowInsets` handling
double-counts against §2.6's per-surface inset rule. **The bar is an app-drawn `Box`:** title in a
`ThemeType` token, actions as ripple-free `clickable` glyphs, inset from `WindowInsets.statusBars`,
sitting inside `ChromeSurface`'s band. **`ScrollEdgeChrome` is the only thing in this app whose
appearance changes with scroll offset.**

**The colour scheme is hand-written and complete (D32).** `MaterialTheme(...)` with no `colorScheme`
argument defaults to **`lightColorScheme()`**, so an unmapped role is not a subtle tint error — it is a
light-on-white tonal slab in a dark-only app. `PreviouslyTheme.kt` constructs a full
`darkColorScheme(...)` mapping **all 30+ M3 roles** onto `ThemeColor` **before** any material3
component can render:

| M3 role(s) | ← `ThemeColor` |
|---|---|
| `primary` / `onPrimary` | `interactive` / `canvas` |
| `secondary` / `onSecondary` / `tertiary` / `onTertiary` | `interactive` / `canvas` — **never `accent`** |
| `primaryContainer` / `secondaryContainer` / `tertiaryContainer` | **`Color.Transparent`** — `secondaryContainer` is the `NavigationBar`'s selected-item indicator pill; transparent is how the pill is prevented from drawing at all |
| `background` / `onBackground` / `surface` / `onSurface` | `canvas` / `textPrimary` |
| `surfaceVariant` / `onSurfaceVariant` | `surfaceFlat` / `textSecondary` |
| `surfaceContainerLowest` → `surfaceContainerHighest` | the app's five lifts in order: `surfaceFlat`, `surfaceFlat`, `surfaceRaised`, `surfaceRaised`, `surfaceFloating` |
| `surfaceTint` | **`Color.Transparent`** — kills M3 tonal elevation everywhere at once |
| `inverseSurface` / `inverseOnSurface` / `inversePrimary` | `surfaceFloating` / `textPrimary` / `interactive` |
| `outline` / `outlineVariant` | `stroke` / `separator`-equivalent hairline |
| `error` / `onError` / `errorContainer` / `onErrorContainer` | `destructive` / `canvas` / `Color.Transparent` / `destructive` |
| `scrim` | the app's own scrim alpha, not M3's 32 % black |

**`MaterialTheme.shapes` is mapped to `ThemeRadius`** (`extraSmall`→4, `small`→8, `medium`→12,
`large`→16, `extraLarge`→22, with `Squircle` wherever ≥ 16 dp), so no dialog or sheet arrives with
M3's 28 dp `ExtraLarge` corner.

**Never `dynamicDarkColorScheme` / `dynamicLightColorScheme`, never `lightColorScheme`, never
`isSystemInDarkTheme()`. The scheme is a constant.** "Never Material You" was previously written only
for the Glance widget, which left the app itself unprotected against the Android Studio template's
default dynamic-colour theme.

**`LocalControlInk` governs app-drawn ink only.** Every material3 component takes its colours as an
explicit `*Defaults.colors(...)` argument at the wrapper — **a component that inherits from
`MaterialTheme.colorScheme` is a bug**, caught by F10's lint rule (b). The two mechanisms are not
interchangeable: a `CompositionLocal` is invisible to `Switch`, `AlertDialog`'s buttons and
`DropdownMenuItem`, all of which read the scheme directly.

**No ripple, and the four components that will not let you turn it off.** D2 requires
`indication = null` everywhere. Provide `LocalIndication = NoIndication` and
`LocalMinimumInteractiveComponentSize = Dp.Unspecified` at the `PreviouslyTheme` root — **and
document that the local alone does not reach a component that constructs its own indication
internally.** Four do: `NavigationBarItem`, `DropdownMenuItem`, `Switch` and the `ModalBottomSheet`
drag handle. Each therefore gets a ripple-free app-drawn replacement: a `NavigationBar` **chassis**
with app-drawn items, a `DropdownMenu` whose items are plain `clickable` `Row`s, `PreviouslySwitch`,
and `dragHandle = null`. (The minimum-interactive local matters separately: M3 enforces a 48 dp
touch inflation around its components, which would silently inflate the 32/34 dp chip capsules
§3.4 forbids inflating.)

```
design/theme/
  ThemeColor.kt      36 tokens (spec/design-tokens.md §1.2; ThemeTokens.swift declares 36 statics,
                     canvas … controlSheen) — object with val Color
  ThemeSpace.kt      x0_5=2 … x16=64 (Dp)
  ThemeRadius.kt     episodeStill 8 … focusCard 24 (Dp)
  ThemeMetrics.kt    gutter/sectionGap/…/rootWashIntensity + scrollSample()
  PosterSize.kt      the 10 slots: size, radius, shadow
  ThemeType.kt       26 TypeToken(fontFamily, weight, sp, letterSpacing.em, features)
                     (16 in the enum + 10 in `extension ThemeType`, ThemeTokens.swift:540.
                     spec/design-tokens.md §1.5's table carries a spurious `UITabBarItem` row —
                     that is a bar-appearance setting, not a ThemeType token. Do not port it as one.)
  ThemeMotion.kt     13 curves + pickMotion(token, reduceMotion)
  ShadowToken.kt     5 tokens + Modifier.shadowToken()
  Squircle.kt        continuous-corner Shape
  PreviouslyTheme.kt CompositionLocalProvider chain
```

CompositionLocals: `LocalControlInk` (default `interactive`, → `accent` inside the `NavigationBar`,
→ `interactive` again inside each tab's nav host), `LocalReduceMotion`, `LocalReduceTransparency`,
`LocalDifferentiateWithoutColor`, `LocalIsAX` (`fontScale >= 1.3f`), `LocalHaptics`,
`LocalListTrailingInset` (the A–Z rail lane), `LocalAppModel`.

**Four token classes need real engineering, not a value:**

| Token class | Implementation | Notes |
|---|---|---|
| **Continuous corners** | `Squircle(radius): Shape` emitting a superellipse path (n ≈ 5). | `RoundedCornerShape` is a circular arc and reads visibly rounder at r22 on a 104-dp card — the app's most-repeated object. Below ~12 dp it does not matter; use `RoundedCornerShape` there to save the path. |
| **Shadows** | `Modifier.shadowToken(token, shape)` → `drawBehind { drawIntoCanvas { … Paint.asFrameworkPaint().setShadowLayer(radius, 0f, dy, color) } }` on a hardware layer. | Compose's `Modifier.shadow` is elevation-driven and honours a custom colour only at API 28+, with no radius/offset control. Five tokens, ~40 call sites — build it once. Radius is **calibrated, not converted** (D22). |
| **`minimumScaleFactor`** | `AutoSizeText(text, style, minScale)` on `BasicText(autoSize = TextAutoSize.StepBased(minFontSize = size × factor, maxFontSize = size))`, with a `TextMeasurer` bisection fallback. | Nine floors in the app: 0.6 (AccountDisc), 0.7 (Today headline, Schedule numeral), 0.78 (MarkSplitButton), 0.82 (ShelfCard, BannerCard), 0.85 (SectionHeaderRow, hero title), 0.9/0.92 (Detail). **Never substitute an ellipsis** — "the hero may never ellipsize the one name the screen exists to show". |
| **Negative padding + zIndex** | `Modifier.overhangVertical(dp)` — a custom `layout {}` that measures tall and reports short — plus `Modifier.zIndex(1f)`. | `SectionHeaderRow` (−10 / −12) and `InlineNotice`'s Retry (−12 / −4). The header must win taps in the overlap band against siblings laid out after it; **re-verify by test**, Compose hit-tests in a different order. |

### 3.2 Typography

- **Outfit** as a single variable file `Outfit[wght].ttf` in `res/font`. minSdk 26 *is* the
  `FontVariation` floor, so no gate. Declare five `Font()` entries with **explicit
  `variationSettings`** — the 4-arg `Font(resId, weight, style, loadingStrategy)` overload hard-codes
  an empty `FontVariation.Settings` and silently fake-bolds.
- **The annotating face** is `FontFamily.Default` (Roboto) at identical sizes and weights. The
  Outfit-speaks / grotesque-annotates contrast survives; metrics, x-height and `tnum` figures do not.
  Every SF-set line (`metadata`, `metadataEmphasis`, `sectionLabel`, `caption`, `numberXL`, `time`,
  `prose`, `rowMeta`, `rowMetaLead`, `shelfCaption`) needs a visual check. See §7 Q4.
- **Tracking:** `letterSpacing = (tracking_pt / size_pt).em` — one convention, recorded here, applied
  to all 26 tokens. `sectionLabel`'s +1.0 on 11 sp is the most visible one.
- **The full 15-slot M3 `Typography` is mapped onto the nearest actual `ThemeType` tokens** — size,
  weight, `letterSpacing` in `.em` **and** `fontFeatureSettings` — not merely re-faced to Outfit.
  Mapping only the face leaves Material's metrics intact, so a slipped-through component still draws
  `bodyLarge` at 16 sp / 24 line-height / 0.5 sp tracking, none of which is a token, on a plan whose
  F3 unit is "sizes in sp equal to the iOS pt value". Suggested mapping: `displayLarge/Medium/Small`
  → `displayXL`/`displayL`/`showTitleL`; `headlineLarge/Medium/Small` → `heroTitle`/`showTitleM`/
  `sectionTitle`; `titleLarge/Medium/Small` → `sectionTitle`/`rowTitle`/`shelfTitle`;
  `bodyLarge/Medium/Small` → `body`/`prose`/`metadata`; `labelLarge/Medium/Small` → `button`/
  `listAction`/`caption`. **Restate the rule out loud:** a component drawing from
  `MaterialTheme.typography` is **a defect to be found** (F10 lint rule (b)), not a supported path —
  the mapping exists so that the failure is legible rather than invisible. The 15 mapped slots are
  asserted by the M2 `ThemeType` token test alongside the 26 real tokens.
- **No font-scale cap, and none is inherited.** Compose's vendored non-linear curve (identical on API
  26 and 36) already lands every token 7–14 % smaller at 2.0 than the same token at iOS's
  `accessibility2` cap. Do not add a clamp on top of it. **`fontScale` is not clamped by the platform
  either** (D6b) — the Pixel slider stops at 2.0, OEM sliders differ, and
  `settings put system font_scale 3` takes effect. Above 2.0 the F1 fixed dimensions stay fixed and
  text wraps into taller rows; nothing clips or overlaps. Captured in M14.
- `sectionLabel` is uppercased at render (`text.uppercase()`), not a small-caps feature.

### 3.3 Icons

Full 42-row substitution table: **`docs/android-port/spec/icon-mapping.md`** — that file is
authoritative; this section carries only the decisions and the vendoring recipe.

**`icon-mapping.md` is the ONLY icon authority — no spec's SF-Symbols risk row is normative.** That
covers the family (**Rounded**), the axes (**opsz 24 / GRAD −25 / wght 500 or 400 / FILL**) and the
vendoring form (**committed `VectorDrawable` XML, never `material-icons-extended`, never an icon
font**). Four specs carry their own contradictory mappings in a different notation and an implementer
working screen-by-screen reads the spec in front of them, not the mapping file: `spec/discover.md`
§9.2 lists `Icons.*` CamelCase names (`Search`, `NorthWest`, `ChevronRight`, `FilterList`, `Cancel`)
— that is the bundled `androidx.compose.material.icons` Filled/Outlined set, i.e. the wrong optical
family, GRAD 0, no auto-mirrored variant unless spelled `AutoMirrored.*`, and several of those names
exist **only** in `material-icons-extended`, which this plan bans; it also says "use the variable
font, not the static drawables", the exact opposite of the recipe below. `spec/schedule.md` §9.1,
`spec/chrome-images.md` §9.5 and `spec/detail.md` §12.3 give three further spellings. All four are
errata-patched to point here (§9.2). §8 rule 9 restates the rule for agents.

**Vendoring:** static `VectorDrawable` XML from `google/material-design-icons`, **Rounded** optical
family, **opsz 24**, **GRAD −25** (Google's own prescription for light-on-dark, which is every icon
in this dark-only app), **wght 500** where iOS draws `.semibold` and **wght 400** where it draws
`.regular`, **FILL 1** where the SF name ends in `.fill`. Vendor once, commit the XML, throw the
checkout away. **No `material-icons-extended`** (frozen at 1.7.8, unpublished since Compose 1.8) and
**no icon font**.

The eight that are a decision rather than a lookup:

| SF | Decision |
|---|---|
| `arrow.triangle.2.circlepath` | `sync`, **not** `refresh` — it means rewatch/restart, not reload. |
| `chevron.down` | `keyboard_arrow_down`, not `expand_more` — the metric-matched one at small sizes. |
| `chevron.forward` | `chevron_right` + `android:autoMirrored="true"`. SF mirrors under RTL automatically; Material does not. |
| `chevron.up.chevron.down` | `unfold_more`. Load-bearing: this is the season picker's affordance and must stay visually distinct from `chevron_right` (push vs menu-in-place). |
| `dot.radiowaves.left.and.right` | ⚠ `sensors` is closest; `podcasts` is nearer visually but means audio. Carries the Now Bar's meaning — **consider a custom vector**. |
| `wifi.exclamationmark` | ⚠ weak match. `signal_wifi_statusbar_not_connected` is closer in meaning than `wifi_tethering_error`. Verify visually. |
| `square.and.arrow.up` | `share` (D3), not `ios_share`. |
| `arrow.up.right` / `arrow.up.backward` | **`open_in_new`** — decided, D29. `icon-mapping.md` rows 2–3 said `arrow_outward` and are errata-patched (§9.2). |
| `curlybraces`, `text.append`, `rectangle.stack`, `line.3.horizontal.decrease` | Need custom vectors or careful re-picking; check optical weight at `textTertiary`. |

**Non-symbol assets:** the four tab icons are `icon/navbar/vector/*.svg` with `viewBox="-3 -3 30 30"`
— translate every path by **+3,+3** (VectorDrawable has no negative viewport origin), viewport 30,
default 24 dp, stroke 1.5, round caps/joins, colour from `LocalControlInk`. **There are no splash
PNGs to port:** `SplashLayerCard`, `SplashLayerPeek` and `SplashLayerProgress` are referenced nowhere
in `ios/Sources` or `ios/project.yml` — `SplashView.swift:199` draws `PreviouslyMark(width: markWidth,
progress:, finish: .hero)`, a vector path, and `spec/profile-shell.md` §4.2 agrees. **The splash's only
raster dependency is the app icon; the mark is drawn by `design/brand/PreviouslyMark.kt`.** App icon:
adaptive (background + foreground with midground merged) **plus a monochrome layer that does not exist
yet and must be drawn** (§7 Q19).

### 3.4 Component inventory — iOS primitive → Compose counterpart

| iOS | Compose | Complexity | Traps |
|---|---|---|---|
| `SurfaceLevel` / `.surface(_:radius:)` | `Modifier.surface(level, radius)` | M | Order is `background(ground)` → `clip(Squircle)` → `border(edge)` → `shadowToken`. `.plate`/`.raised` grounds are white **α lifts**, never `surfaceFlat`/`surfaceRaised` fills. |
| `ArtAdaptiveGround` | `Box` with 4 layered brushes | M | `endRadius: 320` is **points**, so `320.dp.toPx()`; centre `Offset(0.16f·w, 0.02f·h)`; black veil **0.30**, not 0.44. |
| `handoffGround` | `Modifier.handoffGround(tint, radius = 24.dp)` | S | Must sit on the **surviving container**, not on either card, or the canvas flashes through the gap. |
| `PosterSlot` | `PosterSlot(url, slot)` | M | `.fit` never `.fill`; the fit-snap rule (fill when `abs(aspect/target − 1) ≤ 0.08`) is manual; palette tint at **0.60**; edge is `posterEdge` (9 %) never `stroke`; `accessibilityHidden`. No blurred backfill. |
| `LandscapeArt` | `LandscapeArt(url, portraitSource)` | L | The portrait composite (blurred 160-px ground at blur 28 + black 0.32, sharp `.fit` on top with a black-45 % r8 y4 contact shadow) is **baked into the bitmap** by a Coil `Transformation`, so it needs no API gate. |
| `BannerCard` | `BannerCard(...)` | M | One geometry: 104 dp tall, r22. Title `lineLimit(1..2)` + `minScale 0.82`, **never truncated**. Caption amber only when `lead != null`. |
| `ProgressBanner` | `ProgressBanner(...)` | M | **16:9 by ratio, never a fixed height.** 56-dp scrim bottom-aligned; bar inset 12/12. |
| `ArtHeader` | `ArtHeader(...)` | L | `focus` is an alignment passed to the image; drift 1.07× / 24 s on the **sharp layer only**, 80 ms delay, off under Reduce Motion. Decode 2048 for the portrait sharp layer, 1024 ground, 1536 landscape. |
| `ArtScrim` / `HeroTopVeil` / `HeroCopyScrim` | `Brush.verticalGradient` with the exact stops | S | `HeroCopyScrim` stops are in **points off the measured copy height**, not fractions. Full canvas at location 1 is mandatory. |
| `MediaRow` | `MediaRow(...)` | L | Chevron is a **fixed 11-dp column**; separator inset by `slot.width + artGap`; `dimmed = 0.72` as **one opacity on the whole row**; `lead` above `meta`; accessibility label spelled out so the chevron is never spoken. |
| `ShelfCard` | `ShelfCard(...)` | M | Title takes its **wrapped** height whatever the row proposes (`maxLines = 2` + `wrapContentHeight(unbounded = true)`); nothing is reserved under it. |
| `shelfScroller` | `LazyRow` + horizontal fade mask | M | `CompositingStrategy.Offscreen` + `BlendMode.DstIn`; mask padded **−24 dp vertically** so it does not shear the posters' shadow into a line. `clip = false`. Skipped at AX. |
| `SectionHeaderRow` | `SectionHeaderRow(...)` | M | See §3.1 overhang. The title **is** the button; there is no "See all" word. Count on the title's baseline in `textTertiary`, `tnum`. |
| `SectionLabel` / `OverArtLabel` | Composables | S | Eyebrow only. `OverArtLabel` is a hard 24-dp capsule that does **not** grow with type size. Dots are 4 dp (SectionLabel) vs 5 dp (OverArtLabel). |
| `GroupedList` / `GroupedRow` | Composables | M | The `.toggle` case must be a real `Modifier.toggleable(role = Role.Switch)` row with `mergeDescendants` — a switch inside a button loses its trait and its value. |
| `ProgressBar` | `Canvas` | S | 3 dp, **3-dp minimum fill**, wordless, `accessibilityHidden` unless `spoken != null`. |
| `DrawnCheck` | animated-width clip | S | **Mounted unconditionally**; collapse to zero width, never conditionally insert. Nothing else may touch its opacity. |
| `MarkRing` | `MarkRing(...)` | M | 44 dp target, 22 dp ring at 1.5 dp; three ink styles; numeral at 9/7 sp `tnum`; `.settled` is the shipped style. |
| `MarkSplitButton` | Custom composable | L | One 48-dp capsule, **two independent 44-dp targets**, 1×24 divider, per-half press darkening. Label crossfade via `AnimatedContent(fadeIn togetherWith fadeOut)` — **never** an interpolating/shared-element transition. Menu half dims to 0.45 and goes accessibility-hidden when committed. |
| Button/press styles (12) | `Box`/`Row` + `Modifier.surface(level, radius)` + `Modifier.clickable(interactionSource, indication = null)` + the app's press modifier | M | **Never M3 `Button`/`TextButton`/`OutlinedButton`/`FilledTonalButton`/`IconButton`, and never `ButtonColors`.** `ButtonColors` is the M3 `Button` API, and M3 `Button` brings its own ripple, its own 40 dp minimum height, its own `contentPadding` and `MaterialTheme.shapes` corners — the previous "`Modifier` + `ButtonColors` wrappers" instruction contradicted "`indication = null` everywhere (D2)" in the same cell. `strokeBorder` semantics = `Modifier.border` after `clip`. `TertiaryButtonStyle2` has **no** animation on its press. |
| Chips (`FilterChipStyle`, `ChipButtonStyle`) | Composables — **never M3 `FilterChip`/`Chip`/`SegmentedButton`** | S | 32/34-dp visible capsule inside a 44-dp target — do not inflate the capsule (this is why `LocalMinimumInteractiveComponentSize` is unset at the theme root, §3.1). Unselected chips carry no stroke. |
| **Search scope bar** | The app's own chip row (`FilterChipStyle`), inside `AnimatedVisibility(query.isNotEmpty())` | S | `spec/discover.md` §3.2/§9.1 prescribes an M3 `SingleChoiceSegmentedButtonRow` and is **errata-patched** (§9.2): it would arrive with an outlined container, a `secondaryContainer` selected fill and the sliding leading check icon, on the same screen as the app's own chips — **two chip anatomies in one app**, with a selected-state encoding that is neither amber nor the app's. The selected scope is **amber**: an active filter is STATE (design-tokens §1.3 rule 4). Scopes appear `.onTextEntry`, exactly as on iOS. |
| **`PreviouslySwitch`** | Wrapper over M3 `Switch` with a hard-coded `SwitchDefaults.colors(...)` | S | **The only permitted switch construction in the app.** `checkedTrackColor = accent`, `checkedThumbColor = onAccent`, `checkedBorderColor = Transparent`, `uncheckedTrackColor = surfaceRaised`, `uncheckedThumbColor = textSecondary`, `uncheckedBorderColor = stroke`. Amber is legal here and only here on a control: a toggle whose value means STATE carries `accent` (`spec/primitives.md` §7.4; `spec/profile-shell.md` §8.1 makes Haptics amber). Without this every switch inherits `primary` = `interactive` and comes out **ink**, silently losing the state reading. **All five toggles** use it: Notifications, Haptics, Reduce transparency (D12), Differentiate without colour (D13), and the quick-action menu's films toggle. Ripple-free (`interactionSource` + app press style over a `Switch` with `indication` suppressed at the row). |
| **`Spinner(size, tint)`** | `Canvas` sweep arc | S | **The Android reflex here — `CircularProgressIndicator` — defaults its colour to `MaterialTheme.colorScheme.primary` and, in material3 1.4, draws the Expressive indicator with a visible track and a leading gap:** a visibly different object from iOS's `.mini`/`.small` spinner, in the wrong ink, including on the delete-account row where the ink is load-bearing. Plain sweep arc, no track, no gap. **`tint` is a required argument, never defaulted.** Six specified call sites and their inks: Profile's sync footnote `textTertiary` (`spec/profile-shell.md` §7.3, §9.2), sign-out `textSecondary` (`spec/networking-auth.md` §10.2), delete-account `destructive` (`spec/networking-auth.md` §10.4, `spec/profile-shell.md` §8.4), Library's toolbar refresh spinner, Detail's inline refresh, Discover's query progress. Three sizes (mini/small/regular) mapped to explicit dp. Goes in the M5 Component Gallery. |
| **Pull-to-refresh** | M3 `PullToRefreshBox` for the **gesture and `distanceFraction` only**, `indicator = {}` | M | `spec/discover.md` §9.5, `spec/today.md` §17.2 and `spec/primitives-states.md` §11.1 all reach for `PullToRefreshBox` at its defaults, whose indicator is a Material tonal circle drawing its arc in `primary` — a Material object on the two highest-traffic screens. Pass an empty (or `RefreshIndicator`-drawn) indicator; the **visible** refresh affordance stays the app's 400 ms in-bar spinner. R24's armed-haptic rule (fire once at 80 dp **while a finger is down**, re-arm below 0.3×) attaches to that state, not to the default indicator. |
| `EmptyState` | `EmptyState(copy, prominence, primary, secondary)` | M | `ContentUnavailableView`'s anatomy on the canvas: a 44-dp tertiary symbol, a title, one sentence, **ONE hugging button** (a recovery is the quiet capsule, a next step is the amber one) — no plate, no glyph tile, no bloom, no `ambient:`. Keep the debug assertion: a copy that declares a label with no handler must fail the debug build. **Never a `FloatingActionButton` beside it** (§3.1's closed set): Discover's and Library's empty states are exactly where the Android reflex puts one, producing a second, floating, `primaryContainer`-tinted action on a screen whose entire law is one hugging button — and then a permanently docked FAB over shelves the design keeps clear. |
| `InlineNotice` | Composable | S | A footnote line, never an alert box. H→V swap at AX. |
| `StaleStrip` / `RefreshIndicator` / `freshness` | Composables (over `Spinner`) | M | Spinner only after 400 ms, in the bar, suppressed while a native pull drives. |
| **Rewatch start-date row** | `GroupedRow` (min height 56, padding 14/10) + **Q23's answer** for the field itself | M | `spec/detail.md` §10.2/§10.6 specifies a compact `DatePicker` inside a `GroupedRow` with `.tint(accent)`. Android's M3 `DatePicker`/`DatePickerDialog` is a full Material calendar surface — its own headline, Material typography, a `primary` selection ring, 28 dp corners, a mode toggle — dropped inside the one sheet the design system otherwise owns entirely. **Q23 decides** app-built field vs a themed `DatePickerDialog` with every `DatePickerDefaults.colors` role mapped onto `ThemeColor` (recommended: the themed dialog, mapping written out as a token in `design/theme/` and captured in the Component Gallery — a hand-built calendar is a week of work for one row). **Either way the trigger row stays a `GroupedRow` at min height 56.** |
| `SyncBanner` | Composable | M | Wears the toast's capsule. 800 ms retry lockout, no spinner. |
| `ToastView` / `ToastHost` | Composables | L | **Never a Material `Snackbar`.** Hugging capsule: `wrapContentWidth`, `widthIn(max = 420.dp)`, `heightIn(min = 48.dp)`, `CircleShape`, `.floating` shadow, action word in **text ink**. Host always mounted with `AnimatedVisibility` per child; asymmetric specs. Host at h 22 / bottom 62. |
| `SkeletonGate` + atoms | Composables | M | Monotonic clock (`SystemClock.elapsedRealtime()`), never wall clock. Content must be **one** view — two siblings draw on top of each other. `slow` is set at 800 ms and renders nothing (the iOS build shows no spinner either). |
| `FranchiseContextMenu` | `combinedClickable` + `DropdownMenu` | M | Contents/order exact; menu fires **no haptic of its own**; `null` franchise ⇒ no menu at all. |
| `PageInTransition` | `animateFloatAsState` + `graphicsLayer` | S | 6 dp travel, `uiReveal`, **once per tab, never reset**. Driven by tab selection, not `onAppear`. Keep all four tab screens composed — **which is only true because §2.5 takes the four-`NavDisplay` shell**; a single flattened `NavDisplay` would compose one tab at a time and replay page-in on every switch. |
| `PreviouslyMark` / `Wordmark` / `AccountDisc` | Path + composables | M | Port the path commands (an SVG export is insufficient — the dot's x is animated and `.hero` is a 3-pass layer stack). `AccountDisc` **never** draws `person.fill`. |
| `HistoryRail` | Composable | M | The rail is a **background of the card**, not a ZStack sibling. Two-step choreography: `uiSweep` 520 ms then `uiMicro` 220 ms **from the first's completion**, not a timer. |
| `numericFact` | `AnimatedContent` per digit | M | Four call sites only. Crossfade instead of rolling under Reduce Motion — Compose will not do that for you. |
| `DifferentiateMark` / `differentiatingUnderline` | Composables gated on `LocalDifferentiateWithoutColor` | S | D13. |

### 3.5 Chrome, blur and material — the single hardest area

**One file owns every blur decision: `design/chrome/ChromeSurface.kt`.** No screen branches on
`SDK_INT` itself, exactly as no iOS screen calls an iOS 26 symbol directly.

```kotlin
val canUseMaterial: Boolean = Build.VERSION.SDK_INT >= 31 && !reduceTransparency
```

One boolean, resolved once, consumed everywhere. Two independent conditions producing the same
visual would drift apart.

| Surface | `canUseMaterial == true` | `canUseMaterial == false` |
|---|---|---|
| **Chrome glass** (toast, sync banner, rewatch action bar) | Haze 1.7.3 `CupertinoMaterials.ultraThin()` (Apple's own iOS 18 values) behind the capsule + `.floating` shadow | `surfaceFloating` (#2A2D36) fill + 1-dp `strokeStrong` stroke, no refraction |
| **Scroll-edge bands** | Haze-blurred backdrop masked by `Brush.verticalGradient` on the documented stops, under the canvas veil at `chromeBarOpacity` **0.74** | **Opaque** canvas veil at **1.0**, no material — the app's own Reduce-Transparency rendering |
| **Composited-cover ground** (`ArtHeader`/`LandscapeArt` portrait) | — | **Always** the baked-blur Coil transformation (3-pass clamped box blur on a ≤160 px decode). No API branch at all. |
| **`ArtBackdrop` art layer** (blur 56, opaque) | Haze, or `BlurEffect(56.dp.toPx(), 56.dp.toPx(), TileMode.Clamp)` — **`BlurEffect` takes `radiusX: Float, radiusY: Float` in PIXELS, not `Dp`**; `BlurEffect(56.dp, …)` does not compile and the naive fix (dropping `.dp`) silently gives a 56-**pixel** blur, a third of the intended radius at the QA device's 480 dpi. Same unit-error class as `ArtAdaptiveGround`'s `endRadius: 320` two rows above. The 56 is a **starting point**, not a value: it is folded into D22/Q1's calibrated-and-frozen token set, so the literal must not survive into the shipped file. | Drop the art layer; the base gradient carries it — which is exactly what the pre-palette frame already draws. |
| **Hero bloom** (`blendMode(.plusLighter)`) | `graphicsLayer(compositingStrategy = Offscreen)` + `BlendMode.Plus` | same (no blur involved) |

Rules that must survive:

- **A hardened bar is 0.74 canvas over a full-strength blur, never opaque canvas.** At 1.0 with a
  blur present the top ~100 dp of every scrolled screen is a flat #09090B slab and the material under
  it is painted for nothing. Only the no-material path gets 1.0.
- **Never a 0.74 scrim with no blur.** If blur is unobtainable on a surface, go to 1.0.
- **The blur mask and the veil terminate on the same ramp**, or there is a visible seam straight
  across the screen.
- **Use `mask = Brush.verticalGradient`, not `HazeProgressive`** — iOS masks a *constant-radius*
  material rather than varying the radius.
- **Mount a blur layer only while it is on; never hold it at opacity 0.** A material at α 0 over
  moving art is still a backdrop blur the compositor pays for every frame.
- **Blur cost is measured on a real mid-range handset, not asserted from an emulator property.**
  `ro.surface_flinger.supports_background_blur` gates SurfaceFlinger's **window** background blur
  (`Window.setBackgroundBlurRadius`, dim-and-blur behind dialogs) — a compositor feature for
  cross-window blur. **Haze, `Modifier.blur` and `RenderEffect` are HWUI/Skia `RenderNode` effects on
  the app's own render thread and never consult it**; they work with the property at 0, and
  `Modifier.blur` is a no-op on API 26 because `RenderEffect` is **API 31**, not because the property
  is absent. So the property proves nothing about this app's chrome and is struck from TOOLCHAIN.md and
  R5 as evidence. The app's worst-case frame is a full-width `ScrollEdgeChrome` Haze band (a
  full-screen offscreen capture + blur, every frame) over a drifting `ArtHeader` and a `LazyRow`; the
  floor AVD takes the no-blur branch by design and the API 36 AVD renders through an M5 GPU under
  MoltenVK, so neither says anything about an Exynos/Dimensity/Adreno-6xx. **Budget:** 99th-percentile
  frame under **16.6 ms** on the reference mid-ranger, measured with `dumpsys gfxinfo` / JankStats on
  that exact scroll (M11's exit criterion; device named in Q21). **Fallback trigger:** if the band
  cannot hold the budget on that device class, the surface takes the app's **own 1.0 opaque branch**
  there — never a half-blur, never a reduced radius.
- **`bottomUnderfill`:** a 244-dp stack (64 ramp + 180 solid canvas) bottom-aligned and offset
  `+180.dp`, drawn below the `NavigationBar` in z-order. Verify by screenshot that no chevron is
  legible in the gesture strip.
- **All band heights are computed from `WindowInsets.statusBars`.** Never port the iOS `59` constant —
  Android status bars run ~24–48 dp. Regression targets: `chrome-images.md` §3.9 gives the worked
  heights for a 59-pt inset; recompute for the real inset and record the Android numbers.
- **`GlassHelpers.swift` declares SIX shims, four of which are no-ops on Android.** Real:
  `glassChrome` (line 14). No-ops: `chromeScrollEdgeHidden` (52), `chromeScrollEdgeHard` (68),
  `chromeTabBarMinimizeOnScroll` (84), `chromeSharedBackgroundHidden` (104). Two-line title slot:
  `chromeNavigationSubtitle` (118). §4.3's row says the same thing. The one behavioural consequence:
  **Profile relies solely on the system `.hard` scroll edge and has no veil of its own** — it must
  either draw one or accept a plain material bar, and it must **not** paint an opaque toolbar
  background over the scroll edge (that bisects the `SETTINGS` eyebrow through its x-height).

### 3.6 Image pipeline

Authority: `spec/chrome-images.md` §4, `research/images-palette.md`.

- **Coil 3.6.1** with `Precision.INEXACT` globally, a **separate `@ArtHttpClient`** so no bearer
  token can reach `s4.anilist.co` / `image.tmdb.org` and image traffic does not share the API's
  17.6 s call budget (§7 Q8).
- **The bucket ladder is mandatory:** `[128, 192, 256, 384, 512, 768, 1024, 1536, 2048]`, memory key
  `"$url|$bucket"`, plus an `Interceptor` that probes **every bucket ≥ want** before fetching and
  short-circuits on a hit. Coil keys per exact size and does no serve-larger fallback — skipping this
  reproduces the blurry-hero bug verbatim (a 270-px Library decode winning for the whole session).
- **Synchronous first-frame hit:** probe the `MemoryCache` during composition and feed the result
  into `placeholderMemoryCacheKey`, or `AsyncImage` shows a placeholder for at least one frame and
  the port reproduces the flicker this pipeline exists to remove.
- **A cache hit never animates.** Only a network/disk load cross-fades, on `uiGentle` (220 ms).
- **A URL change to an uncached URL clears the old art first.** No stale poster under a new title.
- **A failure has no UI** — no error glyph, no retry, no spinner. It falls back to the host's ground
  or `GradientPlaceholder` (#27272F → #141418).
- **Memory budget:** iOS pins 96 MB of decoded bytes. Coil's default is a heap percentage and will be
  far smaller. **Measure**, do not guess (§7 Q3).
- **Blur is baked into the bitmap** by a custom `Transformation` (3-pass clamped box blur on a
  ≤160 px decode) for the portrait composite — so that surface needs no API-level branch and costs
  nothing per frame.
- **Palette:** port `dominantTint` **verbatim** from `spec/design-tokens.md` §7.2 — 32×32
  `createScaledBitmap` (aspect **not** preserved), α ≥ 0.8, OKLab L ∈ [0.08, 0.92], chroma ≥ 0.035,
  12 hue × 4 lightness buckets, highest population, mean, clamp **L 0.30–0.44** and **C 0.075–0.145**,
  lean **15 %** toward brand amber (unit hue vector **(0.4175, 0.9087)**), back to sRGB. Fed by a
  separate 64-px `allowHardware(false)` request. **Never `androidx.palette`** — median-cut on HSL,
  visibly different grounds, and it still needs the L/C clamps. `DetailTint.quiet` (C ≤ 0.045,
  L 0.40–0.46, 20 % toward `surfaceRaised`, composited at 0.35) ports alongside it.

### 3.7 Motion and haptics

- `AppMotion` object with the 13 curves, converted by the closed form. Two are already Compose
  constants: `uiReveal == EaseOutQuint`, `uiSweep == FastOutSlowInEasing`. Declare every other
  bézier **explicitly**; `FastOutSlowInEasing` (0.4, 0, 0.2, 1) is **not** SwiftUI's `.easeInOut`
  (0.42, 0, 0.58, 1).
- Pre-computed springs: `uiMicro` 815.7/0.88 · `uiSnappy` 341.5/0.84 · `uiSettle` 186.6/0.90 ·
  `uiMilestone` 273.4/0.74. **Verify by eye** — the two integrators are not identical.
- `pickMotion(token, reduceMotion)` mirrors `ThemeMotion.pick`: **one** substitute, a 0.12 s ease-out.
  The rule is not "no animation"; it is `uiReduced` plus **press in opacity (0.72), never in scale**.
- Scroll offset: a `MutableFloatState` in a stable holder, read **only** inside
  `graphicsLayer {}` / `drawBehind {}` lambdas or through `derivedStateOf`. Clamp to `[-320, 240]`
  and round to 0.5 before writing; de-duplicate. Boolean probes guarded `if (new != old)`.
  Geometry probes are `Modifier.onLayoutRectChanged` (18 sites) — **and its parameters are part of the
  spec, not a default to inherit.** The signature is
  `onLayoutRectChanged(throttleMillis: Long = 0, debounceMillis: Long = 64, callback)`: with the
  defaults the callback fires only **~64 ms after movement STOPS**. Every scroll-driven surface in the
  app would then not update *during* the scroll at all and would snap into place after the finger
  lifts — a more visible defect than the "Today lags" regression this section exists to prevent.
  Therefore:
  - **`onLayoutRectChanged(throttleMillis = 0, debounceMillis = 0)`** for the ~5 probes that drive
    per-frame chrome: the bar hardening at `topHold + barEdgeRamp` (Today, Library, Search), Detail's
    docked title and hardened bar at `copyTop − band` (§4.5 is emphatic this is measured, **not** a flat
    130 dp), and `HeroCopyScrim`'s point-based stops.
  - **Keep the 64 ms debounce only for one-shot measurements**: the measured copy height, the
    `containerRelativeFrame` substitutes, the A–Z rail's index map.
  M11's systrace criterion adds a **frame-time check on the zero-debounce sites** — they run on every
  scroll frame by design, so they are the first place a dropped frame will come from.
- Haptics: **one file**, `design/haptic/Feedback.kt`. Route through `LocalHapticFeedback` /
  `HapticFeedbackType` (SegmentTick / Confirm / Reject / GestureThresholdActivate) for
  permission-free, auto-falling-back feedback; touch `Vibrator` + `VibrationEffect.Composition` in
  exactly one place, guarded by `arePrimitivesSupported`. Per-token floors (40 ms `.selection`,
  300 ms everything else), foreground gate, `previously.haptics` DataStore key (default true),
  one-per-transaction. Fired **inside the write**, never by a view.

---

## 4. File-by-file port table

Complexity: **S** ≤ ½ day · **M** ~1 day · **L** 2–4 days · **XL** ≥ 1 week (split it further before
starting). Sizes assume the spec is read first. "Deps" are the port artefacts that must exist first.

### 4.1 `ios/Sources/Models/` and `ios/Sources/Util/` → `:model`

| iOS file | LoC | Android destination | Cx | Deps | Notes |
|---|---|---|---|---|---|
| `Models.swift` | 950 | `model/wire/{Franchise,FranchisePart,Episode,Airing,Enums,Envelopes,ReleaseWindow,FranchiseUpcoming,Subscription}.kt` + `model/derive/PartDerivations.kt` | XL | Formatting | `SafeSerializer<T>(default)` per field; `SafeListSerializer` dropping the **whole** array; `PartCounts` → `Map<PartKind, Int>`; `Patch<T>` sentinel replacing `T??`. |
| `Models+Shared.swift` | 180 | `model/derive/FranchiseDerivations.kt` | M | Models, Copy | The aired/renderable/markTarget ladder. `episodicParts` is implemented twice on iOS — port **one**. |
| `Models+Enrichment.swift` | 530 | `model/wire/Enrichment.kt` + `model/derive/ArtAccessors.kt` | L | Models | `portraitArt`/`landscapeArt`/`wideArt` are the **only** way a view reads art. `legacyBanner` compares against the **raw** `cover`. |
| `Util/Formatting.swift` | 458 | `model/time/{TimeAnchor,Formatting,CalendarStore}.kt` | L | — | `java.time`. `dayDiff` = `Math.round((a−b).toDouble() / 86_400_000)` — integer division is wrong across DST. Cache zone+locale on a composite stamp; the Schedule feed calls this thousands of times per rebuild. `fmtTime` must use `DateFormat.getTimeFormat(context)` to honour the 24-hour switch — this is the one `:model` symbol that needs a `Context`, so inject an `is24Hour` provider rather than a `Context`. |
| `Util/TemporalCopy.swift` | 135 | `model/copy/TemporalCopy.kt` | M | Formatting, Copy | One temporal expression per item. `fmtDayLong` never names **past** weekdays — port the **code**, not the doc comments. |
| `DesignSystem/Copy.swift` | 877 | `model/copy/Copy.kt` + `model/copy/StateIcon.kt` | L | — | Kotlin `object`, **not** `strings.xml`. `EmptyStateCopy.symbol` becomes a `StateIcon` enum; SF names never enter `:model`. `plural` hand-rolled with the NBSP. |
| `DesignSystem/Copy+Library.swift` | 83 | `model/copy/CopyLibrary.kt` | S | Copy | |
| `DesignSystem/Copy+Screens.swift` | 144 | `model/copy/CopyScreens.kt` | S | Copy | |
| `DesignSystem/Copy+Search.swift` | 147 | `model/copy/CopySearch.kt` | S | Copy | |
| `Features/Library/LibraryFacts.swift` | 410 | `model/library/{LibrarySection,ReturnFact,LibraryRowFacts,LibraryDates}.kt` | L | Models, TemporalCopy | `ReturnFact` is the only consumer that reads `releaseWindow.precision` end to end. |
| `Features/Today/RecapDigest.swift` | 141 | `model/recap/{RecapBeat,RecapDigest}.kt` | M | Models, Copy | `RecapBeat.id` embeds a locale-formatted date and that id is persisted in `digestID`; see §7 Q10. |
| `DesignSystem/Palette.swift` (maths half) | — | `model/color/Oklab.kt` | M | — | sRGB ⇄ OKLab + `dominantTint` + `DetailTint.quiet`. Pure arithmetic; the view half stays in `:app`. |
| — | — | `model/derive/ShelfShortened.kt` | S | — | `BreakIterator.getCharacterInstance()` for the `> 40` and `≥ 12` thresholds; code-point-safe substrings. **ICU-dependent — see the collation note below.** |
| — | — | `model/text/AppCollator.kt` | M | — | **One `Collator` instance**, used for every sort and every tie-break (R25). See the collation note below: on Android the bundled ICU moves with the API level, so this file may have to carry a **frozen table** rather than delegate. |
| — | — | `model/test/GoldenFixtures.kt` | M | all | The corpus loader (§4.2). |

**Collation and ICU are not just an iOS↔Android divergence (R25 restated).** On Android
`java.text.Collator` and `java.text.BreakIterator` are ICU-backed and **the bundled ICU version moves
with the API level** — API 26 and API 36 will not order the same library or find the same grapheme
boundaries. That breaks this plan's own verification strategy: the golden-fixture corpus lives in
`:model` and M1 runs it on the **JVM's** collator, so it validates *neither* device, and M5's "layout
is byte-identical between the two AVDs — any layout difference is a bug" would flag genuine ICU
differences as layout bugs. Everything locale- or ICU-dependent is affected: the three sorts and their
tie-breaks, `indexKey` for the A–Z rail, `shelfShortened`'s `> 40` / `≥ 12` grapheme thresholds
(including the CJK + emoji cases M1 explicitly claims to cover), and any localized `DateTimeFormatter`
pattern in `Formatting`/`TemporalCopy`. **Therefore the corpus is split:** pure arithmetic and
derivation fixtures stay JVM tests (M1); the **locale/ICU-dependent subset is additionally replayed as
an instrumented test on BOTH AVDs** (M5 exit criterion). If the API 26 ordering diverges, **freeze the
app's own collation table in `:model`** rather than delegating to the platform — a library that
reorders itself between two Android versions is worse than one that differs slightly from iOS.

### 4.2 `ios/Sources/Networking/` and `ios/Sources/Auth/`

| iOS file | LoC | Android destination | Cx | Deps | Notes |
|---|---|---|---|---|---|
| `Networking/AppConfig.swift` | 96 | `build.gradle.kts` `buildConfigField`s + `data/AppConfig.kt` | S | — | Reproduce the validation and `isLocalBackend`'s address parsing exactly (§2.6). |
| `Networking/APIClient.swift` | 561 | `data/api/ApiService.kt` (Retrofit interface) + `data/api/ApiClient.kt` (the policy wrapper) + `ApiError.kt` + `RetryPolicy.kt` + `TokenRefresher.kt` + `Cancellation.kt` | XL | AppConfig, TokenProvider | The retry/budget/refresh/classification wrapper is a **plain suspend function above Retrofit**, not an OkHttp `Authenticator` — the three-way refresh outcome cannot be expressed there. Branch order in §4.5 of the spec is **not** reorderable. `idempotent` is a required argument with **no default**. `callTimeout` = 17.6 s whole-call; per-attempt `min(15, max(2, remaining))`. Errors carry `userMessage` and `diagnostic` as **separate** properties. |
| `Auth/AuthManager.swift` | 301 | `data/auth/AuthRepository.kt` + `TokenProvider.kt` + `AccountIdentity.kt` | L | Clerk SDK | Preserve: the ≤3 s / 80 ms `isLoaded` poll; `bootstrapped` set **whether or not** Clerk finished; session-change subscription; `signOut()` returning whether the session actually ended; the forced `isSignedIn = false` in `sessionExpired()`; `AccountIdentity`'s resolution order; `letter(of:)` rejecting digits/punctuation/emoji; **never port `avatarInitial`**. `TokenProvider` is thread-safe, not Main-confined. |
| `Auth/SignInView.swift` | 178 | `ui/auth/SignInScreen.kt` + `ui/auth/DevSignInCard.kt` | M (custom: L) | Theme, brand | **Blocked on Q2(b) / D27 — do not default this silently.** `spec/profile-shell.md` §5 specifies the real screen down to the composition: `ZStack` on canvas, `PreviouslyMark(width: 58)` over a `RadialGradient([accent@0.20, accent@0.05, .clear], r 0…260)` in a 520×520 frame at blur 24 ("the screen's one light source"), the app's own buttons, 24/40 padding, and the tagline's tracking pinned at `spec/networking-auth.md` §8.2. Option (a) Clerk's prebuilt `AuthView` + `ClerkTheme` hands that screen to a third-party SDK's Material rendering (its type ramp, button shape, ripple, field chrome, error states) and needs a signed-off side-by-side at M3; option (b) builds the gate on Clerk's **headless** API against §5. `devSignInAvailable` keeps **both** gates (`DEBUG` **and** `isLocalBackend`). |
| `Features/Profile/AccountDeletion.swift` | 76 | `data/auth/AccountDeletion.kt` | S | — | **Bypasses `ApiClient` deliberately.** One attempt, no retry, no silent refresh. 20 s timeout. 403 → "signed out" here only. 200 with any other body → refused. |

### 4.3 `ios/Sources/DesignSystem/` → `:app/design`

| iOS file | LoC | Android destination | Cx | Deps | Notes |
|---|---|---|---|---|---|
| `ThemeTokens.swift` | 713 | `design/theme/{ThemeColor,ThemeSpace,ThemeRadius,ThemeMetrics,PosterSize,ThemeType,ThemeMotion,ShadowToken,Squircle,PreviouslyTheme}.kt` + `design/haptic/Feedback.kt` | XL | — | Split by namespace. `scrollSample` and the metrics that derive from `WindowInsets` live here. |
| `AppFont.swift` | 32 | `design/theme/PreviouslyFonts.kt` | S | Outfit variable font | Explicit `variationSettings` per weight. |
| `Appearance.swift` | 22 | folded into `PreviouslyTheme` + `NavigationBar` label style | S | — | No appearance-proxy layer on Android; style the bar labels directly (Outfit 10 sp, Medium/SemiBold). |
| `ScaledFont.swift` | 32 | **not ported** | — | — | Dead on iOS. |
| `ZoomTransition.swift` | 30 | **not ported** | — | — | Dead on iOS (D15). |
| `Palette.swift` (view half) | 250 | `design/palette/{PaletteCache,ArtAdaptiveGround,ArtBackdrop}.kt` | L | Oklab, ImagePipeline | `PaletteCache` reads the image cache first so the palette costs **zero** extra decodes. `resolveIfAvailable` returns null so branded fallbacks stay on stage. |
| `PreviouslyMark.swift` | 125 | `design/brand/{PreviouslyMark,BookmarkShape,Wordmark}.kt` | M | Theme | Port the path commands; `.hero` is a 3-pass layer stack; the splash's two anchor constants derive from this geometry. |
| `ImageLoader.swift` | 215 | `design/image/{ImagePipeline,BucketLadder,BakedBlurTransformation}.kt` | L | Coil | §3.6. |
| `RemoteImageView.swift` | 55 | `design/image/{RemoteImage,GradientPlaceholder,Thumb}.kt` | S | ImagePipeline | The `Color.clear` sizing box maps to "size the box, let the painter fill it". |
| `GlassHelpers.swift` | 126 | `design/chrome/ChromeSurface.kt` | L | Haze | §3.5. **The six shims** become: one real blur helper (`glassChrome`, line 14), **four** no-ops documented as such (`chromeScrollEdgeHidden` 52, `chromeScrollEdgeHard` 68, `chromeTabBarMinimizeOnScroll` 84, `chromeSharedBackgroundHidden` 104), one two-line title slot (`chromeNavigationSubtitle` 118). §3.5's list is the same six — it previously said five here and four no-ops there, and an implementer working from this table lost one. |
| `Primitives.swift` | 2061 | `design/card/{MediaRow,ShelfCard,BannerCard,ProgressBanner,ArtHeader,Scrims,ShelfScroller}.kt`, `design/control/{Buttons,Chips,PressStyles,MarkRing,MarkSplitButton,DrawnCheck,ProgressBar,GroupedList,AutoSizeText}.kt`, `design/chrome/{ScrollEdgeChrome,ChromeGlassBox,ScrollOffset}.kt`, `design/theme/Surface.kt`, `design/brand/AccountDisc.kt`, `design/state/{SkeletonBlock,Differentiate}.kt` | XL | Theme, ImagePipeline, Palette | **Split before starting.** ~20 components; §3.4 is the checklist. |
| `Primitives+States.swift` | 1248 | `design/state/{EmptyState,InlineNotice,StaleStrip,RefreshIndicator,SyncBanner,Announce,PassiveTick,ProgressText,QueryProgressBar,HistoryRail,Milestones,SeasonSweepLedger,EpisodeArtwork}.kt`, `design/control/{SectionHeaderRow,CompactActionButton}.kt` | XL | Theme, Copy | **Split before starting.** `SeasonSweepLedger` is a **process-wide** ledger of the last 32 tokens — `remember` cannot do its job. |
| `Skeletons+States.swift` | 229 | `design/skeleton/{SkeletonGate,SkeletonAtoms}.kt` | M | Theme | Monotonic clock. Per-screen compositions live with their screens. |
| `UndoToast.swift` | 111 | `design/toast/{ToastHost,ToastView,UndoState}.kt` | M | SyncCenter | `UndoState` equality is by **id only**. |
| `FranchiseContextMenu.swift` | 77 | `design/menu/FranchiseQuickActions.kt` | M | AppModel | D4. |
| `PageTransition.swift` | 52 | `design/motion/PageInTransition.kt` | S | Motion | |

### 4.4 `ios/Sources/App/` → `:app/state`, `:app/nav`, `:app/ui/root`

| iOS file | LoC | Android destination | Cx | Deps | Notes |
|---|---|---|---|---|---|
| `AniTrackApp.swift` | 98 | `PreviouslyApplication.kt` + `MainActivity.kt` + `di/AppModule.kt` | M | Hilt, Clerk | Boot order matters: Clerk configure **before** the composition; notification channels are unconditional at minSdk 26; `onSessionExpired` wiring. |
| `AppModel.swift` | 1374 | `state/AppModel.kt` + `state/AppModelFeeds.kt` + `state/AppModelSearch.kt` | XL | :model, ApiClient, SyncCenter | **Split before starting**: lifecycle/library, derived feeds, search. §2.3. |
| `AppModel+Writes.swift` | 102 | `state/AppModelWrites.kt` | M | AppModel | `markThrough`, `removeWithUndo`, `restoreRemoved`, `undoTapped`. |
| `AppModel+States.swift` | 71 | `state/SurfacePhase.kt` | S | AppModel, SyncCenter | Order matters: cached content beats a failed refresh. |
| `SyncCenter.swift` | 409 | `state/SyncCenter.kt` + `data/disk/FailedChangeStore.kt` | L | DataStore, ConnectivityManager | `WriteIntent` sealed class with polymorphic serialization. `isOnline` optimistic-true default. A row with nothing runnable is **never** cleared as though it succeeded. |
| `RewatchStore.swift` | 179 | `data/disk/RewatchStore.kt` | M | kotlinx.serialization | Synchronous load at construction (Detail reads it in composition). Atomic write + one backup generation. `completedAt == 0` is the implicit-first-watch sentinel. |
| `Routing.swift` | 10 | `nav/{NavKey,DetailRoute,EpisodeFocus,TopLevelBackStack,NavGraph}.kt` | M | Navigation 3 | §2.5. Drop `zoomID`. |
| `RootView.swift` | 322 | `ui/root/RootScaffold.kt` + `ui/root/MainTabScaffold.kt` | L | Auth, AppModel, nav | Two-condition splash hand-off; `surfaceReady`; process-lifecycle wiring (`ProcessLifecycleOwner` ON_START/ON_STOP); the three-layer tint chain; `ToastHost` mounted **twice** (shell + sheet). |
| `SplashView.swift` | 315 | `ui/root/SplashScreen.kt` | L | brand, AGSL | D19. Ignite haptic at 0.92 s; hand-off 1.68 s (1.2 s reduced, no haptic); app revealed at scale 0.965 + blur 4. **The mark is a vector path — there are no splash PNGs** (§3.3). |
| `SplashShaders.metal` | 33 | `ui/root/SplashShaders.kt` (AGSL) | M | — | **D19 / R11.** The sole authority for `emberZoom` (10-tap radial smear + chromatic fringe) and `filmGrain`; it had no row in this table at all, and §4.8's `-name '*.swift'` verification could not detect the omission. The source is reproduced in `spec/profile-shell.md` §1.1 and §3.4, so nothing is lost — the table's completeness claim was simply false. |
| — | — | `ui/root/SystemSplashHandoff.kt` (`installSplashScreen()`) | S | core-splashscreen | **At targetSdk 36 the platform ALWAYS draws its own splash** (the adaptive icon over `windowSplashScreenBackground`) before the first composable runs. It cannot be skipped, only handed off from. Without a hand-off the user sees **two** splashes — the system's, then `SplashScreen.kt`'s own 0.92 s ignite / 1.68 s hand-off — a fidelity break on the app's very first frame, which is the frame D19 spends the most words on. The hand-off: `installSplashScreen()` in `onCreate` **before** `setContent`, `windowSplashScreenBackground = #000000` (§4.7) so the two grounds are the same black, the system icon either suppressed or matched to the brand mark's first frame, and `setKeepOnScreenCondition { !compositionReady }` so the system frame holds until the composition can draw — **one continuous ignite**. M6 checks for a visible seam. |

### 4.5 `ios/Sources/Features/` → `:app/ui`

| iOS file | LoC | Android destination | Cx | Deps | Notes |
|---|---|---|---|---|---|
| `Today/TodayView.swift` | 2222 | `ui/today/{TodayScreen,TodayVeils,HeroSlate,HeroFocus,StretchingHeroArt,TrendingBillboard,CalmBlock,QueueSection,UpcomingSection,WatchingShelf,TodaySkeleton,RecapArrival,RecapLine}.kt` | XL | everything | **Split before starting** — thirteen files, not twelve. **`StretchingHeroArt`** (`TodayView.swift:1815`) had no destination despite being the subject of **Q6, which blocks M11**, and one of only three views permitted to read the scroll offset (§3.7): write it as its own file so the Q6 answer lands in one place. **Rename noted so the Swift stays greppable: `TrendingFocus` (`TodayView.swift:1971`) → `TrendingBillboard.kt`.** The measured-copy geometry (`heroCopyHeight` → scrim stops **and** hero height **and** title hand-over) needs a measure-then-state pass; the invariant that saves it is "the copy's height depends only on the width, never on this". |
| `Schedule/ScheduleView.swift` | 1124 | `ui/schedule/{ScheduleScreen,Ticker,DayHeader,AiringCard,EarlierFold,FilterMenu,ScheduleSkeleton}.kt` | XL | AppModel feeds | Day tracking rebuilt from `LazyListState.layoutInfo.visibleItemsInfo` + a ≥20 %-visible predicate + `snapshotFlow{}.distinctUntilChanged()`, taking the **minimum** visible day. Today's section is always emitted; "today" always means day 0. |
| `Schedule/ScheduleReminders.swift` | 19 | `notify/ScheduleReminders.kt` + `data/disk/ArmedAlertStore.kt` | M | AlarmScheduler | There is **no** way to read pending alarms back — persist the armed set at scheduling time, identifier shape `episode-<mediaId>-<episode>`. Get this wrong and the card's bell lies. |
| `Library/LibraryView.swift` | 1639 | `ui/library/{LibraryScreen,ContinueShelf,ContinueCard,LandscapeShelf,AllTitlesScreen,ChipRow,IndexRail,PosterWall,ArrangeSheet,LibrarySkeleton}.kt` | XL | LibraryFacts | **Split before starting.** Hand-rolled sticky headers for the poster wall (`LazyVerticalGrid` has no `stickyHeader`); a key→flattened-index map for the rail; `containerRelativeFrame` computed by hand (reference device yields 286×161 and 174 wide — the skeleton constants prove it). |
| `Discover/DiscoverView.swift` | 1063 | `ui/discover/{DiscoverScreen,SearchField,ScopeBar,Launchpad,TrendingGrid,ResultsList,NotificationPrimer,CorrectionLine}.kt` | XL | AppModel search | Docked `TextField` under the title — **not** M3 `SearchBar`, which expands to a full-screen surface (the opposite of this screen's rule). IME hides on scroll via `NestedScrollConnection` (snaps rather than tracking the finger — D-list §1.3 note). |
| `Discover/SearchComponents.swift` | 313 | `ui/discover/{AddControl,SearchRows}.kt` | M | Discover | `AddControl` keeps **one identity** across the `owned` flip so the glyph transition survives; owned state drops the primary action so tap opens the menu. |
| `FranchiseDetail/FranchiseDetailView.swift` | 1937 | `ui/detail/{DetailScreen,DetailVeils,HeroBlock,IdentityLine,NextUpCard,AboutSection,EpisodesSection,MoviesAndExtras,DetailToolbar,DetailSkeleton}.kt` | XL | everything | **Split before starting.** Docked title + hardened bar both flip at `copyTop − band`, **not** a flat 130 dp. |
| `FranchiseDetail/DetailSupport.swift` | 557 | `ui/detail/{EpisodeList,EpisodeStill,EpisodeCopy}.kt` + `design/palette/DetailTint.kt` | L | Palette | The one episode-row anatomy, shared with the season screen. |
| `FranchiseDetail/DetailEnrichment.swift` | 328 | `ui/detail/{DetailShelf,TrailerCard,PersonCard,RelatedCard,WatchProviders,VideoSheet}.kt` | L | WebView | The trailer must be an `<iframe>` inside `loadDataWithBaseURL(neutralBase, …)`; **both** YouTube failure modes reproduce identically on Android. |
| `FranchiseDetail/RewatchViews.swift` | 644 | `ui/detail/rewatch/{StartRewatchSheet,WatchHistoryScreen,SessionDetailScreen}.kt` + `ui/detail/SeasonEpisodesScreen.kt` | L | RewatchStore | Sheet height = `clamp(content + 64, 260, 620)`. |
| `Profile/ProfileView.swift` | 1361 | `ui/profile/{ProfileSheet,IdentityRow,WatchingShelf,SyncSection,SyncFootnote,SettingsSection,AccountSection,Colophon,ProfileWash,ExportOptionsScreen}.kt` + `data/disk/ProfileSnapshot.kt` | XL | Auth, SyncCenter | **Split before starting.** **`ProfileSheet.kt`, not `ProfileScreen.kt`** — Profile is a `.sheet` on iOS (`TodayView.swift:223`) and a near-full-height `ModalBottomSheet` here (D18 ③); the old name implied a nav destination and would have quietly cost the drag-to-dismiss, the second `ToastHost` and the deliberate absence of pull-to-refresh. `ExportOptionsScreen` is pushed **inside** the sheet's own host. The wash is anchored to the **content** (offset by −scrollOffset), not the screen. Sync-state precedence tests **offline before checking**. Every settings toggle is `PreviouslySwitch` (§3.4) — the two new toggles (D12, D13) sit in the same group as Haptics and take the same amber ink. |
| `Profile/LibraryExport.swift` | 59 | `data/export/LibraryExport.kt` + `FileProvider` + share intent | M | FileProvider | D3. |

### 4.6 Notifications, widget, shared

| iOS file | LoC | Android destination | Cx | Deps | Notes |
|---|---|---|---|---|---|
| `Notifications/EpisodeNotifications.swift` | 156 | `notify/{EpisodeAlerts,AlarmScheduler,AlertReceiver,NotificationChannels,RearmReceiver}.kt` + `data/disk/AiringPlanStore.kt` | XL | AppModel | **One alarm per air-time bucket** (≤8 buckets, 48 h horizon), not one per episode. **Both exactness branches ship (D7a):** call `canScheduleExactAlarms()` before every arm and catch `SecurityException` regardless (the grant can be revoked between check and arm) — granted → `setExactAndAllowWhileIdle(RTC_WAKEUP, …)`; **denied, which is the DEFAULT on Android 14+ at targetSdk 36** → `setAndAllowWhileIdle`, Doze-limited to ~1 firing / 9 min. `SCHEDULE_EXACT_ALARM` is declared, **never `USE_EXACT_ALARM`** (Play policy limits it to alarm/timer/calendar apps). `ArmedAlertStore` records **which branch armed each row**, so the card's bell never claims a precision the app does not have (copy: spec debt §9.1 D-1). **`RearmReceiver` (D7b)** re-arms from `AiringPlanStore` on `BOOT_COMPLETED` (needs `RECEIVE_BOOT_COMPLETED`), `MY_PACKAGE_REPLACED`, `TIME_SET`, `TIMEZONE_CHANGED` and `ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED` (which also upgrades inexact rows to exact). The alert receiver reads the persisted plan, posts a grouped set, re-arms. Keep: 3 alerts/show, 48 total, round-robin so every show keeps its soonest before any gets its second, `source == anilist && status == watching`, armed the moment the primer's Allow lands. **Ceiling, stated in the code's own comment: D7c.** |
| `Notifications/AiringLiveActivityManager.swift` | 92 | `notify/LiveUpdateManager.kt` | L | API 36 | D8. `setRequestPromotedOngoing(true)` + `setWhen(airsAt)` + `setUsesChronometer(true)` + `setChronometerCountDown(true)`; `POST_PROMOTED_NOTIFICATIONS`. No `staleDate` — schedule an explicit cancel at `airsAt + 15 min`. Lead 60 min, linger 15 min. Gated `SDK_INT >= 36`; below that the feature is absent. |
| `Shared/AiringActivityAttributes.swift` | 16 | `notify/AiringLiveState.kt` | S | — | |
| `Widgets/AniTrackWidgets.swift` | 122 | `notify/LiveUpdateNotification.kt` | L | API 36 | **This file is NOT a home-screen widget (D9).** Its `WidgetBundle` body is exactly one entry, `AiringLiveActivity()` — an `ActivityConfiguration`. Its content is the Live Activity's presentation and ports to the **lock-screen notification card** that `LiveUpdateManager` posts: `LockScreenAiringView` (:67) → the custom `RemoteViews`/`Notification.DecoratedCustomViewStyle` layout; the four Dynamic Island regions (:27-61) → **no target** (D8, no Island); `CountdownText` (:96) → `setUsesChronometer`/`setChronometerCountDown`; `episodeLabel` (:116) and `airLine` (:121) → the two text rows. Colours are inlined in the Swift because extensions do not bundle the theme (accent `0xF0A24E`, backdrop `0x0B0B0E`) — the Kotlin reads `ThemeColor` directly, which is the same value. **Its four user-facing strings live outside `Copy.swift` — "Out now", "Next episode", "Aired just now", "Airs at {time}" — and are catalogued only in `spec/profile-shell.md` §11, not in `spec/copy.md`.** They must be added to `Copy.kt` and to `spec/copy.md` (spec debt §9.1 D-2), or they arrive as literals in a notification builder and F4 cannot see them. |
| — (new feature, **not a port**) | — | `widget/{UpNextWidget,UpNextWidgetReceiver,WidgetTheme,WidgetDataSource}.kt` + `res/xml/up_next_widget_info.xml` | L | Glance, WorkManager | **Scoped in §7 Q22 and recorded as D28 — do not build it as fidelity work.** One "Up Next" 4×2. Art via `ImageProvider(uri)` through a `FileProvider` — **never** `ImageProvider(bitmap)` (RemoteViews byte budget) — **and the content URI needs an explicit cross-app grant, which is the step that makes it work at all**: `android:grantUriPermissions="true"` on the provider, plus `grantUriPermission(launcherPackage, uri, FLAG_GRANT_READ_URI_PERMISSION or FLAG_GRANT_PERSISTABLE_URI_PERMISSION)` for every launcher that hosts the widget (`research/widgets-glance.md` §5.2). The launcher is a different application; without the grant the banner is simply **blank on most launchers, with no error surface**, and without the *persistable* flag it goes blank again after a launcher restart. `GlanceTheme(colors = ColorProviders(fixedDarkScheme))` from `glance-material3`, or the widget renders in the user's Material You palette. Reads the app's own persisted library cache directly. Refresh: event-driven + 30-min `PeriodicWorkRequest` + one inexact `setWindow` at each episode boundary; `updatePeriodMillis="0"`. |

### 4.7 Configuration and assets

| iOS artefact | Android destination | Cx | Notes |
|---|---|---|---|
| `ios/project.yml` | `settings.gradle.kts`, `gradle/libs.versions.toml`, `app/build.gradle.kts`, `model/build.gradle.kts` | M | §2.1. |
| `Resources/Info.plist` | `AndroidManifest.xml` + `buildConfigField`s + `network_security_config.xml` | M | Portrait lock, dark-only, edge-to-edge. **`android:launchMode="singleTop"` on `MainActivity`** (§2.5 — the alert-tap route is dead without it; `research/widgets-glance.md`'s `singleTask` is errata-patched, §9.2), every `PendingIntent` with **`FLAG_IMMUTABLE`**. Permissions: `INTERNET`, `POST_NOTIFICATIONS` (33+), `SCHEDULE_EXACT_ALARM` (31+, **denied by default at targetSdk 36 on Android 14+** — D7a), **`RECEIVE_BOOT_COMPLETED`** (D7b — `RearmReceiver`), `VIBRATE`. **`POST_PROMOTED_NOTIFICATIONS` is added WITH the Live Update, not before it** — Q7's recommended default is not to ship it in v1, and declaring a promoted-notification permission for a feature that does not exist invites a Play Console sensitive-permission question and a Data-safety inconsistency for zero user-visible benefit, while contradicting D8's own "below 36 there is no ambient surface at all". If it is declared ahead of the fast-follow, §7 Q7 must say so and name who cleared it with Play. `FileProvider` (with `android:grantUriPermissions="true"` — §4.6), alarm receiver, `RearmReceiver` (with its five actions), widget receiver **only if Q22 ships the widget**. Backup: **both** `android:fullBackupContent="@xml/backup_rules"` (≤30) **and** `android:dataExtractionRules="@xml/data_extraction_rules"` (31+, `<cloud-backup>` **and** `<device-transfer>`) excluding the library snapshot — D25. |
| `Resources/PrivacyInfo.xcprivacy` | Play Console **Data safety** form | S | Not a file. Someone must fill the form; the manifest is the source of truth for what it declares. |
| `Resources/Fonts/Outfit-*.ttf` (5 statics) | `res/font/outfit_variable.ttf` | S | Source a variable `Outfit[wght].ttf`; if only statics are available, ship five `res/font` entries instead and drop the variation settings. |
| `Assets.xcassets/Tab*.imageset` + `icon/navbar/vector/*.svg` | `ImageVector`s in `design/theme/TabIcons.kt` | M | Translate paths **+3,+3**. |
| `Assets.xcassets/TMDBLogo` | `res/drawable/tmdb_logo.xml` | S | Attribution is contractual. |
| `Resources/AppIcon.icon` + `icon/*.svg` | adaptive icon (background + foreground) + **monochrome layer (new artwork)** | M | §7 Q7. |
| `AccentColor.colorset`, `LaunchBackground.colorset` | `ThemeColor.accent` + `windowBackground` **and `windowSplashScreenBackground` both `#000000`** | S | **Stated once, here, and this is the resolution of a conflict:** the launch frame is **true black `#000000`**, not `canvas` (#09090B), for OLED continuity — verified against `ios/Resources/Assets.xcassets/LaunchBackground.colorset/Contents.json` (r/g/b 0.000) and `ios/Resources/Info.plist:54`. `research/typography-icons.md` §8.1 sets `windowSplashScreenBackground` to `@color/canvas` and is **errata-patched** (§9.2). The system splash and `SplashScreen.kt` must sit on the **same** black or the hand-off (§4.4) shows a step. M0's exit criterion checks the launch frame. |
| iOS `-launchArg` capture routes | debug intent extras (§2.6) | S | One capture script for both platforms. |
| **Fault-injection proxy** (currently a per-session scratchpad file, in no repo) | **`tools/faultproxy/proxy.py`, vendored into the repo** | M | **M14's exit criterion and every error/offline capture for M5 and M7–M12 depend on this artefact, and `find . -name proxy.py` over the repo returns nothing** — it exists only as a per-session scratchpad file referenced by `/CLAUDE.md`. Vendor it: eight modes (`pass` / `down` / `refuse` / `slow` / `empty` / `searcherr` / `detailfail` / `writefail`), mode selected by a file on disk so it can be flipped between captures without a restart, listening on `:8799` and reached from the emulator at `10.0.2.2:8799`. **This is an M0 deliverable**, so no screen milestone blocks on it. Also usable unchanged for the iOS capture set, which is the point of vendoring rather than rewriting. |

### 4.8 Coverage

**All 57 Swift source files plus the 1 Metal source** under `ios/Sources`, `ios/Shared` and
`ios/Widgets` are mapped above — `Palette.swift` appears twice on purpose (its arithmetic half goes to
`:model`, its view half to `:app`), and two files (`ScaledFont.swift`, `ZoomTransition.swift`) are
deliberately not ported. Plus 3 plists/manifests and **7** asset/config groups (the `SplashLayer*`
group is struck — those imagesets are not referenced by the shipping app; §3.3). Verify with:

```bash
find ios/Sources ios/Shared ios/Widgets \( -name '*.swift' -o -name '*.metal' \) | wc -l   # → 58
```

The old command counted only `*.swift`, which is why `ios/Sources/App/SplashShaders.metal` (33 lines,
the sole authority for `emberZoom` and `filmGrain` — D19, R11) sat unmapped while §4.8 claimed
completeness. **A coverage claim whose verification cannot see the omission is not a coverage claim**;
if another non-Swift source is ever added, extend this command with it.

**Thirteen rows are XL.** Split every one into the named sub-files *before* starting it. Six are XL
because they are **entangled** and splitting them is itself design work: `AppModel.swift`,
`Primitives.swift`, `Primitives+States.swift`, `TodayView.swift`, `LibraryView.swift`,
`FranchiseDetailView.swift`. Seven are XL for **volume** and split along obvious seams:
`Models.swift`, `APIClient.swift`, `ThemeTokens.swift`, `DiscoverView.swift`, `ScheduleView.swift`,
`ProfileView.swift`, `EpisodeNotifications.swift`.

---

## 5. Milestones

Each milestone has a goal, an exit criterion that a different agent can verify without reading the
code, and the specs it is executed against. Milestones 3 onward always leave a runnable app.

| # | Milestone | Goal | Exit criterion (demonstrable) |
|---|---|---|---|
| **M0** | **Toolchain & skeleton** | Two Gradle modules, pinned versions, both emulators, the capture loop, the fault proxy. | `./gradlew :app:assembleDebug` succeeds cold; the APK installs and launches on **both** `PreviouslyQA_API36` and `PreviouslyFloor_API26`; `adb exec-out screencap -p` produces a 1280×2856 PNG of a Compose screen on each. **Toolchain gate (§2.1):** KSP 2.3.11 + Hilt 2.60.1 codegen compiles under Kotlin 2.4.10 — if it does not, drop to Kotlin 2.3.21, record it, and move on. **minSdk floor, verified where the number actually lives:** assemble, then assert `app/build/outputs/logs/manifest-merger-debug-report.txt` shows **no `uses-sdk minSdkVersion` injection above 26** and `app/build/intermediates/merged_manifest/debug/AndroidManifest.xml` reads `minSdkVersion="26"`. (The old criterion — `:app:dependencies` "shows no transitive dependency declaring `minSdk > 26`" — is **not executable**: that task prints the resolved dependency graph and reports no `minSdk` for anything; AAR minSdk values live in each library's manifest and surface only in the merger output. R27 had it right.) **Launch frame:** a screenshot taken during launch on both AVDs shows `#000000` behind the system splash icon, and no colour step between the system splash and the first composed frame. **`tools/faultproxy/proxy.py` is in the repo** and its eight modes each answer over `10.0.2.2:8799` from the emulator. Gradle wrapper is pinned in the repo. |
| **M1** | **`:model` + golden corpus** | Wire types, lenient decoding, the freshness ladder, `Formatting`, `Copy`, `TemporalCopy`, `LibraryFacts`, `RecapDigest`, OKLab. | `./gradlew :model:test` green in < 5 s, ≥ 300 assertions. A **golden-fixture corpus** (JSON `(input, now, expected)` triples exported from the Swift) replays with **zero** diffs for: `airedByNow`/`behind`/`lastAired`/`upcomingAiring` across both anchors, `buildScheduleDays` bucketing across a DST seam and at UTC+9, `resumePart`, `shelfState`, `libShelf`, `ReturnFact`, `shelfShortened` (incl. CJK + emoji titles), `prettyReleaseString`, `Copy.plural`, `sessionSpan`. `CopyAuditTest` fails on a straight apostrophe, an `!`, `E19`-style notation, an unpaired ellipsis, or a confirmation button ending in `…`. **The corpus is split by dependency:** everything above is a JVM test; the **locale/ICU-dependent subset** (the three sorts and their tie-breaks, `indexKey`, `shelfShortened`'s grapheme thresholds, any localized `DateTimeFormatter`) is additionally packaged as an instrumented replay, run at M5 on **both** AVDs (§4.1's collation note). A JVM-only run validates neither device. |
| **M2** | **Design tokens & theme** | `PreviouslyTheme`, the M3 role map, squircle, shadow tokens, type, motion, haptics, palette, `PreviouslyMark`. | A debug-only **Token Gallery** screen renders: all **36** colours with their hex, the **26** type tokens, the 10 poster slots, the 5 shadows, the 13 motion curves as animated swatches, the brand mark at 13/58/200 dp, and a palette strip for six known artwork URLs. Screenshot on both AVDs; the shadow and squircle values signed off by the design owner and **frozen as tokens** (D22). **Plus two tests that are the real gates.** ① **`ColorSchemeTest`** (same shape as F2's `ColorTokensTest`) asserts each of the ~30 M3 role ARGBs against D32's map — a `MaterialTheme` with no `colorScheme` silently defaults to `lightColorScheme()`, so this is the only thing standing between the app and light-on-white dialogs. A second assertion covers the 15 mapped `Typography` slots (§3.2) and the `shapes` map. ② **Recomposition-count test (§2.3 rule 10):** advance `now` by 20 s with the library unchanged and assert **zero** recompositions of `MediaRow`, `ShelfCard` and `AiringCard`. This is not a systrace and not M11's job — a stability regression is invisible to both. |
| **M3** | **Transport & identity** | `ApiClient` + `ApiError` + retry/budget + `TokenRefresher`; Clerk `AuthRepository`; splash → sign-in → signed-in. | The app signs in with the **same Clerk account as iOS** and prints the library JSON in a debug list. `ApiClientTest` (MockWebServer) proves: 401 → one forced refresh → success **without** consuming retry budget; a second 401 → `Unauthorized`; **403 never signs out**; an HTML body at any status → `Infrastructure`; 429/5xx retried twice with `Retry-After` clamped to 8 s; whole-call budget ≤ 17.6 s against a black hole; a cancelled call raises no UI error. `npm run auth:smoke` passes against the host the Android build points at. |
| **M4** | **`AppModel`, write policy, SyncCenter, offline cache** | The brain. No UI beyond the debug list. | `AppModelTest` proves, against a fake `ApiClient`: rapid 12→13→14 issues exactly **two** PUTs ending on 14; a failed progress write **keeps** the local value and files a `FailedChange` with a runnable retry; a failed status write **rolls back**; `WriteIntent` survives a simulated relaunch and replays; `reconcileLocalProgress`'s two retirement rules; `teardown()` invalidates an awaiting response; the schedule cache rebuilds exactly once per `(libraryVersion, nowMinute)`. Airplane-mode launch opens on the cached library with an honest stale strip. |
| **M5** | **Primitives, states, chrome** | Every component in §3.4 plus `ChromeSurface`/`ScrollEdgeChrome`. | The Token Gallery grows into a **Component Gallery**: every primitive in every documented state, plus all 15 `EmptyStateCopy` values, all 9 notice strings, the toast stack, the skeleton atoms, every press style, **`Spinner` at its three sizes and three tints, `PreviouslySwitch` on and off, and a frame each of an `AlertDialog`, a `DropdownMenu`, a `ModalBottomSheet` and the `NavigationBar`** (§3.4). Captured on **both** AVDs: API 36 shows blurred bands, API 26 shows the opaque 1.0 bar, and **layout is byte-identical between them** — *except* for the ICU-dependent orderings, which are covered by their own instrumented replay (M1's note) so a collation difference is never mistaken for a layout bug. **Three added gates, each catching something a screenshot review misses.** ① **Pixel probe:** sample the ARGB of the dialog's ground and button ink, the menu's ground, the sheet's top corner, the `NavigationBar`'s selected item, and the bar's bottom edge on a scrolled surface; assert against `ThemeColor` and against `chromeBarOpacity` **0.74-over-blur on API 36 / 1.0 on API 26**. A light `colorScheme` or a stray tonal overlay then shows up as a numeric diff rather than as something nobody noticed. ② **Ripple:** a press-and-hold capture on the tab bar, a menu row, a settings toggle and a poster shows **no ripple ring** on either AVD (D2). ③ **Banned components:** the §3.1 closed set is walked as a review checklist against the diff. |
| **M6** | **App shell** | Splash hand-off, four tabs, nav3 per-tab stacks, pop-to-root, page-in, `ToastHost`, process lifecycle, the tint chain. | Tab switching fires exactly one `.selection` haptic and no other; re-selecting a tab pops it to root; predictive back animates a Detail pop; **system back at a tab root finishes the Activity and does not switch tabs or drop a stack** (D26); backgrounding for > 2 min triggers a reload, > 6 h re-stamps `/me/opened`. **Alert tap, both paths:** a `PendingIntent` **cold** start lands on a stub Detail on the Today stack **once**; and — the case the old criterion could not fail on — a **WARM** tap with the app in the foreground on Library lands on Detail on the **Today** stack **exactly once** (this is what `launchMode="singleTop"` buys; with the default mode `onNewIntent` never fires and the route silently does nothing while the cold test still passes). **Configuration survival:** with a Detail pushed, `adb shell settings put system font_scale 1.3` recreates the Activity and the screen **and its scroll position survive** — no bounce to Today's root. Without this the AX half of M14's capture matrix is uncapturable as scripted. **Splash:** no visible seam between the system splash and `SplashScreen.kt` — one continuous ignite, same black (§4.4). |
| **M7** | **Library + All titles** | Both screens, shelves, chips, sort/filter sheet, index rail, poster wall. | Side-by-side capture against the iOS reference **at default scale**; the ten invariants in `spec/library.md` §9 checked off in writing. Continue card measures **286 × 161**, `BannerCard` **174 wide**. The A–Z rail scrubs A→W with ≥ 20 haptic ticks. **The AX capture is a different comparison, by construction (D6a):** Android at `font_scale 1.3` is compared against **iOS at `.accessibility1`**, because 1.3 is where this port switches its AX layouts while iOS switches at 1.647×. Comparing Android 1.3 against iOS `.large`, as the old criterion did, is guaranteed to differ and proves nothing. Both AX captures must show the **same layout switches taken** (poster width, `ShelfCard` line limit, dropped fade mask, `EmptyState` button width, `InlineNotice` H→V), even though the type sizes differ. |
| **M8** | **Schedule** | Agenda, ticker, Earlier fold, airing cards, filters, reminders. | Today's section renders when empty; day tracking selects the **earliest visible** day; the "Today" button appears iff `selectedDay != 0`; a TMDB row files on its own UTC day with the device set to `Asia/Tokyo`; a reminder bell reflects the persisted armed set after a process kill. |
| **M9** | **Discover / Search** | Field, scopes, launchpad, trending grid, results, add control, primer. | The ten invariants in `spec/discover.md` §15 checked off. An add **never** raises the OS permission dialog; the primer appears ≥ 6.5 s later, once per install, only for an airing AniList show that stuck. Spoken outcome announced on every settle. |
| **M10** | **Detail, Season, Rewatch, History** | The show page and everything pushed from it. | Docked title hands over at the measured `copyTop − band`; a trailer plays in the WebView with the neutral base URL; Where-to-watch is drawn only for `status == available`; a rewatch start is **one** transaction, **one** haptic, **one** toast, fully undoable; the season screen's header is a `ProgressBanner`. |
| **M11** | **Today + Recap** | The billboard, the slate, the stacks, the mark timeline, the recap. | The twenty invariants in `spec/today.md` §20; `-recapDemo` and `-calmDemo` intent extras produce the documented frames; a systrace of one full-length swipe shows **no recomposition of `TodayScreen`** (only the veil and hero-art nodes). **Two additions, because that systrace is blind to both.** ① **Frame budget on real hardware (§3.5):** the worst-case frame — a full-width `ScrollEdgeChrome` Haze band over a drifting `ArtHeader` and a `LazyRow` — holds a **99th-percentile frame under 16.6 ms** on the reference mid-range handset (Q21), measured with `dumpsys gfxinfo` / JankStats. The emulators cannot answer this: the floor AVD takes the no-blur branch by design and the API 36 AVD renders through an M5 GPU under MoltenVK. If the band misses the budget on that device class, it takes the app's own **1.0 opaque** branch there. ② **Probe latency:** the ~5 zero-debounce `onLayoutRectChanged` sites (§3.7) update **within the scroll**, not after it — verified on the same trace; the bar hardening and Detail's title dock must not snap into place after the finger lifts. |
| **M12** | **Profile + settings + account** | Account sheet, sync section, settings, export, sign out, delete. | Sign-out failure raises its alert; delete account is one attempt with a reported outcome; export shares a JSON and a CSV through the system chooser; the **Reduce transparency** and **Differentiate without colour** toggles exist and visibly change the chrome and the amber-only states. |
| **M13** | **Ambient surfaces** | Episode alerts (the port). Live Update and the Glance widget only if Q7/Q22 scope them in. | **BOTH exactness branches are tested, because the denied branch is the default on Android 14+ (D7a).** ① *Grant held:* an alert fires within the documented slop under `adb shell dumpsys deviceidle force-idle`, and `dumpsys alarm` shows ≤ 8 armed alarms for a 30-show library. ② *Grant revoked* (`adb shell cmd appops set <pkg> SCHEDULE_EXACT_ALARM deny`): the app **does not crash**, arms via `setAndAllowWhileIdle`, the alert still arrives (late, within Doze's ~9-minute window), and **the bell and its copy tell the truth about the degraded precision** — an `ArmedAlertStore` that still says "armed, exact" is a failure of this milestone. ③ **Reboot (D7b):** `adb reboot`, then `dumpsys alarm` shows the set re-armed by `RearmReceiver` with no app launch; likewise after a `TIMEZONE_CHANGED` broadcast and after granting the exact-alarm permission (which must upgrade the armed rows). ④ Tapping an alert opens the right show, **warm and cold** (M6's route). ⑤ D7c is documented, not tested — a force-stopped app on a Samsung/Xiaomi receives no broadcasts and there is no in-app remedy. *If the widget is scoped in:* it renders on both AVDs, does **not** move when the wallpaper accent changes, refreshes at an episode boundary, and **its banner art still renders after a launcher restart** (this is where a missing `FLAG_GRANT_PERSISTABLE_URI_PERMISSION` shows up — §4.6). |
| **M14** | **Fidelity & a11y hardening → beta** | The pass that makes it toe-to-toe. | A **capture matrix** — 4 tabs × {default, 1.3 font scale, **2.0 font scale**, **largest display size at font scale 1.0**, reduce-motion, reduce-transparency, offline, error} × {API 36, API 26} — reviewed side by side with the iOS set and signed off. The **display-size (density)** column is new and is a second scaling axis iOS has no analogue for: it can take the usable width well below the 393 dp reference the F1 fixed dimensions were tuned against (D6b). Font scale ≥ 2.0 is checked for clipping and overlap, not for a match. A TalkBack walkthrough per screen. **`tools/faultproxy/proxy.py`'s** eight failure modes each photographed (the proxy is an M0 deliverable, §4.7 — it must not be discovered missing here). **Backup exclusion verified, not trusted (D25):** `adb shell bmgr backupnow <pkg>` then inspect the transport's set and confirm `library-cache.json` is absent on **both** an API 26 device (legacy `fullBackupContent`) and an API 31+ device (`dataExtractionRules`). Play Data safety form filled — and consistent with the shipped permission set (§4.7: no `POST_PROMOTED_NOTIFICATIONS` unless the Live Update ships). Internal-testing track uploaded. |

**Parallelism.** M1–M2 can run concurrently. M7–M12 are independent of one another once M5/M6 land
and can be taken by separate agents; each depends only on `:model`, the design system and `AppModel`.
M13 depends on M4 (for the airing plan) but not on any screen.

---

## 6. Risk register

Severity as assessed by the extraction and research passes. Every **blocker** needs the decision in
§7 before its code is written.

| # | Risk | Severity | Mitigation | Fallback if the mitigation fails |
|---|---|---|---|---|
| **R1** | **Live Activity / Dynamic Island has no Android equivalent.** The lock-screen countdown and the compact/expanded Island regions have no target. | blocker | Android 16 **Live Update** (D8): ongoing notification, `setRequestPromotedOngoing` + chronometer countdown, ticking with the process dead, no foreground service. Gate `SDK_INT >= 36`. | **Ship without it in v1.** `AppModel.nowBarItem` deliberately mirrors the "one soonest episode" model, so the in-app Now Bar is unaffected; the ambient surface is a documented feature gap, not a broken screen. |
| **R2** | **Reduce Transparency has no Android setting**, yet the design branches on it in three places (`ChromeGlassBox`, `ScrollEdgeChrome` veil + mask, `ToastView`) and the "on" branch is also the correct API < 31 rendering. | blocker | In-app toggle (D12), OR'd with `SDK_INT < 31`, resolved into one `canUseMaterial` boolean in `ChromeSurface.kt`. | None needed — the "on" branch must exist regardless, so the toggle is the only open question and it is a copy decision. |
| **R3** | **Differentiate Without Colour has no Android setting**, so every amber-only encoding (today, selected, active filter, next step) has no second carrier. | blocker | In-app toggle (D13) driving `DifferentiateMark` and `differentiatingUnderline`, default off. | Ship Schedule's today-underline **unconditionally** (it is the highest-value one) and accept colour-only elsewhere, documented as a known a11y gap. |
| **R4** | **Liquid Glass** (tab pill, toolbar capsules, search scope bar) cannot be imitated. | blocker | Implement the app's **iOS 18 fallback**, which is already fully specified and shipping. | Not applicable — imitation is the failure mode, not the mitigation. |
| **R5** | **Live backdrop blur — and its per-frame COST, which is the part with no evidence behind it.** `Modifier.blur` blurs a composable's own content, not what is behind it; a true backdrop blur needs a per-frame graphics-layer capture. The core chrome rule is "0.74 canvas over a full-strength blur, never opaque". | hard | **Haze 1.7.3** with `CupertinoMaterials.ultraThin()`, mask = `Brush.verticalGradient`, mounted only while on. ⚠ **`ro.surface_flinger.supports_background_blur` is NOT evidence for this and has been struck from TOOLCHAIN.md** (§9.2): it gates SurfaceFlinger's *window* background blur (`Window.setBackgroundBlurRadius`, dim-and-blur behind dialogs), a compositor feature for **cross-window** blur. Haze, `Modifier.blur` and `RenderEffect` are HWUI/Skia `RenderNode` effects on the app's own render thread and never consult it — they work with the property at 0, and `Modifier.blur` is a no-op on API 26 because `RenderEffect` is **API 31**, not because the property is absent. **Real mitigation:** measure the worst-case frame (full-width `ScrollEdgeChrome` Haze band over a drifting `ArtHeader` and a `LazyRow`) on a **real mid-range handset** with `dumpsys gfxinfo`/JankStats — 99th percentile under 16.6 ms — as an M11 exit criterion (§5), with the device named in Q21. Neither AVD can answer it: the floor takes the no-blur branch by design and the API 36 AVD renders through an M5 GPU under MoltenVK. | The app's **own Reduce-Transparency branch at 1.0** — a shipping, designed rendering — taken **for that whole device class**. **Never** a 0.74 scrim with no blur, and never a quietly reduced radius. |
| **R6** | **Arbitrary colour + radius + Y-offset shadows** (5 tokens, ~40 sites). `Modifier.shadow` is elevation-driven, honours a custom colour only at API 28+, and gives no radius/offset control. | hard | `drawBehind` + `Paint.setShadowLayer` on a hardware layer, built once as `Modifier.shadowToken`. Radii **calibrated visually** and frozen (D22). | Pre-composited nine-patch drawables per token/shape pair. Ugly but bounded. |
| **R7** | **`minimumScaleFactor` has no Compose equivalent**, and it is load-bearing on the hero and the mark capsule. | hard | `BasicText(autoSize = TextAutoSize.StepBased(...))` (Compose 1.8+), nine documented floors. | A `TextMeasurer` bisection in a custom `AutoSizeText`. **Never** an ellipsis. |
| **R8** | **Clerk Android SDK's failure taxonomy is inferred, not documented.** If it collapses "session dead" and "network dead" into one error, the rule *offline must never sign anyone out* cannot be honoured — the exact 2026-08-22 iOS regression. | hard | Verify empirically **before writing the refresh code**: flight mode vs a server-side session revoke, both against `ClerkResult.Failure`'s `error`/`throwable`/`code`/`errorType`. | Use `ConnectivityManager`'s validated-network state as a tiebreaker: an ambiguous failure while offline is `.failed`, never `.notRefreshable`. |
| **R9** | **Serve-larger-never-smaller image cache.** Coil keys per exact size; a naive port gives the hero a 270-px decode for the whole session. | hard | Bucket-keyed `MemoryCache.Key` + an `Interceptor` probing every bucket ≥ want (§3.6). | Key on URL alone and always decode at the **largest** bucket any surface asks for. Costs memory, never blurry. |
| **R10** | **`LazyVerticalGrid` has no sticky headers**, which the All-titles poster wall needs (pinned, opaque, full-bleed letter headers). | hard | A `maxLineSpan` header item plus a manual overlay driven by `LazyGridState`; the header must stay **full-bleed** (an inset one paints a visible plate against the ambient wash). | Drop the pinned behaviour in the grid view only; keep the section headers in flow. The list view keeps `stickyHeader`. |
| **R11** | **Splash Metal shaders** (`emberZoom` 10-tap radial smear + chromatic fringe, `filmGrain`). | hard | AGSL `RuntimeShader` at API 33+. | Below 33: plain scale for the dive, grain dropped (it is near-invisible by design). |
| **R12** | **`@MainActor` `AuthManager` as a `Sendable` TokenProvider** awaited from a background transport. A naive port forces the whole transport onto the UI thread. | hard | Make the Kotlin provider **thread-safe**, hop to Main only where the SDK demands it (§2.4). | A dedicated single-thread dispatcher for Clerk calls, with the coalescing mutex outside it. |
| **R13** | **Cancellation semantics invert.** Kotlin must rethrow `CancellationException`; iOS swallows it at the consumer. | hard | Re-express as "rethrow, suppress the UI effect", and recognise OkHttp's `"Canceled"` `IOException` and `InterruptedIOException` in the same predicate. | None — this must be right. A missed case shows as "couldn't refresh" over good content on every superseded pull. |
| **R14** | **Squircle corners.** `RoundedCornerShape` is a circular arc and reads visibly rounder at r22/r24 — the app's two most-used container radii. | moderate | Custom superellipse `Shape` (§3.1). | Accept the delta below r16 only; above it the difference changes the perceived weight of the app's most-repeated object. |
| **R15** | **Per-field observation collapsing into one `UiState`.** Would reintroduce two named performance regressions (Today at 60–120 Hz; Schedule re-laid out three times a minute). | moderate | §2.3 rules 1–5, plus a systrace check at M11. | None; this is a review rule, not an engineering fallback. |
| **R16** | **Two-calendar time anchoring.** Reading a TMDB instant in the device zone files every row a day late east of UTC+7 and expires date-only slots a day early. Three different passed-ness tests coexist inside `provenAiredCount` on purpose. | moderate | Port `TimeAnchor` first (M1) and gate it with golden fixtures at `Asia/Tokyo` and across a DST seam. | None; the golden corpus is the mitigation. |
| **R17** | **Haptic taxonomy.** No Android notification-haptic vocabulary; impact intensities need API 30+ primitives and may collapse to one grade. | moderate | Hand-authored `VibrationEffect.Composition`s per token, `arePrimitivesSupported`-guarded, tuned by feel on a reference handset. **The throttle, gate and one-per-transaction rules are exact regardless.** | Accept the `.commitLight`/`.commitMedium` collapse (§7 Q11). |
| **R18** | **`onScrollTargetVisibilityChange`** (Schedule's day tracking) has no Compose equivalent. | moderate | Rebuild from `LazyListState.layoutInfo.visibleItemsInfo` + a ≥20 %-visible predicate + `snapshotFlow{}.distinctUntilChanged()`, taking the **minimum** visible day, with `.earlier` reporting null so today is next under it. | None; the reconstruction is behaviourally equivalent and arguably more direct. |
| **R19** | **No way to read pending alarms back**, so `ScheduleReminders.pending` (the card's bell) has no source of truth. | moderate | Persist the armed set at scheduling time (`ArmedAlertStore`), identifier shape `episode-<mediaId>-<episode>`, reconciled on every `sync`. | None; without it the bell either never appears or lies. |
| **R20** | **Exact alarms are denied by default, alarms die on reboot, and OEM battery managers are a hard ceiling.** Not three separate risks — one compounding failure that ends with `ArmedAlertStore` telling the user the bell is armed while nothing is scheduled. | **blocker** | D7a/D7b/D7c, promoted out of this row into §1.3 because they change what the product does: both exactness branches ship and the store records which one armed each row; `RearmReceiver` covers `BOOT_COMPLETED` (+ `RECEIVE_BOOT_COMPLETED`), `MY_PACKAGE_REPLACED`, `TIME_SET`, `TIMEZONE_CHANGED`, `SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED`; the grant ask is a Settings row (D31). M13 tests **both** branches plus the reboot. | Server-side FCM — a backend change (`sync/cron.ts` fan-out) that must be decided **before** the alarm code is written (§7 Q12). **On Samsung ("Put unused apps to sleep", default on) and Xiaomi (Autostart denied by default) a force-stopped app receives no broadcasts at all**, so even `RearmReceiver` does not run: FCM is the only real answer for those devices, and until it exists this is a stated product limit, not a bug. |
| **R21** | **`accessibilityHint` has no Compose equivalent.** | moderate | `semantics { onClick(label = …) }`, which TalkBack reads as "double tap to <label>" — rephrase hints imperatively; **labels stay verbatim**. | Fold the hint into the label where the imperative rephrasing reads badly. |
| **R22** | **Negative padding + `zIndex` hit-testing.** The header's 44-dp target overhangs its layout rect and must win taps against later siblings. | moderate | Custom `layout {}` + `Modifier.zIndex(1f)`; **verify by instrumented test**, do not assume — Compose hit-tests in a different order. | Give the header real height and absorb the 20 dp, accepting a looser rhythm. |
| **R23** | **`Announce.screenChanged`** has no TalkBack equivalent. | moderate | `announceForAccessibility` plus an explicit accessibility-focus move to the new content root. | Announcement only. |
| **R24** | **Pull-to-refresh arm haptic gated on a finger being down.** A momentum flick past the threshold must not buzz. | moderate | Reconstruct `dragging` from the nested-scroll source; fire once at 80 dp, re-arm below 0.3×. | None; it is the detail most likely to be silently dropped. |
| **R25** | **Collator divergence — and it is not only iOS↔Android.** `localizedCaseInsensitiveCompare` is the **one** title order and tie-break; `Collator.SECONDARY` is not byte-identical for titles like "Ōoku"; `String.folding(.diacriticInsensitive)` folds CJK width forms differently from NFD+strip. **Additionally, on Android `java.text.Collator` and `BreakIterator` are ICU-backed and the bundled ICU moves with the API level, so API 26 and API 36 will not order the same library or find the same grapheme boundaries** — which also means M1's JVM-only corpus validates *neither* device, and M5's "any layout difference between the AVDs is a bug" would flag real ICU differences as layout bugs. | moderate | Pick **one** `Collator` instance (`model/text/AppCollator.kt`), use it for every sort and every tie-break, never mix in `String.compareTo`. **Split the corpus** (§4.1): arithmetic/derivation fixtures stay JVM; the locale/ICU-dependent subset — the three sorts and their tie-breaks, `indexKey`, `shelfShortened`'s `> 40`/`≥ 12` grapheme thresholds incl. CJK + emoji, localized `DateTimeFormatter` patterns — is replayed **instrumented on both AVDs** (M5). Verify `indexKey` against a real 300-title library before shipping the rail. | **Freeze the app's own collation table in `:model`** rather than delegating to the platform. A library that reorders itself between two Android versions is worse than one that differs slightly from iOS. Three sorts once broke ties three different ways and titles visibly moved between them — that is the failure to avoid. |
| **R26** | **Compose's `MotionDurationScale` snaps built-in animations under "Remove animations", but freezes the drift/breath infinite loops at their end value.** | moderate | Gate the two infinite loops on an explicit `ANIMATOR_DURATION_SCALE` observer, not on the built-in behaviour. | None; the freeze is a visible bug. |
| **R27** | **Glance/Coil/Haze may declare `minSdk > 26`** and silently raise the floor through manifest merger. | moderate | `./gradlew :app:dependencies` + a manifest-merger report check at M0, **before** the number is written into `build.gradle.kts`. | Raise `minSdk` deliberately with the product owner, or drop the offending dependency (Haze is droppable; the fallback path already exists). |
| **R28** | **`RecapBeat.id` embeds a locale-formatted date** and that id is persisted inside `digestID`, so changing device locale can un-acknowledge a digest. | easy | Reproduce for byte-identical semantics, **or** deliberately diverge to a locale-independent id and record the divergence (§7 Q10). | Either is acceptable; silently inheriting the bug is not. |
| **R29** | **`APIError.rateLimited` → "Something went wrong" while `http(429)` → "Try again in a minute".** Looks like a bug; is deliberate-by-omission. | easy | Port as written, with a comment pointing at `spec/networking-auth.md` §5.1. Add a unit test so a future "fix" fails CI. | — |
| **R30** | **`fmtDayLong` never names past weekdays**, so `TemporalCopy.aired`/`since` emit a month-day for the 2–6-days-ago band, contradicting their own doc comments. | easy | Port the **code**, not the comments. Golden fixture covers it. | — |
| **R31** | **Unicode erosion.** U+00A0, U+2060, U+2019, U+00B7 are line-breaking and typographic rules, not decoration; a `strings.xml` round-trip or a translation pipeline eats them. | easy | Keep the catalogue as a Kotlin `object` in `:model` (also avoids escaping `&` in five headings). `CopyAuditTest` asserts the code points. | — |
| **R32** | **`SkeletonGate`'s minimum-visible window on a wall clock** computes a negative remainder if the system moves the clock mid-window. | easy | `SystemClock.elapsedRealtime()` / `TimeSource.Monotonic`. **Never** `System.currentTimeMillis()`. | — |
| **R33** | **`URL(string:relativeTo:)` vs `appendingPathComponent` inconsistency** between `APIClient` and `AccountDeletion`. | easy | Pick resolve-against-authority (`HttpUrl.resolve`) for both, deliberately, and record it. | — |
| **R34** | **`PartCounts` cannot decode what the server sends** — confirmed drift; the field is `nil` in production today. | easy | Model as `Map<PartKind, Int>`. Do not port a dead field verbatim. | — |
| **R35** | **A shared-element transition into Detail.** An Android engineer will reach for `SharedTransitionLayout` and re-introduce a defect the team already removed. | easy | D15; drop the `zoomID` parameter entirely so the temptation has no hook. | — |
| **R36** | **Compose stability: "recompose the world" by module layout.** `:model` compiles without the Compose plugin, so no `@StabilityInferred` metadata exists for the wire types, and any class holding a `List`/`Map` is inferred unstable regardless. Every row composable becomes non-skippable, and §2.3's 20 s / 60 s ticks then recompose every list on every tab. Structurally worse than the iOS regression it mirrors, because it is caused by the build files rather than by a read site. | **blocker** | §2.1's `stabilityConfigurationFile` over `com.anitrack.model.**` **plus** `@Immutable` + `kotlinx.collections.immutable` on the wire/derive types (compose-runtime is a plain JVM artifact, so this keeps `:model` Android-free). §2.3 rule 10. | None — this is not a tuning knob. The proof is M2's recomposition-count test; **M11's systrace cannot see it** (a swipe does not move `now`, and the criterion watches the screen, not the leaves). |
| **R37** | **Material defaults dissolving the design system.** `MaterialTheme` with no `colorScheme` defaults to `lightColorScheme()`; `NavigationBarItem`/`DropdownMenuItem`/`Switch`/the sheet drag handle construct their own ripple with no `indication` parameter to null; `TopAppBar` stacks a second, uncontrolled scroll-hardening layer on `ScrollEdgeChrome`; `MaterialTheme.typography`/`shapes` leak Material metrics; a FAB/`Card`/`ListItem` is the Android reflex for three of the app's own primitives. F10's `ThemeColor.accent` lint rule is **blind to all of it** — none of those source lines contains the string `ThemeColor`. | **blocker** | D32 + §3.1: a complete hand-written `darkColorScheme`, a **closed** allowed-component list with the banned set named, ripple-free replacements for the four unsuppressable components, `LocalIndication = NoIndication`, `LocalMinimumInteractiveComponentSize = Dp.Unspecified`, shapes mapped to `ThemeRadius`. Enforced by F10 lint rule (b) (ban `MaterialTheme.colorScheme/typography/shapes` reads outside `design/theme/`), M2's `ColorSchemeTest`, and M5's pixel probe + ripple capture. | None. Every fallback here is a visibly different app. |
| **R38** | **The shell cannot deliver what the design system assumes.** A single flattened `NavDisplay` composes one entry, so only one tab screen is alive — contradicting §3.4's "keep all four tab screens composed" and destroying every non-saveable `remember` in the inactive tabs on each switch (scroll offsets, Today's measured `heroCopyHeight`, palette results). The official recipe's `pop()` at a tab root additionally deletes that tab's stack and `SaveableStateHolder` slot. And the stack itself is held in a plain `remember`, so a **font-scale change** — which M14 drives on every screen — recreates the Activity and loses it. | **blocker** | §2.5: four `NavDisplay`s kept composed in a host `Box`; `pop()` never removes a stack (D26); the stack is saveable; all three entry decorators passed in order. M6 tests the font-scale survival on a pushed Detail. | Option (b) — one flattened display with all cross-switch state hoisted onto `AppModel` — which then **requires** deleting "keep all four tab screens composed" from §3.4 and re-specifying page-in. Not a silent fallback. |
| **R39** | **`onLayoutRectChanged`'s 64 ms default debounce.** The probe fires ~64 ms *after movement stops*, so every scroll-driven surface — bar hardening, Detail's docked title, `HeroCopyScrim`'s stops — would snap into place after the finger lifts instead of tracking. More visible than the regression §3.7 exists to prevent. | hard | §3.7: `throttleMillis = 0, debounceMillis = 0` on the ~5 per-frame chrome probes; keep the debounce only for one-shot measurements. M11 adds a frame-time check on the zero-debounce sites. | None; the defaults are simply wrong for this use. |
| **R40** | **Two splashes.** At targetSdk 36 the platform always draws its own splash before the first composable; without `installSplashScreen()` + `setKeepOnScreenCondition` the user sees the system frame *and then* the app's 0.92 s ignite — a fidelity break on the frame D19 spends the most words on. `core-splashscreen` was absent from §2.1 entirely, and the launch-frame colour was specified as `#000000` here and `@color/canvas` in a research note. | moderate | §2.1 pins `androidx.core:core-splashscreen`; §4.4 specifies the hand-off; §4.7 states `#000000` once for both `windowBackground` and `windowSplashScreenBackground`; `research/typography-icons.md` errata-patched (§9.2). M0 checks the launch frame, M6 checks the seam. | Accept the system frame as the whole splash on API < 31 only, where it is a plain window background anyway. |
| **R41** | **Kotlin/KSP line mismatch on the M0 critical path.** KSP 2.3.11 (the newest published) declares `kotlin-stdlib:2.3.20` and embeds the Kotlin Analysis API; the plan pins Kotlin **2.4.10** on "newest stable". Haze 1.7.3 and Compose BOM 2026.08.00 are also on the 2.3.20 line. Hilt codegen runs through KSP, at M0. | moderate | Named M0 gate (§5), not an assumption: "KSP 2.3.11 + Hilt 2.60.1 compiles under Kotlin 2.4.10". Q24. | **Pin Kotlin 2.3.21** and record it. Costs nothing the port uses. |

---

## 7. Open decisions

> ### ✅ ANSWERED BY THE PRODUCT OWNER, 2026-09-04 — these are CLOSED
>
> Recorded in `research/product-decisions.md`, `research/fidelity-line.md` and
> `research/minsdk-decision.md`. **Do not re-open. Do not ask again.**
>
> | # | Answer |
> |---|---|
> | **minSdk** | **26**, not 31 — overriding `compose-architecture.md`. Pre-31 takes the app's existing no-blur reduce-transparency branch. `java.time`, adaptive icons and notification channels all arrive at exactly 26, removing three compat branches. |
> | **Q1** blur/shadow calibration | **CANCELLED as framed.** Native elevation + native blur; re-tune to read right, do not match iOS numerically. See the §1 amendment. |
> | **Q2a** Clerk instance | **Stay on `pk_test_` through both betas**, knowing the cost: the 100-user cap is SHARED across TestFlight and Android, and every beta account is destroyed at the production switch. The cutover is a `server/` task (users keyed on Clerk id — needs a wipe or an id-remap decided *before* switching). |
> | **Q2b** sign-in surface | **Clerk's `AuthView` + `ClerkTheme`.** Accepted divergence: it will not honour the design law exactly. Escape hatch is a custom flow against `clerk-android-api`. |
> | **Q5** external glyph | `open_in_new`. |
> | **Q6** hero stretch | **(a) native overscroll.** |
> | **Q7** Live Update in v1 | **NO — deferred to a fast follow.** API 36+ only, invisible to most users at minSdk 26. The T-0 notification is the feature. The widget and all scheduled alerts REMAIN in v1. |
> | **Q9** applicationId | **`com.anitrack.app`** — permanent, mirrors the iOS bundle id. |
> | **Q11 / Q21** haptics | **Not a blocker and not a release gate.** OEM haptic hardware varies; map to `HapticFeedbackConstants` semantics, accept the two commit grades collapsing. Keep the one-haptic-per-transaction discipline. Devices still wanted for battery-killer/alarm QA, not for haptic feel. |
> | **Q13** exact-alarm ask | **Ask contextually and late**, at the moment alerts are turned on for an airing show — never at launch, once only, with a Settings row as the way back. The app must be **correct without the permission** (inexact baseline); `USE_EXACT_ALARM` is forbidden by Play policy. |
> | **Q16** long-press menu | `DropdownMenu`. |
> | **Q17** Reduce Motion | Accept the platform contract for built-ins. |
> | **Q24 / R41** KSP↔Kotlin | **RESOLVED EMPIRICALLY — not a gate.** Kotlin 2.4.10 + KSP 2.3.11 + Hilt 2.60.1 assembles green (`kspDebugKotlin`, `hiltJavaCompileDebug`, APK). Do **not** downgrade to Kotlin 2.3.21. Evidence in `research/verified-versions.md`. |
>
> **Standing instruction from the product owner (2026-09-04):** *"I don't think there would be any
> blocked-on-Shantanu items that would surface."* For everything still open below, **take the
> recommended default, give it a D-number, log it in `research/product-decisions.md`, and proceed.**
> Do not block.

These need the product owner. Each has a recommended default so work is not blocked; taking the
default silently is acceptable only where marked. **Q1, Q2, Q7, Q12, Q22, Q23 block a milestone.**

**Two rules for this section.** ① **A default that changes user-visible behaviour is not "taken" until
it has a D-number in §1.3** (§1.3's preamble, §8 rule 8). Four answers had already been accepted here
without one — Q2(b) the sign-in surface, Q5's glyph, Q10's id, Q13's Settings row — and they are now
D27, D29, D30 and D31 respectively. ② **A question that is a fidelity decision may not be answered on
cost grounds without saying so** (Q2(b) again).

| # | Question | Recommended default | Blocks |
|---|---|---|---|
| **Q1** | **Blur and shadow calibration.** Skia's blur and `setShadowLayer`'s radius are not on iOS's scale, and this port's baked blur runs in *source pixels before* an upscale where iOS's runs in *points after* one. Every radius (28, 48, 56, the Haze band, and all five shadow radii) is a starting point, not a value. | Capture the same six shows on both platforms through the launch-arg / intent-extra routes, put them side by side, let the design owner pick the Android numbers, then **freeze them as tokens**. Budget half a day. | **M2** |
| **Q2** | **Clerk instance, sign-in surface, One Tap, account linking.** The one subsystem that is a hard ship-blocker if it is wrong, and three of its four parts had answers that do not hold. **(a) Instance.** Cut a **production** instance (`pk_live_`) before Android ships, or stay on `pk_test_` (100-user cap, no migration to production — every existing beta account is thrown away at the switch)? **This is not an Android decision:** swapping the instance invalidates every existing **iOS TestFlight** account and requires a matching server-side key change in `server/.env`. It is a three-surface coordinated cutover. **(b) Sign-in surface.** Clerk's prebuilt `AuthView` + `ClerkTheme`, or the app's own gate on Clerk's headless API? **This is a fidelity decision, not a cost one** — it is the first screen a new user sees, and `spec/profile-shell.md` §5 pins it down to the mark, the radial bloom, the button capsule, the press language and the tagline's tracking. **(c) Google One Tap.** **(d) Linking** for a user who signs up with Apple on iOS and Google on Android. | **(a) Re-scope as iOS + server + Android and name who signs off** before anyone writes a key into a build file. Recommended: cut production before beta, in one coordinated change across the three surfaces. **(b) NOT taken by default — see D27.** If `AuthView` is accepted, D27 records exactly what `ClerkTheme` can restyle (colour roles, corner radii, typeface) and what it cannot (the mark + radial-bloom composition, `PrimaryButtonStyle2`'s capsule, the press language, the field chrome), and **M3 does not pass without a signed-off side-by-side against the iOS sign-in screen**. Otherwise build the gate headless against `spec/profile-shell.md` §5 — the answer consistent with the rest of this plan. **(c) Yes, but the prerequisite list is longer than "the SHA-256 fingerprint":** `research/clerk-android.md` §4.1 requires a Google OAuth client **plus** the fingerprints of **both** the debug keystore **and the Play App Signing key** — a key the developer does not possess until after the first Play upload. Plan for One Tap to work in debug and be **enabled only after the first upload**, or it ships broken in production while working in every local build. **(d) Link by verified email, WITH an explicit account-merge/claim flow for Apple private-relay identities — and this part is blocking.** An iOS account created with Sign in with Apple + Hide My Email carries an `@privaterelay.appleid.com` address that can never match a Google identity's verified email, so plain email linking gives **exactly the existing iOS beta cohort** two accounts and two libraries. `research/clerk-android.md` §7.2 raises the case; the old answer dropped it. | **M3** |
| **Q3** | **Tolerant-list divergence.** iOS empties the **whole** array on one malformed element. Keep that (D24), or drop only the bad element? | Keep iOS's behaviour for parity; revisit once both platforms share a corpus. | M1 |
| **Q4** | **The annotating face.** `FontFamily.Default` (Roboto) at zero bytes, or a bundled Roboto? One UI gives third-party apps Roboto; other OEMs are unconfirmed and a user font pack changes every metadata line's width. | `FontFamily.Default` for v1; bundled `Roboto[wdth,wght].ttf` as the escape hatch if OEM QA shows drift. Decide **before the first beta**. | M2 |
| **Q5** | **"Leaves the app" glyph.** `arrow_outward` (1:1 with SF's `arrow.up.right`) or `open_in_new` (the Android reflex)? Same class of decision as the share glyph. | **Answered: `open_in_new`, recorded as D29**, matching the D3 reasoning — this row genuinely opens a browser. `spec/icon-mapping.md` rows 2–3 errata-patched (§9.2). | M10 |
| **Q6** | **The hero pull-down stretch.** Android clamps overscroll at 0 and stretches the container instead. (a) Keep Android's overscroll and drop the stretch — more native; (b) intercept in `onPreScroll` and reproduce iOS — more toe-to-toe. | (b). The stretch is part of the billboard's identity and `StretchingHeroArt` is one of only three views allowed to read the scroll offset. | M11 |
| **Q7** | **Ship the Live Update in v1?** API 36+ only, invisible to most `minSdk 26` users, sparsely adopted, and lightly QA'd by OEMs. **Note the interaction with Q22:** "No" here plus "yes" there would ship **zero** of iOS's actual ambient surface and one screen iOS has never had. | **No.** The T-0 notification is the whole feature for v1; Live Updates is a fast follow once there is a device to test on. **If No, `POST_PROMOTED_NOTIFICATIONS` does not go in the shipping manifest** (§4.7) — a declared sensitive permission for an absent feature invites a Play Console question and a Data-safety inconsistency for zero benefit. If it is declared ahead of the fast-follow anyway, record here who cleared it with Play. | **M13** |
| **Q8** | **Does the art CDN get its own OkHttp client?** A shared client risks a Clerk bearer reaching `s4.anilist.co` and image traffic sharing the API's 17.6 s budget. | Separate `@ArtHttpClient`. It is a one-line difference and a real security boundary. | M2 |
| **Q9** | **Application id.** `com.anitrack.app` (mirrors the iOS bundle; Play and App Store namespaces are independent) or a distinct id? It also determines the Clerk `clerk://${applicationId}.callback` allowlist entries. | `com.anitrack.app`. | M0 |
| **Q10** | **`RecapBeat.id`'s embedded locale-formatted date** is persisted in `digestID`, so a locale change can un-acknowledge a digest. Reproduce for byte-identical semantics, or fix it? | **Answered: fix it — locale-independent id — and the divergence is recorded as D30**, which is what "record the divergence in this plan" meant and had not been done. | M11 |
| **Q11** | **`.commitLight` vs `.commitMedium`.** Accept the collapse onto one grade on devices without composition primitives, or spend the `VIBRATE` permission to keep two grades on the subset that supports them? | Accept the collapse. | M2 |
| **Q12** | **Are episode alerts "best effort" or a push feature?** If a missed alert is a product failure, the answer is server-side FCM — a backend change to `sync/cron.ts` that must be decided **before** the alarm code is written, not after. | Best effort with exact alarms for v1. | **M13** |
| **Q13** | **The exact-alarm grant — a BLOCKING engineering decision, not a UX footnote.** At targetSdk 36 on Android 14+ `SCHEDULE_EXACT_ALARM` is **denied by default** (`research/notifications-liveupdates.md` §2.3), and `USE_EXACT_ALARM` is correctly ruled out by Play policy. So on a fresh install on any modern device there are **no exact alarms**: `setExactAndAllowWhileIdle` throws `SecurityException` and `setAndAllowWhileIdle` is Doze-limited to ~1 firing per 9 minutes. The question is therefore two questions. **(i) Engineering, decided:** the app ships **both branches** and the armed store records which one armed each row (**D7a**) — this is not optional and M13 tests both. **(ii) Product:** where does the *ask* live? (a) never ask and accept the slop; (b) one Settings row; (c) an inline notice on Today when an alert was demonstrably late. iOS has no analogue to copy. | **(i) is settled in D7a/D7b/D7c and is a precondition for writing any alarm code.** (ii) **(b)** — one Settings row beside Notifications, recorded as **D31**, with honest off-state copy (spec debt §9.1 D-1). It remains a UX question and per project rule it wants research before the copy is written, not a default. | **M13** |
| **Q14** | *(conditional on Q22)* **Does the widget get a mark-as-watched control?** A widget that can only open the app is a bookmark, but a widget write must reach `sendProgress`'s serialisation and `SyncCenter`'s replay from a cold process, and the Undo toast — the safety net the write rules assume — cannot be shown on a home screen. | No in v1. Revisit when the write path has a documented process-agnostic entry point. | M13 |
| **Q15** | *(conditional on Q22)* **Does the widget tick, or speak the app's temporal copy?** A `Chronometer` gives a real `H:MM:SS` for free but breaks `TemporalCopy`'s "in 3h 12m" grammar on exactly one surface. | The app's copy. One grammar. | M13 |
| **Q16** | **Long-press context menus.** iOS's platter (blur + lift + menu) has no Android equivalent; a `DropdownMenu` reads differently. Confirm with design before building. | `DropdownMenu` (D4). | M7 |
| **Q17** | **Reduce Motion == snap.** Under "Remove animations" Compose gives the app *no* transitions at all, rather than iOS's 120 ms fade. Accept the platform contract, or force `uiReduced` through? | Accept the platform contract for built-ins; keep `pickMotion` for everything the app drives itself. | M2 |
| **Q18** | **Tablet / foldable.** v1 is portrait-locked with the large-screen opt-out at targetSdk 36. Play's floor moves to 37 around Aug 2027 and the opt-out disappears with it. | Schedule the decision now; nav3's `SceneStrategy` is the designed answer. Do not discover it as a bug in 2027. | — |
| **Q19** | **The monochrome app-icon layer** for Android 13+ themed icons does not exist in the iOS asset set. Someone has to draw it. | Design task, before the first beta. | M14 |
| **Q20** | **Memory-cache budget.** iOS pins 96 MB of decoded bytes; `maxSizePercent(0.25)` on a 192 MB heap is 48 MB. Enough for a Library grid at 3× plus a 2048-px hero? | Instrument `MemoryCache.size`/`maxSize` in a debug build over a Library → Detail → Schedule walk. If it thrashes, drop the top ladder rung 2048 → 1536 and accept a slightly softer billboard rather than `largeHeap`. | M5 |
| **Q21** | **Physical devices for haptics, OEM QA and CHROME FRAME COST.** The emulator cannot vibrate, cannot reproduce OEM battery killers, **and cannot measure the blur band** — the floor AVD takes the no-blur branch by design and the API 36 AVD renders through an M5 GPU under MoltenVK, which says nothing about an Exynos/Dimensity/Adreno-6xx (R5). Which handsets become the reference — a Pixel (best-case LRA) *and* a mid-range Samsung (worst-case), plus a Xiaomi for alarms? | Budget for two, **and name the tier-2 handset explicitly** — it becomes the device M11's 99th-percentile-under-16.6 ms frame budget is measured on, and the device whose failure flips `ScrollEdgeChrome` to the opaque branch for that class. **Haptics cannot be signed off without one; neither can the chrome.** | **M11**, M14 |
| **Q22** | **Does the "Up Next" Glance widget ship at all, and when?** It is **net-new product** (D9/D28) — iOS has never had a home-screen widget — currently costing a `widget/` package, a WorkManager dependency, M13 exit criteria, and Q14/Q15. Combined with Q7's "No", scoping it in would mean v1 ships **zero** of iOS's actual ambient surface (the Live Activity) and one screen iOS has never had. | **Not in v1.** Port the ambient surface that exists first (the Live Update, Q7) and add the widget as a deliberate Android-first feature afterwards, on its own design brief. If it *is* scoped in, it is tracked as new product with its own design review — never inside §4.6's port table, and never as a substitute for D8. | **M13** |
| **Q23** | **The rewatch start-date field.** `spec/detail.md` §10.2 specifies a compact `DatePicker` inside a `GroupedRow`. Android's M3 `DatePicker`/`DatePickerDialog` is a full Material calendar surface — its own headline, Material typography, a `primary` selection ring, 28 dp corners, a mode toggle — inside the one sheet the design system otherwise owns entirely. App-built field, or themed dialog? | **Themed `DatePickerDialog`**, with **every** `DatePickerDefaults.colors` role mapped onto `ThemeColor` (accent as the selection colour), the mapping written out as a token in `design/theme/` and captured in the Component Gallery. A hand-built calendar is a week of work for one row — but **the mapping must be exhaustive and captured, not defaulted**, or this is R37 arriving through the one door §3.1 left open. Either way the trigger row stays a `GroupedRow` at min height 56. | **M10** |
| **Q24** | **Kotlin 2.4.10 or 2.3.21?** KSP 2.3.11 is the newest published KSP and declares `kotlin-stdlib:2.3.20`; KSP2 embeds the Kotlin Analysis API; Hilt codegen is on the M0 critical path; Haze and the Compose BOM are also on the 2.3.20 line. 2.4.10 was pinned on "newest stable" alone. | Attempt 2.4.10 behind the **named M0 gate** (§5). If the gate fails, **pin 2.3.21** — it costs the port nothing and puts the whole stack on one line. Do not leave the pairing implicit. | **M0** |
| **Q25** | **The tier-2 chrome fallback's blast radius.** If the Haze band misses the frame budget on the reference mid-ranger (R5), the surface takes the app's own 1.0 opaque branch **on that device class**. That is a shipping, designed rendering — but it means two visibly different chromes in the field, chosen by device rather than by a user setting. Is the switch automatic (a runtime perf probe), a build-time device-class list, or folded into the D12 toggle's default? | Fold it into `canUseMaterial` as a third input, resolved **once** at startup from a device-class check, so §3.5's "one boolean, resolved once" rule still holds. Never a per-frame decision, and never a reduced radius. | M11 |

---

## 8. Conventions for the agents executing this plan

1. **Read the spec for the area before writing a line of it.** Every spec carries quoted source
   comments explaining *why* a number is what it is; reverting one re-introduces a named bug.
2. **No literal colours, sizes, fonts, radii, shadows or animations in a screen.** Compose from the
   token layer. This is the same rule the iOS app enforces and it is why the port is tractable.
3. **Split every XL file into the named sub-files before starting it.** Six of them are entangled,
   not merely large.
4. **Every number in a spec is a token or a test, never a magic literal at a call site.**
5. **When a spec's prose and its code disagree, the code wins** — three such divergences are flagged
   in the specs (`fmtDayLong`, the `Palette.swift` header comment, the `shelfTitle` size).
6. **Capture on both AVDs after every UI milestone.** A path nobody looks at is a path that ships
   broken; that is the whole reason `PreviouslyFloor_API26` exists.
7. **Never invent a UX answer.** Anything not in a spec or in §7 goes back to the product owner.
8. **A §7 answer that diverges gets a D-number.** The moment a recommended default that changes
   anything a user can see, hear or feel is accepted, write it into §1.3 with the iOS behaviour it
   replaces. §1.3 claims to be exhaustive; that claim is only true if this rule is kept. Four answers
   had already slipped through and are now D27, D29, D30, D31.
9. **Only two files are authoritative for a substitution.** Icons: `spec/icon-mapping.md`, including
   the family, the axes and the vendoring form — **no spec's SF-Symbols risk row is normative** (§3.3).
   Components: §3.1's closed list — **no spec's "Android reproduction" sidebar is normative** (the
   override clause in the header, §9.2). If a spec's sidebar tells you to reach for a Material
   component, a `strings.xml` catalogue, `androidx.palette`, an auto-hiding nav bar or a dropped
   `bottomUnderfill`, it is stale: patch it in place and add it to §9.2.
10. **Never read `MaterialTheme.colorScheme`, `MaterialTheme.typography` or `MaterialTheme.shapes`
    outside `design/theme/` and the named M3 wrapper files.** This is lint-enforced (F10 rule b). It is
    the Android form of rule 2, and the one the iOS codebase never needed.

---

## 9. Spec debt and errata

Two different things live here. **§9.1 is work that does not exist yet** — behaviour the port needs
that no `spec/` file covers, which must be specced *before* the milestone that consumes it starts.
**§9.2 is work that exists but is wrong** — lines already patched in the spec and research files so
that no agent reads stale advice, recorded here so the patches are auditable.

### 9.1 Spec debt — what still needs speccing before implementation

`spec/` currently covers models, appmodel, networking-auth, copy, design tokens, primitives,
primitives-states, icon mapping and the five screens. It covers **nothing** under `notify/` or
`widget/`, and §8 rule 1 tells agents to read the spec for the area before writing a line of it. For
those areas there is no spec to read, so §4.6 is the operative instruction — which is exactly how the
notification design nearly shipped without its two failure branches. Each row below names the
milestone it blocks.

| # | Missing | Why it cannot be improvised | Blocks |
|---|---|---|---|
| **D-1** | **`spec/notifications.md`** — the whole `notify/` package. Must carry: the bucket plan (≤8 buckets / 48 h, 3 per show, 48 total, round-robin), the channel set and their importances, the grouped-post shape, the primer's timing and once-per-install rule, **both exactness branches and what `ArmedAlertStore` records for each (D7a)**, the rearm broadcast set (D7b), the OEM ceiling as user-facing truth (D7c), and **the copy for the degraded state** — the one string that tells a user their reminders are approximate, which does not exist on iOS and therefore is not in `spec/copy.md`. | Without it, an agent executing §4.6 ships alarms that are inexact on every Android 14+ device and vanish on every reboot, while the bell still says armed. The plan's own precedence rule ("this plan wins over a research note") means the research note's `RearmReceiver` section does **not** save them. | **M13** |
| **D-2** | **The Live Activity's four strings in `spec/copy.md`.** "Out now", "Next episode", "Aired just now", "Airs at {time}" live outside `Copy.swift` (the widget extension does not bundle the theme or the catalogue) and are catalogued only in `spec/profile-shell.md` §11. They must enter `Copy.kt` and `spec/copy.md` or they arrive as literals inside a notification builder, invisible to F4 and to `CopyAuditTest`. | F4 is "byte-identical strings" enforced by a test over one catalogue. A string outside the catalogue is outside the contract. | **M13** |
| **D-3** | **`spec/live-update.md`** (or a §11 in the notifications spec) — the lock-screen card that `AniTrackWidgets.swift` actually is: layout, the chronometer's behaviour, lead 60 min / linger 15 min, the explicit cancel at `airsAt + 15 min`, and what the four Dynamic Island regions do **not** become. | D8/D9 changed what this file *is*. Nothing describes the Android surface it maps to. | **M13** (or the fast-follow, per Q7) |
| **D-4** | **A widget brief**, if and only if Q22 scopes the widget in. It is new product (D28) and there is no iOS surface to extract from — content rules, refresh grammar, empty state, and the answers to Q14/Q15 all have to be *designed*. | §4.6's row is an engineering recipe, not a design. Building from it produces an Android-only screen nobody specified. | M13 |
| **D-5** | **The degraded-precision and permission copy** for D31's Settings row, and for the primer when the exact-alarm grant is absent. Needs the project's usual research-before-UX pass (Q13). | The row is a control with no iOS twin; there is nothing to port and nothing to copy. | M13 |
| **D-6** | **A `spec/` note for the two new a11y toggles** (D12 Reduce transparency, D13 Differentiate without colour): their labels, their footnotes, their group position beside Haptics, and the exact set of surfaces each one changes. `spec/profile-shell.md` §8 describes the iOS settings group, which has neither. | M12's exit criterion says the toggles "exist and visibly change the chrome and the amber-only states" — that is a test, not a specification of what changes. | M12 |
| **D-7** | **The `PreviouslySwitch` / `Spinner` / scope-chip / date-field rows in `spec/primitives.md`.** §3.4 now names four components with no iOS original (or with an iOS original whose Android form is a wrapper). They are design-system members and belong in the primitives spec, not only in a plan table. | "One control family per job" is only enforceable if the family is written down. | M5 |
| **D-8** | **The Android M3 role map as a spec artefact** (D32/§3.1). The table lives in this plan; `spec/design-tokens.md` §1.2 stops at the 36 `ThemeColor` tokens and says nothing about the ~30 Material roles that will draw the dialogs, menus, sheets and tab bar. | M2's `ColorSchemeTest` asserts values; something has to be the authority for what those values *are*. | M2 |

### 9.2 Errata applied to the spec and research files

Patched in place on 2026-09-04 so that no agent reads the stale line. Each is a case where a
document's advice conflicts with a decision taken later in this plan; per the header's **override
clause**, the plan wins over a spec's "Android reproduction / risk" sidebar and over any research note.

| File and line | Was | Now | Authority |
|---|---|---|---|
| `spec/discover.md` §11 (palette) | "AndroidX **Palette** on the decoded bitmap — easy" | "Never `androidx.palette`; port `dominantTint` per PLAN §3.6" | §3.6. `androidx.palette` is median-cut on HSL with no OKLab L ∈ [0.30, 0.44] / C ∈ [0.075, 0.145] clamp and no 15 % lean toward brand amber (unit hue 0.4175, 0.9087) — adopting it changes the hue of every `ArtAdaptiveGround`, `PosterSlot` tint and `ArtBackdrop` in the app and deletes the brand lean. |
| `spec/discover.md` §11 (copy) | keep the curly quotes / NBSP / word-joiners "literal in `strings.xml`" | "Kotlin `object` in `:model`, never `strings.xml`" | F4, R31, §4.1. A `strings.xml` round-trip eats U+00A0 / U+2060 / U+2019 / U+00B7. |
| `spec/discover.md` §11, `spec/chrome-images.md` §9.3, `spec/profile-shell.md` §6.2 | a hand-rolled auto-hiding `NavigationBar` on scroll | "Static `NavigationBar` (D10)" | D10. Already a no-op on the iOS floor; a hand-rolled version is a different component. |
| `spec/discover.md` §11 | "the 180-pt underfill can be dropped" | "`bottomUnderfill` is kept (D21)" | D21. Dropping it puts live chevrons in the gesture-nav strip — the exact defect `chrome-images.md` §3.4 documents. |
| `spec/discover.md` §3.1 | "a `TopAppBar` with `title = "Search"`" | app-drawn bar inside `ChromeSurface`'s band | §3.1. `TopAppBar` stacks a second, uncontrolled scroll-hardening layer on `ScrollEdgeChrome`. |
| `spec/chrome-images.md` §1.2 / §9.4 | "two-line `TopAppBar` title slot" | app-drawn two-line title slot (`chromeNavigationSubtitle`'s port) | §3.1. |
| `spec/discover.md` §3.2 / §9.1 | M3 `SingleChoiceSegmentedButtonRow` for the scope bar | the app's own chip row (`FilterChipStyle`), amber for the selected scope | §3.4. Two chip anatomies in one app, with a selected-state encoding that is neither amber nor the app's. |
| `spec/discover.md` §9.5, `spec/today.md` §17.2, `spec/primitives-states.md` §11.1 | M3 `PullToRefreshBox` at its defaults | `PullToRefreshBox` with `indicator = {}` — gesture and `distanceFraction` only | §3.4. Its default indicator is a Material tonal circle drawing its arc in `primary`. |
| `spec/discover.md` §9.2, `spec/schedule.md` §9.1, `spec/chrome-images.md` §9.5, `spec/detail.md` §12.3 | four different `Icons.*` / glyph-name lists | pointer to `spec/icon-mapping.md` | §3.3. Those are the bundled Filled/Outlined set — wrong optical family, GRAD 0, no auto-mirroring, and several names exist only in the banned `material-icons-extended`. |
| `spec/detail.md` §12.4 and `spec/library.md` §8.2 | "iOS AX1 ≈ 1.35×" as the justification for `isAX = 1.3f` | "iOS AX1 / large = **1.647×** (`.body` 17 pt → 28 pt); the Android threshold is 1.3 as a **deliberate divergence** — see PLAN D6a" | D6a. The old number was arithmetically wrong and made a deliberate divergence look like a conversion. |
| `research/typography-icons.md` §8.1 | `windowSplashScreenBackground` = `@color/canvas` (#09090B) | `#000000` | §4.7. Verified against `LaunchBackground.colorset` (r/g/b 0.000) and `Info.plist:54`. A canvas-coloured system splash puts a colour step in front of the app's first frame. |
| `research/widgets-glance.md` §7.1 | `MainActivity` `launchMode="singleTask"` | **`singleTop`** | §2.5. `singleTask` clears the tab stacks on every notification tap; `singleTop` is what `onNewIntent` needs. `research/notifications-liveupdates.md` §3.2 already said `singleTop`. |
| `docs/android-port/TOOLCHAIN.md` (blur section) | "`ro.surface_flinger.supports_background_blur = 1` … the single most important toolchain fact for this port: `RenderEffect`, `Modifier.blur`, Haze can be built and visually verified on this machine" | struck as evidence; replaced with what the property actually gates and with the on-device measurement R5 now requires | R5, §3.5. The property gates SurfaceFlinger's *window* background blur, not HWUI/Skia `RenderNode` effects; `Modifier.blur` is a no-op on API 26 because `RenderEffect` is API 31. |
| `research/verified-versions.md` | no `core-splashscreen`, no DataStore / WorkManager / lifecycle-process; `lifecycle-viewmodel-navigation3` "may still be alpha" | all five added; `lifecycle-viewmodel-navigation3` resolved to stable **2.11.0**; the Kotlin↔KSP line mismatch stated | §2.1, R41. |

---

## 10. Open decisions raised by the 2026-09-04 review

§7 remains the single register — these are **entered there** as Q22–Q25 and are repeated here only so
that a reader who already knew §7 can see what is new, and why each one was invisible before.

| # | New question | Why it did not exist before | Blocks |
|---|---|---|---|
| **Q22** | Does the "Up Next" Glance widget ship at all, and when? | The plan asserted iOS had a "WidgetKit timeline". It does not (D9), so what looked like a port row was net-new product hiding inside §4.6. | M13 |
| **Q23** | App-built date field, or a fully themed `DatePickerDialog`, for the rewatch start date? | `spec/detail.md` specifies a compact `DatePicker` in a `GroupedRow`; nobody had asked what that becomes on Android, and M3's is a full Material calendar surface inside the one sheet the design system owns. | M10 |
| **Q24** | Kotlin 2.4.10 or 2.3.21? | The version table was assembled artifact-by-artifact on "newest stable", so the Kotlin↔KSP **pairing** was never a question anyone asked. | M0 |
| **Q25** | If the Haze band misses its frame budget on the reference mid-ranger, how is the opaque fallback selected — runtime probe, device-class list, or folded into the D12 toggle? | The blur risk was recorded as "verified possible on this machine" against a property that does not gate it (R5), so the *cost* question — and therefore the fallback's blast radius — never arose. | M11 |

Four further decisions were **already taken but never recorded**, and are now D-numbered rather than
re-opened: the sign-in surface (**D27**, and it is re-opened as a fidelity question in Q2(b)), the
"leaves the app" glyph (**D29**), `RecapBeat.id` (**D30**), and the exact-alarm Settings row (**D31**).
Two more were promoted out of §7's "recommended default" framing into blocking decisions because the
default did not survive contact with the platform: the **exact-alarm grant** (Q13 → D7a/D7b/D7c) and
**Clerk account linking for Apple private-relay identities** (Q2(d)).
