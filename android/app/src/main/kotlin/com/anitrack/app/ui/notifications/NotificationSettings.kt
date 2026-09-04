package com.anitrack.app.ui.notifications

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.util.Log
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.LocalContext
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.notifications.EpisodeNotifications
import com.anitrack.app.ui.profile.ProfileRow
import com.anitrack.app.ui.profile.TrailingGlyph
import com.anitrack.app.ui.schedule.ScheduleReminders
import com.anitrack.model.copy.Copy
import kotlinx.coroutines.launch

/*
 * =====================================================================================
 * PROFILE → SETTINGS: THE NOTIFICATION ROWS
 * =====================================================================================
 *
 * Two rows, at the head of the Settings plate, above Haptics and Export library:
 *
 *     Notifications                                              On   ↗
 *     Exact timing                                               Off  ↗
 *     Episode alerts can arrive a few minutes late
 *
 * They are `ProfileRow`s — the design system's one grouped row in its settings dialect — and this
 * file adds no anatomy of its own. What it adds is the ladder: which row exists, when, and what it
 * is allowed to claim.
 *
 * -------------------------------------------------------------------------------------
 * WHY THERE IS NO IN-APP MASTER SWITCH
 * -------------------------------------------------------------------------------------
 *
 * The obvious shape for this surface is a switch — "Episode alerts", amber, the one legal amber
 * control beside Haptics. It is the wrong shape here, twice over:
 *
 *   * **The app owns neither answer.** Whether a notification may be posted belongs to the OS
 *     (`areNotificationsEnabled()`); whether an alarm fires to the minute belongs to the OS
 *     (`canScheduleExactAlarms()`). A switch the app cannot honour is the same defect as a bell
 *     that claims a precision the app does not have — the thing the whole alert surface is written
 *     to avoid. Both rows are therefore link rows: they state the system's answer and hand the user
 *     to the screen that owns it, with the external arrow (`open_in_new`, D29) that says the row
 *     leaves the app.
 *   * **A second in-app switch would gate one channel twice.** The app posts exactly one kind of
 *     notification — the episode alert (the Live Update countdown is deferred, `product-decisions`
 *     §8). So "Notifications" *is* the master control for episode alerts, and an app-level
 *     "Episode alerts" switch on top of it would be two controls for one fact, disagreeing the
 *     first time a user turned one off and the other on.
 *
 * The Haptics switch stays the one amber control on this screen, and it earns it: haptics are a
 * preference the app genuinely owns.
 *
 * -------------------------------------------------------------------------------------
 * THE LADDER
 * -------------------------------------------------------------------------------------
 *
 * **Exact timing is drawn only when it means something** — the app's own "a section that says 'not
 * here' is not a section" rule, applied to a row:
 *
 *   * below API 31 there is no such grant, and every alarm is already exact;
 *   * without `SCHEDULE_EXACT_ALARM` in the manifest the system screen would not list this app, so
 *     the row would send the user somewhere that cannot help;
 *   * with notifications switched off nothing is posted at all, and the timing of nothing is not a
 *     setting.
 *
 * In the last case the row above already says "Off" and already goes to the screen that fixes it.
 *
 * **Both values are read from the platform on every appearance and on every return from Settings**
 * (`ExactAlarms.granted`, `areNotificationsEnabled`), never cached across a visit. The launcher's
 * callback fires the moment the system screen is dismissed, which is the Android spelling of the
 * iOS row's `didBecomeActiveNotification` re-read — with no dependency on a lifecycle artifact this
 * module does not carry.
 *
 * -------------------------------------------------------------------------------------
 * WHAT IS DELIBERATELY ABSENT
 * -------------------------------------------------------------------------------------
 *
 *   * **Per-show reminder rows.** The spec has none: the reminder bell is the Schedule card's own
 *     control, on the airing it belongs to, and a mirror list of shows in Settings would be a
 *     second place to change one fact.
 *   * **A battery-optimisation row.** Samsung's "Put unused apps to sleep" and Xiaomi's Autostart
 *     are a real ceiling on delivery (PLAN D7c) and there is no in-app fix — but
 *     `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` is Play-restricted and this app does not
 *     qualify, and a row that opens a page to plead with is begging, not a setting. The
 *     Notifications row already reaches the app's system page, which is one tap from all of it.
 *
 * -------------------------------------------------------------------------------------
 * ADOPTION NOTE FOR THE SETTINGS SECTION
 * -------------------------------------------------------------------------------------
 *
 * [NotificationSettingsRows] is a **drop-in replacement for the single Notifications row** in
 * `ui/profile/Settings.kt`'s `SettingsSection`. Adopting it means deleting that row, its
 * `settingsLauncher`, its `LaunchedEffect` re-read and the private `notificationsEnabled` /
 * `launchNotificationSettings` helpers there — the copies here are byte-for-byte the same
 * behaviour, moved so the two notification rows share one launcher and one re-read. Leaving both
 * compiles and draws two Notifications rows, which is the one wrong outcome.
 */

/**
 * The notification block of Profile → Settings: the master row, and the exact-timing row when it
 * has something to say.
 *
 * @param trailingSeparator `false` only if these are the last rows in their plate. In
 *   `SettingsSection` they are followed by Haptics, so the default is right.
 */
@Composable
fun NotificationSettingsRows(trailingSeparator: Boolean = true) {
    val context = LocalContext.current

    var notificationsOn by remember { mutableStateOf(notificationsAllowed(context)) }
    var exactOn by remember { mutableStateOf(ExactAlarms.granted(context)) }

    val scope = rememberCoroutineScope()

    val reread = {
        notificationsOn = notificationsAllowed(context)
        exactOn = ExactAlarms.granted(context)
    }

    // Back from Settings: the sheet is still up, so the rows re-read the answer. One launcher for
    // both rows, because either destination can change either value — turning notifications off in
    // the system screen must remove the exact-timing row on the way back.
    //
    // **And the alarms are re-armed, which the re-read alone never did.** A denial has already run
    // `alarms.cancelAll()`, so at the moment a user switches notifications back on there is nothing
    // armed and nothing to arm it: the only production re-arm was `AmbientSync` off a confirmed
    // library write, and `AppModel.sceneBecameActive()` reloads only after two minutes away — which
    // a trip to the system notification screen and back is not. The row flipped to "On", the user
    // believed alerts were armed, and no alarm existed until the next library write.
    // `rearmNow` is the call this moment is documented as having, and this is the caller.
    // It is also the honest direction the other way: a REVOCATION stands the alarms down here
    // rather than leaving wake-ups armed for a user who has just switched alerts off.
    val launcher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult(),
    ) {
        reread()
        scope.launch {
            EpisodeNotifications.current?.rearmNow()
            // The bell mirror is derived from the same answer, so it is stale the instant the
            // permission changes.
            ScheduleReminders.refresh()
        }
    }

    // Re-read once when the sheet appears, so a permission changed since the last open is not stale.
    LaunchedEffect(Unit) { reread() }

    // Not `ExactAlarms.askable`: that one is about whether there is a GRANT to ask for, and this
    // row exists whether the grant is held or not — it is how a user turns it back off.
    val showExactTiming =
        notificationsOn && ExactAlarms.supported && ExactAlarms.declared(context)

    NotificationsRow(
        on = notificationsOn,
        separator = showExactTiming || trailingSeparator,
        onClick = { openNotificationSettings(context, launcher) },
    )

    if (showExactTiming) {
        ExactTimingRow(
            on = exactOn,
            separator = trailingSeparator,
            onClick = { ExactAlarms.request(context, launcher) },
        )
    }
}

/**
 * **The master row.** Whether this app may post a notification at all — the system's answer, and
 * the system's screen.
 *
 * The value is not decoration: *"the row said nothing about the one thing it is for. A user who
 * declined the system prompt had no way to learn, here, that alerts are off."* On Android the
 * answer is two-valued rather than three — `areNotificationsEnabled()` always answers, and on API
 * 33+ a fresh install answers `false` until the user grants, which is TRUE and is exactly what the
 * row exists to tell them.
 */
@Composable
internal fun NotificationsRow(
    on: Boolean,
    separator: Boolean,
    onClick: () -> Unit,
) {
    val value = if (on) Copy.State.on else Copy.State.off
    ProfileRow(
        title = Copy.Profile.NOTIFICATIONS,
        symbol = PreviouslyIcons.Notifications,
        separator = separator,
        hint = Copy.Profile.HINT_OPENS_SETTINGS,
        value = value,
        onClick = onClick,
    ) {
        ExternalValue(value)
    }
}

/**
 * **The exact-timing row** — the app's only control with no iOS twin (PLAN D31).
 *
 * The subtitle is drawn **only while the grant is absent**, and it is the app's one honest
 * statement of the degraded path: with `setAndAllowWhileIdle` an alert still arrives, Doze just
 * decides when. A row reading "Exact timing · Off" with nothing under it would leave a user whose
 * alerts land late with no line on this screen that admits it.
 *
 * When the grant is held there is no subtitle, because a settings row states a fact a verb cannot,
 * and "On" already is the fact.
 *
 * The bell-with-badge is the icon table's "alerts are on / the permission primer" — this row and
 * the contextual ask are the same subject, so they carry the same glyph. It sits beside the plain
 * bell above it, which is the difference between *whether* an alert arrives and *when*.
 */
@Composable
internal fun ExactTimingRow(
    on: Boolean,
    separator: Boolean,
    onClick: () -> Unit,
) {
    val value = if (on) Copy.State.on else Copy.State.off
    ProfileRow(
        title = Copy.Alert.exactTiming,
        symbol = PreviouslyIcons.NotificationsActive,
        subtitle = if (on) null else Copy.Alert.approximate,
        separator = separator,
        hint = Copy.Profile.HINT_OPENS_SETTINGS,
        value = value,
        onClick = onClick,
    ) {
        ExternalValue(value)
    }
}

/**
 * A row's current value beside the arrow that says the row leaves the app.
 *
 * `open_in_new`, not a chevron: *"This row leaves the app. An external arrow says so; a chevron
 * would not — and an arrow glyph contributes nothing to VoiceOver, which announced this identically
 * to the in-app Export row."* The glyph is silent; the value is spoken through the row's
 * `stateDescription` and the destination through its click label, so the drawn word is not read
 * twice.
 */
@Composable
private fun ExternalValue(value: String) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BasicText(
            text = value,
            style = ThemeType.metadata.copy(color = ThemeColor.textTertiary),
            maxLines = 1,
        )
        TrailingGlyph(PreviouslyIcons.Pending.OpenInNewTrailing, ThemeColor.textTertiary)
    }
}

/**
 * The system's own per-app notification screen.
 *
 * `ACTION_APP_NOTIFICATION_SETTINGS` exists from API 26, which is this app's floor; the app-details
 * screen is the fallback for an OEM that does not carry it, and both are wrapped because a device
 * with neither must not crash on a settings row.
 *
 * Deliberately the app screen and not `ACTION_CHANNEL_NOTIFICATION_SETTINGS`: the channel id
 * belongs to `notify/`, the app screen lists the channel anyway, and a settings row should not know
 * the scheduler's identifiers.
 */
internal fun openNotificationSettings(
    context: Context,
    launcher: ActivityResultLauncher<Intent>,
) {
    try {
        launcher.launch(
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName),
        )
        return
    } catch (e: ActivityNotFoundException) {
        Log.w(ALERTS_LOG_TAG, "No app notification settings screen on this device", e)
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
