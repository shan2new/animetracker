import SwiftUI

/// Two strings this screen needs that the shared copy table does not carry yet: the hero's
/// secondary action and the primary's committed label. Both are filed as an exact diff against
/// `Copy.swift` (a design-system file this track does not own); they live here, named and in one
/// place, until that lands — never inline at a call site.
private enum TodayCopy {
    /// → `Copy.Action.details`
    static let details = "Details"
    /// → `Copy.Action.continueLabel`. The recap's explicit exit: auto-dismiss is a convenience,
    /// never the only way out (and under VoiceOver there is no auto-dismiss at all).
    static let continueAction = "Continue"
    /// The recap's own eyebrow. A window with no noun ("SINCE 18 AUG") described only half of what
    /// sat under it; this names what the card IS, and the window moves to the line below.
    static let whileYouWereAway = "While you were away"
    /// → `Copy.Action.dismiss`
    static let dismissRecap = "Dismiss what you missed"
    /// → `Copy.Accessibility.opensTheShow`. Already written as a bare literal at two call sites in
    /// this file and absent from every Today row, which is why VoiceOver read the facts and never
    /// said what tapping would do. One string, named, until `Copy.Accessibility` carries it.
    static let opensTheShow = "Opens the show"
    /// → `Copy.Progress.sinceYourLastVisit(_:)`. "Since 23 Jul" named a date with no anchor —
    /// since the last visit, the last mark or the last episode? The card can afford the words.
    static func sinceYourLastVisit(_ phrase: String) -> String {
        let tail = phrase.hasPrefix("Since ") ? String(phrase.dropFirst(6)) : phrase
        return "Since your last visit, \(tail)"
    }
}

// "Today" — the Focus Stack (spec v8, boards 01–03), rebuilt around a FULL-BLEED HERO.
//
// The shipped build put the single most cinematic frame in the app — "here is the thing to watch
// right now" — inside a 200-pt stroked box with an 80×120 thumbnail in it, on a canvas it was only
// 4 % lighter than. Identity art went from ≈180 000 px² in the original to ≈11 600 px². This file
// puts it back: artwork from the status bar to ~46 % of the screen, the wordmark and avatar
// floating over it, one primary action laid on the art, and rhythm underneath.
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
    var onAddShow: () -> Void = {}

    private var now: Int64 { appModel.now }

    @State private var showProfile = false
    /// Drives the status-bar veil. At rest the hero art owns the top of the screen (its own
    /// `ArtScrim` protects the clock); the veil only materialises once content is travelling up
    /// towards it, exactly as a large-title navigation bar does.
    @State private var scrollY: CGFloat = 0

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
    /// The hero's art-derived ground, so a 46 %-of-screen frame never opens as a grey slab while
    /// the photograph decodes.
    @State private var heroTint: Color?

    private static let queueCount = 2
    private static let shelfCap = 10

    /// Height of the floating wordmark band, measured from the bottom of the status bar. The top
    /// veil is sized to it so scrolling content dissolves *behind the wordmark*, never across it.
    private static let headerBand: CGFloat = 52
    /// Extra veil below the wordmark band. The chrome's ramp is proportional to its own height, so
    /// a veil that ends at the band ramps out in ~25 pt — and against bright hero artwork that
    /// reads as a straight black line drawn across the screen. Ramping over the band plus this
    /// makes the hand-over a dissolve, which is the entire point of the thing.
    /// Matched to `topVeil`'s own ramp so the two protections are one shape: at 46 the chrome's
    /// proportional gradient was already down to ~30 % by the bottom of the wordmark band, and a
    /// scrolling 34-pt title read through the brand mark at half strength.
    private static let veilRamp: CGFloat = 100
    /// The cinematic band. 0.46 × screen is where the original opened and is the proportion at
    /// which artwork still leaves room for a real reading order underneath it.
    private static let heroFraction: CGFloat = 0.46
    /// What the full-bleed recap frame leaves below itself.
    ///
    /// It must clear the bottom chrome's whole ramp, not just the tab bar: at 96 pt the card's
    /// `Continue` control came to rest *inside* the veil and rendered at a quarter of its ink —
    /// a live control dimmed to 2.5:1, which is the exact failure the bottom-chrome rule forbids.
    private static var recapFloor: CGFloat { ThemeMetrics.tabBarClearance + ThemeSpace.x2 }
    /// The photograph that must remain visible above the hero copy at any type size. The hero
    /// grows past `heroFraction` by the copy's overflow rather than holding a fixed fraction and
    /// letting a taller text block spill off the top of its own protection.
    private static let artBand: CGFloat = 210
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
                    ArtBackdrop(url: ambientArt, height: 340, intensity: 0.55)
                        .ignoresSafeArea(edges: .top)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        SkeletonGate(isLoading: appModel.loading && appModel.libraryEmpty) {
                            skeleton(screenH: screenH, topInset: topInset)
                        } content: {
                            VStack(alignment: .leading, spacing: 0) {
                                topBlock(screenH: screenH, topInset: topInset,
                                         contentH: geo.size.height)
                                belowTheFold
                            }
                            // The recap holds the whole frame; everything under it arrives with
                            // the handoff rather than popping into place after it.
                            .animation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion),
                                       value: recapOnStage)
                        }
                    }
                }
                // `.contentMargins`, not `.padding(.bottom, …)` inside the stack: padding does
                // nothing at all when the content is SHORTER than the viewport, so a short Today —
                // one hero and one row — still came to rest with its last line inside the bottom
                // ramp. A content margin is an inset on the scroll view and applies either way.
                .tabBarContentMargin()
                .scrollIndicators(.hidden)
                // Type travelling under the wordmark DISAPPEARS rather than half-fading.
                //
                // The veil holds a flat coat and then ramps out, so an 88-pt two-line hero title
                // straddled both regions: line 1 at half ink under the brand mark, line 2 at full
                // white, 34 pt apart. The inverse of the veil, used as a mask, takes the type to
                // zero exactly where the veil is fully on — one edge, not two treatments — and the
                // identity is handed to the header (below) instead of simply dissolving.
                .mask(alignment: .top) { scrollMask(topInset: topInset) }
                .onScrollGeometryChange(for: CGFloat.self) { g in
                    g.contentOffset.y + g.contentInsets.top
                } action: { _, y in
                    scrollY = y
                }
                .previouslyRefreshable { await appModel.reload() }

                // Chrome, then the wordmark on top of it: the veil hides content, never identity.
                ScrollEdgeChrome(side: .top,
                                 height: topInset + TodayView.headerBand + TodayView.veilRamp)
                    .opacity(veilOpacity)
                    .allowsHitTesting(false)

                header
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(ThemeColor.canvas.ignoresSafeArea())
        .overlay(alignment: .bottom) { ScrollEdgeChrome(side: .bottom) }
        .sheet(isPresented: $showProfile) { ProfileView() }
        .onChange(of: appModel.loading) { _, loading in
            if !loading { evaluateRecap() }
        }
        .onChange(of: appModel.surfaceReady) { _, _ in startRecapClock() }
        .onAppear {
            evaluateRecap()
            // The empty state's poster fan is the only identity a first run has. Fetching it here
            // (not only from Search) is what lets Today's first frame carry the app's subject.
            if appModel.libraryEmpty { appModel.loadTrendingIfNeeded() }
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

    /// 0 while the hero owns the status bar, 1 once anything is close enough to touch the clock.
    private var veilOpacity: Double {
        Double(min(1, max(0, (scrollY - 16) / 64)))
    }

    /// The inverse of `topVeil`, as a mask on the scrolling content.
    ///
    /// At rest it is a plain rectangle and nothing is touched — the hero must keep bleeding into
    /// the status bar. As the veil comes on, the same band takes the content under it to zero, so
    /// type crosses ONE edge instead of being caught half-lit between a flat coat and its ramp.
    private func scrollMask(topInset: CGFloat) -> some View {
        let f = veilOpacity
        return VStack(spacing: 0) {
            LinearGradient(stops: [
                .init(color: .black.opacity(1 - f), location: 0),
                .init(color: .black.opacity(1 - f), location: 0.56),
                .init(color: .black.opacity(1 - f * 0.55), location: 0.80),
                .init(color: .black, location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: topInset + TodayView.headerBand + 20)
            Rectangle().fill(.black)
        }
        // Up past the scroll view's own top so the status-bar bleed is inside the mask, and well
        // past its bottom so the mask never becomes a second clip on the content.
        .padding(.top, -topInset)
        .padding(.bottom, -400)
        .allowsHitTesting(false)
    }

    /// True once the hero's title has travelled up under the wordmark band.
    private var headerCarriesTitle: Bool {
        guard showsHero, !recapOnStage, heroFranchise != nil else { return false }
        return scrollY > 150
    }

    // MARK: - Header

    /// Wordmark + account, floating over the hero art. It is not a band with 40 pt of dead air in
    /// it — there is nothing behind it but the show you are about to watch.
    private var header: some View {
        HStack(alignment: .center) {
            // The identity is HANDED OVER, not dropped. Scrolling used to dissolve the show's name
            // while the wordmark sat still, so the screen lost the one fact it was about and gained
            // nothing; a navigation bar's whole job at this moment is to say what you are looking
            // at. Cross-faded, so only ever one of the two is legible.
            ZStack(alignment: .leading) {
                Wordmark()
                    .opacity(headerCarriesTitle ? 0 : 1)
                if let title = heroFranchise?.title {
                    Text(title)
                        .type(ThemeType.showTitleM)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .lineLimit(1)
                        .shadow(.art)
                        .opacity(headerCarriesTitle ? 1 : 0)
                        .accessibilityHidden(!headerCarriesTitle)
                }
            }
            .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion),
                       value: headerCarriesTitle)
            Spacer(minLength: ThemeSpace.x4)
            Button { showProfile = true } label: {
                // No `chromeGlass` behind it. `AccountDisc` already carries its own ground
                // (`accentSoft`) and its own 1-pt `posterEdge` ring; the glass was a SECOND disc
                // drawn over a finished one, and on artwork it rendered as a flat grey plate with a
                // hard edge — a smudge on the picture, 12 pt from a wordmark that has the same
                // problem. A contact shadow is what an object laid on a photograph needs.
                AccountDisc(identity: auth.identity, diameter: 34)
                    .shadow(.art)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            // The largest targets on this screen had no press state at all. `OverArtPressStyle`
            // dips and compresses instead of washing a grey rectangle over the artwork.
            .buttonStyle(OverArtPressStyle())
            .accessibilityLabel("Profile")
        }
        .padding(.leading, ThemeMetrics.gutter)
        .padding(.trailing, ThemeSpace.x2)
        .frame(height: TodayView.headerBand)
    }

    // MARK: - Content states

    private var isFailed: Bool { appModel.loadError && appModel.libraryEmpty }
    private var isEmptyAccount: Bool { !appModel.loading && appModel.libraryEmpty && !appModel.loadError }
    /// Whether the top of the screen is a full-bleed hero (and therefore owns the art itself).
    private var showsHero: Bool {
        guard !appModel.libraryEmpty, !isFailed else { return false }
        return heroFranchise != nil || (recapOnStage && recap != nil)
    }
    /// The wash behind a screen that has no hero: whatever the user is closest to caring about.
    private var ambientArt: String? {
        appModel.nextUp?.cover ?? appModel.watchingShelf.first?.cover ?? appModel.library.first?.cover
    }

    @ViewBuilder
    private func topBlock(screenH: CGFloat, topInset: CGFloat, contentH: CGFloat) -> some View {
        if isFailed {
            stateBlock(SyncCenter.shared.isOnline ? .serverNoCache : .offlineNoData,
                       contentH: contentH) {
                Task { await appModel.reload() }
            }
        } else if isEmptyAccount {
            // `emptyToday`, not `emptyAccount`: the latter is LIBRARY's string, and a state may not
            // title itself after a tab the user is not looking at.
            stateBlock(.emptyToday, contentH: contentH, action: onAddShow)
        } else if showsHero {
            hero(heroFranchise, screenH: screenH, topInset: topInset)
        } else {
            calmBlock
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
            // The identity a first run has no artwork for. `EmptyState`'s own `accentSoft` wash
            // handles the colour; this is the app's SUBJECT — three real posters from whatever the
            // account can see (trending, on a genuinely empty account) fanned behind the plate at a
            // whisper, so the first frame a reviewer sees says "shows" rather than "grey box".
            .background(alignment: .center) { emptyFan }
    }

    /// Three fanned posters behind an empty/failed state, at 0.35.
    ///
    /// Never a fourth accent object: the plate already spends its one accent on the button. This is
    /// atmosphere, and it draws nothing at all when there is nothing honest to draw.
    @ViewBuilder
    private var emptyFan: some View {
        let covers = Array(appModel.trending.prefix(3).compactMap(\.cover))
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
            .offset(y: -60)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The calm day. No hero, because nothing has happened — a calm screen that opens on a
    /// 440-pt slab of artwork is lying about how much there is to do.
    private var calmBlock: some View {
        let next = appModel.nextUp
        let when = next.flatMap { f in f.nextAiring(now: now).map { TemporalCopy.airs(at: $0, now: now, source: f.source) } }
        return EmptyState(.calmToday(title: next?.title, when: when))
            .padding(.horizontal, ThemeMetrics.gutter)
            .padding(.top, TodayView.headerBand + ThemeSpace.x2)
    }

    // MARK: - The stack

    /// Actionable items, most actionable first: fresh unwatched episodes, then backlog.
    private var liveItems: [Franchise] { appModel.outNow + appModel.keepWatching }
    private var items: [Franchise] { pinned ?? liveItems }
    /// Only items the Focus grammar can actually describe reach the stack.
    private var actionable: [Franchise] { items.filter { kind(of: $0) != nil } }
    private var heroFranchise: Franchise? { actionable.first }
    private var queue: [Franchise] { Array(actionable.dropFirst().prefix(TodayView.queueCount)) }
    private var stackIds: Set<String> { Set(actionable.prefix(TodayView.queueCount + 1).map(\.id)) }
    private var updateCount: Int { appModel.outNow.count }
    private var comingNext: Franchise? {
        guard let f = appModel.nextUp, !stackIds.contains(f.id) else { return nil }
        return f
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
        let claimed = appModel.watchingShelf.filter { !stackIds.contains($0.id) }
        if claimed.count >= 3 { return Array(claimed.prefix(TodayView.shelfCap)) }
        var seen = Set(claimed.map(\.id))
        var wider = claimed
        for f in appModel.library where f.effectiveStatus == .watching
            && !stackIds.contains(f.id) && seen.insert(f.id).inserted {
            wider.append(f)
        }
        return Array(wider.prefix(TodayView.shelfCap))
    }
    /// Below three honest items there is no shelf to swipe — the same content becomes full-width
    /// rows under the same header, and "See all" goes away because there is nothing more to see.
    private var shelfIsList: Bool { isAX || shelf.count < 3 }
    private var showsViewAll: Bool { updateCount > TodayView.queueCount + 1 }

    // MARK: - Hero

    private func heroHeight(_ screenH: CGFloat) -> CGFloat {
        // The arrival owns the whole screen. Nothing follows the recap while it is held — at the
        // resting 46 % the card floated in the middle of the frame with half a screen of canvas
        // under it, which reads as a notification banner rather than as a moment. Edge to edge,
        // down to the tab bar, the same art then simply *shrinks* into the Focus hero on handoff:
        // one object resizing, which is what `uiSettle` is for.
        if recapOnStage { return screenH - TodayView.recapFloor }
        // The frame grows by the copy's OVERFLOW, not by a guessed accessibility bump. The copy's
        // height depends only on the width, never on this, so there is no layout cycle — and at
        // AX5 the block gets exactly the room it needs instead of 0.56 × screen and a clipped
        // title. `artBand` is the minimum photograph that must survive above the copy.
        let base = screenH * TodayView.heroFraction
        return max(base, heroCopyHeight + TodayView.artBand)
    }

    /// The art the hero is made of.
    ///
    /// **Banner first, cover second** — the same order `FranchiseDetailView` uses, because one show
    /// may not have two hero assets and two crops one tab apart. The reason the order was inverted
    /// here (a banner filled into a 46 %-of-screen frame is scaled ~3× and survives as texture) is
    /// real, but it is an argument about *upscaling*, not about which asset is the identity — and
    /// it applies with far more force to the cover, which was being blown up 2.5× and decapitated.
    /// `ArtHeader(portraitSource:)` composites a cover instead of magnifying it, so the fallback is
    /// now honest and the policy can be the app's one policy.
    private func heroArt(_ f: Franchise?) -> String? {
        f?.banner ?? f?.cover ?? recap?.beats.first?.cover
    }

    /// Whether the resolved hero art is a 2:3 COVER rather than a landscape banner. Drives
    /// `ArtHeader`'s composite path: nothing portrait is ever `.fill`ed into this band.
    private func heroArtIsPortrait(_ f: Franchise?) -> Bool {
        if let banner = f?.banner, !banner.isEmpty { return false }
        return true
    }

    @ViewBuilder
    private func hero(_ f: Franchise?, screenH: CGFloat, topInset: CGFloat) -> some View {
        // The fraction is of the WHOLE screen, status bar included: the art bleeds up into it, so
        // adding the inset on top would push the hero to 52 % and eat the fold.
        let h = heroHeight(screenH)
        let art = heroArt(f)
        // Keyed on the PHOTOGRAPH, not on the franchise id: the image only has a reason to
        // dissolve when the image itself changes. Two shows that share a hero asset hand over
        // without the picture flickering.
        let key = art ?? f?.id ?? recap?.digestID ?? "hero"
        // Pull-down grows the art instead of opening a black gap above it. The frame the layout
        // sees never changes (everything below travels with the pull, once); only the art is
        // taller, bottom-aligned, so it fills the rubber band the way a stretchy header should.
        let stretch = max(0, -scrollY)
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

            ArtHeader(url: art, height: h + stretch, tint: heroTint,
                      // The TOP protection is drawn by `topVeil` below, in POINTS: `ArtScrim`'s
                      // top stops are fractions of the art's height, so on a 46 %-of-screen frame
                      // they ramp out ~100 pt above the wordmark and leave the clock, Wi-Fi,
                      // battery and the brand mark sitting on bare key art (measured white-on-191,
                      // ≈1.15:1 over the Slime cover). The bottom hand-over stays here.
                      scrimTop: 0, scrimBottom: recapOnStage ? 1.9 : 1.6,
                      // Faces live in the upper third of a key visual and in the upper half of a
                      // cover; a centred crop of either is a chin.
                      focus: .top,
                      portraitSource: heroArtIsPortrait(f)) { EmptyView() }
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
            .padding(.bottom, ThemeSpace.x5)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heroCopyHeight = $0 }
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
            Rectangle().padding(.top, -2000).allowsHitTesting(false)
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
        .animation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion), value: recapOnStage)
        .animation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion), value: key)
        .task(id: art) {
            let resolved = await PaletteCache.shared.resolve(url: art, maxPixel: 360)
            heroTint = resolved
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

    /// Protection over the status bar and the wordmark band, ramping out with no discernible knee.
    ///
    /// The shipped ramp held 0.70 flat for 111 pt and then fell to 0.14 within the next 40 — over
    /// bright key art that reads as a hard-edged rectangular plate laid on the picture, right where
    /// the brand mark is. A veil that can be *seen* is not protection, it is a smudge. This holds
    /// only as far as the wordmark's own baseline and then eases out over the rest of the band on
    /// enough stops that no single step is visible.
    private func topVeil(topInset: CGFloat) -> some View {
        let band = topInset + TodayView.headerBand + TodayView.veilRamp
        let mark = (topInset + TodayView.headerBand) / band
        return LinearGradient(stops: [
            .init(color: .black.opacity(0.72), location: 0),
            .init(color: .black.opacity(0.66), location: mark * 0.72),
            .init(color: .black.opacity(0.52), location: mark),
            .init(color: .black.opacity(0.30), location: mark + (1 - mark) * 0.30),
            .init(color: .black.opacity(0.12), location: mark + (1 - mark) * 0.62),
            .init(color: .clear, location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .frame(height: band)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Protection BEHIND the copy, tracking its measured height at every type size.
    private var heroTextScrim: some View {
        // The stops are placed in POINTS off the measured copy height, not as fractions of it.
        // A fixed fraction is a different physical distance at every type size, which is how AX1
        // came to set a three-line 44-pt title over a face at ~55 % luminance while the same stops
        // were comfortable at default size. `lead` is a fixed 24-pt run-in above the eyebrow — the
        // gradient is already working where the copy starts, and it reaches full protection at the
        // title's own band rather than two thirds of the way down the block.
        let lead: CGFloat = 24
        let h = max(1, heroCopyHeight + lead + 8)
        return LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: ThemeColor.canvas.opacity(0.34), location: min(0.99, lead * 0.5 / h)),
            .init(color: ThemeColor.canvas.opacity(0.72), location: min(0.99, lead / h)),
            .init(color: ThemeColor.canvas.opacity(0.90), location: min(0.995, (lead + 56) / h)),
            .init(color: ThemeColor.canvas.opacity(0.97), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .frame(height: h)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

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

    @ViewBuilder
    private func heroOverlay(_ f: Franchise) -> some View {
        if let (kind, part) = kind(of: f) {
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
                   Copy.watchContext(part: part.label, episode: nextEpisode),
                   supportLine(kind, f: f, part: part))
            HeroFocus(
                franchise: f,
                eyebrow: copy.eyebrow,
                eyebrowDot: committed ? false : { if case .fresh = kind { return true } else { return false } }(),
                fact: copy.fact,
                support: copy.support,
                ctaEpisode: committed ? committedEpisode : (behind > 0 ? nextEpisode : nil),
                committed: committed,
                behind: behind,
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
        let first = showsHero ? ThemeMetrics.heroClearance : ThemeMetrics.sectionGap
        let gap = ThemeMetrics.sectionGap
        // A section that ENDS in a `MediaRow` has already spent `rowOwnInset` below its last row.
        let gapAfterRow = gap - TodayView.rowOwnInset
        VStack(alignment: .leading, spacing: 0) {
            if strip, let recap {
                RecapLine(text: recapStripText(recap)) { stageRecap() }
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .padding(.top, first)
                    .transition(.opacity)
            }
            if notice {
                InlineNotice(Copy.Notice.today) { Task { await appModel.reload() } }
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .padding(.top, strip ? ThemeMetrics.cardGap : first)
            }
            if hasQueue {
                queueSection.padding(.top, strip || notice ? gap : first)
            }
            if let next = comingNext {
                comingNextSection(next)
                    .padding(.top, hasQueue ? gapAfterRow : (strip || notice ? gap : first))
            }
            if !shelf.isEmpty {
                let afterRow = hasQueue || comingNext != nil
                watchingShelf
                    .padding(.top, afterRow ? gapAfterRow : (strip || notice ? gap : first))
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
                         poster: f.cover,
                         // `.row` (56×84) at `rowMedia`, not the 44×66 `.queue` slot. A logotype
                         // cover — Game of Thrones, Attack on Titan — is an unreadable smear at
                         // 44 pt, and it sat beside ~300 pt of empty row. Apple TV's Up Next never
                         // goes below a slot you can recognise the show from. `Upcoming` below
                         // keeps `.queue`: it is the quieter block and is allowed to be smaller.
                         slot: .row,
                         // No chevron: this row has a trailing CONTROL. A disclosure indicator and
                         // a mark ring in the same column is two trailing affordances on one row.
                         chevron: false,
                         separator: index < queue.count - 1 || showsViewAll,
                         hint: TodayCopy.opensTheShow,
                         zoomID: "queue/\(f.id)",
                         trailing: { queueMark(f) }) {
                    onOpenDetail(f.id, "queue/\(f.id)")
                }
                .padding(.horizontal, ThemeMetrics.gutter)
                .transition(handoff)
            }
            if showsViewAll {
                Button {
                    (onViewAllUpdates ?? onSeeAllWatching)()
                } label: {
                    HStack(spacing: 6) {
                        Text(Copy.Action.viewAllUpdates(updateCount))
                        Image(systemName: "chevron.forward").font(.system(size: 11, weight: .semibold))
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
            MarkRing(marked: false,
                     style: .quiet,
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
        guard let undo = appModel.markNext(franchiseId: f.id) else { return }
        appModel.presentUndo(undo)
        Announce.status(Copy.Progress.episodeWatched(undo.episode))
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
            guard let last = part.lastAiredAt else { return "New episode" }
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
        let roomForCount = !isAX && ep.count <= 22
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

    private func comingNextSection(_ f: Franchise) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // `Copy.Label.upcoming`, not "Coming next". Never a second "next" on one screen — and
            // this block is defined by NOT having aired, which "upcoming" says and "coming next"
            // only implies against a neighbour that also says "next".
            SectionHeaderRow(Copy.Label.upcoming)
                .padding(.horizontal, ThemeMetrics.gutter)
            MediaRow(title: f.title,
                     meta: f.releasingPart.map { watchLabel(f, part: $0, episode: $0.nextEpisodeNumber ?? $0.airedEpisodes + 1) },
                     lead: f.nextAiring(now: now).map { TemporalCopy.airs(at: $0, now: now, source: f.source) },
                     poster: f.cover,
                     // The quieter block keeps the smaller slot: nothing here is actionable, and a
                     // 56×84 poster under a 56×84 poster with no control beside it would give an
                     // un-actionable row the same weight as the queue above it.
                     slot: .queue,
                     chevron: false,
                     separator: false,
                     hint: TodayCopy.opensTheShow,
                     zoomID: "next/\(f.id)") {
                onOpenDetail(f.id, "next/\(f.id)")
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .padding(.top, ThemeMetrics.labelGap - TodayView.rowOwnInset)
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

    /// `SectionHeaderRow`'s own composition, opened up for one thing it cannot express: while the
    /// Undo toast is presented, this screen carries four amber objects at once (the CTA, the air
    /// time, "See all" and the toast's Undo) and no single one is the loudest. "See all" is an
    /// inline link, not a competing action, so it recedes for the toast's window and comes back.
    private var watchingHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x2) {
            SectionLabel(text: "Watching")
            Spacer(minLength: ThemeSpace.x2)
            if !shelfIsList {
                Button(Copy.Action.seeAll, action: onSeeAllWatching)
                    .buttonStyle(InlineLinkButtonStyle())
                    .padding(.vertical, -12)
                    .opacity(appModel.undo != nil ? 0.45 : 1)
                    .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion),
                               value: appModel.undo != nil)
            }
        }
        .zIndex(1)
        .accessibilityElement(children: .contain)
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
                         poster: f.cover,
                         slot: .queue,
                         chevron: false,
                         separator: index < shelf.count - 1,
                         // A distinct id from the poster shelf's: the same franchise must never
                         // register two zoom sources in one namespace, even when only one of the
                         // two layouts is mounted at a time.
                         zoomID: "shelfrow/\(f.id)") {
                    onOpenDetail(f.id, "shelfrow/\(f.id)")
                }
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
                              caption: caption?.text,
                              // Same grammar as the rows above: a caption that is a TIME or a next
                              // step is amber. "Wed 6:30 PM" was `textSecondary` here while the
                              // identical class of fact 150 pt above was accent — and the
                              // `shelfCaption` token's own note ("accent when it is a next step")
                              // was already honoured by Library's RETURNING shelf.
                              captionIsLead: caption?.lead ?? false,
                              poster: f.cover,
                              slot: .shelfMedium,
                              zoomID: "shelf/\(f.id)") {
                        onOpenDetail(f.id, "shelf/\(f.id)")
                    }
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
        case .newEpisode: return ("New episode", true)
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
        if let part = f.releasingPart, now - (part.lastAiredAt ?? 0) <= AppModel.outNowWindow,
           part.episodesBehind > 0 || appModel.justCaught.contains(f.id) {
            return part.episodesBehind > 0 ? (.fresh(behind: part.episodesBehind), part) : (.caughtUp, part)
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
            if behind > 1 { return Copy.Progress.behind(behind) }
            if let last = part.lastAiredAt { return TemporalCopy.aired(at: last, now: now, source: f.source) }
            return "New episode"
        case .backlog(let left):
            return left > 1 ? Copy.Progress.left(left) : Copy.Progress.lastEpisodeOfTheSeason
        case .caughtUp: return Copy.Progress.caughtUp
        case .waiting: return "Next episode"
        }
    }

    private func supportLine(_ kind: FocusKind, f: Franchise, part: FranchisePart) -> String? {
        switch kind {
        case .fresh(let behind):
            if behind == 1 { return Copy.Progress.caughtUpAfterThisEpisode }
            if let last = part.lastAiredAt { return "Latest " + TemporalCopy.aired(at: last, now: now, source: f.source).lowercased() }
            return nil
        case .backlog:
            // The count moved up to the eyebrow, so this line carries the OTHER fact worth having
            // rather than repeating it: where you are in the season.
            guard part.progressCeiling > 0 else { return nil }
            return Copy.Progress.watchedOf(part.progress, part.progressCeiling)
        case .caughtUp:
            if let at = part.nextAiringAt, at > now { return TemporalCopy.airs(at: at, now: now, source: f.source) }
            return nil
        case .waiting(let at):
            return TemporalCopy.airs(at: at, now: now, source: f.source)
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
                    Copy.watchContext(part: part.label, episode: episode),
                    next)
        }
        let count: String = {
            if case .backlog = kind { return Copy.Progress.left(left) }
            return Copy.Progress.behind(left)
        }()
        return (count,
                Copy.watchContext(part: part.label, episode: episode + 1),
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

    /// "Season 7 · Episode 5" on a multi-part franchise, "Episode 5" on a single one. The queue
    /// used a bare `Copy.episode` while the recap card, on the same tab, printed the same fact with
    /// its season — so a seven-season show said "Episode 5 next" in one block and
    /// "Season 7 · Episode 5 next" in the block above it.
    private func watchLabel(_ f: Franchise, part: FranchisePart, episode n: Int) -> String {
        f.parts.count > 1 ? Copy.watchContext(part: part.label, episode: n) : Copy.episode(n)
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
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                SkeletonLine(width: 96, height: 12)
                SkeletonLine(width: 250, height: 28).padding(.top, 14)
                SkeletonLine(width: 160, height: 14).padding(.top, 12)
                SkeletonBlock(height: 48, radius: 24).padding(.top, 18)
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .padding(.bottom, ThemeSpace.x5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: heroHeight(screenH), alignment: .bottom)
            // The remembered tint, not `surfacePlate`. There is no artwork yet by definition, and
            // the hero's colour rarely changes between two opens — so the frame opens on the app's
            // own atmosphere instead of on a grey slab four shades off the canvas.
            .background {
                ZStack {
                    TodayView.rememberedTint ?? PaletteCache.fallback
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

            VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
                SkeletonLine(width: 62, height: 10)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<2, id: \.self) { _ in
                        // The slot the queue actually uses — now `.row`, matching the promotion of
                        // the queue to `rowMedia`. A stand-in of the wrong size moves every title
                        // sideways and every row down at the swap.
                        SkeletonRow(poster: PosterSize.row.size, lines: [180, 110],
                                    posterRadius: PosterSize.row.radius)
                    }
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .padding(.top, ThemeMetrics.heroClearance)

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
                    SkeletonShelf(count: 4, size: PosterSize.shelfMedium.size, caption: true)
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
        pinned = snapshot
        pendingUndo = undo
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
                if let undo = pendingUndo { appModel.presentUndo(undo); pendingUndo = nil }
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
            message: "\(f.title) · \(part.label). \(Copy.Confirm.batchMarkMessage(from: part.progress + 1, to: through))",
            confirm: Copy.Confirm.batchMarkConfirm(count),
            perform: {
                appModel.markThrough(franchiseId: f.id, mediaId: part.mediaId, episode: through)
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
        guard case .episodesAired(let n, let latest) = beat.kind, n == 1, let latest,
              let f = appModel.library.first(where: { $0.id == beat.franchiseId }),
              let part = f.releasingPart ?? f.resumePart
        else { return beat.label(now: now) }
        return "\(watchLabel(f, part: part, episode: latest)) aired"
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
        if aired > 0 { return "\(Copy.episodes(aired)) aired \(since)" }
        return "\(Copy.updates(recap.beats.count + recap.hiddenBeatCount)) \(since)"
    }
}

extension RecapState {
    /// `-recapDemo 1` launch argument: force the full recap every launch (captures / review).
    static var demo: Bool { UserDefaults.standard.bool(forKey: "recapDemo") }
}

// MARK: - Wordmark

/// "Previously." — the saved-place mark, then Outfit SemiBold 20 with the full stop in accent.
///
/// The mark was dropped in the rebuild and the row became a word floating in dead space. It is the
/// app icon's own geometry (`PreviouslyMark`, shared with the splash and sign-in), set to the
/// wordmark's cap height so the two read as one lockup rather than as a logo beside a title. It
/// sits over artwork, so it carries the same soft contact shadow every other object laid on art
/// does.
struct Wordmark: View {
    var body: some View {
        HStack(spacing: ThemeSpace.x2) {
            PreviouslyMark(width: 13)
            Text("Previously\(Text(".").foregroundStyle(ThemeColor.accent))")
                .foregroundStyle(ThemeColor.textPrimary)
                .type(ThemeType.brandWordmark)
        }
        .shadow(.art)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Previously")
    }
}

// MARK: - Hero focus

/// The one thing to watch, laid on its own artwork.
///
/// Reading order, top to bottom: a scrimmed eyebrow capsule, the title at `displayXL`, the fact
/// the screen exists to deliver in `textPrimary` (not the same grey as its own footnote), the
/// footnote, and one primary action with one secondary beside it.
private struct HeroFocus: View {
    let franchise: Franchise
    let eyebrow: String
    let eyebrowDot: Bool
    let fact: String
    let support: String?
    let ctaEpisode: Int?
    let committed: Bool
    let behind: Int
    /// False while a mark is handing over to the next show: the incoming card may not be tapped
    /// until it has arrived.
    var interactive: Bool = true
    let onOpen: () -> Void
    let onMark: () -> Void
    let onMarkThrough: (Int) -> Void
    let onMarkAll: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var isAX: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 0) {
                    OverArtLabel(text: eyebrow, dot: eyebrowDot)
                    Text(franchise.title)
                        .type(ThemeType.displayXL)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .lineLimit(3)
                        // At AX5 a four-word title otherwise runs to five 60-pt lines and pushes
                        // the fact, the footnote and the primary action off the frame.
                        .minimumScaleFactor(isAX ? 0.85 : 1)
                        .allowsTightening(true)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, ThemeSpace.x3)
                    Text(fact)
                        .type(ThemeType.cardFact)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .numericFact(fact)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, ThemeMetrics.titleGap)
                    if let support {
                        Text(support)
                            .type(ThemeType.metadata)
                            .foregroundStyle(ThemeColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, ThemeSpace.x0_5)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            // The largest target on the home screen had no press state at all. A `surfacePressed`
            // wash over a photograph is a grey film over someone's illustration, so the art dips
            // in brightness and compresses a hair instead.
            .buttonStyle(OverArtPressStyle())
            // Type laid on a photograph needs a contact shadow the same way art laid on a canvas
            // does — without it the descenders dissolve into whatever is behind them.
            .shadow(.art)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the show")

            actions.padding(.top, ThemeSpace.x5)
        }
        .allowsHitTesting(interactive)
    }

    /// The action pair.
    ///
    /// **A capsule never degrades into bare text across a size class.** At AX1 `Details` fell back
    /// to `InlineLinkButtonStyle` — two amber objects on the card, neither reading as secondary, a
    /// control that stopped looking like a control, and (before SYS-9) a target under 44 pt. It
    /// keeps `SecondaryButtonStyle2` at every size and simply stacks full-width, which is the
    /// pattern `LibraryView.viewAsRow` already uses for the same problem.
    ///
    /// **Once the mark is committed, `Details` is the primary.** The confirmation capsule has
    /// dropped to a soft tint and has nothing left to do; leaving the card with no primary action
    /// at all is what made the committed frame read as a dead end.
    @ViewBuilder
    private var actions: some View {
        let layout = isAX
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ThemeMetrics.cardGap))
            : AnyLayout(HStackLayout(spacing: ThemeSpace.x2))
        layout {
            if let ctaEpisode {
                MarkSplitButton(episode: ctaEpisode,
                                committed: committed,
                                behind: behind,
                                title: franchise.title,
                                onMark: onMark,
                                onMarkThrough: onMarkThrough,
                                onMarkAll: onMarkAll)
            }
            detailsButton
        }
    }

    @ViewBuilder
    private var detailsButton: some View {
        let button = Button(TodayCopy.details, action: onOpen)
        if committed {
            // Hugging, not 200 pt wide: the confirmation capsule beside it is the longer label
            // ("Episode 5 watched" plus its drawn check), and giving `Details` a fixed half of the
            // row wrapped that label onto two lines — measured on the recording at frames 43-56.
            // Colour is what makes this the primary now, not width.
            button.buttonStyle(PrimaryButtonStyle2())
                .fixedSize(horizontal: !isAX, vertical: false)
                .frame(maxWidth: isAX ? .infinity : nil)
        } else if isAX {
            button.buttonStyle(SecondaryButtonStyle2())
                .frame(maxWidth: .infinity)
        } else {
            button.buttonStyle(SecondaryButtonStyle2())
                // The style stretches to fill (it is written for full-width sheets); beside a
                // primary it has to hug its own label instead of claiming half the row.
                .fixedSize(horizontal: true, vertical: false)
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
                OverArtLabel(text: TodayCopy.whileYouWereAway)
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
                        HStack(spacing: ThemeSpace.x3) {
                            if showsPoster { PosterSlot(url: beat.cover, .beat) }
                            VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                                HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x2) {
                                    Text(beat.title)
                                        .type(ThemeType.rowTitle)
                                        // BOTH rows at `textPrimary`. The second used to be
                                        // `textSecondary`, so it read as disabled; the aired-vs-
                                        // upcoming distinction lives in the meta line.
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
                    if digest.hiddenBeatCount > 0 {
                        Text("and \(digest.hiddenBeatCount) more")
                            .type(ThemeType.metadata)
                            .foregroundStyle(ThemeColor.textTertiary)
                            .opacity(revealed ? 1 : 0)
                            .animation(ThemeMotion.pick(ThemeMotion.uiReveal, reduceMotion: reduceMotion)
                                .delay(reduceMotion ? 0 : 0.12 * Double(digest.beats.count + 1)),
                                       value: revealed)
                    }
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
            .frame(minHeight: 44, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel(text)
        .accessibilityHint("Opens what you missed")
    }
}
