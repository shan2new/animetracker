import SwiftUI

/// The recap's strings, named in one place — never inline at a call site.
private enum TodayCopy {
    static let whileYouWereAway = Copy.Recap.whileYouWereAway
    static func also(_ names: [String], label: String?) -> String { Copy.Recap.also(names, label: label) }
    static let dismissRecap = Copy.Action.dismissRecap
    static func sinceYourLastVisit(_ phrase: String) -> String { Copy.Recap.sinceYourLastVisit(phrase) }
}

#if DEBUG
/// Deterministic launch states for simulator review. Launch with
/// `-todayDemo empty|inactive|single|watched|multiple|caught`.
private enum TodayDemoState: String {
    case empty, inactive, single, watched, multiple, caught

    static var current: TodayDemoState? {
        UserDefaults.standard.string(forKey: "todayDemo").flatMap(TodayDemoState.init(rawValue:))
    }
}
#endif

private extension Franchise {
    /// The billboard's picture is the SHOW PAGE's (`billboardArt`): the proven-textless poster
    /// under a logo, else the selected poster whole. One hero grammar on both screens, so the
    /// show you tap on Today opens on the same picture under the same name (review, 23 Sep).
    var todayBillboardArt: WideArt { billboardArt }
}

// Today prioritises fresh releases, with intact poster artwork and in-card tracking controls.
// The single-release feature and release carousel share the same artwork-safe composition.
// The recap retains its separate full-bleed arrival treatment.
//
// Presentation is derived from AppModel feeds (outNow → nextUp); the view owns only timing state.
// One haptic per transaction; the committed capsule and the handoff ARE the confirmation, and the
// Undo rides the lane once the handoff settles (23 Sep) — no receipt line is drawn under the hero
// (removed 17 Sep).
struct TodayView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AuthManager.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String) -> Void
    var onSeeAllWatching: () -> Void = {}
    /// "View all N updates" — a DIFFERENT destination from the Watching shelf's "See all".
    ///
    /// Both used to switch to the Library root shelf, so a link that names a set ("all 40 updates")
    /// landed on a list that does not show it: the user then had to open All titles → Sort & filter
    /// → "Most left to watch" → "Unwatched only" by hand. This one belongs on the filtered list;
    /// "See all" stays on the unfiltered root. Defaults to `onSeeAllWatching` so the screen still
    /// behaves while `RootView` (a shared file) has not been rewired yet — see the shared-file
    /// request for `LibraryAllView(initialSort:initialUnwatchedOnly:)`.
    var onViewAllUpdates: (() -> Void)?
    /// A Profile stat tile: open the Library filtered to that status.
    var onOpenLibrary: ((WatchStatus) -> Void)?
    var onAddShow: () -> Void = {}
    /// "Recommended for you ›" — the longer list.
    var onOpenRecommendations: (() -> Void)?

    private var now: Int64 { appModel.now }

    @State private var showProfile = false
    /// The scroll offset, held OUTSIDE this view's state. Only `TodayVeils` and
    /// `StretchingHeroArt` observe it, so a frame of scrolling re-evaluates those two views and
    /// nothing else. As `@State` here it re-ran this whole body — the stack, the queue, the shelf,
    /// every row — on every frame of the first swipe (user, 2 Sep, twice).
    @State private var scroll = ScrollOffset()

    // Recap
    @State private var recap: RecapDigest?
    @State private var recapMode: RecapDigest.Presentation = .none
    @State private var recapOnStage = false        // the recap occupies the hero frame
    @State private var recapRevealed = false       // beats have finished revealing
    @State private var recapEvaluated = false
    @State private var recapClockStarted = false

    // Mark handoff
    @State private var pinned: [Franchise]?        // stack snapshot held while the hero shows its result
    @State private var committedEpisode: Int?
    /// The show whose billboard is drawing its committed frame — on a deck, not necessarily the
    /// first page.
    @State private var committedFranchiseId: String?
    /// Up next cards whose ring is drawing its check (650 ms after a tap).
    @State private var committedQueue: Set<String> = []
    /// The release deck: the page on screen, and the tallest page measured (a horizontal scroll
    /// view has no height of its own).
    @State private var deckVisibleID: String?
    /// How many episodes the committed write marked (a batch behind the chevron, or one).
    @State private var committedCount = 1

    @State private var deckHeight: CGFloat = 0
    /// The deck's one-time NUDGE: the pages slide 44 pt and settle back, once a session, so the
    /// second release shows its edge (review i3/i4, P13: page 2 was signalled only by two 7-pt
    /// dots). One transform on the pages' row; none under Reduce Motion.
    @State private var deckNudge: CGFloat = 0
    @MainActor private static var deckNudgedThisSession = false
    @State private var batchPrompt: BatchPrompt?
    /// True from the moment a mark commits until the INCOMING card has finished arriving.
    ///
    /// Without it the hero is a trap: `committedEpisode` clears at 650 ms and the next show's card
    /// fades in over 460 ms with its Mark button already live and hit-testable at partial opacity,
    /// so a user clearing three episodes has tap 2 swallowed and tap 3 land on a half-faded button
    /// belonging to a *different franchise* — the write goes to the wrong show.
    @State private var handoffInFlight = false

    /// Measured height of the copy laid on the hero art. The scrim that protects it is sized to
    /// THIS, not to a fraction of the image — see `heroTextScrim`.
    @State private var heroCopyHeight: CGFloat = 0
    /// The launch's hand-off: the ident waits for this billboard's picture (`artReady`).
    @Environment(LaunchHandoff.self) private var launch: LaunchHandoff?

    private func markArtReady() { launch?.artReady = true }
    /// The hero's art-derived ground, so a 72 %-of-screen frame never opens as a grey slab while
    /// the photograph decodes.
    @State private var heroTint: Color?
    /// The hero art's mean lightness (`PaletteCache.lightness(for:)`), for `HeroProtection`.
    @State private var heroLightness: Double?

    /// The most a Today shelf carries — the Planned shelf and the trending shelf.
    private static let shelfCap = 10

    /// Height of the floating wordmark band, measured from the bottom of the status bar. The top
    /// veil is sized to it so scrolling content dissolves *behind the wordmark*, never across it.
    fileprivate static let headerBand: CGFloat = 52
    /// Extra veil below the wordmark band. The chrome's ramp is proportional to its own height, so
    /// a veil that ends at the band ramps out in ~25 pt — and against bright hero artwork that
    /// reads as a straight black line drawn across the screen. Ramping over the band plus this
    /// makes the hand-over a dissolve, which is the entire point of the thing.
    /// Matched to `topVeil`'s own ramp so the two protections are one shape: at 46 the chrome's
    /// proportional gradient was already down to ~30 % by the bottom of the wordmark band, and a
    /// scrolling 34-pt title read through the brand mark at half strength.
    fileprivate static let veilRamp: CGFloat = 100
    /// The resting focus stage, at billboard scale (user, 31 Aug — "Apple TV, Netflix has Hero
    /// much larger"). Measured against Apple TV's Home: its hero CTA bottoms out at ~70 % of the
    /// screen and the next shelf's header sits at ~83 %, so at 0.72 our copy block lands on the
    /// same line and the queue's first row peeks above the tab bar as the scroll affordance.
    /// One fraction at every type size — at AX the copy's measured overflow grows the frame
    /// further (see `heroHeight`), so a separate AX fraction has nothing left to buy.
    private static let heroFraction: CGFloat = 0.72
    /// What the full-bleed recap frame leaves below itself.
    ///
    /// It must clear the bottom chrome's whole ramp, not just the tab bar: at 96 pt the card's
    /// `Continue` control came to rest *inside* the veil and rendered at a quarter of its ink —
    /// a live control dimmed to 2.5:1, which is the exact failure the bottom-chrome rule forbids.
    private static var recapFloor: CGFloat { ThemeMetrics.tabBarClearance + ThemeSpace.x2 }
    /// The photograph that must remain visible above the hero copy at any type size. The hero
    /// grows past `heroFraction` by the copy's overflow rather than holding a fixed fraction and
    /// letting a taller text block spill off the top of its own protection.
    private static let artBand: CGFloat = 132
    private static let accessibilityArtBand: CGFloat = 210

    private var isAX: Bool { typeSize.isAccessibilitySize }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let topInset = geo.safeAreaInsets.top
            // The WINDOW's height, as Detail sizes its billboard — never the tab content's, which
            // changes when the tab bar arrives at the end of the launch: the 0.72 hero then
            // shrank by ~41 pt under the splash's dissolve and the capsule the user came for
            // slid up into place (review, 25 Sep).
            let screenH = ThemeMetrics.windowHeight
            ZStack(alignment: .top) {
                ThemeColor.canvas.ignoresSafeArea()
                // The ambient wash — the one root spec every tab draws. On a hero day the hero
                // itself is the art; on an empty or failed day the screen still opens on the
                // atmosphere of the next known event rather than on bare canvas.
                if !showsHero {
                    ArtBackdrop(url: ambientArt, height: ThemeMetrics.rootWashHeight,
                                intensity: ThemeMetrics.rootWashIntensity)
                        .ignoresSafeArea(edges: .top)
                }

                ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        SkeletonGate(isLoading: appModel.loading && appModel.libraryEmpty) {
                            skeleton(screenH: screenH, topInset: topInset)
                        } content: {
                            VStack(alignment: .leading, spacing: 0) {
                                topBlock(screenW: geo.size.width, screenH: screenH, topInset: topInset,
                                         contentH: geo.size.height)
                                    // The billboards' bar edge, measured off the block's own
                                    // frame as the recap measures its copy: the bar hardens once
                                    // the stage has passed under it. Only the recap set it, so
                                    // on a billboard day every shelf scrolled under a soft veil
                                    // and the wordmark sat on live captions (review, 23 Sep).
                                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { maxY in
                                        guard !recapOnStage else { return }
                                        scroll.setCopyUnderBand(false)
                                        // Hard once the LOCKUP reaches the bar — the badge, the
                                        // lines and the capsule sit in the billboard's last
                                        // ~`lockupReach` points. At "the whole stage has passed"
                                        // the lockup's text slid under a soft veil and ghosted
                                        // through the wordmark band (iteration 2).
                                        scroll.setHeroUnderBand(maxY - TodayView.lockupReach
                                            < topInset + TodayView.headerBand + ThemeMetrics.barEdgeRamp)
                                    }
                                belowTheFold
                                    // Faded, not removed, while the recap holds the stage. The
                                    // layout survives (removal was the shove the handoff exists
                                    // to avoid) but the rows no longer glow through the gap
                                    // between the recap's floor and the tab bar — the takeover
                                    // read as a translucent layering glitch with "The Beginning
                                    // After the End" legible under the glass.
                                    .opacity(recapOnStage ? 0 : 1)
                            }
                            // The recap holds the whole frame; everything under it arrives with
                            // the handoff rather than popping into place after it.
                            .animation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion),
                                       value: recapOnStage)
                        }
                    }
                    // The scroll offset, read off the content's own layout frame. This is the belt
                    // to `onScrollGeometryChange`'s braces: on the iOS 27 simulator that callback
                    // never fired, so the veil stayed off, the mask stayed flat, and the hero's
                    // title parked INSIDE the wordmark at full ink ("Previously.Tensei", captured
                    // 30 Aug). A layout frame cannot fail to report a move; when both paths fire
                    // they write the same value, so nothing oscillates.
                    .background {
                        Color.clear.onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.frame(in: .global).minY
                        } action: { minY in
                            scroll.set((showsHero ? 0 : topInset) - minY)
                        }
                    }
                }
                // `.contentMargins`, not `.padding(.bottom, …)` inside the stack: padding does
                // nothing at all when the content is SHORTER than the viewport, so a short Today —
                // one hero and one row — still came to rest with its last line inside the bottom
                // ramp. A content margin is an inset on the scroll view and applies either way.
                .tabBarContentMargin()
                .laneClearance(appModel)
                .scrollIndicators(.hidden)
                .ignoresSafeArea(.container, edges: showsHero ? .top : [])
                // No mask on the scroll view. It took the content under the wordmark band to
                // zero while the hero title crossed it — and it cost a full-screen offscreen pass
                // on every frame of every scroll. The bar does that job now: `TodayVeils` mounts
                // the opaque band the moment the title is handed over, so what passes under it is
                // simply covered.
                .onScrollGeometryChange(for: CGFloat.self) { g in
                    g.contentOffset.y + g.contentInsets.top
                } action: { _, y in
                    scroll.set(y)
                }
                .previouslyRefreshable { await appModel.reload() }
                #if DEBUG
                .task(id: appModel.loading) { await debugScroll(proxy) }
                #endif
                }

                // Chrome, then the wordmark on top of it: the veil hides content, never identity.
                // Its own view, because it is the one thing here that reads the scroll offset.
                TodayVeils(scroll: scroll, topInset: topInset,
                           showsHero: showsHero, carriesBase: headerCarriesBase)

                header
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(ThemeColor.canvas.ignoresSafeArea())
        .overlay(alignment: .bottom) { ScrollEdgeChrome(side: .bottom) }
        .sheet(isPresented: $showProfile) {
            ProfileView(onOpenLibrary: { status in (onOpenLibrary ?? { _ in onSeeAllWatching() })(status) },
                        onOpenDetail: { id in onOpenDetail(id, "profile/\(id)") })
                .perfScreen("Profile")
        }
        .onChange(of: appModel.loading) { _, loading in
            if !loading { evaluateRecap() }
        }
        .onChange(of: appModel.surfaceReady) { _, ready in
            startRecapClock()
            if ready, forYouStageAllowed == nil { forYouStageAllowed = !appModel.recommendations.isEmpty }
        }
        .onAppear {
            #if DEBUG
            // `-openProfile 1` (DEBUG, like `-recapDemo`): open the Profile sheet for a capture.
            if UserDefaults.standard.bool(forKey: "openProfile") { showProfile = true }
            #endif
            evaluateRecap()
            // The empty state's poster fan is the only identity a first run has. Fetching it here
            // (not only from Search) is what lets Today's first frame carry the app's subject.
            // The chart backs BOTH the empty account and the caught-up day.
            appModel.loadTrendingIfNeeded()
        }
        .onChange(of: appModel.libraryEmpty) { _, empty in
            if empty { appModel.loadTrendingIfNeeded() }
        }
        // A pull-to-refresh is a state change with no visible focus move, so VoiceOver was told
        // nothing at all while it ran.
        .onChange(of: appModel.isRefreshing) { _, refreshing in
            if refreshing { Announce.status(Copy.Accessibility.refreshing) }
        }
        .onDisappear { clearRecapStrip() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { clearRecapStrip() }
        }
        // The screen steps back under the alert, as the show page does (review i4, N2: the glass
        // took its emphasis from the billboard behind it).
        .overlay {
            if batchPrompt != nil {
                Color.black.opacity(0.72)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: batchPrompt != nil)
        // An ALERT with Cancel, like every write confirmation (review i3/i4: the anchored dialog is
        // a glass popover on iOS 26, drawn with no Cancel over the amber capsule).
        .alert(batchPrompt?.title ?? "", isPresented: Binding(get: { batchPrompt != nil }, set: { if !$0 { batchPrompt = nil } }),
               presenting: batchPrompt) { prompt in
            Button(prompt.confirm) { prompt.perform() }
            Button(Copy.Confirm.cancel, role: .cancel) {}
        } message: { prompt in
            Text(prompt.message)
        }
    }

    #if DEBUG
    /// `-todayAnchor planned` (DEBUG, like `-calmDemo`): scroll the loaded screen to a
    /// section for a capture — the way to photograph the shelves when the simulator cannot be
    /// touched (the input MCP dies between sessions; `simctl` has no scrolling).
    private func debugScroll(_ proxy: ScrollViewProxy) async {
        guard !appModel.loading,
              let anchor = UserDefaults.standard.string(forKey: "todayAnchor"), !anchor.isEmpty
        else { return }
        try? await Task.sleep(for: .milliseconds(1500))
        guard !Task.isCancelled else { return }
        // `-todayAnchor foryouall`: open "Recommended for you ›" (the longer list) for a capture.
        if anchor == "foryouall" { onOpenRecommendations?(); return }
        proxy.scrollTo("today.\(anchor)", anchor: UnitPoint(x: 0, y: 0.16))
    }
    #endif

    /// True once the hero's title has travelled up under the wordmark band.
    ///
    /// Measured, not thresholded: `scrollY > 150` was calibrated against a tall library and never
    /// tripped on a compact one — a short Today parks at ~92 pt of scroll with the title already
    /// under the band, so the mask erased the show's name and the wordmark never took it over.
    /// The hero copy's own frame (`heroCopyUnderBand`, set where it is measured) is the fact.
    private var headerCarriesBase: Bool {
        guard showsHero, !recapOnStage, heroFranchise != nil else { return false }
        return true
    }

    // MARK: - Header

    /// Wordmark + account, floating over the hero art. It is not a band with 40 pt of dead air in
    /// it — there is nothing behind it but the show you are about to watch.
    private var header: some View {
        TodayHeaderBar(showProfile: $showProfile, scroll: scroll, overArtwork: showsHero)
    }

    // MARK: - Content states

    private var isFailed: Bool { appModel.loadError && appModel.libraryEmpty }
    private var isEmptyAccount: Bool {
        #if DEBUG
        if TodayDemoState.current == .empty { return true }
        #endif
        return !appModel.loading && appModel.libraryEmpty && !appModel.loadError
    }

    /// Shows explicitly marked Watching. A stocked library with none of these is not a quiet
    /// version of the normal feed; it is the deliberate "choose what is next" state.
    private var watchingLibrary: [Franchise] {
        appModel.library.filter { $0.effectiveStatus == .watching }
    }

    private var isInactiveLibrary: Bool {
        #if DEBUG
        if TodayDemoState.current == .inactive { return true }
        #endif
        return !appModel.libraryEmpty
            && freshItems.isEmpty
            && watchingLibrary.isEmpty
            && !plannedShows(excluding: []).isEmpty
    }

    /// The deck is at most three billboards: someone following twelve weekly shows got twelve
    /// full-screen pages behind two 6-pt dots and no overview (review, 23 Sep). The rest wait on
    /// the Up next shelf under it.
    private static let deckCap = 3
    /// How far up from a billboard's foot its lockup reaches — badge, name or lines, bar and
    /// capsule — for the bar's hardening (`topBlock`'s probe).
    fileprivate static let lockupReach: CGFloat = 250
    private var deckItems: [Franchise] { Array(freshItems.prefix(TodayView.deckCap)) }
    private var singleRelease: Franchise? { deckItems.count == 1 ? deckItems.first : nil }
    private var showsMultipleReleases: Bool { !recapOnStage && deckItems.count > 1 }

    /// Every featured state uses the same edge-to-edge stage. More releases add pages,
    /// not smaller cards; the header continues to float over the artwork.
    private var showsHero: Bool {
        guard !isEmptyAccount, !isFailed else { return false }
        return (recapOnStage && recap != nil) || !freshItems.isEmpty
            || (isInactiveLibrary ? inactiveFeature != nil : restingFeature != nil)
    }

    /// The Planned show to feature: one you can start NOW before one that has not aired, the
    /// nearest premiere among those — never the list's first row, which on the real account
    /// was a show whose every episode was already marked (review, 23 Sep).
    private var inactiveFeature: Franchise? {
        let planned = plannedShows(excluding: [])
        func startable(_ f: Franchise) -> Bool {
            f.mainStoryEpisodicParts.contains { !$0.isUpcoming && $0.availableEpisodes() > $0.progress }
        }
        // Among what you can start: one you have ALREADY started, then one on air now, then the
        // list's order — never simply the first row (iteration 2: a 170-episode finished run
        // featured over a show with new episodes this week).
        let startableOnes = planned.filter(startable)
        if let pick = startableOnes.first(where: { f in f.parts.contains { $0.progress > 0 } })
            ?? startableOnes.first(where: { $0.releasingPart != nil })
            ?? startableOnes.first {
            return pick
        }
        return planned.min { (appModel.nextPremiere(of: $0) ?? .max) < (appModel.nextPremiere(of: $1) ?? .max) }
    }

    /// Nothing new today: a show WAITING on you outranks the next airing. The calm hero said
    /// "CAUGHT UP" over Slime while Bleach sat six episodes behind, nowhere on the page (review,
    /// 23 Sep).
    private var restingFeature: Franchise? {
        // Through a mark's committed frame the stage holds the show AS IT WAS (the pinned
        // snapshot): read live, a batch that caught One Piece up swapped the billboard for a flat
        // slab of its ground 0.4 s in, then another show with no lockup (review i5, F5).
        if let id = committedFranchiseId, let held = pinned?.first(where: { $0.id == id }) { return held }
        return liveRestingFeature
    }

    private var liveRestingFeature: Franchise? {
        backlogFeature
            ?? appModel.nextUp
            ?? watchingLibrary.first { $0.isWatchedThrough }
            ?? watchingLibrary.first
            ?? appModel.library.first
    }

    /// The first Watching show, in Today's order, with something to watch now.
    private var backlogFeature: Franchise? {
        watchingInOrder.first { f in kind(of: f).map { queueIsMarkable($0.0) } ?? false }
    }

    /// Watching shows in the order Today ranks them — `AppModel.watchingShelf` (new drops, then
    /// mid-season, then the rest), then any Watching show it does not carry.
    private var watchingInOrder: [Franchise] {
        var seen = Set<String>()
        let ranked = appModel.watchingShelf.filter { $0.effectiveStatus == .watching }
        return (ranked + watchingLibrary).filter { seen.insert($0.id).inserted }
    }

    @ViewBuilder
    private func topBlock(screenW: CGFloat, screenH: CGFloat, topInset: CGFloat,
                          contentH: CGFloat) -> some View {
        if isFailed {
            stateBlock(SyncCenter.shared.isOnline ? .serverNoCache : .offlineNoData,
                       contentH: contentH) {
                Task { await appModel.reload() }
            }
        } else if recapOnStage, recap != nil {
            hero(nil, screenH: screenH, topInset: topInset)
        } else if isEmptyAccount {
            emptyLibraryBlock(screenW: screenW)
        } else if showsMultipleReleases {
            multipleReleaseBlock(screenW: screenW, screenH: screenH)
        } else if let singleRelease {
            singleReleaseBlock(singleRelease, screenW: screenW, screenH: screenH)
        } else if isInactiveLibrary {
            inactiveLibraryBlock(screenW: screenW, screenH: screenH)
        } else {
            restingBlock(screenW: screenW, screenH: screenH)
        }
    }

    // MARK: - Today's states (20 Sep, in the app's amber grammar since 23 Sep)

    /// ONE new release owns the stage — the show page's billboard (`TodayBillboard`).
    private func singleReleaseBlock(_ franchise: Franchise, screenW: CGFloat,
                                    screenH: CGFloat) -> some View {
        releaseBillboard(franchise, width: screenW, fillHeight: heroFillHeight(screenH))
            .frame(maxWidth: .infinity)
    }

    /// An empty account: three posters from the chart, one sentence, the one next step in amber —
    /// "Add a show", the words Library's and Schedule's empty states use for the same action —
    /// and the chart itself under the name Search gives it ("Trending now"). It said "Find shows"
    /// over "Popular this week", two new names for two things the app already named (review,
    /// 23 Sep).
    private func emptyLibraryBlock(screenW: CGFloat) -> some View {
        TodayEmptyLibraryState(
            fanCovers: Array(appModel.trending.compactMap(\.portraitArt).prefix(3)),
            onAddShow: onAddShow
        ) {
            // The fan IS the chart's first three; the shelf carries on from the fourth, so one
            // screen never shows the same three posters twice (review, 23 Sep).
            trendingShelf(skipping: 3)
        }
        .padding(.top, TodayView.headerBand + ThemeSpace.x5)
    }

    /// A library with nothing marked Watching: its first Planned show on the billboard, in the
    /// show page's Planned grammar, with the one step that starts it — the same "Start watching"
    /// the show page offers a Planned show.
    @ViewBuilder
    private func inactiveLibraryBlock(screenW: CGFloat, screenH: CGFloat) -> some View {
        if let feature = inactiveFeature {
            let alone = plannedShows(excluding: [feature.id]).isEmpty && forYouShelfItems.isEmpty
            TodayBillboard(franchise: feature, width: screenW,
                           fillHeight: heroFillHeight(screenH, alone: alone),
                           content: plannedLockup(feature),
                           scroll: scroll,
                           onOpen: { onOpenDetail(feature.id, "today-start/\(feature.id)") },
                           onArtLoaded: markArtReady) {
                Button {
                    appModel.setStatus(franchiseId: feature.id, status: .watching)
                } label: {
                    Text(Copy.Today.startOrContinue(feature)).frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle2())
            }
            .zoomSource("today-start/\(feature.id)")
            .franchiseQuickActions(feature, appModel: appModel)
        }
    }

    /// Several new releases: a deck of billboards, one page per show — the SAME billboard as the
    /// single release, so more releases add pages, not smaller cards.
    private func nudgeDeckOnce(pages: Int) {
        guard pages > 1, !reduceMotion, !Self.deckNudgedThisSession else { return }
        Self.deckNudgedThisSession = true
        Task { @MainActor in
            // After the launch has settled (the ident gone — `surfaceReady`) and the reader has
            // had a beat on page 1.
            while !appModel.surfaceReady { try? await Task.sleep(for: .milliseconds(200)) }
            try? await Task.sleep(for: .milliseconds(1400))
            guard deckVisibleID == deckItems.first?.id else { return }
            withAnimation(.spring(duration: 0.42, bounce: 0)) { deckNudge = -44 }
            try? await Task.sleep(for: .milliseconds(420))
            withAnimation(.spring(duration: 0.55, bounce: 0.18)) { deckNudge = 0 }
        }
    }

    private func multipleReleaseBlock(screenW: CGFloat, screenH: CGFloat) -> some View {
        let items = deckItems
        let frame = heroFillHeight(screenH)
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal) {
                // EAGER, so every page is measured before the first frame: lazily, the deck took
                // the height of the pages it had laid out, and the first swipe to a taller page
                // pushed the whole screen down under the finger. A deck is a handful of pages.
                HStack(alignment: .top, spacing: 0) {
                    ForEach(items) { f in
                        // Every page as tall as the deck: a shorter page used to end above the dots
                        // on bare canvas (140 pt of it under a whole poster beside a filled page,
                        // 23 Sep). Its ground runs on under the poster and its lockup sits at the
                        // foot, like every other page's.
                        releaseBillboard(f, width: screenW, fillHeight: frame, minHeight: deckHeight)
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { h in
                                if h > deckHeight + 0.5 { deckHeight = h }
                            }
                            .id(f.id)
                    }
                }
                .scrollTargetLayout()
                .offset(x: deckNudge)
            }
            // A horizontal scroll view has no intrinsic height: without this boundary the shelf
            // under the deck compressed its layout while the full-size artwork drew over it. The
            // TALLEST PAGE once measured — never a floor of the filled frame: a whole poster is
            // shorter than 72 % of the screen, and the floor left a band of bare canvas between
            // every poster and the dots (review, 23 Sep).
            .frame(height: deckHeight > 0 ? deckHeight : frame)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $deckVisibleID, anchor: .center)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .onAppear {
                if deckVisibleID == nil { deckVisibleID = items.first?.id }
                nudgeDeckOnce(pages: items.count)
                #if DEBUG
                // `-deckPage N` (DEBUG, like `-todayAnchor`): open the deck on its Nth page (0-based).
                let page = UserDefaults.standard.integer(forKey: "deckPage")
                if page > 0, items.indices.contains(page) { deckVisibleID = items[page].id }
                #endif
            }
            .onChange(of: items.map(\.id)) { _, ids in
                if deckVisibleID == nil || !ids.contains(deckVisibleID ?? "") { deckVisibleID = ids.first }
                deckHeight = 0
            }
            .onChange(of: typeSize) { _, _ in deckHeight = 0 }

            let current = items.firstIndex { $0.id == (deckVisibleID ?? items.first?.id) } ?? 0
            HStack(spacing: 8) {
                ForEach(items) { f in
                    Circle()
                        .fill(f.id == items[current].id ? ThemeColor.textPrimary : ThemeColor.textTertiary)
                        .frame(width: 7, height: 7)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 20)
            .padding(.top, ThemeSpace.x2)
            // The dots belong to the billboard: they leave under the bar with its lockup instead
            // of hanging alone under the wordmark at the foot of the page (review i3).
            .fadesUnderBar(ThemeMetrics.topSafeInset + TodayView.headerBand, lead: 160)
            // A page control VoiceOver can read and move (review, 23 Sep: the dots were hidden
            // from it, so the second release was unreachable without sight).
            .accessibilityElement()
            .accessibilityLabel(Copy.Today.releasePosition(current + 1, items.count))
            .accessibilityValue(items[current].displayTitle)
            .accessibilityAdjustableAction { direction in
                let next = direction == .increment ? current + 1 : current - 1
                guard items.indices.contains(next) else { return }
                withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) {
                    deckVisibleID = items[next].id
                }
            }
        }
    }

    /// Nothing new today: the show airing next (else the one you are closest to) on the billboard
    /// in the show page's calm grammar — nothing to mark — over the whole viewport when no shelf
    /// follows. A show with a backlog is not calm: it keeps its count and its mark capsule.
    @ViewBuilder
    private func restingBlock(screenW: CGFloat, screenH: CGFloat) -> some View {
        if let rec = forYouFeature, let stub = rec.stub {
            forYouBillboard(rec, stub: stub, screenW: screenW, screenH: screenH)
        } else if let feature = restingFeature {
            let alone = plannedShows(excluding: [feature.id]).isEmpty && forYouShelfItems.isEmpty
            // Anything with an episode to watch wears the markable billboard — a fresh drop as
            // much as a backlog: the calm lockup said "CAUGHT UP" over Re:ZERO three behind
            // (review, 23 Sep).
            if kind(of: feature).map({ queueIsMarkable($0.0) }) ?? false {
                releaseBillboard(feature, width: screenW, fillHeight: heroFillHeight(screenH, alone: alone))
            } else {
                TodayBillboard(franchise: feature, width: screenW,
                               fillHeight: heroFillHeight(screenH, alone: alone),
                               content: calmLockup(feature),
                               scroll: scroll,
                               onOpen: { onOpenDetail(feature.id, "today-resting/\(feature.id)") },
                               onArtLoaded: markArtReady) { EmptyView() }
                    .zoomSource("today-resting/\(feature.id)")
                    .franchiseQuickActions(feature, appModel: appModel)
            }
        }
    }

    /// The billboard frame for FILLED art: the show page's fraction, or the whole viewport when
    /// nothing follows the hero. A poster drawn whole takes its own height (`TodayBillboard`).
    private func heroFillHeight(_ screenH: CGFloat, alone: Bool = false) -> CGFloat {
        alone ? screenH - ThemeMetrics.tabBarClearance : screenH * TodayView.heroFraction
    }

    /// Unstarted shows only: an active, paused, finished or dropped show already has an expressed
    /// relationship and does not belong on the Planned shelf beside the thing you are watching.
    /// Your Planned list in the order you can ACT on it: what you can watch tonight first (a show
    /// you started before one you have not), then premieres by date, then what waits on an
    /// undated return. Library order led with 3 Body Problem — every released episode watched,
    /// Season 2 "late 2026" — as the first thing to start (review i3/i4, P3-N5).
    private func plannedShows(excluding ids: Set<String>) -> [Franchise] {
        // A title just added from For you is still on that shelf, ticked, until the next list —
        // not twice on one screen (review i5, N4).
        let fromShelf = appModel.addedRecommendationIds
        let ranked = appModel.library.enumerated()
            .filter { $0.element.effectiveStatus == .planned && !ids.contains($0.element.id)
                      && !fromShelf.contains($0.element.id) }
            .map { index, f -> (f: Franchise, tier: Int, key: Int64) in
                if let p = f.currentPart, !p.isUpcoming, p.markTarget(now: now) > p.progress {
                    let started = f.parts.contains { $0.progress > 0 }
                    return (f, started ? 0 : 1, Int64(index))
                }
                if let at = appModel.nextPremiere(of: f) { return (f, 2, at) }
                return (f, 3, Int64(index))
            }
            .sorted { a, b in a.tier != b.tier ? a.tier < b.tier : a.key < b.key }
        return Array(ranked.map(\.f).prefix(TodayView.shelfCap))
    }

    /// What the hero(es) above the shelf are showing — the Planned shelf never repeats them.
    private var heroIds: Set<String> {
        if showsMultipleReleases || singleRelease != nil { return Set(deckItems.map(\.id)) }
        if forYouFeature != nil { return [] }
        if isInactiveLibrary, let feature = inactiveFeature { return [feature.id] }
        if let feature = restingFeature { return [feature.id] }
        return []
    }

    /// The artwork the wash is lit by when there is no hero: the next thing to air, else the first
    /// Watching show, else the library's first.
    private var ambientArt: String? {
        appModel.nextUp?.portraitArt ?? watchingLibrary.first?.portraitArt ?? appModel.library.first?.portraitArt
    }

    // MARK: - What a billboard says

    /// A release — or a backlog — on the billboard: the show page's lockup, with its mark capsule.
    private func releaseBillboard(_ f: Franchise, width: CGFloat, fillHeight: CGFloat,
                                  minHeight: CGFloat = 0) -> some View {
        let r = releaseLockup(f)
        return TodayBillboard(franchise: f, width: width, fillHeight: fillHeight, minHeight: minHeight,
                              content: r?.content ?? calmLockup(f),
                              interactive: !handoffInFlight || r?.committed == true,
                              scroll: scroll,
                              onOpen: { onOpenDetail(f.id, "focus/\(f.id)") },
                              onArtLoaded: markArtReady) {
            if let r, let cta = r.cta {
                MarkSplitButton(episode: cta,
                                committed: r.committed,
                                behind: r.behind,
                                title: f.title,
                                committedCount: r.committed ? committedCount : 1,
                                // The part the LOCKUP names: a mark aimed elsewhere (the airing
                                // part at its ceiling) returned nil and the capsule did nothing
                                // (review i5, F1).
                                onMark: { mark(f, mediaId: r.part.mediaId) },
                                onMarkThrough: { n in promptBatch(f, part: r.part, through: n) },
                                // `markTarget(now:)`, never `progressCeiling` — see `promptBatch`.
                                onMarkAll: { promptBatch(f, part: r.part, through: r.part.markTarget(now: now)) })
            }
        }
        .zoomSource("focus/\(f.id)")
        .franchiseQuickActions(f, appModel: appModel)
    }

    /// The markable billboard's lockup — the show page's grammar: the STATE on the badge ("NEW
    /// EPISODE" only for a drop that struck today; else the count), the moment and the episode as
    /// the one line (the moment only when the drop IS the next episode — review i1), where you
    /// are as the bar, and the drop named on a support line when a backlog stands between you and
    /// it. The 20 Sep cards paired the next episode with the latest drop's time ("Episode 16 ·
    /// Aired 16 min ago", while Episode 18 was the one that aired) and badged a five-day-old drop
    /// NEW (review, 23 Sep).
    private func releaseLockup(_ f: Franchise)
        -> (content: TodayLockupContent, part: FranchisePart, cta: Int?, behind: Int, committed: Bool)? {
        guard let (kind, part) = kind(of: f) else { return nil }
        let nextEpisode = part.progress + 1
        let behind: Int = {
            if case .fresh(let b) = kind { return b }
            if case .backlog(let l) = kind { return l }
            return 0
        }()
        let committed = committedEpisode != nil && committedFranchiseId == f.id
        // The whole block advances in the SAME frame as the capsule's label, so for the length of
        // the confirmation the card never says the episode is both next and already watched.
        let copy: (eyebrow: String, fact: String, support: String?) = committed
            ? advanced(kind, f: f, part: part, from: committedEpisode ?? nextEpisode, behind: behind, marked: committedCount)
            : (eyebrow(kind, f: f, part: part), freshCount(kind, fact: factLine(kind, f: f, part: part)), nil)
        // Watched over what there is to watch: aired-by-now for a fresh drop, the available run
        // for a backlog. It advances with the mark, never after it.
        let bar: (ratio: Double, spoken: String)? = {
            let done = committed ? (committedEpisode ?? part.progress) : part.progress
            let total: Int
            let spoken: String
            switch kind {
            case .fresh:
                total = part.airedByNow(now: now, anchor: f.timeAnchor)
                spoken = Copy.Progress.behind(max(0, total - done))
            case .backlog:
                total = part.availableEpisodes()
                spoken = Copy.Progress.left(max(0, total - done))
            default: return nil
            }
            guard total > 0, done > 0, done < total else { return nil }
            return (Double(done) / Double(total), spoken)
        }()
        let fresh: Bool = { if case .fresh = kind { return true }; return false }()
        // ONE line under the name (24 Sep, owner: "the text in the Hero is too verbose"): the
        // badge is the state — NEW EPISODE already says the drop is new — and the line is the
        // episode the capsule marks. No recency prefix on a release, no second line of drops and
        // cadences under it; the bar is where you are, wordless.
        let content = TodayLockupContent(badge: copy.eyebrow,
                                         attention: fresh && !committed,
                                         moment: committed || fresh ? nil : momentText(kind, f: f, part: part),
                                         fact: copy.fact,
                                         support: nil,
                                         progress: bar?.ratio,
                                         progressSpoken: bar?.spoken)
        let cta: Int? = committed ? committedEpisode : (behind > 0 ? nextEpisode : nil)
        return (content, part, cta, behind, committed)
    }

    /// The calm billboard: waiting on the next airing, else caught up — the show page's words,
    /// nothing to mark.
    private func calmLockup(_ f: Franchise) -> TodayLockupContent {
        guard let (kind, part) = calmKind(of: f) else {
            return TodayLockupContent(badge: Copy.Progress.caughtUp, fact: "")
        }
        // The one line: the next airing leading the episode; a finished season's return date
        // (the support line's old job) becomes the line when there is no airing to lead it.
        let moment = momentText(kind, f: f, part: part)
        let fact = factLine(kind, f: f, part: part)
        let returns = moment == nil ? supportLine(kind, f: f, part: part) : nil
        return TodayLockupContent(badge: eyebrow(kind, f: f, part: part),
                                  moment: moment,
                                  fact: returns.map { "\(fact) \u{00B7} \($0)" } ?? fact)
    }

    /// A Planned show: the show page's Planned block ("PLANNED", the episode it would start on,
    /// its next airing when it has one).
    private func plannedLockup(_ f: Franchise) -> TodayLockupContent {
        let part = f.currentPart ?? f.resumePart ?? f.episodicPartsInOrder.first
        let fact = part.map { f.watchContext(part: $0, episode: $0.progress + 1) } ?? ""
        // The airing NAMES its episode (the show page's line): a bare "Sunday at 4:30 PM" under
        // "Season 5 · Episode 9" read as episode 9 airing Sunday (review i3). Not
        // `nextEpisodeLine`, which a Planned show's calendar gate would silence.
        let next: String? = f.nextAiring(now: now).map { at in
            let airing = f.releasingPart
            let episode = airing?.airings.first(where: { $0.at == at })?.episode ?? airing?.nextEpisodeNumber
            return Copy.Progress.episodeAirs(episode, when: TemporalCopy.airs(at: at, now: now, source: f.source))
        }
        _ = next
        // One line: where it starts (the capsule's "Start watching" acts on it).
        return TodayLockupContent(badge: Copy.Status(.planned), fact: fact)
    }

    // MARK: - Up next (the shelf)

    /// One card on the Up next shelf: a show, the episode the card is about, and the focus
    /// grammar's own kind — so the card knows whether it can be marked.
    private struct UpNextItem: Identifiable {
        let franchise: Franchise
        let kind: FocusKind
        let part: FranchisePart
        var id: String { franchise.id }
        var airsAt: Int64? { if case .waiting(let at) = kind { return at } else { return nil } }
    }

    /// The Watching shows the billboard is not showing: every one with something to watch now,
    /// whatever the age of its last episode, then this week's airings, soonest first.
    private var upNextItems: [UpNextItem] {
        let shown = heroIds
        let pool = watchingInOrder.filter { !shown.contains($0.id) }
        let markable: [UpNextItem] = pool.compactMap { f in
            guard let (k, part) = kind(of: f), queueIsMarkable(k) else { return nil }
            return UpNextItem(franchise: f, kind: k, part: part)
        }
        let taken = Set(markable.map(\.id))
        let week = now + 7 * Formatting.D
        let coming: [UpNextItem] = pool.compactMap { f in
            guard !taken.contains(f.id), let part = f.releasingPart,
                  let at = f.nextAiring(now: now), at <= week else { return nil }
            return UpNextItem(franchise: f, kind: .waiting(at: at), part: part)
        }
        .sorted { ($0.airsAt ?? 0) < ($1.airsAt ?? 0) }
        return Array((markable + coming).prefix(TodayView.shelfCap))
    }

    private func queueIsMarkable(_ kind: FocusKind) -> Bool {
        switch kind {
        case .fresh, .backlog: return true
        case .caughtUp, .waiting: return false
        }
    }

    /// Everything waiting for you, as television: one shelf of 16:9 cards under the billboard —
    /// what you can watch now (each with its mark ring), then what is coming. Apple TV's Up Next
    /// row, in the Library's Continue-card geometry: four fifths of the content width, the next
    /// card peeking. Headed "Next up" while a card can be marked and "Upcoming" when nothing has
    /// aired, so "Next up" only ever heads something you can watch right now.
    @ViewBuilder
    private func upNextShelf(_ cards: [UpNextItem]) -> some View {
        let markable = cards.contains { queueIsMarkable($0.kind) }
        VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
            SectionHeaderRow(markable ? Copy.Label.nextUp : Copy.Label.upcoming) {
                onSeeAllWatching()
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: ThemeMetrics.shelfGap) {
                    ForEach(cards) { item in
                        upNextCard(item)
                            // A peek is an affordance for a NEXT card; a shelf of one, or a
                            // grown type size, runs gutter to gutter.
                            .containerRelativeFrame(.horizontal, count: 5,
                                                    span: cards.count == 1 || isAX ? 5 : 4,
                                                    spacing: ThemeMetrics.shelfGap)
                            .franchiseQuickActions(item.franchise, appModel: appModel)
                            .transition(handoff)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, ThemeMetrics.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .fixedSize(horizontal: false, vertical: true)
            .animation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion),
                       value: cards.map(\.id))
        }
    }

    /// One card: the show's wide art with the episode on it and where you are as the bar, the
    /// show named beneath with ONE caption, and the mark ring beside that while there is
    /// something to mark. The card opens the show; the ring is its own control.
    ///
    /// Not Library's "Next up" scene card, on purpose (review i3 asked for one anatomy): this
    /// shelf is where episodes are MARKED — the ring and its in-place receipt need a caption row
    /// of their own. On the scene card they shared a ~120-pt column over the art with the logo
    /// beside them, and the receipt truncated to "Episo… · Undo" (photographed 24 Sep). Library's
    /// shelf is for browsing and keeps the scene card.
    @ViewBuilder
    private func upNextCard(_ item: UpNextItem) -> some View {
        let f = item.franchise, part = item.part
        let wide = part.wideArt(within: f)
        let caption = upNextCaption(item)
        let episode = upNextEpisode(item).map(Copy.episode)
        let zoom = "upnext/\(f.id)"
        VStack(alignment: .leading, spacing: ThemeSpace.x2) {
            Button { onOpenDetail(f.id, zoom) } label: {
                ProgressBanner(url: wide.url, portraitSource: wide.portraitSource,
                               progress: upNextProgress(item),
                               episode: episode, ultraWide: wide.ultraWide,
                               zoomID: zoom)
                    // RIGID 16:9 at the card's width: left flexible, the art gave way to a longer
                    // caption beside it and the second card's art was 20 pt shorter and narrower
                    // than the first's (review i4, N8).
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(OverArtPressStyle())
            .accessibilityHint(Copy.Accessibility.opensTheShowHint)
            HStack(alignment: .center, spacing: ThemeSpace.x3) {
                Button { onOpenDetail(f.id, zoom) } label: {
                    VStack(alignment: .leading, spacing: ThemeSpace.x0_5) {
                        Text(f.displayTitle)
                            .type(ThemeType.rowTitle)
                            .foregroundStyle(ThemeColor.textPrimary)
                            .lineLimit(1...2)
                            .minimumScaleFactor(0.85)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        // The ring's receipt takes the caption's own line while it is live —
                        // under the card it was a layout child that dropped the Planned shelf
                        // 32 pt for six seconds (review i2).
                        if ReceiptLine.isLive(appModel, host: ReceiptHost.todayQueue(f.id)) {
                            ReceiptLine(host: ReceiptHost.todayQueue(f.id), compact: true, inline: true)
                        } else if let caption {
                            // The rows' two-colour grammar: a forward-looking TIME is amber, an
                            // identity or a count is grey.
                            Text(caption.text)
                                .type(caption.lead ? ThemeType.rowMetaLead : ThemeType.rowMeta)
                                .foregroundStyle(caption.lead ? ThemeColor.accent : ThemeColor.textSecondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .accessibilityHint(Copy.Accessibility.opensTheShowHint)
                if queueIsMarkable(item.kind) {
                    MarkRing(marked: committedQueue.contains(f.id),
                             style: .quiet,
                             // A film has no episode numeral to put in the ring.
                             episode: part.kind == .movie ? nil : part.progress + 1,
                             label: "\(Copy.Action.markAsWatched), \(watchLabel(f, part: part, episode: part.progress + 1)) of \(f.title)") {
                        markQueueRow(f)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel([f.title, episode, caption?.text].compactMap { $0 }.joined(separator: ", "))
    }

    /// One transaction, one haptic (fired inside the write), one receipt — in place, under the
    /// card's caption: the card stays where it is, so the receipt can live on it.
    private func markQueueRow(_ f: Franchise) {
        guard !committedQueue.contains(f.id) else { return }
        guard let undo = appModel.markNext(franchiseId: f.id) else { return }
        withAnimation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion)) {
            _ = committedQueue.insert(f.id)
        }
        appModel.presentUndo(undo.placed(at: ReceiptHost.todayQueue(f.id)))
        Announce.status(Copy.Progress.episodeWatched(undo.episode))
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            committedQueue.remove(f.id)
        }
    }

    /// The episode the card is about: the next unwatched one, or the one coming.
    private func upNextEpisode(_ item: UpNextItem) -> Int? {
        let part = item.part
        switch item.kind {
        case .waiting: return part.nextEpisodeNumber ?? part.airedEpisodes + 1
        case .fresh, .backlog: return part.kind == .movie ? nil : part.progress + 1
        case .caughtUp: return nil
        }
    }

    /// Where you are in the season, on the art — watched over aired-by-now for a fresh drop, over
    /// the available run for a backlog; nothing for a show with nothing started or nothing left.
    private func upNextProgress(_ item: UpNextItem) -> Double? {
        let part = item.part
        let total: Int
        switch item.kind {
        case .fresh: total = part.airedByNow(now: now, anchor: item.franchise.timeAnchor)
        case .backlog: total = part.availableEpisodes()
        case .waiting, .caughtUp: return nil
        }
        guard total > 0, part.progress > 0, part.progress < total else { return nil }
        return Double(part.progress) / Double(total)
    }

    /// The card's one caption, in the rows' two-colour grammar — the episode itself is the pill on
    /// the art. A forward-looking TIME in amber: the airing ("Sunday at 8:30 PM") or today's drop
    /// ("Aired 2h ago"). Else the count in grey — "behind" while the season airs, "left" once it
    /// has finished — else the season on a multi-part show.
    private func upNextCaption(_ item: UpNextItem) -> (text: String, lead: Bool)? {
        let f = item.franchise, part = item.part
        // The SHORT season name ("The Calamity"), the season pill's — the raw arc label printed
        // "Thousand-Year Blood War -…" under the card (review i3).
        let season: String? = {
            let label = Copy.compactPartLabel(part.canonicalLabel)
            return f.parts.count == 1 || label.isEmpty ? nil : label
        }()
        switch item.kind {
        case .waiting(let at):
            return (TemporalCopy.airs(at: at, now: now, source: f.source), true)
        case .fresh(let behind):
            // The drop's recency while the deck would call it fresh — amber on its own day.
            if let last = part.lastAired(now: now, anchor: f.timeAnchor), now - last <= AppModel.outNowWindow,
               behind <= 1 || Formatting.dayDiff(ts: last, now: now, anchor: f.timeAnchor) == 0 {
                return (TemporalCopy.aired(at: last, now: now, source: f.source),
                        Formatting.dayDiff(ts: last, now: now, anchor: f.timeAnchor) == 0)
            }
            if behind > 1 { return (Copy.Progress.behind(behind), false) }
            return season.map { ($0, false) }
        case .backlog(let left):
            // A film is its own caption — the show page's NEXT UP names it the same way.
            if part.kind == .movie { return (part.canonicalLabel, false) }
            if left > 1 || part.isReleasing {
                // The STORY's count once the run is over — the hero's and the show page's
                // (`seriesLeft`), not this season's (iteration 2: 8 here, 16 there).
                return (part.isReleasing ? Copy.Progress.behind(left)
                                         : Copy.Progress.left(max(left, f.seriesLeft(now: now))), false)
            }
            return season.map { ($0, false) }
        case .caughtUp:
            return (Copy.Progress.caughtUp, false)
        }
    }

    /// The rest of what you planned to watch — a wall of POSTERS, the cinematic grammar under a
    /// billboard (Library's two-up landscape cards here read as a settings list under a film
    /// poster, and lost Today its poster wall — user, 23 Sep), with the Library's own facts for
    /// the same shows: where you stopped ("Season 5 · Episode 9 next"), else the premiere with
    /// its verb ("Premieres 9 Oct", amber inside the horizon), else what it is.
    @ViewBuilder
    private func plannedShelf(_ items: [Franchise]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
                SectionHeaderRow(Copy.Status(.planned)) { onOpenLibrary?(.planned) }
                    .padding(.horizontal, ThemeMetrics.gutter)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: ThemeMetrics.shelfGap) {
                        ForEach(items) { f in
                            let caption = plannedCaption(f)
                            // The 20 Sep poster tile, with the one fact that matters for a Planned
                            // show — where you stopped, or when it premieres — in its lower band.
                            // Every card carries its band, captioned or not, with two lines
                            // reserved: one caption position and one card height per row.
                            ArtworkPoster(url: f.tilePoster.url, name: f.tilePoster.name, title: f.displayTitle,
                                          detailInset: ThemeSpace.x2,
                                          detailsInBand: true,
                                          fixedAspect: 2.0 / 3.0,
                                          onOpen: { onOpenDetail(f.id, "today-planned/\(f.id)") }) {
                                if PosterCaption.style == .band {
                                    (caption?.text ?? Text(""))
                                        .type(ThemeType.caption)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2, reservesSpace: true)
                                        .minimumScaleFactor(0.85)
                                        .fixedSize(horizontal: false, vertical: true)
                                } else {
                                    // The name, then the one fact on one line: "Season 5 · Episode
                                    // 9 next", "Season 3 · Premieres 20 Nov" (the date amber).
                                    PosterCaptionText(title: f.displayTitle, fact: caption?.fact,
                                                      lead: caption?.lead ?? false, factHead: caption?.season)
                                }
                            }
                            .frame(width: PosterSize.todayShelf.size.width)
                            .zoomSource("today-planned/\(f.id)")
                            .accessibilityLabel([f.displayTitle, caption?.spoken].compactMap { $0 }.joined(separator: ", "))
                            .accessibilityHint(Copy.Accessibility.opensTheShowHint)
                            .franchiseQuickActions(f, appModel: appModel)
                        }
                    }
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .padding(.vertical, ThemeSpace.x1)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .id("today.planned")
        }
    }

    /// A poster's one caption, at a poster's width (100 pt): where you stopped ("Episode 9
    /// next"), else the premiere ("Premieres 9 Oct" — amber inside the horizon, "Premieres late
    /// 2026" beyond it; the installment's name is the show page's, it cut the caption), else
    /// what the show is.
    private func plannedCaption(_ f: Franchise) -> PlannedCaption? {
        // Where you stopped, the season NAMED on a show of several (review i3: "Episode 1 next"
        // under Rick and Morty, eight seasons in, read as never started).
        if let p = f.currentPart, !p.isUpcoming, f.parts.contains(where: { $0.progress > 0 }),
           p.markTarget(now: now) > p.progress {
            if p.kind == .movie { return PlannedCaption(season: nil, fact: p.canonicalLabel, lead: false) }
            let season = f.seasonPartsInOrder.count > 1 ? Copy.compactPartLabel(p.canonicalLabel) : ""
            return PlannedCaption(season: season.isEmpty ? nil : season,
                                  fact: Copy.Progress.episodeNext(p.progress + 1), lead: false)
        }
        // Not started, with episodes out: where it STARTS — or, on air, that it is and when the
        // next one lands. Percy (Seasons 1–2 out) pointed at Season 3's 20 Nov while its page said
        // "Start watching", and an unstarted airing show fell back to "Anime · 2021" (review i5,
        // N13).
        if !f.parts.contains(where: { $0.progress > 0 }), let p = f.currentPart, !p.isUpcoming,
           p.markTarget(now: now) > 0 {
            if p.isReleasing, let at = f.nextAiring(now: now) {
                return PlannedCaption(season: Copy.ForYou.airing,
                                      fact: TemporalCopy.airsCompact(at: at, now: now, source: f.source), lead: true)
            }
            if p.kind == .movie { return PlannedCaption(season: nil, fact: p.canonicalLabel, lead: false) }
            let season = f.seasonPartsInOrder.count > 1 ? Copy.compactPartLabel(p.canonicalLabel) : ""
            return PlannedCaption(season: season.isEmpty ? nil : season, fact: Copy.episode(1), lead: false)
        }
        // The installment over its date, the verb by progress (`ReturnFact.premiereParts`):
        // "Season 3" over "Premieres 20 Nov" — the season name used to be stripped, and Percy
        // Jackson, two seasons out, read as a series that had never aired.
        // Two deliberate lines in a band ~84 pt wide — the installment (else the verb) over the
        // DATE: "Season 3" / "20 Nov", "Premieres" / "9 Oct". Left to wrap, the date split
        // inside itself: "Premieres 9" / "Oct", "Premieres late" / "2026" (review i3).
        if let parts = ReturnFact.premiereParts(of: f, appModel: appModel) {
            let sentence = parts.fact.sentence.isEmpty ? parts.fact.text : parts.fact.sentence
            // The fact arrives bound with no-break spaces (`ReturnFact`'s one-line rule) — split
            // on either kind of space; the date keeps its own binding.
            let words = sentence.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\u{00A0}" })
                .map(String.init)
            let verb = words.first ?? sentence
            let date = words.count > 1 ? words[1].prefix(1).uppercased() + words[1].dropFirst() : ""
            // With an installment the verb STAYS on the date line — "Season 2" / "Returns late
            // 2026" — a bare "Late 2026" under "Season 2" said nothing about which way the date
            // points (review i5, N13); without one, the verb heads the date.
            if date.isEmpty || parts.installment != nil {
                return PlannedCaption(season: parts.installment, fact: sentence, lead: parts.fact.soon)
            }
            return PlannedCaption(season: verb, fact: date, lead: parts.fact.soon)
        }
        // The dot stays on the first line when the caption wraps (AX-XL printed "Anime / · 2019",
        // review i5, F24).
        let identity = [f.kindWord, f.year.map(String.init)].compactMap { $0 }.joined(separator: "\u{00A0}\u{00B7} ")
        return identity.isEmpty ? nil : PlannedCaption(season: nil, fact: identity, lead: false)
    }

    /// A Planned poster's caption: the installment (white) over the fact (amber when it is a
    /// date inside the horizon) — one text, two lines, two inks.
    private struct PlannedCaption {
        let season: String?
        let fact: String
        let lead: Bool
        var spoken: String { [season, fact].compactMap { $0 }.joined(separator: ", ") }
        var text: Text {
            let factText = Text(fact).foregroundStyle(lead ? ThemeColor.accent : ThemeColor.textPrimary)
            guard let season else { return factText }
            return Text(season + "\n").foregroundStyle(ThemeColor.textPrimary) + factText
        }
    }

    // MARK: - The trending shelf

    /// The rest of the chart, in the app's one shelf anatomy. The header walks to Search, where
    /// the whole chart is the browse grid.
    @ViewBuilder
    private func trendingShelf(skipping: Int = 1) -> some View {
        let items = Array(appModel.trending.dropFirst(skipping).prefix(9))
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
                SectionHeaderRow(Copy.Search.trendingNow, action: onAddShow)
                    .padding(.horizontal, ThemeMetrics.gutter)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: ThemeMetrics.shelfGap) {
                        ForEach(items) { item in
                            // The 20 Sep poster tile: the show's own key art whole, on a soft wash
                            // of itself, naming itself — no caption under it.
                            // One tap builds the first-run Today (the spike's two-tap setup): the
                            // add Search makes, question and all — an airing show opens its page
                            // with "where are you?" raised; a finished one lands on Planned.
                            ArtworkPoster(url: item.tilePoster.url, name: item.tilePoster.name, title: item.title,
                                          showsDetails: false,
                                          cornerMark: appModel.isInLibrary(item.id)
                                            ? AnyView(OwnedMark().padding(ThemeSpace.x2).allowsHitTesting(false))
                                            : AnyView(TileAddDisc(label: "\(Copy.Action.add), \(item.title)") { addTrending(item) }),
                                          onOpen: { onOpenDetail(item.id, "trending/\(item.id)") }) { EmptyView() }
                            .frame(width: PosterSize.todayShelf.size.width)
                            .zoomSource("trending/\(item.id)")
                            .accessibilityLabel(item.title)
                            .accessibilityHint(Copy.Accessibility.opensTheShowHint)
                        }
                    }
                    .padding(.leading, ThemeMetrics.gutter)
                    .padding(.vertical, ThemeSpace.x1)
                    // Every tile carries a mark (+ or the check): one corner for the shelf.
                    .environment(\.cornerRow, CornerRow(urls: items.compactMap(\.tilePoster.url)))
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .padding(.top, ThemeSpace.x5)
        }
    }

    private func addTrending(_ item: FranchiseSummary) {
        if item.isReleasing {
            appModel.pendingAddPrompt = item.id
            onOpenDetail(item.id, "trending/\(item.id)")
            return
        }
        appModel.addToLibrary(franchiseId: item.id, title: item.title, isReleasing: item.isReleasing)
    }

    /// A state that IS the whole screen — nothing follows it, because both cases that reach here
    /// have an empty library. So it is centred in the space it owns rather than parked under the
    /// wordmark with 600 pt of canvas beneath it, which is what "top-pinned empty state" looks
    /// like.
    ///
    /// Centred against the tab bar's VISUAL height, not against `tabBarClearance`. The clearance is
    /// a scroll inset — it has to clear the whole ramp as well as the bar — and subtracting 152 when
    /// *centring* put the card at 41 % of the screen: ~81 pt high, which reads as top-pinned, which
    /// is the exact defect the centring was added to fix. Half of whatever is subtracted is the
    /// error, so it has to be the bar and nothing else.
    private func stateBlock(_ copy: EmptyStateCopy, contentH: CGFloat,
                            action: (() -> Void)? = nil) -> some View {
        EmptyState(copy, primary: action)
            .padding(.horizontal, ThemeMetrics.gutter)
            // `minHeight` inside `centredState`, never `height`: `EmptyState` drops its own minimum
            // at AX and grows with the copy, so a fixed frame let the title + two-line body + 48-pt
            // button draw outside the scrollable region at AX3–AX5 with no way to reach it.
            .centredState(contentH: contentH - TodayView.headerBand)
            .padding(.top, TodayView.headerBand)
            // The identity a first run has no artwork for: three real posters from whatever the
            // account can see (trending, on a genuinely empty account) fanned behind the words at
            // a whisper, so the first frame a reviewer sees says "shows". ONLY behind the empty
            // account — behind "Couldn't load your library" the same fan read as the very shows
            // the message says it cannot show (captured 2 Sep).
            .background(alignment: .center) { if copy == .emptyToday { emptyFan } }
    }

    /// Three fanned posters behind an empty/failed state, at 0.35.
    ///
    /// Never a fourth accent object: the plate already spends its one accent on the button. This is
    /// atmosphere, and it draws nothing at all when there is nothing honest to draw.
    @ViewBuilder
    private var emptyFan: some View {
        let covers = Array(appModel.trending.prefix(3).compactMap(\.portraitArt))
        if covers.count == 3 {
            HStack(spacing: -PosterSize.shelfMedium.size.width * 0.42) {
                ForEach(Array(covers.enumerated()), id: \.offset) { i, url in
                    PosterSlot(url: url, .shelfMedium)
                        .rotationEffect(.degrees(Double(i - 1) * 9))
                        .offset(y: abs(Double(i - 1)) * 10)
                        .zIndex(i == 1 ? 1 : 0)
                }
            }
            .opacity(0.35)
            .blur(radius: 1.5)
            // Three posters under a blur are rasterised once, not filtered per frame.
            .drawingGroup()
            .offset(y: -60)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: - The stack

    /// Fresh unwatched releases, most actionable first. Older backlog deliberately does not enter
    /// Today: it belongs to the Library, and turning Today into a catch-up dashboard was the
    /// rejected direction.
    ///
    /// Within the fresh set, shows the user is WATCHING outrank the rest. `outNow` orders purely
    /// by recency, which handed the hero — the most prominent slot on the urgency surface — to a
    /// show the user had marked *completed* (Mushoku Tensei, 30 Aug) while five in-progress shows
    /// compressed into thumbnails below it. A shelved show keeps its place in the feed; it just
    /// doesn't headline over something the user actually said they are watching.
    private var liveItems: [Franchise] {
        // A PAUSED show is off the deck (review i3): paused is "not now", and a billboard with
        // "Mark as watched" is the loudest "now" the app has.
        let fresh = appModel.outNow.filter { $0.effectiveStatus != .paused }.sorted {
            let a = $0.effectiveStatus == .watching, b = $1.effectiveStatus == .watching
            if a != b { return a }
            // The airings-advanced recency, never `lastAiredSortKey`: that field is the
            // catalogue's and lags a sync, which put a days-old Slime drop over the Re:ZERO
            // episode that had struck 27 minutes earlier (user, 2 Sep).
            return ($0.lastAired(now: now) ?? 0) > ($1.lastAired(now: now) ?? 0)
        }
        #if DEBUG
        switch TodayDemoState.current {
        case .empty, .inactive, .caught: return []
        case .single, .watched:
            if let title = UserDefaults.standard.string(forKey: "todayDemoTitle"),
               let item = fresh.first(where: { $0.displayTitle.localizedCaseInsensitiveContains(title) }) {
                return [item]
            }
            return Array(fresh.prefix(1))
        case .multiple: return Array(fresh.prefix(3))
        case nil: break
        }
        if UserDefaults.standard.bool(forKey: "calmDemo") { return [] }
        #endif
        return fresh
    }
    private var items: [Franchise] { pinned ?? liveItems }
    /// Only items the Focus grammar can actually describe reach the stack.
    private var actionable: [Franchise] { items.filter { kind(of: $0) != nil } }
    private var freshItems: [Franchise] { actionable.filter(isFresh) }
    private var heroFranchise: Franchise? { singleRelease }
    /// True when the show has an episode OUT NOW and unwatched.
    private func isFresh(_ f: Franchise) -> Bool {
        if case .fresh = kind(of: f)?.0 { return true }
        return false
    }
    // MARK: - Hero

    private func heroHeight(_ screenH: CGFloat) -> CGFloat {
        // The arrival owns the whole screen. Nothing follows the recap while it is held — at the
        // resting focus height the card floated in the middle of the frame with canvas
        // under it, which reads as a notification banner rather than as a moment. Edge to edge,
        // down to the tab bar, the same art then simply *shrinks* into the Focus hero on handoff:
        // one object resizing, which is what `uiSettle` is for.
        if recapOnStage { return screenH - TodayView.recapFloor }
        // The frame grows by the copy's OVERFLOW, not by a guessed accessibility bump. The copy's
        // height depends only on the width, never on this, so there is no layout cycle — and at
        // AX5 the block gets exactly the room it needs instead of 0.56 × screen and a clipped
        // title. `artBand` is the minimum photograph that must survive above the copy.
        let artBand = isAX ? TodayView.accessibilityArtBand : TodayView.artBand
        let base = screenH * TodayView.heroFraction
        return max(base, heroCopyHeight + artBand)
    }

    /// The art the hero is made of: `Franchise.billboardArt` — the server-selected PORTRAIT,
    /// composited whole through `ArtHeader(portraitSource:)`, and the landscape only when the
    /// catalogue has no poster. This frame is ~0.64 w/h, within 4 % of a 2:3 poster; a 16:9
    /// backdrop filled into it shows its middle ~36 % (landscape-first ran for a few hours on
    /// 4 Sep and every production billboard was a zoomed slice). The recap's own cover stands in
    /// while a recap holds the frame with no franchise behind it.
    private func heroArt(_ f: Franchise?) -> String? {
        f?.todayBillboardArt.url ?? recap?.beats.first?.cover
    }

    /// Whether the resolved hero art is a 2:3 COVER rather than a landscape asset — `billboardArt`'s
    /// own answer, so the composite path can never disagree with the URL it is given.
    private func heroArtIsPortrait(_ f: Franchise?) -> Bool {
        f?.todayBillboardArt.portraitSource ?? true
    }

    @ViewBuilder
    private func hero(_ f: Franchise?, screenH: CGFloat, topInset: CGFloat) -> some View {
        // The fraction is of the WHOLE screen, status bar included: the art bleeds up into it, so
        // adding the inset again would silently undo the compact resting geometry.
        let h = heroHeight(screenH)
        let art = heroArt(f)
        // Keyed on the PHOTOGRAPH, not on the franchise id: the image only has a reason to
        // dissolve when the image itself changes. Two shows that share a hero asset hand over
        // without the picture flickering.
        let key = art ?? f?.id ?? recap?.digestID ?? "hero"
        ZStack(alignment: .bottom) {
            // The PERSISTENT ground, outside the `.id`/`.transition` above it.
            //
            // The handoff finishes the removal before it starts the insertion — which is right, and
            // which means that for ~80 ms there is a gap with nothing in it. With nothing behind the
            // transitioning `ArtHeader` a 46 %-of-screen frame rendered bare #09090B in the middle of
            // the app's signature moment. The ground survives both cards, so the two images trade
            // places over one continuous surface instead of through a hole.
            (heroTint ?? PaletteCache.fallback)
                .frame(height: h)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            // Pull-down grows the art instead of opening a black gap above it (the stretch is
            // read by `StretchingHeroArt`, which is why the stretch never re-runs this body). Both
            // protections are drawn in POINTS — `HeroTopVeil` over the chrome band and
            // `HeroCopyScrim` sized to the measured copy — so no fractional scrim blankets the
            // middle of a 72 %-of-screen photograph. The recap keeps its own bottom scrim,
            // because its copy fills the frame and the whole image is meant to step back.
            StretchingHeroArt(scroll: scroll, url: art, height: h, tint: heroTint,
                              scrimBottom: recapOnStage ? 1.9 : 0,
                              portrait: heroArtIsPortrait(f),
                              ultraWide: f?.todayBillboardArt.ultraWide ?? false,
                                  onArtLoaded: markArtReady,
                                  // The recap (no franchise) is a poster too, often with its
                                  // title printed across the top: it starts under the header,
                                  // not under the clock (review, 23 Sep).
                                  topInset: (f == nil || f?.billboardName == .type ? topInset + TodayView.headerBand : 0),
                                  groundDim: HeroProtection.groundDim(heroStrength))
                .frame(height: h, alignment: .bottom)
                .id(key)
                .transition(handoff)

            // The copy's own protection, sized to the copy. Stops that are fractions of the image
            // simply do not know how tall the text is, which is why AX1 put "Reincarnated as a /
            // Slime" in white on pale sky at ~1.6:1.
            heroTextScrim

            Group {
                if recapOnStage, let recap {
                    RecapArrival(digest: recap, revealed: recapRevealed, now: now,
                                 reduceMotion: reduceMotion,
                                 heroArt: art,
                                 beatLabel: recapBeatLabel,
                                 beatTitle: { appModel.franchise(id: $0.franchiseId)?.displayTitle ?? $0.title.shelfShortened },
                                 onOpenBeat: { beat in
                                     handoffRecap()
                                     onOpenDetail(beat.franchiseId, "recap/\(beat.franchiseId)")
                                 },
                                 onContinue: { handoffRecap() },
                                 onDismiss: { dismissRecap() })
                        .transition(handoff)
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .padding(.bottom, isAX ? ThemeSpace.x5 : ThemeSpace.x4)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heroCopyHeight = $0 }
            // The identity handover's trigger, measured rather than guessed: the moment the copy's
            // top edge crosses into the wordmark band (where the mask is taking it to zero), the
            // header starts carrying the title. 8 pt of hysteresis-free lead is fine — the two
            // cross-fade on `uiGentle` either way.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                // While the copy is PASSING under the band — not for the rest of the scroll:
                // the bar named a show the reader was no longer looking at (review, 5 Sep).
                let band = topInset + TodayView.headerBand
                // ...and gives it back once the lockup has meaningfully cleared the band.
                let under = frame.minY < band + 8 && frame.maxY > band + 12
                scroll.setCopyUnderBand(under)
                let gone = frame.maxY < band + ThemeMetrics.barEdgeRamp
                scroll.setHeroUnderBand(gone)
            }
        }
        .frame(height: h)
        .frame(maxWidth: .infinity)
        // Clipped at the BOTTOM only.
        //
        // A removing view keeps the frame it had when it left the layout, so during the recap →
        // focus shrink the outgoing recap card (last laid out at ~880 pt) hung in the space the
        // hero had just vacated and drew over UPCOMING and the first shelf row — measured on the
        // recording at frames 133–136, "2 episodes aired" and "Mushoku Tensei" superimposed for
        // ~130 ms. `.clipped()` cannot be used: the pull-stretched art has to keep drawing ABOVE
        // this frame. A mask that extends upward and stops at the bottom edge cuts one side only.
        .mask(alignment: .bottom) {
            // 44 pt below the frame as well: the in-place receipt hangs under the capsule,
            // past the hero's own bottom edge, and must not be cut by the recap's clip.
            Rectangle().padding(.top, -2000).padding(.bottom, -44).allowsHitTesting(false)
        }
        // BEFORE the negative top padding: that padding shifts the layout frame down by the safe
        // inset, and an overlay attached after it would start the veil below the status bar —
        // leaving the clock on bare art with a hard seam under it.
        .overlay(alignment: .top) { topVeil(topInset: topInset) }
        // No `.clipped()` here: `ArtHeader` clips itself, and the stretched art has to be allowed
        // to draw above this frame into the pull. The scroll view is the real clip.
        .padding(.top, -topInset)
        // The home screen's largest tap target was the one route into Detail that did NOT zoom:
        // `"focus/…"` was pushed as a zoom id with no source registered anywhere, so the app's
        // signature navigation fell back to a slide from exactly the object it should grow out of.
        .zoomSource(f.map { "focus/\($0.id)" } ?? "focus/recap")
        // The largest target on the home screen carried no quick actions while every row under
        // it did.
        .franchiseQuickActions(f, appModel: appModel)
        .animation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion), value: recapOnStage)
        .animation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion), value: key)
        .task(id: art) {
            let resolved = await PaletteCache.shared.resolve(url: art, maxPixel: 360)
            heroTint = resolved
            heroLightness = PaletteCache.shared.lightness(for: art)
            TodayView.rememberTint(resolved)
        }
    }

    /// The handoff. Finish the removal, THEN start the insertion.
    ///
    /// The design system now owns this curve (`AnyTransition.handoff`) because four surfaces
    /// replace a card and three of them were crossfading symmetrically — two show titles drawn at
    /// 50 % on top of each other. Today had the asymmetric version and nobody else did; keeping a
    /// private copy here is what let them drift.
    private var handoff: AnyTransition { .handoff(reduceMotion: reduceMotion) }

    /// Protection over the status bar and the wordmark band — the shared `HeroTopVeil`, with the
    /// wordmark's own band as its edge. Detail's floating toolbar uses the same gradient.
    private func topVeil(topInset: CGFloat) -> some View {
        HeroTopVeil(band: topInset + TodayView.headerBand, ramp: TodayView.veilRamp, strength: heroStrength)
    }

    /// Protection BEHIND the copy, tracking its measured height at every type size (the shared
    /// `HeroCopyScrim` — Detail's billboard draws the same one).
    private var heroTextScrim: some View {
        HeroCopyScrim(copyHeight: heroCopyHeight, strength: heroStrength)
    }

    /// How hard the hero's veil, scrim and ground dim are drawn, from the art's lightness.
    private var heroStrength: Double { HeroProtection.strength(lightness: heroLightness) }

    // MARK: - Remembered hero tint

    /// The last hero's palette colour, kept across launches.
    ///
    /// The loading frame is the first thing a returning user sees, and it has no artwork yet by
    /// definition — so it was a black rectangle. The tint of whatever was on the hero last time is
    /// a near-certain match for whatever is coming (the hero rarely changes between two opens), and
    /// even when it is wrong it is the app's own atmosphere rather than an empty canvas.
    private static let tintKey = "today.heroTint"

    private static func rememberTint(_ color: Color?) {
        guard let color, let c = UIColor(color).cgColor.components, c.count >= 3 else { return }
        UserDefaults.standard.set([Double(c[0]), Double(c[1]), Double(c[2])], forKey: tintKey)
    }

    static var rememberedTint: Color? {
        guard let c = UserDefaults.standard.array(forKey: tintKey) as? [Double], c.count >= 3 else { return nil }
        return Color(.sRGB, red: c[0], green: c[1], blue: c[2])
    }

    /// The calm hero's grammar: waiting on its next airing when it has one, else simply caught
    /// up. Always this, never `kind(of:)` — the calm hero exists because the stack is empty, so
    /// there is nothing to mark on it; and under `-calmDemo 1` the stack is emptied by force on
    /// a library that is behind, where `kind(of:)` would hand the calm hero a CTA.
    private func calmKind(of f: Franchise) -> (FocusKind, FranchisePart)? {
        if let part = f.releasingPart, let at = f.nextAiring(now: now) { return (.waiting(at: at), part) }
        guard let part = f.resumePart ?? f.releasingPart ?? f.episodicPartsInOrder.last ?? f.parts.first else { return nil }
        return (.caughtUp, part)
    }

    // MARK: - Below the fold

    /// Everything under the hero.
    ///
    /// It is NOT hidden while the recap is on stage. The recap is the hero's contents, not a
    /// takeover: hiding the rest left ~110 pt of bare canvas above the tab bar with the queue, the
    /// upcoming row and the whole Watching shelf simply gone, and then re-inserted them on a second
    /// curve when the recap handed off — the layout shove the handoff is supposed to avoid. The
    /// sections sit below the recap exactly as they sit below the focus card, and the handoff is
    /// then one object resizing above content that never moved.
    @ViewBuilder
    private var belowTheFold: some View {
        let strip = !recapOnStage && recapMode == .strip && recap != nil
        let notice = appModel.loadError && !appModel.libraryEmpty
        let first = showsHero
            ? (isAX ? ThemeMetrics.heroClearance : ThemeSpace.x4)
            : ThemeMetrics.sectionGap
        let rail = plannedShows(excluding: heroIds)
        VStack(alignment: .leading, spacing: 0) {
            if strip, let recap {
                // Tucked against the hero it summarises (x3, not the section gap): the line is
                // the hero's residue, and at full section distance it floated in the dead zone
                // between hero and queue reading as a stray debug print.
                RecapLine(text: recapStripText(recap)) { stageRecap() }
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .padding(.top, showsHero ? ThemeSpace.x2 : first)
                    .transition(.opacity)
            }
            if notice {
                InlineNotice(Copy.Notice.today) { Task { await appModel.reload() } }
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .padding(.top, strip ? ThemeMetrics.cardGap : first)
            }
            // Everything else you can watch now, then what airs this week — the shows Today
            // used to drop the day their last episode turned eight days old (review, 23 Sep:
            // Bleach, six behind, appeared nowhere on it). The Planned shelf follows it.
            let upNext = upNextItems
            if !recapOnStage, !isEmptyAccount, !isFailed, !upNext.isEmpty {
                upNextShelf(upNext)
                    .padding(.top, strip || notice ? ThemeMetrics.sectionGap : first)
                    .id("today.upnext")
            }
            // DISCOVERY, after everything of yours you can act on and above your own list: the
            // spike's rule — a recommendation never sits over a new episode or a backlog, and never
            // where nobody scrolls. Planned is yours and does not change; this rotates daily.
            // A Planned-only library is CHOOSING what to start: its own shortlist comes first,
            // right under "Start watching", and the strangers after it (review i5, U-N14 — the
            // shelf pushed Planned ~370 pt down, below the fold).
            let forYou = forYouShelfItems
            let showsForYou = !recapOnStage && !isEmptyAccount && !isFailed && (!forYou.isEmpty || forYouLoading)
            let showsPlanned = !recapOnStage && !isEmptyAccount && !isFailed && !rail.isEmpty
            let plannedFirst = isInactiveLibrary && showsPlanned
            if plannedFirst {
                plannedShelf(rail)
                    .padding(.top, upNext.isEmpty && !strip && !notice ? first : ThemeMetrics.sectionGap)
            }
            if showsForYou {
                forYouShelf(forYou)
                    .padding(.top, upNext.isEmpty && !strip && !notice && !plannedFirst ? first : ThemeMetrics.sectionGap)
                    .id("today.foryou")
            }
            if showsPlanned, !plannedFirst {
                plannedShelf(rail)
                    .padding(.top, ThemeMetrics.sectionGap)
            }
        }
        .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: recapMode)
    }

    // MARK: - Recommended for you

    /// When NOTHING of yours needs the stage — no fresh drop, no backlog to mark, a library that is
    /// not Planned-only — the top recommendation takes the billboard: the moment discovery has the
    /// most to give (the spike, 24 Sep: the calm state was a full-screen "CAUGHT UP · Returns
    /// Sunday" dead end). Only a title that already has a show page, so the tap opens at once;
    /// rotating daily among the first three. An added one stays on stage, now "In Planned", until
    /// the next list leaves it out.
    private var forYouFeature: RecommendationItem? {
        guard !isEmptyAccount, !isFailed, !recapOnStage, !isInactiveLibrary, freshItems.isEmpty,
              forYouStageAllowed != false || Self.forYouDemo else { return nil }
        if let f = restingFeature {
            if kind(of: f).map({ queueIsMarkable($0.0) }) ?? false { return nil }
            // YOUR show airing within a day keeps the stage: "Tomorrow at 7:30 PM · Episode 24"
            // is why Today exists, and a stranger's poster in its place put it in a small
            // Upcoming card (review i5, N2). (`-forYouStage 1`, DEBUG: photograph the stage anyway.)
            if !Self.forYouStageDemo, let next = f.nextAiring(now: now), next - now <= 30 * Formatting.H { return nil }
            // ...and so does a show marked this session — the mark that caught you up is not
            // followed, 650 ms later, by a recommendation taking its place.
            if appModel.markedThisSession.contains(f.id) { return nil }
        }
        // The session's pick holds the stage — through an add (it turns into its Planned lockup,
        // "Start watching") and through refetches: advancing to another title a second after the
        // user chose this one yanked it away mid-thought (review i5, F6).
        if let staged = appModel.sessionStage, !appModel.hiddenRecommendationKeys.contains(staged.key) {
            return staged
        }
        // Nothing hidden and nothing yours — a cached list must not feature a show added since.
        let ready = appModel.visibleRecommendations.filter {
            $0.franchiseId != nil && ($0.hasBillboardArt || Self.forYouStageDemo) && !appModel.isOwned($0)
        }
        let pick = appModel.stagedRecommendation(from: ready)
        appModel.sessionStage = pick
        return pick
    }

    /// Whether a recommendation may take the stage this session: decided the first time Today
    /// surfaces — yes if a list is already in hand (the offline copy), no if it is not, so a list
    /// arriving 1.5 s after launch fills the SHELF and never swaps the billboard under the reader
    /// (review i5, N7). The next launch has the copy.
    @State private var forYouStageAllowed: Bool?

    /// `-forYouDemo 1` builds its list after launch, so it is exempt from the first-paint rule.
    private static var forYouDemo: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "forYouDemo")
        #else
        false
        #endif
    }

    private static var forYouStageDemo: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "forYouStage")
        #else
        false
        #endif
    }

    /// The shelf: every visible recommendation the billboard is not showing, up to twelve.
    private var forYouShelfItems: [RecommendationItem] {
        let onStage = forYouFeature?.key
        return Array(appModel.visibleRecommendations.filter { $0.key != onStage }.prefix(12))
    }

    /// The first list is on its way: the shelf holds its place as a skeleton rather than arriving
    /// under the reader's thumb.
    private var forYouLoading: Bool {
        appModel.recommendationsState == .idle && appModel.recommendations.isEmpty && !appModel.libraryEmpty
            // Offline, or against a server that has said 404 today, no list is coming: a
            // skeleton would never resolve (review i5, N14/U-N4).
            && SyncCenter.shared.isOnline && !appModel.loadError && !appModel.recommendationsRecentlyUnavailable
    }

    private func openRecommendation(_ r: RecommendationItem) {
        Task {
            if let id = await appModel.franchiseId(for: r) { onOpenDetail(id, "foryou/\(r.key)") }
        }
    }

    /// The recommendation on the billboard: the show page's hero grammar, with the reason as its
    /// one line ("Because you finished Game of Thrones") and one step, "Add to Planned".
    private func forYouBillboard(_ r: RecommendationItem, stub: Franchise, screenW: CGFloat,
                                 screenH: CGFloat) -> some View {
        let owned = appModel.isOwned(r)
        return TodayBillboard(franchise: stub, width: screenW,
                              fillHeight: heroFillHeight(screenH, alone: forYouShelfItems.isEmpty
                                                          && plannedShows(excluding: []).isEmpty && upNextItems.isEmpty),
                              // Why (the line), and what it IS (the support line — the show
                              // page's identity grammar, "Anime · 2020 · Action · Supernatural"):
                              // the two things a stranger's poster cannot say. On air now leads.
                              // Once added, the SAME stage says so on its badge ("IN PLANNED")
                              // and offers the next step — never a disabled capsule, never a
                              // swap to another title (review i5, P5-N4/F6).
                              // One line — why (24 Sep: the identity line under it was one line
                              // too many; the show page carries what it is).
                              content: TodayLockupContent(badge: owned ? Copy.ForYou.addedToPlanned : Copy.ForYou.badge,
                                                          fact: Copy.ForYou.reason(reason(of: r))),
                              scroll: scroll,
                              onOpen: { openRecommendation(r) },
                              onArtLoaded: markArtReady) {
            if owned, let id = appModel.showId(of: r) {
                // "Start watching" — the Planned billboard's step: it files the show under
                // Watching, and Today's own billboard takes it from there.
                Button {
                    appModel.setStatus(franchiseId: id, status: .watching)
                } label: {
                    Text(Copy.ForYou.startWatching).frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle2())
            } else {
                Button {
                    appModel.addRecommendation(r)
                } label: {
                    Label(Copy.ForYou.addToPlanned, systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle2())
                .disabled(appModel.resolvingRecommendations.contains(r.key))
                .accessibilityHint(Copy.ForYou.addHint)
            }
        }
        .zoomSource("foryou/\(r.key)")
        .contextMenu { ForYouMenu(item: r, reason: reason(of: r), onOpen: { openRecommendation(r) }) }
    }

    /// The reason as Today should SAY it: the user's own short names for their shows ("Re:ZERO",
    /// not the catalogue's "Re:ZERO -Starting Life in Another World-"), and — where several of
    /// their shows agree — the one that fits the moment named first: a show being watched on a
    /// new-episode day, a finished one when there is nothing to watch (the spike's rule). The
    /// server's order breaks ties; a single-seed reason keeps its own verb and seed.
    private func reason(of r: RecommendationItem) -> RecommendationItem.Reason {
        let spoken = appModel.spokenReason(r)
        let seeds = spoken.seeds
        guard seeds.count > 1 else { return spoken }
        let preferred: WatchStatus = freshItems.isEmpty ? .completed : .watching
        let ordered = seeds.enumerated().sorted { a, b in
            let ra = appModel.franchise(id: a.element.franchiseId)?.effectiveStatus == preferred ? 0 : 1
            let rb = appModel.franchise(id: b.element.franchiseId)?.effectiveStatus == preferred ? 0 : 1
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
        return .init(kind: r.reason.kind, seeds: ordered, count: r.reason.count)
    }

    /// What the title IS and what it ASKS: "Anime · 2011 · 148 episodes · Adventure" — after "why",
    /// the size of the commitment is the next question a stranger's show raises (review i5, N14).
    private func forYouIdentity(_ r: RecommendationItem, stub: Franchise) -> String {
        let size = (r.episodes ?? 0) > 1 ? Copy.episodes(r.episodes ?? 0) : nil
        let genres = r.genres.prefix(size == nil ? 2 : 1)
            .map { $0.localizedCapitalized.replacingOccurrences(of: " ", with: "\u{00A0}") }
        return ([stub.kindWord] + [r.year.map(String.init), size].compactMap { $0 } + genres)
            .joined(separator: " \u{00B7} ")
    }

    /// Recommended for you — a wall of the shows' own posters (the 20 Sep shelf grammar), each
    /// saying which of YOUR shows it comes from; + adds it to Planned; the long press says why in
    /// full and carries "Not interested" and "Already seen".
    private func forYouShelf(_ items: [RecommendationItem]) -> some View {
        let reasons = shelfReasons(items)
        return ForYouShelf(items: items, loading: forYouLoading, reason: { reasons[$0.key] ?? reason(of: $0) },
                           onOpen: { openRecommendation($0) },
                           onSeeAll: onOpenRecommendations)
    }

    /// The shelf's reasons read as a SET: where a title has several of the user's shows behind
    /// it, the tile names one its neighbours have not already named (after the moment's
    /// preference) — two neighbours both said "Like TSUKIMICHI" (review i5, N8). The billboard's
    /// seed counts as named.
    private func shelfReasons(_ items: [RecommendationItem]) -> [String: RecommendationItem.Reason] {
        var named = Set<String>()
        if let staged = forYouFeature, let first = reason(of: staged).seeds.first { named.insert(first.franchiseId) }
        var out: [String: RecommendationItem.Reason] = [:]
        for r in items {
            let base = reason(of: r)
            var seeds = base.seeds
            if seeds.count > 1, named.contains(seeds[0].franchiseId),
               let fresh = seeds.firstIndex(where: { !named.contains($0.franchiseId) }) {
                seeds.insert(seeds.remove(at: fresh), at: 0)
            }
            if let first = seeds.first { named.insert(first.franchiseId) }
            out[r.key] = .init(kind: base.kind, seeds: seeds, count: base.count)
        }
        return out
    }

    // MARK: - Focus grammar

    private enum FocusKind { case fresh(behind: Int), backlog(left: Int), caughtUp, waiting(at: Int64) }

    private func kind(of f: Franchise) -> (FocusKind, FranchisePart)? {
        // Evaluated on the object (not the live feed) so a pinned snapshot keeps its wording while
        // the hero shows its result.
        // The airing part, or a season released whole this week (`freshPart`, review i4).
        if let part = f.freshPart(now: now, window: AppModel.outNowWindow), f.hasReached(part) {
            // Airings-derived (`behind` / `lastAired`), never the catalogue's hourly counts: the
            // episode that struck a minute ago is the whole reason this screen exists.
            let behind = part.unwatchedOut(now: now, anchor: f.timeAnchor)
            if now - (part.lastAired(now: now, anchor: f.timeAnchor) ?? 0) <= AppModel.outNowWindow,
               behind > 0 || appModel.justCaught.contains(f.id),
               part.isNews(now: now, anchor: f.timeAnchor, window: AppModel.outNowWindow) {
                return behind > 0 ? (.fresh(behind: behind), part) : (.caughtUp, part)
            }
        }
        if let part = f.resumePart { return (.backlog(left: f.continueBacklog), part) }
        if let part = f.releasingPart, let at = f.nextAiring(now: now) { return (.waiting(at: at), part) }
        return nil
    }

    /// The eyebrow is always a FACT about the episode below it — never an instruction.
    ///
    /// "CONTINUE" was an imperative sitting directly above an amber button that already gives the
    /// instruction, and it alternated with "AIRED YESTERDAY" (a fact) with no inferable rule. The
    /// dot is reserved for genuinely just-aired episodes and nothing else.
    /// A release with a backlog behind it keeps its count on the one line, compactly.
    private func freshCount(_ kind: FocusKind, fact: String) -> String {
        guard case .fresh(let behind) = kind, behind > 1 else { return fact }
        return "\(fact) \u{00B7} \(Copy.Progress.behindShort(behind))"
    }

    private func eyebrow(_ kind: FocusKind, f: Franchise, part: FranchisePart) -> String {
        switch kind {
        case .fresh(let behind):
            // A season released whole is NEW SEASON — never "8 EPISODES BEHIND" about a run that
            // came out this week (review i4, the streaming drop).
            if !part.isReleasing { return Copy.Label.newSeason }
            // The recency of today's drop is the MOMENT row's ("Aired 29 min ago" — the news
            // the person opened the app for, user 2 Sep); the eyebrow says the STATE: the count
            // while there is one, else that this is new. An older drop with a backlog leads
            // with the count; an older single one with its day.
            // A release IS the news, whatever the backlog behind it: NEW EPISODE, in the news red,
            // on every page of the deck (24 Sep, owner: "New Episode is not standing out"). The
            // count rides the one line ("Season 4 · Episode 16 · 3 behind").
            _ = behind
            return Copy.Label.newEpisode
        case .backlog(let left):
            // "Behind" while the season is still airing, "left" once its run is over — the show
            // page's words for the same show (review, 23 Sep).
            if part.isReleasing { return Copy.Progress.behind(left) }
            // A FILM is next, not "the last episode of the season" (review i5, F17 — Demon
            // Slayer's Infinity Castle); the show page says "NEXT UP" for the same state.
            if part.kind == .movie { return Copy.Label.nextUp }
            // The whole story left, the show page's count (`seriesLeft`), not the season's.
            let all = max(left, f.seriesLeft(now: now))
            return all > 1 ? Copy.Progress.left(all) : Copy.Progress.lastEpisodeOfTheSeason
        case .caughtUp: return Copy.Progress.caughtUp
        // The state only — "NEW EPISODE". The moment ("Today at 7:30 PM · in 1h 24m") is the
        // `HeroMoment` row under the title, with its own instrument; said here as well it was
        // either a capsule over a 34-pt amber clock (2 Sep) or a small-caps sentence that
        // treated the app's one delight "like just another thing" (both 4 Sep, user).
        case .waiting:
            // A badge states a fact that is TRUE NOW, and an episode that has not aired is not
            // new yet: "CAUGHT UP" over "Today at 7:30 PM · Season 4 · Episode 21" — the show
            // page's block for the same show, word for word. "NEW EPISODE" hours before the
            // drop made the two rooms disagree about one show (review, 23 Sep; review i2 had
            // already caught it over a Wednesday, on a Saturday). The moment carries the delight.
            return Copy.Progress.caughtUp
        }
    }

    /// The WHEN, leading the hero's one line: a future airing in the app's one temporal ladder
    /// ("Today at 7:30 PM", "Airs in 27 min", "Friday at 7:30 PM", date-only "Friday"), today's
    /// drop ("Aired 29 min ago"), and a caught-up show's next airing. Nothing for a backlog or an
    /// older drop — those are states, and the badge says them.
    private func momentText(_ kind: FocusKind, f: Franchise, part: FranchisePart) -> String? {
        switch kind {
        case .waiting(let at):
            return TemporalCopy.airs(at: at, now: now, source: f.source)
        case .fresh(let behind):
            // Only when the drop IS the next episode: "Aired yesterday · Season 4 · Episode 19"
            // under "3 EPISODES BEHIND" bound episode 21's drop to episode 19 (review, 5 Sep).
            // With a backlog the drop names its own episode on the support line.
            guard behind == 1, let last = part.lastAired(now: now, anchor: f.timeAnchor) else { return nil }
            return TemporalCopy.aired(at: last, now: now, source: f.source)
        case .caughtUp:
            guard let at = part.nextAiringAt, at > now else { return nil }
            return TemporalCopy.airs(at: at, now: now, source: f.source)
        case .backlog:
            return nil
        }
    }

    /// The fact under the title: the episode, except for a caught-up show whose season is done,
    /// where "Season 5 · Episode 25" would name an episode that does not exist — it gets the
    /// season, and the support line carries the return date.
    private func factLine(_ kind: FocusKind, f: Franchise, part: FranchisePart) -> String {
        if case .caughtUp = kind, part.isComplete || part.progress >= max(part.totalEpisodes, 1) && !part.isReleasing {
            return part.canonicalLabel.isEmpty ? part.title : part.canonicalLabel
        }
        if case .waiting = kind {
            // The episode alone: the countdown is the moment row's (it used to ride along here,
            // "in 3h 12m · Season 4 · Episode 15").
            return f.watchContext(part: part, episode: part.nextEpisodeNumber ?? part.airedEpisodes + 1)
        }
        return f.watchContext(part: part, episode: part.progress + 1)
    }

    /// Fewer words (user, 2 Sep): the hero says the state (eyebrow), the episode (fact) and — only
    /// when it is not already said — one more thing. "Latest aired 28 Aug" under "9 EPISODES
    /// BEHIND" and "11 of 24 watched" under "13 EPISODES LEFT" were second sentences about the
    /// same fact.
    /// "Episode 24 airs Friday at 7:30 PM" — the show page's `newEpisodeLine`, for the same show.
    private func nextEpisodeLine(_ f: Franchise) -> String? {
        guard f.tracksAirings, let at = f.nextAiring(now: now) else { return nil }
        let part = f.releasingPart
        let episode = part?.airings.first(where: { $0.at == at })?.episode ?? part?.nextEpisodeNumber
        return Copy.Progress.episodeAirs(episode, when: TemporalCopy.airs(at: at, now: now, source: f.source))
    }

    private func supportLine(_ kind: FocusKind, f: Franchise, part: FranchisePart) -> String? {
        switch kind {
        case .fresh(let behind):
            // A season released whole: how much of it is out ("All 8 episodes out").
            if !part.isReleasing { return Copy.Progress.allOut(part.airedEpisodes) }
            // The drop, named: with a backlog the moment cannot lead the line (it would read as
            // the next episode's), so it says which episode it is about — the same builder the
            // committed frame uses for "Episode 20 airs Friday".
            // For as long as the deck holds the drop (`outNowWindow`), not only on its calendar
            // day: at 00:09 the deck still led with a five-hour-old episode and had stopped
            // naming it (review i3).
            if behind > 1, let last = part.lastAired(now: now, anchor: f.timeAnchor),
               now - last <= AppModel.outNowWindow {
                return Copy.Progress.dropAired(episode: part.airedByNow(now: now, anchor: f.timeAnchor),
                                               when: TemporalCopy.aired(at: last, now: now, source: f.source))
            }
            // Else the cadence — the show page's line for the same show, verbatim ("Episode 24
            // airs Friday at 7:30 PM"); Today said nothing where the page said this (review, 23 Sep).
            return nextEpisodeLine(f)
        case .backlog, .waiting:
            // The eyebrow carries the count and the moment row the recency; the bar under the
            // fact carries where you are. Nothing is left for a third line to say.
            return nil
        case .caughtUp:
            // A dated next airing is the moment row's; only the curated return survives here.
            if let at = part.nextAiringAt, at > now { return nil }
            if let premiere = appModel.nextPremiere(of: f) {
                return TemporalCopy.returns(at: premiere, now: now, source: f.source)
            }
            return nil
        }
    }

    /// The card's copy the instant a mark commits: the same grammar, one episode further on. The
    /// hero must never read "Episode 2 · 6 episodes left" beside a button saying episode 2 is
    /// watched.
    private func advanced(_ kind: FocusKind, f: Franchise, part: FranchisePart, from episode: Int,
                          behind: Int, marked: Int = 1) -> (eyebrow: String, fact: String, support: String?) {
        // What is left after THIS write — a batch of five that cleared a backlog of five is
        // caught up, not "4 EPISODES BEHIND · Episode 14" (review i5, F4).
        let left = max(0, behind - marked)
        guard left > 0 else {
            // The button already says "Episode 19 watched"; the footnote says what comes next
            // instead of saying it twice.
            //
            // And it NAMES the episode it belongs to. A bare "Friday at 7:30 PM" printed directly
            // under "Season 4 · Episode 19" is the identical grammar this screen uses for a future
            // airing, so the line read as "Episode 19 airs Friday" — about an episode the user has
            // just told the app they already watched. The clock is a fact about episode 20.
            let next = part.nextAiringAt.flatMap { at -> String? in
                guard at > now else { return nil }
                let when = TemporalCopy.airs(at: at, now: now, source: f.source)
                return "\(Copy.episode(episode + 1)) airs \(TodayView.midSentence(when))"
            }
            return (Copy.Progress.caughtUp,
                    f.watchContext(part: part, episode: episode),
                    next)
        }
        let count: String = {
            if case .backlog = kind { return Copy.Progress.left(left) }
            return Copy.Progress.behind(left)
        }()
        return (count,
                f.watchContext(part: part, episode: episode + 1),
                left == 1 ? Copy.Progress.caughtUpAfterThisEpisode : nil)
    }

    /// A `TemporalCopy` phrase set INSIDE a sentence rather than at the head of one.
    ///
    /// Only the words that are ordinary adverbs are re-cased. "friday", "aug 28" and "sun" are
    /// proper nouns and a sentence does not get to lower-case them — the same rule `sinceFragment`
    /// below already applies to month abbreviations, written once here so the two cannot drift.
    private static func midSentence(_ phrase: String) -> String {
        let head = phrase.prefix(while: { !$0.isWhitespace })
        guard ["Today", "Tomorrow", "Yesterday"].contains(String(head)) else { return phrase }
        return head.lowercased() + phrase.dropFirst(head.count)
    }

    /// The shared watch-context rule (`Franchise.watchContext`): "Season 7 · Episode 5" on a
    /// multi-part franchise, "Episode 5" on a single one. This screen used to own the rule
    /// privately while Library, Schedule and Detail each spelled it differently.
    private func watchLabel(_ f: Franchise, part: FranchisePart, episode n: Int) -> String {
        f.watchContext(part: part, episode: n)
    }

    // MARK: - Skeleton

    /// The shape the hero will fill, not a generic card.
    ///
    /// What it looked like before: ~110 pt of empty canvas, four small bars floating in the middle
    /// of the frame, and a hard full-width tonal seam where the plate stopped — at normal screen
    /// brightness, a frame that reads as "the app failed to load", on the first thing a returning
    /// user sees. The loaded state opens with full-bleed art at y = 0, so the skeleton does too:
    /// the hero band is an OPAQUE ground carrying the last hero's remembered palette colour, it
    /// bleeds under the status bar, and it hands over to the canvas through the same kind of long
    /// fade `ArtScrim` uses — never on a line.
    private func skeleton(screenH: CGFloat, topInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // The lockup's shape, CENTRED — badge, name, one line, the bar, the capsule (review
            // i5: the frame that arrives is centred; the skeleton laid it at the left foot).
            VStack(alignment: .center, spacing: 0) {
                Spacer(minLength: 0)
                SkeletonBlock(width: 88, height: 20, radius: 4)
                SkeletonLine(width: 250, height: 28).padding(.top, 12)
                SkeletonLine(width: 160, height: 14).padding(.top, 8)
                SkeletonLine(width: 200, height: 3).padding(.top, 10)
                SkeletonBlock(height: 48, radius: 24).padding(.top, 18)
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .padding(.bottom, isAX ? ThemeSpace.x5 : ThemeSpace.x4)
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: heroHeight(screenH), alignment: .bottom)
            // The remembered tint, not `surfacePlate`. There is no artwork yet by definition, and
            // the hero's colour rarely changes between two opens — so the frame opens on the app's
            // own atmosphere instead of on a grey slab four shades off the canvas.
            //
            // The cold fallback is the branded EMBER, not `PaletteCache.fallback`: that one is a
            // card-ground neutral (#1C1A17) two steps off the canvas, and with no remembered tint
            // this band — the first thing on screen, drawn up under the clock — composited to
            // rgb(38,36,32): the status area read as BLACK for the whole first load and then
            // "became flush" when the art landed (user device, 30 Aug).
            // `ambientBackdropFallback` is the token minted for exactly this moment.
            .background {
                ZStack {
                    TodayView.rememberedTint ?? ThemeColor.ambientBackdropFallback
                    // A little tone off the top so the band is not one flat rectangle: this is the
                    // shape of a photograph under a scrim, and a photograph is never uniform.
                    LinearGradient(colors: [.white.opacity(0.05), .clear],
                                   startPoint: .top, endPoint: .center)
                }
            }
            // Long, like `ArtScrim`'s bottom hand-over. The old mask held solid to 0.86 and then
            // dropped inside 14 %, which at 440 pt is a 60-pt cliff — measured as a hard seam.
            .mask(LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.52),
                .init(color: .black.opacity(0.72), location: 0.74),
                .init(color: .black.opacity(0.26), location: 0.90),
                .init(color: .black.opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom))
            .padding(.top, -topInset)

            // The Planned shelf's shape — the one shelf under the billboard (23 Sep): a header
            // and the 100-pt poster cards with their captions.

            VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
                SkeletonLine(width: 84, height: 19)
                    .padding(.horizontal, ThemeMetrics.gutter)
                // Four 100-pt cards plus gaps are 468 pt wide — wider than the screen. In a plain
                // stack that oversized child sets the ideal width of everything above it, and the
                // WHOLE screen (wordmark and avatar included) gets centred 14 pt to the left with
                // the avatar hanging off the edge. It is only visible for the second the skeleton
                // is up, which is exactly why it survived. A scroller takes the width it is
                // offered, like the shelf it stands in for.
                ScrollView(.horizontal) {
                    SkeletonShelf(count: 4, size: PosterSize.todayShelf.size, caption: true)
                        .padding(.horizontal, ThemeMetrics.gutter)
                }
                .scrollDisabled(true)
                .scrollIndicators(.hidden)
            }
            .padding(.top, ThemeMetrics.sectionGap)
        }
        .accessibilityLabel(Copy.Accessibility.loading)
    }

    // MARK: - Mark timeline

    private func mark(_ f: Franchise, mediaId: Int? = nil) {
        // `handoffInFlight` covers the window `committedEpisode` cannot: the 460 ms during which
        // the NEXT show's card is fading in with a live Mark button on it.
        guard committedEpisode == nil, !handoffInFlight else { return }
        // The show being marked rides in the snapshot even when it is not in the deck (a backlog
        // on the resting billboard), so the stage can hold it through the frame.
        let snapshot = items.contains(where: { $0.id == f.id }) ? items : items + [f]
        guard let undo = appModel.markNext(franchiseId: f.id, mediaId: mediaId) else { return }
        // No receipt UNDER the capsule (removed 17 Sep — the committed frame already confirms the
        // mark; the line read as an extra). Its Undo goes to the lane once the frame settles
        // (`settleHero`), as the batch behind the chevron's does and as the show page's does.
        settleHero(f, snapshot: snapshot, undo: undo)
    }

    /// The committed frame, shared by the single mark and the batch behind the chevron: 650 ms
    /// of the drawn check and the advanced bar on the SAME billboard, then the handoff — the next
    /// release, or the deck without this one.
    ///
    /// The committed frame is the confirmation; there is no in-place line under the capsule (17
    /// Sep: it read as a duplicate of the frame). What the frame cannot carry is the way BACK, so
    /// once the handoff has settled the Undo is presented in the LANE — the tab bar's accessory,
    /// away from the capsule — for the single mark and the batch alike, as on the show page. The
    /// hero was the one mark in the app with no Undo at all, and the 20 Sep toggle offered one for
    /// 1.1 s on the button (review, 23 Sep). The receipt is also where "Series finished · Moved to
    /// Watched" is told.
    private func settleHero(_ f: Franchise, snapshot: [Franchise], undo: UndoState) {
        pinned = snapshot
        handoffInFlight = true
        committedFranchiseId = f.id
        committedCount = max(1, undo.episode - undo.prevProgress)
        withAnimation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion)) {
            committedEpisode = undo.episode
        }
        Announce.status(Copy.Progress.episodeWatched(undo.episode))
        clearRecapStrip()
        // Warm what comes NEXT while the frame holds: its picture and its poster's reading, so the
        // handoff lands a composed billboard instead of art first and the lockup seconds later.
        if let next = liveRestingFeature, next.id != f.id, let url = next.billboardArt.url,
           let source = URL(string: url) {
            Task.detached(priority: .userInitiated) {
                _ = try? await ImageLoader.shared.image(for: source, maxPixel: 2048)
            }
            if next.billboardName == .embedded {
                Task { _ = await PosterTitleCache.shared.analysis(url: url, title: next.title) }
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            let settle = ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)
            withAnimation(settle) {
                pinned = nil
                committedEpisode = nil
                committedFranchiseId = nil
            }
            // On a CLOCK, not the animation's completion: the completion never fired on this
            // hand-off, so the Undo was never presented and `handoffInFlight` stayed up — the
            // billboard stopped taking marks after the first (found 23 Sep, on the local build).
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 420))
            appModel.presentUndo(undo)
            // The incoming card's insertion is delayed by `handoff` and then runs `uiSettle`;
            // it is not tappable until it has actually arrived.
            if !reduceMotion { try? await Task.sleep(for: .milliseconds(300)) }
            handoffInFlight = false
        }
    }

    private struct BatchPrompt: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let confirm: String
        let perform: () -> Void
    }

    /// The batch write behind the hero's chevron.
    ///
    /// Both branches now go through `markThrough`, which captures the prior progress, writes once,
    /// and presents ONE undo carrying the true count and a restoring action. What they did before:
    /// "Mark through episode N" called `setProgress`, which mints no `UndoState` at all — so the
    /// app's most-used multi-episode control had no toast and no undo, and recovery was Detail →
    /// season → episode list → confirm an unmark. "Mark all N" called `markCaughtUp`, which left
    /// `UndoState.count` at its default 1, so a six-episode batch reported "Episode 19 marked as
    /// watched". A write that will not say what it did is not reversible in any useful sense.
    private func promptBatch(_ f: Franchise, part: FranchisePart, through: Int) {
        let count = through - part.progress
        guard count > 0 else { return }
        batchPrompt = BatchPrompt(
            title: Copy.Confirm.batchMarkTitle(count),
            message: Copy.Confirm.batchMarkMessage(title: f.title, season: part.label, from: part.progress, to: through),
            confirm: Copy.Confirm.batchMarkConfirm(count),
            perform: {
                guard committedEpisode == nil, !handoffInFlight else { return }
                // The show being marked rides in the snapshot (see `mark`).
                let snapshot = items.contains(where: { $0.id == f.id }) ? items : items + [f]
                guard let undo = appModel.markThrough(franchiseId: f.id, mediaId: part.mediaId,
                                                      episode: through, present: false) else { return }
                settleHero(f, snapshot: snapshot, undo: undo)
                Announce.status(Copy.Confirm.batchMarkConfirm(count))
            }
        )
    }

    // MARK: - Recap

    /// Computes the digest as soon as the library is in — under the splash if need be — and puts
    /// the recap in the hero frame immediately, so it is the first thing on screen. The
    /// reveal/hold clock only starts once the surface is actually visible.
    private func evaluateRecap() {
        guard !appModel.loading, !recapEvaluated, !appModel.library.isEmpty else { return }
        recapEvaluated = true
        let demo = RecapState.demo
        // The demo window is wide on purpose: the recap now only carries genuine CHANGES (the
        // "where you stopped" filler beat is gone), so a four-day window on a small library
        // produces nothing to look at during a capture pass.
        // 30 days was not wide enough to guarantee a digest on a library whose latest change is
        // older than that, so `-recapDemo 1` — documented as "forces the full recap" — silently did
        // nothing and the arrival could not be reviewed at all. A year always finds the beats that
        // exist, and the flag is DEBUG-only, so nothing a user sees depends on this number.
        let since = demo ? now - 400 * Formatting.D : appModel.prevOpenedAt
        let built = demo
            ? RecapDigest.demoDigest(library: appModel.library, since: since, now: now)
            : RecapDigest.build(library: appModel.library, since: since, now: now)
        guard let digest = built else {
            recap = nil; recapMode = .none; return
        }
        let mode = demo ? .full : digest.presentation(absence: now - since, lastFullRecapAt: RecapState.lastFullRecapAt,
                                                      acknowledgedID: RecapState.acknowledgedID, now: now, enteredByDeepLink: false)
        recap = digest
        recapMode = mode
        if mode == .full {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { recapOnStage = true; recapRevealed = false }
            startRecapClock()
        }
    }

    /// The strip was tapped: bring the recap into the hero frame and run its clock.
    private func stageRecap() {
        guard recap != nil, !recapOnStage else { return }
        recapRevealed = false
        recapClockStarted = false
        withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) { recapOnStage = true }
        startRecapClock()
    }

    /// Reveal, hold, hand off — with two accessibility rules the shipped clock had backwards.
    ///
    /// **VoiceOver never auto-dismisses.** A user got roughly one element spoken before the card
    /// was removed from the tree; the card now waits for `Continue`. **Reduce Motion holds
    /// LONGER**, not shorter (it used to cut the hold from 2,000 ms to 1,600): less movement is
    /// not less reading time, and the two settings that most need time were both given less. The
    /// cold-launch surcharge is gone — the app is opened several times a day and the primary
    /// action must exist quickly.
    private func startRecapClock() {
        guard recapOnStage, appModel.surfaceReady, !recapClockStarted else { return }
        recapClockStarted = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(ThemeMotion.pick(ThemeMotion.uiReveal, reduceMotion: reduceMotion)) { recapRevealed = true }
            // The stage changed under the user without a navigation.
            Announce.screenChanged(recap.map(recapSpokenSummary))
            guard !voiceOver else { return }
            try? await Task.sleep(for: .milliseconds(holdMilliseconds))
            handoffRecap()
        }
    }

    /// How long the recap holds, measured from the LAST beat's reveal.
    ///
    /// It was a constant (2,000 / 2,600 ms) while the beats reveal on a 0.12 s stagger, so a
    /// one-beat digest sat still for 1.9 s after it had finished and a four-beat digest gave the
    /// reader ~1.5 s for four titles. The hold now scales with what there is to read and is still
    /// capped, and Reduce Motion keeps its surcharge: less movement is not less reading time.
    private var holdMilliseconds: Int {
        let beats = max(1, recap?.beats.count ?? 1)
        let reveal = reduceMotion ? 0 : Int(120 * Double(beats + 1))
        return reveal + min(4500, 1400 + 300 * beats) + (reduceMotion ? 600 : 0)
    }

    /// A recap beat's meta line, in the SAME grammar as the queue below it.
    ///
    /// `RecapBeat.label` prints "Episode 19 aired" with no season, while the hero for that exact
    /// episode said "Season 4 · Episode 19" 200 pt above it — one screen, two ways of naming one
    /// thing. Routed through `watchLabel`, so a multi-season show gets its season and a single-part
    /// one does not (which is the rule, not an exception).
    private func recapBeatLabel(_ beat: RecapBeat) -> String {
        guard case .episodesAired(let n, let latest) = beat.kind, n >= 1, let latest,
              let f = appModel.library.first(where: { $0.id == beat.franchiseId }),
              let part = f.releasingPart ?? f.resumePart
        else { return beat.label(now: now) }
        // The row is the EPISODES; the headline above already carries the count and the verb
        // (review i5: "3 episodes aired" twice, 330 px apart).
        if n == 1 { return watchLabel(f, part: part, episode: latest) }
        let range = Copy.episodeRange(max(1, latest - n + 1), latest)
        // The short season name ("The Calamity · Episodes 3–8"): the long arc label pushed the
        // range — the row's one fact — to a second line (iteration 2).
        return f.parts.count > 1 ? "\(Copy.compactPartLabel(part.canonicalLabel)) \u{00B7} \(range)" : range
    }

    private func recapSpokenSummary(_ recap: RecapDigest) -> String {
        "\(TodayCopy.whileYouWereAway). \(recapStripText(recap))."
    }

    /// Recap → focus, in ONE move.
    ///
    /// It used to be two: the hero shrank and settled (460 ms), and only in that animation's
    /// `completion:` did `acknowledgeRecap()` set `recapMode = .strip` inside a *second*
    /// `withAnimation`, inserting a 44-pt strip that shoved everything under it down ~60 pt on
    /// another 220 ms curve. The screen appeared to finish and then jumped. The mode change belongs
    /// in the same transaction as the shrink; only the persistence — which animates nothing — is
    /// left for afterwards.
    private func handoffRecap() {
        guard recapOnStage else { return }
        let next: RecapDigest.Presentation = recapMode == .full ? .strip : .none
        withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) {
            recapOnStage = false
            recapMode = next
        }
        // Persistence animates nothing, so it runs here, not in an animation completion that
        // cannot be relied on to fire (the hero's Undo never did, 23 Sep).
        persistRecapAcknowledgement()
    }

    /// The recap's explicit ✕.
    ///
    /// It used to call `onContinue()` — the same thing "Continue" does — so the dismiss control
    /// demoted the card to the strip and it reappeared 460 ms later, which is the opposite of what
    /// a ✕ promises. Dismiss means gone: no strip, nothing to come back to on this visit.
    private func dismissRecap() {
        guard recapOnStage else { return }
        withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) {
            recapOnStage = false
            recapMode = .none
        }
        persistRecapAcknowledgement()
    }

    /// Persistence only — it animates nothing, so it may run in a completion handler without
    /// splitting the handoff into two moves. (The full recap DEMOTES to the strip rather than
    /// disappearing: the strip is the standing way back in, and it is what leaving the screen
    /// finally clears.)
    private func persistRecapAcknowledgement() {
        guard let recap, !RecapState.demo else { return }
        RecapState.acknowledgedID = recap.digestID
        RecapState.lastFullRecapAt = now
    }

    /// Leaving the screen clears the strip.
    private func clearRecapStrip() {
        guard recapMode == .strip else { return }
        persistRecapAcknowledgement()
        recapMode = .none
    }

    /// "since 23 Jul" — the sentence-internal form of `TemporalCopy.since`.
    ///
    /// Lower-casing the whole phrase produced "1 episode aired since 23 **jul**": a month
    /// abbreviation is a proper noun and does not follow the sentence. Only the leading word is
    /// re-cased; everything the formatter produced is left exactly as it wrote it.
    private func sinceFragment(_ ts: Int64) -> String {
        let s = TemporalCopy.since(ts, now: now)
        guard let space = s.firstIndex(of: " ") else { return s.lowercased() }
        return "since " + s[s.index(after: space)...]
    }

    private func recapStripText(_ recap: RecapDigest) -> String {
        let aired = recap.airedCount
        let since = sinceFragment(recap.since)
        // No numeral: the badge 260 pt above already carries one, and "3 episodes aired" under
        // "3 EPISODES BEHIND" was the same number twice (review, 5 Sep).
        if aired > 0 { return "What you missed \(since)" }
        return "\(Copy.updates(recap.allBeats.count)) \(since)"
    }
}

extension RecapState {
    /// `-recapDemo 1` launch argument: force the full recap every launch (captures / review).
    static var demo: Bool { UserDefaults.standard.bool(forKey: "recapDemo") }
}

// The `Wordmark` lockup lives in the design system now (Primitives.swift) — hoisted so Profile's
// colophon and this header draw one logo instead of two drifted copies.

/// The two top veils, the only chrome that reads the scroll offset.
private struct TodayVeils: View {
    let scroll: ScrollOffset
    let topInset: CGFloat
    let showsHero: Bool
    let carriesBase: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hardOn: Bool {
        showsHero ? ((carriesBase && scroll.heroCopyUnderBand) || scroll.heroUnderBand) : scroll.y > 8
    }

    var body: some View {
        let band = topInset + TodayView.headerBand
        ZStack(alignment: .top) {
            // ONE material, mounted once the veil is due, whose height, hold and opacity switch
            // when the bar hardens: the soft veil used to unmount and the hard one mount in the
            // same frame the title docked — a blur torn down and built while the finger was
            // still moving ("halfway through it just halts", 5 Sep).
            if hardOn || scroll.y > 12 {
                ScrollEdgeChrome(side: .top,
                                 height: band + (hardOn ? ThemeMetrics.barEdgeRamp : TodayView.veilRamp),
                                 holdHeight: hardOn ? band : nil)
                    .opacity(hardOn ? 1 : scroll.veilOpacity)
                    .transition(.opacity)
            }
        }
        .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: hardOn)
        .allowsHitTesting(false)
    }
}

/// The hero's art, grown by the pull-down. The frame the layout sees never changes (everything
/// below travels with the pull, once); only the art is taller, bottom-aligned, so it fills the
/// rubber band the way a stretchy header should.
private struct StretchingHeroArt: View {
    let scroll: ScrollOffset
    let url: String?
    let height: CGFloat
    let tint: Color?
    let scrimBottom: Double
    let portrait: Bool
    var ultraWide: Bool = false
    var onArtLoaded: (() -> Void)? = nil
    /// The wordmark band: the picture starts under it, the blurred ground fills it (review i3)
    /// — only for a show whose poster may carry its own logotype (`billboardName == .type`: no
    /// logo drawn, so the selected poster is the titled one or the catalogue has no gallery);
    /// a logo over textless art keeps the full bleed.
    var topInset: CGFloat = 0
    /// See `ArtHeader.groundDim`.
    var groundDim: Double = 0.28

    var body: some View {
        ArtHeader(url: url, height: height + scroll.stretch, tint: tint,
                  scrimTop: 0, scrimBottom: scrimBottom,
                  // Faces live in the upper third of a key visual and in the upper half of a
                  // cover; a centred crop of either is a chin.
                  focus: .top, portraitSource: portrait, drift: true, ultraWide: ultraWide,
                  onArtLoaded: onArtLoaded, topInset: topInset, groundDim: groundDim) { EmptyView() }
    }
}

// MARK: - The billboard

/// What a billboard says — the show page's lockup grammar (`HeroLockup`) as data: the STATE on
/// the badge, the moment and the episode as the one line, where you are as the bar, and a support
/// line only where it is earned.
private struct TodayLockupContent {
    var badge: String
    var attention: Bool = false
    var moment: String? = nil
    var fact: String
    var support: String? = nil
    var progress: Double? = nil
    var progressSpoken: String? = nil
}

/// Today's billboard — the SHOW PAGE's hero, on Today (23 Sep: one hero grammar, the user's pick).
/// A poster that carries its own title (`BillboardName.embedded`) is drawn WHOLE at its native
/// aspect and the lockup is laid AROUND the printed title (`PosterLockupLayout`, the title found
/// on device by `PosterTitleCache`) — never cropped and never typed a second time. Any other art
/// fills the frame and the lockup sits at its foot on the copy scrim. The lockup is `HeroLockup`
/// in the app's amber, the same view the show page draws; the 20 Sep card cropped the titled
/// poster to 0.80 of the screen and laid a white badge and a white toggle over its lettering.
private struct TodayBillboard<Actions: View>: View {
    let franchise: Franchise
    let width: CGFloat
    /// The frame for FILLED art; a whole poster takes its own height.
    let fillHeight: CGFloat
    /// A page of the release deck is as tall as the deck.
    var minHeight: CGFloat = 0
    let content: TodayLockupContent
    var interactive: Bool = true
    /// Today's scroll offset: a PULL grows the art from its foot instead of opening a black band
    /// above it with the ribbon and the avatar floating on nothing (review i5, F9). Read only by
    /// `PullStretch`, one transform, so a scroll frame re-runs that modifier and nothing else.
    var scroll: ScrollOffset? = nil
    let onOpen: () -> Void
    var onArtLoaded: (() -> Void)? = nil
    @ViewBuilder var actions: () -> Actions

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The poster's reading (`PosterTitleCache`); nil until known, and the picture and its lockup
    /// wait for it rather than landing on a guess and jumping.
    @State private var analysis: PosterAnalysis?
    @State private var headlineHeight: CGFloat = 0
    @State private var controlsHeight: CGFloat = 0
    @State private var copyHeight: CGFloat = 0
    @State private var tint: Color?
    @State private var lightness: Double?

    private var isAX: Bool { typeSize.isAccessibilitySize }
    private var art: WideArt { franchise.billboardArt }
    private var embedded: Bool { franchise.billboardName == .embedded }
    private var strength: Double { HeroProtection.strength(lightness: lightness) }

    /// The reading this frame can use: the one this view fetched, else one a previous launch
    /// remembered — so a known poster is staged on its first frame.
    private var reading: PosterAnalysis? {
        analysis ?? PosterTitleCache.shared.cached(url: art.url, title: franchise.title)
    }

    /// The poster staged around its printed title (`PosterStage`). Before the reading lands the
    /// frame is sized on the gallery's aspect and the lower-third guess, and nothing is drawn on it.
    private var stage: PosterStage {
        let gallery: CGFloat? = franchise.artwork?.portraitAspect(for: art.url).map { CGFloat($0) }
        let aspect: CGFloat = reading?.aspect ?? gallery ?? (2.0 / 3.0)
        return PosterStage(posterHeight: width / aspect, region: reading?.region ?? .lowerTitle,
                           chromeBottom: ThemeMetrics.topSafeInset + PosterStage.chromeBand,
                           headline: headlineHeight, controls: controlsHeight, minHeight: minHeight)
    }

    var body: some View {
        Group {
            if embedded { wholePoster } else { filled }
        }
        .task(id: art.url) {
            async let palette = PaletteCache.shared.resolve(url: art.url, maxPixel: 360)
            if embedded {
                if reading == nil {
                    let found = await PosterTitleCache.shared.analysis(url: art.url, title: franchise.title)
                    guard !Task.isCancelled else { return }
                    withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) { analysis = found }
                }
                onArtLoaded?()
            }
            tint = await palette
            lightness = PaletteCache.shared.lightness(for: art.url)
        }
    }

    private var wholePoster: some View {
        let stage = self.stage
        let ground = tint ?? PaletteCache.fallback
        // The show's colour behind the picture, landing on CANVAS AT THE POSTER'S FOOT — the
        // colour the poster itself fades to (`AuthoredHeroArt`'s ground). Ramping to canvas at the
        // STAGE's foot instead put a band of tint under a poster already faded to canvas: an
        // inverted step across the full width at 589 pt, and a flat navy band at AX (review i3).
        let posterFoot = max(0.001, min(1, (stage.posterTop + stage.posterHeight) / max(stage.height, 1)))
        let fadeFrom = max(0, min(posterFoot, (stage.posterTop + stage.posterHeight - 96) / max(stage.height, 1)))
        return ZStack(alignment: .top) {
            LinearGradient(stops: [.init(color: ground, location: 0),
                                   .init(color: ground, location: fadeFrom),
                                   .init(color: ThemeColor.canvas, location: posterFoot)],
                           startPoint: .top, endPoint: .bottom)
            // The whole picture opens the show, and dips when pressed like every art surface. It
            // is drawn at once, full bleed; only the lockup waits for the poster's reading, so it
            // lands around the printed title instead of jumping to it.
            Button(action: onOpen) {
                AuthoredHeroArt(url: art.url, imageHeight: stage.posterHeight,
                                nameBottom: stage.untitled ? nil : stage.nameBottom)
            }
            .buttonStyle(OverArtPressStyle())
            .accessibilityLabel(franchise.displayTitle)
            .accessibilityHint(Copy.Accessibility.opensTheShowHint)
            .frame(height: stage.posterHeight)
            .modifier(PullStretch(scroll: scroll, height: stage.posterHeight))
            lockup(stage: stage)
                .padding(.horizontal, ThemeMetrics.gutter)
                .opacity(reading == nil ? 0 : 1)
            // The clock and the brand mark over a bright poster — a veil only as deep as the bar,
            // at its lightest, so a title printed across the top is never buried under it.
            HeroTopVeil(band: ThemeMetrics.topSafeInset + TodayView.headerBand,
                        ramp: TodayView.veilRamp, strength: min(strength, 0.35))
                .allowsHitTesting(false)
        }
        .frame(width: width, height: stage.height)
        // Clipped at the sides and the foot only — the pull's stretch grows above the frame.
        .clipShape(Rectangle().size(width: width, height: stage.height + 2000).offset(y: -2000))
    }

    private var filled: some View {
        let h = max(fillHeight, copyHeight + (isAX ? 210 : 132), minHeight)
        return ZStack(alignment: .bottom) {
            (tint ?? PaletteCache.fallback)
            ArtHeader(url: art.url, height: h, tint: tint, scrimTop: 0, scrimBottom: 0,
                      focus: .top, portraitSource: art.portraitSource, drift: true,
                      ultraWide: art.ultraWide, onArtLoaded: onArtLoaded,
                      groundDim: HeroProtection.groundDim(strength)) { EmptyView() }
                .modifier(PullStretch(scroll: scroll, height: h))
            HeroCopyScrim(copyHeight: copyHeight, strength: strength)
            lockup(stage: nil)
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.bottom, isAX ? ThemeSpace.x5 : ThemeSpace.x4)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { copyHeight = $0 }
        }
        .frame(width: width, height: h)
        .overlay(alignment: .top) {
            HeroTopVeil(band: ThemeMetrics.topSafeInset + TodayView.headerBand,
                        ramp: TodayView.veilRamp, strength: strength)
                .allowsHitTesting(false)
        }
        // Clipped at the sides and the foot only — the pull's stretch grows above the frame.
        .clipShape(Rectangle().size(width: width, height: h + 2000).offset(y: -2000))
    }

    private func lockup(stage: PosterStage?) -> some View {
        HeroLockup(badge: content.badge,
                   badgeAttention: content.attention,
                   title: franchise.displayTitle,
                   name: franchise.billboardName,
                   posterStage: stage,
                   onPosterHeadlineHeight: { headlineHeight = $0 },
                   onPosterControlsHeight: { controlsHeight = $0 },
                   posterProtection: strength,
                   lineLimit: isAX ? 3 : 2,
                   moment: content.moment,
                   fact: content.fact,
                   support: content.support,
                   progress: content.progress,
                   progressSpoken: content.progressSpoken,
                   onOpen: stage == nil ? onOpen : nil,
                   interactive: interactive,
                   fadeBand: ThemeMetrics.topSafeInset + TodayView.headerBand,
                   accessory: { EmptyView() },
                   actions: actions)
    }
}

/// Three chart posters fanned over an empty account's first sentence.
private struct TodayPosterFan: View {
    let covers: [String]

    var body: some View {
        ZStack {
            ForEach(Array(covers.prefix(3).enumerated()), id: \.element) { index, cover in
                PosterSlot(url: cover, width: index == 1 ? 142 : 126,
                           height: index == 1 ? 213 : 189, radius: PosterSize.shelfLarge.radius)
                    .rotationEffect(.degrees(Double(index - 1) * 9))
                    .offset(x: CGFloat(index - 1) * 82,
                            y: index == 1 ? 0 : 17)
                    .zIndex(index == 1 ? 2 : 1)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 226)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// An empty account's first frame: three posters from the chart, one sentence, the next step in
/// the app's amber — the same "Add a show", hugging, that Library's and Schedule's empty states
/// offer — and the chart.
private struct TodayEmptyLibraryState<Shelf: View>: View {
    let fanCovers: [String]
    let onAddShow: () -> Void
    @ViewBuilder var shelf: () -> Shelf
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            if fanCovers.count == 3 {
                TodayPosterFan(covers: fanCovers)
            }
            VStack(spacing: ThemeSpace.x2) {
                Text(Copy.Today.buildYourToday)
                    .type(ThemeType.displayL)
                    .foregroundStyle(ThemeColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text(Copy.Today.buildYourTodaySupporting)
                    .type(ThemeType.callout)
                    .foregroundStyle(ThemeColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 320)
            .padding(.horizontal, ThemeMetrics.gutter)
            .padding(.top, fanCovers.count == 3 ? ThemeSpace.x5 : ThemeSpace.x8)

            Button(Copy.Action.addAShow, action: onAddShow)
                .buttonStyle(PrimaryButtonStyle2())
                .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: false)
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.top, ThemeSpace.x5)

            shelf()
                .padding(.top, ThemeMetrics.sectionGap)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Recap arrival

/// The arrival, given the hero's anatomy.
///
/// It used to be a ~170-pt strip pinned to the bottom of the frame with 72 % of the screen above
/// it carrying **nothing** — no eyebrow, no title, no CTA, no dismiss, no visible tap target at
/// all, the only exit an undocumented `onTapGesture`. Its eyebrow was a window with no noun
/// ("SINCE 18 AUG") and its plate carried a full-perimeter stroke that `.plate` is specified not to
/// have. Now: the same eyebrow-title-copy ladder the Focus hero uses, laid on the art under the
/// scrim that is sized to it, the beats in one plate below, an explicit `Continue`, and a real
/// dismiss.
private struct RecapArrival: View {
    let digest: RecapDigest
    let revealed: Bool
    let now: Int64
    let reduceMotion: Bool
    /// The photograph the recap is laid on. A beat whose cover IS this art gets no poster — see
    /// `showsPoster`.
    let heroArt: String?
    /// The beat's meta line, resolved against the library so it can carry the season the hero
    /// carries. `RecapBeat` knows only a franchise id and a title.
    let beatLabel: (RecapBeat) -> String
    /// The beat's show by the name every other row uses (`displayTitle`) — the recap printed
    /// "Re:ZERO -Starting Life in Another World-" over the hero that says "Re:ZERO" (review, 23 Sep).
    var beatTitle: (RecapBeat) -> String = { $0.title }
    /// A row opens ITS show (review, 23 Sep: every row looked like a link, and tapping Bleach
    /// only collapsed the card). Nil keeps the whole card as the one Continue target.
    var onOpenBeat: ((RecapBeat) -> Void)? = nil
    let onContinue: () -> Void
    let onDismiss: () -> Void

    @State private var tint: Color?

    // Split out of the card's body: one expression with the rows, the reveal animations and the
    // "and N more" line inside a Button no longer type-checks in reasonable time.
    @ViewBuilder
    private func beatRow(_ beat: RecapBeat, index i: Int) -> some View {
        HStack(spacing: ThemeSpace.x3) {
            if showsPoster { PosterSlot(url: beat.cover, .beat) }
            VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x2) {
                    Text(beatTitle(beat))
                        .type(ThemeType.rowTitle)
                        // BOTH rows at `textPrimary`. The second used to be `textSecondary`, so it
                        // read as disabled; the aired-vs-upcoming distinction lives in the meta line.
                        .foregroundStyle(ThemeColor.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: ThemeSpace.x2)
                    if i == 0 || onOpenBeat != nil {
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ThemeColor.textDisabled)
                            .accessibilityHidden(true)
                    }
                }
                Text(beatLabel(beat))
                    .type(ThemeType.rowMeta)
                    .foregroundStyle(ThemeColor.textSecondary)
                    // Two lines: a long arc name ("Thousand-Year Blood War - The Calamity") cut
                    // the one fact the row exists for — the episodes — off the end.
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed || reduceMotion ? 0 : 6)
        .animation(ThemeMotion.pick(ThemeMotion.uiReveal, reduceMotion: reduceMotion)
            .delay(reduceMotion ? 0 : 0.12 * Double(i + 1)), value: revealed)
    }

    /// The beats past the third row, by name — one opens its show like the rows above it.
    @ViewBuilder
    private var moreLine: some View {
        let hidden = digest.hidden
        let text = TodayCopy.also(hidden.map(beatTitle), label: hidden.count == 1 ? hidden.first.map(beatLabel) : nil)
        Group {
            if hidden.count == 1, let beat = hidden.first, let onOpenBeat {
                Button { onOpenBeat(beat) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x2) {
                        Text(text)
                            .type(ThemeType.metadata)
                            .foregroundStyle(ThemeColor.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: ThemeSpace.x2)
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ThemeColor.textDisabled)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .accessibilityHint(Copy.Accessibility.opensTheShowHint)
            } else {
                Text(text)
                    .type(ThemeType.metadata)
                    .foregroundStyle(ThemeColor.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(revealed ? 1 : 0)
        .animation(ThemeMotion.pick(ThemeMotion.uiReveal, reduceMotion: reduceMotion)
            .delay(reduceMotion ? 0 : 0.12 * Double(digest.beats.count + 1)), value: revealed)
    }

    /// "11 episodes aired" / "2 updates waiting" — what the card is, in the hero's voice, counted
    /// over EVERY beat, the ones past the third row included.
    private var headline: String {
        let aired = digest.airedCount
        return aired > 0 ? "\(Copy.episodes(aired)) aired" : "\(Copy.updates(digest.allBeats.count)) waiting"
    }

    /// Whether the beat rows carry artwork at all.
    ///
    /// A single-title recap laid on that title's own key visual at 440 pt printed the SAME image
    /// again at 34×51 about 200 pt below it — a postage stamp of the picture above it, inside a box,
    /// under a cinematic frame. When the only thing on the card is the show the hero is already
    /// showing, the title line carries the row. Two or more distinct titles still need identifying.
    private var showsPoster: Bool {
        guard digest.beats.count == 1, digest.hiddenBeatCount == 0 else { return true }
        guard let cover = digest.beats.first?.cover, let heroArt else { return true }
        return cover != heroArt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The badge, the headline and its since-line on the billboard's CENTRED axis, as on
            // every other billboard (review i3: the recap was the one lockup on the gutter); the
            // dismiss keeps the trailing corner.
            ZStack(alignment: .topTrailing) {
                HeroBadge(text: TodayCopy.whileYouWereAway)
                    .frame(maxWidth: .infinity)
                // A real dismiss. 22 pt of low-contrast glyph was the only way out of a full-screen
                // takeover, and it called `onContinue` — so ✕ and "Continue" did the same thing and
                // the card came back as the strip 460 ms later. 30 pt on its own ground, ringed, in
                // a 44-pt target, wired to a dismissal that dismisses.
                Button(action: onDismiss) {
                    ZStack {
                        Circle().fill(ThemeColor.scrimStrong)
                        Circle().strokeBorder(ThemeColor.posterEdge, lineWidth: 1)
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ThemeColor.textPrimary)
                    }
                    .frame(width: 30, height: 30)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                }
                .buttonStyle(OverArtPressStyle())
                .accessibilityLabel(TodayCopy.dismissRecap)
                .padding(.trailing, -10)
                .padding(.top, -8)
            }
            Text(headline)
                .type(ThemeType.displayL)
                .foregroundStyle(ThemeColor.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.top, ThemeSpace.x3)
            // "Since 23 Jul" named a date with no anchor — since what? The last visit is what the
            // digest is actually built from, so the card says so. The strip below stays terse.
            Text(TodayCopy.sinceYourLastVisit(TemporalCopy.since(digest.since, now: now)))
                .type(ThemeType.metadata)
                .foregroundStyle(ThemeColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.top, ThemeSpace.x0_5)

            // The WHOLE card is the button, and the chevron sits on the title row.
            //
            // "Continue ›" used to be a 15-pt amber link stranded on the card's floor with a
            // ~150×60 pt hole beside it, in a 110-pt box whose only art was the smallest in the
            // app. The card is now the target it always was, the forward affordance is beside the
            // words it belongs to, and the box is the height of its content.
            Button(action: onContinue) {
                VStack(alignment: .leading, spacing: ThemeSpace.x3) {
                    ForEach(Array(digest.beats.enumerated()), id: \.element.id) { i, beat in
                        if let onOpenBeat {
                            Button { onOpenBeat(beat) } label: { beatRow(beat, index: i).contentShape(Rectangle()) }
                                .buttonStyle(RowPressStyle())
                                .accessibilityLabel("\(beatTitle(beat)), \(beatLabel(beat))")
                                .accessibilityHint(Copy.Accessibility.opensTheShowHint)
                        } else {
                            beatRow(beat, index: i)
                        }
                    }
                    if digest.hiddenBeatCount > 0 { moreLine }
                }
                .padding(ThemeSpace.x4)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                // `.surface(.art(tint))`, not a local stroked box: `.plate` is specified as having
                // no edge, and the recap was the one surface in the app overriding that.
                .surface(.art(tint), radius: ThemeRadius.focusCard)
                .contentShape(Rectangle())
            }
            .buttonStyle(OverArtPressStyle())
            .padding(.top, ThemeSpace.x5)
            // With rows that open their shows, VoiceOver reaches each row; merged, it could not.
            .accessibilityElement(children: onOpenBeat == nil ? .combine : .contain)
            .accessibilityLabel(onOpenBeat == nil
                                ? digest.beats.map { "\($0.title), \(beatLabel($0))" }.joined(separator: ". ")
                                : headline)
            .accessibilityHint(onOpenBeat == nil ? "Continues to what is next" : "")
        }
        .shadow(.art)
        .task(id: digest.beats.first?.cover) {
            tint = await PaletteCache.shared.resolve(url: digest.beats.first?.cover, maxPixel: 360)
        }
    }
}

// MARK: - Recap line

/// The compact recap, on the CANVAS.
///
/// It used to be a 16-pt-radius filled box — the only boxed container on the screen — with its
/// chevron 200–270 pt from the text it belongs to and nothing in between: exactly the pattern the
/// direction had already removed from the queue rows a section below it. Same grammar as every
/// other row here: art, a line, and the forward glyph immediately after the words.
private struct RecapLine: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x2) {
                // The glyph is the line's anchor: without one it was the single row on the screen
                // with neither art nor a control, and read as a stray line of debug output.
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ThemeColor.textSecondary)
                    .accessibilityHidden(true)
                Text(text)
                    .type(ThemeType.metadataEmphasis)
                    .foregroundStyle(ThemeColor.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ThemeColor.textDisabled)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            // 28 pt of drawn line inside a 44-pt target (review i2: a 44-pt row plus the
            // section gap floated the residue 45 pt under the capsule and 51 above Upcoming).
            .frame(minHeight: 28, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .padding(.vertical, -8)
        .accessibilityLabel(text)
        .accessibilityHint("Opens what you missed")
    }
}

/// The wordmark band. Its own view so that the dock (`scroll.heroCopyUnderBand`) invalidates
/// this HStack and nothing else — the screen's body never reads it.
private struct TodayHeaderBar: View {
    @Binding var showProfile: Bool
    let scroll: ScrollOffset
    let overArtwork: Bool

    @Environment(AuthManager.self) private var auth

    var body: some View {
        HStack(alignment: .center) {
            // Over the art, the RIBBON alone: the full wordmark across a poster competes with its
            // printed title and the faces under it, and the billboard is the one place the app
            // steps out of the picture's way ("no longer feels cinematic", user, 23 Sep). Once
            // the art has scrolled off the wordmark returns — CROSSFADED, not swapped (a hard
            // swap at the threshold popped, review 23 Sep).
            let overArt = overArtwork && scroll.y < 100
            ZStack(alignment: .leading) {
                Wordmark()
                    .opacity(overArt ? 0 : 1)
                PreviouslyMark(width: 13)
                    .shadow(.art)
                    .opacity(overArt ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.22), value: overArt)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Previously")
            Spacer(minLength: ThemeSpace.x4)
            Button { showProfile = true } label: {
                AccountDisc(identity: auth.identity, diameter: 34, quiet: true)
                    .shadow(.art)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(OverArtPressStyle())
            .accessibilityLabel("Profile")
        }
        .padding(.leading, ThemeMetrics.gutter)
        // The disc's edge on the gutter: its 44-pt target is 5 pt wider than the 34-pt disc on
        // each side, and x2 left it 13 pt from the edge (review, 23 Sep).
        .padding(.trailing, ThemeMetrics.gutter - 5)
        .frame(height: TodayView.headerBand)
    }
}


