package com.anitrack.app.ui.control

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
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
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.DropdownMenu
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorProducer
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.anitrack.app.design.AppFont
import com.anitrack.app.design.ContinuousCornerShape
import com.anitrack.app.design.LocalControlInk
import com.anitrack.app.design.LocalReduceMotion
import com.anitrack.app.design.MotionToken
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.PreviouslyMaterialBridge
import com.anitrack.app.design.ShadowToken
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeMotion
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.motion
import com.anitrack.app.design.rememberSymbol
import com.anitrack.model.copy.Copy
import kotlin.math.min
import kotlin.math.roundToInt

// =====================================================================================
// THE MARK — `DrawnCheck`, `MarkRing`, `MarkSplitButton`.
//
// The port of the mark half of `ios/Sources/DesignSystem/Primitives.swift`
// (spec/primitives.md §6.2–§6.4). This is the app's core action: everything else on every screen
// exists to bring the reader to one of these three controls.
//
// ONE VERB, ONE CONTROL GRAMMAR. The shipped build had four dialects, two of which used the same
// glyph to mean opposite things. From here, in a 44-dp target around a 22-dp ring:
//
//   hollow `markRingIdle` ring       unmarked, tappable — an INVITATION
//   accent fill + `onAccent` check   the commit frame
//   bare `textTertiary` check        settled, history
//
// The idle stroke is `markRingIdle` (white 34 %) and NOT `strokeStrong` (white 20 %): at 1.5 dp
// over a dark poster, `strokeStrong` read as a disabled ghost and made the app's core control the
// least visible element on its own row.
//
// NO COMPONENT HERE FIRES A HAPTIC. Each takes a closure; the screen decides whether that closure
// also spends a `FeedbackToken`, because the rule is at most one haptic per transaction and only
// the screen knows where the transaction ends.
// =====================================================================================

// -------------------------------------------------------------------------------------
// DrawnCheck
// -------------------------------------------------------------------------------------

/**
 * **The check DRAWS.**
 *
 * Nowhere in the shipped build did it: every tick was an opacity crossfade or a scale pop, so the
 * one moment the product exists to deliver had no signature motion. The mark is masked
 * left-to-right as it lands, which is what a hand-drawn tick does — and under Reduce Motion it is
 * simply there, at full width, with no animation to suppress.
 *
 * ### The rule that is stated twice in the source, and must survive the port
 *
 * `DrawnCheck` must be **mounted unconditionally**. A conditional insert hands the framework an
 * implicit fade *on top of* the mask, and the signature motion renders as a smear. Collapse the
 * host to zero width instead — [MarkSplitButton] does exactly that. **Nothing else may touch this
 * glyph's opacity.**
 *
 * @param size the iOS point size of the glyph; the drawn box is [materialGlyphBox] of it.
 */
@Composable
fun DrawnCheck(
    on: Boolean,
    modifier: Modifier = Modifier,
    size: Dp = drawnCheckDefaultSize,
    tint: Color = ThemeColor.onAccent,
) {
    val reduceMotion = LocalReduceMotion.current
    // Seeded from `on`, which is the port of `onChange(of: on, initial: true)`: a check that is
    // already landed when the row scrolls into view is simply there, not re-drawn.
    val progress = remember { Animatable(if (on) 1f else 0f) }
    LaunchedEffect(on, reduceMotion) {
        when {
            !on -> progress.snapTo(0f)
            reduceMotion -> progress.snapTo(1f)
            else -> progress.animateTo(1f, ThemeMotion.uiMicro())
        }
    }
    Image(
        imageVector = rememberSymbol(PreviouslyIcons.Check),
        contentDescription = null,
        modifier = modifier
            .size(materialGlyphBox(size))
            // The mask IS the animation: a leading-aligned clip whose right edge travels across
            // the glyph. Read in the DRAW phase, so landing a tick invalidates one node's drawing
            // and recomposes nothing. (`size` inside this lambda is the DrawScope's, not the
            // parameter above.)
            .drawWithContent {
                clipRect(right = this.size.width * progress.value) {
                    this@drawWithContent.drawContent()
                }
            }
            // The row's text is 8 dp away and says the same thing; a tick spoken twice is noise.
            .clearAndSetSemantics {},
        colorFilter = ColorFilter.tint(tint),
    )
}

/** The tick's default. `MarkRing` draws a smaller one inside its 22-dp ring. */
private val drawnCheckDefaultSize = 14.dp

// -------------------------------------------------------------------------------------
// MarkRing
// -------------------------------------------------------------------------------------

/**
 * How loudly the marked state is drawn. **The geometry, the target and the motion are identical in
 * all three — only the ink changes**, so there is still exactly ONE mark control in the app.
 */
enum class MarkRingStyle {

    /**
     * Accent fill, `onAccent` check — the louder form, for a control that stands alone. Nothing
     * currently mounts it: the capsule CTAs carry the filled weight now.
     */
    Filled,

    /**
     * Accent ring, accent check, no fill. For a dense repeating list, where twenty filled amber
     * discs down one column would turn a rhythm into a scoreboard. Schedule's airing cards.
     */
    Quiet,

    /**
     * The marked state is a bare tertiary check and the ring is gone. For the episode list, where
     * [Quiet] still put eleven amber rings down one column: **history is quiet, and amber goes to
     * the ONE ring that is a next step** (`lead`).
     */
    Settled,
}

/**
 * **The round mark control**: a 44-dp target holding a 22-dp ring.
 *
 * @param marked whether the write has committed.
 * @param lead the unmarked ring is the next step — accent ring and accent numeral, the only amber
 *   in a settled column.
 * @param episode the episode this tap will write, drawn inside the idle ring. The unmarked control
 *   used to be a bare hairline circle — the app's core action, with no visible object and barely
 *   any ink. With a numeral inside, the ring says exactly what committing it means. Rows with no
 *   single episode (or no room) pass `null` and keep the plain ring.
 * @param label what TalkBack reads in the unmarked state.
 * @param markedLabel what it reads once marked; defaults to "Complete".
 * @param stateDescription the port of iOS's `accessibilityValue` — Detail's episode rows pass
 *   "Watched" / "Not watched". A parameter rather than a caller-applied modifier so it lands on
 *   THIS node: an outer `Modifier.semantics` would publish a second accessibility element beside
 *   the ring instead of describing it.
 * @param actionHint the port of `accessibilityHint` — "Marks as watched" / "Marks as unwatched".
 *   TalkBack reads it as "double tap to <hint>".
 */
@Composable
fun MarkRing(
    marked: Boolean,
    onMark: () -> Unit,
    modifier: Modifier = Modifier,
    style: MarkRingStyle = MarkRingStyle.Filled,
    lead: Boolean = false,
    episode: Int? = null,
    label: String = Copy.Action.markAsWatched,
    markedLabel: String? = null,
    stateDescription: String? = null,
    actionHint: String? = null,
    enabled: Boolean = true,
) {
    val fill = if (marked && style == MarkRingStyle.Filled) ThemeColor.accent else Color.Transparent
    val ring = when {
        !marked -> if (lead) ThemeColor.accent else ThemeColor.markRingIdle
        style == MarkRingStyle.Quiet -> ThemeColor.accent
        else -> Color.Transparent
    }
    val ink = when (style) {
        MarkRingStyle.Filled -> ThemeColor.onAccent
        MarkRingStyle.Quiet -> ThemeColor.accent
        MarkRingStyle.Settled -> ThemeColor.textTertiary
    }

    val fillColor = animateColorAsState(
        targetValue = fill,
        animationSpec = motion(MotionToken.UI_MICRO),
        label = "markRingFill",
    )
    val ringColor = animateColorAsState(
        targetValue = ring,
        animationSpec = motion(MotionToken.UI_MICRO),
        label = "markRingStroke",
    )
    // The numeral's fade is the port of `.transition(.opacity)` inside `.animation(value: marked)`.
    // It is an ALPHA on a mounted glyph, never a conditional insert — same reason as `DrawnCheck`.
    val numeralAlpha = animateFloatAsState(
        targetValue = if (marked) 0f else 1f,
        animationSpec = motion(MotionToken.UI_MICRO),
        label = "markRingNumeral",
    )

    val spoken = if (marked) (markedLabel ?: Copy.Accessibility.complete) else label
    // Both are copied into locals whose names do NOT collide with the semantics receiver's own
    // properties: inside a `semantics { }` block an unqualified `stateDescription` resolves to the
    // receiver's write-only property, and reading one of those throws at runtime.
    val spokenState = stateDescription
    val spokenHint = actionHint

    Box(
        modifier
            // iOS shapes the hit area with `contentShape(Circle())` purely to make the whole 44-pt
            // box tappable rather than only the drawn ring; Compose hit-tests the layout bounds, so
            // the target is a 44-dp square — slightly more forgiving at the corners, never less.
            .size(markRingTarget)
            .clickable(
                interactionSource = null,
                indication = PressStyle.mark,
                enabled = enabled,
                role = Role.Button,
                onClick = onMark,
            )
            .semantics(mergeDescendants = true) {
                contentDescription = spoken
                this.selected = marked
                if (spokenState != null) this.stateDescription = spokenState
                if (spokenHint != null) onClick(label = spokenHint) { onMark(); true }
            },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(markRingDiameter)
                .drawBehind {
                    drawCircle(color = fillColor.value)
                    // `strokeBorder`, not `stroke`: the line sits fully INSIDE the 22-dp circle, so
                    // a ring and a filled disc occupy exactly the same 22 dp and the two states do
                    // not jump by a pixel as one becomes the other.
                    val width = markRingStroke.toPx()
                    drawCircle(
                        color = ringColor.value,
                        radius = this.size.minDimension / 2f - width / 2f,
                        style = Stroke(width),
                    )
                }
        )
        if (episode != null && episode < markRingNumeralCeiling) {
            BasicText(
                text = episode.toString(),
                style = markRingNumeralStyle(episode),
                modifier = Modifier.graphicsLayer { alpha = numeralAlpha.value },
                color = ColorProducer {
                    if (lead) ThemeColor.accent else ThemeColor.textSecondary
                },
            )
        }
        // Mounted unconditionally. A conditional insert re-creates `DrawnCheck` and hands the
        // framework an implicit fade ON TOP of the mask, so the app's signature motion renders as
        // a smear instead of a stroke.
        DrawnCheck(on = marked, size = markRingCheckSize, tint = ink)
    }
}

/** 44 dp. The same floor every tappable thing in this app answers to. */
private val markRingTarget = minimumTapTarget

/** The drawn ring. Big enough to hold a two-digit episode number and still read as a control. */
private val markRingDiameter = 22.dp

private val markRingStroke = 1.5.dp

/** The tick inside the ring, two points down from [DrawnCheck]'s own default. */
private val markRingCheckSize = 12.dp

/**
 * Above this the numeral is dropped rather than shrunk further: One Piece's episode 1128 at 7 sp
 * inside a 22-dp ring is a smudge, and the ring alone still says what the tap does.
 */
private const val markRingNumeralCeiling = 1000

/**
 * The numeral inside an idle ring.
 *
 * Built here rather than added to `ThemeType` because it is the only type in the app whose size is
 * a function of its content — two digits fit at 9 sp, three only at 7 — and iOS declares it at the
 * call site for exactly that reason. The ANNOTATING face with tabular figures, per the type rule:
 * numerals live there so a ring does not re-flow as a season counts up. SF semibold has no Roboto
 * master, so this is Medium (see the note in `Type.kt`).
 */
private fun markRingNumeralStyle(episode: Int): TextStyle = TextStyle(
    fontFamily = AppFont.annotation,
    fontWeight = FontWeight.Medium,
    fontSize = if (episode < 100) 9.sp else 7.sp,
    lineHeight = if (episode < 100) 11.sp else 9.sp,
    fontFeatureSettings = "tnum",
)

// -------------------------------------------------------------------------------------
// MarkSplitButton
// -------------------------------------------------------------------------------------

/**
 * **"Mark as watched" with the batch options behind a real split.**
 *
 * One capsule containing two 44-dp targets separated by a hairline: tapping the label marks,
 * tapping the chevron opens the batch menu. It was lifted out of Today because Detail — the
 * surface where a user actually catches up six episodes — had the batch behind a chevron-less
 * long-press only a power user would find.
 *
 * The label does **not** name its episode: the hero and Detail's state block both state exactly
 * ONE episode directly above this capsule, so the number the label used to repeat is no longer
 * disambiguating anything. VoiceOver still hears it. The committed form keeps its number —
 * "Episode 12 watched" is a receipt.
 *
 * @param episode the episode a plain tap writes.
 * @param committed whether that write has landed. A committed capsule keeps its shape and drops to
 *   a soft amber tint with accent ink: a past-tense fact does not get the app's one primary colour.
 * @param behind how many episodes are unwatched from [episode] on. The menu exists only above 1.
 * @param title the show, named as the menu's section header — with two number-carrying commands
 *   floating free, the reader had to reconstruct whose episodes "2–5" are.
 */
@Composable
fun MarkSplitButton(
    episode: Int,
    committed: Boolean,
    behind: Int,
    title: String,
    onMark: () -> Unit,
    onMarkThrough: (Int) -> Unit,
    onMarkAll: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val showsMenu = behind > 1
    var menuOpen by remember { mutableStateOf(false) }
    // A menu whose commands have just been satisfied is not a menu. iOS makes the chevron
    // non-hit-testable at this moment; on Android the popup is a window of its own and has to be
    // dismissed explicitly, or it outlives the state that justified it.
    LaunchedEffect(committed) { if (committed) menuOpen = false }

    val ground by animateColorAsState(
        targetValue = if (committed) {
            ThemeColor.accent.copy(alpha = committedGroundAlpha)
        } else {
            ThemeColor.accent
        },
        animationSpec = motion(MotionToken.UI_MICRO),
        label = "markCapsuleGround",
    )
    val ink by animateColorAsState(
        targetValue = if (committed) ThemeColor.accent else ThemeColor.onAccent,
        animationSpec = motion(MotionToken.UI_MICRO),
        label = "markCapsuleInk",
    )
    val menuAlpha = animateFloatAsState(
        targetValue = if (committed) committedMenuAlpha else 1f,
        animationSpec = motion(MotionToken.UI_MICRO),
        label = "markCapsuleMenu",
    )
    val checkReveal = animateFloatAsState(
        targetValue = if (committed) 1f else 0f,
        animationSpec = motion(MotionToken.UI_MICRO),
        label = "markCapsuleCheck",
    )
    val labelFade: FiniteAnimationSpec<Float> = motion(MotionToken.UI_MICRO)

    val markLabel = if (committed) {
        Copy.Progress.episodeWatched(episode)
    } else {
        Copy.Action.markAsWatched
    }
    val markSpoken = if (committed) {
        Copy.Progress.episodeWatched(episode)
    } else {
        Copy.Action.markEpisodeWatched(episode, title)
    }

    Row(
        modifier
            .clip(CircleShape)
            .background(ground)
            // The lit top edge every filled control in this app carries: a flat #F0A24E rectangle
            // is a swatch, the same rectangle with one lit edge is an object.
            .border(ThemeMetrics.hairline, controlSheen, CircleShape),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .weight(1f)
                .defaultMinSize(minHeight = splitCapsuleHeight)
                .then(
                    // Committed, the half is not a button at all — no target, no role, just the
                    // receipt. iOS spells this `allowsHitTesting(false)` +
                    // `accessibilityRemoveTraits(.isButton)`; omitting `clickable` says both.
                    if (committed) {
                        Modifier
                    } else {
                        Modifier.clickable(
                            interactionSource = null,
                            indication = PressStyle.splitHalf,
                            role = Role.Button,
                            onClick = onMark,
                        )
                    }
                )
                .semantics(mergeDescendants = true) { contentDescription = markSpoken }
                .padding(horizontal = ThemeSpace.x5),
            contentAlignment = Alignment.Center,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                DrawnCheck(
                    on = committed,
                    tint = ThemeColor.accent,
                    modifier = Modifier
                        .clipToBounds()
                        // Collapsed to zero width, never conditionally inserted — the check keeps
                        // its own state and its own left-to-right mask, and the capsule opens the
                        // space for it on `uiMicro` as the mark lands.
                        .layout { measurable, constraints ->
                            val placeable = measurable.measure(constraints.copy(minWidth = 0))
                            val width = (placeable.width * checkReveal.value).roundToInt()
                            layout(width, placeable.height) { placeable.place(0, 0) }
                        }
                        .padding(end = ThemeSpace.x2),
                )
                AnimatedContent(
                    targetState = markLabel,
                    transitionSpec = {
                        // Two different sentences CROSSFADE; they do not interpolate. A morphing
                        // content transition printed "Mark as watched" and "Episode 19 watched"
                        // superimposed as an unreadable smear, twice per mark. `sizeTransform` is
                        // null for the same reason: the capsule is already full-width, and
                        // animating its width would move the label under the crossfade.
                        ContentTransform(
                            targetContentEnter = fadeIn(labelFade),
                            initialContentExit = fadeOut(labelFade),
                            sizeTransform = null,
                        )
                    },
                    contentAlignment = Alignment.Center,
                    label = "markLabel",
                ) { text ->
                    BasicText(
                        text = text,
                        style = ThemeType.button,
                        // One line, scaled before wrapped: "Mark episode 12 watched" broke into a
                        // two-line capsule beside "Details". A capsule's label compresses a step;
                        // it does not stack. `autoSize` is Compose's own answer to
                        // `minimumScaleFactor` — and an ellipsis is never the substitute.
                        maxLines = 1,
                        autoSize = TextAutoSize.StepBased(
                            minFontSize = ThemeType.button.fontSize * markLabelMinimumScale,
                            maxFontSize = ThemeType.button.fontSize,
                        ),
                        color = ColorProducer { ink },
                    )
                }
            }
        }

        if (showsMenu) {
            Spacer(
                Modifier
                    .width(1.dp)
                    .height(splitDividerHeight)
                    .background(ThemeColor.onAccent.copy(alpha = splitDividerAlpha))
            )
            Box {
                Box(
                    Modifier
                        .size(width = splitMenuWidth, height = splitCapsuleHeight)
                        .graphicsLayer { alpha = menuAlpha.value }
                        .then(
                            if (committed) {
                                Modifier.clearAndSetSemantics {}
                            } else {
                                Modifier
                                    .clickable(
                                        interactionSource = null,
                                        indication = PressStyle.splitHalf,
                                        role = Role.Button,
                                        onClick = { menuOpen = true },
                                    )
                                    .semantics(mergeDescendants = true) {
                                        contentDescription = Copy.Action.moreWaysToMark
                                    }
                            }
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Image(
                        imageVector = rememberSymbol(PreviouslyIcons.KeyboardArrowDown),
                        contentDescription = null,
                        modifier = Modifier.size(materialGlyphBox(splitChevronGlyph)),
                        colorFilter = ColorFilter.tint(ThemeColor.onAccent),
                    )
                }
                MarkBatchMenu(
                    expanded = menuOpen,
                    onDismiss = { menuOpen = false },
                    episode = episode,
                    behind = behind,
                    title = title,
                    onMarkThrough = onMarkThrough,
                    onMarkAll = onMarkAll,
                )
            }
        }
    }
}

/**
 * The batch menu behind the chevron.
 *
 * `DropdownMenu` is the native answer — iOS's blurred lift-and-platter has no Android equivalent
 * and reproducing one is exactly the heavy engineering the fidelity line rules out. It is wrapped
 * in [PreviouslyMaterialBridge] so it cannot arrive wearing `lightColorScheme()`, and its rows are
 * plain `clickable` `Row`s rather than `DropdownMenuItem`s, which build their own ripple with no
 * way to turn it off.
 */
@Composable
private fun MarkBatchMenu(
    expanded: Boolean,
    onDismiss: () -> Unit,
    episode: Int,
    behind: Int,
    title: String,
    onMarkThrough: (Int) -> Unit,
    onMarkAll: () -> Unit,
) {
    PreviouslyMaterialBridge {
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = onDismiss,
            // The `.floating` surface level, spelled out: an opaque ground (it covers content it
            // must never be mistaken for), a full `strokeStrong` ring, and the floating shadow.
            shape = ContinuousCornerShape(ThemeRadius.compactControl),
            containerColor = ThemeColor.surfaceFloating,
            tonalElevation = 0.dp,
            shadowElevation = ShadowToken.Floating.elevation,
            border = BorderStroke(ThemeMetrics.hairline, ThemeColor.strokeStrong),
        ) {
            // The menu is anchored to the show it writes to. A section header is the one menu
            // element that names without acting — and it is NOT uppercased like a section eyebrow,
            // because it is an identity: "Re:ZERO" has to survive as itself.
            BasicText(
                text = title,
                style = ThemeType.metadata,
                modifier = Modifier.padding(
                    horizontal = ThemeMetrics.gutter,
                    vertical = ThemeSpace.x2,
                ),
                maxLines = 2,
                color = ColorProducer { ThemeColor.textTertiary },
            )
            val through = min(episode + markThroughSpan, episode + behind - 1)
            if (through > episode) {
                MarkMenuCommand(Copy.Action.markThrough(from = episode, to = through)) {
                    onDismiss()
                    onMarkThrough(through)
                }
            }
            MarkMenuCommand(Copy.Action.markAll(behind)) {
                onDismiss()
                onMarkAll()
            }
        }
    }
}

/** One command in the batch menu. `interactive` ink — a menu item is an action, and actions are ink. */
@Composable
private fun MarkMenuCommand(label: String, onClick: () -> Unit) {
    val ink = LocalControlInk.current
    Box(
        Modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = null,
                indication = PressStyle.groupedRow,
                role = Role.Button,
                onClick = onClick,
            )
            .defaultMinSize(minHeight = minimumTapTarget)
            .padding(horizontal = ThemeMetrics.gutter, vertical = ThemeSpace.x2),
        contentAlignment = Alignment.CenterStart,
    ) {
        BasicText(text = label, style = ThemeType.body, color = ColorProducer { ink })
    }
}

/**
 * The capsule's own height — taller than the 44-dp floor because it is the one committed action on
 * the surface, exactly like [PrimaryButton].
 */
private val splitCapsuleHeight = 48.dp

/** The chevron half. Wide enough to be its own target without unbalancing the capsule. */
private val splitMenuWidth = 46.dp

/** The hairline between the halves, so the boundary the press promises is visible at rest. */
private val splitDividerHeight = 24.dp
private const val splitDividerAlpha = 0.18f

/** The chevron, at its iOS point size; the drawn box is [materialGlyphBox] of it. */
private val splitChevronGlyph = 12.dp

/** A committed capsule keeps its shape and drops to a soft tint. */
private const val committedGroundAlpha = 0.18f

/** The batch chevron, once there is nothing left for it to do. */
private const val committedMenuAlpha = 0.45f

/**
 * How far ahead the "mark episodes N–M" command reaches. Five in total, so the command stays a
 * batch a reader can picture rather than an unbounded promise; everything beyond it is
 * "Mark all N episodes as watched".
 */
private const val markThroughSpan = 4

/**
 * The floor the capsule's label may scale to (`minimumScaleFactor(0.78)` on iOS).
 *
 * "Episode 1128 watched" at 16 sp does not fit a phone-width capsule beside a second control, and
 * the identity of this control is that it is ONE line.
 */
private const val markLabelMinimumScale = 0.78f


