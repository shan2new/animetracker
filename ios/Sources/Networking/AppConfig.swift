import Foundation

// Reads build-time configuration from Info.plist (populated from xcconfig / project.yml).
enum AppConfig {
    /// Backend base URL. Defaults to the local dev server if the plist value is missing/blank.
    static var apiBaseURL: URL {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let url = URL(string: raw), !raw.isEmpty, url.scheme != nil {
            return url
        }
        return URL(string: "http://localhost:8787")!
    }

    /// Clerk publishable key. Treated as "unconfigured" if blank or still the placeholder.
    static var clerkPublishableKey: String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "ClerkPublishableKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw
    }

    /// True when a real Clerk key has been provided. When false, the app offers a dev-bypass
    /// sign-in that authenticates against the local backend's `DEV_AUTH_BYPASS` mode.
    static var isClerkConfigured: Bool {
        let key = clerkPublishableKey
        return key.hasPrefix("pk_") && !key.contains("REPLACE_ME")
    }

    /// True when `apiBaseURL` points at a machine on this desk: loopback, a Bonjour `.local`
    /// name, or an RFC-1918 address.
    ///
    /// This is the boundary the `dev:` bearer must never cross. The server refuses dev tokens in
    /// production, but a client that would still SEND one toward a production host is a second
    /// mistake waiting to happen — so the token is withheld here too, and the developer sign-in
    /// affordance is hidden against a non-local base URL even in a Debug build.
    static var isLocalBackend: Bool {
        guard let host = apiBaseURL.host?.lowercased() else { return false }
        if host == "localhost" || host == "127.0.0.1" || host == "::1" { return true }
        if host.hasSuffix(".local") { return true }
        if host.hasPrefix("192.168.") || host.hasPrefix("10.") { return true }
        // 172.16.0.0 – 172.31.255.255
        if host.hasPrefix("172.") {
            let second = host.dropFirst("172.".count).prefix(while: { $0 != "." })
            if let n = Int(second), (16...31).contains(n) { return true }
        }
        return false
    }
}
