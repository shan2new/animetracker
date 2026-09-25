import SwiftUI

// Muted shows (iD13): the shows whose news you muted from a post's menu, from `GET /me/hides` plus
// the mutes this device has not confirmed yet. The show as an account (its avatar), its name, and
// one capsule. Unmuting keeps the row — its capsule now says "Mute" — so a slip is undone where it
// happened; the feed takes the show's posts back at once (the model re-composes on the hide).

struct MutedShowsView: View {
    @Environment(AppModel.self) private var appModel

    @State private var shows: [MutedShow] = []
    @State private var phase: Phase = .loading

    private enum Phase: Equatable { case loading, failed(offline: Bool), loaded }

    var body: some View {
        content
            .background(ThemeColor.canvas.ignoresSafeArea())
            .navigationTitle(Copy.Social.mutedTitle)
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if shows.isEmpty {
            switch phase {
            case .loading:
                ProgressView()
                    .tint(ThemeColor.feedSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(Copy.Accessibility.loading)
            case .failed(let offline):
                EmptyState(offline ? .communityOffline : .mutedFailed, prominence: .major) {
                    Task { await load() }
                }
                .padding(.horizontal, ThemeMetrics.gutter)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                EmptyState(.mutedEmpty, prominence: .major)
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            let muted = appModel.mutedShowIds
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(shows) { show in
                        row(show, muted: muted.contains(show.id))
                    }
                }
            }
            .scrollIndicators(.hidden)
            .refreshable { await load() }
            .laneClearance(appModel, base: ThemeMetrics.tabBarClearance)
        }
    }

    private func row(_ show: MutedShow, muted: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: FeedMetrics.gap) {
                ShowAvatar(candidates: show.candidates)
                Text(show.title)
                    .type(ThemeType.feedName)
                    .foregroundStyle(ThemeColor.feedText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    if muted {
                        appModel.unmuteShow(franchiseId: show.id)
                    } else {
                        appModel.muteShow(franchiseId: show.id, showName: show.title, fromPostId: nil)
                    }
                } label: {
                    Text(muted ? Copy.Social.unmute : Copy.Social.mute)
                        .contentTransition(.opacity)
                }
                .buttonStyle(SecondaryButtonStyle2())
                .fixedSize()
                .accessibilityLabel(muted ? Copy.Feed.unmute(show.title) : Copy.Feed.mute(show.title))
            }
            .padding(.horizontal, FeedMetrics.inset)
            .padding(.vertical, ThemeSpace.x3)
            Rectangle().fill(ThemeColor.feedSeparator).frame(height: FeedMetrics.hairline)
        }
    }

    private func load() async {
        if shows.isEmpty { phase = .loading }
        guard let hides = await appModel.loadHides() else {
            if shows.isEmpty { phase = .failed(offline: !SyncCenter.shared.isOnline) }
            return
        }
        var rows: [MutedShow] = []
        var seen = Set<String>()
        // Mutes this device has not confirmed yet lead (they are the newest).
        let confirmed = Set(hides.filter { $0.kind == .show }.map(\.target))
        for id in appModel.mutedShowIds.sorted() where !confirmed.contains(id) {
            if let show = describe(id, serverTitle: nil), seen.insert(id).inserted { rows.append(show) }
        }
        for hide in hides where hide.kind == .show {
            if let show = describe(hide.target, serverTitle: hide.franchise?.title), seen.insert(hide.target).inserted {
                rows.append(show)
            }
        }
        shows = rows
        phase = .loaded
    }

    /// A muted show's name and faces: the library's copy, else a loaded feed's, else the server's
    /// bare title (no art). Nil when nothing can name it.
    private func describe(_ id: String, serverTitle: String?) -> MutedShow? {
        if let f = appModel.franchise(id: id) {
            return MutedShow(id: id, title: f.displayTitle, candidates: FeedAvatar.candidates(f))
        }
        for state in appModel.feedTabs.values {
            if let show = state.response?.franchises.first(where: { $0.id == id }) {
                let stub = show.stub
                return MutedShow(id: id, title: stub.displayTitle, candidates: FeedAvatar.candidates(stub))
            }
        }
        guard let serverTitle, !serverTitle.isEmpty else { return nil }
        return MutedShow(id: id, title: serverTitle, candidates: [])
    }
}

/// A row of Muted shows, resolved once when the list loads.
private struct MutedShow: Identifiable {
    let id: String
    let title: String
    let candidates: [String]
}
