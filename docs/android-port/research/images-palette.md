# Images, art-adaptive palette, and blur on Android

**Status:** research / decision note. Written **2026-09-04**. Every version below was checked against
a primary source on that date (Maven Central `maven-metadata.xml`, the project's own changelog, or
the AOSP/AndroidX source). Links and dates are in §10.

**Scope:** the four subsystems that sit under every pixel of artwork in *Previously.* —
(1) the image pipeline, (2) size-aware requests and the no-flash first frame, (3) the
portrait-poster-on-its-own-blurred-ground composite, (4) the art-adaptive palette — plus (5) the
blur/material chrome that the design language is built on.

**Reads against:** `docs/android-port/spec/chrome-images.md` (the exhaustive behavioural spec of the
iOS side — every number in it is authoritative and this note does not restate them),
`research/compose-architecture.md` (toolchain), `research/minsdk-decision.md` (**minSdk 26**).

> **One correction to the brief up front.** The brief says the iOS app "uses Nuke with maxPixel-sized
> requests, prefetching…". It does not. There is **no third-party image library anywhere in
> `ios/`** — `ImageLoader.swift` is a bespoke ~215-line `NSCache` + ImageIO pipeline, and it does
> **no prefetching at all**. `spec/chrome-images.md` §4.1 already flags this. What the iOS app
> genuinely has, and what must be reproduced, is: bucketed `maxPixel` decodes, a
> **serve-larger-never-smaller** memory cache, in-flight de-duplication, a **synchronous cache hit on
> the first frame**, and off-main downsampling. Prefetching is a *new* opportunity on Android, not a
> port requirement — see §2.5.

---

## 1. Recommendation up front

| Decision | Pick | One-line reason |
|---|---|---|
| Image loader | **Coil `3.6.1`** (`coil-compose` + `coil-network-okhttp`) | Compose-native, already compiled against Compose **1.12.0** (our BOM), minSdk 23, and its memory cache already implements serve-larger-never-smaller. |
| Memory cache | `maxSizePercent(context, 0.25)`, **not** iOS's fixed 96 MB | Android heaps vary 10×; the *rule* (bounded by real decoded bytes) ports, the number does not. |
| Disk cache | Explicit **256 MB** in `cacheDir/image_cache`, `respectCacheHeaders` left **off** (Coil's default) | Coil 3 ignores `Cache-Control` by default and always writes to disk — which is what we want for immutable CDN art. |
| Size discipline | **Bucketed `size(bucket)` + `Precision.INEXACT` on every request**, ladder from `spec/chrome-images.md` §4.3 | Coil's default is `Precision.EXACT`; leaving it there means one decode per distinct pixel width on screen. |
| No-flash first frame | Ladder-probe `imageLoader.memoryCache` during composition → `placeholderMemoryCacheKey` | Reproduces the iOS synchronous-cache-hit behaviour exactly, with Coil's own API. Removes the recycled-cell flash. |
| Portrait→landscape composite | **Bake the blur into the bitmap** with a Coil `Transformation` (3-pass box blur on a ≤160 px decode), *not* `Modifier.blur` | Computed once per (url, radius), cached in memory + keyed on disk, **zero per-frame cost, and no API-level branch** — it works identically on API 26 and API 37. |
| Palette | **Port the OKLab extractor verbatim** (`Palette.swift` → ~70 lines of Kotlin) on a 32×32 `getPixels` | Any Android quantiser (androidx.palette, material-color-utilities) gives a *different colour* from iOS for the same poster. Cross-platform drift in the app's ground colour is not acceptable, and the algorithm is pure arithmetic. |
| Backdrop blur (chrome bands, glass pill) | **Haze `1.7.3`** (`haze` + `haze-materials`), gated on `SDK_INT >= 31 && !reduceTransparency` | The only surfaces that need to blur *live content*. Haze uses `RenderEffect` on API 31+ (verified in source); below 31 the app takes the design's existing opaque-canvas path. |
| Haze major version | **1.7.3 stable, not 2.0.0-beta02** | 1.7.3 is already built against Compose 1.12.0, and `haze-materials` — which contains `CupertinoMaterials.ultraThin()`, literally Apple's iOS 18 `.ultraThinMaterial` values — **exists only on the 1.x line**. 2.x is beta and drops it. |
| Progressive vs mask | **`mask = Brush.verticalGradient(...)`, never `HazeProgressive`** | iOS does not vary the blur radius; it draws a constant-radius material and *masks* it (`Rectangle().fill(.ultraThinMaterial).mask(blurMask)`). Haze's mask costs **+5 %**; progressive costs **+25 %**. Mask is both cheaper and the more faithful port. |

**Confidence: high** on Coil, the bucketing, the baked-blur composite and the palette port — all
verified against source. **Medium** on the Haze frame budget: Chris Banes' published benchmarks are
+29 % to +45 % frame duration for the *cost of Haze*, which is a real number but not measured on our
screens; and Haze carries a documented extra-invalidation workaround on **API 31 exactly** (§5.6).
**Low/uncalibrated** on absolute blur radii: SwiftUI's and Skia's blur-radius→sigma mappings are not
documented as equal, so every radius in `spec/chrome-images.md` needs a side-by-side capture pass
(§9, Q1).

### The single most useful structural finding

**Only *backdrop* blur needs an API-level branch. Every *image* blur in this app can be baked.**

The iOS app blurs images in three places — `LandscapeArt`'s portrait ground (radius 28 over a
**160 px** decode), `ArtHeader`'s portrait ground (radius 48 over a **1024 px** decode), and
`ArtBackdrop`'s ambient wash (radius 56 over a **320 px** decode). All three are *static* — nothing
animates, nothing samples live content, and all three sources are deliberately tiny because most of
the softness is free upscaling. Blurring those at draw time with `Modifier.blur` would (a) force an
offscreen layer per element per frame, (b) be a silent no-op below API 31, and (c) put a Gaussian
over a full-bleed band on every frame of a scroll.

Doing it as a Coil `Transformation` instead: the blur runs **once** per (url, radius, size) on
`Dispatchers.IO` during decode, the result is stored in Coil's memory cache under a key that already
includes the transformation, and it draws like any other bitmap. A 3-pass box blur on 160×240
pixels is ~40 k pixel-ops — sub-millisecond — and it is **identical on API 26 and API 37**.

This directly relaxes `research/minsdk-decision.md` point 4 ("Below 31 there is also no
`RenderEffect` for the hero bloom / art-adaptive wash. Those must degrade to a plain gradient…").
They need not degrade. Only the chrome bands and the glass pill do.

---

## 2. Coil 3

### 2.1 Versions and evidence

| Artifact | Version | Verified |
|---|---|---|
| `io.coil-kt.coil3:coil-compose` | **3.6.1** | `repo1.maven.org` `maven-metadata.xml`, `lastUpdated 20260901051123` |
| `io.coil-kt.coil3:coil-network-okhttp` | **3.6.1** | same |
| Compose it is built against | **1.12.0** (`org.jetbrains.compose.foundation:foundation-android:1.12.0` in the 3.6.1 POM) | POM fetched 2026-09-04 |
| minSdk | **23** (raised from 21 in 3.5.0, 10 Jun 2026) | Coil changelog |

Coil 3.6.1 shipped 1 Sep 2026 (a JS-only fix over 3.6.0, 26 Aug 2026). Relevant recent history:
**3.4.0** (24 Feb 2026) added a *concurrent request strategy* that combines in-flight network
requests — this is the in-flight de-duplication the iOS `ImageLoader` actor hand-rolls, and it means
the palette request (§4) shares a download with the display request for free. **3.3.0** (22 Jul
2025) added memory-cache limiting while the app is backgrounded.

> Note: the Maven Central **Solr search index** (`search.maven.org/solrsearch`) is stale — on
> 2026-09-04 it still reports `3.2.0` for Coil and `1.5.3` for Haze. The
> `repo1.maven.org/.../maven-metadata.xml` files are authoritative and were used instead. Do not
> take a version number from the search UI.

### 2.2 The `ImageLoader`

```kotlin
// di/ImageModule.kt
@Module
@InstallIn(SingletonComponent::class)
object ImageModule {

    @Provides
    @Singleton
    fun imageLoader(
        @ApplicationContext context: Context,
        @ArtHttpClient artClient: dagger.Lazy<OkHttpClient>,
    ): ImageLoader = ImageLoader.Builder(context)
        // ── size discipline ───────────────────────────────────────────────
        // Coil's default is Precision.EXACT (verified in ImageRequest.Defaults).
        // EXACT means the memory cache only serves a byte-for-byte dimension match,
        // so every distinct on-screen pixel width becomes its own decode. INEXACT
        // turns on the "cached image may be LARGER than requested" rule, which is
        // exactly iOS's serve-larger-never-smaller policy.
        .precision(Precision.INEXACT)

        // ── memory: decoded bitmaps ───────────────────────────────────────
        // iOS pins 96 MB via NSCache.totalCostLimit. Do NOT port that number:
        // 96 MB is ~50 % of a mid-range Android heap and will OOM. Percent-of-heap
        // keeps the *rule* (bounded by real decoded bytes) and adapts the value.
        .memoryCache {
            MemoryCache.Builder()
                .maxSizePercent(context, 0.25)
                .build()
        }

        // ── disk: original bytes ──────────────────────────────────────────
        // Explicit bytes, not maxSizePercent: percent is of *free* space, so the
        // same build behaves differently on a full phone and an empty one.
        .diskCache {
            DiskCache.Builder()
                .directory(context.cacheDir.resolve("image_cache"))
                .maxSizeBytes(256L * 1024 * 1024)
                .build()
        }

        // ── network ───────────────────────────────────────────────────────
        // A SEPARATE OkHttpClient from the API client: image hosts must never see
        // the Clerk bearer token, and image traffic must not share the API client's
        // 17.6 s callTimeout budget. Share the connection pool + dispatcher via
        // newBuilder() (see networking-auth.md).
        .components {
            add(OkHttpNetworkFetcherFactory(callFactory = { artClient.get() }))
        }
        // Coil 3 does NOT respect Cache-Control by default and always writes the
        // response to its disk cache. That is the behaviour we want for immutable
        // CDN art (AniList s4.anilist.co, TMDB image.tmdb.org). Leave it. Adding
        // coil-network-cache-control would make an art fetch re-validate over the
        // network on a cold start for no benefit.

        .crossfade(180)          // ThemeMotion.uiPoster = easeOut(0.18)
        .build()
}
```

Two behaviours of that config are load-bearing and worth stating explicitly, because both are
Coil behaviours rather than things we wrote:

1. **Crossfade is skipped for memory-cache hits.** `CrossfadeTransition` returns no transition when
   `result.dataSource == DataSource.MEMORY_CACHE`. That is precisely the iOS rule — "a recycled cell
   never flashes, a fresh load cross-fades" — and it means `crossfade(180)` is safe to set globally.
2. **The memory cache key does not include the size** (unless the request has transformations).
   Coil instead *validates* the cached bitmap against the request: for `Precision.INEXACT` a cached
   image is accepted when it is the same size **or larger**, and rejected when it is smaller. So
   Coil already refuses to hand a hero the row-thumbnail decode — the blurry-hero bug listed as
   Android risk #9 in `spec/chrome-images.md` **does not reproduce**. What Coil lacks is *coexistence*:
   one entry per URL, so a 270 px row decode evicts the 2048 px hero decode and the hero re-decodes
   from disk. §2.3 fixes that with one line.

### 2.3 Buckets: coexistence, not correctness

```kotlin
// ui/image/ImageBuckets.kt
object ImageBuckets {
    /** Verbatim from ImageCache.buckets (ios/Sources/DesignSystem/ImageLoader.swift). */
    val LADDER = intArrayOf(128, 192, 256, 384, 512, 768, 1024, 1536, 2048)

    /** The smallest rung that satisfies [maxPixel]; above the ladder, the exact request. */
    fun bucket(maxPixel: Int): Int =
        LADDER.firstOrNull { it >= maxPixel } ?: maxPixel

    fun key(url: String, bucket: Int) = MemoryCache.Key("$url|$bucket")

    /**
     * iOS's serve-larger walk, as a *placeholder* probe: the best already-decoded
     * copy that is at least as detailed as [want]. Used only to paint frame one;
     * the correctly-bucketed decode still runs and replaces it.
     *
     * O(9) LruCache lookups. Safe to call during composition.
     */
    fun ladderHit(cache: MemoryCache?, url: String, want: Int): MemoryCache.Key? {
        cache ?: return null
        for (b in LADDER) {
            if (b < want) continue
            val k = key(url, b)
            if (cache[k] != null) return k
        }
        return null
    }
}
```

Setting `memoryCacheKey = "$url|$bucket"` gives each rung its own entry, so a Library row thumb can
never evict the Detail hero. Cost versus iOS: a request for bucket 384 is *not served* by a cached
1024 entry (different key) — it decodes again, from the **disk** cache, no network. The
`ladderHit` probe hides that decode behind the larger copy, so the user never sees it.

### 2.4 The `ArtImage` composable — the `CachedAsyncImage` port

```kotlin
// ui/image/ArtImage.kt
private val GradientPlaceholderBrush = Brush.linearGradient(
    colors = listOf(Color(0xFF27272F), Color(0xFF141418)),
    start = Offset.Zero, end = Offset.Infinite,   // topLeading → bottomTrailing
)

@Composable
fun ArtImage(
    url: String?,
    maxPixel: Int,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.Crop,   // iOS .fill
    alignment: Alignment = Alignment.Center,
    /** Hosts that draw their own ground (palette tint, art backdrop) pass false. */
    placeholder: Boolean = true,
    /** Frame aspect (w/h) that a near-matching .fit image snaps to fill against. */
    fitSnapAspect: Float? = null,
    transformations: List<Transformation> = emptyList(),
) {
    val context = LocalContext.current
    val loader = LocalArtImageLoader.current
    val bucket = remember(maxPixel) { ImageBuckets.bucket(maxPixel) }

    // Frame one: the best decode already in memory at >= this bucket.
    val ladderKey = remember(url, bucket) {
        if (url.isNullOrEmpty() || transformations.isNotEmpty()) null
        else ImageBuckets.ladderHit(loader.memoryCache, url, bucket)
    }

    val scale = remember(contentScale, fitSnapAspect) {
        if (fitSnapAspect != null && contentScale == ContentScale.Fit) {
            SnapFitContentScale(fitSnapAspect)
        } else contentScale
    }

    Box(
        modifier
            .clipToBounds()                                    // iOS .clipped()
            .then(if (placeholder) Modifier.background(GradientPlaceholderBrush) else Modifier)
            .clearAndSetSemantics { }                          // iOS .accessibilityHidden(true)
    ) {
        if (!url.isNullOrEmpty()) {
            AsyncImage(
                model = remember(url, bucket, ladderKey, transformations) {
                    ImageRequest.Builder(context)
                        .data(url)
                        .size(bucket)                          // square box; INEXACT + FIT fits inside
                        .precision(Precision.INEXACT)
                        .apply {
                            // A transformed request must let Coil build the key itself:
                            // the transformation's cacheKey (and the size) go into it.
                            if (transformations.isEmpty()) {
                                memoryCacheKey(ImageBuckets.key(url, bucket))
                                placeholderMemoryCacheKey(ladderKey)
                            } else {
                                transformations(transformations)
                                allowHardware(false)           // transforms need a software bitmap
                            }
                        }
                        // Don't re-fade a picture the user is already looking at.
                        .crossfade(if (ladderKey != null) 0 else 180)
                        .build()
                },
                contentDescription = null,
                contentScale = scale,
                alignment = alignment,
                imageLoader = loader,
                modifier = Modifier.matchParentSize(),
            )
        }
    }
}
```

Three details that are not obvious:

**`Modifier.matchParentSize()` inside a sized `Box` is the port of iOS's `Color.clear` sizing box.**
The iOS comment ("an `Image` reports its pixel dimensions as its ideal size… the ideal leaks out and
inflates the whole enclosing layout") has a direct Compose analogue: an `AsyncImage` in a `Row`
with no `weight` and no width will report the painter's intrinsic size. `matchParentSize` measures
from the parent, never contributes to it — same guarantee, different mechanism.

**`fitSnapAspect` becomes a custom `ContentScale`, not view state.** iOS reads the decoded image's
aspect at draw time to decide `.fit` vs `.fill`. In Compose the same decision is a pure function of
(source size, dest size), which is exactly `ContentScale`'s contract — so it needs no state, no
recomposition, and no `AsyncImagePainter.state` observation:

```kotlin
/** iOS CachedAsyncImage.resolvedContentMode: a .fit that would leave only a sliver of mat fills. */
@Immutable
class SnapFitContentScale(
    private val targetAspect: Float,
    private val tolerance: Float = 0.08f,   // ios/…/ImageLoader.swift: fitSnapTolerance
) : ContentScale {
    override fun computeScaleFactor(srcSize: Size, dstSize: Size): ScaleFactor {
        if (srcSize.height <= 0f || targetAspect <= 0f) {
            return ContentScale.Fit.computeScaleFactor(srcSize, dstSize)
        }
        val aspect = srcSize.width / srcSize.height
        return if (abs(aspect / targetAspect - 1f) <= tolerance) {
            ContentScale.Crop.computeScaleFactor(srcSize, dstSize)
        } else {
            ContentScale.Fit.computeScaleFactor(srcSize, dstSize)
        }
    }
}
```

**`LocalArtImageLoader`.** Don't use `SingletonImageLoader` — the Hilt-provided loader should be
published through a `staticCompositionLocalOf<ImageLoader>` at the root. It makes the loader
injectable in tests and Paparazzi/Roborazzi screenshots, and it is what `ladderHit` needs a handle
on anyway.

### 2.5 Prefetching (new on Android, no iOS counterpart)

The iOS app does not prefetch. Android should, because `LazyRow` shelves recycle harder than a
SwiftUI `ScrollView` does. Coil has no prefetch API; you enqueue a request with no target:

```kotlin
// ui/image/Prefetch.kt
@Composable
fun ArtPrefetch(
    state: LazyListState,
    urls: () -> List<String?>,
    maxPixel: Int,
    lookahead: Int = 6,
) {
    val loader = LocalArtImageLoader.current
    val context = LocalContext.current
    val bucket = remember(maxPixel) { ImageBuckets.bucket(maxPixel) }

    LaunchedEffect(state, bucket) {
        val live = ArrayDeque<Disposable>()
        snapshotFlow { state.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0 }
            .distinctUntilChanged()
            .collect { last ->
                val all = urls()
                for (i in (last + 1)..(last + lookahead)) {
                    val u = all.getOrNull(i) ?: continue
                    live += loader.enqueue(
                        ImageRequest.Builder(context)
                            .data(u)
                            .size(bucket)                       // MUST match the display bucket,
                            .precision(Precision.INEXACT)       // or the prefetch is wasted work
                            .memoryCacheKey(ImageBuckets.key(u, bucket))
                            .build()
                    )
                }
                while (live.size > lookahead * 3) live.removeFirst().dispose()
            }
    }
}
```

The one rule that makes prefetching worth anything: **prefetch at the same bucket the display will
ask for.** A prefetch at a different size populates the disk cache but not the memory entry the
composable will look up, so it buys a decode, not a frame.

---

## 3. The portrait-on-its-own-blurred-ground composite

This is `LandscapeArt(portraitSource: true)` and the portrait branch of `ArtHeader` from
`spec/chrome-images.md` §4.8 — "about a third" of the catalogue has no landscape art, so this path
is on screen constantly.

### 3.1 A blur that is baked, not drawn

```kotlin
// ui/image/BlurTransformation.kt
/**
 * Gaussian-ish blur, baked into the decoded bitmap.
 *
 * Three box passes approximate a Gaussian with sigma ~= sqrt(r^2 + r) ~= r, which is
 * close enough that [radius] can be read as "the sigma you want, in source pixels".
 *
 * Edges CLAMP (the window is primed with clamped indices), which is iOS's
 * `.blur(radius:, opaque: true)` — no transparent-black bleed at the frame edge.
 *
 * Runs once per (url, cacheKey, size) on Coil's decoder dispatcher. At the sizes this
 * is used for (<= 160 px for a card, <= 320 px for the wash) it is well under a
 * millisecond and never touches a frame.
 */
class BlurTransformation(
    private val radius: Int,
    /** Longest edge to shrink to before blurring. The upscale does most of the softening. */
    private val downscaleTo: Int = 0,
) : Transformation() {

    override val cacheKey = "blur:$radius:$downscaleTo"

    override suspend fun transform(input: Bitmap, size: Size): Bitmap {
        val src = if (downscaleTo > 0 && max(input.width, input.height) > downscaleTo) {
            val s = downscaleTo.toFloat() / max(input.width, input.height)
            Bitmap.createScaledBitmap(
                input,
                (input.width * s).roundToInt().coerceAtLeast(1),
                (input.height * s).roundToInt().coerceAtLeast(1),
                true,
            )
        } else input

        val w = src.width
        val h = src.height
        val a = IntArray(w * h).also { src.getPixels(it, 0, w, 0, 0, w, h) }
        val b = IntArray(w * h)
        val r = radius.coerceIn(1, min(w, h) / 2)

        repeat(3) {
            boxBlurTransposed(a, b, w, h, r)   // w×h → transposed h×w
            boxBlurTransposed(b, a, h, w, r)   // h×w → transposed back to w×h
        }
        return Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            .apply { setPixels(a, 0, w, 0, 0, w, h) }
    }
}

/** Horizontal box blur of [src] (w×h), written TRANSPOSED into [dst] (h×w). Clamped edges. */
private fun boxBlurTransposed(src: IntArray, dst: IntArray, w: Int, h: Int, r: Int) {
    val div = 2 * r + 1
    for (y in 0 until h) {
        val row = y * w
        var sa = 0; var sr = 0; var sg = 0; var sb = 0
        for (i in -r..r) {
            val p = src[row + i.coerceIn(0, w - 1)]
            sa += (p ushr 24) and 0xFF; sr += (p ushr 16) and 0xFF
            sg += (p ushr 8) and 0xFF;  sb += p and 0xFF
        }
        for (x in 0 until w) {
            dst[x * h + y] =
                ((sa / div) shl 24) or ((sr / div) shl 16) or ((sg / div) shl 8) or (sb / div)
            val out = src[row + (x - r).coerceIn(0, w - 1)]
            val inn = src[row + (x + r + 1).coerceIn(0, w - 1)]
            sa += ((inn ushr 24) and 0xFF) - ((out ushr 24) and 0xFF)
            sr += ((inn ushr 16) and 0xFF) - ((out ushr 16) and 0xFF)
            sg += ((inn ushr 8) and 0xFF) - ((out ushr 8) and 0xFF)
            sb += (inn and 0xFF) - (out and 0xFF)
        }
    }
}
```

### 3.2 The composite

```kotlin
// ui/image/LandscapeArt.kt
@Composable
fun LandscapeArt(
    url: String?,
    portraitSource: Boolean,
    maxPixel: Int,
    modifier: Modifier = Modifier,
    alignment: Alignment = Alignment.TopCenter,   // iOS default .top
) {
    if (!portraitSource) {
        ArtImage(url, maxPixel, modifier, ContentScale.Crop, alignment, placeholder = true)
        return
    }
    Box(modifier.clipToBounds()) {
        // 1. the ground: a 160 px decode, blurred once, cropped to FILL the frame.
        //    Cropping happens at draw time here, where iOS crops before blurring —
        //    with clamped edges the two are visually identical, and blur-then-crop is
        //    the better order at the seams. What matters is `Crop`, not `Fit`:
        //    a `Fit` ground samples whatever corner the poster landed in.
        ArtImage(
            url = url,
            maxPixel = 160,
            modifier = Modifier.matchParentSize(),
            contentScale = ContentScale.Crop,
            placeholder = false,
            transformations = remember { listOf(BlurTransformation(radius = 10, downscaleTo = 160)) },
        )
        Box(Modifier.matchParentSize().background(Color.Black.copy(alpha = 0.32f)))

        // 2. the whole poster, fitted, with its contact shadow.
        //    "Without it the two read as one badly-decoded image."
        ArtImage(
            url = url,
            maxPixel = maxPixel,
            modifier = Modifier
                .matchParentSize()
                .padding(vertical = ThemeSpace.x2)
                .shadow(8.dp, clip = false, ambientColor = Color.Black, spotColor = Color.Black),
            contentScale = ContentScale.Fit,
            placeholder = false,
        )
    }
}
```

Note `radius = 10` where iOS says 28: the iOS radius is in **points on the drawn frame**, applied
after the 160 px source has been upscaled ~2.5×; here the blur runs in **source pixels before** the
upscale, so the number is smaller by roughly that factor. This is the single most likely thing to be
wrong by eye on the first build — see §9, Q1 for how to calibrate it.

The same shape covers `ArtBackdrop` (the ambient wash): `maxPixel = 320`,
`BlurTransformation(radius = 20, downscaleTo = 128)`, `ContentScale.Crop`, `alpha = 0.70f *
intensity`, then the four gradient layers from `spec/chrome-images.md` §4.8(d) drawn with
`Modifier.drawWithContent`/`Brush.verticalGradient`. Because the blur is baked, the wash is **one
static bitmap plus four gradients** — it can sit under a `LazyColumn` at 120 Hz without any
per-frame work at all, which is the property iOS asserts for it ("drawn once, never animated, never
touched on scroll").

---

## 4. The art-adaptive palette

### 4.1 Recommendation: port the OKLab extractor; use no Android palette library

`spec/chrome-images.md` §4.9 already says "do **not** use `androidx.palette`". That is right, and the
reason generalises to every off-the-shelf option:

| Option | Status on 2026-09-04 | Why rejected |
|---|---|---|
| `androidx.palette:palette` | **1.1.0-alpha01**, 1 Jul 2026 (stable is still **1.0.0**; 1.1.0-alpha01's only real change is merging `palette-ktx` in) | Quantises in **HSL**, scores by population × saturation with its own target profiles (`Vibrant`, `Muted`, …). For the same poster it returns a different colour from the iOS extractor — often greyer. The ground colour would visibly differ between platforms for the same show. |
| `material-color-utilities` (HCT + Celebi quantizer, what Material You uses) | Shipped inside `com.google.android.material`, and as third-party wrappers | Technically the best quantiser here — but it answers a *different question* (a tonal palette for theming), and again returns a different hue from the iOS extractor. |
| `kmpalette` | KMP port of androidx.palette | Same algorithm, same objection. |
| **Port `PaletteCache.dominantTint`** | — | ~70 lines of `Double` arithmetic with no platform surface. Produces the **same colour as iOS, bit for bit**, including the L 0.30–0.44 / C 0.075–0.145 clamps and the 15 % blend toward brand amber — clamps that carry a documented regression note and must not be re-derived. |

The clamps are the reason this is not a "just pick a dominant colour" problem. The extractor is not
returning the poster's colour; it is returning a *derived* colour that is guaranteed dark enough for
`textPrimary` (#F4F1EC) to clear 12:1 on the composite, and warm enough that the app does not swing
olive or steel from tab to tab. Any library that does not know those constraints gives an answer
that has to be re-clamped anyway — at which point the library did nothing.

### 4.2 The extractor

```kotlin
// ui/palette/ArtPalette.kt  — a direct port of ios/Sources/DesignSystem/Palette.swift
object ArtPalette {

    /** PaletteCache.fallback — neutral warm surface. */
    val Fallback = Color(0xFF1C1A17)

    private val BRAND_AMBER_LAB = oklab(0xF0 / 255.0, 0xA2 / 255.0, 0x4E / 255.0)

    fun dominantTint(bitmap: Bitmap): Color {
        val w = 32; val h = 32
        val small = Bitmap.createScaledBitmap(bitmap, w, h, /* filter = */ true)
        val px = IntArray(w * h).also { small.getPixels(it, 0, w, 0, 0, w, h) }

        // 12 hue bins × 4 lightness bins, weighted by population.
        val buckets = HashMap<Int, DoubleArray>()   // [sumL, sumA, sumB, n]
        for (p in px) {
            val alpha = ((p ushr 24) and 0xFF) / 255.0
            if (alpha < 0.8) continue
            val (l, a, b) = oklab(
                ((p ushr 16) and 0xFF) / 255.0,
                ((p ushr 8) and 0xFF) / 255.0,
                (p and 0xFF) / 255.0,
            )
            if (l < 0.08 || l > 0.92) continue
            val chroma = sqrt(a * a + b * b)
            if (chroma < 0.035) continue
            val hue = atan2(b, a)
            val key = ((hue + PI) / (2 * PI) * 12).toInt() * 10 + (l * 4).toInt()
            val e = buckets.getOrPut(key) { DoubleArray(4) }
            e[0] += l; e[1] += a; e[2] += b; e[3] += 1.0
        }
        val best = buckets.values.maxByOrNull { it[3] } ?: return Fallback
        if (best[3] <= 0.0) return Fallback

        var l = best[0] / best[3]
        var a = best[1] / best[3]
        var bb = best[2] / best[3]

        // Clamp lightness and chroma; lean the hue 15 % toward brand amber.
        // These numbers are a documented regression fix — see spec/chrome-images.md §4.9.
        l = l.coerceIn(0.30, 0.44)
        val c = sqrt(a * a + bb * bb)
        val cc = c.coerceIn(0.075, 0.145)
        if (c > 0) {
            var ua = a / c; var ub = bb / c
            val (_, wa, wb) = BRAND_AMBER_LAB
            val wn = sqrt(wa * wa + wb * wb)
            ua = 0.85 * ua + 0.15 * (wa / wn)
            ub = 0.85 * ub + 0.15 * (wb / wn)
            val un = sqrt(ua * ua + ub * ub)
            a = ua / un * cc; bb = ub / un * cc
        }
        val (r, g, b2) = srgb(l, a, bb)
        return Color(r.toFloat(), g.toFloat(), b2.toFloat(), 1f)
    }

    // ── sRGB ↔ OKLab (Björn Ottosson) ────────────────────────────────────
    private fun lin(v: Double) = if (v <= 0.04045) v / 12.92 else ((v + 0.055) / 1.055).pow(2.4)
    private fun gam(v: Double) = if (v <= 0.0031308) 12.92 * v else 1.055 * v.pow(1 / 2.4) - 0.055

    fun oklab(r: Double, g: Double, b: Double): Triple<Double, Double, Double> {
        val rl = lin(r); val gl = lin(g); val bl = lin(b)
        val l_ = cbrt(0.4122214708 * rl + 0.5363325363 * gl + 0.0514459929 * bl)
        val m_ = cbrt(0.2119034982 * rl + 0.6806995451 * gl + 0.1073969566 * bl)
        val s_ = cbrt(0.0883024619 * rl + 0.2817188376 * gl + 0.6299787005 * bl)
        return Triple(
            0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
        )
    }

    fun srgb(l: Double, a: Double, b: Double): Triple<Double, Double, Double> {
        val l_ = l + 0.3963377774 * a + 0.2158037573 * b
        val m_ = l - 0.1055613458 * a - 0.0638541728 * b
        val s_ = l - 0.0894841775 * a - 1.2914855480 * b
        val L = l_ * l_ * l_; val M = m_ * m_ * m_; val S = s_ * s_ * s_
        return Triple(
            (4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S).let { gam(it).coerceIn(0.0, 1.0) },
            (-1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S).let { gam(it).coerceIn(0.0, 1.0) },
            (-0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S).let { gam(it).coerceIn(0.0, 1.0) },
        )
    }
}
```

**Put this in `:model`, the pure-JVM module** (`research/compose-architecture.md` §1). `Bitmap` is
Android-only, so split it: `dominantTint(pixels: IntArray)` in `:model` with a millisecond-fast JVM
unit test, and a two-line Android wrapper that does `createScaledBitmap` + `getPixels`. Seed the test
with a handful of real posters and the exact RGB triples the iOS build produces — that is the only
cheap way to prove the port did not drift.

### 4.3 Getting the bitmap: a separate tiny request, not the display decode

iOS shares one decode between the display image and the palette (that's why its palette `maxPixel`s
are *smaller* than its display ones — the serve-larger rule means the already-decoded poster
satisfies them). **On Android that trick is not available**, for one reason: Coil returns
**hardware bitmaps** by default on API 26+, and a hardware bitmap has no CPU-readable pixels —
`getPixels` throws. Setting `allowHardware(false)` app-wide to fix it would move every poster's
pixels back into the Java heap and add a GPU upload per texture: strictly worse.

So the palette gets its own request. It is cheap: the bytes come from Coil's disk cache (or are
coalesced with the in-flight display fetch by Coil 3.4.0+'s concurrent-request strategy), and the
decode is 64 px.

```kotlin
// ui/palette/PaletteCache.kt
@Singleton
class PaletteCache @Inject constructor(
    @ApplicationContext private val context: Context,
    private val loader: ImageLoader,
) {
    private val cache = LruCache<String, Color>(256)
    private val inFlight = ConcurrentHashMap<String, Deferred<Color?>>()

    /** null keeps a caller's *branded* fallback on stage (iOS resolveIfAvailable). */
    suspend fun tintOrNull(url: String?): Color? {
        if (url.isNullOrEmpty()) return null
        cache[url]?.let { return it }
        return coroutineScope {
            inFlight.getOrPut(url) {
                async(Dispatchers.Default) {
                    try {
                        val result = loader.execute(
                            ImageRequest.Builder(context)
                                .data(url)
                                .size(64)
                                .precision(Precision.INEXACT)
                                .allowHardware(false)              // getPixels needs CPU pixels
                                .memoryCachePolicy(CachePolicy.DISABLED) // don't evict display decodes
                                .build()
                        )
                        val bmp = (result.image as? BitmapImage)?.bitmap ?: return@async null
                        ArtPalette.dominantTint(bmp).also { cache.put(url, it) }
                    } finally {
                        inFlight.remove(url)
                    }
                }
            }
        }.await()
    }

    suspend fun tint(url: String?): Color = tintOrNull(url) ?: ArtPalette.Fallback
}
```

`memoryCachePolicy(CachePolicy.DISABLED)` is deliberate: a 64 px palette bitmap in the memory cache
would sit under the same URL key as nothing useful and only add churn. The disk cache still serves
it instantly on the second read, and the `LruCache<String, Color>` above means it is read once per
URL per process anyway.

Compose side:

```kotlin
@Composable
fun rememberArtTint(url: String?): Color? {
    val palette = LocalPaletteCache.current
    return produceState<Color?>(initialValue = null, url) {
        value = palette.tintOrNull(url)
    }.value
}
```

`ArtAdaptiveGround` and `ArtBackdrop` then animate the `null → colour` handover with
`animateColorAsState(…, tween(220, FastOutSlowInEasing))` — `ThemeMotion.uiGentle` — which is what
kills the "black, then it becomes flush" jump the iOS note documents.

**One colour-space caveat.** Coil decodes through `BitmapFactory` on Android, which returns sRGB
unless `inPreferredColorSpace` is set — so the OKLab matrices above (which assume sRGB primaries)
are correct as written. If a future change routes decoding through `ImageDecoder` with wide-gamut
preservation, a Display-P3 poster would feed P3 values into an sRGB transform and the tint would
shift. Pin it: assert `bitmap.colorSpace == ColorSpace.get(ColorSpace.Named.SRGB)` in the palette
path, or convert first.

---

## 5. Blur, material, and the translucent bars

### 5.1 There are exactly three blurred surfaces, and only two of them need Haze

From `spec/chrome-images.md` §1.4:

| Surface | What it blurs | Android answer |
|---|---|---|
| **Chrome glass** — toast, `SyncBanner`, rewatch action bar | live content behind a pill | **Haze**, `CupertinoMaterials.ultraThin()` |
| **Scroll-edge bands** — the top/bottom veils on every screen | live scroll content under the bar | **Haze**, bare `HazeStyle` + our own veil and mask |
| **Composited-cover ground** — `LandscapeArt`, `ArtHeader`, `ArtBackdrop` | a bitmap | **§3** — baked into the bitmap, no Haze, no API branch |

### 5.2 The API-level gate (minSdk is 26, not 31)

`research/minsdk-decision.md` sets **minSdk 26** and requires one boolean, resolved once:

```kotlin
// ui/chrome/ChromeSurface.kt — the Android GlassHelpers.swift
val LocalCanUseMaterial = staticCompositionLocalOf { false }

fun canUseMaterial(reduceTransparency: Boolean): Boolean =
    Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !reduceTransparency
```

Evidence that 31 is the right line, quoted from the AndroidX source of `Modifier.blur`
(`compose/ui/ui/…/draw/Blur.kt`, androidx-main, fetched 2026-09-04):

> "Note this effect is only supported on Android 12 and above. Attempts to use this Modifier on
> older Android versions will be ignored."

**Silent, not an error** — which is precisely the trap `minsdk-decision.md` names. And Haze makes the
same cut, in source (`haze/src/androidMain/…/HazeEffectNode.android.kt`, tag 1.7.3):

```kotlin
val canUseRenderEffect = Build.VERSION.SDK_INT >= 31 &&
  drawScope.drawContext.canvas.nativeCanvas.isHardwareAccelerated
```

Haze *does* have a `RenderScriptBlurEffect` path below 31. **Do not use it.** Reasons: RenderScript
is deprecated (removed from the NDK; the Java API's behaviour varies by OEM), it blurs a fresh
capture on the CPU every frame, and — decisively — **the design already has a correct no-blur
answer**: under Reduce Transparency the material is dropped and `chromeBarOpacity` goes to **1.0**,
an opaque canvas bar. API 26–30 devices should take that branch, not a slow blur that looks like
neither. Set `blurEnabled = LocalCanUseMaterial.current` and the design's existing path does the
rest.

### 5.3 Why Haze 1.7.3 and not 2.0.0-beta02

| | `1.7.3` | `2.0.0-beta02` |
|---|---|---|
| Released | 27 Aug 2026 (`haze` metadata `lastUpdated 20260829083715`) | 27 Aug 2026 |
| Stability | **stable** | beta |
| Built against | Compose **1.12.0**, Kotlin stdlib 2.3.20 (POM) | Compose **1.12.0**, Kotlin stdlib 2.4.10 (POM) |
| minSdk / compileSdk | **23 / 37** (`build-logic/…/Versions.kt`) | 23 / 37 |
| `haze-materials` | **yes** — last version is 1.7.3 | **no** — the artifact does not exist on 2.x |
| API shape | `hazeEffect(state, style)` + `HazeEffectScope` properties directly | properties moved behind a `blurEffect { }` wrapper; `haze-blur` is a separate module |

Both work with our Compose 1.12.0 BOM. The decider is `haze-materials`: it contains
`CupertinoMaterials`, whose values are taken from **Apple's own published iOS 18 Figma file**, and
`CupertinoMaterials.ultraThin()` is therefore the closest thing that exists to a mechanical
translation of `.ultraThinMaterial`. Its dark branch (our app is dark-only, `containerColor` will be
`#09090B`, luminance < 0.5) resolves to:

```kotlin
HazeStyle(
  blurRadius = 24.dp,
  backgroundColor = <surface>,
  tints = listOf(
    HazeTint(Color(0xFF9C9C9C), blendMode = BlendMode.Overlay),
    HazeTint(Color(0x252525).copy(alpha = 0.55f)),
  ),
)
```

Losing that to gain a beta's refraction engine — which the app explicitly does **not** want, because
`spec/chrome-images.md` §7 risk #2 says "target the `.ultraThinMaterial` look, not the iOS 26 one" —
would be a bad trade. Revisit when 2.x is stable and `haze-materials` (or an equivalent) returns.

```kotlin
// gradle/libs.versions.toml
coil = "3.6.1"
haze = "1.7.3"

coil-compose        = { module = "io.coil-kt.coil3:coil-compose",        version.ref = "coil" }
coil-network-okhttp = { module = "io.coil-kt.coil3:coil-network-okhttp", version.ref = "coil" }
haze                = { module = "dev.chrisbanes.haze:haze",             version.ref = "haze" }
haze-materials      = { module = "dev.chrisbanes.haze:haze-materials",   version.ref = "haze" }
```

### 5.4 The glass pill (toast, SyncBanner)

```kotlin
@Composable
fun Modifier.chromeGlass(state: HazeState, shape: Shape): Modifier =
    if (LocalCanUseMaterial.current) {
        this
            .clip(shape)
            .hazeEffect(state, style = CupertinoMaterials.ultraThin(ThemeColor.canvas)) {
                noiseFactor = 0f      // .ultraThinMaterial has no grain; Haze defaults to 0.15
            }
    } else {
        // The Reduce-Transparency recipe, already designed and shipping on iOS.
        this
            .clip(shape)
            .background(ThemeColor.surfaceFloating)                       // #2A2D36
            .border(1.dp, ThemeColor.strokeStrong, shape)                 // white 20 %
    }
```

### 5.5 The scroll-edge band — mask, not progressive

The iOS construction is `Rectangle().fill(.ultraThinMaterial).mask(blurMask)` under a
`LinearGradient` canvas veil. That is a **constant-radius** material with an **alpha-masked result** —
not a variable-radius blur. Haze has both, and the cheap one is the correct one:

- `mask: Brush` — "+5 % (negligible)" in Haze's published benchmarks.
- `progressive: HazeProgressive` — "about 25 % more than non-progressive" on Android 33+, and it
  needs API 33 for the shader path (Compose's own KDoc for the spatially-varying blur says the same:
  "spatially-varying radii (gradients and custom shaders) require Android 13 (API 33) and above").

So: `mask`.

```kotlin
// ui/chrome/ScrollEdgeChrome.kt
@Composable
fun BoxScope.TopScrollEdgeChrome(
    state: HazeState,
    height: Dp,
    holdHeight: Dp,
    hard: Boolean,
) {
    val material = LocalCanUseMaterial.current
    val hold = (holdHeight / height).coerceIn(0f, 1f)          // iOS: a gradient STOP, not a length
    val bar = if (material) ThemeMetrics.chromeBarOpacity else 1f   // 0.74 vs opaque

    // The blur mask and the canvas veil MUST run out on the same ramp and reach zero
    // at the same place. "A mask that terminates while the veil is still at a third
    // leaves a visible seam straight across the screen."
    val maskBrush = remember(hold, hard) {
        if (hard) Brush.verticalGradient(
            0f to Color.Black,
            hold to Color.Black,
            (hold + (1f - hold) * 0.45f) to Color.Black.copy(alpha = 0.42f),
            1f to Color.Transparent,
        ) else Brush.verticalGradient(
            0f to Color.Black.copy(alpha = 0.60f),
            0.5f to Color.Black.copy(alpha = 0.30f),
            1f to Color.Transparent,
        )
    }
    val veilBrush = remember(hold, hard, bar) {
        if (hard) Brush.verticalGradient(
            0f to ThemeColor.chromeVeil.copy(alpha = bar),
            hold to ThemeColor.chromeVeil.copy(alpha = bar),
            (hold + (1f - hold) * 0.45f) to ThemeColor.chromeVeil.copy(alpha = bar * 0.45f),
            1f to Color.Transparent,
        ) else Brush.verticalGradient(
            0f to ThemeColor.chromeVeil.copy(alpha = 0.55f),
            0.5f to ThemeColor.chromeVeil.copy(alpha = 0.30f),
            1f to Color.Transparent,
        )
    }

    Box(
        Modifier
            .align(Alignment.TopCenter)
            .fillMaxWidth()
            .height(height)
            .then(
                if (material) Modifier.hazeEffect(state) {
                    blurRadius = 24.dp                 // CupertinoMaterials.ultraThin's radius
                    noiseFactor = 0f
                    tints = emptyList()                // we paint our own veil, above
                    backgroundColor = ThemeColor.canvas
                    mask = maskBrush
                    inputScale = HazeInputScale.Fixed(0.5f)   // see §6
                } else Modifier
            )
            .drawBehind { drawRect(veilBrush) }        // blur under, canvas veil over
            .clearAndSetSemantics { }
    )
}
```

The host screen marks its scroll content once:

```kotlin
val hazeState = rememberHazeState()
Box {
    LazyColumn(Modifier.hazeSource(hazeState)) { … }
    TopScrollEdgeChrome(hazeState, height = topChromeHeight, holdHeight = topHold, hard = topRaised)
    BottomScrollEdgeChrome(hazeState)
}
```

**One `hazeSource` per screen, on the scroll container. Never per item.** Two `hazeEffect`s (top
band, bottom band) plus the tab bar reading from that one source is the whole budget.

### 5.6 The API 31 quirk, and window blur

Two things an engineer will otherwise discover the hard way.

**Android 12.0 (API 31) exactly pays an extra invalidation.** From Haze 1.7.3's source:

```kotlin
/**
 * - API 31: Ideally this wouldn't be necessary, but its been seen that API 31 has a few issues
 *   with RenderNodes not automatically re-painting. We workaround it by manually invalidating.
 */
internal actual fun invalidateOnHazeAreaPreDraw(): Boolean = Build.VERSION.SDK_INT < 32
```

So the *cheapest* device that gets blur at all is also the one that redraws the haze area on every
pre-draw. Add an **API 31 AVD** to the QA matrix alongside the pre-31 one `minsdk-decision.md`
already asks for — a Pixel 4 on Android 12.0 is the realistic worst case for this app's chrome.

**Compose 1.12 added window blur, and it is not a substitute.** `DialogProperties` and
`PopupProperties` gained `blurBehindRadius` / `backgroundBlurRadius` / `scrimAlpha` / `windowShape`
(landed in the 1.13.0-alpha01 notes, 12 Aug 2026). Those map to `Window.setBackgroundBlurRadius` /
`WindowManager.LayoutParams.blurBehindRadius`, which are **cross-window** blur — a different, less
reliable facility: per AOSP, "some devices might not support cross-window blur due to GPU
limitations, and it can also be disabled at runtime during battery saving mode…", and apps are told
to "have two versions of the window background". It is worth using for the `VideoSheet`'s dim if you
want one, guarded by `WindowManager.isCrossWindowBlurEnabled` + `addCrossWindowBlurEnabledListener`.
It cannot draw a bar over a scrolling list.

**There is still no first-party in-window backdrop blur in Compose.** `Modifier.blur` blurs a
composable's *own* content. AndroidX main has an unreleased `BlurRadiusSpec` overload (its KDoc is
quoted in §5.5) but it is not in 1.12.0 stable and is not in the 1.13.0-alpha01 release notes —
treat it as not shipping. Haze remains the answer; re-check at each BOM bump.

---

## 6. Performance guidance for a scrolling list

Haze's own published benchmark, as *cost of Haze* (the delta it adds to frame duration):
**Scaffold +29 %, Images List +45 %, Credit Card +98 %**. `inputScale = 0.5` cuts the cost of Haze by
**5–20 %** (≈3–5 % of total frame duration). Masking **+5 %**. Progressive **+25 %**.

At 120 Hz the budget is 8.3 ms. A 4 ms frame becoming 5.8 ms is fine; a 6 ms frame becoming 8.7 ms
is a dropped frame. So the rules, in descending order of how much they matter:

1. **Bake every image blur (§3).** This is the biggest single win and it is free. A `Modifier.blur`
   inside a `LazyRow` item forces an offscreen buffer per item per frame — `graphicsLayer`'s docs
   note that "setting a `RenderEffect` … always renders content into an offscreen buffer regardless
   of the `CompositingStrategy` set." Do not put one in a list.
2. **One `hazeSource` per screen; at most three `hazeEffect`s.** Top band, bottom band, and whatever
   pill is on stage. Never a haze on a list item.
3. **`inputScale = HazeInputScale.Fixed(0.5f)` on the bands.** They are blurred past recognition by
   definition — the iOS spec's whole point is that a title under the bar must stop reading as a
   title. Half-resolution input is invisible there and is not obviously safe on the glass pill, where
   the content behind it is closer to legible; measure before applying it there.
4. **`mask`, never `progressive` (§5.5).** Cheaper and more faithful.
5. **Bucket every request and set `Precision.INEXACT` (§2.3).** Uncontrolled `size()` from
   constraints plus Coil's default `EXACT` gives you one decode per distinct on-screen width.
6. **`clearAndSetSemantics { }` on every art node.** Not perf, but an auto-generated "image" node on
   every poster in a grid is a TalkBack regression, and the semantics tree is walked on scroll.
7. **Never mount a veil at `alpha = 0`.** iOS's rule ("veils are mounted only while on") applies
   verbatim: a `hazeEffect` at zero alpha still captures and blurs.
8. **Keep scroll offset out of screen state.** The Compose equivalent of the iOS `ScrollOffset`
   lesson is to read `LazyListState` inside a `derivedStateOf` (or in a `Modifier.drawBehind`
   lambda), never in the screen's composable body — otherwise the whole screen recomposes at 120 Hz.

**Measure, don't estimate.** Add a Macrobenchmark module with `FrameTimingMetric` over a scripted
scroll of Today and Library, on (a) the API 36 emulator from `TOOLCHAIN.md`, (b) a physical API 31
device, (c) a physical mid-range device at minSdk. Run it before and after the chrome lands; the
Haze percentages above are a prior, not a result. Ship a Baseline Profile: Coil's decoders and
Haze's `RenderEffect` setup are both first-run JIT-heavy.

**Verify the emulator can actually blur** — `TOOLCHAIN.md` already confirms
`ro.surface_flinger.supports_background_blur = 1` and `disableBackgroundBlur = false` on
`PreviouslyQA_API36`, and mandates `-gpu host`. Both matter here: a software rasteriser will
misrepresent exactly the surfaces this note is about.

---

## 7. Rejected alternatives

| Rejected | Why |
|---|---|
| **Glide / Picasso / Fresco** | None is Compose-first; Glide's Compose integration has been experimental for years. Coil is Kotlin/coroutines-native, is what the Compose ecosystem has standardised on, and ships an `AsyncImagePainter` that already integrates with Compose's size resolution. |
| **A hand-rolled `NSCache`-equivalent** (the most literal port) | The iOS pipeline exists because `AsyncImage` had no decoded-image cache. Coil has one, plus disk caching, request coalescing, EXIF-aware downsampling and lifecycle-aware cancellation. Reimplementing it would be ~600 lines to arrive at a worse Coil. Port the *policies* (buckets, serve-larger, no-flash), not the mechanism. |
| **`SubcomposeAsyncImage`** | Coil's own docs: it "uses subcomposition… slower than regular composition" and is unsuitable for `LazyList`. Every art surface in this app is in a lazy container. Use `AsyncImage`. |
| **`rememberAsyncImagePainter` as the default** | Coil's docs: it "does not detect the size your image is loaded at on screen and always loads the image with its original dimensions." That is the opposite of the `maxPixel` discipline. Reserve it for the rare surface that must observe load state. |
| **`androidx.palette` / `material-color-utilities` / `kmpalette`** | §4.1 — all three return a *different colour* from iOS for the same poster, and all three still need the app's L/C clamps applied afterwards. |
| **`allowHardware(false)` globally, to share one decode with the palette** | Moves every poster's pixels into the Java heap and adds a GPU upload per draw. A separate 64 px palette request is far cheaper. |
| **`Modifier.blur` for the composited-cover grounds** | Silent no-op below API 31 (our minSdk is 26), offscreen buffer per element per frame, and unnecessary: the source is ≤160 px and static. §3. |
| **Haze's RenderScript path (API < 31)** | RenderScript is deprecated and OEM-variable; it blurs a fresh capture on the CPU every frame; and the design already has a *correct* no-blur answer (opaque canvas bar). §5.2. |
| **Haze 2.0.0-beta02** | Beta, and `haze-materials` — i.e. `CupertinoMaterials.ultraThin()`, Apple's own iOS 18 values — does not exist on the 2.x line. §5.3. |
| **`HazeProgressive` for the band ramp** | 5× the cost of `mask` for something iOS does not do: iOS masks a constant-radius material, it does not vary the radius. §5.5. |
| **`Cloudy` / `Imla` / `Kyant0` Backdrop (liquid glass)** | Cloudy is a pre-31 blur backport we do not want (§5.2); Imla is explicitly experimental (captures the Compose root into a `HardwareBuffer`); the liquid-glass libraries chase the iOS 26 look the app deliberately does **not** target. |
| **Compose 1.12 window blur (`DialogProperties.blurBehindRadius`) for the bars** | Cross-window blur, not in-window: unsupported on some GPUs and disabled at runtime in battery saver. Cannot draw a bar over a scrolling list anyway. §5.6. |
| **`SharedTransitionLayout` wired to Detail** | Out of scope here but worth restating: the iOS `.zoom` transition was tried and **retired** (3 Sep) for a documented reason. Do not reintroduce it on Android because the platform makes it easy. |

---

## 8. Implementation order

1. `:model` — `ArtPalette` (pure arithmetic) + a JVM test seeded with real posters and the iOS RGB
   triples. **Do this first**: it is the only piece that can silently drift from iOS forever.
2. `ImageBuckets` + the `ImageLoader` module + `ArtImage` + `SnapFitContentScale`. Ship the poster
   grids on it and confirm on a recycled `LazyVGrid` that there is no placeholder flash.
3. `BlurTransformation` + `LandscapeArt` + `ArtBackdrop`. Calibrate the radii against iOS captures
   (§9, Q1) before anything else is built on top of them.
4. `PaletteCache` + `rememberArtTint` + `ArtAdaptiveGround`. Verify the `null → colour` handover is
   a fade, not a step.
5. `ChromeSurface` / `LocalCanUseMaterial`, then Haze: the glass pill first (one surface, easy to
   judge), then the scroll-edge bands.
6. Macrobenchmark + Baseline Profile, on the three devices in §6.
7. Prefetching last — it is an optimisation, and its correctness depends on the buckets from step 2.

---

## 9. Open questions — these need a human

**Q1. Blur radii do not port as numbers. Who calibrates, and against what?**
SwiftUI's `.blur(radius:)` and Skia's Gaussian (behind `RenderEffect` / Haze) do not document the
same radius→sigma mapping, and this note's baked blur runs in *source pixels before* an upscale
where iOS's runs in *points after* one. Every radius in `spec/chrome-images.md` (28, 48, 56, and
Haze's 24 dp band) is therefore a starting point, not a value. **Proposal:** capture the same six
shows on both platforms with the launch-arg / intent-extra routes (`-openDetail` ↔ `am start -e`),
put them side by side, and let the design owner pick the Android numbers — then freeze them as
tokens. Budget half a day. This is the single largest fidelity risk in this note.

**Q2. Reduce Transparency has no Android setting. Whose toggle is it?**
`spec/chrome-images.md` risk #13 and `minsdk-decision.md` both need one boolean. Android has no
public equivalent. **Proposal:** an in-app Settings row next to the existing Haptics toggle, default
off, OR'd with `SDK_INT < 31`. Needs a product decision on copy and whether it also disables the
`ArtBackdrop` wash. Note this toggle is now *load-bearing on a fifth of devices*, not an
accessibility nicety.

**Q3. Memory-cache budget.** iOS pins 96 MB. `maxSizePercent(context, 0.25)` on a 192 MB heap is
48 MB — half. Is that enough for a Library grid at 3× density plus a 2048 px hero? **Needs
measurement**, not a guess: instrument `MemoryCache.size` / `maxSize` in a debug build during a
Library → Detail → Schedule walk. If it thrashes, the lever is `android:largeHeap` (discouraged) or
dropping the top ladder rung from 2048 to 1536 and accepting a slightly softer billboard.

**Q4. Is the 2048 ladder rung right at Android densities?** The iOS note says Today's billboard
draws its sharp layer at ~1770 px tall, so 1536 softened it. The QA emulator is 1280 × 2856 px at
480 dpi and **427 × 952 dp** — *wider and taller* than the 393 × 852 pt iPhone. Recompute the hero's
pixel height at 480 dpi before assuming the ladder transfers, and again for a 3× 1080 p phone.

**Q5. Haze 2.x timeline.** 2.0.0 has been in alpha/beta since April 2026. If it stabilises during the
port *and* ships a materials replacement, 1.7.3 → 2.x is a small, contained migration
(`blurEffect { }` wrapper). If it stabilises *without* one, we own the `CupertinoMaterials.ultraThin`
constants ourselves (they are 6 colours, listed in §5.3). Either is fine; someone should own
watching it.

**Q6. Does the art CDN need its own OkHttp client, or a shared one with a scoped interceptor?**
This note assumes a separate client (`@ArtHttpClient`) so no Clerk bearer token can reach
`s4.anilist.co` or `image.tmdb.org` and image traffic does not share the API's 17.6 s call budget.
Cross-check with `spec/networking-auth.md`'s owner — it is a one-line difference and a real
security boundary.

---

## 10. Sources

| Claim | Source | Date checked |
|---|---|---|
| Coil `3.6.1` is latest; 3.6.0 26 Aug 2026, 3.5.0 10 Jun 2026 (minSdk → 23), 3.4.0 24 Feb 2026 (concurrent request strategy), 3.3.0 background memory-cache limiting | https://coil-kt.github.io/coil/changelog/ · https://repo1.maven.org/maven2/io/coil-kt/coil3/coil-compose/maven-metadata.xml (`lastUpdated 20260901051123`) | 2026-09-04 |
| Coil 3.6.1 built against Compose 1.12.0 | `coil-compose-core-android-3.6.1.pom` | 2026-09-04 |
| `ImageLoader.Builder`: `memoryCache`/`diskCache`/`precision`; `SingletonImageLoader.Factory` | https://coil-kt.github.io/coil/image_loaders/ · Coil source `coil3/ImageLoader.kt` | 2026-09-04 |
| **`ImageRequest.Defaults.precision = Precision.EXACT`** | Coil source `coil3/request/ImageRequest.kt` line 229 | 2026-09-04 |
| Memory-cache key excludes size unless transformations are present; `INEXACT` accepts a cached image "the same size or larger" | Coil source `coil3/memory/MemoryCacheService.kt` | 2026-09-04 |
| Crossfade is skipped for `DataSource.MEMORY_CACHE` results | https://github.com/coil-kt/coil/issues/647 + changelog | 2026-09-04 |
| Coil 3 does **not** respect `Cache-Control` by default; `coil-network-cache-control` opts in | https://coil-kt.github.io/coil/network/ | 2026-09-04 |
| `SubcomposeAsyncImage` slower than composition; `rememberAsyncImagePainter` loads at original dimensions | https://coil-kt.github.io/coil/compose/ | 2026-09-04 |
| `Transformation` = `cacheKey` + `suspend transform(Bitmap, Size)`; key is added to the memory cache key | Coil source `coil3/transform/Transformation.kt` | 2026-09-04 |
| Palette recipe requires `allowHardware(false)` | https://github.com/coil-kt/coil/blob/main/docs/recipes.md | 2026-09-04 |
| **"only supported on Android 12 and above… will be ignored"**; `BlurredEdgeTreatment.Rectangle` clips (clamp) vs `Unbounded` (samples transparent black); spatially-varying radii need API 33 | AndroidX source `compose/ui/ui/src/commonMain/kotlin/androidx/compose/ui/draw/Blur.kt` (androidx-main) | 2026-09-04 |
| compose-ui **1.12.0** stable, 12 Aug 2026; `blurBehindRadius`/`backgroundBlurRadius`/`scrimAlpha`/`windowShape` on Dialog/Popup landed in **1.13.0-alpha01**; `BlurRadiusSpec` not in either release note | https://developer.android.com/jetpack/androidx/releases/compose-ui | 2026-09-04 |
| `RenderEffect` forces an offscreen buffer regardless of `CompositingStrategy` | https://developer.android.com/develop/ui/compose/graphics/draw/modifiers | 2026-09-04 |
| Cross-window blur may be unsupported by GPU / disabled in battery saver; use `addCrossWindowBlurEnabledListener` | https://source.android.com/docs/core/display/window-blurs | 2026-09-04 |
| Haze `1.7.3` stable / `2.0.0-beta02` beta; `haze-materials` stops at 1.7.3; `haze-blur` + `haze-glass` are 2.x-only | https://repo1.maven.org/maven2/dev/chrisbanes/haze/{haze,haze-materials,haze-blur,haze-glass}/maven-metadata.xml | 2026-09-04 |
| Haze 1.7.3 → Compose 1.12.0, Kotlin 2.3.20; 2.0.0-beta02 → Compose 1.12.0, Kotlin 2.4.10 | `haze-android-{1.7.3,2.0.0-beta02}.pom` | 2026-09-04 |
| Haze minSdk 23 / compileSdk 37 / targetSdk 36 | `gradle/build-logic/convention/…/Versions.kt` @ tag 1.7.3 | 2026-09-04 |
| **Haze uses `RenderEffect` when `SDK_INT >= 31 && canvas.isHardwareAccelerated`**, RenderScript below, scrim as last resort; extra pre-draw invalidation for `SDK_INT < 32` | `haze/src/androidMain/kotlin/dev/chrisbanes/haze/HazeEffectNode.android.kt` @ tag 1.7.3 | 2026-09-04 |
| `CupertinoMaterials.ultraThin()` values taken from Apple's published iOS 18 Figma; blurRadius 24.dp | `haze-materials/src/commonMain/…/CupertinoMaterials.kt` @ tag 1.7.3 | 2026-09-04 |
| `hazeSource`/`hazeEffect`, `HazeStyle(backgroundColor, tints, blurRadius, noiseFactor, fallbackTint)`, `HazeEffectScope(blurEnabled, inputScale, mask, progressive, alpha, …)`; masking is "a performance-conscious alternative to progressive blurs" | https://chrisbanes.github.io/haze/latest/usage/ · Haze source `HazeStyle.kt`, `HazeEffectNode.kt` | 2026-09-04 |
| Cost of Haze: Scaffold +29 %, Images List +45 %, Credit Card +98 %; `inputScale 0.5` −5–20 %; masking +5 %; progressive +25 % / "0 %" with the Android 34+ shader | https://chrisbanes.github.io/haze/latest/performance/ · usage page | 2026-09-04 |
| Haze 2.0 published 29 Apr 2026; `VisualEffect` interface, blur split into `haze-blur` | https://chrisbanes.me/posts/haze-2.0/ · https://raw.githubusercontent.com/chrisbanes/haze/main/CHANGELOG.md | 2026-09-04 |
| androidx.palette latest **1.1.0-alpha01**, 1 Jul 2026 (stable 1.0.0); `palette-ktx` merged in | https://developer.android.com/jetpack/androidx/releases/palette | 2026-09-04 |
| Maven Central **Solr search index is stale** (reports Coil 3.2.0 / Haze 1.5.3) — use `maven-metadata.xml` | https://search.maven.org/solrsearch/select | 2026-09-04 |

**In-repo:** `ios/Sources/DesignSystem/{ImageLoader,Palette,RemoteImageView,GlassHelpers}.swift` ·
`docs/android-port/spec/chrome-images.md` §§1.4, 2, 3, 4, 7 ·
`docs/android-port/research/{compose-architecture,minsdk-decision,toolchain}.md`
