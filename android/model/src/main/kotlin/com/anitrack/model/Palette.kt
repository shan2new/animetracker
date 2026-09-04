package com.anitrack.model

import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cbrt
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * # The art-adaptive tint
 *
 * A direct port of `PaletteCache.dominantTint` in `ios/Sources/DesignSystem/Palette.swift`. It is
 * the one colour the whole app's atmosphere is built from: the Focus / Recap card ground, the
 * billboard's pre-art fill, and the ambient wash behind every root screen.
 *
 * The pipeline, unchanged from iOS:
 *
 * ```
 * downsample to 32×32 → skip alpha < 0.8, OKLab L < 0.08 or > 0.92, chroma < 0.035
 *   → bucket by 12 hue bins × 4 lightness bins, weighted by population
 *   → average the winning bucket
 *   → clamp L to 0.30…0.44 and chroma to 0.075…0.145, lean the hue 15 % toward brand amber
 * ```
 *
 * ### Why this is a port and not a library call
 *
 * `androidx.palette` quantises in **HSL** and scores by population × saturation against its own
 * target profiles; `material-color-utilities` answers a different question entirely (a tonal
 * palette for theming). Both return a *different colour from iOS for the same poster* — usually
 * greyer — and both would still need the clamps below applied afterwards, at which point the
 * library did nothing. The app's ground colour drifting between platforms for the same show is not
 * a rendering difference anyone could defend, and this is ~80 lines of arithmetic.
 *
 * The extractor is **not** returning the poster's colour. It returns a *derived* colour guaranteed
 * dark enough that `textPrimary` (#F4F1EC) clears 12:1 on the composite, and warm enough that the
 * app does not swing olive or steel from tab to tab. That is what the clamps are for, and they
 * carry a measured regression behind them — see [clampLightness].
 *
 * ### Where it runs
 *
 * Pure arithmetic over an `IntArray` of ARGB pixels, so it lives in `:model` and is unit-testable
 * on the JVM in milliseconds. The Android side is two calls — scale a decoded bitmap to
 * [SAMPLE_EDGE] and `getPixels` — and lives in `ui/image/ImageLoader.kt` beside the loader whose
 * bytes it borrows.
 */
public object ArtPalette {

    /**
     * The edge of the square the artwork is sampled into. 32 × 32 = 1024 pixels is enough for a
     * population histogram and small enough that the whole extraction is free.
     */
    public const val SAMPLE_EDGE: Int = 32

    /**
     * "Neutral warm surface" — the ground when the art is entirely neutral, entirely black or
     * entirely blown out, and the value every caller's own fallback is measured against.
     *
     * Mirrored by `ArtGround.neutralWarm` in the design layer (`:app` cannot see `:model`'s colour
     * types and `:model` cannot see Compose's). **The two must not drift.**
     */
    // Not `const`: an opaque ARGB value does not fit in a positive `Int` literal, and `.toInt()`
    // on the unsigned form is not a compile-time constant expression.
    public val FALLBACK_ARGB: Int = 0xFF1C1A17.toInt()

    /**
     * Brand amber — `ThemeColor.accent`, repeated here because `:model` is a pure-JVM module and
     * cannot import the design layer. If the brand hue ever moves, it moves in both places.
     */
    private const val BRAND_AMBER_RGB: Int = 0xF0A24E

    // -----------------------------------------------------------------------------------------
    // The clamps
    //
    // These four numbers are a documented regression fix, and re-deriving them by taste undoes a
    // measurement. The previous set (L 0.24…0.38, C 0.035…0.075, 35 % brand blend) made
    // "art-derived colour" arithmetically present and perceptually absent — measured against the
    // baseline at (1200, 300):
    //
    //   Library  new rgb(36,30,27) vs original rgb(45,32,22) — 20 % dimmer, R−B falling 23 → 9
    //   Schedule new rgb(32,32,29) vs original rgb(71,64,59) — less than half the luminance,
    //                                                          R−B 12 → 3
    //
    // i.e. neutral charcoal where the baseline had warm ember. The chroma ceiling doubles, the
    // lightness floor rises, and the brand blend drops to a breath that stops the app swinging
    // olive or steel from tab to tab without erasing the show's own hue.
    // -----------------------------------------------------------------------------------------

    private const val LIGHTNESS_MIN = 0.30
    private const val LIGHTNESS_MAX = 0.44
    private const val CHROMA_MIN = 0.075
    private const val CHROMA_MAX = 0.145

    /** How far the winning hue leans toward [BRAND_AMBER_RGB]. A breath, not a wash. */
    private const val BRAND_BLEND = 0.15

    // -----------------------------------------------------------------------------------------
    // The candidate filter
    // -----------------------------------------------------------------------------------------

    /** Below this a pixel is transparent enough that its colour is not the artwork's. */
    private const val ALPHA_FLOOR = 0.8

    /** Near-black is not a tint; it is the letterbox, the shadow or the canvas showing through. */
    private const val CANDIDATE_LIGHTNESS_MIN = 0.08

    /** Near-white is not a tint either; it is the lockup, the snow or the blown highlight. */
    private const val CANDIDATE_LIGHTNESS_MAX = 0.92

    /** Below this a pixel is grey, and a grey ground is the canvas with extra steps. */
    private const val CANDIDATE_CHROMA_MIN = 0.035

    /** Hue bins. 12 × 30° is coarse enough that one costume reads as one colour. */
    private const val HUE_BINS = 12

    /** Lightness bins, so a show's bright key art and its shadows do not average into mud. */
    private const val LIGHTNESS_BINS = 4

    /**
     * Bucket keys are `hueBin * 10 + lightnessBin`. `hue` is `atan2(b, a)` ∈ (−π, π], so a pixel
     * sitting exactly on π lands in a thirteenth hue bin — harmless, and preserved rather than
     * clamped away because iOS computes the identical key.
     */
    private const val BUCKET_SLOTS = (HUE_BINS + 1) * 10

    // -----------------------------------------------------------------------------------------
    // Extraction
    // -----------------------------------------------------------------------------------------

    /**
     * The dominant tint of [pixels], or [FALLBACK_ARGB] when the artwork offers no usable colour.
     *
     * @param pixels ARGB_8888 pixels, as `Bitmap.getPixels` produces them — **non-premultiplied**.
     *   iOS reads a `premultipliedLast` CGContext instead, which differs only for pixels at
     *   0.8 ≤ α < 1.0; every fully-opaque pixel (which is all of a poster) is identical.
     *   The array should be the artwork scaled to [SAMPLE_EDGE] square, but nothing here depends
     *   on the length.
     */
    public fun dominantTint(pixels: IntArray): Int = dominantTintOrNull(pixels) ?: FALLBACK_ARGB

    /**
     * [dominantTint], but `null` rather than [FALLBACK_ARGB] when the artwork is entirely neutral.
     *
     * The distinction matters to a caller with a *branded* fallback on stage (the ambient wash's
     * ember, a hero's palette ground): replacing that with a neutral colour indistinguishable from
     * the canvas is the "black, then it becomes flush" jump, not a fix for it.
     */
    public fun dominantTintOrNull(pixels: IntArray): Int? {
        // Flat accumulators rather than a HashMap: the key space is a fixed 130 slots and the loop
        // runs over every pixel, so boxing a key and hashing it per pixel buys nothing. iOS's
        // dictionary and these arrays hold the same numbers under the same keys.
        val sumL = DoubleArray(BUCKET_SLOTS)
        val sumA = DoubleArray(BUCKET_SLOTS)
        val sumB = DoubleArray(BUCKET_SLOTS)
        val counts = IntArray(BUCKET_SLOTS)

        for (pixel in pixels) {
            val alpha = ((pixel ushr 24) and 0xFF) / 255.0
            if (alpha < ALPHA_FLOOR) continue

            val lab = oklab(
                r = ((pixel ushr 16) and 0xFF) / 255.0,
                g = ((pixel ushr 8) and 0xFF) / 255.0,
                b = (pixel and 0xFF) / 255.0,
            )
            if (lab.l < CANDIDATE_LIGHTNESS_MIN || lab.l > CANDIDATE_LIGHTNESS_MAX) continue

            val chroma = sqrt(lab.a * lab.a + lab.b * lab.b)
            if (chroma < CANDIDATE_CHROMA_MIN) continue

            val hue = atan2(lab.b, lab.a)
            val key = ((hue + PI) / (2 * PI) * HUE_BINS).toInt() * 10 +
                (lab.l * LIGHTNESS_BINS).toInt()
            if (key !in 0 until BUCKET_SLOTS) continue

            sumL[key] += lab.l
            sumA[key] += lab.a
            sumB[key] += lab.b
            counts[key]++
        }

        // Ascending scan with a strict `>`, so an exact population tie always resolves to the same
        // bucket. iOS breaks such a tie on dictionary iteration order, which is stable within a
        // launch and arbitrary between them; a poster whose ground colour changed on relaunch would
        // be a bug on either platform.
        var best = -1
        for (key in 0 until BUCKET_SLOTS) if (counts[key] > (if (best < 0) 0 else counts[best])) best = key
        if (best < 0 || counts[best] == 0) return null

        val n = counts[best].toDouble()
        val averaged = OkLab(sumL[best] / n, sumA[best] / n, sumB[best] / n)
        return srgbArgb(brandLeaned(clampLightness(averaged)))
    }

    /**
     * Clamps lightness into [LIGHTNESS_MIN]…[LIGHTNESS_MAX] — the window in which the ground is
     * dark enough for `textPrimary` and light enough to read as a colour rather than as the canvas.
     */
    private fun clampLightness(lab: OkLab): OkLab =
        OkLab(min(max(lab.l, LIGHTNESS_MIN), LIGHTNESS_MAX), lab.a, lab.b)

    /**
     * Clamps chroma and leans the hue [BRAND_BLEND] toward brand amber, renormalising to the
     * clamped chroma so the blend changes the *direction* of the colour and never its saturation.
     *
     * A fully neutral input (chroma exactly 0) is left alone: there is no hue to lean, and forcing
     * one would paint brand amber under a black-and-white show.
     */
    private fun brandLeaned(lab: OkLab): OkLab {
        val chroma = sqrt(lab.a * lab.a + lab.b * lab.b)
        if (chroma <= 0.0) return lab
        val target = min(max(chroma, CHROMA_MIN), CHROMA_MAX)

        val brand = oklab(
            r = ((BRAND_AMBER_RGB shr 16) and 0xFF) / 255.0,
            g = ((BRAND_AMBER_RGB shr 8) and 0xFF) / 255.0,
            b = (BRAND_AMBER_RGB and 0xFF) / 255.0,
        )
        val brandNorm = sqrt(brand.a * brand.a + brand.b * brand.b)

        var ua = lab.a / chroma
        var ub = lab.b / chroma
        ua = (1 - BRAND_BLEND) * ua + BRAND_BLEND * (brand.a / brandNorm)
        ub = (1 - BRAND_BLEND) * ub + BRAND_BLEND * (brand.b / brandNorm)

        val unitNorm = sqrt(ua * ua + ub * ub)
        return OkLab(lab.l, ua / unitNorm * target, ub / unitNorm * target)
    }

    // -----------------------------------------------------------------------------------------
    // sRGB ↔ OKLab (Björn Ottosson's matrices)
    // -----------------------------------------------------------------------------------------

    /** sRGB transfer function, inverse. */
    private fun lin(v: Double): Double =
        if (v <= 0.04045) v / 12.92 else ((v + 0.055) / 1.055).pow(2.4)

    /** sRGB transfer function. */
    private fun gam(v: Double): Double =
        if (v <= 0.0031308) 12.92 * v else 1.055 * v.pow(1 / 2.4) - 0.055

    /**
     * sRGB (0…1 per channel, gamma-encoded) → OKLab.
     *
     * The matrices assume **sRGB primaries**. Android decodes through `BitmapFactory`, which
     * returns sRGB unless `inPreferredColorSpace` says otherwise — so feeding a Display-P3 bitmap
     * in here without converting first would silently shift every tint. The Android wrapper draws
     * into an sRGB bitmap for exactly that reason.
     */
    public fun oklab(r: Double, g: Double, b: Double): OkLab {
        val rl = lin(r)
        val gl = lin(g)
        val bl = lin(b)
        val lCube = cbrt(0.4122214708 * rl + 0.5363325363 * gl + 0.0514459929 * bl)
        val mCube = cbrt(0.2119034982 * rl + 0.6806995451 * gl + 0.1073969566 * bl)
        val sCube = cbrt(0.0883024619 * rl + 0.2817188376 * gl + 0.6299787005 * bl)
        return OkLab(
            l = 0.2104542553 * lCube + 0.7936177850 * mCube - 0.0040720468 * sCube,
            a = 1.9779984951 * lCube - 2.4285922050 * mCube + 0.4505937099 * sCube,
            b = 0.0259040371 * lCube + 0.7827717662 * mCube - 0.8086757660 * sCube,
        )
    }

    /** OKLab → sRGB, each channel gamma-encoded and clamped to 0…1. */
    public fun srgb(lab: OkLab): Rgb {
        val lCube = lab.l + 0.3963377774 * lab.a + 0.2158037573 * lab.b
        val mCube = lab.l - 0.1055613458 * lab.a - 0.0638541728 * lab.b
        val sCube = lab.l - 0.0894841775 * lab.a - 1.2914855480 * lab.b
        val l = lCube * lCube * lCube
        val m = mCube * mCube * mCube
        val s = sCube * sCube * sCube
        return Rgb(
            r = clamp01(gam(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s)),
            g = clamp01(gam(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s)),
            b = clamp01(gam(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)),
        )
    }

    /** [srgb], packed as an opaque ARGB int — the form the Android side hands to `Color(…)`. */
    public fun srgbArgb(lab: OkLab): Int = srgb(lab).toArgb()

    private fun clamp01(v: Double): Double = min(max(v, 0.0), 1.0)
}

/** A colour in OKLab: perceptual lightness plus the two opponent axes. */
public data class OkLab(val l: Double, val a: Double, val b: Double)

/** A colour in sRGB, one `Double` in 0…1 per channel. */
public data class Rgb(val r: Double, val g: Double, val b: Double) {

    /** Packed as an opaque 8-bit-per-channel ARGB int. */
    public fun toArgb(): Int =
        (0xFF shl 24) or
            ((r * 255.0).roundToInt().coerceIn(0, 255) shl 16) or
            ((g * 255.0).roundToInt().coerceIn(0, 255) shl 8) or
            (b * 255.0).roundToInt().coerceIn(0, 255)
}
