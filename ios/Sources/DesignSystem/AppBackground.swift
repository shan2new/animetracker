import SwiftUI

// The app's base backdrop: a top-down gradient that's warmest behind the header and settles into the
// flat base before the content grid begins — so the tint reads as ambient mood, not a wash competing
// with cover art. Hue is a deep ember derived from the warm accent (not the cooler tones some apps
// use) so it stays cohesive with `Theme.accent`. Use this in place of a bare `Theme.background` fill.
struct AppBackground: View {
    var body: some View {
        LinearGradient(
            stops: [
                // Warm ember crown behind the title / filter row.
                .init(color: Color(hex: 0x2A1E14), location: 0.0),
                // Fully resolved to the base by the time the first card grid scrolls under it.
                .init(color: Theme.background, location: 0.42),
                .init(color: Theme.background, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .top) {
            // A concentrated accent glow just under the status bar — the "lit from above" highlight
            // that gives the crown its premium depth without a visible edge.
            RadialGradient(
                colors: [Theme.accent.opacity(0.10), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 460
            )
        }
        .ignoresSafeArea()
    }
}
