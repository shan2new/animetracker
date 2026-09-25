import SwiftUI
import UIKit

// X's page chrome for a pushed feed page (the post page): the page's own black under a plain
// arrow with the page's name beside it — not the system's glass disc and a centred title (the X
// pass, 25 Sep: "why does this not look like X?").

/// X's bar, leading: the arrow and the page's name in bold.
struct XPageTitle: View {
    let title: String
    let onBack: () -> Void

    /// X's gap between the arrow and the title.
    private static let gap: CGFloat = ThemeSpace.x4

    var body: some View {
        HStack(spacing: Self.gap) {
            Button(action: onBack) {
                AppGlyph(systemName: "arrow.left")
                    .font(ThemeType.feedPageTitle.font.weight(.regular))
                    .foregroundStyle(ThemeColor.feedText)
                    .frame(width: FeedMetrics.actionHitHeight, height: FeedMetrics.actionHitHeight, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(FeedIconPressStyle())
            .accessibilityLabel(Copy.Action.back)
            Text(title)
                .type(ThemeType.feedPageTitle)
                .foregroundStyle(ThemeColor.feedText)
                .lineLimit(1)
                // A toolbar item proposes little width; the title takes what it needs.
                .fixedSize()
                .accessibilityAddTraits(.isHeader)
        }
        .fixedSize()
    }
}

/// Keeps the swipe back on a page that hides its back button: `navigationBarBackButtonHidden`
/// turns UIKit's pops off with the button — the edge pan, and from iOS 26 the content swipe too.
/// While the page is in front, each of its navigation controller's pop gestures asks this
/// delegate (which only needs a page to go back to), and the delegates it replaced are put back
/// as the page leaves.
struct SwipeBackKeeper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        /// Each recognizer this page took over, with the delegate it had.
        private var taken: [(gesture: UIGestureRecognizer, replaced: UIGestureRecognizerDelegate?)] = []

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard taken.isEmpty, let nav = navigationController else { return }
            var gestures: [UIGestureRecognizer] = []
            if let edge = nav.interactivePopGestureRecognizer { gestures.append(edge) }
            if #available(iOS 26.0, *), let content = nav.interactiveContentPopGestureRecognizer {
                gestures.append(content)
            }
            for gesture in gestures where gesture.delegate !== self {
                taken.append((gesture, gesture.delegate))
                gesture.delegate = self
                gesture.isEnabled = true
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            for (gesture, replaced) in taken where gesture.delegate === self {
                gesture.delegate = replaced
            }
            taken = []
        }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}
