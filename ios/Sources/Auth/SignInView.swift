import SwiftUI
import ClerkKit
import ClerkKitUI

// Signed-out screen. Presents Clerk's AuthView when a publishable key is configured; otherwise
// offers a dev-bypass sign-in that authenticates against the local backend's DEV_AUTH_BYPASS mode.
struct SignInView: View {
    @Environment(AuthManager.self) private var auth
    @State private var showClerkAuth = false
    @State private var devId = "demo-user"

    var body: some View {
        ZStack {
            // Subtle accent glow backdrop.
            RadialGradient(colors: [Theme.accent.opacity(0.12), .clear],
                           center: .top, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                Text("✦")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.accent)
                    .shadow(color: Theme.accent.opacity(0.55), radius: 20)
                Text("AniTrack")
                    .font(.system(size: 34, weight: .semibold))
                    .tracking(-1)
                    .padding(.top, 14)
                Text("Your airing-first anime tracker.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.text52)
                    .padding(.top, 8)

                Spacer()

                VStack(spacing: 14) {
                    if AppConfig.isClerkConfigured {
                        Button {
                            showClerkAuth = true
                        } label: {
                            Text("Sign in")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .foregroundStyle(Theme.background)
                        }
                        .buttonStyleProminentGlass()
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    } else {
                        DevSignInCard(devId: $devId) {
                            auth.signInDev(clerkId: devId)
                        }
                    }

                    if let error = auth.lastError {
                        Text(error)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.accent)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showClerkAuth) {
            // Clerk's prebuilt sign-in/sign-up flow.
            // Re-inject Clerk.shared explicitly — sheets can form a detached environment chain.
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

// Dev-bypass card: enter a Clerk user id, signs in with a `dev:<id>` bearer.
private struct DevSignInCard: View {
    @Binding var devId: String
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DEVELOPER SIGN-IN")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Theme.text40)
            Text("No Clerk key configured. Sign in with a dev user id (requires DEV_AUTH_BYPASS=1 on the backend).")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text52)
                .lineSpacing(2)

            TextField("dev user id", text: $devId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Theme.fillSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline, lineWidth: 1))

            Button(action: onContinue) {
                Text("Continue")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(Theme.background)
            }
            .buttonStyleProminentGlass()
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }
}
