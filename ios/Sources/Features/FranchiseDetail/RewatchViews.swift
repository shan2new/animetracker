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
                VStack(alignment: .leading, spacing: ThemeSpace.x5) {
                    Text("Your previous watch history stays unchanged.")
                        .type(ThemeType.callout).foregroundStyle(ThemeColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                        .frame(minHeight: 52)
                    }
                    Button(Copy.Action.startRewatch) {
                        onStart(scope, Int64(startDate.timeIntervalSince1970 * 1000))
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle2())
                    .padding(.top, ThemeSpace.x2)
                }
                .padding(ThemeSpace.x4)
            }
            .background(ThemeColor.canvasRaised.ignoresSafeArea())
            .navigationTitle(Copy.Action.startRewatch)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(Copy.Action.cancel) { dismiss() } }
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
            ScrollView {
                VStack(alignment: .leading, spacing: ThemeSpace.x4) {
                    if sessions.isEmpty {
                        EmptyState(.noSessions, prominence: .section).padding(.top, ThemeSpace.x2)
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
                .padding(.horizontal, ThemeSpace.x4)
                .padding(.top, ThemeSpace.x3)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
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
                        Image(systemName: "ellipsis.circle")
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
                VStack(alignment: .leading, spacing: ThemeSpace.x5) {
                    GroupedList {
                        HStack {
                            Text("Start date").type(ThemeType.body).foregroundStyle(ThemeColor.textPrimary)
                            Spacer()
                            DatePicker("Start date", selection: $startDate, in: ...Date(), displayedComponents: .date)
                                .labelsHidden().tint(ThemeColor.accent)
                        }
                        .padding(.leading, 14).padding(.trailing, 10)
                        .frame(minHeight: 52)
                        .overlay(alignment: .bottom) { Rectangle().fill(ThemeColor.separator).frame(height: 1).padding(.leading, 14) }
                        GroupedRow(title: "Status", trailing: .value(session.isActive ? "In progress" : (session.isCompleted ? "Completed" : "Cancelled")))
                        if let completed = session.completedAt, completed > 0 {
                            GroupedRow(title: "Completed", trailing: .value(TemporalCopy.dateWord(completed, now: now, anchor: .local)))
                        }
                        GroupedRow(title: "Episodes", trailing: .value(session.episodes > 0 ? "\(session.episodes)" : "—"), separator: false)
                    }
                    Button(Copy.Action.deleteThisSession) { confirmDelete = true }
                        .buttonStyle(TertiaryButtonStyle2(destructive: true))
                        .frame(maxWidth: .infinity)
                }
                .padding(ThemeSpace.x4)
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
