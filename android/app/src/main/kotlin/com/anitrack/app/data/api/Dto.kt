package com.anitrack.app.data.api

import com.anitrack.model.FranchiseSummary
import okhttp3.RequestBody
import okhttp3.ResponseBody
import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path
import retrofit2.http.Query
import retrofit2.http.Tag

/*
 * THE ENDPOINT CATALOGUE.
 *
 * Every wire type this file moves lives in `:model` (`Models.kt` / `ModelsEnrichment.kt`) — that
 * module owns the decoding contract and the leniency rules, and nothing here may restate them.
 * What lives here is the SHAPE of the API surface: the routes, their parameters, and the one
 * response type the client assembles rather than decodes.
 *
 * ── Why every route returns `Response<ResponseBody>` rather than a decoded type ────────────────
 *
 * The transport state machine in `ApiClient.send` has to see (status, Content-Type, raw bytes)
 * BEFORE anything is decoded, because the shipped branch order depends on all three and on their
 * order:
 *
 *   401 (with a credential sent, and a non-HTML body) → refresh once
 *   403                                               → infrastructure, session KEPT
 *   429 / 5xx                                         → retry — BEFORE the HTML test, because the
 *                                                       ordinary production 502 arrives as an
 *                                                       nginx or Cloudflare HTML page
 *   HTML at ANY status, 2xx included                  → infrastructure (captive portal / WAF)
 *   any other non-2xx                                 → http(status, body)
 *   otherwise                                         → decode
 *
 * A Retrofit converter would decode a 2xx before the client could sniff it, so a captive portal's
 * `200 text/html` sign-in page would surface as a DECODING failure instead of the truth. And an
 * `Interceptor` that threw on HTML would run before the 5xx retry branch and spend the budget on
 * nothing. Raw bodies keep the shipped order intact.
 *
 * Retrofit still earns its place: `@Path` and `@Query` encoding correct by construction (the iOS
 * code carries a scar from getting exactly that wrong by hand — see [AniTrackService.search]),
 * suspend calls whose cancellation reaches the OkHttp call, and one readable place where the API
 * surface is stated. Retrofit's `BuiltInConverters` handles both `ResponseBody` and `RequestBody`
 * with no converter factory registered at all, which is why `converter-kotlinx-serialization` is
 * not a dependency of this module: encoding a request body happens in `ApiClient`, so that an
 * encode failure lands in the taxonomy as [ApiError.Serialization] exactly as `APIError.decoding`
 * does on iOS.
 *
 * The name is `AniTrackService`, not `AniTrackApi`: `com.anitrack.app.data.AniTrackApi` is the
 * narrow eight-call PORT the model layer declares for itself, and `ApiClientPort` adapts this
 * client onto it. Two different things, two different names.
 *
 * ── Paths begin with `/` on purpose ───────────────────────────────────────────────────────────
 *
 * `URL(string: "/search", relativeTo: base)` resolves against the AUTHORITY and discards any path
 * component of the base URL. `HttpUrl.resolve` does the same for a leading-slash path, so writing
 * every route with one reproduces iOS's resolution exactly, and a base URL of `https://host/api`
 * behaves identically on both platforms (it reaches `https://host/search`). Do not "fix" this into
 * relative paths without changing iOS too.
 */

/**
 * The bearer for one request, carried as an OkHttp request TAG rather than a header argument.
 *
 * `ApiClient` resolves which token to send — the cached one, or the one a forced refresh just
 * minted — because that decision is bound up with the session/transport split and cannot be made
 * inside an interceptor. Attaching it as a tag lets [AuthInterceptor] stay the single place that
 * knows the header's SHAPE (`Authorization: Bearer …`, plus `Accept`), while keeping the token out
 * of the declarative signatures and out of any header the logging interceptor might print.
 *
 * Deliberately a plain class and not a `value class`: an inline class erases to `String` on the
 * JVM, and the tag map is keyed by the runtime type.
 */
public class AuthToken(public val value: String)

/**
 * The `/search` result the app actually consumes: results, plus the two honesty fields the search
 * surface renders and the per-catalogue outcome map.
 *
 * Assembled by [ApiClient.search] rather than decoded, for one reason — [originalQuery] falls back
 * to the query WE sent when the server omits the echo, and only the caller knows what that was.
 *
 * (iOS ships two `search` overloads and a hazard: a bare `api.search(query:)` silently resolves to
 * the results-only one, because Swift prefers the candidate needing no defaulted arguments. Kotlin
 * has no such rule, so there is one function and callers take [franchises] when that is all they
 * want.)
 */
public data class SearchResponse(
    val franchises: List<FranchiseSummary>,
    /** The query the server actually searched, when it silently corrected ours. */
    val correctedQuery: String?,
    /** What we typed, echoed back — the "Search instead for X" half of the correction line. */
    val originalQuery: String?,
    /**
     * Per-catalogue outcome: `ok` / `failed` / `disabled`. A catalogue that FAILED is not a
     * catalogue with no matches; absent means "nothing to report", never "everything failed".
     */
    val sources: Map<String, String>?,
)

/**
 * Every route the app calls, and no route it does not.
 *
 * `GET /me/notifications` and `POST /me/notifications/read` exist in the contract and on the
 * server, and are deliberately ABSENT here: in-app alerts are locally scheduled from
 * `FranchisePart.airings`, not server rows, and iOS has never had a method for either. Adding them
 * is a product decision, not a completeness exercise.
 */
internal interface AniTrackService {

    /**
     * The only unauthenticated route. Nothing in the app calls it — it is kept as the natural
     * reachability probe, and as the one call that proves a 401 on an UNAUTHENTICATED request can
     * never end a session.
     */
    @GET("/health")
    suspend fun health(@Tag token: AuthToken?): Response<ResponseBody>

    @GET("/franchises/trending")
    suspend fun trending(
        @Tag token: AuthToken?,
        @Query("limit") limit: Int,
    ): Response<ResponseBody>

    /**
     * `q` is passed **already percent-encoded** (`encoded = true`).
     *
     * OkHttp's query-component encode set leaves `+` untouched, and a query parser is entitled to
     * read `+` as a space — so a title containing one would arrive corrupted. iOS hit the same class
     * of bug from the other end: `.urlQueryAllowed` leaves `&`, `+` and `=` unescaped, and searching
     * "X & Y" truncated at the ampersand. `ApiClient.search` therefore escapes all five of
     * `& = + ? #` itself and spells a space `%20`; Retrofit's re-encode set then leaves the `%`
     * sequences alone.
     */
    @GET("/search")
    suspend fun search(
        @Tag token: AuthToken?,
        @Query(value = "q", encoded = true) q: String,
        /** `"1"`, or null to leave the parameter off entirely. */
        @Query("exact") exact: String?,
    ): Response<ResponseBody>

    /** `country` selects the viewer's market rating; null omits the parameter. */
    @GET("/franchises/{id}")
    suspend fun franchise(
        @Tag token: AuthToken?,
        @Path("id") id: String,
        @Query("country") country: String?,
    ): Response<ResponseBody>

    @GET("/franchises/{id}/watch-providers")
    suspend fun watchProviders(
        @Tag token: AuthToken?,
        @Path("id") id: String,
        @Query("country") country: String,
    ): Response<ResponseBody>

    @GET("/me/library")
    suspend fun library(@Tag token: AuthToken?): Response<ResponseBody>

    @POST("/me/subscriptions")
    suspend fun subscribe(
        @Tag token: AuthToken?,
        @Body body: RequestBody,
    ): Response<ResponseBody>

    @PATCH("/me/subscriptions/{franchiseId}")
    suspend fun setStatus(
        @Tag token: AuthToken?,
        @Path("franchiseId") franchiseId: String,
        @Body body: RequestBody,
    ): Response<ResponseBody>

    @DELETE("/me/subscriptions/{franchiseId}")
    suspend fun unsubscribe(
        @Tag token: AuthToken?,
        @Path("franchiseId") franchiseId: String,
    ): Response<ResponseBody>

    @PUT("/me/progress")
    suspend fun setProgress(
        @Tag token: AuthToken?,
        @Body body: RequestBody,
    ): Response<ResponseBody>

    /**
     * Sends no body at all — Retrofit synthesises the empty one a POST requires.
     *
     * The one route in this app that must never be replayed: it returns the PREVIOUS
     * `lastOpenedAt` and then stamps now, so a second call answers "now" and destroys
     * "since you were last here" — the recap's whole premise. See `ApiClient.markOpened`.
     */
    @POST("/me/opened")
    suspend fun markOpened(@Tag token: AuthToken?): Response<ResponseBody>
}
