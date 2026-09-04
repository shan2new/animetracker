package com.anitrack.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.sqrt

/**
 * The palette extractor is the one piece of the art pipeline that can silently drift from iOS
 * forever: nothing crashes, nothing logs, the app just grows a different atmosphere on Android.
 * These pin it.
 *
 * The golden ARGB values below are the algorithm's own output for a uniform field of the named
 * colour, recorded when the port landed. **A change to any of them is a change to the app's ground
 * colour on every screen** — if one moves, it moves because someone decided it should, and the iOS
 * side moves with it.
 *
 * Every golden channel sits at least 0.10 away from a rounding boundary, so a floating-point
 * difference between two JVMs cannot flip one.
 */
class PaletteTest {

    private fun field(argb: Int, count: Int = ArtPalette.SAMPLE_EDGE * ArtPalette.SAMPLE_EDGE) =
        IntArray(count) { argb }

    private fun lightnessAndChroma(argb: Int): Pair<Double, Double> {
        val lab = ArtPalette.oklab(
            r = ((argb shr 16) and 0xFF) / 255.0,
            g = ((argb shr 8) and 0xFF) / 255.0,
            b = (argb and 0xFF) / 255.0,
        )
        return lab.l to sqrt(lab.a * lab.a + lab.b * lab.b)
    }

    // -----------------------------------------------------------------------------------------
    // Goldens
    // -----------------------------------------------------------------------------------------

    @Test
    fun `a mid blue resolves to its clamped self`() {
        assertEquals(0xFF285095.toInt(), ArtPalette.dominantTint(field(0xFF3F6FB5.toInt())))
    }

    @Test
    fun `pure red is pulled down in lightness and in chroma`() {
        // Pure red is OKLab L 0.628 / C 0.258 — far outside both windows, so this exercises both
        // ceilings at once.
        assertEquals(0xFF91280E.toInt(), ArtPalette.dominantTint(field(0xFFFF0000.toInt())))
    }

    @Test
    fun `a very dark colour is lifted to the lightness floor`() {
        assertEquals(0xFF37224C.toInt(), ArtPalette.dominantTint(field(0xFF1A0A33.toInt())))
    }

    @Test
    fun `a washed-out colour is lifted to the chroma floor`() {
        // Teal at C 0.066 is below the 0.075 floor: the ground has to read as a colour, not as a
        // slightly-off canvas.
        assertEquals(0xFF106053.toInt(), ArtPalette.dominantTint(field(0xFF2E6F6A.toInt())))
    }

    @Test
    fun `a pale colour is pulled down to the lightness ceiling`() {
        assertEquals(0xFF654F1B.toInt(), ArtPalette.dominantTint(field(0xFFE8D8B0.toInt())))
    }

    // -----------------------------------------------------------------------------------------
    // The candidate filter
    // -----------------------------------------------------------------------------------------

    @Test
    fun `neutral art has no tint`() {
        // Grey is below the chroma floor for a CANDIDATE (0.035), so nothing is nominated at all.
        assertNull(ArtPalette.dominantTintOrNull(field(0xFF808080.toInt())))
        assertEquals(ArtPalette.FALLBACK_ARGB, ArtPalette.dominantTint(field(0xFF808080.toInt())))
    }

    @Test
    fun `black and near-black art has no tint`() {
        // The letterbox, the shadow and the canvas showing through are not the show's colour.
        assertNull(ArtPalette.dominantTintOrNull(field(0xFF000000.toInt())))
        assertNull(ArtPalette.dominantTintOrNull(field(0xFF050505.toInt())))
    }

    @Test
    fun `near-white art has no tint`() {
        // The lockup, the snow and the blown highlight are not the show's colour either.
        assertNull(ArtPalette.dominantTintOrNull(field(0xFFFFFFFF.toInt())))
    }

    @Test
    fun `transparent pixels are not candidates`() {
        // A 60 %-opaque pixel is below the 0.8 alpha floor: whatever its colour, it is not the
        // artwork's.
        assertNull(ArtPalette.dominantTintOrNull(field(0x99FF0000.toInt())))
        // A 90 %-opaque one is.
        assertEquals(
            0xFF91280E.toInt(),
            ArtPalette.dominantTint(field(0xE6FF0000.toInt())),
        )
    }

    @Test
    fun `an empty sample has no tint`() {
        assertNull(ArtPalette.dominantTintOrNull(IntArray(0)))
        assertEquals(ArtPalette.FALLBACK_ARGB, ArtPalette.dominantTint(IntArray(0)))
    }

    // -----------------------------------------------------------------------------------------
    // Population and determinism
    // -----------------------------------------------------------------------------------------

    @Test
    fun `the most populous bucket wins`() {
        val pixels = IntArray(1024) { if (it < 700) 0xFFFF0000.toInt() else 0xFF3F6FB5.toInt() }
        assertEquals(0xFF91280E.toInt(), ArtPalette.dominantTint(pixels))
    }

    @Test
    fun `an exact tie resolves to the lower bucket key, every time`() {
        // Red keys to bucket 62, this blue to 22. Ties must not depend on iteration order, or a
        // show's ground colour would change between launches.
        val pixels = IntArray(1024) { if (it % 2 == 0) 0xFFFF0000.toInt() else 0xFF3F6FB5.toInt() }
        val first = ArtPalette.dominantTint(pixels)
        assertEquals(0xFF285095.toInt(), first)
        repeat(8) { assertEquals(first, ArtPalette.dominantTint(pixels.copyOf())) }
    }

    @Test
    fun `neutral pixels do not dilute the one colour present`() {
        // A poster that is mostly black bars with a small saturated crest still yields the crest.
        val pixels = IntArray(1024) { if (it < 990) 0xFF000000.toInt() else 0xFFFF0000.toInt() }
        assertEquals(0xFF91280E.toInt(), ArtPalette.dominantTint(pixels))
    }

    // -----------------------------------------------------------------------------------------
    // The invariants the clamps exist to guarantee
    // -----------------------------------------------------------------------------------------

    @Test
    fun `every resolved tint lands inside the lightness and chroma windows`() {
        val samples = intArrayOf(
            0xFFFF0000.toInt(), 0xFF00FF00.toInt(), 0xFF0000FF.toInt(),
            0xFFF0A24E.toInt(), 0xFF1A0A33.toInt(), 0xFF2E6F6A.toInt(),
            0xFFE8D8B0.toInt(), 0xFF3F6FB5.toInt(), 0xFF7B1E3A.toInt(),
            0xFF0F3D2E.toInt(), 0xFFFFC0CB.toInt(), 0xFF4B0082.toInt(),
        )
        for (sample in samples) {
            val label = Integer.toHexString(sample)
            val tint = ArtPalette.dominantTintOrNull(field(sample))
                ?: error("expected a tint for $label")
            val (l, c) = lightnessAndChroma(tint)
            // ±0.01 for the 8-bit quantisation the packed colour goes through.
            assertTrue("L $l out of window for $label", l in 0.29..0.45)
            assertTrue("C $c out of window for $label", c in 0.065..0.155)
        }
    }

    @Test
    fun `the hue leans toward brand amber but does not become it`() {
        val brand = ArtPalette.oklab(0xF0 / 255.0, 0xA2 / 255.0, 0x4E / 255.0)
        val brandHue = atan2(brand.b, brand.a)

        val sourceLab = ArtPalette.oklab(0.0, 0.0, 1.0)
        val sourceHue = atan2(sourceLab.b, sourceLab.a)

        val tint = ArtPalette.dominantTint(field(0xFF0000FF.toInt()))
        val resultLab = ArtPalette.oklab(
            r = ((tint shr 16) and 0xFF) / 255.0,
            g = ((tint shr 8) and 0xFF) / 255.0,
            b = (tint and 0xFF) / 255.0,
        )
        val resultHue = atan2(resultLab.b, resultLab.a)

        // Closer to amber than the source was, and still unmistakably blue: 15 % is a breath that
        // stops the app swinging olive or steel from tab to tab, not a wash that erases the show.
        assertTrue(angleBetween(resultHue, brandHue) < angleBetween(sourceHue, brandHue))
        assertTrue(angleBetween(resultHue, sourceHue) < Math.toRadians(20.0))
        assertNotEquals(brandHue, resultHue, 1e-3)
    }

    private fun angleBetween(a: Double, b: Double): Double {
        val raw = abs(a - b) % (2 * Math.PI)
        return if (raw > Math.PI) 2 * Math.PI - raw else raw
    }

    // -----------------------------------------------------------------------------------------
    // The colour-space arithmetic
    // -----------------------------------------------------------------------------------------

    @Test
    fun `sRGB round-trips through OKLab`() {
        val samples = listOf(
            Triple(0.0, 0.0, 0.0),
            Triple(1.0, 1.0, 1.0),
            Triple(0.5, 0.5, 0.5),
            Triple(0.94, 0.63, 0.31), // brand amber
            Triple(0.0, 0.0, 1.0),
            Triple(0.12, 0.44, 0.71),
        )
        for ((r, g, b) in samples) {
            val back = ArtPalette.srgb(ArtPalette.oklab(r, g, b))
            assertEquals(r, back.r, 1e-6)
            assertEquals(g, back.g, 1e-6)
            assertEquals(b, back.b, 1e-6)
        }
    }

    @Test
    fun `the fallback mirrors the design layer's neutral warm ground`() {
        // ArtGround.neutralWarm in :app carries the same literal and the two must not drift.
        assertEquals(0xFF1C1A17.toInt(), ArtPalette.FALLBACK_ARGB)
    }

    @Test
    fun `Rgb packs to opaque ARGB`() {
        assertEquals(0xFF000000.toInt(), Rgb(0.0, 0.0, 0.0).toArgb())
        assertEquals(0xFFFFFFFF.toInt(), Rgb(1.0, 1.0, 1.0).toArgb())
        assertEquals(0xFF804020.toInt(), Rgb(128 / 255.0, 64 / 255.0, 32 / 255.0).toArgb())
    }
}
