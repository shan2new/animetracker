package com.anitrack.app.ui.image

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import coil3.BitmapImage
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.compose.LocalPlatformContext
import coil3.disk.DiskCache
import coil3.memory.MemoryCache
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import coil3.request.CachePolicy
import coil3.request.Disposable
import coil3.request.ImageRequest
import coil3.request.SuccessResult
import coil3.request.allowHardware
import coil3.request.crossfade
import coil3.size.Precision
import coil3.size.Scale
import coil3.size.Size
import coil3.transform.Transformation
import com.anitrack.app.design.ThemeColor
import com.anitrack.model.ArtPalette
import com.anitrack.model.OkLab
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.Call
import okhttp3.Dispatcher
import okhttp3.OkHttpClient
import okio.Path.Companion.toOkioPath

/**
 * # The art pipeline
 *
 * The port of `ios/Sources/DesignSystem/ImageLoader.swift` — but a port of its **policies**, not of
 * its mechanism. The iOS file is a bespoke `NSCache` + ImageIO pipeline because `AsyncImage` kept
 * no decoded-image cache, so every recycled grid cell re-fetched, re-decoded on the main actor and
 * flashed its placeholder back in. Coil already has the decoded cache, the disk cache, request
 * coalescing, EXIF-aware downsampling and lifecycle cancellation; re-implementing the Swift file
 * here would be ~600 lines arriving at a worse Coil.
 *
 * What must be reproduced exactly, because none of it is Coil's default:
 *
 * 1. **Bucketed, size-bounded decodes.** Every request asks for a rung of [ImageBuckets.LADDER],
 *    never for whatever pixel width the layout happens to be.
 * 2. **Serve larger, never smaller.** A request is satisfied by any decode at least as detailed as
 *    it asked for; it is never handed a smaller one. Coil's `Precision.EXACT` default breaks this
 *    in both directions, so [artImageLoader] sets `INEXACT`.
 * 3. **Coexistence.** Bucketed memory-cache keys, so a 270-px Library row thumb cannot evict the
 *    2048-px Detail hero and leave it to re-decode.
 * 4. **No flash on frame one.** A ladder probe into the memory cache during composition, handed to
 *    `placeholderMemoryCacheKey`, so a recycled cell renders the poster on its first frame.
 * 5. **A cache hit never animates.** Only a network/disk load cross-fades.
 * 6. **A separate HTTP client for art.** The API's bearer token must never reach the art CDN, and
 *    image traffic must not share the API's call-timeout budget.
 *
 * Blur lives here too, and it is **baked into the bitmap, not drawn** — see [BlurTransformation].
 * So does the art-adaptive palette's Android half, because it borrows this pipeline's bytes.
 *
 * Everything drawn through it is `clearAndSetSemantics {}`: meaning is carried by the row's text,
 * never by the picture.
 */

// ---------------------------------------------------------------------------------------------
// The ladder
// ---------------------------------------------------------------------------------------------

/**
 * The decode-size ladder, and the two rules built on it.
 *
 * Sizes are rounded **up** to a fixed ladder and the decode is done at the bucket, not at the
 * caller's exact request — otherwise a 207-px decode filed under the 256 bucket would shortchange
 * the next caller who genuinely wants 256. The rungs are spaced ~1.4× so rounding never wastes much
 * memory, and are wide enough at the top to cover a full-bleed banner on a 3× device.
 */
object ImageBuckets {

    /** Verbatim from `ImageCache.buckets` (`ios/Sources/DesignSystem/ImageLoader.swift`). */
    val LADDER: IntArray = intArrayOf(128, 192, 256, 384, 512, 768, 1024, 1536, 2048)

    /** The smallest rung that satisfies [maxPixel]; above the ladder, the exact request. */
    fun bucket(maxPixel: Int): Int {
        val want = maxPixel.coerceAtLeast(1)
        for (rung in LADDER) if (rung >= want) return rung
        return want
    }

    /**
     * The memory-cache key for one rung of one URL.
     *
     * Coil's own key excludes the size and instead *validates* a hit against the request (under
     * `Precision.INEXACT` a cached image is accepted when it is the same size or larger), so Coil
     * already refuses to hand a hero the row-thumbnail decode — the blurry-hero bug the iOS comment
     * describes does not reproduce. What Coil lacks is **coexistence**: one entry per URL, so a
     * 270-px row decode evicts the 2048-px hero decode and the hero re-decodes from disk on the way
     * back. Keying per rung is the one line that fixes it.
     */
    fun key(url: String, bucket: Int): MemoryCache.Key = MemoryCache.Key("$url|$bucket")

    /**
     * iOS's serve-larger walk, as a **placeholder** probe: the best already-decoded copy of [url]
     * that is at least as detailed as [want].
     *
     * This is the port of the synchronous cache hit iOS performs in `CachedAsyncImage.init` —
     * "first frame already shows the poster, so recycled cells don't flash", and `atLeast:` so a
     * hero never inherits a thumbnail-sized decode as its first frame. The correctly-bucketed
     * decode still runs and replaces whatever this finds; the probe only paints frame one.
     *
     * At most nine `LruCache` lookups, no allocation beyond the keys. Safe to call in composition.
     */
    fun ladderHit(cache: MemoryCache?, url: String, want: Int): MemoryCache.Key? {
        if (cache == null || url.isEmpty()) return null
        for (rung in LADDER) {
            if (rung < want) continue
            val candidate = key(url, rung)
            if (cache.get(candidate) != null) return candidate
        }
        // Above the ladder there is no larger rung to fall back on: only an exact match serves.
        return if (want > LADDER.last()) key(url, want).takeIf { cache.get(it) != null } else null
    }
}

/**
 * The `maxPixel` every surface asks for — the port of the table in
 * `docs/android-port/spec/chrome-images.md` §4.7. **`maxPixel` bounds the longest edge, in pixels.**
 *
 * Slot-derived sizes are not here: on iOS they are `max(width, height) × 3` because 3× is the
 * maximum device scale, whereas Android densities run 1.5×–4×. Those go through [artPixels], which
 * reads the real density — a fixed 3× would under-serve an xxxhdpi phone and over-serve an hdpi one.
 * The values below are absolute on both platforms and port unchanged.
 */
object ArtMaxPixel {

    /** The pipeline default. Every surface that has an opinion states it instead. */
    const val DEFAULT = 700

    /** `ArtHeader`'s blurred portrait ground. Stays small: it is blurred. */
    const val HERO_PORTRAIT_GROUND = 1024

    /**
     * `ArtHeader`'s sharp portrait layer. The billboard draws this at ~1770 px tall on iOS, and
     * capping the decode below that softened the one sharp asset in the frame.
     */
    const val HERO_PORTRAIT_SHARP = 2048

    /** `ArtHeader`'s landscape art. */
    const val HERO_LANDSCAPE = 1536

    /**
     * `LandscapeArt`'s blurred ground. Deliberately tiny — most of the softness is free upscaling,
     * which is also why [BlurTransformation] can bake it for nothing.
     */
    const val LANDSCAPE_GROUND = 160

    /** `LandscapeArt`'s sharp layer, and `BannerCard`. */
    const val LANDSCAPE_SHARP = 560

    /** `ProgressBanner` — Library's Up Next card and the season screen's header. */
    const val PROGRESS_BANNER = 900

    /** Schedule's `AiringCard`: gutter-to-gutter 16:9. */
    const val AIRING_CARD = 1100

    /** `ArtBackdrop`, the ambient wash. */
    const val AMBIENT_BACKDROP = 320

    /** `EpisodeArtwork`'s still. */
    const val EPISODE_STILL = 288

    /** `TrailerCard`'s thumbnail. */
    const val TRAILER_THUMB = 640

    /** `VideoSheet`'s poster. */
    const val VIDEO_POSTER = 900

    /** `PersonCard`'s 72-dp disc. */
    const val PERSON_DISC = 216

    /** A watch-provider logo. */
    const val PROVIDER_LOGO = 156

    /**
     * The palette's own decode. iOS shares one decode with the display image — its palette
     * `maxPixel`s (288/320/360/420) are *smaller* than its display ones, so the serve-larger rule
     * hands the already-decoded poster straight back and the palette costs zero extra decodes.
     *
     * **That trick is not available here.** Coil returns hardware bitmaps by default on API 26+ and
     * a hardware bitmap has no CPU-readable pixels, so `getPixels` throws; setting
     * `allowHardware(false)` app-wide to fix that would move every poster's pixels back into the
     * Java heap and add a GPU upload per texture — strictly worse. So the palette takes its own
     * request, and because it does it can be far smaller than iOS's: the bytes come from the disk
     * cache (or are coalesced with the in-flight display fetch), and the decode is 64 px.
     */
    const val PALETTE_SAMPLE = 64
}

/**
 * The `maxPixel` for a slot whose longest edge is [longestEdge], at this device's real density.
 *
 * iOS multiplies points by a fixed 3 ("max device scale — a 160-pt thumb needs ~480 px, not 700").
 * Android has no such ceiling, so the honest answer is the actual pixel size of the frame; the
 * ladder rounds it up either way.
 */
@Composable
@ReadOnlyComposable
fun artPixels(longestEdge: Dp): Int {
    val density = LocalDensity.current
    return ceil(with(density) { longestEdge.toPx() }).toInt().coerceAtLeast(1)
}

/**
 * The art cross-fade, in milliseconds.
 *
 * `ThemeMotion.uiPoster` (ease-out 0.18 s) is the fade the app's most-repeated art surface uses —
 * `PosterSlot`'s `.transition(.opacity.animation(uiPoster))` — so it is the one this pipeline
 * spends. Coil owns the transition and takes a duration rather than a spec, which is why this is a
 * number here rather than a token read at the call site.
 *
 * It is **not** routed through `pickMotion`: a pure opacity fade with no travel is Reduce-Motion
 * safe, and iOS exempts exactly this fade from `ThemeMotion.pick` for the same reason. Coil skips
 * it entirely for a memory-cache hit, which is the iOS rule — "a cache hit never animates" — for
 * free.
 */
internal const val ART_CROSSFADE_MILLIS = 180

// ---------------------------------------------------------------------------------------------
// The loader
// ---------------------------------------------------------------------------------------------

/** Art connections are cheap and idempotent; these are generous, not tight. */
private const val ART_CONNECT_TIMEOUT_SECONDS = 15L
private const val ART_READ_TIMEOUT_SECONDS = 30L
private const val ART_CALL_TIMEOUT_SECONDS = 60L

/**
 * Coil's memory cache, as a fraction of the app heap.
 *
 * iOS pins 96 MB through `NSCache.totalCostLimit`. **Do not port that number**: Android heaps vary
 * by an order of magnitude and 96 MB is around half of a mid-range one. The *rule* — bounded by
 * real decoded bytes rather than by entry count — is what ports; the value adapts.
 */
private const val ART_MEMORY_CACHE_FRACTION = 0.25

/** Original bytes on disk. Explicit, not a percentage of *free* space, which varies per device. */
private const val ART_DISK_CACHE_BYTES = 256L * 1024 * 1024

/**
 * Art's own in-flight budget. **Not OkHttp's defaults, and not the API's.**
 *
 * OkHttp ships 64 global / 5 per host, tuned for a client talking to many hosts about many things.
 * Art talks to one or two CDNs about one thing, so both halves of that are wrong for it: 5 per host
 * serialises a twelve-poster shelf into ranks of five behind one hostname, and a global 64 is a
 * budget large enough to be worth stealing from something else.
 *
 * 8 per host is the shelf: a `LazyRow` fling asks for about that many covers before the user's
 * finger leaves the screen. Both CDNs speak HTTP/2, so those eight multiplex over one connection
 * and the number costs sockets only in the h1.1 fallback, where it is still modest. 16 global
 * leaves room for the second CDN (`image.tmdb.org` beside `s4.anilist.co`) at the same depth.
 */
private const val ART_MAX_REQUESTS = 16
private const val ART_MAX_REQUESTS_PER_HOST = 8

/**
 * The HTTP client the art CDNs see. **Never the API client.**
 *
 * Built from a bare `OkHttpClient.Builder`, so by construction it carries none of the API client's
 * interceptors and no bearer token can reach `s4.anilist.co` or `image.tmdb.org`.
 *
 * ### What is shared, and the one thing that is deliberately not
 *
 * When [shared] is given the two clients share the **connection pool** and the dispatcher's
 * **executor** — sockets and threads, which are expensive to build and carry no policy.
 *
 * They do **not** share the `Dispatcher` itself, which is where an earlier version of this got it
 * wrong while its own comment called a dispatcher "stateless". A `Dispatcher` owns `maxRequests` /
 * `maxRequestsPerHost` and the ready/running queues, so one shared between the two clients is a
 * shared concurrency budget by another name: a scroll burst of poster fetches fills the 64 global
 * slots and the library refresh behind it waits in a queue it never asked to be in — which is
 * exactly the coupling the separate client exists to prevent, arriving on a different axis from
 * the bearer and the call timeout. Art gets its own queue and its own budget
 * ([ART_MAX_REQUESTS]); the API keeps all of its own.
 *
 * The timeouts stay separate for the related reason: an image is allowed to take longer than a
 * JSON request should.
 */
fun artHttpClient(shared: OkHttpClient? = null): OkHttpClient =
    OkHttpClient.Builder()
        .apply { if (shared != null) connectionPool(shared.connectionPool) }
        // Over the API's executor when there is one — OkHttp does not shut down an executor it was
        // handed, and both clients live as long as the process, so the threads are reused and
        // nothing races at teardown.
        .dispatcher(
            (shared?.let { Dispatcher(it.dispatcher.executorService) } ?: Dispatcher()).apply {
                maxRequests = ART_MAX_REQUESTS
                maxRequestsPerHost = ART_MAX_REQUESTS_PER_HOST
            }
        )
        .connectTimeout(ART_CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .readTimeout(ART_READ_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .callTimeout(ART_CALL_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .build()

/**
 * The app's one [ImageLoader]. Build it once, at the application root, and publish it through
 * [ProvideArtPipeline]; never reach for `SingletonImageLoader`, which is not injectable and is not
 * something [ImageBuckets.ladderHit] can get a handle on.
 *
 * @param callFactory the art HTTP client — see [artHttpClient]. Lazy so the client is not
 *   constructed on the main thread during startup.
 */
fun artImageLoader(
    context: Context,
    callFactory: () -> Call.Factory = { artHttpClient() },
): ImageLoader = ImageLoader.Builder(context)
    // Coil's default is Precision.EXACT, which means the memory cache only serves a byte-for-byte
    // dimension match — every distinct on-screen pixel width becomes its own decode, and a hit is
    // rejected for being too LARGE. INEXACT is the "cached image may be larger than requested"
    // rule, which is iOS's serve-larger-never-smaller policy exactly.
    .precision(Precision.INEXACT)
    .memoryCache {
        MemoryCache.Builder()
            .maxSizePercent(context, ART_MEMORY_CACHE_FRACTION)
            .build()
    }
    .diskCache {
        DiskCache.Builder()
            .directory(context.cacheDir.resolve("image_cache").toOkioPath())
            .maxSizeBytes(ART_DISK_CACHE_BYTES)
            .build()
    }
    .components {
        add(OkHttpNetworkFetcherFactory(callFactory = callFactory))
    }
    // Coil 3 does not respect Cache-Control by default and always writes the response to its disk
    // cache — which is what immutable CDN art wants. Adding coil-network-cache-control would make
    // an art fetch re-validate over the network on a cold start for no benefit.
    .crossfade(ART_CROSSFADE_MILLIS)
    .build()

/** The loader published to composition. Provided by [ProvideArtPipeline] at the app root. */
val LocalArtImageLoader = staticCompositionLocalOf<ImageLoader> {
    error("No art ImageLoader. Wrap the app root in ProvideArtPipeline(...).")
}

/** The palette cache published to composition. Provided by [ProvideArtPipeline] at the app root. */
val LocalArtPalette = staticCompositionLocalOf<ArtPaletteCache> {
    error("No ArtPaletteCache. Wrap the app root in ProvideArtPipeline(...).")
}

/**
 * Publishes the art pipeline to the tree. One call, at the root of `setContent`, outside the
 * navigation host — both locals are `static`, so a read costs nothing and nothing invalidates.
 */
@Composable
fun ProvideArtPipeline(imageLoader: ImageLoader, content: @Composable () -> Unit) {
    val context = LocalPlatformContext.current
    val palette = remember(context, imageLoader) { ArtPaletteCache(context, imageLoader) }
    CompositionLocalProvider(
        LocalArtImageLoader provides imageLoader,
        LocalArtPalette provides palette,
        content = content,
    )
}

/**
 * A loader built from the application context, for a host with no dependency injection to hand.
 * Remembered against the application context, so it survives configuration changes with its caches.
 */
@Composable
fun rememberArtImageLoader(): ImageLoader {
    val context = LocalContext.current.applicationContext
    return remember(context) { artImageLoader(context) }
}

/**
 * Warm the memory cache for [url] at the bucket the display will ask for.
 *
 * The iOS app does not prefetch at all — its no-flash guarantee comes from the synchronous cache
 * hit, not from speculation. This is a *new* affordance on Android, where a `LazyRow` shelf recycles
 * harder than a SwiftUI `ScrollView` does, and it has one rule: **prefetch at the display's bucket**.
 * A prefetch at any other size populates the disk cache but not the memory entry the composable
 * will look up, so it buys a decode rather than a frame.
 *
 * Returns the request's [Disposable] so a caller that has scrolled past can drop it.
 */
fun ImageLoader.prefetchArt(context: PlatformContext, url: String?, maxPixel: Int): Disposable? {
    if (url.isNullOrEmpty()) return null
    val bucket = ImageBuckets.bucket(maxPixel)
    if (memoryCache?.get(ImageBuckets.key(url, bucket)) != null) return null
    return enqueue(
        ImageRequest.Builder(context)
            .data(url)
            .size(bucket, bucket)
            .scale(Scale.FIT)
            .precision(Precision.INEXACT)
            .memoryCacheKey(ImageBuckets.key(url, bucket))
            .build()
    )
}

// ---------------------------------------------------------------------------------------------
// Blur — baked, not drawn
// ---------------------------------------------------------------------------------------------

/**
 * A Gaussian-ish blur, **baked into the decoded bitmap**.
 *
 * The app blurs an image in three places — `LandscapeArt`'s portrait ground (a 160-px decode),
 * `ArtHeader`'s portrait ground (1024 px) and `ArtBackdrop`'s ambient wash (320 px). All three are
 * static: nothing animates, nothing samples live content, and all three sources are deliberately
 * tiny because most of the softness is free upscaling. Blurring those at draw time with
 * `Modifier.blur` would (a) force an offscreen buffer per element per frame — `RenderEffect` always
 * renders into one, whatever the compositing strategy — (b) be a **silent no-op below API 31**,
 * which is a fifth of the device floor, and (c) put a Gaussian over a full-bleed band on every
 * frame of a scroll.
 *
 * Baked instead, the blur runs **once** per (url, cacheKey, size) on Coil's decoder dispatcher, is
 * stored in the memory cache under a key that already includes this transformation, and afterwards
 * draws like any other bitmap. Three box passes over 160 × 240 pixels is ~40 k pixel-ops — well
 * under a millisecond — and it is **identical on API 26 and API 37**, so this is the one blurred
 * surface in the app with no capability branch at all.
 *
 * Three box passes approximate a Gaussian with σ ≈ [radius], so the parameter reads as "the sigma
 * you want, **in source pixels**". Edges clamp, which is iOS's `.blur(radius:, opaque: true)` — no
 * transparent-black bleed at the frame edge.
 *
 * **The radii are not iOS's radii.** iOS blurs in points on the drawn frame, *after* the small
 * source has been upscaled; this blurs in source pixels *before* that upscale, so the number is
 * smaller by roughly the upscale factor. iOS's 28 over a 160-px ground is ~10 here. The numbers are
 * a starting point calibrated by eye, not a conversion — see `images-palette.md` §9 Q1.
 *
 * **Equality comes from [cacheKey], and it is coil3's, not this class's.** `Transformation`
 * (coil 3.6.1) implements `equals` / `hashCode` / `toString` in terms of `cacheKey`, so two
 * separately-constructed instances with the same parameters compare equal and a `remember` keyed on
 * a `List<Transformation>` — which is what [ArtImage] does — stays stable across recompositions
 * even for a list built inline. Overriding them here would be dead code that could only get it
 * wrong. What that *does* impose is an invariant on this class: **`cacheKey` must name every
 * parameter that changes the output**, or two configurations would collide both in the memory cache
 * and in `remember`. Add a parameter, add it to the key.
 *
 * @param radius blur sigma in source pixels, after [downscaleTo] is applied.
 * @param downscaleTo longest edge to shrink to before blurring; 0 leaves the decode alone. The
 *   upscale back to the frame does most of the softening, so shrinking first is nearly free
 *   quality-wise and quadratically cheaper.
 */
class BlurTransformation(
    private val radius: Int,
    private val downscaleTo: Int = 0,
) : Transformation() {

    override val cacheKey: String = "blur:$radius:$downscaleTo"

    override suspend fun transform(input: Bitmap, size: Size): Bitmap {
        val source = if (downscaleTo > 0 && max(input.width, input.height) > downscaleTo) {
            val scale = downscaleTo.toFloat() / max(input.width, input.height)
            Bitmap.createScaledBitmap(
                input,
                (input.width * scale).roundToInt().coerceAtLeast(1),
                (input.height * scale).roundToInt().coerceAtLeast(1),
                /* filter = */ true,
            )
        } else {
            input
        }

        val w = source.width
        val h = source.height
        val front = IntArray(w * h).also { source.getPixels(it, 0, w, 0, 0, w, h) }
        val back = IntArray(w * h)
        // A 1-px window is the smallest that does anything; a window wider than half the bitmap
        // would read past both edges at once. Clamped, never coerceIn'd against a bound that can
        // fall below the floor on a 1-px source.
        val r = radius.coerceIn(1, max(1, min(w, h) / 2))

        repeat(BOX_PASSES) {
            boxBlurTransposed(front, back, w, h, r) // w×h → transposed h×w
            boxBlurTransposed(back, front, h, w, r) // h×w → transposed back to w×h
        }

        // The source may be `input`, which Coil owns; only a scaled copy is ours to release.
        if (source !== input) source.recycle()

        return Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            .apply { setPixels(front, 0, w, 0, 0, w, h) }
    }

    private companion object {
        /** Three box passes per axis is the standard Gaussian approximation. */
        const val BOX_PASSES = 3
    }
}

/**
 * Horizontal box blur of [src] (`w × h`), written **transposed** into [dst] (`h × w`), with clamped
 * edges. Running the same kernel twice with the axes swapped gives the separable 2-D blur and needs
 * only one inner loop.
 */
private fun boxBlurTransposed(src: IntArray, dst: IntArray, w: Int, h: Int, r: Int) {
    val div = 2 * r + 1
    for (y in 0 until h) {
        val row = y * w
        var sa = 0
        var sr = 0
        var sg = 0
        var sb = 0
        // Prime the running window with clamped indices — this is what makes the edges clamp.
        for (i in -r..r) {
            val p = src[row + i.coerceIn(0, w - 1)]
            sa += (p ushr 24) and 0xFF
            sr += (p ushr 16) and 0xFF
            sg += (p ushr 8) and 0xFF
            sb += p and 0xFF
        }
        for (x in 0 until w) {
            dst[x * h + y] =
                ((sa / div) shl 24) or ((sr / div) shl 16) or ((sg / div) shl 8) or (sb / div)
            val out = src[row + (x - r).coerceIn(0, w - 1)]
            val into = src[row + (x + r + 1).coerceIn(0, w - 1)]
            sa += ((into ushr 24) and 0xFF) - ((out ushr 24) and 0xFF)
            sr += ((into ushr 16) and 0xFF) - ((out ushr 16) and 0xFF)
            sg += ((into ushr 8) and 0xFF) - ((out ushr 8) and 0xFF)
            sb += (into and 0xFF) - (out and 0xFF)
        }
    }
}

/**
 * **The three blurs in the app, named — the [ArtMaxPixel] of softness.**
 *
 * There are exactly three blurred art surfaces, and each one is a `(radius, downscaleTo)` pair
 * calibrated by eye against the frame it lands in. They live here, beside the mechanism, for the
 * same reason the decode budgets do: a radius spelled at a call site is a size literal in a screen,
 * and three files each constructing their own `BlurTransformation` is three places the softness of
 * this app can drift apart. A composition asks for the blur *by the surface it is drawing*.
 *
 * Each is **one shared instance**, which is also what keeps the `remember` in [ArtImage] cheap: the
 * list is identical by reference on every recomposition, not merely equal.
 *
 * **The radii are not iOS's radii, and no conversion factor connects them.** iOS blurs in POINTS on
 * the drawn frame, *after* its deliberately tiny source has been upscaled into place; this blurs in
 * SOURCE PIXELS *before* that upscale, so each number is smaller by roughly its own surface's
 * upscale factor. The iOS values are recorded below as history, not as targets — see
 * `images-palette.md` §9 Q1. This is the one place they change.
 */
object ArtBlur {

    /**
     * `LandscapeArt`'s portrait ground — a cover composited whole over a blurred copy of itself, at
     * card scale. iOS says 28 over a 160-px ground, upscaled ~2.5× into a 104-dp card.
     */
    val LANDSCAPE_GROUND: List<Transformation> =
        listOf(BlurTransformation(radius = 10, downscaleTo = 160))

    /**
     * `ArtHeader`'s portrait ground — the same composite at BILLBOARD scale, which is why it takes
     * both a larger working size and a larger radius than [LANDSCAPE_GROUND]: the upscale into a
     * 0.7-screen hero is far bigger, and 160 px of source under it reads as mush rather than as a
     * ground. iOS says 48 pt there.
     *
     * Baked rather than drawn, like the other two — see [BlurTransformation]. `Modifier.blur` over
     * a full-bleed hero would cost a `RenderEffect` offscreen buffer on **every frame** of a scroll
     * and would need a private `SDK_INT >= 31` test beside the app's one capability boolean.
     */
    val HERO_PORTRAIT_GROUND: List<Transformation> =
        listOf(BlurTransformation(radius = 26, downscaleTo = 256))

    /**
     * `ArtBackdrop`'s ambient identity wash — the artwork blurred past recognition under the status
     * band.
     *
     * The strongest of the three **relative to its own source**, which is the only comparison that
     * means anything here: 24 over 160 px is a wider kernel than the hero's 26 over 256. It has to
     * be — it is the one blur whose job is that the picture stop being a recognisable picture,
     * where the other two are grounds that a sharp cover sits in front of. iOS says 56 pt, over a
     * source scaled up across the whole screen width.
     */
    val AMBIENT_WASH: List<Transformation> =
        listOf(BlurTransformation(radius = 24, downscaleTo = 160))
}

// ---------------------------------------------------------------------------------------------
// The art-adaptive palette, Android side
// ---------------------------------------------------------------------------------------------

/**
 * Memoises [ArtPalette.dominantTint] per artwork URL. The port of `PaletteCache`
 * (`ios/Sources/DesignSystem/Palette.swift`).
 *
 * One instance per process, published through [LocalArtPalette]. Resolution runs in the cache's own
 * scope rather than a caller's, so a row that scrolls away mid-resolve does not cancel the work the
 * next row is about to need; the result is shared by everyone who asked for the same URL.
 *
 * The extraction itself is in `:model` — pure arithmetic, unit-testable on the JVM, and the only
 * piece of this subsystem that could silently drift from iOS forever.
 */
@Stable
class ArtPaletteCache(
    private val context: PlatformContext,
    private val loader: ImageLoader,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
) {

    /** Resolved tints, as opaque ARGB ints. Bounded by the number of distinct artwork URLs seen. */
    private val resolved = ConcurrentHashMap<String, Int>()

    private val inFlight = HashMap<String, Deferred<Int?>>()
    private val gate = Mutex()

    /** The neutral warm ground. Mirrors `ArtGround.neutralWarm`; the two must not drift. */
    val fallback: Color = Color(ArtPalette.FALLBACK_ARGB)

    /**
     * The tint for [url] **if it is already known**, without suspending.
     *
     * This is the palette's half of the no-flash rule: a screen re-entered with warm caches paints
     * its ground on frame one instead of opening on the fallback and stepping to the real colour.
     */
    fun cachedTint(url: String?): Color? {
        val key = url?.takeIf(String::isNotEmpty) ?: return null
        return resolved[key]?.let { Color(it) }
    }

    /**
     * Resolves the tint for [url], or `null` when there is nothing to derive one from.
     *
     * The optional form is for surfaces that own a meaningful **branded** fallback: returning
     * `null` keeps that fallback on stage while the device is offline or the decode is still busy,
     * instead of replacing it with a neutral colour indistinguishable from the canvas.
     */
    suspend fun tintOrNull(url: String?): Color? {
        val key = url?.takeIf(String::isNotEmpty) ?: return null
        resolved[key]?.let { return Color(it) }

        val work = gate.withLock {
            inFlight[key] ?: scope.async { extract(key) }.also { inFlight[key] = it }
        }
        // Retire the shared job here rather than inside it: a completion handler registered while
        // the map is being written is a re-entrant update of the map from the same thread. A caller
        // cancelled between the await and the cleanup leaves a COMPLETED entry behind, which the
        // next caller for the same URL awaits instantly and then retires — so nothing accumulates.
        //
        // `finally`, because the await can also throw: a shared job that completed exceptionally
        // (a cancellation propagated out of `extract`) left behind would poison the URL for the
        // life of the process — every later caller would take the `inFlight` branch, await the
        // dead job, rethrow, and skip the cleanup again.
        val argb = try {
            work.await()
        } finally {
            // `NonCancellable`: the cleanup itself suspends on the gate, and a cancelled caller
            // would otherwise be cancelled again on the way in and skip the removal.
            withContext(NonCancellable) {
                gate.withLock { if (inFlight[key] === work) inFlight.remove(key) }
            }
        }
        return argb?.let { Color(it) }
    }

    /** [tintOrNull] with the neutral warm [fallback] substituted. */
    suspend fun tint(url: String?): Color = tintOrNull(url) ?: fallback

    /**
     * Fetch, sample, extract. Total by construction: a failure here has **no UI** — the caller
     * keeps whatever ground it already had, and a retry happens only when the URL changes. That is
     * the same contract every art surface in this subsystem honours (no error glyph, no retry
     * button, no spinner), and it is why nothing that happens in here may reach a composition.
     */
    private suspend fun extract(url: String): Int? = try {
        val request = ImageRequest.Builder(context)
            .data(url)
            .size(ArtMaxPixel.PALETTE_SAMPLE, ArtMaxPixel.PALETTE_SAMPLE)
            .scale(Scale.FIT)
            .precision(Precision.INEXACT)
            // getPixels needs CPU-readable pixels, and Coil hands out hardware bitmaps on API 26+
            // by default.
            .allowHardware(false)
            // A 64-px palette bitmap in the memory cache would sit under a key nothing else reads
            // and only add churn against the display decodes. The disk cache still serves it
            // instantly, and `resolved` means it is read once per URL per process anyway.
            .memoryCachePolicy(CachePolicy.DISABLED)
            .build()

        val source = ((loader.execute(request) as? SuccessResult)?.image as? BitmapImage)?.bitmap
        if (source == null) {
            null
        } else {
            withContext(Dispatchers.Default) {
                // `dominantTint`, not `dominantTintOrNull`: art that is entirely neutral, black or
                // blown out resolves to the neutral warm fallback and that answer is CACHED, as it
                // is on iOS. Only a missing or failed image stays unresolved and retryable.
                samplePixels(source)
                    ?.let(ArtPalette::dominantTint)
                    ?.also { resolved[url] = it }
            }
        }
    } catch (cancellation: CancellationException) {
        // Cancellation is not a failure — the app-wide rule (`Error.isCancellation` on iOS) shows
        // up here as letting it through untouched.
        throw cancellation
    } catch (unresolvable: Exception) {
        null
    }

    /**
     * The artwork as [ArtPalette.SAMPLE_EDGE]² sRGB pixels.
     *
     * Drawn through a `Canvas` into a bitmap created explicitly as ARGB_8888 (which is sRGB) rather
     * than scaled with `createScaledBitmap`, for two reasons: it is iOS's construction exactly — a
     * 32 × 32 device-RGB context with medium interpolation — and it *converts* the colour space
     * instead of reinterpreting it. `BitmapFactory` returns sRGB today, so the OKLab matrices are
     * correct as written; the day something routes a Display-P3 poster through here, this draw is
     * what stops P3 values being read as sRGB and every tint shifting.
     */
    private fun samplePixels(bitmap: Bitmap): IntArray? {
        val edge = ArtPalette.SAMPLE_EDGE
        // Defensive: `allowHardware(false)` above means this should never fire, but a hardware
        // bitmap reaching `getPixels` throws rather than degrading.
        val source =
            if (bitmap.config == Bitmap.Config.HARDWARE) bitmap.copy(Bitmap.Config.ARGB_8888, false)
            else bitmap
        if (source == null || source.width <= 0 || source.height <= 0) return null

        val target = Bitmap.createBitmap(edge, edge, Bitmap.Config.ARGB_8888)
        Canvas(target).drawBitmap(
            source,
            null,
            Rect(0, 0, edge, edge),
            Paint(Paint.FILTER_BITMAP_FLAG),
        )
        val pixels = IntArray(edge * edge)
        target.getPixels(pixels, 0, edge, 0, 0, edge, edge)
        target.recycle()
        if (source !== bitmap) source.recycle()
        return pixels
    }
}

// ---------------------------------------------------------------------------------------------
// The quiet form
// ---------------------------------------------------------------------------------------------

/** Chroma ceiling for a quieted ground. */
private const val QUIET_MAX_CHROMA = 0.045

/** The narrow lightness band a tile ground is pinned into. */
private const val QUIET_MIN_LIGHTNESS = 0.40
private const val QUIET_MAX_LIGHTNESS = 0.46

/** How far the quieted colour is pulled toward `surfaceRaised`. */
private const val QUIET_TOWARD_NEUTRAL = 0.20f

/**
 * The card / tile ground form of an art colour — the port of `DetailTint.quiet`
 * (`ios/Sources/Features/FranchiseDetail/DetailSupport.swift`): chroma clamped hard, lightness
 * pinned to a narrow band, then pulled 20 % toward [ThemeColor.surfaceRaised].
 *
 * A tile ground is not a swatch. Behind a numeral, at 120 × 68, an unquieted extraction reads as a
 * colour sample rather than as the show.
 *
 * It lives here, beside [ArtPaletteCache], because it is the *second form of one colour* — putting
 * it anywhere else is how the art layer grew a palette seam of its own.
 */
fun quietTint(tint: Color?): Color? {
    val source = tint ?: return null
    val lab = ArtPalette.oklab(
        r = source.red.toDouble(),
        g = source.green.toDouble(),
        b = source.blue.toDouble(),
    )
    val chroma = kotlin.math.sqrt(lab.a * lab.a + lab.b * lab.b)
    val scale = if (chroma > QUIET_MAX_CHROMA) QUIET_MAX_CHROMA / chroma else 1.0
    val quieted = ArtPalette.srgb(
        OkLab(
            l = min(max(lab.l, QUIET_MIN_LIGHTNESS), QUIET_MAX_LIGHTNESS),
            a = lab.a * scale,
            b = lab.b * scale,
        )
    )
    val neutral = ThemeColor.surfaceRaised
    val m = QUIET_TOWARD_NEUTRAL
    return Color(
        red = quieted.r.toFloat() * (1f - m) + neutral.red * m,
        green = quieted.g.toFloat() * (1f - m) + neutral.green * m,
        blue = quieted.b.toFloat() * (1f - m) + neutral.blue * m,
        alpha = 1f,
    )
}

/**
 * The tint derived from [url]'s artwork, or `null` until it resolves.
 *
 * Seeded from the synchronous cache, so a surface whose palette is already known never renders a
 * frame without it. When [url] changes the state is rebuilt — the previous show's colour is not
 * held on stage under the new one's art.
 *
 * A caller with a branded fallback keeps it while this is `null`; a caller that wants the neutral
 * warm ground writes `?: LocalArtPalette.current.fallback`. Animate the handover on
 * `ThemeMotion.uiGentle` (`animateColorAsState`) — the step from a dark fallback to a lit colour is
 * the "black, then it becomes flush" jump, and a 220 ms fade is the whole fix.
 *
 * @param quiet return the [quietTint] form — the ground behind a numeral on a 120 × 68 tile.
 */
@Composable
fun rememberArtTint(url: String?, quiet: Boolean = false): Color? {
    val palette = LocalArtPalette.current
    val seed = palette.cachedTint(url).let { if (quiet) quietTint(it) else it }
    val state = produceState<Color?>(initialValue = seed, url, palette, quiet) {
        if (value == null) {
            value = palette.tintOrNull(url).let { if (quiet) quietTint(it) else it }
        }
    }
    return state.value
}
