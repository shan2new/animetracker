# Networking, JSON and offline cache on Android

Research note for the Android port of AniTrack / "Previously." — **written 2026-09-04**, versions
verified against Maven Central and Google Maven `maven-metadata.xml` on that date.

Scope: the transport + serialization + on-disk-snapshot layer that replaces
`ios/Sources/Networking/APIClient.swift` (561 lines) and `AppModel`'s `library-cache.json`.

---

## 1. Recommendation

**Retrofit 3.0.0 + `converter-kotlinx-serialization` + kotlinx.serialization 1.11.0, running on
OkHttp 5.5.0 — with the request *policy* (retry, budget, token refresh, error classification)
written as a plain `suspend` wrapper above Retrofit, not inside an OkHttp `Authenticator`.**

Ktor Client 3.5.2 is a legitimate second choice and loses on a narrow, concrete point: its
`Auth`/`bearer` plugin — the thing that would otherwise be its biggest win — cannot express the
three-way refresh outcome this app's contract requires (§5). Everything else is a tie, and on
Android Ktor runs on OkHttp anyway, so choosing Ktor buys a pipeline abstraction on top of the
engine you were going to ship regardless.

### Version table (verified 2026-09-04)

| Artifact | Version | Released | Source |
|---|---|---|---|
| `com.squareup.retrofit2:retrofit` | **3.0.0** | 2025-05-15 | [Maven Central metadata](https://repo1.maven.org/maven2/com/squareup/retrofit2/retrofit/maven-metadata.xml) |
| `com.squareup.retrofit2:converter-kotlinx-serialization` | **3.0.0** | 2025-05-15 | same |
| `com.squareup.okhttp3:okhttp` | **5.5.0** | 2026-08-16 | [OkHttp CHANGELOG](https://github.com/square/okhttp/blob/master/CHANGELOG.md) |
| `com.squareup.okhttp3:mockwebserver3` | **5.5.0** | 2026-08-16 | same |
| `org.jetbrains.kotlinx:kotlinx-serialization-json` | **1.11.0** | 2026-04-10 | [kotlinx.serialization CHANGELOG](https://github.com/Kotlin/kotlinx.serialization/blob/master/CHANGELOG.md) |
| `org.jetbrains.kotlinx:kotlinx-coroutines-core` | **1.11.0** | 2026-05-08 | Maven Central metadata |
| `com.squareup.okio:okio` | **3.18.1** | 2026-07-28 | Maven Central metadata (already transitive via OkHttp 5.5.0) |
| Kotlin | **2.4.10** (latest stable; 2.4.20-RC3 exists) | — | Maven Central metadata |
| AGP | **9.4.0** | — | Google Maven metadata |
| *(rejected)* `io.ktor:ktor-client-*` | 3.5.2 | 2026-07-31 | Maven Central metadata |

Two facts to know before you sign off on Retrofit:

- **Retrofit 3.0.0 declares OkHttp 4.12 transitively.** Override it to OkHttp 5.5.0. Square
  documents that OkHttp 4 and 5 are binary compatible for non-alpha APIs, and the OkHttp 5.0.0
  release notes (2025-07-02) frame 5.x as a drop-in for 4.x. Pin `okhttp-bom` so every OkHttp
  artifact agrees.
- **Retrofit has not cut a release since 3.0.0 (2025-05-15) — ~16 months.** `trunk` is not dead:
  the [CHANGELOG's `[Unreleased]` section](https://github.com/square/retrofit/blob/trunk/CHANGELOG.md)
  carries new work (R8 keep rules, `Invocation.annotationUrl`), and the OkHttp 5.5.0 notes
  (2026-08-16) record that **Retrofit, OkHttp, Okio and SQLDelight joined the Commonhaus
  Foundation**. Retrofit is feature-complete infrastructure, not abandonware — 2.9.0 sat untouched
  from 2020 to 2024 while it ran most of the Play Store. Treat the gap as a mild risk, not a veto.

### Gradle version catalog

```toml
# gradle/libs.versions.toml
[versions]
kotlin              = "2.4.10"
ksp                 = "2.4.10-2.0.4"   # verify the matching KSP build at setup time
okhttp              = "5.5.0"
retrofit            = "3.0.0"
kotlinxSerialization = "1.11.0"
kotlinxCoroutines   = "1.11.0"

[libraries]
okhttp-bom          = { module = "com.squareup.okhttp3:okhttp-bom", version.ref = "okhttp" }
okhttp              = { module = "com.squareup.okhttp3:okhttp" }
okhttp-logging      = { module = "com.squareup.okhttp3:logging-interceptor" }
mockwebserver3      = { module = "com.squareup.okhttp3:mockwebserver3-junit5" }
retrofit            = { module = "com.squareup.retrofit2:retrofit", version.ref = "retrofit" }
retrofit-kotlinx    = { module = "com.squareup.retrofit2:converter-kotlinx-serialization", version.ref = "retrofit" }
kotlinx-serialization-json = { module = "org.jetbrains.kotlinx:kotlinx-serialization-json", version.ref = "kotlinxSerialization" }
kotlinx-coroutines  = { module = "org.jetbrains.kotlinx:kotlinx-coroutines-core", version.ref = "kotlinxCoroutines" }

[plugins]
kotlin-serialization = { id = "org.jetbrains.kotlin.plugin.serialization", version.ref = "kotlin" }
```

```kotlin
// app/build.gradle.kts
plugins { alias(libs.plugins.kotlin.serialization) }

dependencies {
    implementation(platform(libs.okhttp.bom))   // forces 5.5.0 over Retrofit's 4.12
    implementation(libs.okhttp)
    implementation(libs.okhttp.logging)
    implementation(libs.retrofit)
    implementation(libs.retrofit.kotlinx)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines)
    testImplementation(libs.mockwebserver3)
}
```

R8: kotlinx.serialization **ships consumer ProGuard rules** (bundled since the rules PR
[#2092](https://github.com/Kotlin/kotlinx.serialization/pull/2092); revised again with R8 tests in
1.10.0). You need no rules of your own **unless** a `@Serializable` class has a *named* companion
object — then add a keep rule for it. Retrofit ships its own rules. Verify with a release build,
not by reading this.

---

## 2. Why Retrofit over Ktor — the honest comparison

Both stacks decode with kotlinx.serialization, so **requirements 1–3 of the brief (unknown keys,
per-field isolation, ms-epoch Int64) do not discriminate at all.** They are settled in §3 and
apply identically to either choice. The decision turns on four things:

| | Retrofit 3 / OkHttp 5 | Ktor Client 3.5.2 |
|---|---|---|
| **Whole-request wall-clock budget** (iOS `RetryPolicy.budget` = 16.6 s shared across attempts) | `callTimeout` is a genuine whole-call budget: it spans DNS, connect, request write, server processing, response read, **and all redirects and retries**. Better than the iOS original, whose `timeoutIntervalForRequest` is an inter-packet timer that a trickling upstream defeats (the iOS code had to patch that with `timeoutIntervalForResource`). | `HttpTimeout.requestTimeoutMillis` is **per attempt**; with `HttpRequestRetry` installed each retry gets a fresh budget. A shared budget must be hand-rolled with `withTimeout`. |
| **Bearer + refresh** | No built-in. ~50 lines of `Mutex`-guarded single-flight — which is exactly what the iOS `TokenRefresher` actor already is, so it is a *port*, not new design. | `Auth { bearer { loadTokens / refreshTokens } }` is built in, and the docs state that "when multiple requests fail with 401 Unauthorized at the same time, the client performs the token refresh only once." **But `refreshTokens` returns `BearerTokens?` — a two-way answer.** The contract needs three (§5). |
| **Cancellation** | `Call<T>.await()` in `retrofit2/KotlinExtensions.kt` is `suspendCancellableCoroutine { continuation.invokeOnCancellation { cancel() } ... }` — coroutine cancel ⇒ OkHttp call cancel. | Coroutine-native throughout; the `HttpClient` owns a `Job` and cancelling it cancels every in-flight call. Marginally cleaner. |
| **Layers you ship** | Retrofit is a thin declarative facade over OkHttp. | On Android the recommended Ktor engine **is** OkHttp (`ktor-client-okhttp`). You ship OkHttp + a pipeline on top of it, plus `ktor-client-content-negotiation` + `ktor-serialization-kotlinx-json` + `ktor-client-auth`. |

**The deciding point.** `docs/api-contract.md` § "Client failure semantics" is unusually specific:

> A client that cannot **mint** a token (an expired session JWT with no network to renew it) never
> reaches the server and reports a *transport* failure — being offline must not sign anyone out. A
> forced refresh that could not reach the token issuer is likewise transport, not a dead session.
> Only an issuer that answers — with the same token, or with none — turns a `401` into a sign-out.

The iOS layer models this as a three-valued `TokenRefreshOutcome`: `.token`, `.notRefreshable`
(the issuer answered: sign out), `.failed` (the issuer was unreachable: keep the session, report
transport). Ktor's `refreshTokens` block can return a `BearerTokens` or `null`, and `null` means
"clear the tokens" — there is no way to say *"the refresh failed for network reasons; keep the
session and surface this as transport."* Bending the plugin into that shape (throwing out of
`refreshTokens` and catching it three frames up, or keeping a side-channel `AtomicReference` for
the reason) is strictly worse than writing the 50-line refresher you already have a Swift
reference implementation for.

So the one feature that would justify Ktor's extra layer is the one feature that does not fit.

**If any of these become true, revisit and pick Ktor:** (a) a Kotlin Multiplatform model layer is
in scope; (b) you need SSE or WebSockets against this backend; (c) Retrofit still has no release
by mid-2027.

---

## 3. The lenient-decoding contract

This is the load-bearing section. The iOS models satisfy "an older server decodes as empty, never
as a failure" by hand-writing `init(from:)` for every enrichment type with `try?` on *every*
field — see `ios/Sources/Models/Models+Enrichment.swift`:

```swift
init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    country    = (try? c.decode(String.self, forKey: .country)) ?? ""
    status     = (try? c.decode(Status.self, forKey: .status)) ?? .unmatched
    providers  = (try? c.decode([WatchProvider].self, forKey: .providers)) ?? []
    link       = ArtworkSet.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .link))
    attribution = (try? c.decode(String.self, forKey: .attribution)) ?? "JustWatch"
}
```

kotlinx.serialization gets you ~80 % of that from configuration and defaults. The last 20 % —
genuine per-field isolation — needs one small serializer you write once and reuse.

### 3.1 The `Json` instance

```kotlin
// data/net/ApiJson.kt
import kotlinx.serialization.json.Json

val ApiJson: Json = Json {
    // A server that grew a field must not break a client that has not.
    ignoreUnknownKeys = true

    // Coerces a LIMITED subset of bad input "as if the property was missing":
    //   - null arriving for a non-nullable property  -> the property's default
    //   - an unrecognised enum constant              -> the property's default
    // Both require the property to HAVE a default. See 3.2 and 3.4.
    coerceInputValues = true

    // Decoding: a MISSING nullable property with no default becomes null instead of throwing
    // MissingFieldException. Encoding: nulls are omitted, which keeps the offline snapshot small.
    explicitNulls = false

    // Round-trip the snapshot faithfully: defaults are written out, so a value that happens to
    // equal its default still reads back as itself and not as "absent".
    encodeDefaults = true

    // Do NOT set isLenient. The server emits RFC-compliant JSON; isLenient would let a captive
    // portal's HTML fragment parse as an unquoted string instead of failing loudly (see 6.3).
    isLenient = false

    // 1.11.0: keep response payloads out of exception messages / crash reports.
    // JetBrains state this will become the default when the flag stabilises.
    // exceptionsWithDebugInfo = false   // @ExperimentalSerializationApi in 1.11.0
}
```

Sources: the [`coerceInputValues` semantics](https://github.com/Kotlin/kotlinx.serialization/blob/master/docs/json.md)
("This property only affects decoding. It treats a limited subset of invalid input values as if
the corresponding property was missing"); `decodeEnumsCaseInsensitive`, `allowTrailingComma`,
`allowComments` and `prettyPrintIndent` were **stabilised in 1.10.0** (2026-01-21);
`exceptionsWithDebugInfo` was **added in 1.11.0** (2026-04-10).

### 3.2 Rule 1 — every field carries a default. No exceptions.

This single rule does most of the work, and it is the rule a reviewer must enforce.

```kotlin
@Serializable
data class FranchiseSummary(
    val id: String,                                   // required — a row without an id is not a row
    val title: String = "",
    val source: Source = Source.ANILIST,              // contract: "defaults to anilist when absent"
    val cover: String? = null,
    val banner: String? = null,
    val images: ArtworkSet = ArtworkSet(),
    val isReleasing: Boolean = false,
    val partCount: Int = 0,
    val nextAiringAt: Long? = null,                   // ms epoch — see 3.6
    val year: Int? = null,
    val themes: List<String> = emptyList(),
    @Serializable(with = TolerantVideo::class)
    val featuredVideo: FranchiseVideo? = null,        // see 3.5
)
```

Why it matters: **`coerceInputValues` cannot help a property with no default.** Its contract is
"treat the bad value as if the property were missing", and a missing property with no default is a
`MissingFieldException`. Defaults are what turn every coercion into a survivable one.

Corollary: keep `id` (and only `id`) required. A summary with no `id` cannot be routed to a detail
screen, so failing it is correct — and §3.5's list serializer will drop just that element.

### 3.3 Rule 2 — unknown keys

`ignoreUnknownKeys = true` globally. Prefer that to the per-class
`@JsonIgnoreUnknownKeys` annotation (introduced in 1.8.0-RC, 2024-12): the annotation is
*per class only* and does **not** cascade into nested objects, which is precisely the wrong
default for a forward-evolving API where the new field usually appears three levels down.

### 3.4 Rule 3 — enums never throw

Every enum gets a sentinel that the server never sends, and every enum-typed property defaults
to it:

```kotlin
@Serializable
enum class WatchStatus {
    @SerialName("watching")  WATCHING,
    @SerialName("planned")   PLANNED,
    @SerialName("completed") COMPLETED,
    @SerialName("dropped")   DROPPED,
    @SerialName("paused")    PAUSED,
    UNKNOWN,                                  // never emitted by the server; the coercion target
}

@Serializable
data class Subscription(
    val status: WatchStatus = WatchStatus.UNKNOWN,   // the default IS the coercion target
    val addedAt: Long? = null,
)
```

`coerceInputValues = true` + a default ⇒ `"status": "on_hold"` from a newer server lands as
`UNKNOWN` instead of throwing.

**Gotcha: `coerceInputValues` does not cover an enum inside a collection** — a `List<Kind>`
element has no "property default" to fall back on. Any enum that can appear as a bare list element
(or as a map value) needs its own tolerant serializer:

```kotlin
// data/net/TolerantEnum.kt
abstract class TolerantEnumSerializer<T : Enum<T>>(
    name: String,
    private val values: Array<T>,
    private val fallback: T,
) : KSerializer<T> {
    override val descriptor = PrimitiveSerialDescriptor(name, PrimitiveKind.STRING)
    private val bySerialName = values.associateBy { v ->
        // honour @SerialName, else the lower-cased constant name
        v::class.java.getField(v.name).getAnnotation(SerialName::class.java)?.value
            ?: v.name.lowercase()
    }
    override fun deserialize(decoder: Decoder): T =
        bySerialName[decoder.decodeString()] ?: fallback
    override fun serialize(encoder: Encoder, value: T) {
        encoder.encodeString(bySerialName.entries.first { it.value == value }.key)
    }
}

object VideoKindSerializer :
    TolerantEnumSerializer<FranchiseVideo.Kind>(
        "FranchiseVideo.Kind", FranchiseVideo.Kind.entries.toTypedArray(), FranchiseVideo.Kind.OTHER,
    )
```

(The reflection lookup runs once per enum class if you hoist `bySerialName` into a companion —
do that; the version above is written for clarity.)

### 3.5 Rule 4 — per-field failure isolation (the crux)

**Configuration cannot do this.** `coerceInputValues` handles `null`-for-non-null and unknown
enums, and nothing else — a type mismatch (`"year": "2013"` where an `Int` is declared), a
malformed nested object, an array where an object was expected: all still throw, and the throw
kills the *whole* response.

The correct primitive is a serializer that **decodes the value into a `JsonElement` first, then
tries the real serializer against that tree**:

```kotlin
// data/net/Tolerant.kt
import kotlinx.serialization.*
import kotlinx.serialization.descriptors.*
import kotlinx.serialization.encoding.*
import kotlinx.serialization.json.*
import kotlinx.serialization.builtins.ListSerializer

/**
 * Decodes T, or null when the payload for this one field is anything we cannot read.
 * ONE bad field cannot kill the object.
 *
 * The two-step (decodeJsonElement, then decodeFromJsonElement) is not stylistic: kotlinx's JSON
 * decoder is a streaming lexer with no "skip the rest of this value" operation. Catching an
 * exception thrown *out of* `delegate.deserialize(decoder)` leaves the lexer parked at an
 * arbitrary offset inside the failed value and every subsequent field decodes garbage. Consuming
 * the element first advances the cursor past the whole value exactly once, whatever happens next.
 *
 * `decodeJsonElement()` must be the FIRST thing this serializer does with the decoder — the API
 * docs warn it corrupts the position if called after partial decoding.
 */
@OptIn(ExperimentalSerializationApi::class)
open class TolerantSerializer<T : Any>(
    private val delegate: KSerializer<T>,
) : KSerializer<T?> {

    override val descriptor: SerialDescriptor =
        SerialDescriptor("Tolerant<${delegate.descriptor.serialName}>", delegate.descriptor).nullable

    override fun deserialize(decoder: Decoder): T? {
        val json = decoder as? JsonDecoder
            ?: return try { delegate.deserialize(decoder) } catch (e: SerializationException) { null }
        val element = json.decodeJsonElement()          // <- consume, always
        if (element is JsonNull) return null
        return try {
            json.json.decodeFromJsonElement(delegate, element)
        } catch (e: SerializationException) {
            null
        } catch (e: IllegalArgumentException) {          // e.g. an enum valueOf inside a custom serializer
            null
        }
    }

    override fun serialize(encoder: Encoder, value: T?) {
        if (value == null) encoder.encodeNull()
        else encoder.encodeSerializableValue(delegate, value)
    }
}

/** Drops the elements it cannot read; never fails the list. */
open class TolerantListSerializer<T>(
    private val element: KSerializer<T>,
) : KSerializer<List<T>> {

    private val strict = ListSerializer(element)
    override val descriptor: SerialDescriptor = strict.descriptor

    override fun deserialize(decoder: Decoder): List<T> {
        val json = decoder as? JsonDecoder ?: return strict.deserialize(decoder)
        val array = json.decodeJsonElement() as? JsonArray ?: return emptyList()
        return array.mapNotNull { e ->
            try { json.json.decodeFromJsonElement(element, e) }
            catch (t: SerializationException) { null }
            catch (t: IllegalArgumentException) { null }
        }
    }

    override fun serialize(encoder: Encoder, value: List<T>) = strict.serialize(encoder, value)
}

/** An empty or whitespace-only string is no value — the port of iOS `ArtworkSet.nonEmpty`. */
object NonEmptyString : KSerializer<String?> {
    override val descriptor = PrimitiveSerialDescriptor("NonEmptyString", PrimitiveKind.STRING).nullable
    override fun deserialize(decoder: Decoder): String? {
        val json = decoder as? JsonDecoder ?: return decoder.decodeString().takeIf { it.isNotBlank() }
        val e = json.decodeJsonElement()
        return (e as? JsonPrimitive)?.takeIf { it.isString }?.content?.trim()?.takeIf { it.isNotEmpty() }
    }
    override fun serialize(encoder: Encoder, value: String?) {
        if (value == null) encoder.encodeNull() else encoder.encodeString(value)
    }
}
```

Declare the concrete instances once and use them by annotation:

```kotlin
object TolerantVideo       : TolerantSerializer<FranchiseVideo>(FranchiseVideo.serializer())
object TolerantAudience    : TolerantSerializer<AudienceInfo>(AudienceInfo.serializer())
object TolerantPeople      : TolerantSerializer<FranchisePeople>(FranchisePeople.serializer())
object TolerantContinue    : TolerantSerializer<ContinueWatching>(ContinueWatching.serializer())
object TolerantWatchAvail  : TolerantSerializer<WatchAvailability>(WatchAvailability.serializer())

@Serializable
data class Franchise(
    val id: String,
    val title: String = "",
    val source: Source = Source.ANILIST,
    val images: ArtworkSet = ArtworkSet(),

    // Enrichment: an older server, or a row the stale-while-revalidate pass has not reached,
    // reads as EMPTY — never as a decode failure. (docs/api-contract.md, Catalogue enrichment)
    @Serializable(with = TolerantListSerializer::class) val parts:   List<FranchisePart> = emptyList(),
    @Serializable(with = TolerantListSerializer::class) val videos:  List<FranchiseVideo> = emptyList(),
    @Serializable(with = TolerantListSerializer::class) val related: List<RelatedTitle>   = emptyList(),
    @Serializable(with = TolerantVideo::class)    val featuredVideo:    FranchiseVideo?   = null,
    @Serializable(with = TolerantAudience::class) val audience:         AudienceInfo?     = null,
    @Serializable(with = TolerantPeople::class)   val people:           FranchisePeople?  = null,
    @Serializable(with = TolerantContinue::class) val continueWatching: ContinueWatching? = null,
    @Serializable(with = NonEmptyString::class)   val synopsis:         String?           = null,
)
```

`TolerantListSerializer` is generic with one type parameter matching `List<T>`'s, so the
compiler plugin constructs `TolerantListSerializer(FranchisePart.serializer())` for you — the
documented "custom serializer for a generic type" path.

**One deliberate improvement over iOS.** The Swift code writes
`providers = (try? c.decode([WatchProvider].self, ...)) ?? []` — one bad element empties the whole
list. `TolerantListSerializer` drops only the bad element. Both satisfy "never a failure"; the
Kotlin behaviour is strictly more useful and cannot surprise anyone. **Note it in the port log so
the difference is a decision and not a drift.**

**Where to apply it.** Not everywhere — the annotations are noise. The rule:

| Field shape | Treatment |
|---|---|
| Primitive with a default (`String`, `Int`, `Boolean`, `Long?`) | default only — a mismatch here is rare and cheap to lose |
| Enum property | default + `coerceInputValues` (§3.4) |
| Enum as a list element | `TolerantEnumSerializer` |
| Any **enrichment** object (`videos`, `people`, `related`, `audience`, `continueWatching`, `images`, `watch`) | `TolerantSerializer` / `TolerantListSerializer` |
| Any list of objects that renders a shelf | `TolerantListSerializer` |
| A URL/label string that must not be blank | `NonEmptyString` |

### 3.6 ms-epoch Int64

Nothing to do — and this is a real advantage over the Moshi/Gson family.

`Long` is a first-class primitive in kotlinx.serialization: `val at: Long` decodes the JSON number
via a dedicated integer path, not through `Double`. Gson and Moshi both decode an untyped number
as `Double` and only round-trip exactly under `2^53`; a ms epoch (~1.7 × 10¹²) is safely under
that today, but the failure mode is silent and there is no reason to accept it.

```kotlin
val at: Long? = null            // "at": 1756226400000  -> 1756226400000L, exact
```

Model the domain type separately from the wire type — but keep the wire type `Long`:

```kotlin
@JvmInline value class EpochMs(val value: Long) {
    fun toInstant(): Instant = Instant.ofEpochMilli(value)
}
```

**Do not** add a serializer that turns `Long` into `Instant`/`LocalDateTime` at the boundary. The
contract's TMDB caveat ("air *dates* only, synthesized at 17:00 UTC"; clients must not render
minute-level countdowns for `source: "tmdb"`) means the *precision* lives in a sibling field
(`release.precision`), not in the timestamp. Decoding to a wall-clock type at the boundary
launders that away. Decode `Long`, keep `release.precision`, and let the presentation layer decide
— exactly as `Util/TemporalCopy.swift` does on iOS.

Timezone: the contract says all time math is IST (`Asia/Kolkata`). That is a formatting concern;
`java.time.ZoneId.of("Asia/Kolkata")` with core library desugaring or minSdk 26+.

### 3.7 The contract test — make "older server decodes as empty" a red/green fact

The requirement is only real if it is tested. `mockwebserver3` (new coordinate in OkHttp 5.0.0;
no JUnit 4 dependency) plus a fixtures directory:

```kotlin
class LenientDecodingTest {

    private fun decode(json: String) = ApiJson.decodeFromString<Franchise>(json)

    @Test fun `unknown top-level key survives`() {
        val f = decode("""{"id":"a","title":"T","somethingNew":{"deep":[1,2]}}""")
        assertEquals("T", f.title)
    }

    @Test fun `one malformed enrichment field does not kill the object`() {
        val f = decode("""{"id":"a","title":"T","audience":"oops-a-string","people":[1,2,3]}""")
        assertEquals("T", f.title)      // the object survived
        assertNull(f.audience)          // the bad field is EMPTY
        assertNull(f.people)
    }

    @Test fun `one bad element does not kill the list`() {
        val f = decode("""{"id":"a","related":[{"title":"ok"},{"title":{"nope":1}},{"title":"ok2"}]}""")
        assertEquals(2, f.related.size)
    }

    @Test fun `unknown enum coerces to the sentinel`() {
        val s = ApiJson.decodeFromString<Subscription>("""{"status":"on_hold"}""")
        assertEquals(WatchStatus.UNKNOWN, s.status)
    }

    @Test fun `null for a non-nullable coerces to the default`() {
        val f = decode("""{"id":"a","title":null,"isReleasing":null}""")
        assertEquals("", f.title); assertFalse(f.isReleasing)
    }

    @Test fun `ms epoch is exact`() {
        val a = ApiJson.decodeFromString<Airing>("""{"episode":14,"at":1756226400000}""")
        assertEquals(1_756_226_400_000L, a.at)
    }

    /** The regression guard: every payload the server has EVER shipped still decodes. */
    @ParameterizedTest
    @MethodSource("fixtures")   // src/test/resources/wire/**.json, one per server version
    fun `every archived payload decodes`(file: File) { decode(file.readText()) }
}
```

Keep `src/test/resources/wire/` append-only: every time the contract changes, drop the *previous*
server's real response in there. That directory, not a code comment, is what enforces "an older
server decodes as empty".

---

## 4. Coroutine cancellation — the Kotlin analogue of `Error.isCancellation`

iOS treats a cancelled request as not-an-error:

```swift
var isCancellation: Bool {
    if self is CancellationError { return true }
    if (self as? URLError)?.code == .cancelled { return true }
    if let api = self as? APIError, case let .transport(inner) = api,
       (inner as? URLError)?.code == .cancelled { return true }
    return false
}
```

`reload()` and Detail's `load()` ignore it, so a superseded search keystroke or a popped screen
never paints "couldn't refresh".

### 4.1 What the runtime gives you

Cancelling a coroutine that is awaiting a Retrofit call **does** cancel the HTTP call. From
`retrofit2/KotlinExtensions.kt` on `trunk`:

```kotlin
suspend fun <T : Any> Call<T>.await(): T = suspendCancellableCoroutine { continuation ->
    continuation.invokeOnCancellation { cancel() }      // <- OkHttp Call.cancel()
    enqueue(object : Callback<T> { /* resume / resumeWithException */ })
}
```

OkHttp's own `okhttp-coroutines` README states the same guarantee in the other direction:
"Cancellation is implemented sensibly in both directions. Cancelling a coroutine scope will cancel
the call. Cancelling a call will throw a `CancellationException` but not cancel the scope if
caught."

So in the normal path the caller observes `kotlinx.coroutines.CancellationException`, not an
`IOException`. That is the direct analogue of `URLError.cancelled`.

### 4.2 The three pitfalls

**Pitfall 1 — `runCatching` swallows cancellation.** `runCatching` is `catch (e: Throwable)`, and
`CancellationException` is a `Throwable`. Swallowing it breaks structured concurrency: the child
completes "successfully", the parent's cancellation never lands, and the UI shows a result for a
screen that is gone. This is the single most common Android bug in this area. **Ban `runCatching`
in the networking layer** (a Detekt/lint rule is worth the five minutes).

**Pitfall 2 — `catch (e: Exception)` has the same defect.** Any broad catch must re-assert
liveness first.

**Pitfall 3 — a race can still surface `IOException("Canceled")`.** If OkHttp's `onFailure` fires
between the cancel and the continuation completing, or if cancellation arrives while the response
body is being read (`SocketException: Socket closed` on Android), you can see an `IOException`
rather than a `CancellationException`.

### 4.3 The pattern to use everywhere

```kotlin
// util/Cancellation.kt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

/**
 * The port of iOS `Error.isCancellation`, done the Kotlin way: instead of sniffing the error,
 * ask the coroutine whether it is still wanted. This covers CancellationException AND the
 * IOException("Canceled") / SocketException("Socket closed") race, which sniffing does not.
 *
 * Call it as the FIRST statement of every catch block in the networking layer.
 */
suspend inline fun <T> cancellationAware(block: () -> T): Result<T> =
    try {
        Result.success(block())
    } catch (e: CancellationException) {
        throw e                                   // never swallow — rethrow, always
    } catch (e: Throwable) {
        currentCoroutineContext().ensureActive()  // rethrows if WE were cancelled
        Result.failure(e)                         // a genuine failure
    }
```

Call sites then read almost exactly like the Swift:

```kotlin
suspend fun reload() {
    try {
        library = api.library().franchises
        loadError = null
    } catch (e: CancellationException) {
        throw e                                   // a superseded reload is not a failure
    } catch (e: Throwable) {
        currentCoroutineContext().ensureActive()  // ditto, for the IOException("Canceled") race
        loadError = e.toApiError()
    }
}
```

For a search field, do not hand-roll cancellation at all — `flatMapLatest` on a debounced query
`Flow` cancels the previous collector for you, and the cancellation never reaches a `catch`:

```kotlin
val results = queryFlow
    .debounce(250)
    .distinctUntilChanged()
    .flatMapLatest { q -> flow { emit(api.search(q)) } }   // supersedes in flight
    .catch { e -> currentCoroutineContext().ensureActive(); emit(SearchResult.Failed(e)) }
```

**Also**: `withContext(NonCancellable)` around cleanup that must complete after cancellation — the
snapshot write in §7 is the one place this matters.

---

## 5. Bearer token injection with refresh

Port the iOS design directly. The key architectural call: **do the refresh in a `suspend` wrapper
above Retrofit, not in an OkHttp `Authenticator`.**

Why not `Authenticator`: `okhttp3.Authenticator.authenticate(route, response)` is a **blocking**
Java-shaped API (`@Throws(IOException)`), so a `suspend` token provider (Clerk's SDK, a
`DataStore` read) requires `runBlocking` inside it. That blocks an OkHttp dispatcher thread, is
invisible to structured concurrency, and cannot be cancelled by the caller. It also cannot express
the three-way outcome cleanly. The iOS app does its refresh inside `APIClient.send`, at the Swift
level, not in a `URLProtocol` — so a wrapper is the *faithful* port as well as the better one.

OkHttp interceptors keep the jobs they are actually good at: attaching the current token, adding
`Accept`, logging, and detecting HTML bodies.

### 5.1 The token provider and the three-way outcome

```kotlin
// data/auth/TokenProvider.kt
interface TokenProvider {
    suspend fun currentToken(): String?
    /** An identity exists on this device, independent of whether a JWT can be MINTED right now. */
    suspend fun hasSession(): Boolean
    /** A FRESH token, skipping any cache. */
    suspend fun refreshedToken(): TokenRefreshOutcome
}

sealed interface TokenRefreshOutcome {
    data class Token(val value: String) : TokenRefreshOutcome
    /** FINAL answer from the issuer: nothing to renew. A 401 against this ends the session. */
    data object NotRefreshable : TokenRefreshOutcome
    /** The issuer was unreachable. Says NOTHING about the credentials — keep the session. */
    data class Failed(val cause: Throwable) : TokenRefreshOutcome
}
```

### 5.2 Single-flight refresher (port of the `TokenRefresher` actor)

```kotlin
// data/auth/TokenRefresher.kt
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Coalesces concurrent refreshes into ONE network call and reuses the result for a short window,
 * so a burst of 401s (six parallel requests on a cold launch) cannot become a refresh storm.
 */
class TokenRefresher(
    private val scope: CoroutineScope,                 // application-scoped, NOT a caller's scope
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private companion object { const val REUSE_WINDOW_MS = 3_000L }

    private val mutex = Mutex()
    private var inFlight: Deferred<TokenRefreshOutcome>? = null
    private var lastToken: String? = null
    private var lastAt: Long = 0

    suspend fun token(provider: TokenProvider): TokenRefreshOutcome {
        // ONE critical section decides all three cases, so a refresh that lands between two
        // checks cannot cause a redundant second one.
        //   - fresh token in the reuse window -> hand it back, no network at all
        //   - a refresh already in flight      -> join it
        //   - neither                          -> start exactly one
        val existing: Deferred<TokenRefreshOutcome> = mutex.withLock {
            val cached = lastToken
            if (cached != null && clock() - lastAt < REUSE_WINDOW_MS) {
                return TokenRefreshOutcome.Token(cached)
            }
            inFlight ?: scope.async { provider.refreshedToken() }.also { inFlight = it }
        }

        // await OUTSIDE the lock; a caller cancelling must not cancel the shared refresh, so the
        // Deferred is owned by an application scope and only the await is cancellable here.
        val outcome = existing.await()

        mutex.withLock {
            if (inFlight === existing) inFlight = null
            // ONLY a success primes the reuse window. Caching an unreachable-issuer failure would
            // replay it to every 401 for 3 s and turn one network blip into a session teardown.
            if (outcome is TokenRefreshOutcome.Token) { lastToken = outcome.value; lastAt = clock() }
        }
        return outcome
    }

    fun clear() { lastToken = null; lastAt = 0; inFlight = null }   // on sign-out
}
```

`scope` must be application-scoped (`CoroutineScope(SupervisorJob() + Dispatchers.Default)`).
If you build the `Deferred` on the *first caller's* scope, that caller navigating away cancels the
refresh out from under the five coroutines waiting on it. This is the one non-obvious correctness
detail in the whole file.

### 5.3 Injecting the header

```kotlin
// data/net/AuthInterceptor.kt
class AuthInterceptor(private val tokens: TokenProvider) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        if (request.header(SKIP_AUTH) != null) {
            return chain.proceed(request.newBuilder().removeHeader(SKIP_AUTH).build())
        }
        // runBlocking is acceptable ONLY because it is the last resort for a header the wrapper
        // could not attach; the happy path attaches it via the @Header parameter instead.
        val token = runBlocking { tokens.currentToken() }
        val built = request.newBuilder()
            .header("Accept", "application/json")
            .apply { token?.let { header("Authorization", "Bearer $it") } }
            .build()
        return chain.proceed(built)
    }
    companion object { const val SKIP_AUTH = "X-Skip-Auth" }
}
```

Cleaner still, and what I recommend: **pass the token as a Retrofit `@Header` parameter from the
suspend wrapper**, so no `runBlocking` appears anywhere. The interceptor then only adds `Accept`
and logs.

### 5.4 The wrapper: retry, budget, refresh, classification

```kotlin
// data/net/ApiClient.kt
import kotlinx.coroutines.*
import kotlin.random.Random

class ApiClient(
    private val service: AniTrackService,      // the Retrofit interface
    private val tokens: TokenProvider,
    private val refresher: TokenRefresher,
) {
    private companion object {
        const val BUDGET_MS   = 16_600L        // one 15 s attempt + at most ~1.6 s of backoff
        const val MIN_ATTEMPT = 2_000L
        const val MAX_RETRIES = 2
        val BACKOFF = longArrayOf(400, 1_200)
    }

    /**
     * `idempotent` is a REQUIRED argument, not a default: exactly one endpoint in this app is
     * unsafe to replay (`/me/opened`) and the next endpoint someone adds must decide consciously.
     */
    suspend fun <T> send(idempotent: Boolean, call: suspend (bearer: String?) -> T): T =
        withTimeout(BUDGET_MS) {                          // the ONE wall-clock budget
            val deadline = System.currentTimeMillis() + BUDGET_MS
            var attempt = 0
            var refreshed = false

            while (true) {
                val token = tokens.currentToken()
                try {
                    return@withTimeout call(token?.let { "Bearer $it" })
                } catch (e: CancellationException) {
                    throw e                                                   // §4
                } catch (e: Throwable) {
                    currentCoroutineContext().ensureActive()                  // §4, pitfall 3
                    val api = e.toApiError()

                    // ---- 401: refresh ONCE, then retry ------------------------------------
                    if (api is ApiError.Unauthorized && !refreshed) {
                        refreshed = true
                        when (val outcome = refresher.token(tokens)) {
                            is TokenRefreshOutcome.Token -> continue          // retry with the new one
                            // The issuer ANSWERED and had nothing. The session is gone.
                            TokenRefreshOutcome.NotRefreshable -> throw ApiError.Unauthorized
                            // The issuer was UNREACHABLE. Being offline must not sign anyone out.
                            is TokenRefreshOutcome.Failed -> throw ApiError.Transport(outcome.cause)
                        }
                    }

                    if (!api.isRetryable || !idempotent) throw api

                    val delayMs = api.retryAfterMs
                        ?: (BACKOFF[attempt.coerceIn(0, BACKOFF.lastIndex)] *
                            Random.nextDouble(0.8, 1.2)).toLong()
                    // A retry is only worth starting if enough budget survives the sleep.
                    if (attempt >= MAX_RETRIES ||
                        deadline - System.currentTimeMillis() - delayMs < MIN_ATTEMPT) throw api
                    attempt++
                    delay(delayMs)
                }
            }
            @Suppress("UNREACHABLE_CODE") error("unreachable")
        }

    suspend fun library(): LibraryResponse = send(idempotent = true) { service.library(it) }
    suspend fun markOpened(): OpenedResponse = send(idempotent = false) { service.markOpened(it) }
    // ...
}
```

`withTimeout` gives the shared wall-clock budget; `callTimeout` on the OkHttp client bounds each
individual attempt (§6.1). Cancellation from `withTimeout` is a `TimeoutCancellationException`,
which **is** a `CancellationException` — so if the whole budget blows, callers using the §4
pattern would treat it as "not an error". That is wrong. Catch it explicitly at the `send`
boundary:

```kotlin
} catch (e: TimeoutCancellationException) {
    throw ApiError.Transport(e)          // the budget expired: a real failure, not a supersede
}
```

Wrap the `withTimeout(...)` call in that catch. **Order matters** — `TimeoutCancellationException`
must be caught *before* the generic `CancellationException` rethrow.

### 5.5 Sign-out is a boundary, not a state

On sign-out: `refresher.clear()`, wipe the snapshot (§7), and cancel the app-scoped refresh scope's
children — the iOS `teardown()` contract, "the next account inherits nothing."

---

## 6. Timeouts and error classification

### 6.1 The OkHttp client

```kotlin
// data/net/HttpClient.kt
fun okHttpClient(auth: AuthInterceptor, debug: Boolean): OkHttpClient =
    OkHttpClient.Builder()
        // The per-ATTEMPT ceiling. Unlike URLSession's timeoutIntervalForRequest (an inter-packet
        // timer that a trickling upstream defeats), callTimeout is real wall clock: it spans DNS,
        // connect, request write, server processing, response read, redirects and OkHttp's own
        // retries. The iOS side needed timeoutIntervalForResource to plug that hole; we do not.
        .callTimeout(15, TimeUnit.SECONDS)
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .writeTimeout(15, TimeUnit.SECONDS)
        // OkHttp's own transparent retry, which would double-count against our budget.
        .retryOnConnectionFailure(true)
        .addInterceptor(auth)
        .addInterceptor(HtmlBodyInterceptor())
        .apply { if (debug) addInterceptor(HttpLoggingInterceptor().setLevel(BASIC)) }
        .build()
```

OkHttp 5 moved the `Duration` overloads to `kotlin.time.Duration`; the `(long, TimeUnit)` overloads
are 4.x API and remain binary-compatible, so the snippet above compiles against both. Prefer
`15.seconds` if you are on 5.x only.

Never log at `Level.BODY` in a build that could ship — the library payload contains the user's
whole watch history.

### 6.2 The error model

```kotlin
sealed class ApiError(cause: Throwable? = null) : Exception(cause) {
    /** A 401 that survived a forced token refresh. The session is gone. */
    data object Unauthorized : ApiError()
    /** 403, a WAF/captive-portal HTML body at any status, or a non-JSON payload.
     *  The credentials were never the problem — KEEP the session, show stale / no-cache. */
    data class Infrastructure(val status: Int, val kind: String) : ApiError()
    data class RateLimited(val retryAfterMs: Long?) : ApiError()
    data class Http(val status: Int, val body: String) : ApiError()
    data class Decoding(val error: Throwable) : ApiError(error)
    data class Transport(val error: Throwable) : ApiError(error)

    val isSessionEnding: Boolean get() = this is Unauthorized
    val isRetryable: Boolean get() = when (this) {
        is RateLimited -> true
        is Http -> status in 500..599
        is Transport -> true
        else -> false
    }
    val retryAfterMs: Long? get() = (this as? RateLimited)?.retryAfterMs
}
```

Mapping (`Throwable.toApiError()`):

| Thrown | Becomes |
|---|---|
| `retrofit2.HttpException`, 401 | `Unauthorized` (the wrapper decides whether to refresh) |
| `HttpException`, 403 | `Infrastructure(403, "forbidden")` |
| `HttpException`, 429 | `RateLimited(parseRetryAfter(...))`, clamped to ≤ 8 s |
| `HttpException`, other | `Http(code, errorBody)` |
| `kotlinx.serialization.SerializationException` | `Decoding` — but see 6.3 |
| `java.io.IOException` / `SocketTimeoutException` | `Transport` |
| `TimeoutCancellationException` | `Transport` (§5.4) |

Retrofit **buffers** non-2xx bodies into memory before constructing the failed `Response`, so
`e.response()?.errorBody()?.string()` is safe to read in the mapper and does not need a
`peekBody`.

**1.11.0 makes decoding failures diagnosable.** `JsonDecodingException` is now public with
`shortMessage`, `path` and `offset` properties. Log `path` — it names the field that failed —
while keeping `exceptionsWithDebugInfo = false` so the payload itself never reaches a crash
reporter.

### 6.3 The HTML-body rule

`docs/api-contract.md`: *"Any response whose body is HTML is treated the same way at any status,
including 2xx (captive portals)."* This must be caught **before** the converter, or a captive
portal reads as `Decoding` (a bug) instead of `Infrastructure` (the truth):

```kotlin
class HtmlBodyInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val response = chain.proceed(chain.request())
        val type = response.header("Content-Type").orEmpty()
        val looksHtml = type.startsWith("text/html", ignoreCase = true) ||
            response.peekBody(512).string().trimStart().startsWith("<")   // peek does NOT consume
        if (looksHtml) throw ApiError.Infrastructure(response.code, "html")
        return response
    }
}
```

An `Interceptor` may only throw `IOException`, so make `ApiError` extend `IOException` (or wrap it
in one and unwrap in the mapper). This is the one place the sealed hierarchy has to bend to the
platform; pick one and comment it.

---

## 7. The offline snapshot cache

iOS (`AppModel.swift`): a `library-cache.json` in Application Support, holding
`{ response, savedAt }`, read once at `start()` when `library.isEmpty`, written atomically after
every successful `reload()` off the main actor, removed on `teardown()`. `savedAt` is the real
stamp so `StaleStrip` / `InlineNotice` tell the truth.

### Recommendation: Okio + kotlinx.serialization, one file, atomic rename

```kotlin
// data/cache/LibrarySnapshotStore.kt
import kotlinx.coroutines.*
import kotlinx.serialization.Serializable
import okio.FileSystem
import okio.Path
import okio.Path.Companion.toOkioPath

@Serializable
data class LibrarySnapshot(
    /** Bumped whenever the model shape changes. A mismatch is "no cache", never a migration. */
    val schemaVersion: Int = CURRENT,
    /** ms epoch — the REAL age, so the stale strip cannot lie. */
    val savedAt: Long,
    val response: LibraryResponse,
) { companion object { const val CURRENT = 1 } }

class LibrarySnapshotStore(
    filesDir: java.io.File,
    private val fs: FileSystem = FileSystem.SYSTEM,     // FakeFileSystem in unit tests
    private val io: CoroutineDispatcher = Dispatchers.IO,
) {
    private val path: Path = filesDir.resolve("library-cache.json").toOkioPath()
    private val tmp: Path = filesDir.resolve("library-cache.json.tmp").toOkioPath()

    /** Never throws. A missing, truncated, corrupt or stale-schema file is simply no cache. */
    suspend fun read(): LibrarySnapshot? = withContext(io) {
        try {
            if (!fs.exists(path)) return@withContext null
            val text = fs.read(path) { readUtf8() }
            ApiJson.decodeFromString<LibrarySnapshot>(text)
                .takeIf { it.schemaVersion == LibrarySnapshot.CURRENT }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            currentCoroutineContext().ensureActive()
            runCatching { fs.delete(path) }     // a file we cannot read is a file we do not keep
            null
        }
    }

    /**
     * Write-then-rename. rename(2) within one filesystem is atomic, so a launch can never read a
     * half-written file — the exact guarantee of iOS `Data.write(options: .atomic)`.
     *
     * NonCancellable because this runs at the tail of reload(): the screen it belongs to may
     * already be gone, and a half-finished cache write is worse than a missed one.
     */
    suspend fun write(response: LibraryResponse, savedAt: Long) = withContext(io + NonCancellable) {
        try {
            val text = ApiJson.encodeToString(LibrarySnapshot(savedAt = savedAt, response = response))
            fs.write(tmp) { writeUtf8(text) }
            fs.atomicMove(tmp, path)
        } catch (e: Throwable) {
            runCatching { fs.delete(tmp) }      // best effort; a failed cache write is not an error
        }
    }

    /** The copy belongs to the account that fetched it; sign-out removes it. */
    suspend fun clear() = withContext(io + NonCancellable) {
        runCatching { fs.delete(path) }; runCatching { fs.delete(tmp) }
    }
}
```

Wire-up mirrors `AppModel.start()`:

```kotlin
// The offline copy FIRST: a launch with no network opens on the shows, stamped with their real
// age, rather than on an error where the library was.
if (library.isEmpty()) snapshots.read()?.let { snap ->
    library      = snap.response.franchises
    prevOpenedAt = maxOf(prevOpenedAt, snap.response.prevOpenedAt)
    lastLoadedAt = snap.savedAt
}
```

### Why not DataStore

DataStore is the platform-blessed answer and is wrong for *this* shape:

- `DataStore.updateData { }` is a read-modify-write **transaction**: it deserializes the existing
  value before writing the new one. Here the new value wholly replaces the old, so every
  successful `reload()` would pay an extra full parse of the previous snapshot for nothing.
- The docs themselves say: *"If you need to support large or complex datasets, partial updates, or
  referential integrity, consider using Room instead of DataStore. DataStore is ideal for small
  datasets."* A whole library payload sits in the awkward middle.
- Okio is already on the classpath (OkHttp 5.5.0 → Okio 3.18.1) and `FakeFileSystem` makes the
  store unit-testable with no Robolectric.

What DataStore *does* get right and you must therefore hand-write: atomicity (covered by
`atomicMove`), corruption handling (covered by delete-and-return-null), and off-main-thread I/O
(covered by `withContext(io)`). If those three are in the code, DataStore adds nothing here.

Use DataStore (`datastore-core` **1.2.1** stable; 1.3.0 is alpha10) for the *small* things —
last-opened tab, notification opt-in, the dismissed-sync-banner flag — where its `Flow` and
`SharedPreferences` migration genuinely help. Use **Room 2.8.4** if the snapshot ever needs
per-franchise reads or partial updates; that is a different design, not a bigger file.

### Three Android-specific findings that have no iOS counterpart

1. **`allowBackup` will ship this file to Google Drive.** Android auto-backup is on by default;
   the snapshot contains the user's whole library. iOS Application Support is likewise in iCloud
   backup, so parity argues "leave it" — but a restored backup on a *different* signed-in account
   would open on a stale foreign library before the first `reload()` lands. Exclude it:

   ```xml
   <!-- res/xml/data_extraction_rules.xml (Android 12+) and backup_rules.xml (11 and below) -->
   <data-extraction-rules>
     <cloud-backup><exclude domain="file" path="library-cache.json"/></cloud-backup>
     <device-transfer><exclude domain="file" path="library-cache.json"/></device-transfer>
   </data-extraction-rules>
   ```

2. **`filesDir`, never `cacheDir`.** `cacheDir` is evictable by the OS under storage pressure;
   this is a *snapshot*, not a cache, and losing it silently reintroduces the exact bug the iOS
   note records ("a bad connection at launch was 'Couldn't reach the server' over nothing").

3. **Do not put the token here.** `androidx.security:security-crypto` was
   [deprecated in April 2025 at 1.1.0-alpha07](https://proandroiddev.com/goodbye-encryptedsharedpreferences-a-2026-migration-guide-4b819b4a537a);
   `EncryptedSharedPreferences` is no longer the answer. Let the auth SDK own token storage — that
   belongs to the auth research note, not this one.

---

## 8. Alternatives rejected

| Rejected | Why |
|---|---|
| **Ktor Client 3.5.2** | Close second. Its `bearer` plugin's `refreshTokens` returns `BearerTokens?` — a two-way answer where the contract needs three (token / issuer-said-no / issuer-unreachable), and conflating the last two signs offline users out. Secondary: `requestTimeoutMillis` is per-attempt, so the 16.6 s shared budget is hand-rolled anyway; and on Android its recommended engine is OkHttp, so it is a layer *above* the client you were shipping. **Revisit if KMP, SSE or WebSockets enter scope.** |
| **Moshi** (`moshi-kotlin-codegen`) | Excellent library, wrong shape here. Its adapters throw `JsonDataException` on the first bad field with no tree-decode escape hatch as clean as `JsonDecoder.decodeJsonElement()`; per-field tolerance means a hand-written adapter per class — i.e. reproducing the iOS `init(from:)` boilerplate rather than replacing it. `@Json(name=)` + `EnumJsonAdapter.create(...).withUnknownFallback(...)` covers enums well, but not the rest. |
| **Gson** | Untyped numbers become `Double`; silently lossy for Int64. Reflection-based, hostile to R8 full mode, and effectively unmaintained. No. |
| **Jackson (`jackson-module-kotlin`)** | The most *capable* answer to per-field tolerance (`DeserializationProblemHandler`, `FAIL_ON_*` switches) and the worst fit for Android: large method count, reflection-heavy, slow cold start. |
| **Plain OkHttp + `okhttp-coroutines` `executeAsync()`, no Retrofit** | Genuinely viable — Retrofit is thin sugar and this app has ~12 endpoints. Rejected because Retrofit's `@Query`/`@Path` encoding is correct by construction, and the iOS code carries a scar from getting exactly that wrong by hand (`strictQueryValueAllowed` exists because `&`/`+`/`=` truncated a search query). Do not re-earn that bug. |
| **DataStore for the library snapshot** | See §7 — read-modify-write cost, and Google's own "not for large datasets" guidance. |
| **Room for the library snapshot** | Right answer for a different design (per-franchise reads, partial updates, queries). The iOS model is a single blob; matching it toe-to-toe means a single file. Keep Room in the back pocket. |
| **`@JsonIgnoreUnknownKeys` per class instead of the global flag** | It does not cascade into nested objects — the wrong default when new fields appear three levels deep. |
| **Decoding ms-epoch straight into `Instant` at the boundary** | Launders the `release.precision` distinction that the TMDB date-only rule depends on. Decode `Long`; let presentation decide. |
| **`runCatching` anywhere in the networking layer** | Catches `CancellationException`. Ban it. |

---

## 9. Open questions — need a human decision

1. **Is a Kotlin Multiplatform model layer in scope, now or later?** This is the one input that
   flips the recommendation to Ktor outright. The iOS app is Swift and the models are hand-written
   Swift `Codable`, so a shared layer means rewriting both sides — but if that is on the roadmap,
   choose Ktor on day one rather than migrating later.

2. **Which auth SDK provides the token, and does it expose the "issuer answered vs issuer
   unreachable" distinction?** Everything in §5 rests on `TokenProvider.refreshedToken()` being
   able to return three outcomes. Clerk's iOS SDK lets the app derive it. If Clerk's Android SDK
   (or whatever replaces it) collapses a network failure and a dead session into one error, the
   contract's "being offline must not sign anyone out" rule cannot be honoured and needs a
   different implementation — possibly a connectivity check as a tiebreaker. **Resolve this before
   writing §5's code.** It belongs to the auth research note; flagging the dependency here.

3. **Tolerant-list divergence: drop the bad element (proposed) or empty the whole list (iOS)?**
   §3.5. I recommend dropping the element; it needs an explicit yes so it is a decision, not drift.

4. **`minSdk`.** The iOS floor is 18 — very recent. A matching Android posture would be high
   (API 31+?), which decides whether `java.time` needs core library desugaring and whether
   `android.util.AtomicFile`'s pre-API-30 backup-file behaviour is even reachable. The
   TOOLCHAIN.md emulator is API 36.

5. **Exclude the library snapshot from Android auto-backup?** §7, finding 1. I lean yes (a
   restored backup on a different account showing a stale foreign library is a bad first frame);
   it is a small divergence from iOS, which does back the file up to iCloud.

6. **`exceptionsWithDebugInfo = false`?** It is `@ExperimentalSerializationApi` in 1.11.0 and
   JetBrains say it will become the default. Turning it on now costs debuggability in dev builds
   and buys privacy in release builds. Suggest: on in release, off in debug — needs a build-type
   split in the `Json` factory, which is a two-line decision someone should make deliberately.

7. **Does the backend ever return `WWW-Authenticate` on 401?** Not needed for the recommended
   stack (OkHttp/our wrapper key off the status code alone), but if the Ktor decision is ever
   revisited, note that Ktor 3.5.2 documents: *"If the client has only one authentication provider
   installed, the `Auth` plugin always attempts that provider when the server returns 401
   Unauthorized, even if the `WWW-Authenticate` header is missing."* So it would work either way —
   recorded here so nobody re-researches it.

---

## Sources

- [kotlinx.serialization CHANGELOG](https://github.com/Kotlin/kotlinx.serialization/blob/master/CHANGELOG.md) — 1.11.0 (2026-04-10), 1.10.0 (2026-01-21), 1.9.0 (2025-06-27), 1.8.0-RC (`@JsonIgnoreUnknownKeys`)
- [kotlinx.serialization JSON docs](https://github.com/Kotlin/kotlinx.serialization/blob/master/docs/json.md) — `coerceInputValues`, `explicitNulls`, `isLenient`, `decodeEnumsCaseInsensitive`
- [`JsonBuilder.ignoreUnknownKeys`](https://kotlinlang.org/api/kotlinx.serialization/kotlinx-serialization-json/kotlinx.serialization.json/-json-builder/ignore-unknown-keys.html) and [`JsonDecoder.decodeJsonElement`](https://kotlinlang.org/api/kotlinx.serialization/kotlinx-serialization-json/kotlinx.serialization.json/-json-decoder/decode-json-element.html)
- [kotlinx.serialization bundled ProGuard rules PR #2092](https://github.com/Kotlin/kotlinx.serialization/pull/2092)
- [Retrofit CHANGELOG (`trunk`)](https://github.com/square/retrofit/blob/trunk/CHANGELOG.md) — 3.0.0 (2025-05-15), `[Unreleased]`
- [Retrofit `KotlinExtensions.kt`](https://github.com/square/retrofit/blob/trunk/retrofit/src/main/java/retrofit2/KotlinExtensions.kt) — `suspendCancellableCoroutine` + `invokeOnCancellation { cancel() }`
- [Retrofit kotlinx-serialization converter `Serializer.kt`](https://github.com/square/retrofit/blob/trunk/retrofit-converters/kotlinx-serialization/src/main/java/retrofit2/converter/kotlinx/serialization/Serializer.kt) — `format.decodeFromString(loader, body.string())`
- [OkHttp CHANGELOG](https://github.com/square/okhttp/blob/master/CHANGELOG.md) — 5.5.0 (2026-08-16, Commonhaus note), 5.4.0 (2026-06-08), 5.0.0 stable (2025-07-02), `mockwebserver3`
- [OkHttp `okhttp-coroutines` README](https://github.com/square/okhttp/blob/master/okhttp-coroutines/README.md) — bidirectional cancellation
- [`OkHttpClient.Builder.callTimeout`](https://square.github.io/okhttp/5.x/okhttp/okhttp3/-ok-http-client/-builder/call-timeout.html) — spans the complete call including redirects and retries
- [`okhttp3.Authenticator`](https://github.com/square/okhttp/blob/master/okhttp/src/commonJvmAndroid/kotlin/okhttp3/Authenticator.kt) — reactive 401 authentication, blocking contract
- [Ktor: Bearer authentication in Ktor Client (3.5.2)](https://ktor.io/docs/client-bearer-auth.html) — `loadTokens` / `refreshTokens` / `markAsRefreshTokenRequest`, single refresh on concurrent 401s
- [Ktor: Authentication and authorization in Ktor Client (3.5.2)](https://ktor.io/docs/client-auth.html) — single-provider behaviour without `WWW-Authenticate`
- [Ktor: Retrying failed requests](https://ktor.io/docs/client-request-retry.html) and [Timeout](https://ktor.io/docs/client-timeout.html) — `requestTimeoutMillis` is per attempt
- [Android: DataStore](https://developer.android.com/topic/libraries/architecture/datastore) — custom `Serializer<T>`, `ReplaceFileCorruptionHandler`, "not for large datasets", 1.2.1 stable
- [Kotlin: Cancellation and timeouts](https://kotlinlang.org/docs/cancellation-and-timeouts.html) and [Cancellation in Kotlin Coroutines (kt.academy)](https://kt.academy/article/cc-cancellation) — `CancellationException`, `ensureActive`, the `runCatching` pitfall
- [Goodbye EncryptedSharedPreferences: A 2026 Migration Guide (ProAndroidDev / droidcon)](https://www.droidcon.com/2025/12/16/goodbye-encryptedsharedpreferences-a-2026-migration-guide/) — `androidx.security:security-crypto` deprecated April 2025
- Version numbers and dates for every artifact: `maven-metadata.xml` from `repo1.maven.org` and `dl.google.com/dl/android/maven2`, fetched 2026-09-04. (Note: `search.maven.org`'s Solr index was stale by ~15 months on that date — do not use it for currency checks.)
- Project sources read: `ios/Sources/Networking/APIClient.swift`, `ios/Sources/Models/Models+Enrichment.swift`, `ios/Sources/App/AppModel.swift`, `docs/api-contract.md`, `docs/android-port/TOOLCHAIN.md`
