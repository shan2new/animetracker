import SwiftUI

// "Today" — the Focus Stack (spec v8, boards 01–03). One frame answers "what now":
//   arrival  → Previously Recap (eyebrow "Since Tuesday" + ≤3 beats) held, then handed off;
//   resting  → the Focus Card (the single most actionable item) + two queue rows + "View all";
//   calm     → "Nothing changed since you were last here" + the next known event.
// Presentation is derived from AppModel feeds (outNow → keepWatching → nextUp); the view owns
// only timing state. One haptic per transaction; the Undo toast lands when the handoff settles.
struct TodayView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AuthManager.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String) -> Void
    var onSeeAllWatching: () -> Void = {}
    var onAddShow: () -> Void = {}

    private var now: Int64 { appModel.now }

    @State private var showProfile = false
    @State private var showSkeleton = false

    // Recap
    @State private var recap: RecapDigest?
    @State private var recapMode: RecapDigest.Presentation = .none
    @State private var recapOnStage = false        // full card occupies the Focus frame
    @State private var recapRevealed = false       // beats have finished revealing
    @State private var recapEvaluated = false
    @State private var recapClockStarted = false
    @State private var recapSeenSurface = false

    // Mark handoff
    @State private var pinned: [Franchise]?        // stack snapshot held while the card shows its result
    @State private var committedEpisode: Int?
    @State private var pendingUndo: UndoState?
    @State private var batchPrompt: BatchPrompt?

    @Namespace private var ns

    private static let queueCount = 2
    private static let shelfCap = 10

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                content
            }
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(ThemeColor.canvas.ignoresSafeArea())
        .refreshable { await appModel.reload() }
        .sheet(isPresented: $showProfile) { ProfileView() }
        .task {
            try? await Task.sleep(for: .milliseconds(240))
            if appModel.loading && appModel.library.isEmpty { showSkeleton = true }
        }
        .onChange(of: appModel.loading) { _, loading in
            if !loading { showSkeleton = false; evaluateRecap() }
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
            Button("Cancel", role: .cancel) {}
        } message: { prompt in
            Text(prompt.message)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Wordmark()
            Spacer()
            Button { showProfile = true } label: {
                ZStack {
                    Circle().fill(ThemeColor.surfaceFloating)
                    Circle().stroke(ThemeColor.stroke, lineWidth: 1)
                    Text(initials)
                        .type(ThemeType.metadataEmphasis)
                        .foregroundStyle(ThemeColor.textSecondary)
                }
                .frame(width: 30, height: 30)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
        }
        .padding(.leading, 16)
        .padding(.trailing, 9)
        .frame(height: 52)
    }

    private var initials: String {
        let name = auth.displayName.trimmingCharacters(in: .whitespaces)
        let parts = name.split(separator: " ").prefix(2).compactMap { $0.first }
        let s = String(parts).uppercased()
        return s.isEmpty ? "•" : s
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if appModel.loading && appModel.library.isEmpty {
            if showSkeleton { skeleton.transition(.opacity) }
        } else if appModel.loadError && appModel.libraryEmpty {
            stateCard(symbol: "wifi.slash", title: "Connect to load your library",
                      message: "Your shows will appear once you’re back online.",
                      cta: "Try again") { Task { await appModel.reload() } }
        } else if appModel.libraryEmpty {
            stateCard(symbol: "tv", title: "Nothing here yet",
                      message: "Add the shows you’re watching and Today will tell you what’s next.",
                      cta: "Add a show", action: onAddShow)
        } else {
            stack
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 16) {
                    SkeletonBlock(width: 80, height: 120, radius: ThemeRadius.poster)
                    VStack(alignment: .leading, spacing: 10) {
                        SkeletonBlock(width: 90, height: 10)
                        SkeletonBlock(width: 180, height: 18)
                        SkeletonBlock(width: 130, height: 12)
                    }
                    .padding(.top, 4)
                }
                SkeletonBlock(height: 48, radius: 24)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 212, alignment: .topLeading)
            .background(ThemeColor.surfaceFlat, in: RoundedRectangle(cornerRadius: ThemeRadius.focusCard, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 12) {
                    SkeletonBlock(width: 36, height: 54, radius: 6)
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBlock(width: 160, height: 13)
                        SkeletonBlock(width: 110, height: 10)
                    }
                }
                .padding(.horizontal, 24)
            }
            SkeletonBlock(width: 120, height: 10).padding(.horizontal, 16).padding(.top, 8)
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in SkeletonBlock(width: 104, height: 156, radius: ThemeRadius.poster) }
            }
            .padding(.horizontal, 16)
        }
        .accessibilityLabel("Loading")
    }

    private func stateCard(symbol: String, title: String, message: String, cta: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(ThemeColor.textTertiary)
                .padding(.bottom, 4)
            Text(title).type(ThemeType.showTitleL).foregroundStyle(ThemeColor.textPrimary)
            Text(message).type(ThemeType.callout).foregroundStyle(ThemeColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(cta, action: action)
                .buttonStyle(SecondaryButtonStyle2())
                .padding(.top, 8)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThemeColor.surfaceFlat, in: RoundedRectangle(cornerRadius: ThemeRadius.focusCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThemeRadius.focusCard, style: .continuous).stroke(ThemeColor.separator, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - The stack

    /// Actionable items, most actionable first: fresh unwatched episodes, then backlog.
    private var liveItems: [Franchise] {
        appModel.outNow + appModel.keepWatching
    }
    private var items: [Franchise] { pinned ?? liveItems }
    private var focus: Franchise? { items.first }
    private var queue: [Franchise] { Array(items.dropFirst().prefix(TodayView.queueCount)) }
    private var stackIds: Set<String> { Set(items.prefix(TodayView.queueCount + 1).map(\.id)) }
    private var updateCount: Int { appModel.outNow.count }
    private var comingNext: Franchise? {
        guard let f = appModel.nextUp, !stackIds.contains(f.id) else { return nil }
        return f
    }
    private var shelf: [Franchise] {
        Array(appModel.watchingShelf.filter { !stackIds.contains($0.id) }.prefix(TodayView.shelfCap))
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appModel.loadError {
                staleStrip.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 8)
            }
            if recapMode == .strip, !recapOnStage, let recap {
                RecapStrip(text: recapStripText(recap)) { stageRecap() }
                    .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 8)
                    .transition(.opacity)
            }

            // The Focus frame: recap on arrival, otherwise the card.
            ZStack(alignment: .top) {
                if recapOnStage, let recap {
                    RecapCard(digest: recap, revealed: recapRevealed, now: now, ns: ns, reduceMotion: reduceMotion)
                        .onTapGesture { handoffRecap(userAction: true) }
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.985))))
                } else if let focus {
                    focusCard(focus)
                        .id(focus.id)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity.combined(with: .scale(scale: 0.985))))
                } else {
                    calmCard.transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .animation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion), value: recapOnStage)
            .animation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion), value: focus?.id)

            if !recapOnStage {
                if !queue.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(queue) { f in
                            queueRow(f)
                                .transition(.opacity.combined(with: .offset(y: 4)))
                        }
                    }
                    .padding(.top, 6)
                    .padding(.horizontal, 8)
                    .animation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion), value: queue.map(\.id))
                }
                if updateCount > TodayView.queueCount + 1 {
                    Button("View all \(updateCount) updates", action: onSeeAllWatching)
                        .buttonStyle(TertiaryButtonStyle2())
                        .padding(.horizontal, 16)
                }
                if let next = comingNext, let part = next.releasingPart, let at = next.nextAiring(now: now) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Coming next").padding(.horizontal, 16)
                        Button { onOpenDetail(next.id, "next/\(next.id)") } label: {
                            HStack(spacing: 12) {
                                PosterSlot(url: next.cover, width: 36, height: 54, radius: 6)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(next.title).type(ThemeType.showTitleS).foregroundStyle(ThemeColor.textPrimary).lineLimit(1)
                                    Text("Episode \(part.nextEpisodeNumber ?? part.airedEpisodes + 1) · \(TemporalCopy.airs(at: at, now: now, source: next.source))")
                                        .type(ThemeType.metadata).foregroundStyle(ThemeColor.textSecondary).lineLimit(2)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.forward").font(.system(size: 12, weight: .semibold)).foregroundStyle(ThemeColor.textTertiary)
                            }
                            .padding(.horizontal, 8)
                            .frame(minHeight: 68)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        .padding(.horizontal, 8)
                    }
                    .padding(.top, 22)
                }
                if !shelf.isEmpty {
                    watchingShelf.padding(.top, 26)
                }
            }
        }
        .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: recapMode)
    }

    private var staleStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle").font(.system(size: 13, weight: .semibold)).foregroundStyle(ThemeColor.warning)
            Text("Couldn’t refresh airing dates").type(ThemeType.metadataEmphasis).foregroundStyle(ThemeColor.textPrimary)
            Spacer()
            Button("Retry") { Task { await appModel.reload() } }.buttonStyle(TertiaryButtonStyle2())
        }
        .padding(.leading, 14)
        .frame(minHeight: 44)
        .background(ThemeColor.surfaceFlat, in: RoundedRectangle(cornerRadius: ThemeRadius.row, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThemeRadius.row, style: .continuous).stroke(ThemeColor.warning.opacity(0.35), lineWidth: 1))
        .transition(.opacity)
    }

    // MARK: - Focus card

    private enum FocusKind { case fresh(behind: Int), backlog(left: Int), caughtUp, waiting(at: Int64) }

    private func kind(of f: Franchise) -> (FocusKind, FranchisePart)? {
        // Evaluated on the object (not the live feed) so a pinned snapshot keeps its wording while
        // the card shows its result.
        if let part = f.releasingPart, now - (part.lastAiredAt ?? 0) <= AppModel.outNowWindow,
           part.episodesBehind > 0 || appModel.justCaught.contains(f.id) {
            return part.episodesBehind > 0 ? (.fresh(behind: part.episodesBehind), part) : (.caughtUp, part)
        }
        if let part = f.resumePart { return (.backlog(left: f.continueBacklog), part) }
        if let part = f.releasingPart, let at = f.nextAiring(now: now) { return (.waiting(at: at), part) }
        return nil
    }

    @ViewBuilder
    private func focusCard(_ f: Franchise) -> some View {
        if let (kind, part) = kind(of: f) {
            let nextEpisode = part.progress + 1
            let behind: Int = {
                if case .fresh(let b) = kind { return b }
                if case .backlog(let l) = kind { return l }
                return 0
            }()
            let committed = committedEpisode != nil && pinned?.first?.id == f.id
            FocusCardView(
                franchise: f,
                eyebrow: eyebrow(kind, f: f, part: part),
                eyebrowDot: { if case .fresh = kind { return true } else { return false } }(),
                meta: metaLine(part: part, episode: nextEpisode),
                line: supportLine(kind, f: f, part: part),
                ctaEpisode: committed ? committedEpisode : (behind > 0 ? nextEpisode : nil),
                committed: committed,
                behind: behind,
                ns: ns,
                onOpen: { onOpenDetail(f.id, "focus/\(f.id)") },
                onMark: { mark(f) },
                onMarkThrough: { n in promptBatch(f, part: part, through: n) },
                onMarkAll: { promptBatch(f, part: part, through: part.progressCeiling) },
                onViewEpisodes: { onOpenDetail(f.id, "focus/\(f.id)") }
            )
        }
    }

    private func eyebrow(_ kind: FocusKind, f: Franchise, part: FranchisePart) -> String {
        switch kind {
        case .fresh(let behind):
            if behind > 1 { return "\(behind) episodes behind" }
            if let last = part.lastAiredAt { return TemporalCopy.aired(at: last, now: now, source: f.source) }
            return "New episode"
        case .backlog: return "Continue"
        case .caughtUp: return "Caught up"
        case .waiting: return "Up next"
        }
    }

    private func metaLine(part: FranchisePart, episode: Int) -> String {
        if part.isMovie { return part.label }
        let season = part.kind == .season ? part.label : part.label
        return "\(season) · Episode \(episode)"
    }

    private func supportLine(_ kind: FocusKind, f: Franchise, part: FranchisePart) -> String? {
        switch kind {
        case .fresh(let behind):
            if behind == 1 { return "Caught up after this episode" }
            if let last = part.lastAiredAt { return "Latest " + TemporalCopy.aired(at: last, now: now, source: f.source).lowercased() }
            return nil
        case .backlog(let left):
            return left == 1 ? "Last episode of the season" : "\(left) episodes left"
        case .caughtUp:
            if let at = part.nextAiringAt, at > now { return TemporalCopy.airs(at: at, now: now, source: f.source) }
            return nil
        case .waiting(let at):
            return TemporalCopy.airs(at: at, now: now, source: f.source)
        }
    }

    // MARK: - Calm card

    private var calmCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Today")
            Text("Nothing changed since you were last here")
                .type(ThemeType.showTitleM).foregroundStyle(ThemeColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let next = appModel.nextUp, let at = next.nextAiring(now: now) {
                Text("\(next.title) · \(TemporalCopy.airs(at: at, now: now, source: next.source))")
                    .type(ThemeType.metadata).foregroundStyle(ThemeColor.textSecondary).lineLimit(2)
            } else {
                Text("No dates announced for what you’re watching")
                    .type(ThemeType.metadata).foregroundStyle(ThemeColor.textTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThemeColor.surfaceFlat, in: RoundedRectangle(cornerRadius: ThemeRadius.focusCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThemeRadius.focusCard, style: .continuous).stroke(ThemeColor.separator, lineWidth: 1))
    }

    // MARK: - Queue rows

    private func queueRow(_ f: Franchise) -> some View {
        Button { onOpenDetail(f.id, "queue/\(f.id)") } label: {
            HStack(spacing: 12) {
                PosterSlot(url: f.cover, width: 36, height: 54, radius: 6)
                    .matchedGeometryEffect(id: "poster/\(f.id)", in: ns)
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.title).type(ThemeType.showTitleS).foregroundStyle(ThemeColor.textPrimary).lineLimit(1)
                    Text(queueMeta(f)).type(ThemeType.metadata).foregroundStyle(ThemeColor.textSecondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward").font(.system(size: 12, weight: .semibold)).foregroundStyle(ThemeColor.textTertiary)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    private func queueMeta(_ f: Franchise) -> String {
        guard let (kind, part) = kind(of: f) else { return "" }
        let ep = "Episode \(part.progress + 1)"
        switch kind {
        case .fresh(let behind):
            if behind > 1 { return "\(ep) · \(behind) behind" }
            if let last = part.lastAiredAt { return "\(ep) · \(TemporalCopy.aired(at: last, now: now, source: f.source))" }
            return ep
        case .backlog(let left): return "\(ep) · \(left) left"
        case .caughtUp: return "Caught up"
        case .waiting(let at): return TemporalCopy.airs(at: at, now: now, source: f.source)
        }
    }

    // MARK: - Watching shelf

    private var watchingShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Watching")
                Spacer()
                Button("See all", action: onSeeAllWatching).buttonStyle(TertiaryButtonStyle2())
                    .frame(height: 20)
            }
            .padding(.horizontal, 16)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(shelf) { f in
                        Button { onOpenDetail(f.id, "shelf/\(f.id)") } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                PosterSlot(url: f.cover, width: 104, height: 156)
                                Text(f.title).type(ThemeType.showTitleS).foregroundStyle(ThemeColor.textPrimary)
                                    .lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                Text(shelfCaption(f)).type(ThemeType.caption).foregroundStyle(ThemeColor.textTertiary).lineLimit(1)
                            }
                            .frame(width: 104, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    private func shelfCaption(_ f: Franchise) -> String {
        switch appModel.shelfState(of: f) {
        case .newEpisode: return "New episode"
        case .backlog:
            if let p = f.resumePart { return "Episode \(p.progress + 1) next" }
            return "Continue"
        case .airingWait:
            if let at = f.nextAiring(now: now) { return TemporalCopy.airsCompact(at: at, now: now, source: f.source) }
            return "Caught up"
        case .premiereSoon:
            return TemporalCopy.returns(at: appModel.nextPremiere(of: f), now: now, source: f.source)
        case nil: return ""
        }
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
            title: all ? "Mark all \(count) episodes as watched?" : "Mark through Episode \(through)?",
            message: "\(f.title) · \(part.label). You can undo this for a few seconds.",
            confirm: all ? "Mark \(count) episodes" : "Mark \(count) episodes",
            perform: {
                if all { appModel.markCaughtUp(f.id) }
                else { appModel.setProgress(franchiseId: f.id, mediaId: part.mediaId, episodes: through) }
            }
        )
    }

    // MARK: - Recap

    /// Computes the digest as soon as the library is in — under the splash if need be — and puts
    /// the full recap on stage immediately, so it is the first thing in the Focus frame. The
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

    /// The strip was tapped: bring the full recap on stage and run its clock.
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
            handoffRecap(userAction: false)
        }
    }

    private func handoffRecap(userAction: Bool) {
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
        if aired > 0 { return "\(aired == 1 ? "1 episode" : "\(aired) episodes") aired \(since)" }
        return "\(recap.beats.count) updates \(since)"
    }
}

extension RecapState {
    /// `-recapDemo 1` launch argument: force the full recap every launch (captures / review).
    static var demo: Bool { UserDefaults.standard.bool(forKey: "recapDemo") }
}

// MARK: - Wordmark

/// "Previously." — Outfit SemiBold 20, the full stop in accent. Static unless a live indicator
/// is earned (an exact-time episode is airing right now).
struct Wordmark: View {
    var body: some View {
        Text("Previously\(Text(".").foregroundStyle(ThemeColor.accent))")
            .foregroundStyle(ThemeColor.textPrimary)
            .type(ThemeType.brandWordmark)
            .accessibilityLabel("Previously")
    }
}

// MARK: - Focus card view

struct FocusCardView: View {
    let franchise: Franchise
    let eyebrow: String
    let eyebrowDot: Bool
    let meta: String
    let line: String?
    let ctaEpisode: Int?
    let committed: Bool
    let behind: Int
    let ns: Namespace.ID
    let onOpen: () -> Void
    let onMark: () -> Void
    let onMarkThrough: (Int) -> Void
    let onMarkAll: () -> Void
    let onViewEpisodes: () -> Void

    @State private var tint: Color?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Accessibility sizes stack the poster above the text instead of beside it (spec: Dynamic Type).
    private var isAX: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: onOpen) {
                let layout = isAX ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                                  : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                layout {
                    PosterSlot(url: franchise.cover, width: 80, height: 120)
                        .matchedGeometryEffect(id: "poster/\(franchise.id)", in: ns)
                    VStack(alignment: .leading, spacing: 5) {
                        SectionLabel(text: eyebrow, dot: eyebrowDot, tint: eyebrowDot ? ThemeColor.accent : ThemeColor.textTertiary)
                        Text(franchise.title)
                            .type(ThemeType.showTitleL)
                            .foregroundStyle(ThemeColor.textPrimary)
                            .lineLimit(isAX ? 4 : 2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(meta)
                            .type(ThemeType.metadataEmphasis)
                            .foregroundStyle(ThemeColor.textSecondary)
                            .contentTransition(.numericText())
                            .lineLimit(2)
                        if let line {
                            Text(line).type(ThemeType.metadata).foregroundStyle(ThemeColor.textTertiary).lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, isAX ? 0 : 2)
                    if !isAX { Spacer(minLength: 0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the show")

            if let ctaEpisode {
                cta(episode: ctaEpisode)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 212, alignment: .topLeading)
        .background(ArtAdaptiveGround(tint: tint))
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.focusCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThemeRadius.focusCard, style: .continuous).stroke(ThemeColor.stroke, lineWidth: 1))
        .task(id: franchise.cover) {
            tint = await PaletteCache.shared.resolve(url: franchise.cover, maxPixel: 360)
        }
    }

    @ViewBuilder
    private func cta(episode: Int) -> some View {
        let label = HStack(spacing: 8) {
            if committed {
                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            Text(committed ? "Episode \(episode) watched" : "Mark as watched")
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
                let through = min(episode + 4, episode + behind - 1)
                if through > episode {
                    Button("Mark through Episode \(through)") { onMarkThrough(through) }
                }
                Button("Mark all \(behind) episodes as watched") { onMarkAll() }
                Button("View episodes") { onViewEpisodes() }
            } label: {
                label
            } primaryAction: {
                onMark()
            }
            .buttonStyle(PrimaryButtonStyle2())
            .accessibilityLabel("Mark Episode \(episode) of \(franchise.title) as watched")
        } else {
            Button(action: onMark) { label }
                .buttonStyle(PrimaryButtonStyle2())
                .allowsHitTesting(!committed)
                .accessibilityLabel(committed ? "Episode \(episode) watched" : "Mark Episode \(episode) of \(franchise.title) as watched")
        }
    }
}

// MARK: - Recap card

struct RecapCard: View {
    let digest: RecapDigest
    let revealed: Bool
    let now: Int64
    let ns: Namespace.ID
    let reduceMotion: Bool

    @State private var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: TemporalCopy.since(digest.since, now: now))
                .opacity(revealed ? 1 : 0)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(digest.beats.enumerated()), id: \.element.id) { i, beat in
                    HStack(spacing: 12) {
                        PosterSlot(url: beat.cover, width: 36, height: 54, radius: 6)
                            .matchedGeometryEffect(id: "poster/\(beat.franchiseId)", in: ns)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(beat.title).type(ThemeType.showTitleS).foregroundStyle(ThemeColor.textPrimary).lineLimit(1)
                            Text(beat.label(now: now)).type(ThemeType.metadata).foregroundStyle(ThemeColor.textSecondary).lineLimit(1)
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
                    .type(ThemeType.caption).foregroundStyle(ThemeColor.textTertiary)
                    .opacity(revealed ? 1 : 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 212, alignment: .topLeading)
        .background(ArtAdaptiveGround(tint: tint))
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.focusCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThemeRadius.focusCard, style: .continuous).stroke(ThemeColor.stroke, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Since you were last here: " + digest.beats.map { "\($0.title), \($0.label(now: now))" }.joined(separator: ". "))
        .accessibilityHint("Double tap to continue")
        .task(id: digest.beats.first?.cover) {
            tint = await PaletteCache.shared.resolve(url: digest.beats.first?.cover, maxPixel: 360)
        }
    }
}
