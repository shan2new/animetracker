import UIKit

// Lightweight haptic feedback, fired from user-initiated actions in AppModel and views.
// Centralized so the whole app speaks the same tactile language.
//
// Generators are long-lived and re-`prepare()`d right after each fire: a freshly constructed
// generator adds perceptible latency on its first tap, which matters for rapid repeats
// (episode pips, catch-up on several shows in a row).
@MainActor
enum Haptics {
    private static let notification = UINotificationFeedbackGenerator()
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static var impacts: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]

    static func success() {
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    static func error() {
        notification.notificationOccurred(.error)
        notification.prepare()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = impacts[style] ?? {
            let g = UIImpactFeedbackGenerator(style: style)
            impacts[style] = g
            return g
        }()
        generator.impactOccurred()
        generator.prepare()
    }

    static func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }
}
