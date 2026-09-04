package com.anitrack.app.ui.section

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.anitrack.app.design.MaterialSymbol
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.ui.AutoSizeText
import com.anitrack.app.ui.control.InlineLink
import com.anitrack.app.ui.isAccessibilityTextSize
import com.anitrack.app.ui.negativePadding
import com.anitrack.app.ui.control.InlineLinkButton
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.control.SymbolIcon
import com.anitrack.app.ui.control.minimumTapTarget
import com.anitrack.model.copy.Copy
import java.util.Locale

/*
 * SECTION FURNITURE — the port of `SectionHeaderRow` / `SectionHeaderPressStyle`
 * (ios/Sources/DesignSystem/Primitives+States.swift) and `SectionLabel` / `OverArtLabel`
 * (ios/Sources/DesignSystem/Primitives.swift). See docs/android-port/spec/primitives.md §4.
 *
 * ONE SECTION-HEADER FAMILY: [SectionHeaderRow]. Small-caps [SectionLabel] is an EYEBROW only —
 * over art ([OverArtLabel]), a grouped list's header, a sheet label, Schedule's day headers. It is
 * never a shelf header.
 *
 * Two rules from CLAUDE.md govern almost everything below:
 *
 *   * **Amber is never an action colour.** The header's inline command ("Clear") is an
 *     `InlineLinkButton`, drawn in `LocalControlInk` (= `ThemeColor.interactive`), never `accent`.
 *     The only amber this file draws is the "newly changed" dot, which is STATE.
 *   * **A section header paints no ground.** An opaque plate behind a header cuts a hard step
 *     across the root wash; a header is type on the canvas and nothing else.
 *
 * Nothing here declares a press feel, a glyph box, a tap-target floor or an accessibility-size
 * threshold of its own: those are `PressStyle` / `materialGlyphBox` / `minimumTapTarget` in
 * `ui/control/Buttons.kt` and `isAccessibilityTextSize` / `AutoSizeText` in `ui/UiPrimitives.kt`.
 * A second answer to any of them is a second product.
 */

// ─────────────────────────────────────────────────────────────────────────────
// Geometry. Component-local by design: this is the header's own anatomy, not a scale token. The
// design system's rule is that a SCREEN spends no literal — a primitive is where the literals live
// ("Each has exact geometry, named states, and no local colour or radius values").
// ─────────────────────────────────────────────────────────────────────────────

/** Between the dot, the title, the count and the chevron inside a navigating header. */
private val SectionHeaderInnerGap = 6.dp

/** The "newly changed" dot beside a section title — the same 5-dp mark [OverArtLabel] uses. */
private val SectionHeaderDot = 5.dp

/** [SectionLabel]'s dot is a size smaller: it sits beside 11-sp caps, not a 20-sp title. */
private val SectionLabelDot = 4.dp

/**
 * The padding that lifts the header's target to [minimumTapTarget], and the pull-back that hides
 * it again.
 *
 * `padding(vertical = 10)` → `defaultMinSize(minHeight = 44)`, then [negativePadding] takes the
 * 10 back off each edge so the header's LAYOUT is the title's own height. Without the pull-back
 * every stack carrying a header would stand 20 dp taller.
 */
private val SectionHeaderPressOverhang = 10.dp

/**
 * The pull-back applied to the inline command.
 *
 * [InlineLinkButton] already pads itself to a real target — a footnote cap-height is ~13 dp, so it
 * spends 14 dp above and below, symmetric so the hit area is the padded box and not the WORD. This
 * is the `.padding(.vertical, -12)` the header wraps it in, so a "Clear" beside a title does not
 * set the header's height.
 */
private val InlineActionOverhang = InlineLink.sideOverhang

/** iOS `.minimumScaleFactor(0.85)` on the section title. */
private const val SectionTitleMinimumScale = 0.85f

/**
 * The header's chevron, at its iOS point size.
 *
 * 14 pt semibold — one step heavier than a row's 13, because it sits beside a 20-sp title rather
 * than 13-sp metadata. [materialGlyphBox] does the SF→Material conversion; the ratio lives there
 * and nowhere else.
 */
private val SectionChevronGlyph = 14.dp

/** [OverArtLabel]'s capsule. A hard 24 dp: it does **not** grow with the text scale. */
private val OverArtLabelHeight = 24.dp
private val OverArtLabelInset = 10.dp
private val OverArtLabelEdge = ThemeMetrics.hairline

/** The section title, with its ink. A stable value: [AutoSizeText] keys its measurement on it. */
private val SectionTitleStyle: TextStyle =
    ThemeType.sectionTitle.copy(color = ThemeColor.textPrimary)

/**
 * The count sits on the title's baseline in `metadata`, with **tabular** figures.
 *
 * iOS reaches that with `.monospacedDigit()` at the call site. `ThemeType` has no tabular 13-sp
 * token and this file may not add one to the palette, so the token is DERIVED here rather than
 * re-declared: same family, same size, same tracking, `tnum` on. Ink is `textTertiary` (5.14:1 —
 * the AA floor for text at any size); `textDisabled` is reserved for glyphs.
 */
private val SectionCountStyle: TextStyle =
    ThemeType.metadata.copy(fontFeatureSettings = "tnum", color = ThemeColor.textTertiary)

/**
 * THE section header: a bold title in the app's voice, an optional count on its baseline, and —
 * when the header is the way into its section — a trailing chevron with the whole title as the
 * target.
 *
 * Every shelf in Apple TV, Netflix and Apple Music is headed by a bold mixed-case title
 * ("Continue Watching ›"), tappable as a unit; this app headed its shelves with an 11-pt
 * small-caps footnote and hung a 13-pt "See all" off the far edge, so the section's name was the
 * quietest thing in the section and its action was a word to hunt for. **The chevron carries the
 * affordance now — there is no "See all" word in the header; the title IS the button.**
 *
 * Three shapes:
 *
 *  * **A — navigating** ([onAction] set, [inlineAction] false): title + count + chevron is one
 *    button. [actionLabel] is spoken, never drawn (default [Copy.Action.seeAll]).
 *  * **B — plain** (no action, or an action with nothing to label it): title + count, marked as a
 *    heading.
 *  * **C — inline command** ([inlineAction] with an [actionLabel] and an [onAction]): the title
 *    stays inert and a trailing text link carries a command ON the section ("Clear"). The link is
 *    `interactive` ink at `listAction` — it must not out-weigh the title it belongs to, and it is
 *    never amber.
 *
 * @param dot the 5-dp accent mark meaning **newly changed**, and only that.
 */
@Composable
fun SectionHeaderRow(
    text: String,
    modifier: Modifier = Modifier,
    count: Int? = null,
    dot: Boolean = false,
    actionLabel: String? = null,
    inlineAction: Boolean = false,
    onAction: (() -> Unit)? = null,
) {
    val navigates = onAction != null && !inlineAction
    val hasInlineAction = inlineAction && actionLabel != null && onAction != null

    Row(
        modifier = modifier
            .fillMaxWidth()
            // [negativePadding] pulls the header back to the title's own height, which leaves the
            // button DRAWING and HIT-TESTING above and below the row's layout rect. Siblings laid
            // out after the header would otherwise win the taps in the lower overlap band whenever
            // the stack's spacing is under 10 dp, quietly eating the bottom quarter of a 44-dp
            // target. The header paints (and tests) above them.
            .zIndex(1f),
        // The title group takes what it needs and no more (`fill = false`); SpaceBetween puts the
        // slack between it and a trailing command instead of after both, which is what SwiftUI's
        // flexible `Spacer` did. With one child it simply leaves it at the start.
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // `fill = false` also CAPS the group: without it a long title would consume the whole row
        // and push the count, the chevron or the command off the trailing edge.
        val groupModifier = Modifier.weight(1f, fill = false)

        if (navigates) {
            NavigatingHeader(
                text = text,
                count = count,
                dot = dot,
                actionLabel = actionLabel,
                onAction = requireNotNull(onAction),
                modifier = groupModifier,
            )
        } else {
            PlainHeader(text = text, count = count, dot = dot, modifier = groupModifier)
        }

        if (hasInlineAction) {
            InlineLinkButton(
                label = requireNotNull(actionLabel),
                onClick = requireNotNull(onAction),
                modifier = Modifier.negativePadding(top = InlineActionOverhang, bottom = InlineActionOverhang),
            )
        }
    }
}

/** Shape A. Title + count + chevron, as one button, marked as a heading. */
@Composable
private fun NavigatingHeader(
    text: String,
    count: Int?,
    dot: Boolean,
    actionLabel: String?,
    onAction: () -> Unit,
    modifier: Modifier = Modifier,
) {
    // Spoken as one thing: "Continue watching, See all". The chevron is silent, and the drawn
    // header carries no "See all" word for the label to say twice.
    val spoken = "$text, ${actionLabel ?: Copy.Action.seeAll}"

    Row(
        modifier = modifier
            .negativePadding(top = SectionHeaderPressOverhang, bottom = SectionHeaderPressOverhang)
            .clickable(
                interactionSource = null,
                // The title dips like a link. `textAction` is the one treatment shared by
                // `SectionHeaderPressStyle`, `InlineLinkButtonStyle` and the toast's action — and
                // it is emphatically not a ripple, which would draw a control this header has not
                // got.
                indication = PressStyle.textAction,
                role = Role.Button,
                onClick = onAction,
            )
            .semantics(mergeDescendants = true) {
                heading()
                contentDescription = spoken
            }
            .defaultMinSize(minHeight = minimumTapTarget)
            .padding(vertical = SectionHeaderPressOverhang),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (dot) {
            AccentDot(SectionHeaderDot)
            Gap(SectionHeaderInnerGap)
        }
        SectionTitleText(text, Modifier.weight(1f, fill = false).alignByBaseline())
        if (count != null) {
            Gap(SectionHeaderInnerGap)
            CountLabel(count, Modifier.alignByBaseline())
        }
        Gap(SectionHeaderInnerGap)
        // Centred rather than baseline-aligned: a vector glyph carries no baseline, so Compose
        // would fall back to top-aligning it. On a row whose height IS the title's, the title's
        // optical centre and the row's centre are the same place.
        SymbolIcon(
            symbol = PreviouslyIcons.ChevronRight,
            tint = ThemeColor.textTertiary,
            glyph = SectionChevronGlyph,
            modifier = Modifier.align(Alignment.CenterVertically),
        )
    }
}

/** Shapes B and C. The title is inert; the count keeps its place on the title's baseline. */
@Composable
private fun PlainHeader(
    text: String,
    count: Int?,
    dot: Boolean,
    modifier: Modifier = Modifier,
) {
    Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
        if (dot) {
            AccentDot(SectionHeaderDot)
            Gap(SectionHeaderInnerGap)
        }
        SectionTitleText(
            text = text,
            modifier = Modifier
                .weight(1f, fill = false)
                .alignByBaseline()
                .semantics { heading() },
        )
        if (count != null) {
            // 8, not the navigating header's 6: on iOS these two are siblings in the header's own
            // stack rather than inside the button's tighter one.
            Gap(ThemeSpace.x2)
            CountLabel(count, Modifier.alignByBaseline())
        }
    }
}

/**
 * The title. One line, scaled to [SectionTitleMinimumScale] rather than truncated — the port of
 * `.lineLimit(1).minimumScaleFactor(0.85)`, through the app's one auto-sizing text.
 */
@Composable
private fun SectionTitleText(text: String, modifier: Modifier = Modifier) {
    AutoSizeText(
        text = text,
        style = SectionTitleStyle,
        minScale = SectionTitleMinimumScale,
        modifier = modifier,
        maxLines = 1,
    )
}

/** The count, on the title's baseline. */
@Composable
private fun CountLabel(count: Int, modifier: Modifier = Modifier) {
    BasicText(text = count.toString(), modifier = modifier, style = SectionCountStyle, maxLines = 1)
}

/**
 * Eyebrow / section label: 11-sp caps, +1.0 tracking, uppercase, with an optional 4-dp leading dot
 * that means **newly changed** and nothing else.
 *
 * **Eyebrow only.** Legal uses: [OverArtLabel] over art, a grouped list's header, a sheet label,
 * Schedule's day headers ("TODAY · THU 3 SEP") and its Earlier row. A shelf header is
 * [SectionHeaderRow].
 *
 * @param tint `textSecondary`, one step up from the `textTertiary` it shipped at: the label is the
 *   section's IDENTITY, and at tertiary it was outweighed by its own trailing "See all" — the
 *   utility link read as the header and the header read as a footnote.
 */
@Composable
fun SectionLabel(
    text: String,
    modifier: Modifier = Modifier,
    dot: Boolean = false,
    tint: Color = ThemeColor.textSecondary,
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(SectionHeaderInnerGap),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (dot) AccentDot(SectionLabelDot)
        BasicText(
            text = text.uppercased(),
            style = ThemeType.sectionLabel.copy(color = tint),
            // Nothing truncates at accessibility sizes — the container grows.
            maxLines = if (isAccessibilityTextSize()) 2 else 1,
        )
    }
}

/**
 * An eyebrow that sits ON artwork — "CONTINUE", "NEW EPISODE", "AIRED 10H AGO".
 *
 * Over a photograph, plain tertiary-grey caps are unreadable half the time and washed out the
 * rest. A dark capsule makes it legible over anything and reads as a label rather than as text
 * that happens to be floating.
 *
 * The height is a hard 24 dp and deliberately does **not** grow with the text scale: this is a
 * chip laid on a picture, not a line of copy. Its dot is 5 dp, a size up from [SectionLabel]'s.
 */
@Composable
fun OverArtLabel(
    text: String,
    modifier: Modifier = Modifier,
    dot: Boolean = false,
    tint: Color = ThemeColor.textPrimary,
) {
    Row(
        modifier = modifier
            .height(OverArtLabelHeight)
            .background(ThemeColor.scrimStrong, CircleShape)
            // `border` draws INWARD in Compose, which is what SwiftUI's `strokeBorder` does — and
            // a centred stroke on a capsule renders as a soft smear outside the shape.
            .border(OverArtLabelEdge, ThemeColor.hairline, CircleShape)
            .padding(horizontal = OverArtLabelInset),
        horizontalArrangement = Arrangement.spacedBy(SectionHeaderInnerGap),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (dot) AccentDot(SectionHeaderDot)
        BasicText(
            text = text.uppercased(),
            style = ThemeType.sectionLabel.copy(color = tint),
            maxLines = 1,
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared internals
// ─────────────────────────────────────────────────────────────────────────────

/**
 * A fixed gap between two siblings.
 *
 * Written out rather than reached through `Arrangement.spacedBy` because a header mixes two
 * rhythms — 6 dp inside the button, 8 dp between the title and its count — and because every
 * element that must share a baseline has to stay a DIRECT child of the same row.
 */
@Composable
private fun Gap(width: Dp) {
    Spacer(Modifier.width(width))
}

/** The accent mark. Amber here is STATE ("newly changed"), one of its two legal readings. */
@Composable
private fun AccentDot(diameter: Dp, modifier: Modifier = Modifier) {
    Spacer(modifier.size(diameter).background(ThemeColor.accent, CircleShape))
}



/**
 * The port of SwiftUI's `.textCase(.uppercase)`, which is locale-aware — Kotlin's no-argument
 * `uppercase()` is not (it pins `Locale.ROOT`, which spells a Turkish "i" wrongly).
 */
private fun String.uppercased(): String = uppercase(Locale.getDefault())
