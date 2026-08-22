import SwiftUI
import ClerkKit
import ClerkKitUI

// First run (spec board 07): the brand, one action. Nothing to read, nothing to configure.
// The developer sign-in exists only in debug builds without a Clerk key.
struct SignInView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showClerkAuth = false
    @State private var devId = "demo-user"

    var body: some View {
        ZStack {
            ThemeColor.canvas.ignoresSafeArea()
            RadialGradient(colors: [ThemeColor.accent.opacity(0.14), .clear], center: .top, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                Spacer()
                PreviouslyMark(width: 52)
                    .shadow(color: ThemeColor.accent.opacity(0.30), radius: 16, y: 6)
                    .accessibilityHidden(true)
                (Text("Previously").foregroundStyle(ThemeColor.textPrimary) + Text(".").foregroundStyle(ThemeColor.accent))
                    .type(ThemeType.displayXL)
                    .padding(.top, ThemeSpace.x4)
                    .accessibilityLabel("Previously")
                Text("Know what changed. Record what you watched.")
                    .type(ThemeType.callout)
                    .foregroundStyle(ThemeColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, ThemeSpace.x2)
                    .padding(.horizontal, ThemeSpace.x8)
                Spacer()

                VStack(spacing: ThemeSpace.x3) {
                    if AppConfig.isClerkConfigured {
                        Button("Sign in") { showClerkAuth = true }
                            .buttonStyle(PrimaryButtonStyle2())
                    } else {
                        #if DEBUG
                        DevSignInCard(devId: $devId) { auth.signInDev(clerkId: devId) }
                        #else
                        Text("Sign-in isn’t configured for this build.")
                            .type(ThemeType.metadata).foregroundStyle(ThemeColor.textTertiary)
                        #endif
                    }
                    if let error = auth.lastError {
                        InlineNotice(error)
                    }
                }
                .padding(.horizontal, ThemeSpace.x6)
                .padding(.bottom, ThemeSpace.x10)
            }
        }
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
        VStack(alignment: .leading, spacing: ThemeSpace.x3) {
            SectionLabel(text: "Developer sign-in")
            Text("No Clerk key configured. Sign in with a dev user id (the backend must allow DEV_AUTH_BYPASS outside production).")
                .type(ThemeType.metadata).foregroundStyle(ThemeColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("dev user id", text: $devId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .type(ThemeType.body)
                .foregroundStyle(ThemeColor.textPrimary)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(ThemeColor.surfaceFloating, in: RoundedRectangle(cornerRadius: ThemeRadius.compactControl, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ThemeRadius.compactControl, style: .continuous).stroke(ThemeColor.stroke, lineWidth: 1))
            Button("Continue", action: onContinue)
                .buttonStyle(PrimaryButtonStyle2())
        }
        .padding(ThemeSpace.x4)
        .background(ThemeColor.surfaceRaised, in: RoundedRectangle(cornerRadius: ThemeRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThemeRadius.card, style: .continuous).stroke(ThemeColor.separator, lineWidth: 1))
    }
}
#endif
