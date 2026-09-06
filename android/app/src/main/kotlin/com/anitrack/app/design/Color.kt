package com.anitrack.app.design

import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color

/**
 * Every colour in **Previously.**, ported 1:1 from `ios/Sources/DesignSystem/ThemeTokens.swift`.
 *
 * The app is **dark-only** and never follows the system light/dark setting, so there is no second
 * palette and no `isSystemInDarkTheme()` branch anywhere. Every literal here is sRGB and
 * non-premultiplied, exactly as `Color(hex:alpha:)` produced them on iOS; the alpha tokens are
 * *source-over* composites against whatever is beneath them, which is load-bearing for the surface
 * lifts (see [plateLift] / [raisedLift]).
 *
 * No screen may declare a colour. If a colour is needed and is not here, it is added here.
 *
 * ### The one rule that outranks the rest
 *
 * **Amber ([accent]) is not an action colour.** See [interactive].
 */
@Immutable
object ThemeColor {

    // MARK: - Canvas

    /** The app ground. Everything else is a lift over this. */
    val canvas = Color(0xFF09090B)

    /**
     * Ground for a *pushed* full-screen surface — sheet backgrounds, the Watch-history screens.
     */
    val canvasRaised = Color(0xFF0D0E11)

    /*
     * Opaque content surfaces.
     *
     * These are the RESULT of `plateLift` / `raisedLift` composited over `canvas`, so a screen that
     * reaches for the token directly and a container that goes through `Modifier.surface(_)` land
     * on the same colour. The shipped values (#121318 / #181A20) were a 9-value 8-bit step off a
     * #09090B canvas and 6 values apart from each other — Apple's dark grouped step is roughly
     * twice that, which is why every container still needed an outline to exist.
     *
     * The identity is checkable at any time, and should stay checkable:
     *   plateLift.compositeOver(canvas)  == rgb(22.5, 22.5, 24.4) ≈ #171718 ≈ surfaceFlat  #171719
     *   raisedLift.compositeOver(canvas) == rgb(36.1, 36.1, 37.8) ≈ #242426 ≈ surfaceRaised #242428
     */

    /** Opaque result of [plateLift] over [canvas]. `.plate` fill; base layer of the art ground. */
    val surfaceFlat = Color(0xFF171719)

    /** Opaque result of [raisedLift] over [canvas]. `.raised` fill; quiet avatar disc; mark chip. */
    val surfaceRaised = Color(0xFF242428)

    /**
     * `.floating` fill — toast, sync banner, secondary capsule button. Deliberately **opaque**:
     * a translucent toast with a shelf scrolling through it is worse than a flat one.
     */
    val surfaceFloating = Color(0xFF2A2D36)

    /** Pressed state of any neutral surface, row or capsule. */
    val surfacePressed = Color(0xFF353842)

    // MARK: - Text

    /** Warm off-white. Titles, facts, primary ink. 17.66:1 on [canvas]. */
    val textPrimary = Color(0xFFF4F1EC)

    /** Row metadata, hero fact line, colophon. 8.21:1 on [canvas]. */
    val textSecondary = Color(0xFFAAA6A0)

    /** Section counts, footnotes, eyebrows, disabled ticker days. 5.14:1 on [canvas]. */
    val textTertiary = Color(0xFF85817C)

    /**
     * The quietest ink that is still *read*. #6C6965 measured 3.29:1 on the canvas — legal for a
     * chevron (decoration, 3:1) and wrong for the section counts and index letters this token is
     * also assigned to. #807C77 is ≈4.6:1 and nothing else in the ramp moves.
     */
    val textDisabled = Color(0xFF807C77)

    // MARK: - Brand

    /** Brand amber. **Fact / state / ground only** — see [interactive]. 9.46:1 on [canvas]. */
    val accent = Color(0xFFF0A24E)

    /** Pressed state of an amber ground (primary capsule, mark-ring fill). */
    val accentPressed = Color(0xFFD88D3B)

    /**
     * Amber disc/chip ground. The ink on it is [onAccent], never amber. Over [canvas] this
     * composites to ≈ rgb(41, 30, 20).
     */
    val accentSoft = accent.copy(alpha = 0.14f)

    /*
     * THE MARK'S OWN GRADIENT — the three colours the saved-place ribbon is drawn from, and the
     * only three colours in this table that belong to one drawing rather than to the system.
     *
     * They are here, and not beside the geometry, because of the rule at the head of this file: a
     * screen may not declare a colour. Three screens each declared these three, privately, around
     * three hand-drawn copies of the same path; `design/brand/PreviouslyMark.kt` is now the one
     * drawing and this is the one palette. Nothing but that file may spend them.
     */

    /** The ribbon's lit edge — the gradient's top-leading stop. */
    val markHighlight = Color(0xFFFFBB48)

    /** The ribbon's shaded edge — the gradient's bottom-trailing stop. Also the wordmark's stop. */
    val markShadow = Color(0xFFDE4A3C)

    /** The ramp's middle — the app icon's amber (design/app-icon-v2/glass/x9-final.icon). */
    val markMid = Color(0xFFF28C3C)

    /**
     * The full stop. The app icon's coral bead (design/app-icon-v2/glass/x9-final.icon), and the
     * period of "Previously." everywhere the name is set — the launch, the header, the sign-in
     * gate, the colophon — so the icon's two objects are the wordmark's two objects. Not amber
     * (amber is a fact or a state) and not an action colour: it is the name's.
     */
    val brandPeriod = Color(0xFFF0563F)

    /** The icon's coloured shadow: the warm light the lit ribbon leaves on the canvas beneath it. */
    val markCastShadow = Color(0xFFE8702E)

    /**
     * Immediate ground for an artwork wash before a remote image or its palette is available.
     * It must be visibly warmer than [canvas]: a near-black fallback made a cold device launch
     * look as though the gradient had not rendered, while a cache-warm simulator showed the art.
     */
    val ambientBackdropFallback = Color(0xFF432D21)

    /** Ink drawn *on* an amber ground. 9.35:1 on [accent]. */
    val onAccent = Color(0xFF0B0B0D)

    /**
     * The ink of a bare interactive word or glyph — "See all", "Read more", "Clear", "Sync now",
     * "Details", "Add", "Done", a tertiary button in an empty state.
     *
     * **Amber is not an action colour.** It is rationed to two readings and neither is "tappable":
     *   * MEANING — a real next step ("Returns Oct 2", "Episode 19 next", a future air time);
     *   * STATE   — today, owned, selected, an active filter, a committed mark.
     *
     * Amber may also be a GROUND (the primary capsule, the mark ring's fill, [accentSoft] discs) —
     * there the amber is the object and the ink on it is [onAccent], so no amber *word* is drawn
     * and nothing competes.
     *
     * Before this token, twenty tappable words and glyphs wore [accent] and collided head-on with
     * the first reading: Detail's toolbar said "+ Add" in amber directly above "Episode 14 next"
     * in amber, and a Library section header put an amber "See all" over amber "Returns Oct 2"
     * captions. One hue cannot mean "this is a fact about your future" and "this is a button".
     *
     * A bare action carries its affordance the way a list does: position (a bar slot, a section
     * header's trailing edge), semibold weight, a 44-dp target, and a chevron where the row has
     * one. An alias, not a new colour — if this ever needs its own hue, it changes here.
     *
     * One clarification the STATE reading needs, settled once (cohesion pass, 30 Aug): a
     * selector's SELECTED value is legal amber (it is a state, like an active filter) — *except*
     * inside a control where amber already carries another meaning. Schedule's ticker is that
     * exception: amber is today's alone there, so its selection is a neutral raised plate.
     * Library's root tabs keep the amber selection; the two controls are answering different
     * constraints, not disagreeing.
     *
     * On Android this is plumbed through [LocalControlInk] rather than a cascading `tint`, and it
     * is also the M3 `primary` role — Material tints its own controls with `primary`, and mapping
     * `accent` there would be exactly the collision this token exists to end.
     */
    val interactive = textPrimary

    // MARK: - Semantic

    /** Sync "No problems" line only. (Apple's dark systemGreen.) */
    val success = Color(0xFF30D158)

    /** Unsynced-changes dot, sync-status glyph. (Apple's dark systemYellow.) */
    val warning = Color(0xFFFFD60A)

    /** Delete verbs, destructive confirmation buttons. (Apple's dark systemRed.) */
    val destructive = Color(0xFFFF453A)

    /** Declared on iOS, currently unused. Kept so the ramp is complete. */
    val information = Color(0xFF64D2FF)

    // MARK: - Structure

    /** Declared on iOS, currently unused — [separatorQuiet] replaced it. */
    val separator = Color.White.copy(alpha = 0.08f)

    /** Generic outline. **Never** used to make a card visible — see [SurfaceLevel]. */
    val stroke = Color.White.copy(alpha = 0.12f)

    /** The `.floating` level's full ring. */
    val strokeStrong = Color.White.copy(alpha = 0.20f)

    /**
     * The unmarked mark ring's stroke. [strokeStrong] at 1.5 dp over a dark poster read as a
     * disabled ghost — the app's core control was the least visible element on its row. The mark's
     * idle state is an INVITATION and gets its own, clearly-drawn weight.
     */
    val markRingIdle = Color.White.copy(alpha = 0.34f)

    /**
     * Skeleton fill. At 8 % over the #09090B canvas the structure was ~4 % above ground and
     * effectively invisible; it has to read as the shape of what is coming.
     */
    val skeleton = Color(0xFFF4F1EC).copy(alpha = 0.11f)

    /** Declared on iOS, currently unused. */
    val focusRing = accent.copy(alpha = 0.70f)

    // MARK: - Overlays

    /** Bottom-of-art scrim gradient terminal. */
    val scrim = Color.Black.copy(alpha = 0.56f)

    /** Heavier art scrim / over-art legibility. */
    val scrimStrong = Color.Black.copy(alpha = 0.72f)

    // MARK: - Edges
    //
    // On a #09090B ground an outline all the way round a card is the cheapest possible way to say
    // "this is a surface" — it is what a wireframe does. A premium dark UI separates surfaces by
    // TONE and lights their top edge, the way a physical object catches light. These tokens exist
    // so no screen ever reaches for `stroke` to make a card visible again.

    /**
     * 1-dp highlight along the TOP edge of a raised surface, fading out by its vertical centre.
     * This is the only "stroke" a content card is allowed.
     */
    val hairline = Color.White.copy(alpha = 0.055f)

    /**
     * Divider INSIDE a plate. [separator] (0.08) repeated eight times down one list reads as a
     * spreadsheet; at 0.045 the eye reads grouping instead of ruling.
     */
    val separatorQuiet = Color.White.copy(alpha = 0.045f)

    /**
     * The edge of artwork. Never [stroke] — a 12 %-white outline around a bright poster is a
     * picture frame, and around a dark poster it is a glow. Just enough to stop art bleeding into
     * the canvas: at 5 % a near-black poster dissolved into #09090B entirely, so 9 % is the floor
     * at which the art still has a boundary and a bright poster still has no frame.
     */
    val posterEdge = Color.White.copy(alpha = 0.09f)

    // MARK: - Surface lifts
    //
    // A surface is a RELATIVE lift, not an absolute fill. The shipped `.plate` painted opaque
    // `surfaceFlat` wherever it landed, so on any screen carrying an art backdrop the ambient wash
    // lifted the canvas AROUND the plate and the plate itself inverted into a hole 13 levels darker
    // than its own ground — measured on Library, where it is the first element on the screen.
    // Painting white over whatever is beneath means a plate is always *above* its ground.
    //
    // These two must stay TRANSLUCENT. Substituting the opaque `surfaceFlat` / `surfaceRaised`
    // twins re-introduces that bug exactly.

    /** `.plate` — grouped lists, section grounds, notices. */
    val plateLift = Color.White.copy(alpha = 0.055f)

    /** `.raised` — a card that carries the screen's action. */
    val raisedLift = Color.White.copy(alpha = 0.11f)

    /** The bottom of a full-bleed ambient backdrop, where art hands over to the canvas. */
    val backdropFade = canvas

    /**
     * The veil that hides scrolling content as it approaches the status bar. Full canvas, so the
     * handover is invisible: content does not slide *under a grey bar*, it dissolves into the app.
     */
    val chromeVeil = canvas

    /**
     * The light along the top edge of a filled control (the accent capsule, a chip). An orange
     * rectangle is a swatch; an orange rectangle with a lit top edge is an object.
     */
    val controlSheen = Color.White.copy(alpha = 0.22f)
}
