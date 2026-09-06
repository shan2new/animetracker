import Foundation

// The catalogue's deeper metadata (docs/api-contract.md, "Catalogue enrichment"): artwork with
// its orientation stated, trailers, audience ratings, people, related titles, streaming
// availability, and the server's own "continue watching" pointer.
//
// Every field here decodes LENIENTLY. A server older than the field, or a row the server's
// stale-while-revalidate pass has not reached yet, must read as EMPTY — never as a decode failure
// that drops the whole franchise. The screens hide a section that is empty and draw it when it
// arrives; nothing here may throw past the franchise.

// MARK: - Artwork

/// Artwork with its orientation stated. A missing landscape asset is `nil`: the server never puts
/// a portrait poster in the landscape slot, so `nil` here is the signal to composite the cover
/// whole (`LandscapeArt(portraitSource:)`) rather than crop it to a forehead.
struct ArtworkSet: Codable, Hashable, Sendable {
    let portrait: String?
    let landscape: String?

    enum CodingKeys: String, CodingKey { case portrait, landscape }

    init(portrait: String?, landscape: String?) {
        self.portrait = ArtworkSet.nonEmpty(portrait)
        self.landscape = ArtworkSet.nonEmpty(landscape)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(portrait: try? c.decodeIfPresent(String.self, forKey: .portrait),
                  landscape: try? c.decodeIfPresent(String.self, forKey: .landscape))
    }

    /// An empty string is no artwork.
    static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
    }
}

/// One ranked artwork candidate from the server's gallery. Everything but the URL is optional
/// and informational — the app never re-ranks on `score`, `width` or `source`; the server's
/// order IS the ranking.
struct ArtworkImage: Codable, Hashable, Sendable {
    let url: String
    let source: String?
    let width: Int?
    let height: Int?
    let language: String?
    let score: Double?

    enum CodingKeys: String, CodingKey { case url, source, width, height, language, score }

    init(url: String, source: String? = nil, width: Int? = nil, height: Int? = nil,
         language: String? = nil, score: Double? = nil) {
        self.url = url; self.source = source; self.width = width; self.height = height
        self.language = language; self.score = score
    }

    /// Throws only for a missing or empty URL — the one thing an image cannot be without. The
    /// gallery's decoder drops such an entry and keeps the rest.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let url = ArtworkSet.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .url)) else {
            throw DecodingError.dataCorruptedError(forKey: .url, in: c, debugDescription: "artwork without a url")
        }
        self.url = url
        source = ArtworkSet.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .source))
        width = try? c.decodeIfPresent(Int.self, forKey: .width)
        height = try? c.decodeIfPresent(Int.self, forKey: .height)
        language = ArtworkSet.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .language))
        // A score may arrive as an integer; `Double` decodes both.
        score = try? c.decodeIfPresent(Double.self, forKey: .score)
    }
}

/// One element of a list decoded on its own, so a malformed entry drops itself instead of the
/// whole array. `value` is nil for the entry that failed.
private struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) { value = try? T(from: decoder) }
}

/// The server's ranked artwork alternatives, BY ORIENTATION — portraits, landscapes and logos
/// kept apart, never folded into one "artwork" list. The order in each list is the server's
/// ranking and is authoritative: the first entry is what `ArtworkSet` selected, the rest are the
/// alternatives it passed over. Decodes leniently: a missing list is empty, a malformed entry is
/// dropped, and nothing here throws past the franchise.
struct ArtworkGallery: Codable, Hashable, Sendable {
    let portraits: [ArtworkImage]
    let landscapes: [ArtworkImage]
    let logos: [ArtworkImage]

    static let empty = ArtworkGallery(portraits: [], landscapes: [], logos: [])

    enum CodingKeys: String, CodingKey { case portraits, landscapes, logos }

    init(portraits: [ArtworkImage], landscapes: [ArtworkImage], logos: [ArtworkImage]) {
        self.portraits = portraits; self.landscapes = landscapes; self.logos = logos
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func list(_ key: CodingKeys) -> [ArtworkImage] {
            ((try? c.decodeIfPresent([Lenient<ArtworkImage>].self, forKey: key)) ?? []).compactMap(\.value)
        }
        portraits = list(.portraits)
        landscapes = list(.landscapes)
        logos = list(.logos)
    }

    /// The first ranked portrait with no language tag, trusted ONLY when the gallery is tagged at
    /// all — at least one portrait carries a language. A missing tag means "textless" on a ranked
    /// gallery and means nothing on the older shape the server still sends for some rows (no
    /// scores, no sizes, no languages): Bleach's first titled poster passed as textless there and
    /// the text title landed on top of a 100-pt BLEACH logotype (5 Sep).
    var textlessPortrait: String? {
        guard portraits.contains(where: { ArtworkSet.nonEmpty($0.language) != nil }) else { return nil }
        return portraits.first { ArtworkSet.nonEmpty($0.language) == nil }?.url
    }

    var isEmpty: Bool { portraits.isEmpty && landscapes.isEmpty && logos.isEmpty }
}

/// The one decision a wide frame makes: a landscape asset fills it; a portrait one is composited
/// whole on its own blurred ground. Callers pass both halves straight to `LandscapeArt`,
/// `ProgressBanner`, `BannerCard` or `ArtHeader` and never re-derive the choice.
struct WideArt: Hashable, Sendable {
    let url: String?
    /// `url` is a 2:3 cover.
    let portraitSource: Bool
    /// `url` is an AniList banner — 1900×400 (some 1800×550), far wider than any frame that shows
    /// it — so a 16:9 frame must decode it at its native width or draw a ~2.5× upscale of the
    /// middle third (`LandscapeArt.ultraWide`). Decided by the URL, not the source: an enriched
    /// anime franchise may carry a TMDB backdrop, and that IS 16:9. (Every landscape asset in the
    /// library was one of these on 4 Sep. Compositing the cover on the blurred banner instead of
    /// cropping was tried that day and reverted — "the images were just fine", user.)
    let ultraWide: Bool

    init(landscape: String?, portrait: String?) {
        if let landscape {
            url = landscape
            portraitSource = false
            ultraWide = landscape.contains("/anime/banner/")
        } else {
            url = portrait
            portraitSource = true
            ultraWide = false
        }
    }

    /// A billboard's art: the poster whenever there is one — `ArtHeader(portraitSource: true)`
    /// composites it whole in a frame that is nearly its own shape — and a landscape only for a
    /// show the catalogue never gave a poster.
    static func billboard(portrait: String?, landscape: String?) -> WideArt {
        portrait != nil ? WideArt(landscape: nil, portrait: billboardResolution(portrait))
                        : WideArt(landscape: billboardResolution(landscape), portrait: nil)
    }

    /// TMDB serves an image at the size named in its path, and the server hands out `w780`
    /// posters — a 780-px file that a billboard draws 1179 px wide on a 3× phone, a 1.5× upscale
    /// of the one sharp asset in the frame (measured 5 Sep; the original is 2000×3000). A
    /// billboard asks for `original`; every card keeps the size it was sent. Only TMDB paths are
    /// rewritten — AniList's CDN has no size ladder.
    static func billboardResolution(_ url: String?) -> String? {
        guard let url, url.contains("image.tmdb.org/t/p/w") else { return url }
        return url.replacingOccurrences(of: #"/t/p/w\d+/"#, with: "/t/p/original/", options: .regularExpression)
    }
}

/// The legacy `banner` field, trusted only when it is a banner. Writers older than the explicit
/// artwork set copied a portrait cover into `banner` when the catalogue had no landscape asset;
/// exact URL equality is that copy, and it is a poster, not a banner.
private func legacyBanner(_ banner: String?, cover: String?) -> String? {
    guard let b = ArtworkSet.nonEmpty(banner), b != cover else { return nil }
    return b
}

// The art accessors, and the ONE order they answer in. The server selects the best asset per
// orientation (`images`), keeps its ranked alternatives beside it (`artwork`), and mirrors the
// selection into the legacy `cover`/`banner` for older clients. A view reads:
//   · `portraitArt`  — grids, rows, shelves, posters:  images.portrait → artwork.portraits.first → cover
//   · `landscapeArt` — a wide frame's fill:            images.landscape → artwork.landscapes.first → banner
//   · `billboardArt` — a HERO (Today's billboard, Detail's, the trending billboard): the PORTRAIT
//                      first, composited whole through `ArtHeader(portraitSource:)`, and the
//                      landscape only when the catalogue has no poster. The billboard frame is
//                      ~0.64 w/h — within 4 % of a 2:3 poster — so a 16:9 backdrop filled into it
//                      shows its middle ~36 % (production, 4 Sep: every show had a TMDB backdrop
//                      and every billboard was a zoomed slice; "supposed to be portrait", user).
// The gallery's first entry is the server's own top rank — read, never re-sorted by score, size or
// provider — and a URL is used exactly as sent.

extension Franchise {
    /// The 2:3 cover — `images.portrait`, else the gallery's top portrait, else the legacy field
    /// an older server sends.
    var portraitArt: String? {
        images?.portrait ?? artwork?.portraits.first?.url ?? ArtworkSet.nonEmpty(cover)
    }
    /// The landscape asset, or nil when the catalogue has none. Never a portrait poster.
    var landscapeArt: String? {
        images?.landscape ?? artwork?.landscapes.first?.url ?? legacyBanner(banner, cover: cover)
    }
    /// Art for a wide frame: the landscape, else the cover composited.
    var wideArt: WideArt { WideArt(landscape: landscapeArt, portrait: portraitArt) }
    /// Art for a billboard hero: the portrait first (the frame is its shape), the landscape only
    /// when there is none — and the TEXTLESS portrait where the gallery has one (`textlessPortrait`).
    var billboardArt: WideArt {
        WideArt.billboard(portrait: textlessPortrait ?? portraitArt, landscape: landscapeArt)
    }
    /// The first poster the server ranked that carries no language — TMDB's textless key art.
    /// A per-surface FILTER on the server's order, not a re-rank: the billboard draws the name
    /// itself (`billboardLogo`, else the title), so the selected poster's own logotype sat right
    /// under our title ("something is seriously wrong here", user, 4 Sep). Grids keep the
    /// selected poster, where the logotype identifies the show. See `ArtworkGallery.textlessPortrait`
    /// for the one condition on trusting a missing tag.
    var textlessPortrait: String? { artwork?.textlessPortrait }
    /// The show's logo treatment — the server's first-ranked logo — for the billboard's name
    /// (Netflix's, Disney+'s billboard grammar). `nil` reads as "set the name in type".
    var billboardLogo: ArtworkImage? { artwork?.logos.first }
    /// What the billboard draws for the name — see `BillboardName`.
    var billboardName: BillboardName {
        BillboardName.resolve(portrait: portraitArt, textless: textlessPortrait, gallery: artwork, logo: billboardLogo)
    }
}

/// What a billboard draws for the show's NAME, decided by what the art under it already says.
///
/// There is deliberately no "the art carries the name" case any more (5 Sep). It assumed the
/// poster's logotype sits where the copy does; Re:ZERO's sits in the top band — under the back
/// button, the status capsule and the top veil — so the page drew no name and hid the one on the
/// poster, and on Today the wordmark band covers the same zone: a hero with no visible name at
/// all. A name is ALWAYS drawn. Where the selected poster is titled and the gallery has no
/// textless one it is drawn in TYPE, never as a logo — a logo would set the poster's own
/// logotype twice in the same hand, while type beside titled key art is Crunchyroll's and Prime
/// Video's ordinary caption. The real fix for those shows is a textless poster from the server's
/// enrichment; the client's job is to never leave the name off.
enum BillboardName: Hashable, Sendable {
    /// The show's logo treatment. `HeroTitle` draws it only at the headline's mass
    /// (`HeroTitle.logoBox`) and sets the name in type otherwise.
    case logo(ArtworkImage)
    /// The name set in type.
    case type

    static func resolve(portrait: String?, textless: String?, gallery: ArtworkGallery?, logo: ArtworkImage?) -> BillboardName {
        if textless == nil, let portrait,
           let selected = gallery?.portraits.first(where: { $0.url == portrait }),
           ArtworkSet.nonEmpty(selected.language) != nil {
            return .type
        }
        if let logo { return .logo(logo) }
        return .type
    }
}

extension FranchisePart {
    var portraitArt: String? {
        images?.portrait ?? artwork?.portraits.first?.url ?? ArtworkSet.nonEmpty(cover)
    }
    var landscapeArt: String? {
        images?.landscape ?? artwork?.landscapes.first?.url ?? legacyBanner(banner, cover: cover)
    }
    /// This part's OWN art for a wide frame — its banner, else its cover composited. The season
    /// screen's header is the season's picture, never the show's.
    var wideArt: WideArt { WideArt(landscape: landscapeArt, portrait: portraitArt) }
    /// The part's art with the show's behind it, for a card that is about the show as much as the
    /// season (Library's Continue watching, the season screen's header). A TRUE 16:9 wins at either
    /// level before any AniList banner does: the season's `images.landscape` on production is its
    /// banner, and a 4.75:1 banner's middle third in a 16:9 card was a pair of eyes (Library's
    /// Continue card, 4 Sep) while the show had a real backdrop one level up. A banner still beats
    /// the poster composite — that crop was accepted on 4 Sep for AniList-only shows.
    func wideArt(within f: Franchise) -> WideArt {
        let candidates = [wideArt, f.wideArt]
        if let real = candidates.first(where: { !$0.portraitSource && !$0.ultraWide }) { return real }
        if let banner = candidates.first(where: { !$0.portraitSource }) { return banner }
        return WideArt(landscape: nil, portrait: portraitArt ?? f.portraitArt)
    }
    /// A TRUE 16:9 landscape for a 16:9 tile (the episode still's fallback): the season's, else
    /// the show's — never an AniList banner. A 4.75:1 banner filled into a 120×68 tile shows its
    /// middle third, which on production (4 Sep) was a pair of eyes eighteen times down the list.
    func stillLandscape(within f: Franchise) -> String? {
        [wideArt, f.wideArt].first { !$0.portraitSource && !$0.ultraWide }?.url
    }
}

extension FranchiseSummary {
    var portraitArt: String? {
        images?.portrait ?? artwork?.portraits.first?.url ?? ArtworkSet.nonEmpty(cover)
    }
    var landscapeArt: String? {
        images?.landscape ?? artwork?.landscapes.first?.url ?? legacyBanner(banner, cover: cover)
    }
    var wideArt: WideArt { WideArt(landscape: landscapeArt, portrait: portraitArt) }
    /// Art for a billboard hero (the trending billboard): the textless portrait first.
    var billboardArt: WideArt {
        WideArt.billboard(portrait: textlessPortrait ?? portraitArt, landscape: landscapeArt)
    }
    var textlessPortrait: String? { artwork?.textlessPortrait }
    var billboardLogo: ArtworkImage? { artwork?.logos.first }
    var billboardName: BillboardName {
        BillboardName.resolve(portrait: portraitArt, textless: textlessPortrait, gallery: artwork, logo: billboardLogo)
    }
}

// MARK: - Videos

/// A catalogue-curated external video — a trailer, a teaser, a renewal announcement. The app
/// stores the provider's id and link; it never hosts the bytes. `featuredVideo` is the server's
/// pick (an upcoming or current part first, then official status and recency).
struct FranchiseVideo: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case trailer, teaser, announcement, featurette, clip, other
    }

    /// Whole-franchise, or one exact season/movie.
    enum Scope: Equatable, Sendable {
        case franchise
        case part(mediaId: Int, label: String)
    }

    /// The provider's id ("ldfEtPf3CfQ"). Also the `Identifiable` id — the site is a single
    /// provider in practice, and two videos of one show never share an id.
    let id: String
    /// Lower-cased provider name; "youtube" is the only one the app plays in place.
    let site: String
    let kind: Kind
    let title: String?
    let url: String?
    let thumbnail: String?
    let official: Bool?
    let language: String?
    let country: String?
    let publishedAt: String?
    let scope: Scope

    enum CodingKeys: String, CodingKey {
        case id, site, kind, title, url, thumbnail, official, language, country, publishedAt, scope
    }

    private enum ScopeKeys: String, CodingKey { case type, mediaId, label }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        site = ((try? c.decode(String.self, forKey: .site)) ?? "").lowercased()
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .other
        title = ArtworkSet.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .title))
        url = ArtworkSet.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .url))
        thumbnail = ArtworkSet.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .thumbnail))
        official = try? c.decodeIfPresent(Bool.self, forKey: .official)
        language = try? c.decodeIfPresent(String.self, forKey: .language)
        country = try? c.decodeIfPresent(String.self, forKey: .country)
        publishedAt = try? c.decodeIfPresent(String.self, forKey: .publishedAt)
        if let s = try? c.nestedContainer(keyedBy: ScopeKeys.self, forKey: .scope),
           (try? s.decode(String.self, forKey: .type)) == "part",
           let mediaId = try? s.decode(Int.self, forKey: .mediaId) {
            scope = .part(mediaId: mediaId, label: (try? s.decodeIfPresent(String.self, forKey: .label)) ?? "")
        } else {
            scope = .franchise
        }
    }

    /// Written in the contract's own shape, so the library's offline copy reads back exactly.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(site, forKey: .site)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(thumbnail, forKey: .thumbnail)
        try c.encodeIfPresent(official, forKey: .official)
        try c.encodeIfPresent(language, forKey: .language)
        try c.encodeIfPresent(country, forKey: .country)
        try c.encodeIfPresent(publishedAt, forKey: .publishedAt)
        var s = c.nestedContainer(keyedBy: ScopeKeys.self, forKey: .scope)
        switch scope {
        case .franchise:
            try s.encode("franchise", forKey: .type)
        case .part(let mediaId, let label):
            try s.encode("part", forKey: .type)
            try s.encode(mediaId, forKey: .mediaId)
            try s.encode(label, forKey: .label)
        }
    }

    init(id: String, site: String, kind: Kind, title: String?, url: String? = nil, thumbnail: String? = nil,
         official: Bool? = nil, language: String? = nil, country: String? = nil, publishedAt: String? = nil,
         scope: Scope = .franchise) {
        self.id = id; self.site = site.lowercased(); self.kind = kind; self.title = title; self.url = url
        self.thumbnail = thumbnail; self.official = official; self.language = language; self.country = country
        self.publishedAt = publishedAt; self.scope = scope
    }

    /// The YouTube id when this is a YouTube video — the one provider the app plays in place.
    var youtubeID: String? { site == "youtube" ? id : nil }

    /// Where the viewer goes to watch it outside the app: the catalogue's link, else the
    /// provider's own page for the id.
    var watchURL: URL? {
        url.flatMap(URL.init(string:)) ?? youtubeID.flatMap { URL(string: "https://www.youtube.com/watch?v=\($0)") }
    }

    /// The in-app player page (YouTube only): autoplaying, no related-video wall. Not `playsinline`
    /// — the trailer cover hands playback to the system's full-screen player (`VideoEmbed`).
    var embedURL: URL? {
        youtubeID.flatMap {
            URL(string: "https://www.youtube.com/embed/\($0)?autoplay=1&rel=0&modestbranding=1")
        }
    }

    /// The still to draw the card with: the catalogue's, else the provider's own 16:9 frame.
    var thumbnailURL: String? {
        thumbnail ?? youtubeID.map { "https://i.ytimg.com/vi/\($0)/mqdefault.jpg" }
    }

    /// The card's name: the catalogue's title, else what kind of video it is.
    var displayTitle: String { title ?? Copy.Video.kind(kind) }

    /// The provider's title without the show's name and its separator — "Game of Thrones |
    /// Official Series Trailer" under a lockup that already says "Game of Thrones" said the name
    /// twice (review, 5 Sep). Nil when nothing but the name is left.
    func title(cleanedFor show: String?) -> String? {
        guard var t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        if let show, !show.isEmpty {
            let lower = t.lowercased(), name = show.lowercased()
            if lower.hasPrefix(name) {
                t = String(t.dropFirst(show.count)).trimmingCharacters(in: CharacterSet(charactersIn: " |-–—:·"))
            } else if lower.hasSuffix(name) {
                t = String(t.dropLast(show.count)).trimmingCharacters(in: CharacterSet(charactersIn: " |-–—:·"))
            }
        }
        // A trailing "| Provider" credit is the provider's, not the video's.
        if let bar = t.range(of: " | ", options: .backwards), t[bar.upperBound...].count <= 24 {
            t = String(t[..<bar.lowerBound])
        }
        // A trailing "(Provider)" credit is the provider's too, and a provider's straight quotes
        // are set as the app sets them (review i4).
        t = t.replacingOccurrences(of: #"\s*\([A-Za-z][\w+ ]{1,20}\)$"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #""([^"]*)""#, with: "\u{201C}$1\u{201D}", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// The provider's name as it is written, from the wire's lowercase `site` ("youtube").
    static func providerName(_ site: String) -> String? {
        switch site.trimmingCharacters(in: .whitespaces).lowercased() {
        case "": return nil
        case "youtube": return "YouTube"
        case "vimeo": return "Vimeo"
        default: return site.capitalized
        }
    }

    /// "Season 6" when the video belongs to one part.
    var partLabel: String? {
        if case .part(_, let label) = scope, !label.isEmpty { return label }
        return nil
    }
}

// MARK: - Audience

struct ContentRating: Codable, Hashable, Sendable {
    let country: String
    let rating: String
}

/// Who a title is for. `contentRating` is the exact match for the market the app asked for; the
/// server does not substitute another country's rating, so a miss is `nil`, never "US".
struct AudienceInfo: Codable, Equatable, Sendable {
    let isAdult: Bool?
    let contentRating: ContentRating?
    let availableRatings: [ContentRating]

    enum CodingKeys: String, CodingKey { case isAdult, contentRating, availableRatings }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isAdult = try? c.decodeIfPresent(Bool.self, forKey: .isAdult)
        contentRating = try? c.decodeIfPresent(ContentRating.self, forKey: .contentRating)
        availableRatings = (try? c.decode([ContentRating].self, forKey: .availableRatings)) ?? []
    }

    init(isAdult: Bool?, contentRating: ContentRating?, availableRatings: [ContentRating] = []) {
        self.isAdult = isAdult; self.contentRating = contentRating; self.availableRatings = availableRatings
    }
}

// MARK: - People

/// A creator, a director, or a cast member. Anime cast are Japanese voice actors with the
/// character in `role`; general TV cast are top-billed with their character.
struct CatalogPerson: Codable, Identifiable, Hashable, Sendable {
    let source: MediaSource
    let externalId: Int
    let name: String
    let role: String?
    let image: String?

    /// One person can appear once per role (a director who also acts).
    var id: String { "\(source.rawValue):\(externalId):\(role ?? "")" }

    /// The role without a quoted nickname — "Tyrion 'The Halfman' Lannister" lost its surname to
    /// the quote in a one-line caption (review i2).
    var displayRole: String? {
        guard let role else { return nil }
        // A plain string with Swift escapes, NOT a raw string: `#"\u{201C}"#` handed ICU the six
        // characters `\u{201C}`, the pattern never compiled, and the replacement returned its
        // input (review i3 — the nicknames were never stripped).
        let bare = role.replacingOccurrences(of: "\\s*['\"\u{201C}\u{2018}][^'\"\u{201D}\u{2019}]*['\"\u{201D}\u{2019}]\\s*", with: " ",
                                             options: .regularExpression)
            .replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
        return bare.isEmpty ? role : bare
    }

    enum CodingKeys: String, CodingKey { case source, externalId, name, role, image }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = (try? c.decode(MediaSource.self, forKey: .source)) ?? .anilist
        externalId = (try? c.decode(Int.self, forKey: .externalId)) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        role = ArtworkSet.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .role))
        image = ArtworkSet.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .image))
    }

    init(source: MediaSource, externalId: Int, name: String, role: String?, image: String?) {
        self.source = source; self.externalId = externalId; self.name = name; self.role = role; self.image = image
    }
}

struct FranchisePeople: Codable, Equatable, Sendable {
    let creators: [CatalogPerson]
    let directors: [CatalogPerson]
    let cast: [CatalogPerson]

    enum CodingKeys: String, CodingKey { case creators, directors, cast }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        creators = ((try? c.decode([CatalogPerson].self, forKey: .creators)) ?? []).filter { !$0.name.isEmpty }
        directors = ((try? c.decode([CatalogPerson].self, forKey: .directors)) ?? []).filter { !$0.name.isEmpty }
        cast = ((try? c.decode([CatalogPerson].self, forKey: .cast)) ?? []).filter { !$0.name.isEmpty }
    }

    init(creators: [CatalogPerson] = [], directors: [CatalogPerson] = [], cast: [CatalogPerson] = []) {
        self.creators = creators; self.directors = directors; self.cast = cast
    }

    var isEmpty: Bool { creators.isEmpty && directors.isEmpty && cast.isEmpty }

    /// The shelf's order — the people who made it, then the people in it — each with a role word
    /// where the catalogue gave none, so a face is never unexplained. De-duplicated by id.
    var ordered: [CatalogPerson] {
        var seen = Set<String>()
        func named(_ people: [CatalogPerson], role: String) -> [CatalogPerson] {
            people.map { $0.role == nil ? CatalogPerson(source: $0.source, externalId: $0.externalId, name: $0.name, role: role, image: $0.image) : $0 }
        }
        // Cast FIRST — the faces a viewer recognises are the row's reason — then the creators,
        // then only the directors who direct: the server files camera and assistant-director
        // crew under `directors`, and Thrones' row opened on a director of photography and a
        // third assistant director (review, 5 Sep). Capped at 16.
        let keep = ["director", "creator", "showrunner", "writer", "executive producer", "series director"]
        let directing = named(directors, role: Copy.People.director).filter { p in
            guard let r = p.role?.lowercased() else { return true }
            return keep.contains(r)
        }
        return Array((Array(cast.prefix(10)) + named(creators, role: Copy.People.creator) + directing)
            .filter { seen.insert($0.id).inserted }
            .prefix(16))
    }
}

// MARK: - Related titles

/// A source-native recommendation. `franchiseId` is filled only once the title exists locally;
/// otherwise the title is the way to find it.
struct RelatedTitle: Codable, Identifiable, Hashable, Sendable {
    let source: MediaSource
    let externalId: Int
    let franchiseId: String?
    let title: String
    let year: Int?
    let images: ArtworkSet?

    var id: String { "\(source.rawValue):\(externalId)" }

    enum CodingKeys: String, CodingKey { case source, externalId, franchiseId, title, year, images }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = (try? c.decode(MediaSource.self, forKey: .source)) ?? .anilist
        externalId = (try? c.decode(Int.self, forKey: .externalId)) ?? 0
        franchiseId = ArtworkSet.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .franchiseId))
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        year = try? c.decodeIfPresent(Int.self, forKey: .year)
        images = try? c.decodeIfPresent(ArtworkSet.self, forKey: .images)
    }

    var portraitArt: String? { images?.portrait }

    /// "Anime · 2017" — the same two facts a Search tile states.
    var identityLine: String {
        guard let year else { return source.kindWord }
        return "\(source.kindWord) \u{00B7} \(year)"
    }
}

// MARK: - Continue watching

/// The server's own answer to "what do I watch next": the first already-aired episode the user
/// has not watched, with whatever the catalogue knows about it. User-specific, never unaired.
struct ContinueWatching: Codable, Sendable {
    let mediaId: Int
    let partLabel: String
    let episode: Episode

    enum CodingKeys: String, CodingKey { case mediaId, partLabel, episode }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mediaId = try c.decode(Int.self, forKey: .mediaId)
        partLabel = (try? c.decode(String.self, forKey: .partLabel)) ?? ""
        episode = try c.decode(Episode.self, forKey: .episode)
    }

    init(mediaId: Int, partLabel: String, episode: Episode) {
        self.mediaId = mediaId; self.partLabel = partLabel; self.episode = episode
    }
}

// MARK: - Where to watch

/// Country-specific streaming availability (`GET /franchises/:id/watch-providers`). Consumers
/// branch on `status`, never on `providers.isEmpty`: `notAvailable` is a matched title with no
/// streaming option in that country, `unmatched` means the anime→TMDB bridge could not establish
/// identity safely, and `disabled` means this deployment has no TMDB token.
struct WatchAvailability: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case available
        case notAvailable = "not_available"
        case unmatched
        case disabled
    }

    let country: String
    let status: Status
    /// Subscription services first, then free and ad-supported.
    let providers: [WatchProvider]
    /// The provider data's regional watch page — the only reliable link there is.
    let link: String?
    /// Required attribution for the provider data ("JustWatch").
    let attribution: String

    enum CodingKeys: String, CodingKey { case country, status, providers, link, attribution }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        country = (try? c.decode(String.self, forKey: .country)) ?? ""
        status = (try? c.decode(Status.self, forKey: .status)) ?? .unmatched
        providers = (try? c.decode([WatchProvider].self, forKey: .providers)) ?? []
        link = ArtworkSet.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .link))
        attribution = (try? c.decode(String.self, forKey: .attribution)) ?? "JustWatch"
    }

    init(country: String, status: Status, providers: [WatchProvider], link: String?, attribution: String = "JustWatch") {
        self.country = country; self.status = status; self.providers = providers; self.link = link
        self.attribution = attribution
    }

    var linkURL: URL? { link.flatMap(URL.init(string:)) }
}

struct WatchProvider: Codable, Identifiable, Hashable, Sendable {
    enum Access: String, Codable, Sendable { case subscription, free, ads }

    let id: Int
    let name: String
    let logo: String?
    let access: Access

    enum CodingKeys: String, CodingKey { case id, name, logo, access }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        logo = ArtworkSet.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .logo))
        access = (try? c.decode(Access.self, forKey: .access)) ?? .subscription
    }

    init(id: Int, name: String, logo: String?, access: Access) {
        self.id = id; self.name = name; self.logo = logo; self.access = access
    }
}

// MARK: - The viewer's market

enum AppRegion {
    /// The viewer's market as the catalogue names it — ISO 3166-1 alpha-2, upper-case. A device
    /// that states no region falls back to "US": an unset region is not "no market".
    static var current: String {
        let code = (Locale.current.region?.identifier ?? "").uppercased()
        return code.count == 2 && code.allSatisfy(\.isLetter) ? code : "US"
    }
}

// MARK: - Franchise · the enriched view

extension FranchiseUpcoming {
    /// An unconfirmed report. It must be LABELLED as one wherever it is shown, and it is never a
    /// schedule: the server resolves its window to `unknown`, so it already sorts last.
    var isRumored: Bool { status == "rumored" }
}

extension Franchise {
    /// Every trailer and clip the show carries, featured first, then the show's own, then each
    /// part's — de-duplicated by provider id.
    var allVideos: [FranchiseVideo] {
        var seen = Set<String>()
        let all = [featuredVideo].compactMap { $0 } + videos + parts.flatMap(\.videos)
        return all.filter { seen.insert("\($0.site)/\($0.id)").inserted }
    }

    /// The rating word for the identity line — the market's own ("TV-MA", "U/A 16+"), else the
    /// catalogue's adult flag as "18+". Nothing when the catalogue says nothing.
    var contentRatingLabel: String? {
        if let rating = audience?.contentRating?.rating, !rating.isEmpty { return rating }
        return audience?.isAdult == true ? Copy.Label.adultRating : nil
    }

    /// Themes the identity line's genre run does not already state — the catalogue's themes for
    /// an anime often ARE its genres, and a fact printed twice on one screen is a defect.
    var themesBeyondGenres: [String] {
        let genres = Set((genres + parts.flatMap(\.genres)).map { $0.lowercased() })
        return themes.filter { !genres.contains($0.lowercased()) }
    }

    /// True while the server's background enrichment has not reached this row yet — nothing to
    /// draw in the people, related and trailer sections. Detail re-reads once on seeing this.
    var looksUnenriched: Bool {
        (people?.isEmpty ?? true) && related.isEmpty && videos.isEmpty && featuredVideo == nil
    }

    /// The live LIBRARY copy (fresh progress and status) with the DETAIL fetch's per-episode data
    /// and catalogue enrichment grafted on. The library payload carries the enrichment too, but it
    /// was read at launch — before the server's stale-while-revalidate pass may have run — so a
    /// detail read that came back richer wins, field by field; the market-matched `audience` and
    /// the fresher `continueWatching` always come from the detail read.
    /// This copy with the OTHER copy's selected art (interactive review: removing a show swapped
    /// its billboard — the library payload and the catalogue read select different posters).
    func keepingArt(of other: Franchise) -> Franchise {
        Franchise(copying: self, parts: parts,
                  images: other.images ?? images,
                  artwork: other.artwork ?? artwork,
                  themes: themes, featuredVideo: featuredVideo, videos: videos,
                  audience: audience, people: people, related: related,
                  continueWatching: continueWatching)
    }

    func grafting(_ fetched: Franchise) -> Franchise {
        guard fetched.id == id else { return self }
        let byMedia = Dictionary(fetched.parts.map { ($0.mediaId, $0) }, uniquingKeysWith: { a, _ in a })
        let mergedParts = parts.map { p -> FranchisePart in
            guard let d = byMedia[p.mediaId] else { return p }
            let eps = p.episodes.isEmpty ? d.episodes : p.episodes
            let vids = p.videos.isEmpty ? d.videos : p.videos
            let imgs = p.images ?? d.images
            let gallery = p.artwork ?? d.artwork
            if eps.count == p.episodes.count, vids.count == p.videos.count, imgs == p.images,
               gallery == p.artwork { return p }
            return p.with(episodes: eps, images: imgs, artwork: gallery, videos: vids)
        }
        return Franchise(copying: self, parts: mergedParts,
                         images: images ?? fetched.images,
                         artwork: artwork ?? fetched.artwork,
                         themes: themes.isEmpty ? fetched.themes : themes,
                         featuredVideo: featuredVideo ?? fetched.featuredVideo,
                         videos: videos.isEmpty ? fetched.videos : videos,
                         audience: fetched.audience ?? audience,
                         people: (people?.isEmpty ?? true) ? fetched.people : people,
                         related: related.isEmpty ? fetched.related : related,
                         continueWatching: fetched.continueWatching ?? continueWatching)
    }
}

extension FranchisePart {
    /// A copy with the user's progress replaced. Every optimistic write goes through this so a
    /// local mark never drops a field the server sent — `airings` used to fall off here, and a
    /// marked show left the calendar until the next reload.
    func withProgress(_ episodes: Int) -> FranchisePart {
        FranchisePart(mediaId: mediaId, kind: kind, sequence: sequence, label: label, title: title,
                      cover: cover, banner: banner, format: format, relationship: relationship, status: status,
                      isReleasing: isReleasing, totalEpisodes: totalEpisodes, airedEpisodes: airedEpisodes,
                      nextEpisodeNumber: nextEpisodeNumber, nextAiringAt: nextAiringAt, lastAiredAt: lastAiredAt,
                      synopsis: synopsis, genres: genres, progress: max(0, episodes),
                      year: year, studios: studios, nextAiringCount: nextAiringCount, episodes: self.episodes,
                      release: release, airings: airings, images: images, artwork: artwork, videos: videos)
    }

    /// A copy with the detail read's catalogue fields grafted on.
    func with(episodes eps: [Episode], images imgs: ArtworkSet?, artwork gallery: ArtworkGallery?,
              videos vids: [FranchiseVideo]) -> FranchisePart {
        FranchisePart(mediaId: mediaId, kind: kind, sequence: sequence, label: label, title: title,
                      cover: cover, banner: banner, format: format, relationship: relationship, status: status,
                      isReleasing: isReleasing, totalEpisodes: totalEpisodes, airedEpisodes: airedEpisodes,
                      nextEpisodeNumber: nextEpisodeNumber, nextAiringAt: nextAiringAt, lastAiredAt: lastAiredAt,
                      synopsis: synopsis, genres: genres, progress: progress,
                      year: year, studios: studios, nextAiringCount: nextAiringCount, episodes: eps,
                      release: release, airings: airings, images: imgs, artwork: gallery, videos: vids)
    }
}
