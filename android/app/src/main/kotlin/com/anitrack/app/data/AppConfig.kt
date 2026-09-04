package com.anitrack.app.data

import com.anitrack.app.BuildConfig
import java.net.URI
import java.util.Locale
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/*
 * BUILD-TIME CONFIGURATION — the port of `ios/Sources/Networking/AppConfig.swift`.
 *
 * iOS reads five keys out of `Info.plist`, each substituted at build time from a build setting in
 * `project.yml`. Nothing is read from the environment at runtime; every value is baked into the
 * bundle. The Android analogue is `buildConfigField` per build type, declared in
 * `app/build.gradle.kts` — the chain is
 *
 *     build.gradle.kts  buildConfigField("String", "API_BASE_URL", …)
 *           ↓ (generated at build time)
 *     com.anitrack.app.BuildConfig.API_BASE_URL
 *           ↓ (trimmed, validated)
 *     AppConfig.<accessor>
 *
 * Two rules carry across from the Swift, and neither is cosmetic:
 *
 *  1. A BLANK OR PLACEHOLDER VALUE IS `null`, NEVER A STRING. "A placeholder URL baked into a
 *     shipped string is a broken Privacy Policy link, which is itself a rejection" (App Store
 *     guideline 5.1.1; Play's Data safety form asks for the same link). The screen omits a row
 *     rather than drawing one that goes nowhere.
 *
 *  2. [isLocalBackend] IS A SECURITY BOUNDARY, NOT A CONVENIENCE. It decides whether the auth layer
 *     will vend a `dev:<clerkId>` bearer at all, whether a stored dev id counts as a session, and
 *     whether the developer sign-in card is drawn. It therefore parses RFC-1918 BY ADDRESS and
 *     never by string prefix.
 */
public object AppConfig {

    /**
     * Where the app looks when the configured base URL is blank or unparseable.
     *
     * **`10.0.2.2`, not `localhost`** — the one deliberate divergence from iOS's
     * `http://localhost:8787`. On an Android emulator `localhost` is the *emulated device*, so a
     * loopback fallback points the app at itself and every request fails with `ECONNREFUSED`;
     * `10.0.2.2` is the emulator's alias for the host machine's loopback, which is what the iOS
     * simulator gets from `localhost` for free (it shares the Mac's network stack). Same intent —
     * "fall back to the dev server on this desk" — expressed in the Android idiom.
     *
     * It is also inside `10.0.0.0/8`, so [isLocalBackend] answers `true` for it without a special
     * case.
     */
    private const val FALLBACK_BASE_URL: String = "http://10.0.2.2:8787"

    /** A value still carrying this is configuration nobody filled in. */
    private const val PLACEHOLDER: String = "REPLACE_ME"

    /**
     * The backend base URL.
     *
     * iOS accepts any string that `URL(string:)` parses and that carries a scheme. Here the test is
     * `HttpUrl` parsing, which additionally requires the scheme to be `http` or `https` — the only
     * two this client can speak, so a `ftp://` base is a misconfiguration either way and is better
     * caught here than at the first request.
     *
     * The returned URL always ends in a path separator. Retrofit rejects a `baseUrl` whose last
     * path segment is non-empty, and every route in [com.anitrack.app.data.api.AniTrackApi] is
     * declared with a LEADING SLASH so it resolves against the authority and discards any base
     * path — the same resolution `URL(string: "/search", relativeTo: base)` performs on iOS. The
     * normalisation below therefore only exists to satisfy Retrofit's constructor check; it can
     * never change which URL a request reaches.
     */
    public val apiBaseUrl: HttpUrl by lazy {
        val raw = BuildConfig.API_BASE_URL.trim()
        val parsed = raw.takeIf { it.isNotEmpty() }?.toHttpUrlOrNull()
        (parsed ?: FALLBACK_BASE_URL.toHttpUrlOrNull()!!).withTrailingSlash()
    }

    /** Clerk publishable key. Blank or placeholder is "unconfigured", never an error. */
    public val clerkPublishableKey: String
        get() = BuildConfig.CLERK_PUBLISHABLE_KEY.trim()

    /**
     * True when a real Clerk key has been provided.
     *
     * This one boolean decides the whole auth mode — Clerk, or the dev bypass that authenticates
     * against a local backend running `DEV_AUTH_BYPASS` — and whether Clerk is initialised at all.
     */
    public val isClerkConfigured: Boolean
        get() = clerkPublishableKey.let { it.startsWith("pk_") && !it.contains(PLACEHOLDER) }

    /** Privacy Policy URL, or null when the build did not configure one. */
    public val privacyUrl: String?
        get() = configuredUrl(BuildConfig.PRIVACY_POLICY_URL)

    /** Terms of Use URL, or null when the build did not configure one. */
    public val termsUrl: String?
        get() = configuredUrl(BuildConfig.TERMS_URL)

    /** Support contact address. An address without an `@` is not an address. */
    public val supportEmail: String?
        get() = configuredString(BuildConfig.SUPPORT_EMAIL)?.takeIf { it.contains("@") }

    /** [supportEmail] as a `mailto:` URI, for an `ACTION_SENDTO` intent. */
    public val supportUrl: String?
        get() = supportEmail?.let { "mailto:$it" }

    /**
     * True when [apiBaseUrl] points at a machine on this desk: loopback, the emulator's host alias,
     * a Bonjour `.local` name, or an RFC-1918 address.
     *
     * **This is the boundary a `dev:` bearer must never cross.** The server refuses dev tokens in
     * production, but a client that would still SEND one toward a production host is a second
     * mistake waiting to happen — so the token is withheld here too, and the developer sign-in
     * affordance is hidden against a non-local base URL even in a debug build.
     */
    public val isLocalBackend: Boolean
        get() {
            val host = apiBaseUrl.host.lowercase(Locale.ROOT)
            if (host == "localhost" || host == "127.0.0.1" || host == "::1") return true
            if (host.endsWith(".local")) return true
            return isPrivateIPv4(host)
        }

    /**
     * RFC-1918 BY ADDRESS, never by string prefix.
     *
     * `10.example.com` and `192.168.evil.tld` are ordinary internet hostnames that anyone can
     * register; a `startsWith` test would classify them as local and release a `dev:` bearer toward
     * them.
     */
    private fun isPrivateIPv4(host: String): Boolean {
        // Empty subsequences are KEPT (Swift passes `omittingEmptySubsequences: false`), so
        // "10..0.1" fails the parse rather than collapsing into three components.
        val parts = host.split('.')
        if (parts.size != 4) return false
        val octets = parts.mapNotNull { it.toIntOrNull() }
        if (octets.size != 4 || octets.any { it !in 0..255 }) return false
        return when {
            octets[0] == 10 -> true                            // 10.0.0.0/8
            octets[0] == 192 && octets[1] == 168 -> true       // 192.168.0.0/16
            octets[0] == 172 && octets[1] in 16..31 -> true    // 172.16.0.0/12
            else -> false
        }
    }

    /** Trimmed, or null when blank or still the placeholder. */
    private fun configuredString(raw: String?): String? {
        val value = raw?.trim().orEmpty()
        return if (value.isEmpty() || value.contains(PLACEHOLDER)) null else value
    }

    /**
     * [configuredString] that also parses and carries a scheme — the port of iOS's
     * `URL(string:) + url.scheme != nil`. `java.net.URI` rather than `HttpUrl` because a legal link
     * is not required to be http(s) in principle, and the check being made is "is this a URL at
     * all", not "can this client fetch it".
     */
    private fun configuredUrl(raw: String?): String? {
        val value = configuredString(raw) ?: return null
        val scheme = try {
            URI(value).scheme
        } catch (e: java.net.URISyntaxException) {
            null
        }
        return if (scheme.isNullOrEmpty()) null else value
    }

    /** Retrofit requires a base URL whose last path segment is empty. */
    private fun HttpUrl.withTrailingSlash(): HttpUrl =
        if (encodedPath.endsWith("/")) this else newBuilder().addPathSegment("").build()
}
