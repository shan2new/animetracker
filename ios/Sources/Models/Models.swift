import Foundation

// Codable models matching the AniTrack API contract (docs/api-contract.md) exactly.
// All times are milliseconds since epoch (Int64), nullable where the contract says so.

// MARK: - Enums

/// The five watch statuses (spec board 09). `completed` is the wire name; the user's word is
/// "Finished" — see `WatchStatus.displayName` / `Copy.Status(_:)`, the only places it becomes text.
/// The server column is `text()`, so `paused` and `dropped` needed no migration.
enum WatchStatus: String, Codable, Sendable, CaseIterable {
    case watching
    case completed
    case planned
    case paused
    case dropped
}

/// Which catalogue a franchise came from. A franchise never mixes sources; absent in older
/// server responses, so decoding defaults to `.anilist`.
enum MediaSource: String, Codable, Sendable {
    case anilist
    case tmdb

    /// Which calendar this source's timestamps must be read in — the anchor every `Formatting`
    /// helper takes. TMDB air dates are DATE-ONLY facts the server carries as a synthesized
    /// 17:00 UTC instant (docs/api-contract.md), so only their UTC calendar day is real; reading
    /// them locally put every timezone east of UTC+7 a day ahead. AniList ships true instants.
    /// Never branch on `source` at a formatting call site — pass this.
    var timeAnchor: Formatting.TimeAnchor { self == .tmdb ? .utcDate : .local }
}

enum PartKind: String, Codable, Sendable {
    case season
    case movie
    case ova
    case ona
    case special
    case music

    // Section grouping used by the franchise detail screen.
    var sectionTitle: String {
        switch self {
        case .season: return "Seasons"
        case .movie: return "Movies"
        case .ova, .ona: return "OVAs"
        case .special: return "Specials"
        case .music: return "Music"
        }
    }

    // Canonical ordering of sections.
    var sortRank: Int {
        switch self {
        case .season: return 0
        case .movie: return 1
        case .ova: return 2
        case .ona: return 3
        case .special: return 4
        case .music: return 5
        }
    }
}

// MARK: - Episode

/// Per-episode metadata (present only on the franchise-detail response). Richness is
/// source-dependent — TMDB is full; AniList gives best-effort titles/thumbnails and no per-episode
/// airDate/overview. Everything is optional and decoded defensively.
struct Episode: Codable, Identifiable, Sendable {
    let number: Int
    let title: String?
    let airDate: Int64?     // ms epoch
    let overview: String?
    let still: String?      // thumbnail url
    let runtime: Int?       // minutes

    var id: Int { number }

    enum CodingKeys: String, CodingKey { case number, title, airDate, overview, still, runtime }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = (try? c.decode(Int.self, forKey: .number)) ?? 0
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        airDate = try? c.decodeIfPresent(Int64.self, forKey: .airDate)
        overview = try? c.decodeIfPresent(String.self, forKey: .overview)
        still = try? c.decodeIfPresent(String.self, forKey: .still)
        runtime = try? c.decodeIfPresent(Int.self, forKey: .runtime)
    }

    init(number: Int, title: String?, airDate: Int64?, overview: String?, still: String?, runtime: Int?) {
        self.number = number; self.title = title; self.airDate = airDate
        self.overview = overview; self.still = still; self.runtime = runtime
    }

    /// `airDate` only ever comes from TMDB — AniList exposes none (docs/api-contract.md) — so it is
    /// always a date-only fact and must be read in its own UTC day, never the device's.
    static let airDateAnchor: Formatting.TimeAnchor = .utcDate

    /// "Jun 24, 2026" for this episode's air date; nil when the source didn't date it.
    /// Use this instead of `Formatting.fmtFullDate(episode.airDate)`, which reads a day late east
    /// of UTC+7.
    var airDateLabel: String? {
        airDate.map { Formatting.fmtFullDate($0, anchor: Episode.airDateAnchor) }
    }

    /// Day word for this episode's air date ("Today" / "Thursday" / "May 4"); nil when undated.
    func airDayLabel(now: Int64) -> String? {
        airDate.map { Formatting.fmtDayLong(ts: $0, now: now, anchor: Episode.airDateAnchor) }
    }
}

// MARK: - Release precision

/// How precisely the next release instant is known — **stated by the server, never inferred from
/// `source`** (docs/api-contract.md). AniList publishes a real broadcast instant; TMDB publishes a
/// calendar date the sync synthesizes to 17:00 UTC, so its clock half is not a fact and must never
/// be rendered. Absent in older server responses, which is why every field is optional here.
struct ReleasePrecision: Codable, Sendable {
    enum Precision: String, Codable, Sendable {
        /// `at` is a real broadcast instant.
        case exact
        /// `date` is the fact; `at` is synthesized and its clock half is fiction.
        case dateOnly = "date_only"
        /// Nothing is scheduled.
        case unknown
    }

    let precision: Precision
    /// ms epoch. Authoritative only when `precision == .exact`.
    let at: Int64?
    /// "YYYY-MM-DD" (UTC). Authoritative only when `precision == .dateOnly`.
    let date: String?

    enum CodingKeys: String, CodingKey { case precision, at, date }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        precision = (try? c.decode(Precision.self, forKey: .precision)) ?? .unknown
        at = try? c.decodeIfPresent(Int64.self, forKey: .at)
        date = try? c.decodeIfPresent(String.self, forKey: .date)
    }

    init(precision: Precision, at: Int64?, date: String?) {
        self.precision = precision; self.at = at; self.date = date
    }
}

// MARK: - FranchisePart

struct FranchisePart: Codable, Identifiable, Sendable {
    let mediaId: Int
    let kind: PartKind
    let sequence: Int
    let label: String
    let title: String
    let cover: String?
    let banner: String?
    let format: String?
    let status: String?
    let isReleasing: Bool
    let totalEpisodes: Int
    let airedEpisodes: Int
    let nextEpisodeNumber: Int?
    let nextAiringAt: Int64?
    let lastAiredAt: Int64?
    let synopsis: String?
    let genres: [String]
    let progress: Int
    let year: Int?             // premiere/season year
    let studios: [String]      // studios (anime) / networks (TV)
    let nextAiringCount: Int   // episodes sharing the next airing date; > 1 ⇒ a full-season drop
    let episodes: [Episode]    // detail response only; [] on list/library payloads
    /// The honest shape of `nextAiringAt`. `nil` from a server that predates the field.
    let release: ReleasePrecision?

    var id: Int { mediaId }

    // Decode defensively: the server may omit optional/array fields.
    enum CodingKeys: String, CodingKey {
        case mediaId, kind, sequence, label, title, cover, banner, format, status
        case isReleasing, totalEpisodes, airedEpisodes, nextEpisodeNumber, nextAiringAt
        case lastAiredAt, synopsis, genres, progress
        case year, studios, nextAiringCount, episodes, release
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mediaId = try c.decode(Int.self, forKey: .mediaId)
        kind = (try? c.decode(PartKind.self, forKey: .kind)) ?? .season
        sequence = (try? c.decode(Int.self, forKey: .sequence)) ?? 0
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        title = (try? c.decode(String.self, forKey: .title)) ?? "Untitled"
        cover = try? c.decodeIfPresent(String.self, forKey: .cover)
        banner = try? c.decodeIfPresent(String.self, forKey: .banner)
        format = try? c.decodeIfPresent(String.self, forKey: .format)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        isReleasing = (try? c.decode(Bool.self, forKey: .isReleasing)) ?? false
        totalEpisodes = (try? c.decode(Int.self, forKey: .totalEpisodes)) ?? 0
        airedEpisodes = (try? c.decode(Int.self, forKey: .airedEpisodes)) ?? 0
        nextEpisodeNumber = try? c.decodeIfPresent(Int.self, forKey: .nextEpisodeNumber)
        nextAiringAt = try? c.decodeIfPresent(Int64.self, forKey: .nextAiringAt)
        lastAiredAt = try? c.decodeIfPresent(Int64.self, forKey: .lastAiredAt)
        synopsis = try? c.decodeIfPresent(String.self, forKey: .synopsis)
        genres = (try? c.decode([String].self, forKey: .genres)) ?? []
        progress = (try? c.decode(Int.self, forKey: .progress)) ?? 0
        year = try? c.decodeIfPresent(Int.self, forKey: .year)
        studios = (try? c.decode([String].self, forKey: .studios)) ?? []
        nextAiringCount = (try? c.decode(Int.self, forKey: .nextAiringCount)) ?? 0
        // `Episode.id` is its number, so a malformed/duplicate 0 would collide inside a ForEach.
        episodes = ((try? c.decode([Episode].self, forKey: .episodes)) ?? []).filter { $0.number > 0 }
        release = try? c.decodeIfPresent(ReleasePrecision.self, forKey: .release)
    }

    // Memberwise init for previews/tests. New fields default so existing call sites keep working.
    init(mediaId: Int, kind: PartKind, sequence: Int, label: String, title: String,
         cover: String?, banner: String?, format: String?, status: String?,
         isReleasing: Bool, totalEpisodes: Int, airedEpisodes: Int,
         nextEpisodeNumber: Int?, nextAiringAt: Int64?, lastAiredAt: Int64?,
         synopsis: String?, genres: [String], progress: Int,
         year: Int? = nil, studios: [String] = [], nextAiringCount: Int = 0, episodes: [Episode] = [],
         release: ReleasePrecision? = nil) {
        self.mediaId = mediaId; self.kind = kind; self.sequence = sequence
        self.label = label; self.title = title; self.cover = cover; self.banner = banner
        self.format = format; self.status = status; self.isReleasing = isReleasing
        self.totalEpisodes = totalEpisodes; self.airedEpisodes = airedEpisodes
        self.nextEpisodeNumber = nextEpisodeNumber; self.nextAiringAt = nextAiringAt
        self.lastAiredAt = lastAiredAt; self.synopsis = synopsis; self.genres = genres
        self.progress = progress
        self.year = year; self.studios = studios
        self.nextAiringCount = nextAiringCount; self.episodes = episodes
        self.release = release
    }

    /// A copy with the episode list replaced — grafts detail-fetched episodes onto the live
    /// (library) copy, which is loaded without them.
    func withEpisodes(_ eps: [Episode]) -> FranchisePart {
        FranchisePart(mediaId: mediaId, kind: kind, sequence: sequence, label: label, title: title,
                      cover: cover, banner: banner, format: format, status: status,
                      isReleasing: isReleasing, totalEpisodes: totalEpisodes, airedEpisodes: airedEpisodes,
                      nextEpisodeNumber: nextEpisodeNumber, nextAiringAt: nextAiringAt, lastAiredAt: lastAiredAt,
                      synopsis: synopsis, genres: genres, progress: progress,
                      year: year, studios: studios, nextAiringCount: nextAiringCount, episodes: eps,
                      release: release)
    }

    /// Unwatched episodes that have already aired (0 unless currently releasing).
    /// Ported verbatim from format.ts `episodesBehind`.
    var episodesBehind: Int {
        isReleasing ? max(0, airedEpisodes - progress) : 0
    }

    var isBehind: Bool { episodesBehind > 0 }

    /// Currently releasing AND fully watched up to the latest aired episode.
    var isCaughtUp: Bool { isReleasing && episodesBehind == 0 }

    /// Movies are a single binary unit (watched / not watched) — no episode count.
    var isMovie: Bool { kind == .movie }

    /// Announced but not yet aired — nothing is watchable yet, so the UI shows a premiere
    /// date instead of a "Not started" stepper.
    /// Keyed on status ALONE: a catalogue that publishes an announced season's planned episode
    /// count (TMDB does) would otherwise fail the old `airedEpisodes == 0` test and the season
    /// would masquerade as released — losing its premiere date and inventing a backlog.
    var isUpcoming: Bool { status == "NOT_YET_RELEASED" }

    /// Scheduled premiere instant (ms epoch) for an upcoming part, if the source has dated it.
    var premiereAt: Int64? { isUpcoming ? nextAiringAt : nil }

    /// "Jun 24, 2026" premiere date for an announced part, read in its source's calendar.
    /// A part doesn't know its own source, so the franchise supplies it.
    func premiereDateLabel(source: MediaSource) -> String? {
        premiereAt.map { Formatting.fmtFullDate($0, anchor: source.timeAnchor) }
    }

    /// The next airing you can still count down to, or nil when there isn't one.
    ///
    /// A `nextAiringAt` in the past is STALE DATA, not a schedule: the catalogue simply hasn't
    /// advanced the slot yet (an announced premiere whose date has come and gone, a season that
    /// ended between syncs). Reading it as a live schedule is what made a week-old timestamp
    /// render as "today" every day. Same-day is kept — an episode that aired a few hours ago
    /// still legitimately reads as "today".
    ///
    /// `anchor` decides which calendar "same day" means: a TMDB slot must be judged against its
    /// own UTC date or a JST morning keeps yesterday's drop alive as "today". Prefer
    /// `Franchise.nextAiring(now:)`, which can't forget to pass it.
    func scheduledAiring(now: Int64, anchor: Formatting.TimeAnchor = .local) -> Int64? {
        guard let next = nextAiringAt,
              Formatting.dayDiff(ts: next, now: now, anchor: anchor) >= 0 else { return nil }
        return next
    }

    /// Episodes of this part that are actually available to watch right now — aired count while
    /// releasing, else the finite total. Zero for an announced part: a season that hasn't started
    /// has nothing to watch, whatever episode count the catalogue advertises for it.
    func availableEpisodes() -> Int {
        if isUpcoming { return 0 }
        return airedEpisodes > 0 ? airedEpisodes : totalEpisodes
    }

    /// Highest episode number that may be recorded as watched for this part — the season's SIZE.
    /// A "+1" logging control with no ceiling will happily run progress past the end of a season
    /// (a 10-episode season sat at 59/10 because every tap incremented and the progress ring
    /// clamped its *visual* at 100%, so the overrun was invisible).
    ///
    /// Deliberately the season size rather than `availableEpisodes()`: aired counts trail the
    /// catalogue by up to an hour, and blocking a legitimate write on stale sync data is worse
    /// than allowing a keen viewer to run a few episodes ahead. Unknown size (ongoing AniList
    /// shows carry `episodes: null`) leaves it unbounded rather than guessing.
    var progressCeiling: Int {
        if isUpcoming { return 0 }
        let size = max(totalEpisodes, airedEpisodes)
        return size > 0 ? size : Int.max
    }

    /// Has the user watched this part to completion? For movies this is binary (progress > 0);
    /// for finite, non-releasing parts it means progress reached the episode total.
    var isFinished: Bool {
        if isMovie { return progress > 0 }
        return !isReleasing && totalEpisodes > 0 && progress >= totalEpisodes
    }
}

// MARK: - Franchise (full detail)

struct PartCounts: Codable, Sendable {
    var season: Int = 0
    var movie: Int = 0
    var ova: Int = 0
    var ona: Int = 0
    var special: Int = 0
    var music: Int = 0
}

struct Subscription: Codable, Sendable {
    let status: WatchStatus
    /// When the user subscribed (ms since epoch). Absent in older server responses, so Library's
    /// "recently added" ordering must treat `nil` as unknown rather than as the epoch.
    let addedAt: Int64?

    init(status: WatchStatus, addedAt: Int64? = nil) {
        self.status = status
        self.addedAt = addedAt
    }
}

// Web-sourced "what's next" news for a franchise (announced/airing seasons & films). `release`
// is a human-readable date or window ("October 2026", "January 2027", "TBA") because announced
// seasons often have only a window, which AniList doesn't expose as a per-episode airing time.
struct FranchiseUpcoming: Codable, Sendable {
    let status: String?
    let next: String?
    let release: String?
    let note: String?
    let source: String?
    let checked: String?

    enum CodingKeys: String, CodingKey { case status, next, release, note, source, checked }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        next = try? c.decodeIfPresent(String.self, forKey: .next)
        release = try? c.decodeIfPresent(String.self, forKey: .release)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        source = try? c.decodeIfPresent(String.self, forKey: .source)
        checked = try? c.decodeIfPresent(String.self, forKey: .checked)
    }

    init(status: String?, next: String?, release: String?, note: String?, source: String?, checked: String?) {
        self.status = status; self.next = next; self.release = release
        self.note = note; self.source = source; self.checked = checked
    }

    /// Short uppercase tag for the badge, derived from `status`.
    var tag: String {
        switch status {
        case "airing": return "Airing now"
        case "upcoming_dated": return "Upcoming"
        case "announced", "announced_no_date": return "Announced"
        case "recently_aired": return "Recently aired"
        case "rumored": return "Rumored"
        case "concluded": return "Complete"
        default: return "Upcoming"
        }
    }

    /// Concluded franchises have no future season — used to soften the card styling.
    var isConcluded: Bool { status == "concluded" }

    /// Human-friendly release label (ISO dates prettified; curated windows pass through).
    var displayRelease: String {
        guard let r = release, !r.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
        return Formatting.prettyReleaseString(r)
    }

    /// Chronological sort key for ordering the Upcoming bucket nearest-first. `value` is yyyymmdd
    /// (month/day default to 1 when only a year/month is known); `precision` (3=day, 2=month,
    /// 1=year) breaks ties so a concrete month sorts ahead of a bare year. Returns nil when the
    /// date is genuinely unknown — TBA *and* rumored — so those sort to the very end.
    var releaseSortKey: (value: Int, precision: Int)? {
        guard status != "rumored",
              let r = release?.trimmingCharacters(in: .whitespaces), !r.isEmpty else { return nil }
        let segs = r.split(separator: "-").map { Int($0) }
        if segs.count >= 2, let y = segs[0], let m = segs[1], (1...12).contains(m), (1900...2100).contains(y) {
            if segs.count >= 3, let d = segs[2], (1...31).contains(d) { return (y * 10000 + m * 100 + d, 3) }
            return (y * 10000 + m * 100 + 1, 2)
        }
        if let y = FranchiseUpcoming.firstYear(in: r) { return (y * 10000 + 101, 1) }
        return nil
    }

    /// First standalone 4-digit 20xx year in a string (e.g. "2027" in "2027-2028" or "approx 2027").
    private static func firstYear(in s: String) -> Int? {
        guard let range = s.range(of: "(?<![0-9])20[0-9]{2}(?![0-9])", options: .regularExpression) else { return nil }
        return Int(s[range])
    }

    /// True for statuses that represent a *future* installment worth flagging on a card —
    /// a season already airing is covered by the airing countdown, and recently-aired /
    /// concluded franchises have nothing upcoming to advertise.
    var isFutureInstallment: Bool {
        switch status {
        case "upcoming_dated", "announced", "announced_no_date", "rumored": return true
        default: return false
        }
    }

    /// Compact "what's next" line for a poster card, e.g. "Season 3 · Jul 5, 2026". Empty
    /// unless this is a future installment.
    var cardBadge: String {
        guard isFutureInstallment else { return "" }
        let what = (next?.isEmpty == false) ? next! : "New season"
        let when = displayRelease
        return when.isEmpty ? what : "\(what) · \(when)"
    }
}

struct Franchise: Codable, Identifiable, Sendable {
    let id: String
    let source: MediaSource
    let title: String
    let cover: String?
    let banner: String?
    let synopsis: String?
    let genres: [String]
    let isReleasing: Bool
    let partCounts: PartCounts?
    let parts: [FranchisePart]
    let subscription: Subscription?
    let upcoming: FranchiseUpcoming?
    let year: Int?             // premiere year (earliest dated part)
    let studios: [String]      // primary installment's studios (anime) / networks (TV)

    // Fields present only in /me/library responses (LibraryFranchise extends Franchise).
    let status: WatchStatus?
    let behind: Int?
    let newParts: Int?

    enum CodingKeys: String, CodingKey {
        case id, source, title, cover, banner, synopsis, genres, isReleasing, partCounts, parts, subscription, upcoming
        case year, studios
        case status, behind, newParts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        source = (try? c.decode(MediaSource.self, forKey: .source)) ?? .anilist
        title = (try? c.decode(String.self, forKey: .title)) ?? "Untitled"
        cover = try? c.decodeIfPresent(String.self, forKey: .cover)
        banner = try? c.decodeIfPresent(String.self, forKey: .banner)
        synopsis = try? c.decodeIfPresent(String.self, forKey: .synopsis)
        genres = (try? c.decode([String].self, forKey: .genres)) ?? []
        isReleasing = (try? c.decode(Bool.self, forKey: .isReleasing)) ?? false
        partCounts = try? c.decodeIfPresent(PartCounts.self, forKey: .partCounts)
        parts = (try? c.decode([FranchisePart].self, forKey: .parts)) ?? []
        subscription = try? c.decodeIfPresent(Subscription.self, forKey: .subscription)
        upcoming = try? c.decodeIfPresent(FranchiseUpcoming.self, forKey: .upcoming)
        year = try? c.decodeIfPresent(Int.self, forKey: .year)
        studios = (try? c.decode([String].self, forKey: .studios)) ?? []
        status = try? c.decodeIfPresent(WatchStatus.self, forKey: .status)
        behind = try? c.decodeIfPresent(Int.self, forKey: .behind)
        newParts = try? c.decodeIfPresent(Int.self, forKey: .newParts)
    }

    // Memberwise init (previews + optimistic local copies).
    init(id: String, source: MediaSource, title: String, cover: String?, banner: String?, synopsis: String?,
         genres: [String], isReleasing: Bool, partCounts: PartCounts?, parts: [FranchisePart],
         subscription: Subscription?, upcoming: FranchiseUpcoming? = nil,
         year: Int? = nil, studios: [String] = [],
         status: WatchStatus?, behind: Int?, newParts: Int?) {
        self.id = id; self.source = source; self.title = title; self.cover = cover; self.banner = banner
        self.synopsis = synopsis; self.genres = genres; self.isReleasing = isReleasing
        self.partCounts = partCounts; self.parts = parts; self.subscription = subscription
        self.upcoming = upcoming
        self.year = year; self.studios = studios
        self.status = status; self.behind = behind; self.newParts = newParts
    }

    /// Copy with replaced parts — used for optimistic progress updates.
    init(copying other: Franchise, parts: [FranchisePart]) {
        self.init(id: other.id, source: other.source, title: other.title, cover: other.cover, banner: other.banner,
                  synopsis: other.synopsis, genres: other.genres, isReleasing: other.isReleasing,
                  partCounts: other.partCounts, parts: parts, subscription: other.subscription,
                  upcoming: other.upcoming,
                  year: other.year, studios: other.studios,
                  status: other.status, behind: other.behind, newParts: other.newParts)
    }
}

// MARK: - FranchiseSummary (lists)

struct FranchiseSummary: Codable, Identifiable, Sendable {
    let id: String
    let source: MediaSource
    let title: String
    let cover: String?
    let banner: String?
    let isReleasing: Bool
    let partCount: Int
    let nextAiringAt: Int64?
    let upcoming: FranchiseUpcoming?
    let year: Int?

    // Present only in /me/library:
    let status: WatchStatus?
    let behind: Int?
    let newParts: Int?

    enum CodingKeys: String, CodingKey {
        case id, source, title, cover, banner, isReleasing, partCount, nextAiringAt, upcoming, year, status, behind, newParts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        source = (try? c.decode(MediaSource.self, forKey: .source)) ?? .anilist
        title = (try? c.decode(String.self, forKey: .title)) ?? "Untitled"
        cover = try? c.decodeIfPresent(String.self, forKey: .cover)
        banner = try? c.decodeIfPresent(String.self, forKey: .banner)
        isReleasing = (try? c.decode(Bool.self, forKey: .isReleasing)) ?? false
        partCount = (try? c.decode(Int.self, forKey: .partCount)) ?? 0
        nextAiringAt = try? c.decodeIfPresent(Int64.self, forKey: .nextAiringAt)
        upcoming = try? c.decodeIfPresent(FranchiseUpcoming.self, forKey: .upcoming)
        year = try? c.decodeIfPresent(Int.self, forKey: .year)
        status = try? c.decodeIfPresent(WatchStatus.self, forKey: .status)
        behind = try? c.decodeIfPresent(Int.self, forKey: .behind)
        newParts = try? c.decodeIfPresent(Int.self, forKey: .newParts)
    }

    /// The calendar this summary's `nextAiringAt` must be read in — see `MediaSource.timeAnchor`.
    var timeAnchor: Formatting.TimeAnchor { source.timeAnchor }
}

// MARK: - Endpoint response envelopes

struct FranchiseListResponse: Codable, Sendable {
    let franchises: [FranchiseSummary]
    /// `/search` only — set when the server spell-corrected/completed the query before searching.
    let correctedQuery: String?
    /// `/search` only — the query the caller sent, echoed **only** alongside `correctedQuery`.
    let originalQuery: String?
    /// `/search` only — per-catalogue outcome (`ok` / `failed` / `disabled`). Absent means
    /// "nothing to report", never "everything failed": a catalogue that FAILED is not a
    /// catalogue with no matches.
    let sources: [String: String]?

    enum CodingKeys: String, CodingKey { case franchises, correctedQuery, originalQuery, sources }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `franchises` stays a hard requirement: a body without it is a broken response, not an
        // empty result, and swallowing that would render "no results" for a server fault.
        franchises = try c.decode([FranchiseSummary].self, forKey: .franchises)
        correctedQuery = try? c.decodeIfPresent(String.self, forKey: .correctedQuery)
        originalQuery = try? c.decodeIfPresent(String.self, forKey: .originalQuery)
        sources = try? c.decodeIfPresent([String: String].self, forKey: .sources)
    }

    init(franchises: [FranchiseSummary], correctedQuery: String? = nil,
         originalQuery: String? = nil, sources: [String: String]? = nil) {
        self.franchises = franchises
        self.correctedQuery = correctedQuery
        self.originalQuery = originalQuery
        self.sources = sources
    }
}

struct LibraryResponse: Codable, Sendable {
    let franchises: [Franchise]   // LibraryFranchise = full Franchise + status/behind/newParts
    let prevOpenedAt: Int64
}

struct OpenedResponse: Codable, Sendable {
    let prevOpenedAt: Int64
}

struct OKResponse: Codable, Sendable {
    let ok: Bool
}

// MARK: - Request bodies

struct SubscribeBody: Encodable, Sendable {
    let franchiseId: String
    let status: WatchStatus?
}

struct StatusBody: Encodable, Sendable {
    let status: WatchStatus
}

struct ProgressBody: Encodable, Sendable {
    let mediaId: Int
    let episodes: Int
}

// MARK: - Franchise derivation helpers

extension Franchise {
    /// The calendar this franchise's timestamps must be read in — see `MediaSource.timeAnchor`.
    var timeAnchor: Formatting.TimeAnchor { source.timeAnchor }

    /// The next airing you can still count down to, read in this franchise's own calendar.
    /// Prefer this over `releasingPart?.scheduledAiring(now:)`, which defaults to `.local` and so
    /// keeps a TMDB drop alive a day too long east of UTC+7.
    func nextAiring(now: Int64) -> Int64? {
        releasingPart?.scheduledAiring(now: now, anchor: timeAnchor)
    }

    /// Calendar-day bucket key for one of this franchise's timestamps — what day-grouped feeds
    /// (the Schedule rail, Today's buckets) must group on so a TV row lands on its real date.
    func dayKey(of ts: Int64) -> Int64 { Formatting.localDayKey(ts, anchor: timeAnchor) }

    /// Whole-day offset of one of this franchise's timestamps from today (0 = today, +1 = tomorrow,
    /// −1 = yesterday).
    func dayDiff(of ts: Int64, now: Int64) -> Int {
        Formatting.dayDiff(ts: ts, now: now, anchor: timeAnchor)
    }

    /// The one "when does this land" label for this franchise: anime gets day + clock
    /// ("Tomorrow 9:00 PM"), TV gets a day word alone ("Tomorrow" / "Thursday" / "May 4").
    func whenLabel(ts: Int64, now: Int64) -> String {
        Formatting.fmtWhen(ts: ts, now: now, anchor: timeAnchor)
    }

    /// The currently-RELEASING part that Home / Schedule / Library logic operates on.
    /// Mirrors the api-contract "Client-side derivation": pick the releasing part, preferring
    /// the one with the soonest next airing, else the most recently aired.
    var releasingPart: FranchisePart? {
        let releasing = parts.filter { $0.isReleasing }
        if releasing.isEmpty { return nil }
        // Prefer a part with an upcoming airing (soonest first).
        let upcoming = releasing
            .filter { $0.nextAiringAt != nil }
            .sorted { ($0.nextAiringAt ?? .max) < ($1.nextAiringAt ?? .max) }
        if let first = upcoming.first { return first }
        // Otherwise the most recently aired releasing part.
        return releasing.sorted { ($0.lastAiredAt ?? 0) > ($1.lastAiredAt ?? 0) }.first
    }

    /// Soonest upcoming airing as an ascending sort key — franchises without a known next airing
    /// (or no releasing part) sort last. Centralizes the `?? .max` sentinel for the schedule/today/
    /// library "soonest first" orderings.
    var nextAiringSortKey: Int64 { releasingPart?.nextAiringAt ?? .max }

    /// Most-recent airing as a descending sort key — franchises with no aired part sort last.
    var lastAiredSortKey: Int64 { releasingPart?.lastAiredAt ?? 0 }

    /// Episodic parts (a movie is binary, handled elsewhere) in watch order.
    private var episodicParts: [FranchisePart] {
        parts
            .filter { $0.kind == .season || $0.kind == .ona || $0.kind == .ova }
            .sorted { $0.sequence < $1.sequence }
    }

    /// Already-available episodes of a part — see `FranchisePart.availableEpisodes()`.
    private static func availableEpisodes(_ p: FranchisePart) -> Int { p.availableEpisodes() }

    /// The part the user would actually resume, in watch order: the one they're mid-way through,
    /// else the first unstarted part *after* everything they finished, else the earliest part with
    /// anything left. Nil when there's no backlog anywhere.
    /// Picking by sequence (not by largest backlog) is the point: a max() would resume S3 at 3/10
    /// into an untouched S5 just because S5 is longer.
    /// With non-sequential progress (S2 untouched, S3 half-watched) the mid-watch part still wins —
    /// resuming what you're actively watching beats sending you back to a season you skipped.
    var resumePart: FranchisePart? {
        let eps = episodicParts
        func available(_ p: FranchisePart) -> Int { Franchise.availableEpisodes(p) }

        if let mid = eps.first(where: { $0.progress > 0 && $0.progress < available($0) }) { return mid }
        // `last` over the ascending list = highest-sequence part watched to completion.
        if let doneSeq = eps.last(where: { available($0) > 0 && $0.progress >= available($0) })?.sequence,
           let next = eps.first(where: { $0.sequence > doneSeq && available($0) - $0.progress > 0 }) {
            return next
        }
        return eps.first(where: { available($0) - $0.progress > 0 })
    }

    /// Unwatched, already-available episodes of the part you'd resume — the "Keep watching" count.
    /// Zero when nothing is left to watch.
    var continueBacklog: Int {
        guard let p = resumePart else { return 0 }
        return max(0, Franchise.availableEpisodes(p) - p.progress)
    }

    var effectiveStatus: WatchStatus {
        status ?? subscription?.status ?? .planned
    }

    /// Parts grouped into ordered sections for the detail screen. Seasons are listed newest-first
    /// (reverse sequence) so the latest season is at the top; other kinds stay chronological.
    var sections: [(kind: PartKind, parts: [FranchisePart])] {
        let groups = Dictionary(grouping: parts, by: { $0.kind })
        return groups
            .map { (key, value) -> (kind: PartKind, parts: [FranchisePart]) in
                let ordered = value.sorted { $0.sequence < $1.sequence }
                return (kind: key, parts: key == .season ? ordered.reversed() : ordered)
            }
            .sorted { $0.kind.sortRank < $1.kind.sortRank }
    }
}
