package com.anitrack.app.design

import androidx.compose.material3.ColorScheme
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp

/**
 * **Previously.**'s theme. Not `MaterialTheme`, and never wrapped in one at the root.
 *
 * The app is dark-only, takes no dynamic colour, uses no Material typography and reads no Material
 * shape. Everything a screen draws composes from [ThemeColor], [ThemeSpace], [ThemeRadius],
 * [ThemeMetrics], [PosterSize], [ShadowToken] and [SurfaceLevel]; the namespaces are constants, so
 * a screen may reference them directly, and they are *also* published as composition locals here
 * so a future surface (a preview harness, a themed component gallery) can substitute one without
 * every call site changing.
 *
 * ```
 * setContent { PreviouslyTheme { RootView() } }
 * ```
 *
 * ### What is deliberately absent
 *
 * There is no `MaterialTheme(...)` around the app. material3 is pulled in only for a **closed** set
 * of behavioural components — a sheet, a dialog, an anchored popup, a bottom-bar chassis, a switch
 * — and each is wrapped so that no screen ever sees an M3 type. Those wrappers, and only those,
 * put [PreviouslyMaterialBridge] around themselves so the component inherits a colour scheme, a
 * shape scale and a type scale that belong to this app instead of `lightColorScheme()` and
 * Material's own Roboto ramp — which is what `MaterialTheme` with no `colorScheme` / `typography`
 * argument silently defaults to.
 */
object PreviouslyTheme {

    val colors: ThemeColor
        @Composable @ReadOnlyComposable get() = LocalThemeColors.current

    val space: ThemeSpace
        @Composable @ReadOnlyComposable get() = LocalThemeSpace.current

    val radius: ThemeRadius
        @Composable @ReadOnlyComposable get() = LocalThemeRadius.current

    val metrics: ThemeMetrics
        @Composable @ReadOnlyComposable get() = LocalThemeMetrics.current

    /** The ink a bare tappable word or glyph is drawn in here. See [LocalControlInk]. */
    val controlInk: Color
        @Composable @ReadOnlyComposable get() = LocalControlInk.current
}

/**
 * Installs the token layer. Put it once, at the root of `setContent`.
 *
 * It provides locals and nothing else — no window colours, no system-bar work (the activity owns
 * that: edge-to-edge, forced dark), no `MaterialTheme`. Three of the locals are not colour or
 * metric tokens but belong here because "once, at the root" is what they need:
 *
 * * **Reduce Motion** — resolved live from the platform setting and read by every animation.
 * * **The font-scale ceiling** — identity on a stock device, so Android 14's non-linear curve is
 *   preserved; it only clamps an OEM slider that has gone past the platform maximum.
 * * **The control ink** — see [LocalControlInk].
 *
 * ### The two inherited defaults
 *
 * `Text` (and every material3 component that draws a string or a glyph) resolves an omitted style
 * from `LocalTextStyle` and an omitted colour from `LocalContentColor`. Both of those locals have
 * Material defaults that are wrong here and wrong LOUDLY, because this app installs no
 * `MaterialTheme` at the root to correct them:
 *
 * * `LocalTextStyle` defaults to `TextStyle.Default` — the platform face at an unspecified size,
 *   i.e. Roboto. That is exactly the fallback iOS's root
 *   `.font(.custom("Outfit-Regular", size: 17, relativeTo: .body))` exists to prevent, so
 *   [ThemeType.appDefault] is installed here as its counterpart.
 * * `LocalContentColor` defaults to `Color.Black` — #000000 on the #09090B canvas, which is not a
 *   tint error but an invisible string. [ThemeColor.textPrimary] is the app's inherited ink.
 *
 * Neither is a licence to omit the style or the colour: a screen still names its type token and
 * its ink. These are the floor under a mistake, not the mechanism.
 */
@Composable
fun PreviouslyTheme(content: @Composable () -> Unit) {
    ProvideReduceMotion {
        CompositionLocalProvider(
            LocalThemeColors provides ThemeColor,
            LocalThemeSpace provides ThemeSpace,
            LocalThemeRadius provides ThemeRadius,
            LocalThemeMetrics provides ThemeMetrics,
            LocalControlInk provides ThemeColor.interactive,
            LocalTextStyle provides ThemeType.appDefault,
            LocalContentColor provides ThemeColor.textPrimary,
            LocalDensity provides AppTypeScale.ceiling(LocalDensity.current),
            content = content,
        )
    }
}

// MARK: - The token locals
//
// Static, because the values are compile-time constants: a static local costs nothing to read and
// nothing to provide, since nothing ever changes it. `LocalControlInk` is the one exception —
// it is re-provided down the tree, so it is a regular local and only its readers invalidate.

val LocalThemeColors = staticCompositionLocalOf { ThemeColor }
val LocalThemeSpace = staticCompositionLocalOf { ThemeSpace }
val LocalThemeRadius = staticCompositionLocalOf { ThemeRadius }
val LocalThemeMetrics = staticCompositionLocalOf { ThemeMetrics }

/**
 * **The ink of every bare interactive word or glyph** — "See all", "Read more", "Clear",
 * "Sync now", "Details", "Add", "Done".
 *
 * Amber is not an action colour (see [ThemeColor.interactive] for the whole rule and the bug
 * behind it), so this defaults to [ThemeColor.interactive] and is re-provided exactly twice:
 *
 * 1. **root** → `interactive`, so back chevrons, dialog buttons, a search field's Cancel and its
 *    caret are ink, not amber;
 * 2. **inside the bottom navigation bar** → `accent`, because a selected tab is STATE;
 * 3. **inside each tab's nav host** → `interactive` again, so everything pushed on that tab is
 *    back to ink.
 *
 * iOS gets this from three nested `.tint(...)` calls; Compose has no cascading tint, so the chain
 * is explicit. Use [ProvideControlInk] to re-provide it.
 *
 * **This governs app-drawn ink only.** A material3 component does not read composition locals for
 * its colours — it reads `MaterialTheme.colorScheme` — so every wrapped component passes its
 * colours explicitly at the wrapper. The two mechanisms are not interchangeable and a component
 * that inherits its colour from the scheme is a bug.
 */
val LocalControlInk = compositionLocalOf { ThemeColor.interactive }

/** Re-provide [LocalControlInk] for a subtree. */
@Composable
fun ProvideControlInk(ink: Color, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalControlInk provides ink, content = content)
}

// MARK: - The material3 bridge
//
// A defensive mapping, not a theme. It exists so that the handful of behavioural components this
// app borrows from material3 cannot arrive wearing Material's defaults.

/**
 * Every M3 colour role, mapped onto this app's palette.
 *
 * `MaterialTheme(...)` with no `colorScheme` defaults to **`lightColorScheme()`**, so an unmapped
 * role is not a subtle tint error in a dark-only app — it is a light-on-white tonal slab. This map
 * is therefore exhaustive over the roles the allowed components actually paint with.
 *
 * Two mappings are the whole point of the map and must not be "corrected":
 *
 * * **`primary` is [ThemeColor.interactive], never [ThemeColor.accent].** Material tints its
 *   controls with `primary` by default. Mapping amber there would hand every switch, selection
 *   ring and dialog button the one colour that is reserved for MEANING and STATE — precisely the
 *   collision the rule exists to end. A control whose value genuinely *is* state passes
 *   [ThemeColor.accent] explicitly at its wrapper.
 * * **`surfaceTint` and the `*Container` roles are transparent.** `surfaceTint` is what drives M3's
 *   tonal-elevation overlay, and `secondaryContainer` is the navigation bar's selected-item
 *   indicator pill; transparent is how neither draws at all.
 */
val PreviouslyColorScheme: ColorScheme = darkColorScheme(
    primary = ThemeColor.interactive,
    onPrimary = ThemeColor.canvas,
    primaryContainer = Color.Transparent,
    onPrimaryContainer = ThemeColor.textPrimary,
    inversePrimary = ThemeColor.interactive,

    secondary = ThemeColor.interactive,
    onSecondary = ThemeColor.canvas,
    secondaryContainer = Color.Transparent,
    onSecondaryContainer = ThemeColor.textPrimary,

    tertiary = ThemeColor.interactive,
    onTertiary = ThemeColor.canvas,
    tertiaryContainer = Color.Transparent,
    onTertiaryContainer = ThemeColor.textPrimary,

    background = ThemeColor.canvas,
    onBackground = ThemeColor.textPrimary,
    surface = ThemeColor.canvas,
    onSurface = ThemeColor.textPrimary,
    surfaceVariant = ThemeColor.surfaceFlat,
    onSurfaceVariant = ThemeColor.textSecondary,
    surfaceTint = Color.Transparent,

    inverseSurface = ThemeColor.surfaceFloating,
    inverseOnSurface = ThemeColor.textPrimary,

    error = ThemeColor.destructive,
    onError = ThemeColor.canvas,
    errorContainer = Color.Transparent,
    onErrorContainer = ThemeColor.destructive,

    outline = ThemeColor.stroke,
    outlineVariant = ThemeColor.separatorQuiet,

    // Material multiplies this role by its own 0.32 alpha before painting a modal scrim, so a
    // pre-alpha'd token here would land at ~18 %. The value is black; a wrapper that wants the
    // app's own `ThemeColor.scrim` passes it explicitly.
    scrim = Color.Black,

    surfaceBright = ThemeColor.surfaceRaised,
    surfaceDim = ThemeColor.canvas,
    surfaceContainerLowest = ThemeColor.surfaceFlat,
    surfaceContainerLow = ThemeColor.surfaceFlat,
    surfaceContainer = ThemeColor.surfaceRaised,
    surfaceContainerHigh = ThemeColor.surfaceRaised,
    surfaceContainerHighest = ThemeColor.surfaceFloating,
)

/**
 * M3's shape scale, mapped onto [ThemeRadius], so no borrowed sheet or dialog arrives with
 * Material's 28-dp `extraLarge` corner.
 *
 * These stay `RoundedCornerShape` rather than [ContinuousCornerShape]: `Shapes` is typed to
 * `CornerBasedShape`, and at these radii, on chrome the app does not draw itself, the arc/squircle
 * difference is not worth a wrapper.
 */
val PreviouslyShapes = Shapes(
    // Nothing in this app is rounded at 4; the role is mapped anyway so a borrowed component
    // cannot fall through to a Material corner nobody chose.
    extraSmall = RoundedCornerShape(4.dp),
    small = RoundedCornerShape(ThemeRadius.episodeStill),
    medium = RoundedCornerShape(ThemeRadius.compactControl),
    large = RoundedCornerShape(ThemeRadius.row),
    extraLarge = RoundedCornerShape(ThemeRadius.card),
)

/**
 * M3's type scale, mapped onto [ThemeType], so no borrowed component can draw a word in a face
 * this app does not own.
 *
 * A caller-supplied `Text(style = …)` is still the rule, but a borrowed component does not always
 * take the style as a parameter — several set their own internally out of `MaterialTheme.typography`
 * and offer no way to stop them: `AlertDialog`'s title and text (`headlineSmall` / `bodyMedium`),
 * `ModalBottomSheet`'s drag-handle affordances, `DropdownMenuItem` (`labelLarge`), `Snackbar`
 * (`bodyMedium`) and `NavigationBarItem`'s label (`labelMedium`). Left at Material's default those
 * are Roboto at Material's sizes, which is the same leak as an unmapped colour role — quieter, and
 * so more likely to ship.
 *
 * The mapping is by ROLE, not by size: a role is assigned the token this app would have used for
 * that job, which is why `labelMedium` — the navigation label — is [ThemeType.tabLabel] and
 * `labelLarge` — a dialog's confirm word — is [ThemeType.button]. The scale is exhaustive so a
 * component reaching for a role nobody anticipated still lands in the app's own voice.
 */
val PreviouslyTypography = Typography(
    displayLarge = ThemeType.displayXL,
    displayMedium = ThemeType.displayL,
    displaySmall = ThemeType.heroTitle,

    headlineLarge = ThemeType.displayL,
    headlineMedium = ThemeType.heroTitle,
    // An alert's title.
    headlineSmall = ThemeType.showTitleL,

    titleLarge = ThemeType.sectionTitle,
    titleMedium = ThemeType.rowTitle,
    titleSmall = ThemeType.cardFact,

    bodyLarge = ThemeType.body,
    // An alert's message and a snackbar's line — the app speaking, so Outfit at callout size.
    bodyMedium = ThemeType.callout,
    bodySmall = ThemeType.metadata,

    // A dialog button, a menu item.
    labelLarge = ThemeType.button,
    // A navigation-bar item's label.
    labelMedium = ThemeType.tabLabel,
    labelSmall = ThemeType.caption,
)

/**
 * Wrap **only** a borrowed material3 component — never a screen, and never the app root.
 *
 * `MaterialTheme` is used here as a colour/shape/type carrier for components that read
 * `MaterialTheme.colorScheme` and `MaterialTheme.typography` internally and offer no parameter to
 * stop them. Every string this app draws still names its own type token at the call site; the
 * scale passed here ([PreviouslyTypography]) is what a component picks up when it does not ask.
 */
@Composable
fun PreviouslyMaterialBridge(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = PreviouslyColorScheme,
        shapes = PreviouslyShapes,
        typography = PreviouslyTypography,
        content = content,
    )
}
