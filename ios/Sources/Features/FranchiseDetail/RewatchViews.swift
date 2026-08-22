import SwiftUI

// Rewatch surfaces (spec board 06 §1.3, 1.5–1.7): the Start rewatch sheet, the Watch history rail
// and one session's detail. Sessions live in RewatchStore; progress lives on the server.

// MARK: - Start rewatch (Surface C)

struct StartRewatchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let franchise: Franchise
    let onStart: (_ scope: WatchSession.Scope, _ startedAt: Int64) -> Void

    @State private var scope: WatchSession.Scope = .franchise
    @State private var startDate = Date()

    private var parts: [FranchisePart] { franchise.episodicPartsInOrder }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ThemeMetrics.sectionGap) {
                    // The context row from board 06: the sheet says which show it is about, with
                    // its own artwork, before it asks anything. A modal that opens on a grey
                    // sentence and a list of radio rows could be about anything.
                    HStack(alignment: .top, spacing: ThemeMetrics.artGap) {
                        PosterSlot(url: franchise.cover, .queue)
                        VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                            Text(franchise.title)
                                .type(ThemeType.showTitleM)
                                .foregroundStyle(ThemeColor.textPrimary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Your previous watch history stays unchanged.")
                                .type(ThemeType.metadata).foregroundStyle(ThemeColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    GroupedList(header: "Scope") {
                        GroupedRow(title: "Entire franchise", trailing: .check(scope == .franchise), separator: !parts.isEmpty) {
                            FeedbackCoordinator.fire(.selection); scope = .franchise
                        }
                        ForEach(Array(parts.enumerated()), id: \.element.id) { i, part in
                            GroupedRow(title: "\(part.canonicalLabel.isEmpty ? part.title : part.canonicalLabel) only",
                                       subtitle: part.totalEpisodes > 0 ? Copy.episodes(part.totalEpisodes) : nil,
                                       trailing: .check(scope == .part(mediaId: part.mediaId)), separator: i < parts.count - 1) {
                                FeedbackCoordinator.fire(.selection); scope = .part(mediaId: part.mediaId)
                            }
                        }
                    }
                    GroupedList(header: "Start date") {
                        HStack {
                            Text("Start date").type(ThemeType.body).foregroundStyle(ThemeColor.textPrimary)
                            Spacer()
                            DatePicker("Start date", selection: $startDate, in: ...Date(), displayedComponents: .date)
                                .labelsHidden()
                                .tint(ThemeColor.accent)
                        }
                        .padding(.leading, 14).padding(.trailing, 10)
                        .frame(minHeight: ThemeMetrics.rowCompact)
                    }
                    Button(Copy.Action.startRewatch) {
                        onStart(scope, Int64(startDate.timeIntervalSince1970 * 1000))
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle2())
                }
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.top, ThemeSpace.x4)
                .padding(.bottom, ThemeSpace.x8)
            }
            .background(ThemeColor.canvasRaised.ignoresSafeArea())
            .navigationTitle(Copy.Action.startRewatch)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // A plain text button. iOS has never put a filled pill in a sheet's leading
                    // position, and the toolbar's own glass treatment turned this one into one.
                    Button { dismiss() } label: {
                        Text(Copy.Action.cancel)
                            .type(ThemeType.body)
                            .foregroundStyle(ThemeColor.accent)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Watch history (Surface D)

struct WatchHistoryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let franchiseId: String

    @State private var editing: WatchSession?
    @State private var confirmDeleteAll = false

    private var now: Int64 { appModel.now }
    private var store: RewatchStore { RewatchStore.shared }
    private var franchise: Franchise? { appModel.franchise(id: franchiseId) }
    private var sessions: [WatchSession] { store.sessions(for: franchiseId) }

    var body: some View {
        ZStack {
            ThemeColor.canvas.ignoresSafeArea()
            if let f = franchise {
                ArtBackdrop(url: f.banner ?? f.cover, height: 280, intensity: 0.55)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)
            }
            if sessions.isEmpty {
                // Centred, not top-pinned. An empty state pinned under the navigation bar with
                // 1 400 pt of canvas under it reads as a screen that failed to load; centred in
                // the content area it reads as the answer to the question the screen asks.
                EmptyState(.noSessions, prominence: .major)
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .padding(.bottom, ThemeMetrics.tabBarClearance)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: ThemeMetrics.sectionGap) {
                    identityHeader
                    if sessions.count == 1, let only = sessions.first {
                        // A rail needs two nodes to be a rail. One disconnected ring floating
                        // beside a single card was worse than no timeline at all, so a solo
                        // session is a plain row under its own label.
                        //
                        // And it carries NO poster: the identity header 40 pt above it is already
                        // showing that exact artwork at that exact size, and a session is not a
                        // different show — printing the cover twice made the screen read as two
                        // rows of the same list rather than a show and its record.
                        VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
                            SectionLabel(text: "Sessions")
                            soloSessionRow(only)
                        }
                    } else {
                        HistoryRail {
                            ForEach(Array(sessions.enumerated()), id: \.element.id) { i, session in
                                HistorySessionRow(title: session.title,
                                                  subtitle: session.subtitle(nextEpisode: nextEpisode(session), now: now),
                                                  poster: franchise?.cover,
                                                  active: session.isActive,
                                                  position: position(i, of: sessions.count)) {
                                    editing = session
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.top, ThemeSpace.x3)
                .padding(.bottom, ThemeMetrics.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            }
        }
        .scrollEdgeChrome()
        .navigationTitle(Copy.Action.viewWatchHistory.replacingOccurrences(of: "View ", with: "").capitalizedFirst())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !sessions.isEmpty {
                    Menu {
                        Button(role: .destructive) { confirmDeleteAll = true } label: {
                            Label(Copy.Action.deleteWatchHistory, systemImage: "trash")
                        }
                    } label: {
                        // Matches Detail's overflow exactly: a plain glyph on chrome glass. The
                        // amber-ringed `ellipsis.circle` read as this screen's primary action.
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ThemeColor.textPrimary)
                            .frame(width: 34, height: 34)
                            .chromeGlass(in: Circle(), interactive: true)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("More actions")
                }
            }
        }
        .sheet(item: $editing) { session in
            SessionDetailView(session: session)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(Copy.Confirm.deleteHistoryTitle, isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button(Copy.Confirm.deleteHistoryConfirm, role: .destructive) {
                FeedbackCoordinator.fire(.destructive)
                withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) { store.deleteAll(for: franchiseId) }
            }
            Button(Copy.Confirm.cancel, role: .cancel) {}
        } message: {
            Text(Copy.Confirm.deleteHistory(sessions: sessions.count, episodes: sessions.reduce(0) { $0 + $1.episodes }))
        }
    }

    /// Whose history this is. The shipped screen was one card and 700 pt of void under an inline
    /// title that said "Watch history" and nothing else — the show's name never appeared on it.
    /// The one session, as a record rather than as a media row: what it is called, when it ran,
    /// how many episodes it covered, and the way in.
    private func soloSessionRow(_ session: WatchSession) -> some View {
        let line = session.subtitle(nextEpisode: nextEpisode(session), now: now)
        return Button { editing = session } label: {
            HStack(alignment: .center, spacing: ThemeSpace.x3) {
                VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                    Text(session.title)
                        .type(ThemeType.rowTitle)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(line)
                        .type(session.isActive ? ThemeType.rowMetaLead : ThemeType.rowMeta)
                        .foregroundStyle(session.isActive ? ThemeColor.accent : ThemeColor.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: ThemeSpace.x2)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ThemeColor.textDisabled)
            }
            .frame(minHeight: ThemeMetrics.rowCompact)
            .contentShape(Rectangle())
        }
        .buttonStyle(GroupedRowPressStyle())
        .accessibilityLabel("\(session.title), \(line)")
    }

    @ViewBuilder
    private var identityHeader: some View {
        if let f = franchise, !sessions.isEmpty {
            let completed = store.summary(for: franchiseId).completedCount
            HStack(alignment: .top, spacing: ThemeMetrics.artGap) {
                PosterSlot(url: f.cover, .row)
                VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                    Text(f.title)
                        .type(ThemeType.showTitleM)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if completed > 0 { ProgressText(Copy.Progress.watchedTimes(completed)) }
                    ProgressText(Copy.watchSessions(sessions.count) + " · "
                                 + Copy.episodes(sessions.reduce(0) { $0 + $1.episodes }),
                                 tint: ThemeColor.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func nextEpisode(_ session: WatchSession) -> Int? {
        guard session.isActive, let f = franchise else { return nil }
        switch session.scope {
        case .franchise: return f.currentPart.map { $0.progress + 1 }
        case .part(let mediaId): return f.parts.first { $0.mediaId == mediaId }.map { $0.progress + 1 }
        }
    }

    private func position(_ i: Int, of n: Int) -> HistoryRailPosition {
        if n == 1 { return .only }
        if i == 0 { return .first }
        if i == n - 1 { return .last }
        return .middle
    }
}

// MARK: - Session detail (Surface E)

struct SessionDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let session: WatchSession

    @State private var startDate: Date
    @State private var confirmDelete = false

    init(session: WatchSession) {
        self.session = session
        _startDate = State(initialValue: session.startedAt.map { Date(timeIntervalSince1970: Double($0) / 1000) } ?? Date())
    }

    private var now: Int64 { appModel.now }
    private var store: RewatchStore { RewatchStore.shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ThemeMetrics.sectionGap) {
                    GroupedList {
                        HStack {
                            Text("Start date").type(ThemeType.body).foregroundStyle(ThemeColor.textPrimary)
                            Spacer()
                            DatePicker("Start date", selection: $startDate, in: ...Date(), displayedComponents: .date)
                                .labelsHidden().tint(ThemeColor.accent)
                        }
                        .padding(.leading, 14).padding(.trailing, 10)
                        .frame(minHeight: ThemeMetrics.rowCompact)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(ThemeColor.separatorQuiet).frame(height: 1).padding(.leading, 14)
                        }
                        GroupedRow(title: "Status", trailing: .value(session.isActive ? "In progress" : (session.isCompleted ? "Completed" : "Cancelled")))
                        if let completed = session.completedAt, completed > 0 {
                            GroupedRow(title: "Completed", trailing: .value(TemporalCopy.dateWord(completed, now: now, anchor: .local)))
                        }
                        GroupedRow(title: "Episodes", trailing: .value(session.episodes > 0 ? "\(session.episodes)" : "—"), separator: false)
                    }
                    // A destructive verb is a ROW in its own plate, not a red word floating
                    // centred under a void.
                    Button { confirmDelete = true } label: {
                        HStack {
                            Text(Copy.Action.deleteThisSession)
                                .type(ThemeType.body)
                                .foregroundStyle(ThemeColor.destructive)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: ThemeMetrics.rowCompact)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(GroupedRowPressStyle())
                    .surface(.plate, radius: ThemeRadius.row)
                }
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.top, ThemeSpace.x4)
                .padding(.bottom, ThemeSpace.x8)
            }
            .background(ThemeColor.canvasRaised.ignoresSafeArea())
            .navigationTitle(session.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Copy.Action.done) {
                        let ts = Int64(startDate.timeIntervalSince1970 * 1000)
                        if ts != session.startedAt { store.setStartDate(session.id, to: ts) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .confirmationDialog(Copy.Confirm.deleteSessionTitle, isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(Copy.Confirm.deleteSessionConfirm, role: .destructive) {
                    FeedbackCoordinator.fire(.destructive)
                    store.delete(session.id)
                    dismiss()
                }
                Button(Copy.Confirm.cancel, role: .cancel) {}
            } message: {
                Text(Copy.Confirm.deleteSession(count: session.episodes))
            }
        }
    }
}

private extension String {
    func capitalizedFirst() -> String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
