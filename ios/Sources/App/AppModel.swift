import Foundation
import SwiftUI
import OSLog
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
    static let clockTick: TimeInterval = 60            // the clock ticks ON the minute (see `startClock`)
    static let recentsKey = "recentSearches"
    static let recentItemsKey = "recentSearchItems"
    static let maxRecents = 10
    // Foreground-refresh thresholds: reload when the app was backgrounded long enough for aired
    // counts to be stale; re-stamp /me/opened only when the away-time reads as a NEW visit (so
    // brief app switches don't wipe "Out now").
    static let staleReloadAfter: Int64 = 2 * Formatting.minuteMs
    static let newVisitAfter: Int64 = 6 * Formatting.H

    let api: APIClient

    // Library (full franchises with parts + status/behind/newParts). `libraryIds` mirrors it for
    // O(1) membership checks — the Discover grid calls isInLibrary per card on every (animating) frame.
    var library: [Franchise] = [] {
        didSet {
            libraryIds = Set(library.map(\.id))
            libraryIndex = Dictionary(library.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
            libraryVersion &+= 1
        }
    }
    /// id → position in `library`, so `franchise(id:)` is a lookup, not a scan: Search's grid
    /// asked it once per card per body (sampled under the field's focus, 5 Sep).
    @ObservationIgnored private var libraryIndex: [String: Int] = [:]
    /// Bumped on every library write; the key the derived-feed caches (`scheduleDays`) hang off.
    @ObservationIgnored private var libraryVersion = 0
    private(set) var libraryIds: Set<String> = []
    // Ids optimistically added but not yet confirmed by a reload — isInLibrary includes them so
    // "+" buttons flip instantly instead of waiting a network round-trip.
    private(set) var pendingAdds: Set<String> = []
    /// A show whose Add was pressed somewhere that cannot ask "Where are you in X?" (Search's
    /// cards carry no episode counts): the show page opens with the question raised, anchored to
    /// its own Add (review i3 — an airing show added from Search landed on Today as "12 EPISODES
    /// BEHIND", and a long run as "1,1XX").
    var pendingAddPrompt: String?
    /// "Mark series as watched…" chosen on a recommendation's long press: its page opens with the
    /// series confirmation raised — the count, the Cancel and the Undo every series mark has
    /// (review i5, U-N7: from the long press it marked hundreds of episodes with no question).
    var pendingSeriesPrompt: String?

    // ----- Recommended for you (`AppModel+Recommendations.swift`) -----
    /// Server-ranked second-degree recommendations, in the server's order (never re-ranked here).
    var recommendations: [RecommendationItem] = []
    enum RecommendationsState: Sendable { case idle, loaded, unavailable, failed }
    /// `.unavailable`: the server predates the endpoint (404) — the shelf is simply absent.
    var recommendationsState: RecommendationsState = .idle
    @ObservationIgnored var recommendationsFetchedAt: Int64 = 0
    /// The library's membership the last list was ranked against — a change refetches.
    @ObservationIgnored var recommendationsLibraryKey: Int = 0
    @ObservationIgnored var recommendationsTask: Task<Void, Never>?
    /// Hidden at once on "Not interested" / "Already seen", until the next list leaves them out.
    var hiddenRecommendationKeys: Set<String> = []
    /// The recommendation being turned into a show page (a tap or an add on a title with none).
    var resolvingRecommendations: Set<String> = []
    /// Titles added from the shelf this session: they stay on it, ticked, until the next list
    /// (a tile never vanishes under the finger that added it), and their add does not refetch.
    var addedRecommendationKeys: Set<String> = []
    @ObservationIgnored var addedRecommendationIds: Set<String> = []
    /// Show pages materialised for titles the list sent without one (key → franchise id), so a
    /// second tap opens at once and an added one reads as owned.
    var resolvedRecommendationIds: [String: String] = [:]
    /// Shows the user marked this session — the one they just caught up on keeps Today's stage
    /// rather than handing it to a recommendation 650 ms later (review i5, N2).
    @ObservationIgnored var markedThisSession: Set<String> = []
    /// The recommendation holding Today's stage THIS SESSION — kept through an add and through
    /// refetches, so choosing it never swaps it for another title a second later (review i5, F6).
    @ObservationIgnored var sessionStage: RecommendationItem?
    /// A show whose one-call "mark the series" write (`saveProgressBatch`) is in flight — only
    /// ever a show that was not in the library (`markWatched`). Guards a second submission.
    private(set) var savingProgressFor: Set<String> = []
    @ObservationIgnored private var accountGeneration = 0
    /// One-call writes run one after another per show, in the order they were asked for — the
    /// Undo of a series mark waits for the mark itself (the per-part lanes' rule, for this call).
    @ObservationIgnored private var batchChain: [String: Task<Void, Never>] = [:]
    /// How many one-call writes are queued or running per show. `savingProgressFor` is its key
    /// set, so "busy" covers a write still waiting its turn, not only the one on the wire — a
    /// flag raised when the write STARTED read idle for the whole queued window.
    @ObservationIgnored private var batchesInFlight: [String: Int] = [:]
    /// What an isolated model filed instead of Sync status (see `fileFailure`).
    @ObservationIgnored private(set) var isolatedFailures: [WriteIntent?] = []
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
    /// Per-catalogue outcome of the results on screen (`anilist`/`tmdb` → `ok`|`failed`|
    /// `disabled`). The server has always sent it and no view ever read it, so a TMDB outage
    /// rendered as "no TV results". Search renders a notice per failed catalogue.
    var searchSources: [String: String]?
    /// Set by `searchLiterally` for exactly one request: the user asked for the words they typed,
    /// so that request opts out of the server's correction (`exact=1`). Any keystroke clears it.
    private var searchExactOnce = false
    /// The trimmed text the last search was scheduled for — see `scheduleSearch`.
    private var lastScheduledQuery = ""
    // Persisted recent search terms, most-recent first — the search surface's empty state.
    var recentSearches: [String] = []
    /// Shows the user opened or added FROM a search, most recent first — Search's "Recently
    /// searched" rows (Apple Music's model: the things you found, not the strings you typed).
    var recentItems: [FranchiseSummary] = []
    // Trending franchises for the search zero-state shelf. Fetched once per session, lazily on
    // first visit to the search tab; a failure just leaves the shelf out (nothing to retry into).
    var trending: [FranchiseSummary] = []
    private var trendingTask: Task<Void, Never>?
    /// The chart is on its way — Today's empty account holds its skeleton rather than flashing
    /// the "Nothing to watch yet" card for the 300 ms before the billboard arrives.
    var trendingLoading: Bool { trending.isEmpty && trendingTask != nil }

    /// A CTA elsewhere ("Add a show", the empty Schedule) asked for the search field itself, not
    /// just the Search tab. Consumed by `DiscoverView`, which presents the field and clears it.
    var searchFieldRequested = false
    // Anime/TV filter — SEARCH ONLY. Today, Schedule and Library are your shows and always show
    // everything: a filter set once while browsing used to silently hide half of what aired.
    var mediaFilter: MediaFilter = .all

    // Live clock for countdowns.
    var now: Int64 = .nowMs {
        didSet {
            let minute = (now / Formatting.minuteMs) * Formatting.minuteMs
            if minute != nowMinute { nowMinute = minute }
        }
    }
    /// `now` truncated to the minute, written only when the minute changes. A screen whose every
    /// fact is minute-grained (Schedule) observes THIS, so the 20-second tick does not re-lay it
    /// out three times a minute for nothing.
    private(set) var nowMinute: Int64 = (Int64.nowMs / Formatting.minuteMs) * Formatting.minuteMs

    // Celebration + undo + error surfacing.
    var justCaught: Set<String> = []          // franchise ids currently celebrating
    var undo: UndoState?
    // A transient failure message (write didn't reach the server). Rendered by ToastHost.
    var errorToast: String?

    private var clockTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var ccTasks: [String: Task<Void, Never>] = [:]
    /// One in-flight progress PUT per part, and the newest target waiting behind it.
    private var progressLane: [Int: Task<Void, Never>] = [:]
    private var progressQueued: [Int: ProgressWrite] = [:]
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
    /// A show a tapped episode alert asks to open; `MainTabView` consumes it.
    var pendingOpen: String?
    /// A neutral toast (`showNotice`): a receipt, not an error and not an Undo.
    var notice: String?
    private var noticeTask: Task<Void, Never>?

    nonisolated static let log = Logger(subsystem: "app.previously", category: "model")

    /// A model on a scratch transport (the DEBUG write regressions): it never touches what the
    /// device shares with the real model — the offline copy, the follow-up reload, the episode
    /// alerts and the Live Activity.
    @ObservationIgnored private let isolated: Bool
    /// `isolated`, for the model's extensions in other files.
    var isIsolated: Bool { isolated }

    init(api: APIClient, isolated: Bool = false) {
        self.api = api
        self.isolated = isolated
        recentSearches = UserDefaults.standard.stringArray(forKey: AppModel.recentsKey) ?? []
        if let data = UserDefaults.standard.data(forKey: AppModel.recentItemsKey),
           let items = try? JSONDecoder().decode([FranchiseSummary].self, from: data) {
            recentItems = items
        }
    }

    // MARK: - Lifecycle

    func start() {
        startClock()
        // A failed change restored from a previous launch retries by replaying its write here.
        SyncCenter.shared.replay = { [weak self] intent in await self?.replay(intent) }
        // The offline copy first: the last library this device saw, so a launch with no network
        // opens on the shows — stamped with their real age, so the stale strip and the inline
        // notice tell the truth — rather than on an error where the library was. The app had no
        // copy at all: a bad connection at launch was "Couldn't reach the server" over nothing,
        // seconds after the library had been on screen (captured 2 Sep).
        if library.isEmpty {
            // Decoded OFF the main actor (5 Sep): the copy is the whole library, and decoding it
            // here held the main thread for the ident's first frames (sampled: `JSONDecoder`
            // under `start()`, ~300 ms on the simulator). The skeleton holds until it lands, and
            // a reload that lands first wins.
            Task { [weak self] in
                let cached = await Task.detached(priority: .userInitiated) { Self.loadCachedLibrary() }.value
                guard let self, let cached, self.library.isEmpty else { return }
                self.library = cached.response.franchises
                self.prevOpenedAt = max(self.prevOpenedAt, cached.response.prevOpenedAt)
                self.lastLoadedAt = cached.savedAt
            }
        }
        loadCachedRecommendations()
        Task { await stampOpened() }
        Task { await reload() }
    }

    // MARK: - Offline copy

    nonisolated private static let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library-cache.json")
    }()

    private struct LibraryCache: Codable, Sendable {
        let response: LibraryResponse
        let savedAt: Int64
    }

    nonisolated private static func loadCachedLibrary() -> LibraryCache? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(LibraryCache.self, from: data)
    }

    /// Written after every successful load, off the main actor. Atomic, so a launch can never
    /// read a half-written file.
    private static func persistLibrary(_ res: LibraryResponse, at ts: Int64) {
        let cache = LibraryCache(response: res, savedAt: ts)
        let url = cacheURL
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(cache) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// The copy belongs to the account that fetched it; sign-out removes it.
    private static func clearCachedLibrary() {
        try? FileManager.default.removeItem(at: cacheURL)
    }

    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                // To the next minute boundary, not every 20 s (5 Sep): every fact the clock
                // feeds is minute-grained, and each tick re-evaluates every body that reads
                // `now`. Three ticks a minute bought nothing and cost two full re-layouts — one
                // of them, sooner or later, under a moving finger.
                let ms = Int64.nowMs
                let wait = Formatting.minuteMs - ms % Formatting.minuteMs + 50
                try? await Task.sleep(for: .milliseconds(wait))
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
            settleCompletedSeries()
            resumeReturningSeries()
            pruneRecentFragments()
            // Keep the larger of the two prevOpenedAt values we may have seen.
            if res.prevOpenedAt > 0 { prevOpenedAt = max(prevOpenedAt, res.prevOpenedAt) }
            // Animated at the source: every screen's "couldn't refresh" footnote carries a fade
            // transition that never ran, because nothing put an animation in the transaction —
            // the line snapped in and shoved the queue under it 28 pt.
            withAnimation(ThemeMotion.uiGentle) { loadError = false }
            loading = false
            lastLoadedAt = .nowMs
            Self.persistLibrary(res, at: lastLoadedAt)
            refreshRecommendationsIfNeeded()
            await syncAmbient()
        } catch APIError.unauthorized {
            guard seq == reloadSeq else { return }
            // NOT a load failure: retrying can never fix a dead session, and "the server couldn't
            // be reached" would be a lie. Hand it to auth, which returns the user to sign-in.
            handleSessionExpired()
        } catch {
            guard seq == reloadSeq else { return }
            loading = false
            // A cancelled refresh (the pull's task torn down, a superseding reload) is not a
            // failed one: it must not raise the "couldn't refresh" footnote over good content.
            guard !error.isCancellation else { return }
            AppModel.log.error("library reload failed: \(String(describing: error), privacy: .public)")
            withAnimation(ThemeMotion.uiGentle) { loadError = true }
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
        accountGeneration += 1
        savingProgressFor = []
        batchesInFlight = [:]
        batchChain.values.forEach { $0.cancel() }
        batchChain = [:]
        completedByMark = []
        completionSweepDone = false
        // The next account inherits no "already moved back" memory (review i4).
        UserDefaults.standard.removeObject(forKey: Self.resumedPartsKey)
        clearRecommendations()
        recentFragmentsPruned = false
        RewatchStore.shared.reset()
        SeasonSweepLedger.reset()
        Self.clearCachedLibrary()
        clockTask?.cancel(); clockTask = nil
        searchTask?.cancel(); searchTask = nil
        trendingTask?.cancel(); trendingTask = nil
        undoTask?.cancel(); undoTask = nil
        errorTask?.cancel(); errorTask = nil
        noticeTask?.cancel(); noticeTask = nil
        notice = nil
        ccTasks.values.forEach { $0.cancel() }
        ccTasks = [:]
        progressLane.values.forEach { $0.cancel() }
        progressLane = [:]
        progressQueued = [:]
        // The next account must not inherit this one's failed writes — a Retry there would send
        // the previous user's mark into the new user's library.
        SyncCenter.shared.teardown()
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

        lastScheduledQuery = ""
        searchQuery = ""        // didSet clears the results/busy/error triad
        searchResults = []
        searchBusy = false
        searchError = false
        searchCorrection = nil
        searchSources = nil
        trending = []
        searchFieldRequested = false
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

    /// Alerts were just allowed (the Search primer): arm them now, from the library already on
    /// screen. They used to wait for the next reload — "Turn on" granted permission and scheduled
    /// nothing, so the first alert could be a day away.
    func alertsWereAllowed() async {
        await syncAmbient()
    }

    /// Push the current library into the ambient layers (pending episode notifications and the
    /// airing Live Activity) after any confirmed server-side change.
    private func syncAmbient() async {
        guard !isolated else { return }
        await EpisodeNotifications.shared.sync(library: library, now: .nowMs)
        AiringLiveActivityManager.shared.sync(library: library, now: .nowMs)
    }

    // MARK: - Error toast

    /// Surface a write failure. Every optimistic mutation calls this after rolling itself back,
    /// so the UI never silently disagrees with the server.
    /// A quiet receipt with no action: "Episode alerts on". Shorter-lived than an Undo toast.
    func showNotice(_ message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            if Task.isCancelled { return }
            await MainActor.run { self?.notice = nil }
        }
    }

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

    /// A show acted on from a result set (opened or added) is worth remembering as itself.
    func recordRecentItem(_ item: FranchiseSummary) {
        recentItems.removeAll { $0.id == item.id }
        recentItems.insert(item, at: 0)
        if recentItems.count > AppModel.maxRecents {
            recentItems = Array(recentItems.prefix(AppModel.maxRecents))
        }
        persistRecentItems()
    }

    func removeRecentItem(_ id: String) {
        recentItems.removeAll { $0.id == id }
        persistRecentItems()
    }

    /// Everything under "Recently searched": the shows and the leftover terms.
    func clearRecents() {
        recentItems = []
        persistRecentItems()
        clearRecentSearches()
    }

    private func persistRecentItems() {
        UserDefaults.standard.set(try? JSONEncoder().encode(recentItems), forKey: AppModel.recentItemsKey)
    }

    private func persistRecents() {
        UserDefaults.standard.set(recentSearches, forKey: AppModel.recentsKey)
    }

    @ObservationIgnored private var recentFragmentsPruned = false

    /// A bare term that is only the START of a word in a show you have — "slim" on the way to
    /// "Slime" — is a fragment, not a search. The typo guard stops new ones; this clears the ones
    /// saved before it (review i3: "slim" still sat under Recently searched). Once per session,
    /// against the library and the remembered shows.
    private func pruneRecentFragments() {
        guard !recentFragmentsPruned, !recentSearches.isEmpty, !library.isEmpty else { return }
        recentFragmentsPruned = true
        let words = Set((library.map(\.title) + recentItems.map(\.title)).flatMap {
            $0.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        })
        let kept = recentSearches.filter { term in
            let t = term.lowercased()
            return words.contains(t) || !words.contains { $0.count > t.count && $0.hasPrefix(t) }
        }
        if kept != recentSearches {
            recentSearches = kept
            persistRecents()
        }
    }

    // MARK: - Search (debounced)

    private func scheduleSearch() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        // A whitespace-only edit ("naruto" → "naruto ") is not a new query. It used to cancel the
        // in-flight request and re-issue the identical one 300 ms later.
        if trimmed == lastScheduledQuery, !trimmed.isEmpty, !searchExactOnce { return }
        lastScheduledQuery = trimmed
        searchTask?.cancel()

        // Cleared box: cancel any pending search and fall back to the recent-searches empty state.
        if trimmed.isEmpty {
            searchBusy = false
            searchError = false
            searchResults = []
            searchCorrection = nil
            searchSources = nil
            searchTask = nil
            return
        }

        // Busy from the KEYSTROKE, not from the request (tried the other way on 5 Sep and filmed
        // it): with the flag raised only after the debounce, the 300 ms between the last letter
        // and the request drew "No results for …" over the trending grid, then the skeleton,
        // then the answer. Raised here, a query with no answer yet is a skeleton and a list
        // being refined steps back once and stays back until the new answer lands.
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
            searchSources = response.sources
            searchExactOnce = false
            searchError = false
            searchBusy = false
        } catch {
            guard !isCancellation(error) else { return }  // cancelled by a newer keystroke — not a failure
            guard seq == searchSeq else { return }
            searchCorrection = nil
            searchSources = nil
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

    /// The pull on Search: refetch the chart, which also gives a failed first fetch its retry.
    func refreshTrending() async {
        trendingTask?.cancel()
        trendingTask = nil
        if let items = try? await api.trending(limit: 10), !items.isEmpty { trending = items }
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

    func franchise(id: String) -> Franchise? {
        guard let i = libraryIndex[id], i < library.count, library[i].id == id else {
            return library.first { $0.id == id }
        }
        return library[i]
    }

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

    /// All subscribed franchises that have a currently-releasing part AND belong on the calendar
    /// (`Franchise.tracksAirings` — a `planned` show does not). Never media-filtered: what aired
    /// today is a fact about your library, not about a chip you last touched in search.
    var airingFranchises: [Franchise] {
        library.filter { $0.releasingPart != nil && $0.tracksAirings }
    }

    var libraryEmpty: Bool { library.isEmpty }

    // ----- Today -----

    var effectivePrev: Int64 { prevOpenedAt > 0 ? prevOpenedAt : now - AppModel.newLookback }

    /// "Out now" — releasing parts with a RECENTLY aired episode you haven't watched. Keyed on
    /// unwatched-ness + recency, not on `prevOpenedAt`: the old last-open comparison made a new
    /// episode vanish from Today the second time you opened the app, watched or not.
    var outNow: [Franchise] { memo(\.outNow) { computeOutNow() } }

    private func computeOutNow() -> [Franchise] {
        airingFranchises
            .filter {
                // The airing part, or a season released whole this week (`freshPart`).
                guard let part = $0.freshPart(now: now, window: AppModel.outNowWindow) else { return false }
                // A just-caught-up row has to survive its celebration: `behind` drops to 0 the
                // instant progress is written, which would otherwise yank the row (and the frame
                // its result state renders on) before it is ever seen.
                let behind = part.unwatchedOut(now: now, anchor: $0.timeAnchor)
                guard behind > 0 || justCaught.contains($0.id) else { return false }
                // Never-started with a run out is a backlog, not news (`FranchisePart.isNews`).
                guard part.isNews(now: now, anchor: $0.timeAnchor, window: AppModel.outNowWindow) else { return false }
                return now - (part.lastAired(now: now, anchor: $0.timeAnchor) ?? 0) <= AppModel.outNowWindow
            }
            .sorted { lastAiredKey($0) > lastAiredKey($1) }
    }

    /// Descending recency for the live shelf — the airings-advanced `lastAired`, so an episode
    /// that struck a minute ago leads a drop from last night (its catalogue field still says
    /// last week until the next sync).
    private func lastAiredKey(_ f: Franchise) -> Int64 { f.lastAired(now: now) ?? 0 }

    /// "Airing soon" — releasing parts with nextAiringAt within 48h, soonest first.
    var soon: [Franchise] { memo(\.soon) { computeSoon() } }

    private func computeSoon() -> [Franchise] {
        airingFranchises
            .filter {
                guard let next = $0.nextAiring(now: now) else { return false }
                let delta = next - now
                return delta > 0 && delta <= AppModel.soonWindow
            }
            .sorted { ($0.nextAiring(now: now) ?? .max) < ($1.nextAiring(now: now) ?? .max) }
    }

    /// Soonest upcoming episode across all airing franchises (not just the 48h window). This is
    /// the "waiting" hero and the all-caught-up line, so every slot it yields must still be a
    /// genuine WAIT.
    ///
    /// A date-only TV drop stays "up next" for the whole of its day — its clock time is
    /// synthesized, so there is no instant for it to be past, and the labels are day-granular.
    /// An AniList slot is a real instant: once it passes, the episode is out — `nextAiring` (via
    /// `FranchisePart.upcomingAiring`) already moves on to the following slot, so a struck slot
    /// can never be announced here as a future event ("lands Today 9:00 AM" at 8pm).
    var nextUp: Franchise? { memo(\.nextUp) { computeNextUp() } }

    private func computeNextUp() -> Franchise? {
        airingFranchises
            .compactMap { f in f.nextAiring(now: now).map { (f, $0) } }
            .min { $0.1 < $1.1 }?.0
    }

    // MARK: derived-collection memo

    /// The derived collections above and below — `outNow`, `soon`, `nextUp`, `keepWatching`,
    /// `watchingShelf`, `libraryShelves` — used to be bare computed properties, each a filter and
    /// a sort over every `Franchise` (and its airings) on every read, and Today's body read them
    /// about ten times per evaluation. They are pure functions of the library, the minute and
    /// the celebration set, so that is the key (`scheduleDays` has hung off the same idea since
    /// 24 Aug). A read on a warm key touches `library` once, for observation, and copies nothing.
    private struct DerivedKey: Equatable {
        let library: Int
        let minute: Int64
        let caught: Set<String>
    }

    private final class DerivedCache {
        var key: DerivedKey?
        var outNow: [Franchise]?
        var soon: [Franchise]?
        var nextUp: Franchise??
        var keepWatching: [Franchise]?
        var watchingShelf: [Franchise]?
        var libraryShelves: [LibShelfSection]?
    }

    @ObservationIgnored private var derivedCache = DerivedCache()

    private func memo<T>(_ slot: ReferenceWritableKeyPath<DerivedCache, T?>, _ build: () -> T) -> T {
        // `library` is read on every path so a body that only reads a derived collection still
        // observes the library it was derived from (`libraryVersion` is observation-ignored).
        let key = DerivedKey(library: library.isEmpty ? -1 : libraryVersion, minute: nowMinute, caught: justCaught)
        if derivedCache.key != key {
            derivedCache = DerivedCache()
            derivedCache.key = key
        }
        if let hit = derivedCache[keyPath: slot] { return hit }
        let value = build()
        derivedCache[keyPath: slot] = value
        return value
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
        if let f = outNow.first, let last = f.releasingPart?.lastAired(now: now, anchor: f.timeAnchor) {
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
    var keepWatching: [Franchise] { memo(\.keepWatching) { computeKeepWatching() } }

    private func computeKeepWatching() -> [Franchise] {
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
        if let part = f.releasingPart, part.behind(now: now, anchor: f.timeAnchor) > 0,
           now - (part.lastAired(now: now, anchor: f.timeAnchor) ?? 0) <= AppModel.outNowWindow { return .newEpisode }
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
    var watchingShelf: [Franchise] { memo(\.watchingShelf) { computeWatchingShelf() } }

    private func computeWatchingShelf() -> [Franchise] {
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

    /// One episode on the calendar: which show, which part, which episode, when.
    struct ScheduleEntry: Identifiable {
        let franchise: Franchise
        let part: FranchisePart
        let episode: Int
        let at: Int64
        /// It has happened: an exact instant that has passed, or a date-only release whose day is
        /// today or earlier — a TMDB drop is out at some point on its day, and the calendar cannot
        /// know when, so the whole day counts (the row can be marked from the morning on).
        let aired: Bool
        var id: String { "\(franchise.id)/\(part.mediaId)/\(episode)" }
        var dateOnly: Bool { franchise.timeAnchor.isDateOnly }
        var watched: Bool { aired && part.progress >= episode }
    }

    struct ScheduleDay: Identifiable {
        /// Day offset from today in local days — negative for past days.
        let id: Int
        /// Local noon of the day, so day arithmetic and labels never land on a DST seam.
        let noon: Int64
        var isToday: Bool { id == 0 }
        var isPast: Bool { id < 0 }
        /// Ascending by instant, then title.
        let entries: [ScheduleEntry]
    }

    /// A week back through two weeks ahead, chronological, one entry per DATED EPISODE — every
    /// air date of a weekly show inside the window, not once on its next (`FranchisePart.airings`;
    /// `scheduleAirings` falls back to the next/last slots for a server without the field). Empty
    /// days are omitted; today is always present, empty or not, as the feed's anchor — and
    /// `ScheduleView` must RENDER that anchor, empty or not (see `Derived.ahead`).
    /// `planned` shows are excluded (`Franchise.tracksAirings`).
    ///
    /// **Cached.** This used to be a bare computed property, and `ScheduleView` read it through a
    /// dozen of its own computed properties — about thirty full rebuilds per body evaluation. The
    /// feed only changes when the library changes or the minute turns, so that is the cache key.
    var scheduleDays: [ScheduleDay] {
        let key = scheduleFeedKey
        if let cached = scheduleCache, cached.key == key { return cached.days }
        let days = buildScheduleDays()
        scheduleCache = (key, days)
        return days
    }

    /// Identity of the current feed. Equal keys ⇒ identical `scheduleDays`, so a screen can key its
    /// own derivations on it instead of walking the feed again.
    struct ScheduleFeedKey: Equatable { let library: Int; let minute: Int64 }
    var scheduleFeedKey: ScheduleFeedKey {
        // `library` read for observation (see `memo`).
        ScheduleFeedKey(library: library.isEmpty ? -1 : libraryVersion, minute: nowMinute)
    }
    @ObservationIgnored private var scheduleCache: (key: ScheduleFeedKey, days: [ScheduleDay])?

    /// Local noon of today, the anchor every day offset is measured from.
    var scheduleTodayNoon: Int64 {
        let now = nowMinute
        let p = Formatting.localParts(now)
        return now - (Int64(p.hour) * Formatting.H + Int64(p.minute) * Formatting.minuteMs) + 12 * Formatting.H
    }

    private func buildScheduleDays() -> [ScheduleDay] {
        let now = nowMinute
        let noon = scheduleTodayNoon
        let todayKey = Formatting.localDayKey(noon)
        var buckets: [Int: [ScheduleEntry]] = [:]

        // Every part, not only the releasing one: a season that premieres inside the window is
        // announced, not releasing, and a finale that aired three days ago belongs to a finished
        // part. The window is the filter, not the part's status.
        //
        // The SHOW's status is a filter, though — `tracksAirings` keeps `planned` off the
        // calendar. Not written as `airingFranchises` (which is releasing-only): an announced
        // season premiering inside the window has no releasing part and still belongs here.
        for f in library where f.tracksAirings {
            for part in f.parts {
                for a in part.scheduleAirings {
                    // Bucketed by the calendar day the episode lives in, read in ITS source's
                    // calendar: a TMDB drop is a date-only fact, and reading its synthesized
                    // instant locally filed it a day late east of UTC+7.
                    let offset = Int((f.dayKey(of: a.at) - todayKey) / Formatting.D)
                    guard (AppModel.scheduleBack...AppModel.scheduleAhead).contains(offset) else { continue }
                    let aired = f.timeAnchor.isDateOnly ? offset <= 0 : a.at <= now
                    buckets[offset, default: []].append(
                        ScheduleEntry(franchise: f, part: part, episode: a.episode, at: a.at, aired: aired))
                }
            }
        }

        return (AppModel.scheduleBack...AppModel.scheduleAhead).compactMap { offset -> ScheduleDay? in
            let entries = (buckets[offset] ?? []).sorted {
                $0.at != $1.at ? $0.at < $1.at
                    : ($0.franchise.title != $1.franchise.title ? $0.franchise.title < $1.franchise.title
                                                                 : $0.episode < $1.episode)
            }
            guard offset == 0 || !entries.isEmpty else { return nil }
            return ScheduleDay(id: offset, noon: noon + Int64(offset) * Formatting.D, entries: entries)
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
        case planned, comingBack, watching, finished, paused, dropped
        var id: Int { rawValue }
        // No `label` here: the shelf's on-screen name is `LibrarySection.label` (LibraryFacts),
        // the only one ever rendered. A second vocabulary ("Coming back" for the shelf the screen
        // calls "Returning") lived here with no call sites.
    }

    /// One show, one shelf.
    func libShelf(of f: Franchise) -> LibShelf {
        if f.effectiveStatus == .planned { return .planned }
        // In it. The status is the user's own word for the show — it outranks every derived
        // signal, so a finished series they've marked Watching sits on Watching instead of being
        // filed under Finished while the context menu shows a tick next to Watching.
        if f.effectiveStatus == .watching { return .watching }
        // Paused and dropped are the user's word too, and each is its own shelf: filed under
        // "Watched", they vanished behind that shelf's See all, which filters to Watched
        // (review, 23 Sep).
        if f.effectiveStatus == .paused { return .paused }
        if f.effectiveStatus == .dropped { return .dropped }
        // Coming back: nothing to watch right now, but a next installment is announced —
        // dated or TBA alike. This is the "when does it return" lookup made browsable.
        // A day-dated installment whose date has passed has arrived (or slipped) — not "returning"
        // any more, whatever the stale curated note says (`FranchiseUpcoming.hasArrived`).
        // A RUMOUR is not an announcement (review i3: Thrones' "Sequel series rumoured" and Tower
        // of God's "Season 3 rumoured" sat under a header that says Announced) — that show is
        // finished, and its row says the rumour.
        let announced = f.upcoming.map { $0.isFutureInstallment && !$0.isRumored && !$0.hasArrived(now: now) } ?? false
        if announced || nextPremiere(of: f) != nil {
            return .comingBack
        }
        return .finished
    }

    struct LibShelfSection: Identifiable {
        let shelf: LibShelf
        let franchises: [Franchise]
        var id: Int { shelf.id }
    }

    /// The crate, in shelf order; empty shelves are omitted. No filters — the Library root is one
    /// collection (All titles owns search and Arrange). The old `libQuery` filter here had no
    /// writer left anywhere in the app.
    var libraryShelves: [LibShelfSection] { memo(\.libraryShelves) { computeLibraryShelves() } }

    private func computeLibraryShelves() -> [LibShelfSection] {
        return LibShelf.allCases.compactMap { shelf in
            let arr = sortedForShelf(library.filter { libShelf(of: $0) == shelf }, shelf: shelf)
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
        case .planned, .finished, .paused, .dropped:
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

    /// The haptic a progress write signs with — decided HERE, for every surface (review i5 for the
    /// series; 23 Sep for the season: the same season-finishing mark buzzed `.success` on the show
    /// page and `.commitLight` on Today and Schedule). A write that finishes the series or a
    /// finite season is the milestone; otherwise one episode is `.commitLight` and a range
    /// `.commitMedium` (spec: haptic vocabulary). `base` is the caller's token for the
    /// non-milestone case.
    private func progressHaptic(part: FranchisePart, from prev: Int, to target: Int, finished: Bool,
                                base: FeedbackToken? = nil) -> FeedbackToken {
        if finished { return .success }
        if target > prev, !part.isReleasing, part.totalEpisodes > 0,
           prev < part.totalEpisodes, target >= part.totalEpisodes { return .success }
        return base ?? (abs(target - prev) > 1 ? .commitMedium : .commitLight)
    }

    /// Where "Mark all N episodes as watched…" lands for a part: what has aired by NOW (derived
    /// from the part's airings — `markTarget`, the number the show page's menu confirms), bounded
    /// by the same ceiling `setProgress` uses. The long press used the hourly-cron `airedEpisodes`
    /// and could name a different count than the show page for an hour after a drop (review,
    /// 23 Sep).
    func catchUpTarget(_ part: FranchisePart) -> Int {
        min(part.markTarget(now: now), part.progressCeiling)
    }

    /// The long press's "Mark all N episodes as watched…", AFTER its confirmation — the show
    /// page's command from anywhere: the same part (`currentPart`), the same count
    /// (`catchUpTarget`), a confirmation raised by the host (`franchiseQuickActions`).
    func markCaughtUp(_ franchiseId: String) {
        guard let f = franchise(id: franchiseId), let part = f.currentPart, !part.isUpcoming else { return }
        let prev = part.progress
        let target = catchUpTarget(part)
        guard target > prev else { return }
        let shelvedAs = resumableStatus(f, part: part)
        finishedByMark = nil
        applyLocalProgress(franchiseId: franchiseId, mediaId: part.mediaId, episodes: target)
        let finished = finishedByMark == franchiseId
        finishedByMark = nil
        FeedbackCoordinator.fire(progressHaptic(part: part, from: prev, to: target, finished: finished))

        // `count` is the number of episodes this transaction actually recorded — derived from the
        // SAME prev the undo restores, so the sentence and the rollback can never disagree.
        //
        // A pending undo is merged ONLY when it is a plain progress undo on THIS part (then its
        // prev is the older truth and the count covers both writes). Anything else pending — a
        // status move, a series batch, a rewatch start, an add — is a different transaction with a
        // `prevProgress` of 0: merging into it reported "21 episodes watched" for a three-episode
        // catch-up, and its Undo reset the part to zero (review, 23 Sep).
        let base: Int
        if let cur = undo, cur.franchiseId == franchiseId, cur.mediaId == part.mediaId,
           !cur.added, !cur.removed, cur.undoAction == nil, cur.customMessage == nil {
            base = cur.prevProgress
        } else {
            base = prev
        }
        var state = UndoState(mediaId: part.mediaId, franchiseId: franchiseId,
                              prevProgress: base, title: f.title, episode: target,
                              count: max(1, target - base))
        if finished { state.customMessage = Copy.Toast.finished }
        resume(shelvedAs, franchiseId: franchiseId, mediaId: part.mediaId, prevProgress: base, receipt: &state)
        undo = state

        celebrate(franchiseId)
        scheduleUndoDismissal()
        sendProgress(franchiseId: franchiseId, mediaId: part.mediaId, episodes: target)
    }

    /// Mark the next episode of the releasing (or resume) part as watched — the Focus card's primary
    /// action. Local commit first, one `.commitLight`, no toast here: the card shows the result and the
    /// view presents the Undo toast when its handoff settles (spec: mark timeline).
    @discardableResult
    func markNext(franchiseId: String, mediaId: Int? = nil, haptic: FeedbackToken = .commitLight) -> UndoState? {
        guard let f = franchise(id: franchiseId) else { return nil }
        let chosen = mediaId.flatMap { id in f.parts.first { $0.mediaId == id } }
        // The first candidate that can actually advance — the part asked for, else the one the
        // screens call current — never a nil because the first guess was at its ceiling while the
        // lockup named another part (review i5, F1: One Piece's capsule did nothing).
        let candidates = [chosen, f.currentPart, f.resumePart, f.releasingPart].compactMap { $0 }
        guard let part = candidates.first(where: { min($0.progress + 1, $0.progressCeiling) > $0.progress })
        else { return nil }
        let target = min(part.progress + 1, part.progressCeiling)
        let prev = part.progress
        // A mark on a Planned show is watching it: the first one moves it to Watching, and says
        // so on its receipt. Marks never changed the status, so a show 56 episodes in stayed
        // "Planned" — off Today, off Schedule, off the alerts (review, 23 Sep). The same for a
        // show filed WATCHED whose story went on (review i3: Black Clover's Season 2 — marks
        // left it Watched, off Up next, off the alerts, filed under Watched while it aired).
        let shelvedAs = resumableStatus(f, part: part)
        finishedByMark = nil
        applyLocalProgress(franchiseId: franchiseId, mediaId: part.mediaId, episodes: target)
        // The milestone signs the same way on every surface, decided HERE (review i5: Today's
        // capsule tapped `.commitLight` for the mark that finished a series, the show page
        // `.success`), and the move to Watched is told on the receipt.
        let finished = finishedByMark == franchiseId
        finishedByMark = nil
        FeedbackCoordinator.fire(progressHaptic(part: part, from: prev, to: target, finished: finished, base: haptic))
        sendProgress(franchiseId: franchiseId, mediaId: part.mediaId, episodes: target)
        var state = UndoState(mediaId: part.mediaId, franchiseId: franchiseId, prevProgress: prev, title: f.title, episode: target)
        if finished { state.customMessage = Copy.Toast.finished }
        if let shelvedAs, !finished {
            setStatus(franchiseId: franchiseId, status: .watching, haptic: false, present: false)
            state.subtitle = Copy.Toast.movedTo(WatchStatus.watching.displayName)
            let mediaId = part.mediaId
            state.undoAction = { [weak self] in
                self?.setProgress(franchiseId: franchiseId, mediaId: mediaId, episodes: prev, haptic: false)
                self?.setStatus(franchiseId: franchiseId, status: shelvedAs, haptic: false, present: false)
            }
        }
        return state
    }

    /// A user's FORWARD mark watches the show: given the status read BEFORE the write
    /// (`resumableStatus`), moves the show to Watching unless the write finished the series, and
    /// puts the move on the receipt — second line, one Undo that restores the progress AND the
    /// status. Every mark path calls it (review i4: Today's chevron, the long-press, the episode
    /// list's batches and Schedule's toggle left a Planned or Watched show where it was).
    func resume(_ shelvedAs: WatchStatus?, franchiseId: String, mediaId: Int, prevProgress: Int,
                receipt: inout UndoState) {
        guard let shelvedAs, franchise(id: franchiseId)?.isWatchedThrough != true else { return }
        setStatus(franchiseId: franchiseId, status: .watching, haptic: false, present: false)
        receipt.subtitle = Copy.Toast.movedTo(WatchStatus.watching.displayName)
        receipt.undoAction = { [weak self] in
            self?.setProgress(franchiseId: franchiseId, mediaId: mediaId, episodes: prevProgress, haptic: false)
            self?.setStatus(franchiseId: franchiseId, status: shelvedAs, haptic: false, present: false)
        }
    }

    /// The status a forward mark on `part` takes a show OUT of — Planned, or Watched when the part
    /// is an unfinished piece of the main story and no rewatch is running (a rewatch's marks are
    /// the rewatch's). Nil when the mark leaves the status alone.
    func resumableStatus(_ f: Franchise, part: FranchisePart) -> WatchStatus? {
        switch f.effectiveStatus {
        case .planned: return .planned
        case .completed:
            guard part.isMainStory, !part.isComplete,
                  RewatchStore.shared.activeSession(for: f.id) == nil else { return nil }
            return .completed
        default: return nil
        }
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
    ///
    /// Same failure policy as `markNext`: the mark stays and the failure goes to the SyncBanner.
    /// This path used to roll back and flash a red toast, so the tick a user drew on an episode
    /// row survived a bad connection while the batch they confirmed above it vanished — two
    /// answers to one failure, on one screen.
    func setProgress(franchiseId: String, mediaId: Int, episodes: Int, haptic: Bool = true) {
        let part = franchise(id: franchiseId)?.parts.first { $0.mediaId == mediaId }
        let clamped = min(max(0, episodes), part?.progressCeiling ?? .max)
        let prev = part?.progress
        finishedByMark = nil
        applyLocalProgress(franchiseId: franchiseId, mediaId: mediaId, episodes: clamped)
        let finished = finishedByMark == franchiseId
        finishedByMark = nil
        // One watch fact → commitLight; a contiguous range → commitMedium; a write that finishes a
        // season or the series → success — on every surface (`progressHaptic`).
        if haptic {
            if let part {
                FeedbackCoordinator.fire(progressHaptic(part: part, from: prev ?? clamped, to: clamped, finished: finished))
            } else {
                FeedbackCoordinator.fire(abs(clamped - (prev ?? clamped)) > 1 ? .commitMedium : .commitLight)
            }
        }
        sendProgress(franchiseId: franchiseId, mediaId: mediaId, episodes: clamped)
    }

    /// Subscribe to a franchise (POST /me/subscriptions). Status defaults server-side. The add is
    /// optimistic via `pendingAdds` so the card flips to "In library" instantly.
    /// `status`: the shelf the caller chose — "Start from Episode 1" is WATCHING whatever the
    /// run's state (iteration 2: a finished 170-episode run landed on Planned and never reached
    /// Up next). Nil derives it from `isReleasing`, the plain add's rule.
    func addToLibrary(franchiseId: String, title: String, isReleasing: Bool, status chosen: WatchStatus? = nil) {
        guard !isInLibrary(franchiseId) else { return }
        FeedbackCoordinator.fire(.success)
        pendingAdds.insert(franchiseId)
        let status: WatchStatus = chosen ?? (isReleasing ? .watching : .planned)
        // `Copy.Status`, never a local spelling: this line used to say "Plan to watch", a string the
        // copy table explicitly bans, in the one toast every first-time user reads.
        undo = UndoState(mediaId: nil, franchiseId: franchiseId, prevProgress: 0,
                         title: title, episode: 0, added: true, statusLabel: Copy.Status(status))
        scheduleUndoDismissal()
        // **An add never raises the system permission alert.**
        //
        // It used to: this line set the undo state and the next one asked iOS for notification
        // permission, so a modal system alert appeared over the results with "Added … — Undo"
        // counting down underneath it. The undo was unreachable for its whole six-second window,
        // VoiceOver focus was stolen, and the app's first-ever permission ask arrived unprimed in
        // the middle of an unrelated action — where the reflex answer is Don't Allow, after which
        // iOS never asks again and episode alerts are dead for that account permanently.
        //
        // The ask now belongs to an explicit in-app affordance (`DiscoverView.notificationPrimer`,
        // armed by an add that STUCK, raised only after the undo window has closed) and to
        // Profile → Notifications. The system prompt only ever follows the user asking for it.
        Task {
            do {
                // The status the toast promised is the status that is sent. Letting the server
                // re-derive it from `nil` meant the toast could name one shelf and the show land
                // on another whenever the two `isReleasing` readings disagreed.
                _ = try await api.subscribe(franchiseId: franchiseId, status: status)
                await reload()
            } catch {
                if let cur = undo, cur.added, cur.franchiseId == franchiseId { undo = nil }
                pendingAdds.remove(franchiseId)
                // Membership rolls back (the `pendingAdds` entry is gone) and the failure goes
                // where every other membership failure goes: the SyncBanner, with a Retry that
                // re-issues exactly this add. It was the only write in the app that ended in a
                // transient toast with no way back.
                fileFailure(command: Copy.Action.add, title: title,
                                         reason: Copy.Notice.reason(error),
                                         intent: .subscribe(franchiseId: franchiseId, title: title, status: status.rawValue)) {
                    // The status the add was made with — a Planned add from For you retried as
                    // Watching landed on Today as "N EPISODES BEHIND" (review i5, N11).
                    self.addToLibrary(franchiseId: franchiseId, title: title, isReleasing: isReleasing, status: status)
                }
                return
            }
            pendingAdds.remove(franchiseId)
        }
    }

    /// Move a show to another shelf. `present` draws the "Moved to Watching" toast with an Undo
    /// that puts it back — the change used to be the one write in the app that acknowledged
    /// nothing on screen: from Search or Detail the menu closed and that was all.
    func setStatus(franchiseId: String, status: WatchStatus, haptic: Bool = true, present: Bool = true) {
        if haptic { FeedbackCoordinator.fire(.selection) }
        let intent = WriteIntent.status(franchiseId: franchiseId, status: status.rawValue)
        guard let idx = library.firstIndex(where: { $0.id == franchiseId }) else {
            // Not in the loaded library yet (a pending add). Nothing to roll back, but the failure
            // is still a failure: it was fire-and-forget, the only silent write in the app.
            Task {
                do {
                    _ = try await api.setStatus(franchiseId: franchiseId, status: status)
                } catch {
                    guard !Task.isCancelled else { return }
                    fileFailure(command: Copy.Toast.movedTo(status.displayName), title: "",
                                             reason: Copy.Notice.reason(error), intent: intent) {
                        self.setStatus(franchiseId: franchiseId, status: status, haptic: false, present: false)
                    }
                }
            }
            return
        }
        let prevStatus = library[idx].effectiveStatus
        guard prevStatus != status else { return }
        library[idx] = library[idx].withStatus(status)
        let title = library[idx].title
        if present {
            presentUndo(UndoState(mediaId: nil, franchiseId: franchiseId, prevProgress: 0, title: title,
                                  episode: 0, customMessage: Copy.Toast.movedTo(status.displayName),
                                  undoAction: { [weak self] in
                self?.setStatus(franchiseId: franchiseId, status: prevStatus, haptic: false, present: false)
            }))
        }
        Task {
            do {
                _ = try await api.setStatus(franchiseId: franchiseId, status: status)
                await syncAmbient()
                // A finished series or a change of shelf is a change of taste: the list answers
                // it (review i5, N5 — finishing a show used to leave the list untouched until the
                // next reload).
                refreshRecommendationsIfNeeded()
            } catch {
                guard !Task.isCancelled else { return }
                if let i = library.firstIndex(where: { $0.id == franchiseId }) {
                    library[i] = library[i].withStatus(prevStatus)
                }
                if let cur = undo, cur.franchiseId == franchiseId, cur.customMessage != nil { undo = nil }
                fileFailure(command: Copy.Toast.movedTo(status.displayName), title: title,
                                         reason: Copy.Notice.reason(error), intent: intent) {
                    self.setStatus(franchiseId: franchiseId, status: status, haptic: false, present: false)
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
                refreshRecommendationsIfNeeded()
            } catch {
                guard !Task.isCancelled else { return }
                if let removed, !library.contains(where: { $0.id == franchiseId }) {
                    library.insert(removed, at: min(idx ?? library.count, library.count))
                }
                fileFailure(command: Copy.Action.removeFromLibrary, title: removed?.title ?? "",
                                         reason: Copy.Notice.reason(error),
                                         intent: .unsubscribe(franchiseId: franchiseId, title: removed?.title ?? "")) {
                    self.removeFromLibrary(franchiseId: franchiseId, haptic: false)
                }
            }
        }
    }

    func performUndo() {
        guard let u = undo else { return }
        // Undoing a mark IS a progress write, and it signs like the unmark a ring or a disc makes
        // (`.commitLight`); status, add and custom undos keep the selection tick (review, 23 Sep).
        let progressUndo = u.mediaId != nil && !u.added && !u.removed
        FeedbackCoordinator.fire(progressUndo ? .commitLight : .selection)
        if u.added, let fid = u.franchiseId {
            removeFromLibrary(franchiseId: fid, haptic: false)
        } else if let fid = u.franchiseId, let mediaId = u.mediaId, isInLibrary(fid) {
            applyLocalProgress(franchiseId: fid, mediaId: mediaId, episodes: u.prevProgress)
            unsettleCompletion(franchiseId: fid)
            justCaught.remove(fid)
            // An undo is a progress write like any other: it rides the part's lane behind the
            // mark it reverses, so the server can never end on the mark after the user took it
            // back, and a failure keeps the user's last word on screen with a Retry.
            sendProgress(franchiseId: fid, mediaId: mediaId, episodes: u.prevProgress, command: Copy.Action.undo)
        }
        undo = nil
        undoTask?.cancel()
    }

    // MARK: - Progress writes: one lane per part

    private struct ProgressWrite {
        let franchiseId: String
        let episodes: Int
        let command: String
        let title: String
    }

    /// Send a part's progress, serialised per part. Every mark used to spawn a bare `Task`, so
    /// marking 12 then 13 quickly raced two PUTs: when 13's answer landed first, 12's landed
    /// last, the server ended on 12 and the next reload walked the tick back. Now one PUT per
    /// part is in flight at a time, the newest target waits behind it and anything it
    /// superseded is dropped — the server always ends on the user's last word.
    ///
    /// Failure keeps the mark (a mark is a fact about the user — the write rule) and files it
    /// in the SyncBanner with a Retry that re-issues exactly this write, from this launch or the
    /// next (`WriteIntent`).
    private func sendProgress(franchiseId: String, mediaId: Int, episodes: Int,
                              command: String = Copy.Action.markAsWatched) {
        markedThisSession.insert(franchiseId)
        let title = franchise(id: franchiseId)?.title ?? ""
        progressQueued[mediaId] = ProgressWrite(franchiseId: franchiseId, episodes: episodes,
                                                command: command, title: title)
        guard progressLane[mediaId] == nil else { return }
        progressLane[mediaId] = Task { [weak self] in
            while let next = self?.progressQueued.removeValue(forKey: mediaId) {
                await self?.putProgress(next, mediaId: mediaId)
            }
            self?.progressLane[mediaId] = nil
        }
    }

    private func putProgress(_ write: ProgressWrite, mediaId: Int) async {
        do {
            _ = try await api.setProgress(mediaId: mediaId, episodes: write.episodes)
            settleLocalProgress(mediaId: mediaId, episodes: write.episodes)
        } catch {
            // Teardown cancelled the lane, or a newer target is queued behind this one and will
            // decide the outcome — either way this attempt has nothing to report.
            guard !Task.isCancelled, progressQueued[mediaId] == nil else { return }
            fileFailure(command: write.command, title: write.title,
                                     reason: Copy.Notice.reason(error),
                                     intent: .progress(franchiseId: write.franchiseId, mediaId: mediaId,
                                                       episodes: write.episodes)) { [weak self] in
                await self?.putProgress(write, mediaId: mediaId)
            }
        }
    }

    /// Re-issue a write restored from a previous launch (`SyncCenter.replay`). Progress replays
    /// straight to the server — the local value it defends is already on screen if the library
    /// still carries it; membership and status replays go through the live commands so their
    /// optimistic state, rollback and toasts stay the app's one grammar.
    func replay(_ intent: WriteIntent) async {
        switch intent {
        case .franchiseProgress(let franchiseId, let parts, let status, let removeMembership):
            // In the show's chain, so a replay and a fresh mark on the same show cannot race.
            await enqueueBatch(franchiseId) { [weak self] in
                guard let self else { return }
                do {
                    let f: Franchise
                    if let cached = self.franchise(id: franchiseId) { f = cached }
                    else { f = try await self.api.franchise(id: franchiseId, country: AppRegion.current) }
                    try await self.saveProgressBatch(f, parts: parts, status: status, removeMembership: removeMembership)
                } catch {
                    self.recordBatchFailure(franchiseId: franchiseId, title: self.franchise(id: franchiseId)?.title ?? "",
                                            parts: parts, status: status, removeMembership: removeMembership, error: error)
                }
            }.value
        case .progress(let franchiseId, let mediaId, let episodes):
            let write = ProgressWrite(franchiseId: franchiseId, episodes: episodes,
                                      command: Copy.Action.markAsWatched,
                                      title: franchise(id: franchiseId)?.title ?? "")
            await putProgress(write, mediaId: mediaId)
        case .status(let franchiseId, let raw):
            if let status = WatchStatus(rawValue: raw) {
                setStatus(franchiseId: franchiseId, status: status, haptic: false, present: false)
            }
        case .subscribe(let franchiseId, let title, let raw):
            let status = WatchStatus(rawValue: raw) ?? .planned
            addToLibrary(franchiseId: franchiseId, title: title, isReleasing: status == .watching)
        case .unsubscribe(let franchiseId, _):
            removeFromLibrary(franchiseId: franchiseId, haptic: false)
        }
    }

    // MARK: - Internal mutation helpers

    /// Queue `work` behind every one-call write already asked for this show. The show reads
    /// busy (`savingProgressFor`) from this moment until the last queued write has finished.
    @discardableResult
    func enqueueBatch(_ franchiseId: String, _ work: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let generation = accountGeneration
        let previous = batchChain[franchiseId]
        batchesInFlight[franchiseId, default: 0] += 1
        savingProgressFor.insert(franchiseId)
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, generation == self.accountGeneration else { return }
            await work()
            guard generation == self.accountGeneration else { return }
            let left = (self.batchesInFlight[franchiseId] ?? 1) - 1
            if left > 0 {
                self.batchesInFlight[franchiseId] = left
            } else {
                self.batchesInFlight[franchiseId] = nil
                self.batchChain[franchiseId] = nil
                self.savingProgressFor.remove(franchiseId)
            }
        }
        batchChain[franchiseId] = task
        return task
    }

    /// Where a write the server refused is filed: Sync status — the banner, Profile's rows, and
    /// the replay a later launch runs. An ISOLATED model (a scratch transport) files it in a list
    /// of its own, so it can never leave a write behind for a later launch to replay against the
    /// real account (the DEBUG regressions did, 23 Sep).
    func fileFailure(command: String, title: String, reason: String, intent: WriteIntent? = nil,
                     retry: @escaping @MainActor () async -> Void) {
        guard !isolated else { isolatedFailures.append(intent); return }
        SyncCenter.shared.record(command: command, title: title, reason: reason, intent: intent, retry: retry)
    }

    /// A show drawn into the library ahead of the write that adds it (`markWatched` on a show that
    /// was not in the library): in `library` so every screen shows it, and in `pendingAdds` so a
    /// reload that lands first does not take it away.
    func insertPending(_ f: Franchise) {
        pendingAdds.insert(f.id)
        if let index = library.firstIndex(where: { $0.id == f.id }) { library[index] = f } else { library.append(f) }
    }

    /// The same show taken back out — its write failed, or its Undo ran.
    func withdrawPending(_ franchiseId: String) {
        pendingAdds.remove(franchiseId)
        library.removeAll { $0.id == franchiseId }
    }

    /// One server transaction for the chosen seasons, the status, and — for a show that is not in
    /// the library yet — the subscription itself (a progress row with no membership cannot exist).
    /// The caller has already drawn the result (`markWatched`); this makes it canonical. Waits for
    /// any per-part progress lane of the show first, so the server still ends on the user's last
    /// word.
    func saveProgressBatch(_ f: Franchise, parts: [FranchiseProgressValue], status: WatchStatus?,
                           removeMembership: Bool = false) async throws {
        let generation = accountGeneration
        let lanes = f.parts.compactMap { progressLane[$0.mediaId] }
        for lane in lanes { await lane.value }
        guard generation == accountGeneration else { throw CancellationError() }
        let response = try await api.setFranchiseProgress(franchiseId: f.id, parts: parts, status: status)
        guard generation == accountGeneration else { throw CancellationError() }
        if removeMembership { _ = try await api.unsubscribe(franchiseId: f.id) }
        guard generation == accountGeneration else { throw CancellationError() }
        // Any library request started before this transaction returned is now stale.
        reloadSeq += 1
        loading = false
        var saved = franchise(id: f.id)?.grafting(f) ?? f
        for value in response.progress {
            saved = saved.withUpdatedProgress(mediaId: value.mediaId, episodes: value.episodes)
            localProgress[value.mediaId] = LocalWrite(episodes: value.episodes, settledAtSeq: reloadSeq)
        }
        if let status = response.status { saved = saved.withStatus(status) }
        pendingAdds.remove(f.id)
        if removeMembership {
            library.removeAll { $0.id == f.id }
        } else if let index = library.firstIndex(where: { $0.id == f.id }) {
            library[index] = saved
        } else {
            library.append(saved)
        }
        if !isolated {
            Self.persistLibrary(LibraryResponse(franchises: library, prevOpenedAt: prevOpenedAt), at: lastLoadedAt)
            Task { await reload() }
        }
    }

    /// A one-call write that failed: into Sync status with the exact write as its Retry. A
    /// membership write rolls back (the write rules), so the show it added leaves the library.
    func recordBatchFailure(franchiseId: String, title: String, parts: [FranchiseProgressValue],
                            status: WatchStatus?, removeMembership: Bool = false, error: Error) {
        guard !error.isCancellation else { return }
        let intent = WriteIntent.franchiseProgress(franchiseId: franchiseId, parts: parts,
                                                  status: status, removeMembership: removeMembership)
        fileFailure(command: removeMembership ? Copy.Action.undo : Copy.Action.markAsWatched,
                                 title: title, reason: Copy.Notice.reason(error), intent: intent) { [weak self] in
            await self?.replay(intent)
        }
    }

    /// Optimistically rewrite a part's progress in the in-memory library so the UI updates
    /// instantly. The write is ALSO recorded in `localProgress`, which is what makes it survive
    /// the two cases the library alone can't express: the franchise isn't loaded yet (a pending
    /// add), and a reload issued before this write returns a snapshot that predates it.
    private func applyLocalProgress(franchiseId: String, mediaId: Int, episodes: Int) {
        localProgress[mediaId] = LocalWrite(episodes: episodes, settledAtSeq: nil)
        guard let fi = library.firstIndex(where: { $0.id == franchiseId }) else { return }
        library[fi] = library[fi].withUpdatedProgress(mediaId: mediaId, episodes: episodes)
        settleCompletion(franchiseId: franchiseId)
    }

    /// The shows THIS session moved to Watched by marking their last episode — Undo of that
    /// mark takes the move back too (`unsettleCompletion`).
    private var completedByMark: Set<String> = []
    /// The show `settleCompletion` just moved, for the mark that caused it to say so.
    private var finishedByMark: String?
    private var completionSweepDone = false

    /// A finished series whose last episode has just been marked is filed under Watched (review
    /// i4: Thrones read "Watching ⌄" in the bar over "COMPLETE · Watched once"), the way AniList,
    /// MAL and Trakt file it. A status write like any other: it rolls back on failure.
    private func settleCompletion(franchiseId: String) {
        guard let f = franchise(id: franchiseId), f.effectiveStatus == .watching, f.isWatchedThrough else { return }
        completedByMark.insert(franchiseId)
        finishedByMark = franchiseId
        setStatus(franchiseId: franchiseId, status: .completed, haptic: false, present: false)
    }

    private func unsettleCompletion(franchiseId: String) {
        guard completedByMark.remove(franchiseId) != nil,
              let f = franchise(id: franchiseId), f.effectiveStatus == .completed, !f.isWatchedThrough else { return }
        setStatus(franchiseId: franchiseId, status: .watching, haptic: false, present: false)
    }

    /// Rows the server still files under Watching though every episode is watched and nothing is
    /// coming (data from before the rule above): moved once per session, quietly.
    private func settleCompletedSeries() {
        guard !completionSweepDone else { return }
        completionSweepDone = true
        for f in library where f.effectiveStatus == .watching && f.isWatchedThrough {
            setStatus(franchiseId: f.id, status: .completed, haptic: false, present: false)
        }
    }

    /// The sweep's other half: a show filed WATCHED whose story has gone on — the next part of
    /// the main story is airing and everything before it is finished — is back on Watching,
    /// once, with an Undo (review i3: Black Clover's Season 2 would have aired under "Watched",
    /// off Up next and off the alerts, with Library filing it as "Anime · 2017"). TV Time moves
    /// a returning show back the same way. Each part is resumed at most ONCE (`resumedPartsKey`):
    /// a show put back under Watched stays there for that part.
    private func resumeReturningSeries() {
        guard !isolated else { return }
        var done = Set(UserDefaults.standard.array(forKey: Self.resumedPartsKey) as? [Int] ?? [])
        var moved: [Franchise] = []
        for f in library where f.effectiveStatus == .completed {
            // Airing now, or a season dropped whole this week (`freshPart`, review i4 — a Netflix
            // season was never "releasing", so a Watched show never came back for one).
            guard let part = f.freshPart(now: now, window: AppModel.outNowWindow), part.isMainStory,
                  part.progress == 0,
                  !done.contains(part.mediaId),
                  part.airedByNow(now: now, anchor: f.timeAnchor) > 0,
                  f.hasReached(part),
                  RewatchStore.shared.activeSession(for: f.id) == nil else { continue }
            done.insert(part.mediaId)
            moved.append(f)
            setStatus(franchiseId: f.id, status: .watching, haptic: false, present: false)
        }
        guard !moved.isEmpty else { return }
        UserDefaults.standard.set(Array(done), forKey: Self.resumedPartsKey)
        if moved.count == 1, let f = moved.first {
            var receipt = UndoState(mediaId: nil, franchiseId: f.id, prevProgress: 0, title: f.title, episode: 0,
                                    customMessage: Copy.Toast.backOnWatching)
            receipt.undoAction = { [weak self] in
                self?.setStatus(franchiseId: f.id, status: .completed, haptic: false, present: false)
            }
            presentUndo(receipt)
        } else {
            showNotice(Copy.Toast.backOnWatchingCount(moved.count))
        }
    }

    private static let resumedPartsKey = "resumedReturningParts"

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
            // `withProgress` carries EVERY field. The hand-built copy this replaces omitted
            // `airings` (and would have omitted each field added after it), so one local mark
            // silently took the show off the calendar until the next library reload.
            newParts[idx] = newParts[idx].withProgress(episodes)
        }
        return Franchise(copying: self, parts: newParts)
    }

    /// Returns a copy with the watch status replaced (both the library field and the subscription
    /// mirror, so `effectiveStatus` flips immediately). Used for optimistic status updates.
    func withStatus(_ newStatus: WatchStatus) -> Franchise {
        Franchise(copying: self, parts: parts,
                  // `addedAt` is a fact about the account, not about the status: an optimistic
                  // status flip must not erase when the user added the show.
                  subscription: Subscription(status: newStatus, addedAt: subscription?.addedAt),
                  status: newStatus)
    }
}
