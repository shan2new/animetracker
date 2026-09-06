import SwiftUI

/// Two strings this screen needs that the shared copy table does not carry yet: the hero's
/// secondary action and the primary's committed label. Both are filed as an exact diff against
/// `Copy.swift` (a design-system file this track does not own); they live here, named and in one
/// place, until that lands — never inline at a call site.
private enum TodayCopy {
    static let details = Copy.Action.details
    static let continueAction = Copy.Action.continueLabel
    static let whileYouWereAway = Copy.Recap.whileYouWereAway
    static func andMore(_ n: Int) -> String { "and \(n) more" }
    static let dismissRecap = Copy.Action.dismissRecap
    static let opensTheShow = Copy.Accessibility.opensTheShowHint
    static func sinceYourLastVisit(_ phrase: String) -> String { Copy.Recap.sinceYourLastVisit(phrase) }
}

// "Today" — the Focus Stack (spec v8, boards 01–03), rebuilt around a FULL-BLEED HERO.
//
// The shipped build put the single most cinematic frame in the app — "here is the thing to watch
// right now" — inside a 200-pt stroked box with an 80×120 thumbnail in it, on a canvas it was only
// 4 % lighter than. Identity art went from ≈180 000 px² in the original to ≈11 600 px². This file
// puts it back: artwork from the status bar to ~72 % of the screen (Apple TV Home's billboard
// proportion), the wordmark and avatar floating over it, one primary action laid on the art, and
// rhythm underneath.
//
//   arrival  → Previously Recap in the hero frame, over the art of what comes next;
//   resting  → the hero + the rest of the queue + "Coming next" + the Watching shelf;
//   calm     → the copy table's calm state over an ambient wash of the next known event.
//
// Presentation is derived from AppModel feeds (outNow → keepWatching → nextUp); the view owns only
// timing state. One haptic per transaction; the Undo toast lands when the handoff settles.
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
    /// Queue rows whose ring is drawing its check (650 ms after a tap).
    @State private var committedQueue: Set<String> = []
    @State private var pendingUndo: UndoState?
    @State private var batchPrompt: BatchPrompt?
    /// True from the moment a mark commits until the INCOMING card has finished arriving.
    ///
    /// Without it the hero is a trap: `committedEpisode` clears at 650 ms and the next show's card
    /// fades in over 460 ms with its Mark button already live and hit-testable at partial opacity,
    /// so a user clearing three episodes has tap 2 swallowed and tap 3 land on a half-faded button
    /// belonging to a *different franchise* — the write goes to the wrong show and the single Undo
    /// toast only covers the most recent one.
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

    /// The rest of the queue under the hero, as cards on the Up next shelf (rows at accessibility
    /// sizes). Two, not four: the stack is what the Watching shelf excludes, and at four an
    /// eight-show library left ONE poster for that shelf, which then fell back to a single row
    /// (captured 4 Sep). The upcoming cards follow these on the same shelf.
    /// Two while a Watching shelf sat under the queue and caught the overflow; four now that
    /// `Continue watching` only carries shows with NO new episode — an unwatched drop must never
    /// fall off Today into a shelf that is about backlog (user, 6 Sep).
    private var queueCount: Int { 4 }
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
    /// What a `MediaRow` already contributes above and below itself.
    ///
    /// The row carries `ThemeSpace.x2` of vertical padding INSIDE its own minimum height, so a
    /// container that then adds a full `labelGap` or `sectionGap` produces 8 pt more than the token
    /// names — measured at 31 pt under a label whose token says 10, and 51–57 pt between sections
    /// whose token says 30. Rhythm is what the reader sees, so the container pays the token minus
    /// what the row already spends.
    private static let rowOwnInset: CGFloat = ThemeSpace.x2

    private var isAX: Bool { typeSize.isAccessibilitySize }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let topInset = geo.safeAreaInsets.top
            let screenH = geo.size.height + topInset + geo.safeAreaInsets.bottom
            ZStack(alignment: .top) {
                // The ambient wash. On a hero day the hero itself is the art; on a calm, empty or
                // failed day the screen still opens on the atmosphere of the next known event
                // rather than on #09090B.
                if !showsHero {
                    // The one root wash spec — Today's no-hero states carried a private 340/0.55,
                    // one of the seven configurations the cohesion pass collapsed.
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
                                topBlock(screenH: screenH, topInset: topInset,
                                         contentH: geo.size.height)
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
                            scroll.set(topInset - minY)
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
        .onChange(of: appModel.surfaceReady) { _, _ in startRecapClock() }
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
        .confirmationDialog(batchPrompt?.title ?? "", isPresented: Binding(get: { batchPrompt != nil }, set: { if !$0 { batchPrompt = nil } }),
                            titleVisibility: .visible, presenting: batchPrompt) { prompt in
            Button(prompt.confirm) { prompt.perform() }
            Button(Copy.Confirm.cancel, role: .cancel) {}
        } message: { prompt in
            Text(prompt.message)
        }
    }

    #if DEBUG
    /// `-todayAnchor upnext|watching` (DEBUG, like `-calmDemo`): scroll the loaded screen to a
    /// section for a capture — the way to photograph the shelves when the simulator cannot be
    /// touched (the input MCP dies between sessions; `simctl` has no scrolling).
    private func debugScroll(_ proxy: ScrollViewProxy) async {
        guard !appModel.loading,
              let anchor = UserDefaults.standard.string(forKey: "todayAnchor"), !anchor.isEmpty
        else { return }
        try? await Task.sleep(for: .milliseconds(1500))
        guard !Task.isCancelled else { return }
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
        TodayHeaderBar(scroll: scroll, carriesBase: headerCarriesBase, heroFranchise: heroFranchise,
                       showProfile: $showProfile)
    }

    // MARK: - Content states

    private var isFailed: Bool { appModel.loadError && appModel.libraryEmpty }
    private var isEmptyAccount: Bool { !appModel.loading && appModel.libraryEmpty && !appModel.loadError }
    /// A library with nothing to watch. The chart carries the screen, as it already does for an
    /// empty account — the machinery is the same, only the gate is wider.
    ///
    /// Today carries ONLY what you can act on now (6 Sep). The two blocks that reprinted another
    /// tab are gone — the Upcoming cards (Schedule's own first rows, verbatim) and the Watching
    /// shelf (Library's) — and a caught-up day opens on the chart rather than on a future airing
    /// dressed as a hero. A future airing is not actionable BY DEFINITION, so Today does not
    /// print one at all, not as a card and not as a line: the calendar is a tab that owns dates.
    private var showsDiscovery: Bool {
        !appModel.libraryEmpty && !isFailed && !appModel.loading && actionable.isEmpty
    }
    /// Whether the top of the screen is a full-bleed hero (and therefore owns the art itself).
    private var showsHero: Bool {
        guard !appModel.libraryEmpty, !isFailed else { return false }
        return heroFranchise != nil || (recapOnStage && recap != nil)
    }
    /// The wash behind a screen that has no hero: whatever the user is closest to caring about.
    private var ambientArt: String? {
        appModel.nextUp?.portraitArt ?? appModel.watchingShelf.first?.portraitArt ?? appModel.library.first?.portraitArt
    }

    @ViewBuilder
    private func topBlock(screenH: CGFloat, topInset: CGFloat, contentH: CGFloat) -> some View {
        if isFailed {
            stateBlock(SyncCenter.shared.isOnline ? .serverNoCache : .offlineNoData,
                       contentH: contentH) {
                Task { await appModel.reload() }
            }
        } else if isEmptyAccount {
            // A first run opens on television, not on an instruction: the chart's top show on
            // the billboard with one way in, and the rest of the chart under it. The card is the
            // fallback for an account that cannot see a chart (offline, or the chart failed).
            if let top = appModel.trending.first {
                trendingBlock(top, screenH: screenH, topInset: topInset)
            } else if appModel.trendingLoading {
                skeleton(screenH: screenH, topInset: topInset)
            } else {
                // `emptyToday`, not `emptyAccount`: the latter is LIBRARY's string, and a state
                // may not title itself after a tab the user is not looking at.
                stateBlock(.emptyToday, contentH: contentH, action: onAddShow)
            }
        } else if showsDiscovery {
            // The same billboard the first run gets, for the same reason: there is nothing to
            // continue, so the screen shows television rather than four posters saying "Caught up".
            if let top = appModel.trending.first {
                trendingBlock(top, screenH: screenH, topInset: topInset)
            } else if appModel.trendingLoading {
                skeleton(screenH: screenH, topInset: topInset)
            } else {
                calmBlock
            }
        } else if showsHero {
            hero(heroFranchise, screenH: screenH, topInset: topInset)
        } else {
            calmBlock
        }
    }

    // MARK: - First contact: the trending billboard

    /// A brand-new account's first frame, on the hero's own billboard: the chart's top show, its
    /// name and identity, ONE action ("Add to Library" — Netflix's "+ My List" on the billboard),
    /// and the rest of the chart on a shelf beneath. The block opens the show. Apple TV's and
    /// Netflix's first screen is never a sentence on a black canvas; it is television with a way
    /// in. The add is `addToLibrary`'s optimistic path, so the capsule flips to "In library" on
    /// the tap and the real hero takes over when the library lands.
    @ViewBuilder
    private func trendingBlock(_ item: FranchiseSummary, screenH: CGFloat, topInset: CGFloat) -> some View {
        let h = heroHeight(screenH)
        // The same order as the hero's: the server-selected landscape first, the cover composited
        // only when there is none.
        let billboard = item.billboardArt
        let art = billboard.url
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottom) {
                (heroTint ?? PaletteCache.fallback)
                    .frame(height: h)
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                StretchingHeroArt(scroll: scroll, url: art, height: h, tint: heroTint,
                                  scrimBottom: 0, portrait: billboard.portraitSource,
                                  ultraWide: billboard.ultraWide,
                                  onArtLoaded: markArtReady,
                                  topInset: (item.billboardName == .type ? topInset + TodayView.headerBand : 0),
                                  groundDim: HeroProtection.groundDim(heroStrength))
                    .frame(height: h, alignment: .bottom)
                heroTextScrim
                TrendingFocus(item: item,
                              owned: appModel.isInLibrary(item.id),
                              onOpen: { onOpenDetail(item.id, "trending/\(item.id)") },
                              onAdd: {
                                  appModel.addToLibrary(franchiseId: item.id, title: item.title,
                                                        isReleasing: item.isReleasing)
                              })
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .padding(.bottom, isAX ? ThemeSpace.x5 : ThemeSpace.x4)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heroCopyHeight = $0 }
            }
            .frame(height: h)
            .frame(maxWidth: .infinity)
            .mask(alignment: .bottom) {
                Rectangle().padding(.top, -2000).allowsHitTesting(false)
            }
            .overlay(alignment: .top) { topVeil(topInset: topInset) }
            .padding(.top, -topInset)
            .zoomSource("trending/\(item.id)")
            .task(id: art) {
                let resolved = await PaletteCache.shared.resolve(url: art, maxPixel: 360)
                heroTint = resolved
                heroLightness = PaletteCache.shared.lightness(for: art)
            }
            trendingShelf
        }
    }

    /// The rest of the chart, in the app's one shelf anatomy. The header walks to Search, where
    /// the whole chart is the browse grid.
    @ViewBuilder
    private var trendingShelf: some View {
        let items = Array(appModel.trending.dropFirst().prefix(9))
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
                SectionHeaderRow(Copy.Search.trendingNow, action: onAddShow)
                    .padding(.horizontal, ThemeMetrics.gutter)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: ThemeMetrics.shelfGap) {
                        ForEach(items) { item in
                            let caption = [item.source.kindWord, item.year.map(String.init)]
                                .compactMap { $0 }.joined(separator: " · ")
                            ShelfCard(title: item.title,
                                      caption: caption,
                                      poster: item.portraitArt,
                                      slot: .todayShelf,
                                      zoomID: "trending/\(item.id)") {
                                onOpenDetail(item.id, "trending/\(item.id)")
                            }
                            .accessibilityHint(Copy.Accessibility.opensTheShowHint)
                        }
                    }
                    .padding(.leading, ThemeMetrics.gutter)
                    .padding(.vertical, ThemeSpace.x1)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .padding(.top, ThemeSpace.x5)
        }
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

    /// The calm day. No hero, because nothing has happened — a calm screen that opens on a
    /// 440-pt slab of artwork is lying about how much there is to do.
    ///
    /// And no PLATE either. This used to render `EmptyState(.calmToday)`: a boxed card opening
    /// the app with "Nothing changed since you were last here" at display size — the day's first
    /// sentence describing an absence, in empty-state clothing on a populated screen, restating
    /// the exact event the Upcoming row 60 pt below already carries with artwork and an amber
    /// time. The calm open is one quiet, POSITIVE headline, and the Upcoming section owns the
    /// event. Only when nothing is dated anywhere does a supporting sentence say that instead.
    ///
    /// No glyph, on purpose (device capture, 30 Aug): an amber check disc in the wordmark's own
    /// column read as a second lockup — `[amber bookmark] Previously.` mirrored 40 pt above
    /// `[amber check] Caught up`, the exact twin-brand-object collision the account disc was
    /// quieted for. The WORD is the state; the above-the-fold amber budget stays on the fact
    /// ("Today at 8:30 PM" in the Upcoming row), and the headline sits a full breath below the
    /// masthead so it reads as the page's title, not a rider on the brand's.
    private var calmBlock: some View {
        VStack(alignment: .leading, spacing: ThemeSpace.x2) {
            // `heroTitle`, a full step above the 20-pt section headers under it: at `showTitleL`
            // (22) "New episode today" and "Upcoming" 60 pt below read as two headings of one
            // rank. This is the page's title; those are its sections.
            Text(calmHeadline)
                .type(ThemeType.heroTitle)
                .foregroundStyle(ThemeColor.textPrimary)
            if comingNext == nil {
                Text(Copy.Progress.noNewDates)
                    .type(ThemeType.metadata)
                    .foregroundStyle(ThemeColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, ThemeMetrics.gutter)
        .padding(.top, TodayView.headerBand + ThemeSpace.x8)
        .accessibilityElement(children: .combine)
    }

    // MARK: - The stack

    /// Actionable items, most actionable first: fresh unwatched episodes, then backlog.
    ///
    /// Within the fresh set, shows the user is WATCHING outrank the rest. `outNow` orders purely
    /// by recency, which handed the hero — the most prominent slot on the urgency surface — to a
    /// show the user had marked *completed* (Mushoku Tensei, 30 Aug) while five in-progress shows
    /// compressed into thumbnails below it. A shelved show keeps its place in the feed; it just
    /// doesn't headline over something the user actually said they are watching.
    private var liveItems: [Franchise] {
        #if DEBUG
        // `-calmDemo 1`: empty the stack so the calm open renders on a library that has
        // backlog — the same capture-pass convention as `-recapDemo 1`.
        if UserDefaults.standard.bool(forKey: "calmDemo") { return [] }
        #endif
        let fresh = appModel.outNow.sorted {
            let a = $0.effectiveStatus == .watching, b = $1.effectiveStatus == .watching
            if a != b { return a }
            // The airings-advanced recency, never `lastAiredSortKey`: that field is the
            // catalogue's and lags a sync, which put a days-old Slime drop over the Re:ZERO
            // episode that had struck 27 minutes earlier (user, 2 Sep).
            return ($0.lastAired(now: now) ?? 0) > ($1.lastAired(now: now) ?? 0)
        }
        return fresh + appModel.keepWatching
    }
    private var items: [Franchise] { pinned ?? liveItems }
    /// Only items the Focus grammar can actually describe reach the stack.
    private var actionable: [Franchise] { items.filter { kind(of: $0) != nil } }
    /// The calm day's hero: the show airing next, else the show you are closest to. Nothing to
    /// mark, so the card carries no action row — the art, the state and the moment, tap to open.
    ///
    /// The calm open used to be a headline on a wash ("New episode today" / "Caught up") over a
    /// row and a shelf, with 500 pt of canvas under them — a TV app that, on a quiet day, showed
    /// no television (user, 2 Sep: "utter trash"). Apple TV's Up Next and Netflix's home are
    /// never without a billboard; there is always a next thing, and it is always its art.
    private var calmHero: Franchise? {
        // A show you are caught up on is not a hero. The billboard is for something you can
        // press play on; the calendar is a tab.
        return nil
    }
    private var heroFranchise: Franchise? { actionable.first ?? calmHero }
    /// True when the show has an episode OUT NOW and unwatched.
    private func isFresh(_ f: Franchise) -> Bool {
        if case .fresh = kind(of: f)?.0 { return true }
        return false
    }
    /// "Next up" means episodes that are OUT NOW. A show you are part-way through with nothing
    /// airing is not "next up" — it is Continue watching, and letting it into the queue is what
    /// emptied that shelf when `queueCount` went to four (6 Sep).
    private var queue: [Franchise] {
        Array(actionable.dropFirst().filter(isFresh).prefix(queueCount))
    }
    private var stackIds: Set<String> {
        // What the stack ACTUALLY draws, so Continue watching can exclude exactly that and no
        // more (the count-based guess claimed four backlog shows the queue never showed).
        var ids = Set(queue.map(\.id))
        if let hero = heroFranchise { ids.insert(hero.id) }
        return ids
    }
    private var updateCount: Int { appModel.outNow.count }
    private var comingNext: Franchise? {
        guard let f = appModel.nextUp, !stackIds.contains(f.id) else { return nil }
        return f
    }

    /// The calm open's headline, chosen by the day. "Caught up" printed over an Upcoming row
    /// saying "Today at 8:30 PM" was the state shouting over the day's real fact (user, 30 Aug —
    /// the same state/fact inversion Detail's block fixed): when the next episode lands today,
    /// the headline frames the day and the row below keeps the specifics. `dayDiff` with the
    /// source's own anchor is the exact test the row's "Today" word comes from, so the two can
    /// never disagree.
    private var calmHeadline: String {
        if let f = comingNext, let at = f.nextAiring(now: appModel.now),
           Formatting.dayDiff(ts: at, now: appModel.now, anchor: f.source.timeAnchor) == 0 {
            return Copy.Progress.newEpisodeToday
        }
        return Copy.Progress.caughtUp
    }
    /// The Watching shelf's contents.
    ///
    /// `watchingShelf` is already narrowed by a "live claim" predicate, and this narrows it again
    /// against the stack — on a 9-show library that left ONE card in 340 pt of dead black under a
    /// "See all", while the loading skeleton four seconds earlier had promised four cards running
    /// off the right edge. A horizontal shelf that does not reach its trailing edge gives no reason
    /// to swipe and reads as artwork that failed to load. So: when the claim would leave fewer than
    /// three, drop it and fall back to everything the user is watching.
    private var shelf: [Franchise] {
        // CONTINUE WATCHING, not "Watching": shows you are part-way through that have nothing
        // airing — Game of Thrones, House of the Dragon, a finished run you stopped mid-season.
        // A show you are caught up on has nothing to continue and is not here; that is what made
        // the old shelf four posters captioned "Caught up" (user, 6 Sep).
        let shown = stackIds
        return Array(appModel.library.filter {
            $0.effectiveStatus == .watching && !shown.contains($0.id) && $0.continueBacklog > 0
        }
        .sorted { $0.continueBacklog > $1.continueBacklog }
        .prefix(TodayView.shelfCap))
    }

    /// Below three honest items there is no shelf to swipe — the same content becomes full-width
    /// rows under the same header, and "See all" goes away because there is nothing more to see.
    private var shelfIsList: Bool { isAX || shelf.count < 3 }
    private var showsViewAll: Bool { updateCount > queueCount + 1 }

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
        f?.billboardArt.url ?? recap?.beats.first?.cover
    }

    /// Whether the resolved hero art is a 2:3 COVER rather than a landscape asset — `billboardArt`'s
    /// own answer, so the composite path can never disagree with the URL it is given.
    private func heroArtIsPortrait(_ f: Franchise?) -> Bool {
        f?.billboardArt.portraitSource ?? true
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
                              ultraWide: f?.billboardArt.ultraWide ?? false,
                                  onArtLoaded: markArtReady,
                                  topInset: (f?.billboardName == .type ? topInset + TodayView.headerBand : 0),
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
                                 onContinue: { handoffRecap() },
                                 onDismiss: { dismissRecap() })
                        .transition(handoff)
                } else if let f {
                    heroOverlay(f)
                        .id(f.id)
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

    @ViewBuilder
    private func heroOverlay(_ f: Franchise) -> some View {
        if let (kind, part) = (f.id == calmHero?.id ? calmKind(of: f) : kind(of: f)) {
            let nextEpisode = part.progress + 1
            let behind: Int = {
                if case .fresh(let b) = kind { return b }
                if case .backlog(let l) = kind { return l }
                return 0
            }()
            let committed = committedEpisode != nil && pinned?.first?.id == f.id
            // The whole meta block advances in the SAME frame as the button's label. It used to
            // lag, so for the length of the confirmation the card said the episode was both next
            // and already watched.
            let copy: (eyebrow: String, fact: String, support: String?) = committed
                ? advanced(kind, f: f, part: part, from: committedEpisode ?? nextEpisode, behind: behind)
                : (eyebrow(kind, f: f, part: part),
                   factLine(kind, f: f, part: part),
                   supportLine(kind, f: f, part: part))
            // The season bar: watched over what there is to watch — aired-by-now for a fresh
            // drop, the available run for a backlog. It advances in the same frame as a mark
            // (`committedEpisode`), so the bar never lags the button that just moved it.
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
            HeroFocus(
                franchise: f,
                eyebrow: copy.eyebrow,
                moment: committed ? nil : momentText(kind, f: f, part: part),
                fact: copy.fact,
                support: copy.support,
                progress: bar?.ratio,
                progressSpoken: bar?.spoken,
                // No poster beside the copy any more. It existed because the old composite
                // backdrop was the cover blurred into ambience — the featured show had no face
                // (Mushoku, 30 Aug) — but the billboard hero shows the sharp cover whole as the
                // backdrop itself, so a 92-pt copy of it beside the title IS the recap's
                // postage-stamp case: the same asset twice in one frame.
                ctaEpisode: committed ? committedEpisode : (behind > 0 ? nextEpisode : nil),
                committed: committed,
                behind: behind,
                // Only a genuinely fresh drop earns the beat — never a backlog, never a wait.
                attention: { if case .fresh = kind, !committed { return true }; return false }(),
                interactive: !handoffInFlight,
                onOpen: { onOpenDetail(f.id, "focus/\(f.id)") },
                onMark: { mark(f) },
                onMarkThrough: { n in promptBatch(f, part: part, through: n) },
                // `markTarget(now:)`, not `progressCeiling`. The ceiling is `Int.max` for an ongoing
                // AniList season with no published episode count, and for every other releasing
                // season it is the season's SIZE — so "Mark all 6" would have written every unaired
                // episode too. The target is what has actually aired.
                onMarkAll: { promptBatch(f, part: part, through: part.markTarget(now: now)) }
            )
        }
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
        let hasQueue = showsHero && (!queue.isEmpty || showsViewAll)
        // The first block under a hero gets the hero's clearance; every block after it gets a
        // section gap. One rhythm, decided once, instead of 16 pt between everything.
        // x4 under a hero (review, 5 Sep: capsule → next header measured 66 pt; the shelf is
        // the hero's continuation, not a new room. The in-place receipt lives in this band.)
        let first = showsHero
            ? (isAX ? ThemeMetrics.heroClearance : ThemeSpace.x4)
            : ThemeMetrics.sectionGap
        let gap = ThemeMetrics.sectionGap
        // A section that ENDS in a `MediaRow` has already spent `rowOwnInset` below its last row.
        let gapAfterRow = gap - TodayView.rowOwnInset
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
            // No "Upcoming" block: a future airing is Schedule's, and Today carries only what
            // can be acted on now (6 Sep).
            let hasUpNext = hasQueue
            if hasUpNext {
                if isAX {
                    // Rows at accessibility sizes: a 16:9 card gives a grown caption four words.
                    queueSection.padding(.top, strip || notice ? gap : first)
                } else {
                    upNextShelf(upcoming: [])
                        .id("today.upnext")
                        // After the recap's line, x5: the line belongs to the hero above it.
                        .padding(.top, strip ? ThemeSpace.x5 : (notice ? gap : first))
                }
            }
            if !shelf.isEmpty {
                // A full section gap after the card shelf; after rows, the gap minus what the
                // last row already spent.
                let top: CGFloat = hasUpNext ? (isAX ? gapAfterRow : gap) : (strip || notice ? gap : first)
                watchingShelf
                    .id("today.watching")
                    .padding(.top, top)
            }
        }
        .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: recapMode)
    }

    // MARK: - Queue

    /// The rest of what is waiting.
    ///
    /// It used to sit unlabelled on the canvas between a hero and a labelled `COMING NEXT` while
    /// every other block announced itself — and it vanished entirely in the committed state, so
    /// the screen's section structure changed shape between frames.
    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // `Copy.Label.nextUp` — the one "next" rule. "UP NEXT" and "COMING NEXT" differed by a
            // single word, in the same token, 60 pt apart, with no rule anyone could infer; the
            // not-yet-aired block below is now "Upcoming" so there is never a second "next" on one
            // screen. This is the specific episode you can watch right now.
            SectionHeaderRow(Copy.Label.nextUp)
                .padding(.horizontal, ThemeMetrics.gutter)
            // The rhythm is built by the CONTAINER, not by a stack spacing that fights the rows'
            // own padding: measured, label-bottom to first content was 31 pt against a `labelGap`
            // of 10, because `SectionHeaderRow` draws 12 pt outside its layout rect and `MediaRow`
            // adds its own vertical padding on top of the spacing.
            queueRows.padding(.top, ThemeMetrics.labelGap - TodayView.rowOwnInset)
        }
    }

    private var queueRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(queue.enumerated()), id: \.element.id) { index, f in
                MediaRow(title: f.title,
                         meta: queueMeta(f),
                         lead: queueLead(f),
                         poster: f.portraitArt,
                         // Today's purpose-built 52×78 slot keeps logo-led covers recognisable
                         // without borrowing the catalogue's 60×90 / 100-pt row. Accessibility
                         // sizes keep the larger slot while text expands.
                         slot: isAX ? .row : .todayQueue,
                         // No chevron: this row has a trailing CONTROL. A disclosure indicator and
                         // a mark ring in the same column is two trailing affordances on one row.
                         chevron: false,
                         separator: index < queue.count - 1 || showsViewAll,
                         hint: TodayCopy.opensTheShow,
                         zoomID: "queue/\(f.id)",
                         trailing: { queueMark(f) }) {
                    onOpenDetail(f.id, "queue/\(f.id)")
                }
                // The same long-press menu every Library card carries. Today's rows had none.
                .franchiseQuickActions(f, appModel: appModel)
                .padding(.horizontal, ThemeMetrics.gutter)
                .transition(handoff)
            }
            if showsViewAll {
                Button {
                    (onViewAllUpdates ?? onSeeAllWatching)()
                } label: {
                    HStack(spacing: 6) {
                        Text(Copy.Action.viewAllUpdates(updateCount))
                        // 13 semibold — the one size `chevron.forward` is drawn at anywhere
                        // (`MediaRow`, the recap rows); this was an 11 for no reason.
                        Image(systemName: "chevron.forward").font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(InlineLinkButtonStyle())
                // The style holds its 44-pt target with leading padding so it can sit at the
                // trailing end of a header row; pulled back here so the word starts on the gutter.
                .padding(.leading, ThemeMetrics.gutter - 12)
            }
        }
        .animation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion), value: queue.map(\.id))
    }

    /// The queue row's own mark control.
    ///
    /// The comment above this section called Today "a queue you act on" while the rows carried no
    /// action at all: clearing an evening was one tap for the hero and four taps per row for
    /// everything under it (row → Detail → season → episode). It is the same `MarkRing` Schedule's
    /// rows use, so the gesture, the target and the drawn check are the app's one mark, not a
    /// second dialect. Rows with nothing to mark (a show that is only waiting) get no control.
    @ViewBuilder
    private func queueMark(_ f: Franchise) -> some View {
        if let (kind, part) = kind(of: f), queueIsMarkable(kind) {
            // `marked` follows the row's own committed set, as Schedule's rows do: the ring
            // was hard-wired to `false`, so the app's signature drawn check never appeared on
            // one of its two most-tapped mark controls, and a second tap in the same beat
            // marked a second episode.
            MarkRing(marked: committedQueue.contains(f.id),
                     style: .quiet,
                     episode: part.progress + 1,
                     label: "\(Copy.Action.markAsWatched), \(watchLabel(f, part: part, episode: part.progress + 1)) of \(f.title)") {
                markQueueRow(f)
            }
        }
    }

    private func queueIsMarkable(_ kind: FocusKind) -> Bool {
        switch kind {
        case .fresh, .backlog: return true
        case .caughtUp, .waiting: return false
        }
    }

    /// One transaction, one haptic (fired inside the write), one toast. Unlike the hero there is no
    /// card handing over here, so the toast is presented immediately rather than deferred.
    private func markQueueRow(_ f: Franchise) {
        guard !committedQueue.contains(f.id) else { return }
        guard let undo = appModel.markNext(franchiseId: f.id) else { return }
        withAnimation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion)) {
            _ = committedQueue.insert(f.id)
        }
        // In place, under the card's caption.
        appModel.presentUndo(undo.placed(at: ReceiptHost.todayQueue(f.id)))
        Announce.status(Copy.Progress.episodeWatched(undo.episode))
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            committedQueue.remove(f.id)
        }
    }

    // One grammar for the two-colour row, decided once and obeyed by every row on this screen:
    //
    //   amber `rowMetaLead`  the forward-looking TIME — "Aired yesterday", "Tomorrow at 8:30 PM"
    //   grey  `rowMeta`      the EPISODE IDENTITY and its counts — "Season 7 · Episode 5"
    //
    // The shipped rows swapped those two meanings between adjacent blocks (queue: amber episode,
    // grey count; Coming next four lines below: amber time, grey episode), so the reader had to
    // re-learn the code halfway down the screen.

    /// A queue row's forward-looking time, in accent.
    private func queueLead(_ f: Franchise) -> String? {
        guard let (kind, part) = kind(of: f) else { return nil }
        switch kind {
        case .fresh:
            // Amber is for what is live: today's drop. An older one is a plain row — its ring
            // already names the episode, and "Aired 28 Aug" in accent spent the colour on a
            // fact that is neither next nor now.
            guard let last = part.lastAired(now: now, anchor: f.timeAnchor),
                  Formatting.dayDiff(ts: last, now: now, anchor: f.timeAnchor) == 0 else { return nil }
            return TemporalCopy.aired(at: last, now: now, source: f.source)
        case .backlog: return nil
        case .caughtUp: return nil
        case .waiting(let at): return TemporalCopy.airs(at: at, now: now, source: f.source)
        }
    }

    /// A queue row's episode identity, in neutral ink.
    private func queueMeta(_ f: Franchise) -> String? {
        guard let (kind, part) = kind(of: f) else { return nil }
        let ep = watchLabel(f, part: part, episode: part.progress + 1)
        // The row DROPS a fact rather than wrapping one.
        //
        // "Season 7 · Episode 5 · 3 / episodes left" put a numeral on one line and its noun on the
        // next, on the first row of the first section. The direction's own rule is to drop a fact
        // when the line will not hold, and the count is the droppable one: the episode identity is
        // what the row is for, the hero's eyebrow carries the count when it matters, and the row's
        // own `MarkRing` is the action. Always at accessibility sizes; at default sizes only when
        // the identity is already long enough to fill the line on its own ("OVA 2: No Regrets ·
        // Episode 1" is 28 characters before the count is even appended).
        // 13, not 22: at 22 a two-season identity ("Season 2 · Episode 2", 20 chars) still took
        // the count and the assembled line overran the row's ~240 pt, wrapping "… · 11 /
        // episodes left" mid-phrase — the exact defect this heuristic exists to prevent. 13
        // admits the single-part form ("Episode 2") and nothing longer.
        let roomForCount = !isAX && ep.count <= 13
        switch kind {
        case .fresh(let behind):
            return behind > 1 && roomForCount ? "\(ep) · \(Copy.Progress.behind(behind))" : ep
        case .backlog(let left):
            return left > 1 && roomForCount ? "\(ep) · \(Copy.Progress.left(left))" : ep
        case .caughtUp: return Copy.Progress.caughtUp
        case .waiting:
            return watchLabel(f, part: part, episode: part.nextEpisodeNumber ?? part.airedEpisodes + 1)
        }
    }

    // MARK: - Coming next


    // MARK: - Up next (the shelf)

    /// One card on the Up next shelf: a show, the episode the card is about, and the focus
    /// grammar's own kind — so the card knows whether it can be marked.
    private struct UpNextItem: Identifiable {
        let franchise: Franchise
        let kind: FocusKind
        let part: FranchisePart
        var id: String { franchise.id }
    }

    /// Everything waiting for you, as television: one shelf of 16:9 cards under the billboard —
    /// the rest of the queue first (episodes you can watch now, each with its mark ring), then
    /// what is coming (the moment as a pill on the art). Apple TV's Up Next row, in the Library's
    /// Continue-card geometry: four fifths of the content width, the next card peeking.
    ///
    /// It replaces two vertical lists (4 Sep): a "Next up" of 52×78 poster rows and an
    /// "Upcoming" of 44×66 rows with an amber second line and a two-line grey subtitle — a
    /// settings table under a billboard, on the most-viewed screen in the app ("This UI won't
    /// cut it", user). The header says `nextUp` while a card can be marked and `upcoming` when
    /// nothing has aired, so the one "next" rule holds: "Next up" only ever heads something you
    /// can watch right now. At accessibility sizes the rows stay (`queueSection` /
    /// `upcomingSection`): a 16:9 card gives a grown caption four words.
    @ViewBuilder
    private func upNextShelf(upcoming: [Franchise]) -> some View {
        let queued: [UpNextItem] = queue.compactMap { f in
            guard let (kind, part) = kind(of: f) else { return nil }
            return UpNextItem(franchise: f, kind: kind, part: part)
        }
        let coming: [UpNextItem] = upcoming.compactMap { f in
            guard let part = f.releasingPart, let at = f.nextAiring(now: now) else { return nil }
            return UpNextItem(franchise: f, kind: .waiting(at: at), part: part)
        }
        let cards = queued + coming
        let markable = cards.contains { queueIsMarkable($0.kind) }
        let viewAll: (() -> Void)? = showsViewAll ? { (onViewAllUpdates ?? onSeeAllWatching)() } : nil
        VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
            SectionHeaderRow(markable ? Copy.Label.nextUp : Copy.Label.upcoming,
                             actionLabel: showsViewAll ? Copy.Action.viewAllUpdates(updateCount) : nil,
                             action: viewAll)
                .padding(.horizontal, ThemeMetrics.gutter)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: ThemeMetrics.shelfGap) {
                    ForEach(cards) { item in
                        upNextCard(item)
                            // A peek is an affordance for a NEXT card; a shelf of one runs
                            // gutter to gutter (review, 5 Sep).
                            .containerRelativeFrame(.horizontal, count: 5, span: cards.count == 1 ? 5 : 4,
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

    /// One card: the show's wide art with the moment on it, the episode named beneath, the mark
    /// ring beside that while there is something to mark — Schedule's airing card at shelf
    /// width, on the Library's Continue-card frame (`ProgressBanner`), with the season bar on the
    /// art for a show in progress. The card opens the show; the ring is its own control.
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
                    .contentShape(Rectangle())
            }
            .buttonStyle(OverArtPressStyle())
            .accessibilityHint(TodayCopy.opensTheShow)
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
                        if let caption {
                            // The rows' two-colour grammar: a forward-looking TIME is amber
                            // (`rowMetaLead`), an identity or a count is grey.
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
                .accessibilityHint(TodayCopy.opensTheShow)
                if queueIsMarkable(item.kind) {
                    MarkRing(marked: committedQueue.contains(f.id),
                             style: .quiet,
                             episode: part.progress + 1,
                             label: "\(Copy.Action.markAsWatched), \(watchLabel(f, part: part, episode: part.progress + 1)) of \(f.title)") {
                        markQueueRow(f)
                    }
                }
            }
            // The ring's receipt, in place under the caption.
            ReceiptLine(host: ReceiptHost.todayQueue(f.id), compact: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel([f.title, episode, caption?.text].compactMap { $0 }.joined(separator: ", "))
    }

    /// The episode the card is about: the next unwatched one, or the one coming.
    private func upNextEpisode(_ item: UpNextItem) -> Int? {
        let part = item.part
        switch item.kind {
        case .waiting: return part.nextEpisodeNumber ?? part.airedEpisodes + 1
        case .fresh, .backlog: return part.progress + 1
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
    /// ("Aired 2h ago"). Else the count in grey ("6 episodes left", "3 episodes behind" — Today is
    /// the urgency room), else the season on a multi-part show, else nothing. (The card used to
    /// wear the moment as a SECOND pill on the art over a caption that said only "Season 5" —
    /// two chips and a fragment, the busiest object on the screen.)
    private func upNextCaption(_ item: UpNextItem) -> (text: String, lead: Bool)? {
        let f = item.franchise, part = item.part
        let season: String? = {
            let label = part.canonicalLabel
            return f.parts.count == 1 || label.isEmpty ? nil : label
        }()
        switch item.kind {
        case .waiting(let at):
            return (TemporalCopy.airs(at: at, now: now, source: f.source), true)
        case .fresh(let behind):
            if let last = part.lastAired(now: now, anchor: f.timeAnchor),
               Formatting.dayDiff(ts: last, now: now, anchor: f.timeAnchor) == 0 {
                return (TemporalCopy.aired(at: last, now: now, source: f.source), true)
            }
            if behind > 1 { return (Copy.Progress.behind(behind), false) }
            return season.map { ($0, false) }
        case .backlog(let left):
            if left > 1 { return (Copy.Progress.left(left), false) }
            return season.map { ($0, false) }
        case .caughtUp:
            return (Copy.Progress.caughtUp, false)
        }
    }

    // MARK: - Watching shelf

    @ViewBuilder
    private var watchingShelf: some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
            watchingHeader
                .padding(.horizontal, ThemeMetrics.gutter)
            if shelfIsList {
                axWatchingList
            } else {
                shelfScroller
            }
        }
    }

    /// The shared header. Its chevron is tertiary ink, so it no longer competes with the toast's
    /// Undo the way the amber-adjacent "See all" link did — no special case needed.
    private var watchingHeader: some View {
        SectionHeaderRow(Copy.Label.continueWatching,
                         actionLabel: shelfIsList ? nil : Copy.Action.seeAll,
                         action: shelfIsList ? nil : onSeeAllWatching)
    }

    /// Rows instead of a shelf, in the two cases where a shelf is the wrong container: at
    /// accessibility sizes a 112-pt card gives a show's name four characters before it truncates,
    /// and below three items a scroller has nothing to scroll.
    private var axWatchingList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shelf.enumerated()), id: \.element.id) { index, f in
                let caption = shelfCaption(f)
                MediaRow(title: f.title,
                         meta: caption.flatMap { $0.lead ? nil : $0.text },
                         lead: caption.flatMap { $0.lead ? $0.text : nil },
                         poster: f.portraitArt,
                         slot: .queue,
                         chevron: false,
                         separator: index < shelf.count - 1,
                         // A distinct id from the poster shelf's: the same franchise must never
                         // register two zoom sources in one namespace, even when only one of the
                         // two layouts is mounted at a time.
                         zoomID: "shelfrow/\(f.id)") {
                    onOpenDetail(f.id, "shelfrow/\(f.id)")
                }
                .franchiseQuickActions(f, appModel: appModel)
                .padding(.horizontal, ThemeMetrics.gutter)
            }
        }
    }

    private var shelfScroller: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: ThemeMetrics.shelfGap) {
                ForEach(shelf) { f in
                    let caption = shelfCaption(f)
                    ShelfCard(title: f.title,
                              // The captions are this shelf's load-bearing facts; a fact column
                              // with three baselines cannot be scanned (review i3 — challenging
                              // the 24 Aug rule for this shelf only).
                              caption: caption?.text,
                              // Same grammar as the rows above: a caption that is a TIME or a next
                              // step is amber. "Wed 6:30 PM" was `textSecondary` here while the
                              // identical class of fact 150 pt above was accent — and the
                              // `shelfCaption` token's own note ("accent when it is a next step")
                              // was already honoured by Library's RETURNING shelf.
                              captionIsLead: caption?.lead ?? false,
                              // The season is ON AIR. On a Continue-watching shelf this is the
                              // difference between "I can finish this whenever" and "this is
                              // still running and I am behind" — a poster states neither.
                              airing: f.isReleasing,
                              airingFresh: isFresh(f),
                              poster: f.portraitArt,
                              slot: .todayShelf,
                              zoomID: "shelf/\(f.id)") {
                        onOpenDetail(f.id, "shelf/\(f.id)")
                    }
                    .franchiseQuickActions(f, appModel: appModel)
                }
            }
            .padding(.leading, ThemeMetrics.gutter)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        // Art may run off the trailing edge; TYPE may not. See `shelfScroller`.
        .shelfScroller()
    }

    /// A shelf caption and whether it is a forward-looking fact (amber) or an identity/state fact
    /// (grey) — the same two-colour grammar the rows above obey.
    ///
    /// Every card gets one. A dormant show reached the shelf only because the honest-count fallback
    /// widened it, and three captionless cards beside one that has a caption is worse than saying
    /// the true, quiet thing.
    private func shelfCaption(_ f: Franchise) -> (text: String, lead: Bool)? {
        switch appModel.shelfState(of: f) {
        case .newEpisode:
            // The count the badge above carries (review, 5 Sep).
            let behind = f.releasingPart.map { $0.behind(now: now, anchor: f.timeAnchor) } ?? 0
            // Amber only while the drop is today's fact (review i4): the Up next card prints the
            // same count in grey, and one screen may not read one number two ways.
            let struck = f.lastAired(now: now).map { Formatting.dayDiff(ts: $0, now: now, anchor: f.timeAnchor) == 0 } ?? false
            return behind > 1 ? (Copy.Progress.behind(behind), struck) : (Copy.Label.newEpisode, true)
        case .backlog:
            guard let p = f.resumePart else { return nil }
            return (Copy.Progress.episodeNext(p.progress + 1), false)
        case .airingWait:
            if let at = f.nextAiring(now: now) {
                return (TemporalCopy.airsCompact(at: at, now: now, source: f.source), true)
            }
            return (Copy.Progress.caughtUp, false)
        case .premiereSoon:
            return (TemporalCopy.returns(at: appModel.nextPremiere(of: f), now: now, source: f.source), true)
        case nil: return (Copy.Progress.caughtUp, false)
        }
    }

    // MARK: - Focus grammar

    private enum FocusKind { case fresh(behind: Int), backlog(left: Int), caughtUp, waiting(at: Int64) }

    private func kind(of f: Franchise) -> (FocusKind, FranchisePart)? {
        // Evaluated on the object (not the live feed) so a pinned snapshot keeps its wording while
        // the hero shows its result.
        if let part = f.releasingPart {
            // Airings-derived (`behind` / `lastAired`), never the catalogue's hourly counts: the
            // episode that struck a minute ago is the whole reason this screen exists.
            let behind = part.behind(now: now, anchor: f.timeAnchor)
            if now - (part.lastAired(now: now, anchor: f.timeAnchor) ?? 0) <= AppModel.outNowWindow,
               behind > 0 || appModel.justCaught.contains(f.id) {
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
    private func eyebrow(_ kind: FocusKind, f: Franchise, part: FranchisePart) -> String {
        switch kind {
        case .fresh(let behind):
            // The recency of today's drop is the MOMENT row's ("Aired 29 min ago" — the news
            // the person opened the app for, user 2 Sep); the eyebrow says the STATE: the count
            // while there is one, else that this is new. An older drop with a backlog leads
            // with the count; an older single one with its day.
            let last = part.lastAired(now: now, anchor: f.timeAnchor)
            if let last, Formatting.dayDiff(ts: last, now: now, anchor: f.timeAnchor) == 0 {
                return behind > 1 ? Copy.Progress.behind(behind) : Copy.Label.newEpisode
            }
            if behind > 1 { return Copy.Progress.behind(behind) }
            if let last { return TemporalCopy.aired(at: last, now: now, source: f.source) }
            return Copy.Label.newEpisode
        case .backlog(let left):
            return left > 1 ? Copy.Progress.left(left) : Copy.Progress.lastEpisodeOfTheSeason
        case .caughtUp: return Copy.Progress.caughtUp
        // The state only — "NEW EPISODE". The moment ("Today at 7:30 PM · in 1h 24m") is the
        // `HeroMoment` row under the title, with its own instrument; said here as well it was
        // either a capsule over a 34-pt amber clock (2 Sep) or a small-caps sentence that
        // treated the app's one delight "like just another thing" (both 4 Sep, user).
        case .waiting(let at):
            // A badge states a fact that is TRUE NOW: today's airing keeps the delight; a later
            // one is "CAUGHT UP · Wednesday at 6:30 PM · …", exactly the show page's block
            // (review i2: "NEW EPISODE" over a Wednesday, on a Saturday).
            let a = Formatting.localParts(at, anchor: f.timeAnchor), n = Formatting.localParts(now, anchor: f.timeAnchor)
            return (a.y, a.mo, a.d) == (n.y, n.mo, n.d) ? Copy.Label.newEpisode : Copy.Progress.caughtUp
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
            guard behind == 1, let last = part.lastAired(now: now, anchor: f.timeAnchor),
                  Formatting.dayDiff(ts: last, now: now, anchor: f.timeAnchor) == 0 else { return nil }
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
    private func supportLine(_ kind: FocusKind, f: Franchise, part: FranchisePart) -> String? {
        switch kind {
        case .fresh(let behind):
            // The drop, named: with a backlog the moment cannot lead the line (it would read as
            // the next episode's), so it says which episode it is about — the same builder the
            // committed frame uses for "Episode 20 airs Friday".
            guard behind > 1, let last = part.lastAired(now: now, anchor: f.timeAnchor),
                  Formatting.dayDiff(ts: last, now: now, anchor: f.timeAnchor) == 0 else { return nil }
            return Copy.Progress.dropAired(episode: part.airedByNow(now: now, anchor: f.timeAnchor),
                                           when: TemporalCopy.aired(at: last, now: now, source: f.source))
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
                          behind: Int) -> (eyebrow: String, fact: String, support: String?) {
        let left = max(0, behind - 1)
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

            // The Up next shelf's shape: a header and two 16:9 cards with their captions, at the
            // shelf's own card width (four fifths of the content width on a 393-pt screen) —
            // rows at accessibility sizes, as the loaded screen draws them.
            VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
                SkeletonLine(width: 84, height: 19)
                    .padding(.horizontal, ThemeMetrics.gutter)
                if isAX {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<2, id: \.self) { _ in
                            SkeletonRow(poster: PosterSize.row.size, lines: [180, 110],
                                        posterRadius: PosterSize.row.radius)
                        }
                    }
                    .padding(.horizontal, ThemeMetrics.gutter)
                } else {
                    // A scroller, like the shelf it stands in for: two 286-pt cards in a plain
                    // stack are wider than the screen and would centre everything above them.
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: ThemeMetrics.shelfGap) {
                            ForEach(0..<2, id: \.self) { _ in
                                VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                                    SkeletonPoster(width: 286, height: 161, radius: ThemeRadius.card)
                                    SkeletonLine(width: 180, height: 14)
                                    SkeletonLine(width: 110, height: 12)
                                }
                            }
                        }
                        .padding(.horizontal, ThemeMetrics.gutter)
                    }
                    .scrollDisabled(true)
                    .scrollIndicators(.hidden)
                }
            }
            .padding(.top, isAX ? ThemeMetrics.heroClearance : ThemeSpace.x5)

            VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
                SkeletonLine(width: 84, height: 10)
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

    private func mark(_ f: Franchise) {
        // `handoffInFlight` covers the window `committedEpisode` cannot: the 460 ms during which
        // the NEXT show's card is fading in with a live Mark button on it.
        guard committedEpisode == nil, !handoffInFlight else { return }
        let snapshot = items
        guard let undo = appModel.markNext(franchiseId: f.id) else { return }
        // The receipt lands IN PLACE, under this capsule (`ReceiptLine` in `HeroFocus`).
        settleHero(snapshot: snapshot, undo: undo.placed(at: ReceiptHost.todayHero(f.id)))
    }

    /// The committed frame, shared by the single mark and the batch behind the chevron: 650 ms
    /// of the drawn check and the advanced bar on the SAME card, then the handoff to the next
    /// show, then the toast. The batch used to skip all of it — confirm six episodes and the
    /// hero was simply someone else, with no acknowledgement that anything had been recorded.
    private func settleHero(snapshot: [Franchise], undo: UndoState) {
        pinned = snapshot
        pendingUndo = undo
        // The receipt lands at the TAP (interactive review: it used to arrive 1.4 s later, 0.4 s
        // after the capsule had flipped back to amber and looked unacted). The committed frame
        // and the line overlap for 650 ms — the signature and its receipt, together.
        appModel.presentUndo(undo)
        handoffInFlight = true
        withAnimation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion)) {
            committedEpisode = undo.episode
        }
        Announce.status(Copy.Progress.episodeWatched(undo.episode))
        clearRecapStrip()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            let settle = ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)
            withAnimation(settle) {
                pinned = nil
                committedEpisode = nil
            } completion: {
                pendingUndo = nil
                // The incoming card's insertion is delayed by `handoff` and then runs `uiSettle`;
                // it is not tappable until it has actually arrived.
                Task { @MainActor in
                    if !reduceMotion { try? await Task.sleep(for: .milliseconds(300)) }
                    handoffInFlight = false
                }
            }
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
            message: "\(f.title) · \(part.label). \(Copy.Confirm.batchMarkMessage(from: part.progress, to: through))",
            confirm: Copy.Confirm.batchMarkConfirm(count),
            perform: {
                guard committedEpisode == nil, !handoffInFlight else { return }
                let snapshot = items
                guard let undo = appModel.markThrough(franchiseId: f.id, mediaId: part.mediaId,
                                                      episode: through, present: false) else { return }
                settleHero(snapshot: snapshot, undo: undo.placed(at: ReceiptHost.todayHero(f.id)))
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
        return f.parts.count > 1 ? "\(part.canonicalLabel) \u{00B7} \(range)" : range
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
        } completion: {
            persistRecapAcknowledgement()
        }
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
        } completion: {
            persistRecapAcknowledgement()
        }
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
        let aired = recap.beats.reduce(0) { acc, b in
            if case .episodesAired(let n, _) = b.kind { return acc + n } else { return acc }
        }
        let since = sinceFragment(recap.since)
        // No numeral: the badge 260 pt above already carries one, and "3 episodes aired" under
        // "3 EPISODES BEHIND" was the same number twice (review, 5 Sep).
        if aired > 0 { return "What you missed \(since)" }
        return "\(Copy.updates(recap.beats.count + recap.hiddenBeatCount)) \(since)"
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

// MARK: - Hero focus

/// The one thing to watch, laid on its own artwork — a billboard LOCKUP (4 Sep, direction B of
/// three photographed on the simulator).
///
/// Reading order, top to bottom: the STATE as a filled `HeroBadge` ("NEW EPISODE", "4 EPISODES
/// BEHIND"), the show's name at `displayXL` — THE headline, always — then ONE line: the moment
/// and the episode ("Today at 7:30 PM · Season 4 · Episode 21", "Aired 29 min ago · Season 4 ·
/// Episode 12", or the episode alone for a backlog), the season bar, and one primary action when
/// there is something to mark. Prime Video's and Disney+'s grammar: a badge is the signal, the
/// size goes to the title, and the rest is one line.
///
/// Before, in one day (4 Sep): the 2–3 Sep "slate" — a scrimmed capsule pill over the CLOCK at
/// `displayXL` in amber, the show a size down — read on the device as a badge and a clock
/// widget over a black void ("like a 3rd grade app"); a bare small-caps eyebrow with a 20-pt
/// live moment row under the title read as "text heavy and cognitively overloaded". Three rows,
/// one of them a ground, is the answer the user picked.
private struct HeroFocus: View {
    let franchise: Franchise
    /// The badge's text: the state.
    let eyebrow: String
    /// The WHEN, folded into the one line ahead of the episode: "Today at 7:30 PM", "Aired 29
    /// min ago", date-only "Friday". Nil for a state with no live moment (a backlog, an older
    /// drop).
    var moment: String? = nil
    let fact: String
    let support: String?
    /// Where you are in the season, 0–1, drawn as the one `ProgressBar` under the fact — never
    /// "4 episodes behind" in words (the 2 Sep prose rule). Nil when there is nothing to show:
    /// nothing watched yet, or everything.
    var progress: Double? = nil
    /// What the bar says to VoiceOver ("4 episodes behind").
    var progressSpoken: String? = nil
    let ctaEpisode: Int?
    let committed: Bool
    let behind: Int
    /// A drop is out now and unwatched — the badge takes the finite entrance beat.
    var attention: Bool = false
    /// False while a mark is handing over to the next show: the incoming card may not be tapped
    /// until it has arrived.
    var interactive: Bool = true
    let onOpen: () -> Void
    let onMark: () -> Void
    let onMarkThrough: (Int) -> Void
    let onMarkAll: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    private var isAX: Bool { typeSize.isAccessibilitySize }

    /// The SHARED lockup (`HeroLockup`, 5 Sep — the show page draws the same view), fed Today's
    /// grammar: `displayTitle` as every row and shelf names the show ("Re:ZERO", not the full
    /// title across two lines), `displayXL` with a scale floor so the hero may never ellipsize the
    /// one name the screen exists to show, and ONE action — "Details" beside it duplicated the
    /// block's own tap; Apple TV's and Netflix's second button is a different verb, never "open
    /// what you are already looking at".
    var body: some View {
        HeroLockup(badge: eyebrow,
                   badgeAttention: attention,
                   title: franchise.displayTitle,
                   name: franchise.billboardName,
                   lineLimit: isAX ? 3 : 2,
                   moment: moment,
                   fact: fact,
                   support: support,
                   progress: progress,
                   progressSpoken: progressSpoken,
                   onOpen: onOpen,
                   interactive: interactive,
                   receiptHost: ReceiptHost.todayHero(franchise.id),
                   accessory: { EmptyView() }) {
            if let ctaEpisode {
                MarkSplitButton(episode: ctaEpisode,
                                committed: committed,
                                behind: behind,
                                title: franchise.title,
                                onMark: onMark,
                                onMarkThrough: onMarkThrough,
                                onMarkAll: onMarkAll)
            }
        }
    }
}

// MARK: - Trending focus

/// The empty account's slate on the billboard: pill → show → identity, and one capsule. The same
/// anatomy as `HeroFocus` minus the episode, because there is no episode yet — only a show.
private struct TrendingFocus: View {
    let item: FranchiseSummary
    let owned: Bool
    let onOpen: () -> Void
    let onAdd: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    private var isAX: Bool { typeSize.isAccessibilitySize }

    private var identity: String {
        [item.source.kindWord, item.year.map(String.init)].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpen) {
                // Centred, as `HeroLockup` is (5 Sep): one billboard axis.
                VStack(alignment: .center, spacing: 0) {
                    HeroBadge(text: Copy.Label.trending)
                    HeroTitle(text: item.title.shelfShortened, name: item.billboardName, lineLimit: isAX ? 3 : 2)
                        .padding(.top, ThemeSpace.x3)
                    Text(identity)
                        .type(ThemeType.heroMeta)
                        .foregroundStyle(ThemeColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, ThemeSpace.x1)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(OverArtPressStyle())
            .shadow(.art)
            .accessibilityElement(children: .combine)
            .accessibilityHint(Copy.Accessibility.opensTheShowHint)

            Button(action: onAdd) {
                Text(owned ? Copy.Search.inLibrary : Copy.Search.addToLibrary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle2())
            .disabled(owned)
            .padding(.top, isAX ? ThemeSpace.x5 : ThemeSpace.x4)
        }
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
                    Text(beat.title)
                        .type(ThemeType.rowTitle)
                        // BOTH rows at `textPrimary`. The second used to be `textSecondary`, so it
                        // read as disabled; the aired-vs-upcoming distinction lives in the meta line.
                        .foregroundStyle(ThemeColor.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: ThemeSpace.x2)
                    if i == 0 {
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ThemeColor.textDisabled)
                            .accessibilityHidden(true)
                    }
                }
                Text(beatLabel(beat))
                    .type(ThemeType.rowMeta)
                    .foregroundStyle(ThemeColor.textSecondary)
                    .lineLimit(1)
            }
        }
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed || reduceMotion ? 0 : 6)
        .animation(ThemeMotion.pick(ThemeMotion.uiReveal, reduceMotion: reduceMotion)
            .delay(reduceMotion ? 0 : 0.12 * Double(i + 1)), value: revealed)
    }

    private var moreLine: some View {
        Text(TodayCopy.andMore(digest.hiddenBeatCount))
            .type(ThemeType.metadata)
            .foregroundStyle(ThemeColor.textTertiary)
            .opacity(revealed ? 1 : 0)
            .animation(ThemeMotion.pick(ThemeMotion.uiReveal, reduceMotion: reduceMotion)
                .delay(reduceMotion ? 0 : 0.12 * Double(digest.beats.count + 1)), value: revealed)
    }

    /// "2 updates since 18 Aug" — what the card is, in the hero's voice.
    private var headline: String {
        let aired = digest.beats.reduce(0) { acc, b in
            if case .episodesAired(let n, _) = b.kind { return acc + n } else { return acc }
        }
        let total = digest.beats.count + digest.hiddenBeatCount
        return aired > 0 ? "\(Copy.episodes(aired)) aired" : "\(Copy.updates(total)) waiting"
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
            HStack(alignment: .top) {
                HeroBadge(text: TodayCopy.whileYouWereAway)
                Spacer(minLength: ThemeSpace.x3)
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
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ThemeSpace.x3)
            // "Since 23 Jul" named a date with no anchor — since what? The last visit is what the
            // digest is actually built from, so the card says so. The strip below stays terse.
            Text(TodayCopy.sinceYourLastVisit(TemporalCopy.since(digest.since, now: now)))
                .type(ThemeType.metadata)
                .foregroundStyle(ThemeColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
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
                        beatRow(beat, index: i)
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel(digest.beats.map { "\($0.title), \(beatLabel($0))" }.joined(separator: ". "))
            .accessibilityHint("Continues to what is next")
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
    let scroll: ScrollOffset
    let carriesBase: Bool
    let heroFranchise: Franchise?
    @Binding var showProfile: Bool

    @Environment(AuthManager.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var carriesTitle: Bool { carriesBase && scroll.heroCopyUnderBand }

    var body: some View {
        let docked = heroFranchise.flatMap { FranchiseDetailView.dockedName($0, budget: 28) }
        HStack(alignment: .center) {
            ZStack(alignment: .leading) {
                // Fit, shortened, or nothing — the wordmark stays (review i2).
                Wordmark()
                    .opacity(carriesTitle && docked != nil ? 0 : 1)
                if let title = docked {
                    Text(title)
                        .type(ThemeType.showTitleM)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .shadow(.art)
                        .opacity(carriesTitle ? 1 : 0)
                        .accessibilityHidden(!carriesTitle)
                }
            }
            .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: carriesTitle)
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
        .padding(.trailing, ThemeSpace.x2)
        .frame(height: TodayView.headerBand)
    }
}
