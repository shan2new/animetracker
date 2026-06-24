import Foundation
import SwiftUI
import Observation

// The app's central state + view-model. Replaces the legacy React App.tsx state and the
// `useLibrary` store, talking to the backend instead of localStorage. Operates the franchise
// franchise-centrically: Home / Schedule / Library derive from each franchise's releasing part.
@MainActor
@Observable
final class AppModel {
    // Windows (ported from App.tsx constants).
    static let soonWindow: Int64 = 48 * Formatting.H  // "Airing soon" lookahead
    static let newLookback: Int64 = 3 * Formatting.D   // default "out now" window with no prior open
    static let undoSeconds: Double = 5
    static let clockTick: TimeInterval = 20            // countdowns change at minute granularity

    let api: APIClient

    // Library (full franchises with parts + status/behind/newParts). `libraryIds` mirrors it for
    // O(1) membership checks — the Discover grid calls isInLibrary per card on every (animating) frame.
    var library: [Franchise] = [] { didSet { libraryIds = Set(library.map(\.id)) } }
    private(set) var libraryIds: Set<String> = []
    var prevOpenedAt: Int64 = 0
    var loading = true
    var loadError = false

    // Discover/search.
    var searchQuery = "" { didSet { scheduleSearch() } }
    var searchResults: [FranchiseSummary] = []
    var searchBusy = false
    var searchError = false

    // Library filtering.
    var libFilter: LibFilter = .all
    var libQuery = ""

    // Live clock for countdowns.
    var now: Int64 = .nowMs

    // Celebration + undo.
    var justCaught: Set<String> = []          // franchise ids currently celebrating
    var undo: UndoState?

    private var clockTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var ccTasks: [String: Task<Void, Never>] = [:]
    private var undoTask: Task<Void, Never>?

    // Trending, fetched once and reused so clearing the search box restores it instantly.
    private var trendingCache: [FranchiseSummary] = []
    // Monotonic token: each fired request claims the next value; a response only mutates
    // state if it's still the latest, so out-of-order completions can't clobber fresh results.
    private var searchSeq = 0

    init(api: APIClient) {
        self.api = api
    }

    // MARK: - Lifecycle

    func start() {
        startClock()
        Task { await stampOpened() }
        Task { await reload() }
        Task { await loadTrending() }
    }

    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(AppModel.clockTick))
                await MainActor.run { self?.now = .nowMs }
            }
        }
    }

    /// Records the previous-open timestamp (drives "since you were last here") and stamps now.
    private func stampOpened() async {
        do {
            let res = try await api.markOpened()
            prevOpenedAt = res.prevOpenedAt
        } catch {
            // Non-fatal; "out now" falls back to a 3-day lookback.
        }
    }

    func reload() async {
        loading = true
        defer { loading = false }
        do {
            let res = try await api.library()
            library = res.franchises
            // Keep the larger of the two prevOpenedAt values we may have seen.
            if res.prevOpenedAt > 0 { prevOpenedAt = max(prevOpenedAt, res.prevOpenedAt) }
            loadError = false
        } catch {
            loadError = true
        }
    }

    func loadTrending() async {
        let seq = nextSeq()
        if searchResults.isEmpty { searchBusy = true }   // cold start → show the skeleton grid
        do {
            let results = try await api.trending()
            trendingCache = results
            // Don't clobber active search results if the user typed while this was in flight.
            guard seq == searchSeq, queryIsEmpty else { return }
            searchResults = results
            searchBusy = false
            searchError = false
        } catch {
            guard !isCancellation(error), seq == searchSeq, queryIsEmpty else { return }
            searchError = true
            searchBusy = false
        }
    }

    // MARK: - Search (debounced)

    private var queryIsEmpty: Bool {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        // Cleared box: cancel any pending search and restore trending instantly.
        if trimmed.isEmpty {
            searchBusy = false
            searchError = false
            if trendingCache.isEmpty {
                searchTask = Task { [weak self] in await self?.loadTrending() }
            } else {
                searchResults = trendingCache
                searchTask = nil
            }
            return
        }

        searchBusy = true
        searchError = false
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            await self?.runSearch(query: trimmed)
        }
    }

    private func runSearch(query: String) async {
        let seq = nextSeq()
        do {
            let results = try await api.search(query: query)
            guard seq == searchSeq else { return }   // a newer keystroke superseded this request
            searchResults = results
            searchError = false
            searchBusy = false
        } catch {
            guard !isCancellation(error) else { return }  // cancelled by a newer keystroke — not a failure
            guard seq == searchSeq else { return }
            searchError = true
            searchBusy = false
        }
    }

    private func nextSeq() -> Int {
        searchSeq += 1
        return searchSeq
    }

    // A request cancelled by the next keystroke surfaces as URLError.cancelled (wrapped by
    // APIClient as .transport) or CancellationError. Treat these as "superseded", not failures.
    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if (error as? URLError)?.code == .cancelled { return true }
        if case let APIError.transport(inner) = error, (inner as? URLError)?.code == .cancelled {
            return true
        }
        return false
    }

    // MARK: - Derived helpers

    func isInLibrary(_ id: String) -> Bool { libraryIds.contains(id) }

    func franchise(id: String) -> Franchise? { library.first { $0.id == id } }

    /// All subscribed franchises that have a currently-releasing part.
    var airingFranchises: [Franchise] {
        library.filter { $0.releasingPart != nil }
    }

    var libraryEmpty: Bool { library.isEmpty }

    // ----- Today -----

    var effectivePrev: Int64 { prevOpenedAt > 0 ? prevOpenedAt : now - AppModel.newLookback }

    /// "Out now" — releasing parts whose lastAiredAt > prevOpenedAt.
    var outNow: [Franchise] {
        airingFranchises
            .filter { ($0.releasingPart?.lastAiredAt ?? 0) > effectivePrev }
            .sorted { $0.lastAiredSortKey > $1.lastAiredSortKey }
    }

    /// "Airing soon" — releasing parts with nextAiringAt within 48h, soonest first.
    var soon: [Franchise] {
        airingFranchises
            .filter {
                guard let next = $0.releasingPart?.nextAiringAt else { return false }
                let delta = next - now
                return delta > 0 && delta <= AppModel.soonWindow
            }
            .sorted { $0.nextAiringSortKey < $1.nextAiringSortKey }
    }

    /// Soonest upcoming episode across all airing franchises (not just the 48h window).
    var nextUp: Franchise? {
        airingFranchises
            .filter { ($0.releasingPart?.nextAiringAt ?? 0) > now }
            .sorted { $0.nextAiringSortKey < $1.nextAiringSortKey }
            .first
    }

    // ----- Schedule (remainder of the local Mon..Sun week, starting today) -----

    struct ScheduleDay: Identifiable {
        let id: Int
        let label: String
        let isToday: Bool
        let dateLabel: String
        let franchises: [Franchise]
        /// For today only: parts that already aired earlier today (so an empty upcoming list
        /// doesn't falsely read as "nothing happened today").
        let airedToday: [Franchise]

        init(id: Int, label: String, isToday: Bool, dateLabel: String,
             franchises: [Franchise], airedToday: [Franchise] = []) {
            self.id = id
            self.label = label
            self.isToday = isToday
            self.dateLabel = dateLabel
            self.franchises = franchises
            self.airedToday = airedToday
        }
    }

    /// Today through the end of the current local week, dropping past days. Empty days are
    /// omitted (so the list is content-forward) except for today, which is always kept and
    /// stays highlighted even when nothing airs.
    var scheduleDays: [ScheduleDay] {
        let todayCol = Formatting.localMondayCol(now)
        return (todayCol..<7).compactMap { c -> ScheduleDay? in
            let colDate = now + Int64(c - todayCol) * Formatting.D
            let colKey = Formatting.localDayKey(colDate)
            let isToday = c == todayCol
            let items = airingFranchises
                .filter {
                    guard let next = $0.releasingPart?.nextAiringAt else { return false }
                    return Formatting.localDayKey(next) == colKey
                }
                .sorted { $0.nextAiringSortKey < $1.nextAiringSortKey }
            // Skip empty non-today days to keep the schedule tight.
            guard isToday || !items.isEmpty else { return nil }
            // For today, gather parts that already aired earlier today so the day never looks
            // falsely empty when episodes dropped before now.
            let airedToday: [Franchise] = isToday
                ? airingFranchises
                    .filter {
                        guard let last = $0.releasingPart?.lastAiredAt else { return false }
                        return Formatting.localDayKey(last) == colKey && last <= now
                    }
                    .sorted { $0.lastAiredSortKey > $1.lastAiredSortKey }
                : []
            return ScheduleDay(
                id: c,
                label: Formatting.weekdayNameMonFirst(c),
                isToday: isToday,
                dateLabel: Formatting.fmtMonthDay(colDate),
                franchises: items,
                airedToday: airedToday
            )
        }
    }

    // ----- Library buckets -----

    func bucket(of f: Franchise) -> LibGroup {
        let status = f.effectiveStatus
        if status == .planned { return .planned }
        if status == .watching, let part = f.releasingPart, part.isReleasing {
            return part.episodesBehind > 0 ? .behind : .caughtup
        }
        // Not actively airing: a franchise with an announced/upcoming next installment belongs in
        // "Upcoming", not "Finished" — otherwise a completed show with a confirmed new season
        // would be buried as if it were done for good.
        if f.upcoming?.isFutureInstallment == true { return .upcoming }
        return .finished
    }

    struct LibrarySection: Identifiable {
        let id: String
        let label: String
        let count: Int
        let franchises: [Franchise]
    }

    var librarySections: [LibrarySection] {
        let q = libQuery.lowercased().trimmingCharacters(in: .whitespaces)
        let filtered = library.filter { q.isEmpty || $0.title.lowercased().contains(q) }
        return LibGroup.allCases
            .filter { libFilter == .all || libFilter == .group($0) }
            .compactMap { group -> LibrarySection? in
                let arr = sortedForBucket(filtered.filter { bucket(of: $0) == group }, group: group)
                guard !arr.isEmpty else { return nil }
                return LibrarySection(id: group.rawValue, label: group.sectionLabel,
                                      count: arr.count, franchises: arr)
            }
    }

    /// Orders a bucket's franchises for triage. Power users scan "Behind" by most-behind first;
    /// "Caught up" reads best by soonest next airing.
    private func sortedForBucket(_ arr: [Franchise], group: LibGroup) -> [Franchise] {
        switch group {
        case .behind:
            // Most episodes behind first; fall back to `behind` then title for stable ordering.
            return arr.sorted { a, b in
                let ax = a.releasingPart?.episodesBehind ?? a.behind ?? 0
                let bx = b.releasingPart?.episodesBehind ?? b.behind ?? 0
                if ax != bx { return ax > bx }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        case .caughtup:
            // Soonest next airing first; shows without a known next airing sort last.
            return arr.sorted { a, b in
                let an = a.nextAiringSortKey
                let bn = b.nextAiringSortKey
                if an != bn { return an < bn }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        case .upcoming:
            // Nearest announced date first; unknown dates (TBA / rumored) sort last. Ties break by
            // precision (a concrete month ahead of a bare year), then title.
            return arr.sorted { a, b in
                switch (a.upcoming?.releaseSortKey, b.upcoming?.releaseSortKey) {
                case let (x?, y?):
                    if x.value != y.value { return x.value < y.value }
                    if x.precision != y.precision { return x.precision > y.precision }
                    return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil):
                    return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
                }
            }
        case .finished, .planned:
            return arr
        }
    }

    // MARK: - Actions

    /// Mark the releasing part of a franchise caught up (PUT /me/progress {mediaId, airedEpisodes}).
    func markCaughtUp(_ franchiseId: String) {
        guard let f = franchise(id: franchiseId), let part = f.releasingPart else { return }
        Haptics.success()
        let prev = part.progress
        let aired = part.airedEpisodes
        applyLocalProgress(franchiseId: franchiseId, mediaId: part.mediaId, episodes: aired)

        // Preserve the original prev if an undo for this franchise is already pending.
        if let cur = undo, !cur.added, cur.franchiseId == franchiseId {
            undo = UndoState(mediaId: part.mediaId, franchiseId: franchiseId,
                             prevProgress: cur.prevProgress, title: f.title, episode: aired)
        } else {
            undo = UndoState(mediaId: part.mediaId, franchiseId: franchiseId,
                             prevProgress: prev, title: f.title, episode: aired)
        }

        celebrate(franchiseId)
        scheduleUndoDismissal()

        Task { try? await api.setProgress(mediaId: part.mediaId, episodes: aired) }
    }

    /// Set explicit progress for a part (detail stepper).
    func setProgress(franchiseId: String, mediaId: Int, episodes: Int) {
        let clamped = max(0, episodes)
        Haptics.impact(.light)
        applyLocalProgress(franchiseId: franchiseId, mediaId: mediaId, episodes: clamped)
        Task { try? await api.setProgress(mediaId: mediaId, episodes: clamped) }
    }

    /// Subscribe to a franchise (POST /me/subscriptions). Status defaults server-side.
    func addToLibrary(franchiseId: String, title: String, isReleasing: Bool) {
        guard !isInLibrary(franchiseId) else { return }
        Haptics.success()
        let status: WatchStatus = isReleasing ? .watching : .planned
        let label = status == .watching ? "Watching" : "Plan to watch"
        undo = UndoState(mediaId: nil, franchiseId: franchiseId, prevProgress: 0,
                         title: title, episode: 0, added: true, statusLabel: label)
        scheduleUndoDismissal()
        Task {
            _ = try? await api.subscribe(franchiseId: franchiseId, status: nil)
            await reload()
        }
    }

    func setStatus(franchiseId: String, status: WatchStatus) {
        Haptics.selection()
        // Optimistic local update by reloading after the patch.
        Task {
            _ = try? await api.setStatus(franchiseId: franchiseId, status: status)
            await reload()
        }
    }

    func removeFromLibrary(franchiseId: String) {
        Task {
            _ = try? await api.unsubscribe(franchiseId: franchiseId)
            await reload()
        }
    }

    func performUndo() {
        guard let u = undo else { return }
        Haptics.impact(.medium)
        if u.added, let fid = u.franchiseId {
            removeFromLibrary(franchiseId: fid)
        } else if let fid = u.franchiseId, let mediaId = u.mediaId, isInLibrary(fid) {
            applyLocalProgress(franchiseId: fid, mediaId: mediaId, episodes: u.prevProgress)
            justCaught.remove(fid)
            Task { try? await api.setProgress(mediaId: mediaId, episodes: u.prevProgress) }
        }
        undo = nil
        undoTask?.cancel()
    }

    // MARK: - Internal mutation helpers

    /// Optimistically rewrite a part's progress in the in-memory library so the UI updates instantly.
    private func applyLocalProgress(franchiseId: String, mediaId: Int, episodes: Int) {
        guard let fi = library.firstIndex(where: { $0.id == franchiseId }) else { return }
        library[fi] = library[fi].withUpdatedProgress(mediaId: mediaId, episodes: episodes)
    }

    private func celebrate(_ franchiseId: String) {
        justCaught.insert(franchiseId)
        ccTasks[franchiseId]?.cancel()
        ccTasks[franchiseId] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1300))
            await MainActor.run {
                self?.justCaught.remove(franchiseId)
                self?.ccTasks[franchiseId] = nil
            }
        }
    }

    private func scheduleUndoDismissal() {
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AppModel.undoSeconds))
            if Task.isCancelled { return }
            await MainActor.run { self?.undo = nil }
        }
    }
}

// MARK: - Library filter model

enum LibGroup: String, CaseIterable {
    // Order here drives both the filter-chip order and the section order on screen.
    case behind, caughtup, upcoming, finished, planned

    var sectionLabel: String {
        switch self {
        case .behind: return "Behind"
        case .caughtup: return "Caught up"
        case .upcoming: return "Upcoming seasons"
        case .finished: return "Finished airing"
        case .planned: return "Plan to watch"
        }
    }

    var chipLabel: String {
        switch self {
        case .behind: return "Behind"
        case .caughtup: return "Caught up"
        case .upcoming: return "Upcoming"
        case .finished: return "Finished"
        case .planned: return "Planned"
        }
    }

    var cardAction: CardAction { self == .behind ? .mark : .none }
}

enum LibFilter: Equatable {
    case all
    case group(LibGroup)

    static func == (lhs: LibFilter, rhs: LibFilter) -> Bool {
        switch (lhs, rhs) {
        case (.all, .all): return true
        case let (.group(a), .group(b)): return a == b
        default: return false
        }
    }
}

// MARK: - Local progress mutation on the immutable Franchise

extension Franchise {
    /// Returns a copy with one part's `progress` replaced. Used for optimistic UI updates.
    func withUpdatedProgress(mediaId: Int, episodes: Int) -> Franchise {
        var newParts = parts
        if let idx = newParts.firstIndex(where: { $0.mediaId == mediaId }) {
            let p = newParts[idx]
            newParts[idx] = FranchisePart(
                mediaId: p.mediaId, kind: p.kind, sequence: p.sequence, label: p.label,
                title: p.title, cover: p.cover, banner: p.banner, format: p.format,
                status: p.status, isReleasing: p.isReleasing, totalEpisodes: p.totalEpisodes,
                airedEpisodes: p.airedEpisodes, nextEpisodeNumber: p.nextEpisodeNumber,
                nextAiringAt: p.nextAiringAt, lastAiredAt: p.lastAiredAt, synopsis: p.synopsis,
                genres: p.genres, progress: max(0, episodes)
            )
        }
        return Franchise(copying: self, parts: newParts)
    }
}
