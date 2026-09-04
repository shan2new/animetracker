package com.anitrack.app.design.brand

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.anitrack.app.design.ShadowToken
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.shadowToken
import com.anitrack.app.ui.AutoSizeText

/*
 * THE IDENTITY — the port of `ios/Sources/DesignSystem/PreviouslyMark.swift` and of `AccountDisc`
 * in `ios/Sources/DesignSystem/Primitives.swift`.
 *
 * **This file is the source of truth for every in-app drawing of the identity, and the identity may
 * not exist twice.** It does not any more: the saved-place ribbon was hand-drawn in THREE screens
 * (`ui/auth/SignInScreen.kt`, `ui/today/TodayScreen.kt`, `ui/profile/ProfileScreen.kt`), each with
 * its own copy of the path, its own 1.58 aspect and its own private `Color(0xFFFFD6A0)` /
 * `Color(0xFFC9702E)` / `Color(0xFFFFF0DA)` — three literal colours declared inside screens, which
 * `design/Color.kt` forbids by name, and one geometry that could drift three ways. The account disc
 * existed twice on top of that, in a quiet form and an accent form, where iOS has ONE primitive with
 * a `quiet` flag. All five copies carried a note pointing at this package; the package now exists.
 *
 * The mark's colours are `ThemeColor.markHighlight` / `markShadow` / `markProgressDot`, because a
 * colour lives in the palette and nowhere else — not because a call site may reach for them. They
 * are the ribbon's own gradient and this is the only file that spends them.
 */

// ─────────────────────────────────────────────────────────────────────────────
// Geometry. The mark's own anatomy, in fractions of its width — so one number,
// the width, sizes every use of it.
// ─────────────────────────────────────────────────────────────────────────────

/** The mark's fixed aspect: drawn height is `width × 1.58`. */
private const val MARK_ASPECT = 1.58f

private const val CORNER_FRACTION = 0.17f
private const val NOTCH_APEX_FRACTION = 0.76f
private const val EDGE_BOTTOM_FRACTION = 0.96f

private const val SLOT_WIDTH_FRACTION = 0.56f
private const val SLOT_HEIGHT_FRACTION = 0.12f
private const val SLOT_RISE_FRACTION = 0.24f
private const val DOT_DIAMETER_FRACTION = 0.10f

/** Where the progress point sits at 0, and how far it travels to 1. */
private const val DOT_START_FRACTION = -0.32f
private const val DOT_TRAVEL_FRACTION = 0.64f

/** The bloom's reach — iOS `RadialGradient(endRadius: 260)` in a 520 × 520 frame. */
private val BloomRadius = 260.dp

/** What the mark draws inside the ribbon. */
enum class MarkDetail {
    /** The slot and the point riding in it — the wordmark's mark, the sign-in gate's. */
    Progress,

    /** The bare ribbon — the mark standing in for a monogram inside an account disc. */
    None,
}

/**
 * The **Previously.** brand mark: a saved-place ribbon with a single progress point.
 *
 * The whole mark is hidden from accessibility everywhere it is drawn: the wordmark beside it, or the
 * control around it, says the name.
 *
 * @param width the only size a caller gives. The height and every internal measure are fractions of
 *   it, so the mark cannot be drawn out of proportion.
 * @param detail [MarkDetail.Progress] draws the slot and its point; [MarkDetail.None] is the bare
 *   ribbon.
 * @param progress where the point sits in its slot, 0…1. Clamped.
 * @param bloom the sign-in gate's one light source: a three-stop radial gradient centred on the
 *   mark, drawn behind it. **It carries no blur, on any API level** — iOS puts `.blur(24)` behind
 *   the same gradient, where it is a band-smoother rather than a shape change, and reproducing that
 *   on Android would mean `Modifier.blur`, a silent no-op below API 31: the floor devices would get
 *   a visibly different first screen in exchange for a softening nobody can see. Native means,
 *   re-tuned numbers, same reading. Compose does not clip a draw to its node's bounds, so the reach
 *   spills past the mark exactly as the iOS background frame does.
 */
@Composable
fun PreviouslyMark(
    width: Dp,
    modifier: Modifier = Modifier,
    detail: MarkDetail = MarkDetail.Progress,
    progress: Float = 0f,
    bloom: Boolean = false,
) {
    val accent = ThemeColor.accent
    val clamped = progress.coerceIn(0f, 1f)
    Canvas(
        modifier = modifier
            .size(width = width, height = width * MARK_ASPECT)
            .then(if (bloom) Modifier.drawBehind { drawBloom(accent) } else Modifier)
            .clearAndSetSemantics {},
    ) {
        drawRibbon(accent)
        if (detail == MarkDetail.Progress) drawProgressSlot(clamped)
    }
}

/** A soft-cornered bookmark with its saved-place notch cut into the bottom edge. */
private fun DrawScope.drawRibbon(accent: Color) {
    val w = size.width
    val h = size.height
    val corner = w * CORNER_FRACTION
    val notchApex = h * NOTCH_APEX_FRACTION
    val edgeBottom = h * EDGE_BOTTOM_FRACTION
    val ribbon = Path().apply {
        moveTo(corner, 0f)
        lineTo(w - corner, 0f)
        quadraticTo(w, 0f, w, corner)
        lineTo(w, edgeBottom)
        lineTo(w / 2f, notchApex)
        lineTo(0f, edgeBottom)
        lineTo(0f, corner)
        quadraticTo(0f, 0f, corner, 0f)
        close()
    }
    drawPath(
        path = ribbon,
        brush = Brush.linearGradient(
            colors = listOf(ThemeColor.markHighlight, accent, ThemeColor.markShadow),
            start = Offset.Zero,
            end = Offset(w, h),
        ),
    )
}

/** The slot, cut out of the ribbon in canvas ink, and the point riding in it. */
private fun DrawScope.drawProgressSlot(progress: Float) {
    val w = size.width
    val h = size.height
    val slotW = w * SLOT_WIDTH_FRACTION
    val slotH = w * SLOT_HEIGHT_FRACTION
    val slotCentreY = h / 2f - h * SLOT_RISE_FRACTION
    drawRoundRect(
        color = ThemeColor.canvas,
        topLeft = Offset(w / 2f - slotW / 2f, slotCentreY - slotH / 2f),
        size = Size(slotW, slotH),
        cornerRadius = CornerRadius(slotH / 2f),
    )
    drawCircle(
        color = ThemeColor.markProgressDot,
        radius = w * DOT_DIAMETER_FRACTION / 2f,
        center = Offset(
            w / 2f + slotW * DOT_START_FRACTION + slotW * DOT_TRAVEL_FRACTION * progress,
            slotCentreY,
        ),
    )
}

private fun DrawScope.drawBloom(accent: Color) {
    val reach = BloomRadius.toPx()
    drawCircle(
        brush = Brush.radialGradient(
            0.0f to accent.copy(alpha = 0.20f),
            0.5f to accent.copy(alpha = 0.05f),
            1.0f to Color.Transparent,
            center = center,
            radius = reach,
        ),
        radius = reach,
        center = center,
    )
}

// ─────────────────────────────────────────────────────────────────────────────
// The account disc
// ─────────────────────────────────────────────────────────────────────────────

/** The monogram is 0.42 × the disc — the disc's own anatomy, like a ring's numeral. */
private const val MONOGRAM_FRACTION = 0.42f

/** The mark stands in for a monogram at 0.34 × the disc. */
private const val MARK_FRACTION = 0.34f

/** iOS `minimumScaleFactor(0.6)` on the monogram. */
private const val MONOGRAM_MIN_SCALE = 0.6f

/** The ring of canvas around the subject disc: drawn OUTSIDE it, so it separates without cutting. */
private val DiscHaloInset = 5.dp

/**
 * The account disc, drawn once for every surface that shows one.
 *
 * **It never draws a person glyph.** Both call sites once rendered the system's generic account
 * glyph inside a brand-coloured ring — the app spending its one accent on a placeholder, on the
 * element whose entire job is to be *this person*. The chain is: the real initial → the first letter
 * of the label the account is shown under ("Your account" → "Y") → the [PreviouslyMark]. Only the
 * first two are letters, so a wrong initial is still never invented; the third is the app's own
 * identity, which is never wrong.
 *
 * The disc is hidden from accessibility: the control around it is what is named.
 *
 * @param monogram the resolved initial, or `null` for the mark. Callers pass
 *   `AuthManager.AccountIdentity.monogram` — never a letter of their own derivation, which is how
 *   one user came to have two meaningless initials one tap apart.
 * @param quiet neutral ground and ink instead of the accent pair, **and no halo**. Today's header
 *   wears this: the amber budget above the fold belongs to the hero's fact and its one action, and
 *   an amber monogram disc 12 dp from the wordmark was a second brand-coloured object spending it
 *   on chrome. Profile — where the disc IS the subject, and sits on the screen's own wash — keeps
 *   the accent form and the ring of canvas that separates it from what is behind it.
 */
@Composable
fun AccountDisc(
    monogram: String?,
    diameter: Dp,
    modifier: Modifier = Modifier,
    quiet: Boolean = false,
) {
    // A fixed-diameter disc gets a fixed glyph: the iOS `.system(size:)` here carries no Dynamic
    // Type ramp either, and a monogram that grew with the text scale would leave its own circle.
    val density = LocalDensity.current
    val monogramStyle = with(density) {
        ThemeType.showTitleM.copy(
            fontSize = (diameter * MONOGRAM_FRACTION).toSp(),
            lineHeight = (diameter * MONOGRAM_FRACTION * 1.28f).toSp(),
            color = if (quiet) ThemeColor.textSecondary else ThemeColor.accent,
        )
    }

    Box(
        modifier = modifier
            .size(diameter)
            .shadowToken(ShadowToken.Art, CircleShape)
            .background(
                if (quiet) ThemeColor.surfaceRaised else ThemeColor.accentSoft,
                CircleShape,
            )
            .border(ThemeMetrics.hairline, ThemeColor.posterEdge, CircleShape)
            // A ring of canvas, not a hole in the artwork: drawn OUTSIDE the disc, so nothing has to
            // be punched through. Compose does not clip a draw to its node's bounds, which is what
            // lets the ring sit outside the circle it belongs to.
            .then(
                if (quiet) {
                    Modifier
                } else {
                    Modifier.drawBehind {
                        drawCircle(
                            color = ThemeColor.hairline,
                            radius = size.minDimension / 2f + DiscHaloInset.toPx(),
                            style = Stroke(ThemeMetrics.hairline.toPx()),
                        )
                    }
                },
            )
            .clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        if (monogram != null) {
            AutoSizeText(
                text = monogram,
                style = monogramStyle,
                minScale = MONOGRAM_MIN_SCALE,
                maxLines = 1,
            )
        } else {
            PreviouslyMark(width = diameter * MARK_FRACTION, detail = MarkDetail.None)
        }
    }
}
