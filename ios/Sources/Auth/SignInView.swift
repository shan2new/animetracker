import SwiftUI
import ClerkKit
import ClerkKitUI

// First run (spec board 07): the brand, one action. Nothing to read, nothing to configure.
// The developer sign-in exists only in debug builds without a Clerk key.
//
// Polish pass. There is no user artwork on first run, so the mark IS the art — and it has to be
// lit like art rather than decorated like a logo:
//
//  • The accent wash ran from the status bar downward while the mark sat in the middle of the
//    screen, so the screen's only light source had nothing to do with its only object. The bloom
//    is now centred ON the mark.
//  • `PreviouslyMark` carried a raw `.shadow(color: accent.opacity(0.3), …)` — a coloured glow
//    behind a logo, and not a `ShadowToken`. Removed; the bloom does that job honestly.
//  • Two equal spacers pinned the identity to the exact vertical centre and stapled the button to
//    the floor. The identity now sits on the upper third, where a title card sits.
//  • The developer card was a `surfaceRaised` box with a grey outline round it — the exact
//    wireframe grammar this pass exists to remove. It is a `.raised` surface now.
struct SignInView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showClerkAuth = false
    @State private var devId = "demo-user"

    private var isAX: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        ZStack {
            ThemeColor.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: ThemeSpace.x8)
                identity
                // Two spacers below, one above: the identity lands on the upper third rather than
                // dead centre. A title card is never centred on the frame.
                Spacer(minLength: ThemeSpace.x8)
                Spacer(minLength: 0)
                action
            }
            .padding(.horizontal, ThemeSpace.x6)
            .padding(.bottom, ThemeSpace.x10)
        }
    }

    // MARK: - Identity

    private var identity: some View {
        VStack(spacing: 0) {
            PreviouslyMark(width: 58)
                .background {
                    // The screen's one light source, centred on the one object it lights.
                    RadialGradient(colors: [ThemeColor.accent.opacity(0.20),
                                            ThemeColor.accent.opacity(0.05),
                                            .clear],
                                   center: .center, startRadius: 0, endRadius: 260)
                        .frame(width: 520, height: 520)
                        .blur(radius: 24)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            Text("Previously\(Text(".").foregroundStyle(ThemeColor.accent))")
                .foregroundStyle(ThemeColor.textPrimary)
                .type(ThemeType.displayXL)
                .padding(.top, ThemeSpace.x5)
                .accessibilityLabel("Previously")
            Text("Know what changed. Record what you watched.")
                .type(ThemeType.heroMeta)
                .foregroundStyle(ThemeColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ThemeMetrics.labelGap)
                .padding(.horizontal, isAX ? 0 : ThemeSpace.x6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Action

    private var action: some View {
        VStack(spacing: ThemeSpace.x3) {
            if AppConfig.isClerkConfigured {
                Button("Sign in") { showClerkAuth = true }
                    .buttonStyle(PrimaryButtonStyle2())
            } else {
                #if DEBUG
                DevSignInCard(devId: $devId) { auth.signInDev(clerkId: devId) }
                #else
                Text("Sign-in isn’t configured for this build.")
                    .type(ThemeType.metadata)
                    .foregroundStyle(ThemeColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                #endif
            }
            if let error = auth.lastError {
                InlineNotice(error)
            }
        }
        .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: auth.lastError)
        .sheet(isPresented: $showClerkAuth) {
            AuthView()
                .environment(Clerk.shared)
                .onChange(of: Clerk.shared.session != nil) { _, signedIn in
                    if signedIn {
                        auth.refreshClerkSignInState()
                        showClerkAuth = false
                    }
                }
        }
    }
}

#if DEBUG
private struct DevSignInCard: View {
    @Binding var devId: String
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
            SectionLabel(text: "Developer sign-in")
            Text("No Clerk key configured. Sign in with a dev user id (the backend must allow DEV_AUTH_BYPASS outside production).")
                .type(ThemeType.metadata)
                .foregroundStyle(ThemeColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("dev user id", text: $devId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .type(ThemeType.body)
                .foregroundStyle(ThemeColor.textPrimary)
                .tint(ThemeColor.accent)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(ThemeColor.surfaceFloating,
                            in: RoundedRectangle(cornerRadius: ThemeRadius.compactControl, style: .continuous))
                // `strokeBorder`, not `stroke`: a control may carry a full-perimeter edge, but a
                // centred 1-pt line straddles the shape and smears outside it.
                .overlay(RoundedRectangle(cornerRadius: ThemeRadius.compactControl, style: .continuous)
                    .strokeBorder(ThemeColor.stroke, lineWidth: 1))
                .padding(.top, ThemeSpace.x1)
            Button("Continue", action: onContinue)
                .buttonStyle(PrimaryButtonStyle2())
                .padding(.top, ThemeSpace.x1)
        }
        .padding(ThemeSpace.x4)
        // A card is visible because it is LIGHTER and lit along its top edge, not because it has
        // a grey line drawn round it.
        .surface(.raised, radius: ThemeRadius.card)
    }
}
#endif
