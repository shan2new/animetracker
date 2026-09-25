import SwiftUI

// The community rules (spec §4.5 step 1, brief §8, App Review 1.2). Two readings of one page:
//   • `.accept` — the composer's first gate. "Agree and continue" records the CURRENT terms version
//     server-side; a `terms_version_mismatch` (the rules moved while the page was open) says so and
//     asks again, and the model has already refetched the version to agree to.
//   • `.read` — Profile's Community group: the same page, no button.
//
// No NavigationStack of its own: the composer embeds it as a step, Profile pushes it. Its title
// rides whichever bar it is under.

struct CommunityRulesSheet: View {
    enum Mode { case accept, read }

    let mode: Mode
    let onAccepted: (SocialProfile) -> Void

    @Environment(AppModel.self) private var appModel
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var accepting = false
    @State private var problem: String?

    /// The full terms, only over https (brief §14 — the client opens nothing else).
    private var termsURL: URL? {
        guard let url = AppConfig.termsURL, url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(Copy.Social.rulesIntro)
                    .type(ThemeType.feedLightLarge)
                    .foregroundStyle(ThemeColor.feedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, ThemeSpace.x4)
                Rectangle().fill(ThemeColor.feedSeparator).frame(height: FeedMetrics.hairline)
                ForEach(Array(Copy.Social.rulesItems.enumerated()), id: \.offset) { index, rule in
                    HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x3) {
                        AppGlyph(systemName: "\(index + 1).circle.fill")
                            .font(ThemeType.feedMeta.font)
                            .foregroundStyle(ThemeColor.feedSecondary)
                            .accessibilityHidden(true)
                        Text(rule)
                            .type(ThemeType.feedLight)
                            .foregroundStyle(ThemeColor.feedText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, ThemeSpace.x3)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(ThemeColor.feedSeparator).frame(height: FeedMetrics.hairline)
                    }
                }
                if let termsURL {
                    Button {
                        openURL(termsURL)
                    } label: {
                        HStack(spacing: ThemeSpace.x1) {
                            Text(Copy.Social.rulesReadTerms)
                            AppGlyph(systemName: "arrow.up.right").accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(InlineLinkButtonStyle())
                    // The style holds its 44-pt target with padding; pulled back onto the text's edge.
                    .padding(.leading, -ThemeSpace.x3)
                    .padding(.top, ThemeSpace.x2)
                    .accessibilityAddTraits(.isLink)
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .padding(.top, ThemeSpace.x3)
            .padding(.bottom, ThemeSpace.x8)
        }
        .scrollIndicators(.hidden)
        .background(ThemeColor.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if mode == .accept { acceptBar }
        }
        .brandNavigationTitle(Copy.Social.rulesTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var acceptBar: some View {
        VStack(spacing: ThemeSpace.x2) {
            if let problem {
                Text(problem)
                    .type(ThemeType.metadata)
                    .foregroundStyle(ThemeColor.destructive)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            Button(action: accept) {
                ZStack {
                    Text(Copy.Social.rulesAgree).opacity(accepting ? 0 : 1)
                    if accepting { ProgressView().tint(ThemeColor.onAccent) }
                }
            }
            .buttonStyle(PrimaryButtonStyle2())
            .disabled(accepting)
            .accessibilityLabel(Copy.Social.rulesAgree)
        }
        .padding(.horizontal, ThemeMetrics.gutter)
        .padding(.top, ThemeSpace.x3)
        .padding(.bottom, ThemeSpace.x2)
        .frame(maxWidth: .infinity)
        .background { ThemeColor.canvas.ignoresSafeArea(edges: .bottom) }
        .overlay(alignment: .top) {
            Rectangle().fill(ThemeColor.feedSeparator).frame(height: FeedMetrics.hairline)
        }
    }

    private func accept() {
        guard !accepting else { return }
        accepting = true
        withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) { problem = nil }
        Task {
            let result = await appModel.acceptCommunityRules()
            accepting = false
            switch result {
            case .success(let profile):
                onAccepted(profile)
            case .failure(let failure):
                withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) {
                    problem = Self.message(for: failure)
                }
            }
        }
    }

    /// A refusal in the user's words (never a status code).
    static func message(for failure: SocialFailure) -> String {
        switch failure {
        case .termsVersionMismatch: return Copy.Social.rulesChanged
        case .offline: return Copy.Notice.noConnection
        case .rateLimited: return Copy.Notice.rateLimited
        case .handleTaken: return Copy.Social.usernameTaken
        case .invalidHandle(let reason): return Copy.Social.handleRejection(reason)
        case .invalidDisplayName(let reason): return Copy.Social.nameRejection(reason)
        case .server: return Copy.Notice.serverError
        }
    }
}
