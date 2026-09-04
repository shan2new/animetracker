package com.anitrack.app.ui.list

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.anitrack.app.design.ContinuousCornerShape
import com.anitrack.app.design.MaterialSymbol
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.SurfaceLevel
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.surface
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.control.PreviouslySwitch
import com.anitrack.app.ui.control.SymbolIcon
import com.anitrack.app.ui.isAccessibilityTextSize
import com.anitrack.app.ui.section.SectionLabel
import com.anitrack.app.ui.state.IndeterminateArc

/*
 * THE GROUPED LIST — the port of `GroupedList` / `GroupedTrailing` / `GroupedRow` /
 * `GroupedRowPressStyle` in ios/Sources/DesignSystem/Primitives.swift. Spec: §5 of
 * docs/android-port/spec/primitives.md.
 *
 * An inset grouped list in the system grammar: a PLATE, not a stroked box — this is the grouped-
 * table grammar and a grouped table has never had an outline. The fill IS the group.
 *
 * Dividers inside the plate are `separatorQuiet` (white 4.5 %), never `separator` (8 %): eight of
 * these down one plate at 8 % reads as a spreadsheet, and the eye should read GROUPING, not ruling.
 *
 * The press feel and the SF→Material glyph ratio are `PressStyle.groupedRow` and
 * `materialGlyphBox` in `ui/control/Buttons.kt`. This file declares neither.
 */

// ─────────────────────────────────────────────────────────────────────────────
// Geometry. Component-local: this is the row's own anatomy, not a scale token.
// ─────────────────────────────────────────────────────────────────────────────

/** The row's leading inset, and the inset a symbol-less separator starts at. */
private val GroupedRowLeadingInset = 14.dp

/** The row's trailing inset. Two dp wider than the leading one, as the shipped row is. */
private val GroupedRowTrailingInset = 16.dp

/** Between the symbol, the copy column and the trailing view. */
private val GroupedRowGap = ThemeSpace.x3

/** The minimum the flexible gap between the copy column and the trailing view collapses to. */
private val GroupedRowTrailingGap = ThemeSpace.x2

/** Between a trailing value and its chevron. */
private val GroupedRowInlineGap = 6.dp

/** Title → subtitle. One point: they are one thought, and the row is only 56 tall. */
private val GroupedRowCopyGap = 1.dp

/**
 * The row's own vertical air, so a two-line title or a wrapped subtitle does not sit on the
 * separator. It does not change the 56-dp minimum a one-line row draws at.
 */
private val GroupedRowVerticalInset = ThemeSpace.x2

/** The leading symbol TILE — [GroupedSymbolStyle.Tile]'s ground. */
private val SymbolTile = 28.dp
private val SymbolTileRadius = 7.dp

/** The leading symbol COLUMN — [GroupedSymbolStyle.Column], which paints no ground. */
private val SymbolColumn = 22.dp

/**
 * Where a separator starts when the row carries a symbol: [GroupedRowLeadingInset] + the symbol's
 * own width + [GroupedRowGap] — the copy column's leading edge, so the rule is inset to the title
 * exactly as the system's grouped table insets it.
 */
private val SeparatorTileInset = GroupedRowLeadingInset + SymbolTile + GroupedRowGap
private val SeparatorColumnInset = GroupedRowLeadingInset + SymbolColumn + GroupedRowGap

/** One hairline. */
private val SeparatorHeight = ThemeMetrics.hairline

/**
 * The trailing checkmark's reserved column.
 *
 * Reserved whether the row is the chosen one or not: the tick fades rather than unmounts, so
 * choosing a different value does not re-flow the list under the finger.
 */
private val CheckColumn = 22.dp

/**
 * Glyph sizes, at their **iOS point values** — `materialGlyphBox` owns the conversion to a
 * Material Symbol's box, and it is the one place that ratio may change.
 *
 * iOS: symbol tile 15 pt medium, trailing chevron 13 pt semibold, checkmark 15 pt semibold.
 */
private val SymbolGlyph = 15.dp

/** iOS `.system(size: 16, weight: .medium)` on a column symbol — a hair larger, with no tile. */
private val ColumnSymbolGlyph = 16.dp
private val RowChevronGlyph = 13.dp
private val CheckGlyph = 15.dp

/** The "unsaved / needs attention" dot beside a title. */
private val WarningDot = 8.dp

/**
 * The in-flight arc drawn in an empty symbol column — the same arc, turn and Reduce Motion decision
 * every spinner in the app makes ([IndeterminateArc]); only the size and ink are this row's.
 */
private val WaitSpinner = 18.dp
private val WaitSpinnerStroke = 2.dp
private const val WaitSpinnerSweep = 270f

/**
 * The row's geometry, for the handful of hand-built blocks that must ALIGN to a row they are not.
 *
 * Derived, never re-added: Profile's failure row aligned its detail block to a privately computed
 * 50 while the rows above it ruled at 54.
 */
object GroupedRowMetrics {

    /** Where a column-symbol row's separator and copy column begin. */
    val columnSeparatorInset: Dp = SeparatorColumnInset

    /** Where a tile-symbol row's do. */
    val tileSeparatorInset: Dp = SeparatorTileInset

    /** The row's leading inset, for a block that starts at the plate edge. */
    val leadingInset: Dp = GroupedRowLeadingInset
}

/** Defaults a caller may name without spending a literal of its own. */
object GroupedRowDefaults {

    /**
     * The ground of a leading symbol tile.
     *
     * Ported verbatim from the shipped row (`Color(hex: 0x3A3D45)`). It is deliberately NOT a
     * `ThemeColor` token: it exists in exactly one place in the app — the settings tile — and the
     * palette is the app's shared vocabulary, not a home for one component's ground. A caller that
     * wants a different tile colour passes one; it does not invent a token.
     */
    val symbolTint = Color(0xFF3A3D45)
}

/** What a [GroupedRow] draws along its trailing edge. */
@Immutable
sealed interface GroupedTrailing {

    /** A disclosure chevron, optionally preceded by the row's current value. */
    @Immutable
    data class Chevron(val value: String? = null) : GroupedTrailing

    /** A value with no disclosure — the row states something and does not push. */
    @Immutable
    data class Value(val text: String) : GroupedTrailing

    /**
     * A real switch. The row becomes ONE toggleable element rather than a button containing a
     * control — see [GroupedRow].
     */
    @Immutable
    data class Toggle(
        val checked: Boolean,
        val onCheckedChange: (Boolean) -> Unit,
    ) : GroupedTrailing

    /** A selection tick. Amber, because a chosen value is STATE. */
    @Immutable
    data class Check(val on: Boolean) : GroupedTrailing

    /** Nothing. */
    @Immutable
    data object None : GroupedTrailing
}

/**
 * How a [GroupedRow] draws its leading symbol. **The only thing that separates the app's two
 * grouped-row dialects**, now that there is one row.
 *
 * There were two whole components: this one and `ProfileRowLabel` / `ProfileRow` in
 * `ui/profile/Settings.kt`, both drawn inside [GroupedList] plates and four dp apart in every
 * measure — a 16-dp leading inset against 14, a 22-dp symbol column against a 28-dp tile, a 2-dp
 * title→subtitle gap against 1, a 50-dp separator inset against 54. Profile → Settings and Detail →
 * Watch history showed two settings-row anatomies one push apart. The geometry is this file's now,
 * once; the difference that was real — a tinted tile behind an app-vocabulary symbol, versus a bare
 * monochrome column on a screen that paints no ground behind a symbol — is this enum.
 */
enum class GroupedSymbolStyle {
    /** A 28-dp tinted tile at a 7-dp radius, the symbol in `textPrimary` on it. */
    Tile,

    /** A 22-dp column, no ground, the symbol in its own tint. Profile / Settings / Account / Sync. */
    Column,
}

/**
 * An inset grouped list: an eyebrow, then a plate of rows.
 *
 * The plate is [SurfaceLevel.Plate] at [ThemeRadius.row] — a translucent white LIFT over whatever
 * is beneath it, never an opaque fill, so a screen carrying an ambient art wash cannot invert the
 * plate into a hole darker than its own ground.
 *
 * @param header an eyebrow above the plate. Marked as a heading: the heading rotor is how a
 *   grouped screen is skimmed, and without the trait a five-section settings page had exactly one
 *   stop.
 */
@Composable
fun GroupedList(
    modifier: Modifier = Modifier,
    header: String? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(ThemeMetrics.labelGap),
        horizontalAlignment = Alignment.Start,
    ) {
        if (header != null) {
            SectionLabel(
                text = header,
                modifier = Modifier
                    .padding(start = ThemeSpace.x4)
                    .semantics { heading() },
            )
        }
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .surface(SurfaceLevel.Plate, ThemeRadius.row),
            content = content,
        )
    }
}

/**
 * **THE** grouped row: an optional leading symbol, a title, an optional subtitle, and one trailing
 * view. Settings, Account, Sync, Detail's watch-history row, the rewatch screens and All titles'
 * Arrange sheet all draw this and nothing else.
 *
 * **Two structural branches, and the branch matters for accessibility.**
 *
 * A [GroupedTrailing.Toggle] renders a real switch whose LABEL is the row — one element, with the
 * switch role, a spoken on/off value, and the whole row as its target. A switch nested inside a
 * button does not survive as an independent element: it was announced as "Unwatched only, button"
 * with no switch trait and no value, and the outer button's hit-test priority made the switch
 * itself unreliable to hit.
 *
 * Everything else is a button. Both branches press to [ThemeColor.surfacePressed] through
 * `PressStyle.groupedRow`. There is deliberately no clipping on the row: the pressed ground is
 * clipped by the plate around the whole list, which is how the first and last rows get rounded
 * press highlights for free.
 *
 * At accessibility sizes the stack switches to top alignment and the symbol is centred inside a box
 * exactly one title-line tall: a vertically centred glyph beside a two-line title sits next to the
 * SUBTITLE. iOS aligns to `.firstTextBaseline`; a Compose `Image` has no baseline to align to, and
 * a one-line box lands in the same place without sinking when the title wraps.
 *
 * @param onClick `null` makes the row inert — it stops being a button rather than becoming a
 *   disabled one, so nothing announces a target that does nothing.
 * @param enabled a disabled row keeps its place and stops answering: the destructive pair on Profile
 *   disable each other while either is in flight.
 * @param symbolStyle see [GroupedSymbolStyle]. `Tile` is the design system's default; `Column` is
 *   the settings dialect.
 * @param indicateWait with no [symbol], draw the in-flight spinner in the symbol's reserved column —
 *   which is how a row guarantees a wait is shown once, in one place, and never as a glyph plus a
 *   spinner. Ignored when a symbol is given.
 * @param hint what tapping the row does, spoken by TalkBack as the click label. iOS marks the two
 *   web rows `.isLink`; Compose has no link role, so the affordance is carried by this sentence —
 *   which is what a screen-reader user actually needs, and the reason the arrow glyph is silent.
 * @param value the row's current value, spoken as a state description ("On" / "Off").
 * @param label overrides the spoken title, for a row whose drawn words are a format and not a verb
 *   ("JSON" → "Export as JSON").
 * @param trailingContent a caller-drawn trailing view, for the handful of rows whose trailing is a
 *   composition rather than one of the [GroupedTrailing] cases (a value beside an external arrow, a
 *   "Retry all" link, a switch). It **replaces** [trailing] when both are given.
 */
@Composable
fun GroupedRow(
    title: String,
    modifier: Modifier = Modifier,
    symbol: MaterialSymbol? = null,
    symbolStyle: GroupedSymbolStyle = GroupedSymbolStyle.Tile,
    symbolTint: Color = GroupedRowDefaults.symbolTint,
    titleTint: Color = ThemeColor.textPrimary,
    subtitle: String? = null,
    warning: Boolean = false,
    trailing: GroupedTrailing = GroupedTrailing.None,
    separator: Boolean = true,
    enabled: Boolean = true,
    indicateWait: Boolean = false,
    hint: String? = null,
    value: String? = null,
    label: String? = null,
    onClick: (() -> Unit)? = null,
    trailingContent: (@Composable RowScope.() -> Unit)? = null,
) {
    val toggle = trailing as? GroupedTrailing.Toggle
    val isAX = isAccessibilityTextSize()

    val interaction: Modifier = when {
        toggle != null -> Modifier.toggleable(
            value = toggle.checked,
            interactionSource = null,
            enabled = enabled,
            // The row is the target on Android, so it answers like every other row in the plate.
            // iOS's toggle row has no pressed ground only because a SwiftUI `Toggle` takes no
            // `ButtonStyle` — a full-width target that does not respond reads as broken here.
            indication = PressStyle.groupedRow,
            role = Role.Switch,
            onValueChange = toggle.onCheckedChange,
        )

        onClick != null -> Modifier.clickable(
            interactionSource = null,
            indication = PressStyle.groupedRow,
            enabled = enabled,
            onClickLabel = hint,
            role = Role.Button,
            onClick = onClick,
        )

        else -> Modifier
    }

    val spoken: Modifier = if (value == null && label == null) {
        Modifier
    } else {
        Modifier.semantics(mergeDescendants = true) {
            if (value != null) stateDescription = value
            if (label != null) contentDescription = label
        }
    }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .then(interaction)
            .then(spoken)
            .heightIn(min = ThemeMetrics.rowCompact),
        contentAlignment = Alignment.CenterStart,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = GroupedRowLeadingInset, end = GroupedRowTrailingInset)
                .padding(vertical = GroupedRowVerticalInset),
            horizontalArrangement = Arrangement.spacedBy(GroupedRowGap),
            verticalAlignment = if (isAX) Alignment.Top else Alignment.CenterVertically,
        ) {
            LabelStack(
                title = title,
                titleTint = titleTint,
                subtitle = subtitle,
                warning = warning,
                symbol = symbol,
                symbolStyle = symbolStyle,
                symbolTint = symbolTint,
                indicateWait = indicateWait,
                isAX = isAX,
                modifier = Modifier.weight(1f),
            )
            when {
                trailingContent != null -> {
                    Spacer(Modifier.width(GroupedRowTrailingGap))
                    trailingContent()
                }

                trailing !is GroupedTrailing.None -> {
                    Spacer(Modifier.width(GroupedRowTrailingGap))
                    TrailingView(trailing)
                }
            }
        }

        if (separator) {
            val inset = when {
                symbol == null && !indicateWait -> GroupedRowLeadingInset
                symbolStyle == GroupedSymbolStyle.Column -> SeparatorColumnInset
                else -> SeparatorTileInset
            }
            Spacer(
                Modifier
                    .align(Alignment.BottomStart)
                    .fillMaxWidth()
                    .padding(start = inset)
                    .height(SeparatorHeight)
                    .background(ThemeColor.separatorQuiet),
            )
        }
    }
}

/** The symbol, the title (with its warning dot) and the subtitle. */
@Composable
private fun LabelStack(
    title: String,
    titleTint: Color,
    subtitle: String?,
    warning: Boolean,
    symbol: MaterialSymbol?,
    symbolStyle: GroupedSymbolStyle,
    symbolTint: Color,
    indicateWait: Boolean,
    isAX: Boolean,
    modifier: Modifier = Modifier,
) {
    // One title line, for the AX glyph box — see [GroupedRow].
    val titleLine = with(LocalDensity.current) { ThemeType.body.lineHeight.toDp() }

    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(GroupedRowGap),
        verticalAlignment = if (isAX) Alignment.Top else Alignment.CenterVertically,
    ) {
        if (symbol != null || indicateWait) {
            val column = if (symbolStyle == GroupedSymbolStyle.Tile) SymbolTile else SymbolColumn
            Box(
                modifier = Modifier
                    .width(column)
                    .then(
                        when {
                            isAX -> Modifier.height(titleLine)
                            symbolStyle == GroupedSymbolStyle.Tile -> Modifier.height(SymbolTile)
                            else -> Modifier
                        },
                    )
                    .then(
                        if (symbol != null && symbolStyle == GroupedSymbolStyle.Tile) {
                            Modifier.background(symbolTint, ContinuousCornerShape(SymbolTileRadius))
                        } else {
                            Modifier
                        },
                    ),
                contentAlignment = Alignment.Center,
            ) {
                when {
                    // Decorative: the row's title says what the row is. `SymbolIcon` owns the
                    // SF-point-size → Material-box conversion, and it is the only place that ratio
                    // is spelled.
                    symbol != null && symbolStyle == GroupedSymbolStyle.Tile ->
                        SymbolIcon(symbol, ThemeColor.textPrimary, SymbolGlyph)

                    symbol != null -> SymbolIcon(symbol, symbolTint, ColumnSymbolGlyph)

                    else -> IndeterminateArc(
                        tint = ThemeColor.textTertiary,
                        diameter = WaitSpinner,
                        stroke = WaitSpinnerStroke,
                        sweep = WaitSpinnerSweep,
                    )
                }
            }
        }
        // Greedy, as the shipped `frame(maxWidth: .infinity, alignment: .leading)` is: the copy
        // column owns everything the symbol and the trailing view do not.
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(GroupedRowCopyGap),
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                BasicText(
                    text = title,
                    style = ThemeType.body.copy(color = titleTint),
                    maxLines = if (isAX) Int.MAX_VALUE else 2,
                )
                if (warning) {
                    Spacer(Modifier.size(WarningDot).background(ThemeColor.warning, CircleShape))
                }
            }
            if (subtitle != null) {
                BasicText(
                    text = subtitle,
                    style = ThemeType.metadata.copy(color = ThemeColor.textSecondary),
                    maxLines = if (isAX) Int.MAX_VALUE else 2,
                )
            }
        }
    }
}

@Composable
private fun TrailingView(trailing: GroupedTrailing) {
    when (trailing) {
        is GroupedTrailing.Chevron -> Row(
            horizontalArrangement = Arrangement.spacedBy(GroupedRowInlineGap),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val value = trailing.value
            if (value != null) {
                BasicText(
                    text = value,
                    style = ThemeType.body.copy(color = ThemeColor.textTertiary),
                    maxLines = 1,
                )
            }
            SymbolIcon(PreviouslyIcons.ChevronRight, ThemeColor.textTertiary, RowChevronGlyph)
        }

        is GroupedTrailing.Value -> BasicText(
            text = trailing.text,
            style = ThemeType.body.copy(color = ThemeColor.textTertiary),
            maxLines = 1,
        )

        is GroupedTrailing.Toggle -> PreviouslySwitch(trailing.checked)

        is GroupedTrailing.Check -> {
            val on = trailing.on
            Box(Modifier.width(CheckColumn), contentAlignment = Alignment.Center) {
                SymbolIcon(
                    symbol = PreviouslyIcons.Check,
                    tint = ThemeColor.accent,
                    glyph = CheckGlyph,
                    // Faded, not unmounted — see [CheckColumn]. Read inside the layer, so the
                    // change costs a layer property and not a recomposition.
                    modifier = Modifier.graphicsLayer { alpha = if (on) 1f else 0f },
                )
            }
        }

        GroupedTrailing.None -> Unit
    }
}
