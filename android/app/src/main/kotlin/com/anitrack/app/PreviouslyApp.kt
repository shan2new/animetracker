package com.anitrack.app

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.staticCompositionLocalOf
import coil3.ImageLoader
import com.anitrack.app.data.AppConfig
import com.anitrack.app.data.CompositeAmbientSync
import com.anitrack.app.data.LibraryCache
import com.anitrack.app.data.RecentsStore
import com.anitrack.app.data.RewatchStore
import com.anitrack.app.data.SyncCenter
import com.anitrack.app.data.api.ApiClient
import com.anitrack.app.data.api.ApiClientErrorTaxonomy
import com.anitrack.app.data.api.ApiClientPort
import com.anitrack.app.data.auth.AuthManager
import com.anitrack.app.data.auth.SharedPrefsDevIdStore
import com.anitrack.app.data.auth.initializeClerk
import com.anitrack.app.notifications.AiringPlanStore
import com.anitrack.app.notifications.AiringRearm
import com.anitrack.app.notifications.AlarmScheduler
import com.anitrack.app.notifications.EpisodeNotifications
import com.anitrack.app.notifications.NotificationPrimer
import com.anitrack.app.ui.auth.previouslyClerkTheme
import com.anitrack.app.ui.image.artHttpClient
import com.anitrack.app.ui.image.artImageLoader
import com.anitrack.app.ui.profile.HapticsPreference
import com.anitrack.app.ui.schedule.ScheduleReminders
import com.anitrack.app.widget.WidgetAmbientSync
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import okhttp3.OkHttpClient

/*
 * THE PROCESS ROOT — the port of `ios/Sources/App/AniTrackApp.swift`.
 *
 * `AniTrackApp.init()` runs before any view exists and its statement order is load-bearing; so does
 * this. The order below is the same order, with the two UIKit appearance-proxy statements dropped
 * because they have no Android counterpart: a tab-bar label and a search field are ordinary
 * composables with a `style` here, so the type they draw in is `ThemeType.tabLabel` /
 * `ThemeType.fieldInput` at the call site rather than a global proxy installed at launch.
 *
 * | # | iOS | here |
 * | 1 | `Self.applyBrandFont()`          | — (composable `style`; see `ThemeType.tabLabel`) |
 * | 2 | `AppAppearance.install()`        | — (composable `style`; see `ThemeType.fieldInput`) |
 * | 3 | `Clerk.configure(publishableKey:)` | [initializeClerk] — same reason: touching the Clerk
 *                                          singleton before it is configured trips an assertion,
 *                                          so it happens before anything constructs an
 *                                          [AuthManager] and long before the first composition |
 * | 4 | `AuthManager()`                  | [AppGraph.auth] |
 * | 5 | `AppModel(api:)`                 | [AppGraph.model] |
 * | 6 | `model.onSessionExpired = …`     | same |
 * | 7 | notification delegate            | the notification layer installs itself here |
 * | 8 | `EpisodeNotifications.onOpen`    | `MainActivity` reads the tap's intent extra instead |
 * | 9 | DEBUG `-openDetail`              | `MainActivity` — the SAME route a tapped alert takes |
 *
 * Step 7 is [AppGraph.create]'s — `EpisodeNotifications.install` publishes the layer to the process
 * and the model takes it as its `AmbientSync`, both before the first composition.
 *
 * Steps 8–9 are `MainActivity`'s on Android and not this file's, because a notification tap arrives
 * as an `Intent` on the launcher Activity rather than as a delegate callback on the process. What
 * matters is preserved exactly: **the debug launch route and the alert route are one route**
 * ([AppModel.pendingOpen]), so the thing photographed by the capture script is the thing a user
 * taps.
 */

/**
 * The object graph, built once per process.
 *
 * There is no dependency-injection framework here on purpose (`research/compose-architecture.md`
 * §5): the graph is four objects and one of them is a singleton the whole app reads. Hilt would buy
 * a `@HiltViewModel` and an annotation processor for a wiring that fits on one screen.
 */
class AppGraph private constructor(
    val auth: AuthManager,
    val model: AppModel,
    /**
     * The transport itself, not only the model's narrow port: the show page reads three routes the
     * model never touches (`/franchises/{id}`, `/watch-providers`, an exact search), through its own
     * `DetailApi`.
     */
    val client: ApiClient,
    val imageLoader: ImageLoader,
) {

    /**
     * Whether [AppModel.start] has already run for the session that is signed in now.
     *
     * **It lives on the PROCESS, not in composition, and that is the whole point.** iOS starts the
     * library load from `.task(id: auth.isSignedIn)` and never thinks about it again, because a
     * SwiftUI view tree is not rebuilt when the user changes their text size. An Activity is: there
     * is deliberately no `configChanges` in the manifest, so a font-scale change (which the
     * accessibility capture pass performs on purpose) destroys and recreates the whole tree with the
     * same signed-in session underneath it.
     *
     * `start()` is mostly harmless to repeat — but it also stamps `/me/opened`, which is **not
     * idempotent by design**: it returns the previous stamp and then writes now. Running it a second
     * time inside one session would return "a moment ago" and collapse the recap window, so
     * "While you were away" would show nothing for the rest of the day. Once per session, therefore,
     * and the flag has to outlive the composition to say so.
     */
    private var sessionStarted = false

    /** Begin the signed-in session, at most once. See [sessionStarted]. */
    fun startSession() {
        if (sessionStarted) return
        sessionStarted = true
        model.start()
    }

    /**
     * End it. *"Sign-out is the one moment the model outlives its account: the library, the live
     * clock, pending episode alerts and a running Live Activity all survive the view tree. Tear them
     * down here so signing in again starts clean."*
     */
    fun endSession() {
        if (!sessionStarted) return
        sessionStarted = false
        model.teardown()
    }

    companion object {

        fun create(context: Context): AppGraph {
            val app = context.applicationContext

            // The three synchronous restores. All must complete BEFORE the first composition, and
            // all three are `SharedPreferences`/file reads for exactly that reason: a failure the
            // user is still owed has to be on screen when the banner first composes, Detail's
            // history section must not draw empty and then pop in, and a haptic preference read one
            // frame late means the first tap of the session buzzes against the user's choice.
            SyncCenter.install(app)
            RewatchStore.install(app)
            HapticsPreference.install(app)

            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
            val auth = AuthManager(store = SharedPrefsDevIdStore(app), scope = scope)

            // ONE OkHttp client for the API. The art pipeline gets its own (below) and adopts this
            // one's connection pool and its dispatcher's EXECUTOR — sockets and threads, which are
            // expensive to build and carry no policy — but never the `Dispatcher` itself, which
            // owns the in-flight budget: see `artHttpClient`. So the two share the costly parts
            // without sharing behaviour, without queueing a library refresh behind a scroll burst
            // of posters, and no bearer token can ever reach `s4.anilist.co` or `image.tmdb.org`.
            val http: OkHttpClient = ApiClient.defaultHttpClient()
            val client = ApiClient(tokens = auth, baseUrl = AppConfig.apiBaseUrl, httpClient = http)

            // Step 7 of the boot order — the ambient layer, installed BEFORE the model that pushes
            // into it.
            //
            // `install` publishes the instance to the PROCESS (and creates the channel), which is
            // the half that cannot wait for a composition: a fired alarm may be the reason this
            // process exists at all, and `AiringReceiver` reads `EpisodeNotifications.current` on a
            // cold start where no Activity has ever run. It is deliberately not lazy for the same
            // reason.
            val alerts = EpisodeNotifications.install(
                context = app,
                plans = AiringPlanStore.from(app),
                alarms = AlarmScheduler.from(app),
            )

            // The notification primer's persisted answer, published to the process for the same
            // reason: `AppModel.addToLibrary` arms it (from any screen, and from a replayed
            // subscribe) and the Search tab draws it, and neither may own it.
            NotificationPrimer.install(app)

            // The reminder bell's mirror. Android cannot read its own pending alerts back, so
            // Schedule asks the layer that wrote them. **Leaving this unwired is not a missing
            // bell but a LYING one, in the other direction**: `ScheduleReminders.refresh()`
            // resolves to the empty set, so the one surface that tells a user an alert is armed for
            // a specific episode silently never draws.
            ScheduleReminders.source = { alerts.armedAlertTags() }

            // The daily safety net. Idempotent, so every start re-asserts it without displacing an
            // already-enqueued schedule. See `AiringRearm`: the armed set is otherwise recovered
            // only by an alarm firing, a library reload or one of the five re-arm broadcasts, and
            // an OEM that puts the app to sleep drops all eight alarms at once.
            AiringRearm.schedule(app)

            val model = AppModel(
                api = ApiClientPort(client),
                // Never `DefaultApiErrorTaxonomy`: it is HTTP-blind and answers `isUnauthorized`
                // with `false` for everything, which would paint "Couldn't load your library" over
                // a dead session forever.
                errors = ApiClientErrorTaxonomy,
                cache = LibraryCache(dir = app.filesDir),
                recentsStore = RecentsStore.from(app),
                // The two ambient surfaces, composed here because this is the only place that is
                // allowed to know there are two. Both are driven by the same set of moments — a
                // confirmed `reload()`, `setStatus`, `removeFromLibrary`, and the primer's Allow —
                // so neither needs a hook of its own and `AppModel` needs no knowledge of alarms or
                // of Glance.
                //
                // Order is not arbitrary: alerts first, because that is the surface whose failure
                // mode is a missed episode. `CompositeAmbientSync` isolates the members from each
                // other so the widget still re-renders when the alarm layer throws — which it will,
                // the moment somebody revokes "Alarms & reminders" while the app is open.
                //
                // Leaving this at its `NoAmbientSync` default is what the whole notification and
                // widget layers look like when they are compiled but not wired: no plan is ever
                // written, no alarm is ever armed, every bell in the UI still says armed, and the
                // home-screen card never changes.
                ambient = CompositeAmbientSync(alerts, WidgetAmbientSync(app)),
                scope = scope,
            )

            // "A rejected session is auth's problem, not the loader's: the model hands the 401 back
            // here rather than rendering it as 'the server couldn't be reached'."
            model.onSessionExpired = { auth.sessionExpired() }

            return AppGraph(
                auth = auth,
                model = model,
                client = client,
                imageLoader = artImageLoader(app) { artHttpClient(http) },
            )
        }
    }
}

/**
 * The `Application`. It owns the graph and the PROCESS lifecycle, and nothing else.
 *
 * @see AppGraph for the boot order and why it is the order it is.
 */
class PreviouslyApp : Application() {

    lateinit var graph: AppGraph
        private set

    override fun onCreate() {
        super.onCreate()

        // Step 3 of the boot order, and it must precede step 4: `AuthManager`'s constructor decides
        // its mode from `AppConfig.isClerkConfigured`, which is the same boolean that gates this
        // call, so the two can never disagree about whether the Clerk singleton is live. The theme
        // is passed so a Clerk surface reached from ANYWHERE — not only the gate — arrives wearing
        // this app's palette instead of Material's light defaults.
        initializeClerk(this, previouslyClerkTheme())

        graph = AppGraph.create(this)

        registerActivityLifecycleCallbacks(ProcessLifecycle(graph.model))
    }
}

/**
 * `scenePhase` — and the reason it is not `onResume`.
 *
 * iOS's `RootView` watches `scenePhase`: `.active` → `sceneBecameActive()`, `.background` →
 * `sceneEnteredBackground()`. The Android reading of that is the PROCESS's start/stop, not an
 * Activity's resume/pause: a system dialog over the app (the notification-permission prompt, a
 * Clerk OAuth chooser) pauses the Activity without the user having left, and treating that as
 * "returned from background" would fire a reload every time a permission sheet closed.
 *
 * This is `ProcessLifecycleOwner`'s own mechanism, spelled out rather than depended on — it is a
 * started-Activity counter with the same **700 ms debounce**, which is the part that matters:
 * during a configuration change (a font-scale change recreates the Activity by design, see the
 * manifest) the count passes through zero, and without the debounce every accessibility capture
 * would read as a trip to the background.
 */
private class ProcessLifecycle(private val model: AppModel) : Application.ActivityLifecycleCallbacks {

    private val handler = Handler(Looper.getMainLooper())
    private var started = 0
    private var background = true

    private val reportStop = Runnable {
        if (started == 0 && !background) {
            background = true
            model.sceneEnteredBackground()
        }
    }

    override fun onActivityStarted(activity: Activity) {
        handler.removeCallbacks(reportStop)
        started += 1
        if (background) {
            background = false
            // Snaps the countdown clock, reloads when the away-time is stale (> 2 min) and
            // re-stamps `/me/opened` when it reads as a new visit (> 6 h). The launch activation
            // returns immediately — `start()` covers that one.
            model.sceneBecameActive()
            // And re-arm the episode alarms from the plan on disk, which `sceneBecameActive` does
            // NOT cover: it reloads only after two minutes away, and a trip to the system
            // notification screen and back is shorter than that — which is exactly the trip a user
            // makes to turn alerts ON.
            AiringRearm.onForeground(activity)
        }
    }

    override fun onActivityStopped(activity: Activity) {
        started = (started - 1).coerceAtLeast(0)
        if (started == 0) handler.postDelayed(reportStop, CONFIG_CHANGE_GRACE_MILLIS)
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
    override fun onActivityResumed(activity: Activity) = Unit
    override fun onActivityPaused(activity: Activity) = Unit
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
    override fun onActivityDestroyed(activity: Activity) = Unit

    private companion object {
        /** `ProcessLifecycleOwner`'s own value, for the same reason: a recreation is not a departure. */
        const val CONFIG_CHANGE_GRACE_MILLIS = 700L
    }
}

// ---------------------------------------------------------------------------------------------
// The two objects every screen reads
// ---------------------------------------------------------------------------------------------

/**
 * The one [AppModel], published to composition.
 *
 * `static`, because it never changes for the life of the process: a static local costs nothing to
 * read and nothing to provide, and a screen reading it does not become a subscriber to it. The
 * model is `@Stable` with per-field snapshot state, so what a screen actually observes is the
 * fields it touches — which is the whole point of the per-field design (a single `UiState` object
 * would invalidate every screen on the 20-second clock tick).
 */
val LocalAppModel = staticCompositionLocalOf<AppModel> {
    error("No AppModel. The root must provide LocalAppModel — see MainActivity.")
}

/** The one [AuthManager], published to composition. See [LocalAppModel] for why it is static. */
val LocalAuth = staticCompositionLocalOf<AuthManager> {
    error("No AuthManager. The root must provide LocalAuth — see MainActivity.")
}
