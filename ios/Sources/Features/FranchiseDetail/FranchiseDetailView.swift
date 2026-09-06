import SwiftUI

// Franchise Detail (spec board 06). The hero is identity; the Next up card owns the single action
// and shares Today's mark timeline (pinned snapshot → result → handoff → toast on settle).
// Seasons & movies are flat rows in the source's own labels; a season pushes its episode list.
// Every write has Undo or a confirmation that states its exact blast radius.
struct FranchiseDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openURL) private var openURL
    let franchiseId: String
    var focus: EpisodeFocus? = nil
    /// Pushes onto the owning tab's navigation path (Detail is a push, never a sheet).
    var push: (DetailPush) -> Void = { _ in }

    @State private var fetched: Franchise?
    @State private var loading = true
    @State private var loadError = false
    /// A Schedule-routed `focus` lands on its row once (`landOnFocus`).
    @State private var focusConsumed = false
    @State private var synopsisExpanded = false
    // The paragraph's whole height behind its clamped one: the link is drawn only when they differ.
    @State private var synopsisFullHeight: CGFloat = 0
    @State private var synopsisClampedHeight: CGFloat = 0
    /// About three lines of `prose` on a 361-pt run (~52 characters a line).
    static let synopsisBudget = 150
    static func clampedAtWord(_ text: String, budget: Int) -> String {
        guard text.count > budget else { return text }
        let head = String(text.prefix(budget))
        guard let cut = head.lastIndex(of: " ") else { return head + "\u{2026}" }
        return String(head[..<cut]).trimmingCharacters(in: CharacterSet(charactersIn: " ,;:\u{2014}\u{2013}-")) + "\u{2026}"
    }
    @State private var revealed: Set<Int> = []          // episode numbers whose title the user revealed
    @State private var tint: Color?
    /// The BANNER's palette, distinct from `tint` (the cover's). The hero's photograph is the
    /// banner, so the colour that continues it below the fold has to come from the banner too —
    /// derived from the cover it landed a warm brown under a magenta-and-cyan neon header, i.e.
    /// two light sources in one hero. The card and the episode tiles keep the cover's palette:
    /// they are the show's identity, not a continuation of this particular photograph.
    @State private var heroTint: Color?
    /// The hero art's mean lightness (`PaletteCache.lightness(for:)`), for `HeroProtection`.
    @State private var heroLightness: Double?
    /// The trailer card → stage zoom (`VideoSheet`).
    @Namespace private var trailerZoom

    // Mark timeline (identical to Today)
    @State private var pinned: Franchise?
    @State private var committedEpisode: Int?
    @State private var pendingUndo: UndoState?
    @State private var prompt: WritePrompt?
    @State private var showStartRewatch = false
    /// Minted when a mark completes a season; the hairline sweep draws once per token.
    @State private var sweepToken: UUID?
    /// Minted when a mark completes the LAST part of the last season — the series milestone the
    /// status chip settles on. Separate from `sweepToken`: a season ending is not a show ending.
    @State private var milestoneToken: UUID?
    /// True once the hero art has left the top of the screen.
    ///
    /// The hero bleeds under the status bar, so this screen hides the navigation bar's background
    /// — and then nothing stops a season row from rendering at half opacity across the floating
    /// toolbar. `scrollEdgeChrome` holds FULL canvas only through the status bar (by design: it is
    /// a status-bar veil), and the ramp below it is exactly where the toolbar sits. So the bar
    /// takes its own background back the moment there is content rather than artwork behind it —
    /// which is what every shipping media app does, and is native rather than a second hand-rolled
    /// veil stacked on the first.
    @State private var scrolledUnderBar = false
    /// The billboard copy's measured height — the scrim behind it is sized to it (Today's rule).
    @State private var heroCopyHeight: CGFloat = 0
    /// The season the Episodes section shows, once the picker has chosen one.
    @State private var selectedSeasonId: Int?
    /// The scroll offset, outside this view's state — read only by `DetailVeils` (Today's rule).
    @State private var scroll = ScrollOffset()
    /// Country-specific streaming availability, read apart from the franchise (the contract's
    /// rule, so a cold provider lookup never delays the page).
    @State private var providers: WatchAvailability?
    /// The trailer the sheet is playing.
    @State private var video: FranchiseVideo?
    /// The related title whose show is being looked up, so a second tap waits for the first.
    @State private var resolvingRelated: String?
    /// The one quiet re-read that catches the catalogue's enrichment landing after the first fetch.
    @State private var enrichmentRetry: Task<Void, Never>?

    private var now: Int64 { appModel.now }
    private var isAX: Bool { typeSize.isAccessibilitySize }

    /// The cover's palette, made fit to be a GROUND (see `DetailTint`). The raw palette colour at
    /// full chroma composited to a saturated brown block on a warm poster — and to the *same*
    /// brown block on a magenta-and-cyan one, so the screen's one action card was carrying a
    /// colour that said nothing about the show it was derived from.

    /// The floating sync banner is drawn OVER content rather than inset from it, so while a
    /// failure is pending the last row of any screen is sliced through its glyphs. Until the
    /// banner carries a presented-state content inset of its own, the screens that can show one
    /// make room for it. (Shared-file request filed; this is the local half.)
    private var bottomClearance: CGFloat { DetailMetrics.bottomClearance }

    enum DetailPush: Hashable {
        case episodes(franchiseId: String, mediaId: Int, focusEpisode: Int?)
        case history(franchiseId: String)
        /// Another show, from this show's "More like this" shelf.
        case detail(franchiseId: String)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // The show's GROUND (6 Sep): the whole page sits in the art's hue at canvas depth —
            // `DetailTint.ground`, from `groundTopLightness` under the hero to `groundFootLightness`
            // at the foot, with one soft pool of the tint's light — instead of stepping from the
            // billboard onto #09090B ("the details screen should have the theme color veil over
            // the entire screen to make the experience more immersive", user). Two gradients, no
            // image, nothing per frame. The hero's copy scrim LANDS on the top colour
            // (`HeroCopyScrim(landing:)`), so there is no seam; a blurred wash behind the header
            // was tried on 30 Aug and put a 14-level luminance step across the screen because the
            // scrim landed on canvas over it. No `ArtBackdrop`: the billboard is the ambient art.
            showGround
            SkeletonGate(isLoading: franchise == nil && loading && !loadError) {
                detailSkeleton
            } content: {
                if let f = franchise {
                    screen(f)
                } else if loadError {
                    EmptyState(SyncCenter.shared.isOnline ? .serverNoCache : .offlineNoData, prominence: .major) {
                        Task { await load() }
                    }
                    .padding(.horizontal, ThemeMetrics.gutter)
                }
            }
        }
        // This screen hides its navigation-bar background so the hero can own the top. Two veils
        // replace the system edge, Today's anatomy exactly:
        //  * while ARTWORK is behind the toolbar, a soft one fades in with the scroll — the
        //    hero's own `HeroTopVeil` travels away with the picture, and the clock needs something
        //    once it has gone;
        //  * once CONTENT is behind the toolbar, the bar: opaque canvas through the toolbar's
        //    band (status bar + 46), then out over `barEdgeRamp`. It held through the status bar
        //    only before, and ramped across the toolbar — a season row at half ink under the back
        //    button.
        .chromeScrollEdgeHidden(.top)
        .overlay(alignment: .top) {
            DetailVeils(scroll: scroll, hardOn: scrolledUnderBar, band: ThemeMetrics.topSafeInset + Self.toolbarBand,
                        color: DetailTint.chrome(heroTint ?? tint))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        // The system's own back button, at the system's own size, with no title beside it. Three
        // hand-built circles in one navigation stack — a glass one here, a flat grey one on
        // Episodes and another on History — is three answers to "how do I go back".
        .toolbarRole(.editor)
        // TWO items, not one `ToolbarItemGroup`.
        //
        // A group is one Liquid Glass capsule; the status pill and the `···` then drew their own
        // materials INSIDE it — three materials in one cluster, with a visible seam mid-capsule,
        // an empty stretch of glass around the ellipsis, and a refracted inner pill over bright
        // artwork that reads as a rendering bug. Two items are two capsules, drawn by the system,
        // and neither carries a background of its own.
        .toolbar {
            // The show's name docks into the bar once its billboard has scrolled away — the
            // native handover an inline title makes, and what Netflix's and Apple TV's bars do.
            // Before, the bar over a scrolled season list carried two pills and no noun.
            if let f = franchise {
                ToolbarItem(placement: .principal) { barTitle(f) }
                    .chromeSharedBackgroundHidden()
            }
            if let f = franchise, inLibrary {
                ToolbarItem(placement: .topBarTrailing) { statusMenu(f) }
                // The spacer is what makes them two capsules rather than two items sharing one:
                // the status pill is a control with a value, the overflow is a menu, and iOS 26
                // draws a break between glass groups exactly here. There are no glass groups to
                // break below 26, and no ToolbarSpacer either, so it simply does not apply.
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                ToolbarItem(placement: .topBarTrailing) { overflowMenu(f) }
            } else if let f = franchise {
                ToolbarItem(placement: .topBarTrailing) { addButton(f) }
            }
        }
        .task(id: franchiseId) {
            await load()
            await loadProviders()
        }
        // A trailer is a full-screen STAGE the tapped card zooms into, not a sheet (`VideoSheet`).
        .fullScreenCover(item: $video) { v in
            VideoSheet(video: v, showTitle: franchise?.displayTitle ?? "",
                       ambientArt: franchise?.landscapeArt ?? franchise?.portraitArt,
                       tint: heroTint ?? tint)
                .navigationTransition(.zoom(sourceID: v.id, in: trailerZoom))
                .perfScreen("Stage")
        }
        .onChange(of: appModel.library.count, initial: true) { _, _ in
            if let lib = appModel.franchise(id: franchiseId) { lastLibraryCopy = lib }
        }
        .confirmationDialog(prompt?.title ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
                            titleVisibility: .visible, presenting: prompt) { p in
            Button(p.confirm, role: p.destructive ? .destructive : nil) { p.perform() }
            Button(Copy.Confirm.cancel, role: .cancel) {}
        } message: { p in
            Text(p.message)
        }
    }

    // MARK: - Data

    /// `force` is the Retry footnote's; the appearance task passes nothing, so popping back
    /// from the season list no longer refetches the whole franchise under the user.
    private func load(force: Bool = false) async {
        guard force || fetched?.id != franchiseId else { return }
        loading = true
        defer { loading = false }
        do {
            let read = try await appModel.api.franchise(id: franchiseId, country: AppRegion.current)
            // The detail read reflows the identity line (the certificate rides it): a crossfade,
            // never a snap (review i4).
            withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) { fetched = read }
            loadError = false
            retryEnrichmentIfEmpty()
        } catch {
            // A pop mid-fetch cancels the task; that is not a failed load and must not leave
            // the "couldn't refresh" footnote standing when the user comes back.
            if !error.isCancellation { loadError = true }
        }
    }

    /// Streaming availability is a second, separate read. A failure here is a missing section,
    /// never an error state: the page is about the show, not about where to stream it.
    private func loadProviders() async {
        guard providers == nil else { return }
        guard let availability = try? await appModel.api.watchProviders(id: franchiseId, country: AppRegion.current) else { return }
        withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) { providers = availability }
    }

    /// The catalogue's deep metadata arrives stale-while-revalidate: the first read of a show can
    /// return before its people, related titles and trailers exist, and the server fills them in
    /// the background. One quiet re-read a few seconds later catches that, so the shelves fade in
    /// on this visit instead of the next.
    private func retryEnrichmentIfEmpty() {
        guard let f = fetched, f.looksUnenriched, enrichmentRetry == nil else { return }
        enrichmentRetry = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled,
                  let again = try? await appModel.api.franchise(id: franchiseId, country: AppRegion.current),
                  !again.looksUnenriched else { return }
            withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) { fetched = again }
        }
    }

    /// The live franchise (fresh progress/status from the library) grafted with the detail
    /// fetch's per-episode data. A pinned snapshot wins while the card shows a mark's result.
    private var franchise: Franchise? {
        if let pinned { return pinned }
        // Off the library, the catalogue read keeps the face the library copy had.
        guard let base = appModel.franchise(id: franchiseId) ?? fetched.map({ f in lastLibraryCopy.map { f.keepingArt(of: $0) } ?? f }) else { return nil }
        return merged(base)
    }
    @State private var lastLibraryCopy: Franchise?

    private func merged(_ base: Franchise) -> Franchise {
        guard let fetched else { return base }
        return base.grafting(fetched)
    }

    private var inLibrary: Bool { appModel.isInLibrary(franchiseId) }
    private var staleAfterFailure: Bool { loadError && fetched != nil }

    // MARK: - Screen

    private func screen(_ f: Franchise) -> some View {
        ScrollViewReader { proxy in
            scrollContent(f)
                .debugDetailDrive(franchise: f, proxy: proxy, video: $video, openRelated: openRelated)
                .task(id: f.id) { await landOnFocus(f, proxy: proxy) }
        }
    }

    /// A Schedule card lands on its episode. The episodes are on this page (6 Sep), so the route
    /// scrolls to the row instead of pushing a second screen — twice, because the first pass can
    /// run before the section below the hero has laid out. An extra's episode (an OVA airing)
    /// still opens its own list, the one place a run outside the seasons is drawn.
    private func landOnFocus(_ f: Franchise, proxy: ScrollViewProxy) async {
        guard let focus, !focusConsumed else { return }
        focusConsumed = true
        guard f.seasonPartsInOrder.contains(where: { $0.mediaId == focus.mediaId }) else {
            push(.episodes(franchiseId: f.id, mediaId: focus.mediaId, focusEpisode: focus.episode))
            return
        }
        for delay in [0.45, 1.2] {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) {
                proxy.scrollTo("ep-\(focus.episode)", anchor: .center)
            }
        }
    }

    private func scrollContent(_ f: Franchise) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(f)
                VStack(alignment: .leading, spacing: ThemeMetrics.sectionGap) {
                    if staleAfterFailure {
                        InlineNotice(Copy.Notice.detailEpisodes) { Task { await load(force: true) } }
                    }
                    // The state block lives in the billboard's lockup now (5 Sep); the way into
                    // watch history follows the synopsis.
                    about(f)
                    historyRow(f)
                    episodesSection(f)
                    extrasShelf(f)
                    trailersShelf(f)
                    peopleShelf(f)
                    relatedShelf(f)
                    whereToWatch(f)
                }
                .padding(.horizontal, ThemeMetrics.gutter)
                // The first thing under the billboard is the identity line heading the synopsis
                // (5 Sep). x4: capsule → identity line measured 62 pt at x5 (review, 5 Sep); the
                // in-place receipt lives in this band.
                .padding(.top, ThemeSpace.x4)
                .animation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion), value: nextUpState(f)?.identity)
            }
            // The scroll probe — geometry-based, because `onScrollGeometryChange` never fires on
            // the iOS 27 simulator (Today's discovery), which left the bar's veil dead in every
            // capture. The content's top edge in window space is the fact.
            .background {
                Color.clear.onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { minY in
                    let y = -minY
                    scroll.set(y)
                    // The bar hardens — and docks the title — the moment the hero's COPY reaches
                    // the toolbar's bottom edge: Apple TV's handover, the title leaving the
                    // picture as it arrives in the bar. At a flat 130 pt the flip came ~80 pt
                    // later, so the title slid under the glass capsules half-lit and ghosted
                    // through them for the whole of that scroll (captured 3 Sep).
                    // The copy's top is the badge; the NAME sits a badge and a gap beneath it
                    // (5 Sep, the lockup), and it is the name's arrival in the bar that the
                    // dock answers.
                    let copyTop = heroHeight - ThemeSpace.x4 - heroCopyHeight + Self.badgeToName
                    let under = y > copyTop - (ThemeMetrics.topSafeInset + Self.toolbarBand)
                    if under != scrolledUnderBar {
                        withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) { scrolledUnderBar = under }
                    }
                }
            }
        }
        // The bottom clearance is a scroll-content MARGIN, not padding inside the stack.
        //
        // `pushedScreenChrome()` already gives every pushed screen `tabBarClearance`; this only
        // widens it while a sync failure is pending, because the floating banner is drawn OVER
        // content rather than inset from it. Padding inside the stack does nothing at all when the
        // content is shorter than the viewport, which is exactly the case in which the last line
        // came to rest inside the veil — the synopsis measured 4.39 → 1.04:1 over four lines.
        .contentMargins(.bottom, bottomClearance, for: .scrollContent)
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .task(id: f.portraitArt) { tint = await PaletteCache.shared.resolve(url: f.portraitArt, maxPixel: 420) }
        .task(id: heroArt(f).url) {
            heroTint = await PaletteCache.shared.resolve(url: heroArt(f).url, maxPixel: 420)
            heroLightness = PaletteCache.shared.lightness(for: heroArt(f).url)
        }
    }

    // MARK: - Hero (identity only)

    /// The billboard — Today's hero, on the show's own page.
    ///
    /// The cover shown whole at 68 % of the screen, the title and one identity line laid over its
    /// foot, nothing else. The previous hero was a 320-pt landscape band with the 112-pt poster
    /// floating over its lower edge and an eyebrow on the poster's baseline: a database entry's
    /// anatomy (Letterboxd, TMDB), and on this catalogue's art it was the app's worst crop — a
    /// 4.75:1 AniList banner `.fill`ed into a 1.2:1 band shows a quarter of itself, which put a
    /// forehead under the back button on the flagship title (captured 2 Sep). Apple TV and
    /// Netflix open a show on its key art edge to edge with the lockup over it; the cover is
    /// within 4 % of this frame's aspect, so the composite path shows it whole and sharp, and the
    /// same asset is no longer drawn twice at two scales. Today's 0.72 (5 Sep): the state block
    /// that used to sit under the art is inside the lockup now, so nothing below the hero has to
    /// land on the first screen.
    private static let heroFraction: CGFloat = 0.72
    /// The least photograph that must survive above the copy at accessibility sizes.
    private static let artBand: CGFloat = 132
    /// The floating toolbar's band below the status bar.
    private static let toolbarBand: CGFloat = 46
    /// From the lockup's top edge (the badge) to the name: the badge's 20 pt and the gap under it.
    private static let badgeToName: CGFloat = 20 + ThemeSpace.x3
    /// How far the show's colour keeps going after the photograph stops.
    private static let heroBloomHeight: CGFloat = 220
    /// How far the bloom reaches back UP into the photograph, so its ramp is already running where
    /// the image ends and the handover is a gradient rather than a line.
    private static let bloomOverlap: CGFloat = 56

    /// Grows with the copy's OVERFLOW, never by a guessed accessibility bump (Today's rule).
    private var heroHeight: CGFloat {
        max(ThemeMetrics.windowHeight * Self.heroFraction, heroCopyHeight + Self.artBand)
    }

    /// The art the hero is made of: `Franchise.billboardArt` — the server-selected poster,
    /// composited whole, and the landscape only when the catalogue has none. Today's rule, for
    /// one hero grammar (the frame is a poster's shape; a backdrop in it is a slice of itself).
    private func heroArt(_ f: Franchise) -> (url: String?, portrait: Bool, ultraWide: Bool) {
        let art = f.billboardArt
        return (art.url, art.portraitSource, art.ultraWide)
    }

    /// How hard the hero's veil, scrim and ground dim are drawn, from the art's lightness.
    private var heroStrength: Double { HeroProtection.strength(lightness: heroLightness) }

    private func hero(_ f: Franchise) -> some View {
        let h = heroHeight
        let art = heroArt(f)
        return ZStack(alignment: .bottom) {
            // The persistent ground under the photograph, so the frame never flashes canvas
            // while the image decodes.
            (heroTint ?? tint ?? PaletteCache.fallback)
            ArtHeader(url: art.url, height: h, tint: heroTint ?? tint,
                      // Both protections are drawn in POINTS — `HeroTopVeil` over the chrome
                      // band, `HeroCopyScrim` sized to the measured copy. A fractional scrim on a
                      // 580-pt frame blankets the middle of the picture.
                      scrimTop: 0, scrimBottom: 0,
                      // Faces live in the upper half of a cover; a centred crop is a chin.
                      // The same slow breath as Today's billboard: one hero grammar, one motion.
                      focus: .top, portraitSource: art.portrait, drift: true,
                      ultraWide: art.ultraWide, groundDim: HeroProtection.groundDim(heroStrength)) { EmptyView() }
                .id(art.url ?? f.id)
            HeroCopyScrim(copyHeight: heroCopyHeight, strength: heroStrength, landing: groundTop)
            // ONE billboard lockup, Today's (`HeroLockup`, 5 Sep): the state badge, the name, the
            // moment and the episode, the season bar and the one action, all over the art's foot.
            // The page used to end its hero on a logo and a grey identity line and start a second
            // block on canvas with the badge, the fact and the capsule — a poster with a caption,
            // then a widget ("poorly built and rushed", user). The identity line heads the
            // synopsis now; a show that is not in the library draws its name alone.
            heroCopy(f)
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.bottom, isAX ? ThemeSpace.x5 : ThemeSpace.x4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heroCopyHeight = $0 }
                .animation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion), value: nextUpState(f)?.identity)
        }
        .frame(height: h)
        .frame(maxWidth: .infinity)
        // The chrome's own strip is neutralised for the clock and the glass toolbar (iOS 26's
        // glass takes its rim colour from whatever is behind it — on a bright cover the back
        // button drew a saturated ring that read as a focus state); the photograph keeps the
        // band the title lives in.
        .overlay(alignment: .top) { HeroTopVeil(band: ThemeMetrics.topSafeInset + Self.toolbarBand, strength: heroStrength) }
        .zoomSource("detail/\(f.id)")
        // The bloom STARTS INSIDE the photograph and is drawn OVER the hero's foot, not behind
        // it. Ending it where the image ends put the whole colour ramp below the seam — a visible
        // full-width line across the widest part of the hero. And as a `.background` it was
        // occluded by the copy scrim (opaque canvas at the frame's bottom, by design) right up to
        // the seam, then added its light from the first row below it: the same line, measured
        // again on the billboard (2 Sep). As an overlay its ramp runs continuously across the
        // edge; at the overlap's opacities (0 → 0.13) `plusLighter` is invisible on white type.
        .overlay(alignment: .top) {
            heroBloom
                .frame(height: Self.heroBloomHeight + Self.bloomOverlap)
                .padding(.top, h - Self.bloomOverlap)
        }
        .animation(ThemeMotion.uiPoster, value: art.url)
    }

    /// The show's colour keeps going for one more beat after the photograph stops.
    ///
    /// The photograph handed over to `#09090B` at a hard line, and on a dark banner — Game of
    /// Thrones is one — the hero read as a black rectangle with a poster in it. The ORIGINAL
    /// screen's atmosphere was never the photograph: it was a large, soft, art-derived colour
    /// field that the poster and title floated in. This is that field, resumed under the poster's
    /// lower half so the two halves of the hero are one light source instead of two layers.
    ///
    /// It starts at *fully clear*, exactly where `ArtScrim` lands on the canvas, so there is no
    /// seam — the failure mode of running an `ArtBackdrop` behind the header instead, which steps
    /// straight from opaque canvas to 45 %-strength blurred art across the header's bottom edge.
    /// True when the banner's own colour is dark enough that a 0.45 top scrim would leave the hero
    /// at canvas luminance — Game of Thrones' Iron Throne is the case that has no hero moment at
    /// all. Measured off the resolved palette colour rather than off a second decode of the image.
    private var heroIsDark: Bool { Self.lightness(heroTint ?? tint) < 0.34 }

    // MARK: - The show's ground (6 Sep)

    /// The colour the page is grounded in: the banner's palette, else the cover's (`heroBloom`'s base).
    private var groundColor: Color? { heroTint ?? tint }
    /// The ground's top, right under the hero — where `HeroCopyScrim` lands.
    private var groundTop: Color { DetailTint.ground(groundColor, lightness: DetailTint.groundTopLightness) }
    private var groundFoot: Color { DetailTint.ground(groundColor, lightness: DetailTint.groundFootLightness) }

    /// The whole page in the show's hue: a vertical run from the hero's foot to a near-canvas at
    /// the bottom (so the bottom chrome's canvas veil lands on it without a step), and one soft
    /// pool of the tint's light where the eye rests once the billboard has scrolled away — a light
    /// source, not a flat wash (`ArtAdaptiveGround`'s rule). Static, behind the scroll view.
    private var showGround: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [groundTop, groundFoot], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [(groundColor ?? PaletteCache.fallback).opacity(0.14), .clear],
                           center: .init(x: 0.5, y: 0.36), startRadius: 0, endRadius: 360)
                .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
        .animation(ThemeMotion.uiPoster, value: groundColor == nil)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// OKLab lightness of a resolved palette colour, 0…1. `nil` (art still loading) is treated as
    /// mid so the hero never starts by over-correcting.
    private static func lightness(_ color: Color?) -> Double {
        guard let color else { return 0.5 }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0.5 }
        return PaletteCache.oklab(r: Double(r), g: Double(g), b: Double(b)).0
    }

    private var heroBloom: some View {
        let base = heroTint ?? tint ?? PaletteCache.fallback
        // A dark banner gets more of its own colour back, not less: with the photograph sitting at
        // canvas luminance the bloom is the only thing separating identity from background.
        let lift = heroIsDark ? 1.8 : 1.0
        return ZStack {
            LinearGradient(stops: [
                .init(color: base.opacity(0), location: 0.00),
                .init(color: base.opacity(0.20 * lift), location: 0.30),
                .init(color: base.opacity(0.07 * lift), location: 0.70),
                .init(color: base.opacity(0), location: 1.00),
            ], startPoint: .top, endPoint: .bottom)
            // Inside its overlay (review i2, the F9 seam found): centred 12 % from the top with
            // a 300-pt radius the pool was still at 26 % where the overlay BEGAN, and the
            // overlay's top edge printed a straight step 56 pt above the frame's bottom. At
            // 0.55 / 140 it reaches zero twelve points inside the edge.
            // At the SEAM, symmetric (review i3): the i2 pool had moved under the synopsis on
            // one side. Centred 16 pt below the frame's bottom, zero 16 pt inside the top edge.
            RadialGradient(colors: [base.opacity(0.16 * lift), .clear],
                           center: .init(x: 0.5, y: 0.26), startRadius: 0, endRadius: 88)
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(ThemeMotion.uiPoster, value: heroTint == nil)
    }

    /// The loading shape has to be the shape that arrives — composed from the skeleton atoms
    /// (the DS's stale per-screen defaults were deleted in the cohesion pass).
    private var detailSkeleton: some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.sectionGap) {
            // The billboard's centred lockup, then the page that arrives — identity line, prose,
            // the Episodes header and its 120×68 rows (review i5: the skeleton promised a state
            // card the page dropped on 5 Sep and 60×90 rows it never draws).
            ZStack(alignment: .bottom) {
                (tint ?? TodayView.rememberedTint ?? ThemeColor.ambientBackdropFallback)
                VStack(alignment: .center, spacing: 8) {
                    SkeletonBlock(width: 88, height: 20, radius: 4)
                    SkeletonLine(width: 250, height: 26)
                    SkeletonLine(width: 176, height: 13)
                    SkeletonLine(width: 200, height: 3)
                    SkeletonBlock(height: 48, radius: 24).padding(.top, 10)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.bottom, ThemeSpace.x4)
            }
            .frame(height: heroHeight)
            .padding(.horizontal, -ThemeMetrics.gutter)
            VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                SkeletonLine(width: 176, height: 13)
                SkeletonLine(height: 12).padding(.top, ThemeSpace.x1)
                SkeletonLine(height: 12)
                SkeletonLine(width: 210, height: 12)
            }
            SkeletonLine(width: 96, height: 20)
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { _ in
                    SkeletonRow(poster: CGSize(width: 120, height: 68), lines: [150, 104],
                                posterRadius: PosterSize.row.radius, spacing: ThemeMetrics.artGap)
                }
            }
        }
        .padding(.horizontal, ThemeMetrics.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(edges: .top)
    }

    /// The year the WORK premiered — specials excluded.
    ///
    /// TMDB's season 0 carries the air date of the earliest featurette, which on Game of Thrones is
    /// 2010-12-05: a pre-launch promo, five months before the show existed. Taking a plain minimum
    /// across every part therefore printed "TV · 2010" on the flagship title. Same root cause as
    /// the 300-episode Specials row, and the same answer: a catalogue of extras is not a season of
    /// the work. (The server computes this field the same wrong way; filed as a shared-file
    /// request, and this is the client half so the screen is right either way.)
    private func premiereYear(_ f: Franchise) -> Int? {
        let real = f.parts.filter { $0.kind != .special }.compactMap(\.year)
        return (real.isEmpty ? f.parts.compactMap(\.year) : real).min()
    }

    /// The identity line with its certificate drawn as an outlined tag between the year and the
    /// genres. `rating` nil (accessibility sizes) keeps the plain sentence.
    @ViewBuilder
    private func identityRow(_ line: String, rating: String?) -> some View {
        let token = rating.map { " \u{00B7} \($0) \u{00B7} " }
        if let rating, let token, let r = line.range(of: token) {
            // Air on both sides of the tag, no middots against it — Apple TV's grammar (review i4:
            // it had one dot after and none before).
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(line[line.startIndex..<r.lowerBound]))
                Text(rating)
                    .type(ThemeType.caption)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(ThemeColor.strokeStrong, lineWidth: 1))
                Text(String(line[r.upperBound...]))
            }
            .type(ThemeType.metadata)
            .foregroundStyle(ThemeColor.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .accessibilityElement(children: .combine)
        } else {
            Text(line)
                .type(ThemeType.metadata)
                .foregroundStyle(ThemeColor.textSecondary)
                .lineLimit(isAX ? 3 : 1)
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The hero's ONE metadata line: "Anime · 2018 · Action · Adventure · Comedy" — the work's
    /// class and year, then its genres, in a single middot run (Apple TV's "TV Show · Comedy ·
    /// Sport"). The class and year used to be a small-caps eyebrow on the poster's baseline and
    /// the studio closed the genre run, where "8-Bit" and "WIT Studio" read as genres with a
    /// missing separator. A studio is a credit, not identity; it leaves the hero. The genre tail
    /// is shortened until the whole line fits one — a wrapped identity line is the same defect
    /// wearing a different hat.
    private func identityLine(_ f: Franchise) -> String? {
        let genres = f.parts.flatMap(\.genres)
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .map(\.localizedCapitalized)
        var head = [f.kindWord]
        if let y = premiereYear(f) { head.append(String(y)) }
        // The market's own rating sits between the year and the genres, where Apple TV's line
        // puts it ("TV-MA · 2011 · Drama"). Nothing when the catalogue states nothing.
        if let rating = f.contentRatingLabel { head.append(rating) }
        // A conservative character budget for `heroMeta` across the gutter-to-gutter run. It is a
        // budget rather than a measurement on purpose: `minimumScaleFactor` absorbs the last few
        // points, and a `TextRenderer` pass on every identity change is not worth one line of type.
        let budget = isAX ? Int.max : 46
        var tail = Array(genres.prefix(3))
        while true {
            let line = (head + tail).joined(separator: " · ")
            if line.count <= budget || tail.isEmpty { return line }
            tail.removeLast()
        }
    }

    private func addButton(_ f: Franchise) -> some View {
        Button {
            appModel.addToLibrary(franchiseId: f.id, title: f.title, isReleasing: f.isReleasing)
        } label: {
            // A GLYPH, not a word — Apple TV's "+" — as INK on the toolbar's own capsule, sized
            // and framed like the overflow's `···` so the bar's trailing capsules are one pair.
            // "+ Add" was the last piece of prose in the bar (and this SDK broke it "Ad / d");
            // the label below is what VoiceOver says.
            //
            // `interactive`, not `accent`: this glyph sits directly above the episode list's
            // amber "Episode 14 next", so one hue must not mean both "press this" and "this is
            // what's coming". Amber stays on the fact.
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ThemeColor.interactive)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(f.title) to Library")
    }

    private func statusMenu(_ f: Franchise) -> some View {
        Menu {
            ForEach(WatchStatus.menuOrder, id: \.self) { option in
                Button {
                    appModel.setStatus(franchiseId: f.id, status: option)
                } label: {
                    Label(option.displayName, systemImage: f.effectiveStatus == option ? "checkmark" : option.menuGlyph)
                }
            }
        } label: {
            // NO local background. The toolbar item is already a glass capsule; a second capsule
            // inside it is the inner pill that reads as a refraction bug over bright artwork. And
            // the height is the system's 44, so this and the back button share one baseline
            // instead of sitting 8.7 pt apart.
            HStack(spacing: 6) {
                Text(f.effectiveStatus.displayName).type(ThemeType.metadataEmphasis)
                    .contentTransition(.opacity)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(ThemeColor.textPrimary)
            .frame(minHeight: 44)
        }
        // Finishing a series is the payoff the app is built around, and the chip flipped to
        // "Finished" with an instant text swap. `uiMilestone` exists for exactly this moment and
        // had no call sites; claimed through the sweep ledger, it fires once per commit.
        .milestone(token: milestoneToken, reduceMotion: reduceMotion)
        .accessibilityLabel("Change status, \(f.effectiveStatus.displayName)")
    }

    private func overflowMenu(_ f: Franchise) -> some View {
        Menu {
            if let part = f.currentPart, !part.isUpcoming {
                let behind = max(0, part.markTarget(now: now) - part.progress)
                // The batch options used to hang off a bare chevron floating inside the primary
                // capsule. They live here (and on the capsule's long press) instead.
                // The capsule owns the next-episode verbs; this menu keeps the whole-season and
                // whole-series ones (interactive review: three mark verbs, each on two lines).
                if behind > 0 {
                    Button(Copy.Action.markAllEpisodes) { promptBatchMark(f, part: part, through: part.markTarget(now: now)) }
                }
                if part.progress > 0 {
                    Button(Copy.Action.markAllUnwatched(part.progress)) { promptResetSeason(f, part: part) }
                }
            }
            // Finishing a series ELSEWHERE was eight separate season confirmations.
            //
            // `markCaughtUp` only ever touched the releasing part and `setStatus(.completed)`
            // changed the word without touching a single episode — so a user who watched all 95
            // episodes on television had to walk eight seasons by hand, with the seasons list
            // openly disagreeing with the status chip for the whole journey. One command, one
            // confirmation naming the real total, and one undo that puts every part back.
            if seriesBehind(f) > 0 {
                Button(DetailCopy.markSeriesWatched) { promptMarkSeries(f) }
            }
            if let session = RewatchStore.shared.activeSession(for: f.id) {
                Divider()
                Button(Copy.Action.restartRewatch) { promptRestartRewatch(f, session: session) }
                Button(DetailCopy.stopRewatch) { promptCancelRewatch(f, session: session) }
            }
            // Only when there is something to show. `RewatchStore` records the first watch
            // implicitly, at the moment a REWATCH starts — so a finished show with no rewatch has
            // no session, and this door led to "No watch history yet" on a screen whose card, 40 pt
            // above, said "Watched once". Two answers to the same question.
            if !RewatchStore.shared.sessions(for: f.id).isEmpty {
                Button(Copy.Action.viewWatchHistory) { push(.history(franchiseId: f.id)) }
            }
            Divider()
            RemoveFromLibraryButton(franchise: f, appModel: appModel)
        } label: {
            // No local glass disc: the toolbar item supplies the material, and the item is 44 pt,
            // so this sits on the same baseline as the back button and the status pill.
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ThemeColor.textPrimary)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("More actions")
    }

    // MARK: - Next up card

    struct NextUp: Equatable {
        enum Kind: Equatable { case actionable, backlog, caughtUp, seasonComplete, seriesComplete, waiting }
        let kind: Kind
        let part: FranchisePart?
        /// The STATE, staged in the block's capsule eyebrow — Today's hero grammar ("9 EPISODES
        /// BEHIND", "CAUGHT UP", "COMPLETE"). The fact lines below carry the object; the eyebrow
        /// carries what kind of moment this is.
        let eyebrow: String
        /// The eyebrow's amber dot — a fresh, actionable episode only, like Today's hero.
        var dot: Bool = false
        /// The WHEN, leading the lockup's one line ahead of the fact (Today's grammar, 5 Sep):
        /// today's drop ("Aired 2h ago"), a caught-up show's next airing ("Friday at 7:30 PM").
        var moment: String? = nil
        let line1: String
        let line2: String?
        let line3: String?
        let episode: Int?
        let behind: Int
        var identity: String { "\(kind)/\(part?.mediaId ?? 0)/\(episode ?? 0)" }
        static func == (a: NextUp, b: NextUp) -> Bool { a.identity == b.identity && a.line2 == b.line2 }
    }

    /// The finished state, said once.
    ///
    /// The headline used to be "You’ve finished Attack on Titan" at 22 pt, 180 pt below "Attack on
    /// Titan" at 28 pt: the show's name twice at near-hero weight in one viewport, while the two
    /// facts the card exists to deliver — how many times, and when — sat under it in tertiary grey.
    /// A card headlines its STATE; the identity is the hero's job and the hero already did it.
    private func completeState(_ f: Franchise) -> NextUp {
        let summary = RewatchStore.shared.summary(for: f.id)
        let last = summary.lastCompletedAt.flatMap {
            $0 > 0 ? "Last finished \(TemporalCopy.dateWord($0, now: now, anchor: .local))" : nil
        }
        // A show finished before the app ever saw it has no recorded date. The card still states
        // what was watched rather than leaving the fact column empty beside a 132-pt poster.
        let scale: String? = {
            let episodes = f.episodicPartsInOrder.reduce(0) { $0 + max($1.totalEpisodes, $1.progress) }
            return episodes > 0 ? Copy.episodes(episodes) : nil
        }()
        // The curated "what's next", so this page cannot say COMPLETE while the Library's shelf
        // says "Returns Oct 2026" about the same show — and a rumour is called one.
        let ahead: String? = {
            guard let up = f.upcoming, up.isFutureInstallment, !up.hasArrived(now: now) else { return nil }
            let fact = ReturnFact.of(f, appModel: appModel).text
            if up.isRumored { return fact }
            guard let next = up.next, !next.isEmpty else { return fact }
            return "\(next) \u{00B7} \(fact)"
        }()
        // The fact and its scale on ONE line ("Watched once · 95 episodes"), then the ONE more
        // thing — the curated next, else the date. Three equal grey lines gave the reader
        // nothing to read first (review, 5 Sep).
        let fact = [Copy.Progress.watchedTimes(max(1, summary.completedCount)), scale].compactMap { $0 }
            .joined(separator: " \u{00B7} ")
        return NextUp(kind: .seriesComplete, part: nil, eyebrow: Copy.Label.complete,
                      line1: fact, line2: ahead ?? last, line3: nil, episode: nil, behind: 0)
    }

    private func nextUpState(_ f: Franchise) -> NextUp? {
        if f.isSeriesComplete {
            return completeState(f)
        }
        // A Planned show waits (interactive review: it shouted "2 EPISODES BEHIND" with a "Mark as
        // watched" capsule on a bookmark). The status capsule is the way to start.
        if f.effectiveStatus == .planned, let part = f.currentPart ?? f.resumePart ?? f.releasingPart {
            let next = f.nextAiring(now: now).map { TemporalCopy.airs(at: $0, now: now, source: f.source) }
            return NextUp(kind: .waiting, part: part, eyebrow: Copy.Status(.planned),
                          line1: f.watchContext(part: part, episode: part.progress + 1),
                          line2: next, line3: nil, episode: nil, behind: 0)
        }
        guard let part = f.currentPart else {
            // Nothing to resume: an announced installment waits; a finished run (with extras the
            // catalogue still lists as upcoming) is complete for the viewer.
            if let up = f.parts.first(where: \.isUpcoming) {
                return NextUp(kind: .waiting, part: up, eyebrow: Copy.Label.upcoming,
                              line1: up.canonicalLabel.isEmpty ? up.title : up.canonicalLabel,
                              line2: up.announcedDateLabel(source: f.source).map(TemporalCopy.premieres) ?? TemporalCopy.noDateAnnounced,
                              line3: nil, episode: nil, behind: 0)
            }
            let episodic = f.episodicPartsInOrder
            if !episodic.isEmpty, episodic.allSatisfy(\.isComplete) {
                return completeState(f)
            }
            return nil
        }
        if part.isUpcoming {
            return NextUp(kind: .waiting, part: part, eyebrow: Copy.Label.upcoming,
                          line1: part.canonicalLabel,
                          line2: part.announcedDateLabel(source: f.source).map(TemporalCopy.premieres) ?? TemporalCopy.noDateAnnounced,
                          line3: nil, episode: nil, behind: 0)
        }
        let target = part.markTarget(now: now)
        let behind = max(0, target - part.progress)
        if behind == 0 {
            if part.isComplete && !part.isReleasing {
                let next = f.episodicPartsInOrder.first { $0.isUpcoming }
                return NextUp(kind: .seasonComplete, part: part, eyebrow: Copy.Label.complete,
                              line1: Copy.Progress.complete(part.canonicalLabel),
                              line2: "\(part.canonicalLabel) · \(Copy.Progress.watchedOf(part.progress, max(part.totalEpisodes, part.progress)))",
                              line3: next.map { "\($0.canonicalLabel) \(TemporalCopy.returns(at: $0.premiereAt, now: now, source: f.source).lowercasedFirst())" },
                              episode: nil, behind: 0)
            }
            let nextEp = part.nextEpisodeNumber ?? part.progress + 1
            // The STATE goes to the eyebrow and the EPISODE is the fact (user, 30 Aug): a show
            // airing tonight led with a 22-pt "Caught up" while "Today at 8:30 PM" — the thing the
            // person opened the show for — hid in the support line. "Caught up" is what kind of
            // moment this is; "Season 5 · Episode 10 · airs tonight" is the moment itself.
            // (The shared watch-context rule: a multi-season show names its season here too.)
            // The next airing is the MOMENT, leading the line ("Friday at 7:30 PM · Season 5 ·
            // Episode 10"); only its absence is a support line.
            let next = f.nextAiring(now: now).map { TemporalCopy.airs(at: $0, now: now, source: f.source) }
            return NextUp(kind: .caughtUp, part: part, eyebrow: Copy.Progress.caughtUp,
                          moment: next,
                          line1: f.watchContext(part: part, episode: nextEp),
                          line2: next == nil ? TemporalCopy.noDateAnnounced : nil,
                          line3: nil, episode: nil, behind: 0)
        }
        let episode = part.progress + 1
        let context = f.watchContext(part: part, episode: episode)
        if behind > 1 {
            // The count is the STATE — it stages the block from the eyebrow, as on Today's hero,
            // instead of repeating under the fact as a support line.
            // The one more thing is the DROP while it is fresh — Today's last line, verbatim
            // (review i3: one lockup, two rooms, two different last lines); the cadence
            // returns as the caught-up state's moment the instant the backlog is cleared.
            let last = part.lastAired(now: now, anchor: f.timeAnchor)
            let fresh = last.map { Formatting.dayDiff(ts: $0, now: now, anchor: f.timeAnchor) == 0 } ?? false
            let drop = fresh ? last.map { Copy.Progress.dropAired(episode: part.airedByNow(now: now, anchor: f.timeAnchor),
                                                                  when: TemporalCopy.aired(at: $0, now: now, source: f.source)) } : nil
            return NextUp(kind: .backlog, part: part,
                          eyebrow: part.isReleasing ? Copy.Progress.behind(behind) : Copy.Progress.left(behind),
                          line1: context, line2: drop ?? newEpisodeLine(f),
                          line3: nil, episode: episode, behind: behind)
        }
        // Today's fresh-hero grammar, verbatim (5 Sep): a drop that struck today is "NEW EPISODE"
        // on the badge with its recency leading the line ("Aired 2h ago · Season 4 · Episode
        // 19"); an older single drop wears its day on the badge and has no moment.
        let last = part.lastAired(now: now, anchor: f.timeAnchor)
        let recency = last.map { TemporalCopy.aired(at: $0, now: now, source: f.source) }
        let struck = last.map { Formatting.dayDiff(ts: $0, now: now, anchor: f.timeAnchor) == 0 } ?? false
        // No third line. "Caught up after this episode" restated what the badge and the
        // one-episode CTA already say; the capsule is the sentence.
        return NextUp(kind: .actionable, part: part,
                      eyebrow: struck ? Copy.Label.newEpisode : (recency ?? Copy.Label.newEpisode),
                      dot: true,
                      moment: struck ? recency : nil,
                      line1: context, line2: newEpisodeLine(f),
                      line3: nil, episode: episode, behind: 1)
    }

    /// "New episode Friday at 7:30 PM" — the airing cadence, on the block whose eyebrow says how
    /// far behind you are. Netflix ("New episode coming on Saturday") and Apple TV ("New Episode
    /// Every Wednesday") both put it directly under the lockup; this screen had it nowhere while a
    /// show was behind. Planned shows are off the calendar, so they get no line.
    private func newEpisodeLine(_ f: Franchise) -> String? {
        guard f.tracksAirings, let at = f.nextAiring(now: now) else { return nil }
        return Copy.Progress.newEpisode(when: TemporalCopy.airs(at: at, now: now, source: f.source))
    }

    /// The name the bar can hold: `displayTitle` when it fits at a step of scale, else the
    /// shelf-shortened form, else nil.
    static func dockedName(_ f: Franchise, budget: Int = 19) -> String? {
        if f.displayTitle.count <= budget { return f.displayTitle }
        let short = f.title.shelfShortened
        return short.count <= budget ? short : nil
    }

    /// The title, docked. Visible only once the billboard has left; hidden from VoiceOver until
    /// then so the screen does not announce its name twice.
    private func barTitle(_ f: Franchise) -> some View {
        // The short name every row and shelf uses; the full title is the billboard's. Fit, or
        // shortened, or NOTHING (review i2): between the back circle and two capsules the item
        // has ~150 pt, and "That Time I Got R…" over a season list says less than a bar with no
        // noun — Netflix's show page bar. A character budget, as the identity line uses.
        Text(Self.dockedName(f) ?? "")
            .type(ThemeType.bodyEmphasis)
            .foregroundStyle(ThemeColor.textPrimary)
            .lineLimit(1)
            // "Game of Thr…" between the back circle and two capsules (review, 5 Sep): a step
            // of scale before an ellipsis on the one docked title the app draws for a show.
            .minimumScaleFactor(0.85)
            .allowsTightening(true)
            .opacity(scrolledUnderBar ? 1 : 0)
            .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: scrolledUnderBar)
            .accessibilityHidden(!scrolledUnderBar)
    }

    /// The billboard's copy: the lockup for a show in the library, the name alone otherwise.
    @ViewBuilder
    private func heroCopy(_ f: Franchise) -> some View {
        if inLibrary, let state = nextUpState(f) {
            heroLockup(f, state: state)
        } else {
            HeroTitle(text: f.title, name: f.billboardName,
                      font: isAX ? ThemeType.displayXL : ThemeType.heroTitle,
                      lineLimit: isAX ? nil : 3, minimumScale: 0.85)
                .shadow(.art)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// The show page's lockup — `HeroLockup`, Today's view, fed from `NextUp` (5 Sep): the state
    /// on the badge (an active rewatch prefixes its ordinal name), the FULL title at `heroTitle`
    /// with a scale floor, the moment leading the line, the reveal glyph on the line's trailing
    /// edge, the season bar, the airing cadence as the support line, and beneath it the capsule
    /// (or "Start rewatch"). It replaced the boxed-then-deboxed "Next up" block that sat on the
    /// canvas under the art for a week of rounds: the hero and the block were one thing said in
    /// two places.
    private func heroLockup(_ f: Franchise, state: NextUp) -> some View {
        let committed = committedEpisode != nil && pinned != nil
        let active = RewatchStore.shared.activeSession(for: f.id)
        let bar = heroBar(f, state: state, committed: committed)
        let revealTarget: Int? = {
            guard let part = state.part, let ep = state.episode, canReveal(part, episode: ep) else { return nil }
            return ep
        }()
        return HeroLockup(badge: active.map { "\($0.title) · \(state.eyebrow)" } ?? state.eyebrow,
                          title: f.title,
                          name: f.billboardName,
                          font: isAX ? ThemeType.displayXL : ThemeType.heroTitle,
                          lineLimit: isAX ? nil : 3,
                          minimumScale: 0.85,
                          moment: committed ? nil : state.moment,
                          fact: state.line1,
                          support: secondLine(state),
                          third: state.line3,
                          progress: bar?.ratio,
                          progressSpoken: bar?.spoken,
                          receiptHost: ReceiptHost.detailHero(f.id),
                          accessory: {
                              if !isAX, let ep = revealTarget { revealGlyph(ep) }
                          }) {
            if let part = state.part, let episode = state.episode, state.kind == .actionable || state.kind == .backlog {
                cta(f, part: part, episode: committed ? (committedEpisode ?? episode) : episode, behind: state.behind, committed: committed)
            }
            if state.kind == .seriesComplete && active == nil {
                Button(Copy.Action.startRewatch) { showStartRewatch = true }
                    .buttonStyle(PrimaryButtonStyle2())
                    .transition(.opacity)
            }
            // At accessibility sizes the labelled reveal follows the action rather than sharing
            // a line that is now a column.
            if isAX, let ep = revealTarget {
                revealButton(ep).padding(.top, ThemeSpace.x2)
            }
        }
        // ONE sweep implementation — ledger-claimed, Reduce-Motion branched, keyed on the COMMIT.
        .seasonCompleteSweep(token: state.kind == .seasonComplete ? sweepToken : nil,
                             reduceMotion: reduceMotion)
        .sheet(isPresented: $showStartRewatch) {
            StartRewatchSheet(franchise: f) { scope, startedAt in startRewatch(f, scope: scope, startedAt: startedAt) }
                // `.large` only. At `.medium` the scope list ran past the bottom of the sheet
                // and the commit button — now pinned as a bottom inset — had a list a screen and
                // a half tall above it.
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    /// Today's season bar, on the show page: watched over what there is to watch — aired-by-now
    /// for a releasing season, the available run otherwise — advancing in the same frame as a
    /// mark. Nil when there is nothing to show: nothing watched yet, or everything.
    private func heroBar(_ f: Franchise, state: NextUp, committed: Bool) -> (ratio: Double, spoken: String)? {
        guard state.kind == .actionable || state.kind == .backlog, let part = state.part else { return nil }
        let done = committed ? (committedEpisode ?? part.progress) : part.progress
        let total = part.isReleasing ? part.airedByNow(now: now, anchor: f.timeAnchor) : part.availableEpisodes()
        guard total > 0, done > 0, done < total else { return nil }
        let left = max(0, total - done)
        return (Double(done) / Double(total), part.isReleasing ? Copy.Progress.behind(left) : Copy.Progress.left(left))
    }

    /// The reveal as a GLYPH on the line's trailing edge (5 Sep). The labelled toggle shared the
    /// fact's row and took half of it, so "Season 3 · Episode 8" wrapped mid-phrase with a
    /// dangling middot (Thrones). An eye in a 44-pt target, `textSecondary`, spoken as the
    /// labelled control is; `revealButton` survives at accessibility sizes, under the action.
    private func revealGlyph(_ ep: Int) -> some View {
        let on = revealed.contains(ep)
        return Button {
            withAnimation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion)) {
                if on { revealed.remove(ep) } else { revealed.insert(ep) }
            }
        } label: {
            Image(systemName: on ? "eye.slash" : "eye")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ThemeColor.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? DetailCopy.hideEpisodeTitle : DetailCopy.revealEpisodeTitle)
        .accessibilityAddTraits(.isToggle)
    }

    /// The spoiler control, LABELLED and stateful.
    ///
    /// It is a real `Toggle`, not a button that swaps its own caption: the thing it controls is a
    /// two-state property, and a `Toggle` is the control iOS publishes with a switch trait, a
    /// spoken On/Off value and a legible pressed state. It stays in the neutral ramp — a utility,
    /// not a next step, and the card is allowed exactly one amber object.
    ///
    /// The word "title" alone parses as the SHOW's title in a TV app (and the show's title is
    /// already the largest thing on the screen); what it reveals is the EPISODE's.
    private func revealButton(_ ep: Int) -> some View {
        Toggle(isOn: Binding(
            get: { revealed.contains(ep) },
            set: { on in
                withAnimation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion)) {
                    if on { revealed.insert(ep) } else { revealed.remove(ep) }
                }
            })) {
                HStack(spacing: 6) {
                    Image(systemName: revealed.contains(ep) ? "eye.slash" : "eye")
                        .font(.system(size: 11, weight: .semibold))
                    Text(revealed.contains(ep) ? DetailCopy.hideEpisodeTitle : DetailCopy.revealEpisodeTitle)
                        .type(ThemeType.listAction)
                }
                // A utility, quieter than the eyebrow it shares a row with. It used to be set
                // brighter than the card's own label, so the card's least important control was
                // its second-loudest object.
                .foregroundStyle(ThemeColor.textTertiary)
                .padding(.vertical, ThemeSpace.x2)
                .padding(.leading, ThemeSpace.x3)
                .contentShape(Rectangle())
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()
    }

    /// Under the card once any session exists: the way into watch history (board 06 §1.6).
    @ViewBuilder
    private func historyRow(_ f: Franchise) -> some View {
        let sessions = RewatchStore.shared.sessions(for: f.id)
        if !sessions.isEmpty {
            GroupedList {
                // `symbolTint: .clear` — the glyph sits directly on the plate. A filled 28-pt tile
                // inside a plate is a second container around a symbol, and tiles are for rows that
                // carry ART. And the row states a fact the card above does not: the card says how
                // many times the show was watched, this says how much watching that was.
                GroupedRow(symbol: "clock.arrow.circlepath", symbolTint: .clear,
                           title: Copy.Action.viewWatchHistory,
                           // PREDICATED. "95 episodes" (the work) and "50 episodes" (what the user
                           // watched) sat two taps apart in the same noun phrase, so within one
                           // show the same words meant two different quantities.
                           subtitle: Copy.episodesWatched(sessions.reduce(0) { $0 + $1.episodes }),
                           trailing: .chevron(nil), separator: false) {
                    push(.history(franchiseId: f.id))
                }
            }
        }
    }

    // MARK: - Rewatch

    private func startRewatch(_ f: Franchise, scope: WatchSession.Scope, startedAt: Int64) {
        let parts: [FranchisePart] = {
            switch scope {
            case .franchise: return f.episodicPartsInOrder
            case .part(let mediaId): return f.parts.filter { $0.mediaId == mediaId }
            }
        }()
        let snapshot = parts.map { ($0.mediaId, $0.progress) }
        let previousStatus = f.effectiveStatus
        let episodes = parts.reduce(0) { $0 + max($1.totalEpisodes, $1.progress) }
        let session = RewatchStore.shared.startRewatch(franchiseId: f.id, scope: scope, startedAt: startedAt, episodes: episodes)
        // The rail's arrival is drawn once, on the next Watch history that renders.
        RewatchArrival.record(session.id)
        // A beginning is a commit, not an achievement (review i2): `.success` is the season's.
        FeedbackCoordinator.fire(.commitMedium)
        withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) {
            for (mediaId, progress) in snapshot where progress > 0 {
                appModel.setProgress(franchiseId: f.id, mediaId: mediaId, episodes: 0, haptic: false)
            }
            appModel.setStatus(franchiseId: f.id, status: .watching, haptic: false, present: false)
        }
        appModel.presentUndo(UndoState(mediaId: nil, franchiseId: f.id, prevProgress: 0, title: f.title, episode: 0,
                                       customMessage: Copy.Toast.rewatchStarted) {
            RewatchStore.shared.delete(session.id)
            for (mediaId, progress) in snapshot { appModel.setProgress(franchiseId: f.id, mediaId: mediaId, episodes: progress, haptic: false) }
            appModel.setStatus(franchiseId: f.id, status: previousStatus, haptic: false, present: false)
        })
    }

    private func promptRestartRewatch(_ f: Franchise, session: WatchSession) {
        let watched = f.episodicPartsInOrder.reduce(0) { $0 + $1.progress }
        prompt = WritePrompt(title: Copy.Confirm.restartRewatchTitle, message: Copy.Confirm.restartRewatch(count: watched),
                             confirm: Copy.Confirm.restartRewatchConfirm, destructive: true) {
            FeedbackCoordinator.fire(.commitMedium)
            // The same receipt a season reset gets: a toast that names what moved and an Undo
            // that restores the exact snapshot. It wiped every tick with neither.
            let snapshot = f.episodicPartsInOrder.map { ($0.mediaId, $0.progress) }
            for (mediaId, progress) in snapshot where progress > 0 {
                appModel.setProgress(franchiseId: f.id, mediaId: mediaId, episodes: 0, haptic: false)
            }
            appModel.presentUndo(UndoState(mediaId: nil, franchiseId: f.id, prevProgress: 0, title: f.title, episode: 0,
                                           customMessage: Copy.Toast.rewatchRestarted) {
                for (mediaId, progress) in snapshot where progress > 0 {
                    appModel.setProgress(franchiseId: f.id, mediaId: mediaId, episodes: progress, haptic: false)
                }
            })
        }
    }

    private func promptCancelRewatch(_ f: Franchise, session: WatchSession) {
        let at = f.currentPart?.progress ?? 0
        prompt = WritePrompt(title: Copy.Action.stopRewatchTitle,
                             message: "The session is kept in your history as cancelled at \(Copy.episodeInSentence(at)).",
                             confirm: Copy.Action.stopRewatchConfirm, destructive: true) {
            // Cancelling keeps the record: a commit, not a deletion.
            FeedbackCoordinator.fire(.commitLight)
            RewatchStore.shared.cancel(session.id, atEpisode: at, at: now)
        }
    }

    /// The card's metadata line, with the episode's title appended once it has been revealed.
    ///
    /// The withheld case used to print "Title hidden to avoid spoilers" as a metadata FACT beside
    /// the reveal control — the control and the sentence saying the same thing 100 pt apart, and the
    /// sentence advertising that there is a spoiler to be had. The control is the statement; a card
    /// does not need a caption explaining its own button.
    private func secondLine(_ state: NextUp) -> String? {
        guard state.kind == .actionable, let part = state.part, let ep = state.episode else { return state.line2 }
        let title = revealed.contains(ep)
            ? EpisodeCopy.title(part.episodes.first { $0.number == ep }?.title, franchise: franchiseTitle)
            : nil
        return [state.line2, title].compactMap { $0 }.joined(separator: " · ")
    }

    private var franchiseTitle: String { franchise?.title ?? "" }

    private func canReveal(_ part: FranchisePart, episode: Int) -> Bool {
        guard let e = part.episodes.first(where: { $0.number == episode }) else { return false }
        // Only a REAL title can be revealed. The control used to appear whenever the catalogue held
        // any string at all, including "Episode 19" — so tapping it replaced the fact line with the
        // same words the fact line already carried.
        return EpisodeCopy.title(e.title, franchise: franchiseTitle) != nil
    }

    /// One primary action, and it looks like one.
    ///
    /// The shipped capsule carried a bare `chevron.down` floating at its right inset with no
    /// divider and no target of its own — a button with a decoration on it. The batch options now
    /// live on the capsule's long press (`Menu(primaryAction:)`) and in the overflow, where they
    /// are labelled; the capsule is just the action.
    /// The SHARED split control (`DesignSystem/Primitives.swift`), identical to Today's.
    ///
    /// It was a `Menu(primaryAction:)` here: same amber capsule, but with no chevron, no divider
    /// and no target boundary, so the batch options were reachable only by long press — on the one
    /// surface where a user actually catches up six episodes at a time. The checkmark also drew on
    /// an unbranched `.transition(.scale(0.6))` while Today's identical one was Reduce-Motion
    /// branched, and the label used `.contentTransition(.interpolate)` to morph two unrelated
    /// sentences into an unreadable smear. All three are fixed by using the one implementation.
    @ViewBuilder
    private func cta(_ f: Franchise, part: FranchisePart, episode: Int, behind: Int, committed: Bool) -> some View {
        MarkSplitButton(episode: episode,
                        committed: committed,
                        behind: behind,
                        title: f.title,
                        onMark: { mark(f, part: part) },
                        onMarkThrough: { promptBatchMark(f, part: part, through: $0) },
                        onMarkAll: { promptBatchMark(f, part: part, through: part.markTarget(now: now)) })
    }

    // MARK: - Mark timeline (board 03)

    private func mark(_ f: Franchise, part: FranchisePart) {
        guard committedEpisode == nil else { return }
        let completes = part.progress + 1 >= part.markTarget(now: now) && !part.isReleasing && part.totalEpisodes > 0
        let snapshot = f
        guard let undo = appModel.markNext(franchiseId: f.id, mediaId: part.mediaId, haptic: completes ? .success : .commitLight) else { return }
        if completes {
            sweepToken = UUID()
            let others = f.episodicPartsInOrder.filter { $0.mediaId != part.mediaId }
            let seriesDone = others.allSatisfy(\.isComplete) && !f.parts.contains { $0.isReleasing || $0.isUpcoming }
            if seriesDone {
                milestoneToken = UUID()
                if let active = RewatchStore.shared.activeSession(for: f.id) { RewatchStore.shared.complete(active.id, at: now) }
                appModel.setStatus(franchiseId: f.id, status: .completed, haptic: false, present: false)
            }
        }
        pinned = snapshot
        // The receipt lands IN PLACE, under this capsule (`ReceiptLine` in the lockup).
        pendingUndo = undo.placed(at: ReceiptHost.detailHero(f.id))
        withAnimation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion)) { committedEpisode = undo.episode }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) {
                pinned = nil
                committedEpisode = nil
            } completion: {
                if let u = pendingUndo { appModel.presentUndo(u); pendingUndo = nil }
            }
        }
    }

    // MARK: - Confirmations (exact blast radius)

    struct WritePrompt: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let confirm: String
        var destructive = false
        let perform: () -> Void
    }

    private func promptBatchMark(_ f: Franchise, part: FranchisePart, through: Int) {
        let count = through - part.progress
        guard count > 0 else { return }
        prompt = WritePrompt(title: Copy.Confirm.batchMarkTitle(count),
                             message: Copy.Confirm.batchMarkMessage(from: part.progress, to: through),
                             confirm: Copy.Confirm.batchMarkConfirm(count)) {
            let prev = part.progress
            appModel.setProgress(franchiseId: f.id, mediaId: part.mediaId, episodes: through)
            appModel.presentUndo(UndoState(mediaId: part.mediaId, franchiseId: f.id, prevProgress: prev,
                                           title: f.title, episode: through, count: count)
                                    .placed(at: ReceiptHost.detailHero(f.id)))
        }
    }

    /// Episodes of the whole work that are aired and unwatched. 0 means there is nothing a
    /// series-level mark could do, and the command is not offered.
    private func seriesBehind(_ f: Franchise) -> Int {
        f.episodicPartsInOrder.reduce(0) { total, part in
            total + max(0, part.markTarget(now: now) - part.progress)
        }
    }

    /// "I watched all of this, elsewhere." One confirmation stating the true total, one write per
    /// part with the haptics suppressed, ONE `.success`, and one undo carrying `undoAction` — the
    /// field minted for exactly this multi-write case and, until now, never called.
    private func promptMarkSeries(_ f: Franchise) {
        let behind = seriesBehind(f)
        guard behind > 0 else { return }
        let snapshot = f.episodicPartsInOrder.map { ($0.mediaId, $0.progress) }
        let previousStatus = f.effectiveStatus
        prompt = WritePrompt(title: Copy.Confirm.batchMarkTitle(behind),
                             message: "This marks every episode of \(f.title) as watched, across \(Copy.plural(f.episodicPartsInOrder.count, "season", "seasons")).",
                             confirm: Copy.Confirm.batchMarkConfirm(behind)) {
            for part in f.episodicPartsInOrder {
                let target = part.markTarget(now: now)
                guard target > part.progress else { continue }
                appModel.setProgress(franchiseId: f.id, mediaId: part.mediaId, episodes: target, haptic: false)
            }
            appModel.setStatus(franchiseId: f.id, status: .completed, haptic: false, present: false)
            FeedbackCoordinator.fire(.success)
            milestoneToken = UUID()
            appModel.presentUndo(UndoState(mediaId: nil, franchiseId: f.id, prevProgress: 0,
                                           title: f.title, episode: 0, count: behind,
                                           customMessage: Copy.Toast.batchMarked(title: f.title, behind)) {
                for (mediaId, progress) in snapshot {
                    appModel.setProgress(franchiseId: f.id, mediaId: mediaId, episodes: progress, haptic: false)
                }
                appModel.setStatus(franchiseId: f.id, status: previousStatus, haptic: false, present: false)
            })
        }
    }

    private func promptResetSeason(_ f: Franchise, part: FranchisePart) {
        let total = part.progress
        prompt = WritePrompt(title: Copy.Confirm.resetSeasonTitle(total),
                             message: Copy.Confirm.resetSeason(label: part.canonicalLabel, total: total),
                             confirm: Copy.Confirm.resetSeasonConfirm(total), destructive: true) {
            appModel.setProgress(franchiseId: f.id, mediaId: part.mediaId, episodes: 0)
            appModel.presentUndo(UndoState(mediaId: part.mediaId, franchiseId: f.id, prevProgress: total,
                                           title: f.title, episode: 0, count: total,
                                           customMessage: "\(part.canonicalLabel) marked as unwatched"))
        }
    }

    // MARK: - About

    /// No `ABOUT` label. Three stacked blocks at three weights were saying one thing; a synopsis
    /// under a hero does not need to be announced, and "Read more" is a link, not a 17-pt button.
    @ViewBuilder
    private func about(_ f: Franchise) -> some View {
        let synopsis = Formatting.stripHtml(f.parts.first { !(($0.synopsis ?? "").isEmpty) }?.synopsis)
        VStack(alignment: .leading, spacing: 0) {
            // ONE metadata line — class, year, rating, genres — heading the synopsis, where Apple
            // TV keeps a show's metadata (5 Sep). It used to close the hero's lockup under the
            // name; with the state block folded into the billboard the grey identity line was the
            // last thing on the art and the first thing under it an amber badge.
            // `metadata`, not `heroMeta`: off the art it is a footnote over the paragraph (Apple
            // TV's small grey "TV-MA · 2011 · Drama"), and at the prose's own size the two read
            // as one block with its first line in a different face (captured 5 Sep).
            if let meta = identityLine(f) {
                // The certificate as a TAG (review i3): "TV · 2011 · A · Sci-Fi" set "A" as a
                // stray letter in the sentence; Apple TV, Netflix and Prime outline it.
                identityRow(meta, rating: isAX ? nil : f.contentRatingLabel)
                    .padding(.bottom, synopsis.isEmpty ? 0 : ThemeSpace.x2)
            }
            if !synopsis.isEmpty {
                // Clamped at a WORD (review i5: "he awaken…", "holds the l…"): while the paragraph
                // overflows and is folded, the shown string is pre-cut at the last space inside
                // three lines' budget, so the layout never cuts a glyph.
                let overflows = synopsisFullHeight > synopsisClampedHeight + 1
                Text(synopsisExpanded || !overflows ? synopsis : Self.clampedAtWord(synopsis, budget: Self.synopsisBudget))
                    // `prose`, not `body` — see the token: 17-pt default-leading grey read as an
                    // unstyled default and out-sized the hero's own meta line. Opened leading is
                    // what separates reading text from a label at the same size.
                    .type(ThemeType.prose)
                    .lineSpacing(5)
                    .foregroundStyle(ThemeColor.textSecondary)
                    // Three lines, not four: Apple TV shows two and a MORE. The synopsis is the
                    // one paragraph on a screen the art should carry.
                    .lineLimit(synopsisExpanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    // A link that does nothing teaches that links here do nothing (review i4):
                    // the whole paragraph is measured behind the clamped one.
                    .background {
                        Text(synopsis)
                            .type(ThemeType.prose)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                            .hidden()
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { synopsisFullHeight = $0 }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { synopsisClampedHeight = $0 }
                if synopsisExpanded || overflows {
                Button(synopsisExpanded ? Copy.Action.readLess : Copy.Action.readMore) {
                    withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) { synopsisExpanded.toggle() }
                }
                .buttonStyle(InlineLinkButtonStyle())
                // The style holds its 44-pt target with padding rather than a frame, so the link
                // is pulled back optically onto the gutter without shrinking the target.
                .padding(.leading, -12)
                // -8 (review i3): the link's 44-pt target had opened 27 pt under "Read more"
                // against 17 above it; the style still holds the target.
                .padding(.vertical, -8)
                }
                themesLine(f)
            }
        }
    }

    /// The catalogue's themes — only the ones the identity line's genres do not already say — as
    /// one quiet run under the synopsis (Netflix's "This show is: …"), never a plate of chips.
    @ViewBuilder
    private func themesLine(_ f: Franchise) -> some View {
        let themes = f.themesBeyondGenres.prefix(4)
        // A run of one is not a run (review i5: "Friendship" alone under a paragraph).
        if themes.count >= 2 {
            Text(themes.map(\.localizedCapitalized).joined(separator: " \u{00B7} "))
                .type(ThemeType.metadata)
                .foregroundStyle(ThemeColor.textTertiary)
                .lineLimit(1)
                .padding(.top, ThemeSpace.x2)
        }
    }

    // MARK: - Seasons & movies

    /// Full-width rows on the canvas, sized by their artwork. The plate is gone: a season list is
    /// not a settings group, and 68-pt rows with 8 %-white rules down a stroked box is exactly
    /// what makes a media app read as Settings → General.
    /// A catalogue of featurettes is not a member of the work. TMDB's season 0 on Game of Thrones
    /// carries **300** of them; printed inline after Season 1 with an empty tick column and a
    /// subtitle in a grammar no other row used, it read as "this app thinks there are 300 Game of
    /// Thrones specials" — and a viewer who disbelieves one count disbelieves every count above it.
    private static let extraKinds: Set<PartKind> = [.special, .music]

    // MARK: - Episodes (the season picker, a window of rows, the way to the whole run)

    /// The season the Episodes section shows: the picker's choice, else the season a route landed
    /// on (a Schedule card), else the one the screen is about (airing, resuming, or the earliest
    /// unfinished) when that is a season, else the earliest unfinished season, else the last.
    private func focusSeason(_ f: Franchise) -> FranchisePart? {
        let seasons = f.seasonPartsInOrder
        if let id = selectedSeasonId ?? focus?.mediaId, let p = seasons.first(where: { $0.mediaId == id }) { return p }
        if let c = f.currentPart, let p = seasons.first(where: { $0.mediaId == c.mediaId }) { return p }
        return seasons.first { !$0.isComplete } ?? seasons.last
    }

    /// The episodes, ON the show page (Apple TV, Netflix). "Episodes" is the section's title and
    /// the season is a pill beside it; under them the WHOLE season as rows (`EpisodeList` — a long
    /// run opens on a window around the next episode and grows in place). It was six rows from
    /// the next episode with an "All 24 episodes ›" door to a second screen (4–6 Sep): a list that
    /// began at Episode 19 with the season's first eighteen on another page was "a complete
    /// tangent… a broken experience" (user, 6 Sep). Before that the page listed all eleven parts as
    /// database rows and pushed a screen for the episodes, so which episode was next was never on
    /// the page.
    @ViewBuilder
    private func episodesSection(_ f: Franchise) -> some View {
        if let part = focusSeason(f) {
            VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
                episodesHeader(f, part: part)
                // The billboard's palette, not the poster's: the page is grounded in the billboard's
                // colour now, and a list whose discs and tiles took the poster's warm palette sat
                // brown on The Witcher's teal ground (6 Sep).
                EpisodeList(franchise: f, part: part, tint: DetailTint.quiet(heroTint ?? tint),
                            focusEpisode: focus?.mediaId == part.mediaId ? focus?.episode : nil)
                    .id(part.mediaId)
            }
        }
    }

    /// "Episodes" and, trailing, the season as a capsule menu (`SeasonPill`) — the streaming apps'
    /// grammar: a section labelled Episodes, one "Season 4 ⌄" pill that lists seasons only.
    /// Where-you-are is the bar under it, never "18 of 24" in numerals: beside a window that opened
    /// on Episode 18 the pair read as "showing 18 of 24" (4 Sep).
    private func episodesHeader(_ f: Franchise, part: FranchisePart) -> some View {
        let seasons = f.seasonPartsInOrder
        let total = max(part.totalEpisodes, part.airedEpisodes)
        let watched = min(part.progress, total)
        return VStack(alignment: .leading, spacing: ThemeSpace.x2) {
            HStack(alignment: .center, spacing: ThemeSpace.x2) {
                Text(Copy.Heading.episodes)
                    .type(ThemeType.sectionTitle)
                    .foregroundStyle(ThemeColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: ThemeSpace.x2)
                if seasons.count > 1 {
                    SeasonPill(current: part, seasons: seasons) { id in
                        withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) {
                            selectedSeasonId = id
                        }
                    }
                } else if !part.canonicalLabel.isEmpty {
                    // One season with a name: the name, as a fact, not a control.
                    Text(part.canonicalLabel)
                        .type(ThemeType.metadataEmphasis)
                        .foregroundStyle(ThemeColor.textSecondary)
                        .lineLimit(1)
                }
            }
            if total > 0 {
                ProgressBar(value: Double(watched) / Double(total),
                            spoken: Copy.Progress.watchedOf(watched, total))
            }
        }
        .zIndex(1)
    }

    // MARK: - Catalogue shelves (trailers · people · related · where to watch)

    /// Every trailer and clip the show carries, featured first. A tap plays it in a sheet.
    @ViewBuilder
    private func trailersShelf(_ f: Franchise) -> some View {
        let videos = f.allVideos
        if !videos.isEmpty {
            DetailShelf(title: Copy.Heading.trailers) {
                ForEach(videos) { v in
                    TrailerCard(video: v, showTitle: f.title) { video = v }
                        .matchedTransitionSource(id: v.id, in: trailerZoom)
                }
            }
            .id("anchor-trailers")
        }
    }

    /// The people who made it and the people in it — Apple TV's cast row: a disc, a name, a role.
    @ViewBuilder
    private func peopleShelf(_ f: Franchise) -> some View {
        let people = Array((f.people?.ordered ?? []).prefix(20))
        if !people.isEmpty {
            DetailShelf(title: Copy.Heading.castAndCrew) {
                ForEach(people) { PersonCard(person: $0).frame(maxHeight: .infinity, alignment: .top) }
            }
            .id("anchor-people")
        }
    }

    /// The catalogue's own recommendations, as the shelf card every other shelf draws. A title
    /// the catalogue has not materialised yet is looked up by name on the tap.
    @ViewBuilder
    private func relatedShelf(_ f: Franchise) -> some View {
        let related = Array(f.related.prefix(12))
        if !related.isEmpty {
            DetailShelf(title: Copy.Heading.moreLikeThis) {
                ForEach(related) { r in
                    ShelfCard(title: r.title, reserveTitleLines: true, caption: r.identityLine, poster: r.portraitArt, slot: .shelfMedium) {
                        openRelated(r)
                    }
                    .opacity(resolvingRelated == r.id ? 0.55 : 1)
                    .accessibilityHint(Copy.Accessibility.opensTheShowHint)
                }
            }
            .id("anchor-related")
        }
    }

    private func openRelated(_ r: RelatedTitle) {
        if let id = r.franchiseId {
            push(.detail(franchiseId: id))
            return
        }
        guard resolvingRelated == nil else { return }
        resolvingRelated = r.id
        Task {
            defer { resolvingRelated = nil }
            // The catalogue has not materialised this title yet. An exact-title search asks the
            // server to, and the first same-source hit is the show.
            let res: SearchResponse? = try? await appModel.api.search(query: r.title, exact: true)
            let hits = res?.franchises.filter { $0.source == r.source } ?? []
            let hit = hits.first { $0.title.caseInsensitiveCompare(r.title) == .orderedSame } ?? hits.first
            if let hit {
                push(.detail(franchiseId: hit.id))
            } else {
                appModel.showNotice(Copy.Notice.notInCatalogue)
            }
        }
    }

    /// Streaming, for the viewer's own market: the providers' marks in a row, the header the way
    /// to the options. Drawn only when the catalogue has a match with somewhere to stream — a
    /// section that says "not here" is not a section.
    @ViewBuilder
    private func whereToWatch(_ f: Franchise) -> some View {
        if let availability = providers, availability.status == .available, !availability.providers.isEmpty {
            WatchProvidersRow(availability: availability) {
                if let url = availability.linkURL { openURL(url) }
            }
            .id("anchor-watch")
        }
    }

    // MARK: - Movies & extras (the non-season parts, as a shelf)

    /// Everything that is not a season, as art: films and units the viewer marks whole (a tap
    /// toggles, with Undo), episodic extras — an OVA run, an ONA, a spin-off — that open their own
    /// episode list, and the catalogue's own extras — dimmed, because the app does not count them.
    /// The seasons live in the pill above.
    @ViewBuilder
    private func extrasShelf(_ f: Franchise) -> some View {
        let spine = Set(f.seasonPartsInOrder.map(\.mediaId))
        let parts = f.parts.filter { !spine.contains($0.mediaId) }.sorted { $0.sequence < $1.sequence }
        if !parts.isEmpty {
            VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
                SectionHeaderRow(Copy.Heading.moviesAndExtras)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: ThemeMetrics.shelfGap) {
                        ForEach(parts) { part in extraCard(f, part: part) }
                    }
                    .padding(.leading, ThemeMetrics.gutter)
                    .padding(.vertical, ThemeSpace.x1)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                // Art may run off the trailing edge; TYPE may not. See `shelfScroller`.
                .shelfScroller()
                // The section sits inside the page gutter; the shelf runs edge to edge.
                .padding(.horizontal, -ThemeMetrics.gutter)
            }
        }
    }

    private func extraCard(_ f: Franchise, part: FranchisePart) -> some View {
        let isExtra = Self.extraKinds.contains(part.kind)
        // A run of episodes (an OVA series, an ONA, a spin-off) is marked episode by episode on
        // its own screen; a single unit toggles whole.
        let episodic = !isExtra && part.totalEpisodes > 1
        let facts = partFacts(f, part: part)
        // The same count the unit's list draws (interactive review: "Complete" over a list with
        // four unwatched episodes).
        let settled = !isExtra && part.isFinished
        let caption: String? = isExtra
            ? (part.totalEpisodes > 1 ? Copy.episodes(part.totalEpisodes) : nil)
            : (facts.lead ?? facts.meta)
        return ShelfCard(title: part.canonicalLabel.isEmpty ? part.title : part.canonicalLabel,
                         caption: caption,
                         captionIsLead: facts.lead != nil,
                         poster: part.portraitArt ?? f.portraitArt,
                         slot: .shelfMedium) {
            if isExtra { return }
            if episodic {
                push(.episodes(franchiseId: f.id, mediaId: part.mediaId, focusEpisode: part.progress + 1))
            } else if inLibrary {
                toggleUnit(f, part: part)
            }
        }
        .overlay(alignment: .topTrailing) {
            if settled { settledBadge.padding(6) }
        }
        // A catalogue of featurettes the app does not track is not a control.
        .opacity(isExtra ? 0.6 : 1)
        .allowsHitTesting(!isExtra)
        // Not tappable, so not a button to VoiceOver either — it offered a double-tap that did
        // nothing.
        .accessibilityRemoveTraits(isExtra ? .isButton : [])
        .accessibilityValue(settled ? Copy.Accessibility.complete : "")
        .accessibilityHint(isExtra ? "" : (episodic ? "Opens its episodes" : (inLibrary ? "Toggles watched" : "")))
    }

    /// A settled unit's mark, in the add disc's own geometry: 26 pt, scrim ground, a check.
    private var settledBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(ThemeColor.textPrimary)
            .frame(width: 26, height: 26)
            .background(ThemeColor.scrimStrong, in: Circle())
            .overlay(Circle().strokeBorder(ThemeColor.hairline, lineWidth: 1))
            .accessibilityHidden(true)
    }

    /// A row's facts, split by direction and by KIND: what is coming is `lead` and earns the
    /// accent; where you are is the `progress` bar; words for what has happened are gone (the
    /// tick, the bar and the season's own label say it). "11 of 24 watched" under "9 episodes
    /// behind" under "Season 4" was three lines of text per row on a page the art should carry;
    /// Netflix and Apple TV draw the position as a bar and say nothing.
    private func partFacts(_ f: Franchise, part: FranchisePart) -> (meta: String?, lead: String?, progress: Double?, spokenProgress: String?) {
        if part.isUpcoming {
            if let d = part.announcedDateLabel(source: f.source) { return (nil, TemporalCopy.premieres(d), nil, nil) }
            return (TemporalCopy.noDateAnnounced, nil, nil, nil)
        }
        // The specials bucket is a CATALOGUE, not a run. It lives under its own EXTRAS label now,
        // and it says what it is: a pile of featurettes the app does not count against progress.
        if Self.extraKinds.contains(part.kind) {
            let scale = part.totalEpisodes > 1 ? Copy.episodes(part.totalEpisodes) : "Extras"
            return ("\(scale) · not counted towards progress", nil, nil, nil)
        }
        if part.kind != .season && part.totalEpisodes <= 1 {
            // No "Watched" word: the settled tick in the trailing column is that fact.
            var bits = [part.kind.rawValue.uppercased() == "MOVIE" ? "Film" : part.kind.rawValue.capitalized]
            if let y = part.year { bits.append(String(y)) }
            return (bits.joined(separator: " · "), nil, nil, nil)
        }
        let total = max(part.totalEpisodes, part.airedEpisodes)
        let started = total > 0 && part.progress > 0 && part.progress < total
        let ratio: Double? = started ? Double(min(part.progress, total)) / Double(total) : nil
        let spoken: String? = started ? Copy.Progress.watchedOf(min(part.progress, total), total) : nil
        if part.isReleasing {
            let behind = part.behind(now: now, anchor: f.timeAnchor)
            if behind > 0 { return (nil, Copy.Progress.behind(behind), ratio, spoken) }
            if let at = f.nextAiring(now: now), f.releasingPart?.mediaId == part.mediaId {
                return (nil, TemporalCopy.airs(at: at, now: now, source: f.source), ratio, spoken)
            }
            return (Copy.Progress.caughtUp, nil, ratio, spoken)
        }
        // "You are here." The in-progress season carries the one forward-looking fact.
        if f.currentPart?.mediaId == part.mediaId, part.progress < total {
            return (nil, Copy.Progress.episodeNext(part.progress + 1), ratio, spoken)
        }
        // A FINISHED season says nothing: the tick is the statement.
        if part.isComplete && !part.isReleasing { return (nil, nil, nil, nil) }
        if started {
            return (nil, Copy.Progress.left(total - part.progress), ratio, spoken)
        }
        // Not started: its size, as a count, not "0 of 12 watched".
        return (total > 0 ? Copy.episodes(total) : nil, nil, nil, nil)
    }

    private func toggleUnit(_ f: Franchise, part: FranchisePart) {
        let full = max(part.totalEpisodes, 1)
        let watched = part.progress >= full
        let prev = part.progress
        appModel.setProgress(franchiseId: f.id, mediaId: part.mediaId, episodes: watched ? 0 : full)
        appModel.presentUndo(UndoState(mediaId: part.mediaId, franchiseId: f.id, prevProgress: prev, title: f.title, episode: full,
                                       customMessage: "\(part.canonicalLabel.isEmpty ? part.title : part.canonicalLabel) marked as \(watched ? "unwatched" : "watched")"))
    }
}

// MARK: - Capture driving (DEBUG)

private extension View {
    /// `-detailAnchor trailers|people|related|watch`, `-detailTrailer 1`, `-detailOpenRelated N`
    /// (DEBUG, like `-openTab`): scroll a show page to a catalogue shelf, open its first trailer,
    /// or open the Nth related title — for captures on a simulator that cannot be touched.
    func debugDetailDrive(franchise f: Franchise, proxy: ScrollViewProxy,
                          video: Binding<FranchiseVideo?>,
                          openRelated: @escaping (RelatedTitle) -> Void) -> some View {
        #if DEBUG
        return task {
            let defaults = UserDefaults.standard
            let anchor = defaults.string(forKey: "detailAnchor")
            let trailer = defaults.bool(forKey: "detailTrailer")
            let wantsRelated = defaults.object(forKey: "detailOpenRelated") != nil
            guard anchor != nil || trailer || wantsRelated else { return }
            try? await Task.sleep(for: .seconds(2.5))
            if let anchor { withAnimation { proxy.scrollTo("anchor-\(anchor)", anchor: .top) } }
            if trailer { video.wrappedValue = f.allVideos.first }
            let index = defaults.integer(forKey: "detailOpenRelated")
            if wantsRelated, f.related.indices.contains(index) { openRelated(f.related[index]) }
        }
        #else
        return self
        #endif
    }
}

// MARK: - The Detail veils

/// The two top veils over the show page — the only view here that reads the scroll offset.
private struct DetailVeils: View {
    let scroll: ScrollOffset
    let hardOn: Bool
    /// The floating toolbar's band, safe area included.
    let band: CGFloat
    /// The show's colour as bar ink (`DetailTint.chrome`), so the hardened bar is the show's
    /// glass rather than canvas.
    var color: Color? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            // While ARTWORK is behind the toolbar: a soft veil fading in with the scroll. Mounted
            // only in that phase — a material at opacity 0 is still a backdrop blur.
            if !hardOn, scroll.y > 12 {
                ScrollEdgeChrome(side: .top, height: band + 100)
                    .opacity(scroll.veilOpacity)
                    .transition(.opacity)
            }
            // The bar, once content rather than artwork is behind the toolbar.
            if hardOn {
                ScrollEdgeChrome(side: .top, height: band + ThemeMetrics.barEdgeRamp, holdHeight: band,
                                 color: color)
                    .transition(.opacity)
            }
        }
        .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: hardOn)
        .allowsHitTesting(false)
    }
}

// MARK: - Surface B · Season episodes

struct SeasonEpisodesView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let franchiseId: String
    /// The season the push opened on. The header's picker can move to a sibling season in
    /// place (`selectedMediaId`) — Apple TV's season picker — instead of pop, tap, push.
    let mediaId: Int
    var focusEpisode: Int? = nil

    @State private var selectedMediaId: Int?
    @State private var fetched: Franchise?
    /// The whole-list spoiler switch (season overflow). Per-view, deliberately: it is a viewing
    /// preference for the list in front of you, not an account setting.
    @State private var revealAll = false
    @State private var prompt: FranchiseDetailView.WritePrompt?
    @State private var tint: Color?

    private var now: Int64 { appModel.now }
    /// The show's colour, made fit to sit under type (see `DetailTint`).
    private var quietTint: Color? { DetailTint.quiet(tint) }
    private var franchise: Franchise? { appModel.franchise(id: franchiseId) ?? fetched }
    private var activeMediaId: Int { selectedMediaId ?? mediaId }
    private var part: FranchisePart? {
        guard let f = franchise else { return nil }
        let live = f.parts.first { $0.mediaId == activeMediaId }
        let eps = fetched?.parts.first { $0.mediaId == activeMediaId }?.episodes ?? []
        if let live, live.episodes.isEmpty, !eps.isEmpty { return live.withEpisodes(eps) }
        return live
    }

    var body: some View {
        ZStack {
            ThemeColor.canvas.ignoresSafeArea()
            // The season carries the franchise's colour too — quietly, because this screen is a
            // list and the wash is atmosphere, not identity.
            if let f = franchise {
                // The one wash spec — this list carried a private 0.7 intensity, one of the seven
                // configurations the cohesion pass collapsed.
                ArtBackdrop(url: f.landscapeArt ?? f.portraitArt, tint: tint,
                            height: ThemeMetrics.rootWashHeight,
                            intensity: ThemeMetrics.rootWashIntensity)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)
            }
            if let f = franchise, let part {
                ScrollViewReader { proxy in
                    ScrollView {
                        // A long run (Boruto's 293 episodes) opens on a window around the focused
                        // episode and grows in place (`EpisodeList`); `.id("ep-n")` and the
                        // `proxy.scrollTo` focus jump both still work.
                        seasonHeader(f, part: part)
                            .padding(.horizontal, ThemeMetrics.gutter)
                            .padding(.top, ThemeSpace.x3)
                            .padding(.bottom, ThemeSpace.x3)
                        // The one episode list (`EpisodeList`, shared with the show page), in
                        // full. Re-keyed on the season, so a picker change lands on a fresh list
                        // rather than rows morphing their numbers in place.
                        EpisodeList(franchise: f, part: part, revealAll: revealAll, tint: quietTint,
                                    focusEpisode: focusEpisode)
                            .padding(.horizontal, ThemeMetrics.gutter)
                            .id(activeMediaId)
                    }
                    // A MARGIN, not padding. A complete "Episode 11" row — tile, title and check —
                    // rendered in the strip between the floating pill and the home indicator, and
                    // "Episode 10 · Mhysa" was sliced by the pill's edge with its air date entirely
                    // covered, because padding inside the stack is not an inset for the scroll view.
                    // `pushedScreenChrome()` supplies the base clearance; this widens it while a
                    // sync failure is pending.
                    .contentMargins(.bottom, DetailMetrics.bottomClearance, for: .scrollContent)
                    .scrollIndicators(.hidden)
                    .onAppear {
                        if let focusEpisode {
                            // Twice (interactive review: the list opened at Episode 1 of 24 — the
                            // first pass can run before the lazy rows above the target exist).
                            for delay in [0.4, 1.2] {
                                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                    withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) { proxy.scrollTo("ep-\(focusEpisode)", anchor: .center) }
                                }
                            }
                        }
                    }
                }
            } else {
                episodesSkeleton
            }
        }
        // A REAL navigation bar. This screen used to hide it and hand-build its own — a circular
        // back button, a centred 22-pt title, a circular ellipsis, no material and no scroll edge
        // effect, so the first row was chopped in half under a black band and left a decapitated
        // poster ghost at 50 % alpha. It then repeated itself, printing "Season 3" a second time
        // 150 pt below the first in larger type.
        //
        // The season is the subject, so the season is the title; its progress is the subtitle,
        // which is exactly what `navigationSubtitle` is for; the show's name is one tap back and
        // already at the top of the screen you came from.
        // The bar names the SHOW; the season is the header below, where its poster, its picker
        // and its progress live. The bar used to carry the season and a "11 of 24 watched"
        // subtitle over a list with no art at all — a settings screen for a TV show.
        // The short name, as Detail's docked bar and every row: the full title truncated with an
        // ellipsis in a 200-pt bar is the one place it was still spelled out.
        .navigationTitle(franchise?.displayTitle ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let f = franchise, let part, appModel.isInLibrary(f.id) {
                    seasonOverflow(f, part: part)
                }
            }
        }
        .task { if fetched == nil { fetched = try? await appModel.api.franchise(id: franchiseId) } }
        .task(id: franchise?.portraitArt) { tint = await PaletteCache.shared.resolve(url: franchise?.portraitArt, maxPixel: 420) }
        .confirmationDialog(prompt?.title ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
                            titleVisibility: .visible, presenting: prompt) { p in
            Button(p.confirm, role: p.destructive ? .destructive : nil) { p.perform() }
            Button(Copy.Confirm.cancel, role: .cancel) {}
        } message: { p in
            Text(p.message)
        }
    }

    /// The season's own header, in the app's one landscape grammar: its art as a wide card with
    /// the progress bar inset ON it (`ProgressBanner` — Library's Up Next card), then its name as
    /// a PICKER over the franchise's other seasons (Apple TV's "Season 4 ⌃⌄") with the count on
    /// the baseline — Detail's episodes header, verbatim. Art and a numeral, not a sentence.
    ///
    /// It was a portrait poster beside a title and a thin line — a settings row for a TV show
    /// ("absolutely trash", user, 3 Sep) — and the one place in the app that put a 2:3 cover
    /// next to a column of 16:9 stills.
    private func seasonHeader(_ f: Franchise, part: FranchisePart) -> some View {
        let total = max(part.totalEpisodes, part.airedEpisodes)
        let watched = min(part.progress, max(total, part.progress))
        // The seasons, as the show page's pill lists them; an extra opened from the shelf keeps
        // the whole episodic run as its siblings, so a viewer inside an OVA can still hop.
        let seasons = f.seasonPartsInOrder
        let siblings = seasons.contains { $0.mediaId == part.mediaId } ? seasons : f.episodicPartsInOrder
        // The season's picture where it has a real one (`wideArt(within:)`: a TRUE 16:9 at either
        // level before any banner). "The SEASON's own art" was the rule from 3 Sep, but a season's
        // only landscape is its AniList banner, and its middle third gutter to gutter was a pair of
        // eyes (Slime S4 on production, 4 Sep) while the show had a backdrop one level up.
        let wide = part.wideArt(within: f)
        return VStack(alignment: .leading, spacing: ThemeSpace.x3) {
            ProgressBanner(url: wide.url,
                           portraitSource: wide.portraitSource,
                           progress: total > 0 ? Double(watched) / Double(total) : nil,
                           ultraWide: wide.ultraWide)
                .accessibilityHidden(true)
            HStack(alignment: .center, spacing: ThemeSpace.x2) {
                if siblings.count > 1 {
                    SeasonPill(current: part, seasons: siblings) { selectedMediaId = $0 }
                } else {
                    seasonTitle(part).accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: ThemeSpace.x2)
                // The banner above carries the bar; only a season whose length the catalogue never
                // stated says its count in words.
                if total == 0, part.progress > 0 {
                    Text(Copy.episodes(part.progress) + " watched")
                        .type(ThemeType.metadata)
                        .foregroundStyle(ThemeColor.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The same title the show page heads its episode list with.
    private func seasonTitle(_ part: FranchisePart) -> some View {
        Text(part.canonicalLabel.isEmpty ? part.title : part.canonicalLabel)
            .type(ThemeType.sectionTitle)
            .foregroundStyle(ThemeColor.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    /// Season-wide marks, plus the spoiler switch for the whole list. Same glyph as Detail's
    /// overflow — one overflow grammar across the two screens of a franchise.
    @ViewBuilder
    private func seasonOverflow(_ f: Franchise, part: FranchisePart) -> some View {
        Menu {
            let target = part.markTarget(now: now)
            if target > part.progress {
                Button(Copy.Action.markAll(target - part.progress)) { promptMark(f, part: part, through: target) }
            }
            if part.progress > 0 {
                Button(Copy.Action.markAllUnwatched(part.progress), role: .destructive) { promptUnmark(f, part: part, to: 0) }
            }
            Divider()
            // One switch for the whole list. The app has a spoiler model and used it on the Next
            // up card, then showed every still and every title in the one place where the next ten
            // episodes are all on screen at once. Per-row reveal stays for the one episode you
            // want; this is for the viewer who does not want the question asked.
            Toggle(isOn: $revealAll) {
                Label(DetailCopy.revealEpisodeTitlesAndStills, systemImage: revealAll ? "eye" : "eye.slash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ThemeColor.textPrimary)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Episode actions")
    }

    private var episodesSkeleton: some View {
        // The shape that arrives: the season's wide art card, its title line, then the rows.
        VStack(alignment: .leading, spacing: 0) {
            SkeletonBlock(height: nil, radius: ThemeRadius.card)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .padding(.top, ThemeSpace.x3)
            SkeletonLine(width: 120, height: 20)
                .padding(.top, ThemeSpace.x3)
                .padding(.bottom, ThemeSpace.x3)
            ForEach(0..<8, id: \.self) { _ in
                SkeletonRow(poster: EpisodeArtwork.slot, lines: [190, 120],
                            posterRadius: ThemeRadius.episodeStill, spacing: ThemeMetrics.artGap,
                            height: ThemeMetrics.rowEpisode)
            }
        }
        .padding(.horizontal, ThemeMetrics.gutter)
        .padding(.top, ThemeSpace.x2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func promptMark(_ f: Franchise, part: FranchisePart, through: Int) {
        let count = through - part.progress
        guard count > 0 else { return }
        prompt = .init(title: Copy.Confirm.batchMarkTitle(count), message: Copy.Confirm.batchMarkMessage(from: part.progress, to: through),
                       confirm: Copy.Confirm.batchMarkConfirm(count)) {
            let prev = part.progress
            appModel.setProgress(franchiseId: f.id, mediaId: part.mediaId, episodes: through)
            appModel.presentUndo(UndoState(mediaId: part.mediaId, franchiseId: f.id, prevProgress: prev, title: f.title, episode: through, count: count))
        }
    }

    private func promptUnmark(_ f: Franchise, part: FranchisePart, to: Int) {
        let count = part.progress - to
        guard count > 0 else { return }
        let message = to == 0 ? Copy.Confirm.resetSeason(label: part.canonicalLabel, total: count)
                              : Copy.Confirm.batchMarkMessage(from: part.progress, to: to)
        prompt = .init(title: to == 0 ? Copy.Confirm.resetSeasonTitle(count) : "Mark \(Copy.episodes(count)) as unwatched?",
                       message: message, confirm: to == 0 ? Copy.Confirm.resetSeasonConfirm(count) : "Mark \(Copy.episodes(count)) as unwatched",
                       destructive: true) {
            let prev = part.progress
            appModel.setProgress(franchiseId: f.id, mediaId: part.mediaId, episodes: to)
            appModel.presentUndo(UndoState(mediaId: part.mediaId, franchiseId: f.id, prevProgress: prev, title: f.title, episode: to, count: count,
                                           customMessage: to == 0 ? "\(part.canonicalLabel) marked as unwatched" : "\(Copy.episodes(count)) marked as unwatched"))
        }
    }
}

private extension String {
    func lowercasedFirst() -> String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}

extension String {
    /// A source's proper noun, set the way every other proper noun in the app is set — WITHOUT
    /// flattening an acronym.
    ///
    /// The catalogue hands us "WIT STUDIO", "8bit" and "HBO" in three different conventions and
    /// the hero printed all three verbatim in one type style. `localizedCapitalized` alone is
    /// worse than the disease: it turns HBO into "Hbo". So each word is title-cased *unless* it is
    /// a short all-caps token, which is an acronym and already correct.
    var normalisedProperName: String {
        split(separator: " ", omittingEmptySubsequences: true).map { word -> String in
            let w = String(word)
            let isAcronym = w.count <= 4 && w == w.uppercased() && w.contains { $0.isLetter }
            return isAcronym ? w : w.localizedCapitalized
        }.joined(separator: " ")
    }
}
