# DECISION (product owner, 2026-09-04): minSdk = 26

**This supersedes the `minSdk 31` recommendation in `compose-architecture.md` §1.** That note argued
for 31 on the grounds that the design is blur-dependent and "below 31 you ship a visually different
app." The premise is true; the conclusion is not, because **the app already ships a sanctioned
no-blur variant** and always has.

## The reasoning

`ThemeMetrics.chromeBarOpacity` is `0.74` — a hardened bar is canvas *over* a live blur. But
`ScrollEdgeChrome.veil` already has a second, fully designed branch: under **Reduce Transparency**
there is no material at all, and the bar becomes **opaque canvas (1.0)**. From `ThemeTokens.swift`:

> At 1.0 the top ~100 pt of every scrolled screen was a flat #09090B rectangle with a 28-pt edge …
> and the `.ultraThinMaterial` painted under it was doing nothing at all. **Reduce Transparency
> drops the material, so it gets the opaque bar back.**

So "no blur available" is not an unhandled state that degrades the design — it is an accessibility
mode the design system already answers, deliberately, with a coherent result. Pre-31 Android devices
take **exactly that path**. Nothing new needs designing, and no screen needs a second layout.

Given that, a 31 floor would have discarded roughly a fifth of active Android devices to avoid
reusing a code path that must exist regardless. It also would have been out of step with the
project's own platform philosophy: the iOS floor is 18 precisely because it *reaches every device
iOS 26 excludes* (see `CLAUDE.md` and the `ios-18-floor-decision` note). 26 is the Android
expression of the same instinct.

## Why 26 is a naturally clean line

Three platform features the app needs unconditionally all arrive at **exactly API 26**, so the floor
removes three compatibility branches rather than adding any:

| Feature | Available from | Consequence at minSdk 26 |
|---|---|---|
| **`java.time`** (`Instant`, `ZoneId`, `LocalDate`, `ZonedDateTime`) | API 26 | The whole `Formatting` / `TemporalCopy` time substrate — day keys, `dayDiff`, the two-calendar anchor system — ports natively. **No core-library desugaring required for `java.time`.** (Desugaring may still be wanted for other reasons; that is a separate call.) |
| **Adaptive launcher icons** | API 26 | `icon/background.svg` + `foreground.svg` map straight onto the adaptive icon with no legacy-icon fallback path. |
| **Notification channels** | API 26 | Channels are *mandatory* from 26, so the code creates them unconditionally — no `if (SDK_INT >= O)` branch anywhere in the notification layer. |

## What this obliges the implementation to do

1. **`Modifier.blur` is a silent no-op below API 31.** This is the trap. Compose does not throw and
   does not warn — the blur is simply not applied, so a naive call yields a *transparent* bar rather
   than a frosted one, which is the one outcome the design forbids. Every chrome surface must branch
   **explicitly** on `Build.VERSION.SDK_INT >= 31`, exactly as the iOS side routes every iOS 26 API
   through `GlassHelpers.swift` rather than calling it from a screen. Create the Android analogue —
   a single `ChromeSurface` file that is the one home for "blur where available, opaque canvas
   otherwise" — and let no screen decide for itself.
2. **Treat "device cannot blur" and "user asked for reduced transparency" as one state.** One
   boolean, resolved once (`canUseMaterial = SDK_INT >= 31 && !reduceTransparency`), consumed
   everywhere. Two independent conditions producing the same visual would drift apart.
3. **Verify the floor against every dependency.** Clerk's Android SDK declares `minSdk 24`, so it is
   satisfied. Confirm the declared `minSdk` of Glance, Coil 3, and the Media3/WebView usage for the
   trailer sheet before locking the number in `build.gradle.kts`.
4. **Below 31 there is also no `RenderEffect`** for the hero bloom / art-adaptive wash. Those must
   degrade to a plain gradient over the extracted palette colour rather than a blurred bitmap —
   which is close to what the wash already is.
5. **The emulator on this machine is API 36.** A pre-31 AVD (API 26–30) must be added to the QA
   matrix or the no-blur path will never actually be looked at. Add it before the first chrome work
   lands, not after.

## Open sub-question, not blocking

Whether `targetSdk` stays 36 for v1 is unaffected by this decision and remains as
`compose-architecture.md` proposed.
