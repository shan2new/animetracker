package com.anitrack.app.design

import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.platform.LocalView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.findViewTreeLifecycleOwner
import java.lang.ref.WeakReference

/**
 * Every haptic in the app goes through here. One sentence of justification per token — if a new
 * event cannot be written as one of these seven sentences, it does not get a haptic.
 */
enum class FeedbackToken {
    /** A discrete selected value changed. */
    SELECTION,

    /** One watch fact recorded on this device. */
    COMMIT_LIGHT,

    /** A larger contiguous progress change recorded. */
    COMMIT_MEDIUM,

    /** Season/series complete · title added · rewatch started. */
    SUCCESS,

    /** An irreversible deletion was accepted. */
    DESTRUCTIVE,

    /** Releasing now will refresh. */
    REFRESH_ARMED,

    /** An explicit action failed. */
    DIRECT_ERROR,
}

/**
 * The one place a haptic is fired — the port of `FeedbackCoordinator` in
 * `ios/Sources/DesignSystem/ThemeTokens.swift`.
 *
 * The discipline is the product decision, and it is platform-independent: **every haptic goes
 * through [fire], at most one per transaction.** What changes on Android is only the vibration
 * itself.
 *
 * ## Why constants, and not a hand-authored `VibrationEffect`
 *
 * iOS has one Taptic Engine and seven exact patterns. Android has LRAs and ERMs with wildly
 * different amplitude ranges and OEM remapping on top, which is why the product owner ruled
 * (`fidelity-line.md` §Q11):
 *
 * > "Haptics are not really a blocker. Different devices have different ones unlike iPhones."
 *
 * So each token maps to a `HapticFeedbackConstants` **semantic** and the OEM decides how it feels.
 * `VibrationEffect.Composition` would be reached for only where a constant genuinely has no
 * analogue, and there is no such case here:
 *
 * - From API 30 every token has one (`CONFIRM` / `REJECT` / `GESTURE_START` and the tick family).
 * - Below API 30 the positive/negative valence of `SUCCESS` / `DESTRUCTIVE` / `DIRECT_ERROR` has no
 *   constant — but composition primitives are themselves API 30+, so a `Composition` could not
 *   supply it either, and a hand-authored waveform would need the `VIBRATE` permission, which the
 *   same ruling declines to spend ("do not spend the VIBRATE permission to preserve two grades").
 *
 * `View.performHapticFeedback` needs **no permission**, so the app declares none. Consequently
 * `COMMIT_LIGHT` and `COMMIT_MEDIUM` collapse onto one grade wherever the OEM implements
 * `VIRTUAL_KEY` and `CONTEXT_CLICK` identically. That collapse is accepted, not a defect.
 *
 * ## Threading
 *
 * `View.performHapticFeedback` is a UI-thread call and the throttle map is unsynchronised, so
 * [fire] is main-thread-confined the way the iOS type is `@MainActor`. A call from anywhere else
 * is posted to the main looper rather than dropped or crashed — an `AppModel` write that finishes
 * on a background dispatcher still gets its receipt.
 */
object FeedbackCoordinator {

    /**
     * The preference key, kept **identical to iOS's `UserDefaults` key** so the two platforms name
     * the same user choice. Persistence belongs to the settings layer (DataStore); this object
     * holds only the live value.
     */
    const val PREFERENCE_KEY: String = "previously.haptics"

    /**
     * Haptics: On / Off (Accessibility). Default **on**.
     *
     * System settings remain authoritative: [fire] never passes
     * `HapticFeedbackConstants.FLAG_IGNORE_GLOBAL_SETTING`, so a device with system haptic feedback
     * switched off stays silent whatever this says. The settings layer mirrors the persisted
     * preference into here at start and on every change.
     */
    @Volatile
    var enabled: Boolean = true

    /**
     * The minimum gap between two feedback events, **per token**.
     *
     * A blanket 300 ms floor is right for a commit — two marks 100 ms apart are one transaction and
     * must buzz once. It is wrong for [FeedbackToken.SELECTION], which is the token the A–Z index
     * rail and the week strip use: the platform's own index rails fire per section, unthrottled,
     * and at 300 ms an A→W drag yielded at most two taps out of twenty-odd. Selection is *tracking*
     * a finger, not confirming a write.
     */
    private const val SELECTION_FLOOR_MS = 40L // iOS: 0.04 s

    /** Every token that is not a selection. */
    private const val COMMIT_FLOOR_MS = 300L // iOS: 0.3 s

    /**
     * Per token, as the floor is: one shared stamp meant adding two shows in quick succession
     * buzzed once, an error inside 300 ms of the commit it belonged to was swallowed, and Undo
     * tapped straight after a mark gave no selection tick at all.
     *
     * Stamps are `SystemClock.elapsedRealtime()` — monotonic since boot, so a mid-window clock
     * change cannot produce a negative or absurd remainder the way a wall-clock stamp can. Index 0
     * means "never fired", which is only ambiguous in the first 300 ms after a device boots.
     */
    private val lastFire = LongArray(FeedbackToken.entries.size)

    private val mainHandler = Handler(Looper.getMainLooper())

    /** The view the haptic is performed on. Weak: this object outlives every activity. */
    private var host: WeakReference<View>? = null

    /**
     * Point the coordinator at the window's view. Call once, from the app root — [InstallFeedback]
     * is the composable form and cleans up after itself.
     */
    fun attach(view: View) {
        host = WeakReference(view)
    }

    /** Release [view] if it is still the attached one. */
    fun detach(view: View) {
        if (host?.get() === view) host = null
    }

    /**
     * Fires at most one feedback event per token floor, never while the app is not in the
     * foreground.
     *
     * Three conditions, all required, and all three are the iOS ones:
     * 1. the user's Haptics preference is on ([enabled]);
     * 2. the activity is RESUMED — the Android reading of iOS's `applicationState == .active`.
     *    Note a system dialog over the app (the notification-permission prompt, say) does not leave
     *    RESUMED, so the `.success` fired when permission is granted survives, which is the point;
     * 3. the per-token throttle floor has elapsed.
     */
    fun fire(token: FeedbackToken) {
        if (Looper.myLooper() !== Looper.getMainLooper()) {
            mainHandler.post { fire(token) }
            return
        }
        if (!enabled) return
        val view = host?.get() ?: return
        if (!isForeground(view)) return

        val now = SystemClock.elapsedRealtime()
        val floor = if (token == FeedbackToken.SELECTION) SELECTION_FLOOR_MS else COMMIT_FLOOR_MS
        if (now - lastFire[token.ordinal] < floor) return
        lastFire[token.ordinal] = now

        view.performHapticFeedback(constantFor(token))
    }

    private fun isForeground(view: View): Boolean {
        val lifecycle = view.findViewTreeLifecycleOwner()?.lifecycle
            ?: return view.windowVisibility == View.VISIBLE
        return lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
    }

    /**
     * The token → platform-semantic map.
     *
     * Branching is **explicit** on `SDK_INT`, never left to graceful degradation — the same rule the
     * iOS side applies to every iOS 26 API through `GlassHelpers.swift`, and the same trap the blur
     * work has (`minsdk-decision.md`): a constant a device does not know is a silent no-op, so the
     * fallback has to be chosen here rather than discovered on a user's phone.
     *
     * | token           | API 34+        | API 30+         | API 26–29       |
     * | --------------- | -------------- | --------------- | --------------- |
     * | `SELECTION`     | `SEGMENT_TICK` | `CLOCK_TICK`    | `CLOCK_TICK`    |
     * | `COMMIT_LIGHT`  | `VIRTUAL_KEY`  | `VIRTUAL_KEY`   | `VIRTUAL_KEY`   |
     * | `COMMIT_MEDIUM` | `CONTEXT_CLICK`| `CONTEXT_CLICK` | `CONTEXT_CLICK` |
     * | `SUCCESS`       | `CONFIRM`      | `CONFIRM`       | `LONG_PRESS`    |
     * | `DESTRUCTIVE`   | `REJECT`       | `REJECT`        | `LONG_PRESS`    |
     * | `REFRESH_ARMED` | `GESTURE_START`| `GESTURE_START` | `CLOCK_TICK`    |
     * | `DIRECT_ERROR`  | `REJECT`       | `REJECT`        | `LONG_PRESS`    |
     *
     * Three collapses, each deliberate:
     * - the two commit grades differ only as much as the OEM's `VIRTUAL_KEY` and `CONTEXT_CLICK`
     *   differ (iOS separates them by amplitude, 0.65 vs 0.72, which constants cannot express);
     * - `DESTRUCTIVE` and `DIRECT_ERROR` are both `REJECT` — iOS separates them as the *warning*
     *   and *error* notification patterns, and Android has one negative semantic;
     * - below API 30 there is no valence at all, so the three "something notable happened" tokens
     *   share `LONG_PRESS`, the firmest constant that exists there.
     */
    private fun constantFor(token: FeedbackToken): Int = when (token) {
        // A tick that TRACKS a finger. SEGMENT_TICK is built for exactly this (a slider/rail
        // crossing a detent) and is quieter than CLOCK_TICK where the OEM tunes it.
        FeedbackToken.SELECTION ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                HapticFeedbackConstants.SEGMENT_TICK
            } else {
                HapticFeedbackConstants.CLOCK_TICK
            }

        // One light, committed tap — the platform's "you pressed a key" tick.
        FeedbackToken.COMMIT_LIGHT -> HapticFeedbackConstants.VIRTUAL_KEY

        // The firmer single tick. Not CONFIRM: a batch of episodes is a bigger commit, not a
        // celebration, and CONFIRM belongs to SUCCESS alone.
        FeedbackToken.COMMIT_MEDIUM -> HapticFeedbackConstants.CONTEXT_CLICK

        FeedbackToken.SUCCESS ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                HapticFeedbackConstants.CONFIRM
            } else {
                HapticFeedbackConstants.LONG_PRESS
            }

        FeedbackToken.DESTRUCTIVE ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                HapticFeedbackConstants.REJECT
            } else {
                HapticFeedbackConstants.LONG_PRESS
            }

        // "Releasing now will refresh" is literally a gesture crossing its threshold.
        FeedbackToken.REFRESH_ARMED ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                HapticFeedbackConstants.GESTURE_START
            } else {
                HapticFeedbackConstants.CLOCK_TICK
            }

        FeedbackToken.DIRECT_ERROR ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                HapticFeedbackConstants.REJECT
            } else {
                HapticFeedbackConstants.LONG_PRESS
            }
    }
}

/**
 * Installs [FeedbackCoordinator] against the current window for as long as this composition lives.
 * Call it once, at the app root, above the navigation host.
 */
@Composable
fun InstallFeedback() {
    val view = LocalView.current
    DisposableEffect(view) {
        FeedbackCoordinator.attach(view)
        onDispose { FeedbackCoordinator.detach(view) }
    }
}
