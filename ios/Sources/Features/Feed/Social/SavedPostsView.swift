import SwiftUI

// Saved (spec §4.10, iD6): the posts you bookmarked, newest save first, reached from Profile's
// Community group and from `FeedRoute.saved`. A saved post looks like itself: it is drawn by the
// feed's own `FeedPostRow` (composed never-fresh by the model).
//
// Unsaving (the row's bookmark, or anywhere else — the list reads the overlay) folds the row in
// place into "Removed from Saved · Undo", the feed's fold anatomy; the list never reflows under the
// finger. A saved post the server can no longer compose is a quiet "no longer available" row that
// can still be removed.

struct SavedPostsView: View {
    let onOpenPost: (String) -> Void
    let onOpenShow: (String) -> Void

    @Environment(AppModel.self) private var appModel

    @State private var entries: [SavedEntry] = []
    @State private var phase: Phase = .loading

    private enum Phase: Equatable { case loading, failed(offline: Bool), loaded }

    var body: some View {
        content
            .background(ThemeColor.canvas.ignoresSafeArea())
            .brandNavigationTitle(Copy.Social.savedTitle)
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if entries.isEmpty {
            switch phase {
            case .loading:
                ProgressView()
                    .tint(ThemeColor.feedSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(Copy.Accessibility.loading)
            case .failed(let offline):
                EmptyState(offline ? .savedOffline : .savedFailed, prominence: .major) {
                    Task { await load() }
                }
                .padding(.horizontal, ThemeMetrics.gutter)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                EmptyState(.savedEmpty, prominence: .major)
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        row(entry)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .refreshable { await load() }
            .laneClearance(appModel, base: ThemeMetrics.tabBarClearance)
        }
    }

    @ViewBuilder
    private func row(_ entry: SavedEntry) -> some View {
        let postId = entry.item.postId
        if !appModel.isSaved(postId) {
            SavedFoldRow {
                appModel.setSaved(true, postId: postId, franchiseId: entry.model?.post.franchiseId)
            }
        } else if let model = entry.model {
            // The feed's own row (WP3), so a saved post looks like itself — its picture, its bar
            // (whose bookmark unsaves it here). Its picture and its reply open the post page, where
            // both live; the show's avatar opens the show.
            FeedPostRow(model: model,
                        onOpen: { onOpenPost(postId) },
                        onOpenShow: { onOpenShow(model.post.franchiseId) },
                        onPlay: { onOpenPost(postId) },
                        onViewMedia: { onOpenPost(postId) },
                        onComment: { onOpenPost(postId) })
                .equatable()
        } else {
            SavedUnavailableRow {
                appModel.setSaved(false, postId: postId, franchiseId: nil)
            }
        }
    }

    private func load() async {
        if entries.isEmpty { phase = .loading }
        guard let saved = await appModel.loadSaved() else {
            // Rows already on screen stay; with none, the failure is the screen.
            if entries.isEmpty { phase = .failed(offline: !SyncCenter.shared.isOnline) }
            return
        }
        entries = saved.items.map { SavedEntry(item: $0.item, model: $0.model) }
        phase = .loaded
    }
}

/// One saved post, composed (`FeedPostModel`) or not (the server no longer has it).
private struct SavedEntry: Identifiable {
    let item: SavedItem
    let model: FeedPostModel?
    var id: String { item.postId }
}

// MARK: - Rows

/// A saved post the server no longer answers for: said quietly, with its one command.
private struct SavedUnavailableRow: View {
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: FeedMetrics.gap) {
                AppGlyph(systemName: "bookmark.slash")
                    .font(ThemeType.feedMeta.font)
                    .foregroundStyle(ThemeColor.feedSecondary)
                    .frame(width: FeedMetrics.avatar, height: FeedMetrics.avatar)
                    .background(ThemeColor.feedCard, in: ShowAvatar.shape(FeedMetrics.avatar))
                    .accessibilityHidden(true)
                Text(Copy.Social.savedUnavailable)
                    .type(ThemeType.feedSubhead)
                    .foregroundStyle(ThemeColor.feedSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(Copy.Social.removeFromSaved, action: onRemove)
                    .buttonStyle(InlineLinkButtonStyle())
            }
            .padding(.horizontal, FeedMetrics.inset)
            .padding(.vertical, ThemeSpace.x3)
            Rectangle().fill(ThemeColor.feedSeparator).frame(height: FeedMetrics.hairline)
        }
    }
}

/// A post taken out of Saved, folded in place with its Undo (the feed's fold anatomy).
private struct SavedFoldRow: View {
    let onUndo: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x2) {
                Text(Copy.Social.removedFromSaved)
                    .type(ThemeType.feedSubhead)
                    .foregroundStyle(ThemeColor.feedSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(Copy.Action.undo, action: onUndo)
                    .buttonStyle(InlineLinkButtonStyle())
            }
            .padding(.leading, ThemeMetrics.gutter)
            .padding(.trailing, FeedMetrics.inset)
            .padding(.vertical, ThemeSpace.x1)
            Rectangle().fill(ThemeColor.feedSeparator).frame(height: FeedMetrics.hairline)
        }
        .transition(.opacity)
    }
}
