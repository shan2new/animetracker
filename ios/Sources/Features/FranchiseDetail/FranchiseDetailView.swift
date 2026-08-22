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
            if let f = franchise, inLibrary {
                ToolbarItem(placement: .topBarTrailing) { statusMenu(f) }
                // The spacer is what makes them two capsules rather than two items sharing one:
                // the status pill is a control with a value, the overflow is a menu, and iOS 26
                // draws a break between glass groups exactly here.
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) { overflowMenu(f) }
            } else if let f = franchise {
                ToolbarItem(placement: .topBarTrailing) { addButton(f) }
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
                            // The swap happens in a ZStack, OUT of the flow layout.
                            //
                            // An `.id()` swap with a crossfade keeps BOTH cards in a VStack's
                            // layout for the whole 460 ms, so the block was momentarily two cards
                            // tall and About / Seasons & movies / the history row all shoved down a
                            // card height and lurched back — on every mark made from this screen.
                            // In a ZStack the outgoing and incoming card occupy the same slot, and
                            // the reserved minimum stops the block collapsing between them.
                            ZStack(alignment: .top) {
                                nextUpCard(f, state: state)
                                    .id(state.identity)
                                    // No `.offset(y: 6)`. A card arriving from below while its
                                    // predecessor is still on screen is what the shove looked like.
                                    .transition(.opacity)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
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
                      scrimTop: heroIsDark ? 0.22 : 0.45, scrimBottom: 1) { EmptyView() }
                // The photograph used to stop on a straight full-width line, and the ambient
                // gradient below it started at a different tone — so what you saw was the image's
                // bottom BORDER rather than a handover. Image alpha and scrim now reach zero
                // together, over the final 12 % of the header's height.
                .mask(LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 0) {
                PosterSlot(url: f.cover, .hero).zoomSource("detail/\(f.id)")
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
                if let studio = studioLine(f) {
                    Text(studio)
                        .type(ThemeType.metadata)
                        .foregroundStyle(ThemeColor.textTertiary)
                        .lineLimit(1)
                        .padding(.top, 2)
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
    /// True when the banner's own colour is dark enough that a 0.45 top scrim would leave the hero
    /// at canvas luminance — Game of Thrones' Iron Throne is the case that has no hero moment at
    /// all. Measured off the resolved palette colour rather than off a second decode of the image.
    private var heroIsDark: Bool { Self.lightness(heroTint ?? tint) < 0.34 }

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
            RadialGradient(colors: [base.opacity(0.16 * lift), .clear],
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

    /// `TYPE · YEAR`. Always those two, in that shape.
    ///
    /// The airing state used to be appended on some shows and not others ("ANIME · 2018 · AIRING"
    /// beside "ANIME · 2013"), so the hero's metadata changed length between shows with no rule a
    /// viewer could infer — and the state was already on the toolbar's status pill and, where it
    /// is actionable, on the Next up card. The eyebrow is identity, and identity does not flicker.
    private func eyebrow(_ f: Franchise) -> String {
        var bits = [f.kindWord]
        if let y = premiereYear(f) { bits.append(String(y)) }
        return bits.joined(separator: " · ")
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

    /// Genres only. Two classes were being run through one middot chain — "Action · Adventure ·
    /// 8-bit" reads as a genre for a fantasy isekai, and it inherited three different casing
    /// conventions from three different sources on three screens.
    private func metaLine(_ f: Franchise) -> String {
        f.parts.flatMap(\.genres)
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .prefix(3)
            .map(\.localizedCapitalized)
            .joined(separator: " · ")
    }

    /// The studio / network, on its own line and in its own weight. A production company is not a
    /// genre, so it does not sit in the genre run; and it is normalised, so "WIT STUDIO" and "8bit"
    /// are set the way every other proper noun in the app is set.
    private func studioLine(_ f: Franchise) -> String? {
        guard let studio = f.parts.flatMap(\.studios).first(where: { !$0.isEmpty }) else { return nil }
        return studio.normalisedProperName
    }

    private func addButton(_ f: Franchise) -> some View {
        Button {
            appModel.addToLibrary(franchiseId: f.id, title: f.title, isReleasing: f.isReleasing)
        } label: {
            // Accent INK on the toolbar's own capsule, not an accent capsule inside it. Two
            // stacked capsules is the same doubled material the status pill was drawing.
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                Text(Copy.Action.add).type(ThemeType.button)
            }
            .foregroundStyle(ThemeColor.accent)
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
        return NextUp(kind: .seriesComplete, part: nil,
                      line1: Copy.Progress.watchedTimes(max(1, summary.completedCount)),
                      line2: last ?? scale, line3: last == nil ? nil : scale, episode: nil, behind: 0)
    }

    private func nextUpState(_ f: Franchise) -> NextUp? {
        if f.isSeriesComplete {
            return completeState(f)
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
                return completeState(f)
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
            return NextUp(kind: .backlog, part: part, line1: context, line2: part.isReleasing ? Copy.Progress.behind(behind) : Copy.Progress.left(behind),
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
                // No leading dot. It is 4 pt of decoration that does not scale with its label, so
                // at accessibility sizes it detached from the words it belonged to and floated —
                // and the label is already amber, which is the whole signal.
                SectionLabel(text: state.kind == .seasonComplete || state.kind == .seriesComplete ? "Complete" : (active.map { "\($0.title) · Next up" } ?? "Next up"),
                             tint: pending ? ThemeColor.accent : ThemeColor.textTertiary)
                Spacer(minLength: 0)
                if !isAX, let part = state.part, let ep = state.episode, canReveal(part, episode: ep) {
                    revealButton(ep)
                }
            }
            let layout = isAX ? AnyLayout(VStackLayout(alignment: .leading, spacing: ThemeSpace.x3))
                              : AnyLayout(HStackLayout(alignment: .top, spacing: ThemeMetrics.artGap))
            layout {
                if let part = state.part, let ep = state.episode {
                    // The still, by default. A picture of a place you have not been is not a
                    // spoiler — the episode's NAME is, and that is what the reveal control governs
                    // now. Where the catalogue has no still the same rectangle carries the show's
                    // own colour under a quiet glyph; it never becomes a grey box with text in it,
                    // and it never prints an identifier the fact line 8 pt below already states.
                    let still = part.episodes.first { $0.number == ep }?.still
                    // A real still fills the card's width at accessibility sizes — it is the art,
                    // and art that shrinks as type grows is the wrong way round. A PLACEHOLDER
                    // does not: blown up to 376×211 an empty rectangle with a play glyph in it is
                    // the biggest object on the screen and says nothing.
                    NextUpStill(url: still, tint: cardTint,
                                width: isAX && !(still ?? "").isEmpty ? nil : EpisodeArtwork.slot.width)
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
                    PosterSlot(url: state.part?.cover ?? f.episodicPartsInOrder.last?.cover ?? f.cover, .focus)
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
        // ONE sweep implementation. The fully correct one — ledger-claimed, Reduce-Motion branched,
        // keyed on the COMMIT rather than on the state — lived in the design system and was called
        // from two previews, while this screen ran a second, rawer copy. The copy is gone.
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
                        .font(.system(size: 12, weight: .semibold))
                    Text(revealed.contains(ep) ? Copy.Action.hideTitle : Copy.Action.showTitle)
                        .type(ThemeType.metadataEmphasis)
                }
                .foregroundStyle(ThemeColor.textSecondary)
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
                           subtitle: Copy.episodes(sessions.reduce(0) { $0 + $1.episodes }),
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
                milestoneToken = UUID()
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
    /// A catalogue of featurettes is not a member of the work. TMDB's season 0 on Game of Thrones
    /// carries **300** of them; printed inline after Season 1 with an empty tick column and a
    /// subtitle in a grammar no other row used, it read as "this app thinks there are 300 Game of
    /// Thrones specials" — and a viewer who disbelieves one count disbelieves every count above it.
    private static let extraKinds: Set<PartKind> = [.special, .music]

    private func partsList(_ f: Franchise) -> some View {
        let groups = f.sections
        let members = groups.filter { !Self.extraKinds.contains($0.kind) }
        let extras = groups.filter { Self.extraKinds.contains($0.kind) }.flatMap(\.parts)
        return VStack(alignment: .leading, spacing: ThemeMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
                SectionHeaderRow("Seasons & movies", count: members.reduce(0) { $0 + $1.parts.count })
                VStack(spacing: 0) {
                    ForEach(members, id: \.kind) { group in
                        ForEach(group.parts) { part in
                            partRow(f, part: part,
                                    isLast: group.kind == members.last?.kind && part.id == group.parts.last?.id)
                        }
                    }
                }
            }
            if !extras.isEmpty {
                VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
                    SectionLabel(text: "Extras")
                    VStack(spacing: 0) {
                        ForEach(extras) { part in
                            partRow(f, part: part, isLast: part.id == extras.last?.id)
                        }
                    }
                }
            }
        }
    }

    private func partRow(_ f: Franchise, part: FranchisePart, isLast: Bool) -> some View {
        let isExtra = Self.extraKinds.contains(part.kind)
        let episodic = !isExtra && (part.kind == .season || part.totalEpisodes > 1)
        let settled = !isExtra && part.isComplete && !part.isReleasing
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
            else if !isExtra && inLibrary { toggleUnit(f, part: part) }
        }
        .accessibilityLabel("\(part.canonicalLabel), \([facts.lead, facts.meta].compactMap { $0 }.joined(separator: ", "))")
        // `MediaRow` combines its children, and the label override then replaces everything the
        // `PassiveTick` would have contributed — so on a film or a single unit, whose meta line is
        // a date rather than a progress count, "watched" disappeared from the spoken row entirely.
        .accessibilityValue(settled ? Copy.Accessibility.complete : "")
        .accessibilityHint(episodic ? "Opens the episode list" : (!isExtra && inLibrary ? "Toggles watched" : ""))
    }

    /// A row's two facts, split by direction: what has happened is neutral `meta`, what is coming
    /// is `lead` and earns the accent. The shipped row put both in the same grey.
    private func partFacts(_ f: Franchise, part: FranchisePart) -> (meta: String?, lead: String?) {
        if part.isUpcoming {
            if let d = part.announcedDateLabel(source: f.source) { return (nil, "Premieres \(d)") }
            return ("No date announced", nil)
        }
        // The specials bucket is a CATALOGUE, not a run. It lives under its own EXTRAS label now,
        // and it says what it is: a pile of featurettes the app does not count against progress.
        // "0 of 300 watched" was truthful and destroyed trust in every count above it; "300
        // episodes" in the same grammar as "10 of 10 watched" was the same claim, quieter.
        if Self.extraKinds.contains(part.kind) {
            return ("\(part.totalEpisodes > 1 ? "\(part.totalEpisodes) extras" : "Extras") · not tracked", nil)
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
    /// The whole-list spoiler switch (season overflow). Per-view, deliberately: it is a viewing
    /// preference for the list in front of you, not an account setting.
    @State private var revealAll = false
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
                        .padding(.horizontal, ThemeMetrics.gutter)
                        .padding(.top, ThemeSpace.x2)
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
        // A REAL navigation bar. This screen used to hide it and hand-build its own — a circular
        // back button, a centred 22-pt title, a circular ellipsis, no material and no scroll edge
        // effect, so the first row was chopped in half under a black band and left a decapitated
        // poster ghost at 50 % alpha. It then repeated itself, printing "Season 3" a second time
        // 150 pt below the first in larger type.
        //
        // The season is the subject, so the season is the title; its progress is the subtitle,
        // which is exactly what `navigationSubtitle` is for; the show's name is one tap back and
        // already at the top of the screen you came from.
        .navigationTitle(part.map { $0.canonicalLabel.isEmpty ? $0.title : $0.canonicalLabel } ?? "")
        .navigationSubtitle(progressLine)
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

    /// The navigation bar's subtitle: the one progress fact this screen carries. It used to be a
    /// second header inside the content, 150 pt under a bar that said the same thing.
    private var progressLine: String {
        guard let part else { return "" }
        let total = max(part.totalEpisodes, part.airedEpisodes)
        return total > 0 ? Copy.Progress.watchedOf(min(part.progress, total), total)
                         : Copy.episodes(part.progress) + " watched"
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
                Label("Show titles and stills", systemImage: revealAll ? "eye" : "eye.slash")
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
        // The shape that arrives: rows straight under the navigation bar, no content header. The
        // header the skeleton used to promise is now the bar's own title and subtitle.
        VStack(spacing: 0) {
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

    private func row(_ f: Franchise, part: FranchisePart, n: Int, isLast: Bool) -> some View {
        let episode = part.episodes.first { $0.number == n }
        let watched = n <= part.progress
        let aired = !part.isReleasing || n <= part.provenAiredCount(now: now) || n <= part.airedEpisodes
        let isNext = n == part.progress + 1 && aired
        let spoilerSafe = watched || isNext || revealAll || revealed.contains(n)
        let interactive = appModel.isInLibrary(f.id) && aired
        let canReveal = !spoilerSafe && (episode?.title?.isEmpty == false || episode?.still != nil)
        return HStack(spacing: ThemeSpace.x2) {
            Button { if interactive { tapped(f, part: part, n: n, watched: watched) } } label: {
                HStack(alignment: .center, spacing: ThemeMetrics.artGap) {
                    // One 96×54 rectangle for every row — a still, a withheld still, or no still
                    // at all. The shipped list ran two photographs and then five 48-pt grey squares,
                    // so it physically changed shape halfway down.
                    if spoilerSafe {
                        EpisodeArtwork(url: episode?.still, spoilerSafe: true, showTint: quietTint)
                    } else if aired, episode?.still?.isEmpty == false {
                        // Withheld, and it says so: `eye.slash`, the glyph on the control that
                        // reverses it. A blurred still is a tease with no VoiceOver equivalent, and
                        // a play glyph would say "this image failed to load".
                        WithheldStillTile(tint: quietTint)
                    } else {
                        // Nothing is being withheld — the episode has not aired, or the catalogue
                        // has no still for it. `eye.slash` here would claim a picture exists.
                        EpisodeArtwork(url: nil, showTint: quietTint)
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
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            if aired {
                Button { if interactive { tapped(f, part: part, n: n, watched: watched) } } label: {
                    ZStack {
                        // The SAME 22-pt ring in both states. The watched state used to be a bare
                        // tertiary checkmark — pixel-identical to `PassiveTick`, the primitive that
                        // means "a settled fact, never a control" — so the one place a user unmarks
                        // a single episode looked non-interactive, while a genuinely passive glyph
                        // on the Seasons list looked the same. Ring = control; what is inside it is
                        // the state.
                        Circle()
                            .stroke(isNext && !watched ? ThemeColor.accent : ThemeColor.strokeStrong, lineWidth: 1.5)
                            .frame(width: 22, height: 22)
                        DrawnCheck(on: watched, size: 12, tint: ThemeColor.textSecondary)
                            .opacity(watched ? 1 : 0)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: watched)
                }
                .buttonStyle(MarkPressStyle())
                .disabled(!interactive)
                // A statement of fact on a button tells VoiceOver nothing about what a double tap
                // does, and a label that carries the state is never re-announced when the state
                // changes. Label names the thing, value carries the state, hint says what happens.
                .accessibilityLabel(Copy.episode(n))
                .accessibilityValue(watched ? "Watched" : "Not watched")
                .accessibilityHint(interactive ? (watched ? "Marks as unwatched" : "Marks as watched") : "")
                .accessibilityAddTraits(watched ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, 6)
        // One pitch down the column. Row heights ran 64/82/76/79/81/74/91 — a 42 % swing — because
        // the still was centred against a text block that grew from two lines to three, so the
        // stills never formed a column. `rowEpisode` (78) was defined and unused.
        .frame(minHeight: ThemeMetrics.rowEpisode, alignment: .center)
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
        .buttonStyle(MarkPressStyle())
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
