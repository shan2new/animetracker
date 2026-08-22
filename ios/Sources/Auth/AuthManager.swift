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
    ///
    /// Kept only for source compatibility. **Do not call it** — use `identity` instead. It is what
    /// produced "U" on Today (from the raw Clerk id `user_…`) while Profile independently produced
    /// "Y" (from its own fallback label "Your account"): one user, two meaningless letters, one tap
    /// apart. A wrong initial is worse than no initial.
    @available(*, deprecated, message: "Use `identity` — an initial is never derived from an opaque id or from interface copy.")
    var avatarInitial: String {
        displayName.first.map { String($0).uppercased() } ?? "\u{2022}"
    }

    /// The ONE account identity. Both the Today avatar and the Profile monogram read this; neither
    /// derives anything of its own.
    ///
    /// Precedence is strict: a real first name → the local part of an email address → **no letter
    /// at all**, and a `person.fill` symbol in its place. An opaque provider id (`user_2xK…`) and a
    /// piece of interface copy ("Your account", "Signed in", "Developer") are not names and may
    /// never be reduced to a letter.
    struct AccountIdentity: Equatable, Sendable {
        enum Provenance: Equatable, Sendable {
            /// A first name the user gave us.
            case name
            /// The local part of a verified email address.
            case email
            /// Nothing nameable. `initial` is nil; draw the symbol.
            case anonymous
            /// A local dev-bypass session. `#if DEBUG` surfaces only.
            case developer
        }

        let displayName: String
        /// `nil` means "draw `person.fill`", not "draw a bullet".
        let initial: String?
        let provenance: Provenance

        /// The symbol to draw when there is no initial.
        ///
        /// Deprecated as a *drawing*: `AccountDisc` no longer renders a generic person glyph inside
        /// an accent ring — brand colour spent on a placeholder, on the one element that is supposed
        /// to be the user. The constant stays because it is still the right symbol for a list row
        /// or a menu item about the account, where a monogram would be wrong.
        static let fallbackSymbol = "person.fill"

        /// The letter to draw, with the whole fallback chain in one place: the real initial, then
        /// the first letter of whatever label the account is shown under ("Your account" → "Y").
        /// `nil` means there is genuinely nothing nameable and the brand mark is drawn instead.
        var monogram: String? { initial ?? AuthManager.letter(of: displayName) }
    }

    var identity: AccountIdentity {
        switch mode {
        case .clerk:
            if let user = Clerk.shared.user {
                if let name = user.firstName?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let letter = Self.letter(of: name) {
                    return AccountIdentity(displayName: name, initial: letter, provenance: .name)
                }
                if let email = user.emailAddresses.first?.emailAddress,
                   !email.isEmpty {
                    let local = String(email.prefix(while: { $0 != "@" }))
                    return AccountIdentity(displayName: email,
                                           initial: Self.letter(of: local),
                                           provenance: .email)
                }
            }
            return AccountIdentity(displayName: "Your account", initial: nil, provenance: .anonymous)
        case .dev:
            // A `user_2xK…` id is neither a name nor an initial, so it is not `displayName` and
            // it is not a letter. `provenance` is what says this is a dev session; the id itself
            // belongs in a debug affordance, not in the account's heading.
            return AccountIdentity(displayName: "Your account", initial: nil, provenance: .developer)
        }
    }

    /// The first LETTER of a name, or nil. A leading digit, punctuation or emoji is not an initial.
    nonisolated static func letter(of raw: String) -> String? {
        guard let first = raw.trimmingCharacters(in: .whitespacesAndNewlines).first,
              first.isLetter else { return nil }
        return String(first).uppercased()
    }

    // MARK: - TokenProvider

    // Token vending is async: Clerk session tokens are fetched on demand, dev tokens are derived
    // from the stored clerk id. The whole call runs on the main actor (Clerk is @MainActor).
    nonisolated func currentToken() async -> String? {
        await resolveToken()
    }

    /// Whether an identity exists that this backend would accept — asked when there is no token
    /// to send, to tell "signed out" apart from "offline". It must not consult the network: the
    /// whole point is to answer while the network is down.
    ///
    /// Dev mode additionally requires a local backend, because a stored dev id is genuinely
    /// unusable against production — that IS a signed-out state, not a connectivity one.
    nonisolated func hasSession() async -> Bool {
        await currentlyHasSession()
    }

    private func currentlyHasSession() -> Bool {
        switch mode {
        case let .dev(clerkId):
            return !clerkId.isEmpty && AppConfig.isLocalBackend
        case .clerk:
            // The session record is stored on device; it outlives any individual JWT and survives
            // a flight-mode launch. Its existence is exactly the question being asked.
            return Clerk.shared.session != nil
        }
    }

    /// A forced refresh, bypassing Clerk's token cache. Called once per request by
    /// `APIClient` when a 401 comes back, so an expired-but-renewable session recovers invisibly.
    ///
    /// The three answers are deliberately distinct. `.notRefreshable` is FINAL — `dev:<id>` is not
    /// a JWT and has nothing to renew, and a Clerk that returns no token has no session — so a 401
    /// against it ends the session. `.failed` means we could not reach Clerk at all, which says
    /// nothing about the credentials: the caller keeps the session and reports a transport failure.
    nonisolated func refreshedToken() async -> TokenRefreshOutcome {
        await forceRefreshToken()
    }

    private func forceRefreshToken() async -> TokenRefreshOutcome {
        switch mode {
        case .dev:
            return .notRefreshable
        case .clerk:
            do {
                guard let token = try await Clerk.shared.auth.getToken(.init(skipCache: true)) else {
                    return .notRefreshable
                }
                return .token(token)
            } catch {
                return .failed(error)
            }
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
