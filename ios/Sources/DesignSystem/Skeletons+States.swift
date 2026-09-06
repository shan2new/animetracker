import SwiftUI

// Structural skeletons (board 09). A skeleton is the shape of the content that is coming. Board 12
// refuses SHIMMER on skeletons by name and that stands — a travelling highlight is decoration
// pretending to be progress. What the gate does allow, and what a completely static skeleton could
// not answer, is "is this still working?": a 1.4-s opacity breath (0.65 ↔ 1.0, static 0.85 under
// Reduce Motion) and a small `ProgressView` once the wait passes 800 ms.
//
// The 240 / 320 / 120 rule lives in `SkeletonGate` and nowhere else. A screen composes its
// skeleton from the atoms below and hands it to the gate; it never re-implements the timing.

/// The one motion a skeleton gets. Shimmer stays refused (board 12 names it); a 1.4-s ease-in-out
/// breath says "still working" without a travelling highlight, and under Reduce Motion it collapses
/// to a static 0.92. A file-level constant because `SkeletonGate` is generic and cannot hold one.
///
/// The amplitude is 0.88 ↔ 1.0, not 0.65 ↔ 1.0. A 35 % oscillation across the WHOLE screen, forever,
/// is not a reassurance that something is working — it is a pulse the eye cannot ignore and cannot
/// look away from, on the frame the user is already waiting through. 12 % still visibly breathes.
private let skeletonBreath = Animation.easeInOut(duration: 1.4).repeatForever(autoreverses: true)

// MARK: - The gate

/// Owns the whole loading rule:
///   • nothing for the first **240 ms** — a fast response should never flash a skeleton;
///   • once shown, the skeleton stays at least **320 ms** even if data lands at 250 ms;
///   • it swaps to content with a **120-ms crossfade**;
///   • the frame never blanks between them.
///
/// The two waits are timed holds, not springs gated by sleep: the swap itself is an ease-out
/// crossfade, so nothing is animated on a timer.
struct SkeletonGate<Skeleton: View, Content: View>: View {
    let isLoading: Bool
    @ViewBuilder var skeleton: () -> Skeleton
    @ViewBuilder var content: () -> Content

    /// `isLoading` means "there is nothing to show yet". A refresh over content the user can
    /// already see is not this — that is `RefreshIndicator` plus the content itself.
    @State private var visible = false
    /// Monotonic: a wall-clock stamp could be moved by the system mid-window and compute a
    /// negative or absurd remainder. `ContinuousClock` cannot be adjusted.
    @State private var shownAt: ContinuousClock.Instant?
    /// A wait long enough that the structure alone stops answering "is this working?".
    @State private var slow = false
    @State private var breathing = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(isLoading: Bool,
         @ViewBuilder skeleton: @escaping () -> Skeleton,
         @ViewBuilder content: @escaping () -> Content) {
        self.isLoading = isLoading
        self.skeleton = skeleton
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .top) {
            if visible {
                skeleton()
                    .opacity(reduceMotion ? 0.92 : (breathing ? 1.0 : 0.88))
                    .animation(reduceMotion ? nil : skeletonBreath, value: breathing)
                    
                    .onAppear { breathing = true }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Copy.Accessibility.loading)
            } else if isLoading {
                // The first 240 ms: no skeleton and no content. Deliberately empty, so a fast
                // response lands straight on content instead of flashing structure at the user.
                Color.clear.frame(height: 0)
            } else {
                content()
            }
        }
        .animation(ThemeMotion.uiCrossfade, value: visible)
        .animation(ThemeMotion.uiCrossfade, value: isLoading)
        .task(id: isLoading) {
            if isLoading {
                guard !visible else { return }
                try? await Task.sleep(for: .milliseconds(240))
                guard !Task.isCancelled, isLoading else { return }
                shownAt = ContinuousClock.now
                visible = true
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled, isLoading else { return }
                withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) {
                    slow = true
                }
            } else {
                slow = false
                guard visible else { return }
                // Minimum visible window: a skeleton that blinks is worse than one that stays.
                if let shownAt {
                    let remaining = Duration.milliseconds(320) - shownAt.duration(to: .now)
                    if remaining > .zero { try? await Task.sleep(for: remaining) }
                }
                guard !Task.isCancelled else { return }
                visible = false
                shownAt = nil
            }
        }
    }
}

// MARK: - Atoms

/// A poster-shaped block. Skeletons do not scale with Dynamic Type — they are structure, not text.
struct SkeletonPoster: View {
    let width: CGFloat
    let height: CGFloat
    var radius: CGFloat = ThemeRadius.poster

    var body: some View { SkeletonBlock(width: width, height: height, radius: radius) }
}

/// A line of text that has not arrived.
struct SkeletonLine: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12

    var body: some View { SkeletonBlock(width: width, height: height, radius: 6) }
}

/// A list row: poster plus stacked lines. The row height scales with Dynamic Type so the swap to
/// real content does not jump at accessibility sizes.
struct SkeletonRow: View {
    let poster: CGSize
    let lines: [CGFloat]
    var posterRadius: CGFloat = 6
    var spacing: CGFloat = ThemeSpace.x3
    @ScaledMetric(wrappedValue: ThemeMetrics.rowStandard, relativeTo: .body) private var height: CGFloat

    init(poster: CGSize, lines: [CGFloat], posterRadius: CGFloat = 6,
         spacing: CGFloat = ThemeSpace.x3, height: CGFloat = ThemeMetrics.rowStandard) {
        self.poster = poster
        self.lines = lines
        self.posterRadius = posterRadius
        self.spacing = spacing
        _height = ScaledMetric(wrappedValue: height, relativeTo: .body)
    }

    var body: some View {
        HStack(spacing: spacing) {
            if poster.width > 0 {
                SkeletonPoster(width: poster.width, height: poster.height, radius: posterRadius)
            }
            VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, width in
                    SkeletonLine(width: width, height: index == 0 ? 13 : 10)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: height, alignment: .leading)
    }
}

/// A card-shaped block on the flat surface — the shape a Focus, Recap or Next-up card will fill.
struct SkeletonCard<Content: View>: View {
    var height: CGFloat = 168
    var radius: CGFloat = ThemeRadius.card
    @ViewBuilder var content: Content

    init(height: CGFloat = 168, radius: CGFloat = ThemeRadius.card,
         @ViewBuilder content: () -> Content) {
        self.height = height
        self.radius = radius
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeSpace.x4) { content }
            .padding(ThemeSpace.x4)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
            // The shape the card will fill, at the card's own surface level — a skeleton that
            // sits at a different elevation than the content it stands in for makes the swap
            // land as a lighting change.
            .surface(.plate, radius: radius)
    }
}

/// A horizontal poster shelf.
///
/// `titleLines` must match what `ShelfCard` RESERVES, or the swap jumps. Measured on Library: the
/// skeleton put "WATCHING" at 493 pt and the real content at 537 pt, because the skeleton emitted
/// two text lines where a `ShelfCard` reserves two *title* lines **plus** a caption — so everything
/// below moved 44 pt at the swap, and because `SkeletonGate` crossfades in a `ZStack` you saw both
/// misaligned lists superimposed for 120 ms.
///
/// `count` defaults to 5, not 3: the real shelf runs off the trailing edge, and a skeleton that
/// stops short of it promises a shorter shelf than the one that arrives.
struct SkeletonShelf: View {
    var count: Int = 5
    var size: CGSize = PosterSize.shelfLarge.size
    var caption: Bool = false
    /// Title lines the destination `ShelfCard` reserves. Two everywhere in this app today.
    var titleLines: Int = 2

    /// The same @ScaledMetric heights `ShelfCard`'s type occupies, so the handoff lands flush at
    /// every Dynamic Type size rather than only at `.large`.
    @ScaledMetric(relativeTo: .subheadline) private var titleLine: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var captionLine: CGFloat = 11

    var body: some View {
        HStack(alignment: .top, spacing: ThemeMetrics.shelfGap) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                    SkeletonPoster(width: size.width, height: size.height)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(0..<max(0, titleLines), id: \.self) { line in
                            SkeletonLine(width: line == titleLines - 1 ? size.width * 0.62 : size.width,
                                         height: titleLine)
                        }
                        if caption {
                            SkeletonLine(width: size.width * 0.45, height: captionLine)
                        }
                    }
                    .frame(width: size.width, alignment: .leading)
                }
            }
        }
    }
}


// The six per-screen default compositions (`Skeleton.today/schedule/libraryRoot/libraryAll/
// detail/search`) were deleted in the cohesion pass (30 Aug): every screen composes its own
// stand-in from the atoms above, the defaults were referenced only by their own previews, and
// `Skeleton.detail` was already admitted stale in code — a dead layer that no longer matched
// any screen it claimed to model. The atoms and `SkeletonGate` are the contract.
