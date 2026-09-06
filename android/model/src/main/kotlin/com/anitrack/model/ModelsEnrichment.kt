@file:OptIn(ExperimentalSerializationApi::class)

package com.anitrack.model

import java.util.Locale
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.descriptors.element
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/*
 * The catalogue's deeper metadata (docs/api-contract.md, "Catalogue enrichment"): artwork with its
 * orientation stated, trailers, audience ratings, people, related titles, streaming availability,
 * and the server's own "continue watching" pointer. Ported from `Models+Enrichment.swift`.
 *
 * Every field here decodes LENIENTLY. A server older than the field, or a row the server's
 * stale-while-revalidate pass has not reached yet, must read as EMPTY — never as a decode failure
 * that drops the whole franchise. The screens hide a section that is empty and draw it when it
 * arrives; nothing here may throw past the franchise.
 *
 * The decoding machinery (`SafeSerializer`, `SafeValueSerializer`, `SafeListSerializer`,
 * `NonEmptyString`, `LowercasedString`) lives in `Models.kt`, next to the rule it implements.
 */

// ---------------------------------------------------------------------------------------------
// MARK: - Artwork
// ---------------------------------------------------------------------------------------------

/**
 * Artwork with its orientation stated. A missing landscape asset is `null`: the server never puts a
 * portrait poster in the landscape slot, so `null` here is the signal to composite the cover whole
 * rather than crop it to a forehead.
 */
@Serializable
public data class ArtworkSet(
    @Serializable(with = NonEmptyString::class) val portrait: String? = null,
    @Serializable(with = NonEmptyString::class) val landscape: String? = null,
) {
    public companion object {
        /**
         * An empty string is no artwork. Trims spaces (not newlines) to decide, and returns the
         * ORIGINAL, untrimmed string when something is left. See [nonEmptyOrNull].
         */
        public fun nonEmpty(s: String?): String? = nonEmptyOrNull(s)

        /**
         * Construct normalising both slots — the equivalent of iOS's memberwise `init`, which runs
         * `nonEmpty` on the way in. Prefer this over the constructor when building by hand
         * (previews, tests, fixtures); the decode path normalises through [NonEmptyString] already.
         */
        public fun of(portrait: String? = null, landscape: String? = null): ArtworkSet =
            ArtworkSet(portrait = nonEmpty(portrait), landscape = nonEmpty(landscape))
    }
}

public object SafeArtworkSet : SafeSerializer<ArtworkSet>(ArtworkSet.serializer())

/** `(try? c.decode(Double.self, …))`. */
public object LenientDoubleOrNull : SafeSerializer<Double>(Double.serializer())

/**
 * One ranked artwork asset (server 518430b): url, provider, pixel size, language, score. The score,
 * size and provider are informational — the app never re-ranks on them; the server's order is the
 * order. An entry with no url is dropped by [ArtworkImageListSerializer].
 */
@Serializable
public data class ArtworkImage(
    @Serializable(with = LenientString::class) val url: String = "",
    @Serializable(with = LenientStringOrNull::class) val source: String? = null,
    @Serializable(with = LenientIntOrNull::class) val width: Int? = null,
    @Serializable(with = LenientIntOrNull::class) val height: Int? = null,
    @Serializable(with = LenientStringOrNull::class) val language: String? = null,
    @Serializable(with = LenientDoubleOrNull::class) val score: Double? = null,
)

public object ArtworkImageListSerializer : SafeListSerializer<ArtworkImage>(ArtworkImage.serializer()) {
    override fun keep(value: ArtworkImage): Boolean = value.url.isNotBlank()
}

/**
 * The server's ranked artwork per orientation — `images.*` is its top pick, these are the
 * alternatives, first entry first. A missing list is empty; a malformed list is empty too, and the
 * accessors fall through to the legacy fields.
 */
@Serializable
public data class ArtworkGallery(
    @Serializable(with = ArtworkImageListSerializer::class) val portraits: List<ArtworkImage> = emptyList(),
    @Serializable(with = ArtworkImageListSerializer::class) val landscapes: List<ArtworkImage> = emptyList(),
    @Serializable(with = ArtworkImageListSerializer::class) val logos: List<ArtworkImage> = emptyList(),
)

public object SafeArtworkGallery : SafeSerializer<ArtworkGallery>(ArtworkGallery.serializer())

/**
 * What a billboard draws for the show's NAME, decided by what the art under it already says
 * (iOS `BillboardName`).
 *
 * There is deliberately no "the art carries the name" case any more (5 Sep). It assumed the
 * poster's logotype sits where the copy does; Re:ZERO's sits in the top band — under the back
 * button, the status capsule and the top veil — so the page drew no name and hid the one on the
 * poster, and on Today the wordmark band covers the same zone: a hero with no visible name at all.
 * A name is ALWAYS drawn. Where the selected poster is titled and the gallery has no textless one
 * it is drawn in TYPE, never as a logo — a logo would set the poster's own logotype twice in the
 * same hand, while type beside titled key art is Crunchyroll's and Prime Video's ordinary caption.
 */
public sealed class BillboardName {
    /**
     * The show's logo treatment. `HeroTitle` draws it only at the headline's mass and sets the name
     * in type otherwise.
     */
    public data class Logo(val image: ArtworkImage) : BillboardName()

    /** The name set in type. */
    public object Type : BillboardName()

    public companion object {
        public fun resolve(
            portrait: String?,
            textless: String?,
            gallery: ArtworkGallery?,
            logo: ArtworkImage?,
        ): BillboardName {
            if (textless == null && portrait != null) {
                val selected = gallery?.portraits?.firstOrNull { it.url == portrait }
                if (selected != null && ArtworkSet.nonEmpty(selected.language) != null) return Type
            }
            return if (logo != null) Logo(logo) else Type
        }
    }
}

/**
 * The one decision a wide frame makes: a landscape asset fills it; a portrait one is composited
 * whole on its own blurred ground. Callers pass both halves straight to the wide art surfaces and
 * **never re-derive the choice.**
 *
 * Note the edge case, which is deliberate: when both are null, [url] is null **and**
 * [portraitSource] is `true`.
 */
public data class WideArt(
    val url: String?,
    /** [url] is a 2:3 cover, to be composited rather than cropped. */
    val portraitSource: Boolean,
    /**
     * [url] is an AniList banner — 1900×400 (some 1800×550), far wider than any frame that shows
     * it — so a 16:9 frame must decode it at its native width or draw a ~2.5× upscale of the
     * middle third (`LandscapeArt`'s `ultraWide`). Decided by the URL, not the source: an enriched
     * anime franchise may carry a TMDB backdrop, and that IS 16:9. (Compositing the cover on the
     * blurred banner instead of cropping was tried on 4 Sep and reverted — "the images were just
     * fine".)
     */
    val ultraWide: Boolean = false,
) {
    public companion object {
        public fun from(landscape: String?, portrait: String?): WideArt =
            if (landscape != null) {
                WideArt(url = landscape, portraitSource = false, ultraWide = landscape.contains("/anime/banner/"))
            } else {
                WideArt(url = portrait, portraitSource = true)
            }
    }
}

/**
 * The legacy `banner` field, trusted only when it is a banner.
 *
 * Writers older than the explicit artwork set copied a portrait cover into `banner` when the
 * catalogue had no landscape asset; **exact URL equality is that copy**, and it is a poster, not a
 * banner. The comparison is against the raw [cover], not `nonEmpty(cover)`.
 */
private fun legacyBanner(banner: String?, cover: String?): String? {
    val b = nonEmptyOrNull(banner) ?: return null
    return if (b == cover) null else b
}

// The ONLY way a view reads art. Never `cover` / `banner` at a call site.
//
// Note the fall-through in the `?:` chain: `images?.portrait ?: nonEmpty(cover)` still allows the
// legacy cover when `images` exists but its `portrait` is null. That is intended.

/** The 2:3 cover — `images.portrait`, else the legacy field an older server sends. */
public val Franchise.portraitArt: String? get() =
    images?.portrait ?: artwork?.portraits?.firstOrNull()?.url ?: ArtworkSet.nonEmpty(cover)

/** The landscape banner, or null when the catalogue has none. Never a portrait poster. */
public val Franchise.landscapeArt: String? get() =
    images?.landscape ?: artwork?.landscapes?.firstOrNull()?.url ?: legacyBanner(banner, cover)

/** Art for a wide frame: the banner, else the cover composited. */
public val Franchise.wideArt: WideArt get() = WideArt.from(landscapeArt, portraitArt)

public val FranchisePart.portraitArt: String? get() =
    images?.portrait ?: artwork?.portraits?.firstOrNull()?.url ?: ArtworkSet.nonEmpty(cover)

public val FranchisePart.landscapeArt: String? get() =
    images?.landscape ?: artwork?.landscapes?.firstOrNull()?.url ?: legacyBanner(banner, cover)

/**
 * This part's OWN art for a wide frame — its banner, else its cover composited. The season screen's
 * header is the season's picture, never the show's.
 */
public val FranchisePart.wideArt: WideArt get() = WideArt.from(landscapeArt, portraitArt)

/**
 * The part's art with the show's behind it, for a card that is about the show as much as the season
 * (Library's Continue watching).
 */
public fun FranchisePart.wideArt(within: Franchise): WideArt {
    // A TRUE 16:9 wins at either level before any AniList banner does: the season's
    // `images.landscape` on production is its banner, and a 4.75:1 banner's middle third in a
    // 16:9 card was a pair of eyes (Library's Continue card, 4 Sep) while the show had a real
    // backdrop one level up. A banner still beats the poster composite.
    val candidates = listOf(wideArt, within.wideArt)
    candidates.firstOrNull { !it.portraitSource && !it.ultraWide }?.let { return it }
    candidates.firstOrNull { !it.portraitSource }?.let { return it }
    return WideArt.from(null, portraitArt ?: within.portraitArt)
}

/**
 * A TRUE 16:9 landscape for a 16:9 tile (the episode still's fallback): the season's, else the
 * show's — never an AniList banner. A 4.75:1 banner filled into a 120×68 tile shows its middle
 * third, which on production (4 Sep) was a pair of eyes eighteen times down the list.
 */
public fun FranchisePart.stillLandscape(within: Franchise): String? =
    listOf(wideArt, within.wideArt).firstOrNull { !it.portraitSource && !it.ultraWide }?.url

public val FranchiseSummary.portraitArt: String? get() =
    images?.portrait ?: artwork?.portraits?.firstOrNull()?.url ?: ArtworkSet.nonEmpty(cover)

public val FranchiseSummary.landscapeArt: String? get() =
    images?.landscape ?: artwork?.landscapes?.firstOrNull()?.url ?: legacyBanner(banner, cover)

public val FranchiseSummary.wideArt: WideArt get() = WideArt.from(landscapeArt, portraitArt)

/**
 * The first poster the server ranked that carries no language — TMDB's textless key art. A
 * per-surface FILTER on the server's order, not a re-rank: the billboard draws the name itself
 * ([billboardLogo], else the title), so the selected poster's own logotype sat right under our
 * title ("something is seriously wrong here", user, 4 Sep). Grids keep the selected poster.
 */
public val Franchise.textlessPortrait: String? get() = artwork?.textlessPortrait
public val FranchiseSummary.textlessPortrait: String? get() = artwork?.textlessPortrait

/**
 * The first ranked portrait with no language tag, trusted ONLY when the gallery is tagged at all —
 * at least one portrait carries a language. A missing tag means "textless" on a ranked gallery and
 * means nothing on the older shape the server still sends for some rows (no scores, no sizes, no
 * languages): Bleach's first titled poster passed as textless there and the text title landed on
 * top of a 100-dp BLEACH logotype (5 Sep).
 */
public val ArtworkGallery.textlessPortrait: String?
    get() {
        if (portraits.none { ArtworkSet.nonEmpty(it.language) != null }) return null
        return portraits.firstOrNull { ArtworkSet.nonEmpty(it.language) == null }?.url
    }

/**
 * TMDB serves an image at the size named in its path, and the server hands out `w780` posters — a
 * 780-px file that a billboard draws ~1080 px wide on a 3× phone, an upscale of the one sharp asset
 * in the frame (measured 5 Sep; the original is 2000×3000). A billboard asks for `original`; every
 * card keeps the size it was sent. Only TMDB paths are rewritten — AniList's CDN has no size ladder.
 */
public fun billboardResolution(url: String?): String? {
    if (url == null || !url.contains("image.tmdb.org/t/p/w")) return url
    return url.replace(Regex("/t/p/w\\d+/"), "/t/p/original/")
}

/** The show's logo treatment — the server's first-ranked logo — for the billboard's name. */
public val Franchise.billboardLogo: ArtworkImage? get() = artwork?.logos?.firstOrNull()
public val FranchiseSummary.billboardLogo: ArtworkImage? get() = artwork?.logos?.firstOrNull()

/** What the billboard draws for the name — see [BillboardName]. */
public val Franchise.billboardName: BillboardName
    get() = BillboardName.resolve(portraitArt, textlessPortrait, artwork, billboardLogo)
public val FranchiseSummary.billboardName: BillboardName
    get() = BillboardName.resolve(portraitArt, textlessPortrait, artwork, billboardLogo)

// ---------------------------------------------------------------------------------------------
// MARK: - Videos
// ---------------------------------------------------------------------------------------------

/**
 * A catalogue-curated external video — a trailer, a teaser, a renewal announcement. The app stores
 * the provider's id and link; it never hosts the bytes. `Franchise.featuredVideo` is the server's
 * pick (an upcoming or current part first, then official status and recency).
 *
 * [id] is **strict**: it is the provider id, the identity in a keyed list, and the YouTube id all
 * at once, so a video without one fails — and, per the whole-array rule, empties the shelf rather
 * than the show.
 */
@Serializable
public data class FranchiseVideo(
    /** The provider's id, e.g. "ldfEtPf3CfQ". */
    val id: String,
    /** Lower-cased provider name; "youtube" is the only one the app plays in place. */
    @Serializable(with = LowercasedString::class) val site: String = "",
    @Serializable(with = VideoKindSerializer::class) val kind: Kind = Kind.OTHER,
    @Serializable(with = NonEmptyString::class) val title: String? = null,
    @Serializable(with = NonEmptyString::class) val url: String? = null,
    @Serializable(with = NonEmptyString::class) val thumbnail: String? = null,
    @Serializable(with = LenientBoolOrNull::class) val official: Boolean? = null,
    @Serializable(with = LenientStringOrNull::class) val language: String? = null,
    @Serializable(with = LenientStringOrNull::class) val country: String? = null,
    /** ISO 8601. */
    @Serializable(with = LenientStringOrNull::class) val publishedAt: String? = null,
    @Serializable(with = VideoScopeSerializer::class) val scope: Scope = Scope.Franchise,
) {
    /**
     * The provider's title without the show's name and its separator — "Game of Thrones | Official
     * Series Trailer" under a lockup that already says the show said the name twice (i1-F6).
     */
    public fun titleCleanedFor(show: String?): String? {
        var t = title?.trim().orEmpty()
        if (t.isEmpty()) return null
        val seps = " |-–—:·"
        if (!show.isNullOrEmpty()) {
            val lower = t.lowercase(); val name = show.lowercase()
            if (lower.startsWith(name)) t = t.drop(show.length).trim { it in seps }
            else if (lower.endsWith(name)) t = t.dropLast(show.length).trim { it in seps }
        }
        val bar = t.lastIndexOf(" | ")
        if (bar >= 0 && t.length - bar - 3 <= 24) t = t.substring(0, bar)
        // A trailing "(Provider)" credit is the provider's too, and its straight quotes are set
        // as the app sets them (i4).
        t = t.replace(PROVIDER_CREDIT, "")
        t = t.replace(STRAIGHT_QUOTES) { "\u201C${it.groupValues[1]}\u201D" }
        t = t.trim()
        return t.ifEmpty { null }
    }

    @Serializable
    public enum class Kind(public val wire: String) {
        @SerialName("trailer")
        TRAILER("trailer"),

        @SerialName("teaser")
        TEASER("teaser"),

        @SerialName("announcement")
        ANNOUNCEMENT("announcement"),

        @SerialName("featurette")
        FEATURETTE("featurette"),

        @SerialName("clip")
        CLIP("clip"),

        @SerialName("other")
        OTHER("other"),
    }

    /** Whole-franchise, or one exact season/movie. */
    public sealed interface Scope {
        public data object Franchise : Scope
        public data class Part(val mediaId: Int, val label: String) : Scope
    }

    /** The YouTube id when this is a YouTube video — the one provider the app plays in place. */
    public val youtubeId: String? get() = if (site == "youtube") id else null

    /**
     * Where the viewer goes to watch it outside the app: the catalogue's link, else the provider's
     * own page for the id. [url] is already normalised through `nonEmpty`, so a blank one is null.
     */
    public val watchUrl: String? get() = url ?: youtubeId?.let { "https://www.youtube.com/watch?v=$it" }

    /**
     * The in-app player page (YouTube only): inline, autoplaying, no related-video wall.
     *
     * It must be loaded inside a WebView `<iframe>` on a page with a **neutral base URL**. A bare
     * embed URL gets "Video player configuration error"; a youtube.com base URL gets
     * "unavailable · 152-4". Port the wrapper, not just the URL.
     */
    public val embedUrl: String?
        get() = youtubeId?.let {
            "https://www.youtube.com/embed/$it?playsinline=1&autoplay=1&rel=0&modestbranding=1"
        }

    /** The still to draw the card with: the catalogue's, else the provider's own 16:9 frame. */
    public val thumbnailUrl: String?
        get() = thumbnail ?: youtubeId?.let { "https://i.ytimg.com/vi/$it/mqdefault.jpg" }

    /** "Season 6" when the video belongs to one part. */
    public val partLabel: String?
        get() = (scope as? Scope.Part)?.label?.takeIf { it.isNotEmpty() }
}

public object VideoKindSerializer :
    SafeValueSerializer<FranchiseVideo.Kind>(FranchiseVideo.Kind.serializer(), FranchiseVideo.Kind.OTHER)

/**
 * `scope` is a sum type, hand-coded on both sides of the codec.
 *
 * It reads as `.Part` **only when** `scope.type == "part"` **and** `scope.mediaId` is a JSON number
 * that fits an `Int`; `label` defaults to `""`. Anything else is `.Franchise`, so a shape the client
 * does not recognise degrades to "this trailer belongs to the show" rather than failing the video.
 *
 * The writer emits the contract's own shape, so the library's offline copy reads back exactly.
 */
public object VideoScopeSerializer : KSerializer<FranchiseVideo.Scope> {

    override val descriptor: SerialDescriptor =
        buildClassSerialDescriptor("com.anitrack.model.FranchiseVideo.Scope") {
            element<String>("type")
            element<Int>("mediaId")
            element<String>("label")
        }

    override fun deserialize(decoder: Decoder): FranchiseVideo.Scope {
        val json = decoder as? JsonDecoder ?: return FranchiseVideo.Scope.Franchise
        val obj = json.decodeJsonElement() as? JsonObject ?: return FranchiseVideo.Scope.Franchise
        val type = (obj["type"] as? JsonPrimitive)?.takeIf { it.isString }?.content
        if (type != "part") return FranchiseVideo.Scope.Franchise
        // A JSON *number*, matching Swift's strict `decode(Int.self)` — a quoted "123" is not an id.
        val mediaId = (obj["mediaId"] as? JsonPrimitive)?.takeIf { !it.isString }?.content?.toIntOrNull()
            ?: return FranchiseVideo.Scope.Franchise
        val label = (obj["label"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: ""
        return FranchiseVideo.Scope.Part(mediaId = mediaId, label = label)
    }

    override fun serialize(encoder: Encoder, value: FranchiseVideo.Scope) {
        val json = encoder as? JsonEncoder
            ?: throw SerializationException("FranchiseVideo.Scope can only be written to JSON")
        json.encodeJsonElement(
            buildJsonObject {
                when (value) {
                    is FranchiseVideo.Scope.Franchise -> put("type", "franchise")
                    is FranchiseVideo.Scope.Part -> {
                        put("type", "part")
                        put("mediaId", value.mediaId)
                        put("label", value.label)
                    }
                }
            },
        )
    }
}

public object SafeVideo : SafeSerializer<FranchiseVideo>(FranchiseVideo.serializer())

public object VideoListSerializer : SafeListSerializer<FranchiseVideo>(FranchiseVideo.serializer())

// ---------------------------------------------------------------------------------------------
// MARK: - Audience
// ---------------------------------------------------------------------------------------------

/** Both fields strict, matching Swift's synthesised `Codable`: a rating with no market is not one. */
@Serializable
public data class ContentRating(
    val country: String,
    val rating: String,
)

public object SafeContentRating : SafeSerializer<ContentRating>(ContentRating.serializer())

public object ContentRatingListSerializer :
    SafeListSerializer<ContentRating>(ContentRating.serializer())

/**
 * Who a title is for. [contentRating] is the exact match for the market the app asked for; the
 * server does not substitute another country's rating, so a miss is `null`, never "US".
 *
 * [availableRatings] has no consumers today.
 */
@Serializable
public data class AudienceInfo(
    @Serializable(with = LenientBoolOrNull::class) val isAdult: Boolean? = null,
    @Serializable(with = SafeContentRating::class) val contentRating: ContentRating? = null,
    @Serializable(with = ContentRatingListSerializer::class)
    val availableRatings: List<ContentRating> = emptyList(),
)

public object SafeAudience : SafeSerializer<AudienceInfo>(AudienceInfo.serializer())

// ---------------------------------------------------------------------------------------------
// MARK: - People
// ---------------------------------------------------------------------------------------------

/**
 * A creator, a director, or a cast member. Anime cast are Japanese voice actors with the character
 * name in [role]; general-TV cast are top-billed with their character. Creators and directors are
 * separate lists.
 *
 * An entry whose [name] is empty is filtered out by [FranchisePeople] — a face with no name is not
 * a person.
 */
@Serializable
public data class CatalogPerson(
    @Serializable(with = MediaSourceSerializer::class) val source: MediaSource = MediaSource.ANILIST,
    @Serializable(with = LenientInt::class) val externalId: Int = 0,
    @Serializable(with = LenientString::class) val name: String = "",
    @Serializable(with = NonEmptyString::class) val role: String? = null,
    @Serializable(with = NonEmptyString::class) val image: String? = null,
) {
    /** One person can appear once per role (a director who also acts). */
    public val id: String get() = "${source.wire}:$externalId:${role ?: ""}"

    /** The role without a quoted nickname — "Tyrion 'The Halfman' Lannister" lost its surname to the quote (i2-10). */
    public val displayRole: String?
        get() {
            val r = role ?: return null
            val bare = r.replace(Regex("\\s*['\"\u201C\u2018][^'\"\u201D\u2019]*['\"\u201D\u2019]\\s*"), " ")
                .replace("  ", " ").trim()
            return if (bare.isEmpty()) r else bare
        }
}

public object PersonListSerializer : SafeListSerializer<CatalogPerson>(CatalogPerson.serializer()) {
    override fun keep(value: CatalogPerson): Boolean = value.name.isNotEmpty()
}

@Serializable
public data class FranchisePeople(
    @Serializable(with = PersonListSerializer::class) val creators: List<CatalogPerson> = emptyList(),
    @Serializable(with = PersonListSerializer::class) val directors: List<CatalogPerson> = emptyList(),
    @Serializable(with = PersonListSerializer::class) val cast: List<CatalogPerson> = emptyList(),
) {
    public val isEmpty: Boolean get() = creators.isEmpty() && directors.isEmpty() && cast.isEmpty()
}

public object SafePeople : SafeSerializer<FranchisePeople>(FranchisePeople.serializer())

// ---------------------------------------------------------------------------------------------
// MARK: - Related titles
// ---------------------------------------------------------------------------------------------

/**
 * A source-native recommendation. [franchiseId] is filled only once the title exists locally;
 * otherwise the title is the way to find it — present pushes Detail, absent means an exact-title
 * search materialises it or the "not in the catalogue" notice.
 *
 * An entry with an empty [title] is filtered out by `Franchise`.
 */
@Serializable
public data class RelatedTitle(
    @Serializable(with = MediaSourceSerializer::class) val source: MediaSource = MediaSource.ANILIST,
    @Serializable(with = LenientInt::class) val externalId: Int = 0,
    @Serializable(with = NonEmptyString::class) val franchiseId: String? = null,
    @Serializable(with = LenientString::class) val title: String = "",
    @Serializable(with = LenientIntOrNull::class) val year: Int? = null,
    @Serializable(with = SafeArtworkSet::class) val images: ArtworkSet? = null,
) {
    /** No role component, unlike [CatalogPerson]. */
    public val id: String get() = "${source.wire}:$externalId"

    /**
     * "Anime · 2017" — the same two facts a Search tile states.
     *
     * The separator is U+00B7 MIDDLE DOT with a plain ASCII space either side. It is the app's
     * universal fact separator; it is not decoration, and it must survive every round trip.
     */
    public val identityLine: String
        get() = if (year == null) source.kindWord else "${source.kindWord} · $year"
}

/** `images?.portrait` **only** — a related title has no legacy `cover` field to fall back to. */
public val RelatedTitle.portraitArt: String? get() = images?.portrait

public object RelatedTitleListSerializer :
    SafeListSerializer<RelatedTitle>(RelatedTitle.serializer()) {
    override fun keep(value: RelatedTitle): Boolean = value.title.isNotEmpty()
}

// ---------------------------------------------------------------------------------------------
// MARK: - Continue watching
// ---------------------------------------------------------------------------------------------

/**
 * The server's own answer to "what do I watch next": the first already-aired episode the user has
 * not watched, with whatever the catalogue knows about it. User-specific, **never unaired**.
 *
 * [mediaId] and [episode] are **strict** — a pointer with no target is useless — and the whole
 * object then reads as absent. Missing episode *metadata* is different: the server sends an honest
 * Episode-N shell with nullable context rather than suppressing the next episode.
 */
@Serializable
public data class ContinueWatching(
    val mediaId: Int,
    @Serializable(with = LenientString::class) val partLabel: String = "",
    val episode: Episode,
)

public object SafeContinueWatching : SafeSerializer<ContinueWatching>(ContinueWatching.serializer())

// ---------------------------------------------------------------------------------------------
// MARK: - Where to watch
// ---------------------------------------------------------------------------------------------

/**
 * Country-specific streaming availability (`GET /franchises/:id/watch-providers`).
 *
 * Consumers branch on [status], **never on `providers.isEmpty()`**: `NOT_AVAILABLE` is a matched
 * title with no streaming option in that country, `UNMATCHED` means the anime→TMDB bridge could not
 * establish identity safely, and `DISABLED` means this deployment has no TMDB token. An upstream
 * failure is an HTTP error, not any of those catalogue states.
 *
 * The section is drawn only for [Status.AVAILABLE] — a section that says "not here" is not a
 * section — its header opens [link] (the provider data gives a regional watch page, not reliable
 * deep links), and the JustWatch [attribution] is required.
 */
@Serializable
public data class WatchAvailability(
    @Serializable(with = LenientString::class) val country: String = "",
    @Serializable(with = WatchAvailabilityStatusSerializer::class)
    val status: Status = Status.UNMATCHED,
    /** Subscription services first, then free and ad-supported. The order is contractual. */
    @Serializable(with = WatchProviderListSerializer::class)
    val providers: List<WatchProvider> = emptyList(),
    /** The provider data's regional watch page — the only reliable link there is. */
    @Serializable(with = NonEmptyString::class) val link: String? = null,
    /** Required attribution for the provider data. */
    @Serializable(with = LenientAttribution::class) val attribution: String = "JustWatch",
) {
    @Serializable
    public enum class Status(public val wire: String) {
        @SerialName("available")
        AVAILABLE("available"),

        @SerialName("not_available")
        NOT_AVAILABLE("not_available"),

        @SerialName("unmatched")
        UNMATCHED("unmatched"),

        @SerialName("disabled")
        DISABLED("disabled"),
    }
}

public object WatchAvailabilityStatusSerializer : SafeValueSerializer<WatchAvailability.Status>(
    WatchAvailability.Status.serializer(),
    WatchAvailability.Status.UNMATCHED,
)

/**
 * The contract makes `attribution` required; the client defaults it to "JustWatch" when it is
 * absent. Harmless, and it keeps the required credit on screen against an older server — but it
 * does mean the client can show attribution the server never sent.
 */
public object LenientAttribution : SafeValueSerializer<String>(String.serializer(), "JustWatch")

/** [id] is **strict** — a provider with no id cannot be de-duplicated or logged. */
@Serializable
public data class WatchProvider(
    val id: Int,
    @Serializable(with = LenientString::class) val name: String = "",
    @Serializable(with = NonEmptyString::class) val logo: String? = null,
    @Serializable(with = WatchProviderAccessSerializer::class) val access: Access = Access.SUBSCRIPTION,
) {
    @Serializable
    public enum class Access(public val wire: String) {
        @SerialName("subscription")
        SUBSCRIPTION("subscription"),

        @SerialName("free")
        FREE("free"),

        @SerialName("ads")
        ADS("ads"),
    }
}

public object WatchProviderAccessSerializer : SafeValueSerializer<WatchProvider.Access>(
    WatchProvider.Access.serializer(),
    WatchProvider.Access.SUBSCRIPTION,
)

public object WatchProviderListSerializer :
    SafeListSerializer<WatchProvider>(WatchProvider.serializer())

// ---------------------------------------------------------------------------------------------
// MARK: - The viewer's market
// ---------------------------------------------------------------------------------------------

public object AppRegion {
    /**
     * The viewer's market as the catalogue names it — ISO 3166-1 alpha-2, upper-case. A device that
     * states no region falls back to "US": an unset region is not "no market".
     *
     * Sent as `?country=` on `GET /franchises/:id` and `GET /franchises/:id/watch-providers`.
     * `Locale.getDefault().country` is already alpha-2 upper-case where it is a country at all; the
     * two-letter / all-letters test rejects the UN M.49 numeric forms ("419") the platform can also
     * return, which is the same guard iOS applies.
     */
    public val current: String
        get() {
            val code = Locale.getDefault().country.uppercase(Locale.ROOT)
            return if (code.length == 2 && code.all { it.isLetter() }) code else "US"
        }
}

private val PROVIDER_CREDIT = Regex("""\s*\([A-Za-z][\w+ ]{1,20}\)$""")
private val STRAIGHT_QUOTES = Regex("\"([^\"]*)\"")
