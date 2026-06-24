import SwiftUI

// Loading primitives for the Discover/search experience. A search round-trips AniList (and may
// lazily group results with an LLM), so latency is real — these make the wait feel alive instead
// of parking on static text: skeleton placeholders, a sweeping highlight, and an indeterminate bar.

// A diagonal highlight that sweeps across whatever it's masked to. Used for skeletons and to make
// the "Searching…" label feel active. Confine it with `.shimmering(_:)`.
struct ShimmerSweep: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.55), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: w * 0.75)
            .offset(x: phase * w * 1.4)
            .onAppear {
                phase = -1
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    // Overlays a moving highlight masked to the receiver's shape. `active == false` is a no-op so
    // it can be bound directly to a loading flag.
    @ViewBuilder
    func shimmering(_ active: Bool = true) -> some View {
        if active {
            overlay { ShimmerSweep().mask(self).blendMode(.plusLighter) }
        } else {
            self
        }
    }
}

// A thin indeterminate progress bar — an accent segment sweeping left→right over a faint track.
// Shown whenever a search is in flight, so even re-searches over existing results read as "working".
struct IndeterminateBar: View {
    @State private var x: CGFloat = -0.4

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Theme.accent)
                .frame(width: geo.size.width * 0.35)
                .offset(x: x * geo.size.width)
                .onAppear {
                    x = -0.4
                    withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: false)) {
                        x = 1.05
                    }
                }
        }
        .frame(height: 2.5)
        .background(Theme.accent.opacity(0.14), in: Capsule())
        .clipShape(Capsule())
    }
}

// A placeholder with the exact footprint of a PosterCard (2:3, same corner radius and hairline),
// with shimmering title/subtitle bars — the skeleton-screen pattern, so the grid keeps its shape
// while real results load.
struct PosterCardSkeleton: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(Theme.surface)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 7) {
                    bar(width: 104, height: 11)
                    bar(width: 64, height: 9)
                }
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
            .shimmering()
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.white.opacity(0.07))
            .frame(width: width, height: height)
    }
}
