# Clerk authentication on Android

**Status:** research decision note · **Written:** 2026-09-04 · **Owner:** Android port
**Scope:** how the Kotlin/Compose port of *Previously.* authenticates against the **same Clerk
instance** the iOS app uses, so an account created on iPhone opens the same library on Android.

---

## 1. Recommendation

**Use Clerk's official native Android SDK. It exists, it is GA, and it is a near one-to-one mirror of
the `clerk-ios` API the app already ships.** No Frontend-API reimplementation, no WebView, no
backend token exchange, and **zero server changes**.

```kotlin
// app/build.gradle.kts
implementation("com.clerk:clerk-android-api:1.1.5")   // core — required
implementation("com.clerk:clerk-android-ui:1.1.5")    // prebuilt Compose AuthView — recommended
```

- **Same instance, same accounts, automatically.** Point the Android app at the *same publishable
  key* as iOS (`pk_test_bGVnaWJsZS1nb2JibGVyLTU3…`, i.e. the `legible-gobbler-57.clerk.accounts.dev`
  instance). Identity lives in Clerk, not in the client, so `sub` — the Clerk user id — is byte-identical
  across platforms and the server's `upsertUser(id.clerkId, …)` finds the existing `users` row.
- **Bearer token** is `Clerk.auth.getToken()` → `ClerkResult<String, ClerkErrorResponse>`; the `String`
  **is** the session JWT. Forced refresh is `getToken(GetTokenOptions(skipCache = true))` — the exact
  analogue of iOS `Clerk.shared.auth.getToken(.init(skipCache: true))`.
- **Do not pass a `template`.** iOS calls `getToken()` with no template, so the server verifies a
  *default* session token. A JWT-template token would carry different claims and is a silent
  divergence.
- **Backend: nothing to do.** `@clerk/backend`'s `verifyToken` verifies against the instance's JWKS
  (or the networkless `CLERK_JWT_KEY`). The token's *origin platform* is not a claim and not checked.
- **Keep the `dev:<clerkId>` bypass**, ported verbatim including the `isLocalBackend` guard, plus one
  Android-only addition: `10.0.2.2` (the emulator's alias for the host machine) must count as local.

Effort estimate: the auth layer is roughly a **1–2 day port**, dominated by re-deriving the
three-way failure taxonomy (`session dead` / `infrastructure` / `offline`), not by Clerk plumbing.

**Confidence: high** on "the SDK exists, is GA, shares accounts, and vends a Bearer JWT". **Medium**
on the exact SSO redirect strings to allowlist and on the `ClerkResult.Failure` → *"is the session
dead or is the network dead"* mapping — both are verify-on-device items, listed in §8.

---

## 2. Evidence

### 2.1 The SDK is real and current

| Fact | Source | Date |
|---|---|---|
| Android SDK **beta** announced | [clerk.com/changelog/2025-08-07-android-sdk-beta](https://clerk.com/changelog/2025-08-07-android-sdk-beta) | 2025-08-07 |
| Android SDK **generally available** ("After a successful beta, the Clerk Android SDK is now generally available") | [clerk.com/changelog/2025-09-11-android-sdk-ga](https://clerk.com/changelog/2025-09-11-android-sdk-ga) | 2025-09-11 |
| **Prebuilt Compose UI components** shipped | [clerk.com/changelog/2025-12-10-android-ui-components](https://clerk.com/changelog/2025-12-10-android-ui-components) | 2025-12-10 |
| Latest release **v1.1.5** | [github.com/clerk/clerk-android/releases](https://github.com/clerk/clerk-android/releases) (GitHub API `releases/latest`, `published_at` `2026-09-03T05:18:12Z`) | 2026-09-03 |
| `CLERK_API_VERSION=1.1.5`, `CLERK_UI_VERSION=1.1.5` | [gradle.properties](https://raw.githubusercontent.com/clerk/clerk-android/main/gradle.properties) | fetched 2026-09-04 |
| Published to Maven Central under **`com.clerk`** | [central.sonatype.com/artifact/com.clerk/clerk-android-api](https://central.sonatype.com/artifact/com.clerk/clerk-android-api/versions) | fetched 2026-09-04 |

**Maturity read.** Releases are ~weekly and substantive, not abandonware: v1.1.0 (2026-08-11)
"cache environment for offline cold start" and "prevent OAuth network failures from crashing";
v1.1.1 (2026-08-12) biometric/trusted-device sign-in; v1.1.4 (2026-08-25) passkeys as a *second*
factor; v1.1.5 (2026-09-03) sign-in-strategy and SSO-cancellation fixes. Roughly one year past GA
with an active fix cadence — comparable to where `clerk-ios` was when this app adopted it.

> Note the version-number history is confusing: the GA changelog (2025-09-11) told users to update
> to `0.1.10`. The line later went `0.1.x → 1.0.x → 1.1.x`. **Always read the version from Maven
> Central / `gradle.properties`, never from a changelog post.**

### 2.2 Toolchain floor

From the SDK's own version catalog ([`gradle/libs.versions.toml`](https://raw.githubusercontent.com/clerk/clerk-android/main/gradle/libs.versions.toml), fetched 2026-09-04) and the
[Android quickstart](https://clerk.com/docs/android/getting-started/quickstart):

| | Value |
|---|---|
| `minSdk` | **24** (Android 7.0) — the SDK's floor; ours may be higher |
| `compileSdk` | 36 |
| JDK / `jvmTarget` | **17** |
| Kotlin | 2.4.10 |
| AGP | 9.4.0 |
| Compose BOM | 2026.06.01 |

The repo catalog also pins `okhttp = 5.4.0` and `retrofit = 3.0.0`, and v1.1.0's notes mention a
Ktor 3.5.2 bump — the catalog covers samples and e2e as well as the library, so **do not assume the
published AAR's transitive HTTP stack from it**; read the POM after adding the dependency
(§8, Q7). Practically: if our app pins OkHttp 4.x, Gradle will resolve upward to 5.x.

### 2.3 Supported flows (all confirmed in docs)

From [Authentication flows — Android](https://clerk.com/docs/android/reference/native-mobile/auth) and the
[Dokka reference for `com.clerk.api.auth.Auth`](https://clerk-android.clerkstage.dev/source/api/com.clerk.api.auth/-auth/index.html):

```kotlin
Clerk.auth.signInWithOAuth(OAuthProvider.GOOGLE)              // Custom Tabs, SDK-managed
Clerk.auth.signInWithIdToken { token = idToken; provider = IdTokenProvider.GOOGLE }  // native, no browser
Clerk.auth.signInWithOtp { email = "a@b.com" }                // email OTP
Clerk.auth.signInWithOtp { phone = "+1…" }                    // SMS OTP
Clerk.auth.signInWithPassword { identifier = "…"; password = "…" }
Clerk.auth.signInWithPasskey()                                // Credential Manager, discoverable passkeys
Clerk.auth.signInWithBiometrics()                             // "Device Trust" (v1.1.1+)
Clerk.auth.signInWithEnterpriseSso { email = "…" }
Clerk.auth.startEmailLinkSignIn("a@b.com")
Clerk.auth.startHostedAuth()                                  // Account Portal in a browser
Clerk.auth.signInWithTicket(ticket)                           // Backend-API-minted sign-in token
```

Everything the iOS app can offer, Android can offer. **Which methods actually appear is an
instance-level setting in the Clerk Dashboard, not a client setting** — so parity is free and
divergence is impossible to introduce by accident from the client side.

### 2.4 Session JWT for the Bearer header

Exact signatures (Dokka, fetched 2026-09-04):

```kotlin
// com.clerk.api.auth.Auth
suspend fun getToken(options: GetTokenOptions? = null): ClerkResult<String, ClerkErrorResponse>

// com.clerk.api.session
data class GetTokenOptions(
    val template: String? = null,
    val skipCache: Boolean = false,      // "bypass the token cache and always fetch from network"
    val expirationBuffer: Long = 10,     // seconds before expiry at which a cached token is considered invalid
)

// also available, session-scoped, returning the richer TokenResource:
suspend fun Session.fetchToken(options: GetTokenOptions = GetTokenOptions()): ClerkResult<TokenResource, ClerkErrorResponse>
```

Sources: [`Auth`](https://clerk-android.clerkstage.dev/source/api/com.clerk.api.auth/-auth/index.html),
[`GetTokenOptions`](https://clerk-android.clerkstage.dev/source/api/com.clerk.api.session/-get-token-options/index.html),
[`fetchToken`](https://clerk-android.clerkstage.dev/source/api/com.clerk.api.session/fetch-token.html),
[Making authenticated requests](https://clerk.com/docs/guides/development/making-requests).

`GetTokenOptions` **already implements the caching policy `TokenRefresher` hand-rolls on iOS**: an
in-SDK cache with a 10 s expiry buffer, plus an explicit `skipCache` escape hatch. The Android port
therefore needs single-flight coalescing only on the *forced-refresh* path, not on every request.

### 2.5 Reactive state — the parity map

| iOS (`clerk-ios` 1.2.4) | Android (`clerk-android` 1.1.5) |
|---|---|
| `Clerk.configure(publishableKey:)` | `Clerk.initialize(context, publishableKey)` |
| `Clerk.shared.isLoaded` (poll ≤3 s in `bootstrap()`) | `Clerk.isInitialized: StateFlow<Boolean>` — *await it, don't poll* |
| `Clerk.shared.session != nil` | `Clerk.session != null` / `Clerk.sessionFlow: StateFlow<Session?>` |
| `Clerk.shared.user` | `Clerk.user` / `Clerk.userFlow: StateFlow<User?>` |
| `for await e in Clerk.shared.auth.events { if case .sessionChanged … }` | `Clerk.auth.events: Flow<AuthEvent>`, `AuthEvent.SessionChanged(session: Session?)` |
| `Clerk.shared.auth.getToken()` | `Clerk.auth.getToken()` |
| `Clerk.shared.auth.getToken(.init(skipCache: true))` | `Clerk.auth.getToken(GetTokenOptions(skipCache = true))` |
| `Clerk.shared.auth.signOut()` | `Clerk.auth.signOut()` |
| `ClerkKitUI.AuthView()` in a `.sheet` | `com.clerk.ui.auth.AuthView(onAuthComplete = …)` |

`AuthEvent` subtypes: `SignedIn(session, user)`, `SignedOut`, `SessionChanged(session?)`,
`SignInStarted`, `SignUpStarted`, `SignInCompleted`, `SignUpCompleted`, `Error(message, throwable?)`
([Dokka](https://clerk-android.clerkstage.dev/source/api/com.clerk.api.auth/-auth-event/index.html)).

### 2.6 Prebuilt UI

```kotlin
@Composable
fun AuthView(
    modifier: Modifier = Modifier,
    clerkTheme: ClerkTheme? = null,
    initialIdentifier: String? = null,
    persistIdentifiers: Boolean = true,
    preferGoogleOneTap: Boolean = true,
    startSocialOAuthAsSignUp: Boolean = false,
    unsafeMetadata: Map<String, Any>? = null,
    isDismissible: Boolean = true,
    onDismiss: (() -> Unit)? = null,
    onAuthComplete: () -> Unit,
)
```

[AuthView reference](https://clerk.com/docs/android/reference/views/authentication/auth-view) ·
[ClerkTheme](https://clerk.com/docs/android/guides/customizing-clerk/clerk-theme) (colors, typography,
plus `lightColors`/`darkColors` that both fall back to `colors`).

This is the direct analogue of the iOS `SignInView`, which presents `ClerkKitUI.AuthView()` in a
sheet. **Recommendation: ship `AuthView` for v1**, themed with a `ClerkTheme` built from
`ThemeColor`/`ThemeType`, exactly as iOS ships Clerk's own sheet. Revisit a custom flow only if the
themed sheet visibly fights the design system (§8, Q3).

---

## 3. Configuration an engineer can paste

### 3.1 Gradle

```kotlin
// app/build.gradle.kts
android {
    namespace = "com.anitrack.app"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.anitrack.app"     // must match the iOS bundle id for the redirect scheme
        minSdk = 26                            // ≥ 24 (the SDK's floor); pick ours on device-coverage data
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { buildConfig = true; compose = true }

    buildTypes {
        debug {
            buildConfigField("String", "API_BASE_URL", "\"http://10.0.2.2:8787\"")
            buildConfigField("String", "CLERK_PUBLISHABLE_KEY", "\"pk_test_bGVnaWJsZS1nb2JibGVyLTU3LmNsZXJrLmFjY291bnRzLmRldiQ\"")
        }
        release {
            buildConfigField("String", "API_BASE_URL", "\"https://anime.cognipin.com\"")
            buildConfigField("String", "CLERK_PUBLISHABLE_KEY", "\"pk_test_bGVnaWJsZS1nb2JibGVyLTU3LmNsZXJrLmFjY291bnRzLmRldiQ\"")
        }
    }
}

dependencies {
    implementation("com.clerk:clerk-android-api:1.1.5")
    implementation("com.clerk:clerk-android-ui:1.1.5")
}
```

> The publishable key is **public by design** (it is in the shipped iOS binary today). It is not a
> secret and belongs in `buildConfigField`, mirroring `project.yml` → `Info.plist` → `AppConfig`.
> `CLERK_SECRET_KEY` must never appear in the app.

### 3.2 Manifest — there is almost nothing to add

```xml
<uses-permission android:name="android.permission.INTERNET" />

<application
    android:name=".PreviouslyApp"
    android:networkSecurityConfig="@xml/network_security_config">
    …
</application>
```

The SDK's own library manifest
([`source/api/src/main/AndroidManifest.xml`](https://raw.githubusercontent.com/clerk/clerk-android/main/source/api/src/main/AndroidManifest.xml))
already declares `INTERNET`, `ACCESS_NETWORK_STATE`, `USE_BIOMETRIC`, an `SSOManagerActivity`
(`singleTask`), and an exported `SSOReceiverActivity` with intent filters for
**`clerk://${applicationId}.callback`** and **`clerk://${applicationId}.oauth`** — so the OAuth
round-trip through Chrome Custom Tabs needs **no app-side intent-filter**. Verified against the
[quickstart sample manifest](https://raw.githubusercontent.com/clerk/clerk-android/main/samples/quickstart/src/main/AndroidManifest.xml),
which contains only `INTERNET` and a plain LAUNCHER activity.

For our `applicationId` the redirect URIs are therefore:

```
clerk://com.anitrack.app.callback
clerk://com.anitrack.app.oauth
```

The SDK's library manifest also ships a **`SharedSessionSyncProvider`** (cross-app session sync,
gated on a matching signing certificate) and a `<queries>` entry for
`com.clerk.api.action.SHARED_SESSION_SYNC`. We ship one app, so this is dead weight — see
`SharedSessionSyncConfig` and §8, Q5.

### 3.3 `res/xml/network_security_config.xml`

The iOS side uses `NSAllowsLocalNetworking`. The Android equivalent:

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="false" />
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">localhost</domain>
        <domain includeSubdomains="false">10.0.2.2</domain>   <!-- emulator → host machine -->
        <domain includeSubdomains="true">192.168.1.0</domain> <!-- or the specific LAN host -->
    </domain-config>
</network-security-config>
```

Two Android-only gotchas, both of which bite the dev-bypass path:

1. **`localhost` on an emulator is the emulator**, not the Mac. The dev server is reached at
   **`10.0.2.2:8787`**. `isLocalBackend` must treat `10.0.2.2` as local (it already would, via the
   `10.*` private-IPv4 rule — but the *default* dev `API_BASE_URL` must be `10.0.2.2`, not `localhost`).
2. **`.local` (mDNS) hostnames may not resolve on Android.** iOS resolves
   `Shantanus-MacBook-Air.local` natively; Android's `InetAddress` path has no mDNS resolver, and
   whether a given device/ROM resolves `.local` is inconsistent. *(Uncertain — verify on a real
   device.)* Prefer the LAN IPv4 or `10.0.2.2` for the Android dev loop.

### 3.4 `Application` init

```kotlin
class PreviouslyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        if (AppConfig.isClerkConfigured) {
            Clerk.initialize(this, publishableKey = BuildConfig.CLERK_PUBLISHABLE_KEY)
        }
    }
}
```

### 3.5 Dashboard configuration (one-time, per instance)

[Deploy to production — Android](https://clerk.com/docs/android/reference/native-mobile/production) ·
[Social connections — Android](https://clerk.com/docs/android/guides/configure/auth-strategies/social-connections/overview)

1. **Native applications** → register the Android app: package name `com.anitrack.app` + the
   **SHA-256 certificate fingerprint** (debug keystore *and* the Play App Signing key). Needed for
   Google One Tap, passkeys, and Digital Asset Links.
2. **Native applications → "Allowlist for mobile SSO redirect"** → add
   `clerk://com.anitrack.app.callback` and `clerk://com.anitrack.app.oauth`. Clerk "ensures that
   security-critical nonces are passed only to allowlisted URLs", so an un-allowlisted scheme fails
   the OAuth round-trip. *(The prose docs say the default is `{bundleIdentifier}://callback`; the
   shipped Android manifest registers the `clerk://…` forms above. Reconcile in the dashboard — §8, Q6.)*
3. Social connections (Google, Apple, …) — **already configured for iOS; nothing to redo**, because
   it is the same instance.

---

## 4. `AuthRepository` — the port of `AuthManager`

Preserves every invariant `AuthManager.swift` documents: the two modes, the three-answer refresh
outcome, `hasSession()` answering without the network, and the `dev:` bearer never crossing toward
a non-local host.

```kotlin
package com.anitrack.auth

import com.clerk.api.Clerk
import com.clerk.api.auth.AuthEvent
import com.clerk.api.network.serialization.ClerkResult
import com.clerk.api.session.GetTokenOptions
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.withTimeoutOrNull

sealed interface AuthMode {
    data object ClerkMode : AuthMode
    data class Dev(val clerkId: String) : AuthMode
}

/** Three answers, deliberately distinct — mirrors iOS `TokenRefreshOutcome`. */
sealed interface TokenRefresh {
    /** A fresh JWT. Retry the request with it. */
    data class Token(val jwt: String) : TokenRefresh
    /** FINAL: there is nothing to renew. A 401 against this ends the session. */
    data object NotRefreshable : TokenRefresh
    /** We could not reach Clerk. Says nothing about the credentials — keep the session. */
    data class Failed(val cause: Throwable?) : TokenRefresh
}

class AuthRepository(private val prefs: DevIdStore) {

    private val _mode = MutableStateFlow<AuthMode>(
        if (AppConfig.isClerkConfigured) AuthMode.ClerkMode
        else AuthMode.Dev(prefs.devClerkId().orEmpty())
    )
    val mode: StateFlow<AuthMode> = _mode.asStateFlow()

    private val _isSignedIn = MutableStateFlow(false)
    val isSignedIn: StateFlow<Boolean> = _isSignedIn.asStateFlow()

    private val _bootstrapped = MutableStateFlow(false)
    val bootstrapped: StateFlow<Boolean> = _bootstrapped.asStateFlow()

    /**
     * The splash holds on `bootstrapped`. Handing off to sign-in while Clerk is still restoring a
     * session shows a returning user the wrong screen — the 2026 iOS regression this guards.
     *
     * Android improves on the iOS 3 s poll: `isInitialized` is a StateFlow, so we AWAIT it.
     */
    suspend fun bootstrap(scope: CoroutineScope) {
        when (_mode.value) {
            is AuthMode.Dev -> {
                _isSignedIn.value = (_mode.value as AuthMode.Dev).clerkId.isNotEmpty()
                _bootstrapped.value = true
            }
            AuthMode.ClerkMode -> {
                withTimeoutOrNull(3_000) { Clerk.isInitialized.first { it } }
                _isSignedIn.value = Clerk.session != null
                _bootstrapped.value = true
                // Follow every session change for the life of the app.
                Clerk.auth.events
                    .filterIsInstance<AuthEvent.SessionChanged>()
                    .onEach { _isSignedIn.value = Clerk.session != null }
                    .launchIn(scope)
            }
        }
    }

    /** No network. Answers "is there an identity this backend would accept". */
    fun hasSession(): Boolean = when (val m = _mode.value) {
        is AuthMode.Dev -> m.clerkId.isNotEmpty() && AppConfig.isLocalBackend
        AuthMode.ClerkMode -> Clerk.session != null
    }

    suspend fun currentToken(): String? = when (val m = _mode.value) {
        is AuthMode.Dev -> {
            // A dev token is only ever accepted by a non-production server, so it must never be
            // sent toward one — even if a stored dev id survived from a debug run.
            if (!AppConfig.isLocalBackend || m.clerkId.isEmpty()) null else "dev:${m.clerkId}"
        }
        AuthMode.ClerkMode ->
            (Clerk.auth.getToken() as? ClerkResult.Success)?.value   // SDK-cached, 10 s expiry buffer
    }

    /** Called once per request by the transport when a 401 comes back. */
    suspend fun refreshedToken(): TokenRefresh = when (_mode.value) {
        is AuthMode.Dev -> TokenRefresh.NotRefreshable   // `dev:<id>` is not a JWT; nothing to renew
        AuthMode.ClerkMode -> when (val r = Clerk.auth.getToken(GetTokenOptions(skipCache = true))) {
            is ClerkResult.Success ->
                r.value.takeIf { it.isNotBlank() }?.let(TokenRefresh::Token) ?: TokenRefresh.NotRefreshable
            is ClerkResult.Failure ->
                // A transport throwable = we never reached Clerk → keep the session.
                // An API error body with no throwable = Clerk answered "no session" → final.
                if (r.throwable != null) TokenRefresh.Failed(r.throwable) else TokenRefresh.NotRefreshable
        }
    }

    /** `false` when the session is still standing afterwards — Profile says so. */
    suspend fun signOut(): Boolean = when (_mode.value) {
        is AuthMode.Dev -> { prefs.clearDevClerkId(); _isSignedIn.value = false; true }
        AuthMode.ClerkMode -> {
            Clerk.auth.signOut()
            _isSignedIn.value = Clerk.session != null
            !_isSignedIn.value
        }
    }

    fun signInDev(clerkId: String) {
        val trimmed = clerkId.trim()
        if (trimmed.isEmpty()) return
        prefs.setDevClerkId(trimmed)
        _mode.value = AuthMode.Dev(trimmed)
        _isSignedIn.value = true
    }
}
```

### `AppConfig.isLocalBackend` — port the address parse, not the prefix test

```kotlin
object AppConfig {
    val apiBaseUrl: HttpUrl =
        BuildConfig.API_BASE_URL.trim().toHttpUrlOrNull() ?: "http://10.0.2.2:8787".toHttpUrl()

    val isClerkConfigured: Boolean =
        BuildConfig.CLERK_PUBLISHABLE_KEY.startsWith("pk_") &&
            !BuildConfig.CLERK_PUBLISHABLE_KEY.contains("REPLACE_ME")

    val isLocalBackend: Boolean by lazy {
        val host = apiBaseUrl.host.lowercase()
        when {
            host == "localhost" || host == "127.0.0.1" || host == "::1" -> true
            host.endsWith(".local") -> true
            else -> isPrivateIpv4(host)          // covers 10.0.2.2 (emulator → host)
        }
    }

    /**
     * BY ADDRESS, never by string prefix. `10.example.com` and `192.168.evil.tld` are ordinary
     * registrable internet hostnames; a startsWith() test would classify them as local and release
     * a `dev:` bearer toward them.
     */
    private fun isPrivateIpv4(host: String): Boolean {
        val parts = host.split(".")
        if (parts.size != 4) return false
        val o = parts.map { it.toIntOrNull() ?: return false }
        if (o.any { it !in 0..255 }) return false
        return when {
            o[0] == 10 -> true
            o[0] == 192 && o[1] == 168 -> true
            o[0] == 172 && o[1] in 16..31 -> true
            else -> false
        }
    }
}
```

---

## 5. Attaching the Bearer, and the 401 dance

The iOS rule: **exactly one code path ends a session** — a 401 that survives a *forced* refresh.
A 403 (Cloudflare/WAF), an HTML body at any status, and an inability to *mint* a token are all
"keep the session".

OkHttp splits this cleanly: an `Interceptor` attaches the token, an `Authenticator` handles the 401
retry (OkHttp calls it only on 401 and retries automatically with whatever request it returns).

```kotlin
class BearerInterceptor(private val auth: AuthRepository) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val req = chain.request()
        if (req.header("X-No-Auth") != null) return chain.proceed(req.newBuilder().removeHeader("X-No-Auth").build())
        // Already off the main thread; getToken() is SDK-cached so this is a memory read in the
        // common case, a network round-trip only near expiry.
        val token = runBlocking { auth.currentToken() }
            ?: return chain.proceed(req)   // no token → let the server 401; the caller decides why
        return chain.proceed(req.newBuilder().header("Authorization", "Bearer $token").build())
    }
}

class ClerkAuthenticator(
    private val auth: AuthRepository,
    private val onSessionEnded: () -> Unit,
) : Authenticator {
    override fun authenticate(route: Route?, response: Response): Request? {
        // Retry ONCE. priorResponse != null means we already replayed this request.
        if (response.priorResponse != null) return null

        return when (val outcome = runBlocking { auth.refreshedToken() }) {
            is TokenRefresh.Token ->
                response.request.newBuilder()
                    .header("Authorization", "Bearer ${outcome.jwt}")
                    .build()

            // FINAL: a 401 that survived a forced refresh. This is the one place a session dies.
            TokenRefresh.NotRefreshable -> { onSessionEnded(); null }

            // We could not reach Clerk. Says nothing about the credentials — keep the session and
            // let the caller report a transport failure.
            is TokenRefresh.Failed -> null
        }
    }
}
```

Two notes:

- `runBlocking` inside an OkHttp interceptor/authenticator is correct here — both run on OkHttp's
  own dispatcher thread, never the main thread.
- **`GetTokenOptions` removes the need for iOS's `actor TokenRefresher`.** Clerk caches the token
  with a 10 s expiry buffer, so the hot path does not stampede. Only add a `Mutex` + short reuse
  window around `refreshedToken()` if a burst of parallel 401s is observed forcing N `skipCache`
  round-trips.
- 403 / HTML-body classification stays entirely in *our* error taxonomy, unchanged from iOS.
  The `Authenticator` is never invoked for a 403, which is exactly right.

---

## 6. Sharing accounts with the iOS app

There is no work to do beyond "use the same publishable key", but it is worth stating why:

1. The publishable key encodes the **Frontend API host**. Base64-decoding the shipped key gives
   `legible-gobbler-57.clerk.accounts.dev$`. Both apps talking to that host talk to one instance,
   one user table, one set of `user_…` ids.
2. Clerk mints the session JWT; `sub` is the Clerk user id. The Android and iOS tokens for the same
   person are indistinguishable at the server other than by `sid` (session id) — Clerk models each
   device as its own session on the same user, which is the desired behaviour.
3. `server/src/auth/identity.ts` calls `verifyToken(token, { jwtKey, secretKey })` and then
   `upsertUser(claims.sub, claims.email)`. It is a pure function of the instance's signing key. **No
   server change, no migration, no new env var.**
4. **Do not use a JWT template on Android.** iOS calls `getToken()` bare; a template changes the
   claim set (and `email` handling), which would silently diverge the two clients.

**The one real risk is instance choice, not platform.** The shipped key is a `pk_test_`
*development* instance. Per [Instances / Environments](https://clerk.com/docs/guides/development/managing-environments),
development instances are **capped at 100 users**, carry "development" prefixes on emails/SMS, and
**users cannot be migrated to a production instance**. If TestFlight/Play beta is expected to pass
100 accounts, or a production instance is coming, cutting it *before* Android ships avoids doing
the account-loss conversation twice. See §8, Q1.

---

## 7. Alternatives considered and rejected

| Option | Why rejected |
|---|---|
| **Talk to Clerk's Frontend API (FAPI) directly over Retrofit** | Technically possible — FAPI is the same HTTP surface the SDK uses — but you inherit the whole client handshake: the rotating client JWT, dev-instance `__clerk_db_jwt` handling, `sign_in`/`sign_up` attempt state machines, OAuth nonce exchange, MFA, passkey challenge/response, secure session persistence, and token refresh. All of that is undocumented-as-a-public-contract and moves (five releases in the last three weeks). It would be a permanent maintenance tax to reproduce a GA SDK. **Only sane as a fallback if the SDK were absent — it isn't.** |
| **Chrome Custom Tabs + hand-rolled OAuth/PKCE to Google/Apple** | Produces a *provider* token, not a Clerk session. You would still have to hand it to Clerk (`signInWithIdToken`) to get a session JWT the backend accepts — so this is strictly extra work on top of the SDK, and it cannot create Clerk-side accounts, do email OTP, or do MFA. |
| **`clerk-js` in a WebView, bridged to native** | Google's OAuth policy rejects sign-in inside embedded WebViews (`disallowed_useragent`), so social login — the primary path — breaks outright. Passkeys and Credential Manager are unavailable. Cookie→native token bridging is fragile, and the result would look and feel like a web page inside a native app, which is the opposite of this port's premise. |
| **Backend-issued token exchange** (server verifies something, mints its own JWT) | Forks identity: the backend would need its own signing key and issuer, and `resolveIdentity`'s deliberate *two*-issuer design (`dev:` vs Clerk) becomes three. It cannot create accounts or run MFA, so you would need Clerk on the client anyway. It also breaks the `assertAuthConfig` boot guard's premise that a production process verifies exactly one kind of real token. |
| **Clerk's `signInWithTicket` + Backend API sign-in tokens** | Not rejected on merit — this *is* the supported escape hatch for a custom server-mediated exchange, and it stays available if a future flow needs it (e.g. a magic hand-off from the web app). Just not needed for ordinary sign-in. |
| **Firebase Auth / AuthO / roll-your-own on Android only** | Would give Android users different user ids from iOS users. Accounts would not be shared — the one hard requirement. |

---

## 8. Open questions needing a human decision

1. **Development instance vs production instance.** The app ships a `pk_test_` key
   (`legible-gobbler-57.clerk.accounts.dev`): 100-user cap, "development" email/SMS prefixes, and
   **no user migration to production**. Cut a production instance (`pk_live_`) before Android ships,
   or knowingly stay on dev for the beta? This also decides which SHA-256 fingerprints get
   registered where, and whether every existing beta account is thrown away at the switch.
2. **Which sign-in methods appear.** Instance-level, so Android inherits whatever iOS shows today —
   confirm that is intended. Specifically: enable **Google One Tap** on Android
   (`preferGoogleOneTap = true`, needs the SHA-256 fingerprint + a Google OAuth client) for the
   native no-browser flow, or leave the Custom Tabs path?
3. **`AuthView` vs a custom flow.** The app is dark-only with a rationed amber accent and a specific
   type ramp. `ClerkTheme` supports colors + typography and `darkColors`. Do we accept Clerk's sheet
   themed to our tokens (parity with iOS, cheapest), or build the custom flow
   (`signInWithOtp`/`signInWithOAuth` + our own Compose screens) to hit the design system exactly?
4. **Account-linking policy.** If a user signs up on iOS with Apple (private relay email) and later
   taps "Continue with Google" on Android, whether those become one account or two is a Clerk
   Dashboard setting. Decide it once, for both platforms.
5. **`SharedSessionSyncProvider`.** The SDK ships a content provider for sharing a session across
   apps signed with the same certificate. We ship one app. Disable it via `SharedSessionSyncConfig`
   (reduces exported surface) or leave the default?
6. **Verify the SSO redirect strings.** Prose docs say `{bundleIdentifier}://callback`; the SDK's
   library manifest registers `clerk://${applicationId}.callback` and `clerk://${applicationId}.oauth`.
   Allowlist the `clerk://` forms, run one real Google sign-in on a device, and record what actually
   worked in this note.
7. **Read the published POM.** Confirm the AAR's transitive HTTP stack (OkHttp/Retrofit vs Ktor) and
   whether it collides with our own client's pin. `./gradlew :app:dependencies --configuration releaseRuntimeClasspath`.
8. **Verify the failure taxonomy empirically.** §4's mapping of `ClerkResult.Failure` → *"session
   dead"* vs *"network dead"* is inferred from the type's shape (`error`, `throwable`, `code`,
   `errorType`), not from documented guarantees. Test both — flight mode, and a server-side session
   revoke — before trusting it, because getting it wrong signs users out when they go offline (the
   exact 2026-08-22 iOS regression).
9. **`.local` hostnames on Android.** Confirm whether the dev-loop LAN hostname resolves on a real
   device; if not, standardise the Android dev `API_BASE_URL` on `10.0.2.2` (emulator) and a literal
   LAN IPv4 (device).
10. **App-side minSdk.** The SDK floor is 24. Pick ours on device-coverage data, the way the iOS 18
    floor was picked — do not copy 24 by default.

---

## Sources

- [Android SDK Beta — Clerk changelog, 2025-08-07](https://clerk.com/changelog/2025-08-07-android-sdk-beta)
- [Android SDK General Availability — Clerk changelog, 2025-09-11](https://clerk.com/changelog/2025-09-11-android-sdk-ga)
- [Prebuilt Android Components — Clerk changelog, 2025-12-10](https://clerk.com/changelog/2025-12-10-android-ui-components)
- [clerk/clerk-android — GitHub](https://github.com/clerk/clerk-android) · [Releases](https://github.com/clerk/clerk-android/releases) · [gradle.properties](https://raw.githubusercontent.com/clerk/clerk-android/main/gradle.properties) · [gradle/libs.versions.toml](https://raw.githubusercontent.com/clerk/clerk-android/main/gradle/libs.versions.toml) · [source/api AndroidManifest.xml](https://raw.githubusercontent.com/clerk/clerk-android/main/source/api/src/main/AndroidManifest.xml) · [samples/quickstart AndroidManifest.xml](https://raw.githubusercontent.com/clerk/clerk-android/main/samples/quickstart/src/main/AndroidManifest.xml)
- [com.clerk:clerk-android-api on Maven Central](https://central.sonatype.com/artifact/com.clerk/clerk-android-api/versions)
- [Android Quickstart — Clerk Docs](https://clerk.com/docs/android/getting-started/quickstart)
- [Install the SDK — Android — Clerk Docs](https://clerk.com/docs/android/reference/native-mobile/installation)
- [Authentication flows — Android — Clerk Docs](https://clerk.com/docs/android/reference/native-mobile/auth)
- [Deploy your Clerk app to production — Android — Clerk Docs](https://clerk.com/docs/android/reference/native-mobile/production)
- [Social connections (OAuth) — Android — Clerk Docs](https://clerk.com/docs/android/guides/configure/auth-strategies/social-connections/overview)
- [Build a custom flow for authenticating with OAuth connections — Clerk Docs](https://clerk.com/docs/android/guides/development/custom-flows/authentication/oauth-connections)
- [Build a custom sign-in flow with email or phone code — Clerk Docs](https://clerk.com/docs/guides/development/custom-flows/authentication/email-sms-otp)
- [AuthView — Android — Clerk Docs](https://clerk.com/docs/android/reference/views/authentication/auth-view)
- [ClerkTheme — Android — Clerk Docs](https://clerk.com/docs/android/guides/customizing-clerk/clerk-theme)
- [Making authenticated requests — Clerk Docs](https://clerk.com/docs/guides/development/making-requests)
- [Instances / Environments — Clerk Docs](https://clerk.com/docs/guides/development/managing-environments)
- Dokka API reference: [`Auth`](https://clerk-android.clerkstage.dev/source/api/com.clerk.api.auth/-auth/index.html) · [`AuthEvent`](https://clerk-android.clerkstage.dev/source/api/com.clerk.api.auth/-auth-event/index.html) · [`Clerk`](https://clerk-android.clerkstage.dev/source/api/com.clerk.api/-clerk/index.html) · [`GetTokenOptions`](https://clerk-android.clerkstage.dev/source/api/com.clerk.api.session/-get-token-options/index.html) · [`fetchToken`](https://clerk-android.clerkstage.dev/source/api/com.clerk.api.session/fetch-token.html) · [`ClerkResult`](https://clerk-android.clerkstage.dev/source/api/com.clerk.api.network.serialization/-clerk-result/index.html)
- In-repo: `server/src/auth/{identity,authConfig,clerk}.ts`, `ios/Sources/Auth/AuthManager.swift`, `ios/project.yml`, `docs/api-contract.md` §Auth, `docs/android-port/spec/networking-auth.md`
