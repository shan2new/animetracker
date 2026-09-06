package com.anitrack.app

import android.content.Intent
import android.graphics.Color as AndroidColor
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.LocalContext
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.anitrack.app.design.InstallFeedback
import com.anitrack.app.design.PreviouslyTheme
import com.anitrack.app.design.brand.LaunchHandoff
import com.anitrack.app.design.brand.LocalLaunchHandoff
import com.anitrack.app.ui.chrome.ProvideChromeSurface
import com.anitrack.app.ui.chrome.ReduceTransparencyPreference
import com.anitrack.app.ui.image.ProvideArtPipeline
import com.anitrack.app.ui.shell.DebugLaunch
import com.anitrack.app.ui.shell.LocalDebugLaunch
import com.anitrack.app.ui.shell.RootScreen
import com.anitrack.app.ui.shell.ShellIntents
import com.anitrack.app.data.api.DemoLibrary

/**
 * The app's one activity.
 *
 * It does four things and delegates the rest: hands off the system splash, goes edge-to-edge, turns
 * every launch and every notification tap into the app's ONE open-a-show route, and installs the
 * composition roots. The object graph itself is the process's, not this Activity's — see
 * [PreviouslyApp] — because a font-scale change recreates the Activity by design, and rebuilding
 * the model there would drop the library and restart the loader in front of the user.
 *
 * **Everything the roots install is load-bearing, and each one is silently inert when it is
 * missing.** With no `ProvideChromeSurface` every hardened bar draws at opacity 1.0 and the material
 * path is never exercised on any device; with no `ProvideArtPipeline` the first `ArtImage` composed
 * throws; with no `InstallFeedback` every `FeedbackCoordinator.fire` returns at its first line and
 * no haptic ever fires.
 */
class MainActivity : ComponentActivity() {

    /**
     * Flipped by the first composition; the system's own splash is held until it does.
     *
     * Not snapshot state: it is read by a platform callback on the main thread, never by a
     * composable.
     */
    private var composed = false

    private var debugLaunch by mutableStateOf(DebugLaunch.None)

    /** The launch's shared state: one per process, published to the tree. */
    private val launch = LaunchHandoff()

    override fun onCreate(savedInstanceState: Bundle?) {
        // FIRST, and before `setContent`. At targetSdk 36 the platform always draws its own splash
        // (the adaptive icon over `windowSplashScreenBackground`) before the first composable runs;
        // it cannot be skipped, only handed off from. Holding that frame — which sits on the same
        // true black the ident's base does — until the composition can draw is what makes the launch
        // ONE continuous ignite instead of the system's splash followed by the app's own.
        val splash = installSplashScreen()
        splash.setKeepOnScreenCondition { !composed }
        // The exit listener replaces the platform's own fade with nothing: by the time it fires the
        // composition has drawn the SAME picture underneath — the launcher's icon in its disc, on
        // the canvas — from the frame read here, so the system view can simply go. Two frames
        // later, so a frame drawn with the reported frame is on screen first.
        splash.setOnExitAnimationListener { provider ->
            val icon = provider.iconView
            if (icon.width > 0 && icon.height > 0) {
                val location = IntArray(2)
                icon.getLocationInWindow(location)
                launch.systemIcon = Rect(
                    location[0].toFloat(),
                    location[1].toFloat(),
                    (location[0] + icon.width).toFloat(),
                    (location[1] + icon.height).toFloat(),
                )
                Log.d("Launch", "system splash icon ${launch.systemIcon}")
            }
            provider.view.postOnAnimation { provider.view.postOnAnimation { provider.remove() } }
        }

        // The app is dark-only and never follows the system light/dark setting, so both system bars
        // are forced dark with light icons. The bare `enableEdgeToEdge()` default does NOT do this:
        // on API 26 it leaves a light navigation bar (caught on PreviouslyFloor_API26, 4 Sep), which
        // is why the floor device is in the QA matrix.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(AndroidColor.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(AndroidColor.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)

        val graph = (application as PreviouslyApp).graph

        // COLD start: a notification tapped while the app was dead arrives here.
        consume(intent, graph.model)

        // WARM start — and without this the alert route silently does nothing for anyone whose app
        // was already running, which is most taps. It works only because the Activity is
        // `singleTop` (see the manifest): with the default launch mode the system would build a
        // SECOND MainActivity and this listener would never fire, while a cold-start test still
        // passed.
        addOnNewIntentListener { next ->
            setIntent(next)
            consume(next, graph.model)
        }

        setContent {
            PreviouslyRoot(
                graph = graph,
                debugLaunch = debugLaunch,
                launch = launch,
                onReadyToDraw = { composed = true },
            )
        }
    }

    /**
     * The ONE open-a-show route, and the debug launch flags.
     *
     * A tapped episode alert and the `openDetail` capture extra enter through the same door —
     * [AppModel.pendingOpen], which the shell consumes by selecting Today and REPLACING its stack.
     * That is deliberate on both platforms: what the capture script photographs is what a user's tap
     * produces, so the route cannot rot unnoticed.
     *
     * The flags are re-read on every intent, so a warm `am start` re-poses the app without a
     * force-stop; in a release build nothing is parsed at all (see [DebugLaunch.from]).
     */
    private fun consume(intent: Intent?, model: AppModel) {
        debugLaunch = DebugLaunch.from(intent)
        // Set BEFORE the reload the shell triggers, so the first payload is already the fixture.
        DemoLibrary.enabled = debugLaunch.demoBusy

        val franchiseId = intent
            ?.getStringExtra(ShellIntents.EXTRA_OPEN_DETAIL)
            ?.takeIf { it.isNotEmpty() }
        if (franchiseId != null) model.pendingOpen = franchiseId
    }
}

/**
 * The composition root: the token layer, the chrome surface, the art pipeline, the haptic host —
 * then the app.
 *
 * The nesting order is not arbitrary. [PreviouslyTheme] publishes the density ceiling, the inherited
 * type and the control ink that everything below reads; `ProvideChromeSurface` resolves the ONE
 * capability boolean (`SDK_INT >= 31 && !reduceTransparency`) and the Haze state that the two
 * scroll-edge bands and every glass capsule consume; `ProvideArtPipeline` publishes the single
 * `ImageLoader` — with its own art `OkHttpClient`, the 25 %-heap memory cache and the 256 MB disk
 * cache — and the palette cache built over it.
 */
@Composable
private fun PreviouslyRoot(
    graph: AppGraph,
    debugLaunch: DebugLaunch,
    launch: LaunchHandoff,
    onReadyToDraw: () -> Unit,
) {
    val context = LocalContext.current
    // Read once: the preference changes only through the settings row, which recreates nothing below
    // it that a recomposition of this root would not already carry.
    val reduceTransparency = remember(context) {
        ReduceTransparencyPreference.current(context.applicationContext)
    }

    PreviouslyTheme {
        ProvideChromeSurface(reduceTransparency = reduceTransparency) {
            ProvideArtPipeline(graph.imageLoader) {
                CompositionLocalProvider(
                    LocalAppModel provides graph.model,
                    LocalAuth provides graph.auth,
                    LocalDebugLaunch provides debugLaunch,
                    LocalLaunchHandoff provides launch,
                ) {
                    // Binds `FeedbackCoordinator` to this window for as long as the composition
                    // lives. Every haptic in the app goes through it.
                    InstallFeedback()

                    RootScreen(
                        auth = graph.auth,
                        model = graph.model,
                        client = graph.client,
                        onReadyToDraw = onReadyToDraw,
                    )
                }
            }
        }
    }
}
