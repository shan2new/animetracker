/*
 * **The one home for "blur where available, opaque canvas otherwise".** The Android counterpart of
 * `ios/Sources/DesignSystem/GlassHelpers.swift`, and the file every material surface in the app
 * goes through.
 *
 * ## Why this file exists at all
 *
 * On iOS the rule is "never call an iOS 26 symbol from a screen — route it through the gated shim".
 * The Android rule is the same shape and rather more dangerous, because the failure is SILENT.
 * From AndroidX's own KDoc on `Modifier.blur`:
 *
 *   "Note this effect is only supported on Android 12 and above. Attempts to use this Modifier on
 *   older Android versions will be ignored."
 *
 * Ignored — not an error, not a warning, not a log line. Our floor is API 26
 * (`research/minsdk-decision.md`), so a naive `Modifier.blur` under a 74 %-canvas veil yields a
 * TRANSPARENT bar on a fifth of the install base: the one outcome the design forbids. Haze makes
 * the same cut in its own source (`canUseRenderEffect = SDK_INT >= 31 && …`), and its pre-31
 * RenderScript path is deliberately not used — RenderScript is deprecated, OEM-variable, and blurs
 * a fresh CPU capture every frame to arrive somewhere worse than the answer the design already has.
 *
 * Because there IS a designed answer. `ScrollEdgeChrome`'s veil has always carried a second branch:
 * under Reduce Transparency the material is dropped and the hardened bar goes to opaque canvas
 * (`ThemeMetrics.chromeBarOpacityOpaque`). Pre-31 devices take exactly that path. Nothing new needs
 * designing and no screen needs a second layout.
 *
 * ## One boolean, resolved once
 *
 *   canUseMaterial = SDK_INT >= 31 && !reduceTransparency
 *
 * "Device cannot blur" and "user asked for reduced transparency" are ONE state, not two conditions
 * that happen to render alike — two independent conditions producing the same visual drift apart.
 * It is resolved once by `ProvideChromeSurface` and read through `LocalCanUseMaterial` everywhere.
 *
 * ## What a screen may do
 *
 * A screen marks its scroll container with `chromeHazeSource` and mounts the chrome from
 * `ScrollEdgeChrome.kt`. It may call `chromeGlass` for a floating chrome pill. It may NOT branch on
 * `SDK_INT`, call `hazeEffect` or `Modifier.blur` itself, or invent a translucent scrim with
 * nothing softening under it — see `ChromeMaterial`.
 */
package com.anitrack.app.ui.chrome

import android.content.Context
import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.dp
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import dev.chrisbanes.haze.HazeInputScale
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeTint
import dev.chrisbanes.haze.hazeEffect
import dev.chrisbanes.haze.hazeSource
import dev.chrisbanes.haze.materials.CupertinoMaterials
import dev.chrisbanes.haze.materials.ExperimentalHazeMaterialsApi
import dev.chrisbanes.haze.rememberHazeState

// ---------------------------------------------------------------------------------------------
// The parity enum
// ---------------------------------------------------------------------------------------------

/**
 * Which edges a piece of scroll-edge chrome addresses.
 *
 * On iOS this enum is a hard compiler workaround: the `for:` parameter of `scrollEdgeEffectHidden`
 * takes an iOS 26 type, and a function signature naming one cannot compile against an iOS 18
 * deployment target even when every call sits inside an availability check — so the app declares
 * its own edge type and maps it in the bodies, where the symbol is legal.
 *
 * **That constraint has no Android analogue.** Kotlin has no equivalent of "a type that may not
 * appear in a signature below API N". The enum survives for call-site parity and because
 * [ScrollEdgeChromeBox] genuinely needs to say which edges it draws; the compiler reason is
 * history, not a rule.
 *
 * ### The four iOS shims with no Android counterpart
 *
 * Recorded here so nobody goes looking for them, or invents one:
 *
 * * `chromeScrollEdgeHidden(_:)` / `chromeScrollEdgeHard(_:)` — suppress and harden the *system*
 *   scroll-edge effect. Android draws no system scroll-edge effect, so there is nothing to
 *   suppress and nothing to harden. Every edge in this app is app-drawn either way.
 * * `chromeSharedBackgroundHidden()` — drops iOS 26's shared glass capsule from behind a bare
 *   toolbar word. A Compose toolbar action carries no capsule, so the defect it fixes (a lit plate
 *   drawn around something meant to read as text) cannot occur.
 * * `chromeTabBarMinimizeOnScroll()` — **dropped by decision (PLAN D10)**, not merely unavailable.
 *   It is already a no-op on the iOS 18 floor this port targets, and a hand-rolled
 *   `NestedScrollConnection` version is a different component with different physics. The
 *   navigation bar is static.
 */
enum class ChromeEdge {
    /** Both edges. The default for a tab root. */
    All,

    /** The status-bar edge only. */
    Top,

    /** The bottom-bar edge only — what a pushed screen gets, because the system owns its top. */
    Bottom,
}

// ---------------------------------------------------------------------------------------------
// The capability
// ---------------------------------------------------------------------------------------------

/** The first API level at which `RenderEffect` — and therefore any live blur — exists. */
private const val BLUR_API_FLOOR = Build.VERSION_CODES.S // 31

/**
 * **The one boolean.** True when the app may draw a live material; false when it must fall back to
 * the design's own opaque-canvas rendering.
 *
 * @param reduceTransparency the in-app Reduce-transparency toggle (PLAN D12). Android exposes no
 *   system setting for it — the closest thing, high-contrast text, means something else — so the
 *   app owns the preference, in Settings beside Haptics, defaulted off. That toggle is not an
 *   accessibility nicety here: it is OR'd with the API floor, and the branch it selects is
 *   load-bearing on every pre-31 device whether or not anyone ever touches it.
 */
fun chromeCanUseMaterial(reduceTransparency: Boolean): Boolean =
    Build.VERSION.SDK_INT >= BLUR_API_FLOOR && !reduceTransparency

/**
 * The in-app Reduce-transparency preference, so a settings row and the chrome agree on one value.
 *
 * Read [LocalCanUseMaterial] to decide a rendering; read this only to draw the toggle itself or to
 * answer a question that is genuinely about the *preference* rather than about the capability.
 */
val LocalReduceTransparency = staticCompositionLocalOf { false }

/**
 * Where that preference is kept.
 *
 * `SharedPreferences`, not DataStore, and for the reason `SyncCenter` gives: the read has to be
 * **synchronous**. The app root resolves the capability once, before the first frame, and a value
 * arriving one collection later would draw every bar with a live blur for a user who asked for
 * none — or, on a pre-31 device, would not matter at all, which is exactly the asymmetry that makes
 * a late answer hard to notice.
 *
 * The store is the settings file [HapticsPreference][com.anitrack.app.ui.profile] writes to, so the
 * two accessibility choices live together; the KEY is stated here, beside the boolean it feeds,
 * because this file is what decides what the preference means.
 */
object ReduceTransparencyPreference {

    private const val PREFS_NAME = "previously.settings"

    /** iOS names the same user choice under this key. */
    const val PREFERENCE_KEY: String = "previously.reduceTransparency"

    /** Default **off**: the app draws material wherever the device can. */
    fun current(context: Context): Boolean = prefs(context).getBoolean(PREFERENCE_KEY, false)

    fun set(context: Context, on: Boolean) {
        prefs(context).edit().putBoolean(PREFERENCE_KEY, on).apply()
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}

/**
 * [chromeCanUseMaterial], resolved once at the root.
 *
 * **The default is `false` on purpose.** An unprovided subtree renders the opaque bar, which is
 * merely flatter; the inverse default would render a transparent one, which is broken. It is also
 * consistent with [LocalChromeHazeState]'s fallback, which has no registered source and would blur
 * nothing at all.
 */
val LocalCanUseMaterial = staticCompositionLocalOf { false }

/**
 * The app's Haze state — the captured backdrop that every chrome material blurs.
 *
 * One state, registered on the scrolling content by [chromeHazeSource] and consumed by the two
 * scroll-edge bands and whatever glass pill is on stage. **One source per screen, on the scroll
 * container, never per item**; two bands plus one pill is the whole per-frame budget.
 *
 * A subtree that needs its own capture (a sheet with its own scrolling content, for instance)
 * provides a fresh one with [ProvideChromeHazeState].
 */
val LocalChromeHazeState = staticCompositionLocalOf { HazeState(initialBlurEnabled = false) }

/**
 * Install the chrome layer. Once, at the app root, inside `PreviouslyTheme`.
 *
 * @param reduceTransparency the in-app preference (PLAN D12), typically read from `Prefs`.
 */
@Composable
fun ProvideChromeSurface(
    reduceTransparency: Boolean,
    content: @Composable () -> Unit,
) {
    val material = chromeCanUseMaterial(reduceTransparency)
    // `blurEnabled` on the state is the belt to the braces: no `hazeEffect` is mounted at all when
    // the material is off, and the state itself also refuses to blur.
    val state = rememberHazeState(blurEnabled = material)
    CompositionLocalProvider(
        LocalReduceTransparency provides reduceTransparency,
        LocalCanUseMaterial provides material,
        LocalChromeHazeState provides state,
        content = content,
    )
}

/** Give a subtree its own backdrop capture — a sheet over the app, say. Rare. */
@Composable
fun ProvideChromeHazeState(
    state: HazeState = rememberHazeState(blurEnabled = LocalCanUseMaterial.current),
    content: @Composable () -> Unit,
) {
    CompositionLocalProvider(LocalChromeHazeState provides state, content = content)
}

// ---------------------------------------------------------------------------------------------
// The material tokens
// ---------------------------------------------------------------------------------------------

/**
 * The numbers the material itself is made of. Not literals at a call site: the two surfaces that
 * blur live content both spend these, and they are the values a design review re-tunes.
 */
object ChromeMaterial {

    /**
     * The band blur's radius — `CupertinoMaterials.ultraThin`'s own, so the two blurred surfaces
     * agree.
     *
     * Re-tuned by eye rather than converted: SwiftUI's `.blur(radius:)` and Skia's Gaussian (which
     * is what `RenderEffect`, and therefore Haze, drives) do not document the same relationship
     * between a radius and a sigma, so an iOS number carried across arithmetically means nothing.
     * This is the value that reads like `.ultraThinMaterial` on Android.
     */
    val blurRadius = 24.dp

    /**
     * `.ultraThinMaterial` has no grain. Haze defaults to 0.15, which over near-black canvas reads
     * as dither noise crawling under the bar.
     */
    const val noiseFactor: Float = 0f

    /**
     * Half-resolution input for the **bands only**.
     *
     * The bands are blurred past recognition by definition — the whole point of the hardened bar is
     * that a row title under it stops reading as a row title — so halving the input costs nothing
     * anyone can see and takes a measurable slice off the cost of Haze. It is *not* applied to
     * [chromeGlass], where the content behind the pill is closer to legible; measure before
     * spending it there.
     */
    const val bandInputScale: Float = 0.5f

    /** The Reduce-Transparency pill's ring — `strokeStrong`, 20 % white, all the way round. */
    val fallbackStrokeWidth = ThemeMetrics.hairline
}

// ---------------------------------------------------------------------------------------------
// The two sanctioned entry points
// ---------------------------------------------------------------------------------------------

/**
 * Mark this composable's content as the backdrop the chrome blurs. Put it on the screen's **scroll
 * container**, once.
 *
 * A no-op when the material is off: capturing the scroll content into a graphics layer is real work
 * every frame, and with no material to consume it the capture buys nothing.
 *
 * @param zIndex orders overlapping sources; leave at 0 unless two captures genuinely stack.
 * @param key identifies this area, so a chrome effect can filter which sources it draws. Only
 *   needed where more than one source can be on screen at once.
 */
@Composable
fun Modifier.chromeHazeSource(zIndex: Float = 0f, key: Any? = null): Modifier {
    if (!LocalCanUseMaterial.current) return this
    return hazeSource(LocalChromeHazeState.current, zIndex, key)
}

/**
 * The band material: a constant-radius blur of the captured backdrop, masked by [blurMask].
 *
 * **`mask`, never `progressive`.** iOS does not vary its blur radius — it fills a rectangle with a
 * constant-radius material and *masks the result* — so the mask is both the faithful port and the
 * cheap one (Haze's own benchmarks: a mask costs about +5 %, a progressive blur about +25 %, and
 * the spatially-varying shader path needs API 33 anyway).
 *
 * The caller paints its canvas veil **over** this, which is what the modifier order below achieves:
 * an outer draw modifier draws first and then calls through to the inner one.
 *
 * `internal`, because the only legal callers are the bands in `ScrollEdgeChrome.kt`.
 */
@Composable
internal fun Modifier.chromeBandMaterial(blurMask: Brush): Modifier {
    if (!LocalCanUseMaterial.current) return this
    val state = LocalChromeHazeState.current
    return hazeEffect(state) {
        blurRadius = ChromeMaterial.blurRadius
        noiseFactor = ChromeMaterial.noiseFactor
        // We paint our own canvas veil over the top; a Haze tint here would be a second, uncalled-
        // for one. The band's colour is entirely `ScrollEdgeChrome`'s business.
        tints = emptyList()
        backgroundColor = ThemeColor.canvas
        mask = blurMask
        inputScale = HazeInputScale.Fixed(ChromeMaterial.bandInputScale)
        // Haze falls back to a flat scrim if it finds itself on a non-hardware-accelerated canvas
        // even at API 31+. Opaque canvas is the app's own answer to "no material", so the fallback
        // lands on the same rendering the pre-31 branch draws rather than on a grey plate.
        fallbackTint = HazeTint(ThemeColor.chromeVeil)
    }
}

/**
 * **The one sanctioned entry to glass.** Three call sites, all chrome, never content: the toast,
 * the sync banner, and the rewatch sheet's bottom action bar.
 *
 * Glass belongs to navigation and functional chrome only — never stacked on a poster or a content
 * card. (`GlassCircleButton`, `glassTinted`, `GlassGroup` and the two glass button styles were
 * deleted in the 30 Aug cohesion pass with zero call sites each. Do not re-introduce equivalents.)
 *
 * | [LocalCanUseMaterial] | rendering |
 * |---|---|
 * | `true` | Apple's own published iOS 18 `.ultraThinMaterial` values, blurring the live backdrop |
 * | `false` | opaque `surfaceFloating` (#2A2D36) with a 1-dp 20 %-white ring, no refraction |
 *
 * The fallback is not a degradation — it is the recipe the iOS app already ships under Reduce
 * Transparency, designed and reviewed.
 *
 * Applies no shadow and no hairline: `ToastView` and `SyncBanner` own those, exactly as on iOS
 * where `chromeGlass` is a background and the caller adds `ShadowToken.Floating`.
 *
 * @param shape the pill. Both branches clip to it, so the caller does not clip again.
 */
@OptIn(ExperimentalHazeMaterialsApi::class)
@Composable
fun Modifier.chromeGlass(shape: Shape): Modifier {
    if (!LocalCanUseMaterial.current) {
        return clip(shape)
            .background(ThemeColor.surfaceFloating)
            .border(ChromeMaterial.fallbackStrokeWidth, ThemeColor.strokeStrong, shape)
    }
    val state = LocalChromeHazeState.current
    // `CupertinoMaterials`' values are transcribed from the iOS 18 Figma file Apple publishes, so
    // this is the closest thing that exists to a mechanical translation of `.ultraThinMaterial`.
    // Passing the canvas as the container colour is what selects its dark branch (luminance < 0.5).
    val style = CupertinoMaterials.ultraThin(ThemeColor.canvas)
    return clip(shape).hazeEffect(state, style) {
        // NOT redundant, and NOT removable. `CupertinoMaterials` sets its own `backgroundColor`
        // from `MaterialTheme.colorScheme.surface`, and this app has no `MaterialTheme` at its root
        // by design — so that read falls through to Compose's `lightColorScheme()` default and the
        // pill would be backed by a near-white surface. A scope property outranks the style's, so
        // this line is what keeps the glass dark.
        backgroundColor = ThemeColor.canvas
        noiseFactor = ChromeMaterial.noiseFactor
        fallbackTint = HazeTint(ThemeColor.surfaceFloating)
    }
}
