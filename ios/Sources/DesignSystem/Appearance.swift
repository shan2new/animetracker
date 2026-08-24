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
    }
}
