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
                    .padding(.bottom, ThemeMetrics.tabBarClearance)
                }
                .scrollIndicators(.hidden)
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
        .onAppear { evaluateRecap() }
        .onDisappear { if recapMode == .strip { acknowledgeRecap() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, recapMode == .strip { acknowledgeRecap() }
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

    // MARK: - Header

    /// Wordmark + account, floating over the hero art. It is not a band with 40 pt of dead air in
    /// it — there is nothing behind it but the show you are about to watch.
    private var header: some View {
        HStack(alignment: .center) {
            Wordmark()
            Spacer(minLength: ThemeSpace.x4)
            Button { showProfile = true } label: {
                AccountDisc(identity: auth.identity, diameter: 34)
                    .chromeGlass(in: Circle())
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
    /// like. The height is the visible area minus the band the wordmark floats in and the tab
    /// bar's clearance, so the screen still does not scroll.
    private func stateBlock(_ copy: EmptyStateCopy, contentH: CGFloat,
                            action: (() -> Void)? = nil) -> some View {
        EmptyState(copy, primary: action)
            .padding(.horizontal, ThemeMetrics.gutter)
            // `minHeight`, never `height`: `EmptyState` drops its own minimum at AX and grows with
            // the copy, so a fixed frame let the title + two-line body + 48-pt button draw outside
            // the scrollable region at AX3–AX5 and collide with the tab bar with no way to reach it.
            .frame(maxWidth: .infinity,
                   minHeight: max(0, contentH - TodayView.headerBand - ThemeMetrics.tabBarClearance),
                   alignment: .center)
            .padding(.top, TodayView.headerBand)
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
    /// **Cover first, banner second** — measured, not assumed. A banner is a 4.75:1 strip; filled
    /// into a frame this tall it is scaled ~3× and centre-cropped, and what survives is texture:
    /// the captured hero was a wall of anonymous sword blades with no character and no title art in
    /// it. A 2:3 cover cropped to the same frame loses ~12 % top and bottom, stays sharp, and is
    /// still recognisably the show — which is the entire job of identity artwork.
    private func heroArt(_ f: Franchise?) -> String? {
        f?.cover ?? f?.banner ?? recap?.beats.first?.cover
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
            ArtHeader(url: art, height: h + stretch, tint: heroTint,
                      // The TOP protection is drawn by `topVeil` below, in POINTS: `ArtScrim`'s
                      // top stops are fractions of the art's height, so on a 46 %-of-screen frame
                      // they ramp out ~100 pt above the wordmark and leave the clock, Wi-Fi,
                      // battery and the brand mark sitting on bare key art (measured white-on-191,
                      // ≈1.15:1 over the Slime cover). The bottom hand-over stays here.
                      scrimTop: 0, scrimBottom: recapOnStage ? 1.9 : 1.6) { EmptyView() }
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
                                 reduceMotion: reduceMotion, onContinue: { handoffRecap() })
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
        // BEFORE the negative top padding: that padding shifts the layout frame down by the safe
        // inset, and an overlay attached after it would start the veil below the status bar —
        // leaving the clock on bare art with a hard seam under it.
        .overlay(alignment: .top) { topVeil(topInset: topInset) }
        // No `.clipped()` here: `ArtHeader` clips itself, and the stretched art has to be allowed
        // to draw above this frame into the pull. The scroll view is the real clip.
        .padding(.top, -topInset)
        .animation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion), value: recapOnStage)
        .animation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion), value: key)
        .task(id: art) { heroTint = await PaletteCache.shared.resolve(url: art, maxPixel: 360) }
    }

    /// The handoff. Finish the removal, THEN start the insertion.
    ///
    /// A plain `.opacity` transition on both branches drew the outgoing card's eyebrow, 34-pt
    /// title, fact line, footnote and its committed CTA at ~50 % on top of the incoming card's for
    /// six frames — two show titles superimposed at display size, both posters ghosting through
    /// each other. The direction's rule for this moment is "one object moving, not two crossfading".
    private var handoff: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(
                ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)
                    .delay(reduceMotion ? 0 : 0.16)),
            removal: .opacity.animation(
                ThemeMotion.pick(ThemeMotion.uiDismiss, reduceMotion: reduceMotion)))
    }

    /// Flat protection over the status bar and the wordmark band, then a long ramp out.
    ///
    /// Held flat rather than ramping from the first pixel: a gradient that starts falling at y=0
    /// is tuned for a dark backdrop and does nothing for bright key art, which is how the clock,
    /// the battery glyph and "Previously." came to be drawn on clouds.
    private func topVeil(topInset: CGFloat) -> some View {
        // Flat across the STATUS BAR *and* the wordmark band, then a 100-pt ramp out. Ramping
        // across the wordmark itself left its lower half sitting at ~0.3 of the veil, which is how
        // "Previously." measured 6.6:1 at its median and 2.5:1 at its worst pixel over pale sky.
        let band = topInset + TodayView.headerBand + 100
        return LinearGradient(stops: [
            .init(color: .black.opacity(0.70), location: 0),
            .init(color: .black.opacity(0.66), location: (topInset + TodayView.headerBand) / band),
            .init(color: .black.opacity(0.14), location: (topInset + TodayView.headerBand + 40) / band),
            .init(color: .clear, location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .frame(height: band)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Protection BEHIND the copy, tracking its measured height at every type size.
    private var heroTextScrim: some View {
        // Measured at AX1 over the brightest cover in the library: the first stop has to be up at
        // ~0.55 by the eyebrow's own band, or the top of a three-line 44-pt title sits on pale sky
        // at under 5:1 while the lines below it clear 16:1.
        LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: ThemeColor.canvas.opacity(0.55), location: 0.30),
            .init(color: ThemeColor.canvas.opacity(0.86), location: 0.66),
            .init(color: ThemeColor.canvas.opacity(0.96), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        // The measurement already carries the overlay's own bottom padding; + 32 pt of bleed above
        // the eyebrow so the pill never sits on the very first, faintest stop.
        .frame(height: heroCopyHeight + 32)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
                onMarkAll: { promptBatch(f, part: part, through: part.progressCeiling) }
            )
        }
    }

    // MARK: - Below the fold

    @ViewBuilder
    private var belowTheFold: some View {
        if !recapOnStage {
            let strip = recapMode == .strip && recap != nil
            let notice = appModel.loadError && !appModel.libraryEmpty
            let hasQueue = showsHero && (!queue.isEmpty || showsViewAll)
            // The first block under a hero gets the hero's clearance; every block after it gets a
            // section gap. One rhythm, decided once, instead of 16 pt between everything.
            let first = showsHero ? ThemeMetrics.heroClearance : ThemeMetrics.sectionGap
            let gap = ThemeMetrics.sectionGap
            VStack(alignment: .leading, spacing: 0) {
                if strip, let recap {
                    RecapStrip(text: recapStripText(recap)) { stageRecap() }
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
                        .padding(.top, strip || notice || hasQueue ? gap : first)
                }
                if !shelf.isEmpty {
                    watchingShelf
                        .padding(.top, strip || notice || hasQueue || comingNext != nil ? gap : first)
                }
            }
            .transition(.opacity)
            .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: recapMode)
        }
    }

    // MARK: - Queue

    /// The rest of what is waiting.
    ///
    /// It used to sit unlabelled on the canvas between a hero and a labelled `COMING NEXT` while
    /// every other block announced itself — and it vanished entirely in the committed state, so
    /// the screen's section structure changed shape between frames.
    private var queueSection: some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
            SectionHeaderRow("Up next")
                .padding(.horizontal, ThemeMetrics.gutter)
            queueRows
        }
    }

    private var queueRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(queue.enumerated()), id: \.element.id) { index, f in
                MediaRow(title: f.title,
                         meta: queueMeta(f),
                         lead: queueLead(f),
                         poster: f.cover,
                         // The same slot `COMING NEXT` uses directly beneath it. A 48×72 row above
                         // a 44×66 row of the same kind is an art column that does not line up.
                         slot: .queue,
                         // No chevron on Today. A row here carries art, a title and a forward fact
                         // in amber; a 13-pt glyph parked 300 pt away from the text it belongs to
                         // adds an object and says nothing. (Detail and Library keep theirs — they
                         // are lists you navigate; this is a queue you act on.)
                         chevron: false,
                         separator: index < queue.count - 1 || showsViewAll,
                         zoomID: "queue/\(f.id)") {
                    onOpenDetail(f.id, "queue/\(f.id)")
                }
                .padding(.horizontal, ThemeMetrics.gutter)
                .transition(handoff)
            }
            if showsViewAll {
                Button {
                    onSeeAllWatching()
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
        switch kind {
        case .fresh(let behind):
            return behind > 1 ? "\(ep) · \(Copy.Progress.behind(behind))" : ep
        case .backlog(let left):
            return left > 1 ? "\(ep) · \(Copy.Progress.left(left))" : ep
        case .caughtUp: return Copy.Progress.caughtUp
        case .waiting:
            return watchLabel(f, part: part, episode: part.nextEpisodeNumber ?? part.airedEpisodes + 1)
        }
    }

    // MARK: - Coming next

    private func comingNextSection(_ f: Franchise) -> some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
            SectionHeaderRow("Coming next")
                .padding(.horizontal, ThemeMetrics.gutter)
            MediaRow(title: f.title,
                     meta: f.releasingPart.map { watchLabel(f, part: $0, episode: $0.nextEpisodeNumber ?? $0.airedEpisodes + 1) },
                     lead: f.nextAiring(now: now).map { TemporalCopy.airs(at: $0, now: now, source: f.source) },
                     poster: f.cover,
                     slot: .queue,
                     chevron: false,
                     separator: false,
                     zoomID: "next/\(f.id)") {
                onOpenDetail(f.id, "next/\(f.id)")
            }
            .padding(.horizontal, ThemeMetrics.gutter)
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
            let next = part.nextAiringAt.flatMap { $0 > now ? TemporalCopy.airs(at: $0, now: now, source: f.source) : nil }
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

    /// "Season 7 · Episode 5" on a multi-part franchise, "Episode 5" on a single one. The queue
    /// used a bare `Copy.episode` while the recap card, on the same tab, printed the same fact with
    /// its season — so a seven-season show said "Episode 5 next" in one block and
    /// "Season 7 · Episode 5 next" in the block above it.
    private func watchLabel(_ f: Franchise, part: FranchisePart, episode n: Int) -> String {
        f.parts.count > 1 ? Copy.watchContext(part: part.label, episode: n) : Copy.episode(n)
    }

    // MARK: - Skeleton

    /// The shape the hero will fill, not a generic card. A skeleton that stands in for a 440-pt
    /// full-bleed frame with a 212-pt box makes the swap land as a layout jump.
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
            .surface(.plate, radius: 0)
            // The real hero hands over to the canvas through `ArtScrim`; a plate that stops on a
            // hard horizontal edge announces the swap 300 ms before it happens.
            .mask(LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.86),
                .init(color: .black.opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom))
            .padding(.top, -topInset)

            VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
                SkeletonLine(width: 62, height: 10)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<2, id: \.self) { _ in
                        // The slot the queue actually uses. A 48×72 stand-in for a 44×66 row moves
                        // every title 4 pt sideways and every row 6 pt down at the swap.
                        SkeletonRow(poster: PosterSize.queue.size, lines: [180, 110],
                                    posterRadius: PosterSize.queue.radius)
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
        if recapMode == .strip { acknowledgeRecap() }
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

    private func promptBatch(_ f: Franchise, part: FranchisePart, through: Int) {
        let count = through - part.progress
        guard count > 0 else { return }
        let all = through >= part.progressCeiling
        batchPrompt = BatchPrompt(
            title: Copy.Confirm.batchMarkTitle(count),
            message: "\(f.title) · \(part.label). \(Copy.Confirm.batchMarkMessage(from: part.progress + 1, to: through))",
            confirm: Copy.Confirm.batchMarkConfirm(count),
            perform: {
                if all { appModel.markCaughtUp(f.id) }
                else { appModel.setProgress(franchiseId: f.id, mediaId: part.mediaId, episodes: through) }
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
        let since = demo ? now - 30 * Formatting.D : appModel.prevOpenedAt
        guard let digest = RecapDigest.build(library: appModel.library, since: since, now: now) else {
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
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 2600 : 2000))
            handoffRecap()
        }
    }

    private func recapSpokenSummary(_ recap: RecapDigest) -> String {
        "\(TodayCopy.whileYouWereAway). \(recapStripText(recap))."
    }

    private func handoffRecap() {
        guard recapOnStage else { return }
        withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) {
            recapOnStage = false
        } completion: {
            acknowledgeRecap()
        }
    }

    /// A full recap DEMOTES to the strip rather than disappearing.
    ///
    /// It used to go straight to `.none`, which also removed the `RecapStrip` that is the only way
    /// back in — a user returning after a week to 300 titles got a list they could not physically
    /// read, once, and then it was gone. The strip is the standing way back; it is what leaving
    /// the screen finally clears.
    private func acknowledgeRecap() {
        guard let recap else { return }
        if !RecapState.demo {
            RecapState.acknowledgedID = recap.digestID
            if recapMode == .full { RecapState.lastFullRecapAt = now }
        }
        let next: RecapDigest.Presentation = recapMode == .full ? .strip : .none
        withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) { recapMode = next }
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

    @ViewBuilder
    private var actions: some View {
        let layout = isAX
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ThemeSpace.x2))
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
            if isAX {
                // Stacked, the two filled capsules were near-equal in weight and the one-primary
                // rule collapsed: two full-width buttons, no hero. `Details` is a link at every
                // size where it cannot sit beside the primary.
                Button(TodayCopy.details, action: onOpen)
                    .buttonStyle(InlineLinkButtonStyle())
                    .padding(.leading, -12)
            } else {
                Button(TodayCopy.details, action: onOpen)
                    .buttonStyle(SecondaryButtonStyle2())
                    // The style stretches to fill (it is written for full-width sheets); beside a
                    // primary it has to hug its own label instead of claiming half the row.
                    .fixedSize(horizontal: true, vertical: false)
            }
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
    let onContinue: () -> Void

    @State private var tint: Color?

    /// "2 updates since 18 Aug" — what the card is, in the hero's voice.
    private var headline: String {
        let aired = digest.beats.reduce(0) { acc, b in
            if case .episodesAired(let n, _) = b.kind { return acc + n } else { return acc }
        }
        let total = digest.beats.count + digest.hiddenBeatCount
        return aired > 0 ? "\(Copy.episodes(aired)) aired" : "\(Copy.updates(total)) waiting"
    }

    /// A beat's line. When the whole digest is one aired episode the headline above has already
    /// said "aired", so the row names the episode instead of repeating the verb.
    private func beatMeta(_ beat: RecapBeat) -> String {
        if digest.beats.count == 1, digest.hiddenBeatCount == 0,
           case .episodesAired(let n, let latest) = beat.kind, n == 1, let latest {
            return Copy.episode(latest)
        }
        return beat.label(now: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                OverArtLabel(text: TodayCopy.whileYouWereAway)
                Spacer(minLength: ThemeSpace.x3)
                Button(action: onContinue) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(ThemeColor.textTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(OverArtPressStyle())
                .accessibilityLabel(TodayCopy.dismissRecap)
                .padding(.trailing, -10)
                .padding(.top, -10)
            }
            Text(headline)
                .type(ThemeType.displayL)
                .foregroundStyle(ThemeColor.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ThemeSpace.x3)
            Text(TemporalCopy.since(digest.since, now: now))
                .type(ThemeType.metadata)
                .foregroundStyle(ThemeColor.textSecondary)
                .padding(.top, ThemeSpace.x0_5)

            Button(action: onContinue) {
                VStack(alignment: .leading, spacing: ThemeSpace.x3) {
                    ForEach(Array(digest.beats.enumerated()), id: \.element.id) { i, beat in
                        HStack(spacing: ThemeSpace.x3) {
                            PosterSlot(url: beat.cover, .beat)
                            VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                                Text(beat.title)
                                    .type(ThemeType.rowTitle)
                                    // BOTH rows at `textPrimary`. The second used to be
                                    // `textSecondary`, so it read as disabled; the aired-vs-
                                    // upcoming distinction lives in the meta line, where it belongs.
                                    .foregroundStyle(ThemeColor.textPrimary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(beatMeta(beat))
                                    .type(ThemeType.rowMeta)
                                    .foregroundStyle(ThemeColor.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .opacity(revealed ? 1 : 0)
                        .offset(y: revealed || reduceMotion ? 0 : 6)
                        .animation(ThemeMotion.pick(ThemeMotion.uiReveal, reduceMotion: reduceMotion)
                            .delay(reduceMotion ? 0 : 0.12 * Double(i + 1)), value: revealed)
                    }
                    HStack(spacing: ThemeSpace.x2) {
                        if digest.hiddenBeatCount > 0 {
                            Text("and \(digest.hiddenBeatCount) more")
                                .type(ThemeType.metadata)
                                .foregroundStyle(ThemeColor.textTertiary)
                        }
                        Spacer(minLength: ThemeSpace.x3)
                        Text(TodayCopy.continueAction)
                            .type(ThemeType.listAction)
                            .foregroundStyle(ThemeColor.accent)
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ThemeColor.accent)
                    }
                    .opacity(revealed ? 1 : 0)
                    .animation(ThemeMotion.pick(ThemeMotion.uiReveal, reduceMotion: reduceMotion)
                        .delay(reduceMotion ? 0 : 0.12 * Double(digest.beats.count + 1)), value: revealed)
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
            .accessibilityLabel(digest.beats.map { "\($0.title), \($0.label(now: now))" }.joined(separator: ". "))
            .accessibilityHint("Continues to what is next")
        }
        .shadow(.art)
        .task(id: digest.beats.first?.cover) {
            tint = await PaletteCache.shared.resolve(url: digest.beats.first?.cover, maxPixel: 360)
        }
    }
}
