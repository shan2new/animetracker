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
    static let errorSeconds: Double = 4
    static let clockTick: TimeInterval = 20            // countdowns change at minute granularity
    static let recentsKey = "recentSearches"
    static let maxRecents = 10
    // Foreground-refresh thresholds: reload when the app was backgrounded long enough for aired
    // counts to be stale; re-stamp /me/opened only when the away-time reads as a NEW visit (so
    // brief app switches don't wipe "Out now").
    static let staleReloadAfter: Int64 = 2 * Formatting.minuteMs
    static let newVisitAfter: Int64 = 6 * Formatting.H

    let api: APIClient

    // Library (full franchises with parts + status/behind/newParts). `libraryIds` mirrors it for
    // O(1) membership checks — the Discover grid calls isInLibrary per card on every (animating) frame.
    var library: [Franchise] = [] { didSet { libraryIds = Set(library.map(\.id)) } }
    private(set) var libraryIds: Set<String> = []
    // Ids optimistically added but not yet confirmed by a reload — isInLibrary includes them so
    // "+" buttons flip instantly instead of waiting a network round-trip.
    private(set) var pendingAdds: Set<String> = []
    var prevOpenedAt: Int64 = 0
    var loading = true
    var loadError = false

    // Discover/search.
    var searchQuery = "" { didSet { scheduleSearch() } }
    var searchResults: [FranchiseSummary] = []
    var searchBusy = false
    var searchError = false
    // Persisted recent search terms, most-recent first — the search surface's empty state.
    var recentSearches: [String] = []

    // Library filtering.
    var libFilter: LibFilter = .all
    var libQuery = ""

    // Live clock for countdowns.
    var now: Int64 = .nowMs

    // Celebration + undo + error surfacing.
    var justCaught: Set<String> = []          // franchise ids currently celebrating
    var undo: UndoState?
    // A transient failure message (write didn't reach the server). Rendered by ToastHost.
    var errorToast: String?

    private var clockTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var ccTasks: [String: Task<Void, Never>] = [:]
    private var undoTask: Task<Void, Never>?
    private var errorTask: Task<Void, Never>?
    // Set when the scene enters background; drives the staleness checks on return.
    private var backgroundedAt: Int64?

    // Monotonic token: each fired request claims the next value; a response only mutates
    // state if it's still the latest, so out-of-order completions can't clobber fresh results.
    private var searchSeq = 0

    init(api: APIClient) {
        self.api = api
        recentSearches = UserDefaults.standard.stringArray(forKey: AppModel.recentsKey) ?? []
    }

    // MARK: - Lifecycle

    func start() {
        startClock()
        Task { await stampOpened() }
        Task { await reload() }
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
            await syncAmbient()
        } catch {
            loadError = true
        }
    }

    // MARK: - Scene lifecycle (foreground refresh)

    func sceneEnteredBackground() {
        backgroundedAt = .nowMs
    }

    /// Called when the scene becomes active. Snaps the countdown clock immediately (the 20s tick
    /// task was suspended), reloads when the data is stale, and re-stamps /me/opened when the
    /// away-time is long enough to count as a new visit.
    func sceneBecameActive() {
        now = .nowMs
        guard let bg = backgroundedAt else { return }  // launch activation — start() covers it
        backgroundedAt = nil
        let away = now - bg
        guard away >= AppModel.staleReloadAfter else { return }
        Task {
            if away >= AppModel.newVisitAfter { await stampOpened() }
            await reload()
        }
    }

    /// Push the current library into the ambient layers (pending episode notifications and the
    /// airing Live Activity) after any confirmed server-side change.
    private func syncAmbient() async {
        await EpisodeNotifications.shared.sync(library: library, now: .nowMs)
        AiringLiveActivityManager.shared.sync(library: library, now: .nowMs)
    }

    // MARK: - Error toast

    /// Surface a write failure. Every optimistic mutation calls this after rolling itself back,
    /// so the UI never silently disagrees with the server.
    func showError(_ message: String) {
        Haptics.error()
        errorToast = message
        errorTask?.cancel()
        errorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AppModel.errorSeconds))
            if Task.isCancelled { return }
            await MainActor.run { self?.errorToast = nil }
        }
    }

    // MARK: - Recent searches (the search surface's empty state)

    /// Records the current query as a recent term (most-recent first, de-duplicated, capped).
    /// Called when the user submits the search field.
    func recordRecentSearch() {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        recentSearches.removeAll { $0.caseInsensitiveCompare(q) == .orderedSame }
        recentSearches.insert(q, at: 0)
        if recentSearches.count > AppModel.maxRecents {
            recentSearches = Array(recentSearches.prefix(AppModel.maxRecents))
        }
        persistRecents()
    }

    func removeRecentSearch(_ term: String) {
        recentSearches.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
        persistRecents()
    }

    func clearRecentSearches() {
        recentSearches = []
        persistRecents()
    }

    private func persistRecents() {
        UserDefaults.standard.set(recentSearches, forKey: AppModel.recentsKey)
    }

    // MARK: - Search (debounced)

    private func scheduleSearch() {
        searchTask?.cancel()
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        // Cleared box: cancel any pending search and fall back to the recent-searches empty state.
        if trimmed.isEmpty {
            searchBusy = false
            searchError = false
            searchResults = []
            searchTask = nil
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

    /// Re-run the current query immediately (no debounce) — the Retry affordance on a failed search.
    func retrySearch() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchTask?.cancel()
        searchBusy = true
        searchError = false
        searchTask = Task { [weak self] in
            await self?.runSearch(query: trimmed)
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

    func isInLibrary(_ id: String) -> Bool { libraryIds.contains(id) || pendingAdds.contains(id) }

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
            // Server order is subscription order — arbitrary to the reader. Alphabetical scans.
            return arr.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
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

        Task {
            do {
                _ = try await api.setProgress(mediaId: part.mediaId, episodes: aired)
            } catch {
                // Roll back the optimistic write and retract the celebration/undo that now lie.
                applyLocalProgress(franchiseId: franchiseId, mediaId: part.mediaId, episodes: prev)
                justCaught.remove(franchiseId)
                if let cur = undo, !cur.added, cur.franchiseId == franchiseId { undo = nil }
                showError("Couldn't save progress — check your connection.")
            }
        }
    }

    /// Set explicit progress for a part (detail pips / movie toggle).
    func setProgress(franchiseId: String, mediaId: Int, episodes: Int) {
        let clamped = max(0, episodes)
        Haptics.impact(.light)
        let prev = franchise(id: franchiseId)?.parts.first { $0.mediaId == mediaId }?.progress
        applyLocalProgress(franchiseId: franchiseId, mediaId: mediaId, episodes: clamped)
        Task {
            do {
                _ = try await api.setProgress(mediaId: mediaId, episodes: clamped)
            } catch {
                if let prev {
                    applyLocalProgress(franchiseId: franchiseId, mediaId: mediaId, episodes: prev)
                }
                showError("Couldn't save progress — check your connection.")
            }
        }
    }

    /// Subscribe to a franchise (POST /me/subscriptions). Status defaults server-side. The add is
    /// optimistic via `pendingAdds` so the card flips to "In library" instantly.
    func addToLibrary(franchiseId: String, title: String, isReleasing: Bool) {
        guard !isInLibrary(franchiseId) else { return }
        Haptics.success()
        pendingAdds.insert(franchiseId)
        let status: WatchStatus = isReleasing ? .watching : .planned
        let label = status == .watching ? "Watching" : "Plan to watch"
        undo = UndoState(mediaId: nil, franchiseId: franchiseId, prevProgress: 0,
                         title: title, episode: 0, added: true, statusLabel: label)
        scheduleUndoDismissal()
        // First airing show added: the moment notifications become valuable, so ask now.
        if isReleasing {
            Task { _ = await EpisodeNotifications.shared.requestPermissionIfNeeded() }
        }
        Task {
            do {
                _ = try await api.subscribe(franchiseId: franchiseId, status: nil)
                await reload()
            } catch {
                if let cur = undo, cur.added, cur.franchiseId == franchiseId { undo = nil }
                showError("Couldn't add \(title) — check your connection.")
            }
            pendingAdds.remove(franchiseId)
        }
    }

    func setStatus(franchiseId: String, status: WatchStatus) {
        Haptics.selection()
        guard let idx = library.firstIndex(where: { $0.id == franchiseId }) else {
            // Not in the loaded library (e.g. a pending add) — fire and hope; reload reconciles.
            Task { _ = try? await api.setStatus(franchiseId: franchiseId, status: status) }
            return
        }
        let prevStatus = library[idx].effectiveStatus
        guard prevStatus != status else { return }
        library[idx] = library[idx].withStatus(status)
        Task {
            do {
                _ = try await api.setStatus(franchiseId: franchiseId, status: status)
                await syncAmbient()
            } catch {
                if let i = library.firstIndex(where: { $0.id == franchiseId }) {
                    library[i] = library[i].withStatus(prevStatus)
                }
                showError("Couldn't update status — check your connection.")
            }
        }
    }

    /// `haptic: false` for the undo path — performUndo already fired its own impact.
    func removeFromLibrary(franchiseId: String, haptic: Bool = true) {
        if haptic { Haptics.impact(.rigid) }
        pendingAdds.remove(franchiseId)
        let idx = library.firstIndex(where: { $0.id == franchiseId })
        let removed = idx.map { library[$0] }
        if let idx { library.remove(at: idx) }
        Task {
            do {
                _ = try await api.unsubscribe(franchiseId: franchiseId)
                await syncAmbient()
            } catch {
                if let removed, !library.contains(where: { $0.id == franchiseId }) {
                    library.insert(removed, at: min(idx ?? library.count, library.count))
                }
                showError("Couldn't remove \(removed?.title ?? "show") — check your connection.")
            }
        }
    }

    func performUndo() {
        guard let u = undo else { return }
        Haptics.impact(.medium)
        if u.added, let fid = u.franchiseId {
            removeFromLibrary(franchiseId: fid, haptic: false)
        } else if let fid = u.franchiseId, let mediaId = u.mediaId, isInLibrary(fid) {
            applyLocalProgress(franchiseId: fid, mediaId: mediaId, episodes: u.prevProgress)
            justCaught.remove(fid)
            Task {
                do {
                    _ = try await api.setProgress(mediaId: mediaId, episodes: u.prevProgress)
                } catch {
                    showError("Couldn't undo — check your connection.")
                    await reload()  // converge back to server truth
                }
            }
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

    /// Returns a copy with the watch status replaced (both the library field and the subscription
    /// mirror, so `effectiveStatus` flips immediately). Used for optimistic status updates.
    func withStatus(_ newStatus: WatchStatus) -> Franchise {
        Franchise(id: id, title: title, cover: cover, banner: banner, synopsis: synopsis,
                  genres: genres, isReleasing: isReleasing, partCounts: partCounts, parts: parts,
                  subscription: Subscription(status: newStatus), upcoming: upcoming,
                  status: newStatus, behind: behind, newParts: newParts)
    }
}
