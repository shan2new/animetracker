import SwiftUI

// Franchise Detail (spec board 06). The hero is identity; the Next up card owns the single action
// and shares Today's mark timeline (pinned snapshot → result → handoff → toast on settle).
// Seasons & movies are flat rows in the source's own labels; a season pushes its episode list.
// Every write has Undo or a confirmation that states its exact blast radius.
struct FranchiseDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let franchiseId: String
    var focus: EpisodeFocus? = nil
    /// Pushes onto the owning tab's navigation path (Detail is a push, never a sheet).
    var push: (DetailPush) -> Void = { _ in }

    @State private var fetched: Franchise?
    @State private var loading = true
    @State private var loadError = false
    @State private var synopsisExpanded = false
    @State private var revealed: Set<Int> = []          // episode numbers whose title the user revealed
    @State private var tint: Color?
    /// The BANNER's palette, distinct from `tint` (the cover's). The hero's photograph is the
    /// banner, so the colour that continues it below the fold has to come from the banner too —
    /// derived from the cover it landed a warm brown under a magenta-and-cyan neon header, i.e.
    /// two light sources in one hero. The card and the episode tiles keep the cover's palette:
    /// they are the show's identity, not a continuation of this particular photograph.
    @State private var heroTint: Color?

    // Mark timeline (identical to Today)
    @State private var pinned: Franchise?
    @State private var committedEpisode: Int?
    @State private var pendingUndo: UndoState?
    @State private var prompt: WritePrompt?
    @State private var showStartRewatch = false
    /// Minted when a mark completes a season; the hairline sweep draws once per token.
    @State private var sweepToken: UUID?
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

    private var now: Int64 { appModel.now }
    private var isAX: Bool { typeSize.isAccessibilitySize }

    /// The cover's palette, made fit to be a GROUND (see `DetailTint`). The raw palette colour at
    /// full chroma composited to a saturated brown block on a warm poster — and to the *same*
    /// brown block on a magenta-and-cyan one, so the screen's one action card was carrying a
    /// colour that said nothing about the show it was derived from.
    private var cardTint: Color? { DetailTint.quiet(tint) }

    /// The floating sync banner is drawn OVER content rather than inset from it, so while a
    /// failure is pending the last row of any screen is sliced through its glyphs. Until the
    /// banner carries a presented-state content inset of its own, the screens that can show one
    /// make room for it. (Shared-file request filed; this is the local half.)
    private var bottomClearance: CGFloat { DetailMetrics.bottomClearance }

    enum DetailPush: Hashable {
        case episodes(franchiseId: String, mediaId: Int, focusEpisode: Int?)
        case history(franchiseId: String)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            ThemeColor.canvas.ignoresSafeArea()
            // No `ArtBackdrop` here: the hero's `ArtHeader` IS this screen's ambient art, and it
            // hands over to the canvas through `ArtScrim`. Running a blurred wash *behind* the
            // header as well put a 14-level luminance step straight across the screen at the
            // header's bottom edge — a horizontal seam, measured, in the first capture.
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
        // This screen hides its navigation-bar background so the hero can own the top, which means
        // nothing else stops a scrolled season row from landing on the clock. The veil does — with
        // a longer ramp than the default, because here it is dissolving ARTWORK rather than a list,
        // and a 22-pt ramp over a photograph reads as a black bar laid across it.
        .scrollEdgeChrome(topHeight: ThemeMetrics.topSafeInset + 52)
        // The toolbar's own edge, present only once there is content rather than artwork behind
        // the bar. Above the chrome veil, below nothing — it is the last thing over the scroll.
        .overlay(alignment: .top) {
            if scrolledUnderBar { FloatingToolbarVeil().transition(.opacity) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let f = franchise {
                    if inLibrary {
                        statusMenu(f)
                        overflowMenu(f)
                    } else {
                        addButton(f)
                    }
                }
            }
        }
        .task { await load() }
        .onAppear { if let focus { push(.episodes(franchiseId: franchiseId, mediaId: focus.mediaId, focusEpisode: focus.episode)) } }
        .confirmationDialog(prompt?.title ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
                            titleVisibility: .visible, presenting: prompt) { p in
            Button(p.confirm, role: p.destructive ? .destructive : nil) { p.perform() }
            Button(Copy.Confirm.cancel, role: .cancel) {}
        } message: { p in
            Text(p.message)
        }
    }

    // MARK: - Data

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            fetched = try await appModel.api.franchise(id: franchiseId)
            loadError = false
        } catch {
            loadError = true
        }
    }

    /// The live franchise (fresh progress/status from the library) grafted with the detail
    /// fetch's per-episode data. A pinned snapshot wins while the card shows a mark's result.
    private var franchise: Franchise? {
        if let pinned { return pinned }
        guard let base = appModel.franchise(id: franchiseId) ?? fetched else { return nil }
        return merged(base)
    }

    private func merged(_ base: Franchise) -> Franchise {
        guard let fetched, fetched.id == base.id else { return base }
        let byMedia = Dictionary(fetched.parts.map { ($0.mediaId, $0.episodes) }, uniquingKeysWith: { a, _ in a })
        let parts = base.parts.map { p -> FranchisePart in
            if p.episodes.isEmpty, let eps = byMedia[p.mediaId], !eps.isEmpty { return p.withEpisodes(eps) }
            return p
        }
        return Franchise(copying: base, parts: parts)
    }

    private var inLibrary: Bool { appModel.isInLibrary(franchiseId) }
    private var staleAfterFailure: Bool { loadError && fetched != nil }

    // MARK: - Screen

    private func screen(_ f: Franchise) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(f)
                VStack(alignment: .leading, spacing: ThemeMetrics.sectionGap) {
                    if staleAfterFailure {
                        InlineNotice(Copy.Notice.detailEpisodes) { Task { await load() } }
                    }
                    if inLibrary, let state = nextUpState(f) {
                        VStack(alignment: .leading, spacing: ThemeMetrics.cardGap) {
                            nextUpCard(f, state: state)
                                .id(state.identity)
                                .transition(.opacity.combined(with: .offset(y: 6)))
                            historyRow(f)
                        }
                    }
                    about(f)
                    partsList(f)
                }
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.top, ThemeMetrics.heroClearance)
                .padding(.bottom, bottomClearance)
                .animation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion), value: nextUpState(f)?.identity)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y > Self.heroArtHeight - 130
        } action: { _, under in
            withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) { scrolledUnderBar = under }
        }
        .task(id: f.cover) { tint = await PaletteCache.shared.resolve(url: f.cover, maxPixel: 420) }
        .task(id: f.banner ?? f.cover) { heroTint = await PaletteCache.shared.resolve(url: f.banner ?? f.cover, maxPixel: 420) }
    }

    // MARK: - Hero (identity only)

    /// Full-bleed backdrop, the poster floating half over its lower edge, then the title at full
    /// width. This is the screen's one cinematic moment.
    ///
    /// The shipped hero was a 96×144 poster beside three left-aligned lines of decreasing grey —
    /// a contact card, with ≈ 200 pt of dead canvas to the right of the poster. Every franchise in
    /// this library carries a wide `banner`, and it was never drawn anywhere in the app. Now it
    /// is the material the top of the screen is made of: art edge to edge, handed over to the
    /// canvas by `ArtScrim`, with the `.hero` poster (112×168) and its `.artHero` contact shadow
    /// sitting across the seam so the two layers read as one object.
    private static let heroArtHeight: CGFloat = 320
    private static let posterOverlap: CGFloat = 104
    /// How far the show's colour keeps going after the photograph stops.
    private static let heroBloomHeight: CGFloat = 220

    private func hero(_ f: Franchise) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // The top scrim is light: the scroll-edge veil above already owns the status-bar band,
            // and darkening the art twice is how a hero turns into a grey rectangle.
            ArtHeader(url: f.banner ?? f.cover, height: Self.heroArtHeight, tint: heroTint ?? tint,
                      scrimTop: 0.45, scrimBottom: 1) { EmptyView() }
            VStack(alignment: .leading, spacing: 0) {
                DetailPoster(url: f.cover, slot: .hero)
                SectionLabel(text: eyebrow(f))
                    .padding(.top, ThemeMetrics.artGap)
                Text(f.title)
                    .type(ThemeType.heroTitle)
                    .foregroundStyle(ThemeColor.textPrimary)
                    .lineLimit(isAX ? nil : 2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                if !metaLine(f).isEmpty {
                    Text(metaLine(f))
                        .type(ThemeType.heroMeta)
                        .foregroundStyle(ThemeColor.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, ThemeMetrics.titleGap)
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .padding(.top, -Self.posterOverlap)
        }
        .background(alignment: .top) {
            heroBloom
                .frame(height: Self.heroBloomHeight)
                .padding(.top, Self.heroArtHeight)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
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
    private var heroBloom: some View {
        let base = heroTint ?? tint ?? PaletteCache.fallback
        return ZStack {
            LinearGradient(stops: [
                .init(color: base.opacity(0), location: 0.00),
                .init(color: base.opacity(0.20), location: 0.30),
                .init(color: base.opacity(0.07), location: 0.70),
                .init(color: base.opacity(0), location: 1.00),
            ], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [base.opacity(0.16), .clear],
                           center: .init(x: 0.18, y: 0.12), startRadius: 0, endRadius: 300)
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(ThemeMotion.uiPoster, value: heroTint == nil)
    }

    /// The loading shape has to be the shape that arrives. `Skeleton.detail` still models the old
    /// poster-beside-title hero, so the swap would land as a layout jump; this is the new one.
    private var detailSkeleton: some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 0) {
                SkeletonPoster(width: PosterSize.hero.size.width, height: PosterSize.hero.size.height,
                               radius: PosterSize.hero.radius)
                SkeletonLine(width: 84, height: 10).padding(.top, ThemeMetrics.artGap)
                SkeletonLine(width: 250, height: 26).padding(.top, 8)
                SkeletonLine(width: 176, height: 13).padding(.top, 8)
            }
            .padding(.top, Self.heroArtHeight - Self.posterOverlap)
            SkeletonCard(height: 190) {}
            VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                SkeletonLine(height: 12)
                SkeletonLine(height: 12)
                SkeletonLine(width: 210, height: 12)
            }
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonRow(poster: PosterSize.row.size, lines: [150, 104],
                                posterRadius: PosterSize.row.radius, spacing: ThemeMetrics.artGap)
                }
            }
        }
        .padding(.horizontal, ThemeMetrics.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(edges: .top)
    }

    private func eyebrow(_ f: Franchise) -> String {
        var bits = [f.kindWord]
        if let y = f.parts.compactMap(\.year).min() { bits.append(String(y)) }
        if f.isReleasing { bits.append("Airing") }
        return bits.joined(separator: " · ")
    }

    private func metaLine(_ f: Franchise) -> String {
        let studio = f.parts.flatMap(\.studios).first
        let genres = f.parts.flatMap(\.genres).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.prefix(studio == nil ? 3 : 2)
        return (Array(genres) + [studio].compactMap { $0 }).joined(separator: " · ")
    }

    private func addButton(_ f: Franchise) -> some View {
        Button {
            appModel.addToLibrary(franchiseId: f.id, title: f.title, isReleasing: f.isReleasing)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                Text(Copy.Action.add).type(ThemeType.button)
            }
            .foregroundStyle(ThemeColor.onAccent)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(ThemeColor.accent, in: Capsule())
            .frame(minHeight: 44)
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
            HStack(spacing: 6) {
                Text(f.effectiveStatus.displayName).type(ThemeType.metadataEmphasis)
                    .contentTransition(reduceMotion ? .opacity : .interpolate)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(ThemeColor.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            // `chromeGlass`, not `glassChrome`: it carries the Reduce Transparency fallback.
            .chromeGlass(in: Capsule(), interactive: true)
            .frame(minHeight: 44)
        }
        .accessibilityLabel("Change status, \(f.effectiveStatus.displayName)")
    }

    private func overflowMenu(_ f: Franchise) -> some View {
        Menu {
            if let part = f.currentPart, !part.isUpcoming {
                let behind = max(0, part.markTarget(now: now) - part.progress)
                // The batch options used to hang off a bare chevron floating inside the primary
                // capsule. They live here (and on the capsule's long press) instead.
                if behind > 1 {
                    let through = min(part.progress + 5, part.markTarget(now: now))
                    if through > part.progress + 1 {
                        Button(Copy.Action.markThrough(through)) { promptBatchMark(f, part: part, through: through) }
                    }
                }
                if behind > 0 {
                    Button(Copy.Action.markAllEpisodes) { promptBatchMark(f, part: part, through: part.markTarget(now: now)) }
                }
                if part.progress > 0 {
                    Button(Copy.Action.markAllUnwatched(part.progress)) { promptResetSeason(f, part: part) }
                }
                Button(Copy.Action.viewEpisodes) { push(.episodes(franchiseId: f.id, mediaId: part.mediaId, focusEpisode: nil)) }
            }
            if let session = RewatchStore.shared.activeSession(for: f.id) {
                Divider()
                Button(Copy.Action.restartRewatch) { promptRestartRewatch(f, session: session) }
                Button("Cancel rewatch\u{2026}") { promptCancelRewatch(f, session: session) }
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
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ThemeColor.textPrimary)
                .frame(width: 34, height: 34)
                .chromeGlass(in: Circle(), interactive: true)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("More actions")
    }

    // MARK: - Next up card

    struct NextUp: Equatable {
        enum Kind: Equatable { case actionable, backlog, caughtUp, seasonComplete, seriesComplete, waiting }
        let kind: Kind
        let part: FranchisePart?
        let line1: String
        let line2: String?
        let line3: String?
        let episode: Int?
        let behind: Int
        var identity: String { "\(kind)/\(part?.mediaId ?? 0)/\(episode ?? 0)" }
        static func == (a: NextUp, b: NextUp) -> Bool { a.identity == b.identity && a.line2 == b.line2 }
    }

    private func nextUpState(_ f: Franchise) -> NextUp? {
        if f.isSeriesComplete {
            let summary = RewatchStore.shared.summary(for: f.id)
            return NextUp(kind: .seriesComplete, part: nil, line1: "You’ve finished \(f.title)",
                          line2: Copy.Progress.watchedTimes(max(1, summary.completedCount)),
                          line3: summary.lastCompletedAt.flatMap { $0 > 0 ? "Last finished \(TemporalCopy.dateWord($0, now: now, anchor: .local))" : nil },
                          episode: nil, behind: 0)
        }
        guard let part = f.currentPart else {
            // Nothing to resume: an announced installment waits; a finished run (with extras the
            // catalogue still lists as upcoming) is complete for the viewer.
            if let up = f.parts.first(where: \.isUpcoming) {
                return NextUp(kind: .waiting, part: up, line1: up.canonicalLabel.isEmpty ? up.title : up.canonicalLabel,
                              line2: up.announcedDateLabel(source: f.source).map { "Premieres \($0)" } ?? "No date announced",
                              line3: nil, episode: nil, behind: 0)
            }
            let episodic = f.episodicPartsInOrder
            if !episodic.isEmpty, episodic.allSatisfy(\.isComplete) {
                let summary = RewatchStore.shared.summary(for: f.id)
                return NextUp(kind: .seriesComplete, part: nil, line1: "You’ve finished \(f.title)",
                              line2: Copy.Progress.watchedTimes(max(1, summary.completedCount)),
                              line3: summary.lastCompletedAt.flatMap { $0 > 0 ? "Last finished \(TemporalCopy.dateWord($0, now: now, anchor: .local))" : nil },
                              episode: nil, behind: 0)
            }
            return nil
        }
        if part.isUpcoming {
            return NextUp(kind: .waiting, part: part, line1: part.canonicalLabel,
                          line2: part.announcedDateLabel(source: f.source).map { "Premieres \($0)" } ?? "No date announced",
                          line3: nil, episode: nil, behind: 0)
        }
        let target = part.markTarget(now: now)
        let behind = max(0, target - part.progress)
        if behind == 0 {
            if part.isComplete && !part.isReleasing {
                let next = f.episodicPartsInOrder.first { $0.isUpcoming }
                return NextUp(kind: .seasonComplete, part: part, line1: Copy.Progress.complete(part.canonicalLabel),
                              line2: "\(part.canonicalLabel) · \(Copy.Progress.watchedOf(part.progress, max(part.totalEpisodes, part.progress)))",
                              line3: next.map { "\($0.canonicalLabel) \(TemporalCopy.returns(at: $0.premiereAt, now: now, source: f.source).lowercasedFirst())" },
                              episode: nil, behind: 0)
            }
            let nextEp = part.nextEpisodeNumber ?? part.progress + 1
            let when: String = {
                if let at = f.nextAiring(now: now) { return "\(Copy.episode(nextEp)) · \(TemporalCopy.airs(at: at, now: now, source: f.source))" }
                return "No date announced"
            }()
            return NextUp(kind: .caughtUp, part: part, line1: Copy.Progress.caughtUp, line2: when, line3: nil, episode: nil, behind: 0)
        }
        let episode = part.progress + 1
        let context = f.parts.count > 1 ? part.watchContext(episode: episode) : Copy.episode(episode)
        if behind > 1 {
            return NextUp(kind: .backlog, part: part, line1: context, line2: Copy.Progress.behind(behind),
                          line3: nil, episode: episode, behind: behind)
        }
        let aired: String? = part.lastAiredAt.map { TemporalCopy.aired(at: $0, now: now, source: f.source) }
        return NextUp(kind: .actionable, part: part, line1: context, line2: aired,
                      line3: Copy.Progress.caughtUpAfterThisEpisode, episode: episode, behind: 1)
    }

    /// The one card on the screen that carries an action.
    ///
    /// It is a `.art(tint)` surface — a lit, art-derived ground with a hairline along its top edge
    /// — not a flat rectangle inside a warm outline. The outline it used to carry was the single
    /// most bolted-in object in the build: a card that needs a border to be visible is at the
    /// wrong elevation, and no amount of border fixes that.
    @ViewBuilder
    private func nextUpCard(_ f: Franchise, state: NextUp) -> some View {
        let committed = committedEpisode != nil && pinned != nil
        let active = RewatchStore.shared.activeSession(for: f.id)
        let isFact = state.kind == .actionable || state.kind == .backlog
        VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
            // The label row carries the spoiler control on its trailing edge — the one place on
            // the card where nothing else wants to be. Beside the fact it forced "Season 7 ·
            // Episode 2" to wrap and orphaned the separator at the end of the first line; stacked
            // under the metadata it left the 96×54 tile beside 50 pt of empty card.
            HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x3) {
                // One treatment, conditional on ACTIONABILITY rather than on nothing. The label
                // was amber-with-a-dot on `.actionable` (exactly one episode pending) and plain
                // grey on `.backlog` (six pending) — so two Detail screens showed the same card
                // two ways, and the louder one was on the less urgent state. It is amber whenever
                // there is an episode waiting, which is what "Next up" means.
                let pending = state.episode != nil
                SectionLabel(text: state.kind == .seasonComplete || state.kind == .seriesComplete ? "Complete" : (active.map { "\($0.title) · Next up" } ?? "Next up"),
                             dot: pending, tint: pending ? ThemeColor.accent : ThemeColor.textTertiary)
                Spacer(minLength: 0)
                if !isAX, let part = state.part, let ep = state.episode, canReveal(part, episode: ep) {
                    revealButton(ep)
                }
            }
            let layout = isAX ? AnyLayout(VStackLayout(alignment: .leading, spacing: ThemeSpace.x3))
                              : AnyLayout(HStackLayout(alignment: .top, spacing: ThemeMetrics.artGap))
            layout {
                if let part = state.part, let ep = state.episode {
                    let episode = part.episodes.first { $0.number == ep }
                    let safe = revealed.contains(ep)
                    // The same 96×54 rectangle whether or not a still exists. Where there is no
                    // still — or where there is one and it is being withheld — the rectangle
                    // carries the episode's IDENTIFIER on the show's colour. A `play.rectangle` at
                    // 34 % over a brown block is what a failed image load looks like, and it was
                    // the first object inside the only card on the screen that does anything.
                    if safe, let still = episode?.still, !still.isEmpty {
                        EpisodeArtwork(url: still, spoilerSafe: true, showTint: cardTint)
                    } else if !isAX {
                        // At AX sizes the card is a VStack, so the tile stops being a column
                        // beside the text and becomes a 96-pt object stacked on top of it,
                        // dominating the card — and it is saying exactly what the line under it
                        // already says. A real still is content and stays; a repeat of the fact
                        // does not. (In the episode LIST it always stays: there the tile is the
                        // list's rhythm, not a decoration.)
                        EpisodeIdentifierTile(tint: cardTint, identifier: part.tileIdentifier(episode: ep))
                    }
                } else {
                    // No episode to point at — waiting on an announced installment, caught up, or
                    // finished. The card still gets identity art: the part's own poster, or the
                    // franchise's. Without it these states rendered as a 200-pt empty box with two
                    // lines of text in the corner, which is what "Movie 2 / No date announced"
                    // looked like on a screen whose whole subject is artwork.
                    //
                    // On the complete state there is no part, and `f.cover` is the poster already
                    // hanging 400 pt above it in the hero: the card printed the same artwork
                    // twice. The last installment's own cover is the same show and a different
                    // picture, which is what "you finished all of this" should look like.
                    DetailPoster(url: state.part?.cover ?? f.episodicPartsInOrder.last?.cover ?? f.cover, slot: .row)
                }
                VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                    // The fact the card exists to deliver is `textPrimary`. It was rendered in the
                    // same grey ramp as its own footnote.
                    Text(state.line1)
                        .type(isFact ? ThemeType.cardFact : ThemeType.showTitleL)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .contentTransition(.numericText())
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let l2 = secondLine(state) {
                        Text(l2).type(ThemeType.metadata).foregroundStyle(ThemeColor.textTertiary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    if let l3 = state.line3 {
                        Text(l3).type(ThemeType.metadata).foregroundStyle(ThemeColor.textTertiary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    // At AX sizes the row is already a VStack, so the control sits under the text
                    // rather than beside it; nothing is ever pushed off the trailing edge.
                    if isAX, let part = state.part, let ep = state.episode, canReveal(part, episode: ep) {
                        revealButton(ep)
                    }
                }
                Spacer(minLength: 0)
            }
            if let part = state.part, let episode = state.episode, state.kind == .actionable || state.kind == .backlog {
                cta(f, part: part, episode: committed ? (committedEpisode ?? episode) : episode, behind: state.behind, committed: committed)
                    .padding(.top, ThemeSpace.x1)
            }
            if state.kind == .seriesComplete && active == nil {
                Button(Copy.Action.startRewatch) { showStartRewatch = true }
                    .buttonStyle(PrimaryButtonStyle2())
                    .padding(.top, ThemeSpace.x1)
                    .transition(.opacity)
            }
        }
        .padding(ThemeSpace.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(.art(cardTint), radius: ThemeRadius.card)
        .overlay(alignment: .top) {
            if state.kind == .seasonComplete, let token = sweepToken {
                SeasonSweepHairline(token: token).padding(.horizontal, 1)
            }
        }
        .sheet(isPresented: $showStartRewatch) {
            StartRewatchSheet(franchise: f) { scope, startedAt in startRewatch(f, scope: scope, startedAt: startedAt) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    /// The spoiler control, LABELLED. An unlabelled eye floating at the trailing edge of a card is
    /// a decoration; "Show title" is a control. It stays in the neutral ramp — it is a utility,
    /// not a next step, and the card is only allowed one amber object.
    private func revealButton(_ ep: Int) -> some View {
        Button {
            withAnimation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion)) {
                if revealed.contains(ep) { revealed.remove(ep) } else { revealed.insert(ep) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: revealed.contains(ep) ? "eye.slash" : "eye")
                    .font(.system(size: 12, weight: .semibold))
                Text(revealed.contains(ep) ? Copy.Action.hideTitle : Copy.Action.showTitle)
                    .type(ThemeType.metadataEmphasis)
            }
            .foregroundStyle(ThemeColor.textSecondary)
            .padding(.vertical, ThemeSpace.x2)
            .padding(.leading, ThemeSpace.x3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(revealed.contains(ep) ? Copy.Action.hideTitle : Copy.Action.showTitle)
    }

    /// Under the card once any session exists: the way into watch history (board 06 §1.6).
    @ViewBuilder
    private func historyRow(_ f: Franchise) -> some View {
        let sessions = RewatchStore.shared.sessions(for: f.id)
        if !sessions.isEmpty {
            GroupedList {
                // The symbol tile keeps the default neutral. In `accentSoft` it was a third amber
                // object on a screen whose only amber should be its one primary action — and a
                // navigational row is not an action, it is a door.
                GroupedRow(symbol: "clock.arrow.circlepath", title: Copy.Action.viewWatchHistory,
                           subtitle: Copy.watchSessions(sessions.count),
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
        FeedbackCoordinator.fire(.success)
        withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) {
            for (mediaId, progress) in snapshot where progress > 0 {
                appModel.setProgress(franchiseId: f.id, mediaId: mediaId, episodes: 0, haptic: false)
            }
            appModel.setStatus(franchiseId: f.id, status: .watching, haptic: false)
        }
        appModel.presentUndo(UndoState(mediaId: nil, franchiseId: f.id, prevProgress: 0, title: f.title, episode: 0,
                                       customMessage: "Rewatch started") {
            RewatchStore.shared.delete(session.id)
            for (mediaId, progress) in snapshot { appModel.setProgress(franchiseId: f.id, mediaId: mediaId, episodes: progress, haptic: false) }
            appModel.setStatus(franchiseId: f.id, status: previousStatus, haptic: false)
        })
    }

    private func promptRestartRewatch(_ f: Franchise, session: WatchSession) {
        let watched = f.episodicPartsInOrder.reduce(0) { $0 + $1.progress }
        prompt = WritePrompt(title: Copy.Confirm.restartRewatchTitle, message: Copy.Confirm.restartRewatch(count: watched),
                             confirm: Copy.Confirm.restartRewatchConfirm, destructive: true) {
            FeedbackCoordinator.fire(.success)
            for part in f.episodicPartsInOrder where part.progress > 0 {
                appModel.setProgress(franchiseId: f.id, mediaId: part.mediaId, episodes: 0, haptic: false)
            }
        }
    }

    private func promptCancelRewatch(_ f: Franchise, session: WatchSession) {
        let at = f.currentPart?.progress ?? 0
        prompt = WritePrompt(title: "Cancel this rewatch?",
                             message: "The session is kept in your history as cancelled at \(Copy.episodeInSentence(at)).",
                             confirm: "Cancel rewatch", destructive: true) {
            FeedbackCoordinator.fire(.destructive)
            RewatchStore.shared.cancel(session.id, atEpisode: at, at: now)
        }
    }

    private func secondLine(_ state: NextUp) -> String? {
        guard state.kind == .actionable, let part = state.part, let ep = state.episode else { return state.line2 }
        let episode = part.episodes.first { $0.number == ep }
        let title: String? = {
            guard let t = episode?.title, !t.isEmpty else { return nil }
            return revealed.contains(ep) ? t : "Title hidden to avoid spoilers"
        }()
        return [state.line2, title].compactMap { $0 }.joined(separator: " · ")
    }

    private func canReveal(_ part: FranchisePart, episode: Int) -> Bool {
        guard let e = part.episodes.first(where: { $0.number == episode }) else { return false }
        return (e.title?.isEmpty == false) || e.still != nil
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
                if let active = RewatchStore.shared.activeSession(for: f.id) { RewatchStore.shared.complete(active.id, at: now) }
                appModel.setStatus(franchiseId: f.id, status: .completed, haptic: false)
            }
        }
        pinned = snapshot
        pendingUndo = undo
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
                                           title: f.title, episode: through, count: count))
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
        if !synopsis.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(synopsis)
                    .type(ThemeType.body)
                    .foregroundStyle(ThemeColor.textSecondary)
                    .lineLimit(synopsisExpanded ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
                Button(synopsisExpanded ? "Read less" : "Read more") {
                    withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) { synopsisExpanded.toggle() }
                }
                .buttonStyle(InlineLinkButtonStyle())
                // The style holds its 44-pt target with padding rather than a frame, so the link
                // is pulled back optically onto the gutter without shrinking the target.
                .padding(.leading, -12)
                .padding(.vertical, -4)
            }
        }
    }

    // MARK: - Seasons & movies

    /// Full-width rows on the canvas, sized by their artwork. The plate is gone: a season list is
    /// not a settings group, and 68-pt rows with 8 %-white rules down a stroked box is exactly
    /// what makes a media app read as Settings → General.
    private func partsList(_ f: Franchise) -> some View {
        let groups = f.sections
        return VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
            SectionHeaderRow("Seasons & movies", count: f.parts.count)
            VStack(spacing: 0) {
                ForEach(groups, id: \.kind) { group in
                    ForEach(group.parts) { part in
                        partRow(f, part: part, isLast: group.kind == groups.last?.kind && part.id == group.parts.last?.id)
                    }
                }
            }
        }
    }

    private func partRow(_ f: Franchise, part: FranchisePart, isLast: Bool) -> some View {
        let episodic = part.kind == .season || part.totalEpisodes > 1
        let settled = part.isComplete && !part.isReleasing
        let facts = partFacts(f, part: part)
        return MediaRow(title: part.canonicalLabel.isEmpty ? part.title : part.canonicalLabel,
                        meta: facts.meta,
                        lead: facts.lead,
                        poster: part.cover ?? f.cover,
                        slot: .row,
                        // ONE glyph species down the column, and only where it says something.
                        // A chevron on two rows of nine implied the other seven were not
                        // tappable, and alternated glyph species down a list where every row goes
                        // to the same place. Every row is the target; its title carries that.
                        chevron: false,
                        separator: !isLast,
                        trailing: { if settled { PassiveTick() } }) {
            if episodic { push(.episodes(franchiseId: f.id, mediaId: part.mediaId, focusEpisode: nil)) }
            else if inLibrary { toggleUnit(f, part: part) }
        }
        .accessibilityLabel("\(part.canonicalLabel), \([facts.lead, facts.meta].compactMap { $0 }.joined(separator: ", "))")
        .accessibilityHint(episodic ? "Opens the episode list" : (inLibrary ? "Toggles watched" : ""))
    }

    /// A row's two facts, split by direction: what has happened is neutral `meta`, what is coming
    /// is `lead` and earns the accent. The shipped row put both in the same grey.
    private func partFacts(_ f: Franchise, part: FranchisePart) -> (meta: String?, lead: String?) {
        if part.isUpcoming {
            if let d = part.announcedDateLabel(source: f.source) { return (nil, "Premieres \(d)") }
            return ("No date announced", nil)
        }
        // The specials bucket is a CATALOGUE, not a run. Game of Thrones ships 300 of them, and
        // "0 of 300 watched" printed a 300-episode denominator as if it were progress — truthful,
        // and it destroys trust in every other count on the screen. The count is the fact.
        if part.kind == .special, part.totalEpisodes > 1 {
            return (Copy.episodes(part.totalEpisodes), nil)
        }
        if part.kind != .season && part.totalEpisodes <= 1 {
            var bits = [part.kind.rawValue.uppercased() == "MOVIE" ? "Film" : part.kind.rawValue.capitalized]
            if let y = part.year { bits.append(String(y)) }
            if part.isComplete { bits.append("Watched") }
            return (bits.joined(separator: " · "), nil)
        }
        let total = max(part.totalEpisodes, part.airedEpisodes)
        let watched = total > 0 ? Copy.Progress.watchedOf(min(part.progress, total), total)
                                : Copy.episodes(part.progress) + " watched"
        if part.isReleasing {
            if part.episodesBehind > 0 { return (watched, Copy.Progress.behind(part.episodesBehind)) }
            if let at = f.nextAiring(now: now), f.releasingPart?.mediaId == part.mediaId {
                return (Copy.Progress.caughtUp, TemporalCopy.airs(at: at, now: now, source: f.source))
            }
            return (Copy.Progress.caughtUp, nil)
        }
        // "You are here." The original screen pulled the in-progress season out into its own
        // CURRENTLY WATCHING section with an amber pill; the rebuilt list rendered it in exactly
        // the same grey as the eight finished seasons above it, so nine identical rows said
        // nothing about where the viewer had got to. One forward-looking fact restores it — and a
        // forward-looking fact is the second thing the accent is allowed to be.
        if f.currentPart?.mediaId == part.mediaId, part.progress < total {
            return (watched, Copy.Progress.episodeNext(part.progress + 1))
        }
        return (watched, nil)
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

// MARK: - Surface B · Season episodes

struct SeasonEpisodesView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let franchiseId: String
    let mediaId: Int
    var focusEpisode: Int? = nil

    @State private var fetched: Franchise?
    @State private var revealed: Set<Int> = []
    @State private var prompt: FranchiseDetailView.WritePrompt?
    @State private var tint: Color?

    private var now: Int64 { appModel.now }
    /// The show's colour, made fit to sit under type (see `DetailTint`).
    private var quietTint: Color? { DetailTint.quiet(tint) }
    private var franchise: Franchise? { appModel.franchise(id: franchiseId) ?? fetched }
    private var part: FranchisePart? {
        guard let f = franchise else { return nil }
        let live = f.parts.first { $0.mediaId == mediaId }
        let eps = fetched?.parts.first { $0.mediaId == mediaId }?.episodes ?? []
        if let live, live.episodes.isEmpty, !eps.isEmpty { return live.withEpisodes(eps) }
        return live
    }

    var body: some View {
        ZStack {
            ThemeColor.canvas.ignoresSafeArea()
            // The season carries the franchise's colour too — quietly, because this screen is a
            // list and the wash is atmosphere, not identity.
            if let f = franchise {
                ArtBackdrop(url: f.banner ?? f.cover, tint: tint, height: 320, intensity: 0.7)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)
            }
            if let f = franchise, let part {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: ThemeMetrics.sectionGap) {
                            header(f, part: part)
                            // LAZY. One Piece Season 1 advertises ~1,140 episodes; eagerly building
                            // every row (each with a palette task) is a multi-second freeze on the
                            // push transition and a plausible watchdog termination. `.id("ep-n")`
                            // and the `proxy.scrollTo` focus jump both still work.
                            LazyVStack(spacing: 0) {
                                ForEach(1...max(1, count(part)), id: \.self) { n in
                                    row(f, part: part, n: n, isLast: n == count(part))
                                        .id("ep-\(n)")
                                }
                            }
                        }
                        .padding(.horizontal, ThemeMetrics.gutter)
                        .padding(.top, DetailMetrics.toolbarClearance)
                        .padding(.bottom, DetailMetrics.bottomClearance)
                    }
                    .scrollIndicators(.hidden)
                    .onAppear {
                        if let focusEpisode {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) { proxy.scrollTo("ep-\(focusEpisode)", anchor: .center) }
                            }
                        }
                    }
                }
            } else {
                episodesSkeleton
            }
        }
        .scrollEdgeChrome()
        .overlay(alignment: .top) { FloatingToolbarVeil() }
        // The FRANCHISE, not the season. The season is the subject of the content header below in
        // 20-pt type; printing it again in the navigation bar 30 pt above put the same two words
        // on the screen twice, and left the show's own name nowhere on a screen about it.
        .navigationTitle(franchise?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let f = franchise, let part, appModel.isInLibrary(f.id) {
                    seasonOverflow(f, part: part)
                }
            }
        }
        .task { if fetched == nil { fetched = try? await appModel.api.franchise(id: franchiseId) } }
        .task(id: franchise?.cover) { tint = await PaletteCache.shared.resolve(url: franchise?.cover, maxPixel: 420) }
        .confirmationDialog(prompt?.title ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
                            titleVisibility: .visible, presenting: prompt) { p in
            Button(p.confirm, role: p.destructive ? .destructive : nil) { p.perform() }
            Button(Copy.Confirm.cancel, role: .cancel) {}
        } message: { p in
            Text(p.message)
        }
    }

    private func count(_ part: FranchisePart) -> Int {
        max(part.renderableEpisodeCount(now: now), part.progress, part.episodes.map(\.number).max() ?? 0)
    }

    /// The season is the subject of this screen, so it says so. The shipped header was `1 of 7
    /// watched` in grey beside a lone amber-ringed ellipsis: a progress footnote and a control,
    /// with nothing establishing what the list is of.
    ///
    /// The control is gone from here entirely — it is in the navigation bar, where iOS puts an
    /// overflow and where this screen's sibling (Detail) already puts its own. Floating in the
    /// content it had nothing to align to and settled optically between the season name and its
    /// progress line.
    private func header(_ f: Franchise, part: FranchisePart) -> some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
            Text(part.canonicalLabel.isEmpty ? part.title : part.canonicalLabel)
                .type(ThemeType.sectionTitle)
                .foregroundStyle(ThemeColor.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            let total = max(part.totalEpisodes, part.airedEpisodes)
            ProgressText(total > 0 ? Copy.Progress.watchedOf(min(part.progress, total), total) : Copy.episodes(part.progress) + " watched")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, ThemeSpace.x2)
    }

    /// Season-wide marks. Same glyph on the same glass as Detail's overflow — one overflow
    /// grammar across the two screens of a franchise.
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
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ThemeColor.textPrimary)
                .frame(width: 34, height: 34)
                .chromeGlass(in: Circle(), interactive: true)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Episode actions")
    }

    private var episodesSkeleton: some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                SkeletonLine(width: 120, height: 10)
                SkeletonLine(width: 160, height: 20)
                SkeletonLine(width: 110, height: 12)
            }
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { _ in
                    SkeletonRow(poster: EpisodeArtwork.slot, lines: [190, 120],
                                posterRadius: ThemeRadius.episodeStill, spacing: ThemeMetrics.artGap,
                                height: ThemeMetrics.rowEpisode)
                }
            }
        }
        .padding(.horizontal, ThemeMetrics.gutter)
        .padding(.top, DetailMetrics.toolbarClearance)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ f: Franchise, part: FranchisePart, n: Int, isLast: Bool) -> some View {
        let episode = part.episodes.first { $0.number == n }
        let watched = n <= part.progress
        let aired = !part.isReleasing || n <= part.provenAiredCount(now: now) || n <= part.airedEpisodes
        let isNext = n == part.progress + 1 && aired
        let spoilerSafe = watched || isNext || revealed.contains(n)
        let interactive = appModel.isInLibrary(f.id) && aired
        let canReveal = !spoilerSafe && (episode?.title?.isEmpty == false || episode?.still != nil)
        return HStack(spacing: ThemeSpace.x2) {
            Button { if interactive { tapped(f, part: part, n: n, watched: watched) } } label: {
                HStack(spacing: ThemeMetrics.artGap) {
                    // One 96×54 rectangle for every row, still or not: the shipped list ran two
                    // photographs and then five 48-pt grey squares, so it physically changed shape
                    // halfway down. Where there is no still the rectangle carries the episode's
                    // number on the show's colour — a withheld or missing still is not a broken
                    // one, and a play glyph over nothing is what a broken one looks like.
                    if spoilerSafe, let still = episode?.still, !still.isEmpty {
                        EpisodeArtwork(url: still, spoilerSafe: true, showTint: quietTint)
                    } else {
                        EpisodeIdentifierTile(tint: quietTint, identifier: "E\(n)")
                    }
                    VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                        HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x2) {
                            Text(rowTitle(episode, n: n, spoilerSafe: spoilerSafe))
                                .type(ThemeType.rowTitle)
                                .foregroundStyle(watched ? ThemeColor.textSecondary : ThemeColor.textPrimary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            // The spoiler control belongs to the TITLE it is hiding, not to the
                            // trailing control column — a row has one control column, not a toolbar.
                            if canReveal { revealGlyph(n) }
                        }
                        if let sub = rowSubtitle(f, part: part, episode: episode, n: n, aired: aired, isNext: isNext) {
                            Text(sub.text)
                                .type(sub.accent ? ThemeType.rowMetaLead : ThemeType.rowMeta)
                                .foregroundStyle(sub.accent ? ThemeColor.accent : ThemeColor.textSecondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if aired {
                Button { if interactive { tapped(f, part: part, n: n, watched: watched) } } label: {
                    ZStack {
                        Circle().stroke(isNext ? ThemeColor.accent : ThemeColor.strokeStrong, lineWidth: 1.5)
                            .frame(width: 22, height: 22).opacity(watched ? 0 : 1)
                        // A settled fact is a bare check, not a filled disc: a column of them is a
                        // record of what happened, not a column of disabled controls.
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ThemeColor.textTertiary).opacity(watched ? 1 : 0)
                    }
                    .frame(width: 44, height: 44)
                    .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: watched)
                }
                .buttonStyle(.plain)
                .disabled(!interactive)
                .accessibilityLabel("\(Copy.episode(n)), \(watched ? "watched" : "not watched")")
            }
        }
        .padding(.vertical, ThemeSpace.x2)
        .frame(minHeight: ThemeMetrics.rowEpisode)
        // Unaired rows recede as a group, one opacity — never element-by-element greys.
        .opacity(aired ? 1 : 0.45)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(ThemeColor.separatorQuiet).frame(height: 1)
                    .padding(.leading, EpisodeArtwork.slot.width + ThemeMetrics.artGap)
            }
        }
    }

    private func revealGlyph(_ n: Int) -> some View {
        Button {
            _ = withAnimation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion)) { revealed.insert(n) }
        } label: {
            Image(systemName: "eye")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ThemeColor.textTertiary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The 44-pt target is held by the frame; the row is pulled back optically so a hidden
        // title does not sit 30 pt taller than the row beneath it.
        .padding(.vertical, -14)
        .accessibilityLabel(Copy.Action.showTitle)
    }

    private func rowTitle(_ episode: Episode?, n: Int, spoilerSafe: Bool) -> String {
        if let t = episode?.title, !t.isEmpty, spoilerSafe { return "\(Copy.episode(n)) · \(t)" }
        return Copy.episode(n)
    }

    private func rowSubtitle(_ f: Franchise, part: FranchisePart, episode: Episode?, n: Int, aired: Bool, isNext: Bool) -> (text: String, accent: Bool)? {
        if isNext { return ("Next up", true) }
        if !aired {
            if n == part.airedEpisodes + 1, let at = part.scheduledAiring(now: now, anchor: f.source.timeAnchor) {
                return (TemporalCopy.airs(at: at, now: now, source: f.source), false)
            }
            return ("Upcoming", false)
        }
        if let d = episode?.airDate { return (TemporalCopy.aired(at: d, now: now, source: .tmdb), false) }
        return nil
    }

    private func tapped(_ f: Franchise, part: FranchisePart, n: Int, watched: Bool) {
        if watched {
            if n == part.progress {
                let prev = part.progress
                appModel.setProgress(franchiseId: f.id, mediaId: part.mediaId, episodes: n - 1)
                appModel.presentUndo(UndoState(mediaId: part.mediaId, franchiseId: f.id, prevProgress: prev, title: f.title, episode: n,
                                               customMessage: "\(Copy.episode(n)) marked as unwatched"))
            } else {
                promptUnmark(f, part: part, to: n - 1)
            }
        } else if n == part.progress + 1 {
            let prev = part.progress
            let completes = n >= part.markTarget(now: now) && !part.isReleasing && part.totalEpisodes > 0
            _ = appModel.markNext(franchiseId: f.id, mediaId: part.mediaId, haptic: completes ? .success : .commitLight)
            appModel.presentUndo(UndoState(mediaId: part.mediaId, franchiseId: f.id, prevProgress: prev, title: f.title, episode: n))
        } else {
            promptMark(f, part: part, through: n)
        }
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
                              : "Your progress will move from \(Copy.episodeInSentence(part.progress)) to \(Copy.episodeInSentence(to))."
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


/// The season-complete hairline (board 06 state 6): 1 pt of accent at the card's top inside edge,
/// width 0 → full with `uiSweep`, exactly once per completion token; not drawn under Reduce Motion.
struct SeasonSweepHairline: View {
    let token: UUID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var visible = false

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(ThemeColor.accent)
                .frame(width: geo.size.width * progress, height: 1)
                .opacity(visible ? 1 : 0)
        }
        .frame(height: 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard SeasonSweepLedger.claim(token) else { return }
            visible = true
            // Both curves go through `pick`. The shipped pair were raw `uiSweep` and
            // `uiGentle.delay(0.4)` behind a `!reduceMotion` early return, which meant Reduce
            // Motion did not calm the milestone — it deleted it. A milestone is information; the
            // setting suppresses its THEATRE, not its acknowledgement.
            withAnimation(ThemeMotion.pick(ThemeMotion.uiSweep, reduceMotion: reduceMotion)) {
                progress = 1
            } completion: {
                withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion).delay(0.4)) {
                    visible = false
                }
            }
        }
    }
}
