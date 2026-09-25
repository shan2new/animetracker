import SwiftUI

// BROWSE BY GENRE (ios-spec §3.6): the catalogue's genres in the field's scope, as tiles — Apple
// Music's category grid — each wearing a collage of that genre's own posters (the server's
// top-trending picks, `DiscoverGenre.posters`), never a literal colour. A tile is a value link:
// it appends `DiscoverRoute.genre` to the Discover tab's `NavigationStack(path:)`, whose
// destination (`GenreResultsView`) is registered with the tab's other routes in
// `RootView.detailDestinations`.
//
// The tiles come from `DiscoverCatalog.shared`, loaded by `DiscoverView` per scope; this view only
// draws the array it is handed (no computation in the body) and is EQUATABLE on it, because the
// launchpad's body re-runs on every keystroke and on the field's focus.

struct DiscoverGenres: View, @MainActor Equatable {
    let genres: [DiscoverGenre]
    /// How many tiles; nil for all of them (Discover's Genres page).
    var limit: Int? = DiscoverCatalog.tileLimit
    /// The "Browse by genre" header; off where the page's tab already says it.
    var header = true

    /// Tiles grow with the type, so a two-line name and its count never crowd the collage.
    @ScaledMetric(relativeTo: .headline) private var tileHeight: CGFloat = FeedMetrics.genreTileHeight
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var typeSize

    static func == (a: DiscoverGenres, b: DiscoverGenres) -> Bool { a.genres == b.genres }

    private var shown: [DiscoverGenre] { limit.map { Array(genres.prefix($0)) } ?? genres }
    /// One column at the accessibility sizes: a name at AX-XL in half the width broke mid-word.
    private var columns: Int { typeSize.isAccessibilitySize ? 1 : 2 }
    private var tileWidth: CGFloat {
        let content = ThemeMetrics.windowWidth - 2 * ThemeMetrics.gutter
        return columns == 1 ? content : (content - ThemeMetrics.shelfGap) / 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
            if header {
                SectionHeaderRow(Copy.Discover.browseByGenre)
                    .padding(.horizontal, ThemeMetrics.gutter)
            }
            // EAGER (a `Grid`), not a `LazyVGrid`: the launchpad folds to zero height under a
            // query, and a lazy grid folded to nothing drops its cells and rebuilds them on
            // Cancel — the cost the fold exists to avoid (the trending grid's rule). Eight tiles.
            Grid(alignment: .topLeading, horizontalSpacing: ThemeMetrics.shelfGap,
                 verticalSpacing: ThemeMetrics.shelfGap) {
                ForEach(Array(stride(from: 0, to: shown.count, by: columns)), id: \.self) { start in
                    GridRow {
                        ForEach(shown[start..<min(start + columns, shown.count)]) { genre in
                            tile(genre)
                        }
                        // A lone last tile keeps its column's width, not the row's.
                        if shown.count - start < columns {
                            Color.clear.frame(height: 0).gridCellUnsizedAxes(.vertical)
                        }
                    }
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
        }
    }

    private func tile(_ genre: DiscoverGenre) -> some View {
        let shape = RoundedRectangle(cornerRadius: ThemeRadius.row, style: .continuous)
        return NavigationLink(value: DiscoverRoute.genre(key: genre.key, name: genre.name)) {
            ZStack(alignment: .bottomLeading) {
                GenreCollage(posters: genre.posters, cellMaxPixel: cellMaxPixel(genre.posters.count))
                // Art protection under the name, in the app's scrim tokens.
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: ThemeColor.scrim, location: 0.55),
                    .init(color: ThemeColor.scrimStrong, location: 1),
                ], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                    Text(genre.name)
                        .type(ThemeType.showTitleM)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.leading)
                    Text(Copy.Discover.genreCount(genre.count))
                        .type(ThemeType.metadata)
                        .foregroundStyle(ThemeColor.textSecondary)
                        .lineLimit(1)
                }
                .padding(ThemeSpace.x3)
            }
            .frame(maxWidth: .infinity)
            .frame(height: tileHeight)
            .clipShape(shape)
            .overlay(shape.strokeBorder(ThemeColor.posterEdge, lineWidth: FeedMetrics.hairline))
            .contentShape(shape)
        }
        .buttonStyle(OverArtPressStyle())
        .accessibilityLabel(Copy.Discover.genreA11y(name: genre.name, count: genre.count))
    }

    /// Each poster decodes at its own cell's longest edge on screen: four share the tile two by
    /// two; fewer run across it at full height.
    private func cellMaxPixel(_ count: Int) -> CGFloat {
        let n = min(max(count, 1), GenreCollage.cellLimit)
        let cell: CGSize = n == GenreCollage.cellLimit
            ? CGSize(width: tileWidth / 2, height: tileHeight / 2)
            : CGSize(width: tileWidth / CGFloat(n), height: tileHeight)
        return ceil(max(cell.width, cell.height) * displayScale)
    }
}

/// A genre's posters as one picture: four as a 2×2 mosaic, one to three side by side at the
/// tile's full height, none as the raised surface. Each poster FILLS its cell from the top (a
/// poster's faces and logotype sit high).
private struct GenreCollage: View {
    let posters: [String]
    let cellMaxPixel: CGFloat

    static let cellLimit = 4

    var body: some View {
        let urls = Array(posters.prefix(Self.cellLimit))
        ZStack {
            ThemeColor.surfaceRaised
            switch urls.count {
            case 0:
                EmptyView()
            case Self.cellLimit:
                VStack(spacing: Metrics.seam) {
                    HStack(spacing: Metrics.seam) { cell(urls[0]); cell(urls[1]) }
                    HStack(spacing: Metrics.seam) { cell(urls[2]); cell(urls[3]) }
                }
            default:
                HStack(spacing: Metrics.seam) {
                    ForEach(urls, id: \.self) { cell($0) }
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// A cell takes exactly its share (`Color.clear` accepts the proposal), and the poster fills
    /// it inside that frame.
    private func cell(_ url: String) -> some View {
        Color.clear
            .overlay {
                RemoteImageView(url: url, contentMode: .fill, maxPixel: cellMaxPixel,
                                alignment: .top, placeholderHidden: true)
            }
            .clipped()
    }
}

/// Sizes with no token. Each says why it is the number it is.
private enum Metrics {
    /// The hairline between two posters in a collage: enough that four covers read as four
    /// pictures, not one smeared one.
    static let seam: CGFloat = 1
}
