package com.anitrack.app.ui.shell

import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.navigation3.runtime.NavKey
import com.anitrack.app.AppModel
import com.anitrack.app.BuildConfig
import com.anitrack.app.design.FeedbackCoordinator
import com.anitrack.app.design.FeedbackToken
import com.anitrack.app.ui.library.AllTitlesRoute
import com.anitrack.model.AniTrackJson
import com.anitrack.model.WatchStatus
import com.anitrack.model.copy.Copy
import kotlinx.serialization.Serializable

/*
 * THE ROUTING LAYER — the port of `ios/Sources/App/RootView.swift` (`AppTab`, `paths`,
 * `libraryRequest`, `libraryPops`, `detailDestinations`) and `Routing.swift` (`DetailRoute`).
 *
 * The whole model in one sentence: **the back stack is a list this app owns, one per tab.** That is
 * the iOS shape — `MainTabView` holds a `NavigationPath` per tab and pushes onto the ACTIVE one —
 * and it is why Navigation 3 is the library here and `NavController` is not: four of the five
 * requirements below are one line each when you hold the list, and an incantation when a controller
 * holds it for you.
 *
 *   1. a back stack PER TAB, preserved across tab switches;
 *   2. re-selecting the active tab pops that tab to root (and Library also drops All titles, which
 *      is an ITEM destination rather than a stack entry — clearing the stack alone left it standing
 *      and the tap did nothing);
 *   3. Detail is a PLAIN PUSH on the active tab's stack — the `.zoom` transition was tried on
 *      2 Sep and retired on 3 Sep, because it scales the WHOLE destination into the tapped poster,
 *      so for its first 150 ms the show page was a miniature of itself inflating;
 *   4. the alert route REPLACES Today's stack rather than appending to it;
 *   5. system back at a tab root finishes the Activity — it does not switch tabs and does not drop
 *      another tab's stack (PLAN D26). This is why the display is driven by the ACTIVE TAB'S stack
 *      rather than by the four flattened together, which is what the official nav3 recipe does:
 *      flattened, the back gesture at Library's root would walk to Today instead of leaving.
 */

// ---------------------------------------------------------------------------------------------
// The tabs
// ---------------------------------------------------------------------------------------------

/**
 * The four tabs, in bar order.
 *
 * [DISCOVER] is labelled **"Search"** and wears a magnifier, and both halves of that are recorded
 * decisions: *"'Search', the same word the screen's title and the field's prompt use, and the word
 * VoiceOver already speaks for a search-role tab. It said 'Add' — a tab named for one of the things
 * you can do on it, under a magnifier glyph."* It is also an ORDINARY tab, never a search-role
 * island: the field lives under the title on the screen itself (Apple Music's Search).
 */
enum class AppTab {
    TODAY,
    SCHEDULE,
    LIBRARY,
    DISCOVER,
    ;

    /** The bar's word. See [ShellCopy]. */
    val label: String
        get() = when (this) {
            TODAY -> ShellCopy.today
            SCHEDULE -> Copy.Schedule.title
            LIBRARY -> Copy.Library.title
            DISCOVER -> Copy.Search.title
        }

    companion object {
        /**
         * The debug `openTab` extra. `search` is accepted alongside `discover` because the tab is
         * NAMED Search and a capture script written against the label must work.
         */
        fun parse(raw: String?): AppTab? = when (raw?.trim()?.lowercase()) {
            "today" -> TODAY
            "schedule" -> SCHEDULE
            "library" -> LIBRARY
            "discover", "search" -> DISCOVER
            else -> null
        }
    }
}

/**
 * The two words this surface owns.
 *
 * Everything else the shell draws is read from the shared table — the tab labels for Schedule,
 * Library and Search are `Copy.Schedule.title` / `Copy.Library.title` / `Copy.Search.title`, the
 * same strings those screens title themselves with, so a rename can never leave the bar disagreeing
 * with the screen it opens.
 *
 * "Today" is here rather than in `:model` for the reason `AuthCopy` is where it is: a Kotlin object
 * cannot be reopened from `:app`, and `Copy.Schedule.today` is the AGENDA's return control ("Today"
 * meaning day 0), not this tab's name. One table for one surface is still one place; what the copy
 * law forbids is the same sentence living in two.
 */
internal object ShellCopy {

    /** The first tab. The screen has no title of its own — the wordmark is its heading. */
    const val today = "Today"

    /** What a screen reader calls the bar itself. */
    const val tabBar = "Tabs"
}

// ---------------------------------------------------------------------------------------------
// The routes
// ---------------------------------------------------------------------------------------------

/**
 * Every destination in the app.
 *
 * `@Serializable` so a whole shell state — the selected tab and all four stacks — round-trips
 * through `rememberSaveable`. That is not a nicety: **a font-scale change recreates the Activity by
 * design** (there is no `configChanges` in the manifest), and the accessibility capture pass does
 * exactly that with a Detail pushed. The stacks survive because they are saveable, not because
 * recreation was suppressed.
 */
@Serializable
sealed interface Route : NavKey {

    /** A tab's root screen. One per tab, so each tab's root keeps its own saved state. */
    @Serializable
    data class TabRoot(val tab: AppTab) : Route

    /**
     * A show page.
     *
     * The two focus fields are Schedule's deep link — the show page opens AT that episode. They are
     * carried as plain nullable ints rather than as the show page's own `EpisodeFocus` because a
     * route has to survive process death, and the screen's type is the screen's; the router rebuilds
     * one from these.
     *
     * There is no `zoomID` here. On iOS the `zoomSource` registrations stay because they cost
     * nothing and are the hook if a transition that fits ever arrives; on Android there is no zoom
     * transition to hook, so carrying the string in a serialized route would be dead weight in
     * every saved state. Screens may still PASS one — see [ShellNavigator.openDetail].
     */
    @Serializable
    data class Detail(
        val franchiseId: String,
        val focusMediaId: Int? = null,
        val focusEpisode: Int? = null,
    ) : Route

    /** One season's full episode run. */
    @Serializable
    data class SeasonEpisodes(
        val franchiseId: String,
        val mediaId: Int,
        val focusEpisode: Int? = null,
    ) : Route

    /** The show's watch history. */
    @Serializable
    data class WatchHistory(val franchiseId: String) : Route
}

// ---------------------------------------------------------------------------------------------
// The navigator
// ---------------------------------------------------------------------------------------------

/**
 * The tab shell's whole navigation surface: four stacks, the selected tab, and the cross-tab
 * requests that are not stack entries at all.
 *
 * Screens receive this and nothing else. Each method below is one of the callbacks the iOS root
 * passes down (`onOpenDetail`, `onSeeAllWatching`, `onViewAllUpdates`, `onOpenLibrary`,
 * `onAddShow`, `push`), named for what it MEANS rather than for the mutation it performs, so a
 * screen never learns how routing works.
 */
@Stable
class ShellNavigator internal constructor(
    private val model: AppModel,
    initialTab: AppTab,
    restored: Map<AppTab, List<Route>>? = null,
) {

    /**
     * One stack per tab, all four created up front.
     *
     * Eagerly, not lazily: a `get()` that created a tab's list on first read would mutate a plain
     * map during composition, and the four lists cost four allocations at launch.
     */
    private val stacks: Map<AppTab, SnapshotStateList<Route>> = AppTab.entries.associateWith { tab ->
        val saved = restored?.get(tab)?.takeIf { it.isNotEmpty() }
        saved?.toMutableStateList() ?: mutableStateListOf<Route>(Route.TabRoot(tab))
    }

    var tab: AppTab by mutableStateOf(initialTab)
        private set

    /** The ACTIVE tab's stack — what the display renders. See the file header, point 5. */
    val backStack: List<Route> get() = stacks.getValue(tab)

    /**
     * True when the last change was a tab switch rather than a push or a pop.
     *
     * The transition spec reads it to make a tab change an INSTANT CUT: a switch is not navigation
     * and must not slide. (On iOS this is free — a `TabView` cuts and each tab's `NavigationStack`
     * animates its own pushes. Here one display serves all four stacks, so the difference has to be
     * stated.)
     */
    internal var lastChangeWasTabSwitch: Boolean by mutableStateOf(false)
        private set

    /**
     * An All-titles route requested from another tab — Today's "See all", Today's "N updates", the
     * Profile sheet's counts. Library consumes it and calls [consumeAllTitlesRequest]; it is a
     * one-shot, never a standing filter.
     *
     * Deliberately NOT part of the saved state: it is an instruction in flight, and re-issuing it
     * after a process death would re-open a filtered list the user had already left.
     */
    var allTitlesRequest: AllTitlesRoute? by mutableStateOf(null)
        private set

    /**
     * Bumped when the Library tab is re-selected.
     *
     * *"All titles is an item destination, not a path entry, so clearing the path alone left it
     * standing and the tap did nothing."* Library observes this and drops All titles.
     */
    var libraryPops: Int by mutableIntStateOf(0)
        private set

    // MARK: - Tabs

    /**
     * Select a tab, or — when it is already selected — pop that tab to its root.
     *
     * The haptic fires only on an ACTUAL change, never on a pop-to-root: on iOS that falls out of
     * `.onChange(of: selectedTab)` not firing when the value does not change, and the same rule is
     * stated here rather than left to a caller to remember.
     */
    fun select(tab: AppTab) {
        if (tab == this.tab) {
            popToRoot()
            return
        }
        lastChangeWasTabSwitch = true
        this.tab = tab
        FeedbackCoordinator.fire(FeedbackToken.SELECTION)
    }

    /** Re-selecting the active tab. Truncates its stack and, on Library, drops All titles too. */
    fun popToRoot() {
        val stack = stacks.getValue(tab)
        if (stack.size > 1) {
            lastChangeWasTabSwitch = false
            stack.removeRange(1, stack.size)
        }
        if (tab == AppTab.LIBRARY) libraryPops += 1
    }

    // MARK: - Pushes

    /**
     * Open a show page on the CURRENTLY SELECTED tab. A plain push — see the file header, point 3.
     *
     * @param zoomId accepted and ignored. Every screen's iOS call site passes a `zoomID` string for
     *   a transition that was retired; the parameter exists so those call sites port verbatim
     *   rather than each one having to remember that Android never had a zoom to register.
     */
    fun openDetail(franchiseId: String, zoomId: String? = null) {
        push(Route.Detail(franchiseId))
    }

    /** Schedule's route: the same show page, landed on one episode of one season. */
    fun openEpisode(franchiseId: String, mediaId: Int, episode: Int) {
        push(Route.Detail(franchiseId, focusMediaId = mediaId, focusEpisode = episode))
    }

    /** Detail's own pushes: the season's full run, the watch history, a related show. */
    fun push(route: Route) {
        lastChangeWasTabSwitch = false
        stacks.getValue(tab).add(route)
    }

    /** One level back on the active tab. At a root this does NOTHING — see the file header, point 5. */
    fun pop() {
        val stack = stacks.getValue(tab)
        if (stack.size > 1) {
            lastChangeWasTabSwitch = false
            stack.removeAt(stack.lastIndex)
        }
    }

    // MARK: - Cross-tab requests

    /** Today's "See all" on the Watching shelf. */
    fun seeAllWatching() = openAllTitles(status = WatchStatus.WATCHING)

    /**
     * Today's "N updates".
     *
     * Deliberately NOT pinned to Watching: the count is `outNow`, which is any status, so a Paused
     * show that aired would make the number and the list disagree.
     */
    fun viewAllUpdates() = openAllTitles(status = null, unwatchedOnly = true)

    /** The Profile sheet's counts row, and the general form of the two above. */
    fun openAllTitles(status: WatchStatus? = null, unwatchedOnly: Boolean = false) {
        allTitlesRequest = AllTitlesRoute(status = status, unwatchedOnly = unwatchedOnly)
        select(AppTab.LIBRARY)
    }

    /** Library has taken the route. It is a one-shot. */
    fun consumeAllTitlesRequest() {
        allTitlesRequest = null
    }

    /**
     * "Add a show" — from an empty state, or from Today's trending header.
     *
     * It asks for the FIELD, not just the tab: Search consumes `searchFieldRequested` and focuses
     * itself, so the user lands with a caret rather than on a browse grid they then have to tap.
     */
    fun addShow() {
        model.searchFieldRequested = true
        select(AppTab.DISCOVER)
    }

    // MARK: - The alert route

    /**
     * A tapped episode alert (or the `openDetail` capture extra) opens its show **on Today, above
     * whatever was there**.
     *
     * The stack is REPLACED rather than appended to, and the tab is set directly rather than through
     * [select] — this is not the user choosing a tab, so it fires no selection haptic and does not
     * count as a tab switch for the transition spec: the show page slides in as a push, which is
     * what it is.
     */
    internal fun openFromAlert(franchiseId: String) {
        tab = AppTab.TODAY
        lastChangeWasTabSwitch = false
        val stack = stacks.getValue(AppTab.TODAY)
        stack.clear()
        stack.add(Route.TabRoot(AppTab.TODAY))
        stack.add(Route.Detail(franchiseId))
    }

    internal fun snapshot(): Map<AppTab, List<Route>> = stacks.mapValues { it.value.toList() }
}

/**
 * The shell's navigator, surviving both a configuration change and process death.
 *
 * `rememberSaveable` rather than `remember`, for the reason [Route] carries: a font-scale change
 * recreates the Activity, and a Detail the user was reading must still be there afterwards. The
 * state is encoded as one JSON string, which is what makes it Bundle-safe without a Parcelize
 * dependency.
 */
@Composable
fun rememberShellNavigator(model: AppModel, initialTab: AppTab): ShellNavigator {
    val saver = remember(model) {
        Saver<ShellNavigator, String>(
            save = { nav ->
                runCatching {
                    AniTrackJson.encodeToString(
                        SavedShell.serializer(),
                        SavedShell(
                            tab = nav.tab,
                            stacks = nav.snapshot().mapKeys { it.key.name },
                        ),
                    )
                }.getOrNull()
            },
            restore = { encoded ->
                val saved = runCatching {
                    AniTrackJson.decodeFromString(SavedShell.serializer(), encoded)
                }.getOrNull()
                ShellNavigator(
                    model = model,
                    initialTab = saved?.tab ?: initialTab,
                    restored = saved?.stacks?.mapNotNull { (name, routes) ->
                        AppTab.entries.firstOrNull { it.name == name }?.let { it to routes }
                    }?.toMap(),
                )
            },
        )
    }
    return rememberSaveable(saver = saver) { ShellNavigator(model, initialTab) }
}

@Serializable
private data class SavedShell(
    val tab: AppTab,
    val stacks: Map<String, List<Route>>,
)

// ---------------------------------------------------------------------------------------------
// Intent extras
// ---------------------------------------------------------------------------------------------

/**
 * The keys the launcher Activity reads.
 *
 * They are the iOS launch arguments, letter for letter, so **one capture script drives both
 * platforms**: `-openTab library` becomes `adb shell am start -e openTab library`.
 */
object ShellIntents {

    /**
     * The show to open — the alert route AND the debug route, deliberately the same key.
     *
     * The notification layer builds its `PendingIntent` with this extra (and `FLAG_IMMUTABLE`), so
     * what the capture script photographs is exactly what a user's tap produces and the route
     * cannot rot unnoticed.
     */
    const val EXTRA_OPEN_DETAIL = "openDetail"

    const val EXTRA_OPEN_TAB = "openTab"
    const val EXTRA_OPEN_PROFILE = "openProfile"
    const val EXTRA_OPEN_ALL_TITLES = "openAllTitles"
    const val EXTRA_OPEN_SEARCH_FIELD = "openSearchField"
    const val EXTRA_RECAP_DEMO = "recapDemo"
    const val EXTRA_CALM_DEMO = "calmDemo"
    const val EXTRA_SCHEDULE_EARLIER = "scheduleEarlier"
    const val EXTRA_SCHEDULE_FILTER = "scheduleFilter"
    const val EXTRA_SCHEDULE_HIDE_WATCHED = "scheduleHideWatched"
    const val EXTRA_DETAIL_ANCHOR = "detailAnchor"
    const val EXTRA_DETAIL_TRAILER = "detailTrailer"
    const val EXTRA_DETAIL_OPEN_RELATED = "detailOpenRelated"

    /** Read by the sign-in gate itself (`ui/auth/SignInScreen.kt`), not by the shell. */
    const val EXTRA_DEV_SIGN_IN_ID = "devSignInId"
    const val EXTRA_DEV_SIGN_IN_AUTO = "devSignInAuto"
}

/**
 * The debug launch arguments, resolved once per intent and published to the tree.
 *
 * **The whole design-QA loop depends on these.** Without `devSignInAuto` no screenshot of a
 * populated screen can be taken unattended, and without the rest the app cannot be posed: the
 * capture script drives every state through them and never touches the UI by coordinate, so the
 * matrix survives layout changes.
 *
 * Each flag is read by the screen that owns the state it poses, exactly as iOS reads
 * `UserDefaults.standard` from the view that owns it — which is why this is a composition local
 * rather than seven parameters threaded through the shell.
 *
 * **`adb shell am start -e <key> <value>` sets a STRING extra**, so every boolean here accepts both
 * a real boolean (`--ez`) and the strings `1`/`true`. A reader that only asked
 * `getBooleanExtra(...)` would silently ignore the entire capture script.
 */
@androidx.compose.runtime.Immutable
data class DebugLaunch(
    val openTab: AppTab? = null,
    /** Opens the Profile sheet on Today's appearance. */
    val openProfile: Boolean = false,
    /** One-shot: Library opens All titles. The latch is Library's — `onAppear` fires again on pop. */
    val openAllTitles: Boolean = false,
    /** Search opens with the field focused. */
    val openSearchField: Boolean = false,
    /** Today forces the full Previously Recap. */
    val recapDemo: Boolean = false,
    /** Today's focus stack is emptied, so the calm open renders over a library WITH backlog. */
    val calmDemo: Boolean = false,
    /** Schedule opens with the Earlier block already unfolded. */
    val scheduleEarlier: Boolean = false,
    /** `anime` | `tv`; anything else is "all". The mapping belongs to Schedule, so this is raw. */
    val scheduleFilter: String? = null,
    /** Schedule opens with watched episodes hidden. */
    val scheduleHideWatched: Boolean = false,
    /** `trailers` | `people` | `related` | `watch` — Detail scrolls that shelf to the top. */
    val detailAnchor: String? = null,
    /** Detail opens the first trailer's sheet. */
    val detailTrailer: Boolean = false,
    /** Detail opens the Nth related title (bounds-checked by Detail). */
    val detailOpenRelated: Int? = null,
) {
    companion object {

        /** A release build, and any launch with no extras. */
        val None = DebugLaunch()

        /**
         * Reads the extras. **Release builds get [None] and nothing is parsed at all** —
         * `BuildConfig.DEBUG` is a compile-time constant, so R8 deletes the branch and everything
         * only it reaches. A runtime `FLAG_DEBUGGABLE` test would leave the whole debug surface in
         * the shipped APK.
         */
        fun from(intent: Intent?): DebugLaunch {
            if (!BuildConfig.DEBUG || intent == null) return None
            return DebugLaunch(
                openTab = AppTab.parse(intent.getStringExtra(ShellIntents.EXTRA_OPEN_TAB)),
                openProfile = intent.flag(ShellIntents.EXTRA_OPEN_PROFILE),
                openAllTitles = intent.flag(ShellIntents.EXTRA_OPEN_ALL_TITLES),
                openSearchField = intent.flag(ShellIntents.EXTRA_OPEN_SEARCH_FIELD),
                recapDemo = intent.flag(ShellIntents.EXTRA_RECAP_DEMO),
                calmDemo = intent.flag(ShellIntents.EXTRA_CALM_DEMO),
                scheduleEarlier = intent.flag(ShellIntents.EXTRA_SCHEDULE_EARLIER),
                scheduleFilter = intent.getStringExtra(ShellIntents.EXTRA_SCHEDULE_FILTER)
                    ?.trim()?.lowercase()?.takeIf { it.isNotEmpty() },
                scheduleHideWatched = intent.flag(ShellIntents.EXTRA_SCHEDULE_HIDE_WATCHED),
                detailAnchor = intent.getStringExtra(ShellIntents.EXTRA_DETAIL_ANCHOR)
                    ?.trim()?.lowercase()?.takeIf { it.isNotEmpty() },
                detailTrailer = intent.flag(ShellIntents.EXTRA_DETAIL_TRAILER),
                detailOpenRelated = intent.index(ShellIntents.EXTRA_DETAIL_OPEN_RELATED),
            )
        }

        /** `--ez key true`, `-e key true` and `-e key 1` all mean the same thing. */
        private fun Intent.flag(key: String): Boolean =
            getBooleanExtra(key, false) ||
                getStringExtra(key)?.trim()?.lowercase() in TRUTHY

        /** `--ei key 2` and `-e key 2` both mean 2. Negative and unparseable read as absent. */
        private fun Intent.index(key: String): Int? {
            val fromInt = getIntExtra(key, -1)
            if (fromInt >= 0) return fromInt
            return getStringExtra(key)?.trim()?.toIntOrNull()?.takeIf { it >= 0 }
        }

        private val TRUTHY = setOf("1", "true")
    }
}

/**
 * The launch flags, for the screen that owns the state each one poses.
 *
 * `static`, because it changes at most once per intent and a change should re-pose the whole app.
 */
val LocalDebugLaunch = staticCompositionLocalOf { DebugLaunch.None }

/** `List<Route>` → a `SnapshotStateList` the navigator can mutate. */
private fun List<Route>.toMutableStateList(): SnapshotStateList<Route> =
    mutableStateListOf<Route>().also { it.addAll(this) }
