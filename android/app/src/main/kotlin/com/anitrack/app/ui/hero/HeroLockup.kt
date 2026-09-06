package com.anitrack.app.ui.hero

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredHeight
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorProducer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMotion
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.control.ProgressBar
import com.anitrack.app.ui.isAccessibilityTextSize
import com.anitrack.app.ui.section.HeroBadge
import com.anitrack.model.BillboardName
import com.anitrack.model.copy.Copy
import androidx.compose.ui.text.style.TextAlign
import com.anitrack.app.ui.state.ReceiptLine

/**
 * The billboard LOCKUP — Today's hero and the show page's, ONE composable (5 Sep, iOS `HeroLockup`).
 *
 * Reading order, top to bottom: the STATE as a filled [HeroBadge] ("NEW EPISODE", "4 EPISODES
 * BEHIND", "COMPLETE"); the show's NAME ([HeroTitle] — the logo treatment at the headline's mass,
 * else the name in type); ONE line, the moment then the episode ("Today at 7:30 PM · Season 4 ·
 * Episode 21"), with an optional [accessory] on its trailing edge (the show page's reveal glyph);
 * the season bar; a support line where one is earned; and the [actions] beneath (the mark capsule,
 * "Start rewatch", "Add to Library"). Prime Video's and Disney+'s grammar: a badge is the signal,
 * the size goes to the name, the rest is one line.
 *
 * The show page drew its own version until 5 Sep — the name and a grey identity line on the art,
 * then the badge, the fact and the capsule as a second block on canvas: two lockups with two
 * grammars in 150 dp ("poorly built and rushed", user). One composable, two callers; the page's
 * identity line heads its synopsis now.
 *
 * [actions] carry their own top inset ([HeroLockupDefaults.actionGap]) so an empty slot adds no
 * height — a calm hero is the art, the state and the moment, with no action row at all.
 *
 * @param onOpen Today: the whole copy block opens the show. Null on the show page, where the block
 *   IS the page and nothing opens.
 * @param interactive `false` while a card is still arriving on Today.
 */
@Composable
fun HeroLockup(
    badge: String,
    /** A drop that is OUT NOW and unwatched: the badge arrives and keeps catching the light. */
    badgeAttention: Boolean = false,
    title: String,
    name: BillboardName,
    moment: String?,
    fact: String,
    support: String?,
    progress: Float?,
    progressSpoken: String?,
    modifier: Modifier = Modifier,
    third: String? = null,
    style: TextStyle = ThemeType.displayXL.copy(color = ThemeColor.textPrimary),
    minScale: Float = HeroLockupDefaults.titleMinScale,
    maxLines: Int = 2,
    onOpen: (() -> Unit)? = null,
    interactive: Boolean = true,
    accessory: (@Composable () -> Unit)? = null,
    /** The in-place receipt's host, drawn as an OVERLAY hanging under the actions — never a layout child. */
    receiptHost: String? = null,
    actions: @Composable ColumnScope.() -> Unit = {},
) {
    val isAX = isAccessibilityTextSize()
    Column(modifier.fillMaxWidth()) {
        Column(
            Modifier
                .fillMaxWidth()
                .then(
                    if (onOpen != null) {
                        Modifier.clickable(
                            interactionSource = null,
                            indication = PressStyle.overArt,
                            enabled = interactive,
                            onClickLabel = Copy.Accessibility.opensTheShowHint,
                            role = Role.Button,
                            onClick = onOpen,
                        )
                    } else {
                        Modifier
                    },
                )
                // `children: .combine` — badge, name, line and bar are one utterance.
                .semantics(mergeDescendants = true) {},
            // CENTRED (5 Sep): the whole lockup on the billboard's axis — the Netflix billboard's
            // lockup, chosen from three photographed placements after the show's logotype came
            // back as the headline; the rest of the page keeps its left axis.
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            HeroBadge(text = badge, attention = badgeAttention)

            HeroTitle(
                text = title,
                name = name,
                style = style,
                minScale = minScale,
                maxLines = maxLines,
                isAX = isAX,
                modifier = Modifier.padding(top = ThemeSpace.x3),
            )

            // ONE line: the moment, then the episode — `textSecondary`, so the name and the line
            // never read as one. The accessory is a 44-dp control that shares the row without
            // growing it, pulled back onto the gutter optically.
            Row(
                Modifier
                    .padding(top = ThemeSpace.x1),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x1),
            ) {
                NumericLine(
                    text = listOfNotNull(moment, fact).joinToString(" $MIDDLE_DOT "),
                ) { text ->
                    BasicText(
                        text = text,
                        style = ThemeType.heroMeta.copy(textAlign = TextAlign.Center),
                        color = ColorProducer { ThemeColor.textSecondary },
                    )
                }
                if (accessory != null) {
                    Box(
                        Modifier
                            .requiredHeight(HeroLockupDefaults.lineBox)
                            .wrapContentHeight(Alignment.CenterVertically, unbounded = true)
                            .offset(x = HeroLockupDefaults.accessoryOverhang),
                        contentAlignment = Alignment.Center,
                    ) { accessory() }
                }
            }

            if (progress != null) {
                ProgressBar(
                    value = progress,
                    spoken = progressSpoken,
                    modifier = Modifier
                        .padding(top = ThemeSpace.x2)
                        .then(
                            if (isAX) Modifier.fillMaxWidth() else Modifier.width(HeroLockupDefaults.progressWidth),
                        ),
                )
            }

            if (support != null) {
                BasicText(
                    text = support,
                    style = ThemeType.metadata.copy(textAlign = TextAlign.Center),
                    color = ColorProducer { ThemeColor.textSecondary },
                    modifier = Modifier.padding(top = ThemeSpace.x1),
                )
            }

            if (third != null) {
                BasicText(
                    text = third,
                    style = ThemeType.metadata.copy(textAlign = TextAlign.Center),
                    color = ColorProducer { ThemeColor.textTertiary },
                    modifier = Modifier.padding(top = ThemeSpace.x0_5),
                )
            }
        }

        Box(Modifier.fillMaxWidth()) {
            Column(Modifier.fillMaxWidth(), content = actions)
            if (receiptHost != null) {
                ReceiptLine(
                    host = receiptHost,
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .offset(y = HeroLockupDefaults.receiptHang),
                )
            }
        }
    }
}

object HeroLockupDefaults {
    /** iOS `.minimumScaleFactor(0.82)` on the title: a long name lands on its two-line fit. */
    const val titleMinScale: Float = 0.82f

    /** The bar is a measurement, not a banner: it stops well short of the gutter at ordinary sizes. */
    val progressWidth: Dp = 200.dp

    /** The inset an action carries above itself. */
    fun actionGap(isAX: Boolean): Dp = if (isAX) ThemeSpace.x5 else ThemeSpace.x4

    /** From the lockup's top edge (the badge, 20 dp) to the name: the badge and the gap under it. */
    val badgeToName: Dp = 20.dp + ThemeSpace.x3

    /** The one line's box, which an accessory may overflow. */
    val lineBox: Dp = 20.dp

    /** How far a 44-dp accessory is pulled past the copy's trailing edge onto the gutter. */
    val accessoryOverhang: Dp = 12.dp

    /** The minimum target of an accessory. */
    val accessoryTarget: Dp = 44.dp

    /** How far the in-place receipt hangs under the actions' bottom edge: its own 28 dp plus a gap. */
    val receiptHang: Dp = 24.dp
}

/**
 * A line whose content is a NUMBER that changed.
 *
 * iOS rolls the digits (`contentTransition(.numericText())`) and crossfades under Reduce Motion.
 * Compose has no rolling-digit transition, and the spec names the crossfade as the sanctioned
 * fallback — which is also the treatment Reduce Motion already specifies, so the two states agree
 * rather than diverging.
 */
@Composable
internal fun NumericLine(
    text: String,
    modifier: Modifier = Modifier,
    content: @Composable (String) -> Unit,
) {
    AnimatedContent(
        targetState = text,
        transitionSpec = {
            ContentTransform(
                targetContentEnter = fadeIn(ThemeMotion.uiNumeric()),
                initialContentExit = fadeOut(ThemeMotion.uiNumeric()),
                // Never a size transform: the line is one row of a slate, and animating its box
                // moves the four lines under it for a digit.
                sizeTransform = null,
            )
        },
        modifier = modifier,
        label = "numericFact",
    ) { current ->
        content(current)
    }
}

private const val MIDDLE_DOT = "·"
