package com.anitrack.app.ui.profile

import android.content.Context
import android.graphics.Color as AndroidColor
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.anitrack.app.AppModel
import com.anitrack.app.data.FailedChange
import com.anitrack.app.data.SyncCenter
import com.anitrack.app.data.auth.AccountIdentity
import com.anitrack.app.data.auth.AuthManager
import com.anitrack.app.design.ArtGround
import com.anitrack.app.design.FeedbackCoordinator
import com.anitrack.app.design.FeedbackToken
import com.anitrack.app.design.MaterialSymbol
import com.anitrack.app.design.PosterSize
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.ShadowToken
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.brand.AccountDisc
import com.anitrack.app.design.brand.BrandWord
import com.anitrack.app.design.brand.PreviouslyMark
import com.anitrack.app.design.shadowToken
import com.anitrack.app.ui.AutoSizeText
import com.anitrack.app.ui.card.ShelfCard
import com.anitrack.app.ui.chrome.ChromeEdge
import com.anitrack.app.ui.chrome.ScrollEdgeChromeBox
import com.anitrack.app.ui.control.InlineLinkButton
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.control.SecondaryButton
import com.anitrack.app.ui.control.SymbolIcon
import com.anitrack.app.ui.control.TertiaryButton
import com.anitrack.app.ui.image.rememberArtTint
import com.anitrack.app.ui.isAccessibilityTextSize
import com.anitrack.app.ui.list.GroupedList
import com.anitrack.app.ui.scroll.ScrollOffset
import com.anitrack.app.ui.scroll.past
import com.anitrack.app.ui.scroll.rememberScrollOffset
import com.anitrack.app.ui.scroll.track
import com.anitrack.app.ui.section.SectionHeaderRow
import com.anitrack.app.ui.state.ToastHost
import com.anitrack.model.AniTrackJson
import com.anitrack.model.Formatting
import com.anitrack.model.Franchise
import com.anitrack.model.ShelfState
import com.anitrack.model.TemporalCopy
import com.anitrack.model.WatchStatus
import com.anitrack.model.copy.Copy
import com.anitrack.model.effectiveStatus
import com.anitrack.model.nextAiring
import com.anitrack.model.portraitArt
import com.anitrack.model.resumePart
import kotlin.math.max
import kotlinx.coroutines.launch
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import com.anitrack.model.behind
import com.anitrack.model.releasingPart
import com.anitrack.model.timeAnchor
import com.anitrack.model.lastAired
import com.anitrack.model.ShelfWindows

// =====================================================================================
// THE ACCOUNT SHEET — the port of `ios/Sources/Features/Profile/ProfileView.swift`.
// Spec: docs/android-port/spec/profile-shell.md §6.
//
// **Profile is an account sheet in the App Store's reading order, not a dashboard.** The header
// comment on the Swift records the whole decision and it is the law here too:
//
//   "Reading order: who, what they are watching, then the controls — the App Store account sheet's
//    order. A plate of three display numerals sat between the name and the shelf and read as a
//    dashboard; the counts are one quiet line under the name now."
//
// So: identity row → Watching shelf → Settings → the sync FOOTNOTE → Account → Sign out → colophon
// → Delete. The sync PLATE exists only while a change has failed; otherwise the state is one line
// under Settings, because "a 'Sync' plate with its own control beside a check mark was the most
// SaaS object on the screen for a fact that needs no action while it is true."
//
// Delete sits BELOW the colophon: "one of these is routine and reversible, the other is not, and
// the layout should never let a thumb confuse them."
//
// -------------------------------------------------------------------------------------
// WHAT CHANGED IN THE PORT, AND WHY
//
// 1. **The screen is a composable, not a presentation.** iOS is a `.sheet` with its own
//    `NavigationStack`; the Android host presents this in a near-full-height sheet and passes
//    [onDismiss]. The bar and the one push (Export) are drawn here, because this app's bars are
//    app-drawn boxes — M3's `TopAppBar` is banned and there is no toolbar slot to reach into.
//
// 2. **The wash travels with the CONTENT, and the offset is read at draw time.** iOS offsets the
//    field by `-max(0, scrollOffset)` for a recorded reason: painted fixed to the screen it stayed
//    where it was while the plates slid through it, "so the SETTINGS plate was warm at the top of
//    the scroll and the ACCOUNT plate neutral grey further down — one component, two hues, decided
//    by scroll position." Here the offset is a `ScrollOffset` read inside `graphicsLayer`, never in
//    a body: the scroll offset is never screen state.
//
// 3. **The poster fan is not ported.** It is fully written and never rendered on iOS
//    ("Dead code — do not port"); `fanCovers` survives only as the wash's colour source and the
//    snapshot's payload, and that is exactly what is here.
//
// 4. **No pull-to-refresh.** Deliberately removed on iOS "from a sheet where it fights interactive
//    dismiss", and a sheet on Android is dismissed by the same downward drag.
// =====================================================================================

/**
 * The account sheet.
 *
 * @param onDismiss closes the sheet. The identity row's callbacks dismiss FIRST and then navigate,
 *   so the user lands on the screen they asked for rather than behind a sheet.
 * @param onOpenLibrary opens All titles filtered to a status. `null` in a host that has not wired
 *   it — the shelf header then draws no chevron and states no action, so the section stays a fact
 *   rather than pretending to be a control.
 * @param onOpenDetail opens a show. `null` behaves the same way.
 * @param topInset the status-bar band the bar sits under. The default is the window's own inset,
 *   which is right for a full-height presentation; a host that has already inset its sheet passes
 *   `0.dp`.
 */
@Composable
fun ProfileScreen(
    appModel: AppModel,
    auth: AuthManager,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    onOpenLibrary: ((WatchStatus) -> Unit)? = null,
    onOpenDetail: ((String) -> Unit)? = null,
    topInset: Dp = ThemeMetrics.topSafeInset(),
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    // A plain collection, not `collectAsStateWithLifecycle`: that lives in
    // `lifecycle-runtime-compose`, an artifact this module does not carry, and a sheet is composed
    // only while it is on screen — so the collection is already scoped to the surface's lifetime.
    val identity by auth.identityFlow.collectAsState()

    // Profile lists every failed change with its reason, Retry and Discard, so the global banner
    // would be a duplicate of the screen the user is already reading.
    DisposableEffect(Unit) {
        SyncCenter.profileIsOpen = true
        onDispose { SyncCenter.profileIsOpen = false }
    }

    var exporting by remember { mutableStateOf(false) }
    var hapticsOn by remember { mutableStateOf(HapticsPreference.current(context)) }
    var confirmSignOut by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var discardTarget by remember { mutableStateOf<String?>(null) }
    var signingOut by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    /** The one failure this screen has to report itself: the account deletion that did not happen. */
    var deleteFailure by remember { mutableStateOf<String?>(null) }
    var signOutFailed by remember { mutableStateOf(false) }

    // What the account looked like the last time the library actually loaded. The screen renders
    // from this when the network is gone, instead of deleting the summary.
    var snapshot by remember { mutableStateOf(ProfileSnapshot.load(context)) }

    val library = appModel.library
    val liveCovers = remember(library) { liveCovers(appModel) }

    LaunchedEffect(library.size) {
        val fresh = ProfileSnapshot.capture(library, liveCovers)
        if (fresh != null) {
            fresh.save(context)
            snapshot = fresh
        } else if (SyncCenter.lastSyncedAt != null && SyncCenter.isOnline) {
            // A library that LOADED and is empty is a real empty account, not a failure — and the
            // memory has to go with it, or the last show the user removed keeps posing as their
            // artwork. Only a successful, online load may clear it.
            ProfileSnapshot.clear(context)
            snapshot = ProfileSnapshot()
        }
    }

    Box(modifier.fillMaxSize().background(ThemeColor.canvas)) {
        if (exporting) {
            BackHandler { exporting = false }
            ExportScreen(
                library = library,
                topInset = topInset,
                onBack = { exporting = false },
                onFailure = { appModel.showError(Copy.Notice.serverError) },
            )
        } else {
            ProfileRoot(
                appModel = appModel,
                identity = identity,
                snapshot = snapshot,
                liveCovers = liveCovers,
                topInset = topInset,
                hapticsOn = hapticsOn,
                signingOut = signingOut,
                deleting = deleting,
                onHapticsChange = { on ->
                    hapticsOn = on
                    HapticsPreference.set(context, on)
                },
                onExport = { exporting = true },
                onDone = onDismiss,
                onOpenLibrary = onOpenLibrary?.let { open ->
                    { status: WatchStatus -> onDismiss(); open(status) }
                },
                onOpenDetail = onOpenDetail?.let { open ->
                    { id: String -> onDismiss(); open(id) }
                },
                onRetry = { SyncCenter.retry(it) },
                onRetryAll = { SyncCenter.retryAll() },
                onDiscard = { discardTarget = it },
                onSignOut = { confirmSignOut = true },
                onDelete = { confirmDelete = true },
            )
        }

        // The sheet carries its own toast layer: it presents above the shell's stack, so a receipt
        // raised from here — or one still standing from before it opened — must be visible on it.
        // The sync BANNER is suppressed (count 0) for the reason `profileIsOpen` exists.
        ToastHost(
            syncFailureCount = 0,
            onRetrySync = { SyncCenter.retryAll() },
            onDiscardSync = { SyncCenter.discardAll() },
            laneItem = appModel.laneItem,
            onUndo = { appModel.undoTapped(it) },
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(horizontal = ToastGutter)
                .padding(bottom = ThemeMetrics.toastClearance),
        )
    }

    // ALERTS, not a bottom sheet of choices. iOS's reason ports exactly: this moment needs a
    // dimming scrim, an explicit Cancel, and the destructive verb rendered as destructive.
    if (confirmSignOut) {
        ProfileAlert(
            title = Copy.Account.signOutTitle,
            message = Copy.Profile.signOutMessage(SyncCenter.failedChanges.size),
            confirmLabel = Copy.Action.signOut,
            onDismiss = { confirmSignOut = false },
            onConfirm = {
                confirmSignOut = false
                FeedbackCoordinator.fire(FeedbackToken.DESTRUCTIVE)
                signingOut = true
                scope.launch {
                    val signedOut = auth.signOut()
                    signingOut = false
                    // Deletion had a failure alert; sign-out had none. Same moment, same answer.
                    if (!signedOut) signOutFailed = true
                }
            },
        )
    }

    if (confirmDelete) {
        ProfileAlert(
            title = Copy.Account.deleteTitle,
            message = Copy.Profile.deleteMessage(library.size),
            confirmLabel = Copy.Account.deleteConfirm,
            onDismiss = { confirmDelete = false },
            onConfirm = {
                confirmDelete = false
                FeedbackCoordinator.fire(FeedbackToken.DESTRUCTIVE)
                deleting = true
                scope.launch {
                    val failure = AccountDeletion.deleteAccount(auth.currentToken())
                    deleting = false
                    if (failure == null) {
                        // The account is gone; the session must go with it, the snapshot too, and
                        // the sheet with both. A deleted account may not leave its counts on the
                        // device.
                        ProfileSnapshot.clear(context)
                        snapshot = ProfileSnapshot()
                        auth.signOut()
                        onDismiss()
                    } else {
                        deleteFailure = failure.message
                    }
                }
            },
        )
    }

    deleteFailure?.let { message ->
        ProfileAlert(
            title = Copy.Account.deleteFailedTitle,
            message = message,
            onDismiss = { deleteFailure = null },
        )
    }

    if (signOutFailed) {
        ProfileAlert(
            title = Copy.Account.signOutFailedTitle,
            message = Copy.Account.signOutFailedMessage,
            onDismiss = { signOutFailed = false },
        )
    }

    discardTarget?.let { id ->
        val change = SyncCenter.failedChanges.firstOrNull { it.id == id }
        ProfileAlert(
            title = Copy.Confirm.discardChangeTitle,
            // Names its object: "Discard" alone beside a show name is genuinely ambiguous.
            message = change?.let { Copy.Profile.discardMessage(it.title, it.command) }
                ?: Copy.Confirm.discardChangeMessage,
            confirmLabel = Copy.Confirm.discardChangeConfirm,
            onDismiss = { discardTarget = null },
            onConfirm = {
                discardTarget = null
                FeedbackCoordinator.fire(FeedbackToken.DESTRUCTIVE)
                SyncCenter.discard(id)
            },
        )
    }
}

/** The bottom bar's own horizontal margin, which the toast shares so the two do not disagree. */
private val ToastGutter = 22.dp

// ─────────────────────────────────────────────────────────────────────────────
// The sheet's root
// ─────────────────────────────────────────────────────────────────────────────

@Composable
private fun ProfileRoot(
    appModel: AppModel,
    identity: AccountIdentity,
    snapshot: ProfileSnapshot,
    liveCovers: List<String>,
    topInset: Dp,
    hapticsOn: Boolean,
    signingOut: Boolean,
    deleting: Boolean,
    onHapticsChange: (Boolean) -> Unit,
    onExport: () -> Unit,
    onDone: () -> Unit,
    onOpenLibrary: ((WatchStatus) -> Unit)?,
    onOpenDetail: ((String) -> Unit)?,
    onRetry: (String) -> Unit,
    onRetryAll: () -> Unit,
    onDiscard: (String) -> Unit,
    onSignOut: () -> Unit,
    onDelete: () -> Unit,
) {
    val density = LocalDensity.current
    val scrollState = rememberScrollState()
    val scroll = rememberScrollOffset()
    scroll.track(scrollState)

    // Content passes under the BAR, not under the clock: the veil hardens once a bar-edge ramp of
    // content has travelled under it.
    val raised by scroll.past(ThemeMetrics.topChromeRamp)

    val barBottom = topInset + ThemeMetrics.inlineBarHeight

    // The measured screen-space top of the Watching shelf, taken at rest only. The wash's ramp OUT
    // lands exactly on it, "so no plate on this screen ever contains the end of a gradient, which
    // is what produced the visible horizontal tone step inside the stats card."
    var shelfTop by remember { mutableStateOf(0.dp) }
    val fadeEnd = if (shelfTop > WashFallbackFloor) shelfTop else WashFadeFallback

    val covers = if (liveCovers.isEmpty()) snapshot.covers else liveCovers
    // **The CENTRE card**, not the first title in the library: the wash is sampled from the poster
    // the eye is actually resting on.
    val washArtwork = covers.getOrNull(covers.size / 2)
    val washTint = rememberArtTint(washArtwork)

    val failures = SyncCenter.failedChanges
    val sync = rememberSyncState(appModel = appModel, snapshotEmpty = snapshot.isEmpty)

    ScrollEdgeChromeBox(
        modifier = Modifier.fillMaxSize(),
        edges = ChromeEdge.Top,
        softTop = true,
        topRaised = raised,
        topHold = barBottom,
    ) {
        ProfileWash(
            tint = washTint,
            fadeEnd = fadeEnd,
            barBottom = barBottom,
            scroll = scroll,
            modifier = Modifier.align(Alignment.TopCenter),
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(scrollState),
        ) {
            // The content begins at the bar's bottom edge; the bar is chrome drawn over it.
            Spacer(Modifier.height(barBottom + ThemeSpace.x4))

            IdentityRow(
                identity = identity,
                summary = librarySummary(appModel, snapshot),
                modifier = Modifier.padding(horizontal = ThemeMetrics.gutter),
            )

            WatchingShelf(
                appModel = appModel,
                onOpenLibrary = onOpenLibrary,
                onOpenDetail = onOpenDetail,
                modifier = Modifier
                    .padding(top = ThemeSpace.x6)
                    // Measured at rest only: the value is the shelf's position on SCREEN, and
                    // during a scroll that is not where it sits in the content.
                    .onGloballyPositioned { coords ->
                        if (scroll.y <= 1f) {
                            val y = with(density) { coords.positionInRoot().y.toDp() }
                            if (y != shelfTop) shelfTop = y
                        }
                    },
            )

            // 3 and 5 are mutually exclusive: the sync PLATE exists only while something failed.
            if (failures.isNotEmpty()) {
                SyncSection(
                    state = sync,
                    failures = failures,
                    onRetry = onRetry,
                    onRetryAll = onRetryAll,
                    onDiscard = onDiscard,
                    modifier = Modifier
                        .padding(top = ThemeMetrics.sectionGap)
                        .padding(horizontal = ThemeMetrics.gutter),
                )
            }

            SettingsSection(
                hapticsOn = hapticsOn,
                onHapticsChange = onHapticsChange,
                onExport = onExport,
                modifier = Modifier
                    .padding(top = ThemeMetrics.sectionGap)
                    .padding(horizontal = ThemeMetrics.gutter),
            )

            if (failures.isEmpty()) {
                SyncFootnote(
                    state = sync,
                    modifier = Modifier
                        .padding(top = ThemeSpace.x2)
                        .padding(horizontal = ThemeMetrics.gutter),
                )
            }

            AccountSection(
                modifier = Modifier
                    .padding(top = ThemeMetrics.sectionGap)
                    .padding(horizontal = ThemeMetrics.gutter),
            )

            SignOutSection(
                signingOut = signingOut,
                deleting = deleting,
                onSignOut = onSignOut,
                modifier = Modifier
                    .padding(top = ThemeMetrics.sectionGap)
                    .padding(horizontal = ThemeMetrics.gutter),
            )

            Colophon(
                modifier = Modifier
                    .padding(top = ThemeSpace.x10)
                    .padding(horizontal = ThemeMetrics.gutter),
            )

            DeleteSection(
                signingOut = signingOut,
                deleting = deleting,
                onDelete = onDelete,
                modifier = Modifier
                    .padding(top = ThemeSpace.x8)
                    .padding(horizontal = ThemeMetrics.gutter),
            )

            // "The sheet had no bottom inset, so the last line of the colophon ended flush against
            // the bezel." 34 dp INSIDE the gesture strip, as iOS adds 34 inside the safe area.
            Spacer(Modifier.height(SheetBottomClearance + bottomSafeInset()))
        }

        ProfileBar(
            title = Copy.Profile.PROFILE,
            topInset = topInset,
            trailing = { TertiaryButton(label = Copy.Action.done, onClick = onDone) },
            modifier = Modifier.align(Alignment.TopCenter),
        )
    }
}

/** iOS `.safeAreaPadding(.bottom, 34)`. */
private val SheetBottomClearance = 34.dp

/** Below this the measurement has not happened yet; iOS's first-frame fallback. */
private val WashFallbackFloor = 120.dp
private val WashFadeFallback = 260.dp

@Composable
private fun bottomSafeInset(): Dp =
    WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()

// ─────────────────────────────────────────────────────────────────────────────
// The bar
// ─────────────────────────────────────────────────────────────────────────────

/**
 * The sheet's inline bar: a centred title with one action on the trailing edge.
 *
 * Drawn rather than borrowed — M3's `TopAppBar` is banned, and every bar in this app is an app-drawn
 * box over the chrome band. The title is `bodyEmphasis`, the app's one recipe for a bar's confirm
 * word; the action is a bare word in `interactive` ink, because amber is not an action colour.
 *
 * @param leading an optional back control. The root has none — a sheet is dismissed by its own
 *   action and by the system gesture.
 */
@Composable
private fun ProfileBar(
    title: String,
    topInset: Dp,
    modifier: Modifier = Modifier,
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(top = topInset)
            .height(ThemeMetrics.inlineBarHeight)
            // A 44-dp target sits 12 dp from the edge, which puts its INK on the screen's own
            // gutter — the same place the content below it starts.
            .padding(horizontal = ThemeSpace.x3),
    ) {
        if (leading != null) {
            Box(Modifier.align(Alignment.CenterStart)) { leading() }
        }
        BasicText(
            text = title,
            style = ThemeType.bodyEmphasis.copy(color = ThemeColor.textPrimary),
            maxLines = 1,
            modifier = Modifier
                .align(Alignment.Center)
                // The bar states the screen, so it is the screen's heading.
                .semantics { heading() },
        )
        if (trailing != null) {
            Box(Modifier.align(Alignment.CenterEnd)) { trailing() }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Identity
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Who: the disc, the name, how this device is signed in, and the library in one line — a leading
 * row, the way the App Store's and Settings' account rows are built. The centred 72-dp disc under a
 * display-size name was a template's opening, not an account's.
 *
 * The whole row is ONE screen-reader element: a name, a provenance and a counts line are one fact
 * about one account, and three stops for them is three stops too many.
 */
@Composable
private fun IdentityRow(
    identity: AccountIdentity,
    summary: String?,
    modifier: Modifier = Modifier,
) {
    val name = identity.displayName
    val provenance = identity.provenanceLabel
    val spoken = Copy.Profile.signedInAs(name)
    val value = listOfNotNull(provenance, summary).joinToString(", ")

    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = ThemeSpace.x1)
            .semantics(mergeDescendants = true) {
                contentDescription = spoken
                stateDescription = value
                heading()
            },
        horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x4),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AccountDisc(monogram = identity.monogram, diameter = AccountDiscDiameter)
        Column(verticalArrangement = Arrangement.spacedBy(ThemeSpace.x0_5)) {
            AutoSizeText(
                text = name,
                style = ThemeType.showTitleL.copy(color = ThemeColor.textPrimary),
                minScale = AccountNameMinScale,
                maxLines = 1,
            )
            if (provenance != null) {
                BasicText(
                    text = provenance,
                    style = ThemeType.metadata.copy(color = ThemeColor.textSecondary),
                    maxLines = 1,
                )
            }
            if (summary != null) {
                BasicText(
                    text = summary,
                    style = ThemeType.metadata.copy(color = ThemeColor.textTertiary),
                    maxLines = 2,
                    modifier = Modifier.padding(top = ThemeSpace.x0_5),
                )
            }
        }
    }
}

private val AccountDiscDiameter = 56.dp
private const val AccountNameMinScale = 0.7f


// ─────────────────────────────────────────────────────────────────────────────
// The one quiet counts line
// ─────────────────────────────────────────────────────────────────────────────

/**
 * "635 episodes · 5 watching · 13 watched" — the plate's three numerals as one fact.
 *
 * Note the deliberate **three-valued** logic underneath: `null` is *unknown* and is not zero. "A
 * library that loaded successfully and is empty is a real zero. One that has never arrived is
 * unknown, and unknown is not zero."
 */
private fun librarySummary(appModel: AppModel, snapshot: ProfileSnapshot): String? {
    val parts = ArrayList<String>(4)
    episodesWatched(appModel)?.let { parts += Copy.episodes(it) }
    for (status in listOf(WatchStatus.WATCHING, WatchStatus.COMPLETED)) {
        val n = statusCount(appModel, snapshot, status) ?: continue
        if (n > 0) parts += statusPhrase(n, status)
    }
    // Three numerals, one line (i1-F11): the minor statuses wrapped "6 planned" onto a line of its own.
    return if (parts.isEmpty()) null else parts.joinToString(MiddotSeparator)
}

/**
 * Statuses with no line of their own.
 *
 * "Paused" appeared in "Black Clover · Moved to Paused" and nowhere else in the app — a user who
 * paused a show watched Watching drop by one and saw nothing appear anywhere.
 */
private fun minorStatusLine(appModel: AppModel, snapshot: ProfileSnapshot): String? {
    val parts = listOf(WatchStatus.PLANNED, WatchStatus.PAUSED, WatchStatus.DROPPED)
        .mapNotNull { status ->
            val n = statusCount(appModel, snapshot, status) ?: return@mapNotNull null
            if (n > 0) statusPhrase(n, status) else null
        }
    return if (parts.isEmpty()) null else parts.joinToString(MiddotSeparator)
}

/**
 * "5 watching" — a REGULAR space, unlike `Copy.plural`'s non-breaking one: the episodes count is a
 * fact inside a sentence and may not break, while these are their own clause.
 *
 * `lowercase()` with no argument is root-locale in Kotlin, never the device's — which would turn a
 * Turkish "I" into a dotless one.
 */
private fun statusPhrase(n: Int, status: WatchStatus): String =
    "$n ${Copy.statusLabel(status.wire).lowercase()}"

/** U+00B7 flanked by regular spaces. */
private const val MiddotSeparator = " · "

/** Every episode the account has marked, across every part of every show. */
private fun episodesWatched(appModel: AppModel): Int? {
    if (appModel.library.isNotEmpty()) {
        return appModel.library.sumOf { f -> f.parts.sumOf { it.progress } }
    }
    // Deliberately does NOT consult the snapshot: it stores counts and covers, no episode total.
    return if (SyncCenter.lastSyncedAt == null) null else 0
}

private fun statusCount(appModel: AppModel, snapshot: ProfileSnapshot, status: WatchStatus): Int? {
    // The RAW status, never `effectiveStatus`: this is the shelf the user filed the show under.
    if (appModel.library.isNotEmpty()) return appModel.library.count { it.status == status }
    snapshot.counts[status.wire]?.let { return it }
    return if (SyncCenter.lastSyncedAt == null) null else 0
}

// ─────────────────────────────────────────────────────────────────────────────
// The Watching shelf
// ─────────────────────────────────────────────────────────────────────────────

/**
 * The shows the account is watching, in the order Today ranks them.
 *
 * "This is the one thing a profile in a TV app should show that a settings screen cannot — the
 * screen used to go straight from three numbers to a sync row. Netflix's own profile tab opens on
 * the person's list for the same reason."
 */
@Composable
private fun WatchingShelf(
    appModel: AppModel,
    onOpenLibrary: ((WatchStatus) -> Unit)?,
    onOpenDetail: ((String) -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val shows = remember(appModel.library, appModel.now) { shelfItems(appModel) }
    if (shows.isEmpty()) return

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(ThemeMetrics.labelGap),
    ) {
        SectionHeaderRow(
            text = Copy.Label.watching,
            // The words "See all" are never DRAWN — the title is the button and the chevron carries
            // the affordance; the label is only what a screen reader hears.
            actionLabel = if (onOpenLibrary == null) null else Copy.Action.seeAll,
            onAction = onOpenLibrary?.let { open -> { open(WatchStatus.WATCHING) } },
            modifier = Modifier.padding(horizontal = ThemeMetrics.gutter),
        )
        // The section sits inside the page gutter; the shelf runs edge to edge.
        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(ThemeMetrics.shelfGap),
            contentPadding = PaddingValues(
                start = ThemeMetrics.gutter,
                end = ThemeMetrics.gutter,
                top = ThemeSpace.x1,
                bottom = ThemeSpace.x1,
            ),
        ) {
            items(count = shows.size, key = { shows[it].id }) { i ->
                val f = shows[i]
                val caption = shelfCaption(appModel, f)
                ShelfCard(
                    title = f.title,
                    caption = caption?.first,
                    captionIsLead = caption?.second ?: false,
                    poster = f.portraitArt,
                    slot = PosterSize.TodayShelf,
                    reserveTitleLines = true,
                    hint = if (onOpenDetail == null) null else Copy.Accessibility.opensTheShowHint,
                    onClick = { onOpenDetail?.invoke(f.id) },
                )
            }
        }
    }
}

private const val ShelfLimit = 12

private fun shelfItems(appModel: AppModel): List<Franchise> {
    val live = appModel.watchingShelf
    if (live.size >= 3) return live.take(ShelfLimit)
    val seen = live.mapTo(HashSet()) { it.id }
    val wider = live + appModel.library.filter {
        it.effectiveStatus == WatchStatus.WATCHING && seen.add(it.id)
    }
    return wider.take(ShelfLimit)
}

/**
 * Today's shelf-caption grammar, verbatim: **a forward-looking fact is amber, a state is grey.**
 */
private fun shelfCaption(appModel: AppModel, f: Franchise): Pair<String, Boolean>? =
    when (appModel.shelfState(f)) {
        ShelfState.NEW_EPISODE -> {
            // The count Today's badge carries at the same minute (i1-F11).
            val behind = f.releasingPart?.behind(appModel.now, f.timeAnchor) ?: 0
            // Amber only while the drop is today's fact (i4) — Today's rule verbatim.
            val struck = f.lastAired(appModel.now)?.let { appModel.now - it <= ShelfWindows.NOW_BAR_LIVE } ?: false
            if (behind > 1) Copy.Progress.behind(behind) to struck else Copy.Label.newEpisode to true
        }
        ShelfState.BACKLOG -> f.resumePart?.let { Copy.Progress.episodeNext(it.progress + 1) to false }
        ShelfState.AIRING_WAIT -> {
            val at = f.nextAiring(appModel.now)
            if (at != null) TemporalCopy.airsCompact(at, appModel.now, f.source) to true
            else Copy.Progress.caughtUp to false
        }

        ShelfState.PREMIERE_SOON ->
            TemporalCopy.returns(appModel.nextPremiere(f), appModel.now, f.source) to true

        null -> Copy.Progress.caughtUp to false
    }

/** Covers loaded right now, in the order Today ranks them. Always 1 or 3 — a two-poster fan has no centre. */
private fun liveCovers(appModel: AppModel): List<String> {
    val ranked = appModel.outNow + appModel.keepWatching
    val rankedIds = ranked.mapTo(HashSet()) { it.id }
    val rest = appModel.library.filterNot { it.id in rankedIds }
    val ordered = ranked +
        rest.filter { it.status == WatchStatus.WATCHING } +
        rest.filter { it.status != WatchStatus.WATCHING }
    val covers = ordered.mapNotNull { it.portraitArt }
    return if (covers.size >= 3) covers.take(3) else covers.take(1)
}

// ─────────────────────────────────────────────────────────────────────────────
// Sync
// ─────────────────────────────────────────────────────────────────────────────

/**
 * The sync ladder, resolved in ONE pass so the title, the stamp, the glyph and the tint can never
 * disagree with each other.
 *
 * **Offline is tested before `checking`** — the shipped order tested `checking` first, "so a device
 * whose path monitor had already reported no path still watched 'Checking for changes' spin until
 * the request timed out, and nothing on the screen ever said the user was offline."
 *
 * @property glyph `null` means *a spinner belongs in this column instead* — which is how the row
 *   guarantees it never shows two indicators for one wait.
 */
@Immutable
private data class SyncState(
    val title: String,
    val stamp: String?,
    val glyph: MaterialSymbol?,
    val tint: Color,
)

@Composable
private fun rememberSyncState(appModel: AppModel, snapshotEmpty: Boolean): SyncState {
    val failures = SyncCenter.failedChanges
    val online = SyncCenter.isOnline
    val checking = SyncCenter.checking
    val lastSyncedAt = SyncCenter.lastSyncedAt
    val now = appModel.now

    return remember(failures, online, checking, lastSyncedAt, now, snapshotEmpty) {
        when {
            failures.isNotEmpty() -> SyncState(
                title = Copy.Toast.syncFailed(failures.size),
                stamp = null,
                glyph = PreviouslyIcons.WarningFilled,
                // `warning`, never `destructive`: red beside a red Delete account row makes a
                // recoverable write failure look like data loss.
                tint = ThemeColor.warning,
            )

            !online -> SyncState(
                title = Copy.Empty.offlineCached.title,
                stamp = Copy.Account.offlineSupporting,
                glyph = PreviouslyIcons.WifiOff,
                tint = ThemeColor.textSecondary,
            )

            checking -> SyncState(
                title = Copy.State.checkingForChanges,
                stamp = null,
                // A spinner, not a glyph.
                glyph = null,
                tint = ThemeColor.textSecondary,
            )

            lastSyncedAt == null -> if (snapshotEmpty) {
                SyncState(
                    title = Copy.State.neverSynced,
                    stamp = null,
                    glyph = PreviouslyIcons.Sync,
                    tint = ThemeColor.textTertiary,
                )
            } else {
                // "'Not synced yet' is only true if there is also nothing remembered — with a
                // snapshot's counts on screen it is the screen contradicting itself."
                SyncState(
                    title = Copy.State.couldNotCheck,
                    stamp = Copy.Account.showingSavedCopy,
                    glyph = PreviouslyIcons.WifiTetheringError,
                    tint = ThemeColor.warning,
                )
            }

            else -> SyncState(
                title = Copy.Account.upToDate,
                stamp = Copy.Profile.checked(stampWord(lastSyncedAt, now)),
                // A bare check, in the text ramp. The shipped glyph was a filled `success` disc —
                // the only green in the app, spent decorating a settled state. Colour is not what
                // says "fine"; the sentence is.
                glyph = PreviouslyIcons.Check,
                tint = ThemeColor.textSecondary,
            )
        }
    }
}

/** "Just now" · "12 min ago" · "9:41 AM" · "Aug 19" — the same ladder as `Copy.synced`, without the verb. */
private fun stampWord(at: Long, now: Long): String {
    val elapsed = max(0L, now - at)
    val minutes = (elapsed / Formatting.MINUTE_MS).toInt()
    if (minutes < 1) return Copy.Profile.JUST_NOW
    if (minutes < 60) return Copy.Profile.minutesAgo(minutes)
    if (Formatting.dayDiff(at, now) == 0) return Formatting.fmtTime(at)
    return TemporalCopy.dateWord(at, now, Formatting.TimeAnchor.LOCAL)
}

/**
 * The calm state, as the footnote the system prints under a group ("Last backup: …"): one line, no
 * plate, no button.
 *
 * There is deliberately **no "Sync" control**: offline there is nothing for it to do, and online
 * the fact needs no action while it is true.
 */
@Composable
private fun SyncFootnote(state: SyncState, modifier: Modifier = Modifier) {
    val line = listOfNotNull(state.title, state.stamp).joinToString(MiddotSeparator)
    Row(
        modifier = modifier
            .fillMaxWidth()
            // A second gutter, deliberately: the footnote aligns with the TEXT inside the plate
            // above it, not with the plate's own edge.
            .padding(horizontal = ThemeMetrics.gutter)
            .semantics(mergeDescendants = true) { contentDescription = line },
        horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
        verticalAlignment = Alignment.Top,
    ) {
        val glyph = state.glyph
        // iOS aligns the glyph to the line's FIRST TEXT BASELINE. A vector has no baseline, so it
        // is centred in a box exactly one caption line tall — the same place, and it does not sink
        // when the sentence wraps.
        Box(
            modifier = Modifier.height(with(LocalDensity.current) { ThemeType.caption.lineHeight.toDp() }),
            contentAlignment = Alignment.Center,
        ) {
            if (glyph != null) {
                SymbolIcon(symbol = glyph, tint = state.tint, glyph = FootnoteGlyph)
            } else {
                InlineSpinner(tint = ThemeColor.textTertiary, diameter = FootnoteSpinner)
            }
        }
        BasicText(
            text = line,
            style = ThemeType.caption.copy(color = ThemeColor.textTertiary),
            maxLines = 2,
        )
    }
}

/** iOS draws the footnote glyph at 10 pt semibold; `SymbolIcon` converts to the Material box. */
private val FootnoteGlyph = 10.dp
private val FootnoteSpinner = 12.dp

/**
 * Drawn only while something failed: the summary row is a HEADING, not a button, because the plate
 * below it carries real controls and a row cannot be two things.
 *
 * No glyph on the detail rows: "the section's state is declared ONCE, above them. A stack of
 * identical triangles down one plate is the same defect as a column of grey check discs — the alarm
 * stops being an alarm."
 */
@Composable
private fun SyncSection(
    state: SyncState,
    failures: List<FailedChange>,
    onRetry: (String) -> Unit,
    onRetryAll: () -> Unit,
    onDiscard: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    GroupedList(header = Copy.Profile.SYNC, modifier = modifier) {
        ProfileRowLabel(
            title = state.title,
            symbol = state.glyph,
            symbolTint = state.tint,
            indicateWait = state.glyph == null,
        ) {
            if (SyncCenter.canRetryAny && failures.size > 1) {
                InlineLinkButton(label = Copy.Action.retryAll, onClick = onRetryAll)
            }
        }
        failures.forEachIndexed { i, change ->
            FailureRow(
                change = change,
                isLast = i == failures.lastIndex,
                onRetry = { onRetry(change.id) },
                onDiscard = { onDiscard(change.id) },
            )
        }
    }
}

/**
 * One failed write, with the two things a user can actually do about it.
 *
 * Four slots, in reading order: WHAT (the show, plus when it failed), WHICH CHANGE, WHY, and then —
 * on its own row, clear of the text — WHAT TO DO.
 *
 * The defect this replaced: "the shipped row put 'Black Clover · Moved to Paused' and 'Couldn't
 * reach the server · 8:44 PM' through a text column narrowed by a fixed action lane, so the title
 * wrapped at half the available width, the middot dangled at a line end and the clock was orphaned
 * on line two — while Retry and Discard sat as two ~28-pt words in two competing colours ~20 pt
 * apart, with the destructive one a mis-tap away from the recovery one."
 */
@Composable
private fun FailureRow(
    change: FailedChange,
    isLast: Boolean,
    onRetry: () -> Unit,
    onDiscard: () -> Unit,
) {
    val isAX = isAccessibilityTextSize()
    // No `mergeDescendants`: every child stays individually reachable, because two of them are
    // controls — the port of iOS's `accessibilityElement(children: .contain)`.
    Box(Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(
                start = ProfileRowTextInset,
                end = ThemeMetrics.gutter,
                top = ThemeSpace.x3,
                bottom = ThemeSpace.x3,
            ),
            verticalArrangement = Arrangement.spacedBy(ThemeSpace.x1),
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x3),
                verticalAlignment = Alignment.Top,
            ) {
                BasicText(
                    text = change.title,
                    style = ThemeType.rowTitle.copy(color = ThemeColor.textPrimary),
                    maxLines = 2,
                    modifier = Modifier.weight(1f),
                )
                // Its own slot. Joined to the reason with a middot it was the half that wrapped.
                // Tabular figures, so a clock that ticks does not re-flow the row it sits in; the
                // token is DERIVED from `metadata` rather than declared, because a screen may not
                // add to the type palette.
                BasicText(
                    text = Formatting.fmtTime(change.at),
                    style = FailureClockStyle,
                    maxLines = 1,
                )
            }
            BasicText(
                text = change.command,
                style = ThemeType.rowMeta.copy(color = ThemeColor.textSecondary),
                maxLines = 2,
            )
            BasicText(
                text = failureReason(change),
                style = ThemeType.metadata.copy(color = ThemeColor.textTertiary),
                maxLines = 2,
            )

            // Shape, not only colour, tells these two apart: one is a bordered control and the
            // other is a plain destructive verb. Two identically-shaped capsules differing only in
            // ink is the pattern that makes a destructive action a mis-tap.
            //
            // `SecondaryButton` is the app's bordered neutral control and stands in for iOS's
            // `CompactActionButtonStyle`, which is the same object one type step down; a second
            // bordered capsule would be a second answer to one question.
            if (isAX) {
                // At accessibility sizes they stack rather than shrink.
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = ThemeSpace.x1),
                    horizontalAlignment = Alignment.End,
                    verticalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
                ) {
                    if (change.canRetry()) {
                        SecondaryButton(label = Copy.Action.retry, onClick = onRetry, hugging = true)
                    }
                    DiscardLink(onDiscard)
                }
            } else {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = ThemeSpace.x1),
                    horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x5, Alignment.End),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (change.canRetry()) {
                        SecondaryButton(label = Copy.Action.retry, onClick = onRetry, hugging = true)
                    }
                    DiscardLink(onDiscard)
                }
            }
        }

        if (!isLast) {
            Spacer(
                Modifier
                    .align(Alignment.BottomStart)
                    .fillMaxWidth()
                    // The rule starts where the TITLE starts, exactly as a settings row's does.
                    .padding(start = ProfileRowTextInset)
                    .height(SeparatorHeight)
                    .background(ThemeColor.separatorQuiet),
            )
        }
    }
}

/** 13 sp, tabular. See the call site. */
private val FailureClockStyle =
    ThemeType.metadata.copy(fontFeatureSettings = "tnum", color = ThemeColor.textTertiary)

private val SeparatorHeight = ThemeMetrics.hairline

@Composable
private fun DiscardLink(onDiscard: () -> Unit) {
    InlineLinkButton(
        label = Copy.Confirm.discardChangeConfirm,
        onClick = onDiscard,
        destructive = true,
        // What the tap DOES, where the verb alone does not say it.
        onClickLabel = Copy.Profile.HINT_DISCARD,
    )
}

/**
 * Maps the one engineer-vocabulary string on its way to the screen, and passes everything else
 * through — so it becomes a no-op the moment the shared copy changes.
 */
private fun failureReason(change: FailedChange): String =
    if (change.reason == Copy.Notice.serverError) Copy.Account.couldNotReachServer else change.reason

// ─────────────────────────────────────────────────────────────────────────────
// Colophon
// ─────────────────────────────────────────────────────────────────────────────

/**
 * How the screen ends: the mark, the version, and the attribution the TMDB terms require — set as
 * fine print, because that is what it is.
 *
 * The attribution STRING is verbatim and must not be reworded; only the MEASURE is a design
 * decision. 330 dp is the width at which the two lines break after a noun.
 */
@Composable
private fun Colophon(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val version = remember(context) { versionName(context) }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) { },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
    ) {
        // The shared lockup: one drawing of the logo for the whole app, the full stop in the icon's
        // coral everywhere the name is set.
        Row(
            horizontalArrangement = Arrangement.spacedBy(WordmarkGap),
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.semantics { contentDescription = WordmarkSpoken },
        ) {
            PreviouslyMark(width = ColophonMarkWidth)
            BrandWord(style = ThemeType.brandWordmark, ink = ThemeColor.textSecondary)
        }
        BasicText(
            text = version,
            style = ThemeType.caption.copy(color = ThemeColor.textTertiary),
            maxLines = 1,
        )
        BasicText(
            text = Copy.Profile.ATTRIBUTION,
            style = ThemeType.caption.copy(
                color = ThemeColor.textDisabled,
                textAlign = TextAlign.Center,
            ),
            modifier = Modifier
                .padding(top = ThemeSpace.x2)
                .widthIn(max = AttributionWidth),
        )
    }
}

private val ColophonMarkWidth = 9.dp
private val WordmarkGap = 7.dp
private val AttributionWidth = 330.dp
private const val WordmarkSpoken = "Previously"

/** "1.0 (1)" — the version, then the build when there is one. */
private fun versionName(context: Context): String {
    val info = runCatching {
        context.packageManager.getPackageInfo(context.packageName, 0)
    }.getOrNull()
    val name = info?.versionName ?: "1.0"
    @Suppress("DEPRECATION")
    val code = info?.let {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) it.longVersionCode
        else it.versionCode.toLong()
    }
    return if (code != null) "$name ($code)" else name
}

// ─────────────────────────────────────────────────────────────────────────────
// Export
// ─────────────────────────────────────────────────────────────────────────────

/**
 * The pushed export screen, inside the sheet's own host.
 *
 * A PUSH, not a menu: "the pushed screen gives each format a title and a real support line, and
 * covers nothing (the menu anchored itself over the row that raised it)."
 */
@Composable
private fun ExportScreen(
    library: List<Franchise>,
    topInset: Dp,
    onBack: () -> Unit,
    onFailure: () -> Unit,
) {
    val scrollState = rememberScrollState()
    val scroll = rememberScrollOffset()
    scroll.track(scrollState)
    val raised by scroll.past(ThemeMetrics.topChromeRamp)
    val barBottom = topInset + ThemeMetrics.inlineBarHeight

    ScrollEdgeChromeBox(
        modifier = Modifier.fillMaxSize(),
        edges = ChromeEdge.Top,
        softTop = true,
        topRaised = raised,
        topHold = barBottom,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(scrollState)
                .padding(horizontal = ThemeMetrics.gutter),
        ) {
            Spacer(Modifier.height(barBottom + ThemeSpace.x4))
            ExportRows(library = library, onFailure = onFailure)
            BasicText(
                text = Copy.Profile.EXPORT_FOOTNOTE,
                style = ThemeType.metadata.copy(color = ThemeColor.textTertiary),
                modifier = Modifier
                    .padding(horizontal = ThemeMetrics.gutter)
                    .padding(top = ThemeMetrics.labelGap),
            )
            Spacer(Modifier.height(SheetBottomClearance + bottomSafeInset()))
        }

        ProfileBar(
            title = Copy.Profile.EXPORT,
            topInset = topInset,
            leading = { BackControl(onBack) },
            modifier = Modifier.align(Alignment.TopCenter),
        )
    }
}

/**
 * The bar's back control.
 *
 * **A known substitution:** the icon vocabulary carries no `arrow_back`, which is the Android
 * reflex here; `chevron_right` mirrored is the same glyph pointing the way back, and it is what the
 * vocabulary can express today. Flagged for the icon owner rather than vendored on the fly.
 */
@Composable
private fun BackControl(onBack: () -> Unit) {
    Box(
        modifier = Modifier
            .size(ThemeMetrics.inlineBarHeight)
            .clickable(
                interactionSource = null,
                indication = PressStyle.textAction,
                role = Role.Button,
                onClick = onBack,
            )
            // The glyph says nothing aloud, so the control is named rather than hinted: what it
            // DOES and what it IS are the same word here.
            .semantics { contentDescription = BackSpoken },
        contentAlignment = Alignment.Center,
    ) {
        SymbolIcon(
            symbol = PreviouslyIcons.ChevronRight,
            tint = ThemeColor.textPrimary,
            glyph = BackGlyph,
            // Mirrored: the vocabulary's chevron points forward, and this one points back.
            modifier = Modifier.graphicsLayer { scaleX = -1f },
        )
    }
}

/** iOS draws a bar's back chevron at 17 pt semibold. */
private val BackGlyph = 17.dp

/** The system word for the control, since the glyph itself says nothing aloud. */
private const val BackSpoken = "Back"

// ─────────────────────────────────────────────────────────────────────────────
// The wash
// ─────────────────────────────────────────────────────────────────────────────

/**
 * The ambient field behind the identity block.
 *
 * **It draws no image.** `ArtBackdrop` blurs the poster's own top-left corner, "which is why this
 * screen measured rgb(66,80,94) on one side against rgb(29,49,67) on the other: a blurred crop of
 * an off-centre region is lit by whatever happened to be in that region, and a 2.2× left-to-right
 * falloff reads as a bug, not as atmosphere. An elliptical field centred on the top edge is even by
 * construction."
 *
 * Three things are load-bearing:
 *
 *  * **It travels with the content** ([scroll] is read inside `graphicsLayer`, never in a body).
 *  * **It ENDS.** Nothing above the bar, a 90-dp ramp under it, and a 110-dp ramp OUT that lands on
 *    the shelf's top edge — so no plate on this screen ever contains the end of a gradient.
 *  * **Its hue travels TOWARD the brand and is clamped**, never interpolated freely: "a free 55 %
 *    mix … Wistoria's cover derives a teal, and 55 % of the way from teal to amber is olive — a
 *    full-screen green field on a warm-branded app."
 *
 * ### The one sanctioned exception to the single-wash rule
 *
 * Everything else in the app draws `ArtBackdrop` at `ThemeMetrics.rootWashHeight` /
 * `rootWashIntensity`, and a screen may not carry a private height/intensity pair — the season
 * screen carried one until it was deleted (3 Sep pass). This field is the exception, on BOTH
 * platforms and deliberately: iOS carries the identical bespoke field and calls it "the local
 * stand-in for the shared `ArtBackdrop`" (`ios/Sources/Features/Profile/ProfileView.swift`). It is
 * a different drawing for a different job — no image, an elliptical field, scroll-tracked, with a
 * measured end — not a second configuration of the same one. Recorded here so the rule has one
 * known exception rather than two undocumented ones.
 */
@Composable
private fun ProfileWash(
    tint: Color?,
    fadeEnd: Dp,
    barBottom: Dp,
    scroll: ScrollOffset,
    modifier: Modifier = Modifier,
) {
    val warm = remember(tint) { warmField(tint) }
    val height = maxOf(fadeEnd + WashTail, WashMinHeight)

    Spacer(
        modifier = modifier
            .fillMaxWidth()
            .height(height)
            .graphicsLayer {
                // The mask is a DstIn pass, which needs a layer of its own to land in.
                compositingStrategy = CompositingStrategy.Offscreen
                // The offset is read HERE, at draw time. A body read would re-run this screen on
                // every sampled frame of a scroll, which is the exact jank the offset object exists
                // to prevent.
                translationY = -max(0f, scroll.y) * density
            }
            .drawBehind {
                val cx = size.width * WashCenterX
                val cy = size.height * WashCenterY
                val rx = size.width * WashRadiusFraction
                val ry = size.height * WashRadiusFraction

                // An ellipse, drawn as a circle in a scaled space. The rect is deliberately larger
                // than the node so the scaled fill still covers every corner.
                scale(scaleX = 1f, scaleY = ry / rx, pivot = Offset(cx, cy)) {
                    drawRect(
                        brush = Brush.radialGradient(
                            0.00f to warm.copy(alpha = 0.28f),
                            0.42f to warm.copy(alpha = 0.16f),
                            0.62f to warm.copy(alpha = 0.09f),
                            0.80f to warm.copy(alpha = 0.04f),
                            1.00f to Color.Transparent,
                            center = Offset(cx, cy),
                            radius = rx,
                        ),
                        topLeft = Offset(-size.width, -size.height),
                        size = Size(size.width * 3f, size.height * 3f),
                    )
                }

                drawRect(
                    brush = washMask(
                        heightPx = size.height,
                        barBottomPx = barBottom.toPx(),
                        fadeEndPx = fadeEnd.toPx(),
                        rampInPx = WashRampIn.toPx(),
                        rampOutPx = WashRampOut.toPx(),
                    ),
                    blendMode = BlendMode.DstIn,
                )
            },
    )
}

private const val WashCenterX = 0.5f
private const val WashCenterY = 0.42f
private const val WashRadiusFraction = 0.92f
private val WashTail = 40.dp
private val WashMinHeight = 420.dp
private val WashRampIn = 90.dp
private val WashRampOut = 110.dp

/**
 * The alpha ramp the field is cut to: clear above the bar, in over [rampInPx], solid, then out over
 * [rampOutPx] so it finishes exactly on the shelf's top edge.
 */
private fun washMask(
    heightPx: Float,
    barBottomPx: Float,
    fadeEndPx: Float,
    rampInPx: Float,
    rampOutPx: Float,
): Brush {
    if (heightPx <= 0f) return Brush.verticalGradient(0f to Color.Black, 1f to Color.Black)
    val top = (barBottomPx / heightPx).coerceIn(0f, 1f)
    val inEnd = ((barBottomPx + rampInPx) / heightPx).coerceIn(top, 1f)
    val outEnd = (fadeEndPx / heightPx).coerceIn(inEnd, 1f)
    val outStart = ((fadeEndPx - rampOutPx) / heightPx).coerceIn(inEnd, outEnd)
    return Brush.verticalGradient(
        0f to Color.Transparent,
        top to Color.Transparent,
        inEnd to Color.Black,
        outStart to Color.Black,
        outEnd to Color.Transparent,
        1f to Color.Transparent,
    )
}

/**
 * The field's hue: the artwork chooses the DIRECTION and the saturation; the brand chooses the
 * range.
 *
 * ±12.6° from the accent's 31° spans **18°…44°** — a blue- or red-led library reads orange-red, a
 * green- or teal-led one reads gold. Visibly different libraries, one warm range. Interpolating
 * toward a hue and clamping the distance to it are not the same operation, and only the second one
 * has a floor.
 */
private fun warmField(tint: Color?): Color {
    val base = FloatArray(3)
    val brand = FloatArray(3)
    AndroidColor.colorToHSV((tint ?: ArtGround.neutralWarm).toArgb(), base)
    AndroidColor.colorToHSV(ThemeColor.accent.toArgb(), brand)

    val travel = shorterArc(from = brand[0], to = base[0]).coerceIn(-HueTravelDegrees, HueTravelDegrees)
    val hue = ((brand[0] + travel) % 360f + 360f) % 360f
    val saturation = (base[1] * 0.5f + brand[1] * 0.5f)
        .coerceAtLeast(WashSaturationFloor)
        .coerceAtMost(brand[1])
    return Color.hsv(hue, saturation, WashBrightness)
}

/** The signed shorter arc from `from` to `to`, in degrees. */
private fun shorterArc(from: Float, to: Float): Float = ((to - from + 540f) % 360f) - 180f

/** iOS ±0.035 turns. */
private const val HueTravelDegrees = 12.6f
private const val WashSaturationFloor = 0.30f
private const val WashBrightness = 0.85f

// ─────────────────────────────────────────────────────────────────────────────
// The snapshot
// ─────────────────────────────────────────────────────────────────────────────

/**
 * What the account looked like the last time its library actually arrived.
 *
 * "The screen had no memory at all, so an offline open collapsed from `fan + disc + name + counts +
 * sync + settings` to `disc + name + sync + settings`: the stats plate and the artwork were REMOVED
 * rather than degraded, and the user lost the only summary of their account exactly when they could
 * not verify it anywhere else. Three integers and three URLs … is the whole cost of the frame
 * surviving the failure."
 *
 * `SharedPreferences`, not DataStore, and for the reason `SyncCenter` gives: the read is
 * synchronous, because the screen renders from it on its first frame.
 */
@Immutable
internal data class ProfileSnapshot(
    val counts: Map<String, Int> = emptyMap(),
    val covers: List<String> = emptyList(),
) {

    /** Nothing remembered. The screen tells "never synced" apart from "couldn't check" with this. */
    val isEmpty: Boolean get() = counts.isEmpty() && covers.isEmpty()

    fun save(context: Context) {
        prefs(context).edit()
            .putString(COUNTS_KEY, encode(CountsSerializer, counts))
            .putString(COVERS_KEY, encode(CoversSerializer, covers))
            .apply()
    }

    companion object {
        private const val PREFS_NAME = "previously.profile"
        private const val COUNTS_KEY = "profile.snapshot.counts"
        private const val COVERS_KEY = "profile.snapshot.covers"

        private val CountsSerializer = MapSerializer(String.serializer(), Int.serializer())
        private val CoversSerializer = ListSerializer(String.serializer())

        fun load(context: Context): ProfileSnapshot {
            val p = prefs(context)
            return ProfileSnapshot(
                counts = decode(CountsSerializer, p.getString(COUNTS_KEY, null)) ?: emptyMap(),
                // A LIST, never a `StringSet`: the wash samples the CENTRE cover, and a set has no
                // centre because it has no order.
                covers = decode(CoversSerializer, p.getString(COVERS_KEY, null)) ?: emptyList(),
            )
        }

        /**
         * `null` when there is nothing worth remembering — **an empty library must never overwrite
         * a real snapshot**, because "the request failed" and "the account is empty" arrive as the
         * same value.
         */
        fun capture(library: List<Franchise>, covers: List<String>): ProfileSnapshot? {
            if (library.isEmpty()) return null
            val counts = WatchStatus.entries.associate { status ->
                status.wire to library.count { it.status == status }
            }
            return ProfileSnapshot(counts = counts, covers = covers)
        }

        fun clear(context: Context) {
            prefs(context).edit().remove(COUNTS_KEY).remove(COVERS_KEY).apply()
        }

        private fun prefs(context: Context) =
            context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        private fun <T> encode(serializer: KSerializer<T>, value: T): String? =
            runCatching { AniTrackJson.encodeToString(serializer, value) }.getOrNull()

        private fun <T> decode(serializer: KSerializer<T>, raw: String?): T? = raw?.let {
            runCatching { AniTrackJson.decodeFromString(serializer, it) }.getOrNull()
        }
    }
}

