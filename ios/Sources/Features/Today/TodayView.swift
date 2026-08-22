import SwiftUI

/// Two strings this screen needs that the shared copy table does not carry yet: the hero's
/// secondary action and the primary's committed label. Both are filed as an exact diff against
/// `Copy.swift` (a design-system file this track does not own); they live here, named and in one
/// place, until that lands — never inline at a call site.
private enum TodayCopy {
    /// → `Copy.Action.details`
    static let details = "Details"
    /// → `Copy.Progress.episodeWatched(_:)`
    static func episodeWatched(_ n: Int) -> String { "\(Copy.episode(n)) watched" }
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
    @State private var recapSeenSurface = false

    // Mark handoff
    @State private var pinned: [Franchise]?        // stack snapshot held while the hero shows its result
    @State private var committedEpisode: Int?
    @State private var pendingUndo: UndoState?
    @State private var batchPrompt: BatchPrompt?

    private static let queueCount = 2
    private static let shelfCap = 10

    /// Height of the floating wordmark band, measured from the bottom of the status bar. The top
    /// veil is sized to it so scrolling content dissolves *behind the wordmark*, never across it.
    private static let headerBand: CGFloat = 52
    /// Extra veil below the wordmark band. The chrome's ramp is proportional to its own height, so
    /// a veil that ends at the band ramps out in ~25 pt — and against bright hero artwork that
    /// reads as a straight black line drawn across the screen. Ramping over the band plus this
    /// makes the hand-over a dissolve, which is the entire point of the thing.
    private static let veilRamp: CGFloat = 46
    /// The cinematic band. 0.46 × screen is where the original opened and is the proportion at
    /// which artwork still leaves room for a real reading order underneath it.
    private static let heroFraction: CGFloat = 0.46
    /// What the full-bleed recap frame leaves below itself: enough for the floating tab bar to sit
    /// on canvas rather than on artwork.
    private static let recapFloor: CGFloat = 96

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
                Text(initial)
                    .type(ThemeType.showTitleS)
                    .foregroundStyle(ThemeColor.textPrimary)
                    .frame(width: 34, height: 34)
                    // Warmed with `accentSoft` — the same identity the Profile row uses, so the
                    // account reads as a person rather than as an empty ring floating on the art.
                    .background(ThemeColor.accentSoft, in: Circle())
                    .chromeGlass(in: Circle())
                    .shadow(.art)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
        }
        .padding(.leading, ThemeMetrics.gutter)
        .padding(.trailing, ThemeSpace.x2)
        .frame(height: TodayView.headerBand)
    }

    /// One letter. "YA" in a 30-pt grey ring is a form field, not a person.
    private var initial: String {
        let name = auth.displayName.trimmingCharacters(in: .whitespaces)
        guard let first = name.split(separator: " ").first?.first else { return "\u{2022}" }
        return String(first).uppercased()
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
            stateBlock(.emptyAccount, contentH: contentH, action: onAddShow)
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
            .frame(maxWidth: .infinity)
            .frame(height: max(0, contentH - TodayView.headerBand - ThemeMetrics.tabBarClearance),
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
    private var shelf: [Franchise] {
        Array(appModel.watchingShelf.filter { !stackIds.contains($0.id) }.prefix(TodayView.shelfCap))
    }
    private var showsViewAll: Bool { updateCount > TodayView.queueCount + 1 }

    // MARK: - Hero

    private func heroHeight(_ screenH: CGFloat) -> CGFloat {
        // The arrival owns the whole screen. Nothing follows the recap while it is held — at the
        // resting 46 % the card floated in the middle of the frame with half a screen of canvas
        // under it, which reads as a notification banner rather than as a moment. Edge to edge,
        // down to the tab bar, the same art then simply *shrinks* into the Focus hero on handoff:
        // one object resizing, which is what `uiSettle` is for.
        if recapOnStage { return screenH - TodayView.recapFloor }
        // At accessibility sizes the same block of copy is half as tall again; the art grows with
        // it rather than the type being clipped by it.
        return screenH * (isAX ? TodayView.heroFraction + 0.10 : TodayView.heroFraction)
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
        let key = f?.id ?? recap?.digestID ?? "hero"
        // Pull-down grows the art instead of opening a black gap above it. The frame the layout
        // sees never changes (everything below travels with the pull, once); only the art is
        // taller, bottom-aligned, so it fills the rubber band the way a stretchy header should.
        let stretch = max(0, -scrollY)
        ZStack(alignment: .bottom) {
            ArtHeader(url: heroArt(f), height: h + stretch,
                      // The bottom hand-over is pushed harder than the default because a whole
                      // reading order sits on it — a hero's scrim is doing typography, not mood.
                      scrimTop: 1, scrimBottom: recapOnStage ? 1.9 : 1.6) { EmptyView() }
                .frame(height: h, alignment: .bottom)
                .id(key)
                .transition(.opacity)

            Group {
                if recapOnStage, let recap {
                    RecapCardView(digest: recap, revealed: recapRevealed, now: now, reduceMotion: reduceMotion)
                        .onTapGesture { handoffRecap() }
                        .transition(.opacity)
                } else if let f {
                    heroOverlay(f)
                        .id(f.id)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .padding(.bottom, ThemeSpace.x5)
        }
        .frame(height: h)
        .frame(maxWidth: .infinity)
        // No `.clipped()` here: `ArtHeader` clips itself, and the stretched art has to be allowed
        // to draw above this frame into the pull. The scroll view is the real clip.
        .padding(.top, -topInset)
        .animation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion), value: recapOnStage)
        .animation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion), value: key)
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
            HeroFocus(
                franchise: f,
                eyebrow: eyebrow(kind, f: f, part: part),
                eyebrowDot: { if case .fresh = kind { return true } else { return false } }(),
                fact: Copy.watchContext(part: part.label, episode: nextEpisode),
                support: supportLine(kind, f: f, part: part),
                ctaEpisode: committed ? committedEpisode : (behind > 0 ? nextEpisode : nil),
                committed: committed,
                behind: behind,
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

    /// The rest of what is waiting. No label: these continue the hero's sentence, and a second
    /// header here would compete with the only one the screen is allowed.
    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(queue.enumerated()), id: \.element.id) { index, f in
                MediaRow(title: f.title,
                         meta: queueMeta(f),
                         lead: queueLead(f),
                         poster: f.cover,
                         slot: .row,
                         // No chevron on Today. A row here carries art, a title and a forward fact
                         // in amber; a 13-pt glyph parked 300 pt away from the text it belongs to
                         // adds an object and says nothing. (Detail and Library keep theirs — they
                         // are lists you navigate; this is a queue you act on.)
                         chevron: false,
                         separator: index < queue.count - 1 || showsViewAll) {
                    onOpenDetail(f.id, "queue/\(f.id)")
                }
                .padding(.horizontal, ThemeMetrics.gutter)
                .transition(.opacity)
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

    /// A queue row's forward-looking fact, in accent — only when it genuinely is one.
    private func queueLead(_ f: Franchise) -> String? {
        guard let (kind, part) = kind(of: f) else { return nil }
        switch kind {
        case .fresh: return nil
        case .backlog: return Copy.Progress.episodeNext(part.progress + 1)
        case .caughtUp: return nil
        case .waiting(let at): return TemporalCopy.airs(at: at, now: now, source: f.source)
        }
    }

    private func queueMeta(_ f: Franchise) -> String? {
        guard let (kind, part) = kind(of: f) else { return nil }
        switch kind {
        case .fresh(let behind):
            let ep = Copy.episode(part.progress + 1)
            if behind > 1 { return "\(ep) · \(Copy.Progress.behind(behind))" }
            if let last = part.lastAiredAt { return "\(ep) · \(TemporalCopy.aired(at: last, now: now, source: f.source))" }
            return ep
        case .backlog(let left): return Copy.Progress.left(left)
        case .caughtUp: return Copy.Progress.caughtUp
        case .waiting: return nil
        }
    }

    // MARK: - Coming next

    private func comingNextSection(_ f: Franchise) -> some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
            SectionHeaderRow("Coming next")
                .padding(.horizontal, ThemeMetrics.gutter)
            MediaRow(title: f.title,
                     meta: f.releasingPart.map { Copy.episode($0.nextEpisodeNumber ?? $0.airedEpisodes + 1) },
                     lead: f.nextAiring(now: now).map { TemporalCopy.airs(at: $0, now: now, source: f.source) },
                     poster: f.cover,
                     slot: .row,
                     chevron: false,
                     separator: false) {
                onOpenDetail(f.id, "next/\(f.id)")
            }
            .padding(.horizontal, ThemeMetrics.gutter)
        }
    }

    // MARK: - Watching shelf

    @ViewBuilder
    private var watchingShelf: some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
            SectionHeaderRow("Watching", actionLabel: Copy.Action.seeAll, action: onSeeAllWatching)
                .padding(.horizontal, ThemeMetrics.gutter)
            if isAX {
                axWatchingList
            } else {
                shelfScroller
            }
        }
    }

    /// At accessibility sizes a 100-pt shelf card gives a show's name four characters before it
    /// truncates — `Re:ZER…` over `Wed 6:3…`. The content is the same; the layout that can carry
    /// it is a row, which is allowed as many lines as the name needs.
    private var axWatchingList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shelf.enumerated()), id: \.element.id) { index, f in
                let isLead = appModel.shelfState(of: f) == .newEpisode
                let caption = shelfCaption(f)
                MediaRow(title: f.title,
                         meta: isLead ? nil : caption,
                         lead: isLead ? caption : nil,
                         poster: f.cover,
                         slot: .row,
                         chevron: false,
                         separator: index < shelf.count - 1) {
                    onOpenDetail(f.id, "shelf/\(f.id)")
                }
                .padding(.horizontal, ThemeMetrics.gutter)
            }
        }
    }

    private var shelfScroller: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: ThemeMetrics.shelfGap) {
                ForEach(shelf) { f in
                    ShelfCard(title: f.title,
                              caption: shelfCaption(f),
                              captionIsLead: appModel.shelfState(of: f) == .newEpisode,
                              poster: f.cover,
                              slot: .shelfMedium) {
                        onOpenDetail(f.id, "shelf/\(f.id)")
                    }
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func shelfCaption(_ f: Franchise) -> String? {
        switch appModel.shelfState(of: f) {
        case .newEpisode: return "New episode"
        case .backlog:
            if let p = f.resumePart { return Copy.Progress.episodeNext(p.progress + 1) }
            return nil
        case .airingWait:
            if let at = f.nextAiring(now: now) { return TemporalCopy.airsCompact(at: at, now: now, source: f.source) }
            return Copy.Progress.caughtUp
        case .premiereSoon:
            return TemporalCopy.returns(at: appModel.nextPremiere(of: f), now: now, source: f.source)
        case nil: return nil
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

    private func eyebrow(_ kind: FocusKind, f: Franchise, part: FranchisePart) -> String {
        switch kind {
        case .fresh(let behind):
            if behind > 1 { return Copy.Progress.behind(behind) }
            if let last = part.lastAiredAt { return TemporalCopy.aired(at: last, now: now, source: f.source) }
            return "New episode"
        case .backlog: return "Continue"
        case .caughtUp: return Copy.Progress.caughtUp
        case .waiting: return "Up next"
        }
    }

    private func supportLine(_ kind: FocusKind, f: Franchise, part: FranchisePart) -> String? {
        switch kind {
        case .fresh(let behind):
            if behind == 1 { return Copy.Progress.caughtUpAfterThisEpisode }
            if let last = part.lastAiredAt { return "Latest " + TemporalCopy.aired(at: last, now: now, source: f.source).lowercased() }
            return nil
        case .backlog(let left):
            return left == 1 ? Copy.Progress.lastEpisodeOfTheSeason : Copy.Progress.left(left)
        case .caughtUp:
            if let at = part.nextAiringAt, at > now { return TemporalCopy.airs(at: at, now: now, source: f.source) }
            return nil
        case .waiting(let at):
            return TemporalCopy.airs(at: at, now: now, source: f.source)
        }
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
            .padding(.top, -topInset)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<2, id: \.self) { _ in
                    SkeletonRow(poster: PosterSize.row.size, lines: [180, 110], posterRadius: PosterSize.row.radius)
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
        guard committedEpisode == nil else { return }
        let snapshot = items
        guard let undo = appModel.markNext(franchiseId: f.id) else { return }
        pinned = snapshot
        pendingUndo = undo
        withAnimation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion)) {
            committedEpisode = undo.episode
        }
        if recapMode == .strip { acknowledgeRecap() }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            let settle = ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)
            withAnimation(settle) {
                pinned = nil
                committedEpisode = nil
            } completion: {
                if let undo = pendingUndo { appModel.presentUndo(undo); pendingUndo = nil }
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
        let since = demo ? now - 4 * Formatting.D : appModel.prevOpenedAt
        guard let digest = RecapDigest.build(library: appModel.library, since: since, now: now, keepWatching: appModel.keepWatching) else {
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

    /// 0–460 ms reveal · hold · handoff at ≈2,060 ms (Reduce Motion: no stagger, 1,600 ms hold).
    /// On a cold launch the clock starts at the splash handoff, so the beats reveal while the
    /// splash crossfades away and the hold is counted from the first clean frame.
    private func startRecapClock() {
        guard recapOnStage, appModel.surfaceReady, !recapClockStarted else { return }
        recapClockStarted = true
        let coldLaunch = !recapSeenSurface
        recapSeenSurface = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(ThemeMotion.pick(ThemeMotion.uiReveal, reduceMotion: reduceMotion)) { recapRevealed = true }
            let hold = (reduceMotion ? 1600 : 2000) + (coldLaunch ? 460 : 0)
            try? await Task.sleep(for: .milliseconds(hold))
            handoffRecap()
        }
    }

    private func handoffRecap() {
        guard recapOnStage else { return }
        withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) {
            recapOnStage = false
        } completion: {
            acknowledgeRecap()
        }
    }

    private func acknowledgeRecap() {
        guard let recap else { return }
        if !RecapState.demo {
            RecapState.acknowledgedID = recap.digestID
            if recapMode == .full { RecapState.lastFullRecapAt = now }
        }
        withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) { recapMode = .none }
    }

    private func recapStripText(_ recap: RecapDigest) -> String {
        let aired = recap.beats.reduce(0) { acc, b in
            if case .episodesAired(let n) = b.kind { return acc + n } else { return acc }
        }
        let since = TemporalCopy.since(recap.since, now: now).lowercased()
        if aired > 0 { return "\(Copy.episodes(aired)) aired \(since)" }
        return "\(Copy.updates(recap.beats.count)) \(since)"
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
            .buttonStyle(.plain)
            // Type laid on a photograph needs a contact shadow the same way art laid on a canvas
            // does — without it the descenders dissolve into whatever is behind them.
            .shadow(.art)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the show")

            actions.padding(.top, ThemeSpace.x5)
        }
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
            Button(TodayCopy.details, action: onOpen)
                .buttonStyle(SecondaryButtonStyle2())
                // The style stretches to fill (it is written for full-width sheets); beside a
                // primary it has to hug its own label instead of claiming half the row.
                .fixedSize(horizontal: !isAX, vertical: false)
        }
    }
}

// MARK: - The split primary

/// "Mark as watched" with the batch options behind a real split.
///
/// The shipped build drew a 48-pt accent capsule with a bare `chevron.down` floating at the right
/// inset — no divider, no target boundary, no pressed state of its own. It read as a button with a
/// decoration on it. This is one capsule containing two 44-pt targets separated by a hairline:
/// tapping the label marks, tapping the chevron opens the batch menu.
private struct MarkSplitButton: View {
    let episode: Int
    let committed: Bool
    let behind: Int
    let title: String
    let onMark: () -> Void
    let onMarkThrough: (Int) -> Void
    let onMarkAll: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsMenu: Bool { behind > 1 && !committed }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onMark) {
                HStack(spacing: ThemeSpace.x2) {
                    if committed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .transition(reduceMotion
                                        ? .opacity
                                        : .scale(scale: 0.6).combined(with: .opacity))
                    }
                    Text(committed ? TodayCopy.episodeWatched(episode) : Copy.Action.markAsWatched)
                        .type(ThemeType.button)
                        .contentTransition(.interpolate)
                }
                .foregroundStyle(ThemeColor.onAccent)
                .padding(.horizontal, ThemeSpace.x5)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(SplitHalfStyle())
            .allowsHitTesting(!committed)
            .accessibilityLabel(committed
                                ? TodayCopy.episodeWatched(episode)
                                : "\(Copy.Action.markAsWatched), \(Copy.episode(episode)) of \(title)")

            if showsMenu {
                Rectangle()
                    .fill(ThemeColor.onAccent.opacity(0.18))
                    .frame(width: 1, height: 24)
                Menu {
                    let through = min(episode + 4, episode + behind - 1)
                    if through > episode {
                        Button(Copy.Action.markThrough(through)) { onMarkThrough(through) }
                    }
                    Button(Copy.Action.markAll(behind)) { onMarkAll() }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ThemeColor.onAccent)
                        .frame(width: 46, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SplitHalfStyle())
                .accessibilityLabel("More ways to mark")
            }
        }
        .background(ThemeColor.accent)
        .clipShape(Capsule())
        // The lit top edge every filled control in this app carries: a flat #F0A24E rectangle is
        // a swatch, the same rectangle with one lit edge is an object.
        .overlay(Capsule().strokeBorder(
            LinearGradient(colors: [ThemeColor.controlSheen, .clear],
                           startPoint: .top, endPoint: .center),
            lineWidth: 1))
        .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: committed)
    }
}

/// One half of a split control: the press darkens only the half under the finger, inside the
/// shared capsule, so the boundary the divider promises is real.
private struct SplitHalfStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? ThemeColor.accentPressed : Color.clear)
            .animation(ThemeMotion.pick(ThemeMotion.uiPress, reduceMotion: reduceMotion),
                       value: configuration.isPressed)
    }
}

// MARK: - Recap card

/// The arrival. It sits in the hero frame, over the artwork of the show it is about to hand off
/// to, on the art-adaptive ground — never a stroked box with 60 pt of dead space under its last
/// row, which is what a forced 212-pt minimum produced.
private struct RecapCardView: View {
    let digest: RecapDigest
    let revealed: Bool
    let now: Int64
    let reduceMotion: Bool

    @State private var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
            SectionLabel(text: TemporalCopy.since(digest.since, now: now))
                .opacity(revealed ? 1 : 0)
            VStack(alignment: .leading, spacing: ThemeSpace.x3) {
                ForEach(Array(digest.beats.enumerated()), id: \.element.id) { i, beat in
                    HStack(spacing: ThemeSpace.x3) {
                        PosterSlot(url: beat.cover, .beat)
                        VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                            Text(beat.title)
                                .type(ThemeType.rowTitle)
                                .foregroundStyle(ThemeColor.textPrimary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(beat.label(now: now))
                                .type(ThemeType.rowMeta)
                                .foregroundStyle(ThemeColor.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed || reduceMotion ? 0 : 6)
                    .animation(ThemeMotion.pick(ThemeMotion.uiReveal, reduceMotion: reduceMotion).delay(reduceMotion ? 0 : 0.12 * Double(i + 1)), value: revealed)
                }
            }
            if digest.hiddenBeatCount > 0 {
                Text("and \(digest.hiddenBeatCount) more")
                    .type(ThemeType.metadata)
                    .foregroundStyle(ThemeColor.textTertiary)
                    .opacity(revealed ? 1 : 0)
            }
        }
        .padding(ThemeSpace.x4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .surface(.art(tint), radius: ThemeRadius.card)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Since you were last here: " + digest.beats.map { "\($0.title), \($0.label(now: now))" }.joined(separator: ". "))
        .accessibilityHint("Double tap to continue")
        .task(id: digest.beats.first?.cover) {
            tint = await PaletteCache.shared.resolve(url: digest.beats.first?.cover, maxPixel: 360)
        }
    }
}
