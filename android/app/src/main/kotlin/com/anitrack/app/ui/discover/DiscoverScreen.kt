package com.anitrack.app.ui.discover

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.focusTarget
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.ColorProducer
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.anitrack.app.AppModel
import com.anitrack.app.MediaFilter
import com.anitrack.app.data.SyncCenter
import com.anitrack.app.design.ContinuousCornerShape
import com.anitrack.app.design.FeedbackCoordinator
import com.anitrack.app.design.FeedbackToken
import com.anitrack.app.design.LocalControlInk
import com.anitrack.app.design.LocalReduceMotion
import com.anitrack.app.design.MotionToken
import com.anitrack.app.design.PosterSize
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeMotion
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.motion
import com.anitrack.app.notifications.NotificationPrimer
import com.anitrack.app.ui.art.ArtBackdrop
import com.anitrack.app.ui.card.ShelfCard
import com.anitrack.app.ui.chrome.ScrollEdgeChromeBox
import com.anitrack.app.ui.chrome.chromeHazeSource
import com.anitrack.app.ui.chrome.tabBarContentBottom
import com.anitrack.app.ui.control.FilterChip
import com.anitrack.app.ui.control.InlineLink
import com.anitrack.app.ui.control.InlineLinkButton
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.control.SymbolIcon
import com.anitrack.app.ui.control.minimumTapTarget
import com.anitrack.app.ui.isAccessibilityTextSize
import com.anitrack.app.ui.library.PreviouslyPullToRefresh
import com.anitrack.app.ui.negativePadding
import com.anitrack.app.ui.row.MediaRow
import com.anitrack.app.ui.scroll.past
import com.anitrack.app.ui.scroll.rememberScrollOffset
import com.anitrack.app.ui.scroll.track
import com.anitrack.app.ui.section.SectionHeaderRow
import com.anitrack.app.ui.state.EmptyState
import com.anitrack.app.ui.state.InlineNotice
import com.anitrack.app.ui.state.RefreshIndicator
import com.anitrack.app.ui.state.SkeletonGate
import com.anitrack.app.ui.state.SkeletonRow
import com.anitrack.app.ui.state.centredState
import com.anitrack.model.FranchiseSummary
import com.anitrack.model.MediaSource
import com.anitrack.model.TemporalCopy
import com.anitrack.model.copy.Copy
import com.anitrack.model.copy.EmptyStateCopy
import com.anitrack.model.effectiveStatus
import com.anitrack.model.portraitArt
import kotlinx.coroutines.launch

// =====================================================================================
// SEARCH — ONE BROWSE ANATOMY.
//
// The port of `ios/Sources/Features/Discover/DiscoverView.swift`. The screen is one slot
// with two mutually exclusive trees in it — the LAUNCHPAD (trimmed query empty) and the
// RESULTS (trimmed query non-empty) — swapped with the app's asymmetric `handoff`.
//
// Its single most important rule, from CLAUDE.md:
//
//   "Search has one browse anatomy: a 3-column ShelfCard poster grid at rest AND focused
//    (recents rows above it once focused), scopes appear on text entry, results are
//    MediaRows only (no top-match card, no headers, `.row` slot everywhere); the hardened
//    bar hold follows focus — the title collapses when the field has focus, so the hold
//    shrinks to the drawer."
//
// The grid used to become a different list — the same shows as compact rows — the moment
// the field was tapped, so the tab's content changed anatomy under the finger for no reason
// a reader could name. Apple TV keeps its grid under the keyboard; so does this.
//
// Two further app-wide rules govern almost every decision here:
//
//   * **Amber is never an action colour.** It is rationed to a real forward-looking fact
//     (`whenFact`) and to the owned tick; every tappable word — Clear, Turn on, Retry,
//     "Search instead for …" — is `interactive` ink.
//   * **The payoff frame is never emptier than the question.** The trending grid stays
//     mounted underneath every empty, scoped-out and error state, because the screen has
//     already decoded that artwork. The app used to throw away a decoded shelf in order to
//     say one sentence, leaving a plate over 900 pt of black — on the screen a reviewer
//     walks first.
//
// -------------------------------------------------------------------------------------
// WHAT CHANGED IN THE PORT (fidelity line: port the meaning, render with native means,
// re-tune the numbers)
//
// 1. **The bar is app-drawn, not an M3 `TopAppBar`.** `TopAppBar` interpolates
//    `containerColor → scrolledContainerColor` as its scroll behaviour progresses, stacking
//    a second uncontrolled hardening layer on `ScrollEdgeChrome`'s 0.74-over-blur, and it
//    draws its title at `MaterialTheme.typography.titleLarge`. Neither is negotiable, so the
//    bar is a `Box` inside the chrome band with the app's own type. M3's `SearchBar` is
//    likewise unusable: it expands to full screen when active, which is not this behaviour.
//
// 2. **The pull, the bar's anatomy and the show context menu are the app's shared ones**, not
//    this screen's: `PreviouslyPullToRefresh` owns the gesture and the armed haptic, the title
//    band is `InlineChromeBar`'s anatomy (an inline title centred in the 44-dp band, no ground
//    of its own), and the long-press menu is the same seven commands the Library draws. The one
//    thing Search does NOT borrow is that menu's backlog count — see `LongPressMenu`.
//
// 3. **The keyboard dismisses on the first downward drag, it does not track the finger.**
//    Compose has no `scrollDismissesKeyboard(.interactively)` and the finger-tracked half is
//    not reproducible; a hide-on-drag `NestedScrollConnection` is the honest substitute.
//
// 4. **The scroll container is a plain `Column`, not a `LazyColumn`.** Everything on this
//    screen is bounded — the chart is 10, recents are capped at 10 + 10, a result set is one
//    page — and the launchpad↔results `handoff` has to animate two whole trees in one slot,
//    which a lazy list cannot express. The bottom clearance is still applied INSIDE the
//    scroll (`padding` after `verticalScroll`), which is what makes it extend the scrollable
//    range the way iOS's content margin does — padding under a stack shorter than the viewport
//    changes no layout at all, which is exactly the case the launchpad is in.
// =====================================================================================

/**
 * The Search tab.
 *
 * @param onOpenDetail pushes the show page. **A plain push, not a zoom** — the `.zoom`
 *   transition was tried on iOS and retired, and the `zoomID` strings it needed are dropped
 *   entirely here.
 */
@Composable
fun DiscoverScreen(
    appModel: AppModel,
    onOpenDetail: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val scope = rememberCoroutineScope()
    val reduceMotion = LocalReduceMotion.current
    val isAX = isAccessibilityTextSize()
    val keyboard = LocalSoftwareKeyboardController.current
    val focusManager = LocalFocusManager.current

    // `query` trims SPACES ONLY, exactly as the iOS view does; the model's own scheduler trims
    // whitespace and newlines. The two are deliberately allowed to differ: this one decides which
    // TREE is on screen, and a trailing newline is not a reason to swap the page.
    val query = appModel.searchQuery.trim(' ')

    // Computed ONCE per composition and handed down, never re-read. The iOS body read
    // `filteredSearchResults` eight times and `ResultSet`'s duplicate-title scan ran once per ROW on
    // top of that — a regex over every title, dozens of times per keystroke.
    val filtered = appModel.filteredSearchResults
    val results = remember(filtered) { ResultSet(filtered) }

    // The chart is filtered too: with TV selected the results were TV-only and the chart underneath
    // them still led with an anime, so the scope bar appeared to govern half the screen.
    val trendingAll = appModel.trending
    val mediaFilter = appModel.mediaFilter
    val trending = remember(trendingAll, mediaFilter) {
        trendingAll.filter { appModel.matchesMediaFilter(it.source) }
    }

    // The ambient wash is keyed to the chart's leader — a poster this screen is already loading, so
    // the atmosphere costs one decode and never changes under the user mid-session, not even when
    // the scope hides it from the chart. Hence the UNFILTERED list.
    val washUrl = trendingAll.firstOrNull()?.portraitArt

    val scrollState = rememberScrollState()
    val scroll = rememberScrollOffset()
    scroll.track(scrollState)

    var fieldPresented by remember { mutableStateOf(false) }
    val focusRequester = remember { FocusRequester() }

    val topSafe = ThemeMetrics.topSafeInset()
    val scopesVisible = query.isNotEmpty()

    // Where the bar's chrome ends: title + drawer at rest; once the field has focus the title
    // collapses and only the field's band remains. The hardened veil and its probe follow it —
    // sized to the RESTING chrome, the veil swallowed the grid's header the moment the field was
    // tapped. The scope band is added because on Android the chips live in the bar rather than in a
    // system drawer, and content may not slide under them either.
    val searchChromeBottom = topSafe +
        (if (fieldPresented) 0.dp else ThemeMetrics.inlineBarHeight) +
        ThemeMetrics.searchDrawerHeight +
        (if (scopesVisible) scopeBandHeight else 0.dp)
    val chromeBand by animateDpAsState(
        targetValue = searchChromeBottom,
        animationSpec = motion(MotionToken.UI_GENTLE),
        label = "searchChromeBottom",
    )

    // The scroll content starts at the bar's bottom edge, so anything at all under the bar means
    // "raised". A boolean probe, so the screen recomposes on the CROSSING rather than on the scroll.
    val raisedTop by scroll.past(chromeRaiseThreshold)

    // ---- the query pipeline's side effects -------------------------------------------------

    LaunchedEffect(Unit) { appModel.loadTrendingIfNeeded() }

    // A start that lands ON this tab opens at REST — the browse grid, the title, no caret.
    //
    // Compose gives INITIAL focus to the first focusable node in the tree, and on this screen that
    // node is the field; the platform then raises the IME, because a focused editor is what it
    // sees. So a cold start onto Search (`-e openTab discover`, and any future deep link onto this
    // tab) opened with the keyboard over the chart, the title already collapsed and Cancel already
    // drawn — a screen caught mid-interaction before the user had touched it. Arriving by TAPPING
    // the tab never did this, because by then focus already lived somewhere else.
    //
    // The fix is to give that assignment somewhere harmless to land, NOT to undo it afterwards.
    // Both ways of undoing it were tried and neither survives contact: clearing from inside
    // `onFocusChanged` re-enters the focus dispatch and dies with a StackOverflowError, and
    // clearing a frame later hands focus straight back to the field (nothing else can hold it),
    // leaving a caret in the field and an IME that neither `SoftwareKeyboardController.hide` nor
    // the window insets controller will take down. An anchor ends the argument: it is focusable,
    // it is not an editor, and it is first — so the assignment lands on it, no keyboard is raised,
    // and the field is left for whoever actually asks for it.
    //
    // `focusTarget` rather than `focusable`: this must exist for the FOCUS system only. `focusable`
    // would also publish semantics and put an invisible stop in the TalkBack order.
    val restAnchor = remember { FocusRequester() }
    LaunchedEffect(Unit) {
        if (!appModel.searchFieldRequested) {
            // Attached by now in every real frame; a request against a detached node throws rather
            // than returning false, and a screen that never composed its anchor needs no anchor.
            try {
                restAnchor.requestFocus()
            } catch (e: IllegalStateException) {
                Log.d(SEARCH_LOG_TAG, "rest anchor not attached: ${e.message}")
            }
        }
    }

    // An off-tab CTA ("Add a show", the empty Schedule) asked for the FIELD, not just the tab.
    LaunchedEffect(appModel.searchFieldRequested) {
        if (appModel.searchFieldRequested) {
            appModel.searchFieldRequested = false
            focusRequester.requestFocus()
        }
    }

    // ---- the spoken outcome (WCAG 4.1.3) ---------------------------------------------------
    //
    // A screen-reader user typed a query and results arrived, or didn't, or failed, and nothing was
    // spoken. The announcement says the SAME title the visible state shows: it used to announce the
    // anime catalogue's notice for a server error and the no-results title for a scoped-out set.

    var announcement by remember { mutableStateOf("") }
    val outcome = {
        announcement = outcomeTitle(
            results = ResultSet(appModel.filteredSearchResults),
            appModel = appModel,
            query = query,
        )
    }
    LaunchedEffect(appModel.searchBusy) {
        if (!appModel.searchBusy && query.isNotEmpty()) outcome()
    }
    var lastFilter by remember { mutableStateOf(mediaFilter) }
    LaunchedEffect(mediaFilter) {
        if (mediaFilter == lastFilter) return@LaunchedEffect
        lastFilter = mediaFilter
        FeedbackCoordinator.fire(FeedbackToken.SELECTION)
        if (query.isNotEmpty() && !appModel.searchBusy) outcome()
    }

    // ---- the notification primer -----------------------------------------------------------

    val context = LocalContext.current
    var primerVisible by remember { mutableStateOf(false) }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        // Allowed is a success (one haptic, one line); declined is the system's own answer and needs
        // no second one. The card used to vanish either way with no receipt at all.
        if (granted) {
            FeedbackCoordinator.fire(FeedbackToken.SUCCESS)
            appModel.showNotice(Copy.Toast.alertsOn)
            scope.launch { appModel.alertsWereAllowed() }
        }
        primerVisible = false
    }

    // The pending flag is `NotificationPrimer`'s, not this screen's: every add path arms it through
    // `AppModel.addToLibrary`, so an add on Today or on the show page raises the ask here. This
    // screen still owns the half that is about the DEVICE — whether the OS can be asked at all.
    val refreshPrimer = {
        primerVisible = NotificationPrimer.pending &&
            !NotificationPrimer.answered &&
            canAskForNotifications(context)
    }
    LaunchedEffect(Unit) { refreshPrimer() }
    // On any library-size change, exactly as iOS re-runs its `.task(id: library.count)`, and on the
    // arming itself — which lands seconds after the add, once the undo window has closed. The
    // permission round-trip happens ONLY while there is a primer to show: it used to run on every
    // library change for every user, forever, including the ones who answered on day one.
    LaunchedEffect(appModel.library.size) { refreshPrimer() }
    LaunchedEffect(NotificationPrimer.pending, NotificationPrimer.answered) { refreshPrimer() }

    val answerPrimer: (Boolean) -> Unit = { turnOn ->
        // Both answers set "answered" permanently; Profile → Notifications is the only route back.
        NotificationPrimer.settle()
        primerVisible = false
        if (turnOn) permissionLauncher.launch(POST_NOTIFICATIONS)
    }

    // ---- actions ---------------------------------------------------------------------------

    // The SHOW the user acted on is what "Recently searched" remembers — the term only when it came
    // from the field. Opening a card from the launchpad's chart (empty query) records nothing.
    val open: (FranchiseSummary) -> Unit = { item ->
        if (query.isNotEmpty()) appModel.recordRecentItem(item)
        onOpenDetail(item.id)
    }
    val add: (FranchiseSummary) -> Unit = { item ->
        appModel.addToLibrary(
            franchiseId = item.id,
            title = item.title,
            isReleasing = item.isReleasing,
            source = item.source,
        )
        if (query.isNotEmpty()) appModel.recordRecentItem(item)
    }

    // ---- pull to refresh -------------------------------------------------------------------
    //
    // The one root without a pull: the chart is a network list like any other. Note the asymmetry —
    // the pull refreshes TRENDING, never the query. A failed search is retried through the notice's
    // "Retry" or the empty state's "Try again".
    //
    // The gesture, the armed haptic and the re-arm floor all live in the app's ONE pull component;
    // this screen supplies the work and takes back "the system indicator owns this moment", which is
    // what stands the bar's own spinner down.

    var pullDriving by remember { mutableStateOf(false) }

    val dismissKeyboardOnDrag = remember(keyboard) {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (source == NestedScrollSource.UserInput && available.y < 0f) keyboard?.hide()
                return Offset.Zero
            }
        }
    }

    // ---- the screen ------------------------------------------------------------------------

    Box(
        modifier
            .fillMaxSize()
            .background(ThemeColor.canvas)
            // Where Compose's initial focus assignment lands, so that it never lands in the field.
            .focusRequester(restAnchor)
            .focusTarget(),
    ) {
        ScrollEdgeChromeBox(
            softTop = true,
            topRaised = raisedTop,
            // The SOFT layer's band: the at-rest edge of an art-backed screen, sized to the field's
            // own drawer. The hard layer's height is computed independently from `topHold`.
            topHeight = topSafe + ThemeMetrics.searchDrawerHeight,
            topHold = chromeBand,
        ) {
            ArtBackdrop(
                modifier = Modifier.align(Alignment.TopCenter),
                url = washUrl,
                // No artwork anywhere (a chart that has not landed, or an offline first run): the
                // band gets the app's own colour rather than a grey strip.
                tint = if (washUrl == null) ThemeColor.accent else null,
            )

            PreviouslyPullToRefresh(
                modifier = Modifier.fillMaxSize(),
                onRefresh = { appModel.refreshTrending() },
                onDrivingChange = { if (it != pullDriving) pullDriving = it },
            ) {
                // The viewport's own height, for `centredState`. Taken from the constraints rather
                // than measured after the fact: a state block that is centred one frame late lands
                // visibly, and the chrome band comes off it because the content below already starts
                // at the bar's bottom edge.
                BoxWithConstraints(Modifier.fillMaxSize()) {
                    val contentHeight = (maxHeight - searchChromeBottom).coerceAtLeast(0.dp)
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .chromeHazeSource()
                            .nestedScroll(dismissKeyboardOnDrag)
                            .verticalScroll(scrollState)
                            // Bottom clearance INSIDE the scroll, so it extends the scrollable range.
                            // Padding under a stack shorter than the viewport changes no layout at all,
                            // which is exactly the case the launchpad is in — and it is why the sixth
                            // chart row came to rest inside the bottom ramp with its enabled `+` at
                            // 131/255 against 241 for the identical control four rows higher.
                            .padding(top = chromeBand, bottom = tabBarContentBottom()),
                    ) {
                        LiveOutcome(announcement)

                        // The primer is orthogonal: it can appear over any state of the slot below it.
                        AnimatedVisibility(
                            visible = primerVisible,
                            enter = fadeIn(ThemeMotion.uiSettle()) + expandVertically(ThemeMotion.uiSettle()),
                            exit = fadeOut(ThemeMotion.uiSettle()) + shrinkVertically(ThemeMotion.uiSettle()),
                        ) {
                            NotificationPrimerRow(
                                onTurnOn = { answerPrimer(true) },
                                onNotNow = { answerPrimer(false) },
                                modifier = Modifier.padding(top = ThemeSpace.x2),
                            )
                        }

                        // THE one structural change on this screen. SwiftUI's default crossfade
                        // dissolved three posters and a numbered chart THROUGH a list of rows for
                        // 220 ms — the double-exposure class of artefact. `handoff` is asymmetric: the
                        // outgoing tree leaves first (160 ms) and the incoming one settles into the
                        // space it left, delayed past the removal.
                        AnimatedContent(
                            targetState = query.isEmpty(),
                            transitionSpec = { ThemeMotion.handoff(reduceMotion) },
                            label = "searchSlot",
                        ) { launchpad ->
                            if (launchpad) {
                                Launchpad(
                                    appModel = appModel,
                                    trending = trending,
                                    fieldPresented = fieldPresented,
                                    contentHeight = contentHeight,
                                    isAX = isAX,
                                    onOpen = open,
                                    onAdd = add,
                                )
                            } else {
                                SearchBody(
                                    appModel = appModel,
                                    query = query,
                                    results = results,
                                    trending = trending,
                                    isAX = isAX,
                                    onOpen = open,
                                    onAdd = add,
                                )
                            }
                        }
                    }
                }
            }
        }

        SearchChrome(
            modifier = Modifier.align(Alignment.TopCenter),
            topSafe = topSafe,
            titleVisible = !fieldPresented,
            query = appModel.searchQuery,
            onQueryChange = { appModel.searchQuery = it },
            prompt = Copy.Search.prompt(mediaFilter.wire),
            focusRequester = focusRequester,
            onFieldFocus = { fieldPresented = it },
            onSubmit = { appModel.recordRecentSearch() },
            onCancel = {
                // Matching iOS's Cancel: the field loses focus AND the query goes — which is what
                // brings the title (and the resting chrome band) back.
                appModel.searchQuery = ""
                focusManager.clearFocus()
            },
            scopesVisible = scopesVisible,
            mediaFilter = mediaFilter,
            onScope = { appModel.mediaFilter = it },
            refreshing = appModel.trendingLoading,
            pullDriving = pullDriving,
        )
    }
}

// =====================================================================================
// The chrome
// =====================================================================================

/** The scope band's own height: a 34-dp capsule inside a 44-dp target, and nothing else. */
private val scopeBandHeight = minimumTapTarget

/**
 * The first real pixel of scroll.
 *
 * The content starts at the bar's bottom edge, so "content has passed under the BAR" is simply
 * "the scroll moved". iOS says the same thing as `minY < searchChromeBottom` against a scroll view
 * whose content inset already IS `searchChromeBottom`.
 */
private val chromeRaiseThreshold = 1.dp

/** The search field's own height, and the glyphs inside it at their iOS point sizes. */
private val fieldHeight = minimumTapTarget
private val fieldGlyph = 15.dp
private val fieldClearGlyph = 13.dp

/**
 * The bar: a title row, the docked field, and the scope chips.
 *
 * Drawn ABOVE the scroll-edge veil, inside the same band the veil holds canvas through, so the two
 * cannot disagree about where the chrome ends.
 */
@Composable
private fun SearchChrome(
    topSafe: Dp,
    titleVisible: Boolean,
    query: String,
    onQueryChange: (String) -> Unit,
    prompt: String,
    focusRequester: FocusRequester,
    onFieldFocus: (Boolean) -> Unit,
    onSubmit: () -> Unit,
    onCancel: () -> Unit,
    scopesVisible: Boolean,
    mediaFilter: MediaFilter,
    onScope: (MediaFilter) -> Unit,
    refreshing: Boolean,
    pullDriving: Boolean,
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxWidth().padding(top = topSafe)) {
        AnimatedVisibility(
            visible = titleVisible,
            enter = fadeIn(ThemeMotion.uiGentle()) + expandVertically(ThemeMotion.uiGentle()),
            exit = fadeOut(ThemeMotion.uiGentle()) + shrinkVertically(ThemeMotion.uiGentle()),
        ) {
            // The same anatomy as `InlineChromeBar`: the title CENTRED in the 44-dp band under the
            // status bar, with the trailing slot laid over it rather than beside it, so a control
            // present on one side only cannot shift the title. Inline, never a large title — "a
            // large title collapses on the first scroll and moves the top safe area ~50 pt
            // mid-flight; an inline one holds still over the wash." The bar paints no ground: the
            // hardened veil under it is the bar's material.
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(ThemeMetrics.inlineBarHeight),
                contentAlignment = Alignment.Center,
            ) {
                BasicText(
                    text = Copy.Search.title,
                    style = ThemeType.showTitleM,
                    maxLines = 1,
                    color = ColorProducer { ThemeColor.textPrimary },
                )
                // Mounted only while refreshing — never held at opacity 0 as a layout placeholder —
                // and it stands down entirely while the system's pull indicator owns the moment.
                if (refreshing) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = ThemeMetrics.gutter),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Spacer(Modifier.weight(1f))
                        RefreshIndicator(isRefreshing = true, suppressed = pullDriving)
                    }
                }
            }
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(ThemeMetrics.searchDrawerHeight)
                .padding(horizontal = ThemeMetrics.gutter),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
        ) {
            SearchField(
                value = query,
                onValueChange = onQueryChange,
                prompt = prompt,
                focusRequester = focusRequester,
                onFieldFocus = onFieldFocus,
                onSubmit = onSubmit,
                modifier = Modifier.weight(1f),
            )
            AnimatedVisibility(
                visible = !titleVisible,
                enter = fadeIn(ThemeMotion.uiGentle()),
                exit = fadeOut(ThemeMotion.uiGentle()),
            ) {
                // `interactive` ink, like every other bare tappable word in the app.
                InlineLinkButton(label = Copy.Action.cancel, onClick = onCancel)
            }
        }

        AnimatedVisibility(
            visible = scopesVisible,
            enter = fadeIn(ThemeMotion.uiGentle()) + expandVertically(ThemeMotion.uiGentle()),
            exit = fadeOut(ThemeMotion.uiGentle()) + shrinkVertically(ThemeMotion.uiGentle()),
        ) {
            SearchScopeBar(
                selected = mediaFilter,
                onSelect = onScope,
                modifier = Modifier
                    .height(scopeBandHeight)
                    .padding(horizontal = ThemeMetrics.gutter),
            )
        }
    }
}

/**
 * The field.
 *
 * A `BasicTextField` with the app's own decoration rather than an M3 `TextField`: Material's would
 * arrive with Material typography, a Material container and a `primary`-tinted caret, and the caret
 * in particular must be `interactive` ink — amber is not an action colour, and a blinking amber bar
 * is the loudest thing on a screen full of artwork.
 *
 * Capitalisation and autocorrect are both OFF: the system field capitalises the first letter and
 * autocorrects romaji titles into English words ("Sousou" → "Season").
 */
@Composable
private fun SearchField(
    value: String,
    onValueChange: (String) -> Unit,
    prompt: String,
    focusRequester: FocusRequester,
    onFieldFocus: (Boolean) -> Unit,
    onSubmit: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val ink = LocalControlInk.current
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier
            .height(fieldHeight)
            .focusRequester(focusRequester)
            .onFocusChanged { onFieldFocus(it.isFocused) },
        singleLine = true,
        textStyle = ThemeType.fieldInput.copy(color = ThemeColor.textPrimary),
        cursorBrush = SolidColor(ink),
        keyboardOptions = KeyboardOptions(
            capitalization = KeyboardCapitalization.None,
            autoCorrectEnabled = false,
            imeAction = ImeAction.Search,
        ),
        // The field always carried a Search return key on iOS and then threw the submission away,
        // so RECENT could only ever hold terms left over from an older build.
        keyboardActions = KeyboardActions(onSearch = { onSubmit() }),
        decorationBox = { field ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(fieldHeight)
                    .background(
                        ThemeColor.surfaceFlat,
                        ContinuousCornerShape(ThemeRadius.compactControl),
                    )
                    .padding(horizontal = ThemeSpace.x3),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
            ) {
                SymbolIcon(
                    symbol = PreviouslyIcons.Search,
                    tint = ThemeColor.textTertiary,
                    glyph = fieldGlyph,
                )
                Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                    if (value.isEmpty()) {
                        BasicText(
                            text = prompt,
                            style = ThemeType.fieldInput,
                            maxLines = 1,
                            color = ColorProducer { ThemeColor.textTertiary },
                        )
                    }
                    field()
                }
                if (value.isNotEmpty()) {
                    Box(
                        modifier = Modifier
                            .clickable(
                                interactionSource = null,
                                indication = PressStyle.textAction,
                                role = Role.Button,
                                onClick = { onValueChange("") },
                            )
                            .semantics { contentDescription = Copy.Action.clear }
                            .size(minimumTapTarget),
                        contentAlignment = Alignment.Center,
                    ) {
                        SymbolIcon(
                            symbol = PreviouslyIcons.Close,
                            tint = ThemeColor.textTertiary,
                            glyph = fieldClearGlyph,
                        )
                    }
                }
            }
        },
    )
}

/**
 * The spoken outcome, as a polite live region on an invisible node.
 *
 * A screen-reader user typed a query and results arrived, or didn't, or failed, and nothing was
 * spoken. **Polite** rather than assertive: it waits for the reader to finish whatever it is saying,
 * which is what `AccessibilityNotification.Announcement` does on iOS.
 *
 * One dp rather than zero: a 0 × 0 node is not reliably kept in the semantics tree, and a live
 * region that is pruned announces nothing at all.
 */
@Composable
private fun LiveOutcome(message: String) {
    Spacer(
        Modifier
            .size(liveRegionNode)
            .clearAndSetSemantics {
                liveRegion = LiveRegionMode.Polite
                contentDescription = message
            },
    )
}

private val liveRegionNode = 1.dp

// =====================================================================================
// The launchpad
// =====================================================================================

/**
 * The empty-query page: [the active scope token] · [recents] · the chart.
 *
 * **One page in the slot, at rest and focused.** The recents rows appear ABOVE the grid once the
 * field has focus; the grid itself never changes anatomy.
 */
@Composable
private fun Launchpad(
    appModel: AppModel,
    trending: List<FranchiseSummary>,
    fieldPresented: Boolean,
    contentHeight: Dp,
    isAX: Boolean,
    onOpen: (FranchiseSummary) -> Unit,
    onAdd: (FranchiseSummary) -> Unit,
) {
    val recentsEmpty = appModel.recentItems.isEmpty() && appModel.recentSearches.isEmpty()
    val showRecents = fieldPresented && !recentsEmpty

    Column(Modifier.fillMaxWidth()) {
        // An active scope is VISIBLE whenever the scope bar is not (the bar exists only while there
        // is text): a sticky TV/anime scope would otherwise filter the whole grid with nothing on
        // screen saying so and nothing to clear it with. Schedule's rule — whatever is filtering the
        // feed sits in the chrome as a removable token.
        AnimatedVisibility(
            visible = appModel.mediaFilter != MediaFilter.ALL,
            enter = fadeIn(ThemeMotion.uiSnappy()),
            exit = fadeOut(ThemeMotion.uiSnappy()),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = ThemeMetrics.gutter, vertical = ThemeSpace.x2),
                horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
            ) {
                FilterChip(
                    text = appModel.mediaFilter.chipLabel,
                    onRemove = {
                        // The haptic is fired once, by the screen's own `mediaFilter` observer.
                        appModel.mediaFilter = MediaFilter.ALL
                    },
                )
            }
        }

        if (showRecents) {
            RecentsSection(
                appModel = appModel,
                onOpen = onOpen,
                modifier = Modifier.padding(top = ThemeSpace.x2),
            )
        }

        if (trending.isNotEmpty()) {
            TrendingGrid(
                appModel = appModel,
                trending = trending,
                isAX = isAX,
                onOpen = onOpen,
                onAdd = onAdd,
                modifier = Modifier.padding(
                    top = if (showRecents) ThemeMetrics.sectionGap else ThemeSpace.x2,
                ),
            )
        } else {
            LaunchpadEmptyState(
                appModel = appModel,
                fieldPresented = fieldPresented,
                recentsEmpty = recentsEmpty,
                contentHeight = contentHeight,
            )
        }
    }
}

/**
 * The launchpad's three empty states, in order — and the fourth, implicit case.
 *
 * A focused page that already has recents on it draws NOTHING below them: the recents are content.
 */
@Composable
private fun LaunchpadEmptyState(
    appModel: AppModel,
    fieldPresented: Boolean,
    recentsEmpty: Boolean,
    contentHeight: Dp,
) {
    val scopeWord = Copy.Search.scopeWord(appModel.mediaFilter.wire)
    val stateModifier = Modifier
        .centredState(contentHeight)
        .padding(horizontal = ThemeMetrics.gutter)

    when {
        // "Find your next show" over a grid that will never load is a promise, and the connectivity
        // monitor knows it is an empty one.
        !SyncCenter.isOnline -> EmptyState(
            copy = EmptyStateCopy.searchOffline,
            modifier = stateModifier,
            onPrimary = { appModel.loadTrendingIfNeeded() },
        )

        // The SCOPE emptied the chart, not the server: name the filter and offer the same one-tap
        // way out the results page gives.
        appModel.mediaFilter != MediaFilter.ALL && appModel.trending.isNotEmpty() -> EmptyState(
            copy = EmptyStateCopy.noScopeTrending(scopeWord),
            modifier = stateModifier,
            onPrimary = { appModel.mediaFilter = MediaFilter.ALL },
        )

        !fieldPresented || recentsEmpty -> EmptyState(
            copy = EmptyStateCopy.searchLaunchpad,
            modifier = stateModifier,
        )
    }
}

/** "Recently searched" — the shows first, then whatever bare terms are left. */
@Composable
private fun RecentsSection(
    appModel: AppModel,
    onOpen: (FranchiseSummary) -> Unit,
    modifier: Modifier = Modifier,
) {
    val items = appModel.recentItems
    val terms = appModel.recentSearches

    Column(modifier, verticalArrangement = Arrangement.spacedBy(ThemeMetrics.labelGap)) {
        SectionHeaderRow(
            text = Copy.Search.recentlySearched,
            modifier = Modifier.padding(horizontal = ThemeMetrics.gutter),
            actionLabel = Copy.Action.clear,
            inlineAction = true,
            onAction = { appModel.clearRecents() },
        )
        Column(Modifier.padding(horizontal = ThemeMetrics.gutter)) {
            items.forEachIndexed { index, item ->
                LongPressMenu(
                    enabled = true,
                    menuContent = { dismiss ->
                        RecentRemoveCommand(
                            onRemove = {
                                dismiss()
                                appModel.removeRecentItem(item.id)
                            },
                        )
                    },
                ) {
                    MediaRow(
                        // The WHOLE title: a history list is not a disambiguation context.
                        title = item.title,
                        onClick = { onOpen(item) },
                        meta = shelfFacts(item, appModel).joinToString(FactLine.separator),
                        poster = item.portraitArt,
                        slot = PosterSize.Row,
                        // Recents rows keep the disclosure indicator; result rows do not, because
                        // their trailing column holds a control.
                        chevron = true,
                        separator = index < items.size - 1 || terms.isNotEmpty(),
                        hint = Copy.Accessibility.opensTheShowHint,
                    )
                }
            }
            terms.forEachIndexed { index, term ->
                SearchTermRow(
                    term = term,
                    separator = index < terms.size - 1,
                    onFill = { appModel.searchQuery = term },
                    onRemove = { appModel.removeRecentSearch(term) },
                )
            }
        }
    }
}

// =====================================================================================
// The trending grid
// =====================================================================================

/** Three flexible columns at 12-dp spacing inside a 16-dp gutter — the `.shelfMedium` poster width. */
private const val trendingColumns = 3

/**
 * "Trending now" — the chart, as a 3-column poster grid at rest AND focused.
 *
 * The header carries no count, no chevron and no action: it is a plain section title.
 *
 * **At accessibility sizes the grid becomes ROWS, not a one-column grid.** A poster grid has no
 * honest shape there — one card per row stretched a caption across the screen with its add disc
 * floating at the far edge. The results' own row is the anatomy that reflows, so the chart renders
 * the exact same row.
 */
@Composable
private fun TrendingGrid(
    appModel: AppModel,
    trending: List<FranchiseSummary>,
    isAX: Boolean,
    onOpen: (FranchiseSummary) -> Unit,
    onAdd: (FranchiseSummary) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(ThemeMetrics.labelGap)) {
        SectionHeaderRow(
            text = Copy.Search.trendingNow,
            modifier = Modifier.padding(horizontal = ThemeMetrics.gutter),
        )

        if (isAX) {
            Column(Modifier.padding(horizontal = ThemeMetrics.gutter)) {
                trending.forEachIndexed { index, item ->
                    ResultRow(
                        item = item,
                        appModel = appModel,
                        // A chart is not a disambiguation context.
                        ambiguous = emptySet(),
                        separator = index < trending.size - 1,
                        onOpen = onOpen,
                        onAdd = onAdd,
                    )
                }
            }
        } else {
            Column(
                modifier = Modifier.padding(horizontal = ThemeMetrics.gutter),
                verticalArrangement = Arrangement.spacedBy(ThemeMetrics.shelfGap),
            ) {
                trending.chunked(trendingColumns).forEach { row ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(ThemeMetrics.shelfGap),
                        // Top-aligned, so a two-line title in one card does not push its neighbours
                        // down.
                        verticalAlignment = Alignment.Top,
                    ) {
                        row.forEach { item ->
                            Box(Modifier.weight(1f)) {
                                TrendingCard(
                                    item = item,
                                    appModel = appModel,
                                    onOpen = onOpen,
                                    onAdd = onAdd,
                                )
                            }
                        }
                        repeat(trendingColumns - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }
        }
    }
}

/**
 * One chart card: the poster, the shortened title, and **exactly two facts**.
 *
 * A 112-dp caption cannot hold a third, and the owned disc in the art's corner already says the show
 * is in the library ("Watched · Anime / · 2021" wrapped with a middot opening the second line). Note
 * this is deliberately NOT `shelfFacts`: no status word, no season count.
 */
@Composable
private fun TrendingCard(
    item: FranchiseSummary,
    appModel: AppModel,
    onOpen: (FranchiseSummary) -> Unit,
    onAdd: (FranchiseSummary) -> Unit,
) {
    val franchise = appModel.franchise(item.id)
    val caption = listOfNotNull(item.source.kindWord, item.year?.toString())
        .joinToString(FactLine.separator)

    LongPressMenu(
        // A long-press menu only when the show is in the loaded library; otherwise no menu at all.
        enabled = franchise != null,
        menuContent = { dismiss ->
            if (franchise != null) {
                FranchiseCommands(
                    franchise = franchise,
                    appModel = appModel,
                    onDismiss = dismiss,
                )
            }
        },
        modifier = Modifier.width(PosterSize.ShelfMedium.width),
    ) {
        ShelfCard(
            reserveTitleLines = true,
            title = item.title,
            onClick = { onOpen(item) },
            caption = caption,
            poster = item.portraitArt,
            slot = PosterSize.ShelfMedium,
            hint = Copy.Accessibility.opensTheShowHint,
        )
        // OUTSIDE the card's own button on purpose: a button nested inside another button's label is
        // a coin-toss for which one gets the tap.
        AddControl(
            item = item,
            placement = AddControlPlacement.OverArt,
            appModel = appModel,
            onAdd = { onAdd(item) },
            // On the poster's foot (i3/i4): the top corner of a poster is where a face is, and
            // the card's bottom corner is the caption.
            modifier = Modifier
                .align(Alignment.TopEnd)
                .overArtFootPosition(PosterSize.ShelfMedium.width / PosterSize.posterAspectRatio),
        )
    }
}

// =====================================================================================
// The results
// =====================================================================================

/**
 * The non-empty-query page, behind the loading gate.
 *
 * The gate's condition excludes three cases that must NOT show a skeleton: a scoped-out set (the
 * data is already here), an error (there is a state for that), and a non-empty result set being
 * refined (that is the group dim).
 */
@Composable
private fun SearchBody(
    appModel: AppModel,
    query: String,
    results: ResultSet,
    trending: List<FranchiseSummary>,
    isAX: Boolean,
    onOpen: (FranchiseSummary) -> Unit,
    onAdd: (FranchiseSummary) -> Unit,
) {
    val scopedOut = appModel.scopedOut(results)
    SkeletonGate(
        isLoading = appModel.searchBusy && results.isEmpty && !scopedOut && !appModel.searchError,
        modifier = Modifier.fillMaxWidth(),
        skeleton = { SearchSkeleton() },
    ) {
        ResultsContent(
            appModel = appModel,
            query = query,
            results = results,
            trending = trending,
            isAX = isAX,
            onOpen = onOpen,
            onAdd = onAdd,
        )
    }
}

/**
 * The shape the results are about to take: rows at exactly the `.row` geometry the content uses, so
 * nothing reflows when the data lands.
 */
@Composable
private fun SearchSkeleton() {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = ThemeMetrics.gutter)
            .padding(top = ThemeSpace.x3),
    ) {
        repeat(skeletonRows) {
            SkeletonRow(
                poster = PosterSize.Row.size,
                lines = listOf(skeletonTitleWidth, skeletonMetaWidth),
                posterRadius = PosterSize.Row.radius,
                spacing = ThemeMetrics.artGap,
                height = ThemeMetrics.rowMedia,
            )
        }
    }
}

private const val skeletonRows = 5
private val skeletonTitleWidth = 188.dp
private val skeletonMetaWidth = 126.dp

/** The three-way branch: scoped out · empty · the list. */
@Composable
private fun ResultsContent(
    appModel: AppModel,
    query: String,
    results: ResultSet,
    trending: List<FranchiseSummary>,
    isAX: Boolean,
    onOpen: (FranchiseSummary) -> Unit,
    onAdd: (FranchiseSummary) -> Unit,
) {
    val notices = appModel.catalogueNotices()

    when {
        // The scope, not the query, emptied the list.
        appModel.scopedOut(results) -> StateWithTrending(
            appModel = appModel,
            trending = trending,
            isAX = isAX,
            onOpen = onOpen,
            onAdd = onAdd,
        ) {
            EmptyState(
                copy = EmptyStateCopy.noScopeMatches(
                    scope = Copy.Search.scopeWord(appModel.mediaFilter.wire),
                    query = query,
                ),
                onPrimary = { appModel.mediaFilter = MediaFilter.ALL },
            )
        }

        results.isEmpty -> StateWithTrending(
            appModel = appModel,
            trending = trending,
            isAX = isAX,
            onOpen = onOpen,
            onAdd = onAdd,
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(ThemeMetrics.gutter)) {
                Notices(messages = notices, appModel = appModel)
                when {
                    // `searchFailed` carries the wifi glyph and "check your connection", so it is
                    // the OFFLINE copy; online, the catalogue itself failed. Both name SEARCH — the
                    // online branch used the library's own error, on a screen that has nothing to do
                    // with the library. The two titles are deliberately the same words: one failure
                    // has one name.
                    appModel.searchError && SyncCenter.isOnline -> EmptyState(
                        copy = EmptyStateCopy.searchUnavailable,
                        onPrimary = { appModel.retrySearch() },
                    )

                    appModel.searchError -> EmptyState(
                        copy = EmptyStateCopy.searchFailed,
                        onPrimary = { appModel.retrySearch() },
                    )

                    else -> EmptyState(copy = EmptyStateCopy.noSearchResults(query))
                }
            }
        }

        else -> PopulatedResults(
            appModel = appModel,
            results = results,
            notices = notices,
            onOpen = onOpen,
            onAdd = onAdd,
        )
    }
}

/**
 * A whole-surface state, followed by the artwork this screen already has.
 *
 * The state is TOP-anchored at `sectionGap`, not centred: it has the grid under it, so there is
 * nothing to centre in.
 */
@Composable
private fun StateWithTrending(
    appModel: AppModel,
    trending: List<FranchiseSummary>,
    isAX: Boolean,
    onOpen: (FranchiseSummary) -> Unit,
    onAdd: (FranchiseSummary) -> Unit,
    state: @Composable () -> Unit,
) {
    Column(Modifier.fillMaxWidth()) {
        Box(
            Modifier
                .padding(horizontal = ThemeMetrics.gutter)
                .padding(top = ThemeMetrics.sectionGap),
        ) {
            state()
        }
        if (trending.isNotEmpty()) {
            TrendingGrid(
                appModel = appModel,
                trending = trending,
                isAX = isAX,
                onOpen = onOpen,
                onAdd = onAdd,
                modifier = Modifier.padding(top = ThemeMetrics.sectionGap),
            )
        }
    }
}

/**
 * The list.
 *
 * **Rows only — no headers, no top-match card, `.row` slot everywhere.** Apple TV's answer to a
 * query is the list of what matched; "Top match" (a plate, then an art tile) over "More results 3"
 * was two anatomies and a count for one list. There is no trending grid under a populated list: the
 * chart appears only in the empty and scoped-out branches.
 */
@Composable
private fun PopulatedResults(
    appModel: AppModel,
    results: ResultSet,
    notices: List<String>,
    onOpen: (FranchiseSummary) -> Unit,
    onAdd: (FranchiseSummary) -> Unit,
) {
    // Refining a query that already has results: the old set steps back as a GROUP while the new one
    // is in flight, so a list that is about to change never looks settled. 0.72 is the app-wide
    // group dim — `textSecondary` at 0.72 composites to ≈5.4:1 and still reads as content that has
    // stepped back (0.45 measured ≈2.64:1 and was unreadable).
    val dim = animateFloatAsState(
        targetValue = if (appModel.searchBusy) groupDim else 1f,
        animationSpec = motion(MotionToken.UI_GENTLE),
        label = "resultsGroupDim",
    )

    Column(
        Modifier
            .fillMaxWidth()
            // A deferred read: the dim animates a layer, not the list.
            .graphicsLayer { alpha = dim.value },
    ) {
        val refreshFailed = if (appModel.searchError) listOf(Copy.Search.couldNotRefresh) else emptyList()
        val messages = refreshFailed + notices
        if (messages.isNotEmpty()) {
            Notices(
                messages = messages,
                appModel = appModel,
                modifier = Modifier
                    .padding(horizontal = ThemeMetrics.gutter)
                    .padding(top = ThemeMetrics.gutter),
            )
        }

        appModel.searchCorrection?.let { correction ->
            CorrectionLine(
                correction = correction.corrected,
                original = correction.original,
                onSearchLiterally = { appModel.searchLiterally(correction.original) },
            )
        }

        Column(
            Modifier
                .padding(horizontal = ThemeMetrics.gutter)
                .padding(top = ThemeSpace.x3),
        ) {
            results.items.forEachIndexed { index, item ->
                ResultRow(
                    item = item,
                    appModel = appModel,
                    ambiguous = results.ambiguous,
                    separator = index < results.items.size - 1,
                    onOpen = onOpen,
                    onAdd = onAdd,
                )
            }
        }
    }
}

private const val groupDim = 0.72f

/**
 * THE one row anatomy for both lists on this screen: the app's `MediaRow`, no chevron (the trailing
 * column holds a control), the amber `whenFact` as its lead so a screen reader hears it inside the
 * row's own label, and the add control in the trailing slot.
 */
@Composable
private fun ResultRow(
    item: FranchiseSummary,
    appModel: AppModel,
    ambiguous: Set<String>,
    separator: Boolean,
    onOpen: (FranchiseSummary) -> Unit,
    onAdd: (FranchiseSummary) -> Unit,
) {
    val franchise = appModel.franchise(item.id)
    val now = appModel.nowMinute
    val lead = whenFact(item, now)
    val meta = rowFacts(item, ambiguous, appModel, now).joinToString(FactLine.separator)

    LongPressMenu(
        enabled = franchise != null,
        menuContent = { dismiss ->
            if (franchise != null) {
                FranchiseCommands(
                    franchise = franchise,
                    appModel = appModel,
                    onDismiss = dismiss,
                )
            }
        },
    ) {
        MediaRow(
            title = disambiguated(item, ambiguous),
            onClick = { onOpen(item) },
            meta = meta.takeIf { it.isNotEmpty() },
            lead = lead,
            poster = item.portraitArt,
            slot = PosterSize.Row,
            chevron = false,
            separator = separator,
            hint = Copy.Accessibility.opensTheShowHint,
        ) {
            AddControl(
                item = item,
                placement = AddControlPlacement.Row,
                appModel = appModel,
                onAdd = { onAdd(item) },
            )
        }
    }
}

/**
 * The catalogue notices, as footnote lines.
 *
 * `/search` names the outcome per source, and a catalogue that FAILED is not a catalogue with no
 * matches — so the rows that did arrive get a notice above them rather than standing in for the
 * whole answer.
 */
@Composable
private fun Notices(
    messages: List<String>,
    appModel: AppModel,
    modifier: Modifier = Modifier,
) {
    if (messages.isEmpty()) return
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(ThemeSpace.x2)) {
        messages.forEach { message ->
            InlineNotice(message = message, onRetry = { appModel.retrySearch() })
        }
    }
}

/**
 * "Showing results for “x”" with the literal search one tap away.
 *
 * Drawn only over a POPULATED list — a zero-result correction never reaches the screen, because the
 * server only returns a corrected query when the rewrite actually found something. A search for
 * "one pieceszz" used to show a flat "No results" while the backend had already worked out what was
 * meant.
 */
@Composable
private fun CorrectionLine(
    correction: String,
    original: String,
    onSearchLiterally: () -> Unit,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = ThemeMetrics.gutter)
            .padding(top = ThemeMetrics.sectionGap),
    ) {
        BasicText(
            text = Copy.Search.showingResultsFor(correction),
            style = ThemeType.metadata.copy(color = ThemeColor.textSecondary),
        )
        InlineLinkButton(
            label = Copy.Search.searchInsteadFor(original),
            onClick = onSearchLiterally,
            // The link style pads 12 dp leading to hold its 44-dp target; the pull-back puts the
            // WORD on the gutter.
            modifier = Modifier.negativePadding(start = InlineLink.sideOverhang),
        )
    }
}

// =====================================================================================
// Derivations — every string here comes from `Copy`, and every fact has a rule
// =====================================================================================

/**
 * The result set, plus the titles more than one item shares.
 *
 * Built ONCE per composition: the scan is a regex over every title, and at eight reads of `results`
 * and one scan per row it was running dozens of times per keystroke.
 */
@Immutable
private class ResultSet(val items: List<FranchiseSummary>) {

    /** Normalised titles that more than one item in this set carries. */
    val ambiguous: Set<String> = items
        .groupingBy { normalised(it.title) }
        .eachCount()
        .filterValues { it > 1 }
        .keys

    val isEmpty: Boolean get() = items.isEmpty()

    val count: Int get() = items.size

    companion object {
        private val leadingThe = Regex("^the\\s+")

        fun normalised(title: String): String = title
            .lowercase()
            .replace(leadingThe, "")
            .filter { it.isLetterOrDigit() }
    }
}

/**
 * The one amber, forward-looking fact on a row.
 *
 * The shipped iOS row printed a bare "29 Aug 2:00 PM" as its fourth fact, in the same grey as the
 * year and the season count — a date-time with nothing saying whether it was a premiere, the next
 * episode or the finale, set as though it were trivia. It is the one forward-looking fact on the
 * screen, so it is NAMED, it LEADS the line, and it is the one thing on it in amber.
 *
 * "today" and "tomorrow" are common nouns mid-sentence; a weekday and a month are not.
 */
private fun whenFact(item: FranchiseSummary, now: Long): String? {
    if (!item.isReleasing) return null
    val at = item.nextAiringAt
    if (at == null || at <= now) return Copy.Search.airingNow
    val word = TemporalCopy.airsCompact(at, now, item.source)
    // Root-locale on purpose: these are two fixed English words from the temporal table, not user
    // content, and the device locale must not turn "Today" into a dotless Turkish "ı".
    val cased = if (word == "Today" || word == "Tomorrow") word.lowercase() else word
    return Copy.Search.newEpisode(cased)
}

/**
 * The season count, only where it is true.
 *
 * **AniList prints no count at all.** Its member count asserts something the app disproves two taps
 * later: Search said One Piece had "45 seasons" and One Piece's own screen prints "SEASONS &
 * MOVIES 23". Renaming the number does not fix it — 41 is not 23 under any label, and this is the
 * figure a user checks before adding a 45-"season" show. TMDB keeps its count because there one
 * member genuinely is one season.
 */
private fun sizeFact(item: FranchiseSummary): String? {
    if (item.partCount <= 0 || item.source != MediaSource.TMDB) return null
    return Copy.Search.seasons(item.partCount)
}

/**
 * The grey facts, in priority order.
 *
 * 1. **An owned show leads with its shelf.** The tick alone said "in your library" and never which
 *    of five lists it was on; the status word answers that, in the same vocabulary Library's own
 *    rows use.
 * 2. **Kind next.** A search for "one piece" returns the 1999 anime, the 2023 live-action and the
 *    2027 anime, separated by capitalisation and a year — and there is no other moment where the
 *    kind matters more, because adding the wrong one puts the wrong show in the library.
 * 3. **The year goes when a next-episode date is present** (and when the title already carries it).
 *    They are the same class of fact and the line only holds so much: for a show airing tomorrow,
 *    "1999" is the least useful thing on it.
 */
private fun rowFacts(
    item: FranchiseSummary,
    ambiguous: Set<String>,
    appModel: AppModel,
    now: Long,
): List<String> = buildList {
    appModel.franchise(item.id)?.let { add(Copy.statusLabel(it.effectiveStatus.wire)) }
    add(item.source.kindWord)
    val year = item.year
    if (year != null && whenFact(item, now) == null && !titleCarriesYear(item, ambiguous)) {
        add(year.toString())
    }
    sizeFact(item)?.let { add(it) }
}

/**
 * The recents-row caption: the SAME schema as a row — shelf, then kind — minus the two
 * `whenFact`-dependent suppressions. It carries no lead, so it keeps the year.
 */
private fun shelfFacts(item: FranchiseSummary, appModel: AppModel): List<String> = buildList {
    appModel.franchise(item.id)?.let { add(Copy.statusLabel(it.effectiveStatus.wire)) }
    add(item.source.kindWord)
    item.year?.let { add(it.toString()) }
    sizeFact(item)?.let { add(it) }
}

private fun titleCarriesYear(item: FranchiseSummary, ambiguous: Set<String>): Boolean =
    item.year != null && ambiguous.contains(ResultSet.normalised(item.title))

/**
 * "One Piece (1999)" where the ambiguity is real; the catalogue's own spelling where it is not.
 *
 * A search for "one piece" returns five results whose titles differ only in capitalisation and a
 * definite article, separated by a 13-dp grey line — so "One Piece (Anime · 1999)" and "ONE PIECE
 * (TV · 2023)" read as the same show, and one of them is the wrong one to put in the library. Where
 * the ambiguity is not real the source title is left exactly as the catalogue spells it, because in
 * search the user is matching against what they typed.
 */
private fun disambiguated(item: FranchiseSummary, ambiguous: Set<String>): String {
    val year = item.year
    return if (year != null && titleCarriesYear(item, ambiguous)) "${item.title} ($year)" else item.title
}

/** A WIRE marker, not copy. */
private const val failedMarker = "failed"

/**
 * "Anime results couldn’t refresh" / "TV results couldn’t refresh", filtered by scope — an anime
 * notice over a TV-only list names a failure the user cannot see.
 *
 * An absent `sources` map is "nothing to report", never a failure, and `"disabled"` (the TMDB token
 * unset, i.e. anime-only mode) produces no notice at all.
 */
private fun AppModel.catalogueNotices(): List<String> {
    val sources = searchSources ?: return emptyList()
    return buildList {
        if (sources["anilist"] == failedMarker && matchesMediaFilter(MediaSource.ANILIST)) {
            add(Copy.Notice.searchAnime)
        }
        if (sources["tmdb"] == failedMarker && matchesMediaFilter(MediaSource.TMDB)) {
            add(Copy.Notice.searchTV)
        }
    }
}

/** The scope, not the query, emptied the list. */
private fun AppModel.scopedOut(results: ResultSet): Boolean =
    mediaFilter != MediaFilter.ALL && results.isEmpty && searchResults.isNotEmpty()

/** Speaks the SAME title the visible state shows. */
private fun outcomeTitle(results: ResultSet, appModel: AppModel, query: String): String {
    if (appModel.scopedOut(results)) {
        return EmptyStateCopy.noScopeMatches(
            scope = Copy.Search.scopeWord(appModel.mediaFilter.wire),
            query = query,
        ).title
    }
    if (results.isEmpty) {
        return if (appModel.searchError) {
            (if (SyncCenter.isOnline) EmptyStateCopy.searchUnavailable else EmptyStateCopy.searchFailed).title
        } else {
            EmptyStateCopy.noSearchResults(query).title
        }
    }
    return buildList {
        add(Copy.Search.results(results.count))
        if (appModel.searchError) add(Copy.Search.couldNotRefresh)
        addAll(appModel.catalogueNotices())
    }.joinToString(". ")
}

// =====================================================================================
// The notification primer's persistence and eligibility
// =====================================================================================

/** API 33's runtime notification permission, spelled once. */
private val POST_NOTIFICATIONS: String = Manifest.permission.POST_NOTIFICATIONS

/**
 * Can the OS still be asked?
 *
 * Android has no `notDetermined`, so "we have asked" is tracked in `NotificationPrimer` and
 * combined with three facts about the device:
 *
 * * **below API 33 notifications need no runtime permission**, so the primer simply never appears;
 * * the app must actually DECLARE `POST_NOTIFICATIONS`, or the request returns denied instantly and
 *   the primer would be a card promising a dialog that will never be shown — the exact defect the
 *   whole primer exists to avoid;
 * * the permission must not already be granted.
 */
private fun canAskForNotifications(context: Context): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false
    if (!declaresPostNotifications(context)) return false
    return ContextCompat.checkSelfPermission(context, POST_NOTIFICATIONS) !=
        PackageManager.PERMISSION_GRANTED
}

private fun declaresPostNotifications(context: Context): Boolean = runCatching {
    context.packageManager
        .getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
        .requestedPermissions
        ?.contains(POST_NOTIFICATIONS) == true
}.getOrDefault(false)

// The primer's two flags live on `NotificationPrimer` (`notifications/NotificationPrimer.kt`),
// under the same `@AppStorage` keys iOS uses. They were a private class here, which is how the ask
// came to be armed by ONE of the app's four add paths: see that file's header.


/** Logcat tag for this screen. Matches `PROFILE_LOG_TAG`'s spelling. */
internal const val SEARCH_LOG_TAG = "Search"
