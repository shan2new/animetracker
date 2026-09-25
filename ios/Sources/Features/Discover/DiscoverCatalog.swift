import Foundation
import Observation

// Discover's catalogue data (ios-spec §3.5, iD11): the genre tiles per scope and the loaded genre
// pages. It is CATALOGUE data — the same for every viewer, cached per process by the server
// (server §10.2) — so it lives here, beside the screens that draw it, and not in `AppModel`.
//
// The one viewer-specific fact a page carries is `FranchiseSummary.status` (an owned title is
// MARKED, not excluded). Pages are therefore bound to the account that fetched them
// (`adopt(account:)`): the next account never inherits the last one's marks.

/// One genre page as far as it has been read: the items in rank order (deduped by id across
/// pages), where to continue, and what the last request did.
struct GenrePageState {
    var genre: DiscoverGenre?
    var items: [FranchiseSummary] = []
    var nextCursor: String?
    var loading = false
    /// The last request failed (content already on screen stays).
    var failed = false
    /// The failure was a continuation (`more`): the notice belongs at the FOOT of the grid,
    /// beside the rows that did arrive, and the retry continues rather than restarts.
    var failedMore = false
    /// The server has nothing after the last page (no cursor, or the genre is unknown to it).
    var exhausted = false
    /// A first page has answered at least once (with items or with none).
    var loaded = false
    var loadedAt: Int64 = 0
}

@MainActor @Observable final class DiscoverCatalog {
    static let shared = DiscoverCatalog()

    /// Genre tiles per scope. Key: `MediaFilter.rawValue`. An empty array is an ANSWER (no genres,
    /// or a server older than `/discover/genres`) and hides the section; a missing key has not
    /// been asked yet.
    private(set) var genres: [String: [DiscoverGenre]] = [:]
    private(set) var genresLoading: Set<String> = []
    /// Key: `"\(genreKey)|\(filter.rawValue)"` (`pageKey`).
    private(set) var pages: [String: GenrePageState] = [:]

    /// When each scope's genre list last answered (ms). Not observed: a timestamp is not UI.
    @ObservationIgnored private var genresLoadedAt: [String: Int64] = [:]
    /// The account the loaded pages belong to (`adopt`).
    @ObservationIgnored private var account: Int?
    /// Bumped when the pages are dropped, so a response that set out for the previous account
    /// lands nowhere.
    @ObservationIgnored private var generation = 0

    /// The genre list answers for 30 minutes (the server rebuilds it at most that often).
    static let genresFreshness: Int64 = 30 * 60 * 1000
    /// A page reloads on return after 10 minutes — ownership marks and the chart's order move.
    static let pageFreshness: Int64 = 10 * 60 * 1000
    /// Tiles on the launchpad: two columns, four rows, then nothing ("See all" would be a page of
    /// the same tiles).
    static let tileLimit = 8

    private init() {}

    // MARK: Reads

    func genres(for filter: MediaFilter) -> [DiscoverGenre] {
        genres[filter.rawValue] ?? []
    }

    func page(key: String, filter: MediaFilter) -> GenrePageState {
        pages[Self.pageKey(key, filter)] ?? GenrePageState()
    }

    static func pageKey(_ key: String, _ filter: MediaFilter) -> String { "\(key)|\(filter.rawValue)" }

    /// The catalogue's source for a scope: All asks for both.
    static func source(for filter: MediaFilter) -> MediaSource? {
        switch filter {
        case .all: return nil
        case .anime: return .anilist
        case .tv: return .tmdb
        }
    }

    // MARK: Account

    /// Binds the loaded pages to `account` (`AppModel.accountEpoch`). A different account drops
    /// them — a page's `status` marks are the viewer's. Genres are viewer-independent and stay.
    func adopt(account: Int) {
        guard self.account != account else { return }
        if self.account != nil {
            generation &+= 1
            pages = [:]
        }
        self.account = account
    }

    /// Drops every loaded page and invalidates the requests still out (`AppModel.teardown()`): a
    /// signed-out account's `status` marks must not sit in memory for the next one, even until its
    /// first genre page. The genre LIST is catalogue data — the same for every viewer — and stays.
    func clear() {
        generation &+= 1
        pages = [:]
        account = nil
    }

    // MARK: Loading

    /// The tiles for one scope. Fresh for 30 minutes (unless `force`, the launchpad's pull); a
    /// failure keeps whatever was there and the next appearance asks again; a 404 (a server older
    /// than this build) is an answer — no genres, the section stays hidden.
    func loadGenres(api: APIClient, filter: MediaFilter, force: Bool = false) async {
        let key = filter.rawValue
        guard !genresLoading.contains(key) else { return }
        let now = Int64.nowMs
        if !force, genres[key] != nil, let at = genresLoadedAt[key], now - at < Self.genresFreshness { return }
        genresLoading.insert(key)
        defer { genresLoading.remove(key) }
        do {
            let res = try await api.discoverGenres(source: Self.source(for: filter))
            genres[key] = res.genres.filter { $0.count > 0 && !$0.key.isEmpty }
            genresLoadedAt[key] = .nowMs
        } catch let error as APIError where error.status == 404 {
            genres[key] = []
            genresLoadedAt[key] = .nowMs
        } catch {
            // Cancelled (the scope changed, the tab left) or failed: nothing to record. The next
            // `.task` run asks again; what was on screen stays.
        }
    }

    /// One genre page. `more` follows `nextCursor` (appending, deduped by id); otherwise the
    /// first page — skipped while a fresh one is loaded, unless `force` (the pull).
    func loadPage(api: APIClient, key: String, filter: MediaFilter, more: Bool, force: Bool = false) async {
        let pageKey = Self.pageKey(key, filter)
        var state = pages[pageKey] ?? GenrePageState()
        guard !state.loading else { return }
        let cursor: String?
        if more {
            guard state.loaded, !state.exhausted, let next = state.nextCursor else { return }
            cursor = next
        } else {
            if !force, state.loaded, !state.failed, Int64.nowMs - state.loadedAt < Self.pageFreshness { return }
            cursor = nil
        }
        state.loading = true
        state.failed = false
        state.failedMore = false
        pages[pageKey] = state
        let generation = self.generation

        do {
            let res = try await api.discoverGenre(key: key, source: Self.source(for: filter), cursor: cursor)
            guard generation == self.generation else { return }
            var next = pages[pageKey] ?? GenrePageState()
            if !res.genre.key.isEmpty { next.genre = res.genre }
            if more {
                var seen = Set(next.items.map(\.id))
                next.items += res.franchises.filter { seen.insert($0.id).inserted }
            } else {
                var seen = Set<String>()
                next.items = res.franchises.filter { seen.insert($0.id).inserted }
            }
            next.nextCursor = res.nextCursor
            next.exhausted = res.nextCursor == nil
            next.loading = false
            next.failed = false
            next.failedMore = false
            next.loaded = true
            if !more { next.loadedAt = .nowMs }
            pages[pageKey] = next
        } catch {
            guard generation == self.generation else { return }
            var next = pages[pageKey] ?? GenrePageState()
            next.loading = false
            if error.isCancellation {
                // Superseded, not failed: the page keeps what it had and asks again on return.
            } else if let apiError = error as? APIError, apiError.status == 404 {
                // An unknown genre, or a server that predates the route: an empty, finished page.
                if !more { next.items = [] }
                next.nextCursor = nil
                next.exhausted = true
                next.loaded = true
                if !more { next.loadedAt = .nowMs }
            } else {
                next.failed = true
                next.failedMore = more
            }
            pages[pageKey] = next
        }
    }
}
