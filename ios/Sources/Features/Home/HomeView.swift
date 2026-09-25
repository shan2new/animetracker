import SwiftUI

// Home — the departures board (26 Sep 2026).
//
// "I think the today screen should become Feed… feed should not be the home screen for sure"
// (owner). Home is what the mark stands for — "P." on a departures board, what arrives next — and
// it answers the reason the app is opened, in the order a person acts on it:
//   · the BILLBOARD — the next thing to watch, full bleed, as the old Today's was ("let's make it
//     like the full bleed art it was earlier", owner): a drop you have not seen, else tonight's
//     airing, else the top of your queue;
//   · RECENTLY AIRED — the past week's episodes you have not marked ("what about previous week /
//     unmarked episodes?", owner), each one tap from marked;
//   · UP NEXT — the rest of your queue as the Library's poster cards, at the episode you left off,
//     including the shows that are NOT airing — which a calendar never shows;
//   · THIS WEEK — the next airings; "This week ›" and the bar's calendar open the whole Schedule.
// Each show appears once, in the first place that carries it. It is short by construction: it lists
// what can be acted on, so it is never a wall and never empty while a show is in progress.
//
// A mark is an EVENT here (26 Sep, "it doesn't feel as delightful as it should be", owner): the
// control fills and says so for a beat (`commitBeat`), then the write lands and what it changed
// rolls — the episode, the count, the bar — and whatever it finished leaves its place (a row, a
// tile, the billboard handing over to the next thing).
struct HomeView: View {
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String, _ focus: EpisodeFocus?) -> Void
    let onOpenSchedule: () -> Void
    let onOpenLibrary: (WatchStatus) -> Void
    let onOpenRoute: (FeedRoute) -> Void
    let onAddShow: () -> Void
    /// Bumped when Home is re-selected: every sheet goes, and the page goes to its top.
    let topSignal: Int
    /// Bumped by the notification route: every sheet goes (the route then pushes).
    let dismissSignal: Int

    @Environment(AppModel.self) private var appModel
    @Environment(LaunchHandoff.self) private var launch: LaunchHandoff?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var chrome = HomeChrome()
    @State private var box = HomeFeedBox()
    @State private var showProfile = false
    /// A feed page asked for from inside Profile (Saved → a post): opened once the sheet has gone.
    @State private var pendingRouteAfterSheet: FeedRoute?
    /// A mark that covers more than one episode waits for its exact count to be confirmed.
    @State private var prompt: FranchiseDetailView.WritePrompt?
    /// Marks mid-flight — the billboard's, a tile's (franchise id), a row's (airing id).
    @State private var committingHero = false
    @State private var committingTiles: Set<String> = []
    @State private var committingRows: Set<String> = []
    @State private var artMarked = false
    /// The billboard art's palette colour: the page's ground and the bar are painted from it.
    @State private var heroTint: Color?

    private enum Anchor {
        static let top = "home/top"
    }

    /// The billboard's share of the window (26 Sep, "make the art take more height", owner): most of
    /// the screen above the tab bar, the next section's title peeking under its foot so the page
    /// says there is more. A titled poster fills the frame below the bar; a logo'd one is whole.
    private static let billboardFraction: CGFloat = 0.84
    /// How long a control holds its marked state before the write lands and the page moves on —
    /// the episode list's `beginCommit` hold.
    private static let commitBeat: Duration = .milliseconds(550)

    private var billboardHeight: CGFloat { (ThemeMetrics.windowHeight * Self.billboardFraction).rounded() }
    private var band: CGFloat { ThemeMetrics.topSafeInset + FeedMetrics.headerRow }

    /// The art's colour — resolved this visit, else remembered from the last (`PaletteCache`
    /// persists), so the page opens in its colour on the first frame.
    private func tint(_ feed: HomeFeed) -> Color? {
        heroTint ?? PaletteCache.shared.tint(for: feed.hero?.franchise.billboardArt.url)
    }

    /// The show's hue at canvas depth — where the billboard lands and the bar sits (canvas with no
    /// billboard).
    private func groundTop(_ feed: HomeFeed) -> Color {
        guard feed.hero != nil else { return ThemeColor.canvas }
        return DetailTint.ground(tint(feed), lightness: DetailTint.groundTopLightness)
    }

    /// Composed once per library and minute — never in a body.
    private var feed: HomeFeed {
        let key = appModel.scheduleFeedKey
        if box.key == key { return box.value }
        let value = HomeCompose.feed(appModel)
        box.key = key
        box.value = value
        return value
    }

    // MARK: - Body

    var body: some View {
        let feed = feed
        let billboard = feed.hero == nil ? 0 : billboardHeight
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 0).id(Anchor.top)
                        content(feed)
                    }
                    .background(alignment: .top) {
                        if feed.hero != nil {
                            HomeGround(tint: tint(feed), top: groundTop(feed), billboard: billboard)
                                .animation(ThemeMotion.uiPoster, value: tint(feed) == nil)
                        }
                    }
                    // The scroll probe: WRITES the bar's one fact, never screen state.
                    .background {
                        Color.clear.onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.frame(in: .global).minY
                        } action: { minY in
                            chrome.track(contentTop: minY, billboard: billboard)
                        }
                    }
                }
                // The billboard runs under the status bar and the bar, as the old Today's did.
                .ignoresSafeArea(edges: .top)
                .scrollIndicators(.hidden)
                .tabBarContentMargin()
                .laneClearance(appModel)
                .previouslyRefreshable { await appModel.reload() }

                HomeHeader(chrome: chrome,
                           ground: groundTop(feed),
                           onProfile: { showProfile = true },
                           onTop: { scrollToTop(proxy) },
                           onSchedule: onOpenSchedule)
            }
            .onChange(of: topSignal) { _, _ in
                dismissAll()
                scrollToTop(proxy)
            }
            #if DEBUG
            // `-homeAnchor recent|upnext|week` (DEBUG): a capture scrolled to a section.
            .task(id: appModel.library.isEmpty) {
                guard !appModel.library.isEmpty, let anchor = UserDefaults.standard.string(forKey: "homeAnchor") else { return }
                try? await Task.sleep(for: .milliseconds(1200))
                proxy.scrollTo("home/\(anchor)", anchor: UnitPoint(x: 0.5, y: 0.12))
            }
            #endif
        }
        .background(ThemeColor.canvas.ignoresSafeArea())
        // The bar is Home's own; no system edge effect and no system navigation bar under it.
        .chromeScrollEdgeHidden(.top)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showProfile, onDismiss: profileDismissed) {
            ProfileView(onOpenLibrary: { status in
                            showProfile = false
                            onOpenLibrary(status)
                        },
                        onOpenDetail: { id in
                            showProfile = false
                            onOpenDetail(id, "profile/\(id)", nil)
                        })
                .environment(\.openFeedRoute, { route in
                    pendingRouteAfterSheet = route
                    showProfile = false
                })
                .perfScreen("Profile")
        }
        // An alert, not a popover: a batch changes a number the user did not type (Schedule's rule).
        .alert(prompt?.title ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
               presenting: prompt) { p in
            Button(p.confirm) { p.perform() }
            Button(Copy.Confirm.cancel, role: .cancel) {}
        } message: { p in
            Text(p.message)
        }
        .onChange(of: dismissSignal) { _, _ in dismissAll() }
        .onChange(of: showProfile) { _, open in
            if appModel.feedOverlayOpen != open { appModel.feedOverlayOpen = open }
        }
        // Nothing to wait for (no billboard, an empty or failed library): the launch may leave.
        .onChange(of: feed.hero == nil && !(appModel.loading && appModel.library.isEmpty), initial: true) { _, nothing in
            if nothing { markArtReady() }
        }
        .task(id: feed.hero?.franchise.billboardArt.url) {
            guard let url = feed.hero?.franchise.billboardArt.url else { return }
            let resolved = await PaletteCache.shared.resolve(url: url, maxPixel: 360)
            withAnimation(ThemeMotion.uiPoster) { heroTint = resolved }
        }
        .onAppear {
            #if DEBUG
            if FeedCapture.openProfile { showProfile = true }
            #endif
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ feed: HomeFeed) -> some View {
        if appModel.loading && appModel.library.isEmpty {
            SkeletonGate(isLoading: true) { skeleton } content: { EmptyView() }
        } else if appModel.library.isEmpty {
            EmptyState(appModel.loadError
                       ? (SyncCenter.shared.isOnline ? .serverNoCache : .offlineNoData)
                       : .emptyToday,
                       prominence: .major,
                       primary: appModel.loadError ? { Task { await appModel.reload() } } : onAddShow)
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.top, band + ThemeSpace.x10 * 2)
        } else if feed.isEmpty {
            caughtUp
        } else {
            if let hero = feed.hero {
                HomeBillboard(hero: hero, now: appModel.nowMinute, height: billboardHeight, band: band,
                              committing: committingHero,
                              tint: tint(feed), landing: groundTop(feed),
                              onOpen: { open(hero) },
                              onMark: { markHero(hero) },
                              onArtLoaded: markArtReady,
                              onCopyTop: { chrome.trackCopy(top: $0) })
                    .franchiseQuickActions(appModel.isInLibrary(hero.franchise.id) ? hero.franchise : nil,
                                           appModel: appModel)
                    // A new show on the billboard (the last one caught up): the old picture leaves,
                    // THEN the next arrives — the app's handoff, never two titles at half opacity.
                    .id(hero.franchise.id)
                    .transition(.handoff(reduceMotion: reduceMotion))
            } else {
                Color.clear.frame(height: band)
            }
            if appModel.sectionFailed {
                InlineNotice(Copy.Notice.today) { Task { await appModel.reload() } }
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .padding(.top, ThemeSpace.x3)
            }
            // The first section under the billboard sits close to its mark (the old Today's x4: the
            // pill to the next header ≈ 36 pt), the rest a section's gap apart.
            let lead = feed.hero != nil
            if !feed.recent.isEmpty { recent(feed.recent, leading: lead) }
            if !feed.queue.isEmpty { upNext(feed.queue, leading: lead && feed.recent.isEmpty) }
            if !feed.week.isEmpty { week(feed.week, leading: lead && feed.recent.isEmpty && feed.queue.isEmpty) }
        }
    }

    /// Nothing out, nothing queued, nothing this week: the board is clear — said once, calmly, with
    /// the way to the whole Schedule.
    private var caughtUp: some View {
        EmptyState(Copy.Home.caughtUp, prominence: .major, primary: onOpenSchedule)
            .padding(.horizontal, ThemeMetrics.gutter)
            .padding(.top, band + ThemeSpace.x10 * 2)
    }

    // MARK: - Recently aired

    /// The past week's episodes you have not marked: the agenda's own row with the day in its date
    /// column and the ring — the one next step on the row — to mark it. A marked row leaves.
    private func recent(_ items: [HomeAiring], leading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeaderRow(Copy.Home.recentlyAired, action: onOpenSchedule)
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.bottom, ThemeSpace.x2)
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                let first = i == 0 || items[i - 1].day != item.day
                let e = item.entry
                let count = max(1, e.episode - e.part.progress)
                airingRow(item, first: first, state: .toWatch) {
                    AiringStateControl(state: .toWatch, episode: e.episode,
                                       committing: committingRows.contains(item.id),
                                       title: e.franchise.displayTitle, batch: count > 1, count: count,
                                       canMark: appModel.isInLibrary(e.franchise.id)) {
                        markThrough(item)
                    }
                }
                .padding(.top, first && i > 0 ? ThemeSpace.x3 : 0)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .padding(.top, leading ? ThemeSpace.x4 : ThemeMetrics.sectionGap)
        .animation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion), value: items.map(\.id))
        .id("home/recent")
    }

    // MARK: - Up next

    private func upNext(_ items: [HomeQueueItem], leading: Bool) -> some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
            SectionHeaderRow(Copy.Home.upNext, action: { onOpenLibrary(.watching) })
                .padding(.horizontal, ThemeMetrics.gutter)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: ThemeMetrics.shelfGap) {
                    ForEach(items) { item in
                        HomeUpNextTile(item: item, now: appModel.nowMinute,
                                       committing: committingTiles.contains(item.id),
                                       onOpen: {
                                           onOpenDetail(item.franchise.id, "home-next/\(item.id)",
                                                        EpisodeFocus(mediaId: item.part.mediaId, episode: item.episode))
                                       },
                                       onMark: { markTile(item) })
                            .franchiseQuickActions(item.franchise, appModel: appModel)
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                }
                .scrollTargetLayout()
                .animation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion), value: items.map(\.id))
            }
            .contentMargins(.horizontal, ThemeMetrics.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .padding(.top, leading ? ThemeSpace.x4 : ThemeMetrics.sectionGap)
        .id("home/upnext")
    }

    // MARK: - This week

    private func week(_ items: [HomeAiring], leading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeaderRow(Copy.Home.thisWeek, action: onOpenSchedule)
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.bottom, ThemeSpace.x2)
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                let first = i == 0 || items[i - 1].day != item.day
                airingRow(item, first: first, state: .upcoming) { EmptyView() }
                    .padding(.top, first && i > 0 ? ThemeSpace.x3 : 0)
            }
        }
        .padding(.top, leading ? ThemeSpace.x4 : ThemeMetrics.sectionGap)
        .id("home/week")
    }

    // MARK: - Rows

    /// Schedule's agenda row: the date on a day's first row, the show's face, its name, "Episode 14
    /// · 7:30 PM", and the trailing slot.
    private func airingRow<Trailing: View>(_ item: HomeAiring, first: Bool, state: AiringState,
                                           @ViewBuilder trailing: @escaping () -> Trailing) -> some View {
        let e = item.entry
        let f = e.franchise
        let line = airingLine(e)
        let p = Formatting.localParts(item.noon)
        return ScheduleAgendaRow(franchise: f,
                                 date: first ? (Formatting.weekdayShort(p.wd), "\(p.d)") : nil,
                                 isToday: item.day == 0, line: line, state: state,
                                 spoken: "\(Formatting.formatted(e.at, skeleton: "EEEEdMMMM", anchor: f.timeAnchor)), \(f.title), \(line)",
                                 onOpen: {
                                     onOpenDetail(f.id, "home-row/\(item.id)",
                                                  EpisodeFocus(mediaId: e.part.mediaId, episode: e.episode))
                                 },
                                 trailing: trailing)
            .franchiseQuickActions(appModel.isInLibrary(f.id) ? f : nil, appModel: appModel)
    }

    /// "Episode 14 · 7:30 PM" — a premiere in its own words; a date-only airing has no clock.
    private func airingLine(_ e: AppModel.ScheduleEntry) -> String {
        let what: String
        if e.part.kind == .movie || e.episode == 1 {
            let label = e.part.kind == .movie
                ? e.part.canonicalLabel
                : (e.franchise.parts.count > 1 ? Copy.compactPartLabel(e.part.canonicalLabel) : "")
            what = Copy.Schedule.premiere(label)
        } else {
            what = Copy.episode(e.episode)
        }
        guard !e.dateOnly else { return what }
        return "\(what) \u{00B7} \(Formatting.fmtTime(e.at, anchor: e.franchise.timeAnchor))"
    }

    // MARK: - Loading

    /// The loading frame in the screen's own shape: the billboard's ground, then a shelf of posters.
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: ThemeSpace.x3) {
            SkeletonBlock(width: nil, height: billboardHeight, radius: 0)
            SkeletonLine(width: 96, height: 19)
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.top, ThemeSpace.x4)
            HStack(spacing: ThemeMetrics.shelfGap) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonPoster(width: 150, height: 225, radius: ThemeRadius.poster)
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Actions

    private func open(_ hero: HomeHero) {
        onOpenDetail(hero.franchise.id, "home-billboard/\(hero.franchise.id)",
                     EpisodeFocus(mediaId: hero.part.mediaId, episode: hero.episode))
    }

    /// The billboard's mark: the pill says "Watched" for a beat, then the write lands and the
    /// billboard rolls to the next episode — or hands over, if that was the last one out.
    private func markHero(_ hero: HomeHero) {
        guard !committingHero else { return }
        committingHero = true
        Task {
            try? await Task.sleep(for: Self.commitBeat)
            write(hero.franchise, part: hero.part)
            committingHero = false
        }
    }

    /// A tile's mark: the disc fills for a beat, then the tile rolls to the next episode — or
    /// leaves the shelf, caught up.
    private func markTile(_ item: HomeQueueItem) {
        guard !committingTiles.contains(item.id) else { return }
        committingTiles.insert(item.id)
        Task {
            try? await Task.sleep(for: Self.commitBeat)
            write(item.franchise, part: item.part)
            committingTiles.remove(item.id)
        }
    }

    /// The next episode, written. Everything it changes rolls (numeric text, the bar) on one spring;
    /// the Undo rides the lane.
    private func write(_ f: Franchise, part: FranchisePart) {
        withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) {
            if let undo = appModel.markNext(franchiseId: f.id, mediaId: part.mediaId) {
                appModel.presentUndo(undo)
            }
        }
    }

    /// A recently aired episode, marked — and everything before it, with the exact count confirmed
    /// first when that is more than one (Schedule's ladder). The ring fills, then the row leaves.
    private func markThrough(_ item: HomeAiring) {
        let e = item.entry
        let part = e.part
        let target = e.episode
        let count = target - part.progress
        guard count > 0, !committingRows.contains(item.id) else { return }
        let commit = {
            committingRows.insert(item.id)
            Task {
                try? await Task.sleep(for: Self.commitBeat)
                withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) {
                    appModel.setProgress(franchiseId: e.franchise.id, mediaId: part.mediaId, episodes: target)
                }
                committingRows.remove(item.id)
            }
        }
        if count > 1 {
            prompt = .init(title: Copy.Confirm.batchMarkTitle(count),
                           message: Copy.Confirm.batchMarkMessage(from: part.progress, to: target),
                           confirm: Copy.Confirm.batchMarkConfirm(count),
                           perform: { commit() })
        } else {
            commit()
        }
    }

    private func scrollToTop(_ proxy: ScrollViewProxy) {
        withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
            proxy.scrollTo(Anchor.top, anchor: .top)
        }
    }

    /// The launch leaves on the billboard's picture — or at once when there is none to wait for.
    /// The splash bounds the wait itself.
    private func markArtReady() {
        guard !artMarked else { return }
        artMarked = true
        launch?.artReady = true
        PerfProbe.mark("home-ready")
    }

    private func dismissAll() {
        pendingRouteAfterSheet = nil
        prompt = nil
        showProfile = false
    }

    private func profileDismissed() {
        if let route = pendingRouteAfterSheet {
            pendingRouteAfterSheet = nil
            onOpenRoute(route)
        }
    }
}
