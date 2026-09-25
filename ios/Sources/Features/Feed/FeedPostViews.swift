import SwiftUI
import UIKit

// The post, on X's measured anatomy (round 3, 393 pt; round 4 polish):
//   · ONE metadata line — the show as the account, its installment in the handle's slot, the time,
//     in grey. Nothing else competes with it.
//   · ONE plain sentence of content at reading weight. No bold headline over a grey paragraph.
//   · The media is the picture and nothing more: no pill, no tag, no date printed on the art.
//   · A row of quiet outline icons.
//   · No colour in the post except STATE: a like is pink, a reminder you set rings the bell amber,
//     and the gold check says the news came from the studio or network itself (brief §13).
//
// The whole post is one press (X lifts the row's ground while the finger is down); the avatar and
// the name open the show, as an account's do; the picture opens the viewer — or, tapped twice,
// likes the post with Instagram's heart. Every post carries its menu on a long press (iD20).

/// X's measured spacings inside a post, in one place.
enum FeedPostLayout {
    /// Name line → sentence.
    static let sentenceTop: CGFloat = 1
    /// Sentence → media (or the rumour's note).
    static let mediaTop: CGFloat = 10
    /// Media → action bar.
    static let barTop: CGFloat = 2
    /// Inside the name line.
    static let nameSpacing: CGFloat = 4
    /// The sentence's leading.
    static let lineSpacing: CGFloat = 1.5
    /// The `···` sits 6 pt into the row's trailing inset, as X's does.
    static let menuTrailingPull: CGFloat = 6
    /// The For you "Add" capsule: 30 pt tall, 14 pt of side padding (X's follow pill).
    static let addHeight: CGFloat = 30
    static let addPadding: CGFloat = 14
    /// The double-tap heart over a picture.
    static let bigHeart: CGFloat = 78
    /// The rumour note: its title's glyph → words, and its lines' leading.
    static let noteGlyphGap: CGFloat = 6
    static let noteLineSpacing: CGFloat = 1
}

// MARK: - The row

/// One post in a list. `Equatable` on what it shows (the model and the tab), applied with
/// `.equatable()`, so a minute tick, a like elsewhere or the list re-composing does not rebuild a
/// row whose post did not change. The action bar inside reads the social overlay itself, so a like
/// re-evaluates one bar.
struct FeedPostRow: View, @MainActor Equatable {
    let model: FeedPostModel
    /// For you's posts are about shows you do not track: the name line offers Add instead of `···`.
    var tab: FeedTab = .following
    /// The feed's zoom namespace: the picture viewer and the trailer's stage grow out of the post.
    var zoom: Namespace.ID? = nil
    let onOpen: () -> Void
    let onOpenShow: () -> Void
    let onPlay: () -> Void
    let onViewMedia: () -> Void
    let onComment: () -> Void
    /// The first post's picture is on screen (the launch hands off on it).
    var onMediaLoaded: (() -> Void)? = nil

    static func == (a: Self, b: Self) -> Bool {
        a.model == b.model && a.tab == b.tab && a.zoom == b.zoom
    }

    var body: some View {
        Button(action: onOpen) { content }
            .buttonStyle(FeedRowPressStyle())
            .contextMenu { PostMenuItems(model: model, onOpenShow: onOpenShow) }
            .accessibilityElement(children: .contain)
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: FeedMetrics.gap) {
                Button(action: onOpenShow) {
                    ShowAvatar(franchise: model.franchise)
                }
                .buttonStyle(OverArtPressStyle())
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    textColumn
                    switch model.media {
                    case .none:
                        RumourNote(model: model)
                            .padding(.top, FeedPostLayout.mediaTop)
                    case .art, .trailer:
                        PostMediaButton(model: model, zoom: zoom, onPlay: onPlay, onViewMedia: onViewMedia,
                                        onLoaded: onMediaLoaded)
                            .padding(.top, FeedPostLayout.mediaTop)
                    }
                    PostActionBar(model: model, onComment: onComment)
                        .padding(.top, FeedPostLayout.barTop)
                    ReminderPrimerSlot(model: model)
                }
            }
            .padding(.horizontal, FeedMetrics.inset)
            .padding(.top, FeedMetrics.rowTop)
            .padding(.bottom, FeedMetrics.rowBottom)
            FeedHairline()
        }
        .contentShape(Rectangle())
        .onAppear {
            // A post with no picture is ready the moment it is drawn (its avatar is a 44-pt crop).
            if case .none = model.media { onMediaLoaded?() }
        }
    }

    /// The name line and the sentence: ONE VoiceOver element, labelled with the post's composed
    /// sentence, carrying the row's actions (the buttons below stay reachable by swiping too).
    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            PostNameLine(model: model, suggested: tab == .forYou, onOpenShow: onOpenShow)
            Text(model.sentence)
                .type(ThemeType.feedBody)
                .foregroundStyle(ThemeColor.feedText)
                .multilineTextAlignment(.leading)
                .lineSpacing(FeedPostLayout.lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, FeedPostLayout.sentenceTop)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { onOpen() }
        .modifier(PostAccessibilityActions(model: model, suggested: tab == .forYou,
                                           onComment: onComment, onOpenShow: onOpenShow))
    }
}

/// The row's named VoiceOver actions (spec §5.5): Like/Unlike, Save, Remind me, Reply (comments
/// on), Share, Go to <show>, Not interested — and Add on a For you post.
private struct PostAccessibilityActions: ViewModifier {
    let model: FeedPostModel
    let suggested: Bool
    let onComment: () -> Void
    let onOpenShow: () -> Void

    @Environment(AppModel.self) private var appModel

    func body(content: Content) -> some View {
        let id = model.id
        content
            .accessibilityAction(named: appModel.isLiked(id) ? Copy.Feed.unlike : Copy.Feed.like) {
                appModel.toggleLike(id, franchiseId: model.post.franchiseId)
            }
            .accessibilityAction(named: appModel.isSaved(id) ? Copy.Feed.unsave : Copy.Feed.save) {
                appModel.toggleSave(model)
            }
            .accessibilityAction(named: appModel.isReminded(id) ? Copy.Feed.reminderOn : Copy.Feed.remindMe) {
                appModel.toggleRemind(model)
            }
            .modifier(OptionalAction(name: Copy.Feed.replies(appModel.commentCount(id)),
                                     enabled: appModel.feedCapabilities.comments, action: onComment))
            .accessibilityAction(named: Copy.Feed.share) {
                SystemShare.present(model.shareURL.map { [$0 as Any, model.shareText as Any] } ?? [model.shareText as Any])
            }
            .modifier(OptionalAction(name: Copy.Search.add,
                                     enabled: suggested && !appModel.isInLibrary(model.post.franchiseId)) {
                addFromFeed(model, appModel: appModel, onOpenShow: onOpenShow)
            })
            .accessibilityAction(named: Copy.Feed.goTo(model.showName), onOpenShow)
            .accessibilityAction(named: Copy.Feed.notInterested) { appModel.hidePost(model) }
    }
}

/// For you's Add (the capsule and its VoiceOver action). An AIRING show asks where you are before
/// it is added — Discover's rule (`DiscoverView.add`): its page raises "Where are you?" from
/// `pendingAddPrompt`. Added straight to Watching at zero, a trending airing show arrived in the
/// story tray as "N new episodes" and on Schedule as a backlog. A finished run is added here.
@MainActor
func addFromFeed(_ model: FeedPostModel, appModel: AppModel, onOpenShow: () -> Void) {
    let id = model.post.franchiseId
    if model.show.isReleasing {
        appModel.pendingAddPrompt = id
        onOpenShow()
    } else {
        appModel.addToLibrary(franchiseId: id, title: model.show.title, isReleasing: false)
    }
}

/// A named accessibility action that exists only when it can do something — conditional inside
/// the actions builder, so the element keeps its identity when the condition flips.
private struct OptionalAction: ViewModifier {
    let name: String
    let enabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content.accessibilityActions {
            if enabled { Button(name, action: action) }
        }
    }
}

/// The feed's rule between rows: X's separator grey, a hairline.
struct FeedHairline: View {
    var body: some View {
        Rectangle().fill(ThemeColor.feedSeparator).frame(height: FeedMetrics.hairline)
    }
}

// MARK: - The name line

/// "Black Clover ✓ Season 2 · 2h  ···" — X's line: the account in bold, its mark, the grey slot X
/// uses for the handle (here the installment), the time, the overflow. With room: all of it.
/// Without: the installment goes first, whole — X drops the handle before it cuts anything, and
/// never the time. At the accessibility sizes it is two lines: the name, then installment · time.
struct PostNameLine: View {
    let model: FeedPostModel
    /// A For you post: a trailing Add capsule instead of the `···` menu (iD20 — the menu stays on
    /// the long press).
    let suggested: Bool
    let onOpenShow: () -> Void

    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: FeedPostLayout.nameSpacing) {
            Button(action: onOpenShow) {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: FeedPostLayout.nameSpacing) {
                            name
                            mark
                        }
                        Text(Copy.Feed.separated([model.post.installment, model.stamp]))
                            .type(ThemeType.feedMeta)
                            .foregroundStyle(ThemeColor.feedSecondary)
                    }
                    .contentShape(Rectangle())
                } else {
                    ViewThatFits(in: .horizontal) {
                        line(installment: true)
                        line(installment: false)
                    }
                }
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            Spacer(minLength: FeedPostLayout.nameSpacing)
            if suggested {
                ShowAddCapsule(model: model, onOpenShow: onOpenShow)
            } else {
                // Hosted: in a list that installs `postMenuHost` the `···` is a plain button and
                // the list presents the one menu.
                PostMenuButton(model: model, onOpenShow: onOpenShow, hosted: true)
                    .padding(.trailing, -FeedPostLayout.menuTrailingPull)
            }
        }
    }

    private var name: some View {
        Text(model.showName)
            .type(ThemeType.feedName)
            .foregroundStyle(ThemeColor.feedText)
            .lineLimit(1)
    }

    @ViewBuilder private var mark: some View {
        if model.showsOfficialMark { ConfirmedMark() }
    }

    private func line(installment: Bool) -> some View {
        HStack(alignment: .center, spacing: FeedPostLayout.nameSpacing) {
            name.layoutPriority(2)
            mark
            if installment, !model.post.installment.isEmpty {
                Text(model.post.installment)
                    .type(ThemeType.feedMeta)
                    .foregroundStyle(ThemeColor.feedSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Text(Copy.Feed.afterDot(model.stamp))
                .type(ThemeType.feedMeta)
                .foregroundStyle(ThemeColor.feedSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .contentShape(Rectangle())
    }
}

/// X's follow pill, for a show: ink on white until it is yours, then an outline. The add is the
/// library's own (`addToLibrary`, which signs it with its haptic and its lane receipt) — or, for an
/// airing show, the show's page asking where you are first (`addFromFeed`). On a For you post's
/// name line and on the post page's author row.
struct ShowAddCapsule: View {
    let model: FeedPostModel
    let onOpenShow: () -> Void

    @Environment(AppModel.self) private var appModel

    var body: some View {
        let owned = appModel.isInLibrary(model.post.franchiseId)
        Button {
            addFromFeed(model, appModel: appModel, onOpenShow: onOpenShow)
        } label: {
            Text(owned ? Copy.Search.added : Copy.Search.add)
                .type(ThemeType.feedSmall)
                .fontWeight(.bold)
                .foregroundStyle(owned ? ThemeColor.feedText : ThemeColor.onAccent)
                .contentTransition(.interpolate)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, FeedPostLayout.addPadding)
                .frame(minHeight: FeedPostLayout.addHeight)
                .background(owned ? Color.clear : ThemeColor.feedText, in: Capsule())
                .overlay(Capsule().strokeBorder(owned ? ThemeColor.feedSeparator : .clear, lineWidth: FeedMetrics.hairline))
                .frame(minHeight: FeedMetrics.actionHitHeight)
                .contentShape(Rectangle())
                .padding(.vertical, -(FeedMetrics.actionHitHeight - FeedPostLayout.addHeight) / 2)
        }
        .buttonStyle(FeedIconPressStyle())
        .disabled(owned)
        .accessibilityHint(owned ? "" : Copy.Feed.addHint)
        .fixedSize()
        .layoutPriority(3)
        .animation(ThemeMotion.uiMicro, value: owned)
    }
}

// MARK: - The menu

/// The post's `···`: X's menu for a news account in a 44×44 target that does not grow the line.
struct PostMenuButton: View {
    let model: FeedPostModel
    let onOpenShow: () -> Void
    /// Over a picture (the media viewer): white instead of X's grey.
    var tint: Color = ThemeColor.feedSecondary
    /// In a text line (the name line): the 44-pt target does not make the line 44 tall. Off where
    /// the button stands alone (the media viewer's corner).
    var insideLine = true
    /// A row of a list: when the list installs `postMenuHost`, a plain button that names the post
    /// to the list's one menu instead of a `Menu` of its own. A page's single `···` (the post
    /// page, the media viewer) keeps its own `Menu`.
    var hosted = false

    @Environment(\.postMenuRequest) private var request

    var body: some View {
        Group {
            if hosted, let request {
                Button { request.target = model } label: { glyph }
                    .buttonStyle(FeedIconPressStyle())
            } else {
                Menu {
                    PostMenuItems(model: model, onOpenShow: onOpenShow)
                } label: {
                    glyph
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, insideLine ? -ThemeSpace.x3 : 0)
        .accessibilityLabel(Copy.Feed.more)
    }

    private var glyph: some View {
        Image(systemName: "ellipsis")
            .font(ThemeType.feedNote.font.weight(.medium))
            .foregroundStyle(tint)
            .frame(width: FeedMetrics.actionHitHeight, height: FeedMetrics.actionHitHeight)
            .contentShape(Rectangle())
    }
}

/// The feed's ONE post menu (craft review, iD20). A `Menu` per realised row is a UIKit menu
/// interaction per row, and a lazy feed realises rows continuously — Search measured one per
/// result row at 40 % of an answer landing, which is why its unowned add became a plain button.
/// A list installs this (`postMenuHost`); its rows' `···` write the post here and the list presents
/// one dialog. The long-press `.contextMenu` stays on the row, as it stays on Search's rows.
@MainActor
@Observable
final class PostMenuRequest {
    var target: FeedPostModel?
}

extension EnvironmentValues {
    @Entry var postMenuRequest: PostMenuRequest? = nil
}

extension View {
    /// Installs the list's one post menu: the rows below find `request` in the environment, and
    /// the menu opens as one dialog over the list.
    func postMenuHost(_ request: PostMenuRequest,
                      onOpenShow: @escaping (FeedPostModel) -> Void) -> some View {
        modifier(PostMenuHost(request: request, onOpenShow: onOpenShow))
    }
}

private struct PostMenuHost: ViewModifier {
    let request: PostMenuRequest
    let onOpenShow: (FeedPostModel) -> Void

    func body(content: Content) -> some View {
        content
            .environment(\.postMenuRequest, request)
            .confirmationDialog(Copy.Feed.more, isPresented: presented, titleVisibility: .hidden,
                                presenting: request.target) { m in
                PostMenuItems(model: m, onOpenShow: { onOpenShow(m) }, divided: false)
            }
    }

    private var presented: Binding<Bool> {
        Binding(get: { request.target != nil }, set: { if !$0 { request.target = nil } })
    }
}

/// Every item does what it says: less of this, none of this show (or its news back), copy, the
/// source (an https link only), the show.
struct PostMenuItems: View {
    let model: FeedPostModel
    let onOpenShow: () -> Void
    /// A menu draws its rule between the curation items and the rest; a dialog has none to draw.
    var divided = true

    @Environment(AppModel.self) private var appModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        let franchiseId = model.post.franchiseId
        Button { appModel.hidePost(model) } label: {
            Label(Copy.Feed.notInterested, systemImage: "hand.thumbsdown")
        }
        if appModel.mutedShowIds.contains(franchiseId) {
            Button { appModel.unmuteShow(franchiseId: franchiseId) } label: {
                Label(Copy.Feed.unmute(model.showName), systemImage: "speaker.wave.2")
            }
        } else {
            Button {
                appModel.muteShow(franchiseId: franchiseId, showName: model.showName, fromPostId: model.id)
            } label: {
                Label(Copy.Feed.mute(model.showName), systemImage: "speaker.slash")
            }
        }
        if divided { Divider() }
        Button { UIPasteboard.general.string = model.shareText } label: {
            Label(Copy.Feed.copyText, systemImage: "doc.on.doc")
        }
        if let source = model.readOn, let url = SafeURL.https(source.url?.absoluteString) {
            Button { openURL(url) } label: {
                Label(Copy.Feed.readOn(source.publisher), systemImage: "safari")
            }
        }
        Button(action: onOpenShow) {
            Label(Copy.Feed.goTo(model.showName), systemImage: "play.rectangle.on.rectangle")
        }
    }
}

// MARK: - Folded

/// X's inline answer to Not interested and Mute: the post folds into one grey line with Undo,
/// where it was — the feed never jumps under your thumb.
struct FoldedPostRow: View {
    let fold: FeedFold
    let onUndo: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: ThemeSpace.x3) {
                Text(text)
                    .type(ThemeType.feedNote)
                    .foregroundStyle(ThemeColor.feedSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(action: onUndo) {
                    Text(Copy.Action.undo)
                        .type(ThemeType.feedNoteTitle)
                        .foregroundStyle(ThemeColor.interactive)
                        .frame(minWidth: FeedMetrics.actionHitHeight, minHeight: FeedMetrics.actionHitHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FeedIconPressStyle())
            }
            .padding(.leading, ThemeMetrics.gutter)
            .padding(.trailing, ThemeSpace.x2)
            .padding(.vertical, ThemeSpace.x1)
            FeedHairline()
        }
        .transition(.opacity)
    }

    private var text: String {
        switch fold {
        case .notInterested: Copy.Feed.foldNotInterested
        case .muted(let show): Copy.Feed.foldMuted(show)
        }
    }
}

// MARK: - The rumour's note

/// X's Community Note, for a rumour: a bordered card — the reason in bold, what was reported, and
/// how many reports, none official. The feed clamps the note; the post page shows it whole.
struct RumourNote: View {
    let model: FeedPostModel
    var lines: Int? = 4

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeSpace.x2) {
            Label {
                Text(Copy.Feed.rumourNoteTitle).type(ThemeType.feedNoteTitle)
            } icon: {
                Image(systemName: "person.2.fill").font(ThemeType.feedSmall.font)
            }
            .labelStyle(RumourNoteTitleStyle())
            .foregroundStyle(ThemeColor.feedText)
            if let note = model.post.note, !note.isEmpty {
                Text(note)
                    .type(ThemeType.feedNote)
                    .foregroundStyle(ThemeColor.feedText)
                    .lineSpacing(FeedPostLayout.noteLineSpacing)
                    .lineLimit(lines)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(Copy.Feed.rumourNoteReports(model.post.sources.count))
                .type(ThemeType.feedSmall)
                .foregroundStyle(ThemeColor.feedSecondary)
        }
        .padding(ThemeSpace.x3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: FeedMetrics.noteRadius, style: .continuous)
            .strokeBorder(ThemeColor.feedSeparator, lineWidth: FeedMetrics.hairline))
    }
}

private struct RumourNoteTitleStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: FeedPostLayout.noteGlyphGap) {
            configuration.icon
            configuration.title
        }
    }
}

// MARK: - Media

/// One tap opens (the trailer's stage, or the picture's viewer); two like the post with
/// Instagram's heart. The single tap waits out the double, as Instagram's does.
struct PostMediaButton: View {
    let model: FeedPostModel
    let zoom: Namespace.ID?
    let onPlay: () -> Void
    let onViewMedia: () -> Void
    var onLoaded: (() -> Void)? = nil
    /// The post page shows a poster whole, the timeline its 4:5 crop (`PostMedia.posterAspect`).
    var posterAspect: CGFloat = PostMedia.posterInFeed
    /// The media's width, for its decode budget (the feed's column by default).
    var width: CGFloat = PostMedia.columnWidth

    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.feedAutoplay) private var autoplay
    @State private var hearts = 0

    private var isTrailer: Bool {
        if case .trailer = model.media { return true }
        return false
    }

    /// This post's trailer is the one playing in place.
    private var playingInline: Bool { isTrailer && autoplay?.playingId == model.id }

    var body: some View {
        PostMedia(model: model, onLoaded: onLoaded, width: width, posterAspect: posterAspect)
            .overlay { BigHeartPop(trigger: hearts, size: FeedPostLayout.bigHeart) }
            .modifier(ZoomSourceIfAny(id: FeedZoom.media(model.id), namespace: zoom))
            .contentShape(RoundedRectangle(cornerRadius: FeedMetrics.mediaRadius, style: .continuous))
            .gesture(
                TapGesture(count: 2).onEnded { likeByDoubleTap() }
                    .exclusively(before: TapGesture().onEnded { open() })
            )
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isTrailer ? Copy.Feed.playTrailer : Copy.Feed.viewPicture)
            .accessibilityValue(playingInline ? Copy.Feed.trailerPlaying : "")
            .accessibilityAction(.default) { open() }
            .accessibilityAction(named: Copy.Feed.likePost) { likeByDoubleTap() }
            .modifier(SoundAction(autoplay: playingInline ? autoplay : nil))
    }

    private func open() {
        if isTrailer { onPlay() } else { onViewMedia() }
    }

    /// Instagram's double tap only ever LIKES — it never takes a like back.
    private func likeByDoubleTap() {
        if !reduceMotion { hearts += 1 }
        appModel.like(model.id, franchiseId: model.post.franchiseId)
    }
}

/// The inline trailer's sound, as a named VoiceOver action on the media (its corner button is
/// inside an element VoiceOver reads as one). The action is conditional INSIDE the actions
/// builder, never an `if` around `content`: a branch there gives the media a new identity when a
/// trailer starts, which tears the player down the moment it mounts.
private struct SoundAction: ViewModifier {
    let autoplay: FeedAutoplay?

    func body(content: Content) -> some View {
        content.accessibilityActions {
            if let autoplay {
                Button(autoplay.muted ? Copy.Feed.soundOn : Copy.Feed.soundOff) { autoplay.muted.toggle() }
            }
        }
    }
}

/// The zoom's source ids, one spelling for the row, the post page and the covers.
enum FeedZoom {
    static func media(_ postId: String) -> String { "media/\(postId)" }
}

/// X's media: the column's width, radius 12 and X's one-pixel border — nothing on it but a play
/// glyph. A trailer's still is tried in order (iD10) at 16:9, and so is a true landscape. A POSTER
/// is shown as the tall picture it is (the X pass, 25 Sep — "why does this not look like X?"): X
/// draws a tall image tall, cropped in the timeline (4:5 here, around where a key visual's faces
/// sit) and whole on the post page (2:3). The 16:9 frame with the poster composited small on its own
/// blurred ground read as a picture in a box — nothing X or Instagram draws.
struct PostMedia: View {
    let model: FeedPostModel
    var onLoaded: (() -> Void)? = nil
    /// The frame's width — the post's text column by default.
    var width: CGFloat = PostMedia.columnWidth
    /// A poster's frame, width ÷ height: the timeline's crop by default; the post page passes the
    /// whole poster (`posterWhole`).
    var posterAspect: CGFloat = PostMedia.posterInFeed

    /// X's timeline crop of a tall picture, and the whole poster on the post page.
    static let posterInFeed: CGFloat = 4.0 / 5.0
    static let posterWhole: CGFloat = 2.0 / 3.0
    /// A key visual's faces sit about a third of the way down: the timeline's crop centres there.
    static let posterFocus: CGFloat = 0.36

    @Environment(\.displayScale) private var displayScale
    /// X's inline video, where the list installs it (the feed, the post page).
    @Environment(\.feedAutoplay) private var autoplay

    /// The feed's text column: the window less the row's insets, the avatar and the gap.
    static var columnWidth: CGFloat {
        ThemeMetrics.windowWidth - 2 * FeedMetrics.inset - FeedMetrics.avatar - FeedMetrics.gap
    }

    /// The decode budget: the frame's pixels, at most 1280 (900 on a constrained or expensive path).
    private var decodePixels: CGFloat {
        let constrained = SyncCenter.shared.isConstrained || SyncCenter.shared.isExpensive
        return min(constrained ? PostMedia.constrainedPixels : PostMedia.maxPixels, width * displayScale)
    }

    static let maxPixels: CGFloat = 1280
    static let constrainedPixels: CGFloat = 900

    /// A poster's budget is its LONG side: 1.5 × the width, up to 1800 px (1200 constrained).
    private var posterPixels: CGFloat {
        let constrained = SyncCenter.shared.isConstrained || SyncCenter.shared.isExpensive
        return min(constrained ? 1200 : 1800, width * 1.5 * displayScale)
    }

    /// The frame's shape: a poster's own, else X's 16:9.
    private var aspect: CGFloat {
        if case .art(let art) = model.media, art.portraitSource { return posterAspect }
        return 16.0 / 9.0
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FeedMetrics.mediaRadius, style: .continuous)
        ZStack {
            shape.fill(ThemeColor.surfaceRaised)
            switch model.media {
            case .trailer(let stills, let video):
                ChainedRemoteImage(urls: stills, contentMode: .fill, maxPixel: decodePixels, onLoaded: onLoaded)
                if let autoplay, video.youtubeID != nil {
                    InlineTrailerSlot(postId: model.id, video: video, autoplay: autoplay)
                } else {
                    PlayGlyph()
                }
            case .art(let art):
                if art.portraitSource {
                    // The poster itself, filling its tall frame (the launch still signals on the
                    // picture's decode, never on the grey ground under it).
                    PostPoster(url: art.url, maxPixel: posterPixels, focus: Self.posterFocus, onLoaded: onLoaded)
                } else {
                    // `LandscapeArt`'s own landscape branch, with the load callback the launch needs.
                    RemoteImageView(url: art.url, contentMode: .fill,
                                    maxPixel: art.ultraWide ? max(decodePixels, LandscapeArt.ultraWidePixels) : decodePixels,
                                    alignment: .top, placeholderHidden: true, onLoaded: onLoaded)
                }
            case .none:
                EmptyView()
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(shape)
        .overlay(shape.strokeBorder(ThemeColor.feedSeparator, lineWidth: FeedMetrics.hairline))
    }
}

/// A poster filling a tall frame: laid out at its 2:3 and moved up so the frame's crop is centred
/// `focus` of the way down it. A 2:3 frame shows it whole.
private struct PostPoster: View {
    let url: String?
    let maxPixel: CGFloat
    let focus: CGFloat
    var onLoaded: (() -> Void)? = nil

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let tall = max(g.size.height, w / PostMedia.posterWhole)
            RemoteImageView(url: url, contentMode: .fill, maxPixel: maxPixel, alignment: .top,
                            placeholderHidden: true, onLoaded: onLoaded)
                .frame(width: w, height: tall)
                .offset(y: -(tall - g.size.height) * focus)
        }
        .clipped()
    }
}

extension LandscapeArt {
    /// An AniList banner's native width (`LandscapeArt.ultraWide`'s decode).
    static let ultraWidePixels: CGFloat = 1900
}

/// The platforms' play button: a white triangle in a dark translucent disc, nothing more.
struct PlayGlyph: View {
    private static let disc: CGFloat = 52
    private static let edge: CGFloat = 1.5

    var body: some View {
        Image(systemName: "play.fill")
            .font(.title3.weight(.bold))
            .foregroundStyle(FeedStage.ink)
            .offset(x: Self.edge)
            .frame(width: Self.disc, height: Self.disc)
            .background(FeedStage.glyphGround, in: Circle())
            .overlay(Circle().strokeBorder(FeedStage.ink.opacity(0.9), lineWidth: Self.edge))
            .accessibilityHidden(true)
    }
}

/// `matchedTransitionSource` when there is a namespace to register in (the feed's zoom), else
/// nothing (Saved and the other hosts that present no viewer).
struct ZoomSourceIfAny: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace) {
                $0.clipShape(RoundedRectangle(cornerRadius: FeedMetrics.mediaRadius, style: .continuous))
            }
        } else {
            content
        }
    }
}

// MARK: - The reminder primer slot

/// The alerts primer under the one post whose reminder is waiting on notification permission
/// (§4.4). Its own view, so only it observes `reminderPrimerPostId`, not every row.
private struct ReminderPrimerSlot: View {
    let model: FeedPostModel
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if appModel.reminderPrimerPostId == model.id {
            AlertsPrimerLine(model: model)
                .padding(.top, ThemeSpace.x1)
                .padding(.bottom, ThemeSpace.x2)
                .transition(.opacity)
        }
    }
}

// MARK: - Share, from an accessibility action

/// The system share sheet, presented from the frontmost controller — for the row's "Share"
/// VoiceOver action (a `ShareLink` cannot be triggered from an action).
@MainActor
enum SystemShare {
    static func present(_ items: [Any]) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = top.view
        top.present(sheet, animated: true)
    }
}

// MARK: - Glyph sizes

/// A symbol at an exact point size — the action bar's glyph, scaled with Dynamic Type and capped
/// (`@ScaledMetric` from `FeedMetrics.actionGlyph`). SF's own weights; no text is set with it.
enum FeedGlyph {
    static func font(_ size: CGFloat, weight: UIFont.Weight = .regular) -> Font {
        Font(UIFont.systemFont(ofSize: size, weight: weight))
    }
}
