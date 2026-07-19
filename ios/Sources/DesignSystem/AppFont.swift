import SwiftUI
import UIKit

// The app's brand typeface is Outfit (bundled static weights, registered via UIAppFonts). Every
// font in the app resolves through here so the family lives in one place. We ship five cuts —
// Light / Regular / Medium / SemiBold / Bold — and snap rarer weights to the nearest one.
//
// `Font.Weight` is a struct (not an enum), so we compare by value rather than `switch`-ing cases.
enum AppFont {
    /// PostScript name of the bundled Outfit cut closest to `weight`.
    static func name(_ weight: Font.Weight) -> String {
        if weight == .ultraLight || weight == .thin || weight == .light { return "Outfit-Light" }
        if weight == .medium { return "Outfit-Medium" }
        if weight == .semibold { return "Outfit-SemiBold" }
        if weight == .bold || weight == .heavy || weight == .black { return "Outfit-Bold" }
        return "Outfit-Regular"
    }

    /// SwiftUI font at a fixed point size (callers that scale wrap this in `@ScaledMetric`).
    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(name(weight), size: size)
    }

    /// UIKit counterpart for appearance proxies (e.g. tab-bar item titles), Dynamic Type-scaled.
    /// Falls back to the system font if the bundled font somehow isn't registered.
    static func uiFont(size: CGFloat, weight: Font.Weight = .regular,
                       relativeTo style: UIFont.TextStyle = .body) -> UIFont {
        let base = UIFont(name: name(weight), size: size)
            ?? .systemFont(ofSize: size, weight: .regular)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }
}
