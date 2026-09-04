package com.anitrack.app.design

import android.content.ContentResolver
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.InfiniteRepeatableSpec
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.StartOffset
import androidx.compose.animation.core.StartOffsetType
import androidx.compose.animation.core.TweenSpec
import androidx.compose.animation.core.VisibilityThreshold
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp

/**
 * Motion tokens — the port of `ThemeMotion` and the two named transitions in
 * `ios/Sources/DesignSystem/ThemeTokens.swift`.
 *
 * No screen declares an animation. Every animated value in the app resolves its spec here, and
 * every one of them goes through [pickMotion] so Reduce Motion is answered in exactly one place.
 *
 * ## SwiftUI springs → Compose springs
 *
 * SwiftUI's `spring(response:dampingFraction:)` is **period-based**: `response` is the natural
 * period of the undamped oscillator, so its natural frequency is `ω₀ = 2π / response`. Compose's
 * `spring(dampingRatio, stiffness)` is **stiffness-based** on a unit mass, where `ω₀ = √stiffness`.
 * Therefore, for Compose's default displacement threshold and unit mass:
 *
 * ```
 * stiffness    = (2π / response)²
 * dampingRatio = dampingFraction        // the two parameters mean the same thing
 * ```
 *
 * Every stiffness below is that formula evaluated, kept as a literal so the value is readable, with
 * the source `response` in the comment so a future reader can re-derive it:
 *
 * | token         | response | ω₀ = 2π/response | stiffness = ω₀² | damping |
 * | ------------- | -------- | ---------------- | --------------- | ------- |
 * | `uiMicro`     | 0.22     | 28.560           | 815.7           | 0.88    |
 * | `uiSnappy`    | 0.34     | 18.480           | 341.5           | 0.84    |
 * | `uiSettle`    | 0.46     | 13.659           | 186.6           | 0.90    |
 * | `uiMilestone` | 0.38     | 16.535           | 273.4           | 0.74    |
 *
 * ## SwiftUI easings → Compose easings
 *
 * SwiftUI's `.easeIn` / `.easeOut` / `.easeInOut` are the CSS / Core Animation cubic-béziers
 * `(0.42, 0, 1, 1)` / `(0, 0, 0.58, 1)` / `(0.42, 0, 0.58, 1)`. Compose's Material defaults are
 * **not** those curves — `FastOutSlowInEasing` is `(0.4, 0, 0.2, 1)` and `LinearOutSlowInEasing` is
 * `(0, 0, 0.2, 1)` — so substituting them silently re-times half the app. The béziers are declared
 * explicitly below. (They are numerically identical to Compose's own `EaseIn` / `EaseOut` /
 * `EaseInOut`; they are written out rather than imported so the port carries its own numbers.)
 */
object ThemeMotion {

    // ---------------------------------------------------------------------------------------
    // Easings — iOS's actual curves, written out. See the class doc: NOT FastOutSlowInEasing.
    // ---------------------------------------------------------------------------------------

    /** SwiftUI `.easeIn` — CSS `ease-in`. */
    val easeIn: Easing = CubicBezierEasing(0.42f, 0f, 1f, 1f)

    /** SwiftUI `.easeOut` — CSS `ease-out`. */
    val easeOut: Easing = CubicBezierEasing(0f, 0f, 0.58f, 1f)

    /** SwiftUI `.easeInOut` — CSS `ease-in-out`. */
    val easeInOut: Easing = CubicBezierEasing(0.42f, 0f, 0.58f, 1f)

    /** `uiReveal`'s curve — SwiftUI `timingCurve(0.22, 1.00, 0.36, 1.00)`. */
    val revealCurve: Easing = CubicBezierEasing(0.22f, 1f, 0.36f, 1f)

    /** `uiSweep`'s curve — SwiftUI `timingCurve(0.40, 0.00, 0.20, 1.00)`. */
    val sweepCurve: Easing = CubicBezierEasing(0.40f, 0f, 0.20f, 1f)

    // ---------------------------------------------------------------------------------------
    // Spring parameters, named once. The tokens below are the only legal way to spend them; a
    // call site that needs a non-default visibility threshold passes it to the token function
    // rather than re-declaring the numbers.
    // ---------------------------------------------------------------------------------------

    private const val MICRO_DAMPING = 0.88f
    private const val MICRO_STIFFNESS = 815.7f // response 0.22 → (2π/0.22)²
    private const val SNAPPY_DAMPING = 0.84f
    private const val SNAPPY_STIFFNESS = 341.5f // response 0.34 → (2π/0.34)²
    private const val SETTLE_DAMPING = 0.90f
    private const val SETTLE_STIFFNESS = 186.6f // response 0.46 → (2π/0.46)²
    private const val MILESTONE_DAMPING = 0.74f
    private const val MILESTONE_STIFFNESS = 273.4f // response 0.38 → (2π/0.38)²

    // ---------------------------------------------------------------------------------------
    // The tokens. Each is a generic function, not a val, because `AnimationSpec<T>` is invariant:
    // one `AnimationSpec<Float>` instance cannot animate a `Dp`, a `Color` or an `IntOffset`.
    // Call sites read as `animateFloatAsState(x, ThemeMotion.uiMicro())` — T is inferred.
    // ---------------------------------------------------------------------------------------

    /** Touch compression only. */
    fun <T> uiPress(): TweenSpec<T> = tween(durationMillis = 90, easing = easeOut)

    /** Checkmarks, icon replacement, chip selection, status change. */
    fun <T> uiMicro(visibilityThreshold: T? = null): SpringSpec<T> =
        spring(MICRO_DAMPING, MICRO_STIFFNESS, visibilityThreshold)

    /** Fast local layout changes and user-requested expansion. */
    fun <T> uiSnappy(visibilityThreshold: T? = null): SpringSpec<T> =
        spring(SNAPPY_DAMPING, SNAPPY_STIFFNESS, visibilityThreshold)

    /** Large but controlled card-to-card or source-to-destination motion. */
    fun <T> uiSettle(visibilityThreshold: T? = null): SpringSpec<T> =
        spring(SETTLE_DAMPING, SETTLE_STIFFNESS, visibilityThreshold)

    /** One restrained overshoot for a meaningful milestone (series complete only). */
    fun <T> uiMilestone(visibilityThreshold: T? = null): SpringSpec<T> =
        spring(MILESTONE_DAMPING, MILESTONE_STIFFNESS, visibilityThreshold)

    /** State fades, stale strips, error notices, NOW movement. */
    fun <T> uiGentle(): TweenSpec<T> = tween(durationMillis = 220, easing = easeInOut)

    /** Initial content reveal. */
    fun <T> uiReveal(): TweenSpec<T> = tween(durationMillis = 280, easing = revealCurve)

    /** Poster tint to final image. */
    fun <T> uiPoster(): TweenSpec<T> = tween(durationMillis = 180, easing = easeOut)

    /** Numeric content transition. */
    fun <T> uiNumeric(): TweenSpec<T> = tween(durationMillis = 220, easing = easeOut)

    /** Season-complete hairline, History rail. */
    fun <T> uiSweep(): TweenSpec<T> = tween(durationMillis = 520, easing = sweepCurve)

    /**
     * Toast dismissal only. Minted for exactly that moment: a toast leaving on the spring it
     * arrived on reads as a bounce, not a dismissal.
     */
    fun <T> uiDismiss(): TweenSpec<T> = tween(durationMillis = 160, easing = easeIn)

    /**
     * Wordmark live indicator. Declared on iOS with **no call sites**; carried across so the
     * vocabulary is complete and the next person to need a slow breath does not invent one.
     */
    fun <T> uiLiveBreath(): InfiniteRepeatableSpec<T> = infiniteRepeatable(
        animation = tween(durationMillis = 1_800, easing = easeInOut),
        repeatMode = RepeatMode.Reverse,
    )

    /** Universal Reduce Motion fallback. There is ONE substitute for everything: a 120 ms ease-out. */
    fun <T> uiReduced(): TweenSpec<T> = tween(durationMillis = 120, easing = easeOut)

    /**
     * Skeleton ⇄ content swap. "Board 09's '120-ms crossfade' and board 11's Reduce Motion fallback
     * are the same curve, so this is a name for `uiReduced`, not a fourteenth token."
     */
    fun <T> uiCrossfade(): TweenSpec<T> = uiReduced()

    // ---------------------------------------------------------------------------------------
    // §5.4 — the motions that branch on Reduce Motion THEMSELVES rather than through pickMotion.
    // They live here so a screen still spends no literal: `pickMotion` cannot express "do not
    // start the animation at all", which is what these three need.
    // ---------------------------------------------------------------------------------------

    /**
     * The billboard breathing on Today and Detail (`ArtHeader(drift: true)`). The **sharp layer
     * only** scales 1.0 → [driftScale] over [driftDurationMillis], eased and reversing. One
     * transform on one layer, so no body re-evaluates. Nothing else in the app drifts.
     *
     * Start it after [driftDelayMillis]: "an animation started in the same transaction as the
     * view's own appearance is folded into it and never repeats." That beat is carried by the
     * spec's own [StartOffset] rather than by a `delay` in front of an `Animatable.animateTo`: an
     * `animateTo` on an infinite spec NEVER RETURNS, so it holds its caller's coroutine open for
     * the life of the screen and `ComposeTestRule.waitForIdle` / Espresso never see an idle frame
     * — a drifting billboard hangs the test clock. Every infinite animation in this app is a
     * [androidx.compose.animation.core.rememberInfiniteTransition], which Compose's own idling
     * resource knows to ignore.
     *
     * Under Reduce Motion the drift is **not started at all** — it is not swapped for a shorter
     * one. Branch on the flag at the call site; do not run this through [pickMotion].
     */
    fun <T> drift(): InfiniteRepeatableSpec<T> = infiniteRepeatable(
        animation = tween(durationMillis = driftDurationMillis, easing = easeInOut),
        repeatMode = RepeatMode.Reverse,
        initialStartOffset = StartOffset(driftDelayMillis.toInt(), StartOffsetType.Delay),
    )

    const val driftDurationMillis: Int = 24_000
    const val driftDelayMillis: Long = 80L
    const val driftScale: Float = 1.07f

    /**
     * The skeleton's breath (`SkeletonGate`), opacity [skeletonBreathLow] ⇄ [skeletonBreathHigh].
     *
     * The amplitude is 0.88 ↔ 1.0, not 0.65 ↔ 1.0. A 35 % oscillation across the WHOLE screen,
     * forever, is not a reassurance that something is working — it is a pulse the eye cannot ignore
     * and cannot look away from, on the frame the user is already waiting through. 12 % still
     * visibly breathes.
     *
     * Under Reduce Motion the skeleton holds a static [skeletonBreathStatic] and starts nothing.
     * A travelling highlight (shimmer) is refused by name: "decoration pretending to be progress."
     */
    fun <T> skeletonBreath(): InfiniteRepeatableSpec<T> = infiniteRepeatable(
        animation = tween(durationMillis = 1_400, easing = easeInOut),
        repeatMode = RepeatMode.Reverse,
    )

    const val skeletonBreathLow: Float = 0.88f
    const val skeletonBreathHigh: Float = 1.0f
    const val skeletonBreathStatic: Float = 0.92f

    /**
     * An indeterminate arc's rotation — one turn a second, **linear and restarting**.
     *
     * Both spinners in the app spin at this rate: `RefreshIndicator` (a background refresh over
     * content already on screen) and `InlineSpinner` (a settings row's write in flight). What
     * separates them is when they appear and how big they are, never how fast they go round, and
     * two literal turns were two chances for that to stop being true.
     *
     * The one motion in the app that may not be eased: an indeterminate spinner on an ease-in-out
     * curve visibly hesitates at the top of every revolution, which reads as the thing it is
     * reporting on having stalled. Nor may it go through [pickMotion] — a 120 ms substitute is not
     * a rotation.
     *
     * **Under Reduce Motion it does not turn.** The earlier note here argued the opposite, from the
     * platform's own indicators — but this app draws BOTH of its spinners by hand and gates its
     * other perpetual decoration (the skeleton's breath) on the preference, so the argument left
     * one infinite animation running forever on a screen where the user had asked for none, twice
     * over. A held arc still reports "in flight" — that reading comes from the arc being on screen
     * at all, which is why the caller mounts it only while work is genuinely running — and the
     * decision is made once, inside `IndeterminateArc`, never at a call site.
     */
    fun <T> refreshSpin(): InfiniteRepeatableSpec<T> = infiniteRepeatable(
        animation = tween(durationMillis = 1_000, easing = LinearEasing),
        repeatMode = RepeatMode.Restart,
    )

    /** Where a held arc rests when Reduce Motion is on: the frame the turn starts from. */
    const val refreshSpinStatic: Float = 0f

    // ---------------------------------------------------------------------------------------
    // The handoff (`AnyTransition.handoff`)
    //
    // One card is replaced by the next one on four surfaces — Today's Focus card after a mark,
    // Detail's Next-up card, a Schedule row settling, Search's results replacing the launchpad.
    // The iOS build once shipped four different answers: one correct asymmetric construction, a
    // symmetric 460 ms crossfade on Detail that rendered two show titles and two CTA labels
    // superimposed for a quarter of a second, a 40 % scale pop on Schedule, and a default crossfade
    // of two whole view trees on Search.
    //
    // The outgoing card LEAVES FIRST (uiDismiss, 160 ms); the incoming one settles into the space
    // it left, delayed past the removal. The asymmetry is the whole point — a symmetric crossfade
    // superimposes two different sentences, which is what a smear is.
    // ---------------------------------------------------------------------------------------

    /** The incoming card waits this long, so the space is empty before it is refilled. */
    const val handoffDelayMillis: Int = 80

    /**
     * The insertion's duration.
     *
     * iOS fades the incoming card in on `uiSettle.delay(0.08)` — a *delayed spring*. Compose's
     * `SpringSpec` carries no delay and only duration-based specs do, so the insertion is expressed
     * as the tween that reads like that spring: `uiSettle` is ζ = 0.90 at ω₀ = 13.659 rad/s, whose
     * 2 % settling time is 4 / (ζ·ω₀) ≈ 326 ms, rounded to 320. Of the two halves — the spring's
     * shape and the 80 ms gap — the GAP is the load-bearing one (it is what stops the two cards
     * being on screen together), and on an opacity fade a 0.9-damped spring and an ease-out are
     * the same picture. Re-tuned to read the same, not to measure the same.
     */
    const val handoffSettleMillis: Int = 320

    /**
     * The handoff as an `AnimatedContent` transform: `AnimatedContent(card, transitionSpec = {
     * ThemeMotion.handoff(reduceMotion) })`.
     *
     * `sizeTransform` is deliberately `null`. The ground must not belong to either card — it is
     * painted by the container that SURVIVES the swap (the art-adaptive ground clipped to
     * `ThemeRadius.focusCard`), "or the canvas flashes through the gap between them". A size
     * transform would animate that surviving container, which is the same bug from the other side.
     *
     * Under Reduce Motion both halves collapse to `uiReduced` with **no delay**: still a handover,
     * no travel.
     */
    fun handoff(reduceMotion: Boolean): ContentTransform = ContentTransform(
        targetContentEnter = handoffEnter(reduceMotion),
        initialContentExit = handoffExit(reduceMotion),
        sizeTransform = null,
    )

    /** The handoff's insertion half, for a surface that mounts its cards with `AnimatedVisibility`. */
    fun handoffEnter(reduceMotion: Boolean): EnterTransition = if (reduceMotion) {
        fadeIn(uiReduced())
    } else {
        fadeIn(tween(handoffSettleMillis, delayMillis = handoffDelayMillis, easing = easeOut))
    }

    /** The handoff's removal half. Leaves first, on `uiDismiss`. */
    fun handoffExit(reduceMotion: Boolean): ExitTransition =
        fadeOut(if (reduceMotion) uiReduced() else uiDismiss())

    // ---------------------------------------------------------------------------------------
    // The toast (`AnyTransition.toast`)
    // ---------------------------------------------------------------------------------------

    /** The toast's rise: it arrives from 4 pt below and settles. */
    val toastRise: Dp = 4.dp

    /**
     * The toast's own timing, owned by the toast rather than by whichever container happens to
     * mount it: a 4-pt rise on `uiSnappy` in, `uiDismiss` out (see [toastExit]).
     *
     * `@Composable` because the 4 dp rise has to be resolved against the current density before it
     * can be handed to `slideInVertically`, which works in pixels.
     */
    @Composable
    fun toastEnter(reduceMotion: Boolean): EnterTransition {
        val rise = with(LocalDensity.current) { toastRise.roundToPx() }
        return if (reduceMotion) {
            fadeIn(uiReduced())
        } else {
            fadeIn(uiSnappy()) +
                slideInVertically(uiSnappy(IntOffset.VisibilityThreshold)) { rise }
        }
    }

    /**
     * The toast leaves on `uiDismiss` and does **not** slide back down: `uiDismiss` was minted for
     * exactly this moment, and a toast leaving on the spring it arrived on reads as a bounce.
     */
    fun toastExit(reduceMotion: Boolean): ExitTransition =
        fadeOut(if (reduceMotion) uiReduced() else uiDismiss())
}

/**
 * The names of the motion tokens, so a screen can hand a token to [pickMotion] rather than
 * choosing between a spec and its Reduce Motion substitute itself. The port of passing
 * `ThemeMotion.uiSettle` to `ThemeMotion.pick(_:reduceMotion:)` (93 call sites on iOS).
 *
 * `UI_LIVE_BREATH`, `DRIFT` and `SKELETON_BREATH` are absent on purpose: they are infinite, so they
 * are not `FiniteAnimationSpec`s, and — more to the point — Reduce Motion **stops** them rather
 * than shortening them (see `ThemeMotion.drift`).
 */
enum class MotionToken {
    UI_PRESS,
    UI_MICRO,
    UI_SNAPPY,
    UI_SETTLE,
    UI_MILESTONE,
    UI_GENTLE,
    UI_REVEAL,
    UI_POSTER,
    UI_NUMERIC,
    UI_SWEEP,
    UI_DISMISS,
    UI_REDUCED,
    UI_CROSSFADE,
    ;

    /** This token's spec, ignoring Reduce Motion. Prefer [pickMotion], which does not ignore it. */
    fun <T> spec(): FiniteAnimationSpec<T> = when (this) {
        UI_PRESS -> ThemeMotion.uiPress()
        UI_MICRO -> ThemeMotion.uiMicro()
        UI_SNAPPY -> ThemeMotion.uiSnappy()
        UI_SETTLE -> ThemeMotion.uiSettle()
        UI_MILESTONE -> ThemeMotion.uiMilestone()
        UI_GENTLE -> ThemeMotion.uiGentle()
        UI_REVEAL -> ThemeMotion.uiReveal()
        UI_POSTER -> ThemeMotion.uiPoster()
        UI_NUMERIC -> ThemeMotion.uiNumeric()
        UI_SWEEP -> ThemeMotion.uiSweep()
        UI_DISMISS -> ThemeMotion.uiDismiss()
        UI_REDUCED -> ThemeMotion.uiReduced()
        UI_CROSSFADE -> ThemeMotion.uiCrossfade()
    }
}

/**
 * The token, or the Reduce Motion fallback when the setting is on. The port of
 * `ThemeMotion.pick(_:reduceMotion:)`.
 *
 * There is **one** substitute for everything: a 120 ms ease-out. Nothing is disabled outright here;
 * the three motions that must actually stop (billboard drift, skeleton breath, the splash timeline)
 * branch on the flag themselves.
 *
 * Two Android notes that are easy to get wrong:
 *
 * 1. **This is for motion the app drives itself.** Per `fidelity-line.md` §Q17, Android's own
 *    contract wins for built-in transitions: under "Remove animations" the platform gives no
 *    transition at all rather than iOS's 120 ms fade, and that is the Android user's expectation.
 *    Do not reach into system transitions to reinstate a fade.
 * 2. Compose already scales its own animation durations by the system's animator duration scale
 *    (`AndroidComposeView` provides a `MotionDurationScale` read from the same setting this flag
 *    reads), so at a scale of 0 an app-driven animation finishes on its first frame whatever spec
 *    it was given. This function still matters because the *flag* is what the branching motions,
 *    the handoff's delay and the toast's rise consult.
 */
fun <T> pickMotion(token: MotionToken, reduceMotion: Boolean): FiniteAnimationSpec<T> =
    if (reduceMotion) ThemeMotion.uiReduced() else token.spec()

/** [pickMotion] against the ambient [LocalReduceMotion]. The everyday form inside a composable. */
@Composable
fun <T> motion(token: MotionToken): FiniteAnimationSpec<T> =
    pickMotion(token, LocalReduceMotion.current)

/**
 * Is Reduce Motion on? Provided once at the root by [ProvideReduceMotion] and read by every screen.
 *
 * `staticCompositionLocalOf` on purpose: the value changes at most a handful of times in a session,
 * and when it does every screen's motion must be re-decided — a whole-subtree invalidation is the
 * correct behaviour, and reads stay free.
 */
val LocalReduceMotion = staticCompositionLocalOf { false }

/** Resolves Reduce Motion once and provides it to [content]. Wrap the app root in this. */
@Composable
fun ProvideReduceMotion(content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalReduceMotion provides rememberReduceMotion(), content = content)
}

/**
 * Android's Reduce Motion signal: `Settings.Global.ANIMATOR_DURATION_SCALE == 0`.
 *
 * Android has no "Reduce Motion" accessibility flag of its own. The a11y toggle that means it —
 * Settings → Accessibility → **Remove animations** — writes 0 into the three animation scales
 * (`WINDOW_ANIMATION_SCALE`, `TRANSITION_ANIMATION_SCALE`, `ANIMATOR_DURATION_SCALE`), and it is
 * the animator scale that governs property animation, which is all this app's motion is.
 *
 * The setting **reads back as unset** on a device where it was never written — that is not "off",
 * it is "default". `getFloat(resolver, key, 1f)` returns the 1f default in that case, so an absent
 * value and an explicit 1 are treated alike and **only an explicit 0 turns Reduce Motion on**.
 *
 * Observed live, because a user who turns the setting on while the app is open expects the app to
 * obey without a relaunch.
 */
@Composable
fun rememberReduceMotion(): Boolean {
    val resolver = LocalContext.current.contentResolver
    var reduced by remember(resolver) { mutableStateOf(animationsAreRemoved(resolver)) }
    DisposableEffect(resolver) {
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                reduced = animationsAreRemoved(resolver)
            }
        }
        resolver.registerContentObserver(
            Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE),
            false,
            observer,
        )
        onDispose { resolver.unregisterContentObserver(observer) }
    }
    return reduced
}

private fun animationsAreRemoved(resolver: ContentResolver): Boolean =
    Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
