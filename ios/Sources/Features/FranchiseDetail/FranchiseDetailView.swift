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

    // Mark timeline (identical to Today)
    @State private var pinned: Franchise?
    @State private var committedEpisode: Int?
    @State private var pendingUndo: UndoState?
    @State private var prompt: WritePrompt?
    @State private var showStartRewatch = false
    /// Minted when a mark completes a season; the hairline sweep draws once per token.
    @State private var sweepToken: UUID?

    private var now: Int64 { appModel.now }
    private var isAX: Bool { typeSize.isAccessibilitySize }

    enum DetailPush: Hashable {
        case episodes(franchiseId: String, mediaId: Int, focusEpisode: Int?)
        case history(franchiseId: String)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            ThemeColor.canvas.ignoresSafeArea()
            SkeletonGate(isLoading: franchise == nil && loading && !loadError) {
                Skeleton.detail
            } content: {
                if let f = franchise {
                    screen(f)
                } else if loadError {
                    EmptyState(SyncCenter.shared.isOnline ? .serverNoCache : .offlineNoData, prominence: .major) {
                        Task { await load() }
                    }
                    .padding(ThemeSpace.x4)
                }
            }
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
                VStack(alignment: .leading, spacing: ThemeSpace.x5) {
                    if staleAfterFailure {
                        InlineNotice(Copy.Notice.detailEpisodes) { Task { await load() } }
                    }
                    if inLibrary, let state = nextUpState(f) {
                        nextUpCard(f, state: state)
                            .id(state.identity)
                            .transition(.opacity.combined(with: .offset(y: 6)))
                        historyRow(f)
                    }
                    about(f)
                    partsList(f)
                }
                .padding(.horizontal, ThemeSpace.x4)
                .padding(.top, ThemeSpace.x4)
                .padding(.bottom, 120)
                .animation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion), value: nextUpState(f)?.identity)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .task(id: f.cover) { tint = await PaletteCache.shared.resolve(url: f.cover, maxPixel: 420) }
    }

    // MARK: - Hero (identity only)

    private func hero(_ f: Franchise) -> some View {
        ZStack(alignment: .top) {
            ArtAdaptiveGround(tint: tint)
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, ThemeColor.canvas], startPoint: .top, endPoint: .bottom)
                        .frame(height: 96)
                }
            VStack(alignment: .leading, spacing: ThemeSpace.x4) {
                let layout = isAX ? AnyLayout(VStackLayout(alignment: .leading, spacing: ThemeSpace.x3))
                                  : AnyLayout(HStackLayout(alignment: .bottom, spacing: ThemeSpace.x4))
                layout {
                    PosterSlot(url: f.cover, width: 96, height: 144)
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                    VStack(alignment: .leading, spacing: 5) {
                        SectionLabel(text: eyebrow(f))
                        Text(f.title)
                            .type(ThemeType.showTitleL)
                            .foregroundStyle(ThemeColor.textPrimary)
                            .lineLimit(isAX ? 5 : 3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if !metaLine(f).isEmpty {
                            Text(metaLine(f)).type(ThemeType.metadata).foregroundStyle(ThemeColor.textSecondary)
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.bottom, 2)
                }
                .padding(.horizontal, ThemeSpace.x4)
                .padding(.bottom, ThemeSpace.x2)
            }
            .padding(.top, 108)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
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
            .glassChrome(in: Capsule(), interactive: true)
            .frame(minHeight: 44)
        }
        .accessibilityLabel("Change status, \(f.effectiveStatus.displayName)")
    }

    private func overflowMenu(_ f: Franchise) -> some View {
        Menu {
            if let part = f.currentPart, !part.isUpcoming {
                let behind = max(0, part.markTarget(now: now) - part.progress)
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
            if !RewatchStore.shared.sessions(for: f.id).isEmpty || f.isSeriesComplete {
                Button(Copy.Action.viewWatchHistory) { push(.history(franchiseId: f.id)) }
            }
            Divider()
            RemoveFromLibraryButton(franchise: f, appModel: appModel)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ThemeColor.textPrimary)
                .frame(width: 34, height: 34)
                .glassChrome(in: Circle(), interactive: true)
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
        guard let part = f.currentPart else { return nil }
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

    @ViewBuilder
    private func nextUpCard(_ f: Franchise, state: NextUp) -> some View {
        let committed = committedEpisode != nil && pinned != nil
        let active = RewatchStore.shared.activeSession(for: f.id)
        VStack(alignment: .leading, spacing: ThemeSpace.x3) {
            SectionLabel(text: state.kind == .seasonComplete || state.kind == .seriesComplete ? "Complete" : (active.map { "\($0.title) · Next up" } ?? "Next up"),
                         dot: state.kind == .actionable, tint: state.kind == .actionable ? ThemeColor.accent : ThemeColor.textTertiary)
            let layout = isAX ? AnyLayout(VStackLayout(alignment: .leading, spacing: ThemeSpace.x3))
                              : AnyLayout(HStackLayout(alignment: .center, spacing: ThemeSpace.x3))
            layout {
                if let part = state.part, let ep = state.episode {
                    let episode = part.episodes.first { $0.number == ep }
                    let safe = revealed.contains(ep)
                    if let still = episode?.still, safe {
                        EpisodeArtwork(url: still, spoilerSafe: true)
                    } else {
                        EpisodeGlyphTile()
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.line1).type(ThemeType.bodyEmphasis).foregroundStyle(ThemeColor.textPrimary)
                        .contentTransition(.numericText()).lineLimit(2)
                    if let l2 = secondLine(state) {
                        Text(l2).type(ThemeType.metadata).foregroundStyle(ThemeColor.textSecondary).lineLimit(2)
                    }
                    if let l3 = state.line3 {
                        Text(l3).type(ThemeType.metadata).foregroundStyle(ThemeColor.textTertiary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if let part = state.part, let ep = state.episode, canReveal(part, episode: ep) {
                    Button {
                        withAnimation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion)) {
                            if revealed.contains(ep) { revealed.remove(ep) } else { revealed.insert(ep) }
                        }
                    } label: {
                        Image(systemName: revealed.contains(ep) ? "eye.slash" : "eye").font(.system(size: 15, weight: .regular))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ThemeColor.textTertiary)
                    .accessibilityLabel(revealed.contains(ep) ? Copy.Action.hideTitle : Copy.Action.showTitle)
                }
            }
            .frame(minHeight: 60)
            if let part = state.part, let episode = state.episode, state.kind == .actionable || state.kind == .backlog {
                cta(f, part: part, episode: committed ? (committedEpisode ?? episode) : episode, behind: state.behind, committed: committed)
            }
            if state.kind == .seriesComplete && active == nil {
                Button(Copy.Action.startRewatch) { showStartRewatch = true }
                    .buttonStyle(PrimaryButtonStyle2())
                    .transition(.opacity)
            }
        }
        .padding(.top, 10).padding(.horizontal, 12).padding(.bottom, 12)
        .background(ThemeColor.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: ThemeRadius.row, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThemeRadius.row, style: .continuous).stroke(ThemeColor.accent.opacity(0.18), lineWidth: 1))
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

    /// Under the card once any session exists: the way into watch history (board 06 §1.6).
    @ViewBuilder
    private func historyRow(_ f: Franchise) -> some View {
        let sessions = RewatchStore.shared.sessions(for: f.id)
        if !sessions.isEmpty || f.isSeriesComplete {
            GroupedList {
                GroupedRow(symbol: "clock.arrow.circlepath", symbolTint: ThemeColor.accentSoft, title: Copy.Action.viewWatchHistory,
                           subtitle: sessions.isEmpty ? Copy.Progress.watchedTimes(1) : Copy.watchSessions(sessions.count),
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

    @ViewBuilder
    private func cta(_ f: Franchise, part: FranchisePart, episode: Int, behind: Int, committed: Bool) -> some View {
        let label = HStack(spacing: 8) {
            if committed {
                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            Text(committed ? "\(Copy.episode(episode)) watched" : Copy.Action.markAsWatched)
                .contentTransition(.interpolate)
            if behind > 1 && !committed {
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).opacity(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: committed)

        if behind > 1 && !committed {
            Menu {
                let through = min(episode + 4, part.markTarget(now: now))
                if through > episode {
                    Button(Copy.Action.markThrough(through)) { promptBatchMark(f, part: part, through: through) }
                }
                Button(Copy.Action.markAll(behind)) { promptBatchMark(f, part: part, through: part.markTarget(now: now)) }
                Button(Copy.Action.viewEpisodes) { push(.episodes(franchiseId: f.id, mediaId: part.mediaId, focusEpisode: nil)) }
            } label: {
                label
            } primaryAction: {
                mark(f, part: part)
            }
            .buttonStyle(PrimaryButtonStyle2())
            .accessibilityLabel("Mark \(Copy.episode(episode)) as watched")
        } else {
            Button { mark(f, part: part) } label: { label }
                .buttonStyle(PrimaryButtonStyle2())
                .allowsHitTesting(!committed)
                .accessibilityLabel(committed ? "\(Copy.episode(episode)) watched" : "Mark \(Copy.episode(episode)) as watched")
        }
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

    @ViewBuilder
    private func about(_ f: Franchise) -> some View {
        let synopsis = Formatting.stripHtml(f.parts.first { !(($0.synopsis ?? "").isEmpty) }?.synopsis)
        if !synopsis.isEmpty {
            VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                SectionLabel(text: "About")
                Text(synopsis)
                    .type(ThemeType.callout)
                    .foregroundStyle(ThemeColor.textSecondary)
                    .lineLimit(synopsisExpanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                Button(synopsisExpanded ? "Read less" : "Read more") {
                    withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) { synopsisExpanded.toggle() }
                }
                .buttonStyle(TertiaryButtonStyle2())
            }
        }
    }

    // MARK: - Seasons & movies

    private func partsList(_ f: Franchise) -> some View {
        let groups = f.sections
        return VStack(alignment: .leading, spacing: ThemeSpace.x2) {
            SectionHeaderRow("Seasons & movies", count: f.parts.count)
            VStack(spacing: 0) {
                ForEach(groups, id: \.kind) { group in
                    ForEach(group.parts) { part in
                        partRow(f, part: part, isLast: group.kind == groups.last?.kind && part.id == group.parts.last?.id)
                    }
                }
            }
            .background(ThemeColor.surfaceRaised, in: RoundedRectangle(cornerRadius: ThemeRadius.row, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThemeRadius.row, style: .continuous).stroke(ThemeColor.separator, lineWidth: 1))
        }
    }

    private func partRow(_ f: Franchise, part: FranchisePart, isLast: Bool) -> some View {
        let episodic = part.kind == .season || part.totalEpisodes > 1
        return Button {
            if episodic { push(.episodes(franchiseId: f.id, mediaId: part.mediaId, focusEpisode: nil)) }
            else if inLibrary { toggleUnit(f, part: part) }
        } label: {
            HStack(spacing: ThemeSpace.x3) {
                PosterSlot(url: part.cover ?? f.cover, width: 40, height: 60, radius: ThemeRadius.episodeStill)
                VStack(alignment: .leading, spacing: 2) {
                    Text(part.canonicalLabel.isEmpty ? part.title : part.canonicalLabel)
                        .type(ThemeType.showTitleS).foregroundStyle(ThemeColor.textPrimary).lineLimit(2)
                    Text(partSubtitle(f, part: part)).type(ThemeType.metadata).foregroundStyle(ThemeColor.textSecondary).lineLimit(2)
                }
                Spacer(minLength: ThemeSpace.x2)
                if part.isComplete && !part.isReleasing {
                    PassiveTick(boxed: false)
                }
                if episodic {
                    Image(systemName: "chevron.forward").font(.system(size: 12, weight: .semibold)).foregroundStyle(ThemeColor.textTertiary)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 68)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !isLast { Rectangle().fill(ThemeColor.separator).frame(height: 1).padding(.leading, 66) }
            }
        }
        .buttonStyle(GroupedRowPressStyle())
        .accessibilityLabel("\(part.canonicalLabel), \(partSubtitle(f, part: part))")
        .accessibilityHint(episodic ? "Opens the episode list" : (inLibrary ? "Toggles watched" : ""))
    }

    private func partSubtitle(_ f: Franchise, part: FranchisePart) -> String {
        if part.isUpcoming {
            return part.announcedDateLabel(source: f.source).map { "Premieres \($0)" } ?? "No date announced"
        }
        if part.kind != .season && part.totalEpisodes <= 1 {
            var bits = [part.kind.rawValue.uppercased() == "MOVIE" ? "Film" : part.kind.rawValue.capitalized]
            if let y = part.year { bits.append(String(y)) }
            if part.isComplete { bits.append("Watched") }
            return bits.joined(separator: " · ")
        }
        let total = max(part.totalEpisodes, part.airedEpisodes)
        if part.isReleasing {
            if part.episodesBehind > 0 { return Copy.Progress.behind(part.episodesBehind) }
            if let at = f.nextAiring(now: now), f.releasingPart?.mediaId == part.mediaId {
                return "\(Copy.Progress.caughtUp) · \(TemporalCopy.airs(at: at, now: now, source: f.source))"
            }
            return Copy.Progress.caughtUp
        }
        if total > 0 { return Copy.Progress.watchedOf(min(part.progress, total), total) }
        return Copy.episodes(part.progress) + " watched"
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

    private var now: Int64 { appModel.now }
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
            if let f = franchise, let part {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: ThemeSpace.x3) {
                            header(f, part: part)
                            VStack(spacing: 0) {
                                ForEach(1...max(1, count(part)), id: \.self) { n in
                                    row(f, part: part, n: n, isLast: n == count(part))
                                        .id("ep-\(n)")
                                }
                            }
                            .background(ThemeColor.surfaceRaised, in: RoundedRectangle(cornerRadius: ThemeRadius.row, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: ThemeRadius.row, style: .continuous).stroke(ThemeColor.separator, lineWidth: 1))
                        }
                        .padding(.horizontal, ThemeSpace.x4)
                        .padding(.bottom, 120)
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
                Skeleton.detail
            }
        }
        .navigationTitle(part?.canonicalLabel ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { if fetched == nil { fetched = try? await appModel.api.franchise(id: franchiseId) } }
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

    private func header(_ f: Franchise, part: FranchisePart) -> some View {
        HStack(alignment: .firstTextBaseline) {
            let total = max(part.totalEpisodes, part.airedEpisodes)
            ProgressText(total > 0 ? Copy.Progress.watchedOf(min(part.progress, total), total) : Copy.episodes(part.progress) + " watched")
            Spacer()
            if appModel.isInLibrary(f.id) {
                Menu {
                    let target = part.markTarget(now: now)
                    if target > part.progress {
                        Button(Copy.Action.markAll(target - part.progress)) { promptMark(f, part: part, through: target) }
                    }
                    if part.progress > 0 {
                        Button(Copy.Action.markAllUnwatched(part.progress), role: .destructive) { promptUnmark(f, part: part, to: 0) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 20, weight: .regular))
                        .foregroundStyle(ThemeColor.accent).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Episode actions")
            }
        }
        .padding(.top, ThemeSpace.x2)
    }

    private func row(_ f: Franchise, part: FranchisePart, n: Int, isLast: Bool) -> some View {
        let episode = part.episodes.first { $0.number == n }
        let watched = n <= part.progress
        let aired = !part.isReleasing || n <= part.provenAiredCount(now: now) || n <= part.airedEpisodes
        let isNext = n == part.progress + 1 && aired
        let spoilerSafe = watched || isNext || revealed.contains(n)
        let interactive = appModel.isInLibrary(f.id) && aired
        return HStack(spacing: ThemeSpace.x3) {
            Button { if interactive { tapped(f, part: part, n: n, watched: watched) } } label: {
                HStack(spacing: ThemeSpace.x3) {
                    if let still = episode?.still, spoilerSafe {
                        EpisodeArtwork(url: still, spoilerSafe: true)
                    } else {
                        EpisodeGlyphTile()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rowTitle(episode, n: n, spoilerSafe: spoilerSafe))
                            .type(ThemeType.bodyEmphasis)
                            .foregroundStyle(watched ? ThemeColor.textSecondary : ThemeColor.textPrimary)
                            .lineLimit(2)
                        if let sub = rowSubtitle(f, part: part, episode: episode, n: n, aired: aired, isNext: isNext) {
                            Text(sub.text).type(ThemeType.metadata).foregroundStyle(sub.accent ? ThemeColor.accent : ThemeColor.textTertiary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !spoilerSafe, (episode?.title?.isEmpty == false || episode?.still != nil) {
                Button {
                    withAnimation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion)) { revealed.insert(n) }
                } label: {
                    Image(systemName: "eye").font(.system(size: 15)).frame(width: 44, height: 44).foregroundStyle(ThemeColor.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Copy.Action.showTitle)
            }
            if aired {
                Button { if interactive { tapped(f, part: part, n: n, watched: watched) } } label: {
                    ZStack {
                        Circle().stroke(isNext ? ThemeColor.accent : ThemeColor.strokeStrong, lineWidth: 1.5).frame(width: 24, height: 24).opacity(watched ? 0 : 1)
                        Circle().fill(ThemeColor.textPrimary).frame(width: 24, height: 24).opacity(watched ? 1 : 0)
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(ThemeColor.canvas).opacity(watched ? 1 : 0)
                    }
                    .frame(width: 44, height: 44)
                    .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: watched)
                }
                .buttonStyle(.plain)
                .disabled(!interactive)
                .accessibilityLabel("\(Copy.episode(n)), \(watched ? "watched" : "not watched")")
            }
        }
        .padding(.leading, 12).padding(.trailing, 6)
        .frame(minHeight: 68)
        .opacity(aired ? 1 : 0.55)
        .overlay(alignment: .bottom) {
            if !isLast { Rectangle().fill(ThemeColor.separator).frame(height: 1).padding(.leading, 120) }
        }
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
            guard !reduceMotion, SeasonSweepLedger.claim(token) else { return }
            visible = true
            withAnimation(ThemeMotion.uiSweep) { progress = 1 } completion: {
                withAnimation(ThemeMotion.uiGentle.delay(0.4)) { visible = false }
            }
        }
    }
}
