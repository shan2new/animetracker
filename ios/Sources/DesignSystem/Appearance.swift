import SwiftUI
import UIKit

/// UIKit appearance proxies, installed ONCE at launch.
///
/// Two screens used to install theirs from `onAppear`: Library's All titles set the segmented
/// control's colours and Search set the search field's font. A proxy is global, so every other
/// segmented control and search field in the app rendered one way before the user had visited
/// that screen and another way after. Launch is the only place a global belongs.
@MainActor
enum AppAppearance {
    static func install() {
        // No segmented-control proxy. One was installed here (plate colours for the Arrange
        // sheet's "View as") and it flattened the system SEARCH SCOPE BAR into a grey strip — on
        // iOS 26+ that control is Liquid Glass by default, and it stays that way everywhere.

        // The system search field inherits the app's Outfit body font through SwiftUI's default;
        // input in a catalogue field is information, not identity, so it is SF at body size.
        UISearchTextField.appearance().font = UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: .systemFont(ofSize: 17, weight: .regular))
        installScopeFont()
        // The scope bar is built when the field presents, so a text-size change while the app
        // runs is honoured from the next search on.
        NotificationCenter.default.addObserver(forName: UIContentSizeCategory.didChangeNotification,
                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { installScopeFont() }
        }
    }

    /// The search scope bar's labels at a TEXT STYLE. The SwiftUI `Text` styling inside
    /// `.searchScopes` never reaches the system bar: at AX-XL its "All · Anime · TV" stayed at the
    /// default size under a field and results set at the reader's size — the one control on the
    /// screen that did not grow (review, 23 Sep). Font ONLY, scoped to the search bar: the plate
    /// colours an earlier proxy set are what flattened the bar's Liquid Glass (see above).
    private static func installScopeFont() {
        let font = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: .systemFont(ofSize: 13, weight: .semibold))
        UISegmentedControl.appearance(whenContainedInInstancesOf: [UISearchBar.self])
            .setTitleTextAttributes([.font: font], for: .normal)
    }
}
