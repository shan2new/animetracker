package com.anitrack.app.ui.notifications

import android.Manifest
import android.app.AlarmManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.core.app.NotificationManagerCompat
import com.anitrack.app.design.FeedbackCoordinator
import com.anitrack.app.design.FeedbackToken
import com.anitrack.app.design.MaterialSymbol
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.ui.control.InlineLink
import com.anitrack.app.ui.control.InlineLinkButton
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.control.SymbolIcon
import com.anitrack.app.ui.control.minimumTapTarget
import com.anitrack.app.ui.isAccessibilityTextSize
import com.anitrack.app.ui.negativePadding
import com.anitrack.model.copy.Copy

/*
 * =====================================================================================
 * THE EXACT-ALARM ASK
 * =====================================================================================
 *
 * The one control in this app with **no iOS twin**, and the reason it exists is a platform fact,
 * not a feature:
 *
 *   * `USE_EXACT_ALARM` — auto-granted, non-revocable — is **forbidden by Play policy** for this
 *     app. It is reserved for apps "whose core, user-facing functionality requires precisely-timed
 *     actions, such as dedicated alarm, timer, or calendar applications". An episode-drop notifier
 *     is not that, and declaring it is a review rejection. The app declares `SCHEDULE_EXACT_ALARM`
 *     and nothing else.
 *   * `SCHEDULE_EXACT_ALARM` is **denied by default** on Android 14+ for an app targeting API 33+.
 *     So on a fresh install on any modern device there are no exact alarms at all.
 *   * There is **no in-app dialog** for it. The only route is
 *     `Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM`, a screen in the system Settings app.
 *
 * Everything below follows from that (`docs/android-port/research/product-decisions.md` §4,
 * PLAN D7a / D31):
 *
 *  1. **The app is correct without the grant.** The scheduler's baseline is
 *     `setAndAllowWhileIdle`; an alert still arrives, minutes late in Doze. Nothing here gates a
 *     feature, and nothing here nags. If this file were deleted the alerts would still work.
 *  2. **Ask contextually and late** — at the moment alerts are turned on for an airing show, which
 *     is the same moment the notification primer is answered, and never at launch. Once per
 *     install, whichever way it is answered ([ExactTimingAskStore.answered]); the Settings row
 *     (`NotificationSettings.kt`) is the only way back in.
 *  3. **The wording states the benefit, not the mechanism** — `CopyAlerts` owns it, and its header
 *     carries the three copy laws this ask is written under. No string in this file.
 *  4. **Never claim a precision the app does not have.** [ExactAlarms.granted] is read from the
 *     platform on every composition and on every return from Settings; no cached "we asked, so it
 *     must be on".
 *
 * ## Why the ask is a ROW and not a dialog
 *
 * The notification primer settled this on the same screen, for the same reason, and the two asks
 * are literally consecutive in the same slot: *"The system permission dialog is never raised by an
 * add … It was a plate with a bell in a tile, a paragraph and a full-width amber capsule — a promo
 * card from a marketing site, on a search screen. It is a row on the canvas now."* A modal we raise
 * ourselves, seconds after the user answered the system's own modal, would be the second dialog in
 * one flow — and the reflex answer to an unexplained ask is No, after which the ask is spent
 * forever.
 *
 * [AlertPrimerRow] is therefore **the** primer anatomy, generalised over its words, and
 * `ui/discover/SearchComponents.kt`'s `NotificationPrimerRow` is the same drawing with the
 * notification strings baked in. When the two are next touched together, that one should delegate
 * here; until then this file is the copy that takes parameters, so no third anatomy can appear.
 *
 * ## Ordering — the two asks can never collide
 *
 * [ExactTimingAsk.visible] requires notifications to be *allowed*; the notification primer only
 * appears while they are *not*. So at most one ask is on screen at a time, without either knowing
 * about the other.
 *
 * ## What re-arms the alarms after a grant
 *
 * Nothing in this file calls the scheduler. The platform broadcasts
 * `ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED` when the user flips that switch, and
 * `notify/RearmReceiver` re-arms and upgrades the armed set from inexact to exact (PLAN D7b). A UI
 * file that also poked the scheduler would be a second, racier path to the same work.
 */

// ─────────────────────────────────────────────────────────────────────────────
// Geometry — the primer row's own anatomy
// ─────────────────────────────────────────────────────────────────────────────

/** The primer's glyph, at its iOS point size, and the fixed column it sits in. */
private val primerGlyph = 20.dp
private val primerGlyphColumn = 28.dp

/** The dismiss disc. The TARGET around it is [minimumTapTarget]. */
private val dismissDisc = 28.dp

/** The × inside it, at its iOS point size (`.caption2`, 11, bold). */
private val dismissGlyph = 11.dp

/**
 * The pull-back that keeps an inline link off the row's height.
 *
 * [InlineLinkButton] holds its own 44-dp target with real padding; without taking that back the
 * answer sets the row's height instead of sitting on its baseline.
 */
private val primerActionOverhang = InlineLink.sideOverhang

/** Logcat tag for the alert surfaces. Matches `PROFILE_LOG_TAG` / `SEARCH_LOG_TAG`'s spelling. */
internal const val ALERTS_LOG_TAG = "Alerts"

// ─────────────────────────────────────────────────────────────────────────────
// The row
// ─────────────────────────────────────────────────────────────────────────────

/**
 * **The primer row**: a glyph, a title, one supporting line, and the two answers as a link and a
 * dismiss disc — on the canvas, in the app's own row grammar, never a card.
 *
 * At an accessibility text size the layout flips to a column so the words take the full width and
 * the answers drop to their own line; beside two controls the sentence wraps one word per line.
 *
 * The rule underneath is drawn *after* the content so it spans the full width like every other
 * separator in the app, rather than starting at the copy column.
 *
 * @param action the affirmative answer. It is an [InlineLinkButton] — `interactive` ink, never
 *   amber: amber in this app means a fact or a state, and this is neither.
 * @param actionHint what the tap DOES, spoken by TalkBack as the click label. An answer that leaves
 *   the app for the system Settings app must say so; the word alone cannot.
 * @param dismiss the deferral's spoken label. There is no drawn word — the disc is the control —
 *   so this string *is* the control's name to a screen reader.
 */
@Composable
fun AlertPrimerRow(
    title: String,
    body: String,
    action: String,
    onAction: () -> Unit,
    dismiss: String,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    symbol: MaterialSymbol = PreviouslyIcons.NotificationsActive,
    actionHint: String? = null,
) {
    val isAX = isAccessibilityTextSize()

    val words: @Composable (Modifier) -> Unit = { slot ->
        Row(
            modifier = slot,
            horizontalArrangement = Arrangement.spacedBy(ThemeMetrics.artGap),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.width(primerGlyphColumn), contentAlignment = Alignment.Center) {
                SymbolIcon(symbol = symbol, tint = ThemeColor.textTertiary, glyph = primerGlyph)
            }
            Column(verticalArrangement = Arrangement.spacedBy(ThemeMetrics.titleGap)) {
                BasicText(
                    text = title,
                    style = ThemeType.rowTitle.copy(color = ThemeColor.textPrimary),
                )
                BasicText(
                    text = body,
                    style = ThemeType.rowMeta.copy(color = ThemeColor.textSecondary),
                )
            }
        }
    }

    val answers: @Composable () -> Unit = {
        Row(
            horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            InlineLinkButton(
                label = action,
                onClick = onAction,
                onClickLabel = actionHint,
                modifier = Modifier.negativePadding(
                    top = primerActionOverhang,
                    bottom = primerActionOverhang,
                    start = if (isAX) primerActionOverhang else 0.dp,
                ),
            )
            PrimerDismiss(label = dismiss, onClick = onDismiss)
        }
    }

    val container = modifier
        .fillMaxWidth()
        .drawWithContent {
            drawContent()
            val thickness = ThemeMetrics.hairline.toPx()
            drawRect(
                color = ThemeColor.separatorQuiet,
                topLeft = Offset(0f, size.height - thickness),
                size = Size(size.width, thickness),
            )
        }
        .padding(horizontal = ThemeMetrics.gutter)
        .heightIn(min = ThemeMetrics.rowCompact)
        .padding(vertical = ThemeSpace.x2)

    if (isAX) {
        Column(
            modifier = container,
            verticalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
            horizontalAlignment = Alignment.Start,
        ) {
            words(Modifier.fillMaxWidth())
            answers()
        }
    } else {
        Row(modifier = container, verticalAlignment = Alignment.CenterVertically) {
            words(Modifier.weight(1f))
            answers()
        }
    }
}

/** The deferral: a 28-dp disc in a 44-dp target. The × is decoration; [label] names the control. */
@Composable
private fun PrimerDismiss(label: String, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .clickable(
                interactionSource = null,
                indication = PressStyle.textAction,
                role = Role.Button,
                onClick = onClick,
            )
            .semantics(mergeDescendants = true) { contentDescription = label }
            .size(minimumTapTarget)
            .padding(ThemeSpace.x1),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .size(dismissDisc)
                .background(ThemeColor.surfaceRaised, CircleShape)
                .border(ThemeMetrics.hairline, ThemeColor.posterEdge, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            SymbolIcon(
                symbol = PreviouslyIcons.Close,
                tint = ThemeColor.textTertiary,
                glyph = dismissGlyph,
            )
        }
    }
}

/**
 * The exact-alarm ask, in the primer's own grammar:
 *
 * > **Exact timing** · Without it, an episode alert can arrive a few minutes late. · Turn on · ×
 *
 * "Turn on" rather than "Settings": the destination is one switch named the same thing, and naming
 * the *place* instead of the *outcome* would make this the only answer in the app that describes
 * where it goes rather than what it does. The click label carries the leaving.
 *
 * The bell-with-badge is [PreviouslyIcons.NotificationsActive] — the icon table's registered
 * meaning is "alerts are on / the permission primer", which is exactly this row.
 */
@Composable
fun ExactTimingPrimerRow(
    onTurnOn: () -> Unit,
    onNotNow: () -> Unit,
    modifier: Modifier = Modifier,
) {
    AlertPrimerRow(
        title = Copy.Alert.exactTiming,
        body = Copy.Alert.askBody,
        action = Copy.Search.primerTurnOn,
        onAction = onTurnOn,
        dismiss = Copy.Search.primerNotNow,
        onDismiss = onNotNow,
        modifier = modifier,
        actionHint = Copy.Profile.HINT_OPENS_SETTINGS,
    )
}

// ─────────────────────────────────────────────────────────────────────────────
// The platform truth
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Everything this app knows about the exact-alarm grant, in one object, read from the platform
 * every time.
 *
 * **Nothing here is cached.** The grant is revocable from system Settings at any moment, including
 * while this process is alive, and a screen that remembered "we asked and they said yes" would be
 * the app claiming a precision it does not have — the one thing the alert surfaces may never do.
 */
object ExactAlarms {

    /**
     * Is there a grant to hold at all?
     *
     * The permission arrived in API 31. Below that every alarm is exact and asking for anything
     * would be a control for a problem the device does not have, so the row and the ask simply
     * never appear. (`minSdk` is 26 — see `docs/android-port/research/minsdk-decision.md`.)
     */
    val supported: Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S

    /** Will an alarm armed right now fire to the minute? Read from `AlarmManager`, never stored. */
    fun granted(context: Context): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(AlarmManager::class.java)?.canScheduleExactAlarms() ?: false
        } else {
            true
        }

    /**
     * Does the app actually DECLARE `SCHEDULE_EXACT_ALARM`?
     *
     * The same guard the notification primer keeps for `POST_NOTIFICATIONS`, and for the same
     * reason: the system's "Alarms & reminders" screen lists only apps that declare it, so without
     * the declaration this would be a row promising a switch the user will not find — the exact
     * defect the whole ask exists to avoid. It is also the honest failure mode if the manifest
     * entry is ever dropped in a refactor: the control disappears rather than lying.
     */
    fun declared(context: Context): Boolean {
        // The permission constant is a compile-time String and resolves on any API level, but a
        // device that cannot hold the grant has nothing to declare it for — answer without walking
        // the package manager.
        if (!supported) return false
        return runCatching {
            context.packageManager
                .getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
                .requestedPermissions
                ?.contains(Manifest.permission.SCHEDULE_EXACT_ALARM) == true
        }.getOrDefault(false)
    }

    /** Is there anything to offer this device — a grant that exists, is declared, and is missing? */
    fun askable(context: Context): Boolean =
        supported && declared(context) && !granted(context)

    /**
     * Opens the system screen that owns the switch, through [launcher] so the caller re-reads the
     * answer the moment the user comes back.
     *
     * No `package:` data URI on the request: the action already resolves to the calling package's
     * own page, and adding data is a known way to get `ActivityNotFoundException` on some OEM
     * builds. The app-details page is the fallback — it is one tap from the same switch — and a
     * device with neither must not crash on a settings row.
     */
    fun request(context: Context, launcher: ActivityResultLauncher<Intent>) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                launcher.launch(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM))
                return
            } catch (e: ActivityNotFoundException) {
                Log.w(ALERTS_LOG_TAG, "No exact-alarm settings screen on this device", e)
            }
        }
        try {
            launcher.launch(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(Uri.fromParts("package", context.packageName, null)),
            )
        } catch (e: ActivityNotFoundException) {
            Log.w(ALERTS_LOG_TAG, "No app-details settings screen on this device", e)
        }
    }
}

/** `true` when this app may post a notification at all — the gate the ask sits behind. */
internal fun notificationsAllowed(context: Context): Boolean =
    NotificationManagerCompat.from(context).areNotificationsEnabled()

// ─────────────────────────────────────────────────────────────────────────────
// The ask's persistence and its state
// ─────────────────────────────────────────────────────────────────────────────

/**
 * The ask's two flags, in the **same preferences file the notification primer uses**
 * (`previously.notifications`) — they are two answers to one question ("do you want to be told
 * about episodes?") and splitting them across two files would be two places to reach for whenever
 * that state is cleared.
 *
 * Like the notification primer's flags, they are **per install, not per account**: the OS asks its
 * own permission question once per install too, and re-raising both asks at every sign-in would be
 * the nag the product decision rules out. Sign-out clears the airing plan and the alarms; it does
 * not un-ask a question the device has already answered.
 *
 * `SharedPreferences` rather than DataStore, deliberately, for the reason the notification primer's
 * store carries: the read has to be SYNCHRONOUS, so the ask's visibility is decided on the frame
 * the screen first composes rather than one collection later.
 *
 * There are no iOS keys to match here — this ask has no iOS twin — so the keys are named after the
 * primer's, in the same shape.
 */
internal class ExactTimingAskStore(private val prefs: SharedPreferences) {

    /**
     * Alerts were turned on for an airing show, so the ask has something to be about.
     *
     * Persisted, like the notification primer's, because the moment that arms it (an add that
     * stuck, an Allow that landed) and the moment the row can be drawn are not the same frame, and
     * the user may leave the tab in between.
     */
    var pending: Boolean
        get() = prefs.getBoolean(PENDING_KEY, false)
        set(value) = prefs.edit().putBoolean(PENDING_KEY, value).apply()

    /**
     * Answered once. **One-shot forever, whichever way it was answered** — the product decision is
     * "ask once; if declined, never ask again", and the Settings row is the way back in.
     */
    var answered: Boolean
        get() = prefs.getBoolean(ANSWERED_KEY, false)
        set(value) = prefs.edit().putBoolean(ANSWERED_KEY, value).apply()

    companion object {
        const val PENDING_KEY = "previously.exactAlarmPrimerPending"
        const val ANSWERED_KEY = "previously.exactAlarmPrimerAnswered"

        /** The notification primer's file. One question, one home. */
        private const val PREFS_NAME = "previously.notifications"

        fun from(context: Context): ExactTimingAskStore = ExactTimingAskStore(
            context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE),
        )
    }
}

/**
 * The ask's whole behaviour, so a screen hosting it writes no policy of its own.
 *
 * Life of an ask:
 *
 * ```
 *  alerts turned on for an airing show ─→ arm()
 *                                          ↓  (pending, and everything else true)
 *                                       visible ─→ ExactTimingPrimerRow
 *                                          ↓
 *                        turnOn() ──────────┴────────── notNow()
 *                            ↓                              ↓
 *                    system Settings                    answered = true
 *                            ↓                          (never asked again)
 *                    back → re-read the grant
 *                            ↓ granted
 *                    one haptic + onGranted()
 * ```
 *
 * Both answers set `answered`, and [visible] is recomputed from the platform rather than from the
 * flags alone — a user who granted the permission from the Settings row first will never see the
 * ask at all.
 */
@Stable
class ExactTimingAsk internal constructor(
    private val context: Context,
    private val store: ExactTimingAskStore,
) {

    /**
     * How the ask reaches the system screen.
     *
     * Set by [rememberExactTimingAsk] once the `ActivityResultLauncher` exists — the launcher's
     * callback has to be able to call [refresh] on *this* instance, so one of the two has to be
     * built first and handed the other. It is the opener, because a launcher created after the ask
     * keeps `rememberLauncherForActivityResult`'s own lifecycle handling intact.
     */
    internal var opener: (() -> Unit)? = null

    /** Whether the row should be drawn this frame. */
    var visible by mutableStateOf(false)
        private set

    /**
     * Alerts were just turned on for an airing show — the moment the ask is allowed to exist.
     *
     * Call it from the notification primer's granted branch, and from wherever an airing AniList
     * show is added on a device that already allows notifications (API 31/32, or a user who granted
     * long ago). It is cheap and idempotent: everything that decides whether the row can appear is
     * re-read here.
     */
    fun arm() {
        if (store.answered) return
        store.pending = true
        refresh()
    }

    /**
     * Re-decide visibility from the platform. Call on first composition and after anything that
     * could have changed the grant or the notification permission.
     */
    fun refresh() {
        visible = store.pending &&
            !store.answered &&
            notificationsAllowed(context) &&
            ExactAlarms.askable(context)
    }

    /** The affirmative answer: spend the ask, then hand the user to the system's own switch. */
    fun turnOn() {
        settle()
        opener?.invoke()
    }

    /** The deferral. Spends the ask too — asking twice is the nag the decision forbids. */
    fun notNow() = settle()

    private fun settle() {
        store.answered = true
        store.pending = false
        visible = false
    }
}

/**
 * Hosts an [ExactTimingAsk] in a composition, with the Settings round trip wired up.
 *
 * @param onGranted the grant actually landed. The caller shows the receipt —
 *   `appModel.showNotice(Copy.Alert.exactTimingOn)` — because a notice belongs to the screen that
 *   owns the toast host, not to a permission helper. The **haptic is fired here**, once, so the two
 *   halves of one transaction cannot both buzz.
 */
@Composable
fun rememberExactTimingAsk(onGranted: () -> Unit = {}): ExactTimingAsk {
    val context = LocalContext.current
    val store = remember(context) { ExactTimingAskStore.from(context) }
    val ask = remember(context, store) { ExactTimingAsk(context = context, store = store) }

    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) {
        // The result code is meaningless here — the system screen reports nothing. The answer is
        // the platform's, read back the moment the user returns.
        ask.refresh()
        if (ExactAlarms.granted(context)) {
            // One haptic for one transaction. The receipt itself is the caller's — `showNotice`
            // fires none of its own.
            FeedbackCoordinator.fire(FeedbackToken.SUCCESS)
            onGranted()
        }
    }

    SideEffect { ask.opener = { ExactAlarms.request(context, launcher) } }

    // Re-read once when the host appears, so a grant or a revocation since the last visit is not
    // stale — and so an ask armed on a previous launch is drawn on the frame the screen composes.
    LaunchedEffect(ask) { ask.refresh() }

    return ask
}
