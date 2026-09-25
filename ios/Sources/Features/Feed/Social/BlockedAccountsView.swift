import SwiftUI

// Blocked accounts (spec §4.6, iD13, App Review 1.2 — the block list must be reachable): everyone
// you blocked, from `GET /me/blocks` with this device's unconfirmed words applied. X's list: the
// person's disc, name and handle, and one capsule. Unblocking keeps the row — its capsule now says
// "Block" — so a slip is undone where it happened; the list is re-read on the next visit.

struct BlockedAccountsView: View {
    @Environment(AppModel.self) private var appModel

    @State private var users: [BlockedUser] = []
    @State private var phase: Phase = .loading
    /// Unblocked on this visit: the row stays, and its capsule blocks again.
    @State private var unblocked: Set<String> = []

    private enum Phase: Equatable { case loading, failed(offline: Bool), loaded }

    var body: some View {
        content
            .background(ThemeColor.canvas.ignoresSafeArea())
            .brandNavigationTitle(Copy.Social.blockedTitle)
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if users.isEmpty {
            switch phase {
            case .loading:
                ProgressView()
                    .tint(ThemeColor.feedSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(Copy.Accessibility.loading)
            case .failed(let offline):
                EmptyState(offline ? .communityOffline : .blockedFailed, prominence: .major) {
                    Task { await load() }
                }
                .padding(.horizontal, ThemeMetrics.gutter)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                EmptyState(.blockedEmpty, prominence: .major)
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(users) { blocked in
                        row(blocked.user)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .refreshable { await load() }
            .laneClearance(appModel, base: ThemeMetrics.tabBarClearance)
        }
    }

    private func row(_ user: PublicUser) -> some View {
        let isUnblocked = unblocked.contains(user.id)
        return VStack(spacing: 0) {
            HStack(spacing: FeedMetrics.gap) {
                PersonDisc(user: user, size: FeedMetrics.avatar)
                VStack(alignment: .leading, spacing: 0) {
                    if !user.displayName.isEmpty {
                        Text(user.displayName)
                            .type(ThemeType.feedName)
                            .foregroundStyle(ThemeColor.feedText)
                            .lineLimit(1)
                    }
                    Text(Copy.Social.handle(user.handle))
                        .type(ThemeType.feedMeta)
                        .foregroundStyle(ThemeColor.feedSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                Button {
                    toggle(user, unblocking: !isUnblocked)
                } label: {
                    Text(isUnblocked ? Copy.Social.block : Copy.Social.unblock)
                        .contentTransition(.opacity)
                }
                .buttonStyle(SecondaryButtonStyle2())
                .fixedSize()
                .accessibilityLabel(isUnblocked ? Copy.Social.blockUser(user.handle) : Copy.Social.unblockUser(user.handle))
            }
            .padding(.horizontal, FeedMetrics.inset)
            .padding(.vertical, ThemeSpace.x3)
            Rectangle().fill(ThemeColor.feedSeparator).frame(height: FeedMetrics.hairline)
        }
    }

    private func toggle(_ user: PublicUser, unblocking: Bool) {
        if unblocking {
            unblocked.insert(user.id)
            Task { _ = await appModel.unblock(user) }
        } else {
            unblocked.remove(user.id)
            Task { _ = await appModel.block(user) }
        }
    }

    private func load() async {
        if users.isEmpty { phase = .loading }
        guard let list = await appModel.loadBlocked() else {
            if users.isEmpty { phase = .failed(offline: !SyncCenter.shared.isOnline) }
            return
        }
        users = list
        unblocked = []
        phase = .loaded
    }
}
