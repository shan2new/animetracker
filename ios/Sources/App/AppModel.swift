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
    // Toast lifetimes live on `SyncCenter` (`toastSeconds` / `errorSeconds`), which is the only
    // thing that knows whether VoiceOver is running. These two constants were the reason that
    // knowledge never reached the live timer: `SyncCenter.toastSeconds` was declared, documented
    // and never called, while the sleep below used a hard-coded 6 — so an Undo a VoiceOver user
    // could not reach in time was still exactly 6 seconds long.
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
    /// Epoch-ms of the last library payload that actually arrived (freshness source for SyncCenter).
    var lastLoadedAt: Int64 = 0
    /// True once the cold-launch splash has left and Today is actually visible — the recap waits for it.
    var surfaceReady = false
    var loadError = false

    // Discover/search.
    var searchQuery = "" { didSet { searchExactOnce = false; scheduleSearch() } }
    var searchResults: [FranchiseSummary] = []
    var searchBusy = false
    var searchError = false
    /// The server's spell correction for the results currently on screen.
    ///
    /// `/search` has always returned `correctedQuery` + `originalQuery`, `FranchiseListResponse`
    /// has always decoded them, and **no view ever read them**: a search for "one pieceszz" showed
    /// a flat "No results" while the backend had already worked out what was meant. Search renders
    /// it as "Showing results for …" with a literal-search escape hatch.
    var searchCorrection: SearchCorrection?
    /// Set by `searchLiterally` for exactly one request: the user asked for the words they typed,
    /// so that request opts out of the server's correction (`exact=1`). Any keystroke clears it.
    private var searchExactOnce = false
    // Persisted recent search terms, most-recent first — the search surface's empty state.
    var recentSearches: [String] = []
    // Trending franchises for the search zero-state shelf. Fetched once per session, lazily on
    // first visit to the search tab; a failure just leaves the shelf out (nothing to retry into).
    var trending: [FranchiseSummary] = []
    private var trendingTask: Task<Void, Never>?

    // Library filtering.
    var libQuery = ""
    // Anime/TV filter — SEARCH ONLY. Today, Schedule and Library are your shows and always show
    // everything: a filter set once while browsing used to silently hide half of what aired.
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
    // Same guard for library reloads: several can be in flight (an add, a pull-to-refresh, a
    // foreground refresh) and a sign-out invalidates all of them at once.
    private var reloadSeq = 0

    /// One optimistic progress write, awaiting a server snapshot that confirms it.
    private struct LocalWrite {
        var episodes: Int
        /// `reloadSeq` at the moment the PUT settled (returned, succeeded or failed); nil while
        /// it is still in flight. Any snapshot fetched by a LATER reload was read after the
        /// server had its final say, so it is authoritative — see `reconcileLocalProgress`.
        var settledAtSeq: Int?
    }

    /// Optimistic progress writes a server snapshot hasn't confirmed yet, keyed by mediaId
    /// (globally unique). Two jobs: a franchise added seconds ago isn't in `library` until the
    /// add's reload lands, so the write has nowhere to go; and a reload already in flight when
    /// the write happened carries a pre-write snapshot that would silently revert it. An entry
    /// is dropped the moment a fetched library agrees with it — or once the write has settled and
    /// a snapshot taken afterwards still disagrees, which means the server didn't accept it.
    private var localProgress: [Int: LocalWrite] = [:]

    /// Invoked when the server rejects our credentials. The auth layer owns the response — a 401
    /// means the session is gone, which is a sign-in problem, never a connectivity one.
    var onSessionExpired: (@MainActor () -> Void)?

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
        reloadSeq += 1
        let seq = reloadSeq
        loading = true
        do {
            let res = try await api.library()
            // A newer reload — or a sign-out teardown — superseded this request. Its snapshot is
            // stale by definition; applying it would resurrect state we just tore down.
            guard seq == reloadSeq else { return }
            library = reconcileLocalProgress(res.franchises, seq: seq)
            // Keep the larger of the two prevOpenedAt values we may have seen.
            if res.prevOpenedAt > 0 { prevOpenedAt = max(prevOpenedAt, res.prevOpenedAt) }
            loadError = false
            loading = false
            lastLoadedAt = .nowMs
            await syncAmbient()
        } catch APIError.unauthorized {
            guard seq == reloadSeq else { return }
            // NOT a load failure: retrying can never fix a dead session, and "the server couldn't
            // be reached" would be a lie. Hand it to auth, which returns the user to sign-in.
            handleSessionExpired()
        } catch {
            guard seq == reloadSeq else { return }
            loadError = true
            loading = false
        }
    }

    /// The session is gone (401/403). Drop every trace of the signed-in account, then let the
    /// auth layer surface the honest reason on the sign-in screen.
    private func handleSessionExpired() {
        teardown()
        onSessionExpired?()
    }

    /// Full account teardown, run on every sign-out (voluntary or expired). Anything that outlives
    /// the view tree has to be dismantled here — the in-memory library, the live clock, in-flight
    /// requests, and the two ambient layers (pending episode alerts and the airing Live Activity)
    /// would otherwise keep serving the previous account. Leaves the model in its launch state so
    /// the next sign-in opens on a loader, never on someone else's shows.
    func teardown() {
        RewatchStore.shared.reset()
        SeasonSweepLedger.reset()
        clockTask?.cancel(); clockTask = nil
        searchTask?.cancel(); searchTask = nil
        trendingTask?.cancel(); trendingTask = nil
        undoTask?.cancel(); undoTask = nil
        errorTask?.cancel(); errorTask = nil
        ccTasks.values.forEach { $0.cancel() }
        ccTasks = [:]
        // Invalidate every in-flight response so a late completion can't repopulate the model.
        searchSeq += 1
        reloadSeq += 1

        library = []
        pendingAdds = []
        localProgress = [:]
        prevOpenedAt = 0
        loadError = false
        loading = true          // the next sign-in mounts on the loader, not on an empty shelf
        backgroundedAt = nil

        searchQuery = ""        // didSet clears the results/busy/error triad
        searchResults = []
        searchBusy = false
        searchError = false
        searchCorrection = nil
        trending = []
        libQuery = ""
        mediaFilter = .all

        justCaught = []
        undo = nil
        errorToast = nil

        EpisodeNotifications.shared.cancelAll()
        AiringLiveActivityManager.shared.endAll()
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
        FeedbackCoordinator.fire(.directError)
        errorToast = message
        errorTask?.cancel()
        errorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(SyncCenter.shared.errorSeconds))
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
            searchCorrection = nil
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
        let exact = searchExactOnce
        do {
            let response: SearchResponse = try await api.search(query: query, exact: exact)
            guard seq == searchSeq else { return }   // a newer keystroke superseded this request
            searchResults = response.franchises
            searchCorrection = SearchCorrection(response)
            searchExactOnce = false
            searchError = false
            searchBusy = false
        } catch {
            guard !isCancellation(error) else { return }  // cancelled by a newer keystroke — not a failure
            guard seq == searchSeq else { return }
            searchCorrection = nil
            searchError = true
            searchBusy = false
        }
    }

    /// "Search instead for …": re-run the words the user actually typed, with the server's
    /// spell correction turned off for that one request.
    func searchLiterally(_ term: String) {
        if searchQuery != term { searchQuery = term }   // didSet clears the flag and re-schedules
        searchExactOnce = true                          // set AFTER, so the request below reads it
        retrySearch()
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

    /// Search results with the anime/TV chip applied (the server interleaves both sources). This
    /// is the ONLY surface the chip touches — see `mediaFilter`.
    var filteredSearchResults: [FranchiseSummary] {
        searchResults.filter { matchesMediaFilter($0.source) }
    }

    func franchise(id: String) -> Franchise? { library.first { $0.id == id } }

    /// Which catalogue a franchise came from, resolved from whatever is loaded — the library, or
    /// the search/trending results an add can originate from. nil when we genuinely don't know
    /// (callers should treat that as "not AniList" rather than guess).
    func source(of franchiseId: String) -> MediaSource? {
        if let f = franchise(id: franchiseId) { return f.source }
        if let s = searchResults.first(where: { $0.id == franchiseId }) { return s.source }
        if let t = trending.first(where: { $0.id == franchiseId }) { return t.source }
        return nil
    }

    func matchesMediaFilter(_ source: MediaSource) -> Bool {
        switch mediaFilter {
        case .all: return true
        case .anime: return source == .anilist
        case .tv: return source == .tmdb
        }
    }

    /// All subscribed franchises that have a currently-releasing part. Never media-filtered: what
    /// aired today is a fact about your library, not about a chip you last touched in search.
    var airingFranchises: [Franchise] {
        library.filter { $0.releasingPart != nil }
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
                // frame its result state renders on) before it is ever seen.
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

    /// Soonest upcoming episode across all airing franchises (not just the 48h window). This is
    /// the "waiting" hero and the all-caught-up line, so every slot it yields must still be a
    /// genuine WAIT.
    ///
    /// A date-only TV drop stays "up next" for the whole of its day — its clock time is
    /// synthesized, so there is no instant for it to be past, and the labels are day-granular.
    /// An AniList slot is a real instant: once it passes, the episode is out. `scheduledAiring`
    /// deliberately keeps such a slot alive for the rest of the day (it reads as "today"
    /// elsewhere), but here it would sort ahead of the genuinely-next episode and be announced as
    /// a future event — "lands Today 9:00 AM" at 8pm. Keep those strictly future.
    var nextUp: Franchise? {
        airingFranchises
            .filter {
                $0.timeAnchor.isDateOnly
                    ? $0.nextAiring(now: now) != nil
                    : ($0.releasingPart?.nextAiringAt ?? 0) > now
            }
            .sorted { $0.nextAiringSortKey < $1.nextAiringSortKey }
            .first
    }

    // MARK: now bar

    /// Today's Now Bar fact — one global answer to "when". Deliberately mirrors the Live
    /// Activity's "one soonest episode" model (`AiringLiveActivityManager.sync`) so the lock
    /// screen and Today tell the same story.
    struct NowBarItem: Equatable {
        enum State { case live, next }
        let franchiseId: String
        let state: State
        /// The instant the bar is about: the drop (`.live`) or the next airing (`.next`).
        let at: Int64
    }

    /// How long a fresh unwatched drop holds the bar's LIVE state. Deliberately tighter than
    /// `outNowWindow` — the bar answers "what's happening now", not "what's still unwatched".
    static let nowBarLiveWindow: Int64 = 24 * Formatting.H

    /// LIVE = the freshest unwatched drop within the live window (same-day for date-only TV,
    /// which has no real instant to measure hours against); else NEXT = the soonest scheduled
    /// airing; else nil — the bar collapses to nothing (Today must not nag with an idle strip).
    var nowBarItem: NowBarItem? {
        if let f = outNow.first, let last = f.releasingPart?.lastAiredAt {
            let fresh = f.timeAnchor.isDateOnly
                ? f.dayDiff(of: last, now: now) == 0
                : now - last <= AppModel.nowBarLiveWindow
            if fresh { return NowBarItem(franchiseId: f.id, state: .live, at: last) }
        }
        if let f = nextUp, let next = f.nextAiring(now: now) {
            return NowBarItem(franchiseId: f.id, state: .next, at: next)
        }
        return nil
    }

    /// "Keep watching" — franchises you're mid-watch with an unwatched backlog NOT already surfaced
    /// in Out now (a binged TV season, or a show you've fallen behind on off its airing schedule).
    /// Most backlog first. An airing show can appear here AND in Up next (a new episode still comes).
    var keepWatching: [Franchise] {
        let outNowIds = Set(outNow.map(\.id))
        return Array(
            library
                .filter {
                    $0.effectiveStatus == .watching
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
        // A stale airing slot the source hasn't advanced is not a wait — `nextAiring` drops it (in
        // the franchise's OWN calendar, so a date-only TV slot doesn't expire a day early), so the
        // card falls through to a premiere date or off the shelf instead of claiming "today" for
        // days on end.
        if let part = f.releasingPart, part.isCaughtUp,
           f.nextAiring(now: now) != nil { return .airingWait }
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
            .filter { $0.effectiveStatus == .watching }
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

            // Each franchise is bucketed by the calendar day IT lives in (`dayKey(of:)`): a TMDB
            // drop is a date-only fact, so reading its synthesized instant locally filed it a day
            // late east of UTC+7. Today's cell then splits into "still to come" / "already aired"
            // — but only anime has a real clock to split on; a date-only row stays ahead of you
            // for the whole of its day instead of flipping at a fabricated 17:00 UTC.
            let items = airingFranchises
                .filter {
                    guard let next = $0.releasingPart?.nextAiringAt,
                          $0.dayKey(of: next) == dayKey else { return false }
                    return $0.timeAnchor.isDateOnly ? offset >= 0 : next > now
                }
                .sorted { $0.nextAiringSortKey < $1.nextAiringSortKey }
            // Ascending, like `items`: the rail is one continuous time axis, and flipping the
            // aired half to newest-first ran the morning backwards under the afternoon.
            let aired = airingFranchises
                .filter {
                    guard let last = $0.releasingPart?.lastAiredAt,
                          $0.dayKey(of: last) == dayKey else { return false }
                    return $0.timeAnchor.isDateOnly ? offset <= 0 : last <= now
                }
                .sorted { $0.lastAiredSortKey < $1.lastAiredSortKey }

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
            // "Watched", the same word `LibrarySection.finished` renders and the same word
            // `Copy.statusLabel` now returns for `.completed`. "Finished" is out of the vocabulary
            // (SYS-4): it was naming the user's list state and the series' production state at once.
            case .finished: return "Watched"
            }
        }
    }

    /// One show, one shelf.
    func libShelf(of f: Franchise) -> LibShelf {
        if f.effectiveStatus == .planned { return .planned }
        // In it. The status is the user's own word for the show — it outranks every derived
        // signal, so a finished series they've marked Watching sits on Watching instead of being
        // filed under Finished while the context menu shows a tick next to Watching.
        if f.effectiveStatus == .watching { return .watching }
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
            // Read in the franchise's own calendar — a TMDB premiere is a date, not an instant.
            let p = Formatting.localParts(premiere, anchor: f.timeAnchor)
            return (p.y * 10000 + p.mo * 100 + p.d, 3)
        }
        return f.upcoming?.releaseSortKey ?? (Int.max, 0)
    }

    // MARK: - Actions

    /// Mark the releasing part of a franchise caught up (PUT /me/progress {mediaId, airedEpisodes}).
    func markCaughtUp(_ franchiseId: String) {
        guard let f = franchise(id: franchiseId), let part = f.releasingPart else { return }
        let milestone = !part.isReleasing && part.totalEpisodes > 0 && part.airedEpisodes >= part.totalEpisodes
        FeedbackCoordinator.fire(milestone ? .success : .commitMedium)
        let prev = part.progress
        // Through the same ceiling `setProgress` uses: asserting a number the server would clamp
        // shows "caught up" against a server that disagrees, and the next launch silently reverts.
        let aired = min(part.airedEpisodes, part.progressCeiling)
        applyLocalProgress(franchiseId: franchiseId, mediaId: part.mediaId, episodes: aired)

        // Preserve the original prev if an undo for this franchise is already pending.
        //
        // `count` is the number of episodes this transaction actually recorded, and it must be the
        // real one: it was left at its default of 1, so catching up six episodes confirmed "Episode
        // 12 marked as watched" — the app under-reporting its own write by five, on the one control
        // whose whole purpose is a batch. It is derived from the SAME prev the undo restores, so
        // the sentence and the rollback can never disagree.
        if let cur = undo, !cur.added, cur.franchiseId == franchiseId {
            undo = UndoState(mediaId: part.mediaId, franchiseId: franchiseId,
                             prevProgress: cur.prevProgress, title: f.title, episode: aired,
                             count: max(1, aired - cur.prevProgress))
        } else {
            undo = UndoState(mediaId: part.mediaId, franchiseId: franchiseId,
                             prevProgress: prev, title: f.title, episode: aired,
                             count: max(1, aired - prev))
        }

        celebrate(franchiseId)
        scheduleUndoDismissal()

        Task {
            do {
                _ = try await api.setProgress(mediaId: part.mediaId, episodes: aired)
                settleLocalProgress(mediaId: part.mediaId, episodes: aired)
            } catch {
                // Roll back the optimistic write and retract the celebration/undo that now lie.
                applyLocalProgress(franchiseId: franchiseId, mediaId: part.mediaId, episodes: prev)
                settleLocalProgress(mediaId: part.mediaId, episodes: prev)
                justCaught.remove(franchiseId)
                if let cur = undo, !cur.added, cur.franchiseId == franchiseId { undo = nil }
                showError("Couldn't save progress — check your connection.")
            }
        }
    }

    /// Mark the next episode of the releasing (or resume) part as watched — the Focus card's primary
    /// action. Local commit first, one `.commitLight`, no toast here: the card shows the result and the
    /// view presents the Undo toast when its handoff settles (spec: mark timeline).
    @discardableResult
    func markNext(franchiseId: String, mediaId: Int? = nil, haptic: FeedbackToken = .commitLight) -> UndoState? {
        guard let f = franchise(id: franchiseId) else { return nil }
        let chosen = mediaId.flatMap { id in f.parts.first { $0.mediaId == id } }
        guard let part = chosen ?? f.currentPart ?? f.releasingPart ?? f.resumePart else { return nil }
        let target = min(part.progress + 1, part.progressCeiling)
        guard target > part.progress else { return nil }
        FeedbackCoordinator.fire(haptic)
        let prev = part.progress
        applyLocalProgress(franchiseId: franchiseId, mediaId: part.mediaId, episodes: target)
        Task {
            do {
                _ = try await api.setProgress(mediaId: part.mediaId, episodes: target)
                settleLocalProgress(mediaId: part.mediaId, episodes: target)
            } catch {
                // A mark is a fact about the user: it stays. The failure goes to the SyncBanner
                // with a Retry that re-issues exactly this write.
                SyncCenter.shared.record(command: Copy.Action.markAsWatched, title: f.title,
                                         reason: Copy.Notice.reason(error)) {
                    if let _ = try? await self.api.setProgress(mediaId: part.mediaId, episodes: target) {
                        self.settleLocalProgress(mediaId: part.mediaId, episodes: target)
                    }
                }
            }
        }
        return UndoState(mediaId: part.mediaId, franchiseId: franchiseId, prevProgress: prev, title: f.title, episode: target)
    }

    /// Present an Undo toast for a write that already happened (called when the card handoff settles).
    func presentUndo(_ state: UndoState) {
        undo = state
        scheduleUndoDismissal()
    }

    /// Set explicit progress for a part (detail pips / movie toggle / Library's log-next ring).
    /// The single choke point where every write is bounded to the part's episode count — an
    /// unbounded "+1" control otherwise walks progress off the end of a season (see
    /// `FranchisePart.progressCeiling`).
    func setProgress(franchiseId: String, mediaId: Int, episodes: Int, haptic: Bool = true) {
        let part = franchise(id: franchiseId)?.parts.first { $0.mediaId == mediaId }
        let clamped = min(max(0, episodes), part?.progressCeiling ?? .max)
        let prev = part?.progress
        // One watch fact → commitLight; a contiguous range → commitMedium (spec: haptic vocabulary).
        if haptic { FeedbackCoordinator.fire(abs(clamped - (prev ?? clamped)) > 1 ? .commitMedium : .commitLight) }
        applyLocalProgress(franchiseId: franchiseId, mediaId: mediaId, episodes: clamped)
        Task {
            do {
                _ = try await api.setProgress(mediaId: mediaId, episodes: clamped)
                settleLocalProgress(mediaId: mediaId, episodes: clamped)
            } catch {
                if let prev {
                    applyLocalProgress(franchiseId: franchiseId, mediaId: mediaId, episodes: prev)
                    settleLocalProgress(mediaId: mediaId, episodes: prev)
                } else {
                    // Marked on a franchise we hadn't loaded yet (a pending add) — there's no
                    // previous value to restore, so drop the claim and let the server's win.
                    forgetLocalProgress(mediaId: mediaId)
                }
                showError("Couldn't save progress — check your connection.")
            }
        }
    }

    /// Subscribe to a franchise (POST /me/subscriptions). Status defaults server-side. The add is
    /// optimistic via `pendingAdds` so the card flips to "In library" instantly.
    func addToLibrary(franchiseId: String, title: String, isReleasing: Bool) {
        guard !isInLibrary(franchiseId) else { return }
        FeedbackCoordinator.fire(.success)
        pendingAdds.insert(franchiseId)
        let status: WatchStatus = isReleasing ? .watching : .planned
        let label = status == .watching ? "Watching" : "Plan to watch"
        undo = UndoState(mediaId: nil, franchiseId: franchiseId, prevProgress: 0,
                         title: title, episode: 0, added: true, statusLabel: label)
        scheduleUndoDismissal()
        // First airing ANIME added: the moment notifications become valuable, so ask now. Both
        // ambient layers are AniList-only (TMDB air times are synthesized, so an alert would fire
        // at a fictitious instant) — asking a TV-only user for permission buys them nothing.
        if isReleasing, source(of: franchiseId) == .anilist {
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

    func setStatus(franchiseId: String, status: WatchStatus, haptic: Bool = true) {
        if haptic { FeedbackCoordinator.fire(.selection) }
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
                SyncCenter.shared.record(command: Copy.Toast.movedTo(status.displayName), title: self.franchise(id: franchiseId)?.title ?? "",
                                         reason: Copy.Notice.reason(error)) {
                    self.setStatus(franchiseId: franchiseId, status: status)
                }
            }
        }
    }

    /// `haptic: false` for the undo path — performUndo already fired its own impact.
    func removeFromLibrary(franchiseId: String, haptic: Bool = true) {
        if haptic { FeedbackCoordinator.fire(.commitLight) }
        pendingAdds.remove(franchiseId)
        let idx = library.firstIndex(where: { $0.id == franchiseId })
        let removed = idx.map { library[$0] }
        // Drop any unconfirmed progress for this show — re-adding it later must not replay a
        // write against the fresh subscription.
        removed?.parts.forEach { forgetLocalProgress(mediaId: $0.mediaId) }
        if let idx { library.remove(at: idx) }
        Task {
            do {
                _ = try await api.unsubscribe(franchiseId: franchiseId)
                await syncAmbient()
            } catch {
                if let removed, !library.contains(where: { $0.id == franchiseId }) {
                    library.insert(removed, at: min(idx ?? library.count, library.count))
                }
                SyncCenter.shared.record(command: Copy.Action.removeFromLibrary, title: removed?.title ?? "",
                                         reason: Copy.Notice.reason(error)) {
                    self.removeFromLibrary(franchiseId: franchiseId, haptic: false)
                }
            }
        }
    }

    func performUndo() {
        guard let u = undo else { return }
        FeedbackCoordinator.fire(.selection)
        if u.added, let fid = u.franchiseId {
            removeFromLibrary(franchiseId: fid, haptic: false)
        } else if let fid = u.franchiseId, let mediaId = u.mediaId, isInLibrary(fid) {
            applyLocalProgress(franchiseId: fid, mediaId: mediaId, episodes: u.prevProgress)
            justCaught.remove(fid)
            Task {
                do {
                    _ = try await api.setProgress(mediaId: mediaId, episodes: u.prevProgress)
                    settleLocalProgress(mediaId: mediaId, episodes: u.prevProgress)
                } catch {
                    showError("Couldn't undo — check your connection.")
                    // The undo never reached the server, so there is nothing to defend: drop the
                    // claim BEFORE reloading or the overlay re-applies it over server truth.
                    forgetLocalProgress(mediaId: mediaId)
                    await reload()  // converge back to server truth
                }
            }
        }
        undo = nil
        undoTask?.cancel()
    }

    // MARK: - Internal mutation helpers

    /// Optimistically rewrite a part's progress in the in-memory library so the UI updates
    /// instantly. The write is ALSO recorded in `localProgress`, which is what makes it survive
    /// the two cases the library alone can't express: the franchise isn't loaded yet (a pending
    /// add), and a reload issued before this write returns a snapshot that predates it.
    private func applyLocalProgress(franchiseId: String, mediaId: Int, episodes: Int) {
        localProgress[mediaId] = LocalWrite(episodes: episodes, settledAtSeq: nil)
        guard let fi = library.firstIndex(where: { $0.id == franchiseId }) else { return }
        library[fi] = library[fi].withUpdatedProgress(mediaId: mediaId, episodes: episodes)
    }

    /// The PUT for this part returned — success or failure, both are the end of the story. The
    /// overlay stops being unconditional from here: the next snapshot fetched after this moment
    /// decides, so a value the server won't accept (a clamp, a rejected write) can't stay pinned
    /// for the rest of the session. Superseded by a newer write for the same part.
    private func settleLocalProgress(mediaId: Int, episodes: Int) {
        guard var write = localProgress[mediaId], write.episodes == episodes else { return }
        write.settledAtSeq = reloadSeq
        localProgress[mediaId] = write
    }

    /// Forget an optimistic write without asserting a replacement value — used when a failed write
    /// has no known previous value to roll back to (a part we've never seen). The next snapshot
    /// then wins outright.
    private func forgetLocalProgress(mediaId: Int) {
        localProgress[mediaId] = nil
    }

    /// Replay unconfirmed local writes over a freshly fetched library (`seq` = the `reloadSeq` of
    /// the reload that fetched it). An entry retires when the server reports the same number — the
    /// write has landed and the overlay would only pin a stale value from then on — and also when
    /// this snapshot was fetched AFTER the write settled and still disagrees: the server had its
    /// say and said something else (a clamp, or a PUT that never arrived). Without that second
    /// rule a value the server will not accept is re-applied on every reload forever. Entries for
    /// franchises still missing from the snapshot (an add mid-flight) are kept for the next one.
    private func reconcileLocalProgress(_ fetched: [Franchise], seq: Int) -> [Franchise] {
        guard !localProgress.isEmpty else { return fetched }
        var result = fetched
        for (mediaId, write) in localProgress {
            guard let fi = result.firstIndex(where: { f in
                f.parts.contains { $0.mediaId == mediaId }
            }) else { continue }
            let serverProgress = result[fi].parts.first { $0.mediaId == mediaId }?.progress
            let settledBeforeFetch = write.settledAtSeq.map { seq > $0 } ?? false
            if serverProgress == write.episodes || settledBeforeFetch {
                localProgress[mediaId] = nil
            } else {
                result[fi] = result[fi].withUpdatedProgress(mediaId: mediaId, episodes: write.episodes)
            }
        }
        return result
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
            try? await Task.sleep(for: .seconds(SyncCenter.shared.toastSeconds))
            if Task.isCancelled { return }
            await MainActor.run { self?.undo = nil }
        }
    }
}

/// A zero-result query the server was able to repair, and the words the user actually typed.
/// Present only when the two differ — "showing results for X" that echoes X back is noise.
struct SearchCorrection: Equatable, Sendable {
    let original: String
    let corrected: String

    init?(_ response: SearchResponse) {
        guard let corrected = response.correctedQuery,
              let original = response.originalQuery,
              corrected.caseInsensitiveCompare(original) != .orderedSame else { return nil }
        self.original = original
        self.corrected = corrected
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
                episodes: p.episodes, release: p.release
            )
        }
        return Franchise(copying: self, parts: newParts)
    }

    /// Returns a copy with the watch status replaced (both the library field and the subscription
    /// mirror, so `effectiveStatus` flips immediately). Used for optimistic status updates.
    func withStatus(_ newStatus: WatchStatus) -> Franchise {
        Franchise(id: id, source: source, title: title, cover: cover, banner: banner, synopsis: synopsis,
                  genres: genres, isReleasing: isReleasing, partCounts: partCounts, parts: parts,
                  // `addedAt` is a fact about the account, not about the status: an optimistic
                  // status flip must not erase when the user added the show.
                  subscription: Subscription(status: newStatus, addedAt: subscription?.addedAt),
                  upcoming: upcoming,
                  year: year, studios: studios,
                  status: newStatus, behind: behind, newParts: newParts)
    }
}
