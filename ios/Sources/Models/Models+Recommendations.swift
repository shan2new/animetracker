import Foundation

// "Recommended for you" — second-degree recommendations from the user's own library
// (`GET /me/recommendations`, docs/api-contract.md). The server ranks: every show the user has
// casts one vote across its catalogue's "if you liked this" list, weighted by how engaged the user
// is with it, then consensus across the library, quality, fit, freshness and diversity decide the
// order. The client draws what it is sent, in that order, and never re-ranks.

/// One recommended title the user does NOT have. Decoded LENIENTLY, like the enrichment models: a
/// malformed item drops itself and a missing field reads as empty — never a decode failure.
struct RecommendationItem: Codable, Identifiable, Sendable {
    struct Seed: Codable, Hashable, Sendable {
        let franchiseId: String
        let title: String
    }

    /// Why this title — the user's shows it comes from. `count` is how many of them point at it.
    struct Reason: Codable, Sendable {
        /// `started` is the client's own: a Planned show with progress, named from the live
        /// library (`AppModel.spokenReason`) — the server's "watching" for it contradicted every
        /// screen that files it as Planned (review i5, N9).
        enum Kind: String, Codable, Sendable { case consensus, finished, watching, watched, planned, started, world }
        let kind: Kind
        let seeds: [Seed]
        let count: Int

        enum CodingKeys: String, CodingKey { case kind, seeds, count }

        init(kind: Kind, seeds: [Seed], count: Int) {
            self.kind = kind; self.seeds = seeds; self.count = count
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .consensus
            seeds = ((try? c.decode([LossySeed].self, forKey: .seeds)) ?? []).compactMap(\.value)
            count = max((try? c.decode(Int.self, forKey: .count)) ?? 0, seeds.count)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(kind, forKey: .kind)
            try c.encode(seeds, forKey: .seeds)
            try c.encode(count, forKey: .count)
        }

        private struct LossySeed: Decodable {
            let value: Seed?
            init(from decoder: Decoder) throws { value = try? Seed(from: decoder) }
        }
    }

    let key: String
    let franchiseId: String?
    let source: MediaSource
    let externalId: Int
    let title: String
    let year: Int?
    let images: ArtworkSet?
    let artwork: ArtworkGallery?
    let format: String?
    let episodes: Int?
    let airing: Bool
    let genres: [String]
    let reason: Reason
    let score: Double
    /// The title as a catalogue-only `Franchise` (no parts, no status), built ONCE at decode, so
    /// the poster tile and the billboard draw it through the same machinery as every other show
    /// (`tilePoster`, `billboardArt`, `billboardName`, the poster reading).
    let stub: Franchise?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, franchiseId, source, externalId, title, year, images, artwork, format, episodes,
             airing, genres, reason, score
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // The two fields an item cannot be drawn or acted on without.
        key = try c.decode(String.self, forKey: .key)
        title = try c.decode(String.self, forKey: .title)
        franchiseId = ArtworkSet.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .franchiseId))
        source = (try? c.decode(MediaSource.self, forKey: .source)) ?? .anilist
        externalId = (try? c.decode(Int.self, forKey: .externalId)) ?? 0
        year = try? c.decodeIfPresent(Int.self, forKey: .year)
        images = try? c.decodeIfPresent(ArtworkSet.self, forKey: .images)
        artwork = try? c.decodeIfPresent(ArtworkGallery.self, forKey: .artwork)
        format = try? c.decodeIfPresent(String.self, forKey: .format)
        episodes = try? c.decodeIfPresent(Int.self, forKey: .episodes)
        airing = (try? c.decode(Bool.self, forKey: .airing)) ?? false
        genres = (try? c.decode([String].self, forKey: .genres)) ?? []
        reason = (try? c.decode(Reason.self, forKey: .reason)) ?? Reason(kind: .consensus, seeds: [], count: 0)
        score = (try? c.decode(Double.self, forKey: .score)) ?? 0
        stub = Self.makeStub(id: franchiseId ?? key, title: title, source: source, year: year,
                             images: images, artwork: artwork, genres: genres)
    }

    /// For the offline copy (`AppModel`'s recommendations cache) — the stub is rebuilt on decode.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(franchiseId, forKey: .franchiseId)
        try c.encode(source, forKey: .source)
        try c.encode(externalId, forKey: .externalId)
        try c.encodeIfPresent(year, forKey: .year)
        try c.encodeIfPresent(images, forKey: .images)
        try c.encodeIfPresent(artwork, forKey: .artwork)
        try c.encodeIfPresent(format, forKey: .format)
        try c.encodeIfPresent(episodes, forKey: .episodes)
        try c.encode(airing, forKey: .airing)
        try c.encode(genres, forKey: .genres)
        try c.encode(reason, forKey: .reason)
        try c.encode(score, forKey: .score)
    }

    private static func makeStub(id: String, title: String, source: MediaSource, year: Int?,
                                 images: ArtworkSet?, artwork: ArtworkGallery?, genres: [String]) -> Franchise? {
        var dict: [String: Any] = ["id": id, "title": title, "source": source.rawValue, "genres": genres]
        if let year { dict["year"] = year }
        if let portrait = images?.portrait { dict["cover"] = portrait }
        if let landscape = images?.landscape { dict["banner"] = landscape }
        let encoder = JSONEncoder()
        if let images, let data = try? encoder.encode(images),
           let object = try? JSONSerialization.jsonObject(with: data) { dict["images"] = object }
        if let artwork, let data = try? encoder.encode(artwork),
           let object = try? JSONSerialization.jsonObject(with: data) { dict["artwork"] = object }
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(Franchise.self, from: data)
    }

    /// The name every surface uses — the short form (`displayTitle`), never "Re:ZERO -Starting
    /// Life in Another World-".
    var displayTitle: String { stub?.displayTitle ?? title }

    /// The name on a TILE: a catalogue's trailing year disambiguator dropped — "Hunter x Hunter
    /// (2011)" set a year as a name line (review i5); the page keeps the full title.
    var tileTitle: String {
        let t = displayTitle
        guard let open = t.range(of: " (", options: .backwards), t.hasSuffix(")") else { return t }
        let inner = t[open.upperBound..<t.index(before: t.endIndex)]
        return inner.count == 4 && inner.allSatisfy(\.isNumber) ? String(t[..<open.lowerBound]) : t
    }

    /// Art fit for a BILLBOARD — a picture at least ~900 px across, or any non-AniList poster
    /// (TMDB's are 780–2000 px). AniList's `/cover/large/` is 460 px, drawn 1,179 px wide it was
    /// the softest picture in the app (review i5, U-N3); such a title stays on the shelf.
    var hasBillboardArt: Bool {
        guard let url = stub?.billboardArt.url else { return false }
        if let image = artwork?.portraits.first(where: { $0.url == url }) {
            if let width = image.width { return width >= 900 }
            return image.source != nil && image.source != "anilist"
        }
        return !url.contains("anilist")
    }
}

/// `GET /me/recommendations`. Items decode one at a time; a bad one is dropped, not the list.
struct RecommendationsResponse: Codable, Sendable {
    let items: [RecommendationItem]
    let generatedAt: Int64?

    enum CodingKeys: String, CodingKey { case items, generatedAt }

    init(items: [RecommendationItem], generatedAt: Int64?) {
        self.items = items; self.generatedAt = generatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = ((try? c.decode([Lossy].self, forKey: .items)) ?? []).compactMap(\.value)
        generatedAt = try? c.decodeIfPresent(Int64.self, forKey: .generatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(items, forKey: .items)
        try c.encodeIfPresent(generatedAt, forKey: .generatedAt)
    }

    private struct Lossy: Decodable {
        let value: RecommendationItem?
        init(from decoder: Decoder) throws { value = try? RecommendationItem(from: decoder) }
    }
}

/// A write that answers 204 with no body.
struct NoContent: Decodable, Sendable {}
