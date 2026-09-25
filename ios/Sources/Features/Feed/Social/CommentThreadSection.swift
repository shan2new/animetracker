import SwiftUI

// A thread's replies, as ROWS for a host's LazyVStack (spec §7.2) — not a ScrollView, so the post
// page and the episode discussion scroll as one page and every reply is its own lazy row. The body
// is a flat run of views (no wrapping stack): a lazy stack realises them one by one.
//
// Top to bottom: the sort ("Top ⌄" — a real sort, server-ordered), the episode room's lock when the
// server keeps it shut, your replies still on their way ("Sending", "Not sent · Retry · Discard"),
// the replies, then "Show more replies" while the server has more. Nothing at all while replies are
// off (§4.9).
//
// A notification's reply (`focusCommentId`) is found — the thread opens on Latest, where a new
// reply sits, and walks up to three pages for it — then lit once where it landed, and handed to the
// host by its scroll id (`onFocusLanded`) so the host's ScrollViewReader can bring it on screen.

struct CommentThreadSection: View {
    let subject: String
    let franchiseTitle: String
    var focusCommentId: String? = nil
    let onCompose: (ComposeTarget) -> Void
    /// Added by WP5 (defaulted): the show the thread belongs to, for a reply's compose target.
    /// Derived when nil — the post's show from whatever has it loaded, or the episode's library show.
    var franchiseId: String? = nil
    /// Added by WP5 (defaulted): called once, when the focused reply is in the list, with its scroll
    /// id (`scrollID(_:)`). A host inside a `ScrollViewReader` scrolls to it.
    var onFocusLanded: ((_ scrollID: String) -> Void)? = nil
    /// A link on the sort row's trailing side — X's "Relevant ⌄ … View quotes ›" row (the post
    /// page's "How this story got here ›").
    var trailing: Trailing? = nil

    struct Trailing {
        let title: String
        let action: () -> Void
    }

    /// The sort row's trailing link: interactive ink, a chevron, a 44-pt target.
    struct TrailingLink: View {
        let trailing: Trailing

        var body: some View {
            Button(action: trailing.action) {
                HStack(spacing: ThemeSpace.x1) {
                    Text(trailing.title)
                        .type(ThemeType.feedNoteTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    AppGlyph(systemName: "chevron.right")
                        .font(ThemeType.feedSmall.font.weight(.bold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(ThemeColor.interactive)
                .frame(minHeight: FeedMetrics.actionHitHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(FeedIconPressStyle())
        }
    }

    /// The id every reply row carries (`.id(_:)`), for a host's `ScrollViewProxy.scrollTo`: the
    /// comment id itself, so a host that scrolls to `focusCommentId` directly lands on the row.
    static func scrollID(_ commentId: String) -> String { commentId }
    /// The sort row's id — where "the replies" begin on the page.
    static let headerID = "replies"

    @Environment(AppModel.self) private var appModel

    /// The reply the notification pointed at, once found: lit, once.
    @State private var litId: String?
    @State private var focusSettled = false
    /// The load key the thread was last read for. A lazy stack re-runs a row's `.task` every time
    /// the row scrolls back on screen; without this, scrolling up past the sort row would reset a
    /// thread read three pages deep back to its first page.
    @State private var loadedKey: String?

    private var episode: (mediaId: Int, episode: Int)? { ThreadSubject.parseEpisode(subject) }

    var body: some View {
        if appModel.feedCapabilities.comments {
            let thread = appModel.thread(subject)
            let pending = appModel.pendingComments(for: subject)
            let locked = thread?.locked ?? false

            sortRow(thread)
                .id(Self.headerID)
                .task(id: loadKey) { await firstLoad() }

            if locked, let episode {
                lockRow(thread, episode: episode.episode)
            }

            ForEach(pending) { p in
                PendingCommentRow(pending: p)
            }

            if let thread, !locked {
                if !thread.loadedOnce && thread.loading && thread.items.isEmpty {
                    loadingRow
                } else if thread.failed && thread.items.isEmpty {
                    InlineNotice(Copy.Social.repliesFailed) { reload() }
                        .padding(.horizontal, FeedMetrics.inset)
                        .padding(.vertical, ThemeSpace.x3)
                } else if thread.loadedOnce && thread.items.isEmpty && pending.isEmpty {
                    emptyRow
                }
            } else if thread == nil {
                loadingRow
            }

            if let thread, !locked {
                ForEach(thread.items) { c in
                    CommentRow(comment: c,
                               onReply: { onCompose(replyTarget(to: c)) },
                               focused: c.id == litId)
                        .id(Self.scrollID(c.id))
                }
                footer(thread)
            }
        }
    }

    // MARK: Rows

    private func sortRow(_ thread: CommentThread?) -> some View {
        let sort = thread?.sort ?? initialSort
        return VStack(spacing: 0) {
            HStack {
                Menu {
                    Picker(Copy.Social.sortLabel, selection: Binding(get: { sort }, set: { resort($0) })) {
                        ForEach(CommentSort.allCases, id: \.self) { option in
                            Text(Copy.Social.sortTitle(option)).tag(option)
                        }
                    }
                } label: {
                    HStack(spacing: ThemeSpace.x1) {
                        Text(Copy.Social.sortTitle(sort))
                            .type(ThemeType.feedName)
                        AppGlyph(systemName: "chevron.down")
                            .font(ThemeType.feedSmall.font.weight(.bold))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(ThemeColor.feedText)
                    .frame(minHeight: FeedMetrics.actionHitHeight)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(Copy.Social.sortLabel)
                .accessibilityValue(Copy.Social.sortA11y(sort))
                .disabled(thread?.locked ?? false)
                Spacer(minLength: ThemeSpace.x3)
                if let trailing { TrailingLink(trailing: trailing) }
            }
            .padding(.horizontal, FeedMetrics.inset)
            Rectangle().fill(ThemeColor.feedSeparator).frame(height: FeedMetrics.hairline)
        }
    }

    /// The episode room the server keeps shut (§4.2 step 3): "Saving your progress" while a mark
    /// the client already counts is still reaching the server, else the lock in words.
    private func lockRow(_ thread: CommentThread?, episode n: Int) -> some View {
        Group {
            if thread?.loading == true && thread?.access == .unwatched {
                HStack(spacing: ThemeSpace.x2) {
                    ProgressView().controlSize(.small).tint(ThemeColor.feedSecondary)
                    Text(Copy.Stories.savingProgress)
                        .type(ThemeType.feedSubhead)
                        .foregroundStyle(ThemeColor.feedSecondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x2) {
                    AppGlyph(systemName: "lock.fill")
                        .font(ThemeType.feedSubhead.font)
                        .accessibilityHidden(true)
                    Text(thread?.access == .unaired ? Copy.Stories.lockedUnaired(n) : Copy.Stories.lockedUnwatched(n))
                        .type(ThemeType.feedSubhead)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(ThemeColor.feedSecondary)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, minHeight: FeedMetrics.actionHitHeight, alignment: .leading)
        .padding(.horizontal, FeedMetrics.inset)
        .padding(.vertical, ThemeSpace.x3)
    }

    private var loadingRow: some View {
        ProgressView()
            .tint(ThemeColor.feedSecondary)
            .frame(maxWidth: .infinity, minHeight: FeedMetrics.actionHitHeight * 2)
            .accessibilityLabel(Copy.Accessibility.loading)
    }

    private var emptyRow: some View {
        VStack(spacing: ThemeSpace.x1) {
            Text(Copy.Social.noReplies)
                .type(ThemeType.feedName)
                .foregroundStyle(ThemeColor.feedText)
            Text(Copy.Social.beFirst)
                .type(ThemeType.feedSubhead)
                .foregroundStyle(ThemeColor.feedSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ThemeMetrics.gutter)
        .padding(.vertical, ThemeSpace.x8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func footer(_ thread: CommentThread) -> some View {
        if thread.failed && !thread.items.isEmpty {
            InlineNotice(Copy.Social.repliesFailed) {
                if thread.nextCursor != nil { loadMore() } else { reload() }
            }
                .padding(.horizontal, FeedMetrics.inset)
                .padding(.vertical, ThemeSpace.x2)
        } else if thread.nextCursor != nil {
            Group {
                if thread.loading {
                    ProgressView().tint(ThemeColor.feedSecondary)
                        .accessibilityLabel(Copy.Accessibility.loading)
                } else {
                    Button(Copy.Social.showMoreReplies) { loadMore() }
                        .buttonStyle(InlineLinkButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, minHeight: FeedMetrics.actionHitHeight)
            .padding(.vertical, ThemeSpace.x2)
        }
    }

    // MARK: Loading

    /// A notification's thread opens on Latest (a fresh reply sits at its top); any other, on Top.
    private var initialSort: CommentSort { focusCommentId == nil ? .top : .latest }

    /// The first load runs again when the client's own gate opens (a mark made while the room is
    /// on screen), so the lock gives way without a pull.
    private var loadKey: String {
        guard let episode, let fid = resolvedFranchiseId else { return subject }
        let access = appModel.clientEpisodeAccess(franchiseId: fid, mediaId: episode.mediaId, episode: episode.episode)
        return "\(subject)|\(access.rawValue)"
    }

    private func firstLoad() async {
        let key = loadKey
        guard key != loadedKey else { return }
        let sort = appModel.thread(subject)?.sort ?? initialSort
        await appModel.loadComments(subject, sort: sort, reset: true)
        guard !Task.isCancelled else { return }
        loadedKey = key
        await landFocus()
    }

    /// Finds the focused reply (walking at most `focusPageBudget` more pages), lights it and tells
    /// the host where it is. Once per appearance of the section.
    private func landFocus() async {
        guard let focusCommentId, !focusSettled else { return }
        var pages = 0
        while !(appModel.thread(subject)?.items.contains { $0.id == focusCommentId } ?? false),
              appModel.thread(subject)?.nextCursor != nil,
              pages < SocialMetrics.focusPageBudget,
              !Task.isCancelled {
            await appModel.loadMoreComments(subject)
            pages += 1
        }
        guard !Task.isCancelled,
              appModel.thread(subject)?.items.contains(where: { $0.id == focusCommentId }) == true else { return }
        focusSettled = true
        litId = focusCommentId
        onFocusLanded?(Self.scrollID(focusCommentId))
    }

    private func reload() {
        let sort = appModel.thread(subject)?.sort ?? initialSort
        Task { await appModel.loadComments(subject, sort: sort, reset: true) }
    }

    private func loadMore() {
        Task { await appModel.loadMoreComments(subject) }
    }

    private func resort(_ sort: CommentSort) {
        guard sort != (appModel.thread(subject)?.sort ?? initialSort) else { return }
        litId = nil
        Task { await appModel.loadComments(subject, sort: sort, reset: true) }
    }

    // MARK: Targets

    /// The show this thread belongs to: given by the host, else whatever has the post loaded, else
    /// the library show that owns the episode.
    private var resolvedFranchiseId: String? {
        if let franchiseId { return franchiseId }
        if let episode {
            return appModel.library.first { f in f.parts.contains { $0.mediaId == episode.mediaId } }?.id
        }
        return appModel.franchiseIdOfPost(subject)
    }

    /// A reply to one reply: same subject, the parent named, "Replying to @dex".
    private func replyTarget(to c: SocialComment) -> ComposeTarget {
        ComposeTarget(subject: subject,
                      franchiseId: resolvedFranchiseId ?? "",
                      franchiseTitle: franchiseTitle,
                      parentId: c.id,
                      replyingTo: c.author,
                      episode: episode?.episode)
    }
}
