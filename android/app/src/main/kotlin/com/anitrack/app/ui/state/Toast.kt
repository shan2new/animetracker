package com.anitrack.app.ui.state

import android.content.Context
import android.view.accessibility.AccessibilityManager
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.material3.AlertDialog
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.anitrack.app.design.ContinuousCornerShape
import com.anitrack.app.design.FeedbackCoordinator
import com.anitrack.app.design.FeedbackToken
import com.anitrack.app.design.LocalControlInk
import com.anitrack.app.design.LocalReduceMotion
import com.anitrack.app.design.MotionToken
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.PreviouslyMaterialBridge
import com.anitrack.app.design.ShadowToken
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMotion
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.motion
import com.anitrack.app.design.rememberSymbol
import com.anitrack.app.design.shadowToken
import com.anitrack.app.ui.chrome.chromeGlass
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.control.SecondaryButton
import com.anitrack.app.ui.control.TertiaryButton
import com.anitrack.app.ui.control.minimumTapTarget
import com.anitrack.app.ui.isAccessibilityTextSize
import com.anitrack.model.copy.Copy
import kotlinx.coroutines.delay
import com.anitrack.app.LocalAppModel
import com.anitrack.app.data.ReceiptPlacement
import com.anitrack.app.data.UndoState
import com.anitrack.app.ui.art.PosterSlot
import com.anitrack.app.ui.control.DrawnCheck
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import com.anitrack.model.portraitArt
import com.anitrack.model.shelfShortened

// =====================================================================================
// THE TOAST IS A CAPSULE, AND IT IS NEVER A SNACKBAR.
//
// The port of `ios/Sources/DesignSystem/UndoToast.swift` plus `ToastView` /
// `ToastActionStyle` (Primitives.swift) and `SyncBanner` (Primitives+States.swift).
//
// "The shipped shape — a full-width rounded rectangle with a 1-px perimeter stroke and a
// trailing amber 'Undo' — is an Android Material snackbar in shape, position and
// construction, and it put a second amber object beside the amber CTA it had just been
// used to confirm. A capsule that hugs its own text is the iOS grammar (the AirPods /
// silent-switch HUDs, the Photos 'Copied' pill)."
//
// So: **a port must not regress to a Material `Snackbar`** — which is banned outright
// (PLAN §3.1) along with `SnackbarHost`. This is a hugging capsule: `wrapContentWidth`,
// `widthIn(max = 420.dp)`, `heightIn(min = 48.dp)`, `CircleShape`, the `.floating`
// shadow, and the action word in TEXT INK.
//
// "Not accent: the mark this toast is confirming was committed by an amber control, and a
// second amber word 6 pt away competes with it. Weight carries the action."
// =====================================================================================

// -------------------------------------------------------------------------------------
// The glass ground
// -------------------------------------------------------------------------------------
//
// The capsule's ground is `Modifier.chromeGlass(shape)` — `ui/chrome/ChromeSurface.kt`, which owns
// **every** blur decision in the app. There are exactly two renderings and the design system
// already specifies both: a live backdrop blur behind the capsule where the app may draw material,
// and otherwise `surfaceFloating` plus a 1-dp `strokeStrong` ring with no refraction.
//
// The second is not a degradation invented for Android — it is the app's shipped **Reduce
// Transparency** rendering, which is why pre-31 devices take it unchanged. `canUseMaterial` is ONE
// boolean (`SDK_INT >= 31 && !reduceTransparency`), resolved once by `ProvideChromeSurface`;
// "device cannot blur" and "user asked for reduced transparency" must never become two conditions
// that drift apart. This file used to declare a SECOND glass seam with an opaque default that
// nothing ever provided over, so the toast and the sync banner drew the fallback on every device
// including the ones that can blur.

// -------------------------------------------------------------------------------------
// Lifetimes
// -------------------------------------------------------------------------------------

/**
 * How long each channel holds its value.
 *
 * The timers are the model's, not the host's: `AppModel` owns `undoTask` / `errorTask` /
 * `noticeTask` because `teardown()` cancels them on sign-out and `markCaughtUp` coalesces an
 * already-pending undo. The **numbers** belong to the toast layer, so they live here and the model
 * reads them.
 *
 * "An Undo the user cannot reach in time is not an Undo" is the whole reason for the screen-reader
 * extensions.
 */
object ToastDuration {

    /** Undo: 6 s, or 10 s while a screen reader is running. */
    fun undo(screenReaderOn: Boolean): Long = if (screenReaderOn) 10_000L else 6_000L

    /** Error: 4 s, or 8 s while a screen reader is running. */
    fun error(screenReaderOn: Boolean): Long = if (screenReaderOn) 8_000L else 4_000L

    /** A neutral receipt with no action ("Episode alerts on"). Fixed — there is nothing to reach. */
    const val NOTICE_MILLIS = 2_500L
}

/**
 * "Present when the handoff settles" — the one place a toast is NOT presented immediately.
 *
 * A single mark **on a card that hands over to its successor** waits for the outgoing card to
 * leave. Today's hero is the reference implementation:
 *
 * ```
 * tap Mark
 *  ├─ appModel.markNext(...)                    // optimistic write + ONE commit haptic
 *  ├─ committedEpisode = undo.episode           // uiMicro: the capsule flips to "Episode N watched"
 *  ├─ (the queue row's committed membership lasts the same beat)
 *  └─ delay(HOLD_MILLIS)                        // 650
 *       └─ uiSettle: pinned = null; committedEpisode = null
 *            when it finishes:
 *              ├─ presentUndo(pendingUndo)      // ← the toast lands HERE
 *              └─ delay(tailMillis(reduceMotion)) → handoffInFlight = false
 * ```
 *
 * The incoming card's insertion is delayed by `ThemeMotion.handoffEnter` and is **not tappable
 * until it has actually arrived** (`handoffInFlight` covers the window `committedEpisode` cannot).
 *
 * **Every other surface presents immediately** — Today's queue rows ("Unlike the hero there is no
 * card handing over here"), Schedule's airing cards, Detail's episode rows, Library's context menu,
 * and `removeWithUndo` ("unlike a mark, a removal has no handoff to wait for").
 */
object HandoffUndo {
    /** The beat the committed card holds before it hands over. */
    const val HOLD_MILLIS = 650L

    /** The tail after the settle, during which the incoming card refuses a second mark. */
    fun tailMillis(reduceMotion: Boolean): Long = if (reduceMotion) 0L else 300L
}

/**
 * Is a screen reader driving? — the Android reading of `UIAccessibility.isVoiceOverRunning`, which
 * is what doubles the toast lifetimes.
 *
 * Touch exploration, not merely "an accessibility service is enabled": a switch-access or
 * magnification service does not change how long a message needs to stay reachable.
 *
 * Observed live, because a user who starts TalkBack while the app is open expects the next toast to
 * obey without a relaunch.
 */
@Composable
fun rememberScreenReaderEnabled(): Boolean {
    val context = LocalContext.current
    var on by remember(context) { mutableStateOf(screenReaderEnabled(context)) }
    DisposableEffect(context) {
        val manager =
            context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
        val listener = AccessibilityManager.TouchExplorationStateChangeListener { enabled ->
            on = enabled && (manager?.isEnabled ?: false)
        }
        manager?.addTouchExplorationStateChangeListener(listener)
        onDispose { manager?.removeTouchExplorationStateChangeListener(listener) }
    }
    return on
}

/** The non-composable read, for the model layer that schedules the dismissals. */
fun screenReaderEnabled(context: Context): Boolean {
    val manager =
        context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
            ?: return false
    return manager.isEnabled && manager.isTouchExplorationEnabled
}

// -------------------------------------------------------------------------------------
// The capsule
// -------------------------------------------------------------------------------------

/** The toast's own action word. A 44-dp target inside a 48-dp capsule, no container of its own. */
@Composable
private fun ToastAction(label: String, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .heightIn(min = minimumTapTarget)
            // The hit shape is the capsule, not the word: a 44-dp target inside a 48-dp capsule.
            .clip(CircleShape)
            .clickable(
                interactionSource = null,
                // The app's one bare-text press: dim to 0.55 on `uiPress`. Never the Material
                // ripple, and never a hand-rolled second spelling of the same dip.
                indication = PressStyle.textAction,
                role = Role.Button,
                onClick = onClick,
            )
            .padding(horizontal = ThemeSpace.x4),
        contentAlignment = Alignment.Center,
    ) {
        BasicText(
            text = label,
            // The control ink, NEVER accent — through `LocalControlInk`, like every other bare
            // tappable word in the app (`TertiaryButton`, `InlineLinkButton`, a header's action).
            // Naming `textPrimary` here spelled the same ink a second way: the tint is re-provided
            // per navigation host, and an action that read the colour directly would be the one
            // word in the app that did not follow it. Weight carries the affordance.
            style = ThemeType.metadataEmphasis.copy(color = LocalControlInk.current),
        )
    }
}

/**
 * The canonical toast: a content-width glass **capsule**, centred over the bottom bar's own margin.
 *
 * @param message the receipt. Two lines at most — the title is the part allowed to truncate, the
 *   fact never is.
 * @param actionLabel drawn only with [onAction]. One action, never two.
 * @param failure adds the warning triangle. `warning` ink, never `destructive` red.
 * @param spokenOverride what a screen reader hears instead of [message]. The Undo toast uses it to
 *   say "…. Undo available." — "A VoiceOver user was never told the toast existed, let alone that
 *   Undo was available for the next six (or ten) seconds."
 */
@Composable
fun ToastView(
    message: String,
    modifier: Modifier = Modifier,
    actionLabel: String? = null,
    failure: Boolean = false,
    spokenOverride: String? = null,
    onAction: (() -> Unit)? = null,
) {
    val hasAction = actionLabel != null && onAction != null
    Row(
        modifier = modifier
            .wrapContentWidth()
            .widthIn(max = TOAST_MAX_WIDTH)
            .heightIn(min = 48.dp)
            .shadowToken(ShadowToken.Floating, CircleShape)
            .chromeGlass(CircleShape)
            .padding(
                start = ThemeSpace.x4,
                end = if (hasAction) ThemeSpace.x1 else ThemeSpace.x4,
            ),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x3),
    ) {
        if (failure) {
            Image(
                imageVector = rememberSymbol(PreviouslyIcons.WarningFilled),
                contentDescription = null,
                colorFilter = ColorFilter.tint(ThemeColor.warning),
                modifier = Modifier.size(13.dp),
            )
        }
        BasicText(
            text = message,
            style = ThemeType.metadataEmphasis.copy(
                color = ThemeColor.textPrimary,
                textAlign = TextAlign.Start,
            ),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            // The message is a POLITE live region — Compose's answer to iOS's
            // `AccessibilityNotification.Announcement`. It sits on the text node, not on the row,
            // so the action beside it stays separately focusable.
            modifier = Modifier
                .weight(1f, fill = false)
                .semantics {
                    liveRegion = LiveRegionMode.Polite
                    if (spokenOverride != null) contentDescription = spokenOverride
                },
        )
        if (hasAction) {
            ToastAction(label = actionLabel!!, onClick = onAction!!)
        }
    }
}

/** The toast never spans the screen over content the user is reading. */
val TOAST_MAX_WIDTH = 420.dp

// -------------------------------------------------------------------------------------
// The sync banner
// -------------------------------------------------------------------------------------

/**
 * The persistent write-failure surface, above the bottom bar.
 *
 * **A failed write is never a transient toast: it stays until it is retried or discarded.** It
 * wears the toast's own capsule — "a failed write is the same class of message as a committed one,
 * and it wears the same object; only its persistence differs." It was a full-width floating plate
 * at 17 pt: a system alert bar laid across the app.
 *
 * Silent on appearance — **a background failure earns no haptic**. The explicit Retry earns one
 * `DIRECT_ERROR` if it fails again, and that is fired by the sync centre, not here.
 *
 * ### Retry is optimistic, and double-tap-proof
 *
 * There is **no spinner**: "a local-first write returns before the network does — a spinner here
 * could only be a lie about waiting." Instead the button holds inert for [RETRY_LOCKOUT_MILLIS] —
 * "a timed hold, not a gate on a spring: the sync closure returns immediately, so there is no
 * completion to wait on. Long enough to swallow a double-tap, short enough that a banner which
 * comes straight back is pressable again." The banner leaves as soon as the retry is issued (the
 * failed rows are removed) and returns if the write fails again.
 *
 * @param count failed changes — one row per `(command, title)` pair, because "a repeatedly failing
 *   write is one problem, not a list".
 * @param onRetry `null` when nothing here can be retried (the change was restored from a previous
 *   launch with no replay installed). The banner then offers "Dismiss", which confirms first:
 *   discarding a write is destructive and a row is **never** cleared as though it had succeeded.
 * @param onDiscardAll runs after the confirmation. The `DESTRUCTIVE` haptic is fired here, once.
 */
@Composable
fun SyncBanner(
    count: Int,
    onDiscardAll: () -> Unit,
    modifier: Modifier = Modifier,
    onRetry: (() -> Unit)? = null,
) {
    val isAX = isAccessibilityTextSize()
    var retryInFlight by remember { mutableStateOf(false) }
    var confirmDiscard by remember { mutableStateOf(false) }

    LaunchedEffect(retryInFlight) {
        if (!retryInFlight) return@LaunchedEffect
        delay(RETRY_LOCKOUT_MILLIS)
        retryInFlight = false
    }

    val message: @Composable (Modifier) -> Unit = { slot ->
        BasicText(
            text = Copy.Toast.syncFailed(count),
            style = ThemeType.metadataEmphasis.copy(color = ThemeColor.textPrimary),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = slot,
        )
    }

    val control: @Composable () -> Unit = {
        val retry = onRetry
        if (retry != null) {
            val issue = {
                if (!retryInFlight) {
                    retryInFlight = true
                    retry()
                }
            }
            if (isAX) {
                SecondaryButton(Copy.Action.retry, issue, enabled = !retryInFlight, hugging = true)
            } else {
                TertiaryButton(Copy.Action.retry, issue, enabled = !retryInFlight)
            }
        } else {
            val open = { confirmDiscard = true }
            if (isAX) {
                SecondaryButton(Copy.Action.dismiss, open, hugging = true)
            } else {
                TertiaryButton(Copy.Action.dismiss, open)
            }
        }
    }

    val capsule = modifier
        .wrapContentWidth()
        .widthIn(max = TOAST_MAX_WIDTH)
        .heightIn(min = 48.dp)
        .shadowToken(ShadowToken.Floating, CircleShape)
        .chromeGlass(CircleShape)
        .padding(
            start = ThemeSpace.x4,
            end = if (isAX) ThemeSpace.x4 else ThemeSpace.x1,
            top = if (isAX) ThemeSpace.x3 else 0.dp,
            bottom = if (isAX) ThemeSpace.x3 else 0.dp,
        )
        // One summary object: a screen reader reaches the message and the control in order without
        // the capsule announcing itself as chrome.
        .semantics { isTraversalGroup = true }

    if (isAX) {
        Column(
            modifier = capsule,
            horizontalAlignment = Alignment.Start,
            verticalArrangement = Arrangement.spacedBy(ThemeSpace.x3),
        ) {
            message(Modifier)
            control()
        }
    } else {
        Row(
            modifier = capsule,
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x3),
        ) {
            message(Modifier.weight(1f, fill = false))
            control()
        }
    }

    if (confirmDiscard) {
        DiscardChangesDialog(
            count = count,
            onDismiss = { confirmDiscard = false },
            onConfirm = {
                confirmDiscard = false
                FeedbackCoordinator.fire(FeedbackToken.DESTRUCTIVE)
                onDiscardAll()
            },
        )
    }
}

/** Long enough to swallow a double-tap, short enough that a returning banner is pressable again. */
const val RETRY_LOCKOUT_MILLIS = 800L

/**
 * "Discard N changes?" — iOS presents an action sheet; Android's idiom for a two-button destructive
 * confirmation is a dialog, and the sheet-vs-dialog difference is idiomatic on each platform.
 *
 * `AlertDialog` is one of the six material3 components this app is allowed, and it is the only
 * thing in this package that touches material3. It is wrapped in [PreviouslyMaterialBridge] so it
 * cannot arrive wearing `lightColorScheme()`, and **every** colour is passed explicitly: a
 * component that inherits its colour from the scheme is a bug. Its buttons are the app's own —
 * M3's `TextButton` is banned, and its label would be drawn in `primary` at Material's type scale.
 */
@Composable
private fun DiscardChangesDialog(count: Int, onDismiss: () -> Unit, onConfirm: () -> Unit) {
    PreviouslyMaterialBridge {
        AlertDialog(
            onDismissRequest = onDismiss,
            confirmButton = {
                TertiaryButton(
                    label = Copy.Account.discardChangesConfirm(count),
                    onClick = onConfirm,
                    destructive = true,
                )
            },
            dismissButton = {
                TertiaryButton(label = Copy.Confirm.cancel, onClick = onDismiss)
            },
            title = {
                BasicText(
                    text = Copy.Account.discardChangesTitle(count),
                    style = ThemeType.showTitleM.copy(color = ThemeColor.textPrimary),
                )
            },
            text = {
                BasicText(
                    text = Copy.Account.discardChangesMessage,
                    style = ThemeType.callout.copy(color = ThemeColor.textSecondary),
                )
            },
            shape = ContinuousCornerShape(ThemeRadius.card),
            containerColor = ThemeColor.surfaceFloating,
            titleContentColor = ThemeColor.textPrimary,
            textContentColor = ThemeColor.textSecondary,
            tonalElevation = 0.dp,
        )
    }
}

// -------------------------------------------------------------------------------------
// The host
// -------------------------------------------------------------------------------------

/**
 * The shared toast layer: the sync banner and up to three toasts stacked above the bottom chrome.
 *
 * **Order is fixed** — sync banner (top), error toast, neutral notice, undo toast (bottom, nearest
 * the thumb). All four can be on screen simultaneously.
 *
 * **There is no queue.** Each channel holds at most one value and a new one replaces the old: the
 * model cancels and restarts that channel's timer, and because an undo is identified by [undoKey]
 * the replacement re-announces.
 *
 * **The host is always mounted**, with conditional children — never mounted conditionally itself.
 * "Keeping the host always mounted also means the insert/remove transitions actually animate — the
 * animation lives on this container, not the transient child." It is mounted **twice** (the tab
 * shell and the Profile sheet), because a sheet presents above the shell's stack; whichever is
 * frontmost shows the same state, and a toast survives the sheet dismissing.
 *
 * ### Placement
 *
 * ```
 * ToastHost(...)
 *     .padding(horizontal = 22.dp)                       // the bottom bar's own margin
 *     .padding(bottom = ThemeMetrics.toastClearance)      // 62
 * ```
 * 22 is the bar's horizontal margin (the shipped 17 disagreed with it by 5 pt). The bottom inset is
 * measured from the **window**, not from the bar: too small and the toast lands ON the bar — on
 * Search it covered the field with the user's own query in it.
 *
 * ### Why the 9-dp gap is inside each child
 *
 * `Arrangement.spacedBy` inserts spacing between **every** child, including a zero-height
 * `AnimatedVisibility` that is currently hidden — which would leave phantom gaps in the stack. The
 * gap therefore travels with the child that owns it. The stack is bottom-anchored, so the extra
 * space above the topmost visible toast is invisible.
 *
 * ### The banner is suppressed over Profile
 *
 * Profile lists every failed change with its own Retry and Discard, so the banner there was a
 * duplicate of the screen being read. That is the CALLER's decision, not this host's: pass
 * `syncFailureCount = 0` while Profile is open (`SyncCenter.profileIsOpen`, which "existed for
 * exactly this and nothing read it").
 *
 * @param syncFailureCount failed changes; 0 hides the banner. See the note above.
 * @param syncRetryAvailable whether at least one failed row has something Retry can actually run.
 *   When false the banner offers "Dismiss" and confirms before discarding.
 * @param undoKey the live undo's identity (`UndoState.id`). A new value is a NEW toast: the
 *   transition replays and the live region speaks again.
 */
@Composable
fun ToastHost(
    syncFailureCount: Int,
    onRetrySync: () -> Unit,
    onDiscardSync: () -> Unit,
    laneItem: LaneItem?,
    onUndo: (UndoState) -> Unit,
    modifier: Modifier = Modifier,
    syncRetryAvailable: Boolean = false,
) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Bottom,
    ) {
        // 1 — the sync banner. Persistent chrome FADES; it never springs in.
        AnimatedVisibility(
            visible = syncFailureCount > 0,
            enter = fadeIn(motion(MotionToken.UI_SNAPPY)),
            exit = fadeOut(motion(MotionToken.UI_SNAPPY)),
        ) {
            SyncBanner(
                count = syncFailureCount,
                onDiscardAll = onDiscardSync,
                onRetry = if (syncRetryAvailable) onRetrySync else null,
            )
        }

        // 2 — the LANE (5 Sep): a removal, a move, an add, a notice or a failure, docked on the
        // bottom chrome. A mark's receipt is not here — it lands in place, under the control
        // that was pressed (`ReceiptLine`).
        LaneHost(item = laneItem, onUndo = onUndo, modifier = Modifier.padding(top = TOAST_STACK_GAP))
    }
}

// -------------------------------------------------------------------------------------
// Receipts (5 Sep)
// -------------------------------------------------------------------------------------
//
// The transient confirmation, rebuilt from the toast. A receipt is drawn in ONE of two places,
// decided at the write (`UndoState.placement`):
//   • IN PLACE — under the control that was pressed, when that control stays on screen: every
//     mark from a capsule (Today's hero, the show page) or a ring (Schedule's cards, the Up next
//     cards, the episode list). One quiet line, "✓ Episode 19 watched · Undo", for the window.
//   • THE LANE — docked on the bottom chrome: the poster, the fact, the show, Undo. For everything
//     whose object LEFT the screen or never had a control to hold the receipt, and for the notices
//     and the write failures. (iOS docks it INTO the tab bar as its 26.1 accessory; the Android bar
//     has no such lane, so it sits attached above it.)

/** What the lane shows. One item at a time — the lane is one lane. */
sealed class LaneItem {
    data class Error(val message: String) : LaneItem()
    data class Undo(val state: UndoState) : LaneItem()
    data class Notice(val message: String) : LaneItem()

    val key: String
        get() = when (this) {
            is Error -> "error/$message"
            is Undo -> "undo/${state.id}"
            is Notice -> "notice/$message"
        }
}

/**
 * The receipt IN the control: one line under the capsule or the row that was pressed. Drawn only
 * while the live undo is placed at [host] (and, on a row, is about [episode]).
 */
@Composable
fun ReceiptLine(
    host: String,
    modifier: Modifier = Modifier,
    episode: Int? = null,
    compact: Boolean = false,
) {
    val appModel = LocalAppModel.current
    val reduceMotion = LocalReduceMotion.current
    val undo = appModel.undo
    val live = undo != null &&
        undo.placement == ReceiptPlacement.InPlace(host) &&
        (episode == null || undo.episode == episode)
    // The last live state, kept for the exit so the line can leave with its words.
    var shown by remember { mutableStateOf<UndoState?>(null) }
    if (live) shown = undo
    AnimatedVisibility(
        visible = live,
        enter = ThemeMotion.toastEnter(reduceMotion),
        exit = ThemeMotion.toastExit(reduceMotion),
        modifier = modifier,
    ) {
        val state = shown ?: return@AnimatedVisibility
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = if (compact) 32.dp else 24.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = if (compact) Arrangement.Start else Arrangement.Center,
        ) {
            DrawnCheck(on = true, size = if (compact) 10.dp else 11.dp, tint = ThemeColor.accent)
            BasicText(
                text = state.receipt,
                style = (if (compact) ThemeType.metadata else ThemeType.metadataEmphasis)
                    .copy(color = ThemeColor.textSecondary),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(start = if (compact) ThemeSpace.x1 else ThemeSpace.x2),
            )
            BasicText(
                text = "·",
                style = ThemeType.metadataEmphasis.copy(color = ThemeColor.textTertiary),
                modifier = Modifier.padding(horizontal = ThemeSpace.x1),
            )
            ToastAction(label = Copy.Action.undo, onClick = { appModel.undoTapped(state) })
        }
    }
}

/** The lane's content: the poster (or a glyph), the fact, the show, and the one action. */
@Composable
fun ReceiptLane(item: LaneItem, onUndo: (UndoState) -> Unit, modifier: Modifier = Modifier) {
    val appModel = LocalAppModel.current
    val undo = (item as? LaneItem.Undo)?.state
    val poster = undo?.franchiseId?.let { appModel.franchise(it)?.portraitArt }
        ?: undo?.removedFranchise?.portraitArt
    val fact = when (item) {
        is LaneItem.Error -> item.message
        is LaneItem.Notice -> item.message
        is LaneItem.Undo -> item.state.receipt
    }
    val title = undo?.takeIf { it.title.isNotEmpty() && !it.added }?.title?.shelfShortened(fitting = LANE_TITLE_FIT)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .padding(start = ThemeSpace.x3, end = ThemeSpace.x1),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x3),
    ) {
        if (poster != null) {
            PosterSlot(url = poster, width = 26.dp, height = 39.dp, radius = 4.dp)
        } else {
            Box(
                modifier = Modifier
                    .size(28.dp)
                    .background(ThemeColor.surfaceFloating, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                if (item is LaneItem.Error) {
                    Image(
                        imageVector = rememberSymbol(PreviouslyIcons.WarningFilled),
                        contentDescription = null,
                        colorFilter = ColorFilter.tint(ThemeColor.warning),
                        modifier = Modifier.size(12.dp),
                    )
                } else {
                    DrawnCheck(on = true, size = 12.dp, tint = ThemeColor.accent)
                }
            }
        }
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(1.dp),
        ) {
            BasicText(
                text = fact,
                style = ThemeType.metadataEmphasis.copy(color = ThemeColor.textPrimary),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
            )
            if (title != null) {
                BasicText(
                    text = title,
                    style = ThemeType.caption.copy(color = ThemeColor.textSecondary),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        if (undo != null) {
            ToastAction(label = Copy.Action.undo, onClick = { onUndo(undo) })
        }
    }
}

/** The lane, docked on the bottom chrome: springs up from the bar, leaves on `uiDismiss`. */
@Composable
fun LaneHost(item: LaneItem?, onUndo: (UndoState) -> Unit, modifier: Modifier = Modifier) {
    val reduceMotion = LocalReduceMotion.current
    var shown by remember { mutableStateOf<LaneItem?>(null) }
    if (item != null) shown = item
    AnimatedVisibility(
        visible = item != null,
        enter = if (reduceMotion) fadeIn(motion(MotionToken.UI_REDUCED)) else
            fadeIn(motion(MotionToken.UI_SNAPPY)) + slideInVertically(motion(MotionToken.UI_SNAPPY)) { it / 2 },
        exit = ThemeMotion.toastExit(reduceMotion),
        modifier = modifier,
    ) {
        val current = shown ?: return@AnimatedVisibility
        key(current.key) {
            ReceiptLane(
                item = current,
                onUndo = onUndo,
                modifier = Modifier
                    .fillMaxWidth()
                    .shadowToken(ShadowToken.Floating, RoundedCornerShape(22.dp))
                    .chromeGlass(RoundedCornerShape(22.dp)),
            )
        }
    }
}

/** Between two stacked toasts. */
val TOAST_STACK_GAP = 9.dp

/** The lane's second line: two lines of caption beside a 26-dp poster (i3). */
private const val LANE_TITLE_FIT = 30
