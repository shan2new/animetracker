@file:OptIn(ExperimentalSerializationApi::class)

package com.anitrack.model

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.SerialKind
import kotlinx.serialization.descriptors.nullable
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive

/*
 * Wire types for the AniTrack REST API (docs/api-contract.md), ported from
 * `ios/Sources/Models/Models.swift`. The enrichment half lives in `ModelsEnrichment.kt`, mirroring
 * `Models+Enrichment.swift`.
 *
 * Three house rules govern this file, and none of them is style:
 *
 *  1. TIME IS `Long` MILLISECONDS SINCE THE UNIX EPOCH — never `Instant`, never a wall-clock type,
 *     on the wire. TMDB's instants are date-only facts synthesized at 17:00 UTC, so the *precision*
 *     lives in a sibling field (`release.precision`) and in the source's calendar anchor, not in the
 *     number. Decoding to a wall-clock type at the boundary launders that away.
 *
 *  2. EVERY TYPE IS AN IMMUTABLE `data class`. `Franchise.snapshotForUndo` is free only because the
 *     whole graph is a value — parts, progress and status frozen at the instant of a removal, which
 *     is what lets Undo restore before any network round-trip. Never hand-build a `FranchisePart`;
 *     always `copy()`. A hand-written constructor call silently omits a newer field, and that is
 *     exactly how `airings` once fell off an optimistic mark and took a show off the calendar until
 *     the next reload.
 *
 *  3. LENIENT DECODING IS A CONTRACT, NOT A NICETY. A server older than a field, or a row the
 *     backend's stale-while-revalidate pass has not reached, must read as EMPTY — never as a decode
 *     failure that drops the whole franchise. The screens hide an empty section and draw it when it
 *     arrives; nothing here may throw past the franchise. The handful of fields that DO throw are
 *     each marked, with the reason, at their declaration.
 *
 * Compose stability: `:model` compiles without the Compose plugin, so these classes carry no
 * `@StabilityInferred` metadata and every `List` makes them inferred-unstable. `:app` must list
 * `com.anitrack.model.**` in its `stabilityConfigurationFile` (PLAN R36), or every row composable
 * becomes non-skippable and the clock ticks recompose whole screens.
 */

// ---------------------------------------------------------------------------------------------
// MARK: - The decoding contract
// ---------------------------------------------------------------------------------------------

/**
 * The one [Json] the app decodes and encodes with.
 *
 * iOS gets per-field leniency from `try? c.decode(...)` inside every hand-written `init(from:)`.
 * kotlinx.serialization's default is the opposite — a type mismatch throws and kills the whole
 * response — so the leniency is reconstructed here from four flags plus the delegating serializers
 * below. Configuration alone is NOT equivalent: `coerceInputValues` covers only `null`-for-non-null
 * and unknown enum constants, and only for properties that have a default.
 */
public val AniTrackJson: Json = Json {
    // A server that grew a field must not break a client that has not.
    ignoreUnknownKeys = true

    // Coerces a limited subset of bad input "as if the property were missing": null arriving for a
    // non-nullable property, and an unrecognised enum constant. Both need the property to HAVE a
    // default. Belt-and-braces here — every enum-typed property also carries an explicit lenient
    // serializer, because coercion does not cover a type mismatch.
    coerceInputValues = true

    // Decoding: a missing nullable property with no default reads as null instead of throwing.
    // Encoding: nulls are omitted, which is what Swift's `encodeIfPresent` does and what keeps the
    // offline library snapshot small.
    explicitNulls = false

    // Round-trip the offline snapshot faithfully: a value that happens to equal its default still
    // reads back as itself rather than as "absent".
    encodeDefaults = true

    // Deliberately NOT lenient. The server emits RFC-compliant JSON; `isLenient` would let a
    // captive portal's HTML fragment parse as an unquoted string instead of failing loudly.
    isLenient = false
}

/**
 * An empty string is no value — the port of iOS `ArtworkSet.nonEmpty`.
 *
 * Trims Swift's `CharacterSet.whitespaces` (Unicode general category Zs plus CHARACTER TABULATION)
 * only — **not newlines** — and returns the ORIGINAL, untrimmed string when something is left.
 * Both halves are load-bearing: a value that is only a newline survives, and a URL is never
 * silently rewritten on its way through.
 */
internal fun nonEmptyOrNull(s: String?): String? {
    if (s == null) return null
    val trimmed = s.trim { it == '\t' || Character.getType(it) == Character.SPACE_SEPARATOR.toInt() }
    return if (trimmed.isEmpty()) null else s
}

/**
 * Reports a delegate's descriptor as an opaque STRING when the delegate is an ENUM.
 *
 * **This is load-bearing, not cosmetic — without it the entire library payload fails to decode.**
 *
 * `AniTrackJson` sets `coerceInputValues = true`, and kotlinx runs that coercion *before* a
 * property's own deserializer, keyed on the kind the property's serializer ADVERTISES. For an
 * ENUM-kind element it calls `lexer.peekString()` to see whether the constant is recognised — and
 * that "peek" consumes: the string is lifted off the input and stashed in the lexer's `peekedString`
 * slot. `decodeString()` reads the stash, so an ordinary enum property never notices. But every
 * wrapper below is built on `decodeJsonElement()`, which reads the raw cursor, and the cursor is now
 * parked on the delimiter AFTER the value — so it dies on `Unexpected JSON token … unexpected
 * comma`, and takes the whole response with it.
 *
 * `source` is the second field of the first franchise on the wire, so the symptom was not a missing
 * badge on one show: it was "Couldn't load your library" on every screen, against a server returning
 * a perfectly good 220 kB of JSON.
 *
 * Declaring STRING is honest rather than evasive — the wire form of every one of these enums IS a
 * string, and the wrappers are strictly better at the job the coercion was doing: an unrecognised
 * constant, a null, and a type mismatch (which `coerceInputValues` never covered at all) all land on
 * the fallback. `coerceInputValues` stays on for enum properties that carry no wrapper.
 */
private fun SerialDescriptor.opaqueIfEnum(): SerialDescriptor =
    if (kind == SerialKind.ENUM) PrimitiveSerialDescriptor(serialName, PrimitiveKind.STRING) else this

/**
 * Decodes [T], or null when the payload for this ONE field is anything we cannot read. One bad
 * field never kills the object — the port of `try? c.decodeIfPresent(T.self, forKey:)`.
 *
 * The two-step (`decodeJsonElement`, then `decodeFromJsonElement`) is not stylistic. kotlinx's JSON
 * decoder is a streaming lexer with no "skip the rest of this value" operation: catching an
 * exception thrown *out of* `delegate.deserialize(decoder)` leaves the lexer parked at an arbitrary
 * offset inside the failed value, and every subsequent field then decodes garbage. Consuming the
 * element first advances the cursor past the whole value exactly once, whatever happens next — and
 * `decodeJsonElement()` must be the FIRST thing done with the decoder.
 *
 * Which is exactly why the descriptor goes through [opaqueIfEnum]: for an ENUM-kind element the
 * format consumes the value before this class is ever entered, and "first" stops being first.
 */
public open class SafeSerializer<T : Any>(
    private val delegate: KSerializer<T>,
) : KSerializer<T?> {

    override val descriptor: SerialDescriptor = delegate.descriptor.opaqueIfEnum().nullable

    override fun deserialize(decoder: Decoder): T? {
        val json = decoder as? JsonDecoder ?: return try {
            delegate.deserialize(decoder)
        } catch (e: SerializationException) {
            null
        }
        val element = json.decodeJsonElement()
        if (element is JsonNull) return null
        return try {
            json.json.decodeFromJsonElement(delegate, element)
        } catch (e: SerializationException) {
            null
        } catch (e: IllegalArgumentException) {
            // e.g. an enum lookup inside a nested custom serializer.
            null
        } catch (e: IndexOutOfBoundsException) {
            // A non-string where an enum was expected: the tree decoder resolves the constant to
            // UNKNOWN_NAME (-3) and then indexes the name table with it. Not an
            // IllegalArgumentException, and not a bug we can pre-empt by inspecting the element —
            // the same shape is thrown from nested enums we never see.
            null
        }
    }

    override fun serialize(encoder: Encoder, value: T?) {
        if (value == null) encoder.encodeNull() else encoder.encodeSerializableValue(delegate, value)
    }
}

/**
 * The same isolation for a non-nullable property: [fallback] when the field is null or the wrong
 * shape — the port of `(try? c.decode(T.self, forKey:)) ?? default`.
 */
public open class SafeValueSerializer<T : Any>(
    private val delegate: KSerializer<T>,
    private val fallback: T,
) : KSerializer<T> {

    override val descriptor: SerialDescriptor = delegate.descriptor.opaqueIfEnum()

    override fun deserialize(decoder: Decoder): T {
        val json = decoder as? JsonDecoder ?: return try {
            delegate.deserialize(decoder)
        } catch (e: SerializationException) {
            fallback
        }
        val element = json.decodeJsonElement()
        if (element is JsonNull) return fallback
        return try {
            json.json.decodeFromJsonElement(delegate, element)
        } catch (e: SerializationException) {
            fallback
        } catch (e: IllegalArgumentException) {
            fallback
        } catch (e: IndexOutOfBoundsException) {
            // See SafeSerializer.deserialize — an enum name table indexed with UNKNOWN_NAME.
            fallback
        }
    }

    override fun serialize(encoder: Encoder, value: T) = encoder.encodeSerializableValue(delegate, value)
}

/**
 * A list that never fails — and, **deliberately, one malformed element empties the WHOLE array**
 * rather than being dropped on its own (PLAN D24).
 *
 * This is parity with iOS, where `(try? c.decode([T].self, forKey:)) ?? []` fails the array as a
 * unit, and it is chosen rather than inherited: an element-wise drop would be *more* useful in
 * isolation, but it would make the two clients disagree about how much of a shelf one bad row
 * costs, and the golden-fixture corpus replays both. Revisit it as a product decision, never as a
 * quiet improvement.
 *
 * [keep] is the post-decode filter iOS applies immediately after the array decode; it runs only on
 * an array that decoded whole.
 */
public open class SafeListSerializer<T>(
    element: KSerializer<T>,
) : KSerializer<List<T>> {

    private val strict = ListSerializer(element)

    override val descriptor: SerialDescriptor = strict.descriptor

    /** Post-decode filter. Keeps everything unless a subclass narrows it. */
    protected open fun keep(value: T): Boolean = true

    override fun deserialize(decoder: Decoder): List<T> {
        val json = decoder as? JsonDecoder ?: return try {
            strict.deserialize(decoder).filter { keep(it) }
        } catch (e: SerializationException) {
            emptyList()
        }
        val decoded = json.decodeJsonElement()
        if (decoded !is JsonArray) return emptyList()
        return try {
            json.json.decodeFromJsonElement(strict, decoded).filter { keep(it) }
        } catch (e: SerializationException) {
            emptyList()
        } catch (e: IllegalArgumentException) {
            emptyList()
        }
    }

    override fun serialize(encoder: Encoder, value: List<T>) = strict.serialize(encoder, value)
}

/** `(try? c.decode(String.self, …)) ?? ""`. */
public object LenientString : SafeValueSerializer<String>(String.serializer(), "")

/** `(try? c.decode(String.self, forKey: .title)) ?? "Untitled"` — the one non-empty string default. */
public object LenientTitle : SafeValueSerializer<String>(String.serializer(), "Untitled")

/** `(try? c.decode(Int.self, …)) ?? 0`. */
public object LenientInt : SafeValueSerializer<Int>(Int.serializer(), 0)

/** `(try? c.decode(Bool.self, …)) ?? false`. */
public object LenientBool : SafeValueSerializer<Boolean>(Boolean.serializer(), false)

/** `try? c.decodeIfPresent(String.self, …)`. */
public object LenientStringOrNull : SafeSerializer<String>(String.serializer())

/** `try? c.decodeIfPresent(Int.self, …)`. */
public object LenientIntOrNull : SafeSerializer<Int>(Int.serializer())

/** `try? c.decodeIfPresent(Int64.self, …)` — ms epoch. */
public object LenientLongOrNull : SafeSerializer<Long>(Long.serializer())

/** `try? c.decodeIfPresent(Bool.self, …)`. */
public object LenientBoolOrNull : SafeSerializer<Boolean>(Boolean.serializer())

/** `(try? c.decode([String].self, …)) ?? []`. */
public object StringListSerializer : SafeListSerializer<String>(String.serializer())

/** `try? c.decodeIfPresent([String: String].self, …)` — the search response's per-catalogue outcome. */
public object SafeStringMap :
    SafeSerializer<Map<String, String>>(MapSerializer(String.serializer(), String.serializer()))

/**
 * `ArtworkSet.nonEmpty(try? c.decodeIfPresent(String.self, …))` as one serializer: a non-string, a
 * null, or a blank string all read as no value, and a real value comes through untouched.
 */
public object NonEmptyString : KSerializer<String?> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("com.anitrack.model.NonEmptyString", PrimitiveKind.STRING).nullable

    override fun deserialize(decoder: Decoder): String? {
        val json = decoder as? JsonDecoder ?: return try {
            nonEmptyOrNull(decoder.decodeString())
        } catch (e: SerializationException) {
            null
        }
        val element = json.decodeJsonElement()
        val raw = (element as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return null
        return nonEmptyOrNull(raw)
    }

    override fun serialize(encoder: Encoder, value: String?) {
        if (value == null) encoder.encodeNull() else encoder.encodeString(value)
    }
}

/**
 * `((try? c.decode(String.self, forKey: .site)) ?? "").lowercased()`.
 *
 * The provider name is stored lower-cased so `youtubeId` — and therefore the in-place player — is a
 * single comparison rather than a case-insensitive one at every call site.
 */
public object LowercasedString : KSerializer<String> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("com.anitrack.model.LowercasedString", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): String {
        val json = decoder as? JsonDecoder ?: return try {
            decoder.decodeString().lowercase()
        } catch (e: SerializationException) {
            ""
        }
        val element = json.decodeJsonElement()
        return ((element as? JsonPrimitive)?.takeIf { it.isString }?.content ?: "").lowercase()
    }

    override fun serialize(encoder: Encoder, value: String) = encoder.encodeString(value)
}

// ---------------------------------------------------------------------------------------------
// MARK: - Enumerations
// ---------------------------------------------------------------------------------------------

/**
 * The five watch statuses. `COMPLETED` is the wire name; the user's word is **"Watched"** — the
 * copy layer is the only place a status becomes text.
 *
 * "Finished" is not in this vocabulary. It was carrying both the user's list state and the series'
 * production state at once, which is how the app came to file a show as finished on one screen and
 * promise it returns in six weeks on the next. "Complete" is reserved for the *series*, "Watched"
 * for the *user*. Never emit "Completed" or "Plan to watch".
 *
 * There is deliberately **no `UNKNOWN` sentinel**: an unrecognised status must read as *absent*
 * (`Franchise.status` → null, an unreadable `Subscription` → null), exactly as iOS's `try?` does,
 * and not as a sixth state every screen would have to draw.
 */
@Serializable
public enum class WatchStatus(public val wire: String) {
    @SerialName("watching")
    WATCHING("watching"),

    @SerialName("completed")
    COMPLETED("completed"),

    @SerialName("planned")
    PLANNED("planned"),

    @SerialName("paused")
    PAUSED("paused"),

    @SerialName("dropped")
    DROPPED("dropped"),
}

/**
 * Which catalogue a franchise came from. A franchise never mixes sources; absent in older server
 * responses, so decoding defaults to [ANILIST].
 *
 * The calendar anchor a source's timestamps must be read in (`MediaSource.timeAnchor` on iOS) lives
 * with the time substrate, not here: TMDB air dates are DATE-ONLY facts the server carries as a
 * synthesized 17:00 UTC instant, so only their UTC calendar day is real, and reading them locally
 * put every timezone east of UTC+7 a day ahead. **Never branch on `source` at a formatting call
 * site — pass the anchor.**
 */
@Serializable
public enum class MediaSource(public val wire: String) {
    @SerialName("anilist")
    ANILIST("anilist"),

    @SerialName("tmdb")
    TMDB("tmdb");

    /**
     * "Anime" | "TV" — the word for what a title is, in the user's vocabulary. The app never says
     * "AniList" or "TMDB" to a viewer.
     *
     * It lives on the source so `FranchiseSummary` (Search) and `Franchise` (Library, Detail)
     * cannot spell it differently.
     */
    public val kindWord: String get() = if (this == TMDB) "TV" else "Anime"
}

@Serializable
public enum class PartKind(public val wire: String) {
    @SerialName("season")
    SEASON("season"),

    @SerialName("movie")
    MOVIE("movie"),

    @SerialName("ova")
    OVA("ova"),

    @SerialName("ona")
    ONA("ona"),

    @SerialName("special")
    SPECIAL("special"),

    @SerialName("music")
    MUSIC("music");

    /**
     * Section grouping used by the franchise detail screen.
     *
     * Latent defect, carried over knowingly: [OVA] and [ONA] share a title but have *different*
     * [sortRank]s, so a franchise carrying both renders two sections both titled "OVAs". Currently
     * unreachable — Detail no longer draws the seasons section list — but the two cases stay
     * distinct everywhere else, so the collision is preserved rather than papered over.
     */
    public val sectionTitle: String
        get() = when (this) {
            SEASON -> "Seasons"
            MOVIE -> "Movies"
            OVA, ONA -> "OVAs"
            SPECIAL -> "Specials"
            MUSIC -> "Music"
        }

    /** Canonical ordering of sections. */
    public val sortRank: Int
        get() = when (this) {
            SEASON -> 0
            MOVIE -> 1
            OVA -> 2
            ONA -> 3
            SPECIAL -> 4
            MUSIC -> 5
        }
}

public object MediaSourceSerializer :
    SafeValueSerializer<MediaSource>(MediaSource.serializer(), MediaSource.ANILIST)

public object PartKindSerializer :
    SafeValueSerializer<PartKind>(PartKind.serializer(), PartKind.SEASON)

/** `try? c.decodeIfPresent(WatchStatus.self, …)` — an unknown status is absent, not a new state. */
public object SafeWatchStatus : SafeSerializer<WatchStatus>(WatchStatus.serializer())

// ---------------------------------------------------------------------------------------------
// MARK: - Episode
// ---------------------------------------------------------------------------------------------

/**
 * Per-episode metadata (present only on the franchise-detail response). Richness is
 * source-dependent — TMDB gives title/overview/still/runtime/date; AniList gives best-effort titles
 * and thumbnails from `streamingEpisodes` and **no** per-episode `airDate`/`overview`.
 *
 * Every field is lenient, so an `Episode` can never throw: `{}` decodes as `Episode(number = 0, …)`
 * and the parent's filter then drops it. [id] is the number, so a malformed or duplicate 0 would
 * collide inside a keyed list.
 *
 * [airDate] only ever comes from TMDB, so it is always a date-only fact and must be read in its own
 * UTC day, never the device's — the time layer's `Episode.airDateAnchor` is `utcDate` for that
 * reason, source-independent.
 */
@Serializable
public data class Episode(
    @Serializable(with = LenientInt::class) val number: Int = 0,
    @Serializable(with = LenientStringOrNull::class) val title: String? = null,
    /** ms epoch. */
    @Serializable(with = LenientLongOrNull::class) val airDate: Long? = null,
    @Serializable(with = LenientStringOrNull::class) val overview: String? = null,
    /** Thumbnail url. */
    @Serializable(with = LenientStringOrNull::class) val still: String? = null,
    /** Minutes. */
    @Serializable(with = LenientIntOrNull::class) val runtime: Int? = null,
) {
    public val id: Int get() = number
}

public object EpisodeListSerializer : SafeListSerializer<Episode>(Episode.serializer()) {
    // `Episode.id` is its number, so a malformed or duplicate 0 would collide inside a keyed list.
    override fun keep(value: Episode): Boolean = value.number > 0
}

// ---------------------------------------------------------------------------------------------
// MARK: - Airing
// ---------------------------------------------------------------------------------------------

/**
 * One dated episode of a part inside Schedule's window: the number and the instant. TMDB's instant
 * is date-only (17:00 UTC) — read it in the source's calendar.
 *
 * The server ships the window (8 days back … 15 days ahead) on **every** payload — list, library
 * and detail — merged from the dated episode list, the catalogue's next slot and `lastAiredAt`,
 * de-duplicated by episode number with the episode list winning. `[]` means nothing in the window
 * is dated *or* the server predates the field.
 *
 * Both fields are **strict**, matching Swift's synthesised `Codable`: an airing with no number or
 * no instant is not an airing, and one of them empties the whole list.
 */
@Serializable
public data class Airing(
    val episode: Int,
    /** ms epoch. */
    val at: Long,
)

public object AiringListSerializer : SafeListSerializer<Airing>(Airing.serializer()) {
    override fun keep(value: Airing): Boolean = value.episode > 0 && value.at > 0
}

// ---------------------------------------------------------------------------------------------
// MARK: - Release precision
// ---------------------------------------------------------------------------------------------

/**
 * How precisely the next release instant is known — **stated by the server, never inferred from
 * `source`**. AniList publishes a real broadcast instant; TMDB publishes a calendar date the sync
 * synthesizes to 17:00 UTC, so its clock half is not a fact and must never be rendered. Absent in
 * older server responses, which is why every field is optional.
 *
 * Note: this type has **no consumers in the app today** — the date-only decision is taken from the
 * source's calendar anchor instead. It is ported for wire fidelity; do not build UI on it without
 * first deciding which of the two mechanisms wins.
 */
@Serializable
public data class ReleasePrecision(
    @Serializable(with = ReleasePrecisionSerializer::class)
    val precision: Precision = Precision.UNKNOWN,
    /** ms epoch. Authoritative only when [precision] is [Precision.EXACT]. */
    @Serializable(with = LenientLongOrNull::class) val at: Long? = null,
    /** "YYYY-MM-DD" (UTC). Authoritative only when [precision] is [Precision.DATE_ONLY]. */
    @Serializable(with = LenientStringOrNull::class) val date: String? = null,
) {
    @Serializable
    public enum class Precision(public val wire: String) {
        /** [at] is a real broadcast instant. */
        @SerialName("exact")
        EXACT("exact"),

        /** [date] is the fact; [at] is synthesized and its clock half is fiction. */
        @SerialName("date_only")
        DATE_ONLY("date_only"),

        /** Nothing is scheduled. */
        @SerialName("unknown")
        UNKNOWN("unknown"),
    }
}

public object ReleasePrecisionSerializer : SafeValueSerializer<ReleasePrecision.Precision>(
    ReleasePrecision.Precision.serializer(),
    ReleasePrecision.Precision.UNKNOWN,
)

public object SafeReleasePrecision : SafeSerializer<ReleasePrecision>(ReleasePrecision.serializer())

// ---------------------------------------------------------------------------------------------
// MARK: - FranchisePart
// ---------------------------------------------------------------------------------------------

/**
 * A single installment — one season, movie or OVA — merged with the authenticated user's progress.
 * [id] is [mediaId]; TMDB ids are `1_000_000_000 + tmdb season id`.
 *
 * [mediaId] is the one **strict** field: an unidentifiable installment is not an installment, and a
 * part without it fails the array, which the parent's lenient list serializer turns into
 * `parts = []` rather than a lost franchise.
 *
 * House rule: **[sequence] is the ordering key and NEVER displays.** It counts a franchise's
 * members, which is not the number the world uses for a season — rendering "S5" beside a label that
 * reads "Season 4" was observed live on 2026-08-22. Read [label] instead.
 *
 * Read art through `portraitArt` / `landscapeArt` / `wideArt` (`ModelsEnrichment.kt`), never
 * [cover] / [banner] in a view.
 */
@Serializable
public data class FranchisePart(
    val mediaId: Int,
    @Serializable(with = PartKindSerializer::class) val kind: PartKind = PartKind.SEASON,
    /** Ordering key within the franchise. Never displayed. */
    @Serializable(with = LenientInt::class) val sequence: Int = 0,
    /** The source's own words: "Season 4", "Final Season", "Part 2". */
    @Serializable(with = LenientString::class) val label: String = "",
    @Serializable(with = LenientTitle::class) val title: String = "Untitled",
    /** Legacy portrait url; read `portraitArt`. */
    @Serializable(with = LenientStringOrNull::class) val cover: String? = null,
    /** Legacy landscape url; read `landscapeArt`. */
    @Serializable(with = LenientStringOrNull::class) val banner: String? = null,
    /** Raw catalogue format, e.g. "TV". */
    @Serializable(with = LenientStringOrNull::class) val format: String? = null,
    /**
     * How the catalogue relates this part to the work — "SEQUEL", "PREQUEL", "SIDE_STORY",
     * "SPIN_OFF", "SUMMARY", "OTHER"… (AniList's relation type, as the server sends it). Read for
     * one decision only: a spin-off is an extra, not a season (`isSpinOff`).
     */
    @Serializable(with = LenientStringOrNull::class) val relationship: String? = null,
    /** Raw catalogue status, e.g. "FINISHED", "NOT_YET_RELEASED". */
    @Serializable(with = LenientStringOrNull::class) val status: String? = null,
    @Serializable(with = LenientBool::class) val isReleasing: Boolean = false,
    /** 0 = unknown, which is common for an ongoing AniList show. */
    @Serializable(with = LenientInt::class) val totalEpisodes: Int = 0,
    /**
     * The catalogue's own count, advanced by an hourly cron — always 0 while NOT_YET_RELEASED.
     * It trails reality by up to an hour, so every live "is it out yet" question reads the
     * airings-derived ladder in the derive layer instead. This field stays for sort keys and the
     * Library's calm captions, where an hour is nothing.
     */
    @Serializable(with = LenientInt::class) val airedEpisodes: Int = 0,
    /** 1 on a dated NOT_YET_RELEASED part — the premiere is the next slot. */
    @Serializable(with = LenientIntOrNull::class) val nextEpisodeNumber: Int? = null,
    /** ms epoch. Contract: always == `release.at`. */
    @Serializable(with = LenientLongOrNull::class) val nextAiringAt: Long? = null,
    /** ms epoch. */
    @Serializable(with = LenientLongOrNull::class) val lastAiredAt: Long? = null,
    /** HTML. */
    @Serializable(with = LenientStringOrNull::class) val synopsis: String? = null,
    @Serializable(with = StringListSerializer::class) val genres: List<String> = emptyList(),
    /** The user's watched count for THIS part. */
    @Serializable(with = LenientInt::class) val progress: Int = 0,
    /** Premiere/season year. */
    @Serializable(with = LenientIntOrNull::class) val year: Int? = null,
    /** Studios (anime) / networks (TV). */
    @Serializable(with = StringListSerializer::class) val studios: List<String> = emptyList(),
    /** Episodes sharing the next airing date; > 1 ⇒ a full-season drop. No consumers today. */
    @Serializable(with = LenientInt::class) val nextAiringCount: Int = 0,
    /** Detail response only; `[]` on list/library payloads. Filtered to `number > 0`. */
    @Serializable(with = EpisodeListSerializer::class) val episodes: List<Episode> = emptyList(),
    /** The honest shape of [nextAiringAt]. Null from a server that predates the field. */
    @Serializable(with = SafeReleasePrecision::class) val release: ReleasePrecision? = null,
    /**
     * Dated episodes 8 days back … 15 days ahead, oldest first, on EVERY payload — the calendar's
     * per-episode facts. `[]` from a server that predates the field.
     */
    @Serializable(with = AiringListSerializer::class) val airings: List<Airing> = emptyList(),
    /** Artwork with its orientation stated. Null from a server that predates the field. */
    @Serializable(with = SafeArtworkSet::class) val images: ArtworkSet? = null,
    /** The server's ranked alternatives per orientation (`ArtworkGallery`). Empty from an older server. */
    @Serializable(with = SafeArtworkGallery::class) val artwork: ArtworkGallery? = null,
    /** Trailers and teasers scoped to this exact part. `[]` from an older server. */
    @Serializable(with = VideoListSerializer::class) val videos: List<FranchiseVideo> = emptyList(),
) {
    public val id: Int get() = mediaId
}

public object PartListSerializer : SafeListSerializer<FranchisePart>(FranchisePart.serializer())

// ---------------------------------------------------------------------------------------------
// MARK: - Subscription
// ---------------------------------------------------------------------------------------------

/**
 * The user's membership row for a franchise.
 *
 * [status] is **strict** on purpose: Swift's synthesised `Codable` throws on a status it does not
 * know, and the whole `Subscription` then reads as absent. A membership whose state cannot be read
 * is not a membership. [addedAt] is absent in older server responses, so Library's "recently added"
 * ordering must treat null as *unknown* rather than as the epoch.
 */
@Serializable
public data class Subscription(
    val status: WatchStatus,
    /** ms epoch. */
    val addedAt: Long? = null,
)

public object SafeSubscription : SafeSerializer<Subscription>(Subscription.serializer())

// ---------------------------------------------------------------------------------------------
// MARK: - Release window
// ---------------------------------------------------------------------------------------------

/**
 * `FranchiseUpcoming.release` resolved into something orderable — **stated by the server**, because
 * `release` is prose: the catalogue announces "October 2026" and "Summer 2027" far more often than
 * it announces a date. The app's own ISO-only reading of that prose filed every window under
 * January of its year, so a shelf sorted "soonest first" put October 2026 ahead of an August 2026
 * premiere while its own caption read "Returns Oct 2026".
 *
 * **Nothing here re-parses `release`**; [sortKey] is the one order and [date] is the one date.
 */
@Serializable
public data class ReleaseWindow(
    /** "YYYY-MM-DD" | "YYYY-MM" | "YYYY", at the precision actually known. */
    @Serializable(with = LenientStringOrNull::class) val date: String? = null,
    @Serializable(with = ReleaseWindowPrecisionSerializer::class)
    val precision: Precision = Precision.UNKNOWN,
    /**
     * `yyyymmdd` of the earliest instant the window can mean. Ascending = soonest first; null sorts
     * LAST — never as 0, never as January of a year nobody stated.
     */
    @Serializable(with = LenientIntOrNull::class) val sortKey: Int? = null,
) {
    @Serializable
    public enum class Precision(public val wire: String) {
        /** [date] is exactly what was announced, to the day. */
        @SerialName("day")
        DAY("day"),

        /** [date] is exactly what was announced, to the month. */
        @SerialName("month")
        MONTH("month"),

        /**
         * A broadcast season or quarter. [date] is that quarter's FIRST month — order by it, never
         * print it as a month ("Summer 2027" is not "July 2027").
         */
        @SerialName("quarter")
        QUARTER("quarter"),

        /**
         * Only the year may be printed. [sortKey] may still place the window inside that year
         * ("Late 2026" sorts in September) — that placement is an order, not a fact to render.
         */
        @SerialName("year")
        YEAR("year"),

        /** TBA, a rumor, or prose with no date in it. */
        @SerialName("unknown")
        UNKNOWN("unknown"),
    }

    /** The calendar parts of [date]. See [parts]. */
    public data class Parts(val year: Int, val month: Int, val day: Int)

    /**
     * Calendar parts of [date], for the surfaces that print a month. Month and day are **1** when
     * the window does not state them, so a caller must check [precision] before printing either.
     *
     * Non-numeric segments are dropped silently, exactly as Swift's `compactMap { Int($0) }` does:
     * `"2026-XX-05"` yields `(2026, 5, 1)`. Reproduced rather than fixed — the server's sort order
     * and the golden corpus were both built against it.
     */
    public val parts: Parts?
        get() {
            val d = date ?: return null
            val segs = d.split("-").mapNotNull { it.toIntOrNull() }
            val y = segs.firstOrNull() ?: return null
            return Parts(
                year = y,
                month = if (segs.size > 1) segs[1] else 1,
                day = if (segs.size > 2) segs[2] else 1,
            )
        }
}

public object ReleaseWindowPrecisionSerializer : SafeValueSerializer<ReleaseWindow.Precision>(
    ReleaseWindow.Precision.serializer(),
    ReleaseWindow.Precision.UNKNOWN,
)

public object SafeReleaseWindow : SafeSerializer<ReleaseWindow>(ReleaseWindow.serializer())

// ---------------------------------------------------------------------------------------------
// MARK: - FranchiseUpcoming
// ---------------------------------------------------------------------------------------------

/**
 * Web-sourced "what's next" news for a franchise (announced or airing seasons and films). [release]
 * is a human-readable date or window ("October 2026", "Summer 2027", "TBA") because announced
 * seasons often have only a window, which the catalogue does not expose as a per-episode airing
 * time. [releaseWindow] is that same window resolved by the server — the only thing to sort by.
 *
 * [status] stays an open [String], not an enum: the seven known values are `airing`,
 * `upcoming_dated`, `announced`, `announced_no_date`, `rumored`, `recently_aired` and `concluded`,
 * and an unseen eighth must degrade through the `else` branches of the derive layer rather than
 * fail to decode.
 */
@Serializable
public data class FranchiseUpcoming(
    @Serializable(with = LenientStringOrNull::class) val status: String? = null,
    /** Shortest stable name for the installment, e.g. "Season 2". */
    @Serializable(with = LenientStringOrNull::class) val next: String? = null,
    /** Prose: "October 2026", "2026-11-20", "Summer 2027", "TBA". */
    @Serializable(with = LenientStringOrNull::class) val release: String? = null,
    @Serializable(with = LenientStringOrNull::class) val note: String? = null,
    /** The primary announcement URL. */
    @Serializable(with = LenientStringOrNull::class) val source: String? = null,
    /** ISO date the info was last verified. */
    @Serializable(with = LenientStringOrNull::class) val checked: String? = null,
    /**
     * Absent from a server older than this field. Nothing here falls back to parsing [release]:
     * that fallback IS the bug it replaced, and an unknown window sorts last rather than wrong.
     */
    @Serializable(with = SafeReleaseWindow::class) val releaseWindow: ReleaseWindow? = null,
)

public object SafeUpcoming : SafeSerializer<FranchiseUpcoming>(FranchiseUpcoming.serializer())

// ---------------------------------------------------------------------------------------------
// MARK: - Franchise (full detail)
// ---------------------------------------------------------------------------------------------

/**
 * `partCounts` on the wire, as a map.
 *
 * **Deliberate divergence from iOS, and a confirmed contract drift.** iOS models this as a struct
 * with six `Int` properties; Swift's synthesised `init(from:)` ignores property defaults and calls
 * `decode` for every key, while the server emits a *partial* record populated only for the kinds
 * that exist (`franchiseView.ts` builds a `Partial<Record<PartKind, number>>`, and the contract's
 * own example omits `ona` and `music`). `Franchise.partCounts` is therefore `nil` in production for
 * essentially every row on iOS. It has zero consumers, so nothing breaks there — but modelling the
 * shape the wire actually carries is the correct port. Read it with `getOrDefault(kind, 0)`.
 */
public object PartCountsSerializer : SafeValueSerializer<Map<PartKind, Int>>(
    MapSerializer(PartKind.serializer(), Int.serializer()),
    emptyMap(),
)

/**
 * A show. [id] is the one **strict** field on the whole type — an unidentifiable show is not a
 * show, and because [LibraryResponse.franchises] is strict too, a franchise that cannot be
 * identified fails the whole library read rather than quietly disappearing from the shelves.
 *
 * The `/me/library`-only fields ([status], [behind], [newParts]) live on this one type rather than
 * on a second "LibraryFranchise": the server's `LibraryFranchise` *is* a `Franchise` plus those
 * three, and one type with three nullable fields keeps every screen reading the same model.
 */
@Serializable
public data class Franchise(
    val id: String,
    @Serializable(with = MediaSourceSerializer::class) val source: MediaSource = MediaSource.ANILIST,
    @Serializable(with = LenientTitle::class) val title: String = "Untitled",
    /** Legacy portrait url; read `portraitArt`. */
    @Serializable(with = LenientStringOrNull::class) val cover: String? = null,
    /** Legacy landscape url; read `landscapeArt`. */
    @Serializable(with = LenientStringOrNull::class) val banner: String? = null,
    @Serializable(with = LenientStringOrNull::class) val synopsis: String? = null,
    @Serializable(with = StringListSerializer::class) val genres: List<String> = emptyList(),
    /** Any part currently releasing. */
    @Serializable(with = LenientBool::class) val isReleasing: Boolean = false,
    @Serializable(with = PartCountsSerializer::class) val partCounts: Map<PartKind, Int> = emptyMap(),
    @Serializable(with = PartListSerializer::class) val parts: List<FranchisePart> = emptyList(),
    @Serializable(with = SafeSubscription::class) val subscription: Subscription? = null,
    @Serializable(with = SafeUpcoming::class) val upcoming: FranchiseUpcoming? = null,
    /** Premiere year (earliest dated part). */
    @Serializable(with = LenientIntOrNull::class) val year: Int? = null,
    /** The primary installment's studios (anime) / networks (TV). */
    @Serializable(with = StringListSerializer::class) val studios: List<String> = emptyList(),

    // Catalogue enrichment. Every one of these is EMPTY, not absent, on a server older than the
    // field or a row the server's background pass has not reached yet.
    @Serializable(with = SafeArtworkSet::class) val images: ArtworkSet? = null,
    /** The server's ranked alternatives per orientation (`ArtworkGallery`). Empty from an older server. */
    @Serializable(with = SafeArtworkGallery::class) val artwork: ArtworkGallery? = null,
    /** Spoiler-screened. */
    @Serializable(with = StringListSerializer::class) val themes: List<String> = emptyList(),
    /** The server's pick. */
    @Serializable(with = SafeVideo::class) val featuredVideo: FranchiseVideo? = null,
    @Serializable(with = VideoListSerializer::class) val videos: List<FranchiseVideo> = emptyList(),
    @Serializable(with = SafeAudience::class) val audience: AudienceInfo? = null,
    @Serializable(with = SafePeople::class) val people: FranchisePeople? = null,
    @Serializable(with = RelatedTitleListSerializer::class) val related: List<RelatedTitle> = emptyList(),
    /** User-specific; never points at an unaired episode. */
    @Serializable(with = SafeContinueWatching::class) val continueWatching: ContinueWatching? = null,

    // Present only in /me/library responses.
    @Serializable(with = SafeWatchStatus::class) val status: WatchStatus? = null,
    /** The server's count of unwatched aired episodes across releasing parts. */
    @Serializable(with = LenientIntOrNull::class) val behind: Int? = null,
    /** Parts added since the user last opened the app — the badge. */
    @Serializable(with = LenientIntOrNull::class) val newParts: Int? = null,
)

// ---------------------------------------------------------------------------------------------
// MARK: - FranchiseSummary (lists)
// ---------------------------------------------------------------------------------------------

/** A row in trending, search or the library index. [id] is strict for the same reason. */
@Serializable
public data class FranchiseSummary(
    val id: String,
    @Serializable(with = MediaSourceSerializer::class) val source: MediaSource = MediaSource.ANILIST,
    @Serializable(with = LenientTitle::class) val title: String = "Untitled",
    /** Legacy portrait url; read `portraitArt`. */
    @Serializable(with = LenientStringOrNull::class) val cover: String? = null,
    /** Legacy landscape url; read `landscapeArt`. */
    @Serializable(with = LenientStringOrNull::class) val banner: String? = null,
    @Serializable(with = LenientBool::class) val isReleasing: Boolean = false,
    @Serializable(with = LenientInt::class) val partCount: Int = 0,
    /** Soonest upcoming across parts. ms epoch. */
    @Serializable(with = LenientLongOrNull::class) val nextAiringAt: Long? = null,
    @Serializable(with = SafeUpcoming::class) val upcoming: FranchiseUpcoming? = null,
    @Serializable(with = LenientIntOrNull::class) val year: Int? = null,
    @Serializable(with = SafeArtworkSet::class) val images: ArtworkSet? = null,
    /** The server's ranked alternatives per orientation (`ArtworkGallery`). Empty from an older server. */
    @Serializable(with = SafeArtworkGallery::class) val artwork: ArtworkGallery? = null,
    @Serializable(with = StringListSerializer::class) val themes: List<String> = emptyList(),
    @Serializable(with = SafeVideo::class) val featuredVideo: FranchiseVideo? = null,

    // Present only in /me/library.
    @Serializable(with = SafeWatchStatus::class) val status: WatchStatus? = null,
    @Serializable(with = LenientIntOrNull::class) val behind: Int? = null,
    @Serializable(with = LenientIntOrNull::class) val newParts: Int? = null,
)

// ---------------------------------------------------------------------------------------------
// MARK: - Endpoint response envelopes
// ---------------------------------------------------------------------------------------------

/**
 * The envelope every franchise-list route returns.
 *
 * [franchises] stays a **hard requirement**, and its element serializer stays strict: a body
 * without it is a broken response, not an empty result, and swallowing that would render
 * "no results" for a server fault.
 *
 * The other three are present only on `/search`. An absent [sources] means "nothing to report",
 * never "everything failed" — a catalogue that FAILED is not a catalogue with no matches.
 */
@Serializable
public data class FranchiseListResponse(
    val franchises: List<FranchiseSummary>,
    /** Set when the server spell-corrected or completed the query before searching. */
    @Serializable(with = LenientStringOrNull::class) val correctedQuery: String? = null,
    /** The query the caller sent, echoed **only** alongside [correctedQuery]. */
    @Serializable(with = LenientStringOrNull::class) val originalQuery: String? = null,
    /** Per-catalogue outcome: `ok` / `failed` / `disabled`. */
    @Serializable(with = SafeStringMap::class) val sources: Map<String, String>? = null,
)

/**
 * `/me/library`. Both fields strict — the envelope shape is contractual, and `LibraryFranchise` is
 * a full [Franchise] plus `status` / `behind` / `newParts`.
 */
@Serializable
public data class LibraryResponse(
    val franchises: List<Franchise>,
    /** ms epoch. */
    val prevOpenedAt: Long,
)

/** `/me/opened` — the value from *before* this call. */
@Serializable
public data class OpenedResponse(
    /** ms epoch. */
    val prevOpenedAt: Long,
)

/** `{ ok: true }`. */
@Serializable
public data class OKResponse(
    val ok: Boolean,
)

// ---------------------------------------------------------------------------------------------
// MARK: - Request bodies (encode only)
// ---------------------------------------------------------------------------------------------

/**
 * `POST /me/subscriptions`. A null [status] lets the server pick — `watching` if the show is
 * releasing, else `planned` — and `explicitNulls = false` omits the key entirely, matching Swift's
 * synthesised `encodeIfPresent`.
 */
@Serializable
public data class SubscribeBody(
    val franchiseId: String,
    val status: WatchStatus? = null,
)

/** `PATCH /me/subscriptions/:franchiseId`. */
@Serializable
public data class StatusBody(
    val status: WatchStatus,
)

/** `PUT /me/progress`. */
@Serializable
public data class ProgressBody(
    val mediaId: Int,
    val episodes: Int,
)
