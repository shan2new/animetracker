import SwiftUI

/// The launch's shared state. `RootView` owns one per launch and puts it in the environment; the
/// ident reads auth's answer from it and writes its phase back, and the shell reads the phase to
/// know when the app is coming through.
@Observable @MainActor
final class LaunchHandoff {
    enum Phase {
        /// The ident is on stage: the ribbon being drawn, the full stop landing, the held beat.
        case holding
        /// The ident is pushing through into the app; the app is emerging beneath it.
        case leaving
    }

    var phase: Phase = .holding
    /// Auth has answered (session or none), so the screen under the ident is the right one.
    var authReady = false
    /// Today's billboard has its sharp picture (or there is none to wait for), so the app can
    /// emerge as television rather than as a colour.
    var artReady = false
    /// The ident has been removed. Once true, page-ins fade as usual; during the launch the
    /// app's own emergence is the fade (see `pageInTransition(fadeIn:)`).
    var finished = false
    /// The app is emerging (or the launch is over): safe to show the tab bar, which the system
    /// composites above any overlay.
    var emerging: Bool { phase == .leaving || finished }
}
