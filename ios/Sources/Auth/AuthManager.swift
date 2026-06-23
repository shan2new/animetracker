import Foundation
import Observation
import ClerkKit

// Centralizes authentication state and token vending.
//
// Two modes:
//  • Clerk mode (real publishable key present): uses the Clerk iOS SDK for sign-in and
//    session-token retrieval.
//  • Dev mode (no Clerk key, or the user opts in): issues a `dev:<clerkId>` bearer token that
//    the backend accepts when started with DEV_AUTH_BYPASS=1. Lets the app run end-to-end
//    against the local server before real Clerk keys are wired in.
@MainActor
@Observable
final class AuthManager: TokenProvider {
    enum Mode: Equatable {
        case clerk
        case dev(clerkId: String)
    }

    private(set) var mode: Mode
    /// True once we have a usable identity (a Clerk session, or a dev id).
    private(set) var isSignedIn: Bool = false
    /// Surfaced to the UI for inline error display.
    var lastError: String?

    private let devIdDefaultsKey = "anitrack.devClerkId"

    init() {
        // Default to dev mode when no real Clerk key is configured.
        if AppConfig.isClerkConfigured {
            mode = .clerk
        } else {
            let saved = UserDefaults.standard.string(forKey: devIdDefaultsKey)
            mode = .dev(clerkId: saved ?? "")
        }
    }

    // MARK: - Lifecycle

    /// Derive initial sign-in state. Clerk.configure() is called earlier in AniTrackApp.init().
    func bootstrap() async {
        if AppConfig.isClerkConfigured {
            refreshClerkSignInState()
        } else {
            // Dev mode: signed in iff we already have a remembered dev id.
            if case let .dev(clerkId) = mode {
                isSignedIn = !clerkId.isEmpty
            }
        }
    }

    /// Re-derive signed-in state from the current Clerk session.
    func refreshClerkSignInState() {
        isSignedIn = Clerk.shared.session != nil
    }

    // MARK: - Dev bypass

    /// Sign in using a `dev:<clerkId>` bearer for local DEV_AUTH_BYPASS testing.
    func signInDev(clerkId: String) {
        let trimmed = clerkId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "Enter a dev user id."
            return
        }
        UserDefaults.standard.set(trimmed, forKey: devIdDefaultsKey)
        mode = .dev(clerkId: trimmed)
        isSignedIn = true
        lastError = nil
    }

    func signOut() async {
        switch mode {
        case .clerk:
            try? await Clerk.shared.auth.signOut()
            refreshClerkSignInState()
        case .dev:
            UserDefaults.standard.removeObject(forKey: devIdDefaultsKey)
            mode = AppConfig.isClerkConfigured ? .clerk : .dev(clerkId: "")
            isSignedIn = false
        }
    }

    // MARK: - TokenProvider

    // Token vending is async: Clerk session tokens are fetched on demand, dev tokens are derived
    // from the stored clerk id. The whole call runs on the main actor (Clerk is @MainActor).
    nonisolated func currentToken() async -> String? {
        await resolveToken()
    }

    private func resolveToken() async -> String? {
        switch mode {
        case let .dev(clerkId):
            return clerkId.isEmpty ? nil : "dev:\(clerkId)"
        case .clerk:
            // `auth.getToken()` returns a fresh session JWT (or nil if signed out).
            return try? await Clerk.shared.auth.getToken()
        }
    }
}
