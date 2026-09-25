import SwiftUI
import UIKit

// One reply, in X's feed anatomy (spec §4.6): the person's disc, "Name @handle · 2h  ···", a
// "Replying to @mira.k" line when it answers someone, the words, and the small bar (reply, like).
// The spike's dead bookmark/share icons are gone: a reply is not a post. The `···` menu carries
// the UGC controls App Review asks for (1.2): report and block on someone else's reply, delete on
// your own — each through its confirmation.
//
// Also here: the social layer's metrics and the pending row a reply wears until the server has it.

// MARK: - Metrics

/// The social surfaces' own measures, named once (the rest come from `FeedMetrics`).
enum SocialMetrics {
    /// The composer's character ring at rest, and once `ringNearLeft` characters are left (X's).
    static let ringSize: CGFloat = 22
    static let ringSizeNear: CGFloat = 30
    static let ringLine: CGFloat = 2
    static let ringNearLeft = 20
    /// Activity: the actor's disc beside the kind glyph.
    static let activityDisc: CGFloat = 32
    /// A report's optional note, in code points (server `ReportBody.note`).
    static let reportNoteLimit = 500
    /// Identity bounds (server §4.3): a display name's code points, a handle's length.
    static let nameLimit = 40
    static let handleMin = 3
    static let handleMax = 20
    /// The username field asks the server this long after the last keystroke.
    static let handleCheckDelay: Duration = .milliseconds(300)
    /// How long the composer waits on a send before handing off to the thread's pending row (iD5).
    static let sendPatience: Duration = .milliseconds(1500)
    /// A reply a notification pointed at holds its light this long, then fades.
    static let focusHold: Duration = .milliseconds(900)
    /// Activity's unread rows stay lit this long after the sheet first shows them.
    static let unreadHold: Duration = .milliseconds(1400)
    /// Pages walked to find a notification's reply before the thread stops looking.
    static let focusPageBudget = 3
    /// An unread Activity row's ground: `accentSoft` at this strength (amber as STATE, unread).
    static let unreadLitStrength: Double = 0.5
    /// A pending reply's words while they are on their way.
    static let sendingInkOpacity: Double = 0.6
}

// MARK: - Ink

enum SocialInk {
    /// `sentence` in `base`, with `part` (a name, a show) picked out in `emphasis` and, when
    /// `bold`, strong weight. Copy composes the whole sentence; this only finds the part again, so
    /// the words stay Copy's and the emphasis stays the view's.
    static func emphasising(_ part: String, in sentence: String, base: Color, emphasis: Color,
                            bold: Bool) -> AttributedString {
        var out = AttributedString(sentence)
        out.foregroundColor = base
        guard !part.isEmpty, let range = out.range(of: part) else { return out }
        out[range].foregroundColor = emphasis
        if bold { out[range].inlinePresentationIntent = .stronglyEmphasized }
        return out
    }
}

// MARK: - A reply

struct CommentRow: View {
    let comment: SocialComment
    /// Nil when replies are off (§4.9): the reply item is not drawn.
    let onReply: (() -> Void)?
    /// A notification's reply: lit once where it landed, then settling (X's).
    var focused = false

    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .footnote) private var glyph: CGFloat = FeedMetrics.actionGlyph

    @State private var lit = false
    /// A row scrolled back on screen re-runs its `.task`; the light plays once.
    @State private var litOnce = false
    @State private var confirmDelete = false
    @State private var confirmBlock = false
    @State private var reporting = false

    private var glyphSize: CGFloat { min(glyph, FeedMetrics.actionGlyph * FeedMetrics.actionGlyphMaxScale) }
    private var stamp: String { TemporalCopy.feedStamp(comment.createdAt, dateOnly: false, now: appModel.now) }
    private var name: String { comment.author.displayName.isEmpty ? Copy.Social.handle(comment.author.handle) : comment.author.displayName }
    private var handleLine: String { Copy.Social.line([Copy.Social.handle(comment.author.handle), stamp]) }

    var body: some View {
        let liked = appModel.isCommentLiked(comment)
        let likes = appModel.commentLikeCount(comment)
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: FeedMetrics.gap) {
                PersonDisc(user: comment.author, size: FeedMetrics.avatar)
                VStack(alignment: .leading, spacing: ThemeSpace.x0_5) {
                    HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x1) {
                        words
                        Spacer(minLength: ThemeSpace.x1)
                        menu
                    }
                    actions(liked: liked, likes: likes)
                }
            }
            .padding(.horizontal, FeedMetrics.inset)
            .padding(.top, FeedMetrics.rowTop)
            .padding(.bottom, FeedMetrics.rowBottom)
            .background(ThemeColor.accentSoft.opacity(lit ? 1 : 0))
            Rectangle().fill(ThemeColor.feedSeparator).frame(height: FeedMetrics.hairline)
        }
        .task(id: focused) { await light() }
        .alert(Copy.Social.deleteTitle, isPresented: $confirmDelete) {
            Button(Copy.Social.deleteConfirm, role: .destructive) { delete() }
            Button(Copy.Confirm.cancel, role: .cancel) {}
        } message: {
            Text(Copy.Social.deleteMessage)
        }
        .alert(Copy.Social.blockTitle(comment.author.handle), isPresented: $confirmBlock) {
            Button(Copy.Social.blockConfirm, role: .destructive) { block() }
            Button(Copy.Confirm.cancel, role: .cancel) {}
        } message: {
            Text(Copy.Social.blockMessage)
        }
        .sheet(isPresented: $reporting) {
            ReportSheet(comment: comment)
        }
    }

    // MARK: Words

    /// Name, handle and stamp, the "Replying to" line and the body: ONE VoiceOver element, with
    /// the row's commands as its actions (the buttons stay reachable by swiping too).
    private var words: some View {
        VStack(alignment: .leading, spacing: ThemeSpace.x0_5) {
            identityLine
            if let to = comment.replyTo {
                Text(SocialInk.emphasising(Copy.Social.handle(to.handle),
                                           in: Copy.Social.replyingToLine(to.handle),
                                           base: ThemeColor.feedSecondary, emphasis: ThemeColor.feedText,
                                           bold: false))
                    .type(ThemeType.feedNote)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            }
            Text(comment.body)
                .type(ThemeType.feedBody)
                .foregroundStyle(ThemeColor.feedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityActions { accessibilityCommands }
    }

    @ViewBuilder
    private var identityLine: some View {
        if typeSize.isAccessibilitySize {
            // Two lines at the accessibility sizes: a name is never cut to fit its handle.
            VStack(alignment: .leading, spacing: 0) {
                Text(name).type(ThemeType.feedName).foregroundStyle(ThemeColor.feedText)
                Text(handleLine).type(ThemeType.feedMeta).foregroundStyle(ThemeColor.feedSecondary)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x1) {
                Text(name)
                    .type(ThemeType.feedName)
                    .foregroundStyle(ThemeColor.feedText)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(handleLine)
                    .type(ThemeType.feedMeta)
                    .foregroundStyle(ThemeColor.feedSecondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: The bar

    private func actions(liked: Bool, likes: Int) -> some View {
        HStack(spacing: 0) {
            if let onReply {
                Button(action: onReply) {
                    HStack(spacing: ThemeSpace.x1) {
                        Image(systemName: "bubble.left")
                            .font(ThemeType.feedBody.font)
                            .imageScale(.medium)
                        if comment.replyCount > 0 {
                            Text(FeedCount.text(comment.replyCount)).type(ThemeType.feedCount)
                        }
                    }
                    .foregroundStyle(ThemeColor.feedSecondary)
                    .frame(minWidth: FeedMetrics.actionSlot, minHeight: FeedMetrics.actionHitHeight, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(FeedIconPressStyle())
                .accessibilityLabel(Copy.Social.replyTo(comment.author.handle))
                .accessibilityValue(comment.replyCount > 0 ? Copy.Social.repliesCount(comment.replyCount) : "")
            }
            Button { appModel.toggleCommentLike(comment) } label: {
                HStack(spacing: ThemeSpace.x1) {
                    LikeGlyph(liked: liked, size: glyphSize)
                    if likes > 0 {
                        Text(FeedCount.text(likes))
                            .type(ThemeType.feedCount)
                            .foregroundStyle(liked ? ThemeColor.like : ThemeColor.feedSecondary)
                            .contentTransition(reduceMotion ? ContentTransition.opacity : .numericText(value: Double(likes)))
                    }
                }
                .frame(minWidth: FeedMetrics.actionSlot, minHeight: FeedMetrics.actionHitHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(FeedIconPressStyle())
            .accessibilityLabel(liked ? Copy.Feed.unlike : Copy.Feed.like)
            .accessibilityValue(Copy.Feed.likes(likes))
            Spacer(minLength: 0)
        }
        // The bar stays one row at the accessibility sizes (glyphs cap at 1.6×).
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.top, -ThemeSpace.x1)
    }

    // MARK: The menu

    private var menu: some View {
        Menu {
            Button {
                UIPasteboard.general.string = comment.body
            } label: {
                Label(Copy.Feed.copyText, systemImage: "doc.on.doc")
            }
            if comment.mine {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label(Copy.Social.deleteCommand, systemImage: "trash")
                }
            } else {
                Button { reporting = true } label: {
                    Label(Copy.Social.reportCommand, systemImage: "flag")
                }
                Button(role: .destructive) { confirmBlock = true } label: {
                    Label(Copy.Social.blockCommand(comment.author.handle), systemImage: "hand.raised")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(ThemeType.feedNote.font)
                .foregroundStyle(ThemeColor.feedSecondary)
                .frame(width: FeedMetrics.actionHitHeight, height: FeedMetrics.actionHitHeight)
                .contentShape(Rectangle())
        }
        // The target is 44 × 44; pulled back so the name line keeps its own height.
        .padding(.vertical, -ThemeSpace.x3)
        .padding(.trailing, -ThemeSpace.x3)
        .accessibilityLabel(Copy.Feed.more)
    }

    @ViewBuilder
    private var accessibilityCommands: some View {
        Button(appModel.isCommentLiked(comment) ? Copy.Feed.unlike : Copy.Feed.like) {
            appModel.toggleCommentLike(comment)
        }
        if let onReply {
            Button(Copy.Social.replyTo(comment.author.handle), action: onReply)
        }
        Button(Copy.Feed.copyText) { UIPasteboard.general.string = comment.body }
        if comment.mine {
            Button(Copy.Social.deleteCommand) { confirmDelete = true }
        } else {
            Button(Copy.Social.reportCommand) { reporting = true }
            Button(Copy.Social.blockCommand(comment.author.handle)) { confirmBlock = true }
        }
    }

    // MARK: Writes

    private func delete() {
        let comment = comment
        Task {
            // The model removes it, signs the deletion and says so; a refusal is said here.
            if !(await appModel.deleteComment(comment)) {
                appModel.showNotice(Copy.Social.deleteFailed)
            }
        }
    }

    private func block() {
        let author = comment.author
        Task { _ = await appModel.block(author) }
    }

    /// The focused reply lights at once, holds, then settles onto the canvas.
    private func light() async {
        guard focused, !litOnce else { return }
        litOnce = true
        lit = true
        try? await Task.sleep(for: SocialMetrics.focusHold)
        // Scrolled away mid-hold: the light still settles, without an animation nobody sees.
        guard !Task.isCancelled else { lit = false; return }
        withAnimation(ThemeMotion.pick(ThemeMotion.uiSweep, reduceMotion: reduceMotion)) { lit = false }
    }
}

// MARK: - A reply on its way

/// The viewer's reply before the server has it: drawn at the top of its thread with its state —
/// "Sending", or "Not sent" with Retry and Discard (the SyncBanner carries the same retry), or the
/// rate limit's sentence.
struct PendingCommentRow: View {
    let pending: PendingComment

    @Environment(AppModel.self) private var appModel
    @Environment(AuthManager.self) private var auth
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let profile = appModel.socialProfile
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: FeedMetrics.gap) {
                if let profile {
                    PersonDisc(monogram: profile.displayName ?? profile.handle, userId: profile.userId,
                               size: FeedMetrics.avatar)
                } else {
                    AccountDisc(identity: auth.identity, diameter: FeedMetrics.avatar, quiet: true)
                }
                VStack(alignment: .leading, spacing: ThemeSpace.x0_5) {
                    VStack(alignment: .leading, spacing: ThemeSpace.x0_5) {
                        if let profile, let shown = profile.displayName ?? profile.handle {
                            HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x1) {
                                Text(shown)
                                    .type(ThemeType.feedName)
                                    .foregroundStyle(ThemeColor.feedText)
                                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                                if let handle = profile.handle, !typeSize.isAccessibilitySize {
                                    Text(Copy.Social.handle(handle))
                                        .type(ThemeType.feedMeta)
                                        .foregroundStyle(ThemeColor.feedSecondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        if let to = pending.replyingTo {
                            Text(SocialInk.emphasising(Copy.Social.handle(to.handle),
                                                       in: Copy.Social.replyingToLine(to.handle),
                                                       base: ThemeColor.feedSecondary,
                                                       emphasis: ThemeColor.feedText, bold: false))
                                .type(ThemeType.feedNote)
                        }
                        Text(pending.body)
                            .type(ThemeType.feedBody)
                            .foregroundStyle(ThemeColor.feedText)
                            .opacity(pending.state == .sending ? SocialMetrics.sendingInkOpacity : 1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    status
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, FeedMetrics.inset)
            .padding(.top, FeedMetrics.rowTop)
            .padding(.bottom, FeedMetrics.rowBottom)
            Rectangle().fill(ThemeColor.feedSeparator).frame(height: FeedMetrics.hairline)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var status: some View {
        switch pending.state {
        case .sending:
            HStack(spacing: ThemeSpace.x2) {
                ProgressView().controlSize(.mini).tint(ThemeColor.feedSecondary)
                Text(Copy.Social.sending)
                    .type(ThemeType.feedSmall)
                    .foregroundStyle(ThemeColor.feedSecondary)
            }
            .frame(minHeight: FeedMetrics.actionHitHeight, alignment: .leading)
            .accessibilityElement(children: .combine)
        case .failed:
            failureLine(Copy.Social.notSent, discardable: true)
        case .rateLimited:
            failureLine(Copy.Social.rateLimited, discardable: true)
        }
    }

    private func failureLine(_ message: String, discardable: Bool) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 0))
        return layout {
            Text(message)
                .type(ThemeType.feedSmall)
                .foregroundStyle(ThemeColor.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, ThemeSpace.x1)
            HStack(spacing: 0) {
                Button(Copy.Action.retry) {
                    let id = pending.id
                    Task { _ = await appModel.retryComment(id: id) }
                }
                .buttonStyle(InlineLinkButtonStyle())
                if discardable {
                    Button(Copy.Social.discard) { appModel.discardComment(id: pending.id) }
                        .buttonStyle(InlineLinkButtonStyle())
                }
            }
        }
    }
}
