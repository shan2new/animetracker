package com.anitrack.app.data.api

import android.util.Log
import com.anitrack.app.BuildConfig
import com.anitrack.app.data.AniTrackApi
import com.anitrack.app.data.ApiErrorTaxonomy
import com.anitrack.app.data.AppConfig
import com.anitrack.model.AniTrackJson
import com.anitrack.model.Franchise
import com.anitrack.model.FranchiseListResponse
import com.anitrack.model.FranchiseSummary
import com.anitrack.model.LibraryResponse
import com.anitrack.model.OKResponse
import com.anitrack.model.OpenedResponse
import com.anitrack.model.ProgressBody
import com.anitrack.model.StatusBody
import com.anitrack.model.SubscribeBody
import com.anitrack.model.WatchAvailability
import com.anitrack.model.WatchStatus
import com.anitrack.model.copy.Copy
import java.io.IOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.URLEncoder
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.util.Locale
import java.util.concurrent.TimeUnit
import kotlin.random.Random
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerializationException
import okhttp3.HttpUrl
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.ResponseBody
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Response
import retrofit2.Retrofit

/*
 * THE TRANSPORT LAYER — the port of `ios/Sources/Networking/APIClient.swift`.
 *
 * The single most important idea in this file is a THREE-WAY SPLIT of "the request failed":
 *
 *   1. THE SESSION IS DEAD          → sign the user out.        [ApiError.Unauthorized]
 *   2. THE INFRASTRUCTURE IS IN THE WAY → keep the session, keep the content, show a footnote.
 *                                        [ApiError.Infrastructure] — 403, and HTML at any status.
 *   3. WE COULD NOT REACH ANYTHING  → keep everything, say "No connection". [ApiError.Transport]
 *
 * A 403, an HTML body at any status, and an inability to MINT a token are all in bucket 2 or 3.
 * **Exactly one code path in the whole client ends a session** — branch 1 of [ApiClient.send], and
 * only when a credential was actually SENT and the body was not HTML. Getting that split wrong is
 * a shipped regression this codebase has already lived through (2026-08-22): a Cloudflare WAF
 * challenge signed users out.
 *
 * The second idea is that **a cancelled request is not a failure**. iOS sniffs for it
 * (`Error.isCancellation`) and the consumers swallow it. Kotlin inverts that: `CancellationException`
 * MUST be rethrown or structured concurrency breaks — a child that "completes successfully" after
 * being cancelled lets its parent carry on and paints a result for a screen that is gone. So the
 * rule here is: never `runCatching`, never a bare `catch (e: Exception)` without first re-asserting
 * liveness. Every broad catch in this file opens with `currentCoroutineContext().ensureActive()`,
 * which rethrows if WE were cancelled and additionally covers the race where a cancelled OkHttp
 * call surfaces as `IOException("Canceled")` or `SocketException("Socket closed")` rather than as a
 * `CancellationException` — a case sniffing the error cannot catch at all.
 *
 * Consumers repeat the pattern rather than importing a predicate:
 *
 *     try { library = api.library().franchises }
 *     catch (e: CancellationException) { throw e }               // a superseded reload is not a failure
 *     catch (e: Throwable) { currentCoroutineContext().ensureActive(); loadError = e }
 */

// ---------------------------------------------------------------------------------------------
// MARK: - Token vending
// ---------------------------------------------------------------------------------------------
//
// `TokenProvider` and the three-valued `TokenRefreshOutcome` are declared in THIS package
// (`TokenProvider.kt`), beside the consumer that states the requirement — the auth layer already
// depends on the transport for `ApiError`, so declaring them next to `AuthManager` instead would
// put the two packages in a cycle. iOS keeps both in `APIClient.swift`; the split is a package
// boundary, not a change of contract. The transport depends on exactly three facts:
//
//   * `currentToken()` may be cached, and `null` means "none available right now" — NOT "signed
//     out". A `dev:` token is never vended toward a non-local backend (`AppConfig.isLocalBackend`).
//   * `hasSession()` says an identity EXISTS, independent of whether a token can be MINTED, and
//     MUST NOT touch the network — the whole point is to answer while it is down. "Offline, a Clerk
//     session still exists on this device; its ~60 s JWT does not. The two must never be confused:
//     one is a signed-out user, the other is a user on a train."
//   * `refreshedToken()` answers with THREE outcomes, not two — a fresh token, a final "nothing to
//     renew" from the issuer, or "the issuer was unreachable", which says nothing about the
//     credentials and therefore KEEPS the session. That third answer is the reason this app cannot
//     use an off-the-shelf bearer plugin, all of which collapse it onto "clear the tokens".

/**
 * The Android stand-in for iOS's `URLError(.notConnectedToInternet)`.
 *
 * It extends [ConnectException] (and so `SocketException`) deliberately: `Copy.Notice.reason` walks
 * a throwable's cause chain and resolves that family to **"No connection"**, which is the honest
 * word for "there is an identity on this device and we could not mint a token for it".
 */
public class NoConnectionException(message: String) : ConnectException(message)

// ---------------------------------------------------------------------------------------------
// MARK: - Error taxonomy
// ---------------------------------------------------------------------------------------------

/**
 * What the transport layer learned about a failed request.
 *
 * The distinction that matters is [isSessionEnding]: exactly one case ends the session, and a
 * Cloudflare 403 is not it.
 *
 * A plain [Exception], not an `IOException`: nothing in this client throws an [ApiError] from
 * inside an OkHttp `Interceptor` (which may only throw `IOException`), because the HTML sniff and
 * every other classification happen in [ApiClient.send] where the shipped branch ORDER can be
 * honoured. If a future interceptor ever needs to classify, wrap rather than widen this type.
 */
public sealed class ApiError(cause: Throwable? = null) : Exception(cause) {

    /** The route could not be built from the arguments given. */
    public data object InvalidUrl : ApiError()

    /**
     * A 401 that survived a forced token refresh, or a request made with no session at all.
     * **The session is gone.** The only case for which [isSessionEnding] is true.
     */
    public data object Unauthorized : ApiError()

    /**
     * 403, a WAF/captive-portal HTML body at any status, or a response that was not HTTP at all.
     * The credentials were never the problem, so the SESSION IS KEPT and the surface shows stale
     * content or a footnote.
     */
    public data class Infrastructure(val status: Int, val kind: String) : ApiError()

    /** A 429 that outlived the retry budget. [retryAfterMs] is the server's hint, clamped to 8 s. */
    public data class RateLimited(val retryAfterMs: Long?) : ApiError()

    /** Any other non-2xx. [body] is log-only. */
    public data class Http(val status: Int, val body: String) : ApiError()

    /**
     * A decode failure — **and a request-body ENCODE failure**, which iOS also files under its
     * `decoding` case. Named for both.
     */
    public data class Serialization(val error: Throwable) : ApiError(error)

    /**
     * The request never got an answer: no route, a timeout, a token that could not be minted, or a
     * token issuer that could not be reached.
     */
    public data class Transport(val error: Throwable) : ApiError(error)

    /**
     * The predicate every caller branches on. Spelling the same test longhand at a call site is
     * what lets a new case quietly acquire the wrong behaviour; only this survives adding one.
     */
    public val isSessionEnding: Boolean get() = this is Unauthorized

    /**
     * Log-only detail: status codes, MIME types, body text.
     *
     * **This may never reach a surface** (board 14: no status code and no MIME type in anything a
     * user reads). Everything a user reads comes from [userMessage] or [writeFailureReason], which
     * are drawn from the copy table.
     */
    public val diagnostic: String
        get() = when (this) {
            is InvalidUrl -> "invalid-url"
            is Unauthorized -> "unauthorized"
            is Infrastructure -> "infrastructure status=$status kind=$kind"
            is RateLimited -> "rate-limited retryAfter=${retryAfterMs?.let { (it / 1000).toString() } ?: "-"}"
            is Http -> "http status=$status body=${body.take(MAX_LOGGED_BODY)}"
            is Serialization -> "serialization $error"
            is Transport -> "transport $error"
        }

    /**
     * The one projection a SURFACE may render.
     *
     * iOS keeps two tables here — `errorDescription`/`failureReason` on `APIError`, and
     * `Copy.Notice.reason` for the Sync rows — and in the shipped app only the `.unauthorized`
     * sentence from the first is ever drawn; the rest ("Server error", "Rate limited") have no call
     * site. This port keeps the sentence and routes everything else through the copy table, so
     * there is ONE ladder, every string still lives in `Copy`, and no surface can say "server" —
     * which the voice rules forbid everywhere except the account-deletion failure.
     */
    public val userMessage: String
        get() = if (this is Unauthorized) Copy.State.signedOut else writeFailureReason

    /**
     * The short reason a failed write shows in Sync status — never a status code, never a raw
     * exception message.
     *
     * The mapping is the one `Copy.Notice.reason`'s own documentation states, including the
     * deliberate asymmetry it warns about: a 429 that arrived as an HTTP status reads "Try again in
     * a minute", while a 429 that outlived the retry budget and became [RateLimited] falls to
     * `OTHER` and reads "Something went wrong". That is what the shipped iOS code does. Reproduce
     * it rather than "fixing" it, or the Sync list changes wording for the same user-visible
     * failure.
     */
    public val writeFailureReason: String
        get() = when (this) {
            is Unauthorized -> Copy.Notice.reason(Copy.Notice.Failure.UNAUTHORIZED)
            is Http -> Copy.Notice.reason(Copy.Notice.Failure.HTTP, httpStatus = status)
            is Transport -> Copy.Notice.reason(Copy.Notice.Failure.TRANSPORT, cause = error)
            is InvalidUrl, is Infrastructure, is RateLimited, is Serialization ->
                Copy.Notice.reason(Copy.Notice.Failure.OTHER)
        }

    internal companion object {
        /** iOS logs the first 200 characters of an error body. */
        const val MAX_LOGGED_BODY: Int = 200
    }
}

// ---------------------------------------------------------------------------------------------
// MARK: - Logging
// ---------------------------------------------------------------------------------------------

/**
 * One tag for the request lines AND the `auth.refresh` lines, deliberately — so
 * `adb logcat -s anitrack.api` interleaves them and single-flight refresh is verifiable without a
 * UI. (iOS achieves the same by putting `APIClient` and `TokenRefresher` in one
 * subsystem/category.)
 *
 * iOS emits every one of these at `.error` because that is what survives the unified log's default
 * predicate. Android's logcat shows every level by default, so that reason does not carry over, and
 * a scheduled retry is a warning rather than an error — ERROR here would feed crash-reporting
 * breadcrumbs for an event the client handles by design. The LINE FORMATS are unchanged, because
 * those are the diagnostic contract.
 */
internal object ApiLog {
    const val TAG: String = "anitrack.api"

    fun line(message: String) {
        Log.w(TAG, message)
    }
}

// ---------------------------------------------------------------------------------------------
// MARK: - Retry policy
// ---------------------------------------------------------------------------------------------

/**
 * Bounded, jittered backoff. Two retries add at most ~1.6 s to a failing request, so a skeleton can
 * never hang on a flaky upstream — and a request that will fail, fails inside the budget.
 */
public object RetryPolicy {

    public const val MAX_RETRIES: Int = 2

    /** The delay BEFORE retry #1 and #2, in ms. */
    private val BASE_MS = longArrayOf(400, 1_200)

    /**
     * The whole LOGICAL request's wall-clock budget: one full attempt plus at most ~1.6 s of
     * backoff. Every attempt and every sleep is spent from this one budget, because a per-attempt
     * timeout stacks — three fresh 15 s attempts against a black hole is 45 s of skeleton.
     */
    public const val BUDGET_MS: Long = 16_600

    /**
     * The floor on any single attempt's timeout, and the survivability test for a retry: another
     * attempt is only worth starting if this much of the budget outlives the backoff sleep.
     */
    public const val MIN_ATTEMPT_MS: Long = 2_000

    /**
     * The ceiling on any single attempt.
     *
     * On iOS this is `timeoutIntervalForRequest`, an INTER-PACKET timer that an upstream trickling
     * one byte every 14 s defeats — which is why that side also needs `timeoutIntervalForResource`
     * as a true wall-clock cap. OkHttp's `callTimeout` already IS wall clock: it spans DNS,
     * connect, request write, server processing, response read, redirects and OkHttp's own route
     * retries. So the resource cap has no analogue here, and deliberately none is invented.
     */
    public const val REQUEST_TIMEOUT_MS: Long = 15_000

    /** `Retry-After` is clamped so a hostile header cannot stall the UI. */
    private const val RETRY_AFTER_CAP_MS: Long = 8_000

    /**
     * A monotonic clock. `System.currentTimeMillis` can step backwards (NTP, the user editing the
     * clock) and would hand a request an unbounded budget when it did.
     */
    public fun monotonicMs(): Long = System.nanoTime() / 1_000_000

    /** Whether another attempt fits: retries left, AND enough budget after the sleep to make one. */
    public fun canRetry(attempt: Int, delayMs: Long, deadlineMs: Long, nowMs: Long): Boolean =
        attempt < MAX_RETRIES && (deadlineMs - nowMs) - delayMs >= MIN_ATTEMPT_MS

    /** [attempt] is 1-based (the delay BEFORE retry #1). ±20 % jitter de-synchronises a fan-out. */
    public fun delayMs(attempt: Int): Long {
        val base = BASE_MS[attempt.coerceIn(1, BASE_MS.size) - 1]
        return (base * Random.nextDouble(0.8, 1.2)).toLong()
    }

    /** `Retry-After` in seconds or as an HTTP-date, in ms, clamped to `0…8 s`. Unparseable → null. */
    public fun retryAfterMs(header: String?): Long? {
        val raw = header?.trim().orEmpty()
        if (raw.isEmpty()) return null
        raw.toDoubleOrNull()?.let { return clamp(it) }
        return try {
            // RFC 1123 — "Wed, 21 Oct 2015 07:28:00 GMT", the one date form HTTP mandates. Wall
            // clock, not the monotonic one, because the header names an absolute instant.
            val at = ZonedDateTime.parse(raw, DateTimeFormatter.RFC_1123_DATE_TIME)
            clamp((at.toInstant().toEpochMilli() - System.currentTimeMillis()) / 1_000.0)
        } catch (e: DateTimeParseException) {
            null
        }
    }

    private fun clamp(seconds: Double): Long =
        (seconds * 1_000).toLong().coerceIn(0L, RETRY_AFTER_CAP_MS)
}

// ---------------------------------------------------------------------------------------------
// MARK: - Single-flight token refresh
// ---------------------------------------------------------------------------------------------

/**
 * Coalesces concurrent token refreshes into ONE network call, and reuses its result for a short
 * window afterwards, so a burst of 401s (six parallel requests on a cold launch) cannot become a
 * refresh storm.
 *
 * @param scope MUST be application-scoped. If the shared refresh were launched on the FIRST
 *   caller's scope, that caller navigating away would cancel the refresh out from under the five
 *   coroutines waiting on it. This is the one non-obvious correctness detail in the file.
 */
public class TokenRefresher(
    private val scope: CoroutineScope,
    private val clock: () -> Long = RetryPolicy::monotonicMs,
) {

    private companion object {
        /**
         * Long enough to cover one screen's fan-out, short enough that a genuinely new 401
         * refetches.
         */
        const val REUSE_WINDOW_MS: Long = 3_000
    }

    private val mutex = Mutex()
    private var inFlight: Deferred<TokenRefreshOutcome>? = null
    private var lastToken: String? = null
    private var lastAt: Long = 0

    /**
     * The `auth.refresh` log lines live HERE rather than at the call site: one `begin`/`end` pair is
     * emitted per ACTUAL refresh, so a burst of six concurrent 401s prints one pair plus five
     * `coalesced`/`reused` lines. Logging at the call site would print six of each and make
     * single-flight unverifiable from logcat.
     */
    public suspend fun token(provider: TokenProvider): TokenRefreshOutcome {
        // ONE critical section decides all three cases, so a refresh landing between two separate
        // checks cannot cause a redundant second one.
        val pending: Deferred<TokenRefreshOutcome> = mutex.withLock {
            val cached = lastToken
            if (cached != null && clock() - lastAt < REUSE_WINDOW_MS) {
                ApiLog.line("auth.refresh reused")
                return TokenRefreshOutcome.Token(cached)
            }
            val running = inFlight
            // `isActive`, not merely non-null: a caller cancelled while awaiting never reaches the
            // bookkeeping below, so a COMPLETED deferred can survive here — and joining that would
            // hand the next 401 a stale answer instead of refreshing.
            if (running != null && running.isActive) {
                ApiLog.line("auth.refresh coalesced")
                running
            } else {
                ApiLog.line("auth.refresh begin")
                scope.async { provider.refreshedToken() }.also { inFlight = it }
            }
        }

        // Awaited OUTSIDE the lock, and the Deferred belongs to `scope`: a caller cancelling here
        // cancels only its own await, never the refresh the other waiters are sharing.
        val outcome = pending.await()

        mutex.withLock {
            // Exactly one waiter finalises, so exactly one `end(...)` line is printed per refresh.
            if (inFlight === pending) {
                inFlight = null
                when (outcome) {
                    is TokenRefreshOutcome.Token -> ApiLog.line("auth.refresh end(changed:true)")
                    // The issuer had nothing to renew — a `dev:` token, or no session. NOT a
                    // network call, and a final answer.
                    TokenRefreshOutcome.NotRefreshable ->
                        ApiLog.line("auth.refresh end(changed:false, notRefreshable)")
                    is TokenRefreshOutcome.Failed ->
                        ApiLog.line("auth.refresh end(changed:false, unreachable)")
                }
                // ONLY a success primes the reuse window. Caching a refresh that failed because the
                // issuer was unreachable would replay that failure to every 401 for the next 3 s,
                // turning one network blip into a session-wide teardown.
                if (outcome is TokenRefreshOutcome.Token) {
                    lastToken = outcome.jwt
                    lastAt = clock()
                }
            }
        }
        return outcome
    }

    /** Sign-out: the next account inherits nothing, not even a three-second-old token. */
    public suspend fun clear() {
        mutex.withLock {
            lastToken = null
            lastAt = 0
            inFlight = null
        }
    }
}

// ---------------------------------------------------------------------------------------------
// MARK: - Header injection
// ---------------------------------------------------------------------------------------------

/**
 * Puts `Accept` on every request and promotes the [AuthToken] tag [ApiClient] attached into an
 * `Authorization` header.
 *
 * It reads a tag rather than calling [TokenProvider] itself, because `Interceptor.intercept` is a
 * blocking Java-shaped API: asking a suspending provider from inside it needs `runBlocking`, which
 * pins an OkHttp dispatcher thread, is invisible to structured concurrency and cannot be cancelled
 * by the caller. It also could not express the pre-flight split (§"no token is two different facts"
 * in [ApiClient.send]) or the forced-refresh retry, both of which must choose WHICH token to send.
 * So the wrapper decides the token and the interceptor owns the header's shape — one place each.
 */
internal class AuthInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): okhttp3.Response {
        val request = chain.request()
        val builder = request.newBuilder().header("Accept", "application/json")
        request.tag(AuthToken::class.java)?.let {
            builder.header("Authorization", "Bearer ${it.value}")
        }
        return chain.proceed(builder.build())
    }
}

// ---------------------------------------------------------------------------------------------
// MARK: - The client
// ---------------------------------------------------------------------------------------------

/**
 * Every endpoint in the API contract, and the transport state machine that serves them.
 *
 * @param tokens the auth layer's token vendor.
 */
public class ApiClient internal constructor(
    private val api: AniTrackService,
    private val tokens: TokenProvider,
    private val refresher: TokenRefresher,
) {

    /**
     * @param baseUrl defaults to the build's configured backend.
     * @param refreshScope application-scoped; see [TokenRefresher].
     * @param httpClient injectable so the client is exercisable against MockWebServer without a
     *   network — the analogue of iOS's injectable `URLSession`.
     */
    public constructor(
        tokens: TokenProvider,
        baseUrl: HttpUrl = AppConfig.apiBaseUrl,
        refreshScope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
        httpClient: OkHttpClient = defaultHttpClient(),
    ) : this(
        api = Retrofit.Builder()
            .baseUrl(baseUrl)
            .callFactory(httpClient)
            .build()
            .create(AniTrackService::class.java),
        tokens = tokens,
        refresher = TokenRefresher(refreshScope),
    )

    // -----------------------------------------------------------------------------------------
    // MARK: Endpoints
    //
    // Every call states its own retryability. `idempotent` is a REQUIRED argument, not a default,
    // because exactly one endpoint in this app is unsafe to replay (`/me/opened`) and the next
    // endpoint someone adds must make that decision consciously.
    // -----------------------------------------------------------------------------------------

    /**
     * The only unauthenticated call, and the one that proves a 401 without a credential can never
     * end a session. Nothing in the app calls it; it is the natural reachability probe.
     */
    public suspend fun health(): OKResponse =
        send("GET", "/health", auth = false, idempotent = true, serializer = OKResponse.serializer()) {
            api.health(it)
        }

    /**
     * @param limit iOS declares 30 and every real caller passes 10; the default here is what the
     *   callers actually use.
     */
    public suspend fun trending(limit: Int = DEFAULT_TRENDING_LIMIT): List<FranchiseSummary> =
        send(
            "GET", "/franchises/trending", auth = true, idempotent = true,
            serializer = FranchiseListResponse.serializer(),
        ) { api.trending(it, limit) }.franchises

    /**
     * The full search response, including what the server corrected and which catalogue failed.
     *
     * @param exact opts out of the server's spell-correction.
     */
    public suspend fun search(query: String, exact: Boolean = false): SearchResponse {
        // `URLEncoder` escapes all five of `& = + ? #`, which is what this needs: OkHttp's own
        // query-component encode set leaves `+` alone, and iOS's `.urlQueryAllowed` leaves `&`, `+`
        // and `=` alone — which is why searching "X & Y" once truncated at the ampersand.
        //
        // Then `+` → `%20`. `URLEncoder` is form-encoding, so it writes a SPACE as `+`, and a `+`
        // that means "space" is a convention of the parser rather than of URLs. Fastify's default
        // query parser honours it, but a proxy, a CDN or a future parser change need not, and a
        // multi-word title arriving as one `+`-joined token would match nothing. `%20` is a space to
        // every parser there is. (A literal `+` in the title is already `%2B` by this point and is
        // untouched by the replace.)
        val q = URLEncoder.encode(query, "UTF-8").replace("+", "%20")
        val response = send(
            "GET", "/search", auth = true, idempotent = true,
            serializer = FranchiseListResponse.serializer(),
        ) { api.search(it, q, if (exact) "1" else null) }
        return SearchResponse(
            franchises = response.franchises,
            correctedQuery = response.correctedQuery,
            // The server echoes the original only alongside a correction; substitute ours when it
            // does not, so the "Search instead for X" line always has both halves.
            originalQuery = response.originalQuery ?: query,
            sources = response.sources,
        )
    }

    /**
     * @param country ISO 3166-1 alpha-2, selecting `audience.contentRating` for the viewer's
     *   market. The server never substitutes another market's rating, so a miss is absent, not
     *   "US". Send it always; only one legacy iOS call site omits it.
     */
    public suspend fun franchise(id: String, country: String? = null): Franchise =
        send(
            "GET", "/franchises/$id", auth = true, idempotent = true,
            serializer = Franchise.serializer(),
        ) { api.franchise(it, id, country) }

    /**
     * Country-specific streaming availability, read apart from the franchise so a cold provider
     * lookup never delays the show page. A failure here is a MISSING SECTION, never an error.
     */
    public suspend fun watchProviders(id: String, country: String): WatchAvailability =
        send(
            "GET", "/franchises/$id/watch-providers", auth = true, idempotent = true,
            serializer = WatchAvailability.serializer(),
        ) { api.watchProviders(it, id, country) }

    public suspend fun library(): LibraryResponse =
        send(
            "GET", "/me/library", auth = true, idempotent = true,
            serializer = LibraryResponse.serializer(),
        ) { api.library(it) }

    /** Idempotent: the server upserts, so a replay lands on the same row with the same status. */
    public suspend fun subscribe(franchiseId: String, status: WatchStatus? = null): OKResponse {
        val body = jsonBody(SubscribeBody.serializer(), SubscribeBody(franchiseId, status))
        return send(
            "POST", "/me/subscriptions", auth = true, idempotent = true,
            serializer = OKResponse.serializer(),
        ) { api.subscribe(it, body) }
    }

    public suspend fun setStatus(franchiseId: String, status: WatchStatus): OKResponse {
        val body = jsonBody(StatusBody.serializer(), StatusBody(status))
        return send(
            "PATCH", "/me/subscriptions/$franchiseId", auth = true, idempotent = true,
            serializer = OKResponse.serializer(),
        ) { api.setStatus(it, franchiseId, body) }
    }

    public suspend fun unsubscribe(franchiseId: String): OKResponse =
        send(
            "DELETE", "/me/subscriptions/$franchiseId", auth = true, idempotent = true,
            serializer = OKResponse.serializer(),
        ) { api.unsubscribe(it, franchiseId) }

    /** Idempotent because the count is ABSOLUTE, never a delta — replaying it is a no-op. */
    public suspend fun setProgress(mediaId: Int, episodes: Int): OKResponse {
        val body = jsonBody(ProgressBody.serializer(), ProgressBody(mediaId, episodes))
        return send(
            "PUT", "/me/progress", auth = true, idempotent = true,
            serializer = OKResponse.serializer(),
        ) { api.setProgress(it, body) }
    }

    /**
     * **NOT retryable.** It stamps `lastOpenedAt` and returns the PREVIOUS value; a replay would
     * return "now" and destroy "since you were last here" — the recap's whole premise.
     */
    public suspend fun markOpened(): OpenedResponse =
        send(
            "POST", "/me/opened", auth = true, idempotent = false,
            serializer = OpenedResponse.serializer(),
        ) { api.markOpened(it) }

    /** Sign-out. The next account inherits nothing — not even a three-second-old refreshed token. */
    public suspend fun clearTokenCache() {
        refresher.clear()
    }

    // -----------------------------------------------------------------------------------------
    // MARK: The transport state machine
    // -----------------------------------------------------------------------------------------

    /**
     * Exactly one RESPONSE path throws [ApiError.Unauthorized] — a 401 that survived a forced
     * refresh, on a request that CARRIED a credential and came back with a non-HTML body. An HTML
     * body outranks the status: a 401 from nginx `auth_basic`, a Cloudflare Access challenge or a
     * captive portal is `Infrastructure(401, "html")` with the session kept. The only other
     * `Unauthorized` site is the pre-flight guard below, and it fires only when there is no
     * SESSION. **403 is on neither.**
     *
     * The whole logical request — every attempt plus every backoff sleep — is bounded by one
     * wall-clock budget, and each attempt's own timeout is clamped to what is left of it. A request
     * that will fail, fails inside ~16.6 s however many attempts it made.
     *
     * @param method used only for the log lines; the real verb is on the [AniTrackService] annotation.
     * @param path likewise — the real URL is Retrofit's.
     */
    private suspend fun <T> send(
        method: String,
        path: String,
        auth: Boolean,
        idempotent: Boolean,
        serializer: KSerializer<T>,
        call: suspend (AuthToken?) -> Response<ResponseBody>,
    ): T {
        val deadline = RetryPolicy.monotonicMs() + RetryPolicy.BUDGET_MS
        var attempt = 0             // retries consumed
        var refreshed = false       // the one forced token refresh this request is allowed
        var forcedToken: String? = null   // set by that refresh, so the retry does not re-read the cache

        while (true) {
            var sentToken: String? = null
            var bearer: AuthToken? = null
            if (auth) {
                val resolved = forcedToken ?: tokens.currentToken()
                if (resolved == null) {
                    // No token, for one of two very different reasons — and only one of them ends a
                    // session. Either there is no identity at all (signed out), or there IS one and
                    // we could not mint a token right now: a cold launch in airplane mode, where the
                    // ~60 s JWT has expired and nothing can renew it. Signing a user out for being
                    // offline is the same failure class as the 2026-08-22 regression.
                    if (tokens.hasSession()) {
                        ApiLog.line("$method $path: token unavailable while signed in — transport, session kept")
                        throw ApiError.Transport(NoConnectionException("no token while signed in"))
                    }
                    ApiLog.line("$method $path: no session — unauthorized")
                    throw ApiError.Unauthorized
                }
                sentToken = resolved
                bearer = AuthToken(resolved)
            }

            // Spend from the shared budget, never restart it: a retry after a timeout gets only the
            // seconds that are left, so attempts cannot stack up behind a skeleton. OkHttp's
            // per-client `callTimeout` is the same 15 s ceiling, but it cannot vary per call, so the
            // REMAINDER is enforced here.
            val attemptTimeout = (deadline - RetryPolicy.monotonicMs())
                .coerceIn(RetryPolicy.MIN_ATTEMPT_MS, RetryPolicy.REQUEST_TIMEOUT_MS)

            val response: Response<ResponseBody> = try {
                withTimeout(attemptTimeout) { call(bearer) }
            } catch (e: Throwable) {
                // FIRST, always: rethrows if WE were cancelled. That is the "a request cancelled by
                // the next keystroke is superseded" rule, and it also covers the race where a
                // cancelled OkHttp call surfaces as IOException("Canceled") or
                // SocketException("Socket closed") instead of a CancellationException.
                currentCoroutineContext().ensureActive()
                if (e is ApiError) throw e
                // Our own per-attempt timeout arrives as TimeoutCancellationException and IS a
                // failure; any other CancellationException reaching here is not ours to reinterpret.
                if (e is CancellationException && e !is TimeoutCancellationException) throw e
                // Retrofit could not build a URL from these arguments. (SerializationException is a
                // subclass of IllegalArgumentException; it cannot occur on this path — bodies are
                // encoded before `send` — but the guard states the intent.)
                if (e is IllegalArgumentException && e !is SerializationException) {
                    ApiLog.line("$method $path: ${ApiError.InvalidUrl.diagnostic}")
                    throw ApiError.InvalidUrl
                }
                val cause: Throwable = if (e is TimeoutCancellationException) {
                    SocketTimeoutException("attempt timed out after $attemptTimeout ms")
                } else {
                    e
                }
                val backoff = RetryPolicy.delayMs(attempt + 1)
                if (!idempotent ||
                    !RetryPolicy.canRetry(attempt, backoff, deadline, RetryPolicy.monotonicMs())
                ) {
                    ApiLog.line("$method $path: transport error: $cause")
                    throw ApiError.Transport(cause)
                }
                attempt++
                logRetry(method, path, attempt, backoff, status = 0)
                delay(backoff)
                continue
            }

            val status = response.code()
            val contentType = response.headers()["Content-Type"].orEmpty().lowercase(Locale.ROOT)
            val bytes = try {
                // Retrofit has already buffered both the success body and the error body into
                // memory, so this cannot do I/O; the guard exists so a surprise can never escape as
                // a raw IOException. Not retried — the network part of this attempt succeeded.
                (response.body() ?: response.errorBody())?.use { it.bytes() } ?: ByteArray(0)
            } catch (e: IOException) {
                currentCoroutineContext().ensureActive()
                ApiLog.line("$method $path: transport error: $e")
                throw ApiError.Transport(e)
            }

            // 1 — 401: refresh ONCE, then retry immediately. That retry does NOT consume the backoff
            // budget: a stale token is not a flaky network. This is the ONLY branch in the client
            // that ends a session, so it is guarded on the two facts that make a 401 mean "your
            // credential is dead":
            //   * `auth` — we actually SENT a credential. A 401 on an unauthenticated probe
            //     (`health()`) is the server's business, never a reason to sign anyone out.
            //   * not HTML — a real expired session is `401 {"error":"invalid token"}` in
            //     `application/json`. An HTML 401 is nginx `auth_basic`, a Cloudflare Access
            //     challenge or a captive portal; it falls through to branch 4 and becomes
            //     `Infrastructure(401, "html")` with the session KEPT.
            if (status == 401 && auth && !isHtml(bytes, contentType)) {
                if (!refreshed) {
                    refreshed = true
                    when (val outcome = refresher.token(tokens)) {
                        is TokenRefreshOutcome.Token ->
                            if (outcome.jwt != sentToken) {
                                forcedToken = outcome.jwt
                                continue
                            }
                        is TokenRefreshOutcome.Failed -> {
                            // We never learned whether the credentials are dead — only that the
                            // issuer is unreachable. That is a network fact, not a session fact.
                            ApiLog.line("$method $path: auth.refresh unreachable — transport, session kept")
                            // `Failed.cause` is nullable on the auth side (a Clerk result can carry
                            // no throwable at all); the taxonomy needs one, and "we could not reach
                            // the issuer" is a connection fact, so that is what stands in.
                            throw ApiError.Transport(
                                outcome.cause ?: NoConnectionException("auth.refresh unreachable"),
                            )
                        }
                        // The issuer answered, and the answer was final: the same token back, or an
                        // issuer with nothing to renew. Falls through to the sign-out below.
                        TokenRefreshOutcome.NotRefreshable -> Unit
                    }
                }
                ApiLog.line("unauthorized after refresh")
                throw ApiError.Unauthorized
            }

            // 2 — 403 is INFRASTRUCTURE, never a sign-out. A Cloudflare WAF challenge says nothing
            // about the user's session; signing them out on it is the 2026-08-22 regression.
            if (status == 403) {
                val e = ApiError.Infrastructure(403, contentType.ifEmpty { "forbidden" })
                ApiLog.line("$method $path: ${e.diagnostic}")
                throw e
            }

            // 3 — 429 and 5xx are worth one or two more attempts. This runs BEFORE the HTML test
            // because the ordinary production 502/503 arrives with an HTML error page from nginx or
            // Cloudflare; classifying on the body first would refuse to retry a transient outage.
            if (status == 429 || status in 500..504) {
                val after = if (status == 429) {
                    RetryPolicy.retryAfterMs(response.headers()["Retry-After"])
                } else {
                    null
                }
                val backoff = after ?: RetryPolicy.delayMs(attempt + 1)
                if (idempotent &&
                    RetryPolicy.canRetry(attempt, backoff, deadline, RetryPolicy.monotonicMs())
                ) {
                    attempt++
                    logRetry(method, path, attempt, backoff, status)
                    delay(backoff)
                    continue
                }
                if (status == 429) {
                    val e = ApiError.RateLimited(after)
                    ApiLog.line("$method $path: ${e.diagnostic}")
                    throw e
                }
                // An exhausted 5xx falls through: if its body is HTML it is infrastructure (branch
                // 4), otherwise it is a server error we can report (branch 5).
            }

            // 4 — an HTML body at ANY status (captive portal, WAF interstitial, a 200 sign-in page,
            // a CDN's 503 page) is an infrastructure failure, not a decode failure.
            if (isHtml(bytes, contentType)) {
                val e = ApiError.Infrastructure(status, "html")
                ApiLog.line(
                    "$method $path: ${e.diagnostic} contentType=${contentType.ifEmpty { "sniffed" }}",
                )
                throw e
            }

            if (status !in 200..299) {
                val e = ApiError.Http(status, bytes.toString(Charsets.UTF_8))
                ApiLog.line("$method $path: ${e.diagnostic}")
                throw e
            }

            return try {
                // `--ez demoBusy true`: the library payload is rewritten on the way IN, so the
                // screens render the fixture exactly as they render the real thing. No-op in a
                // release build and for every other path.
                val text = DemoLibrary.rewriteIfNeeded(path, bytes.toString(Charsets.UTF_8))
                AniTrackJson.decodeFromString(serializer, text)
            } catch (e: IllegalArgumentException) {
                // Covers SerializationException, which extends it — kotlinx raises the bare
                // IllegalArgumentException for structurally valid JSON a serializer rejects.
                ApiLog.line("$method $path: decoding failed: $e")
                throw ApiError.Serialization(e)
            }
        }
    }

    /**
     * A request body, encoded up front.
     *
     * Encoding happens BEFORE [send] so an encode failure lands in the taxonomy as
     * [ApiError.Serialization] rather than being caught by the transport's retry logic — iOS files
     * the same failure under its `decoding` case for the same reason.
     */
    private fun <B> jsonBody(serializer: KSerializer<B>, value: B): RequestBody = try {
        AniTrackJson.encodeToString(serializer, value).toRequestBody(JSON_MEDIA_TYPE)
    } catch (e: IllegalArgumentException) {
        throw ApiError.Serialization(e)
    }

    /**
     * HTML by declared type, or by the first non-whitespace byte. Cheap, and it catches the proxies
     * that serve an interstitial as `text/plain`. An empty body is not HTML.
     */
    private fun isHtml(data: ByteArray, contentType: String): Boolean {
        if (contentType.contains("text/html")) return true
        val first = data.firstOrNull {
            it != SPACE && it != LINE_FEED && it != CARRIAGE_RETURN && it != TAB
        } ?: return false
        return first == LESS_THAN
    }

    private fun logRetry(method: String, path: String, attempt: Int, delayMs: Long, status: Int) {
        val seconds = "%.2f".format(Locale.ROOT, delayMs / 1_000.0)
        ApiLog.line("retry scheduled $method $path attempt=$attempt delay=$seconds status=$status")
    }

    public companion object {

        /** iOS declares 30; every real caller passes 10. */
        public const val DEFAULT_TRENDING_LIMIT: Int = 10

        private val JSON_MEDIA_TYPE = "application/json".toMediaType()

        private const val SPACE: Byte = 0x20
        private const val LINE_FEED: Byte = 0x0a
        private const val CARRIAGE_RETURN: Byte = 0x0d
        private const val TAB: Byte = 0x09
        private const val LESS_THAN: Byte = 0x3c   // '<'

        /**
         * The client the app ships with — owned, never a shared default.
         *
         * `callTimeout` is the per-ATTEMPT ceiling and a genuine wall-clock budget: it spans DNS,
         * connect, request write, server processing, response read, redirects and OkHttp's own
         * route retries. That is strictly better than the iOS original, whose
         * `timeoutIntervalForRequest` is an inter-packet timer a trickling upstream defeats — which
         * is why that side needs a second `timeoutIntervalForResource` cap and this one does not.
         *
         * `retryOnConnectionFailure` stays ON (the default): it only tries the remaining routes for
         * a host — a second A record, IPv4 after IPv6 — and it happens INSIDE `callTimeout`, so it
         * cannot overrun the attempt budget the way an application-level replay would.
         *
         * **The logging interceptor never goes above BASIC, and only in a debug build.** At BODY it
         * would print the user's entire watch history to logcat.
         */
        public fun defaultHttpClient(): OkHttpClient = OkHttpClient.Builder()
            .callTimeout(RetryPolicy.REQUEST_TIMEOUT_MS, TimeUnit.MILLISECONDS)
            .connectTimeout(CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .readTimeout(RetryPolicy.REQUEST_TIMEOUT_MS, TimeUnit.MILLISECONDS)
            .writeTimeout(RetryPolicy.REQUEST_TIMEOUT_MS, TimeUnit.MILLISECONDS)
            .retryOnConnectionFailure(true)
            // Added first, so it is the OUTERMOST application interceptor and the logger below sees
            // the request it actually sent.
            .addInterceptor(AuthInterceptor())
            .apply {
                if (BuildConfig.DEBUG) {
                    addInterceptor(
                        HttpLoggingInterceptor().apply {
                            level = HttpLoggingInterceptor.Level.BASIC
                            redactHeader("Authorization")
                        },
                    )
                }
            }
            .build()

        private const val CONNECT_TIMEOUT_SECONDS: Long = 10
    }
}

// ---------------------------------------------------------------------------------------------
// MARK: - Seams onto the model layer
// ---------------------------------------------------------------------------------------------

/**
 * [ApiClient] as the narrow eight-call port `AppModel` declares for itself
 * (`com.anitrack.app.data.AniTrackApi`).
 *
 * The model deliberately does not import the transport — that keeps it testable with no OkHttp on
 * the classpath — so the adaptation belongs on this side of the seam, where the client's owner can
 * see it. It is a pure rename layer: no retry, no classification, no policy of its own.
 *
 * The one shape change is [search], which the port wants as the wire envelope. The client's
 * [SearchResponse] is folded back into a `FranchiseListResponse` **keeping the substituted
 * `originalQuery`** — the server echoes it only alongside a correction, and losing the fallback
 * here would leave the "Search instead for X" line with one half missing.
 */
public class ApiClientPort(private val client: ApiClient) : AniTrackApi {

    override suspend fun library(): LibraryResponse = client.library()

    override suspend fun markOpened(): OpenedResponse = client.markOpened()

    override suspend fun search(query: String, exact: Boolean): FranchiseListResponse {
        val response = client.search(query = query, exact = exact)
        return FranchiseListResponse(
            franchises = response.franchises,
            correctedQuery = response.correctedQuery,
            originalQuery = response.originalQuery,
            sources = response.sources,
        )
    }

    override suspend fun trending(limit: Int): List<FranchiseSummary> = client.trending(limit)

    override suspend fun setProgress(mediaId: Int, episodes: Int) {
        client.setProgress(mediaId = mediaId, episodes = episodes)
    }

    override suspend fun subscribe(franchiseId: String, status: WatchStatus?) {
        client.subscribe(franchiseId = franchiseId, status = status)
    }

    override suspend fun setStatus(franchiseId: String, status: WatchStatus) {
        client.setStatus(franchiseId = franchiseId, status = status)
    }

    override suspend fun unsubscribe(franchiseId: String) {
        client.unsubscribe(franchiseId)
    }
}

/**
 * The real [ApiErrorTaxonomy] — the three questions the model asks about a thrown error, answered
 * from [ApiError].
 *
 * **Wire this one, never `DefaultApiErrorTaxonomy`.** That fallback is HTTP-blind and answers
 * `isUnauthorized` with `false` for everything, so a client using it would paint "Couldn't load your
 * library" over a dead session forever and no amount of retrying could fix it.
 *
 * `isCancellation` is deliberately NOT overridden: the inherited implementation walks the cause
 * chain for a `CancellationException` and for OkHttp's `IOException("Canceled")`, which is exactly
 * right — and it stays correct for a throwable that never passed through this client at all.
 */
public object ApiClientErrorTaxonomy : ApiErrorTaxonomy {

    /**
     * Only [ApiError.Unauthorized]. A 403, an HTML body at any status and a token that could not be
     * MINTED are ordinary failures that keep the session — the 2026-08-22 regression was signing
     * users out on a Cloudflare challenge.
     */
    override fun isUnauthorized(error: Throwable): Boolean =
        (error as? ApiError)?.isSessionEnding == true

    /** A `Copy.Notice` string, never a status code and never a raw exception message. */
    override fun reason(error: Throwable): String =
        (error as? ApiError)?.writeFailureReason ?: Copy.Notice.reason(error)
}
