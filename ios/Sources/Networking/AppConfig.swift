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
}
