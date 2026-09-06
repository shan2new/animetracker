package com.anitrack.app.data.auth

import android.content.Context
import android.content.SharedPreferences
import com.anitrack.app.BuildConfig
import com.anitrack.app.data.AppConfig
import com.anitrack.app.data.api.ApiError
import com.anitrack.app.data.api.TokenProvider
import com.anitrack.app.data.api.TokenRefreshOutcome
import com.anitrack.model.copy.Copy
import com.clerk.api.Clerk
import com.clerk.api.auth.AuthEvent
import com.clerk.api.network.serialization.ClerkResult
import com.clerk.api.session.GetTokenOptions
import com.clerk.api.ui.ClerkTheme
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

// =====================================================================================
// IDENTITY — the port of `ios/Sources/Auth/AuthManager.swift`.
//
// Two modes:
//  • Clerk mode (a real publishable key is configured): the Clerk Android SDK owns sign-in and
//    session-token retrieval. Same publishable key as iOS, therefore the same instance, the same
//    `user_…` ids and the same libraries — an account created on iPhone opens here.
//  • Dev mode (no Clerk key): issues a `dev:<clerkId>` bearer the backend accepts when started
//    with DEV_AUTH_BYPASS=1, so the app runs end to end against the local server before real
//    Clerk keys are wired in. This is how every Android QA run authenticates
//    (`http://10.0.2.2:8787`, the emulator's alias for the development machine).
//
// THE ONE RULE THIS FILE EXISTS TO PROTECT: exactly one code path in the whole client ends a
// session — a 401 that survived a FORCED token refresh. A 403, an HTML body at any status, and an
// inability to *mint* a token are all "keep the session". Signing a user out for being offline is
// the 2026-08-22 regression, and `TokenRefreshOutcome`'s three answers are how that stays fixed.
//
// THREADING (PLAN R12). On iOS every member here is `@MainActor`, because Clerk's iOS SDK is, and
// each `TokenProvider` method is a `nonisolated` wrapper that hops to the main actor and is then
// awaited from a background transport. The Clerk Android SDK is not main-confined: `Clerk.session`
// / `Clerk.user` are StateFlow reads and `getToken`/`signOut` are ordinary suspend functions. So
// this class is THREAD-SAFE rather than main-confined — every piece of mutable state is a
// `MutableStateFlow` — and nothing here forces the transport onto `Dispatchers.Main`.
// =====================================================================================

// The gate's strings live in `Copy.Auth` (`:model`, `copy/CopyAuth.kt`); the wordmark and the
// tagline it used to declare are `Copy.Brand`'s, which is the one place the app's name is spelled.


// -------------------------------------------------------------------------------------
// Where the dev id is remembered
// -------------------------------------------------------------------------------------

/**
 * The one persisted value this layer owns: the dev-bypass clerk id.
 *
 * An interface rather than a direct `SharedPreferences` read so [AuthManager] is constructible in
 * a unit test without a `Context`, mirroring the injectable `URLSession` the iOS transport takes.
 *
 * **Deliberately synchronous**, which is why this is `SharedPreferences` and not `DataStore`
 * (`spec/networking-auth.md` §13.1 suggests DataStore for the preference layer generally).
 * [AuthManager.hasSession] must answer "is there an identity at all" *without suspending and
 * without touching the network* — "the whole point is to answer while the network is down" — and
 * the mode it answers from is resolved once, at construction. A `Flow`-shaped store would make
 * that answer arrive a frame late, which is the difference between "signed out" and "on a train".
 * The value is not a secret (it is only ever sent to a LAN host), so no encrypted store is needed.
 */
interface DevIdStore {
    fun devClerkId(): String?

    fun setDevClerkId(id: String)

    fun clearDevClerkId()
}

/** The shipping [DevIdStore]. The key is iOS's, verbatim. */
class SharedPrefsDevIdStore(context: Context) : DevIdStore {

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    override fun devClerkId(): String? = prefs.getString(KEY, null)

    override fun setDevClerkId(id: String) {
        prefs.edit().putString(KEY, id).apply()
    }

    override fun clearDevClerkId() {
        prefs.edit().remove(KEY).apply()
    }

    private companion object {
        const val FILE = "previously.auth"

        /** iOS `UserDefaults` key, kept identical so the two apps' debug docs read the same. */
        const val KEY = "anitrack.devClerkId"
    }
}

// -------------------------------------------------------------------------------------
// The transport's view of identity
// -------------------------------------------------------------------------------------

/** Which issuer is vending this app's bearer token. */
sealed interface AuthMode {

    /** A real Clerk publishable key is configured; the SDK owns the session. */
    data object ClerkMode : AuthMode

    /** No Clerk key: a `dev:<clerkId>` bearer, accepted only by a non-production backend. */
    data class Dev(val clerkId: String) : AuthMode
}

// `TokenProvider` and its three-answer `TokenRefreshOutcome` are the transport's contract and live
// with it, in `data/api/ApiClient.kt`. [AuthManager] is the one implementation. The three answers
// exist because "offline, a Clerk session still exists on this device; its ~60 s JWT does not. The
// two must never be confused: one is a signed-out user, the other is a user on a train."

// -------------------------------------------------------------------------------------
// Display identity
// -------------------------------------------------------------------------------------

/**
 * The ONE account identity. Both the Today avatar and the Profile monogram read this; neither
 * derives anything of its own.
 *
 * Precedence is strict: a real first name → the local part of an email address → **no letter at
 * all**. An opaque provider id (`user_2xK…`) and a piece of interface copy ("Your account",
 * "Signed in", "Developer") are not names and may never be reduced to a letter.
 *
 * iOS's `avatarInitial` is **deprecated and deliberately not ported**: "It is what produced 'U' on
 * Today (from the raw Clerk id `user_…`) while Profile independently produced 'Y' (from its own
 * fallback label 'Your account'): one user, two meaningless letters, one tap apart. A wrong
 * initial is worse than no initial."
 */
data class AccountIdentity(
    val displayName: String,
    /** `null` means "there is no letter", not "draw a bullet". */
    val initial: String?,
    val provenance: Provenance,
) {

    enum class Provenance {
        /** A first name the user gave us. */
        Name,

        /** The local part of a verified email address. */
        Email,

        /** Nothing nameable. */
        Anonymous,

        /** A local dev-bypass session. Named as such on debug surfaces only. */
        Developer,
    }

    /**
     * The letter to draw, with the whole fallback chain in one place: the real initial, then the
     * first letter of whatever label the account is shown under ("Your account" → "Y").
     *
     * Note what this means and do not "fix" it: because both [Provenance.Anonymous] and
     * [Provenance.Developer] carry the display name "Your account", the chain still yields "Y" and
     * a `null` monogram is unreachable in practice for them. Ported exactly as written.
     */
    val monogram: String? get() = initial ?: AuthManager.letter(displayName)

    /**
     * The line under the name on Profile.
     *
     * "'Developer session' is a debug string one build configuration away from a TestFlight
     * screenshot, so it is gated. A Release build that somehow reaches dev mode says the true
     * thing instead of the embarrassing one."
     */
    val provenanceLabel: String?
        get() = if (provenance == Provenance.Developer && BuildConfig.DEBUG) {
            DEVELOPER_SESSION
        } else {
            // "Signed in" under a name on the account sheet names nothing the sheet does not
            // already say (i1): the line is drawn only for the developer session.
            null
        }

    companion object {

        /**
         * The symbol to draw where a monogram would be wrong — a list row or a menu item about the
         * account. **`AccountDisc` never draws it**: brand colour spent on a generic person glyph,
         * on the one element that is supposed to be the user.
         *
         * A Material Symbols name (`spec/icon-mapping.md` row 28), not SF's `person.fill` — the
         * icon vocabulary is `PreviouslyIcons.PersonFilled`, and `account_circle` is wrong because
         * it draws its own disc and the app already drew one.
         */
        const val FALLBACK_SYMBOL = "person"

        private const val DEVELOPER_SESSION = "Developer session"

        /** What the account is called when it has no name of its own. Never reduced to a letter. */
        internal const val YOUR_ACCOUNT = "Your account"

        /** Clerk mode with no user object at all. */
        internal const val SIGNED_IN = "Signed in"

        /** Dev mode with no id stored yet. */
        internal const val DEVELOPER = "Developer"
    }
}

// -------------------------------------------------------------------------------------
// Configuration
// -------------------------------------------------------------------------------------

/**
 * Configure Clerk. **Call this from `Application.onCreate()`, before anything constructs an
 * [AuthManager]** — it is the analogue of iOS calling `Clerk.configure(publishableKey:)`
 * synchronously in `AniTrackApp.init()`, "before the view hierarchy builds", because "accessing
 * `Clerk.shared` without calling `configure()` first triggers an assertion failure."
 *
 * A no-op when no real key is configured, which is the same boolean [AuthManager] uses to decide
 * it is in dev mode — so the two can never disagree about whether the Clerk singleton is live.
 *
 * @param theme pass `previouslyClerkTheme()` (ui/auth/SignInScreen.kt) so a Clerk surface reached
 *   from anywhere — not only the gate — arrives wearing this app's palette rather than Material's
 *   light defaults. Typed as a parameter rather than imported here so the data layer keeps no
 *   dependency on the UI layer.
 */
fun initializeClerk(context: Context, theme: ClerkTheme?) {
    if (!AppConfig.isClerkConfigured) return
    Clerk.initialize(context, BuildConfig.CLERK_PUBLISHABLE_KEY, theme = theme)
}

// -------------------------------------------------------------------------------------
// AuthManager
// -------------------------------------------------------------------------------------

/**
 * Authentication state and token vending.
 *
 * **Clerk must already be initialised** when this is constructed in [AuthMode.ClerkMode] — see
 * [initializeClerk], which `Application.onCreate()` calls. Nothing in this class touches the Clerk
 * singleton unless [AppConfig.isClerkConfigured] is true, which is the same boolean that gates the
 * initialise call.
 *
 * @param store where the dev-bypass id is remembered.
 * @param scope the application-lifetime scope. Two things outlive any one caller: the session
 *   watch started by [bootstrap], and the sign-out [sessionExpired] fires. On iOS both are
 *   unstructured `Task`s owned by this object; here they are owned by the scope that owns it.
 */
class AuthManager(
    private val store: DevIdStore,
    private val scope: CoroutineScope,
) : TokenProvider {

    private val _mode = MutableStateFlow<AuthMode>(
        // Default to dev mode when no real Clerk key is configured.
        if (AppConfig.isClerkConfigured) {
            AuthMode.ClerkMode
        } else {
            AuthMode.Dev(clerkId = store.devClerkId().orEmpty())
        },
    )
    val mode: StateFlow<AuthMode> = _mode.asStateFlow()

    /** True once we have a usable identity (a Clerk session, or a dev id). */
    private val _isSignedIn = MutableStateFlow(false)
    val isSignedIn: StateFlow<Boolean> = _isSignedIn.asStateFlow()

    /** Surfaced to the UI for inline error display. */
    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError.asStateFlow()

    /**
     * Set once the first sign-in answer is known. The root holds the splash on it: handing off to
     * the sign-in screen while Clerk is still restoring a session would show a returning user the
     * wrong screen for a beat, or for good.
     */
    private val _bootstrapped = MutableStateFlow(false)
    val bootstrapped: StateFlow<Boolean> = _bootstrapped.asStateFlow()

    private var sessionWatch: Job? = null

    // MARK: - Lifecycle

    /**
     * Derive initial sign-in state, then follow every session change Clerk reports for the life of
     * the app.
     *
     * "The session used to be read exactly once, the instant this ran — before Clerk had
     * necessarily restored it — and never re-derived, so a returning user could land on sign-in
     * with a valid session and nothing to correct it."
     *
     * [bootstrapped] is set **whether or not** Clerk finished loading: the wait is a courtesy, not
     * a gate. Three seconds is the ceiling, exactly as on iOS.
     *
     * **The one mechanical divergence, and it is an improvement:** iOS polls `Clerk.shared.isLoaded`
     * every 80 ms because it has no signal to await. `Clerk.isInitialized` on Android is a
     * `StateFlow<Boolean>`, so this AWAITS it (`research/clerk-android.md` §4) — same 3 s ceiling,
     * same "set it regardless" contract, without up to 80 ms of dead time on a fast restore.
     */
    suspend fun bootstrap() {
        when (val current = _mode.value) {
            is AuthMode.Dev -> {
                // Dev mode: signed in iff we already have a remembered dev id.
                _isSignedIn.value = current.clerkId.isNotEmpty()
                _bootstrapped.value = true
            }

            AuthMode.ClerkMode -> {
                withTimeoutOrNull(CLERK_LOAD_TIMEOUT_MS) { Clerk.isInitialized.first { it } }
                refreshClerkSignInState()
                _bootstrapped.value = true
                sessionWatch?.cancel()
                sessionWatch = Clerk.auth.events
                    .filterIsInstance<AuthEvent.SessionChanged>()
                    .onEach { refreshClerkSignInState() }
                    .launchIn(scope)
            }
        }
    }

    /** Re-derive signed-in state from the current Clerk session. */
    fun refreshClerkSignInState() {
        val signedIn = Clerk.session != null
        _isSignedIn.value = signedIn
        // A fresh session answers whatever the last one failed at.
        if (signedIn) _lastError.value = null
    }

    // MARK: - Dev bypass

    /**
     * Sign in using a `dev:<clerkId>` bearer for local DEV_AUTH_BYPASS testing.
     *
     * An empty id changes no state at all — it only reports itself, so a mistyped Continue cannot
     * leave the app "signed in" as nobody.
     */
    fun signInDev(clerkId: String) {
        val trimmed = clerkId.trim()
        if (trimmed.isEmpty()) {
            _lastError.value = Copy.Auth.ENTER_DEV_USER_ID
            return
        }
        store.setDevClerkId(trimmed)
        _mode.value = AuthMode.Dev(clerkId = trimmed)
        _isSignedIn.value = true
        _lastError.value = null
    }

    /**
     * `false` when the session is still standing afterwards — Clerk could not end it (no
     * connection, usually).
     *
     * "The caller says so; before, the spinner simply stopped and the Profile sheet sat there
     * signed in with nothing to explain why."
     */
    suspend fun signOut(): Boolean {
        _lastError.value = null
        return when (_mode.value) {
            AuthMode.ClerkMode -> {
                // Errors are swallowed on purpose: the question this function answers is "did the
                // session end", and `refreshClerkSignInState` answers it from the session itself
                // rather than from whether a call threw.
                //
                // **Not `runCatching`.** `signOut` is an ordinary suspend function, and
                // `runCatching` around a suspending call also swallows the `CancellationException`
                // thrown while it is suspended — after which this coroutine keeps running, writes
                // `_isSignedIn` and returns a Boolean into a caller that has already been
                // cancelled. Cancellation is not an error and must leave by the normal route; only
                // the swallow of *ordinary* failures is the intent here.
                try {
                    Clerk.auth.signOut()
                } catch (cancellation: CancellationException) {
                    throw cancellation
                } catch (_: Throwable) {
                    // See above: the session, not the call, is the answer.
                }
                refreshClerkSignInState()
                !_isSignedIn.value
            }

            is AuthMode.Dev -> {
                store.clearDevClerkId()
                _mode.value =
                    if (AppConfig.isClerkConfigured) AuthMode.ClerkMode else AuthMode.Dev(clerkId = "")
                _isSignedIn.value = false
                true
            }
        }
    }

    /**
     * The backend rejected our credentials with a **401 that survived a forced token refresh**.
     * That, and only that, ends a session.
     *
     * A 403 must never reach here: a Cloudflare/WAF challenge says nothing about the user's
     * session, and signing them out on it is the exact regression observed on 2026-08-22. The
     * transport classifies it as infrastructure and the surface keeps its content — the error
     * type's own `isSessionEnding` is the only predicate a caller may branch on.
     */
    fun sessionExpired() {
        if (!_isSignedIn.value) return
        scope.launch {
            signOut()
            // A Clerk sign-out that failed locally must not leave us "signed in" against a server
            // that disagrees; the next sign-in re-authenticates either way.
            _isSignedIn.value = false
            // iOS: `APIError.unauthorized.errorDescription`. Read from the error rather than from
            // the copy table directly, so the gate and the transport can never say two things
            // about one event.
            _lastError.value = ApiError.Unauthorized.userMessage
        }
    }

    // MARK: - Display identity

    /** Best-available human name for the profile UI (Clerk first name → email → mode fallback). */
    val displayName: String
        get() = when (val current = _mode.value) {
            AuthMode.ClerkMode -> {
                val user = Clerk.user
                val first = user?.firstName?.takeIf { it.isNotEmpty() }
                val email = user?.emailAddresses?.firstOrNull()?.emailAddress?.takeIf { it.isNotEmpty() }
                first ?: email ?: AccountIdentity.SIGNED_IN
            }

            is AuthMode.Dev ->
                current.clerkId.ifEmpty { AccountIdentity.DEVELOPER }
        }

    /** The ONE account identity — see [AccountIdentity]. */
    val identity: AccountIdentity
        get() = when (_mode.value) {
            AuthMode.ClerkMode -> {
                val user = Clerk.user
                val name = user?.firstName?.trim()
                val nameLetter = name?.let { letter(it) }
                // `.first`, not the primary address: iOS reads `emailAddresses.first`, and the two
                // differ for an account with several addresses. Ported as written.
                val email = user?.emailAddresses?.firstOrNull()?.emailAddress?.takeIf { it.isNotEmpty() }
                when {
                    name != null && nameLetter != null ->
                        AccountIdentity(name, nameLetter, AccountIdentity.Provenance.Name)

                    email != null ->
                        AccountIdentity(
                            displayName = email,
                            initial = letter(email.substringBefore('@')),
                            provenance = AccountIdentity.Provenance.Email,
                        )

                    else -> AccountIdentity(
                        displayName = AccountIdentity.YOUR_ACCOUNT,
                        initial = null,
                        provenance = AccountIdentity.Provenance.Anonymous,
                    )
                }
            }

            // A `user_2xK…` id is neither a name nor an initial, so it is not `displayName` and it
            // is not a letter. `provenance` is what says this is a dev session; the id itself
            // belongs in a debug affordance, not in the account's heading.
            is AuthMode.Dev -> AccountIdentity(
                displayName = AccountIdentity.YOUR_ACCOUNT,
                initial = null,
                provenance = AccountIdentity.Provenance.Developer,
            )
        }

    /**
     * [identity] as a stream, for the surfaces that draw it.
     *
     * iOS gets this free from `@Observable`: `identity` reads `Clerk.shared.user`, and SwiftUI
     * re-evaluates whoever touched it. Compose has no such dependency tracking across an SDK
     * boundary, so the two inputs are combined explicitly.
     *
     * `by lazy` because Clerk's flows may not be touched before `Clerk.initialize` — the first read
     * of this happens from a composition, long after the application object has run.
     */
    val identityFlow: StateFlow<AccountIdentity> by lazy {
        val source: Flow<Unit> =
            if (AppConfig.isClerkConfigured) {
                combine(_mode, Clerk.userFlow) { _, _ -> Unit }
            } else {
                _mode.map { }
            }
        source
            .map { identity }
            .stateIn(scope, SharingStarted.Eagerly, identity)
    }

    // MARK: - TokenProvider

    /**
     * The bearer for the next request.
     *
     * Clerk's own token cache does the coalescing iOS hand-rolls: `GetTokenOptions` carries a 10 s
     * expiry buffer, so in the common case this is a memory read and only a round-trip near expiry.
     */
    override suspend fun currentToken(): String? = when (val current = _mode.value) {
        is AuthMode.Dev -> {
            // A dev token is only ever accepted by a non-production server, so it must never be
            // SENT toward one. In a release build pointed at production this is what guarantees a
            // stored dev id cannot leak, even if one survived from a debug run.
            if (!AppConfig.isLocalBackend || current.clerkId.isEmpty()) null
            else "$DEV_TOKEN_PREFIX${current.clerkId}"
        }

        // No `template`: iOS calls `getToken()` bare, so the server verifies a DEFAULT session
        // token. A JWT-template token carries a different claim set and would silently diverge the
        // two clients against one backend.
        AuthMode.ClerkMode -> when (val result = Clerk.auth.getToken()) {
            // Blank is treated as absent: "Bearer " is not a credential, and the transport's
            // pre-flight guard is the place that decides whether "no token" means signed out or
            // offline. iOS gets this free — its `getToken()` returns an optional.
            is ClerkResult.Success -> result.value.takeIf { it.isNotBlank() }
            is ClerkResult.Failure -> null
        }
    }

    /**
     * Whether an identity exists that this backend would accept — asked when there is no token to
     * send, to tell "signed out" apart from "offline". It must not consult the network: the whole
     * point is to answer while the network is down.
     *
     * Dev mode additionally requires a local backend, because a stored dev id is genuinely
     * unusable against production — that IS a signed-out state, not a connectivity one.
     */
    override suspend fun hasSession(): Boolean = when (val current = _mode.value) {
        is AuthMode.Dev -> current.clerkId.isNotEmpty() && AppConfig.isLocalBackend

        // The session record is stored on device; it outlives any individual JWT and survives a
        // flight-mode launch. Its existence is exactly the question being asked.
        AuthMode.ClerkMode -> Clerk.session != null
    }

    /**
     * A forced refresh, bypassing Clerk's token cache. Called at most once per request by the
     * transport when a 401 comes back, so an expired-but-renewable session recovers invisibly.
     */
    override suspend fun refreshedToken(): TokenRefreshOutcome = when (_mode.value) {
        // `dev:<id>` is not a JWT and has nothing to renew.
        is AuthMode.Dev -> TokenRefreshOutcome.NotRefreshable

        AuthMode.ClerkMode ->
            when (val result = Clerk.auth.getToken(GetTokenOptions(skipCache = true))) {
                is ClerkResult.Success ->
                    result.value.takeIf { it.isNotBlank() }
                        ?.let { TokenRefreshOutcome.Token(it) }
                        ?: TokenRefreshOutcome.NotRefreshable

                // A throwable means we never reached Clerk, so the session is KEPT. An API error
                // body with no throwable is Clerk answering "there is no session", which is final.
                // (`research/clerk-android.md` §8 Q8: verify this split on device — flight mode and
                // a server-side session revoke — because getting it wrong signs users out when they
                // go offline, which is the exact 2026-08-22 regression.)
                is ClerkResult.Failure -> {
                    val cause = result.throwable
                    if (cause != null) TokenRefreshOutcome.Failed(cause)
                    else TokenRefreshOutcome.NotRefreshable
                }
            }
    }

    companion object {

        /** The bearer scheme the backend accepts only when `APP_ENV != production`. */
        const val DEV_TOKEN_PREFIX = "dev:"

        /** iOS's hard cap on waiting for Clerk to restore a session before the splash hands off. */
        private const val CLERK_LOAD_TIMEOUT_MS = 3_000L

        /**
         * The first LETTER of a name, or `null`.
         *
         * **A leading digit, punctuation or emoji is not an initial.** Neither is the first
         * character of an opaque provider id or of interface copy — which is why the callers hand
         * this a real name or an email's local part, and nothing else.
         */
        fun letter(raw: String): String? {
            val first = raw.trim().firstOrNull() ?: return null
            return if (first.isLetter()) first.uppercase() else null
        }
    }
}
