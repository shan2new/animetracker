import SwiftUI

/// Covers the whole app while `AppModel.accountSuspended` is raised (iD14): the server answered
/// `403 { error: 'account_suspended' }` (server D12), and every route but two now refuses this
/// account. What is left is what the account may still do — leave, take its data, or erase
/// itself — so that is all this screen offers.
///
/// `EmptyState`'s anatomy on the canvas (a symbol, a title, one sentence, the actions), not an
/// alert: an alert can be dismissed into an app that no longer answers. It makes no request of its
/// own; Export your data is `GET /me/export` (allowed while suspended) through `LibraryExport`,
/// Delete account is `DELETE /me` (allowed while suspended) through `AccountDeletion`, exactly
/// Profile's flows, and Sign out is local. RootView mounts it above the tab view and the lane.
struct AccountSuspendedView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AuthManager.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The symbol answers to Dynamic Type like the type beside it (`EmptyState`'s rule).
    @ScaledMetric(relativeTo: .title3) private var glyphUnit: CGFloat = 1

    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var signingOut = false
    @State private var deleting = false
    @State private var signOutFailed = false
    /// The deletion that did not happen, in `AccountDeletion.Failure`'s words.
    @State private var deleteFailure: String?

    private var busy: Bool { signingOut || deleting }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                content
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .padding(.vertical, ThemeSpace.x8)
                    // Centred in the screen while it fits; at the accessibility sizes the block
                    // grows past it and the screen scrolls instead of clipping the buttons.
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .background(ThemeColor.canvas.ignoresSafeArea())
        // Nothing under this screen may be reached: not by a touch, not by VoiceOver.
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isModal)
        .onAppear { Announce.screenChanged(Copy.Social.suspendedTitle) }
        .alert(Copy.Account.signOutTitle, isPresented: $confirmSignOut) {
            Button(Copy.Confirm.cancel, role: .cancel) {}
            Button(Copy.Action.signOut, role: .destructive) { performSignOut() }
        } message: {
            Text(Copy.Account.signOutMessage(pending: 0))
        }
        .alert(Copy.Account.deleteTitle, isPresented: $confirmDelete) {
            Button(Copy.Confirm.cancel, role: .cancel) {}
            Button(Copy.Account.deleteConfirm, role: .destructive) { performDelete() }
        } message: {
            Text(Copy.Account.deleteMessage(titles: appModel.library.count))
        }
        .alert(Copy.Account.deleteFailedTitle,
               isPresented: Binding(get: { deleteFailure != nil },
                                    set: { if !$0 { deleteFailure = nil } })) {
            Button(Copy.Action.done, role: .cancel) { deleteFailure = nil }
        } message: {
            Text(deleteFailure ?? "")
        }
        .alert(Copy.Account.signOutFailedTitle, isPresented: $signOutFailed) {
            Button(Copy.Action.done, role: .cancel) { signOutFailed = false }
        } message: {
            Text(Copy.Account.signOutFailedMessage)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 44 * glyphUnit, weight: .regular))
                .foregroundStyle(ThemeColor.textTertiary)
                .padding(.bottom, ThemeSpace.x4)
                .accessibilityHidden(true)
            Text(Copy.Social.suspendedTitle)
                .type(ThemeType.showTitleL)
                .foregroundStyle(ThemeColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(Copy.Social.suspendedMessage)
                .type(ThemeType.callout)
                .foregroundStyle(ThemeColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ThemeSpace.x2)
            actions.padding(.top, ThemeSpace.x5)
        }
        .frame(maxWidth: 300)
    }

    /// The routine exit first, as the quiet capsule; the irreversible one under it as a bare
    /// destructive verb — shape, not only colour, keeps a thumb from confusing them (Profile's M8).
    /// No amber anywhere: none of them is a next step the app is recommending.
    private var actions: some View {
        VStack(spacing: ThemeSpace.x3) {
            Button { confirmSignOut = true } label: {
                ZStack {
                    Text(Copy.Action.signOut).opacity(signingOut ? 0 : 1)
                    if signingOut {
                        ProgressView().controlSize(.small).tint(ThemeColor.textSecondary)
                    }
                }
            }
            .buttonStyle(SecondaryButtonStyle2())
            .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: false)
            .accessibilityLabel(Copy.Action.signOut)

            // The account's own copy before it is erased (an access request is exactly what a
            // suspended account still has a right to): `GET /me/export`, allowed while suspended,
            // shared through Profile's own file (`LibraryExport`) — fetched when a destination is
            // picked, never when this screen opens. A bare `interactive` verb: not a next step the
            // app recommends, so no amber and no capsule.
            ShareLink(item: LibraryExport(appModel: appModel, format: .json),
                      preview: SharePreview(Copy.Account.exportPreviewTitle)) {
                Text(Copy.Account.exportCommand)
            }
            .buttonStyle(TertiaryButtonStyle2())
            .accessibilityLabel(Copy.Account.exportCommand)

            Button { confirmDelete = true } label: {
                ZStack {
                    Text(Copy.Account.deleteCommand).opacity(deleting ? 0 : 1)
                    if deleting {
                        ProgressView().controlSize(.small).tint(ThemeColor.destructive)
                    }
                }
            }
            .buttonStyle(TertiaryButtonStyle2(destructive: true))
            .accessibilityLabel(Copy.Account.deleteCommand)
        }
        .disabled(busy)
    }

    // The two flows are Profile's (ProfileView `performSignOut` / `performDelete`), so the same
    // moment answers the same way wherever it is reached.

    private func performSignOut() {
        FeedbackCoordinator.fire(.destructive)
        withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) {
            signingOut = true
        }
        Task {
            let signedOut = await auth.signOut()
            signingOut = false
            if !signedOut { signOutFailed = true }
        }
    }

    private func performDelete() {
        FeedbackCoordinator.fire(.destructive)
        withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) {
            deleting = true
        }
        Task {
            // Profile's erasure: nothing the app sends may reach the server after the DELETE.
            await appModel.prepareForErasure()
            do {
                try await AccountDeletion.deleteAccount(token: auth.currentToken)
                // The account is gone; the session goes with it, and so does Profile's memory of
                // its counts. The model is wiped FIRST, so the wipe never depends on Clerk's
                // sign-out succeeding. The wipe lowers `accountSuspended`; it is raised again at
                // once so this cover stays up until the sign-in screen replaces it (no flash of an
                // empty app) — the sign-out's own teardown (RootView) lowers it for good.
                ProfileSnapshot.clear()
                appModel.teardown()
                appModel.accountSuspended = true
                await auth.accountErased()
                deleting = false
            } catch {
                // Not deleted: the account is still suspended, so nothing held back is sent
                // (`flushSocial` and SyncCenter stay quiet behind the suspension).
                appModel.abortErasure()
                deleting = false
                deleteFailure = (error as? LocalizedError)?.errorDescription
                    ?? AccountDeletion.Failure.refused.errorDescription
            }
        }
    }
}
