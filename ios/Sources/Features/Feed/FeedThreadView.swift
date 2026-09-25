import SwiftUI

/// A post opened (X's post detail, measured): the author, the news at reading size, the rumour's
/// note or the post's note, the media, the meta line ("15 Jun 2026 · via Crunchyroll News · 12
/// Likes"), the bar, "How this story got here ›", and the replies — a real, server-backed thread
/// on the post's CANONICAL id (`detail.post.id`, never the id the route arrived with: an adopted
/// `catalog:` id answers with its new post, server §13.12).
///
/// A post the list already composed shows at once (`appModel.feedPost(id:)`); the page's own
/// read (`GET /feed/posts/:id`) fills in the trail, the sources and the thread.
struct FeedThreadView: View {
    let postId: String
    let focusCommentId: String?
    let push: (any Hashable) -> Void

    init(postId: String, focusCommentId: String?, push: @escaping (any Hashable) -> Void) {
        self.postId = postId
        self.focusCommentId = focusCommentId
        self.push = push
    }

    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    /// The full composer (the gate's steps, or the inline bar's ↗).
    @State private var composing: ComposeTarget?
    /// The inline bar's target when it is not the post itself (a reply to one reply) — or the
    /// post's, when the page's own reply button opened the bar.
    @State private var replyTarget: ComposeTarget?
    @State private var trailOpen = false
    @State private var viewing: FeedPostModel?
    @State private var video: FeedPostModel?
    @State private var focusLanded = false
    @State private var captureLanded = false
    /// X plays the post's video on its page too.
    @State private var autoplay = FeedAutoplay()
    @State private var onScreen = false
    @Environment(\.scenePhase) private var scenePhase
    /// What the picture viewer asked for on its way out, done once it has gone (a sheet or a push
    /// raised while the cover is still leaving is dropped).
    @State private var afterCover: AfterCover?
    @Namespace private var mediaZoom

    private enum AfterCover { case compose(ComposeTarget), show(String) }

    private static let authorTop: CGFloat = ThemeSpace.x2
    private static let sentenceTop: CGFloat = 14
    private static let sentenceLeading: CGFloat = 4
    private static let blockGap: CGFloat = 14
    private static let metaTop: CGFloat = 16

    var body: some View {
        let state = appModel.postDetails[postId]
        let detail = state?.detail
        let model = state?.model ?? appModel.feedPost(id: postId)
        Group {
            if let model {
                page(model: model, detail: detail)
            } else if state?.notFound == true {
                gone
            } else if state?.failed == true {
                failed
            } else {
                ProgressView()
                    .controlSize(.regular)
                    .tint(ThemeColor.feedSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(Copy.Accessibility.loading)
            }
        }
        .background(ThemeColor.canvas.ignoresSafeArea())
        // X's bar: a plain arrow and "Post" beside it, on the page's own black — not the system's
        // glass disc and a centred title. The title stays the screen's name (VoiceOver, and the
        // back label of a page pushed on top); the principal slot is emptied so it is drawn once.
        .navigationTitle(Copy.Feed.postTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                XPageTitle(title: Copy.Feed.postTitle) { dismiss() }
            }
            .chromeSharedBackgroundHidden()
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
        }
        // A hidden back button takes UIKit's edge swipe with it; X's page keeps it.
        .background(SwipeBackKeeper().frame(width: 0, height: 0).accessibilityHidden(true))
        .task(id: postId) { await appModel.loadPostDetail(postId) }
        .sheet(item: $composing) { ComposeSheet(target: $0) }
        .sheet(isPresented: $trailOpen) {
            if let detail { NewsTrailSheet(detail: detail) }
        }
        .fullScreenCover(item: $viewing, onDismiss: runAfterCover) { m in
            FeedMediaViewer(model: m, onComment: { afterCover = .compose(composeTarget(m, detail: detail)) },
                            onOpenShow: { afterCover = .show(m.post.franchiseId) })
                .navigationTransition(.zoom(sourceID: FeedZoom.media(m.id), in: mediaZoom))
        }
        .fullScreenCover(item: $video) { m in
            if case .trailer(_, let v) = m.media {
                VideoSheet(video: v, showTitle: m.showName, ambientArt: ambientArt(m),
                           startAt: Int(autoplay.position(m.id)))
                    .navigationTransition(.zoom(sourceID: FeedZoom.media(m.id), in: mediaZoom))
            }
        }
        .environment(\.feedAutoplay, autoplay)
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        // Nothing plays behind a cover or a sheet, under a push, or in the background.
        .onChange(of: autoplayHeld, initial: true) { _, held in autoplay.suspend(held) }
    }

    private var autoplayHeld: Bool {
        viewing != nil || video != nil || composing != nil || trailOpen || !onScreen || scenePhase != .active
    }

    // MARK: - The page

    @ViewBuilder
    private func page(model: FeedPostModel, detail: FeedPostDetail?) -> some View {
        let comments = appModel.feedCapabilities.comments
        let subject = detail?.post.id
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    postBlock(model: model, detail: detail)
                        .padding(.horizontal, FeedMetrics.inset)
                    // X's second rule, under the bar. Its id is the page's own: the section's sort
                    // row is "replies" (`CommentThreadSection.headerID`), and a lazy stack drops a
                    // duplicate id — the sort row, with the task that loads the thread, went with it.
                    FeedHairline()
                        .id(Self.repliesAnchor)
                    if comments, let subject {
                        // A reply to one reply opens the bar below on that person (X's thread);
                        // "How this story got here ›" rides the sort row, as X's "View quotes ›".
                        CommentThreadSection(subject: subject, franchiseTitle: model.showName,
                                             focusCommentId: focusCommentId,
                                             onCompose: { replyTarget = $0 },
                                             trailing: storyTrail(detail))
                    } else if let trail = storyTrail(detail) {
                        trailRow(trail)
                    }
                }
                .padding(.bottom, ThemeSpace.x4)
            }
            .scrollIndicators(.hidden)
            // X's: dragging the thread takes the keyboard down with the finger.
            .scrollDismissesKeyboard(.interactively)
            .onScrollPhaseChange { _, next in autoplay.scrollMoving(next != .idle) }
            .laneClearance(appModel)
            .previouslyRefreshable { await reloadPage() }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if comments, let subject {
                    InlineReplyComposer(target: ComposeTarget(subject: subject, franchiseId: model.post.franchiseId,
                                                              franchiseTitle: model.showName),
                                        replyingTo: $replyTarget,
                                        onFullComposer: { composing = $0 },
                                        onSent: {
                                            // The reply lands at the top of the thread: bring it into view.
                                            withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
                                                proxy.scrollTo(Self.repliesAnchor, anchor: .top)
                                            }
                                        })
                }
            }
            // The reply a notification pointed at: once its page is in, scrolled to (the section
            // lights it). Twice — the first pass can run before the lazy rows above it have laid out.
            .task(id: focusKey(subject)) { await landOnFocus(proxy, subject: subject) }
            .task(id: detail != nil) { await captureLanding(proxy, model: model, detail: detail) }
        }
    }

    private func postBlock(model: FeedPostModel, detail: FeedPostDetail?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            author(model)
                .padding(.top, Self.authorTop)
            // ONE body in one style, as an X post is: the sentence, then the research's note as its
            // next paragraph (a rumour's note lives in its Community Note box instead). The note
            // in grey at 15 under a 17-pt sentence read as two fonts in one post (owner, 25 Sep).
            Text(bodyText(model))
                .type(ThemeType.feedBodyLarge)
                .foregroundStyle(ThemeColor.feedText)
                .lineSpacing(Self.sentenceLeading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Self.sentenceTop)
                .textSelection(.enabled)
            switch model.media {
            case .none:
                RumourNote(model: model, lines: nil)
                    .padding(.top, Self.blockGap)
            case .art, .trailer:
                PostMediaButton(model: model, zoom: mediaZoom,
                                onPlay: { video = model }, onViewMedia: { viewing = model },
                                posterAspect: PostMedia.posterWhole, width: Self.mediaWidth)
                    .padding(.top, Self.blockGap)
            }
            metaLine(model)
                .padding(.top, Self.metaTop)
            // X's post page sets its bar between two rules.
            FeedHairline()
                .padding(.top, ThemeSpace.x3)
            PostActionBar(model: model, large: true, onComment: {
                // X's: the page's reply button opens the bar at the foot, not a second screen.
                replyTarget = composeTarget(model, detail: detail)
            })
            .padding(.vertical, ThemeSpace.x0_5)
            if let detail, !detail.live {
                Text(Copy.Feed.notLive)
                    .type(ThemeType.feedSmall)
                    .foregroundStyle(ThemeColor.feedSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, ThemeSpace.x3)
            }
        }
    }

    /// The post's words: the sentence, and the note as a second paragraph when the post has a
    /// picture (a rumour's note is its Community Note).
    private func bodyText(_ model: FeedPostModel) -> String {
        if case .none = model.media { return model.sentence }
        guard let note = model.post.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else {
            return model.sentence
        }
        return model.sentence + "\n\n" + note
    }

    /// The post page's media runs the page's width, inside its insets.
    private static var mediaWidth: CGFloat { ThemeMetrics.windowWidth - 2 * FeedMetrics.inset }

    /// "How this story got here ›" — when the post has a trail to show.
    private func storyTrail(_ detail: FeedPostDetail?) -> CommentThreadSection.Trailing? {
        guard let detail, !detail.storyline.isEmpty else { return nil }
        return CommentThreadSection.Trailing(title: Copy.Feed.howThisStoryGotHere) { trailOpen = true }
    }

    /// The trail's link on its own row, for a page with replies off.
    private func trailRow(_ trail: CommentThreadSection.Trailing) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                CommentThreadSection.TrailingLink(trailing: trail)
            }
            .padding(.horizontal, FeedMetrics.inset)
            FeedHairline()
        }
    }

    /// The show as the account: its avatar, its name (✓ when the news is the studio's own), and
    /// "Season 2 · Anime" in grey. The whole row opens the show; the `···` is the post's menu.
    private func author(_ model: FeedPostModel) -> some View {
        HStack(spacing: FeedMetrics.gap) {
            Button { openShow(model.post.franchiseId) } label: {
                HStack(spacing: FeedMetrics.gap) {
                    ShowAvatar(franchise: model.franchise)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: FeedPostLayout.nameSpacing) {
                            Text(model.showName)
                                .type(ThemeType.feedName)
                                .foregroundStyle(ThemeColor.feedText)
                                .lineLimit(1)
                            if model.showsOfficialMark { ConfirmedMark() }
                        }
                        Text(Copy.Feed.separated([model.post.installment,
                                                  model.franchise.source == .tmdb ? Copy.Filter.tv : Copy.Filter.anime]))
                            .type(ThemeType.feedMeta)
                            .foregroundStyle(ThemeColor.feedSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(Copy.Feed.goTo(model.showName))
            // X's Follow: a show you have not added offers Add beside its name.
            if !model.isOwned {
                ShowAddCapsule(model: model, onOpenShow: { openShow(model.post.franchiseId) })
            }
            PostMenuButton(model: model, onOpenShow: { openShow(model.post.franchiseId) })
                .padding(.trailing, -FeedPostLayout.menuTrailingPull)
        }
    }

    /// X's meta line: "2:19 PM · 15 Jun 2026 · via Crunchyroll News · 12 Likes" — the clock first
    /// (never for a date-only fact), the numeral in bold ink. A trailer names no publisher (its
    /// source is the video itself).
    private func metaLine(_ model: FeedPostModel) -> some View {
        let time = model.post.time
        let clock = time.dateOnly ? nil : Formatting.formatted(time.at, skeleton: "jmm", anchor: time.anchor)
        let date = Formatting.formatted(time.at, skeleton: "dMMMyyyy", anchor: time.anchor)
        let publisher = model.post.kind == .trailer ? nil : model.post.sources.first?.publisher
        let lead = Copy.Feed.separated([clock, date, publisher.map(Copy.Feed.via)].compactMap { $0 })
        let likes = appModel.likeCount(model.id)
        let words = Copy.Feed.likesInline(likes)
        // `likesInline` joins the numeral and the noun with U+00A0 (`Copy.plural`): split there.
        let parts = words.split(separator: "\u{00A0}", maxSplits: 1).map(String.init)
        var line = Text(lead).foregroundStyle(ThemeColor.feedSecondary)
        if likes > 0, parts.count == 2 {
            line = line
                + Text(Copy.Feed.separator).foregroundStyle(ThemeColor.feedSecondary)
                + Text(parts[0]).bold().foregroundStyle(ThemeColor.feedText)
                + Text("\u{00A0}" + parts[1]).foregroundStyle(ThemeColor.feedSecondary)
        }
        return line
            .type(ThemeType.feedNote)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.numericText(value: Double(likes)))
    }

    // MARK: - States

    /// Updated or removed — or an adopted `catalog:` id. "Go to <show>" when the show is known.
    private var gone: some View {
        let known = knownShow
        let goToShow: (() -> Void)? = known.map { show -> () -> Void in { openShow(show.id) } }
        return GeometryReader { geo in
            ScrollView {
                EmptyState(Copy.Feed.postGone(show: known?.name), prominence: .major, primary: goToShow)
                    .centredState(contentH: geo.size.height)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var failed: some View {
        GeometryReader { geo in
            ScrollView {
                EmptyState(SyncCenter.shared.isOnline ? .feedServerNoCache : .feedOfflineNoData,
                           prominence: .major,
                           primary: { Task { await appModel.loadPostDetail(postId, force: true) } })
                    .centredState(contentH: geo.size.height)
            }
            .scrollIndicators(.hidden)
            .previouslyRefreshable { await reloadPage() }
        }
    }

    /// The show a gone post belonged to, when anything loaded knows it: a feed tab or a reminder,
    /// else — for a `catalog:<mediaId>` id — the library season with that media id.
    private var knownShow: (id: String, name: String)? {
        var id = appModel.franchiseIdOfPost(postId)
        if id == nil, let mediaId = ThreadSubject.catalogMediaId(postId) {
            id = appModel.library.first { f in f.parts.contains { $0.mediaId == mediaId } }?.id
        }
        guard let id else { return nil }
        let name = appModel.franchise(id: id)?.displayTitle
            ?? appModel.feedPost(id: postId)?.showName
            ?? appModel.feedTabs.values.lazy.compactMap { $0.response?.franchises.first { $0.id == id } }
                .first.map { $0.stub.displayTitle }
        return name.map { (id, $0) }
    }

    // MARK: - Actions

    private func runAfterCover() {
        guard let next = afterCover else { return }
        afterCover = nil
        switch next {
        case .compose(let target): replyTarget = target
        case .show(let id): openShow(id)
        }
    }

    private func openShow(_ franchiseId: String) {
        push(FranchiseDetailView.DetailPush.detail(franchiseId: franchiseId))
    }

    private func composeTarget(_ model: FeedPostModel, detail: FeedPostDetail?) -> ComposeTarget {
        ComposeTarget(subject: detail?.post.id ?? model.post.id, franchiseId: model.post.franchiseId,
                      franchiseTitle: model.showName)
    }

    private func ambientArt(_ m: FeedPostModel) -> String? {
        if case .art(let art) = m.media { return art.url }
        return m.franchise.landscapeArt ?? m.franchise.portraitArt
    }

    private func reloadPage() async {
        await appModel.loadPostDetail(postId, force: true)
        if let subject = appModel.postDetails[postId]?.detail?.post.id, appModel.feedCapabilities.comments {
            await appModel.loadComments(subject, sort: appModel.thread(subject)?.sort ?? .top, reset: true)
        }
    }

    // MARK: - Landing on a reply

    /// The rule under the post — never "replies", the section's own sort-row id.
    private static let repliesAnchor = "post-foot"
    private static let focusRetry: Duration = .milliseconds(450)

    /// Changes when the focused reply's row can exist (the thread has loaded it).
    private func focusKey(_ subject: String?) -> String {
        guard let focusCommentId, let subject else { return "" }
        let loaded = appModel.thread(subject)?.items.contains { $0.id == focusCommentId } ?? false
        return loaded ? "\(subject)|\(focusCommentId)" : ""
    }

    private func landOnFocus(_ proxy: ScrollViewProxy, subject: String?) async {
        guard !focusLanded, let focusCommentId, !focusKey(subject).isEmpty else { return }
        focusLanded = true
        let motion = ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)
        withAnimation(motion) { proxy.scrollTo(focusCommentId, anchor: .center) }
        try? await Task.sleep(for: Self.focusRetry)
        guard !Task.isCancelled else { return }
        withAnimation(motion) { proxy.scrollTo(focusCommentId, anchor: .center) }
    }

    /// `-feedThreadAnchor replies|sources`, `-feedCompose "<text>"` (FeedCapture): a capture's
    /// landing on this page. Inert outside DEBUG (every capture value is nil there).
    private func captureLanding(_ proxy: ScrollViewProxy, model: FeedPostModel, detail: FeedPostDetail?) async {
        guard !captureLanded, FeedCapture.compose != nil || FeedCapture.threadAnchor != nil else { return }
        guard detail != nil || FeedCapture.threadAnchor == nil else { return }
        try? await Task.sleep(for: FeedCapture.threadLandingDelay)
        // Marked only once it lands: the detail arriving mid-wait re-keys this task (cancelling
        // it), and the next run must still land.
        guard !Task.isCancelled, !captureLanded else { return }
        captureLanded = true
        if let text = FeedCapture.compose {
            var target = composeTarget(model, detail: detail)
            target.prefill = text
            composing = target
        } else if let anchor = FeedCapture.threadAnchor {
            if anchor == "sources" || anchor == "history" {
                trailOpen = detail != nil
            } else {
                proxy.scrollTo(Self.repliesAnchor, anchor: UnitPoint(x: 0.5, y: 0.02))
            }
        }
    }
}
