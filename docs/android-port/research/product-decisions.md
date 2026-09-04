# Product-owner decisions (2026-09-04)

Taken by the product owner at kickoff. These are settled — implement against them, do not re-open.
`minsdk-decision.md` holds the minSdk call separately because it overrides a research recommendation.

## 1. Fidelity: same look, Android reflexes

> **Superseded in part by `fidelity-line.md`** (same day, later). Read that first: it settles who
> wins when iOS and Android disagree about *rendering*. In short — port the meaning, render with
> native means, re-tune the numbers. "Pixel-match" below means the **design law**, not iOS's
> numeric values.

Match the design law in `CLAUDE.md` — dark canvas, amber rationed to MEANING and STATE and
never to action, Outfit as the voice, the hero slate grammar, material bars, custom toasts, rationed
prose, consumer-not-SaaS states. **Do not adopt Material defaults**: no `MaterialTheme` as the app
theme, no dynamic colour, no Material typography, no FAB, no `Snackbar` in place of the custom
toast, no `TopAppBar` tonal elevation, no default ripple where the design says otherwise.

But **use Android reflexes where a user's hands expect them**:

| Use the Android idiom | Not the iOS one |
|---|---|
| Predictive back gesture | Edge-swipe-only back |
| System share sheet (`Intent.ACTION_SEND`) | A copied iOS share box-and-arrow |
| Android notification model (channels, groups, bundling) | A 1:1 clone of `UNNotificationRequest` behaviour |
| Glance widget shape and update cadence | WidgetKit timeline semantics |
| `sp` text scaling + Android 14+ non-linear font scaling | A fixed reimplementation of Dynamic Type |

## 2. V1 scope: full parity

All five tabs; Detail with all four enrichment shelves (Trailers, Cast & crew, More like this,
Where to watch); rewatch; search; profile and settings; Clerk auth; the offline library cache; the
write policy including `WriteIntent` replay; episode alerts; and the home-screen widget.

**One deliberate exception, added later the same day: the Live-Update countdown is deferred — see
§8.** Everything else ships in v1.

## 3. `applicationId` = `com.anitrack.app`

**Permanent — it can never change after the first Play upload.**

Mirrors the iOS bundle id exactly. Play and App Store namespaces are independent, so there is no
collision, and analytics / crash reporting / internal tooling line up one-to-one across the two
platforms. The user-visible name stays **"Previously."** (`android:label`); `applicationId` is never
shown to anyone.

The widget process gets `com.anitrack.app.widgets` if a separate id is ever needed, matching the iOS
extension's `com.anitrack.app.widgets`.

## 4. Exact alarms: ask contextually, degrade gracefully

The constraint, restated so nobody re-litigates it:

- `USE_EXACT_ALARM` (auto-granted, non-revocable) is **forbidden by Play policy** for this app — that
  permission is reserved for apps whose core function is alarms, timers or calendars. Declaring it
  is a review rejection.
- `SCHEDULE_EXACT_ALARM` is **denied by default** on Android 14+ for apps targeting API 33+, and
  there is no in-app dialog for it — the only route is a deep link to system Settings.

**Decision — three obligations:**

1. **The app must be correct without the permission.** Inexact alarms
   (`setAndAllowWhileIdle`) are the baseline. An alert may land late in Doze; nothing may break,
   and no screen may claim a precision the app does not have.
2. **Ask contextually and late** — when someone turns on alerts for an airing show, which is the
   same moment the iOS app asks for notification permission. Never at launch. One time; if declined,
   do not ask again (a Settings row remains as the way back in).
3. **Wording states the benefit, not the mechanism.** Per the copy voice laws, this is a fact about
   the user's episodes, not a lecture about `AlarmManager`.

Note this composes with the bucketed-alarm architecture in `notifications-liveupdates.md`: one alarm
per air-time bucket, not one per episode. Buckets matter *more* without exact alarms, because Doze
coalescing hurts a burst of alarms far worse than a single one.

## 5. Where the app knowingly diverges from iOS

Record these so they read as decisions, not bugs:

| iOS | Android | Why |
|---|---|---|
| Live Activity (Lock Screen + Dynamic Island) | Live Update notification, API 36+; plain ongoing notification below | Android has no Dynamic Island. Samsung One UI 8 ingests the standard Live Updates API into the Now Bar, so reach is better than it first appears. |
| Blur-backed material bars everywhere | Blur on API 31+; opaque-canvas reduce-transparency treatment below | `Modifier.blur` is a silent no-op below 31. See `minsdk-decision.md`. |
| Notification fires at the exact second | May be late without the exact-alarm permission | Play policy + Android 14 default-deny. See §4. |
| `square.and.arrow.up` share glyph | Material `share` + system share sheet | §1, Android reflexes. |

---

## 6. Clerk: stay on the `pk_test_` dev instance through both betas

**Decided knowing the costs**, which are recorded here so they are never a surprise:

1. **100-user cap is SHARED across iOS and Android.** It is one Clerk instance, so TestFlight
   testers and Android internal testers draw from the same 100. Plan the two beta lists together.
2. **Every beta account is destroyed at the production switch.** There is no dev → production
   migration in Clerk. When `pk_live_` is eventually cut, all beta users re-register and their
   libraries — subscriptions and per-part progress — are orphaned server-side, keyed to Clerk ids
   that no longer exist.
3. **Server-side consequence to check before the switch:** `users` rows are keyed on the Clerk id.
   A production cutover therefore needs either a deliberate wipe or an id-remap script. Decide which
   *before* cutting production, not after. This is a `server/` task, not an Android one.
4. **Verify before beta:** dev instances typically use Clerk's *shared* OAuth credentials for social
   providers, which means the Google/Apple consent screen may show Clerk's name rather than
   "Previously." Confirm this against the current Clerk docs and decide whether it is acceptable for
   external testers — it is a trust signal on the first screen a new user ever sees.

Nothing about this blocks Android work: the Android app points at the same publishable key the iOS
app already uses, which is exactly what makes accounts shared.

## 7. Sign-in surface: Clerk's `AuthView` + `ClerkTheme`

Prebuilt Compose component, themed to the palette. Parity with iOS, which also leans on Clerk's UI.

**Accepted divergence:** `AuthView` is someone else's component and will *not* honour the design law
exactly — Outfit, the amber-is-never-an-action rule, and the button anatomy are all outside our
control inside it. Theme it as close as `ClerkTheme` allows, and treat any remaining gap as a known
divergence rather than a bug. If it turns out to look foreign enough to matter, the escape hatch is
a custom flow against `clerk-android-api` directly — a few days, not a re-architecture.

## 8. Live Updates: deferred to a fast follow

**This narrows the "full parity" scope decision in §2, deliberately.**

The T-0 episode notification is the feature; the Live Update countdown is a garnish that, at
`minSdk 26`, most users would never see (API 36+ only), with sparse adoption and thin OEM QA. Ship
the notification in v1 and add Live Updates once there is a physical device to test it on.

Consistent with the fidelity line (`fidelity-line.md`): do not spend heavy engineering reaching for
an iOS affordance Android answers weakly.

**Still in v1:** the home-screen widget, and all scheduled episode alerts including the bucketed
alarm architecture and the contextual exact-alarm ask.
