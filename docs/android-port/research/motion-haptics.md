# Motion, gestures and haptics on Android

**Status:** research decision note · **Written:** 2026-09-04 · **Owner:** Android port
**Scope:** reproducing *Previously.*'s motion language (`ThemeMotion`), its scroll-offset
architecture (`ScrollOffset` / `onGeometryChange` probes / `ArtHeader(drift:)`), its gestures, and
its haptic vocabulary (`FeedbackToken` / `FeedbackCoordinator`) in Kotlin + Jetpack Compose.

---

## 1. Recommendation

**Port the motion tokens as *numbers*, not as vibes — the conversion is exact and lossless.** Then
diverge deliberately in exactly three places, because Android's platform semantics differ from
iOS's and pretending otherwise produces bugs, not parity.

### 1.1 What to build

| Layer | Decision |
|---|---|
| **Motion tokens** | Hand-port `ThemeMotion` to a Kotlin `object AppMotion` of `AnimationSpec<T>` factories. `spring(response:dampingFraction:)` → `spring(dampingRatio, stiffness)` via **`stiffness = (2π/response)²`, `dampingRatio = dampingFraction`** (mass = 1 on both sides — see §3.1). Two of the app's bespoke cubic-Béziers are *already* Compose constants: `uiReveal` == `EaseOutQuint`, `uiSweep` == `FastOutSlowInEasing`. |
| **Material's MotionScheme** | **Do not adopt.** `MaterialTheme.motionScheme` (standard / expressive) is a fine system, but it is a *different* system from the one already shipped and QA'd on iOS. Keep `AppMotion`; the app's springs sit between Material `standard` and `expressive` anyway (§3.3). |
| **Reduce Motion** | Compose already zeroes every animation when the user turns on **Settings → Accessibility → Remove animations** — it reads `Settings.Global.ANIMATOR_DURATION_SCALE` into the Recomposer's coroutine context and animations *snap to their end value* (§4). Accept that; do **not** try to reproduce iOS's `uiReduced` 120 ms cross-fade. **But you must still gate decorative loops yourself**, or the drift and the breathing wordmark freeze at their *end* value (art permanently 7 % over-scaled). |
| **Scroll-driven UI** | The iOS `ScrollOffset` object maps to a `MutableFloatState` written by a `NestedScrollConnection` and read **only inside lambda modifiers** (`Modifier.graphicsLayer { }`, `Modifier.offset { }`, `Modifier.drawBehind { }`). Bool probes (`raisedTop`, `scrolledUnderBar`) go through `derivedStateOf`. The 18 `onGeometryChange` probes map to **`Modifier.onLayoutRectChanged(throttleMillis, debounceMillis)`** (Compose 1.8+), which is the cheap, debounced equivalent. §5. |
| **Drift** | `rememberInfiniteTransition` + `infiniteRepeatable(tween(24_000, easing = EaseInOut), RepeatMode.Reverse)` read inside `graphicsLayer { }` — one transform on one RenderNode, no recomposition, no re-record. Gate on reduce-motion **and** on visibility. §6. |
| **Shared-element / container transform** | **Ship without it.** `SharedTransitionLayout` is stable (animation 1.10.0, 3 Dec 2025) and Navigation3 wires it up, but the iOS side *tried* the zoom transition on 2 Sep and **retired it on 3 Sep** — "it scales the whole page into the tapped poster, so the show page opened as a miniature of itself inflating" (CLAUDE.md). Detail is a plain push on both platforms. §8. |
| **Predictive back** | Mandatory, not optional: targeting API 36 (Play requires it from **31 Aug 2026**) means `onBackPressed()` is never called. Use `BackHandler` / `PredictiveBackHandler` from `activity-compose`, and let Navigation3 (1.1.7) drive the in-app back animation. §8.2. |
| **Haptics** | Default path is **`LocalHapticFeedback` → `HapticFeedbackType`** (Compose 1.8+ has all 13 types), which routes through `ViewCompat.performHapticFeedback` → `HapticFeedbackConstantsCompat`. **No `VIBRATE` permission, documented per-API-level fallbacks, honours the system touch-feedback setting.** Map the 7 `FeedbackToken`s to 5 constants (§9.2). Port `FeedbackCoordinator`'s per-token throttle verbatim. Reach for `Vibrator` + `VibrationEffect.Composition` in **one** place only (the milestone), gated on `arePrimitivesSupported`. |

### 1.2 The three deliberate divergences

1. **Reduce Motion snaps, it does not shorten.** iOS keeps a 120 ms ease-out; Android's setting is called *Remove* animations and the platform means it. Follow the platform.
2. **The hero cannot stretch on pull-down the way it does on iOS.** Android's scroll containers clamp at 0 and render a *stretch shader* on the container instead of yielding a negative offset. `ScrollOffset.stretch` (`max(0, -y)`) has no free equivalent — you either write a custom `OverscrollEffect` or intercept in `NestedScrollConnection.onPreScroll` at the top. §7.3.
3. **Haptic intensity is gone.** iOS fires `.light` at `intensity: 0.65`, `.medium` at `0.72`, `refreshArmed` at `0.50`. `HapticFeedbackConstants` has no scale. You express "lighter" by choosing a *different constant*, not a smaller number. §9.4.

### 1.3 Confidence

**High** on the spring/easing math, the Compose reduce-motion mechanism (read from AndroidX source),
the deferred-read architecture, and the haptic constant mapping + its compat fallbacks (read from
`HapticFeedbackConstantsCompat.java`).
**Medium** on which haptic constant *feels* right per token — that is a physical-device judgement
call, and **the QA emulator has no vibrator at all** (§9.6), which is a real blocker listed in §11.
**Medium** on whether `MotionScheme` is stable in the material3 version you will actually pin (§2).

---

## 2. Versions (all verified 2026-09-04)

| Artifact | Latest stable | Date | Source |
|---|---|---|---|
| `androidx.compose:compose-bom` | **2026.08.00** | 2026-08-12 | [Compose Aug '26 release blog](https://android-developers.googleblog.com/2026/08/jetpack-compose-august-2026-release.html) |
| `androidx.compose.animation:*` | **1.12.0** (1.13.0-alpha02 on 2026-08-26) | 2026-08-12 | [compose-animation release notes](https://developer.android.com/jetpack/androidx/releases/compose-animation) |
| `androidx.compose.ui:*` | **1.12.0** | 2026-08-12 | [compose-ui release notes](https://developer.android.com/jetpack/androidx/releases/compose-ui) |
| `androidx.compose.foundation:*` | **1.12.0** | 2026-08-12 | [compose-foundation release notes](https://developer.android.com/jetpack/androidx/releases/compose-foundation) |
| `androidx.compose.material3:material3` | **1.4.0** | 2026-08-26 | [compose-material3 release notes](https://developer.android.com/jetpack/androidx/releases/compose-material3) |
| `androidx.navigation3:*` | **1.1.7** | 2026-08-26 | [navigation3 release notes](https://developer.android.com/jetpack/androidx/releases/navigation3) |

Milestones that matter here:

- **`SharedTransitionLayout` became stable in animation `1.10.0`** (2025-12-03). `LookaheadScope` had been stable since `1.7.0-alpha08` (2024-05-01).
- **`MotionScheme` was promoted to stable in material3 `1.5.0-alpha15`** (`If822f`). In the **1.4.0 stable** line it is still behind `@ExperimentalMaterial3ExpressiveApi`. *Verify at build time* — see §11.
- **Compose 1.8 (2025-04-23)** added the expanded `HapticFeedbackType` set and `Modifier.onLayoutRectChanged`.
- **Compose 1.12 (2026-08-12)** graduated `DeferredTargetAnimation` and added `DeferredAnimatedContent` / `DeferredAnimatedVisibility` — "two-stage transitions" with gesture→animation **velocity handoff**, explicitly aimed at predictive back. It also added `SoundEffectOnInteraction` (interaction *sounds*, not haptics).

The Android toolchain note (`docs/android-port/TOOLCHAIN.md`) pins the emulator at API 36
(Android 16), Gradle 9.7.1 / Kotlin 2.4.0, JDK 21. Everything below compiles against that.

---

## 3. Motion: SwiftUI → Compose

### 3.1 The spring conversion is exact

Both systems model a damped harmonic oscillator with **mass normalised to 1** — only `k/m` and `c/m`
affect the trajectory, so normalising is lossless, not an approximation.

- SwiftUI's legacy `Animation.spring(response:dampingFraction:blendDuration:)` (the API this app
  uses — 4 of its tokens) is defined by `stiffness = (2π / response)²`, `damping = 4π·ζ / response`,
  `mass = 1`. (The same conversion `UISpringTimingParameters` uses;
  [reference implementation](https://gist.github.com/edwardsanchez/a46c0eb6fbc5030541a23bd67e543de9).)
- Compose's `spring(dampingRatio, stiffness)` takes `stiffness = k/m` and
  `dampingRatio = c / (2√(k·m))`.

Substituting: `dampingRatio = (4π·ζ/response) / (2 · 2π/response) = ζ`. **The damping fraction
carries over 1:1; only the stiffness needs converting.**

```
stiffness   = (2 * PI / response)^2
dampingRatio = dampingFraction
```

> ⚠️ This holds for `spring(response:dampingFraction:)`. It does **not** hold for SwiftUI's newer
> `.spring(duration:bounce:)`, whose `duration` is a *perceptual* duration that only equals
> `response` when `bounce >= 0`. `ThemeTokens.swift` uses `response:` throughout, so the mapping
> above is exact for this codebase.

### 3.2 The full token table

Every value below is computed from `ios/Sources/DesignSystem/ThemeTokens.swift` (`enum ThemeMotion`).

| `ThemeMotion` | SwiftUI | Compose | Note |
|---|---|---|---|
| `uiPress` | `easeOut(duration: 0.09)` | `tween(90, easing = EaseOut)` | `EaseOut` == `CubicBezierEasing(0f, 0f, 0.58f, 1f)`, byte-identical to CoreAnimation's `easeOut` |
| `uiMicro` | `spring(0.22, 0.88)` | `spring(dampingRatio = 0.88f, stiffness = 815.7f)` | ≈213 ms settle |
| `uiSnappy` | `spring(0.34, 0.84)` | `spring(dampingRatio = 0.84f, stiffness = 341.5f)` | ≈336 ms |
| `uiSettle` | `spring(0.46, 0.90)` | `spring(dampingRatio = 0.90f, stiffness = 186.6f)` | ≈442 ms |
| `uiMilestone` | `spring(0.38, 0.74)` | `spring(dampingRatio = 0.74f, stiffness = 273.4f)` | ≈409 ms, the one overshoot |
| `uiGentle` | `easeInOut(0.22)` | `tween(220, easing = EaseInOut)` | `EaseInOut` == `(0.42, 0, 0.58, 1)` |
| `uiReveal` | `timingCurve(0.22, 1.00, 0.36, 1.00, 0.28)` | `tween(280, easing = EaseOutQuint)` | **exact match** — Compose's `EaseOutQuint` *is* `CubicBezierEasing(0.22f, 1f, 0.36f, 1f)` |
| `uiPoster` | `easeOut(0.18)` | `tween(180, easing = EaseOut)` | |
| `uiNumeric` | `easeOut(0.22)` | `tween(220, easing = EaseOut)` | |
| `uiSweep` | `timingCurve(0.40, 0.00, 0.20, 1.00, 0.52)` | `tween(520, easing = FastOutSlowInEasing)` | **exact match** — `FastOutSlowInEasing` *is* `CubicBezierEasing(0.4f, 0f, 0.2f, 1f)`. The iOS app was already drawing Material's standard curve. |
| `uiDismiss` | `easeIn(0.16)` | `tween(160, easing = EaseIn)` | `EaseIn` == `(0.42, 0, 1, 1)` |
| `uiLiveBreath` | `easeInOut(1.8).repeatForever(autoreverses: true)` | `infiniteRepeatable(tween(1800, easing = EaseInOut), RepeatMode.Reverse)` | must be gated — §4.3 |
| `uiReduced` | `easeOut(0.12)` | *(deliberately dropped — §4)* | |

Easing constants verified against
[`EasingFunctions.kt`](https://raw.githubusercontent.com/androidx/androidx/androidx-main/compose/animation/animation-core/src/commonMain/kotlin/androidx/compose/animation/core/EasingFunctions.kt)
and
[`Easing.kt`](https://raw.githubusercontent.com/androidx/androidx/androidx-main/compose/animation/animation-core/src/commonMain/kotlin/androidx/compose/animation/core/Easing.kt)
(androidx-main, fetched 2026-09-04).

### 3.3 Why not Material's `MotionScheme`

For reference, Material's own token values (from
[`StandardMotionTokens.kt`](https://raw.githubusercontent.com/androidx/androidx/androidx-main/compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/tokens/StandardMotionTokens.kt)
/ `ExpressiveMotionTokens.kt`), expressed back in SwiftUI terms:

| Material spec | `stiffness` / `dampingRatio` | == SwiftUI |
|---|---|---|
| standard `fastSpatial` | 1400 / 0.9 | `spring(response: 0.168, dampingFraction: 0.9)` |
| standard `defaultSpatial` | 700 / 0.9 | `spring(0.237, 0.9)` |
| standard `slowSpatial` | 300 / 0.9 | `spring(0.363, 0.9)` |
| standard `defaultEffects` | 1600 / 1.0 | `spring(0.157, 1.0)` |
| expressive `defaultSpatial` | 380 / 0.8 | `spring(0.322, 0.8)` |
| expressive `fastSpatial` | 800 / 0.6 | `spring(0.222, 0.6)` — visible bounce |

The app's `uiMicro`/`uiSnappy`/`uiSettle` (0.22 / 0.34 / 0.46 at ζ 0.84–0.90) land almost exactly on
Material **standard**'s fast/default/slow spatial ladder, which is a good sign the language is not
alien to Android. But `MotionScheme` is a *theme* input consumed by every Material component; adopting
it would mean re-tuning against Material's ladder rather than porting the one that shipped. Keep
`AppMotion`, and pass its specs explicitly where a Material component takes an `AnimationSpec`.

### 3.4 The token file

```kotlin
// ui/theme/AppMotion.kt
package app.previously.ui.theme

import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.EaseIn
import androidx.compose.animation.core.EaseInOut
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.EaseOutQuint
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween

/**
 * The iOS `ThemeMotion` table, converted 1:1.
 *
 *   stiffness    = (2*PI / response)^2
 *   dampingRatio = dampingFraction          (identical parameterisation, mass = 1 both sides)
 *
 * These are functions, not vals, because an AnimationSpec<T> is generic in T and Compose's
 * `spring()` needs the right `visibilityThreshold` for the value type. Call `AppMotion.settle<Dp>()`.
 */
object AppMotion {
    /** Touch compression only. */
    fun <T> press(): FiniteAnimationSpec<T> = tween(90, easing = EaseOut)

    /** Checkmarks, icon replacement, chip selection, status change. */
    fun <T> micro(): FiniteAnimationSpec<T> = spring(dampingRatio = 0.88f, stiffness = 815.7f)

    /** Fast local layout changes and user-requested expansion. */
    fun <T> snappy(): FiniteAnimationSpec<T> = spring(dampingRatio = 0.84f, stiffness = 341.5f)

    /** Large but controlled card-to-card or source-to-destination motion. */
    fun <T> settle(): FiniteAnimationSpec<T> = spring(dampingRatio = 0.90f, stiffness = 186.6f)

    /** One restrained overshoot for a meaningful milestone (series complete only). */
    fun <T> milestone(): FiniteAnimationSpec<T> = spring(dampingRatio = 0.74f, stiffness = 273.4f)

    /** State fades, stale strips, error notices, NOW movement. */
    fun <T> gentle(): FiniteAnimationSpec<T> = tween(220, easing = EaseInOut)

    /** Initial content reveal. `EaseOutQuint` IS (0.22, 1, 0.36, 1). */
    fun <T> reveal(): FiniteAnimationSpec<T> = tween(280, easing = EaseOutQuint)

    /** Poster tint to final image. */
    fun <T> poster(): FiniteAnimationSpec<T> = tween(180, easing = EaseOut)

    /** Numeric content transition. */
    fun <T> numeric(): FiniteAnimationSpec<T> = tween(220, easing = EaseOut)

    /** Season-complete hairline, History rail. `FastOutSlowInEasing` IS (0.4, 0, 0.2, 1). */
    fun <T> sweep(): FiniteAnimationSpec<T> = tween(520, easing = FastOutSlowInEasing)

    /** Toast dismissal only. */
    fun <T> dismiss(): FiniteAnimationSpec<T> = tween(160, easing = EaseIn)

    /** Wordmark live indicator. NEVER start this without checking LocalReduceMotion — see §4.3. */
    fun liveBreath(): AnimationSpec<Float> =
        infiniteRepeatable(tween(1800, easing = EaseInOut), RepeatMode.Reverse)

    /** Drift on the billboard art: ~7% over 24 s, eased, reversing. */
    fun drift(): AnimationSpec<Float> =
        infiniteRepeatable(tween(24_000, easing = EaseInOut), RepeatMode.Reverse)
}
```

**Gotcha — `visibilityThreshold`.** Compose springs stop when the remaining displacement is under a
threshold. `spring<Float>()` defaults to `Spring.DefaultDisplacementThreshold = 0.01f`, which is
right for an alpha in 0..1 and *far too small* for a float used as a pixel offset (it will keep
ticking frames for tens of milliseconds after it looks settled). Use the typed animation helpers
(`animateDpAsState`, `animateIntOffsetAsState`, …) which inject the right threshold, or pass
`visibilityThreshold` explicitly. Verified constants:
`DampingRatioNoBouncy = 1.0f`, `DampingRatioLowBouncy = 0.75f`, `DampingRatioMediumBouncy = 0.5f`,
`DampingRatioHighBouncy = 0.2f`; `StiffnessHigh = 10000f`, `StiffnessMedium = 1500f`,
`StiffnessMediumLow = 400f`, `StiffnessLow = 200f`, `StiffnessVeryLow = 50f`
([animation-core `api/current.txt`](https://raw.githubusercontent.com/androidx/androidx/androidx-main/compose/animation/animation-core/api/current.txt)).

---

## 4. Reduce Motion

### 4.1 There is no "Reduce Motion" on Android — there is "Remove animations"

iOS's Reduce Motion asks apps to *substitute* cross-fades for movement; the app honours it with
`uiReduced` (120 ms ease-out). Android's equivalent user-facing control is
**Settings → Accessibility → Remove animations**, which zeroes the three global animation scales
(`window_animation_scale`, `transition_animation_scale`, `animator_duration_scale`). The same zero
arrives from Developer options and from Battery Saver. There is no separate "reduce but keep short
fades" state.

### 4.2 Compose already honours it — by snapping

This is not opt-in and it is worth knowing exactly what it does, because the behaviour is *jump to
the end value*, not *skip the animation*.

`WindowRecomposer.android.kt` installs a `MotionDurationScaleImpl` — a `ContentObserver` on
`Settings.Global.ANIMATOR_DURATION_SCALE` — into the Recomposer's coroutine context:

```kotlin
val motionDurationScale = baseContext[MotionDurationScale]
    ?: MotionDurationScaleImpl(context.applicationContext).also { motionDurationScaleImpl = it }
val contextWithClockAndMotionScale =
    baseContext + (pausableClock ?: EmptyCoroutineContext) + motionDurationScale
```

`SuspendAnimation.kt` then reads it per frame:

```kotlin
internal val CoroutineContext.durationScale: Float
    get() = this[MotionDurationScale]?.scaleFactor ?: 1f

val playTimeNanos =
    if (durationScale == 0f) anim.durationNanos
    else ((frameTimeNanos - startTimeNanos) / durationScale).toLong()
```

and `InfiniteTransition.kt`:

```kotlin
if (durationScale == 0f) {
    // Finish right away
    _animations.forEach { it.skipToEnd() }
}
```

(All three from androidx-main, fetched 2026-09-04.)

**Consequence: every `animate*AsState`, `Animatable`, `Transition`, `AnimatedVisibility` and
`AnimatedContent` in the app becomes instant, for free.** That is the correct platform behaviour and
you should accept it. Do **not** override `MotionDurationScale` back to `1f` to get a 120 ms
cross-fade — that overrides an explicit accessibility request.

### 4.3 The bug this creates, and the fix

`skipToEnd()` sets `value = animation.targetValue`. For a *reversing infinite* animation the "target"
is the far end of the loop. So with Remove animations on:

- `ArtHeader(drift: true)` freezes at **scale 1.07** — the billboard art sits permanently 7 % over-scaled
  and off-register, forever, on every screen that draws one.
- The wordmark's live indicator freezes at its bright end, so it reads as permanently "live".

You must therefore keep an explicit reduce-motion signal *in addition to* the free behaviour, and use
it to **not start** decorative loops.

```kotlin
// ui/theme/ReduceMotion.kt
package app.previously.ui.theme

import android.animation.ValueAnimator
import android.content.Context
import android.database.ContentObserver
import android.os.Build
import android.provider.Settings
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext

val LocalReduceMotion = staticCompositionLocalOf { false }

/**
 * True when the user asked for no animation.
 *
 * Settings -> Accessibility -> "Remove animations" (and Developer options, and Battery Saver) set
 * Settings.Global.ANIMATOR_DURATION_SCALE to 0. Compose reads the same key to zero animation
 * durations; we read it too because a *reversing infinite* animation does not stop when durations
 * are zeroed -- it jumps to its far end and stays there (drift would sit at 1.07 forever).
 *
 * NOTE: the key reads back as null when it was never written. null == 1 == "animations on";
 * only an explicit 0 means reduce.
 */
@Composable
fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    var reduced by remember { mutableStateOf(context.animationsRemoved()) }
    DisposableEffect(context) {
        val resolver = context.contentResolver
        val observer = object : ContentObserver(null) {
            override fun onChange(selfChange: Boolean) { reduced = context.animationsRemoved() }
        }
        resolver.registerContentObserver(
            Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE),
            /* notifyForDescendants = */ false,
            observer,
        )
        onDispose { resolver.unregisterContentObserver(observer) }
    }
    return reduced
}

private fun Context.animationsRemoved(): Boolean =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        // Also false under Battery Saver, which is the behaviour we want.
        !ValueAnimator.areAnimatorsEnabled()
    } else {
        Settings.Global.getFloat(contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
```

- `ValueAnimator.areAnimatorsEnabled()` is **API 26+**; its docs: *"can change if either the user
  sets a Developer Option to set the animator duration scale to 0 or by Battery Saver mode being
  enabled"*
  ([reference](https://developer.android.com/reference/android/animation/ValueAnimator#areAnimatorsEnabled())).
- `ValueAnimator.registerDurationScaleChangeListener` exists but is **API 33+**
  ([confirmed `ApiSince=33`](https://learn.microsoft.com/en-us/dotnet/api/android.animation.valueanimator.registerdurationscalechangelistener?view=net-android-36.0)),
  so the `ContentObserver` above is the portable route — and it is exactly what Compose itself does.
- Reading `Settings.Global` needs **no permission**.

Usage:

```kotlin
val scale by rememberInfiniteTransition(label = "drift").animateFloat(
    initialValue = 1f, targetValue = 1.07f, animationSpec = AppMotion.drift(), label = "driftScale",
)
val reduce = LocalReduceMotion.current
Image(
    painter = painter,
    contentDescription = null,
    modifier = Modifier.graphicsLayer {
        // Read the animation INSIDE the layer block: invalidates the layer, not the composition.
        val s = if (reduce) 1f else scale
        scaleX = s; scaleY = s
        transformOrigin = TransformOrigin(0.5f, 0f)   // == SwiftUI anchor: .top
    },
)
```

`rememberInfiniteTransition` is cheap to *have* — it only costs frames while running — but prefer not
even creating it under reduce motion if the composable is on a hot path.

### 4.4 QA

From `docs/android-port/TOOLCHAIN.md` (already verified on this machine):

```bash
adb shell settings put global animator_duration_scale 0
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
# restore
adb shell settings put global animator_duration_scale 1
```

Capture *every* screen with a billboard in this state; the drift freeze is the failure mode to look for.

---

## 5. Scroll-offset-driven UI without recomposing the world

### 5.1 What iOS does, and what it costs

`ScrollOffset` (`Primitives.swift`) is an `@Observable` holding one `CGFloat`, quantised by
`ThemeMetrics.scrollSample` (clamp to `[-320, 240]`, round to 0.5 pt) and de-duplicated. Only
`TodayVeils`, `DetailVeils` and `StretchingHeroArt` read `.y` in a body. Bool probes are guarded with
`if new != old`. The comment in CLAUDE.md is blunt about why: *"The raw offset as `@State` re-ran
Today's entire body at 60–120 Hz on the first swipe."*

### 5.2 The Compose model

Compose has the same hazard with a sharper name: **a state read at phase N invalidates phase N and
every phase below it**. Composition → Layout → Draw. Reading a scroll offset in composition
re-composes the subtree every frame; reading it in a *lambda* modifier defers it to Layout or Draw
and lets Compose skip the phases above. This is the official
[performance best-practices](https://developer.android.com/develop/ui/compose/performance/bestpractices)
guidance, and the doc's own worked example is literally a collapsing toolbar:

```kotlin
@Composable
private fun Title(snack: Snack, scrollProvider: () -> Int) {
    Column(
        modifier = Modifier.offset { IntOffset(x = 0, y = scrollProvider()) }
    ) { /* ... */ }
}
```

So the mapping is:

| iOS | Compose |
|---|---|
| `@Observable ScrollOffset` held in `@State` | `remember { mutableFloatStateOf(0f) }` (or just read `LazyListState` directly) |
| `.y` read in `TodayVeils.body` | read inside `Modifier.drawBehind { }` / `graphicsLayer { }` |
| `veilOpacity` derived getter | read inside the draw lambda, or `derivedStateOf` if it must be a `State` |
| `raisedTop` / `scrolledUnderBar` bools with `if new != old` | `remember { derivedStateOf { … } }` — emits only when the *boolean* flips |
| `ThemeMetrics.scrollSample` quantisation | **not needed** for lambda reads (they never recompose); keep it only for a value that reaches composition |
| `Color.clear.onGeometryChange` probes (18 sites) | `Modifier.onLayoutRectChanged(throttleMillis, debounceMillis) { bounds -> }` |

### 5.3 The concrete architecture

For a `LazyColumn` you cannot ask for "total pixels scrolled" directly. Accumulate it in a
`NestedScrollConnection` — the write is a plain `MutableFloatState`, so it costs nothing until
somebody reads it.

```kotlin
// ui/scroll/ScrollProbe.kt
package app.previously.ui.scroll

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.runtime.*
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource

/**
 * The Compose analogue of iOS `ScrollOffset`.
 *
 * `y` is snapshot state, so anything that reads it is invalidated -- which is exactly why NOTHING
 * may read it during composition. Read it inside graphicsLayer{} / drawBehind{} / offset{} lambdas
 * (deferred to layout or draw), or behind derivedStateOf when you only need a threshold crossing.
 */
@Stable
class ScrollProbe {
    var y by mutableFloatStateOf(0f)
        private set

    /** Pull-down distance, for a hero stretch. Always 0 unless something feeds it -- see §7.3. */
    var overpull by mutableFloatStateOf(0f)
        internal set

    internal fun consume(dy: Float) {
        val next = (y - dy).coerceIn(0f, 4000f)
        if (next != y) y = next
    }

    /** 0 while the hero owns the status bar, 1 once anything is close enough to touch the clock. */
    fun veilAlpha(): Float = ((y - 16f) / 64f).coerceIn(0f, 1f)
}

@Composable
fun rememberScrollProbe(): Pair<ScrollProbe, NestedScrollConnection> {
    val probe = remember { ScrollProbe() }
    val connection = remember(probe) {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                probe.consume(available.y)
                return Offset.Zero              // observe only; do not consume
            }
        }
    }
    return probe to connection
}
```

Wiring, and the two read sites:

```kotlin
@Composable
fun TodayScreen() {
    val (probe, nested) = rememberScrollProbe()
    val listState = rememberLazyListState()

    // Bool probe: recomposes ONLY when the boolean flips. The Compose equivalent of `if new != old`.
    val barHardened by remember(probe) {
        derivedStateOf { probe.y > ThemeMetrics.inlineBarBottom + BarEdgeRamp }
    }

    Box(Modifier.fillMaxSize().nestedScroll(nested)) {
        LazyColumn(state = listState) { /* ... */ }

        // The veil: reads probe.y in the DRAW phase. No recomposition, no relayout.
        Spacer(
            Modifier
                .fillMaxWidth()
                .height(ThemeMetrics.rootWashHeight)
                .drawBehind {
                    drawRect(color = ThemeColor.canvas, alpha = probe.veilAlpha())
                }
        )

        TopBar(hardened = barHardened)   // recomposes twice per screen, not 120x per second
    }
}
```

### 5.4 `onLayoutRectChanged` — the `onGeometryChange` replacement

The 18 iOS scroll probes exist because `onScrollGeometryChange` never fires on the iOS 27 simulator.
On Android the analogue is `Modifier.onGloballyPositioned`, which is the *expensive* one. Compose 1.8
added the cheap one:

```kotlin
Modifier.onLayoutRectChanged(
    throttleMillis = 32L,       // at most ~2 frames
    debounceMillis = 0L,
) { bounds: RelativeLayoutBounds ->
    // bounds.boundsInRoot / bounds.boundsInWindow / bounds.fractionVisibleIn(viewport)
}
```

Signature verified in
[compose-ui `api/current.txt`](https://raw.githubusercontent.com/androidx/androidx/androidx-main/compose/ui/ui/api/current.txt).
The April '25 release blog states it *"solves many use cases that the existing onGloballyPositioned
modifier does; however, it does so with much less overhead"* and explicitly supports throttling and
debouncing "for performance optimization in scrollable lists". Use it for Detail's `copyTop` measurement
(the hero-copy-reaches-the-bar probe) and for Schedule's day-header tracking.

Note the callback is **not** a composable scope — write into a `MutableFloatState`, never into a
`var` you then read in composition.

### 5.5 When to reach for `Modifier.Node`

Rarely. `drawBehind`/`graphicsLayer`/`offset` lambdas already give phase-deferred reads. Drop to
[`Modifier.Node`](https://developer.android.com/develop/ui/compose/custom-modifiers) when you need
*fine-grained invalidation control* — a node that both measures and draws, where a colour change
must invalidate draw but not measurement:

```kotlin
class VeilNode(var alpha: Float) : Modifier.Node(), DrawModifierNode {
    override val shouldAutoInvalidate: Boolean get() = false
    fun update(newAlpha: Float) {
        if (alpha != newAlpha) { alpha = newAlpha; invalidateDraw() }   // draw only
    }
    override fun ContentDrawScope.draw() { drawRect(Color.Black, alpha = alpha); drawContent() }
}
```

The official doc is explicit that `composed { }` "is no longer recommended due to performance issues"
and `Modifier.Node` is the supported way to write a custom modifier. But for this app's scroll work,
**you should not need one** — that is the honest answer, and building one first is premature.

### 5.6 How to prove it

- Layout Inspector → **Recomposition counts**. Today's screen root must not tick during a swipe.
- `adb shell dumpsys gfxinfo <pkg> framestats` for jank.
- Compose compiler metrics (`-P plugin:androidx.compose.compiler.plugins.kotlin:reportsDestination`)
  to confirm the screen composables are skippable.

---

## 6. The drift

iOS: `ArtHeader(drift: true)` scales the sharp layer ~7 % over 24 s, eased, reversing, off under
Reduce Motion, **one transform on one layer**, on Today and Detail only.

Compose does this with `rememberInfiniteTransition` (§4.3 shows the code). The parity properties:

| Property | iOS | Compose |
|---|---|---|
| One transform, one layer | `.scaleEffect` on the sharp layer | `Modifier.graphicsLayer { scaleX/scaleY }` — the RenderNode transform, content is not re-recorded |
| No recomposition | only `StretchingHeroArt` reads it | the animation `State` is read **inside** the layer lambda |
| Anchor | `.top` / `.bottom` / `.center` via `driftAnchor` | `transformOrigin = TransformOrigin(0.5f, 0f / 0.5f / 1f)` |
| Off under reduce motion | `.task(id: drift && !reduceMotion)` | `LocalReduceMotion` gate — **required**, §4.3 |
| Stops offscreen | SwiftUI cancels the `.task` | Compose stops the frame clock when the window is not visible; the transition also stops when the composable leaves composition. **Verify** with `dumpsys gfxinfo` while the app is backgrounded. |

One real cost difference: on iOS a `CABasicAnimation` is handed to the render server and runs without
the app process; in Compose an infinite transition ticks on the UI thread every frame (`withFrameNanos`).
For a single float feeding a `graphicsLayer` this is a few microseconds per frame and is fine — but it
means the process never idles while a hero is on screen. If battery telemetry ever flags it, the fallback
is to run the drift only for the first N seconds after the screen appears rather than forever.

---

## 7. Gestures

The iOS app's actual gesture surface (grepped from `ios/Sources`, 2026-09-04):
`refreshable` ×4, `contextMenu` ×4, one `DragGesture` (Library's A–Z index rail),
`scrollTargetBehavior(.viewAligned)` ×2 (Library's shelves), `scrollPosition` ×2,
`onScrollTargetVisibilityChange` ×2 (Schedule), `onGeometryChange` ×18. No `swipeActions`, no
`onLongPressGesture`, no `matchedGeometryEffect`, no `sensoryFeedback`.

| iOS | Compose | Notes |
|---|---|---|
| `.refreshable { }` | `PullToRefreshBox` (material3) | See §7.2 — the arming haptic needs hand-wiring |
| `.contextMenu { }` | `Modifier.combinedClickable(onLongClick = …)` + a `DropdownMenu`, or M3 `ModalBottomSheet` | Android has no system context-menu-on-long-press affordance; a menu anchored at the row is the convention |
| `DragGesture(minimumDistance: 0)` on the index rail | `Modifier.pointerInput { detectDragGestures / awaitPointerEventScope }`, then `LazyListState.scrollToItem` | Fire `SegmentTick` per section — §9 |
| `.scrollTargetBehavior(.viewAligned)` | `LazyRow(flingBehavior = rememberSnapFlingBehavior(rememberSnapLayoutInfoProvider(state)))` | `androidx.compose.foundation.gestures.snapping` |
| `.scrollPosition` / `.onScrollTargetVisibilityChange` | `LazyListState.layoutInfo.visibleItemsInfo` behind `derivedStateOf`, or `snapshotFlow { … }.distinctUntilChanged()` | For Schedule's "which day is at the top" |
| `.tabBarMinimizeBehavior(.onScrollDown)` | `FloatingToolbarDefaults.floatingToolbarVerticalNestedScroll(expanded, onExpand, onCollapse)` or a hand-rolled `NestedScrollConnection` that animates the `NavigationBar` height | M3 has `FloatingToolbarScrollBehavior` / `exitAlwaysScrollBehavior`; a plain `NavigationBar` has no built-in minimize |
| Bar hardening at `topHold + barEdgeRamp` | `TopAppBarScrollBehavior` (`TopAppBarState.collapsedFraction` / `heightOffset`) **or** the `ScrollProbe` above | The app's rule is bespoke (hardens when the *hero copy* reaches the bar's bottom edge, not a fixed 130 pt), so `ScrollProbe` + `derivedStateOf` is the honest fit |

### 7.2 Pull-to-refresh and the arming haptic

`Primitives+States.swift` fires `.refreshArmed` **once per pull, only while a finger is down**, with
re-arm below 0.3× threshold, precisely because a momentum overshoot must not buzz. `PullToRefreshBox`
does not do this for you. Reimplement against `PullToRefreshState.distanceFraction`:

```kotlin
val state = rememberPullToRefreshState()
var armed by remember { mutableStateOf(false) }
val haptics = LocalHapticFeedback.current

LaunchedEffect(state) {
    snapshotFlow { state.distanceFraction }.collect { f ->
        if (!armed && f >= 1f) {
            armed = true
            // The documented use case: "a swipe/drag-style gesture, such as pull-to-refresh, where
            // the gesture action is eligible at a certain threshold of movement".
            haptics.performHapticFeedback(HapticFeedbackType.GestureThresholdActivate)
        } else if (armed && f < 0.3f) {
            armed = false                       // re-arm only after the finger has come well back
        }
    }
}
```

`GestureThresholdActivate` is a better semantic match than anything iOS had — Apple has no such
constant, which is why iOS used a 0.50-intensity light impact.

### 7.3 The hero stretch has no free equivalent

`ScrollOffset.stretch = max(0, -y)` relies on UIScrollView's rubber-band handing back a **negative
content offset**. Android does not: scroll containers clamp at 0 and hand the excess to an
`OverscrollEffect`, whose stock Android 12+ implementation is a **stretch shader applied to the whole
container**. So out of the box you get an Android-flavoured overscroll (which is arguably correct
platform behaviour) and *no* hero-only stretch.

Two ways to get the iOS behaviour, if it is judged worth keeping:

1. **Intercept at the top.** In `NestedScrollConnection.onPreScroll`, when the list is already at
   index 0 offset 0 and `available.y > 0` (finger pulling down), consume the delta yourself into
   `probe.overpull` with a rubber-band curve, and return it consumed. Then feed `overpull` into the
   hero's `graphicsLayer` height/scale. Release it with an `Animatable` on `onPostFling`.
2. **A custom `OverscrollEffect`.** `OverscrollEffect`, `rememberOverscrollEffect()`,
   `Modifier.overscroll()` and `LocalOverscrollFactory` are all **stable** in foundation 1.12
   ([`api/current.txt`](https://raw.githubusercontent.com/androidx/androidx/androidx-main/compose/foundation/foundation/api/current.txt)),
   and `withoutVisualEffect()` / `withoutEventHandling()` let you keep the event stream while
   suppressing the stretch shader. Heavier, but composes correctly with fling.

**Recommendation: ship (1) only if design insists, and otherwise let Android's stretch overscroll be
Android's stretch overscroll.** This is a genuine platform idiom difference, not a regression, and it
is listed as an open question in §11.

---

## 8. Transitions, shared elements, predictive back

### 8.1 Shared elements: available, and deliberately not used

- `SharedTransitionLayout` / `Modifier.sharedElement` / `Modifier.sharedBounds` /
  `rememberSharedContentState` became **stable in `androidx.compose.animation:animation:1.10.0`**
  (2025-12-03).
- 1.11.0 (2026-04-22) added visual debugging (`LookaheadAnimationVisualDebugging`).
- 1.12.0 (2026-08-12) added `CapturedAnimatedVisibility`, stable `unveilIn` / `veilOut`, and
  `EnterExitTransitionConfig`.
- Navigation3 1.1.7 will drive them: *"Navigation3 now supports treating scenes as shared element
  object… You can enable this by passing a `SharedTransitionScope` to either the `NavDisplay` or to
  `rememberSceneState`."*

**And the app should still not use them for Detail.** CLAUDE.md records the experiment and the
retirement (2 Sep → 3 Sep): the zoom transition "scales the whole page into the tapped poster, so the
show page opened as a miniature of itself inflating"; `zoomSource` registrations remain but nothing
consumes them. Reproducing that mistake on Android would cost a week and land the same verdict.
Detail is a plain push. If shared elements ever earn a place, the single candidate is the poster in
the Library grid → the Detail hero — and that is a design decision, not a port decision.

### 8.2 Predictive back is not optional

- Google Play requires new apps and updates to **target API 36 by 2026-08-31**.
- **Android 16 no longer calls `onBackPressed()` or dispatches `KEYCODE_BACK` for apps targeting
  API 36+.** All back handling must go through `OnBackPressedDispatcher` / AndroidX.
- From **Android 15**, the developer option for predictive back animations is gone; system animations
  (back-to-home, cross-task, cross-activity) appear automatically for apps that opted in.
- Manifest: `android:enableOnBackInvokedCallback="true"` on `<application>` (app-level default,
  overridable per-activity).
  ([Predictive back guide](https://developer.android.com/guide/navigation/custom-back/predictive-back-gesture))

In Compose:

```kotlin
// Simple interception (dismiss a sheet, collapse a search field, pop a stack)
BackHandler(enabled = drawerOpen) { drawerOpen = false }

// Progress-tracked: the "user is dragging the page away" affordance
PredictiveBackHandler(enabled = canGoBack) { progress: Flow<BackEventCompat> ->
    try {
        progress.collect { event ->
            // event.progress 0..1, event.touchX/Y, event.swipeEdge
            offset.snapTo(event.progress)     // Animatable, read in graphicsLayer{}
        }
        navigateBack()                        // completed
    } catch (e: CancellationException) {
        offset.animateTo(0f, AppMotion.settle())   // cancelled -- spring back
    }
}
```

`PredictiveBackHandler` needs `androidx.activity:activity-compose:1.8.0+`.

**Use Compose 1.12's new deferred APIs for the handoff.** `DeferredAnimatedContent` /
`DeferredAnimatedVisibility` (graduated 1.12, Aug '26) exist specifically for "two-stage transitions"
— manual property manipulation during the gesture, then automatic handoff **with velocity transfer**
— which is exactly the seam that makes a hand-rolled predictive back feel wrong (the page stops dead
when the finger lifts, then restarts). Prefer them over hand-driving an `Animatable` if you write a
custom back transition.

**Recommendation:** let Navigation3 own the standard push/pop + predictive back; reach for
`PredictiveBackHandler` only for the non-navigation dismissals (the trailer `VideoSheet`, the season
picker, the search drawer).

---

## 9. Haptics

### 9.1 Which API surface

Four exist. Pick per row:

| Surface | Since | Permission | Fallbacks | Verdict |
|---|---|---|---|---|
| `HapticFeedbackConstants` via `View.performHapticFeedback` (in Compose: `LocalHapticFeedback` + `HapticFeedbackType`) | Android 1.5+, per constant | **none** | **yes**, documented per-constant | **Default. Use this for 6 of 7 tokens.** |
| Predefined `VibrationEffect` (`EFFECT_CLICK`, `EFFECT_TICK`, `EFFECT_HEAVY_CLICK`, `EFFECT_DOUBLE_CLICK`) via `Vibrator.vibrate` | Android 10 (API 29) | `VIBRATE` | platform fallbacks exist | Only if a constant genuinely can't say it |
| `VibrationEffect.Composition` primitives | Android 11 (API 30); `PRIMITIVE_LOW_TICK` API 33; support-checking reliable from API 31 | `VIBRATE` | **none — you must check `arePrimitivesSupported`** | One place only (the milestone) |
| Envelope effects (`BasicEnvelopeBuilder`, `WaveformEnvelopeBuilder`, `VibratorFrequencyProfile`) | **Android 16 (API 36)** | `VIBRATE` | `areEnvelopeEffectsSupported()` | **Reject for v1** — §10 |

The docs are unambiguous about the first row: *"When using `View` components with
`HapticFeedbackConstants`, there's no need to evaluate specific device support, as these constants
will have fallback behavior if necessary."*
([Add haptic feedback to events](https://developer.android.com/develop/ui/views/haptics/haptic-feedback))
And about the third: *"If a composition contains primitives that aren't supported by the device, the
entire `VibrationEffect.Composition` won't play any vibration."*
([Create custom haptic effects](https://developer.android.com/develop/ui/views/haptics/custom-haptic-effects))

### 9.2 Token mapping

Compose exposes 13 `HapticFeedbackType`s (all added in **Compose 1.8**, April 2025 — the release note
reads *"`LocalHapticFeedback` now provides a default `HapticFeedback` implementation when the
`Vibrator` API indicates that haptics are supported, and the following have been added to the
`HapticFeedbackType`: Confirm, ContextClick, GestureEnd, GestureThresholdActivate, Reject,
SegmentFrequentTick, SegmentTick, ToggleOn, ToggleOff, and VirtualKey."*). Verified against
[`HapticFeedbackType.kt`](https://raw.githubusercontent.com/androidx/androidx/androidx-main/compose/ui/ui/src/commonMain/kotlin/androidx/compose/ui/hapticfeedback/HapticFeedbackType.kt)
and compose-ui `api/current.txt`.

| `FeedbackToken` (iOS) | iOS generator | Android `HapticFeedbackType` | constant / value | added | fallback below that API |
|---|---|---|---|---|---|
| `.selection` — a discrete selected value changed | `UISelectionFeedbackGenerator` | `SegmentTick` | `SEGMENT_TICK` (26) | 34 | `CONTEXT_CLICK` |
| `.commitLight` — one watch fact recorded | `.light` @ 0.65 | `Confirm` | `CONFIRM` (16) | 30 | `VIRTUAL_KEY` |
| `.commitMedium` — larger contiguous progress change | `.medium` @ 0.72 | `Confirm` **+ optional `PRIMITIVE_CLICK` @0.7** | — | 30 | `VIRTUAL_KEY` |
| `.success` — season/series complete, title added | `.notification(.success)` | `Confirm` **+ optional two-primitive composition** | — | 30 | `VIRTUAL_KEY` |
| `.destructive` — irreversible deletion accepted | `.notification(.warning)` | `Reject` | `REJECT` (17) | 30 | `LONG_PRESS` |
| `.refreshArmed` — releasing now will refresh | `.light` @ 0.50 | `GestureThresholdActivate` | `GESTURE_THRESHOLD_ACTIVATE` (23) | 34 | `CONTEXT_CLICK` |
| `.directError` — an explicit action failed | `.notification(.error)` | `Reject` | `REJECT` (17) | 30 | `LONG_PRESS` |

Fallback column is from
[`HapticFeedbackConstantsCompat.java`](https://raw.githubusercontent.com/androidx/androidx/androidx-main/core/core/src/main/java/androidx/core/view/HapticFeedbackConstantsCompat.java)
(`getFeedbackConstantOrFallback`), which is what Compose's Android `HapticFeedback` implementation
calls through `ViewCompat.performHapticFeedback`. **You get these fallbacks for free — do not write
your own `Build.VERSION.SDK_INT` ladder.**

Note the collisions: three tokens collapse onto `Confirm` and two onto `Reject`. That is the honest
consequence of Android's vocabulary being *action-shaped* rather than *intensity-shaped* — see §9.4.

### 9.3 The `FeedbackCoordinator` port

The iOS coordinator's three rules all survive: a per-token floor (0.04 s for `.selection` because it
tracks a finger on the index rail; 0.3 s otherwise because two marks 100 ms apart are one transaction),
a user preference, and "never while the app is inactive".

```kotlin
// ui/feedback/Feedback.kt
package app.previously.ui.feedback

import android.os.SystemClock
import androidx.compose.runtime.*
import androidx.compose.ui.hapticfeedback.HapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner

enum class FeedbackToken {
    Selection,      // a discrete selected value changed
    CommitLight,    // one watch fact recorded on this device
    CommitMedium,   // a larger contiguous progress change recorded
    Success,        // season/series complete, title added, rewatch started
    Destructive,    // an irreversible deletion was accepted
    RefreshArmed,   // releasing now will refresh
    DirectError,    // an explicit action failed
}

/**
 * Every haptic in the app goes through here, at most one per transaction.
 *
 * Floors are PER TOKEN, as on iOS: a blanket 300 ms is right for a commit (two marks 100 ms apart
 * are one transaction and must buzz once) and wrong for Selection, which tracks a finger down the
 * A-Z rail and must fire per section.
 *
 * The system's own "Touch feedback" setting is honoured for free: View.performHapticFeedback
 * respects Settings.System.HAPTIC_FEEDBACK_ENABLED. This class only adds the app's own toggle.
 */
@Stable
class FeedbackCoordinator(
    private val haptics: HapticFeedback,
    private val isResumed: () -> Boolean,
    private val enabled: () -> Boolean,
) {
    private val lastFire = HashMap<FeedbackToken, Long>()

    private fun floorMs(token: FeedbackToken) = if (token == FeedbackToken.Selection) 40L else 300L

    fun fire(token: FeedbackToken) {
        if (!enabled() || !isResumed()) return
        val now = SystemClock.uptimeMillis()
        if (now - (lastFire[token] ?: 0L) < floorMs(token)) return
        lastFire[token] = now
        haptics.performHapticFeedback(
            when (token) {
                FeedbackToken.Selection    -> HapticFeedbackType.SegmentTick
                FeedbackToken.CommitLight  -> HapticFeedbackType.Confirm
                FeedbackToken.CommitMedium -> HapticFeedbackType.Confirm
                FeedbackToken.Success      -> HapticFeedbackType.Confirm
                FeedbackToken.Destructive  -> HapticFeedbackType.Reject
                FeedbackToken.RefreshArmed -> HapticFeedbackType.GestureThresholdActivate
                FeedbackToken.DirectError  -> HapticFeedbackType.Reject
            }
        )
    }
}

val LocalFeedback = staticCompositionLocalOf<FeedbackCoordinator> {
    error("No FeedbackCoordinator provided")
}

@Composable
fun ProvideFeedback(hapticsEnabled: Boolean, content: @Composable () -> Unit) {
    val haptics = LocalHapticFeedback.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val enabled by rememberUpdatedState(hapticsEnabled)
    val coordinator = remember(haptics) {
        FeedbackCoordinator(
            haptics = haptics,
            isResumed = { lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) },
            enabled = { enabled },
        )
    }
    CompositionLocalProvider(LocalFeedback provides coordinator, content = content)
}
```

The iOS `enabled` flag lives in `UserDefaults` under `previously.haptics`; on Android put it in
DataStore alongside the rest of Profile's settings.

### 9.4 What is lost: intensity

iOS fires `light.impactOccurred(intensity: 0.65)`, `medium.impactOccurred(intensity: 0.72)`,
`light.impactOccurred(intensity: 0.50)`. `HapticFeedbackConstants` has **no scale parameter**. Scale
exists only on `VibrationEffect.Composition.addPrimitive(primitive, scale, delayMs)` where
`scale ∈ [0,1]` and — per the official guidance — *"scale 0.0 = minimum perceivable vibration, not
off"*, with recommended distinct levels of **0.5 / 0.7 / 1.0** and a rule that scales must differ by
a **ratio of ≥1.4** to be perceptually distinguishable.

So `.commitLight` (0.65) and `.commitMedium` (0.72) are a **1.11× ratio** — below Android's own
perceptual-distinguishability floor. That difference would not be felt on Android even if you did use
compositions.

**Recommendation: drop the intensity axis. Give `.commitLight` and `.commitMedium` the same
`Confirm`, and if a stronger milestone is wanted, escalate `.success` to a *composition* (a different
shape, not a louder one):**

```kotlin
// ui/feedback/Milestone.kt — the ONE place that touches Vibrator. Requires <uses-permission
// android:name="android.permission.VIBRATE"/>. Everything else goes through LocalHapticFeedback.
fun Context.playMilestone(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return false
    val vibrator = getSystemService(Vibrator::class.java) ?: return false
    if (!vibrator.hasVibrator()) return false
    val p = VibrationEffect.Composition
    // No platform fallback exists for primitives: an unsupported primitive plays NOTHING at all.
    if (!vibrator.areAllPrimitivesSupported(p.PRIMITIVE_TICK, p.PRIMITIVE_CLICK)) return false
    vibrator.vibrate(
        VibrationEffect.startComposition()
            .addPrimitive(p.PRIMITIVE_TICK, 0.5f)
            .addPrimitive(p.PRIMITIVE_CLICK, 1.0f, /* delayMs = */ 80)
            .compose()
    )
    return true
}
```

Call it as *an attempt*, and fall through to `HapticFeedbackType.Confirm` when it returns false.
80 ms sits inside the documented "50 ms or longer creates a discernible gap … gaps longer than
100 ms feel like individual effects" window.

### 9.5 What Android has that iOS does not

Worth spending, because they buy back some of what intensity gave:

- **`GestureThresholdActivate` / `GestureThresholdDeactivate`** — purpose-built for the pull-to-refresh
  arming moment (§7.2). Better than iOS's improvised 0.50-intensity light tap.
- **`SegmentTick` vs `SegmentFrequentTick`** — two grades of "you moved between choices".
  `SegmentTick` for the A–Z index rail and the Schedule week strip; `SegmentFrequentTick`
  ("switching between a series of **many** potential choices … designed to be very soft") if a
  future scrubber needs a denser tick.
- **`ToggleOn` / `ToggleOff`** — the settings switches in Profile (Notifications, Haptics) can say
  *which way* they moved. iOS gives them all the same selection tick.

### 9.6 Reality check on devices

Three facts to plan around, all sourced:

1. **The QA emulator has no vibrator.** `Vibrator.hasVibrator()` returns false on an AVD (it is a
   stub), so `docs/android-port/TOOLCHAIN.md`'s whole emulator-based design-QA loop **cannot verify
   a single haptic**. Calls are harmless no-ops, so nothing crashes — you simply get no signal.
   A physical device is required. This is the single biggest gap between the iOS QA loop and the
   Android one.
2. **Hardware varies enormously.** Android OEMs independently choose LRA or ERM actuators; system
   presets are interpreted differently per vendor; timing precision is roughly **~5 ms on iOS vs
   ~50 ms on Android**
   ([Software Mansion, 2026-06-18](https://swmansion.com/blog/what-is-the-difference-between-i-os-and-android-haptics/)).
   The `HapticFeedbackConstants` route is the one that degrades gracefully across that spread; the
   primitives route is the one that silently plays nothing.
3. **Primitive support is genuinely spotty and not knowable ahead of time.** AOSP's own docs note
   per-primitive support checking is only fully reliable from **API 31**; on API 30 the check returns
   true for everything as long as compositions are supported at all. Hence the `hasVibrator()` +
   `areAllPrimitivesSupported()` + boolean-return pattern in §9.4.

### 9.7 One thing to leave alone

Compose 1.12 added `SoundEffectOnInteraction` — automatic click/focus **sounds**, opt-out-able. The
app is silent on iOS, but Android's touch sounds are a *system* setting the user controls (and are
off by default on most devices). **Do not disable them app-wide**; that overrides a user preference
for a platform convention. Leave the default.

---

## 10. Alternatives considered and rejected

| Option | Why rejected |
|---|---|
| **Adopt `MaterialTheme.motionScheme` (standard/expressive) as the motion language** | It is a good system, but a *different* one from the one that shipped and was QA'd. The app's springs already sit on Material standard's ladder (§3.3), so adopting it buys consistency-with-Material at the cost of consistency-with-iOS — and the port's brief is toe-to-toe parity. Also still `@ExperimentalMaterial3ExpressiveApi` in the 1.4.0 stable line. |
| **Approximate the springs by eyeballing `Spring.StiffnessMediumLow` etc.** | Unnecessary. The conversion is closed-form and exact; `StiffnessMediumLow` (400) is `response 0.314`, nowhere near `uiSnappy`'s 0.34/0.84 pair when you also fix damping. |
| **Override `MotionDurationScale` to keep a 120 ms `uiReduced` cross-fade under "Remove animations"** | Overrides an explicit accessibility request. Android's setting means *remove*, not *reduce*. Follow the platform (§4.2). |
| **Detect reduce-motion only via `LocalAccessibilityManager`** | Compose's `AccessibilityManager` interface exposes only `calculateRecommendedTimeoutMillis`; there is no `isAnimationEnabled` / `isReduceMotionEnabled` on it. (Several blog posts claim otherwise; the API surface does not have it.) `ANIMATOR_DURATION_SCALE` + `ValueAnimator.areAnimatorsEnabled()` is the real route. |
| **Mirror iOS's `ScrollOffset` as a plain `@Composable`-read `State<Float>`** | This is the exact bug the iOS side fixed twice ("Today lags", 2 Sep). In Compose it is worse — a composition-phase read invalidates layout and draw too. Lambda modifiers + `derivedStateOf` (§5). |
| **`Modifier.onGloballyPositioned` for the 18 scroll probes** | It is the expensive callback; `onLayoutRectChanged` exists since Compose 1.8 specifically to replace it "with much less overhead" and supports throttle/debounce. |
| **`Modifier.Node` for the veils and the hero from day one** | Premature. `drawBehind` / `graphicsLayer` lambdas already defer the read to the right phase. `Modifier.Node` is for fine-grained invalidation control you have not yet proven you need (§5.5). |
| **Shared-element (container transform) push into Detail** | Product decision already taken and reversed on iOS (3 Sep). Do not re-litigate it in a port. |
| **`VibrationEffect.Composition` for the whole haptic vocabulary (to recover intensity)** | Needs `VIBRATE`, has **no platform fallback** (an unsupported primitive plays *nothing*), and the two intensities it would distinguish (0.65 vs 0.72) are a 1.11× ratio — under Android's own ≥1.4 perceptual threshold. Used in exactly one place (§9.4). |
| **Android 16 envelope APIs (`BasicEnvelopeBuilder` / `WaveformEnvelopeBuilder`)** | The right long-term answer for rich haptics, but: API 36 only, gated on `areEnvelopeEffectsSupported()`, and the app has no haptic that needs a frequency envelope. Revisit if a scrubber or a Live-Activity-style progress haptic ever lands. |
| **A third-party haptics library** | The Compose + `HapticFeedbackConstantsCompat` path is first-party, permission-free, and already carries the fallback ladder. Nothing to buy. |

---

## 11. Open questions (need a human decision)

1. **Physical device for haptic QA.** The emulator cannot vibrate. Which handset(s) become the
   haptics reference — a Pixel (best-case LRA, Google's own tuning) *and* a mid-range Samsung
   (worst-case)? Without this, §9's mapping is unvalidated theory. **This blocks sign-off on haptics.**
2. **Does the hero stretch survive the port?** §7.3: Android clamps at 0 and stretches the container
   instead. Options are (a) keep Android's overscroll and drop the hero stretch, (b) intercept in
   `onPreScroll` and reproduce iOS. (a) is more native, (b) is more "toe-to-toe". Design call.
3. **`.commitLight` vs `.commitMedium` collapse onto one constant.** Accept the collapse, or spend the
   `VIBRATE` permission to keep two grades via compositions on the ~subset of devices that support
   primitives (with the rest getting one grade anyway)? Recommendation: accept the collapse.
4. **Reduce Motion == snap.** Confirm design accepts that under "Remove animations" the app has *no*
   transitions at all, rather than iOS's 120 ms fade. (Recommendation: yes — it is the platform contract.)
5. **`MotionScheme` stability in the pinned material3.** If the build pins material3 **1.4.0**,
   `MaterialTheme.motionScheme` is still `@ExperimentalMaterial3ExpressiveApi`; it is stable from
   **1.5.0-alpha15**. Since §1 says don't adopt it, this only matters if a Material component's
   default animation needs overriding. Verify at first build.
6. **Tab-bar minimize on scroll.** iOS uses `tabBarMinimizeBehavior(.onScrollDown)`. Android's
   `NavigationBar` has no equivalent; M3's `FloatingToolbar` does, but it is a different component
   with different anatomy. Keep a static `NavigationBar` (more native), or hand-roll the minimize?
7. **Drift battery cost.** Compose ticks the infinite transition on the UI thread for as long as a
   billboard is on screen. Measure on a real device; if it shows, cap the drift to the first ~60 s
   after the screen appears.
8. **Long-press context menus.** iOS's `.contextMenu` has a strong system look (blur + lift + menu).
   Android has no direct equivalent; a `DropdownMenu` anchored at the row is the convention but reads
   differently. Confirm with design before building.

---

## 12. Verification checklist

Run these on the `PreviouslyQA_API36` AVD (from `docs/android-port/TOOLCHAIN.md`) unless noted:

- [ ] **Springs**: side-by-side capture of a mark-ring commit on iPhone and on device; the settle
      should be indistinguishable. (`uiMicro` ≈213 ms.)
- [ ] **Reveal / sweep**: confirm `EaseOutQuint` and `FastOutSlowInEasing` were used, not `tween`
      defaults (`FastOutSlowInEasing` is the `tween` default, so `uiSweep` is free; `uiReveal` is not).
- [ ] **Recomposition**: Layout Inspector, swipe Today for 5 s — the screen root's recomposition
      count must not move. Detail too.
- [ ] **Reduce Motion**: `adb shell settings put global animator_duration_scale 0`, then open Today
      and Detail. The billboard must be at scale **1.0**, not 1.07. The live dot must not be stuck bright.
- [ ] **Reduce Motion, live toggle**: flip the setting while the app is foregrounded; the
      `ContentObserver` must pick it up without a restart.
- [ ] **Predictive back**: swipe from the left edge on Detail; the page must track the finger and
      spring back on cancel. Verify `onBackPressed()` is never called (targetSdk 36).
- [ ] **Pull-to-refresh arming**: one buzz per pull, none on a momentum overshoot with no finger down,
      re-arm only below 0.3×. *(Physical device.)*
- [ ] **Index rail**: drag A→W; every section must tick (40 ms floor, not 300). *(Physical device.)*
- [ ] **Haptic throttle**: mark two episodes 100 ms apart → one buzz. Undo immediately after a mark →
      a selection tick still fires. *(Physical device.)*
- [ ] **Haptics off**: Profile toggle off → silence; system Touch feedback off → silence regardless
      of the app toggle. *(Physical device.)*
- [ ] **API 30 device / emulator**: `SegmentTick` and `GestureThresholdActivate` fall back to
      `CONTEXT_CLICK` rather than doing nothing.

---

## 13. Sources

- [Compose Animation release notes](https://developer.android.com/jetpack/androidx/releases/compose-animation) — versions, `SharedTransitionLayout` stable in 1.10.0 (2025-12-03), 1.12.0 (2026-08-12)
- [Compose UI release notes](https://developer.android.com/jetpack/androidx/releases/compose-ui) — 1.12.0, `SoundEffectOnInteraction`
- [Compose Material3 release notes](https://developer.android.com/jetpack/androidx/releases/compose-material3) — 1.4.0 (2026-08-26), `MotionScheme` stable in 1.5.0-alpha15
- [Navigation3 release notes](https://developer.android.com/jetpack/androidx/releases/navigation3) — 1.1.7 (2026-08-26), predictive back + shared elements
- [What's new in the Jetpack Compose August '26 release](https://android-developers.googleblog.com/2026/08/jetpack-compose-august-2026-release.html) — BOM 2026.08.00, `DeferredAnimatedContent`, velocity handoff
- [Compose performance best practices](https://developer.android.com/develop/ui/compose/performance/bestpractices) — deferred state reads, lambda modifiers, `derivedStateOf`
- [Custom modifiers / `Modifier.Node`](https://developer.android.com/develop/ui/compose/custom-modifiers)
- [Shared element transitions](https://developer.android.com/develop/ui/compose/animation/shared-elements)
- [Add support for the predictive back gesture](https://developer.android.com/guide/navigation/custom-back/predictive-back-gesture)
- [About predictive back in Compose](https://developer.android.com/develop/ui/compose/system/predictive-back)
- [Add haptic feedback to events](https://developer.android.com/develop/ui/views/haptics/haptic-feedback)
- [Create custom haptic effects](https://developer.android.com/develop/ui/views/haptics/custom-haptic-effects) — primitive list, `addPrimitive(primitive, scale, delayMs)`, scale/gap guidance, envelope builders
- [Android haptics API reference](https://developer.android.com/develop/ui/views/haptics/haptics-apis) — API-surface availability table
- [AOSP: Implement constants and primitives](https://source.android.com/docs/core/interaction/haptics/haptics-constants-primitives)
- [`ValueAnimator.areAnimatorsEnabled()`](https://developer.android.com/reference/android/animation/ValueAnimator#areAnimatorsEnabled())
- [`registerDurationScaleChangeListener` — `ApiSince=33`](https://learn.microsoft.com/en-us/dotnet/api/android.animation.valueanimator.registerdurationscalechangelistener?view=net-android-36.0)
- AndroidX source, androidx-main, all fetched 2026-09-04:
  [`EasingFunctions.kt`](https://raw.githubusercontent.com/androidx/androidx/androidx-main/compose/animation/animation-core/src/commonMain/kotlin/androidx/compose/animation/core/EasingFunctions.kt) ·
  [`Easing.kt`](https://raw.githubusercontent.com/androidx/androidx/androidx-main/compose/animation/animation-core/src/commonMain/kotlin/androidx/compose/animation/core/Easing.kt) ·
  [`SuspendAnimation.kt`](https://raw.githubusercontent.com/androidx/androidx/androidx-main/compose/animation/animation-core/src/commonMain/kotlin/androidx/compose/animation/core/SuspendAnimation.kt) ·
  [`InfiniteTransition.kt`](https://raw.githubusercontent.com/androidx/androidx/androidx-main/compose/animation/animation-core/src/commonMain/kotlin/androidx/compose/animation/core/InfiniteTransition.kt) ·
  [`WindowRecomposer.android.kt`](https://raw.githubusercontent.com/androidx/androidx/androidx-main/compose/ui/ui/src/androidMain/kotlin/androidx/compose/ui/platform/WindowRecomposer.android.kt) ·
  [`HapticFeedbackType.kt`](https://raw.githubusercontent.com/androidx/androidx/androidx-main/compose/ui/ui/src/commonMain/kotlin/androidx/compose/ui/hapticfeedback/HapticFeedbackType.kt) ·
  [`HapticFeedbackConstantsCompat.java`](https://raw.githubusercontent.com/androidx/androidx/androidx-main/core/core/src/main/java/androidx/core/view/HapticFeedbackConstantsCompat.java) ·
  [`MotionScheme.kt`](https://raw.githubusercontent.com/androidx/androidx/androidx-main/compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/MotionScheme.kt) ·
  [`StandardMotionTokens.kt`](https://raw.githubusercontent.com/androidx/androidx/androidx-main/compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/tokens/StandardMotionTokens.kt)
- [Spring parameter conversion reference](https://gist.github.com/edwardsanchez/a46c0eb6fbc5030541a23bd67e543de9) — `stiffness = pow(2π/response, 2)`, `damping = 4π·ζ/response`, `mass = 1`
- [iOS vs Android haptics: why the gap exists](https://swmansion.com/blog/what-is-the-difference-between-i-os-and-android-haptics/) (2026-06-18) — LRA/ERM fragmentation, timing precision
- In-repo: `CLAUDE.md` (iOS conventions), `ios/Sources/DesignSystem/ThemeTokens.swift`
  (`ThemeMotion`, `FeedbackToken`, `FeedbackCoordinator`, `ThemeMetrics.scrollSample`),
  `ios/Sources/DesignSystem/Primitives.swift` (`ScrollOffset`, `ArtHeader(drift:)`),
  `ios/Sources/DesignSystem/Primitives+States.swift` (the `.refreshArmed` rule),
  `docs/android-port/TOOLCHAIN.md`
