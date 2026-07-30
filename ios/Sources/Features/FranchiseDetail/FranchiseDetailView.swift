import SwiftUI

// Franchise detail sheet — the approved "8a · refined accordion" redesign. Top to bottom:
//  - a poster-forward hero (color-wash background + floating cover), with a frosted back button,
//    a status-chip menu (Watching / Completed / Plan), and a ⋯ overflow (Refresh / Share / Remove),
//  - centered title + a genre/format meta line + a clamped synopsis with "Read more",
//  - an announced-installment line when a future season is known but not yet in the parts,
//  - "SEASONS & MOVIES": a per-season accordion (each season expands to per-episode rows with a
//    watched toggle, a "Next up" highlight, and a source-aware date badge on the next episode);
//    movies / specials are binary-toggle peer rows.
//
// Note: the API exposes episode COUNTS, not per-episode metadata, so episode rows read "Episode N"
// rather than titles/synopses, and progress is contiguous (tapping episode N sets watched-through-N).
/// Deep-link target inside the detail sheet: pre-open a season's accordion and land on one episode
/// (Schedule rows pass the aired/next episode; nil = the normal everything-collapsed opening).
struct EpisodeFocus: Equatable {
    let mediaId: Int
    let episode: Int
}

struct FranchiseDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let franchiseId: String
    var focus: EpisodeFocus? = nil

    @State private var franchise: Franchise?
    @State private var loading = true
    @State private var loadError = false
    @State private var synopsisExpanded = false
    @State private var confirmRemove = false
    @State private var openState: [Int: Bool] = [:]   // part.mediaId → user-overridden open/closed
    @State private var openKinds: Set<PartKind> = []  // non-season kind groups currently expanded

    private var now: Int64 { appModel.now }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let f = franchise ?? appModel.franchise(id: franchiseId) {
                content(f)
            } else if loading {
                Loader()
            } else if loadError {
                VStack(spacing: 14) {
                    Text("Couldn't load this franchise.").foregroundStyle(Theme.text52)
                    Button("Retry") { Task { await load() } }
                        .buttonStyleProminentGlass()
                }
            }
        }
        .overlay(alignment: .bottom) {
            ToastHost().padding(.horizontal, 16).padding(.bottom, 24)
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            franchise = try await appModel.api.franchise(id: franchiseId)
            loadError = false
        } catch {
            loadError = true
        }
    }

    /// The live franchise: prefer the in-library copy (so optimistic progress shows), else fetched.
    private func live(_ fallback: Franchise) -> Franchise {
        appModel.franchise(id: franchiseId) ?? franchise ?? fallback
    }

    /// The live franchise (fresh progress/status) grafted with per-episode data from the detail
    /// fetch — the in-library copy is loaded without episodes, so overlay them by mediaId.
    private func mergedEpisodes(into base: Franchise) -> Franchise {
        guard let fetched = franchise, fetched.id == base.id else { return base }
        let epByMedia = Dictionary(fetched.parts.map { ($0.mediaId, $0.episodes) }, uniquingKeysWith: { a, _ in a })
        let parts = base.parts.map { p -> FranchisePart in
            if p.episodes.isEmpty, let eps = epByMedia[p.mediaId], !eps.isEmpty { return p.withEpisodes(eps) }
            return p
        }
        return Franchise(copying: base, parts: parts)
    }

    @ViewBuilder
    private func content(_ initial: Franchise) -> some View {
        let f = mergedEpisodes(into: live(initial))
        let inLibrary = appModel.isInLibrary(f.id)

        GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        hero(f, inLibrary: inLibrary)

                        VStack(alignment: .leading, spacing: 0) {
                            titleBlock(f)
                            synopsisBlock(f).padding(.top, 14)
                            announcedLine(f).padding(.top, 2)

                            if !inLibrary {
                                addButton(f).padding(.top, 22)
                            }

                            seasonsAndMovies(f, inLibrary: inLibrary).padding(.top, 28)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 44)
                    }
                    .frame(width: proxy.size.width, alignment: .topLeading)
                }
                .scrollIndicators(.hidden)
                .onAppear { focusScroll(scrollProxy) }
            }
        }
        .ignoresSafeArea(edges: .top)
        .scrollContentBackground(.hidden)
        .overlay(alignment: .center) {
            ZStack {
                if appModel.justCaught.contains(f.id) {
                    CaughtUpOverlay(size: 62).frame(width: 200, height: 200).allowsHitTesting(false)
                }
            }
            .animation(.uiGentle, value: appModel.justCaught.contains(f.id))
        }
    }

    // MARK: hero — color wash + floating poster + frosted controls

    private func hero(_ f: Franchise, inLibrary: Bool) -> some View {
        ZStack(alignment: .top) {
            // The 8a subtle radial colour wash, fading to the app background. Independent of artwork
            // loading, so the hero is always premium and the floating cover reads clearly on top.
            LinearGradient(
                colors: [Color(hex: 0x2C3242), Theme.background],
                startPoint: .top, endPoint: .bottom
            )
            .overlay(alignment: .top) {
                RadialGradient(
                    colors: [Color(hex: 0x3A4155).opacity(0.85), .clear],
                    center: .top, startRadius: 0, endRadius: 300
                )
            }
            .frame(height: 262)
            .frame(maxWidth: .infinity)

            // Floating cover.
            Thumb(cover: f.cover, width: 116, height: 168, radius: 14)
                .shadow(color: .black.opacity(0.6), radius: 24, y: 16)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1))
                .padding(.top, 54)

            // Overlaid controls.
            HStack(alignment: .top) {
                GlassCircleButton(systemName: "chevron.down", size: 34, iconSize: 16,
                                  foreground: Theme.textPrimary) { dismiss() } // close haptic fires in the sheet's onDismiss
                Spacer()
                HStack(spacing: 8) {
                    if inLibrary {
                        statusMenu(f)
                        overflowMenu(f)
                    } else {
                        addPill(f)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .frame(height: 262)
        .frame(maxWidth: .infinity)
    }

    private func statusMenu(_ f: Franchise) -> some View {
        Menu {
            ForEach(WatchStatus.allCases, id: \.self) { s in
                Button {
                    withAnimation(.uiSnappy) { appModel.setStatus(franchiseId: f.id, status: s) }
                } label: {
                    if f.effectiveStatus == s {
                        Label(statusLabel(s), systemImage: "checkmark")
                    } else {
                        Text(statusLabel(s))
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(statusLabel(f.effectiveStatus))
                    .scaledFont(12.5, weight: .medium)
                    .foregroundStyle(Theme.text72)
                    .contentTransition(.numericText())
                Image(systemName: "chevron.down")
                    .scaledFont(10, weight: .semibold)
                    .foregroundStyle(Theme.text40)
            }
            .frostedChrome(shape: Capsule(), leading: 12, trailing: 9)
        }
    }

    private func overflowMenu(_ f: Franchise) -> some View {
        Menu {
            Button { Task { await load() } } label: { Label("Refresh metadata", systemImage: "arrow.clockwise") }
            ShareLink(item: f.title) { Label("Share", systemImage: "square.and.arrow.up") }
            Button(role: .destructive) { confirmRemove = true } label: {
                Label("Remove from library", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .scaledFont(15, weight: .semibold)
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 34, height: 34)
                .frostedChrome(shape: Circle())
        }
        .confirmationDialog("Remove \u{201C}\(f.title)\u{201D} from your library?",
                            isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { appModel.removeFromLibrary(franchiseId: f.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your episode progress for this franchise will no longer be tracked.")
        }
    }

    private func addPill(_ f: Franchise) -> some View {
        Button {
            appModel.addToLibrary(franchiseId: f.id, title: f.title, isReleasing: f.isReleasing)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus").scaledFont(11, weight: .bold)
                Text("Add").scaledFont(12.5, weight: .semibold)
            }
            .foregroundStyle(Theme.background)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(Theme.accent, in: Capsule())
        }
        .buttonStyle(SpringPressButtonStyle(scale: 0.94))
    }

    // MARK: title + synopsis + announced line

    private func titleBlock(_ f: Franchise) -> some View {
        VStack(spacing: 7) {
            Text(f.title)
                .scaledFont(23, weight: .semibold)
                .tracking(-0.6)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !metaLine(f).isEmpty {
                Text(metaLine(f))
                    .scaledFont(12.5, weight: .medium)
                    .foregroundStyle(Theme.text62)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    // "HBO · Drama · Fantasy · 2011" — studio/network + up to two genres + premiere year, falling
    // back to the parts breakdown.
    private func metaLine(_ f: Franchise) -> String {
        var parts: [String] = []
        if let studio = f.studios.first { parts.append(studio) }
        parts.append(contentsOf: f.genres.prefix(2))
        if let y = f.year { parts.append(String(y)) }
        return parts.isEmpty ? (partBreakdown(f.partCounts) ?? "") : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func synopsisBlock(_ f: Franchise) -> some View {
        let synopsis = Formatting.stripHtml(f.synopsis)
        if !synopsis.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(synopsis)
                    .scaledFont(13.5)
                    .foregroundStyle(Theme.text70)
                    .lineSpacing(4)
                    .lineLimit(synopsisExpanded ? nil : 3)
                if synopsis.count > 160 {
                    Button {
                        withAnimation(.uiSmooth) { synopsisExpanded.toggle() }
                    } label: {
                        Text(synopsisExpanded ? "Less" : "Read more")
                            .scaledFont(13, weight: .semibold)
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // A known future installment the airing schedule can't surface yet (no per-episode date).
    @ViewBuilder
    private func announcedLine(_ f: Franchise) -> some View {
        if let up = f.upcoming, up.isFutureInstallment, !up.cardBadge.isEmpty {
            HStack(spacing: 7) {
                Image(systemName: "calendar").scaledFont(11, weight: .semibold).foregroundStyle(Theme.accent)
                Text(up.cardBadge)
                    .scaledFont(12.5, weight: .medium)
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
            }
            .padding(.top, 12)
        }
    }

    private func addButton(_ f: Franchise) -> some View {
        Button {
            appModel.addToLibrary(franchiseId: f.id, title: f.title, isReleasing: f.isReleasing)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "plus").scaledFont(16, weight: .bold)
                Text("Add to library").scaledFont(15.5, weight: .semibold)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .foregroundStyle(Theme.background)
        }
        .buttonStyleProminentGlass()
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    // MARK: seasons & movies accordion

    private func seasonsAndMovies(_ f: Franchise, inLibrary: Bool) -> some View {
        let seasons = f.parts.filter { $0.kind == .season }.sorted { $0.sequence < $1.sequence }
        let groups = nonSeasonGroups(f)
        return VStack(alignment: .leading, spacing: 0) {
            Text("SEASONS & MOVIES")
                .scaledFont(11.5, weight: .semibold)
                .tracking(0.9)
                .foregroundStyle(Theme.text40)
                .padding(.bottom, 4)

            // Seasons — individual accordions, collapsed by default (tap to open).
            ForEach(seasons) { part in
                SeasonAccordion(
                    part: part,
                    source: f.source,
                    now: now,
                    isOpen: isOpen(part),
                    interactive: inLibrary,
                    onToggleOpen: { toggleOpen(part) },
                    onSetProgress: { eps in setProgress(f, part: part, eps: eps) }
                )
                .id("part-\(part.mediaId)")
            }

            // Non-season parts — one collapsible category group per kind (Movies / OVAs / Specials /
            // …), each with its kind as the header and its parts below, so they stay visually
            // distinct from seasons and don't clutter the list.
            ForEach(groups, id: \.kind) { group in
                KindGroup(
                    kind: group.kind,
                    parts: group.parts,
                    isOpen: openKinds.contains(group.kind),
                    interactive: inLibrary,
                    onToggleOpen: { toggleKind(group.kind) },
                    onSetProgress: { part, eps in setProgress(f, part: part, eps: eps) }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Non-season parts grouped by kind, ordered by canonical rank (Movies, OVAs, ONAs, Specials, …).
    private func nonSeasonGroups(_ f: Franchise) -> [(kind: PartKind, parts: [FranchisePart])] {
        Dictionary(grouping: f.parts.filter { $0.kind != .season }, by: { $0.kind })
            .map { (kind: $0.key, parts: $0.value.sorted { $0.sequence < $1.sequence }) }
            .sorted { $0.kind.sortRank < $1.kind.sortRank }
    }

    /// Everything starts COLLAPSED; only a user tap opens a season — except a deep-linked focus
    /// season (Schedule → episode), which arrives already open. A tap still overrides it.
    private func isOpen(_ p: FranchisePart) -> Bool {
        openState[p.mediaId] ?? (focus?.mediaId == p.mediaId)
    }

    /// Two-stage landing for a deep-linked episode: after the sheet settles, put the (pre-opened)
    /// focus season at the top — realizing its lazy episode rows — then centre the episode itself.
    private func focusScroll(_ proxy: ScrollViewProxy) {
        guard let focus else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.uiSmooth) { proxy.scrollTo("part-\(focus.mediaId)", anchor: .top) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.uiSmooth) {
                    proxy.scrollTo("ep-\(focus.mediaId)-\(focus.episode)", anchor: .center)
                }
            }
        }
    }

    private func toggleOpen(_ p: FranchisePart) {
        Haptics.selection()
        withAnimation(.uiSnappy) { openState[p.mediaId] = !isOpen(p) }
    }

    private func toggleKind(_ kind: PartKind) {
        Haptics.selection()
        withAnimation(.uiSnappy) {
            if openKinds.contains(kind) { openKinds.remove(kind) } else { openKinds.insert(kind) }
        }
    }

    private func setProgress(_ f: Franchise, part: FranchisePart, eps: Int) {
        withAnimation(.uiSnappy) {
            appModel.setProgress(franchiseId: f.id, mediaId: part.mediaId, episodes: eps)
        }
    }

    // MARK: helpers

    private func statusLabel(_ s: WatchStatus) -> String {
        switch s {
        case .watching: return "Watching"
        case .completed: return "Completed"
        case .planned: return "Plan"
        }
    }

    /// "4 Seasons · 1 Movie · 2 OVAs" — only non-zero kinds, properly pluralised.
    private func partBreakdown(_ counts: PartCounts?) -> String? {
        guard let c = counts else { return nil }
        func unit(_ n: Int, _ singular: String, _ plural: String) -> String? {
            n > 0 ? "\(n) \(n == 1 ? singular : plural)" : nil
        }
        let pieces = [
            unit(c.season, "Season", "Seasons"),
            unit(c.movie, "Movie", "Movies"),
            unit(c.ova, "OVA", "OVAs"),
            unit(c.ona, "ONA", "ONAs"),
            unit(c.special, "Special", "Specials"),
            unit(c.music, "Music", "Music"),
        ].compactMap { $0 }
        return pieces.isEmpty ? nil : pieces.joined(separator: " · ")
    }
}

// MARK: - Season accordion

// A single season row that expands to its per-episode list. Collapsed shows a short state + a
// chevron; open shows a detailed sub-line and the episode rows. Open/closed is signalled by the
// chevron only — no background tint (restraint).
private struct SeasonAccordion: View {
    let part: FranchisePart
    let source: MediaSource
    let now: Int64
    let isOpen: Bool
    let interactive: Bool
    let onToggleOpen: () -> Void
    let onSetProgress: (Int) -> Void

    // With a known total, never exceed it. With an unknown total (0, common for ongoing AniList
    // shows), extend one past what's aired so the airing/next-to-air row can render its date badge.
    private var episodeCount: Int {
        if part.totalEpisodes > 0 { return part.totalEpisodes }
        let nextToAir = (part.isReleasing && part.nextAiringAt != nil) ? part.airedEpisodes + 1 : 0
        return max(part.airedEpisodes, part.progress, nextToAir)
    }

    /// Mark-all target: catch up to what's aired for a releasing season, else the full episode count.
    private var markTarget: Int { part.isReleasing ? part.airedEpisodes : episodeCount }
    /// Whether every available episode of this season is watched (drives the header checkbox).
    private var seasonWatched: Bool { markTarget > 0 && part.progress >= markTarget }

    private var status: PartStatus {
        if part.isUpcoming { return .upcoming }
        if part.isReleasing {
            if part.isBehind { return .behind(part.episodesBehind) }
            return part.progress > 0 ? .caughtUp : .airing
        }
        if part.isFinished { return .watched }
        return part.progress > 0 ? .watching : .notStarted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggleOpen) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(part.label.isEmpty ? part.title : part.label)
                            .scaledFont(15, weight: .semibold)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        subLine
                    }
                    Spacer(minLength: 8)
                    // Mark-all-watched checkbox (its own tap target inside the header button).
                    // Hidden when there's nothing to mark yet (releasing season, 0 aired) — else
                    // it's a dead control that still bounces and haptics on tap.
                    if interactive && !part.isUpcoming && markTarget > 0 {
                        WatchedControl(watched: seasonWatched, isNext: false, interactive: true) {
                            onSetProgress(seasonWatched ? 0 : markTarget)
                        }
                    } else if !isOpen {
                        collapsedState
                    }
                    Image(systemName: "chevron.right")
                        .scaledFont(12, weight: .semibold)
                        .foregroundStyle(Theme.text36)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                if part.isUpcoming {
                    Text(part.premiereAt.map { "Premieres \(Formatting.fmtFullDate($0))" } ?? "Release date TBA")
                        .scaledFont(12.5, weight: .medium)
                        .foregroundStyle(Theme.accent)
                        .padding(.bottom, 14)
                } else if episodeCount > 0 {
                    LazyVStack(spacing: 0) {
                        ForEach(1...episodeCount, id: \.self) { n in
                            EpisodeRow(part: part, index: n, source: source,
                                       now: now, interactive: interactive, onSetProgress: onSetProgress)
                                .id("ep-\(part.mediaId)-\(n)")
                            if n < episodeCount { HairlineDivider(inset: 0) }
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        .overlay(alignment: .bottom) { HairlineDivider(inset: 0) }
    }

    // Detailed sub-line under the season name.
    @ViewBuilder
    private var subLine: some View {
        switch status {
        case .airing:
            HStack(spacing: 6) {
                Circle().fill(Theme.accent).frame(width: 5, height: 5)
                Text(part.totalEpisodes > 0
                     ? "Airing · \(part.airedEpisodes) of \(episodeCount) aired"
                     : "Airing · \(part.airedEpisodes) aired")
                    .scaledFont(12, weight: .medium).foregroundStyle(Theme.text46)
                    .contentTransition(.numericText())
            }
        case .behind:
            Text("Watching · \(part.progress) / \(episodeCount)")
                .scaledFont(12, weight: .medium).foregroundStyle(Theme.text46)
                .contentTransition(.numericText())
        case .watching, .caughtUp:
            Text("Watching · \(part.progress) / \(episodeCount)")
                .scaledFont(12, weight: .medium).foregroundStyle(Theme.text46)
                .contentTransition(.numericText())
        case .watched:
            Text("\(episodeCount) episodes").scaledFont(12, weight: .medium).foregroundStyle(Theme.text40)
        case .upcoming:
            Text("Announced").scaledFont(12, weight: .medium).foregroundStyle(Theme.text46)
        case .notStarted:
            Text("\(episodeCount) episodes").scaledFont(12, weight: .medium).foregroundStyle(Theme.text40)
        }
    }

    // Short state shown at the trailing edge when collapsed.
    @ViewBuilder
    private var collapsedState: some View {
        switch status {
        case .watched:
            HStack(spacing: 4) {
                Image(systemName: "checkmark").scaledFont(9, weight: .bold)
                Text("Watched").scaledFont(12, weight: .medium)
            }
            .foregroundStyle(Theme.text46)
        case .behind(let n):
            Text("\(n) \(source == .tmdb ? "unwatched" : "behind")")
                .scaledFont(11, weight: .semibold)
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Theme.accentChipFill, in: Capsule())
        case .notStarted:
            Text("Not started").scaledFont(12, weight: .medium).foregroundStyle(Theme.text46)
        case .upcoming:
            Text("Announced").scaledFont(12, weight: .medium).foregroundStyle(Theme.accent)
        default:
            EmptyView()
        }
    }
}

// MARK: - Episode row

// One episode within an expanded season. "E1 · Title" (or "Episode N" when untitled) + a state
// sub-line, with a trailing watched toggle (aired) or a source-aware date badge (next to air).
// Tapping the row expands an episode-detail card (still + synopsis + Mark watched) when there's
// detail to show. Progress is contiguous: tapping marks watched-through-N (or N-1 to unmark).
private struct EpisodeRow: View {
    let part: FranchisePart
    let index: Int
    let source: MediaSource
    let now: Int64
    let interactive: Bool
    let onSetProgress: (Int) -> Void
    @State private var expanded = false

    private var episode: Episode? { part.episodes.first { $0.number == index } }
    private var watched: Bool { index <= part.progress }
    private var aired: Bool { !part.isReleasing || index <= part.airedEpisodes }
    private var isNextToAir: Bool {
        part.isReleasing && index == part.airedEpisodes + 1 && part.nextAiringAt != nil
    }
    private var isNextUp: Bool { index == part.progress + 1 && aired }
    private var dimmed: Bool { !aired && !isNextToAir }
    private var hasDetail: Bool { (episode?.overview?.isEmpty == false) || episode?.still != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            if expanded { detailCard.padding(.bottom, 10) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let still = episode?.still {
                Thumb(cover: still, width: 58, height: 34, radius: 6)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .scaledFont(13.5, weight: .semibold)
                    .foregroundStyle(watched ? Theme.text62 : Theme.textPrimary)
                    .lineLimit(1)
                if let sub = subLabel {
                    Text(sub.text).scaledFont(11, weight: .medium).foregroundStyle(sub.color)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 9)
        .opacity(dimmed ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: onRowTap)
    }

    private var titleText: String {
        if let t = episode?.title, !t.isEmpty { return "E\(index) · \(t)" }
        return "Episode \(index)"
    }

    private var subLabel: (text: String, color: Color)? {
        if isNextUp { return ("Next up", Theme.accent) }
        if isNextToAir { return ("New episode", Theme.accent) }
        if !aired { return ("Upcoming", Theme.text40) }
        if let d = episode?.airDate { return ("Aired \(Formatting.fmtFullDate(d))", Theme.text46) }
        return nil
    }

    @ViewBuilder
    private var trailing: some View {
        if isNextToAir, let next = part.nextAiringAt {
            DateBadge(ts: next, now: now, source: source)
        } else if aired {
            WatchedControl(watched: watched, isNext: isNextUp, interactive: interactive) {
                onSetProgress(watched ? index - 1 : index)
            }
        }
    }

    private func onRowTap() {
        if hasDetail {
            Haptics.selection()
            withAnimation(.uiSnappy) { expanded.toggle() }
        } else if interactive, aired {
            onSetProgress(watched ? index - 1 : index)
        }
    }

    // Expanded episode-detail card — a 16:9 still with a play affordance, the runtime/date meta,
    // the synopsis, and a full-width Mark-watched button.
    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let still = episode?.still {
                Color.clear
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay { RemoteImageView(url: still).frame(maxWidth: .infinity, maxHeight: .infinity) }
                    .overlay {
                        Image(systemName: "play.fill")
                            .scaledFont(15)
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(Theme.background.opacity(0.5), in: Circle())
                            .glassChrome(in: Circle())
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if !detailMeta.isEmpty {
                Text(detailMeta).scaledFont(12, weight: .medium).foregroundStyle(Theme.text46)
            }
            if let ov = episode?.overview, !ov.isEmpty {
                Text(ov)
                    .scaledFont(13)
                    .foregroundStyle(Theme.text70)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if interactive, aired {
                Button {
                    onSetProgress(watched ? index - 1 : index)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark").scaledFont(13, weight: .bold)
                        Text(watched ? "Watched" : "Mark watched").scaledFont(14, weight: .semibold)
                    }
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .foregroundStyle(Theme.background)
                }
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .buttonStyle(SpringPressButtonStyle(scale: 0.98))
            }
        }
        .padding(12)
        .background(Theme.fillFaint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }

    private var detailMeta: String {
        var parts = ["Episode \(index)"]
        if let r = episode?.runtime { parts.append("\(r) min") }
        if let d = episode?.airDate { parts.append(Formatting.fmtFullDate(d)) }
        return parts.joined(separator: " · ")
    }
}

// The per-episode / per-movie watched toggle. Watched = a quiet neutral filled disc + check
// (recedes); next-up = an accent ring; unwatched = a hairline ring.
private struct WatchedControl: View {
    let watched: Bool
    let isNext: Bool
    let interactive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(watched ? Color.white.opacity(0.55) : Color.clear)
                    .frame(width: 22, height: 22)
                    .overlay {
                        if !watched {
                            Circle().stroke(isNext ? Theme.accent : Theme.hairlineStrong, lineWidth: 1.6)
                        }
                    }
                if watched {
                    Image(systemName: "checkmark")
                        .scaledFont(11, weight: .bold)
                        .foregroundStyle(Theme.background)
                        // Liquid-Glass "responsive feedback": the check springs in when you mark it,
                        // so the interaction reads as satisfying without leaning on a heavier haptic.
                        .symbolEffect(.bounce, value: watched)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 30, height: 30)
            .contentShape(Circle())
            .animation(.uiBouncy, value: watched)
        }
        .buttonStyle(BounceButtonStyle())
        .disabled(!interactive)
        .accessibilityLabel(watched ? "Watched" : "Not watched")
    }
}

// MARK: - Movie / special peer row

private struct MovieRow: View {
    let part: FranchisePart
    let interactive: Bool
    let onSetProgress: (Int) -> Void

    private var full: Int { max(part.totalEpisodes, 1) }
    private var watched: Bool { part.progress >= full }   // whole unit (incl. multi-episode OVAs)
    private var kindTag: String {
        switch part.kind {
        case .movie: return "MOVIE"
        case .ova: return "OVA"
        case .ona: return "ONA"
        case .special: return "SPECIAL"
        case .music: return "MUSIC"
        case .season: return "SEASON"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Thumb(cover: part.cover, width: 40, height: 56, radius: 7)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(part.label.isEmpty ? part.title : part.label)
                            .scaledFont(15, weight: .semibold)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(kindTag)
                            .scaledFont(9.5, weight: .bold)
                            .tracking(0.5)
                            .foregroundStyle(Theme.text62)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.fillSoft, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Theme.hairlineStrong, lineWidth: 1))
                    }
                    if let fmt = part.format, !fmt.isEmpty {
                        Text(fmt).scaledFont(12, weight: .medium).foregroundStyle(Theme.text46)
                    } else if part.isUpcoming {
                        Text(part.premiereAt.map { "Premieres \(Formatting.fmtFullDate($0))" } ?? "TBA")
                            .scaledFont(12, weight: .medium).foregroundStyle(Theme.accent)
                    }
                }
                Spacer(minLength: 8)
                if !part.isUpcoming {
                    WatchedControl(watched: watched, isNext: false, interactive: interactive) {
                        onSetProgress(watched ? 0 : full)
                    }
                }
            }
            .padding(.vertical, 13)
        }
        .overlay(alignment: .bottom) { HairlineDivider(inset: 0) }
    }
}

// MARK: - Kind group (Movies / OVAs / Specials …)

// A collapsible category group for non-season parts: the kind is the header, its parts (binary
// watched-toggle rows) sit below. Collapsed by default so supplementary content stays visually
// distinct from seasons and never clutters the list.
private struct KindGroup: View {
    let kind: PartKind
    let parts: [FranchisePart]
    let isOpen: Bool
    let interactive: Bool
    let onToggleOpen: () -> Void
    let onSetProgress: (FranchisePart, Int) -> Void

    private var title: String {
        switch kind {
        case .movie: return parts.count == 1 ? "Movie" : "Movies"
        case .ova: return "OVAs"
        case .ona: return "ONAs"
        case .special: return "Specials"
        case .music: return "Music"
        case .season: return "Seasons"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggleOpen) {
                HStack(spacing: 10) {
                    Text(title)
                        .scaledFont(15, weight: .semibold)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(parts.count)")
                        .scaledFont(12, weight: .medium, monospacedDigit: true)
                        .foregroundStyle(Theme.text40)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .scaledFont(12, weight: .semibold)
                        .foregroundStyle(Theme.text36)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(spacing: 0) {
                    ForEach(parts) { part in
                        MovieRow(part: part, interactive: interactive) { eps in onSetProgress(part, eps) }
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .overlay(alignment: .bottom) { HairlineDivider(inset: 0) }
    }
}

// MARK: - Part status

// The watch state of a single part, used to drive its accordion sub-line and collapsed chip.
private enum PartStatus {
    case watched
    case behind(Int)
    case caughtUp
    case airing
    case watching
    case upcoming
    case notStarted
}

// A gently pulsing accent dot (retained for reuse by airing surfaces).
private struct LivePulseDot: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 6, height: 6)
            .shadow(color: Theme.accent.opacity(0.9), radius: 4)
            .scaleEffect(on ? 0.82 : 1)
            .opacity(on ? 0.45 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

private extension View {
    /// Frosted-glass chrome for the hero's overlaid controls (status chip, ⋯ button).
    func frostedChrome<S: Shape>(shape: S, leading: CGFloat = 0, trailing: CGFloat = 0) -> some View {
        self
            .padding(.leading, leading)
            .padding(.trailing, trailing)
            .padding(.vertical, leading == 0 ? 0 : 6)
            .background(Theme.background.opacity(0.4), in: shape)
            .glassChrome(in: shape)
            .overlay(shape.stroke(Theme.hairlineStrong, lineWidth: 1))
    }
}

// Simple wrapping chip row for genres (retained; used by other surfaces).
struct FlowChips: View {
    let items: [String]
    var body: some View {
        FlexibleWrap(spacing: 7, lineSpacing: 7) {
            ForEach(items, id: \.self) { g in
                Text(g)
                    .scaledFont(12)
                    .foregroundStyle(Theme.text62)
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(Theme.fillSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
            }
        }
    }
}
