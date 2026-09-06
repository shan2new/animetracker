package com.anitrack.app.ui.shell

import androidx.compose.animation.AnimatedContentTransitionScope
import androidx.compose.animation.Crossfade
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.ui.NavDisplay
import com.anitrack.app.AppModel
import com.anitrack.app.data.SyncCenter
import com.anitrack.app.data.api.ApiClient
import com.anitrack.app.data.auth.AuthManager
import com.anitrack.app.design.LocalReduceMotion
import com.anitrack.app.design.brand.LaunchHandoff
import com.anitrack.app.design.brand.LocalLaunchHandoff
import com.anitrack.app.design.MotionToken
import com.anitrack.app.design.PreviouslyMaterialBridge
import com.anitrack.app.design.ProvideControlInk
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeMotion
import com.anitrack.app.design.motion
import com.anitrack.app.ui.auth.SignInScreen
import com.anitrack.app.ui.chrome.PushedScreenChrome
import com.anitrack.app.ui.detail.ApiClientDetailApi
import com.anitrack.app.ui.detail.DetailDebugArgs
import com.anitrack.app.ui.detail.DetailPush
import com.anitrack.app.ui.detail.DetailScreen
import com.anitrack.app.ui.detail.EpisodeFocus
import com.anitrack.app.ui.detail.SeasonEpisodesScreen
import com.anitrack.app.ui.detail.WatchHistoryScreen
import com.anitrack.app.ui.discover.DiscoverScreen
import com.anitrack.app.ui.library.LibraryScreen
import com.anitrack.app.ui.profile.ProfileScreen
import com.anitrack.app.ui.schedule.ScheduleScreen
import com.anitrack.app.ui.state.ToastHost
import com.anitrack.app.ui.today.TodayScreen
import com.anitrack.model.Formatting
import com.anitrack.model.TemporalCopy
import com.anitrack.model.WatchStatus
import com.anitrack.model.copy.CopyDates

/*
 * THE ROOT — the port of `ios/Sources/App/RootView.swift`.
 *
 * Two things live here and nothing else does: **the gate** (splash → sign-in or app) and **the
 * shell** (four tabs, one navigation display, the toast layer, the Profile sheet).
 *
 * THE GATE'S ONE RULE, and it is the reason the whole file exists:
 *
 *   "The splash leaves when its timeline is done AND auth knows whether there is a session — so the
 *    screen it reveals is the right one, never sign-in for a signed-in user."
 *
 * `AuthManager.bootstrap()` waits up to 3 s for Clerk to restore a session, so on a cold launch
 * over a slow network the ident rests past its own beats rather than flashing the sign-in screen
 * at a returning user. The ident reads that answer through `LaunchHandoff.authReady`, set below.
 */

/**
 * The gate and the shell.
 *
 * @param onReadyToDraw called on the first composition. The SYSTEM splash is held until it fires,
 *   and the ident's first frame is that splash's own picture, so the platform's launch frame and
 *   this app's ident are one continuous image rather than two splashes.
 */
@Composable
fun RootScreen(
    auth: AuthManager,
    model: AppModel,
    client: ApiClient,
    modifier: Modifier = Modifier,
    onReadyToDraw: () -> Unit = {},
) {
    LaunchedEffect(Unit) { onReadyToDraw() }

    // The ≤3 s wait for Clerk. iOS runs it from the scene's `.task`; the root is the same place.
    LaunchedEffect(auth) { auth.bootstrap() }

    val signedIn by auth.isSignedIn.collectAsState()
    val bootstrapped by auth.bootstrapped.collectAsState()

    // Saveable: an Activity recreation (a font-scale change, which the manifest deliberately does
    // not suppress) must not replay the launch over an app the user is already using.
    var launchDone by rememberSaveable { mutableStateOf(false) }
    val launch = LocalLaunchHandoff.current ?: remember { LaunchHandoff() }

    // The ident waits for auth's first answer before it leaves, so the screen it reveals is the
    // right one — never sign-in for a signed-in user.
    LaunchedEffect(bootstrapped) { if (bootstrapped) launch.authReady = true }

    // The surface is the user's to read once the app starts emerging: Today's page-in (rise only —
    // the emergence is the fade) and the recap clock wait on this.
    LaunchedEffect(launchDone) { if (launchDone) model.surfaceReady = true }

    // `.task(id: auth.isSignedIn)` — the library load starts the instant a session exists, BEHIND
    // the ident, so a signed-in launch has content by the time the ident leaves.
    //
    // The teardown half may run only on a real sign-OUT, never on the first composition of a
    // signed-out launch: `teardown()` clears the restored failed changes, and discarding writes the
    // previous session is still owed would be a silent data loss at launch.
    var wasSignedIn by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(signedIn) {
        if (signedIn) {
            wasSignedIn = true
            model.start()
        } else if (wasSignedIn) {
            wasSignedIn = false
            // "Sign-out is the one moment the model outlives its account: the library, the live
            // clock, pending episode alerts and a running Live Activity all survive the view tree."
            model.teardown()
        }
    }

    Box(modifier.fillMaxSize().background(ThemeColor.canvas)) {

        // The app is laid out under the ident from the first frame and EMERGES through it: a hair
        // small while the ident holds, settling to full size as the ident pushes through and fades
        // off it. It is never faded itself — an alpha ramp over the whole tree is an offscreen
        // pass on every frame; the ident's two layers fading is the same picture for the price
        // of two layers. Under Reduce Motion nothing scales.
        val reduceMotion = LocalReduceMotion.current
        val emerge by animateFloatAsState(
            targetValue = if (launch.emerging || launchDone || reduceMotion) 1f else EMERGE_SCALE,
            animationSpec = motion(MotionToken.UI_SETTLE),
            label = "launchEmerge",
        )
        Box(
            Modifier
                .fillMaxSize()
                .graphicsLayer {
                    scaleX = emerge
                    scaleY = emerge
                },
        ) {
            Crossfade(
                targetState = signedIn,
                animationSpec = motion(MotionToken.UI_GENTLE),
                label = "authGate",
            ) { inside ->
                if (inside) {
                    MainTabs(model = model, auth = auth, client = client, launch = launch)
                } else {
                    SignInScreen(auth = auth)
                }
            }
        }

        if (!launchDone) {
            LaunchIdent(
                handoff = launch,
                onLeaving = { model.surfaceReady = true },
                onFinished = {
                    launchDone = true
                    launch.finished = true
                },
            )
        }
    }
}

/** The app under the ident: a hair small, so it comes forward as the ident pushes through. */
private const val EMERGE_SCALE = 0.96f

// ---------------------------------------------------------------------------------------------
// The shell
// ---------------------------------------------------------------------------------------------

/**
 * Four tabs, one navigation display, the toast layer and the Profile sheet.
 *
 * The z-order is fixed and each layer is where it is for a reason: the screens draw their own
 * scroll-edge chrome (which over-draws 180 dp of opaque canvas past the bottom of the layout), the
 * bar sits on that canvas without insetting anything, and the toast floats above the bar because it
 * is the one thing that must never be underneath it.
 */
@Composable
private fun MainTabs(
    model: AppModel,
    auth: AuthManager,
    client: ApiClient,
    launch: LaunchHandoff,
) {
    val debug = LocalDebugLaunch.current
    val reduceMotion = LocalReduceMotion.current
    val nav = rememberShellNavigator(model, initialTab = debug.openTab ?: AppTab.TODAY)
    val identity by auth.identityFlow.collectAsState()
    val detailApi = remember(client) { ApiClientDetailApi(client) }

    // ONE freshness source for every stale strip and Profile's sync line. Until this closure is
    // installed nothing can be stale and Profile reads "Not synced yet" — the honest reading of
    // "this build has no freshness source wired", never a silent claim of freshness.
    //
    // It is NOT torn down on dispose: the model outlives this composition (an Activity recreation
    // rebuilds the tree, not the process), and a null `signals` between the two would make every
    // stale strip claim ignorance for a frame.
    val context = LocalContext.current
    DisposableEffect(model) {
        SyncCenter.signals = { SyncCenter.Signals(model.lastLoadedAt, model.loading) }
        SyncCenter.startMonitoring(context)
        onDispose { }
    }

    // THE ALERT ROUTE. A tapped episode alert — and the `openDetail` capture extra, which is the
    // same door — opens its show on Today, ABOVE whatever was there.
    //
    // Read through `snapshotFlow` rather than as a composable read: `pendingOpen` would otherwise
    // recompose the whole shell every time it is set and cleared.
    LaunchedEffect(model, nav) {
        snapshotFlow { model.pendingOpen }.collect { id ->
            if (id == null) return@collect
            model.pendingOpen = null
            nav.openFromAlert(id)
        }
    }

    var showProfile by rememberSaveable { mutableStateOf(false) }

    // The page-in transition runs ONCE PER TAB, and this is where "once" is remembered: replaying it
    // on every switch turned an ordinary tab change into a 0.42 s loading beat, when what a native
    // tab promises after the first landing is an instant cut.
    val landed = rememberSaveable(
        saver = listSaver<MutableList<String>, String>(
            save = { it.toList() },
            restore = { restored -> mutableStateListOf<String>().apply { addAll(restored) } },
        ),
    ) { mutableStateListOf<String>() }

    Box(Modifier.fillMaxSize()) {

        // Layer 1 — the screens. Ink again inside the host: the bar's amber stops at the bar, so a
        // back glyph, an alert's buttons and a search caret are all `interactive`.
        ProvideControlInk(ThemeColor.interactive) {
            NavDisplay(
                backStack = nav.backStack,
                modifier = Modifier.fillMaxSize(),
                onBack = { nav.pop() },
                // A plain push. The `.zoom` transition was tried and retired — it scaled the whole
                // destination into the tapped poster, so the show page opened as a miniature of
                // itself inflating. A TAB SWITCH is not navigation and gets no transition at all.
                transitionSpec = {
                    if (nav.lastChangeWasTabSwitch) {
                        EnterTransition.None togetherWith ExitTransition.None
                    } else {
                        pushEnter(reduceMotion) togetherWith pushExit(reduceMotion)
                    }
                },
                popTransitionSpec = { popEnter(reduceMotion) togetherWith popExit(reduceMotion) },
                // `clazzContentKey` is nav3's own name for the parameter on
                // `EntryProviderScope.entry` (1.1.7); `contentKey` is what `NavEntry`'s
                // CONSTRUCTOR calls the same thing, and writing that here does not compile.
                //
                // Each one is written out rather than left to `defaultContentKey`, whose value is
                // the route's own `toString()`: this is the identity Compose saves state against,
                // so on the default a field ADDED to a route — one more capture flag on
                // `Route.Detail` — would silently change every show page's key and drop the scroll
                // position of the page the user was reading. Spelled out, the key names the
                // destination and changes only when someone means it to.
                //
                // The content lambda is handed the KEY. It is bound as `key` rather than left as a
                // bare `it` because these bodies run to twenty lines and the noun has to survive
                // the distance.
                entryProvider = entryProvider<Route> {

                    entry<Route.TabRoot>(clazzContentKey = { "root/${it.tab.name}" }) { key ->
                        PageIn(tab = key.tab, landed = landed, ready = model.surfaceReady, fadeIn = launch.finished) {
                            when (key.tab) {
                                AppTab.TODAY -> TodayScreen(
                                    appModel = model,
                                    identity = identity,
                                    onOpenDetail = { id -> nav.openDetail(id) },
                                    onSeeAllWatching = { nav.seeAllWatching() },
                                    // Deliberately not pinned to Watching: the count is `outNow`,
                                    // which is any status.
                                    onViewAllUpdates = { nav.viewAllUpdates() },
                                    onAddShow = { nav.addShow() },
                                    onOpenProfile = { showProfile = true },
                                )

                                AppTab.SCHEDULE -> ScheduleScreen(
                                    appModel = model,
                                    dates = PreviouslyDates,
                                    // A Schedule row carries the episode it names, so the show page
                                    // opens AT it rather than at the top.
                                    onOpenDetail = { id, mediaId, episode ->
                                        nav.openEpisode(id, mediaId = mediaId, episode = episode)
                                    },
                                    onAddShow = { nav.addShow() },
                                )

                                AppTab.LIBRARY -> LibraryScreen(
                                    appModel = model,
                                    dates = PreviouslyDates,
                                    onOpenDetail = { id -> nav.openDetail(id) },
                                    onAddShow = { nav.addShow() },
                                    requestedAll = nav.allTitlesRequest,
                                    onRequestedAllHandled = { nav.consumeAllTitlesRequest() },
                                    // All titles is an ITEM destination inside Library, not a stack
                                    // entry, so clearing the stack alone would leave it standing and
                                    // the tab tap would do nothing. This is what it listens to.
                                    popSignal = nav.libraryPops,
                                    openAllTitlesOnLaunch = debug.openAllTitles,
                                )

                                AppTab.DISCOVER -> DiscoverScreen(
                                    appModel = model,
                                    onOpenDetail = { id -> nav.openDetail(id) },
                                )
                            }
                        }
                    }

                    // The three pushed destinations get `PushedScreenChrome` HERE rather than each
                    // opting in — "so every future push inherits it". The tab roots got their
                    // bottom chrome and the pushed screens did not, so Detail, its episode list and
                    // Watch history each drew whole rows at full opacity under the bottom bar, with
                    // no opaque canvas for the bar to sit on. Their top edge is deliberately
                    // untouched: a pushed screen draws its own bar and owns that edge.

                    entry<Route.Detail>(
                        clazzContentKey = { "detail/${it.franchiseId}/${it.focusMediaId}/${it.focusEpisode}" },
                    ) { key ->
                        PushedScreenChrome {
                            DetailScreen(
                                franchiseId = key.franchiseId,
                                appModel = model,
                                api = detailApi,
                                push = { push -> nav.push(push.asRoute()) },
                                onBack = { nav.pop() },
                                focus = key.focus(),
                                debug = debug.detailArgs(),
                            )
                        }
                    }

                    entry<Route.SeasonEpisodes>(
                        clazzContentKey = { "season/${it.franchiseId}/${it.mediaId}" },
                    ) { key ->
                        PushedScreenChrome {
                            SeasonEpisodesScreen(
                                franchiseId = key.franchiseId,
                                mediaId = key.mediaId,
                                appModel = model,
                                api = detailApi,
                                onBack = { nav.pop() },
                                focusEpisode = key.focusEpisode,
                            )
                        }
                    }

                    entry<Route.WatchHistory>(
                        clazzContentKey = { "history/${it.franchiseId}" },
                    ) { key ->
                        PushedScreenChrome {
                            WatchHistoryScreen(
                                franchiseId = key.franchiseId,
                                appModel = model,
                                onBack = { nav.pop() },
                            )
                        }
                    }
                },
            )
        }

        // Layer 2 — the bar. It draws OVER the content on the opaque canvas the bottom chrome
        // over-draws for it; nothing here insets a screen.
        PreviouslyTabBar(
            selected = nav.tab,
            onSelect = nav::select,
            modifier = Modifier.align(Alignment.BottomCenter),
        )

        // Layer 3 — the toast stack.
        ShellToasts(model = model, modifier = Modifier.align(Alignment.BottomCenter))
    }

    if (showProfile) {
        ProfileSheet(
            model = model,
            auth = auth,
            onDismiss = { showProfile = false },
            onOpenLibrary = { status ->
                showProfile = false
                nav.openAllTitles(status = status)
            },
            onOpenDetail = { id ->
                showProfile = false
                nav.openDetail(id)
            },
        )
    }
}

/**
 * The shared toast layer, above the bar because it is the one thing that may never be underneath
 * it.
 *
 * **It is its own composable so that the shell is not.** Four channels change here — a failed
 * write, an error, a receipt, an undo — and every one of them is a snapshot read; made in
 * `MainTabs`'s own body they would recompose the shell, and with it the navigation display, every
 * time a toast arrived or left. Only this composable reads them, so only this composable re-runs.
 *
 * ### The clearance
 *
 * Composed from what is actually on screen — the bar's own height, the LIVE system inset, and one
 * gap — rather than from `ThemeMetrics.toastClearance`, whose 62 is iOS's window-relative constant
 * (a 52-pt bar plus 10) and knows nothing about a gesture strip that is 24 dp on one device and 48
 * on another. The rule it encodes is what ports: the toast clears the bar, and the failure it
 * exists to prevent is measured — a 12-pt pad put the toast at 858–935 against a tab pill at
 * 873–935, covering the bar outright, and on Search it covered the field with the user's own query
 * still in it.
 *
 * The side margin is the app's own [ThemeMetrics.gutter]. iOS matches the tab bar's 22-pt margin
 * instead, because iOS's bar is a floating pill with a margin to match; an Android bar is full
 * width and has none, so the honest equivalent is the margin every other floating thing in the app
 * aligns to.
 */
@Composable
private fun ShellToasts(model: AppModel, modifier: Modifier = Modifier) {
    val navBarInset = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()

    ToastHost(
        // Profile lists every failed change with its own Retry and Discard, so the banner there
        // would be a duplicate of the screen being read. That is the CALLER's decision, not the
        // host's — `SyncCenter.profileIsOpen` "existed for exactly this and nothing read it".
        syncFailureCount = if (SyncCenter.profileIsOpen) 0 else SyncCenter.failedChanges.size,
        syncRetryAvailable = SyncCenter.canRetryAny,
        onRetrySync = { SyncCenter.retryAll() },
        onDiscardSync = { SyncCenter.discardAll() },
        // The lane's one item (a failure, a lane-placed undo, a notice); a mark's receipt lands in
        // place under its control instead.
        laneItem = model.laneItem,
        onUndo = { model.undoTapped(it) },
        modifier = modifier
            .padding(horizontal = ThemeMetrics.gutter)
            .padding(bottom = ThemeMetrics.bottomChromeHeight + navBarInset + ThemeMetrics.cardGap),
    )
}

/**
 * Profile, presented as a near-full-height sheet.
 *
 * iOS presents it as a `.sheet` from Today's account disc; a sheet is the Android idiom for the
 * same thing, and the same downward drag dismisses it — which is why the screen deliberately has no
 * pull-to-refresh.
 *
 * `dragHandle = null`: the sheet's drag handle is one of the four material3 components that
 * construct their own ripple with no way to null it, and the screen draws its own bar with its own
 * Done control anyway.
 *
 * The opt-in sits on THIS function rather than on the file: `ModalBottomSheet`, `SheetState` and
 * `rememberModalBottomSheetState` are all still `@ExperimentalMaterial3Api` in material3 1.4.0, and
 * this is the only thing in the root that touches them. A file-level `@file:OptIn` would silence a
 * future experimental call anywhere in the gate or the shell — the same reason every other sheet in
 * the app (`VideoSheet`, Detail's, Library's) carries the annotation on the composable itself.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProfileSheet(
    model: AppModel,
    auth: AuthManager,
    onDismiss: () -> Unit,
    onOpenLibrary: (WatchStatus) -> Unit,
    onOpenDetail: (String) -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    PreviouslyMaterialBridge {
        ModalBottomSheet(
            onDismissRequest = onDismiss,
            sheetState = sheetState,
            containerColor = ThemeColor.canvas,
            contentColor = ThemeColor.textPrimary,
            scrimColor = ThemeColor.scrim,
            dragHandle = null,
        ) {
            ProfileScreen(
                appModel = model,
                auth = auth,
                onDismiss = onDismiss,
                onOpenLibrary = onOpenLibrary,
                onOpenDetail = onOpenDetail,
                // The sheet has already inset itself past the status bar.
                topInset = 0.dp,
            )
        }
    }
}

// ---------------------------------------------------------------------------------------------
// The page-in transition
// ---------------------------------------------------------------------------------------------

/**
 * A tab's content fades in and rises 6 dp — ONCE, the first time that tab is landed on.
 *
 * *"It runs ONCE per tab: replaying it on every switch turned ordinary tab changes into a 0.42 s
 * loading beat, so after the first landing a switch is the instant cut native tabs promise."*
 *
 * And the travel is 6, not 10: *"at 10 the first landing reads as content sliding into place, which
 * is a loading beat; at 6 it reads as the screen coming into focus."* Under Reduce Motion it is a
 * pure crossfade — the fade still says "this is new", the travel is what is dropped.
 */
@Composable
private fun PageIn(
    tab: AppTab,
    landed: MutableList<String>,
    ready: Boolean,
    fadeIn: Boolean,
    content: @Composable () -> Unit,
) {
    val reduceMotion = LocalReduceMotion.current
    val already = remember(tab) { landed.contains(tab.name) }
    var shown by remember(tab) { mutableStateOf(already) }

    // The first landing waits for the launch: the tab arrives as the ident's ground lifts, not
    // underneath it.
    // The first landing waits for the launch: the tab arrives as the ident pushes through, not
    // underneath it.
    LaunchedEffect(tab, ready) {
        if (!already && ready) {
            landed.add(tab.name)
            shown = true
        }
    }

    val progress by animateFloatAsState(
        targetValue = if (shown) 1f else 0f,
        animationSpec = motion(MotionToken.UI_REVEAL),
        label = "pageIn",
    )

    // The launch's arrival is the app emerging through the ident, so that page-in only rises:
    // an alpha ramp over the whole hero tree is an offscreen pass on every frame.
    Box(
        Modifier.graphicsLayer {
            alpha = if (fadeIn) progress else 1f
            translationY = if (reduceMotion) 0f else (1f - progress) * PAGE_IN_TRAVEL * density
        },
    ) {
        content()
    }
}

/** 6 dp. See [PageIn] — 10 read as a loading beat. */
private const val PAGE_IN_TRAVEL = 6f

// ---------------------------------------------------------------------------------------------
// The push transition
// ---------------------------------------------------------------------------------------------
//
// The system slide, driven by tokens rather than by nav3's own 700 ms default. Predictive back is
// left entirely to `NavDisplay`, which drives the pop with the gesture's own progress — that is the
// Android reflex this port deliberately adopts, and it is why there is no `predictivePopTransitionSpec`
// here: the default IS the platform's.

private fun AnimatedContentTransitionScope<*>.pushEnter(reduceMotion: Boolean) =
    if (reduceMotion) {
        fadeIn(ThemeMotion.uiReduced())
    } else {
        slideIntoContainer(
            towards = AnimatedContentTransitionScope.SlideDirection.Start,
            animationSpec = ThemeMotion.uiReveal(),
        ) + fadeIn(ThemeMotion.uiReveal())
    }

private fun AnimatedContentTransitionScope<*>.pushExit(reduceMotion: Boolean) =
    if (reduceMotion) {
        fadeOut(ThemeMotion.uiReduced())
    } else {
        slideOutOfContainer(
            towards = AnimatedContentTransitionScope.SlideDirection.Start,
            animationSpec = ThemeMotion.uiReveal(),
        ) + fadeOut(ThemeMotion.uiGentle())
    }

private fun AnimatedContentTransitionScope<*>.popEnter(reduceMotion: Boolean) =
    if (reduceMotion) {
        fadeIn(ThemeMotion.uiReduced())
    } else {
        slideIntoContainer(
            towards = AnimatedContentTransitionScope.SlideDirection.End,
            animationSpec = ThemeMotion.uiReveal(),
        ) + fadeIn(ThemeMotion.uiGentle())
    }

private fun AnimatedContentTransitionScope<*>.popExit(reduceMotion: Boolean) =
    if (reduceMotion) {
        fadeOut(ThemeMotion.uiReduced())
    } else {
        slideOutOfContainer(
            towards = AnimatedContentTransitionScope.SlideDirection.End,
            animationSpec = ThemeMotion.uiReveal(),
        ) + fadeOut(ThemeMotion.uiReveal())
    }

// ---------------------------------------------------------------------------------------------
// Routing translations
// ---------------------------------------------------------------------------------------------

/** Detail's own pushes, as stack routes. */
private fun DetailPush.asRoute(): Route = when (this) {
    is DetailPush.Episodes -> Route.SeasonEpisodes(franchiseId, mediaId, focusEpisode)
    is DetailPush.History -> Route.WatchHistory(franchiseId)
    is DetailPush.Detail -> Route.Detail(franchiseId)
}

/**
 * The route's focus, rebuilt as Detail's own type.
 *
 * The route carries two nullable ints rather than an `EpisodeFocus` because it is `@Serializable`
 * and survives process death; the screen's type is the one the screen reads.
 */
private fun Route.Detail.focus(): EpisodeFocus? {
    val media = focusMediaId ?: return null
    val episode = focusEpisode ?: return null
    return EpisodeFocus(mediaId = media, episode = episode)
}

/** The capture driver's arguments, in the shape the show page reads them. */
private fun DebugLaunch.detailArgs(): DetailDebugArgs? =
    if (detailAnchor == null && !detailTrailer && detailOpenRelated == null) {
        null
    } else {
        DetailDebugArgs(
            anchor = detailAnchor,
            trailer = detailTrailer,
            openRelated = detailOpenRelated,
        )
    }

// ---------------------------------------------------------------------------------------------
// Dates
// ---------------------------------------------------------------------------------------------

/**
 * THE app's [CopyDates] — the five date facts the copy table needs from the time layer, in the
 * mapping the interface's own documentation prescribes.
 *
 * It lives at the root because the root is what hands it to the screens that take one (Schedule,
 * Library, All titles, the stale strip), and because **two implementations of this would be two
 * spellings of one date**: the copy table's job is that a date is written once, and a second
 * mapping is exactly how "31 Mar, 2013" gets re-invented on one screen.
 */
object PreviouslyDates : CopyDates {

    override fun dayDiff(ts: Long, now: Long): Int =
        Formatting.dayDiff(ts, now, Formatting.TimeAnchor.LOCAL)

    override fun weekdayName(ts: Long): String =
        Formatting.weekdayNameMonFirst(Formatting.localMondayCol(ts))

    override fun dateWord(ts: Long, now: Long): String =
        TemporalCopy.dateWord(ts, now, Formatting.TimeAnchor.LOCAL)

    override fun monthDay(ts: Long): String = Formatting.fmtMonthDay(ts)

    override fun year(ts: Long): Int = Formatting.localParts(ts).y
}
