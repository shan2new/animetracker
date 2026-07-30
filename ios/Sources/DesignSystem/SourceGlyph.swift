import SwiftUI

/// The quiet, monochrome source cue that sits at the head of a card's metadata line.
///
/// Redesign rule #1: *status gets the color, source gets a glyph.* A mixed anime + TV library stays
/// coherent by demoting catalogue (anime vs TV) to a ~40%-opacity glyph — never a loud "TV/ANIME"
/// pill — while loud accent stays reserved for watch status / urgency. Anime = a sparkle, TV = a
/// display. Type also lives in the All / Anime / TV filter, so this is a reinforcing cue, not the
/// only signal; it carries an accessibility label but no standalone VoiceOver focus by default.
struct SourceGlyph: View {
    let source: MediaSource
    var size: CGFloat = 12
    var color: Color = Theme.text40

    var body: some View {
        Image(systemName: source == .tmdb ? "tv" : "sparkles")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(color)
            .accessibilityLabel(source == .tmdb ? "TV" : "Anime")
    }
}

extension MediaSource {
    /// Human label for the source, used where a word (not the glyph) reads better — e.g. Discover
    /// cards' "TV · 2024" / "Anime · 2023" metadata line.
    var shortLabel: String { self == .tmdb ? "TV" : "Anime" }
}
