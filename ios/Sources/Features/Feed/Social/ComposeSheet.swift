import SwiftUI

// The reply composer (spec §4.5), a small flow in its own NavigationStack:
//
//   1. THE GATE, in the brief's order (§8): replies switched off → one sentence; no profile yet →
//      it loads (offline or failed → a recoverable state); the rules not accepted → the rules;
//      no name and username → the identity step; then
//   2. THE COMPOSER: X's — Cancel · Reply capsule, your disc beside "Replying about <show>" (or
//      "Replying to @dex") in grey with the name in text ink (never amber), the field, and a foot
//      that says who can read it and fills a ring with the SERVER's count.
//   3. SEND: waits on the model at most 1.5 s (iD5). Sent, queued (offline or a transport failure —
//      the thread's pending row and Sync status carry it) or still going at 1.5 s → the sheet
//      goes. A gate the server says is not passed steps back into it; a refusal stays, says why
//      under the field, and keeps the draft. The draft is never cleared except by a send.
//
// No haptic: the model signs writes, and a reply's receipt is the row that appears in its thread.

struct ComposeSheet: View {
    let target: ComposeTarget

    @Environment(AppModel.self) private var appModel
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draft: String
    @State private var sending = false
    @State private var problem: String?
    /// The server refused a gate the profile we held said was passed: that step comes back.
    @State private var forced: Step?
    @State private var profileFailed = false
    @State private var confirmDiscard = false
    @FocusState private var fieldFocused: Bool

    init(target: ComposeTarget) {
        self.target = target
        _draft = State(initialValue: target.prefill)
    }

    private enum Step: Equatable {
        case loading, failed(offline: Bool), disabled, rules, identity, composer
    }

    private var step: Step {
        guard appModel.feedCapabilities.comments else { return .disabled }
        if let forced { return forced }
        switch appModel.composeGate {
        case .disabled: return .disabled
        case .loading: return profileFailed ? .failed(offline: !SyncCenter.shared.isOnline) : .loading
        case .needsTerms: return .rules
        case .needsIdentity: return .identity
        case .ready: return .composer
        }
    }

    private var count: Int { SocialText.count(draft) }
    private var canSend: Bool { count > 0 && count <= SocialText.limit && !sending }
    private var hasDraft: Bool { count > 0 }
    private var episode: Int? { target.episode ?? ThreadSubject.parseEpisode(target.subject)?.episode }

    var body: some View {
        let step = step
        NavigationStack {
            ZStack {
                ThemeColor.canvas.ignoresSafeArea()
                content(step)
                    .transition(.opacity)
            }
            .animation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion), value: step)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.Action.cancel, action: cancel)
                        .foregroundStyle(ThemeColor.interactive)
                }
                if step == .composer {
                    ToolbarItem(placement: .confirmationAction) { replyCapsule }
                        .chromeSharedBackgroundHidden()
                }
            }
        }
        .tint(ThemeColor.interactive)
        .presentationDragIndicator(.visible)
        // A swipe never throws a draft away; Cancel asks first.
        .interactiveDismissDisabled(hasDraft || sending)
        .confirmationDialog(Copy.Social.discardDraftTitle, isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(Copy.Social.discardDraft, role: .destructive) { dismiss() }
            Button(Copy.Social.keepEditing, role: .cancel) {}
        }
        .task { await loadProfile() }
        .task(id: step == .composer) {
            // Focus once the presentation has settled — a yield, not a sleep.
            guard step == .composer else { return }
            await Task.yield()
            fieldFocused = true
        }
        .perfScreen("Compose")
    }

    // MARK: Steps

    @ViewBuilder
    private func content(_ step: Step) -> some View {
        switch step {
        case .loading:
            ProgressView()
                .tint(ThemeColor.feedSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Copy.Accessibility.loading)
        case .failed(let offline):
            EmptyState(offline ? .composeOffline : .composeFailed, prominence: .major) {
                Task { await loadProfile() }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .disabled:
            EmptyState(.commentsOff, prominence: .major)
                .padding(.horizontal, ThemeMetrics.gutter)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .rules:
            CommunityRulesSheet(mode: .accept) { _ in
                if forced == .rules { forced = nil }
            }
        case .identity:
            IdentitySetupView(mode: .firstReply) { _ in
                if forced == .identity { forced = nil }
            }
        case .composer:
            composer
        }
    }

    // MARK: The composer

    private var composer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // X's composer: what you are answering, above your own line, joined to it by the
                // thread's rule.
                ReplyContextBlock(target: target)
                composerRow
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .padding(.top, ThemeSpace.x2)
            .padding(.bottom, ThemeSpace.x6)
        }
        .scrollDismissesKeyboard(.never)
        .safeAreaInset(edge: .bottom, spacing: 0) { foot }
    }

    private var composerRow: some View {
        HStack(alignment: .top, spacing: ThemeSpace.x3) {
            AccountDisc(identity: auth.identity, diameter: FeedMetrics.composeAvatar, quiet: true)
            VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                Text(replyingLine)
                    .type(ThemeType.feedSubhead)
                    .fixedSize(horizontal: false, vertical: true)
                TextField(fieldPlaceholder, text: $draft, axis: .vertical)
                    .type(ThemeType.composeField)
                    .foregroundStyle(ThemeColor.feedText)
                    .readingLines(FeedPostLayout.lineHeightLarge)
                    .lineLimit(3...10)
                    .focused($fieldFocused)
                    .onChange(of: draft) {
                        if problem != nil {
                            withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) {
                                problem = nil
                            }
                        }
                    }
                if let problem {
                    Text(problem)
                        .type(ThemeType.metadata)
                        .foregroundStyle(ThemeColor.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "Replying about Frieren" / "Replying to @dex" — grey, with the show or the handle in text ink.
    private var replyingLine: AttributedString {
        if let to = target.replyingTo {
            return SocialInk.emphasising(Copy.Social.handle(to.handle), in: Copy.Social.replyingToUser(to.handle),
                                         base: ThemeColor.feedSecondary, emphasis: ThemeColor.feedText, bold: false)
        }
        return SocialInk.emphasising(target.franchiseTitle, in: Copy.Social.replyingTo(target.franchiseTitle),
                                     base: ThemeColor.feedSecondary, emphasis: ThemeColor.feedText, bold: false)
    }

    private var fieldPlaceholder: String {
        if target.replyingTo == nil, let episode { return Copy.Stories.commentOnEpisode(episode) }
        return Copy.Social.replyPlaceholder
    }

    /// Who can read it (the spoiler rule for an episode room), and the ring.
    private var foot: some View {
        HStack(spacing: ThemeSpace.x2) {
            AppGlyph(systemName: episode == nil ? "globe" : "eye.slash")
                .font(ThemeType.feedSmall.font)
                .accessibilityHidden(true)
            Text(episode.map(Copy.Social.episodeAudience) ?? Copy.Social.everyoneCanReply)
                .type(ThemeType.feedSmall)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            ComposeRing(count: count, limit: SocialText.limit)
                .opacity(hasDraft ? 1 : 0)
                .accessibilityHidden(!hasDraft)
        }
        .foregroundStyle(ThemeColor.feedSecondary)
        .padding(.horizontal, ThemeMetrics.gutter)
        .padding(.vertical, ThemeSpace.x2)
        .frame(minHeight: FeedMetrics.actionHitHeight)
        .background { ThemeColor.canvas.ignoresSafeArea(edges: .bottom) }
        .overlay(alignment: .top) {
            Rectangle().fill(ThemeColor.feedSeparator).frame(height: FeedMetrics.hairline)
        }
    }

    /// X's Reply pill: text ink on a light capsule — an action, so never amber. Dimmed until there is
    /// something the server will take.
    private var replyCapsule: some View {
        Button(action: send) {
            ZStack {
                Text(Copy.Social.reply).opacity(sending ? 0 : 1)
                if sending { ProgressView().controlSize(.small).tint(ThemeColor.canvas) }
            }
            .type(ThemeType.feedNoteTitle)
            .foregroundStyle(ThemeColor.canvas)
            .padding(.horizontal, ThemeSpace.x4)
            .frame(minHeight: FeedMetrics.replyFieldHeight)
            .background(canSend || sending ? ThemeColor.feedText : ThemeColor.feedSecondary, in: Capsule())
            .frame(minHeight: FeedMetrics.actionHitHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(FeedIconPressStyle())
        .disabled(!canSend)
        .accessibilityLabel(Copy.Social.reply)
    }

    // MARK: Actions

    private func cancel() {
        if hasDraft && !sending {
            confirmDiscard = true
        } else {
            dismiss()
        }
    }

    private func loadProfile() async {
        guard appModel.feedCapabilities.comments else { return }
        profileFailed = false
        if appModel.socialProfile != nil { return }
        let profile = await appModel.loadSocialProfile()
        if profile == nil { profileFailed = true }
    }

    private func send() {
        guard canSend else { return }
        sending = true
        withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) { problem = nil }
        let body = draft
        let target = target
        // The send runs on its own: the composer stops WAITING at 1.5 s, the model does not stop
        // sending (a transport failure becomes the thread's pending row and a Sync status row).
        let work = Task { await appModel.sendComment(target, body: body) }
        Task {
            let outcome = await ReplySend.firstAnswer(work, within: SocialMetrics.sendPatience)
            sending = false
            settle(outcome)
        }
    }

    private func settle(_ outcome: SendOutcome?) {
        switch outcome {
        case nil, .queued?:
            dismiss()
        case .sent?:
            Announce.status(Copy.Social.replyPosted)
            dismiss()
        case .needsTerms?:
            forced = .rules
        case .needsIdentity?:
            forced = .identity
        case let refused?:
            let message = ReplySend.problem(refused, episode: episode)
            withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) { problem = message }
            if let message { Announce.status(message) }
            fieldFocused = true
        }
    }
}

// MARK: - Sending, shared

/// The composers' one send policy (the sheet's and the inline bar's): wait on the model at most
/// `SocialMetrics.sendPatience` (iD5), and say a refusal in the same words either way.
enum ReplySend {
    /// The send's answer, or nil once `patience` has run out — whichever comes first. The send
    /// itself is not cancelled.
    @MainActor
    static func firstAnswer(_ work: Task<SendOutcome, Never>, within patience: Duration) async -> SendOutcome? {
        let gate = FirstAnswerGate()
        return await withCheckedContinuation { (continuation: CheckedContinuation<SendOutcome?, Never>) in
            Task { @MainActor in
                let value = await work.value
                gate.settle(continuation, value)
            }
            Task { @MainActor in
                try? await Task.sleep(for: patience)
                gate.settle(continuation, nil)
            }
        }
    }

    /// What a refused send says under the field; nil for an outcome that is not a refusal.
    static func problem(_ outcome: SendOutcome, episode: Int?) -> String? {
        switch outcome {
        case .sent, .queued, .needsTerms, .needsIdentity:
            return nil
        case .rejected(let reason):
            return Copy.Social.rejection(reason)
        case .locked(let access):
            guard let episode else { return Copy.Social.gone }
            return access == .unaired ? Copy.Stories.lockedUnaired(episode) : Copy.Stories.lockedUnwatched(episode)
        case .rateLimited:
            return Copy.Social.rateLimited
        case .disabled:
            return Copy.Social.commentsOff
        case .gone:
            return Copy.Social.gone
        }
    }
}

/// Resumes a continuation exactly once — the first of the send and the timer.
@MainActor
private final class FirstAnswerGate {
    private var settled = false

    func settle(_ continuation: CheckedContinuation<SendOutcome?, Never>, _ value: SendOutcome?) {
        guard !settled else { return }
        settled = true
        continuation.resume(returning: value)
    }
}

// MARK: - What you are answering

/// X's composer opens on what you are answering: the reply (the person, their words) or the post
/// (the show as the account, its words — `FeedPostModel.body`, as the timeline draws them), with a
/// rule from its avatar down to yours — the thread you are adding to. The words are whole, as X
/// quotes them (the composer scrolls). An episode room names the episode. Nothing when nothing is
/// known.
struct ReplyContextBlock: View {
    let target: ComposeTarget

    @Environment(AppModel.self) private var appModel

    /// The rule joining the two avatars (X's: 2 pt, the separator grey).
    private static let rule: CGFloat = 2

    var body: some View {
        if let parent = parentComment {
            block(avatar: AnyView(PersonDisc(user: parent.author, size: FeedMetrics.composeAvatar)),
                  name: parent.author.displayName.isEmpty ? Copy.Social.handle(parent.author.handle) : parent.author.displayName,
                  meta: Copy.Social.line([Copy.Social.handle(parent.author.handle),
                                          TemporalCopy.feedStamp(parent.createdAt, dateOnly: false, now: appModel.now)]),
                  words: parent.body)
        } else if let post = appModel.feedPost(id: target.subject) {
            block(avatar: AnyView(ShowAvatar(franchise: post.franchise, size: FeedMetrics.composeAvatar)),
                  name: post.showName,
                  meta: Copy.Feed.separated([post.post.installment, post.stamp].filter { !$0.isEmpty }),
                  words: post.body)
        } else if let room = ThreadSubject.parseEpisode(target.subject) {
            block(avatar: AnyView(ShowAvatar(candidates: showCandidates, size: FeedMetrics.composeAvatar)),
                  name: target.franchiseTitle,
                  meta: "",
                  words: Copy.Stories.discussionTitle(room.episode))
        }
    }

    private func block(avatar: AnyView, name: String, meta: String, words: String) -> some View {
        HStack(alignment: .top, spacing: ThemeSpace.x3) {
            VStack(spacing: ThemeSpace.x1) {
                avatar
                Rectangle()
                    .fill(ThemeColor.feedSeparator)
                    .frame(width: Self.rule)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: FeedMetrics.composeAvatar)
            VStack(alignment: .leading, spacing: ThemeSpace.x0_5) {
                HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x1) {
                    Text(name)
                        .type(ThemeType.feedPostName)
                        .foregroundStyle(ThemeColor.feedText)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if !meta.isEmpty {
                        Text(meta)
                            .type(ThemeType.feedSubhead)
                            .foregroundStyle(ThemeColor.feedSecondary)
                            .lineLimit(1)
                    }
                }
                Text(words)
                    .type(ThemeType.feedBody)
                    .foregroundStyle(ThemeColor.feedText)
                    .readingLines(FeedPostLayout.lineHeight)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, ThemeSpace.x4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// The reply being answered, when this thread has it loaded.
    private var parentComment: SocialComment? {
        guard let parentId = target.parentId else { return nil }
        return appModel.thread(target.subject)?.items.first { $0.id == parentId }
    }

    private var showCandidates: [String] {
        if let f = appModel.franchise(id: target.franchiseId) { return FeedAvatar.candidates(f) }
        for state in appModel.feedTabs.values {
            if let hit = state.response?.franchises.first(where: { $0.id == target.franchiseId }) {
                return FeedAvatar.candidates(hit.stub)
            }
        }
        return []
    }
}
