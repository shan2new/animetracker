package com.anitrack.app.ui.control

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.Image
import androidx.compose.foundation.Indication
import androidx.compose.foundation.IndicationNodeFactory
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.InteractionSource
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorProducer
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.node.CompositionLocalConsumerModifierNode
import androidx.compose.ui.node.DelegatableNode
import androidx.compose.ui.node.DrawModifierNode
import androidx.compose.ui.node.currentValueOf
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.anitrack.app.design.ContinuousCornerShape
import com.anitrack.app.design.LocalControlInk
import com.anitrack.app.design.LocalReduceMotion
import com.anitrack.app.design.MaterialSymbol
import com.anitrack.app.design.MotionToken
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.motion
import com.anitrack.app.design.pickMotion
import com.anitrack.app.design.rememberSymbol
import com.anitrack.model.copy.Copy
import kotlinx.coroutines.launch

// =====================================================================================
// BUTTONS, PRESS STYLES AND CHIPS — the port of the button half of
// `ios/Sources/DesignSystem/Primitives.swift` (spec/primitives.md §7).
//
// THE RULE THAT OUTRANKS EVERY OTHER DECISION IN THIS FILE:
//
//   Amber is not an action colour. `ThemeColor.accent` is rationed to MEANING (a real next step)
//   and STATE (today, owned, selected, a committed mark), plus brand and GROUNDS — the primary
//   capsule's ground, the mark ring's fill, an `accentSoft` disc — where the amber is the OBJECT
//   and the ink on it is `onAccent`, so no amber *word* is ever drawn. Every bare tappable word
//   or glyph ("See all", "Clear", "Add", "Done", "Try again") wears `ThemeColor.interactive`,
//   carried through `LocalControlInk`.
//
//   Detail once drew an amber "+ Add" directly above an amber "Episode 14 next"; Library put an
//   amber "See all" over amber "Returns Oct 2" captions. One hue cannot mean "this is what is
//   coming" and "press this".
//
// -------------------------------------------------------------------------------------
// WHAT CHANGED IN THE PORT, AND WHY (fidelity line: port the meaning, render with native means,
// re-tune the numbers)
//
// 1. A SwiftUI `ButtonStyle` becomes a Compose `Indication`.
//    `ButtonStyle.makeBody(configuration)` is "how this control reacts to being pressed", which is
//    precisely what `Indication` is on Android — and `Modifier.clickable(interactionSource,
//    indication)` wires it up as the framework's own mechanism. So the press half of every style
//    is an `IndicationNodeFactory` in `PressStyle`, and the *static* half (ground, ink, height,
//    padding, edge) is the composable that hosts it. Nothing in this app ever gets the Material
//    ripple: it is not suppressed, it is REPLACED, at every call site, by name.
//
// 2. `pressFeedback` is one node, not one modifier per style. Board 11's rule survives verbatim:
//    **Reduce Motion presses in OPACITY (0.72), never in scale.** It is answered once, inside the
//    node, from `LocalReduceMotion`.
//
// 3. The lit top edge is `Modifier.border(ThemeMetrics.hairline, brush, CircleShape)`. Its border draws
//    INWARD, which is what SwiftUI's `strokeBorder` (not `stroke`) does — and the reason iOS uses
//    `strokeBorder` ports exactly: "a centred 1-pt line straddles the capsule's edge and renders
//    as a soft 2-px smear on the outside of the shape."
//
// 4. Targets are 44 dp, not Material's 48. The chips' "32/34-then-44" pattern — a visible capsule
//    of 32 or 34 dp inside a 44-dp target — is reproduced exactly, which is also why
//    `LocalMinimumInteractiveComponentSize` must stay off: M3's 48-dp inflation would silently
//    grow every chip.
//
// 5. No component here fires a haptic. Every primitive that carries an action takes a closure; the
//    SCREEN decides whether that closure also spends a `FeedbackToken`, because the rule is one
//    haptic per transaction and only the screen knows what the transaction is.
// =====================================================================================

// -------------------------------------------------------------------------------------
// The press treatment
// -------------------------------------------------------------------------------------

/**
 * One press treatment, as data. Every style in §7 of the spec is a value of this shape; the node
 * below is the only thing that draws one.
 *
 * @param scale the compression at full press. Applied **only** when Reduce Motion is off — board
 *   11: a reduced-motion press is an opacity change, never a transform.
 * @param pressedAlpha the opacity at full press with Reduce Motion off. `1f` for the styles that
 *   compress instead (the whole `pressFeedback` family); `0.88` for a target that IS a photograph;
 *   `0.6` / `0.55` for the bare text actions, which have no ground to darken.
 * @param reducedAlpha the opacity at full press with Reduce Motion on. `0.72` is the substitute
 *   for a compression; a style that already presses in opacity keeps its own value here, so the
 *   press does not get *louder* for a user who asked for less motion.
 * @param wash a ground painted under (or over) the content while pressed — the row/grouped-row
 *   highlight and the split capsule's half-darkening. Its own alpha is multiplied by the press
 *   progress, so it fades in and out with the animation rather than snapping.
 * @param washShape the wash's silhouette. **It must match the surface being pressed**: left at a
 *   16-dp default, a pressed 24-dp Focus card paints a 16-dp highlight inside its own corners —
 *   a 4-dp sliver of un-highlighted card at each corner, visible on every single tap of the app's
 *   most important control.
 * @param washOnTop `true` reproduces SwiftUI's `.overlay` (the row highlight sits over the row's
 *   own artwork and text); `false` reproduces `.background`.
 * @param animated `false` is the hard opacity switch — `TertiaryButtonStyle2` is the one style in
 *   the app with no animation on its press, and that is deliberate.
 * @param releaseSettles `true` presses in on `uiPress` (90 ms) and releases on the `uiMicro`
 *   spring. The rows do this; a ground that snapped on and off in one frame, in both directions,
 *   on the densest screens in the app, is what it replaced.
 */
@Immutable
internal data class PressTreatment(
    val scale: Float = 1f,
    val pressedAlpha: Float = 1f,
    val reducedAlpha: Float = 0.72f,
    val wash: Color = Color.Transparent,
    val washShape: Shape = RectangleShape,
    val washOnTop: Boolean = false,
    val animated: Boolean = true,
    val releaseSettles: Boolean = false,
)

/**
 * **The app's press feedback, as an `Indication`.** Hand one to `Modifier.clickable`:
 *
 * ```
 * Modifier.clickable(
 *     interactionSource = null,           // the node makes its own; hoist one only when the
 *     indication = PressStyle.control,    // composable also needs `collectIsPressedAsState`
 *     role = Role.Button,
 *     onClick = onClick,
 * )
 * ```
 *
 * Passing one of these is the ONLY sanctioned way to make something tappable in this app. A
 * `clickable` with no `indication` argument falls through to `LocalIndication`, which with
 * material3 on the classpath is the Material ripple — a spreading grey circle this design does not
 * use anywhere.
 */
@Stable
object PressStyle {

    /**
     * The default: compression to 0.985, opacity 0.72 under Reduce Motion.
     *
     * Serves `PrimaryButtonStyle2`, `SecondaryButtonStyle2`, both chips and
     * `CompactActionButtonStyle` — every filled or outlined control with a ground of its own.
     */
    val control: Indication = PressIndication(PressTreatment(scale = 0.985f))

    /**
     * The round mark control (`MarkPressStyle`): **compression only, no rounded-rect wash behind a
     * circle**. Identical treatment to [control]; it is named separately because that is the whole
     * point — the episode-row rings, Schedule's rings and the Search add badge are the same shape
     * and had no press state at all before there was one name for it.
     */
    val mark: Indication = control

    /**
     * A target that IS a photograph — the Today hero, the account disc, the recap card,
     * `BannerCard`. Art dips in brightness (0.88) and compresses a hair (0.99).
     *
     * It may not take [row]: a `surfacePressed` wash over artwork is a grey film over someone's
     * illustration.
     */
    val overArt: Indication = PressIndication(
        PressTreatment(scale = 0.99f, pressedAlpha = 0.88f)
    )

    /**
     * `TertiaryButtonStyle2` — a bare word in a 44-dp box, no container. A hard opacity switch with
     * **no animation**; it is the only style in the app like that, and that is preserved.
     */
    val tertiary: Indication = PressIndication(
        PressTreatment(pressedAlpha = 0.6f, reducedAlpha = 0.6f, animated = false)
    )

    /**
     * The bare inline text action — "See all", "Read more", "Clear", "Sync now", "Details".
     *
     * One treatment for `InlineLinkButtonStyle`, `SectionHeaderPressStyle` and the toast's own
     * action: all three are a word with no ground, and all three dim to 0.55 on `uiPress`.
     */
    val textAction: Indication = PressIndication(
        PressTreatment(pressedAlpha = 0.55f, reducedAlpha = 0.55f)
    )

    /**
     * One half of the split mark capsule (`SplitHalfStyle`): the press darkens **only the half
     * under the finger**, inside the shared capsule, so the boundary the divider promises is real.
     */
    val splitHalf: Indication = PressIndication(
        PressTreatment(wash = ThemeColor.accentPressed)
    )

    /**
     * A row inside a grouped list (`GroupedRowPressStyle`): the pressed ground fills the row's full
     * width, because the row's own plate already provides the corners.
     */
    val groupedRow: Indication = PressIndication(
        PressTreatment(wash = ThemeColor.surfacePressed, releaseSettles = true)
    )

    /**
     * A content card or media row (`RowPressStyle`): a `surfacePressed` wash at 60 % over the row,
     * plus a 0.992 compression.
     *
     * **Pass the radius of the surface being pressed.** `ShelfCard` passes its slot's radius; a
     * 24-dp Focus card passes 24.
     */
    fun row(radius: Dp = ThemeRadius.row): Indication = PressIndication(
        PressTreatment(
            scale = 0.992f,
            wash = ThemeColor.surfacePressed.copy(alpha = 0.6f),
            washShape = ContinuousCornerShape(radius),
            washOnTop = true,
            releaseSettles = true,
        )
    )
}

/**
 * The `Indication` half of [PressStyle]. Not a data class: `IndicationNodeFactory` declares
 * `equals`/`hashCode` abstract, and Compose reuses a node only when two factories compare equal —
 * so both are written out rather than left to code generation.
 */
@Immutable
private class PressIndication(private val treatment: PressTreatment) : IndicationNodeFactory {

    override fun create(interactionSource: InteractionSource): DelegatableNode =
        PressIndicationNode(interactionSource, treatment)

    override fun equals(other: Any?): Boolean =
        other is PressIndication && other.treatment == treatment

    override fun hashCode(): Int = treatment.hashCode()
}

/**
 * The node that actually draws a press.
 *
 * `progress` is an `Animatable` read **inside `draw()`**, never in a composable body: a press
 * invalidates this one node's draw pass and nothing else. That is the same discipline the scroll
 * offset is held to — a value that changes every frame may never re-run a screen's body.
 */
private class PressIndicationNode(
    private val interactionSource: InteractionSource,
    private val treatment: PressTreatment,
) : Modifier.Node(), DrawModifierNode, CompositionLocalConsumerModifierNode {

    private val progress = Animatable(0f)

    /** Reused so a press does not allocate a `Paint` per frame. */
    private val layerPaint = Paint()

    override fun onAttach() {
        val scope = coroutineScope
        scope.launch {
            // Presses can nest (a second pointer down before the first is released), so the state
            // is a count, not a boolean — releasing one finger must not un-press the control.
            var presses = 0
            interactionSource.interactions.collect { interaction ->
                when (interaction) {
                    is PressInteraction.Press -> presses++
                    is PressInteraction.Release -> presses--
                    is PressInteraction.Cancel -> presses--
                    else -> return@collect
                }
                val target = if (presses > 0) 1f else 0f
                if (target != progress.targetValue) {
                    // A separate coroutine: animating inside `collect` would suspend the
                    // collection and swallow the release that arrives mid-animation. `Animatable`
                    // cancels its own in-flight animation, so no job bookkeeping is needed.
                    scope.launch { animatePress(target) }
                }
            }
        }
    }

    private suspend fun animatePress(target: Float) {
        if (!treatment.animated) {
            progress.snapTo(target)
            return
        }
        val reduced = reduceMotion()
        // Press in fast; release either equally fast or, for the rows, on the `uiMicro` spring.
        val token =
            if (target >= 1f || !treatment.releaseSettles) MotionToken.UI_PRESS else MotionToken.UI_MICRO
        progress.animateTo(target, pickMotion(token, reduced))
    }

    override fun ContentDrawScope.draw() {
        val pressed = progress.value
        if (pressed <= 0f) {
            drawContent()
            return
        }
        val reduced = reduceMotion()
        val targetAlpha = if (reduced) treatment.reducedAlpha else treatment.pressedAlpha
        val alpha = 1f - (1f - targetAlpha) * pressed
        val compression = if (reduced) 1f else 1f - (1f - treatment.scale) * pressed

        if (alpha >= 1f) {
            drawPressed(compression, pressed)
        } else {
            // An offscreen layer is the only way to fade the CONTENT (not just this node's own
            // drawing) from inside a draw modifier. It exists for the length of a press on one
            // control, which is nothing; the alternative — a `graphicsLayer` hoisted to the call
            // site — would put the treatment back into every screen, which is what this file
            // exists to prevent.
            layerPaint.alpha = alpha
            drawIntoCanvas { canvas -> canvas.saveLayer(Rect(Offset.Zero, size), layerPaint) }
            drawPressed(compression, pressed)
            drawIntoCanvas { canvas -> canvas.restore() }
        }
    }

    /** Wash and content together inside the compression, so the highlight tracks the corners. */
    private fun ContentDrawScope.drawPressed(compression: Float, pressed: Float) {
        scale(compression) {
            if (!treatment.washOnTop) drawWash(pressed)
            this@drawPressed.drawContent()
            if (treatment.washOnTop) drawWash(pressed)
        }
    }

    private fun DrawScope.drawWash(pressed: Float) {
        if (treatment.wash == Color.Transparent) return
        val outline = treatment.washShape.createOutline(size, layoutDirection, this)
        // `alpha` multiplies the colour's own alpha, so `surfacePressed @ 0.6` fades 0 → 0.6.
        drawOutline(outline = outline, color = treatment.wash, alpha = pressed)
    }

    private fun reduceMotion(): Boolean = isAttached && currentValueOf(LocalReduceMotion)
}

// -------------------------------------------------------------------------------------
// Shared control furniture
// -------------------------------------------------------------------------------------

/**
 * **The lit top edge every filled control in this app carries.**
 *
 * "Flat #F0A24E across 48×376 pt is a swatch of orange; one 22 %-white hairline along the top,
 * dead by the vertical centre, is what makes it read as a physical, pressable object." The
 * gradient must die by 0.5 — a full-height ramp is a bevel, and a ring of uniform grey is the
 * thing this replaces.
 */
internal val controlSheen: Brush = Brush.verticalGradient(
    0f to ThemeColor.controlSheen,
    0.5f to Color.Transparent,
)

/**
 * An SF Symbol point size, re-tuned to the Material Symbol box that replaces it.
 *
 * `Image(systemName:).font(.system(size: S))` draws roughly S points of ink. A Material Symbol is
 * authored as ~20 units of ink inside a 24-unit box, so a box of S renders only ~0.83 S of ink and
 * every glyph in the app would arrive a size small beside type that did not change. The box is
 * therefore 24/20 × the iOS point size.
 *
 * Per the fidelity line the number is chosen so the glyph READS the same, not so it measures the
 * same; it is a design-review number, and this is the one place it changes.
 */
internal fun materialGlyphBox(sfPointSize: Dp): Dp = sfPointSize * 1.25f

/**
 * **A vendored Material Symbol at its iOS point size, in a chosen ink.** The one glyph drawer.
 *
 * Deliberately not material3's `Icon`: that reads `LocalContentColor` from a Material theme this
 * app never installs, so an omitted tint is `Color.Black` on the #09090B canvas — an invisible
 * glyph rather than a wrong one — and no screen may see an M3 type at all.
 *
 * It lives here because the SF→Material box conversion is [materialGlyphBox]'s, and a glyph drawn
 * anywhere else in the app would be a second place that ratio could be spelled. Always decorative:
 * the row, header or card around a glyph is what says what it means.
 *
 * @param glyph the **iOS point size** of the ink; the drawn box is [materialGlyphBox] of it.
 */
@Composable
internal fun SymbolIcon(
    symbol: MaterialSymbol,
    tint: Color,
    glyph: Dp,
    modifier: Modifier = Modifier,
) {
    Image(
        imageVector = rememberSymbol(symbol),
        contentDescription = null,
        modifier = modifier.size(materialGlyphBox(glyph)),
        colorFilter = ColorFilter.tint(tint),
    )
}

/** Every tappable thing in this app is at least this. Material's own 48 is deliberately not used. */
internal val minimumTapTarget = 44.dp

/** The primary capsule's height. Taller than the rest: it is the screen's one committed action. */
private val primaryCapsuleHeight = 48.dp

/**
 * A capsule's side padding. Not a [ThemeSpace] step on purpose — 16 crowds the label against the
 * curve and 20 makes a two-word capsule read as a banner.
 */
private val capsulePadding = 18.dp

/** The scope chip's own side padding, one step wider than its 12-dp filter sibling. */
private val scopeChipPadding = 14.dp

/** The active filter chip's visible capsule. The TARGET around it is [minimumTapTarget]. */
private val filterChipHeight = 32.dp

/** The scope chip's visible capsule — a step taller than a filter chip, because it is a choice. */
private val scopeChipHeight = 34.dp

/** Between the criterion and its ×. */
private val chipGlyphGap = 5.dp

/** The × inside a filter chip, at its iOS point size. */
private val chipRemoveGlyph = 10.dp

/** The inline link's vertical padding: a 13-dp footnote needs this much to reach a real target. */
private val inlineLinkVerticalPadding = 14.dp

/**
 * [InlineLinkButton]'s own padding, published so a caller can CANCEL it.
 *
 * The control holds a 44-dp target with padding it draws nothing in, which is right for the target
 * and wrong for the layout: the word then starts 12 dp inside the gutter, and a footnote row it sits
 * in inflates from 28 dp to 44. Every caller that cares pulls the padding back with
 * `Modifier.negativePadding(...)` — and the number they pull back must be the number the control
 * spends, which is why it is here and not typed at a call site. It was typed at five of them, in
 * four spellings (`INLINE_LINK_INSET`, `InlineActionOverhang`, `inlineActionOverhang`, and a bare
 * `12.dp` twice in Detail).
 */
object InlineLink {

    /** The side padding. Cancel it so the link's first glyph lands on the gutter. */
    val sideOverhang: Dp = ThemeSpace.x3

    /**
     * The vertical padding. A caller cancels as much of it as its row can spare — a header row
     * cancels all of it; a paragraph with air around it cancels only [readingLift].
     */
    val verticalOverhang: Dp = inlineLinkVerticalPadding

    /** What a link inside a block of prose pulls back: enough to sit close, not enough to touch. */
    val readingLift: Dp = ThemeSpace.x1
}

/** The disabled primary capsule. Dim enough to be inert, not so dim it leaves the layout. */
private const val DISABLED_ALPHA = 0.38f

// -------------------------------------------------------------------------------------
// The buttons
// -------------------------------------------------------------------------------------

/**
 * **The amber capsule** (`PrimaryButtonStyle2`) — the one committed action on a surface.
 *
 * Amber here is a GROUND, not an action colour: the capsule is the object and the ink on it is
 * `onAccent`, so no amber *word* is drawn and the rule survives intact. A recovery ("Try again")
 * is **not** this button — it is [SecondaryButton]. Amber is for a real next step ("Add a show").
 *
 * @param hugging `true` makes the capsule wrap its label instead of filling its column — the
 *   `.fixedSize(horizontal:)` an empty state applies ("hugging, never a banner"). The caller drops
 *   it at accessibility text sizes so the label may take the full column and wrap.
 */
@Composable
fun PrimaryButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    hugging: Boolean = false,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val ground by animateColorAsState(
        targetValue = if (pressed) ThemeColor.accentPressed else ThemeColor.accent,
        animationSpec = motion(MotionToken.UI_PRESS),
        label = "primaryGround",
    )
    CapsuleButton(
        label = label,
        style = ThemeType.button,
        ink = ThemeColor.onAccent,
        ground = ground,
        edge = controlSheen,
        minHeight = primaryCapsuleHeight,
        modifier = modifier.alpha(if (enabled) 1f else DISABLED_ALPHA),
        hugging = hugging,
        enabled = enabled,
        interaction = interaction,
        onClick = onClick,
    )
}

/**
 * **The quiet capsule** (`SecondaryButtonStyle2`) — a neutral floating ground with a
 * full-perimeter `stroke` edge. A CONTROL is allowed a full-perimeter edge; a container is not.
 *
 * This is what a recovery wears: "Try again" retries a fetch, and retrying a fetch is not a next
 * step worth the app's one accent.
 */
@Composable
fun SecondaryButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    hugging: Boolean = false,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val ground by animateColorAsState(
        targetValue = if (pressed) ThemeColor.surfacePressed else ThemeColor.surfaceFloating,
        animationSpec = motion(MotionToken.UI_PRESS),
        label = "secondaryGround",
    )
    CapsuleButton(
        label = label,
        style = ThemeType.button,
        ink = ThemeColor.textPrimary,
        ground = ground,
        edge = SolidColor(ThemeColor.stroke),
        minHeight = minimumTapTarget,
        modifier = modifier,
        hugging = hugging,
        enabled = enabled,
        interaction = interaction,
        onClick = onClick,
    )
}

/** The shared capsule body. Nothing here is decided per call site except what it is handed. */
@Composable
private fun CapsuleButton(
    label: String,
    style: TextStyle,
    ink: Color,
    ground: Color,
    edge: Brush,
    minHeight: Dp,
    modifier: Modifier,
    hugging: Boolean,
    enabled: Boolean,
    interaction: MutableInteractionSource,
    onClick: () -> Unit,
) {
    Box(
        modifier
            .then(if (hugging) Modifier else Modifier.fillMaxWidth())
            .defaultMinSize(minHeight = minHeight)
            // Before the ground, so the press compression scales the capsule and its lit edge with
            // the label rather than shrinking the label inside a stationary pill.
            .clickable(
                interactionSource = interaction,
                indication = PressStyle.control,
                enabled = enabled,
                role = Role.Button,
                onClick = onClick,
            )
            .clip(CircleShape)
            .background(ground)
            .border(ThemeMetrics.hairline, edge, CircleShape)
            .padding(horizontal = capsulePadding),
        contentAlignment = Alignment.Center,
    ) {
        BasicText(text = label, style = style, color = ColorProducer { ink })
    }
}

/**
 * **A bare word in a 44-dp box** (`TertiaryButtonStyle2`) — no ground, no edge, `interactive` ink.
 *
 * The affordance is carried by position, semibold weight and the target, exactly as a list row
 * carries its own. Never amber: see the file header.
 */
@Composable
fun TertiaryButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    destructive: Boolean = false,
) {
    val ink = if (destructive) ThemeColor.destructive else LocalControlInk.current
    Box(
        modifier
            .clickable(
                interactionSource = null,
                indication = PressStyle.tertiary,
                enabled = enabled,
                role = Role.Button,
                onClick = onClick,
            )
            .defaultMinSize(minWidth = minimumTapTarget, minHeight = minimumTapTarget),
        contentAlignment = Alignment.Center,
    ) {
        BasicText(text = label, style = ThemeType.button, color = ColorProducer { ink })
    }
}

/**
 * **An inline text action beside a label** (`InlineLinkButtonStyle`) — "See all", "Read more",
 * "Clear", "Sync now", Detail's "Details".
 *
 * `listAction` (Outfit SemiBold 13) rather than `button` (16): a 16-pt semibold word beside an
 * 11-pt grey label wins a fight it should lose.
 *
 * The padding is **symmetric and comes before the target floor**: a footnote cap-height is ~13 dp,
 * so 14 dp of vertical padding gives a comfortable target, and leading-only padding would end the
 * hit area at the last glyph — the user would have to hit the WORD. True at every type size.
 *
 * @param onClickLabel what a screen reader says the tap DOES ("Retry loading"), where the label
 *   alone does not — the port of the iOS accessibility hint on the same control.
 */
@Composable
fun InlineLinkButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    destructive: Boolean = false,
    onClickLabel: String? = null,
) {
    val ink = if (destructive) ThemeColor.destructive else LocalControlInk.current
    Box(
        modifier
            .clickable(
                interactionSource = null,
                indication = PressStyle.textAction,
                enabled = enabled,
                onClickLabel = onClickLabel,
                role = Role.Button,
                onClick = onClick,
            )
            .defaultMinSize(minHeight = minimumTapTarget)
            .padding(vertical = InlineLink.verticalOverhang, horizontal = InlineLink.sideOverhang),
        contentAlignment = Alignment.Center,
    ) {
        BasicText(text = label, style = ThemeType.listAction, color = ColorProducer { ink })
    }
}

// -------------------------------------------------------------------------------------
// Chips
//
// The two chip styles are deliberately different objects. An ACTIVE filter is a soft amber wash
// with amber ink and an ×; a scope CHOICE is a solid amber capsule with `onAccent` ink. Four solid
// amber capsules above a list is louder than anything on the screen they are filtering.
//
// Both use the 32/34-then-44 pattern: the visible capsule is 32 or 34 dp tall and the TARGET is
// 44. Do not inflate the capsule to reach the target.
// -------------------------------------------------------------------------------------

/**
 * **An active, removable filter chip** (`FilterChipStyle` + `FilterChipLabel`).
 *
 * The amber here is STATE — this filter is on — and it is a GROUND at 14 %, with the criterion in
 * amber ink on it. Tapping removes the filter, which is why the whole chip is the target and why
 * the × is decoration rather than a second control.
 */
@Composable
fun FilterChip(
    text: String,
    onRemove: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val ground by animateColorAsState(
        targetValue = if (pressed) ThemeColor.surfacePressed else ThemeColor.accentSoft,
        animationSpec = motion(MotionToken.UI_PRESS),
        label = "filterChipGround",
    )
    val spoken = Copy.Accessibility.removeFilter(text)
    Box(
        modifier
            .clickable(
                interactionSource = interaction,
                indication = PressStyle.control,
                role = Role.Button,
                onClick = onRemove,
            )
            // The chip says what it is and what tapping it does, in one utterance; TalkBack would
            // otherwise read the criterion and leave the × to be guessed at.
            .semantics(mergeDescendants = true) { contentDescription = spoken }
            .defaultMinSize(minHeight = minimumTapTarget),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            modifier = Modifier
                .clip(CircleShape)
                .background(ground)
                .defaultMinSize(minHeight = filterChipHeight)
                .padding(horizontal = ThemeSpace.x3),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(chipGlyphGap),
        ) {
            BasicText(
                text = text,
                style = ThemeType.metadataEmphasis,
                maxLines = 1,
                color = ColorProducer { ThemeColor.accent },
            )
            Image(
                imageVector = rememberSymbol(PreviouslyIcons.Close),
                contentDescription = null,
                modifier = Modifier.size(materialGlyphBox(chipRemoveGlyph)),
                colorFilter = ColorFilter.tint(ThemeColor.accent),
            )
        }
    }
}

/**
 * **A primary choice** (`ChipButtonStyle`) — a search scope, a "Reset" on a filter row.
 *
 * **Unselected chips carry NO stroke.** Search shipped a grey-outlined pill for every scope and
 * every recent query, so eight outlined objects competed with the three posters underneath them.
 * Tone alone separates an unselected chip from the canvas; the selected one is the only chip
 * allowed to use colour, and its selection is legal amber because a selected value is STATE.
 */
@Composable
fun ChipButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    selected: Boolean = false,
) {
    val isSelected = selected
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val ground by animateColorAsState(
        targetValue = when {
            isSelected && pressed -> ThemeColor.accentPressed
            isSelected -> ThemeColor.accent
            pressed -> ThemeColor.surfacePressed
            else -> ThemeColor.surfaceRaised
        },
        animationSpec = motion(MotionToken.UI_PRESS),
        label = "chipGround",
    )
    val ink = if (isSelected) ThemeColor.onAccent else ThemeColor.textSecondary
    Box(
        modifier
            .clickable(
                interactionSource = interaction,
                indication = PressStyle.control,
                role = Role.Button,
                onClick = onClick,
            )
            // iOS states the selection in colour alone here. TalkBack cannot see amber, so the
            // state is spoken as well — the second carrier the design should always have had.
            .semantics { this.selected = isSelected }
            .defaultMinSize(minHeight = minimumTapTarget),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .clip(CircleShape)
                .background(ground)
                .then(
                    // The lit top edge belongs to a FILLED control, so only the selected chip has
                    // one. An unselected chip is separated by tone and by nothing else.
                    if (isSelected) Modifier.border(ThemeMetrics.hairline, controlSheen, CircleShape) else Modifier
                )
                .defaultMinSize(minHeight = scopeChipHeight)
                .padding(horizontal = scopeChipPadding),
            contentAlignment = Alignment.Center,
        ) {
            BasicText(
                text = text,
                style = ThemeType.metadataEmphasis,
                maxLines = 1,
                color = ColorProducer { ink },
            )
        }
    }
}
