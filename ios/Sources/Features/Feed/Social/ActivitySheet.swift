import SwiftUI

// Activity, behind the feed's bell (spec §4.7, brief §11): what your shows did — a date, an
// announcement, a rumour — and what people did with you — a reply to you, a like on your reply.
// Server rows only (`GET /me/notifications`); nothing sampled.
//
// X's notification row on the feed's grid: the kind's glyph right-aligned in the avatar column (a
// reply shows its author's disc there instead), the sentence at 15 with the NAME bold, the time at
// the trailing edge, the quote under it in grey. Unread rows start lit and settle onto the canvas a
// beat after they are seen (the sheet marks everything read when it goes — `onDismiss` in FeedView).
// A tap opens the thread at the reply, the post, or the show (`AppModel.openRoute(for:)`).

struct ActivitySheet: View {
    let onOpen: (OpenRoute) -> Void

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Unread rows are lit until this goes false, a beat after the first rows show.
    @State private var lit = true
    /// The first answer has come back (or failed) since the sheet opened.
    @State private var asked = false

    var body: some View {
        NavigationStack {
            content
                .background(ThemeColor.canvas.ignoresSafeArea())
                .brandNavigationTitle(Copy.Social.activityTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(Copy.Social.done) { dismiss() }
                            .fontWeight(.semibold)
                            .foregroundStyle(ThemeColor.interactive)
                    }
                }
        }
        .tint(ThemeColor.interactive)
        .presentationDragIndicator(.visible)
        .task {
            // FeedView asks too when it opens the sheet; a request already on its way is the answer.
            if !appModel.activityLoading { await appModel.loadActivity(reset: true) }
            asked = true
        }
        .onChange(of: appModel.activityLoading) { was, now in
            if was && !now { asked = true }
        }
        .task(id: appModel.activity.isEmpty) {
            guard !appModel.activity.isEmpty, lit else { return }
            try? await Task.sleep(for: SocialMetrics.unreadHold)
            guard !Task.isCancelled else { return }
            withAnimation(ThemeMotion.pick(ThemeMotion.uiSweep, reduceMotion: reduceMotion)) { lit = false }
        }
    }

    @ViewBuilder
    private var content: some View {
        let items = appModel.activity
        if items.isEmpty {
            if appModel.activityLoading || !asked {
                ProgressView()
                    .tint(ThemeColor.feedSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(Copy.Accessibility.loading)
            } else if appModel.activityFailed {
                EmptyState(SyncCenter.shared.isOnline ? .activityFailed : .activityOffline, prominence: .major) {
                    Task { await appModel.loadActivity(reset: true) }
                }
                .padding(.horizontal, ThemeMetrics.gutter)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyState(.activityEmpty, prominence: .major)
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if appModel.activityFailed {
                        InlineNotice(Copy.Social.activityRefreshFailed) {
                            Task { await appModel.loadActivity(reset: true) }
                        }
                        .padding(.horizontal, FeedMetrics.inset)
                        .padding(.vertical, ThemeSpace.x2)
                    }
                    ForEach(items) { item in
                        // A moderation notice opens nothing (a hidden reply is nobody's to open).
                        ActivityRow(item: item,
                                    lit: lit && item.readAt == nil,
                                    now: appModel.now,
                                    open: item.kind.isModeration ? nil : { onOpen(appModel.openRoute(for: item)) })
                        .equatable()
                    }
                    if appModel.activityCursor != nil {
                        Group {
                            if appModel.activityLoading {
                                ProgressView().tint(ThemeColor.feedSecondary)
                                    .accessibilityLabel(Copy.Accessibility.loading)
                            } else {
                                Button(Copy.Social.activityShowMore) {
                                    Task { await appModel.loadMoreActivity() }
                                }
                                .buttonStyle(InlineLinkButtonStyle())
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: FeedMetrics.actionHitHeight)
                        .padding(.vertical, ThemeSpace.x2)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .refreshable { await appModel.loadActivity(reset: true) }
        }
    }
}

/// One notification. Equatable on what it shows: a page landing, the lit fade or a minute tick
/// rebuilds only the rows it changes.
private struct ActivityRow: View, @MainActor Equatable {
    let item: NotificationItem
    let lit: Bool
    let now: Int64
    /// Nil for a row that opens nothing (a moderation notice): drawn as plain text, not a button.
    let open: (() -> Void)?

    static func == (a: Self, b: Self) -> Bool {
        a.item == b.item && a.lit == b.lit && a.now == b.now && (a.open == nil) == (b.open == nil)
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    private var stamp: String { TemporalCopy.feedStamp(item.createdAt, dateOnly: false, now: now) }

    var body: some View {
        if let open {
            Button(action: open) { rowContent }
                .buttonStyle(FeedRowPressStyle())
                .accessibilityElement(children: .combine)
                .accessibilityValue(item.readAt == nil ? Copy.Social.unread : "")
        } else {
            rowContent
                .accessibilityElement(children: .combine)
                .accessibilityValue(item.readAt == nil ? Copy.Social.unread : "")
        }
    }

    private var rowContent: some View {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: FeedMetrics.gap) {
                    leading
                        .frame(width: FeedMetrics.avatar, alignment: .trailing)
                    VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                        if item.kind == .likeComment, let actor = item.actor {
                            PersonDisc(user: actor, size: SocialMetrics.activityDisc)
                        }
                        headline
                        if let detail {
                            // Whole, as X's notifications quote a reply: the server already sends
                            // the reply's excerpt, and three lines cut its last words again.
                            // In SF, as a reply's or a post's words are — but a moderation row's
                            // line is the app speaking, in Outfit.
                            Text(detail)
                                .type(item.kind.isModeration ? ThemeType.feedSubhead : ThemeType.feedNote)
                                .foregroundStyle(item.kind.isSocial || item.kind.isModeration
                                                 ? ThemeColor.feedSecondary : ThemeColor.feedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, FeedMetrics.inset)
                .padding(.trailing, ThemeMetrics.gutter)
                .padding(.vertical, ThemeSpace.x3)
                .background(ThemeColor.accentSoft.opacity(lit ? SocialMetrics.unreadLitStrength : 0))
                Rectangle().fill(ThemeColor.feedSeparator).frame(height: FeedMetrics.hairline)
            }
            .contentShape(Rectangle())
    }

    /// The avatar column: a reply's author, else the kind's glyph (a like's heart in the like's
    /// rose; news in the quiet grey — amber is rationed to meaning and state, and a bell on every
    /// news row is neither: the row's unread ground already says what is new).
    @ViewBuilder
    private var leading: some View {
        switch item.kind {
        case .reply:
            if let actor = item.actor {
                PersonDisc(user: actor, size: FeedMetrics.avatar)
            } else {
                glyph("bubble.left.fill", ink: ThemeColor.feedSecondary)
            }
        case .likeComment:
            glyph("heart.fill", ink: ThemeColor.like)
        case .newsDated, .newsAnnounced, .newsRumored:
            glyph("bell.fill", ink: ThemeColor.feedSecondary)
        case .commentHidden:
            glyph("eye.slash.fill", ink: ThemeColor.feedSecondary)
        case .reportResolved:
            glyph("flag.fill", ink: ThemeColor.feedSecondary)
        case .unknown:
            glyph("bell", ink: ThemeColor.feedSecondary)
        }
    }

    private func glyph(_ name: String, ink: Color) -> some View {
        AppGlyph(systemName: name)
            .font(ThemeType.feedModuleTitle.font)
            .foregroundStyle(ink)
            .accessibilityHidden(true)
    }

    /// The sentence, the name in bold, and the time at the trailing edge.
    private var headline: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ThemeSpace.x1))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: ThemeSpace.x2))
        return layout {
            Text(sentence)
                .type(ThemeType.feedSubhead)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(stamp)
                .type(ThemeType.feedSmall)
                .foregroundStyle(ThemeColor.feedSecondary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var sentence: AttributedString {
        switch item.kind {
        case .reply:
            if let actor = item.actor {
                let name = Self.name(actor)
                return SocialInk.emphasising(name, in: Copy.Social.activityReply(name: name, show: item.title),
                                             base: ThemeColor.feedText, emphasis: ThemeColor.feedText, bold: true)
            }
            // No public profile behind the reply (its name was reset): worded without one.
            return Self.plain(Copy.Social.activityReplyAnonymous(show: item.title))
        case .likeComment:
            if let actor = item.actor {
                let name = Self.name(actor)
                return SocialInk.emphasising(name, in: Copy.Social.activityLike(name: name, others: item.actorCount - 1),
                                             base: ThemeColor.feedText, emphasis: ThemeColor.feedText, bold: true)
            }
            // Liking needs no handle, so the newest liker often has no public profile: the server
            // sends the row nameless by design, and the heart glyph stands in for the disc.
            return Self.plain(Copy.Social.activityLikeAnonymous(item.actorCount))
        case .commentHidden:
            // `body` is a machine category (server §5.2), worded here — never printed.
            return AttributedString(Copy.Social.activityHidden(reason: item.body, show: item.title))
        case .reportResolved:
            return AttributedString(Copy.Social.activityReportResolved(outcome: item.body, show: item.title))
        case .newsDated, .newsAnnounced, .newsRumored, .unknown:
            break
        }
        // News (and anything this build does not know): the show, bold, as the account.
        return SocialInk.emphasising(item.title, in: item.title,
                                     base: ThemeColor.feedText, emphasis: ThemeColor.feedText, bold: true)
    }

    /// The quote under a social row; the news in the feed's own words under a news row (from
    /// `news`, the server's English `body` only when `news` is nil); where to write under a
    /// moderation notice.
    private var detail: String? {
        if item.kind.isSocial {
            guard let excerpt = item.excerpt, !excerpt.isEmpty else { return nil }
            return excerpt
        }
        if item.kind.isModeration {
            return AppConfig.supportEmail.map { Copy.Social.activitySupport($0) }
        }
        if let news = item.news { return news.sentence(now: now) }
        return item.body.isEmpty ? nil : item.body
    }

    private static func name(_ user: PublicUser) -> String {
        user.displayName.isEmpty ? Copy.Social.handle(user.handle) : user.displayName
    }

    /// A sentence with no name to set bold, in the rows' text ink.
    private static func plain(_ text: String) -> AttributedString {
        var out = AttributedString(text)
        out.foregroundColor = ThemeColor.feedText
        return out
    }
}

private extension NotificationKind {
    /// A person did something (a reply, a like) — as opposed to a show's news.
    var isSocial: Bool { self == .reply || self == .likeComment }
    /// A moderation decision told to its author or its reporter: it opens nothing.
    var isModeration: Bool { self == .commentHidden || self == .reportResolved }
}

private extension NotificationNews {
    /// The row in the feed's headline grammar (dated / window / announced / rumour), the time text
    /// the client's own, from `releaseWindow` — never from `release` or `body` (server §5.2). A
    /// day-precise window is a date, read in its own UTC day; a window with no printable words
    /// (`release` "" and not day-precise) is worded as announced.
    func sentence(now: Int64) -> String {
        let kind: FeedPostKind
        let headline: String
        switch status {
        case "rumored":
            kind = .rumour
            headline = Copy.Feed.headlineRumour(name: installment)
        case "announced_no_date":
            kind = .announced
            headline = Copy.Feed.headlineAnnounced(name: installment, isMovie: isMovie)
        default:
            if releaseWindow.precision == .day, let p = releaseWindow.parts,
               let day = Formatting.utcTimestamp(y: p.year, mo: p.month, d: p.day) {
                let at = day + 12 * Formatting.H          // a date-only fact, carried at 12:00 UTC
                let when = TemporalCopy.premiereWhen(at, anchor: .utcDate, now: now)
                kind = .dated
                headline = TemporalCopy.premiereHasPassed(at, anchor: .utcDate, now: now)
                    ? Copy.Feed.headlinePremiered(name: installment, isMovie: isMovie, when: when)
                    : Copy.Feed.headlineDated(name: installment, isMovie: isMovie, when: when)
            } else {
                let phrase = release.isEmpty ? "" : Copy.Feed.windowPhrase(release: release, window: releaseWindow)
                kind = phrase.isEmpty ? .announced : .window
                headline = Copy.Feed.headlineWindow(name: installment, isMovie: isMovie, phrase: phrase)
            }
        }
        return Copy.Feed.sentence(kind: kind, headline: headline, name: installment, isMovie: isMovie,
                                  premiereLine: nil)
    }
}
