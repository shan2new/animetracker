package com.anitrack.app.data.api

/**
 * What the transport needs from the auth layer, and nothing more.
 *
 * The interface lives HERE, beside its consumer, rather than in `data.auth` beside its
 * implementer: [ApiClient] is the party that states the requirement, and the auth layer already
 * depends on the transport for [ApiError]. Declaring it in `data.auth` instead would put the two
 * packages in a cycle — and would let a future second implementer (a fake in a MockWebServer test,
 * the widget's cut-down client) drag the whole Clerk stack in behind it.
 *
 * The three questions are deliberately distinct. Collapsing them is how the 2026-08-22 regression
 * happened: "I have no token" and "I have no session" are NOT the same fact, and only the second
 * one may ever end a session — see the `token unavailable while signed in` branch in
 * [ApiClient.request].
 */
public interface TokenProvider {

    /**
     * The bearer for the next request, or `null` when none can be minted right now.
     *
     * `null` is not by itself a signed-out answer — a cold launch in airplane mode with an expired
     * JWT returns `null` from a perfectly good session. The transport asks [hasSession] before it
     * decides which of those it is looking at.
     */
    public suspend fun currentToken(): String?

    /**
     * Whether an identity exists at all, independent of whether a token can be minted for it.
     *
     * This is the question that separates "signed out" from "offline", so it must be answerable
     * while the network is down — it reads device-local session state, never the issuer.
     */
    public suspend fun hasSession(): Boolean

    /**
     * A forced refresh that bypasses the issuer's token cache.
     *
     * Called at most once per request, by the transport, on a 401 — and funnelled through
     * [TokenRefresher] so a fan-out of concurrent 401s costs exactly one round-trip.
     */
    public suspend fun refreshedToken(): TokenRefreshOutcome
}

/**
 * The three genuinely different answers to "renew this credential".
 *
 * A two-case success/failure split cannot express the middle one, and the middle one is where the
 * session-keeping rule lives: [Failed] means we never reached the issuer, so the credential's
 * validity is UNKNOWN and the session must be kept; [NotRefreshable] means the issuer answered and
 * had nothing to renew, which is final.
 */
public sealed interface TokenRefreshOutcome {

    /** The issuer minted a token. It may still be byte-identical to the one that just 401'd. */
    public data class Token(val jwt: String) : TokenRefreshOutcome

    /**
     * The issuer answered, and the answer was "nothing to renew" — a `dev:` token, or no session.
     * Final: a request holding this may stop and report [ApiError.Unauthorized].
     */
    public data object NotRefreshable : TokenRefreshOutcome

    /**
     * We never reached the issuer. A network fact, not a session fact.
     *
     * @param cause nullable because a Clerk failure can carry no throwable at all; the transport
     *   substitutes a connection exception so the error taxonomy still has something to classify.
     */
    public data class Failed(val cause: Throwable?) : TokenRefreshOutcome
}
