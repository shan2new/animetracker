package com.anitrack.app.design

import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/*
 * SURFACES, second half: the rules that belong to ARTWORK.
 *
 * The four legal containers — `SurfaceLevel` (plate / raised / floating / art) and
 * `Modifier.surface(level, radius)` with its top-edge hairline — live in `Elevation.kt`, next to
 * `ShadowToken`, because a level IS a (ground, edge, shadow) triple and splitting the three apart
 * is how a design system grows a fifth container nobody named. Read that file first; this one
 * assumes it.
 *
 * What is here is the surface treatment art gets, which is deliberately NOT one of the four:
 *
 *   - [Modifier.artEdge] — the 1-dp `posterEdge` hairline, all the way round, and the ONE outline
 *     a picture is allowed;
 *   - [Modifier.artFrame] — shadow → clip → edge in the shipped order, as one call, so no screen
 *     re-derives it;
 *   - [Modifier.handoffGround] — the art-adaptive ground held BEHIND a container whose contents
 *     are being swapped.
 *
 * The governing rule, from `CLAUDE.md` and the design-token spec: **tone separates, light
 * describes, strokes are for things that float.** A container that needs an outline to be visible
 * is at the wrong surface level — move it up, do not draw a box around it. Artwork is the one
 * exception, and it gets its own, quieter token for exactly that reason.
 */

/** 1 dp, the shipped `strokeBorder` width. Compose insets a border the same way, so this maps. */
private val artEdgeWidth = ThemeMetrics.hairline

/**
 * The edge of a piece of ARTWORK: [ThemeColor.posterEdge] (white 9 %), 1 dp, inset, all the way
 * round.
 *
 * This is the one place a full ring is correct, and it is correct because the thing inside it is a
 * photograph rather than a container. **Never [ThemeColor.stroke] here** (white 12 %): *"the job is
 * to stop a dark poster dissolving into a black canvas, NOT to draw a frame around every piece of
 * artwork"* — a 12 %-white outline reads as a picture frame around a bright poster and as a glow
 * around a dark one. At 5 % a near-black poster dissolved into the #09090B canvas entirely, so 9 %
 * is the floor at which the art still has a boundary and a bright poster still has no frame.
 *
 * Compose's `Modifier.border` strokes INWARD, like SwiftUI's `strokeBorder` (and unlike `stroke`),
 * and it draws **after** the node's content — so an edge placed early in a chain still lands on top
 * of the picture, which is what `.overlay(strokeBorder(...))` does on iOS.
 */
fun Modifier.artEdge(shape: Shape): Modifier = border(artEdgeWidth, ThemeColor.posterEdge, shape)

/** [artEdge] against a continuous-cornered rounded rectangle of [radius]. */
fun Modifier.artEdge(radius: Dp): Modifier = artEdge(ContinuousCornerShape(radius))

/**
 * The whole frame around a piece of artwork, in the shipped construction order: **shadow (outside
 * the clip) → clip → edge**.
 *
 * Everything that comes *after* this in the modifier chain — the `surfaceRaised` ground, the
 * palette tint over it, the image, a scrim — is drawn inside the clip and underneath the edge,
 * because `Modifier.border` draws its stroke after the content it wraps. So the whole of a poster
 * slot is one chain:
 *
 * ```
 * Box(
 *     Modifier
 *         .size(slot.width, slot.height)
 *         .artFrame(slot.radius, slot.shadow)
 *         .background(ThemeColor.surfaceRaised)
 * ) { … }
 * ```
 *
 * @param shadow only art large enough to read as an object earns one — pass a slot's
 *   [PosterSize.shadow] straight through; [ShadowToken.None] is a no-op.
 *   The shadow is cast from a plain `RoundedCornerShape` while the content is clipped to the
 *   squircle: a generic path casts no platform shadow below API 29 (this app's floor is 26), and
 *   the silhouette difference is invisible once blurred. Same trade as `Modifier.surface`.
 */
fun Modifier.artFrame(radius: Dp, shadow: ShadowToken = ShadowToken.None): Modifier {
    val shape = ContinuousCornerShape(radius)
    return shadowToken(shadow, RoundedCornerShape(radius))
        .clip(shape)
        .artEdge(shape)
}

/**
 * Puts the art-adaptive ground BEHIND a container that survives a card swap.
 *
 * Required wherever a `handoff` transition exchanges two cards in the same slot: *"if the ground
 * belongs to the cards themselves, the canvas flashes through the gap between them"* — the outgoing
 * card leaves before the incoming one arrives (that asymmetry is the point of the transition), so
 * for those ~80 ms there is no card, and whatever the ground was has to still be there.
 *
 * The tint is the show's own colour; `null` falls back to [ArtGround.neutralWarm] rather than the
 * canvas, so the slot has a body from the first frame instead of flashing black.
 *
 * Declared and currently unused, exactly as on iOS — Detail's state block was moved onto the canvas
 * in the 3 Sep pass and dropped its handoff ground with a comment saying so. It stays because the
 * next thing that cross-fades two cards in one slot must not re-derive it by hand.
 *
 * @param radius defaults to [ThemeRadius.focusCard] (24), the Focus/handoff corner.
 *
 * One Android note: iOS clips only the background layer, leaving the content unclipped. Compose
 * clips the node, so the container's own content is clipped to the same rounded rect. Every real
 * caller *is* that rounded rect, so nothing changes; a caller that deliberately draws outside its
 * own corners should paint the ground as a sibling instead.
 */
fun Modifier.handoffGround(tint: Color?, radius: Dp = ThemeRadius.focusCard): Modifier =
    this then Modifier
        .clip(ContinuousCornerShape(radius))
        .artAdaptiveGround(tint = tint ?: ArtGround.neutralWarm, intensity = 1f)
