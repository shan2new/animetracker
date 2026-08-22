import SwiftUI

// Structural skeletons (board 09). A skeleton is the shape of the content that is coming, drawn
// once and never animated: no shimmer, no pulse, no breathing opacity, no spinner. Board 12
// refuses shimmer on skeletons by name.
//
// The 240 / 320 / 120 rule lives in `SkeletonGate` and nowhere else. A screen composes its
// skeleton from the atoms below and hands it to the gate; it never re-implements the timing.

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
            } else {
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
struct SkeletonShelf: View {
    var count: Int = 3
    var size: CGSize = PosterSize.shelfLarge.size
    var caption: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: ThemeSpace.x3) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonPoster(width: size.width, height: size.height)
                    if caption {
                        SkeletonLine(width: size.width * 0.78, height: 10)
                    }
                }
            }
        }
    }
}

// MARK: - Default compositions
//
// One per screen. A screen track may compose its own from the atoms when its layout diverges —
// the atoms are the contract, these are the default. What may never be re-implemented is the gate.

@MainActor
enum Skeleton {

    /// Focus card + two queue rows + the Watching shelf. Promoted verbatim from `TodayView`.
    static var today: some View {
        VStack(alignment: .leading, spacing: ThemeSpace.x6) {
            SkeletonCard(height: 212, radius: ThemeRadius.focusCard) {
                HStack(alignment: .top, spacing: ThemeSpace.x4) {
                    SkeletonPoster(width: 80, height: 120)
                    VStack(alignment: .leading, spacing: 10) {
                        SkeletonLine(width: 90, height: 10)
                        SkeletonLine(width: 180, height: 18)
                        SkeletonLine(width: 130, height: 12)
                    }
                    .padding(.top, ThemeSpace.x1)
                }
                SkeletonBlock(height: 48, radius: 24)
            }
            .padding(.horizontal, ThemeSpace.x4)
            .padding(.top, ThemeSpace.x2)

            VStack(spacing: 0) {
                ForEach(0..<2, id: \.self) { _ in
                    SkeletonRow(poster: CGSize(width: 36, height: 54), lines: [160, 110])
                }
            }
            .padding(.horizontal, ThemeSpace.x6)

            SkeletonLine(width: 120, height: 10)
                .padding(.horizontal, ThemeSpace.x4)
                .padding(.top, ThemeSpace.x2)

            SkeletonShelf()
                .padding(.horizontal, ThemeSpace.x4)
        }
    }

    /// Week strip, day rule, one group of dated rows.
    static var schedule: some View {
        VStack(alignment: .leading, spacing: ThemeSpace.x5) {
            HStack(spacing: ThemeSpace.x2) {
                ForEach(0..<7, id: \.self) { _ in
                    SkeletonBlock(width: 36, height: 44, radius: ThemeRadius.compactControl)
                }
            }
            SkeletonLine(width: 120, height: 11)
            SkeletonLine(width: 60, height: 9)
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: ThemeSpace.x3) {
                        SkeletonRow(poster: CGSize(width: 36, height: 54), lines: [170, 100])
                        SkeletonLine(width: 52, height: 12)
                    }
                }
            }
        }
        .padding(.horizontal, ThemeSpace.x4)
        .padding(.top, ThemeSpace.x2)
    }

    /// The All-titles row plus three shelves.
    static var libraryRoot: some View {
        VStack(alignment: .leading, spacing: ThemeSpace.x6) {
            SkeletonBlock(height: 52, radius: ThemeRadius.row)
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    SkeletonLine(width: 90, height: 10)
                    SkeletonShelf(caption: true)
                }
            }
        }
        .padding(.horizontal, ThemeSpace.x4)
        .padding(.top, ThemeSpace.x2)
    }

    /// The compact instrument behind All titles.
    static var libraryAll: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { _ in
                SkeletonRow(poster: CGSize(width: 40, height: 60), lines: [170, 120],
                            posterRadius: ThemeRadius.poster)
            }
        }
        .padding(.horizontal, ThemeSpace.x4)
        .padding(.top, ThemeSpace.x2)
    }

    /// Hero, the Next-up card, the About block, the grouped part rows.
    static var detail: some View {
        VStack(alignment: .leading, spacing: ThemeSpace.x6) {
            HStack(alignment: .top, spacing: ThemeSpace.x4) {
                SkeletonPoster(width: 96, height: 144)
                VStack(alignment: .leading, spacing: 10) {
                    SkeletonLine(width: 220, height: 22)
                    SkeletonLine(width: 140, height: 12)
                }
                .padding(.top, ThemeSpace.x1)
            }
            SkeletonCard(height: 168) {}
            VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                SkeletonLine(height: 12)
                SkeletonLine(height: 12)
                SkeletonLine(width: 200, height: 12)
            }
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonRow(poster: .zero, lines: [150], height: 52)
                }
            }
            .padding(.horizontal, 14)
            .surface(.plate, radius: ThemeRadius.row)
        }
        .padding(.horizontal, ThemeSpace.x4)
        .padding(.top, ThemeSpace.x2)
    }

    /// Search results keep their own row height (52×78 covers).
    static var search: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { _ in
                SkeletonRow(poster: CGSize(width: 52, height: 78), lines: [190, 130],
                            posterRadius: ThemeRadius.poster, height: 92)
            }
        }
        .padding(.horizontal, ThemeSpace.x4)
        .padding(.top, ThemeSpace.x2)
    }
}

// MARK: - Previews

#Preview("Skeleton · Today") {
    ScrollView { Skeleton.today }.background(ThemeColor.canvas)
}

#Preview("Skeleton · Detail") {
    ScrollView { Skeleton.detail }.background(ThemeColor.canvas)
}

#Preview("Skeleton · Library and Search") {
    ScrollView {
        VStack(alignment: .leading, spacing: ThemeSpace.x8) {
            Skeleton.libraryRoot
            Skeleton.search
            Skeleton.schedule
        }
    }
    .background(ThemeColor.canvas)
}
