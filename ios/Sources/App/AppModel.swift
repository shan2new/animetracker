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
    static let outNowWindow: Int64 = 7 * Formatting.D  // how recent an unwatched drop stays "out now"
    // Calendar feed span, in local days either side of today.
    static let scheduleBack = -7
    static let scheduleAhead = 14
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
    // Trending franchises for the search zero-state shelf. Fetched once per session, lazily on
    // first visit to the search tab; a failure just leaves the shelf out (nothing to retry into).
    var trending: [FranchiseSummary] = []
    private var trendingTask: Task<Void, Never>?

    // Library filtering.
    var libQuery = ""
    // Global anime/TV filter — applies to Today, Schedule, Library, and search results.
    var mediaFilter: MediaFilter = .all

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

    /// Fetch the zero-state trending shelf, once. Quiet on failure — the launchpad simply shows
    /// recents alone; the next cold visit (task released only on success) tries again.
    func loadTrendingIfNeeded() {
        guard trending.isEmpty, trendingTask == nil else { return }
        trendingTask = Task { [weak self] in
            defer { self?.trendingTask = nil }
            guard let items = try? await self?.api.trending(limit: 10) else { return }
            self?.trending = items
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

    /// Search results with the anime/TV chip applied (the server interleaves both sources).
    var filteredSearchResults: [FranchiseSummary] {
        searchResults.filter { matchesMediaFilter($0.source) }
    }

    func franchise(id: String) -> Franchise? { library.first { $0.id == id } }

    func matchesMediaFilter(_ source: MediaSource) -> Bool {
        switch mediaFilter {
        case .all: return true
        case .anime: return source == .anilist
        case .tv: return source == .tmdb
        }
    }

    /// All subscribed franchises that have a currently-releasing part (media-filtered).
    var airingFranchises: [Franchise] {
        library.filter { $0.releasingPart != nil && matchesMediaFilter($0.source) }
    }

    var libraryEmpty: Bool { library.isEmpty }

    // ----- Today -----

    var effectivePrev: Int64 { prevOpenedAt > 0 ? prevOpenedAt : now - AppModel.newLookback }

    /// "Out now" — releasing parts with a RECENTLY aired episode you haven't watched. Keyed on
    /// unwatched-ness + recency, not on `prevOpenedAt`: the old last-open comparison made a new
    /// episode vanish from Today the second time you opened the app, watched or not.
    var outNow: [Franchise] {
        airingFranchises
            .filter {
                guard let part = $0.releasingPart else { return false }
                // A just-caught-up row has to survive its celebration: `episodesBehind` drops to 0
                // the instant progress is written, which would otherwise yank the row (and the
                // frame CaughtUpOverlay renders on) before the overlay is ever seen.
                guard part.episodesBehind > 0 || justCaught.contains($0.id) else { return false }
                return now - (part.lastAiredAt ?? 0) <= AppModel.outNowWindow
            }
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

    /// "Keep watching" — franchises you're mid-watch with an unwatched backlog NOT already surfaced
    /// in Out now (a binged TV season, or a show you've fallen behind on off its airing schedule).
    /// Most backlog first. An airing show can appear here AND in Up next (a new episode still comes).
    var keepWatching: [Franchise] {
        let outNowIds = Set(outNow.map(\.id))
        return Array(
            library
                .filter {
                    matchesMediaFilter($0.source)
                        && $0.effectiveStatus == .watching
                        && !outNowIds.contains($0.id)
                        && $0.resumePart != nil
                }
                .sorted {
                    if $0.continueBacklog != $1.continueBacklog { return $0.continueBacklog > $1.continueBacklog }
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                // Today is a glance, not the whole library — surface the strongest handful.
                .prefix(8)
        )
    }

    // ----- Currently watching shelf (Today redesign) -----

    /// How a franchise earns its place on Today's "Currently watching" shelf — doubles as the
    /// shelf's sort order (rawValue ascending) and drives each card's caption.
    enum ShelfState: Int {
        case newEpisode = 0   // unwatched episode aired recently — NEW badge
        case backlog          // something to resume ("S3 · E4 · 7 left")
        case airingWait       // caught up, next episode dated ("Sun · 3d")
        case premiereSoon     // announced season premiering within the window ("S3 · Oct 12")
    }

    /// Window inside which an announced-but-unaired season is worth shelf space. A dated premiere
    /// months out (or TBA) is noise on a "what am I watching" rail — per design, those are dropped.
    static let premiereShelfWindow: Int64 = 45 * Formatting.D

    /// The state that admits `f` to the shelf, or nil (dormant: caught up with nothing dated).
    func shelfState(of f: Franchise) -> ShelfState? {
        if let part = f.releasingPart, part.episodesBehind > 0,
           now - (part.lastAiredAt ?? 0) <= AppModel.outNowWindow { return .newEpisode }
        if f.resumePart != nil { return .backlog }
        if let part = f.releasingPart, part.isCaughtUp, part.nextAiringAt != nil { return .airingWait }
        if let premiere = nextPremiere(of: f), premiere - now <= AppModel.premiereShelfWindow {
            return .premiereSoon
        }
        return nil
    }

    /// Soonest dated future premiere among a franchise's announced parts.
    func nextPremiere(of f: Franchise) -> Int64? {
        f.parts.compactMap { $0.premiereAt }.filter { $0 > now }.min()
    }

    /// "Currently watching" — every Watching-status show with a live claim on your attention:
    /// new episode > backlog > caught-up-airing > imminent premiere. Ties break most-actionable
    /// first (freshest drop / biggest backlog / soonest airing / soonest premiere).
    var watchingShelf: [Franchise] {
        library
            .filter { matchesMediaFilter($0.source) && $0.effectiveStatus == .watching }
            .compactMap { f in shelfState(of: f).map { (f, $0) } }
            .sorted { a, b in
                if a.1 != b.1 { return a.1.rawValue < b.1.rawValue }
                switch a.1 {
                case .newEpisode: return a.0.lastAiredSortKey > b.0.lastAiredSortKey
                case .backlog: return a.0.continueBacklog > b.0.continueBacklog
                case .airingWait: return a.0.nextAiringSortKey < b.0.nextAiringSortKey
                case .premiereSoon:
                    return (nextPremiere(of: a.0) ?? .max) < (nextPremiere(of: b.0) ?? .max)
                }
            }
            .map(\.0)
    }

    // ----- Schedule (a chronological calendar feed around today) -----

    struct ScheduleDay: Identifiable {
        /// Day offset from today in local days — negative for past days.
        let id: Int
        let label: String
        let isToday: Bool
        let isPast: Bool
        let dateLabel: String
        /// Episodes still to air on this day (future days + later today).
        let franchises: [Franchise]
        /// Episodes that already aired on this day — populated for past days and earlier today.
        let airedToday: [Franchise]

        init(id: Int, label: String, isToday: Bool, dateLabel: String,
             franchises: [Franchise], airedToday: [Franchise] = [], isPast: Bool = false) {
            self.id = id
            self.label = label
            self.isToday = isToday
            self.isPast = isPast
            self.dateLabel = dateLabel
            self.franchises = franchises
            self.airedToday = airedToday
        }
    }

    /// A week back through two weeks ahead, chronological. Empty days are omitted so the feed stays
    /// content-forward; today is always kept and stays highlighted even when nothing airs.
    /// A franchise carries a single `nextAiringAt`, so it lands on at most one future day.
    var scheduleDays: [ScheduleDay] {
        // Anchor on local noon so a day step survives DST transitions.
        let p = Formatting.localParts(now)
        let noon = now - (Int64(p.hour) * Formatting.H + Int64(p.minute) * Formatting.minuteMs) + 12 * Formatting.H

        return (AppModel.scheduleBack...AppModel.scheduleAhead).compactMap { offset -> ScheduleDay? in
            let dayDate = noon + Int64(offset) * Formatting.D
            let dayKey = Formatting.localDayKey(dayDate)
            let isToday = offset == 0

            let items = airingFranchises
                .filter {
                    guard let next = $0.releasingPart?.nextAiringAt else { return false }
                    return Formatting.localDayKey(next) == dayKey && next > now
                }
                .sorted { $0.nextAiringSortKey < $1.nextAiringSortKey }
            let aired = airingFranchises
                .filter {
                    guard let last = $0.releasingPart?.lastAiredAt else { return false }
                    return Formatting.localDayKey(last) == dayKey && last <= now
                }
                .sorted { $0.lastAiredSortKey > $1.lastAiredSortKey }

            guard isToday || !items.isEmpty || !aired.isEmpty else { return nil }
            return ScheduleDay(
                id: offset,
                label: Formatting.weekdayNameMonFirst(Formatting.localMondayCol(dayDate)),
                isToday: isToday,
                dateLabel: Formatting.fmtMonthDay(dayDate),
                franchises: items,
                airedToday: aired,
                isPast: offset < 0
            )
        }
    }

    // ----- Library shelves (the "crate" redesign) -----

    /// The Library crate's four shelves — grouped by the show's relationship to your FUTURE,
    /// not by app state: you're in it / it's coming back / you haven't started / it's over.
    /// Per the urgency pact, none of these carry obligations; "Coming back" carries a return
    /// date (anticipation, the one kind of state that relaxes instead of nags).
    // Case order = shelf order on screen: Planned leads (the library is where you browse what
    // to start next — Today already fronts what you're watching), then Coming back, Watching,
    // and the Finished archive.
    enum LibShelf: Int, CaseIterable, Identifiable {
        case planned, comingBack, watching, finished
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .watching: return "Watching"
            case .comingBack: return "Coming back"
            case .planned: return "Planned"
            case .finished: return "Finished"
            }
        }
    }

    /// One show, one shelf.
    func libShelf(of f: Franchise) -> LibShelf {
        if f.effectiveStatus == .planned { return .planned }
        // In it: a season is live for you, or you have episodes left to continue.
        if f.effectiveStatus == .watching, f.releasingPart != nil || f.resumePart != nil {
            return .watching
        }
        // Coming back: nothing to watch right now, but a next installment is announced —
        // dated or TBA alike. This is the "when does it return" lookup made browsable.
        if f.upcoming?.isFutureInstallment == true || nextPremiere(of: f) != nil {
            return .comingBack
        }
        return .finished
    }

    struct LibShelfSection: Identifiable {
        let shelf: LibShelf
        let franchises: [Franchise]
        var id: Int { shelf.id }
    }

    /// The crate, in shelf order, search-filtered; empty shelves are omitted. No other filters —
    /// the Library is one collection and search is its only control.
    var libraryShelves: [LibShelfSection] {
        let q = libQuery.lowercased().trimmingCharacters(in: .whitespaces)
        let filtered = library.filter { q.isEmpty || $0.title.lowercased().contains(q) }
        return LibShelf.allCases.compactMap { shelf in
            let arr = sortedForShelf(filtered.filter { libShelf(of: $0) == shelf }, shelf: shelf)
            return arr.isEmpty ? nil : LibShelfSection(shelf: shelf, franchises: arr)
        }
    }

    private func sortedForShelf(_ arr: [Franchise], shelf: LibShelf) -> [Franchise] {
        switch shelf {
        case .watching:
            // Recently-active first — the show you're living with floats to the top.
            return arr.sorted { a, b in
                if a.lastAiredSortKey != b.lastAiredSortKey { return a.lastAiredSortKey > b.lastAiredSortKey }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        case .comingBack:
            // Soonest return first; TBA/undated last. Ties break by date precision, then title.
            return arr.sorted { a, b in
                let ak = comingBackSortKey(a), bk = comingBackSortKey(b)
                if ak.value != bk.value { return ak.value < bk.value }
                if ak.precision != bk.precision { return ak.precision > bk.precision }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        case .planned, .finished:
            return arr.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }

    /// Chronological key for the Coming back shelf: a dated premiere beats the curated release
    /// window; genuinely unknown dates sort to the very end.
    private func comingBackSortKey(_ f: Franchise) -> (value: Int, precision: Int) {
        if let premiere = nextPremiere(of: f) {
            let p = Formatting.localParts(premiere)
            return (p.y * 10000 + p.mo * 100 + p.d, 3)
        }
        return f.upcoming?.releaseSortKey ?? (Int.max, 0)
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
        // Soft, refined tick for per-episode / movie watched toggles (distinct from catch-up's success).
        Haptics.impact(.soft)
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

enum MediaFilter: String, CaseIterable {
    case all
    case anime
    case tv

    var chipLabel: String {
        switch self {
        case .all: return "All"
        case .anime: return "Anime"
        case .tv: return "TV"
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
                genres: p.genres, progress: max(0, episodes),
                year: p.year, studios: p.studios, nextAiringCount: p.nextAiringCount,
                episodes: p.episodes
            )
        }
        return Franchise(copying: self, parts: newParts)
    }

    /// Returns a copy with the watch status replaced (both the library field and the subscription
    /// mirror, so `effectiveStatus` flips immediately). Used for optimistic status updates.
    func withStatus(_ newStatus: WatchStatus) -> Franchise {
        Franchise(id: id, source: source, title: title, cover: cover, banner: banner, synopsis: synopsis,
                  genres: genres, isReleasing: isReleasing, partCounts: partCounts, parts: parts,
                  subscription: Subscription(status: newStatus), upcoming: upcoming,
                  year: year, studios: studios,
                  status: newStatus, behind: behind, newParts: newParts)
    }
}
