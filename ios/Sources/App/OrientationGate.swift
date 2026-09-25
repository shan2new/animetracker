import SwiftUI
import UIKit

/// The app is PORTRAIT. The plist lists landscape only so the trailer's full screen
/// (`TrailerFullScreen`) can turn with the phone; this gate is what keeps every other screen
/// upright. The full screen opens it on appear and closes it on disappear, and every controller in
/// the window — the presented ones included — is asked to re-evaluate each time, so a phone left on
/// its side rotates back the moment the player is gone.
@MainActor
enum OrientationGate {
    private(set) static var allowsLandscape = false

    static func set(allowsLandscape value: Bool) {
        guard allowsLandscape != value else { return }
        allowsLandscape = value
        refresh()
    }

    /// Opened BY turning the phone: the interface follows the phone into landscape at once rather
    /// than waiting for the next turn.
    static func follow(_ orientation: UIDeviceOrientation) {
        guard allowsLandscape, orientation.isLandscape else { return }
        // A device turned LEFT is an interface turned RIGHT.
        let mask: UIInterfaceOrientationMask = orientation == .landscapeLeft ? .landscapeRight : .landscapeLeft
        for scene in UIApplication.shared.connectedScenes {
            (scene as? UIWindowScene)?.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
    }

    static var mask: UIInterfaceOrientationMask { allowsLandscape ? .allButUpsideDown : .portrait }

    private static func refresh() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                var controller = window.rootViewController
                while let c = controller {
                    c.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = c.presentedViewController
                }
            }
        }
    }
}

/// Exists for one delegate method: the orientation gate. Everything else stays in the SwiftUI
/// `App`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationGate.mask
    }
}
