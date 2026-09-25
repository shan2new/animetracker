import SwiftUI

// X's reply bar, and the composer it OPENS INTO where it stands (spec §4.5, §7.2; the X pass of
// 25 Sep). At rest: your disc and a capsule that says "Post your reply" over the thread's foot.
// Tapped, it grows in place above the keyboard — "Replying to …", the field, and a foot with who
// can read it, the ring and the Reply pill — while the post and its replies stay in view above it.
// X's ↗ in the corner moves the draft to the full composer. A reply to one reply (the thread's
// reply buttons) opens the same bar on that person ("Replying to @dex").
//
// The gate is the sheet's: with the rules not accepted or no name and username yet (or the
// profile not in), the tap opens the full composer (`ComposeSheet`), which walks the steps; the
// inline field only ever writes for a profile that can post. The send is the sheet's too
// (`ReplySend`): at most 1.5 s of waiting, then the thread's pending row carries it. A refusal
// stays in the bar, says why and keeps the draft.
//
// Draws nothing while replies are off (§4.9), so a host mounts it unconditionally in
// `.safeAreaInset(edge: .bottom)`. The ground is the feed header's: the canvas, flush.

struct InlineReplyComposer: View {
    /// The thread's own target: the post, or the episode room.
    let target: ComposeTarget
    /// A reply to one reply, set by the thread's reply buttons; the bar opens on it. Cleared when
    /// the bar closes.
    @Binding var replyingTo: ComposeTarget?
    /// The full composer — the gate's steps, or the ↗. The draft travels in `prefill`.
    let onFullComposer: (ComposeTarget) -> Void
    /// A reply was handed to the thread (sent, or queued as its pending row).
    var onSent: () -> Void = {}

    @Environment(AppModel.self) private var appModel
    @Environment(AuthManager.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var draft = ""
    @State private var open = false
    @State private var sending = false
    @State private var problem: String?
    @FocusState private var focused: Bool

    /// The Reply pill's height (X's), inside a 44-pt target.
    private static let pillHeight: CGFloat = 32

    private var current: ComposeTarget { replyingTo ?? target }
    private var episode: Int? { current.episode ?? ThreadSubject.parseEpisode(current.subject)?.episode }
    private var count: Int { SocialText.count(draft) }
    private var canSend: Bool { count > 0 && count <= SocialText.limit && !sending }

    var body: some View {
        if appModel.feedCapabilities.comments {
            VStack(spacing: 0) {
                if open { expanded } else { collapsed }
            }
            .background { ground.ignoresSafeArea(edges: .bottom) }
            .overlay(alignment: .top) {
                Rectangle().fill(ThemeColor.feedSeparator).frame(height: FeedMetrics.hairline)
            }
            .animation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion), value: open)
            .transition(.opacity)
            // The gate is usually decided before the first tap: the profile is read once, here.
            .task { _ = await appModel.loadSocialProfile() }
            .onChange(of: replyingTo) { _, next in
                if let next { begin(next) }
            }
            .onChange(of: focused) { _, isFocused in
                // X keeps a draft in the bar; an empty bar that loses the keyboard closes.
                if !isFocused, !sending, count == 0 { close() }
            }
        }
    }

    // MARK: At rest

    private var placeholder: String {
        if current.replyingTo == nil, let episode { return Copy.Stories.commentOnEpisode(episode) }
        return Copy.Social.replyPlaceholder
    }

    private var collapsed: some View {
        Button { begin(target) } label: {
            HStack(spacing: ThemeSpace.x3) {
                AccountDisc(identity: auth.identity, diameter: FeedMetrics.replyBarAvatar, quiet: true)
                // A draft is a reply's words (SF); the invitation is the app's (Outfit).
                Text(count > 0 ? draft : placeholder)
                    .type(count > 0 ? ThemeType.feedNote : ThemeType.storyReply)
                    .foregroundStyle(count > 0 ? ThemeColor.feedText : ThemeColor.feedSecondary)
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ThemeSpace.x4)
                    .padding(.vertical, ThemeSpace.x1)
                    .frame(minHeight: FeedMetrics.replyFieldHeight)
                    .background(ThemeColor.feedField, in: Capsule())
            }
            .padding(.horizontal, FeedMetrics.inset)
            .padding(.vertical, ThemeSpace.x2)
            .frame(maxWidth: .infinity, minHeight: FeedMetrics.actionHitHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(OverArtPressStyle())
        .accessibilityLabel(count > 0 ? draft : placeholder)
        .accessibilityHint(count > 0 ? Copy.Social.replyPlaceholder : "")
    }

    // MARK: Open

    private var expanded: some View {
        VStack(alignment: .leading, spacing: ThemeSpace.x2) {
            HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x2) {
                Text(replyingLine)
                    .type(ThemeType.feedSubhead)
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                expandButton
            }
            HStack(alignment: .top, spacing: ThemeSpace.x3) {
                AccountDisc(identity: auth.identity, diameter: FeedMetrics.replyBarAvatar, quiet: true)
                TextField(placeholder, text: $draft, axis: .vertical)
                    .type(ThemeType.composeField)
                    .foregroundStyle(ThemeColor.feedText)
                    .readingLines(FeedPostLayout.lineHeightLarge)
                    .lineLimit(1...5)
                    .focused($focused)
                    .submitLabel(.return)
                    .padding(.top, ThemeSpace.x1)
                    .onChange(of: draft) {
                        if problem != nil {
                            withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) {
                                problem = nil
                            }
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
            foot
        }
        .padding(.horizontal, FeedMetrics.inset + ThemeSpace.x1)
        .padding(.top, ThemeSpace.x3)
        .padding(.bottom, ThemeSpace.x1)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    /// "Replying about Frieren" / "Replying to @dex" — grey, with the show or the handle in ink.
    private var replyingLine: AttributedString {
        if let to = current.replyingTo {
            return SocialInk.emphasising(Copy.Social.handle(to.handle), in: Copy.Social.replyingToUser(to.handle),
                                         base: ThemeColor.feedSecondary, emphasis: ThemeColor.feedText, bold: false)
        }
        return SocialInk.emphasising(current.franchiseTitle, in: Copy.Social.replyingTo(current.franchiseTitle),
                                     base: ThemeColor.feedSecondary, emphasis: ThemeColor.feedText, bold: false)
    }

    /// X's ↗: the draft moves to the full composer, and this bar closes behind it.
    private var expandButton: some View {
        Button {
            var full = current
            full.prefill = draft
            draft = ""
            close()
            onFullComposer(full)
        } label: {
            AppGlyph(systemName: "arrow.up.left.and.arrow.down.right")
                .font(ThemeType.feedSubhead.font.weight(.semibold))
                .foregroundStyle(ThemeColor.interactive)
                .frame(width: FeedMetrics.actionHitHeight, height: FeedMetrics.actionHitHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(FeedIconPressStyle())
        .padding(.vertical, -ThemeSpace.x3)
        .padding(.trailing, -ThemeSpace.x2)
        .accessibilityLabel(Copy.Social.expandComposer)
    }

    /// Who can read it (an episode room's spoiler rule), the ring, the pill.
    private var foot: some View {
        HStack(spacing: ThemeSpace.x2) {
            AppGlyph(systemName: episode == nil ? "globe" : "eye.slash")
                .font(ThemeType.feedSmall.font)
                .accessibilityHidden(true)
            Text(episode.map(Copy.Social.episodeAudience) ?? Copy.Social.everyoneCanReply)
                .type(ThemeType.feedSmall)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
            ComposeRing(count: count, limit: SocialText.limit)
                .opacity(count > 0 ? 1 : 0)
                .accessibilityHidden(count == 0)
            replyPill
        }
        .foregroundStyle(ThemeColor.feedSecondary)
        .frame(minHeight: FeedMetrics.actionHitHeight)
    }

    /// X's Reply pill: text ink on a light capsule — an action, so never amber. Dimmed until there
    /// is something the server will take.
    private var replyPill: some View {
        Button(action: send) {
            ZStack {
                Text(Copy.Social.reply).opacity(sending ? 0 : 1)
                if sending { ProgressView().controlSize(.small).tint(ThemeColor.canvas) }
            }
            .type(ThemeType.feedNoteTitle)
            .foregroundStyle(ThemeColor.canvas)
            .padding(.horizontal, ThemeSpace.x4)
            .frame(minHeight: Self.pillHeight)
            .background(canSend || sending ? ThemeColor.feedText : ThemeColor.feedSecondary, in: Capsule())
            .frame(minHeight: FeedMetrics.actionHitHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(FeedIconPressStyle())
        .disabled(!canSend)
        .accessibilityLabel(Copy.Social.reply)
    }

    /// Flush with the thread, as X's bar is (and as the feed's header is, `FeedHeaderGround`): a
    /// material under canvas read as a lighter band across the foot of the page.
    private var ground: some View {
        ThemeColor.canvas
    }

    // MARK: Actions

    /// Opens the bar on `t` — or, when this profile cannot post yet, the full composer's gate.
    private func begin(_ t: ComposeTarget) {
        guard appModel.composeGate == .ready else {
            var full = t
            full.prefill = draft
            if replyingTo != nil { replyingTo = nil }
            onFullComposer(full)
            return
        }
        if t.id != target.id, replyingTo?.id != t.id { replyingTo = t }
        problem = nil
        open = true
        // The field exists on the next pass; focus it there (a yield, not a sleep).
        Task { @MainActor in
            await Task.yield()
            focused = true
        }
    }

    private func close() {
        focused = false
        open = false
        problem = nil
        if replyingTo != nil { replyingTo = nil }
    }

    private func send() {
        guard canSend else { return }
        sending = true
        problem = nil
        let body = draft
        let target = current
        // The send runs on its own: the bar stops WAITING at 1.5 s, the model does not stop
        // sending (a transport failure becomes the thread's pending row and a Sync status row).
        let work = Task { await appModel.sendComment(target, body: body) }
        Task {
            let outcome = await ReplySend.firstAnswer(work, within: SocialMetrics.sendPatience)
            sending = false
            settle(outcome, target: target, body: body)
        }
    }

    private func settle(_ outcome: SendOutcome?, target: ComposeTarget, body: String) {
        switch outcome {
        case nil, .queued?:
            draft = ""
            close()
            onSent()
        case .sent?:
            Announce.status(Copy.Social.replyPosted)
            draft = ""
            close()
            onSent()
        case .needsTerms?, .needsIdentity?:
            // The server says a step is missing: the full composer walks it, with the words.
            var full = target
            full.prefill = body
            draft = ""
            close()
            onFullComposer(full)
        case let refused?:
            let message = ReplySend.problem(refused, episode: episode)
            withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) { problem = message }
            if let message { Announce.status(message) }
            focused = true
        }
    }
}
