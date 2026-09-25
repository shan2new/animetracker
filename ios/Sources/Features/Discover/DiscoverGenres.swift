import SwiftUI

// GENRES — Discover's third page (ios-spec §3.6), as Apple Music's Browse grid (25 Sep: "I wanted
// something like this. Spotify UX isnt good", owner, with Apple Music's Search). Measured off that
// screenshot: two across, 12 pt apart, 16:9 tiles with a ~10-pt continuous corner; the picture
// FULL-BLEED and graded into one colour; the name bottom-left in white bold, up to two lines. No
// scrim, no shadow, no count. It replaced, the same day, Spotify's colour tile with one picture
// tilted into its corner.
//   · the picture is the genre's own art in the viewer's FLAVOUR, anime or TV (`GenreArt`); a genre
//     with none leads with a trending poster under a wash of that poster's colour;
//   · a lead poster is never the same picture twice on the page (`leads`).
// Two across; one at the accessibility sizes. A tile is a value link: it appends
// `DiscoverRoute.genre` to the Discover tab's path, whose destination is `GenreResultsView`.
//
// Equatable on what it is handed: the explore re-runs its body on the field's focus.
struct DiscoverGenres: View, @MainActor Equatable {
    let genres: [DiscoverGenre]
    /// Which picture every tile wears (`GenreArt.flavour(for:leaning:)`).
    var flavour: GenreArt.Flavour = .anime
    /// How many tiles; nil for all of them (Discover's Genres page).
    var limit: Int? = DiscoverCatalog.tileLimit
    /// The "Browse by genre" header; off where the page's tab already says it.
    var header = true

    @Environment(\.dynamicTypeSize) private var typeSize

    static func == (a: DiscoverGenres, b: DiscoverGenres) -> Bool {
        a.genres == b.genres && a.flavour == b.flavour && a.limit == b.limit && a.header == b.header
    }

    /// Apple Music's gap between tiles.
    static let gap: CGFloat = ThemeSpace.x3

    private var shown: [DiscoverGenre] { limit.map { Array(genres.prefix($0)) } ?? genres }

    var body: some View {
        let leads = Self.leads(shown)
        let columns = Array(repeating: GridItem(.flexible(), spacing: Self.gap, alignment: .top),
                            count: typeSize.isAccessibilitySize ? 1 : 2)
        VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
            if header {
                SectionHeaderRow(Copy.Discover.browseByGenre)
                    .padding(.horizontal, ThemeMetrics.gutter)
            }
            LazyVGrid(columns: columns, spacing: Self.gap) {
                ForEach(shown) { genre in
                    NavigationLink(value: DiscoverRoute.genre(key: genre.key, name: genre.name)) {
                        GenreTile(key: genre.key, name: genre.name, poster: leads[genre.key], flavour: flavour)
                    }
                    .buttonStyle(OverArtPressStyle())
                    .accessibilityLabel(Copy.Discover.genreA11y(name: genre.name, count: genre.count))
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
        }
    }

    /// Each genre's lead poster: its first that no earlier genre on the page already leads with,
    /// else its first.
    static func leads(_ genres: [DiscoverGenre]) -> [String: String] {
        var used = Set<String>()
        var out: [String: String] = [:]
        for genre in genres {
            guard let pick = genre.posters.first(where: { !used.contains($0) }) ?? genre.posters.first else { continue }
            out[genre.key] = pick
            used.insert(pick)
        }
        return out
    }
}

/// A genre's OWN art: generated per genre (icon/genres), graded into the genre's colour and imported
/// by `icon/genres/import.py` as `genre-<key>-<flavour>`. Two flavours, because the app files two
/// catalogues: ANIME art is an illustration, TV art a photograph, in the same colour. A genre only
/// one catalogue holds has that catalogue's picture only (Mecha is anime, Western is TV), whichever
/// flavour is asked for.
@MainActor
enum GenreArt {
    enum Flavour: String, CaseIterable { case anime, tv }

    /// The viewer's leaning, for the scope that holds both catalogues (All). The defaults key a
    /// personalisation toggle will write (25 Sep, owner: "We'll later on build a toggle to change
    /// personalisation according to the user"); nothing writes it yet, so it reads anime. A
    /// capture sets it with `-genreArt tv` (a launch argument IS the defaults' argument domain).
    static let leaningKey = "genreArt"

    /// A one-catalogue scope draws its own flavour; All draws the viewer's leaning.
    static func flavour(for filter: MediaFilter, leaning: String) -> Flavour {
        switch filter {
        case .anime: .anime
        case .tv: .tv
        case .all: Flavour(rawValue: leaning) ?? .anime
        }
    }

    /// The art in `flavour`, else in the other one, else nil (the tile leads with a poster).
    static func image(_ key: String, flavour: Flavour) -> UIImage? {
        let other: Flavour = flavour == .anime ? .tv : .anime
        return UIImage(named: "genre-\(key)-\(flavour.rawValue)") ?? UIImage(named: "genre-\(key)-\(other.rawValue)")
    }
}

/// Apple Music's Browse tile: the picture full-bleed, the name in white at its foot.
struct GenreTile: View {
    let key: String
    let name: String
    let poster: String?
    let flavour: GenreArt.Flavour

    /// A poster-led tile's colour, from the poster (`PaletteCache`, which remembers it across
    /// launches). A tile with art has its colour in the picture.
    @State private var tint: Color?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let aspect: CGFloat = 16 / 9
    static let radius: CGFloat = ThemeRadius.poster
    /// The name's inset from the leading edge and the foot: its baseline lands ~17 pt up (Apple's 16).
    static let nameInset: CGFloat = ThemeSpace.x3

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        Color.clear
            .aspectRatio(Self.aspect, contentMode: .fit)
            .background { picture }
            // A soft pool of shade under the name, strongest at the tile's foot-left and gone by its
            // middle: the art is not always calm where the name sits, and a text shadow reads
            // cheap. One gradient — no mask, no filter — so a scrolling grid pays nothing for it.
            .overlay {
                EllipticalGradient(stops: [.init(color: .black.opacity(0.46), location: 0),
                                           .init(color: .black.opacity(0.18), location: 0.45),
                                           .init(color: .clear, location: 0.85)],
                                   center: .bottomLeading, startRadiusFraction: 0, endRadiusFraction: 1)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                Text(name)
                    .type(ThemeType.genreName)
                    .foregroundStyle(.white)
                    // Wrapped at its spaces only: Text breaks a word that cannot fit its line
                    // ("Psychologica / l"), so a one-word name keeps one line and shrinks instead.
                    .lineLimit(name.contains(" ") ? 2 : 1)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
                    .padding([.horizontal, .bottom], Self.nameInset)
            }
            .clipShape(shape)
            .contentShape(shape)
            .task(id: poster) {
                guard GenreArt.image(key, flavour: flavour) == nil, let poster else { return }
                if tint == nil, let known = PaletteCache.shared.tint(for: poster) { tint = Self.vivid(known) }
                let resolved = Self.vivid(await PaletteCache.shared.resolve(url: poster, maxPixel: 300))
                guard resolved != tint else { return }
                withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) { tint = resolved }
            }
    }

    @ViewBuilder
    private var picture: some View {
        if let art = GenreArt.image(key, flavour: flavour) {
            Image(uiImage: art)
                .resizable()
                .scaledToFill()
                .accessibilityHidden(true)
        } else {
            let ground = tint ?? ThemeColor.surfaceRaised
            ground.overlay {
                if let poster {
                    // The poster under a wash of its own colour: the graded tiles' kin.
                    RemoteImageView(url: poster, contentMode: .fill, maxPixel: 600, alignment: .top,
                                    placeholderHidden: true)
                        .overlay(ground.opacity(0.6))
                        .accessibilityHidden(true)
                }
            }
        }
    }

    /// The poster's hue as a tile: OKLab lightness 0.45 and chroma 0.10–0.14, so every genre
    /// reads as a colour (a grey poster still gets a hue's worth of chroma) and white type holds
    /// on all of them.
    static func vivid(_ color: Color) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return color }
        var (_, ca, cb) = PaletteCache.oklab(r: Double(r), g: Double(g), b: Double(b))
        let chroma = (ca * ca + cb * cb).squareRoot()
        let target = min(max(chroma, 0.10), 0.14)
        if chroma > 0.0001 {
            ca *= target / chroma
            cb *= target / chroma
        }
        let (vr, vg, vb) = PaletteCache.srgb(l: 0.45, a: ca, b: cb)
        return Color(.sRGB, red: vr, green: vg, blue: vb, opacity: 1)
    }
}
