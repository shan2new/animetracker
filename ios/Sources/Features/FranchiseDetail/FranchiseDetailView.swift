import SwiftUI

// Franchise detail sheet — the approved "8a · refined accordion" redesign. Top to bottom:
//  - a poster-forward hero (color-wash background + floating cover), with a frosted back button,
//    a status-chip menu (Watching / Completed / Plan), and a ⋯ overflow (Refresh / Share / Remove),
//  - centered title + a genre/format meta line,
//  - for a show being watched: a "CURRENTLY WATCHING" block — the current season's accordion
//    hoisted above the synopsis, its next-up episode row visible even while collapsed, so "where
//    am I" is the first thing the sheet answers,
//  - a clamped synopsis with "Read more",
//  - an announced-installment line when a future season is known but not yet in the parts,
//  - "SEASONS & MOVIES" ("OTHER SEASONS & MOVIES" when a season is hoisted above): a per-season
//    accordion (each season expands to per-episode rows with a watched toggle, a "Next up"
//    highlight, and a source-aware date badge on the next episode); movies / specials are
//    binary-toggle peer rows.
//
// Note: per-episode metadata (title / still / overview / air date) arrives on the DETAIL response
// only, and its richness is source-dependent — a row falls back to "Episode N" when the catalogue
// gave nothing. Progress is contiguous (tapping episode N sets watched-through-N).
// Nothing here presents a count the API didn't publish: an unknown season length shows progress
// without a denominator rather than a plausible-looking guess.
/// Deep-link target inside the detail sheet: pre-open a season's accordion and land on one episode
/// (Schedule rows pass the aired/next episode; nil = the normal everything-collapsed opening).
struct EpisodeFocus: Equatable {
    let mediaId: Int
    let episode: Int
}

/// Lines the collapsed synopsis is clamped to (file-scope so it can't join the memberwise init).
private let synopsisClampLines = 3

/// Heights of the clamped and unclamped synopsis twins, published as one value so a single
/// preference read can tell whether the clamp is actually cutting text off.
private struct SynopsisHeights: Equatable {
    var clamped: CGFloat = 0
    var full: CGFloat = 0
}

private struct SynopsisHeightKey: PreferenceKey {
    static let defaultValue = SynopsisHeights()
    static func reduce(value: inout SynopsisHeights, nextValue: () -> SynopsisHeights) {
        let next = nextValue()
        value = SynopsisHeights(clamped: max(value.clamped, next.clamped),
                                full: max(value.full, next.full))
    }
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
    @State private var synopsisTruncates = false   // measured, never guessed — see truncationProbe
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
                            currentlyWatchingBlock(f, inLibrary: inLibrary)
                            synopsisBlock(f).padding(.top, 14)
                            announcedLine(f).padding(.top, 2)

                            if !inLibrary {
                                addButton(f).padding(.top, 22)
                            }

                            seasonsAndMovies(f, inLibrary: inLibrary)
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
                                  foreground: Theme.textPrimary,
                                  accessibilityLabel: "Close") { dismiss() } // close haptic fires in the sheet's onDismiss
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
        .accessibilityLabel("More actions")
        .confirmationDialog("Remove \u{201C}\(f.title)\u{201D} from your library?",
                            isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                appModel.removeFromLibrary(franchiseId: f.id)
                // Nothing here is tracked any more: the sheet would otherwise keep rendering the
                // stale fetch snapshot (ticked episodes, "Watching · 7 / 12") beside an Add button.
                dismiss()
            }
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
                synopsisText(synopsis)
                    .lineLimit(synopsisExpanded ? nil : synopsisClampLines)
                if synopsisTruncates {
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
            // "Read more" follows ACTUAL truncation, not a character count: three lines hold a
            // paragraph at the smallest Dynamic Type size and barely a sentence at the largest, so
            // a fixed threshold both offered to expand fully-visible text and hid clipped text
            // behind no affordance at all.
            .background(alignment: .topLeading) { truncationProbe(synopsis) }
            .onPreferenceChange(SynopsisHeightKey.self) { h in
                synopsisTruncates = h.full > h.clamped + 1
            }
        }
    }

    private func synopsisText(_ s: String) -> some View {
        Text(s)
            .scaledFont(13.5)
            .foregroundStyle(Theme.text70)
            .lineSpacing(4)
    }

    /// Two invisible twins of the synopsis — one clamped, one unclamped — that publish their
    /// heights together. Living in a `.background` they are laid out at the real text width and
    /// contribute nothing to the layout; the unclamped one is free to overflow, which is the
    /// measurement. Their heights are stable under the state they drive, so this can't oscillate.
    private func truncationProbe(_ s: String) -> some View {
        ZStack(alignment: .topLeading) {
            synopsisText(s)
                .lineLimit(synopsisClampLines)
                .background { heightReader { SynopsisHeights(clamped: $0, full: 0) } }
            synopsisText(s)
                .fixedSize(horizontal: false, vertical: true)
                .background { heightReader { SynopsisHeights(clamped: 0, full: $0) } }
        }
        .opacity(0)   // still laid out (that's the point); `.hidden()` would risk the preferences
        .accessibilityHidden(true)
    }

    private func heightReader(_ make: @escaping (CGFloat) -> SynopsisHeights) -> some View {
        GeometryReader { g in
            Color.clear.preference(key: SynopsisHeightKey.self, value: make(g.size.height))
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

    // MARK: currently watching + seasons & movies accordion

    /// The season the user is actually ON: the releasing season when one is airing, else the one
    /// their next unwatched episode falls in (`resumePart`). Only for shows they're watching — a
    /// planned or completed show has no "current" to speak of, and outside the library nothing is
    /// tracked at all.
    private func currentSeason(_ f: Franchise, inLibrary: Bool) -> FranchisePart? {
        guard inLibrary, f.effectiveStatus == .watching else { return nil }
        return [f.releasingPart, f.resumePart].compactMap { $0 }.first { $0.kind == .season }
    }

    /// The current season hoisted above the synopsis, so opening a show you're watching answers
    /// "where am I" before anything else. It is the season's REAL accordion (same open state, same
    /// toggles), just relocated — the list below drops it rather than duplicating it.
    @ViewBuilder
    private func currentlyWatchingBlock(_ f: Franchise, inLibrary: Bool) -> some View {
        if let part = currentSeason(f, inLibrary: inLibrary) {
            VStack(alignment: .leading, spacing: 0) {
                Text("CURRENTLY WATCHING")
                    .scaledFont(11.5, weight: .semibold)
                    .tracking(0.9)
                    .foregroundStyle(Theme.text40)
                    .padding(.bottom, 4)
                SeasonAccordion(
                    part: part,
                    source: f.source,
                    now: now,
                    isOpen: isOpen(part),
                    interactive: true,
                    previewsNextUp: true,
                    onToggleOpen: { toggleOpen(part) },
                    onSetProgress: { eps in setProgress(f, part: part, eps: eps) }
                )
                .id("part-\(part.mediaId)")
            }
            .padding(.top, 22)
        }
    }

    @ViewBuilder
    private func seasonsAndMovies(_ f: Franchise, inLibrary: Bool) -> some View {
        let current = currentSeason(f, inLibrary: inLibrary)
        let seasons = f.parts
            .filter { $0.kind == .season && $0.mediaId != current?.mediaId }
            .sorted { $0.sequence < $1.sequence }
        let groups = nonSeasonGroups(f)
        // A one-season show that's hoisted above leaves nothing here — no orphaned header then.
        if !(seasons.isEmpty && groups.isEmpty) {
            seasonsList(f, seasons: seasons, groups: groups,
                        hoisted: current != nil, inLibrary: inLibrary)
                .padding(.top, 28)
        }
    }

    private func seasonsList(_ f: Franchise, seasons: [FranchisePart],
                             groups: [(kind: PartKind, parts: [FranchisePart])],
                             hoisted: Bool, inLibrary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hoisted ? "OTHER SEASONS & MOVIES" : "SEASONS & MOVIES")
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
                    source: f.source,
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

    private func statusLabel(_ s: WatchStatus) -> String { Copy.Status(s) }

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
    /// Hoisted "Currently watching" mode: while collapsed, keep the single next-up episode row
    /// visible under the header. One row on purpose, never the auto-opened list — a long-running
    /// season (One Piece is four digits of episodes) would bury everything below it.
    var previewsNextUp: Bool = false
    let onToggleOpen: () -> Void
    let onSetProgress: (Int) -> Void

    /// Episodes we can prove have aired.
    ///
    /// `airedEpisodes` is the server's derivation from catalogue airing data, but a part caught
    /// mid-sync can report 0 while its own episode list already carries dates in the past. Trusting
    /// that blindly dims every row (nothing is tappable) and collapses `markTarget` onto the user's
    /// progress, so the header checkbox renders "watched" purely because there is nothing left to
    /// compare against. An episode whose air date has passed HAS aired, so take the higher count.
    ///
    /// Strictly BEFORE today, not "today or earlier": today's slot is the one the catalogue is
    /// still counting down to, and swallowing it here would cost the next-to-air row its date badge
    /// on every healthy season the moment its drop day arrives.
    private var airedCount: Int {
        guard part.isReleasing else { return part.airedEpisodes }
        let dated = part.episodes.reduce(0) { acc, ep in
            guard let d = ep.airDate,
                  Formatting.dayDiff(ts: d, now: now, anchor: Episode.airDateAnchor) < 0 else { return acc }
            return max(acc, ep.number)
        }
        return max(part.airedEpisodes, dated)
    }

    // Rows to render when open. With a known total, never exceed it. With an unknown total (0,
    // common for ongoing AniList shows), extend one past what's aired so the airing/next-to-air row
    // can render its date badge. Row plumbing ONLY — it is a guess, and a guess must never be shown
    // as a season length (see `progressLine` / `countLine`).
    private var episodeCount: Int {
        if part.totalEpisodes > 0 { return part.totalEpisodes }
        let nextToAir = (part.isReleasing && part.nextAiringAt != nil) ? airedCount + 1 : 0
        return max(airedCount, part.progress, nextToAir)
    }

    /// Mark-all target: catch up to what's aired for a releasing season, else the full episode count.
    private var markTarget: Int { part.isReleasing ? airedCount : episodeCount }
    /// Whether every available episode of this season is watched (drives the header checkbox).
    private var seasonWatched: Bool { markTarget > 0 && part.progress >= markTarget }
    /// Hidden when there's nothing to mark yet (releasing season, 0 aired) — else it's a dead
    /// control that still bounces and haptics on tap.
    private var showsWatchedToggle: Bool { interactive && !part.isUpcoming && markTarget > 0 }
    private var seasonName: String { part.label.isEmpty ? part.title : part.label }
    private var behindCount: Int { part.isReleasing ? max(0, airedCount - part.progress) : 0 }

    private var status: PartStatus {
        if part.isUpcoming { return .upcoming }
        if part.isReleasing {
            if behindCount > 0 { return .behind(behindCount) }
            return part.progress > 0 ? .caughtUp : .airing
        }
        if part.isFinished { return .watched }
        return part.progress > 0 ? .watching : .notStarted
    }

    /// The one row the hoisted block shows while collapsed: the next unwatched episode — which,
    /// for a caught-up airing season, is the next-to-air row wearing its date badge. Nil once
    /// everything available is watched (nothing to act on).
    private var previewIndex: Int? {
        guard previewsNextUp, !isOpen, !part.isUpcoming else { return nil }
        let next = part.progress + 1
        return next <= episodeCount ? next : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let idx = previewIndex {
                HairlineDivider(inset: 0)
                EpisodeRow(part: part, index: idx, source: source, airedCount: airedCount,
                           now: now, interactive: interactive, onSetProgress: onSetProgress)
                    .padding(.bottom, 6)
            }

            if isOpen {
                if part.isUpcoming {
                    Text(premiereLine)
                        .scaledFont(12.5, weight: .medium)
                        .foregroundStyle(Theme.accent)
                        .padding(.bottom, 14)
                } else if episodeCount > 0 {
                    LazyVStack(spacing: 0) {
                        ForEach(1...episodeCount, id: \.self) { n in
                            EpisodeRow(part: part, index: n, source: source, airedCount: airedCount,
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

    // The header carries TWO independent controls, so it is built as two sibling buttons.
    // Nesting the checkbox inside the disclosure Button's label (with a contentShape spanning both)
    // made taps ambiguous and let VoiceOver merge the checkbox away entirely — a season could not
    // be marked watched with VoiceOver at all. Keeping them siblings also lets the collapsed-state
    // chip and the checkbox coexist, which the old if/else made impossible.
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onToggleOpen) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(seasonName)
                            .scaledFont(15, weight: .semibold)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        subLine
                    }
                    Spacer(minLength: 8)
                    if !isOpen { collapsedState }
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Hides the episodes" : "Shows the episodes")

            if showsWatchedToggle {
                WatchedControl(watched: seasonWatched, isNext: false, interactive: true,
                               accessibilityLabel: seasonName) {
                    onSetProgress(seasonWatched ? 0 : markTarget)
                }
            }

            Button(action: onToggleOpen) {
                Image(systemName: "chevron.right")
                    .scaledFont(12, weight: .semibold)
                    .foregroundStyle(Theme.text36)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // A duplicate of the disclosure action above, kept as a touch target only — announcing
            // "expand" twice would just make the row noisier under VoiceOver.
            .accessibilityHidden(true)
        }
    }

    /// The announced season's date. `premiereAt` is the catalogue's own premiere slot, but TMDB
    /// routinely dates a season only through its first episode — check that before declaring TBA.
    private var premiereLine: String {
        part.announcedDateLabel(source: source).map { "Premieres \($0)" } ?? "Release date TBA"
    }

    /// Progress WITHOUT a fabricated denominator: `episodeCount` invents a length for an ongoing
    /// season with no published total, and "Watching · 1100 / 1101" presented that invention as a
    /// season length.
    private var progressLine: String {
        part.totalEpisodes > 0
            ? "Watching · \(part.progress) / \(part.totalEpisodes)"
            : "Watching · E\(part.progress)"
    }

    /// A size line that only states what's known: the published season length, else how much has
    /// aired so far, else nothing at all.
    private var countLine: String {
        if part.totalEpisodes > 0 { return "\(part.totalEpisodes) episodes" }
        if airedCount > 0 { return "\(airedCount) aired so far" }
        return ""
    }

    // Detailed sub-line under the season name.
    @ViewBuilder
    private var subLine: some View {
        switch status {
        case .airing:
            HStack(spacing: 6) {
                Circle().fill(Theme.accent).frame(width: 5, height: 5)
                Text(part.totalEpisodes > 0
                     ? "Airing · \(airedCount) of \(part.totalEpisodes) aired"
                     : "Airing · \(airedCount) aired")
                    .scaledFont(12, weight: .medium).foregroundStyle(Theme.text46)
                    .contentTransition(.numericText())
            }
        case .behind, .watching, .caughtUp:
            Text(progressLine)
                .scaledFont(12, weight: .medium).foregroundStyle(Theme.text46)
                .contentTransition(.numericText())
        case .upcoming:
            Text("Announced").scaledFont(12, weight: .medium).foregroundStyle(Theme.text46)
        case .watched, .notStarted:
            if !countLine.isEmpty {
                Text(countLine).scaledFont(12, weight: .medium).foregroundStyle(Theme.text40)
            }
        }
    }

    // Short state shown at the trailing edge when collapsed.
    @ViewBuilder
    private var collapsedState: some View {
        switch status {
        case .watched:
            // The checkbox states this when it's on screen; two ticks side by side is just noise.
            if !showsWatchedToggle {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").scaledFont(9, weight: .bold)
                    Text("Watched").scaledFont(12, weight: .medium)
                }
                .foregroundStyle(Theme.text46)
            }
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
    /// Aired episodes as the accordion derived them (see `SeasonAccordion.airedCount`). Passed in
    /// rather than re-read off `part` so a degenerate `airedEpisodes` can't dim — and untap — a row
    /// the season already proved has aired.
    let airedCount: Int
    let now: Int64
    let interactive: Bool
    let onSetProgress: (Int) -> Void
    @State private var expanded = false

    private var episode: Episode? { part.episodes.first { $0.number == index } }
    private var watched: Bool { index <= part.progress }
    private var aired: Bool { !part.isReleasing || index <= airedCount }
    /// The part's live airing slot, judged in its source's own calendar — a TMDB slot compared
    /// locally keeps yesterday's drop alive as "today" east of UTC+7.
    private var nextAiring: Int64? { part.scheduledAiring(now: now, anchor: source.timeAnchor) }
    private var isNextToAir: Bool {
        part.isReleasing && index == airedCount + 1 && nextAiring != nil
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
        if let label = episode?.airDateLabel { return ("Aired \(label)", Theme.text46) }
        return nil
    }

    @ViewBuilder
    private var trailing: some View {
        if isNextToAir, let next = nextAiring {
            DateBadge(ts: next, now: now, source: source)
        } else if aired {
            WatchedControl(watched: watched, isNext: isNextUp, interactive: interactive,
                           accessibilityLabel: "Episode \(index)") {
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
                            .accessibilityHidden(true)   // decorative — nothing plays from here
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
        if let label = episode?.airDateLabel { parts.append(label) }
        return parts.joined(separator: " · ")
    }
}

// The per-episode / per-movie watched toggle. Watched = a quiet neutral filled disc + check
// (recedes); next-up = an accent ring; unwatched = a hairline ring.
private struct WatchedControl: View {
    let watched: Bool
    let isNext: Bool
    let interactive: Bool
    /// What this toggle marks ("Season 2", "Episode 7") — the checked state travels as the
    /// accessibility VALUE, so the label must name the thing, not repeat the state.
    let accessibilityLabel: String
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
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(watched ? "Watched" : "Not watched")
    }
}

// MARK: - Movie / special peer row

private struct MovieRow: View {
    let part: FranchisePart
    let source: MediaSource
    let interactive: Bool
    let onSetProgress: (Int) -> Void

    private var full: Int { max(part.totalEpisodes, 1) }
    private var watched: Bool { part.progress >= full }   // whole unit (incl. multi-episode OVAs)
    private var name: String { part.label.isEmpty ? part.title : part.label }
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
                        Text(name)
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
                    if let sub = subLine {
                        Text(sub.text)
                            .scaledFont(12, weight: .medium)
                            .foregroundStyle(sub.accent ? Theme.accent : Theme.text46)
                    }
                }
                Spacer(minLength: 8)
                if !part.isUpcoming {
                    WatchedControl(watched: watched, isNext: false, interactive: interactive,
                                   accessibilityLabel: name) {
                        onSetProgress(watched ? 0 : full)
                    }
                }
            }
            .padding(.vertical, 13)
        }
        .overlay(alignment: .bottom) { HairlineDivider(inset: 0) }
    }

    /// The one extra fact under the title. The kind pill sits two points above, so the raw API
    /// format enum ("MOVIE", "OVA") only echoed it — and, being non-nil almost always, it silently
    /// shadowed the premiere date of every announced film. Say WHEN instead: the premiere for an
    /// announced part, the release year for one that's already out, nothing when neither is known.
    private var subLine: (text: String, accent: Bool)? {
        if part.isUpcoming {
            return (part.announcedDateLabel(source: source).map { "Premieres \($0)" } ?? "Release date TBA",
                    true)
        }
        if let y = part.year { return (String(y), false) }
        return nil
    }
}

// MARK: - Kind group (Movies / OVAs / Specials …)

// A collapsible category group for non-season parts: the kind is the header, its parts (binary
// watched-toggle rows) sit below. Collapsed by default so supplementary content stays visually
// distinct from seasons and never clutters the list.
private struct KindGroup: View {
    let kind: PartKind
    let parts: [FranchisePart]
    let source: MediaSource
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
                        MovieRow(part: part, source: source, interactive: interactive) { eps in
                            onSetProgress(part, eps)
                        }
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

private extension FranchisePart {
    /// "Jun 24, 2026" for an announced part — the date the UI can actually promise.
    ///
    /// `premiereDateLabel` reads the catalogue's own premiere slot, which TMDB frequently leaves
    /// null while still dating the season through its first episode. Falling back to the earliest
    /// episode air date is the difference between a real date and a bare "TBA".
    func announcedDateLabel(source: MediaSource) -> String? {
        if let label = premiereDateLabel(source: source) { return label }
        guard let first = episodes.compactMap({ $0.airDate }).min() else { return nil }
        return Formatting.fmtFullDate(first, anchor: Episode.airDateAnchor)
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
