import SwiftUI
import UIKit

/// The app is PORTRAIT. The plist lists landscape only so the system's full-screen video player
/// — the trailer stage's hand-off — can rotate ("absolute bliss to watch", user, 4 Sep); this
/// gate is what keeps every other screen upright. The stage opens it on appear and closes it on
/// disappear, and the root asks UIKit to re-evaluate each time so a phone left on its side rotates
/// back the moment the player is gone.
@MainActor
enum OrientationGate {
    private(set) static var allowsLandscape = false

    static func set(allowsLandscape value: Bool) {
        guard allowsLandscape != value else { return }
        allowsLandscape = value
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }

    static var mask: UIInterfaceOrientationMask { allowsLandscape ? .allButUpsideDown : .portrait }
}

/// Exists for one delegate method: the orientation gate. Everything else stays in the SwiftUI
/// `App`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationGate.mask
    }
}
