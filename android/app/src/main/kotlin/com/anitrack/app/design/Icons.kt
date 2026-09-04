package com.anitrack.app.design

import androidx.annotation.DrawableRes
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathBuilder
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.res.vectorResource
import androidx.compose.ui.unit.dp
import com.anitrack.app.R

/*
 * The app's whole icon vocabulary, in one file.
 *
 * Two halves, because the app draws icons from two sources:
 *
 *  1. THE FOUR TAB ICONS are the app's own artwork (`icon/navbar/vector/Tab*.svg`, Hugeicons
 *     line set). They are ported here as `ImageVector` builders rather than vendored as
 *     VectorDrawable XML, because the source SVGs use `viewBox="-3 -3 30 30"` — a NEGATIVE
 *     viewport origin, which neither VectorDrawable nor `ImageVector` supports. Every path is
 *     translated by +3,+3 and drawn into a 30×30 viewport; see `TAB_VIEWPORT` below.
 *
 *  2. EVERY OTHER GLYPH is a Material Symbol, vendored as committed VectorDrawable XML from
 *     `google/material-design-icons`. This file declares the 42-row substitution table from
 *     `docs/android-port/spec/icon-mapping.md` as data — the Material name, the FILL/wght axes,
 *     the RTL mirroring, and the meaning that must survive the substitution — so that the
 *     vendoring pass is mechanical and every screen names an icon by one stable Kotlin symbol.
 *
 * NOT here, deliberately:
 *  - `androidx.compose.material:material-icons-extended`. Frozen at 1.7.8, unpublished since
 *    Compose 1.8, wrong optical family (Filled/Outlined, GRAD 0), and ~2,000 `ImageVector`
 *    initialisers dragged in for 40-odd icons. PLAN §3.3 bans it.
 *  - An icon FONT. Same ban, same section.
 *  - Any colour. Tab tinting is runtime state (ink in a nav host, amber for the selected tab),
 *    so colour is supplied at the call site from `LocalControlInk`, never baked in here.
 */

// ─────────────────────────────────────────────────────────────────────────────
// 1. The four tab icons
// ─────────────────────────────────────────────────────────────────────────────

/**
 * The source artwork is 24 units of ink inside a 30-unit box (`viewBox="-3 -3 30 30"`): the
 * 3-unit bleed is the tab-bar padding baked into the asset. Android keeps the whole 30-unit box
 * as the viewport and the paths shift by +3,+3 into it.
 */
private const val TAB_VIEWPORT = 30f

/**
 * 24 dp, per `spec/icon-mapping.md` — NOT 30 dp, and this is a re-tune, not a slip.
 *
 * A 24-dp box over a 30-unit viewport draws 19.2 dp of ink, where iOS draws 24 pt of ink (the
 * asset is a 30-pt template PNG). F1 ("1 pt = 1 dp, no rescaling") would argue for a 30-dp box —
 * but the fifth tab is not this artwork: Discover uses the Material Symbol `search`, whose ink
 * fills ~20/24 of its own box. At a 24-dp box the four custom tabs (19.2 dp of ink) and `search`
 * (~20 dp of ink) read as one set; at 30 dp they would be 24 dp of ink beside a 20-dp magnifier,
 * and the odd one out would be the tab that is not ours. Per the fidelity line, the number is
 * re-tuned so the row READS the same, not so it measures the same.
 *
 * If a call site needs a different size it passes `Modifier.size(...)`. It must never re-crop the
 * viewport to get bigger ink — that would delete the 3-unit optical padding the artwork is drawn
 * around.
 */
private val TabIconBox = 24.dp

/** `stroke-width="1.5"` on every path in all four SVGs. */
private const val TAB_STROKE_WIDTH = 1.5f

/**
 * White, not black: the vector is tinted by a `ColorFilter` at the call site (`Icon(tint = …)`),
 * so the baked colour never survives — except when someone reaches for `Image()` instead, where a
 * black glyph on this app's #09090B canvas is invisible and a white one is an obvious mistake.
 * Same reasoning as the `fillColor` normalisation in the Material Symbols vendoring recipe.
 */
private val TabInk = Color.White

/**
 * Round caps and joins on every path.
 *
 * The source SVGs are inconsistent — `TabToday`'s card declares only `stroke-linecap`,
 * `TabLibrary`'s three rules and both card outlines declare only `stroke-linejoin` — so a literal
 * port would ship three cap treatments across four icons. Round everywhere is safe because the
 * artwork is drawn so that every open end lands underneath another 1.5-wide stroke: `TabLibrary`'s
 * shelf line ends inside the card's own border, its two diagonals end inside the card's top edge
 * and inside the shelf line, `TabSchedule`'s rule ends inside the card border. A round cap extends
 * 0.75 units past the endpoint and is masked in all of them. Joins are moot on the card outlines —
 * every corner there is tangent-continuous.
 */
private inline fun ImageVector.Builder.strokedPath(
    crossinline block: PathBuilder.() -> Unit,
): ImageVector.Builder = path(
    fill = null,
    stroke = SolidColor(TabInk),
    strokeLineWidth = TAB_STROKE_WIDTH,
    strokeLineCap = StrokeCap.Round,
    strokeLineJoin = StrokeJoin.Round,
) { block() }

private fun tabVector(name: String, paths: ImageVector.Builder.() -> Unit): ImageVector {
    val builder = ImageVector.Builder(
        name = name,
        defaultWidth = TabIconBox,
        defaultHeight = TabIconBox,
        viewportWidth = TAB_VIEWPORT,
        viewportHeight = TAB_VIEWPORT,
    )
    builder.paths()
    return builder.build()
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. The Material Symbols substitution table, as data
// ─────────────────────────────────────────────────────────────────────────────

/**
 * One row of `docs/android-port/spec/icon-mapping.md`, carrying everything the vendoring pass
 * needs and the one thing a reviewer needs: what the glyph has to keep saying.
 *
 * The axes are not decoration. **Rounded** optical family (SF's default face is rounded-terminal
 * geometric; Material Symbols Outlined reads colder against Outfit), **opsz 24**, **GRAD −25**
 * (Google's own prescription for light-on-dark, which is every icon in this dark-only app),
 * `wght` 500 where the iOS call site draws `.medium`/`.semibold` and 400 where it draws
 * `.regular`, `FILL 1` where the SF name ends in `.fill`.
 *
 * @param sf the SF Symbol this replaces, so the table can be diffed against the iOS source.
 * @param symbol the Material Symbols Rounded name.
 * @param fill the FILL axis, 0 or 1. SF's `.fill` suffix is an axis here, not a different glyph.
 * @param weight the wght axis.
 * @param autoMirrored whether the vendored XML carries `android:autoMirrored="true"`. SF mirrors
 *   directional glyphs under RTL by itself; Material does not, so it is opt-in per file.
 * @param meaning what the substitution must preserve. A visually closer glyph that changes this
 *   is the wrong pick.
 * @param resId the vendored drawable, wired by the vendoring pass. `0` until then — see
 *   [rememberSymbol].
 */
@Immutable
data class MaterialSymbol(
    val sf: String,
    val symbol: String,
    val fill: Int = 0,
    val weight: Int = 400,
    val autoMirrored: Boolean = false,
    val meaning: String,
    @DrawableRes val resId: Int = 0,
) {
    /**
     * The resource this vendors to.
     *
     * **The axes are part of the name, because they are part of the file.** `notifications` is
     * vendored twice — outline at wght 500 for Profile's row, FILL 1 at wght 400 for the committed
     * reminder on a Schedule card — and so is `check_circle`. A bare `ic_$symbol` would have
     * collided, and one of each pair would have silently drawn the other's glyph: an outline bell
     * where amber STATE was meant, which is precisely the distinction `PreviouslyIcons` exists to
     * keep. `gradN25` is not encoded because GRAD −25 is unconditional in this dark-only app (and
     * a capital `N` is not a legal resource name); the default weight and FILL 0 are omitted the
     * same way the upstream filename omits them.
     */
    val drawableName: String
        get() = buildString {
            append("ic_").append(symbol)
            if (weight != 400) append("_w").append(weight)
            if (fill == 1) append("_fill")
        }

    /**
     * The exact file this was pulled from in `google/material-design-icons`:
     * `symbols/web/<symbol>/materialsymbolsrounded/<symbol><variant>_24px.svg`.
     * The 400 weight is the axis default and is omitted from the filename; 500 is spelled out.
     *
     * **SVG, not XML.** The repository ships VectorDrawable XML only under the legacy `android/`
     * tree, which has no Symbols and no axes; the Symbols live under `symbols/web` as SVG. The
     * conversion is the one in each vendored file's header — path data copied verbatim, the
     * negative viewBox origin absorbed by a translated `<group>`.
     */
    val variantSuffix: String
        get() = buildString {
            append('_')
            if (weight != 400) append("wght$weight")
            append("gradN25")
            if (fill == 1) append("fill1")
        }

    val sourceFileName: String get() = "$symbol${variantSuffix}_24px.svg"
}

/**
 * Resolves a vendored symbol to its `ImageVector`.
 *
 * ```
 * Icon(
 *     imageVector = rememberSymbol(PreviouslyIcons.ChevronRight),
 *     contentDescription = null,          // decorative; the row carries the label
 *     tint = LocalControlInk.current,
 *     modifier = Modifier.size(18.dp),    // glyph size, separate from the 48-dp target
 * )
 * ```
 *
 * Fails loudly rather than drawing nothing: an unwired icon is a vendoring gap, and a silently
 * blank 18-dp box on a state screen is exactly the kind of defect that survives to beta.
 */
@Composable
fun rememberSymbol(symbol: MaterialSymbol): ImageVector {
    check(symbol.resId != 0) {
        "Material Symbol '${symbol.symbol}' (for SF '${symbol.sf}') has no vendored drawable. " +
            "Fetch ${symbol.sourceFileName} from google/material-design-icons into " +
            "res/drawable/${symbol.drawableName}.xml and set resId on PreviouslyIcons."
    }
    return ImageVector.vectorResource(symbol.resId)
}

/**
 * The app's icon vocabulary. Every glyph the app draws is named here; a screen that reaches for a
 * glyph not on this list is either a spec gap or an improvisation, and both should be argued
 * before they are drawn.
 */
object PreviouslyIcons {

    // ── Tab bar ──────────────────────────────────────────────────────────────
    // Four of the five tabs are app artwork; the fifth (Discover) is [Search] — *"It said 'Add' —
    // a tab named for one of the things you can do on it, under a magnifier glyph."*

    private var _tabToday: ImageVector? = null

    /**
     * Today — a card with a tick above it. `icon/navbar/vector/TabToday.svg`, translated +3,+3.
     */
    val TabToday: ImageVector
        get() = _tabToday ?: tabVector("TabToday") {
            // The card. A squircle drawn as eight tangent-continuous cubics; the flat runs on the
            // top and bottom edges are `H` segments in the source and stay `horizontalLineTo` here.
            strokedPath {
                moveTo(5f, 17f)
                curveTo(5f, 13.2288f, 5f, 11.34315f, 6.17157f, 10.17157f)
                curveTo(7.34315f, 9f, 9.22876f, 9f, 13f, 9f)
                horizontalLineTo(17f)
                curveTo(20.7712f, 9f, 22.6569f, 9f, 23.8284f, 10.17157f)
                curveTo(25f, 11.34315f, 25f, 13.2288f, 25f, 17f)
                curveTo(25f, 20.7712f, 25f, 22.6569f, 23.8284f, 23.8284f)
                curveTo(22.6569f, 25f, 20.7712f, 25f, 17f, 25f)
                horizontalLineTo(13f)
                curveTo(9.22876f, 25f, 7.34315f, 25f, 6.17157f, 23.8284f)
                curveTo(5f, 22.6569f, 5f, 20.7712f, 5f, 17f)
                close()
            }
            // The tick, sitting above the card and breaking its top edge.
            strokedPath {
                moveTo(12f, 6f)
                lineTo(15f, 9f)
                lineTo(19f, 5f)
            }
        }.also { _tabToday = it }

    private var _tabSchedule: ImageVector? = null

    /**
     * Schedule — a calendar: two hangers, a card, a head rule, and five day dots.
     * `icon/navbar/vector/TabSchedule.svg`, translated +3,+3.
     */
    val TabSchedule: ImageVector
        get() = _tabSchedule ?: tabVector("TabSchedule") {
            // The two hangers, above the card and passing through its top edge.
            strokedPath {
                moveTo(19f, 5f)
                verticalLineTo(9f)
                moveTo(11f, 5f)
                verticalLineTo(9f)
            }
            // The card.
            strokedPath {
                moveTo(16f, 7f)
                horizontalLineTo(14f)
                curveTo(10.22876f, 7f, 8.34315f, 7f, 7.17157f, 8.17157f)
                curveTo(6f, 9.34315f, 6f, 11.22876f, 6f, 15f)
                verticalLineTo(17f)
                curveTo(6f, 20.7712f, 6f, 22.6569f, 7.17157f, 23.8284f)
                curveTo(8.34315f, 25f, 10.22876f, 25f, 14f, 25f)
                horizontalLineTo(16f)
                curveTo(19.7712f, 25f, 21.6569f, 25f, 22.8284f, 23.8284f)
                curveTo(24f, 22.6569f, 24f, 20.7712f, 24f, 17f)
                verticalLineTo(15f)
                curveTo(24f, 11.22876f, 24f, 9.34315f, 22.8284f, 8.17157f)
                curveTo(21.6569f, 7f, 19.7712f, 7f, 16f, 7f)
                close()
            }
            // The rule under the calendar's head.
            strokedPath {
                moveTo(6f, 13f)
                horizontalLineTo(24f)
            }
            // Five day dots — at (10.5,17) (15,17) (19.5,17) (10.5,21) (15,21). The sixth cell,
            // (19.5,21), is empty in the source artwork; that asymmetry is the drawing, not a
            // transcription slip, and it is what keeps the mark from reading as a plain grid.
            //
            // Each dot is drawn twice in the source, exactly as ported: a 0.125-long horizontal
            // segment (a round cap turns it into a 1.5-wide blob) with a 0.25-radius circle
            // stroked on top of it. Neither alone gives the dot its weight.
            strokedPath {
                moveTo(15.1258f, 17f)
                horizontalLineTo(15.0008f)
                moveTo(15.1258f, 21f)
                horizontalLineTo(15.0008f)
                moveTo(10.625f, 17f)
                horizontalLineTo(10.5f)
                moveTo(10.625f, 21f)
                horizontalLineTo(10.5f)
                moveTo(19.625f, 17f)
                horizontalLineTo(19.5f)

                moveTo(15.2508f, 17f)
                curveTo(15.2508f, 17.1381f, 15.1389f, 17.25f, 15.0008f, 17.25f)
                curveTo(14.8628f, 17.25f, 14.7508f, 17.1381f, 14.7508f, 17f)
                curveTo(14.7508f, 16.8619f, 14.8628f, 16.75f, 15.0008f, 16.75f)
                curveTo(15.1389f, 16.75f, 15.2508f, 16.8619f, 15.2508f, 17f)
                close()

                moveTo(15.2508f, 21f)
                curveTo(15.2508f, 21.1381f, 15.1389f, 21.25f, 15.0008f, 21.25f)
                curveTo(14.8628f, 21.25f, 14.7508f, 21.1381f, 14.7508f, 21f)
                curveTo(14.7508f, 20.8619f, 14.8628f, 20.75f, 15.0008f, 20.75f)
                curveTo(15.1389f, 20.75f, 15.2508f, 20.8619f, 15.2508f, 21f)
                close()

                moveTo(10.75f, 17f)
                curveTo(10.75f, 17.1381f, 10.63807f, 17.25f, 10.5f, 17.25f)
                curveTo(10.36193f, 17.25f, 10.25f, 17.1381f, 10.25f, 17f)
                curveTo(10.25f, 16.8619f, 10.36193f, 16.75f, 10.5f, 16.75f)
                curveTo(10.63807f, 16.75f, 10.75f, 16.8619f, 10.75f, 17f)
                close()

                moveTo(10.75f, 21f)
                curveTo(10.75f, 21.1381f, 10.63807f, 21.25f, 10.5f, 21.25f)
                curveTo(10.36193f, 21.25f, 10.25f, 21.1381f, 10.25f, 21f)
                curveTo(10.25f, 20.8619f, 10.36193f, 20.75f, 10.5f, 20.75f)
                curveTo(10.63807f, 20.75f, 10.75f, 20.8619f, 10.75f, 21f)
                close()

                moveTo(19.75f, 17f)
                curveTo(19.75f, 17.1381f, 19.6381f, 17.25f, 19.5f, 17.25f)
                curveTo(19.3619f, 17.25f, 19.25f, 17.1381f, 19.25f, 17f)
                curveTo(19.25f, 16.8619f, 19.3619f, 16.75f, 19.5f, 16.75f)
                curveTo(19.6381f, 16.75f, 19.75f, 16.8619f, 19.75f, 17f)
                close()
            }
        }.also { _tabSchedule = it }

    private var _tabLibrary: ImageVector? = null

    /**
     * Library — a film-can lid: a shelf rule, two diagonal spines, the card, and a play triangle.
     * `icon/navbar/vector/TabLibrary.svg`, translated +3,+3.
     */
    val TabLibrary: ImageVector
        get() = _tabLibrary ?: tabVector("TabLibrary") {
            // The shelf rule across the card, under the two diagonals.
            strokedPath {
                moveTo(5.50012f, 10.5f)
                horizontalLineTo(24.5001f)
            }
            // The two diagonal spines. The 0.0001 offsets are the source artwork's own — kept so
            // that a future diff against the SVG is empty rather than "close enough".
            strokedPath {
                moveTo(20.0001f, 5.5f)
                lineTo(17.0001f, 10.5f)
            }
            strokedPath {
                moveTo(13.0001f, 5.5f)
                lineTo(10.00012f, 10.5f)
            }
            // The card. Note the geometry differs from TabToday's: this squircle is 19 units
            // across (2.5…21.5 in source space) where Today's is 20, so the two are NOT
            // interchangeable paths even though they read as the same shape.
            strokedPath {
                moveTo(5.5f, 15f)
                curveTo(5.5f, 10.52166f, 5.5f, 8.28249f, 6.89124f, 6.89124f)
                curveTo(8.28249f, 5.5f, 10.52166f, 5.5f, 15f, 5.5f)
                curveTo(19.4783f, 5.5f, 21.7175f, 5.5f, 23.1088f, 6.89124f)
                curveTo(24.5f, 8.28249f, 24.5f, 10.52166f, 24.5f, 15f)
                curveTo(24.5f, 19.4783f, 24.5f, 21.7175f, 23.1088f, 23.1088f)
                curveTo(21.7175f, 24.5f, 19.4783f, 24.5f, 15f, 24.5f)
                curveTo(10.52166f, 24.5f, 8.28249f, 24.5f, 6.89124f, 23.1088f)
                curveTo(5.5f, 21.7175f, 5.5f, 19.4783f, 5.5f, 15f)
                close()
            }
            // The play triangle, drawn as a rounded-corner wedge rather than three straight lines.
            strokedPath {
                moveTo(17.9531f, 17.8948f)
                curveTo(17.8016f, 18.5215f, 17.0857f, 18.9644f, 15.6539f, 19.8502f)
                curveTo(14.2697f, 20.7064f, 13.5777f, 21.1346f, 13.0199f, 20.9625f)
                curveTo(12.78934f, 20.8913f, 12.57925f, 20.7562f, 12.40982f, 20.57f)
                curveTo(12f, 20.1198f, 12f, 19.2465f, 12f, 17.5f)
                curveTo(12f, 15.7535f, 12f, 14.8802f, 12.40982f, 14.4299f)
                curveTo(12.57925f, 14.2438f, 12.78934f, 14.1087f, 13.0199f, 14.0375f)
                curveTo(13.5777f, 13.8654f, 14.2697f, 14.2936f, 15.6539f, 15.1498f)
                curveTo(17.0857f, 16.0356f, 17.8016f, 16.4785f, 17.9531f, 17.1052f)
                curveTo(18.0156f, 17.3639f, 18.0156f, 17.6361f, 17.9531f, 17.8948f)
                close()
            }
        }.also { _tabLibrary = it }

    private var _tabAdd: ImageVector? = null

    /**
     * The `TabAdd` artwork — a card with a plus. Retained because it is committed artwork, but
     * **the Discover tab does not use it**: the tab is named "Search" under a magnifier
     * ([Search]), because a tab named for one of the things you can do on it was the wrong
     * promise. `icon/navbar/vector/TabAdd.svg`, translated +3,+3.
     */
    val TabAdd: ImageVector
        get() = _tabAdd ?: tabVector("TabAdd") {
            // Same card as TabLibrary's, to the digit.
            strokedPath {
                moveTo(5.5f, 15f)
                curveTo(5.5f, 10.52166f, 5.5f, 8.28249f, 6.89124f, 6.89124f)
                curveTo(8.28249f, 5.5f, 10.52166f, 5.5f, 15f, 5.5f)
                curveTo(19.4783f, 5.5f, 21.7175f, 5.5f, 23.1088f, 6.89124f)
                curveTo(24.5f, 8.28249f, 24.5f, 10.52166f, 24.5f, 15f)
                curveTo(24.5f, 19.4783f, 24.5f, 21.7175f, 23.1088f, 23.1088f)
                curveTo(21.7175f, 24.5f, 19.4783f, 24.5f, 15f, 24.5f)
                curveTo(10.52166f, 24.5f, 8.28249f, 24.5f, 6.89124f, 23.1088f)
                curveTo(5.5f, 21.7175f, 5.5f, 19.4783f, 5.5f, 15f)
                close()
            }
            strokedPath {
                moveTo(15f, 11f)
                verticalLineTo(19f)
                moveTo(19f, 15f)
                horizontalLineTo(11f)
            }
        }.also { _tabAdd = it }

    // ── Material Symbols, in the order of spec/icon-mapping.md ───────────────

    /** 1. Rewatch / restart. NOT `refresh` — that reads as reload. */
    val Sync = MaterialSymbol(
        sf = "arrow.triangle.2.circlepath", symbol = "sync", weight = 400,
        meaning = "Rewatch / restart, and StaleStrip's freshness mark. Never 'reload'.",
        resId = R.drawable.ic_sync,
    )

    /**
     * 2. Discover's recent-term row: "put this query back in the field".
     *
     * Was `north_west` (SF's own diagonal) and then `arrow_outward`; settled as `open_in_new` by
     * D29 — the Android reflex for "this leaves where you are", the same reasoning that made the
     * share glyph Material's `share`.
     */
    val RecentQuery = MaterialSymbol(
        sf = "arrow.up.backward", symbol = "open_in_new", weight = 500,
        meaning = "Lift this recent search back into the field.",
        resId = R.drawable.ic_open_in_new_w500,
    )

    /** 3. External link — a trailer provider, JustWatch. D29: `open_in_new`, not `arrow_outward`. */
    val OpenInNew = MaterialSymbol(
        sf = "arrow.up.right", symbol = "open_in_new", weight = 500,
        meaning = "Leaves the app.",
        resId = R.drawable.ic_open_in_new_w500,
    )

    /** 4. Reminder, unset. Profile's Notifications row, drawn at `.medium`. */
    val Notifications = MaterialSymbol(
        sf = "bell", symbol = "notifications", weight = 500,
        meaning = "Episode alerts. Unset — outline, never amber.",
        resId = R.drawable.ic_notifications_w500,
    )

    /** 5. Reminder set. Material's badge is motion lines where SF has a dot — accepted. */
    val NotificationsActive = MaterialSymbol(
        sf = "bell.badge", symbol = "notifications_active", weight = 400,
        meaning = "Alerts are on / the permission primer.",
        resId = R.drawable.ic_notifications_active,
    )

    /** 6. Reminder committed. Amber STATE — the one legal amber glyph on the Schedule card. */
    val NotificationsFilled = MaterialSymbol(
        sf = "bell.fill", symbol = "notifications", fill = 1, weight = 400,
        meaning = "Reminder committed for this episode. Amber = STATE, not an action.",
        resId = R.drawable.ic_notifications_fill,
    )

    /** 7. Planned / saved. Library's planned-shelf empty state. */
    val Bookmark = MaterialSymbol(
        sf = "bookmark", symbol = "bookmark", weight = 400,
        meaning = "Planned / saved for later.",
        resId = R.drawable.ic_bookmark,
    )

    /** 8. Schedule's empty state. `event` is an acceptable alternative. */
    val CalendarMonth = MaterialSymbol(
        sf = "calendar", symbol = "calendar_month", weight = 400,
        meaning = "The airing calendar.",
        resId = R.drawable.ic_calendar_month,
    )

    /**
     * 9. The bare tick. `MarkRing`'s settled watched state, and the episode row's watched mark.
     *
     * **Never `check_circle`** — the ring is drawn by the app; the glyph is only the tick. A filled
     * disc at tertiary grey reads as a disabled control, which is the "grey tick glyphs" complaint
     * exactly.
     */
    val Check = MaterialSymbol(
        sf = "checkmark", symbol = "check", weight = 500,
        meaning = "Watched. A finished thing is a tick, not the word 'Watched'.",
        resId = R.drawable.ic_check_w500,
    )

    /** 10. "Everything synced" — Profile's settled state. */
    val CheckCircleFilled = MaterialSymbol(
        sf = "checkmark.circle.fill", symbol = "check_circle", fill = 1, weight = 400,
        meaning = "Everything synced / caught up.",
        resId = R.drawable.ic_check_circle_fill,
    )

    /**
     * 11. Disclosure. `keyboard_arrow_down`, not `expand_more`: same outline on a different grid,
     * and it will not line up in a row of chevrons at small sizes.
     */
    val KeyboardArrowDown = MaterialSymbol(
        sf = "chevron.down", symbol = "keyboard_arrow_down", weight = 500,
        meaning = "Disclosure / more below.",
        resId = R.drawable.ic_keyboard_arrow_down_w500,
    )

    /** 12. Row and section-header navigation — the most-drawn glyph in the app. Mirrors in RTL. */
    val ChevronRight = MaterialSymbol(
        sf = "chevron.forward", symbol = "chevron_right", weight = 500, autoMirrored = true,
        meaning = "This pushes a screen. A fixed 11-dp column in MediaRow; never spoken.",
        resId = R.drawable.ic_chevron_right_w500,
    )

    /**
     * 13. The season picker and Library's sort. Load-bearing: it must stay visually distinct from
     * [ChevronRight] — menu-in-place versus push.
     */
    val UnfoldMore = MaterialSymbol(
        sf = "chevron.up.chevron.down", symbol = "unfold_more", weight = 500,
        meaning = "Choose in place (season picker, sort). Not a push.",
        resId = R.drawable.ic_unfold_more_w500,
    )

    /** 14. Watch history, and Today's "Previously" recap line. `restore` is the same glyph. */
    val History = MaterialSymbol(
        sf = "clock.arrow.circlepath", symbol = "history", weight = 500,
        meaning = "What you watched before.",
        resId = R.drawable.ic_history_w500,
    )

    /** 15. Debug / JSON row in Profile. */
    val DataObject = MaterialSymbol(
        sf = "curlybraces", symbol = "data_object", weight = 500,
        meaning = "Raw JSON, for the debug rows.",
        resId = R.drawable.ic_data_object_w500,
    )

    /** 16. Export / legal document. */
    val Description = MaterialSymbol(
        sf = "doc.text", symbol = "description", weight = 500,
        meaning = "A document — terms, export.",
        resId = R.drawable.ic_description_w500,
    )

    /**
     * 17. ⚠ "Live / airing now" — the Now Bar's meaning.
     *
     * `sensors` is a centre dot with arcs radiating both ways, which is close. `podcasts` is
     * visually nearer and means audio, so it is wrong. The deeper problem is the surface: on iOS
     * this glyph lives in the Live Activity, which Android answers with a notification — where it
     * becomes the small icon and must be a white-on-transparent single-colour 24-dp drawable.
     */
    val Sensors = MaterialSymbol(
        sf = "dot.radiowaves.left.and.right", symbol = "sensors", weight = 400,
        meaning = "Airing now / live.",
        resId = R.drawable.ic_sensors,
    )

    /** 18. Overflow menu. Exact match. */
    val MoreHoriz = MaterialSymbol(
        sf = "ellipsis", symbol = "more_horiz", weight = 500,
        meaning = "More actions on this thing.",
        resId = R.drawable.ic_more_horiz_w500,
    )

    /** 19. Support contact. */
    val Mail = MaterialSymbol(
        sf = "envelope", symbol = "mail", weight = 500,
        meaning = "Write to support.",
        resId = R.drawable.ic_mail_w500,
    )

    /** 20. Recoverable failure. Keep FILL 0 — the filled disc reads as a hard stop. */
    val Error = MaterialSymbol(
        sf = "exclamationmark.circle", symbol = "error", weight = 400,
        meaning = "Something went wrong, and you can try again.",
        resId = R.drawable.ic_error,
    )

    /**
     * 21. Sync failure — the SyncBanner's mark.
     *
     * `research/typography-icons.md` §5.3 records wght 400 for this row; the iOS call site
     * (`Primitives.swift:1015`) draws it at 13 pt `.semibold`, so 500 is the honest port. The code
     * wins over the research note.
     */
    val WarningFilled = MaterialSymbol(
        sf = "exclamationmark.triangle.fill", symbol = "warning", fill = 1, weight = 500,
        meaning = "A change did not save. Warning ink, never destructive red.",
        resId = R.drawable.ic_warning_w500_fill,
    )

    /** 22. Reveal — the button over a hidden episode still. Not a settings toggle. */
    val Visibility = MaterialSymbol(
        sf = "eye", symbol = "visibility", weight = 500,
        meaning = "Show me the thing I chose to hide (spoiler reveal).",
        resId = R.drawable.ic_visibility_w500,
    )

    /** 23. Hidden — the censored still itself, and Schedule's "hide watched" filter. */
    val VisibilityOff = MaterialSymbol(
        sf = "eye.slash", symbol = "visibility_off", weight = 400,
        meaning = "Hidden to avoid a spoiler.",
        resId = R.drawable.ic_visibility_off,
    )

    /** 24. Privacy policy row. */
    val FrontHand = MaterialSymbol(
        sf = "hand.raised", symbol = "front_hand", weight = 500,
        meaning = "Privacy.",
        resId = R.drawable.ic_front_hand_w500,
    )

    /** 25. Haptics setting. */
    val TouchApp = MaterialSymbol(
        sf = "hand.tap", symbol = "touch_app", weight = 500,
        meaning = "Haptics — what the app does under your finger.",
        resId = R.drawable.ic_touch_app_w500,
    )

    /**
     * 26. Filter. `filter_list` is the 1:1 for SF's decreasing rules; `filter_alt` (the funnel) is
     * the Android reflex but changes the mark. Mirrors in RTL — the rules are left-aligned and
     * decreasing, so unmirrored it reads backwards.
     */
    val FilterList = MaterialSymbol(
        sf = "line.3.horizontal.decrease", symbol = "filter_list", weight = 500, autoMirrored = true,
        meaning = "Arrange / filter. Amber only while filters are active — that is STATE.",
        resId = R.drawable.ic_filter_list_w500,
    )

    /** 27. Search. Also the Discover tab's icon — the fifth tab, beside the four app vectors. */
    val Search = MaterialSymbol(
        sf = "magnifyingglass", symbol = "search", weight = 500,
        meaning = "Find a show. The Discover tab's mark.",
        resId = R.drawable.ic_search_w500,
    )

    /**
     * 28. Avatar fallback — `PersonCard`'s 72-dp disc, and the account disc.
     * **Not `account_circle`**: that draws its own disc and the app already drew one.
     */
    val PersonFilled = MaterialSymbol(
        sf = "person.fill", symbol = "person", fill = 1, weight = 400,
        meaning = "A person we have no photograph of.",
        resId = R.drawable.ic_person_fill,
    )

    /** 29. Art placeholder inside `PosterSlot`. `broken_image` says "failed"; this is "not yet". */
    val Image = MaterialSymbol(
        sf = "photo", symbol = "image", weight = 400,
        meaning = "Art that has not arrived yet. Never 'art that failed'.",
        resId = R.drawable.ic_image,
    )

    /** 30. Trailer play triangle. */
    val PlayArrowFilled = MaterialSymbol(
        sf = "play.fill", symbol = "play_arrow", fill = 1, weight = 400,
        meaning = "Play the trailer.",
        resId = R.drawable.ic_play_arrow_fill,
    )

    /** 31. `TrailerCard`'s affordance — a triangle in a rounded rectangle. */
    val SmartDisplay = MaterialSymbol(
        sf = "play.rectangle", symbol = "smart_display", weight = 400,
        meaning = "There is a video behind this card.",
        resId = R.drawable.ic_smart_display,
    )

    /**
     * 32. Add to library — Detail's toolbar glyph.
     *
     * **Stays `interactive` ink, never amber.** This is the rule the iOS build broke and fixed: an
     * amber "+ Add" directly above an amber "Episode 14 next" made one hue mean both "press this"
     * and "this is what's coming".
     */
    val Add = MaterialSymbol(
        sf = "plus", symbol = "add", weight = 500,
        meaning = "Add this show. Neutral ink — amber is not an action colour.",
        resId = R.drawable.ic_add_w500,
    )

    /** 33. Sign out. Mirrors in RTL. */
    val Logout = MaterialSymbol(
        sf = "rectangle.portrait.and.arrow.right", symbol = "logout", weight = 500,
        autoMirrored = true,
        meaning = "Leave this account.",
        resId = R.drawable.ic_logout_w500,
    )

    /** 34. Library / all titles. `video_library` is the alternative if `layers` reads as a tool. */
    val Layers = MaterialSymbol(
        sf = "rectangle.stack", symbol = "layers", weight = 400,
        meaning = "Your shelf of shows.",
        resId = R.drawable.ic_layers,
    )

    /** 35. "No titles match your filters." */
    val Tune = MaterialSymbol(
        sf = "slider.horizontal.3", symbol = "tune", weight = 400,
        meaning = "The filters, not the library, are why this is empty.",
        resId = R.drawable.ic_tune,
    )

    /**
     * 36. Share.
     *
     * ⚠ `ios_share` exists in Material Symbols and is a literal copy of the iOS box-and-arrow.
     * **Do not use it.** This is the one place the fidelity rule yields outright to the platform
     * reflex: `share` plus the system share sheet (`Intent.ACTION_SEND`). Shipping the iOS glyph
     * on Android reads as a port, not as an app.
     */
    val Share = MaterialSymbol(
        sf = "square.and.arrow.up", symbol = "share", weight = 500,
        meaning = "Send this somewhere else — through Android's own share sheet.",
        resId = R.drawable.ic_share_w500,
    )

    /** 37. Export as a table. `table_chart` / `grid_on` are the alternatives. */
    val Table = MaterialSymbol(
        sf = "tablecells", symbol = "table", weight = 500,
        meaning = "Export as rows and columns.",
        resId = R.drawable.ic_table_w500,
    )

    /** 38. Destructive. */
    val Delete = MaterialSymbol(
        sf = "trash", symbol = "delete", weight = 400,
        meaning = "Remove. Destructive ink; always with Undo where the app offers it.",
        resId = R.drawable.ic_delete,
    )

    /** 39. TV scope / source badge. */
    val Tv = MaterialSymbol(
        sf = "tv", symbol = "tv", weight = 400,
        meaning = "This is television, not anime — the source badge and the search scope.",
        resId = R.drawable.ic_tv,
    )

    /**
     * 40. ⚠ Weak match. `signal_wifi_statusbar_not_connected` and `signal_wifi_bad` both read
     * closer to "connected but not working", which is what this state actually is. Compare all
     * three on device before the vendoring is treated as settled.
     */
    val WifiTetheringError = MaterialSymbol(
        sf = "wifi.exclamationmark", symbol = "wifi_tethering_error", weight = 400,
        meaning = "We reached the network and it did not answer. Not the same as offline.",
        resId = R.drawable.ic_wifi_tethering_error,
    )

    /** 41. Offline. Exact match. */
    val WifiOff = MaterialSymbol(
        sf = "wifi.slash", symbol = "wifi_off", weight = 400,
        meaning = "You're offline. (The copy says exactly that — never 'server'.)",
        resId = R.drawable.ic_wifi_off,
    )

    /** 42. Dismiss. Exact match. */
    val Close = MaterialSymbol(
        sf = "xmark", symbol = "close", weight = 500,
        meaning = "Dismiss this.",
        resId = R.drawable.ic_close_w500,
    )

    /**
     * Symbols the iOS source draws that `spec/icon-mapping.md`'s 42-row inventory does not list.
     *
     * All ten were verified as live `Image(systemName:)` / `Label(systemImage:)` call sites in the
     * working tree on 2026-09-04; most of them live in `DesignSystem/FranchiseContextMenu.swift`,
     * a file the inventory pass appears to have missed, and the rest are ternary or
     * stored-property payloads that neither the 24-literal count nor the 42-row count caught.
     *
     * **These picks are PROVISIONAL.** They exist so that a screen agent who needs the status
     * glyph for "Paused" finds an answer here instead of improvising one, and so that the gap is
     * visible rather than discovered during QA. Each needs the same owner ruling the 42 got.
     *
     * Two more call sites are deliberately NOT declared here, because on Android they are not
     * glyphs at all:
     *  - `circle.fill` (`DifferentiateMark`, a 6-pt dot shown only under Differentiate Without
     *    Colour) → a 6-dp `Box` with `CircleShape`. Cheaper and sharper than a glyph.
     *  - `line.3.horizontal.decrease.circle.fill` (Schedule's toolbar while filters are active) →
     *    [FilterList] drawn on an `accentSoft` disc. Material has no circled-filter glyph, and the
     *    app already owns that disc primitive.
     */
    object Pending {

        /** Profile's retry action. `refresh` — and note this is exactly where [Sync] is wrong. */
        val Refresh = MaterialSymbol(
            sf = "arrow.clockwise", symbol = "refresh", weight = 400,
            meaning = "Try loading that again. Reload, not rewatch.",
        resId = R.drawable.ic_refresh,
        )

        /** Profile's trailing glyph on rows that leave the app. Same D29 ruling as [OpenInNew]. */
        val OpenInNewTrailing = MaterialSymbol(
            sf = "arrow.up.forward", symbol = "open_in_new", weight = 500,
            meaning = "This row leaves the app — a chevron would promise a push.",
        resId = R.drawable.ic_open_in_new_w500,
        )

        /** The status menu's Completed. FILL 0 — the filled disc belongs to [CheckCircleFilled]. */
        val CheckCircle = MaterialSymbol(
            sf = "checkmark.circle", symbol = "check_circle", weight = 400,
            meaning = "Status: completed.",
        resId = R.drawable.ic_check_circle,
        )

        /** The status menu's Watching. */
        val PlayCircle = MaterialSymbol(
            sf = "play.circle", symbol = "play_circle", weight = 400,
            meaning = "Status: watching.",
        resId = R.drawable.ic_play_circle,
        )

        /** The status menu's Paused. */
        val PauseCircle = MaterialSymbol(
            sf = "pause.circle", symbol = "pause_circle", weight = 400,
            meaning = "Status: paused.",
        resId = R.drawable.ic_pause_circle,
        )

        /** The status menu's Dropped. `highlight_off` is the alternative. */
        val Cancel = MaterialSymbol(
            sf = "xmark.circle", symbol = "cancel", weight = 400,
            meaning = "Status: dropped. Not destructive — the show stays in the library.",
        resId = R.drawable.ic_cancel,
        )

        /** `InlineNotice` when the kind is not a failure — a plain footnote fact. */
        val Info = MaterialSymbol(
            sf = "info.circle", symbol = "info", weight = 500,
            meaning = "A fact worth a footnote. Not a warning, not an error.",
        resId = R.drawable.ic_info_w500,
        )

        /**
         * ⚠ "Mark N episodes as watched" in the context menu. No clean Material equivalent —
         * `playlist_add` is the nearest ("add many to a list") but says *add*, where this means
         * *catch up*. PLAN §3.3 flags this as one of the four that may need a custom vector.
         */
        val PlaylistAdd = MaterialSymbol(
            sf = "text.append", symbol = "playlist_add", weight = 400,
            meaning = "Mark the whole backlog at once.",
        resId = R.drawable.ic_playlist_add,
        )
    }

    /**
     * The 42 rows, in `spec/icon-mapping.md` order. Two uses: the vendoring script reads
     * [MaterialSymbol.sourceFileName] off it, and a unit test asserts the count and the axes so
     * that a silently dropped row fails CI rather than a state screen.
     */
    val vocabulary: List<MaterialSymbol> = listOf(
        Sync, RecentQuery, OpenInNew, Notifications, NotificationsActive, NotificationsFilled,
        Bookmark, CalendarMonth, Check, CheckCircleFilled, KeyboardArrowDown, ChevronRight,
        UnfoldMore, History, DataObject, Description, Sensors, MoreHoriz, Mail, Error,
        WarningFilled, Visibility, VisibilityOff, FrontHand, TouchApp, FilterList, Search,
        PersonFilled, Image, PlayArrowFilled, SmartDisplay, Add, Logout, Layers, Tune, Share,
        Table, Delete, Tv, WifiTetheringError, WifiOff, Close,
    )

    /**
     * The eight provisional picks (the other two unlisted call sites are not glyphs on Android —
     * see [Pending]). Kept out of [vocabulary] so that 42 stays the number the spec says it is.
     */
    val pendingVocabulary: List<MaterialSymbol> = with(Pending) {
        listOf(
            Refresh, OpenInNewTrailing, CheckCircle, PlayCircle, PauseCircle, Cancel, Info,
            PlaylistAdd,
        )
    }
}
