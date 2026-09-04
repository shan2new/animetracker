package com.anitrack.app.ui.profile

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.util.Log
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.BasicText
import androidx.compose.material3.AlertDialog
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.core.app.NotificationManagerCompat
import com.anitrack.app.data.AppConfig
import com.anitrack.app.design.ContinuousCornerShape
import com.anitrack.app.design.FeedbackCoordinator
import com.anitrack.app.design.FeedbackToken
import com.anitrack.app.design.MaterialSymbol
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.PreviouslyMaterialBridge
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeMotion
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.ui.control.PreviouslySwitch
import com.anitrack.app.ui.control.SymbolIcon
import com.anitrack.app.ui.control.TertiaryButton
import com.anitrack.app.ui.control.minimumTapTarget
import com.anitrack.app.ui.isAccessibilityTextSize
import com.anitrack.app.ui.list.GroupedList
import com.anitrack.app.ui.list.GroupedRow
import com.anitrack.app.ui.list.GroupedTrailing
import com.anitrack.app.ui.list.GroupedRowMetrics
import com.anitrack.app.ui.list.GroupedSymbolStyle
import com.anitrack.app.ui.scaledDp
import com.anitrack.app.ui.state.IndeterminateArc
import com.anitrack.model.AniTrackJson
import com.anitrack.model.Franchise
import com.anitrack.model.FranchisePart
import com.anitrack.model.canonicalLabel
import com.anitrack.model.copy.Copy
import com.anitrack.model.effectiveStatus
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request

// =====================================================================================
// THE ACCOUNT SHEET'S CONTROLS — the port of the settings / account / destructive half of
// `ios/Sources/Features/Profile/ProfileView.swift`, plus `LibraryExport.swift` and
// `AccountDeletion.swift`. Spec: docs/android-port/spec/profile-shell.md §6.9–6.16, §6.21.
//
// Two rules govern everything below and neither is cosmetic:
//
//   * **Settings rows are VERB-ONLY.** No poster fan, no marketing subtitles. The one subtitle on
//     this screen states a fact a verb cannot ("Erases your library, progress and history").
//   * **Amber is never an action colour.** The Haptics switch is the one legal amber here: a switch
//     reports STATE, and the ink on its amber track is `onAccent`, so no amber *word* is drawn.
//
// [ProfileRowLabel] IS `GroupedRow` — the design system's one grouped row, in its
// `GroupedSymbolStyle.Column` dialect. It used to be a second component with its own geometry,
// justified by three differences (a bare monochrome symbol column instead of a tinted tile, a
// destructive title ink, an in-flight state); all three are parameters on the one row now, and the
// four-dp drift between the two anatomies is gone with the copy.
//
// -------------------------------------------------------------------------------------
// WHAT CHANGED IN THE PORT, AND WHY (fidelity line: port the meaning, render with native means,
// re-tune the numbers)
//
// 1. **Export is Android's document picker, not a share sheet.** iOS wraps each row in a
//    `ShareLink`. `Intent.ACTION_SEND` with a file needs a `FileProvider` declared in the manifest;
//    `ACTION_CREATE_DOCUMENT` needs nothing at all, and the shipped footnote already describes it
//    word for word — "Nothing leaves your account until you choose a destination." The user picks
//    the destination, the app writes the bytes, and no permission is spent.
//
// 2. **The notification row's value is two-valued, not three.** iOS distinguishes `notDetermined`
//    (draw no word at all) from denied. Android has no such state at the row's altitude:
//    `areNotificationsEnabled()` always answers, and on API 33+ a fresh install answers `false`
//    until the user grants — which is TRUE and is exactly what the row exists to tell them.
//
// 3. **"Back from Settings" is an activity result, not a lifecycle observer.** The row launches the
//    system screen through a launcher and re-reads in its callback, which fires the moment the user
//    returns. Same intent as the iOS `didBecomeActiveNotification` re-read, with no dependency on a
//    lifecycle-compose artifact this module does not carry.
//
// 4. **"Opens in Safari" / "Opens Mail" are Android sentences here.** A hint that names an iPhone
//    app is wrong on a device that has neither. Everything else is verbatim.
// =====================================================================================

// ─────────────────────────────────────────────────────────────────────────────
// Copy
//
// This screen's strings live in `Copy.Profile` (`:model`, `copy/CopyProfile.kt`) — the port of the
// `AccountCopy` enum in `ProfileView.swift`. They were staged here while the argument stood that a
// Kotlin object cannot be reopened from another module; it never ruled out a sibling object in the
// catalogue package, which is where they are now, inside the corpus the copy gate walks.
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Row geometry
//
// There is none here any more. The settings row's whole anatomy — leading inset, symbol column,
// copy gap, vertical air, separator inset, the accessibility-size alignment — is `GroupedRow`'s, in
// `ui/list/GroupedList.kt`, drawn in its `GroupedSymbolStyle.Column` dialect. This file used to
// carry a second copy of all of it, four dp apart in every measure, so Profile → Settings and
// Detail → Watch history showed two settings-row anatomies one push apart. What is left below is
// the trailing furniture that genuinely belongs to this screen.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Where a settings row's separator starts — the TITLE's leading edge, which is also where a
 * `GroupedRow` in the column dialect insets its own rule.
 *
 * Exported because two hand-built rows on the Profile sheet (the failure row and its detail block)
 * align their own content to it. It is DERIVED from the one row's geometry, never re-added: it was
 * `gutter + 22 + 12` = 50 while the row it was supposed to match ruled at 54.
 */
internal val ProfileRowTextInset: Dp = GroupedRowMetrics.columnSeparatorInset

/**
 * Trailing indicators scale with the row titles they sit beside — iOS
 * `@ScaledMetric(relativeTo: .body) private var indicatorSize: CGFloat = 14`. Fixed-size glyphs
 * shrank to specks against ~24-dp titles at AX1.
 */
@Composable
internal fun indicatorSize(): Dp = scaledDp(14.dp)

/** The in-flight spinner's diameter, stroke and arc. */
private val SpinnerSize = 18.dp
private val SpinnerStroke = 2.dp
private const val SpinnerSweep = 270f

/** The trailing indicator's own box: iOS `.frame(width: 28, height: 44)` — the 44 is the rule. */
private val TrailingColumn = 28.dp
private val TrailingColumnHeight = minimumTapTarget

// ─────────────────────────────────────────────────────────────────────────────
// The row
// ─────────────────────────────────────────────────────────────────────────────

/**
 * A settings row: the shared [GroupedRow] in its column dialect, with this screen's ink.
 *
 * It exists as a name, not as an anatomy — every measurement is the design system's. The two
 * defaults it fixes are the ones the settings dialect always wants: a monochrome symbol column with
 * no ground, and `textSecondary` for the symbol.
 *
 * @param symbol `null` keeps the column's width and — when [indicateWait] — draws the in-flight
 *   indicator in it, which is how the row guarantees a wait is shown once, in one place, and never
 *   as a glyph plus a spinner.
 */
@Composable
internal fun ProfileRowLabel(
    title: String,
    modifier: Modifier = Modifier,
    symbol: MaterialSymbol? = null,
    symbolTint: Color = ThemeColor.textSecondary,
    titleTint: Color = ThemeColor.textPrimary,
    subtitle: String? = null,
    separator: Boolean = true,
    indicateWait: Boolean = true,
    trailing: (@Composable RowScope.() -> Unit)? = null,
) {
    GroupedRow(
        title = title,
        modifier = modifier,
        symbol = symbol,
        symbolStyle = GroupedSymbolStyle.Column,
        symbolTint = symbolTint,
        titleTint = titleTint,
        subtitle = subtitle,
        separator = separator,
        indicateWait = indicateWait,
        trailingContent = trailing,
    )
}

/**
 * [ProfileRowLabel] as a button, pressing to `surfacePressed` through the shared grouped-row press
 * style — which is the same row with an `onClick`, not a second one.
 *
 * @param enabled a disabled row keeps its place and stops answering — the destructive pair disable
 *   each other while either is in flight.
 * @param hint what tapping the row does, spoken by TalkBack as the click label. iOS marks the two
 *   web rows `.isLink`; Compose has no link role, so the affordance is carried by this sentence —
 *   which is what a screen-reader user actually needs, and the reason the arrow glyph is silent.
 * @param value the row's current value, spoken as a state description ("On" / "Off").
 * @param label overrides the spoken title, for a row whose drawn words are a format and not a verb
 *   ("JSON" → "Export as JSON").
 */
@Composable
internal fun ProfileRow(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    symbol: MaterialSymbol? = null,
    symbolTint: Color = ThemeColor.textSecondary,
    titleTint: Color = ThemeColor.textPrimary,
    subtitle: String? = null,
    separator: Boolean = true,
    enabled: Boolean = true,
    hint: String? = null,
    value: String? = null,
    label: String? = null,
    trailing: (@Composable RowScope.() -> Unit)? = null,
) {
    GroupedRow(
        title = title,
        modifier = modifier,
        symbol = symbol,
        symbolStyle = GroupedSymbolStyle.Column,
        symbolTint = symbolTint,
        titleTint = titleTint,
        subtitle = subtitle,
        separator = separator,
        enabled = enabled,
        indicateWait = false,
        hint = hint,
        value = value,
        label = label,
        onClick = onClick,
        trailingContent = trailing,
    )
}

/**
 * A trailing indicator that scales with the row's text.
 *
 * @param scale iOS's `chevron.forward` is drawn at 0.86 — a disclosure sits a size below an
 *   external arrow, because one of them is the app and the other is not.
 */
@Composable
internal fun TrailingGlyph(
    symbol: MaterialSymbol,
    tint: Color,
    modifier: Modifier = Modifier,
    scale: Float = 1f,
) {
    Box(
        modifier = modifier.size(TrailingColumn, TrailingColumnHeight),
        contentAlignment = Alignment.Center,
    ) {
        SymbolIcon(symbol = symbol, tint = tint, glyph = indicatorSize() * scale)
    }
}

/**
 * A settings row's in-flight spinner, at the size a row's trailing column holds.
 *
 * It is a size and an ink, not a second spinner: the arc, the turn and the Reduce Motion decision
 * are all [IndeterminateArc]'s (`ui/state/Notices.kt`). This file used to hand-roll its own copy
 * of the drawing, which is how the app came to honour the preference on a skeleton and ignore it on
 * a spinner two taps away.
 *
 * Deliberately **not** `RefreshIndicator`: that one waits 400 ms before it appears, which is right
 * for a background refresh and wrong here — *"every other write in the app is optimistic and shows
 * its result immediately; the one that cannot be undone showed nothing at all, so a user who waited
 * a second tapped Sign out again."*
 */
@Composable
internal fun InlineSpinner(
    tint: Color,
    modifier: Modifier = Modifier,
    diameter: Dp = SpinnerSize,
) {
    IndeterminateArc(
        tint = tint,
        diameter = diameter,
        stroke = SpinnerStroke,
        sweep = SpinnerSweep,
        modifier = modifier,
    )
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Notifications · Haptics · Export library. Verb-only rows, in that order.
 *
 * @param onExport pushes the export screen inside the sheet's own host.
 */
@Composable
internal fun SettingsSection(
    hapticsOn: Boolean,
    onHapticsChange: (Boolean) -> Unit,
    onExport: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    var notificationsOn by remember { mutableStateOf(notificationsEnabled(context)) }

    // Back from Settings: the sheet is still up, so the row re-reads the answer. The launcher's
    // callback fires the moment the system screen is dismissed — see note 3 in the file header.
    val settingsLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult(),
    ) { notificationsOn = notificationsEnabled(context) }

    // Re-read once when the sheet appears, so a permission changed since the last open is not stale.
    LaunchedEffect(Unit) { notificationsOn = notificationsEnabled(context) }

    GroupedList(header = Copy.Profile.SETTINGS, modifier = modifier) {
        val notificationsValue = if (notificationsOn) Copy.State.on else Copy.State.off
        ProfileRow(
            title = Copy.Profile.NOTIFICATIONS,
            symbol = PreviouslyIcons.Notifications,
            hint = Copy.Profile.HINT_OPENS_SETTINGS,
            value = notificationsValue,
            onClick = { settingsLauncher.launchNotificationSettings(context) },
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // The row said nothing about the one thing it is for. A user who declined the
                // system prompt had no way to learn, here, that alerts are off.
                BasicText(
                    text = notificationsValue,
                    style = ThemeType.metadata.copy(color = ThemeColor.textTertiary),
                    maxLines = 1,
                )
                // This row leaves the app. An external arrow says so; a chevron would not.
                TrailingGlyph(PreviouslyIcons.Pending.OpenInNewTrailing, ThemeColor.textTertiary)
            }
        }

        HapticsRow(checked = hapticsOn, onCheckedChange = onHapticsChange)

        // A PUSH, not a menu: the pushed screen gives each format a title and a real support line,
        // and covers nothing.
        ProfileRow(
            title = Copy.Profile.EXPORT,
            symbol = PreviouslyIcons.Share,
            separator = false,
            onClick = onExport,
        ) {
            TrailingGlyph(PreviouslyIcons.ChevronRight, ThemeColor.textDisabled, scale = 0.86f)
        }
    }
}

/**
 * The one switch on this screen, and the one legal amber control on it: a switch reports STATE, and
 * state in this app is one colour. The ink on the amber track is `onAccent`, so no amber *word* is
 * drawn.
 *
 * `GroupedTrailing.Toggle` rather than a switch drawn into a trailing slot: the shared row then
 * makes ITSELF the toggleable element, which is the branch that matters — a switch nested inside a
 * button does not survive as an independent element, and was announced without the switch trait and
 * without its on/off value.
 */
@Composable
private fun HapticsRow(checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    GroupedRow(
        title = Copy.Profile.HAPTICS,
        symbol = PreviouslyIcons.TouchApp,
        symbolStyle = GroupedSymbolStyle.Column,
        symbolTint = ThemeColor.textSecondary,
        trailing = GroupedTrailing.Toggle(checked, onCheckedChange),
    )
}

/** `true` when this app may post a notification at all. See note 2 in the file header. */
private fun notificationsEnabled(context: Context): Boolean =
    NotificationManagerCompat.from(context).areNotificationsEnabled()

/**
 * The system's own per-app notification screen.
 *
 * `ACTION_APP_NOTIFICATION_SETTINGS` exists from API 26, which is this app's floor; the app-details
 * screen is the fallback for an OEM that does not carry it, and both are wrapped because a device
 * with neither must not crash on a settings row.
 */
private fun androidx.activity.result.ActivityResultLauncher<Intent>.launchNotificationSettings(
    context: Context,
) {
    val appNotifications = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
        .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
    val details = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
        .setData(Uri.fromParts("package", context.packageName, null))
    try {
        launch(appNotifications)
    } catch (e: ActivityNotFoundException) {
        try {
            launch(details)
        } catch (e2: ActivityNotFoundException) {
            Log.w(PROFILE_LOG_TAG, "No settings activity for notifications", e2)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Account (Play Store / App Store guideline 5.1.1)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Privacy, Terms and a way to reach a human.
 *
 * **A row whose destination is not configured is OMITTED**, never drawn inert: a placeholder baked
 * into a shipped string is a broken Privacy Policy link, which is itself a store rejection. (iOS
 * draws all three unconditionally and only the tap is inert; `AppConfig`'s own comment says the row
 * should be omitted, and that is the behaviour ported here.)
 *
 * **The case rule, settled:** Title Case is for the NAMES OF WORKS, and a privacy policy and terms
 * of use are named documents — "Privacy Policy", "Terms of Use". Everything else on this screen is
 * a verb phrase in sentence case, including "Contact support", which is an action and not the name
 * of a document. Two conventions, one rule, no exceptions.
 */
@Composable
internal fun AccountSection(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val rows = remember {
        listOfNotNull(
            AppConfig.privacyUrl?.let {
                LegalRow(PreviouslyIcons.FrontHand, Copy.Action.privacyPolicy, null, it, Copy.Profile.HINT_OPENS_BROWSER)
            },
            AppConfig.termsUrl?.let {
                LegalRow(PreviouslyIcons.Description, Copy.Action.termsOfUse, null, it, Copy.Profile.HINT_OPENS_BROWSER)
            },
            AppConfig.supportUrl?.let {
                LegalRow(
                    symbol = PreviouslyIcons.Mail,
                    title = Copy.Action.contactSupport,
                    subtitle = AppConfig.supportEmail,
                    url = it,
                    hint = Copy.Profile.HINT_OPENS_MAIL,
                )
            },
        )
    }
    if (rows.isEmpty()) return

    GroupedList(header = Copy.Profile.ACCOUNT, modifier = modifier) {
        rows.forEachIndexed { i, row ->
            ProfileRow(
                title = row.title,
                symbol = row.symbol,
                subtitle = row.subtitle,
                separator = i < rows.lastIndex,
                // `hint` IS the link affordance here. iOS marks these rows `.isLink`; Compose's
                // `Role` has no `Link` member (Button, Checkbox, Switch, RadioButton, Tab, Image,
                // DropdownList, ValuePicker, Carousel — and that is the whole set), so the
                // destination is spoken instead: "Opens in your browser", "Opens your email app".
                hint = row.hint,
                onClick = { openExternal(context, row.url) },
            ) {
                TrailingGlyph(PreviouslyIcons.Pending.OpenInNewTrailing, ThemeColor.textTertiary)
            }
        }
    }
}

private data class LegalRow(
    val symbol: MaterialSymbol,
    val title: String,
    val subtitle: String?,
    val url: String,
    val hint: String,
)

/**
 * Hands a URL to whatever the device uses for it.
 *
 * A `mailto:` goes out as `ACTION_SENDTO`, which is the intent an email client declares; everything
 * else is `ACTION_VIEW`. Both are wrapped: on API 30+ a `mailto:` target is subject to package
 * visibility, so a build whose manifest carries no `<queries>` entry for it resolves to nothing —
 * that is a build problem, and one line in logcat is a better debugging experience than a crash on
 * a support row.
 */
private fun openExternal(context: Context, url: String) {
    val uri = Uri.parse(url)
    val action = if (uri.scheme.equals("mailto", ignoreCase = true)) Intent.ACTION_SENDTO else Intent.ACTION_VIEW
    try {
        context.startActivity(Intent(action, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (e: ActivityNotFoundException) {
        Log.w(PROFILE_LOG_TAG, "Nothing on this device handles $url", e)
    }
}

internal const val PROFILE_LOG_TAG = "Profile"

// ─────────────────────────────────────────────────────────────────────────────
// Sign out / Delete
// ─────────────────────────────────────────────────────────────────────────────

/**
 * A row, not a centred word. The colour carries the weight — but only on the LABEL: a fully
 * saturated destructive icon on a routine, reversible action made Sign out and Delete account read
 * as a pair of equal choices.
 */
@Composable
internal fun SignOutSection(
    signingOut: Boolean,
    deleting: Boolean,
    onSignOut: () -> Unit,
    modifier: Modifier = Modifier,
) {
    GroupedList(modifier = modifier) {
        ProfileRow(
            title = Copy.Action.signOut,
            symbol = PreviouslyIcons.Logout,
            symbolTint = ThemeColor.textSecondary,
            titleTint = ThemeColor.destructive,
            separator = false,
            enabled = !signingOut && !deleting,
            hint = Copy.Profile.HINT_SIGN_OUT,
            onClick = onSignOut,
        ) {
            if (signingOut) {
                Box(
                    Modifier.size(TrailingColumnHeight),
                    contentAlignment = Alignment.Center,
                ) { InlineSpinner(ThemeColor.textSecondary) }
            }
        }
    }
}

/**
 * Its own plate, below the colophon: one of these two rows is reversible and the other is not, and
 * the layout should never let a thumb confuse them. This is where the system's own Settings puts it
 * too.
 */
@Composable
internal fun DeleteSection(
    signingOut: Boolean,
    deleting: Boolean,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
) {
    GroupedList(modifier = modifier) {
        ProfileRow(
            title = Copy.Action.deleteAccount,
            symbol = PreviouslyIcons.Delete,
            symbolTint = ThemeColor.destructive,
            titleTint = ThemeColor.destructive,
            subtitle = Copy.Account.deleteSubtitle,
            separator = false,
            enabled = !signingOut && !deleting,
            // A screen reader carries a severity that colour alone no longer does.
            hint = Copy.Profile.HINT_DELETE,
            onClick = onDelete,
        ) {
            if (deleting) {
                Box(
                    Modifier.size(TrailingColumnHeight),
                    contentAlignment = Alignment.Center,
                ) { InlineSpinner(ThemeColor.destructive) }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Confirmations
// ─────────────────────────────────────────────────────────────────────────────

/**
 * The app's confirmation dialog.
 *
 * iOS insists on `.alert` over `confirmationDialog` because an alert *"guarantees the three things
 * this moment needs: a dimming scrim, an explicit Cancel, and the destructive verb rendered as
 * destructive."* Android's dialog is that presentation, and `AlertDialog` is one of the handful of
 * material3 components this app is allowed — bridged so it cannot arrive wearing
 * `lightColorScheme()`, with every colour passed explicitly and both buttons drawn by the app.
 *
 * @param confirmLabel `null` makes this an acknowledgement — one "Done", no destructive verb.
 */
@Composable
internal fun ProfileAlert(
    title: String,
    message: String,
    onDismiss: () -> Unit,
    confirmLabel: String? = null,
    onConfirm: (() -> Unit)? = null,
    destructive: Boolean = true,
) {
    PreviouslyMaterialBridge {
        AlertDialog(
            onDismissRequest = onDismiss,
            confirmButton = {
                if (confirmLabel != null && onConfirm != null) {
                    TertiaryButton(
                        label = confirmLabel,
                        onClick = onConfirm,
                        destructive = destructive,
                    )
                } else {
                    TertiaryButton(label = Copy.Action.done, onClick = onDismiss)
                }
            },
            dismissButton = {
                if (confirmLabel != null && onConfirm != null) {
                    TertiaryButton(label = Copy.Confirm.cancel, onClick = onDismiss)
                }
            },
            title = {
                BasicText(
                    text = title,
                    style = ThemeType.showTitleM.copy(color = ThemeColor.textPrimary),
                )
            },
            text = {
                BasicText(
                    text = message,
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

// ─────────────────────────────────────────────────────────────────────────────
// Export
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Two formats, each with a real support line, on a pushed screen the row's chevron already
 * promised. The menu this replaces anchored itself over the row that raised it and wrapped both of
 * its items to two lines.
 *
 * Tapping a row opens the system document picker; the bytes are written to whatever destination the
 * user chooses. See note 1 in the file header for why this is not a share sheet.
 *
 * @param onFailure a local write that failed. Silence on success is deliberate: the picker
 *   returning IS the receipt, exactly as the iOS share sheet is.
 */
@Composable
internal fun ExportRows(
    library: List<Franchise>,
    onFailure: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    // The bytes are produced when the export is STARTED, on the library as it is now, so a reload
    // landing while the picker is open cannot change what the file says.
    var pending by remember { mutableStateOf<ByteArray?>(null) }

    val json = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.CreateDocument(EXPORT_JSON_MIME),
    ) { uri ->
        val bytes = pending
        pending = null
        if (uri != null && bytes != null) {
            scope.launch { if (!writeExport(context, uri, bytes)) onFailure() }
        }
    }
    val csv = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.CreateDocument(EXPORT_CSV_MIME),
    ) { uri ->
        val bytes = pending
        pending = null
        if (uri != null && bytes != null) {
            scope.launch { if (!writeExport(context, uri, bytes)) onFailure() }
        }
    }

    GroupedList(modifier = modifier) {
        ExportRow(
            title = Copy.Profile.EXPORT_JSON,
            subtitle = Copy.Profile.EXPORT_JSON_SUB,
            symbol = PreviouslyIcons.DataObject,
        ) {
            pending = LibraryExport.json(library)
            runCatching { json.launch(Copy.Profile.EXPORT_FILE_JSON) }
                .onFailure { Log.w(PROFILE_LOG_TAG, "No document picker on this device", it) }
        }
        ExportRow(
            title = Copy.Profile.EXPORT_CSV,
            subtitle = Copy.Profile.EXPORT_CSV_SUB,
            symbol = PreviouslyIcons.Table,
            separator = false,
        ) {
            pending = LibraryExport.csv(library)
            runCatching { csv.launch(Copy.Profile.EXPORT_FILE_CSV) }
                .onFailure { Log.w(PROFILE_LOG_TAG, "No document picker on this device", it) }
        }
    }
}

@Composable
private fun ColumnScope.ExportRow(
    title: String,
    subtitle: String,
    symbol: MaterialSymbol,
    separator: Boolean = true,
    onClick: () -> Unit,
) {
    ProfileRow(
        title = title,
        symbol = symbol,
        subtitle = subtitle,
        separator = separator,
        // Label and hint, as iOS sets them: "Export as JSON" is what the row does, and the support
        // line is what it will produce.
        label = Copy.Profile.exportAs(title),
        hint = subtitle,
        onClick = onClick,
    ) {
        TrailingGlyph(PreviouslyIcons.Share, ThemeColor.textTertiary)
    }
}

private const val EXPORT_JSON_MIME = "application/json"
private const val EXPORT_CSV_MIME = "text/csv"

/** Writes off the main thread. `false` when the destination refused the bytes. */
private suspend fun writeExport(context: Context, uri: Uri, bytes: ByteArray): Boolean =
    withContext(Dispatchers.IO) {
        try {
            context.contentResolver.openOutputStream(uri)?.use { it.write(bytes) } ?: return@withContext false
            true
        } catch (e: IOException) {
            Log.w(PROFILE_LOG_TAG, "Export could not be written", e)
            false
        } catch (e: SecurityException) {
            Log.w(PROFILE_LOG_TAG, "Export destination refused the write", e)
            false
        }
    }

/**
 * The user's library as a file. **Titles, statuses and progress only — never account identifiers.**
 */
internal object LibraryExport {

    /**
     * `prettyPrinted` + property order.
     *
     * iOS encodes with `.sortedKeys` so two exports of the same library are byte-identical and
     * diffable. kotlinx has no sorted-keys flag, so the payload types below declare their fields in
     * alphabetical order instead — same guarantee, expressed in the type.
     */
    private val exportJson = Json {
        prettyPrint = true
        encodeDefaults = true
    }

    @Serializable
    private data class PartRow(
        val kind: String,
        val label: String,
        val mediaId: Int,
        val progress: Int,
        val totalEpisodes: Int,
    )

    @Serializable
    private data class TitleRow(
        val id: String,
        val parts: List<PartRow>,
        val source: String,
        val status: String,
        val title: String,
    )

    fun json(library: List<Franchise>): ByteArray {
        val rows = library.map { f ->
            TitleRow(
                id = f.id,
                parts = f.parts.map { it.row() },
                source = f.source.wire,
                status = f.effectiveStatus.wire,
                title = f.title,
            )
        }
        return exportJson
            .encodeToString(ListSerializer(TitleRow.serializer()), rows)
            .toByteArray()
    }

    private fun FranchisePart.row() = PartRow(
        kind = kind.wire,
        label = canonicalLabel,
        mediaId = mediaId,
        progress = progress,
        totalEpisodes = totalEpisodes,
    )

    /** One row per PART. `"` is doubled inside a quoted field; no trailing newline. */
    fun csv(library: List<Franchise>): ByteArray {
        val lines = ArrayList<String>(1 + library.sumOf { it.parts.size })
        lines += "title,source,status,part,kind,progress,total_episodes"
        for (f in library) {
            for (p in f.parts) {
                lines += listOf(
                    quote(f.title),
                    f.source.wire,
                    f.effectiveStatus.wire,
                    quote(p.canonicalLabel),
                    p.kind.wire,
                    p.progress.toString(),
                    p.totalEpisodes.toString(),
                ).joinToString(",")
            }
        }
        return lines.joinToString("\n").toByteArray()
    }

    private fun quote(s: String): String = "\"" + s.replace("\"", "\"\"") + "\""
}

// ─────────────────────────────────────────────────────────────────────────────
// Account deletion
// ─────────────────────────────────────────────────────────────────────────────

/**
 * `DELETE /me`, deliberately **outside** the shared API client.
 *
 * *"That client is built for reads and for writes the app can replay: it retries transport failures
 * and silently refreshes a 401. Both behaviours are wrong here. A request the app is not certain
 * reached the server must be REPORTED, not quietly repeated, and a session that has expired must be
 * re-authenticated by the user before their account is destroyed — not renewed behind a
 * confirmation they gave a minute ago. One attempt, one answer, and the answer is shown to the user
 * either way."*
 *
 * It lives in the profile package rather than in `data/` for the same reason the Swift keeps it in
 * `Features/Profile/`: it is one route with one caller, and the transport must not grow a way to
 * retry it.
 */
internal object AccountDeletion {

    /**
     * Why the deletion did not happen, in the words the alert prints. **Never a status code:** the
     * user is being told whether their account still exists, and "500" does not answer that.
     */
    enum class Failure(val message: String) {
        /** There is no credential to send. The account was not touched. */
        NotSignedIn(Copy.Account.deleteFailedNotSignedIn),

        /** The server answered, and the answer was not "deleted". */
        Refused(Copy.Account.deleteFailedRefused),

        /** The request never got an answer. The account may or may not still exist. */
        Unreachable(Copy.Account.deleteFailedUnreachable),
    }

    /** One attempt, one answer: no interceptors, no auth refresh, no connection retry. */
    private val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .callTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .connectTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .readTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .retryOnConnectionFailure(false)
            .build()
    }

    private const val TIMEOUT_SECONDS = 20L

    @Serializable
    private data class DeletedResponse(val deleted: Boolean = false)

    /**
     * Sends the deletion. Returns `null` when the server confirmed the erasure, and the [Failure]
     * to report otherwise.
     */
    suspend fun deleteAccount(token: String?): Failure? = withContext(Dispatchers.IO) {
        val bearer = token?.takeIf { it.isNotEmpty() } ?: return@withContext Failure.NotSignedIn

        val request = Request.Builder()
            .url(AppConfig.apiBaseUrl.newBuilder().addPathSegment("me").build())
            .header("Authorization", "Bearer $bearer")
            .header("Accept", "application/json")
            // No body at all: the route rejects a body it does not recognise, and there is nothing
            // an erasure needs to say beyond who is asking.
            .delete()
            .build()

        val response = try {
            client.newCall(request).execute()
        } catch (e: IOException) {
            return@withContext Failure.Unreachable
        }

        response.use {
            when (it.code) {
                200 -> {
                    // The route answers `{ "deleted": true }`. A 200 carrying anything else is a
                    // proxy or a captive portal answering for the server, and must not be read as a
                    // deletion.
                    val body = runCatching { it.body?.string().orEmpty() }.getOrDefault("")
                    val ok = runCatching {
                        AniTrackJson.decodeFromString(DeletedResponse.serializer(), body).deleted
                    }.getOrDefault(false)
                    if (ok) null else Failure.Refused
                }

                204 -> null

                // Deliberately unlike the shared client, where a 403 is never a sign-out: on this
                // one route the safest report is "we deleted nothing and you may need to sign in
                // again."
                401, 403 -> Failure.NotSignedIn

                else -> Failure.Refused
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// The haptics preference
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Persistence for `FeedbackCoordinator.enabled`, under **the same key iOS uses**
 * (`previously.haptics`) so the two platforms name the same user choice.
 *
 * `SharedPreferences`, not DataStore, and for the same reason `SyncCenter` gives: the read has to be
 * synchronous, because the coordinator is consulted by the first haptic the app fires and a value
 * arriving one collection later would spend a buzz the user had switched off.
 */
object HapticsPreference {

    private const val PREFS_NAME = "previously.settings"

    /** Mirror the stored preference into [FeedbackCoordinator]. Call once, from the app root. */
    fun install(context: Context) {
        FeedbackCoordinator.enabled = prefs(context)
            .getBoolean(FeedbackCoordinator.PREFERENCE_KEY, true)
    }

    /**
     * Record the user's choice and apply it immediately.
     *
     * Turning haptics **on** demonstrates one; turning them off is silent — there is nothing to
     * demonstrate, and buzzing to confirm "no more buzzing" is the joke that writes itself.
     */
    fun set(context: Context, on: Boolean) {
        prefs(context).edit().putBoolean(FeedbackCoordinator.PREFERENCE_KEY, on).apply()
        FeedbackCoordinator.enabled = on
        if (on) FeedbackCoordinator.fire(FeedbackToken.SELECTION)
    }

    fun current(context: Context): Boolean =
        prefs(context).getBoolean(FeedbackCoordinator.PREFERENCE_KEY, true)

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}


// The `-openProfile 1` launch argument is NOT read here. The shell already parses it
// (`ShellIntents.EXTRA_OPEN_PROFILE` → `DebugLaunch.openProfile`) and Today raises the sheet
// through its own `onOpenProfile`, so a second reader would consume the same extra twice and the
// two could disagree about whether it had been handled.
