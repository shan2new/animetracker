package com.anitrack.app.design.brand

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.geometry.Rect

/**
 * The launch's shared state — the port of `ios/Sources/App/LaunchHandoff.swift`.
 *
 * `MainActivity` owns one per process and publishes it through [LocalLaunchHandoff]; the ident
 * reads auth's answer from it and writes its phase back, the shell reads the phase to know when
 * the app is coming through, and the system splash's icon frame arrives here so the ident's first
 * frame is the same picture the platform was showing.
 */
class LaunchHandoff {
    enum class Phase {
        /** The ident is on stage: the ribbon released and lit, the held beat. */
        Holding,

        /** The ident is pushing through into the app; the app is emerging beneath it. */
        Leaving,
    }

    var phase: Phase by mutableStateOf(Phase.Holding)

    /** Auth has answered (session or none), so the screen under the ident is the right one. */
    var authReady: Boolean by mutableStateOf(false)

    /** The first billboard's art has decoded, so the app under the ident is a picture, not a plate. */
    var artReady: Boolean by mutableStateOf(false)

    /**
     * The ident has been removed. Once true, page-ins fade as usual; during the launch the app's
     * own emergence is the fade (see `PageIn(fadeIn)`).
     */
    var finished: Boolean by mutableStateOf(false)

    /** The app is emerging (or the launch is over). */
    val emerging: Boolean get() = phase == Phase.Leaving || finished

    /**
     * The system splash's icon view, in window coordinates (px), read in the exit-animation
     * listener — `null` until it fires, or forever on a platform that never does; the ident then
     * predicts it (the icon is centred in the window).
     */
    var systemIcon: Rect? by mutableStateOf(null)
}

/** The launch in progress, or `null` when there is none (a preview, a test). */
val LocalLaunchHandoff = staticCompositionLocalOf<LaunchHandoff?> { null }
