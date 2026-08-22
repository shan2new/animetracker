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
        // A fresh session answers whatever the last one failed at.
        if isSignedIn { lastError = nil }
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
        lastError = nil
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

    /// The backend rejected our credentials with a **401 that survived a forced token refresh**.
    /// That, and only that, ends a session.
    ///
    /// A 403 must never reach here: a Cloudflare/WAF challenge says nothing about the user's
    /// session, and signing them out on it is the exact regression observed on 2026-08-22.
    /// `APIClient` classifies it as `.infrastructure` and the surface keeps its content —
    /// `APIError.isSessionEnding` is the only predicate a caller may branch on.
    func sessionExpired() {
        guard isSignedIn else { return }
        Task {
            await signOut()
            // A Clerk sign-out that failed locally must not leave us "signed in" against a server
            // that disagrees; the next sign-in re-authenticates either way.
            isSignedIn = false
            lastError = APIError.unauthorized.errorDescription
        }
    }

    // MARK: - Display identity

    /// Best-available human name for the profile UI (Clerk first name → email → mode fallback).
    var displayName: String {
        switch mode {
        case .clerk:
            if let user = Clerk.shared.user {
                if let name = user.firstName, !name.isEmpty { return name }
                if let email = user.emailAddresses.first?.emailAddress, !email.isEmpty { return email }
            }
            return "Signed in"
        case let .dev(clerkId):
            return clerkId.isEmpty ? "Developer" : clerkId
        }
    }

    /// Single-letter avatar initial derived from the display name.
    var avatarInitial: String {
        displayName.first.map { String($0).uppercased() } ?? "•"
    }

    // MARK: - TokenProvider

    // Token vending is async: Clerk session tokens are fetched on demand, dev tokens are derived
    // from the stored clerk id. The whole call runs on the main actor (Clerk is @MainActor).
    nonisolated func currentToken() async -> String? {
        await resolveToken()
    }

    /// A forced refresh, bypassing Clerk's token cache. Called once per request by
    /// `APIClient` when a 401 comes back, so an expired-but-renewable session recovers invisibly.
    ///
    /// Dev mode returns nil on purpose: `dev:<id>` is not a JWT and has nothing to renew, so a
    /// 401 against it is final and the retry would only repeat the same rejection.
    nonisolated func refreshedToken() async -> String? {
        await forceRefreshToken()
    }

    private func forceRefreshToken() async -> String? {
        switch mode {
        case .dev:
            return nil
        case .clerk:
            return try? await Clerk.shared.auth.getToken(.init(skipCache: true))
        }
    }

    private func resolveToken() async -> String? {
        switch mode {
        case let .dev(clerkId):
            // A dev token is only ever accepted by a non-production server, so it must never be
            // sent toward one. In a Release build pointed at production this is what guarantees a
            // stored dev id cannot leak, even if one survived from a Debug run.
            guard AppConfig.isLocalBackend else { return nil }
            return clerkId.isEmpty ? nil : "dev:\(clerkId)"
        case .clerk:
            // `auth.getToken()` returns a fresh session JWT (or nil if signed out).
            return try? await Clerk.shared.auth.getToken()
        }
    }
}
