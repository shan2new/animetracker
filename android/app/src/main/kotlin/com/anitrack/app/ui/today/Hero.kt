package com.anitrack.app.ui.today

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorProducer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.anitrack.app.design.ArtGround
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeMotion
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.ui.AutoSizeText
import com.anitrack.app.ui.image.rememberArtTint
import com.anitrack.app.ui.control.MarkSplitButton
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.control.PrimaryButton
import com.anitrack.app.ui.control.ProgressBar
import com.anitrack.app.ui.hero.ArtHeader
import com.anitrack.app.ui.hero.Billboard
import com.anitrack.app.ui.hero.HeroCopyScrim
import com.anitrack.app.ui.hero.HeroTopVeil
import com.anitrack.app.ui.hero.billboardHeight
import com.anitrack.app.ui.isAccessibilityTextSize
import com.anitrack.app.ui.section.OverArtLabel
import com.anitrack.model.Formatting
import com.anitrack.model.Franchise
import com.anitrack.model.FranchisePart
import com.anitrack.model.FranchiseSummary
import com.anitrack.model.ShelfWindows
import com.anitrack.model.TemporalCopy
import com.anitrack.model.TimeAnchor
import com.anitrack.model.airedByNow
import com.anitrack.model.availableEpisodes
import com.anitrack.model.behind
import com.anitrack.model.canonicalLabel
import com.anitrack.model.continueBacklog
import com.anitrack.model.dayDiff
import com.anitrack.model.displayTitle
import com.anitrack.model.episodicPartsInOrder
import com.anitrack.model.isComplete
import com.anitrack.model.landscapeArt
import com.anitrack.model.lastAired
import com.anitrack.model.nextAiring
import com.anitrack.model.portraitArt
import com.anitrack.model.releasingPart
import com.anitrack.model.resumePart
import com.anitrack.model.shelfShortened
import com.anitrack.model.timeAnchor
import com.anitrack.model.watchContext
import com.anitrack.model.copy.Copy

// =====================================================================================
// THE BILLBOARD HERO — the port of `hero(...)`, `HeroFocus`, `TrendingFocus`,
// `StretchingHeroArt` and `FocusKind` from `ios/Sources/Features/Today/TodayView.swift`
// (spec/today.md §5–§7).
//
// **The hero is a SLATE, read in a TV listing's order: pill → headline → show → fact.**
// Never let the reason someone opened the app be the smallest text on it, and never say in
// words what a numeral beside them already says.
//
//   pill      OverArtLabel     the STATE, uppercase, on a dark capsule over the art
//   headline  displayXL/accent the MOMENT — and only a moment earns one (the clock)
//   show      heroTitle        `displayTitle` ("Re:ZERO"), as every row and shelf draws it
//   fact      heroMeta/2ndary  "in 3h 12m · Season 4 · Episode 15"
//   bar       ProgressBar      where-you-are, WORDLESS
//   support   metadata/2ndary  at most one more thing
//
// ONE ACTION — the mark capsule. The block itself opens the show; "Details" beside it
// duplicated the card's own tap, and Apple TV's / Netflix's second button is a different
// verb, never "open what you are already looking at".
// =====================================================================================

// -------------------------------------------------------------------------------------
// The classifier
// -------------------------------------------------------------------------------------

/** What kind of moment the hero (or a queue row) is describing. */
@Immutable
sealed interface FocusKind {

    /** A drop has aired that you have not watched. */
    @Immutable
    data class Fresh(val behind: Int) : FocusKind

    /** Mid-watch, off any airing schedule. */
    @Immutable
    data class Backlog(val left: Int) : FocusKind

    /** Nothing left to mark. */
    @Immutable
    data object CaughtUp : FocusKind

    /** The next episode is dated and has not struck. */
    @Immutable
    data class Waiting(val at: Long) : FocusKind
}

/**
 * The classifier, evaluated **on the object, not on the live feed** — a pinned snapshot keeps its
 * wording while the hero shows the result of a mark that has already moved the feed on.
 *
 * Every freshness test reads the airings-derived values (`behind` / `lastAired`), never the
 * catalogue's counts: reading the raw fields made the one show that had just aired (6:30 PM) the
 * one show Today could not see for an hour — not fresh (count unchanged), not waiting (slot
 * passed), gone.
 */
fun focusKind(f: Franchise, now: Long, justCaught: Set<String>): Pair<FocusKind, FranchisePart>? {
    val releasing = f.releasingPart
    if (releasing != null) {
        val behind = releasing.behind(now, f.timeAnchor)
        val last = releasing.lastAired(now, f.timeAnchor) ?: 0L
        if (now - last <= ShelfWindows.OUT_NOW && (behind > 0 || justCaught.contains(f.id))) {
            return if (behind > 0) {
                FocusKind.Fresh(behind) to releasing
            } else {
                FocusKind.CaughtUp to releasing
            }
        }
    }
    f.resumePart?.let { return FocusKind.Backlog(f.continueBacklog) to it }
    if (releasing != null) {
        f.nextAiring(now)?.let { return FocusKind.Waiting(it) to releasing }
    }
    return null
}

/**
 * The classifier for the CALM hero, and only for it.
 *
 * The calm hero exists **because the focus stack is empty**, so there is nothing to mark on it; and
 * under `calmDemo` the stack is emptied by force on a library that *is* behind, where [focusKind]
 * would hand the calm hero a CTA.
 */
fun calmFocusKind(f: Franchise, now: Long): Pair<FocusKind, FranchisePart>? {
    val releasing = f.releasingPart
    if (releasing != null) {
        f.nextAiring(now)?.let { return FocusKind.Waiting(it) to releasing }
    }
    val part = f.resumePart
        ?: releasing
        ?: f.episodicPartsInOrder.lastOrNull()
        ?: f.parts.firstOrNull()
        ?: return null
    return FocusKind.CaughtUp to part
}

/** How many episodes this kind leaves unwatched — what the CTA and its batch menu are sized by. */
val FocusKind.outstanding: Int
    get() = when (this) {
        is FocusKind.Fresh -> behind
        is FocusKind.Backlog -> left
        else -> 0
    }

// -------------------------------------------------------------------------------------
// The slate
// -------------------------------------------------------------------------------------

/** The four lines, the bar and the one action — computed once, drawn by [HeroFocus]. */
@Immutable
data class HeroSlate(
    val eyebrow: String,
    val eyebrowDot: Boolean,
    val headline: String?,
    val title: String,
    val fact: String,
    val support: String?,
    val progress: Float?,
    val progressSpoken: String?,
    val ctaEpisode: Int?,
    val outstanding: Int,
)

/**
 * Build the slate for one franchise.
 *
 * @param committedEpisode the episode a mark **on this card** has just written, or `null`. While it
 *   is set the whole meta block advances in the SAME FRAME as the button's label — see the
 *   committed branch below; a capsule that says "Episode 19 watched" over a pill still reading
 *   "9 episodes behind" reports two different truths about one tap.
 * @param nextPremiere `appModel.nextPremiere(f)` — the caught-up hero's one support line.
 */
fun heroSlate(
    f: Franchise,
    kind: FocusKind,
    part: FranchisePart,
    now: Long,
    committedEpisode: Int?,
    nextPremiere: Long?,
): HeroSlate {
    val anchor = f.timeAnchor
    val outstanding = kind.outstanding
    val lastAired = f.lastAired(now)
    // "It has literally aired just now" is the news the person opened the app for.
    val struckToday = lastAired != null && now - lastAired <= ShelfWindows.NOW_BAR_LIVE

    if (committedEpisode != null) {
        val advanced = advancedFrame(f, part, kind, committedEpisode, outstanding, now)
        val bar = heroProgress(kind, part, committedEpisode, now, anchor)
        return HeroSlate(
            eyebrow = advanced.eyebrow,
            // In the committed frame the dot is forced off: nothing is pulsing, a write has landed.
            eyebrowDot = false,
            // The headline is suppressed — the moment is the mark, not the clock.
            headline = null,
            title = f.displayTitle,
            fact = advanced.fact,
            support = advanced.support,
            progress = bar?.first,
            progressSpoken = bar?.second,
            ctaEpisode = committedEpisode,
            outstanding = outstanding,
        )
    }

    val eyebrow = when (kind) {
        is FocusKind.Fresh -> when {
            struckToday && lastAired != null -> TemporalCopy.aired(lastAired, now, f.source)
            kind.behind > 1 -> Copy.Progress.behind(kind.behind)
            lastAired != null -> TemporalCopy.aired(lastAired, now, f.source)
            else -> Copy.Label.newEpisode
        }
        // "Last episode of the season" is a fact worth more than the numeral 1.
        is FocusKind.Backlog ->
            if (kind.left > 1) Copy.Progress.left(kind.left) else Copy.Progress.lastEpisodeOfTheSeason
        FocusKind.CaughtUp -> Copy.Progress.caughtUp
        // Just the DAY. "NEW EPISODE TODAY" said in three words what the pill's day and the
        // headline's clock already say between them. A date-only source has no clock to follow it
        // with, so the day word moves to the headline and the pill states the kind of moment.
        is FocusKind.Waiting ->
            if (anchor.isDateOnly) Copy.Label.newEpisode
            else TemporalCopy.airsCompact(kind.at, now, anchor)
    }

    // A days-old drop with a backlog is a count, not a pulse.
    val dot = when (kind) {
        is FocusKind.Fresh -> struckToday
        is FocusKind.Waiting -> f.dayDiff(kind.at, now) == 0
        else -> false
    }

    // Only a moment earns a headline. An aired episode has none — there the show and the action
    // are the news.
    val headline = (kind as? FocusKind.Waiting)?.let {
        if (anchor.isDateOnly) TemporalCopy.airsCompact(it.at, now, anchor)
        else Formatting.fmtTime(it.at, anchor)
    }

    val fact = heroFact(f, kind, part, now)

    val support = when (kind) {
        // The count only when NOTHING is watched yet and the pill spent itself on the recency.
        // "Latest aired 28 Aug" under "9 EPISODES BEHIND" was a second sentence about one fact.
        is FocusKind.Fresh ->
            if (part.progress == 0 && kind.behind > 1 && struckToday) {
                Copy.Progress.behind(kind.behind)
            } else {
                null
            }
        FocusKind.CaughtUp -> {
            val next = part.nextAiringAt
            when {
                next != null && next > now -> TemporalCopy.airs(next, now, f.source)
                nextPremiere != null -> TemporalCopy.returns(nextPremiere, now, f.source)
                else -> null
            }
        }
        else -> null
    }

    val bar = heroProgress(kind, part, null, now, anchor)
    return HeroSlate(
        eyebrow = eyebrow,
        eyebrowDot = dot,
        headline = headline,
        title = f.displayTitle,
        fact = fact,
        support = support,
        progress = bar?.first,
        progressSpoken = bar?.second,
        // Only when there is something to mark. A calm hero carries NO action row at all — the art,
        // the state and the moment, tap to open.
        ctaEpisode = if (outstanding > 0) part.progress + 1 else null,
        outstanding = outstanding,
    )
}

private fun heroFact(f: Franchise, kind: FocusKind, part: FranchisePart, now: Long): String {
    // A caught-up show whose season is finished names the SEASON, not a nonexistent next episode.
    if (kind is FocusKind.CaughtUp &&
        (part.isComplete || (part.progress >= maxOf(part.totalEpisodes, 1) && !part.isReleasing))
    ) {
        return part.canonicalLabel.ifEmpty { part.title }
    }
    if (kind is FocusKind.Waiting) {
        val episode = f.watchContext(part, part.nextEpisodeNumber ?: part.airedEpisodes + 1)
        val anchor = f.timeAnchor
        // The countdown rides along ONLY inside the day: "in 3h 12m" is the thing to be excited
        // about, "in 4d 2h" is arithmetic.
        if (anchor.isDateOnly || kind.at <= now || kind.at - now >= ShelfWindows.NOW_BAR_LIVE) {
            return episode
        }
        return "in ${Formatting.fmtCountdown(kind.at, now, anchor)} $MIDDLE_DOT $episode"
    }
    return f.watchContext(part, part.progress + 1)
}

private data class AdvancedFrame(val eyebrow: String, val fact: String, val support: String?)

/**
 * The committed frame: the eyebrow, fact, support and bar advance in the same frame as the button's
 * label.
 *
 * The `left == 0` branch is the one worth reading twice. The button already says "Episode 19
 * watched", so the footnote says what comes NEXT — and it says it about **episode 20**. A bare
 * "Friday at 7:30 PM" printed under "Season 4 · Episode 19" is the identical grammar this screen
 * uses for a future airing, so the line read as "Episode 19 airs Friday" — about an episode the
 * user had just told the app they already watched.
 */
private fun advancedFrame(
    f: Franchise,
    part: FranchisePart,
    kind: FocusKind,
    episode: Int,
    outstanding: Int,
    now: Long,
): AdvancedFrame {
    val left = maxOf(0, outstanding - 1)
    if (left == 0) {
        val next = part.nextAiringAt
            ?.takeIf { it > now }
            ?.let { at ->
                val phrase = midSentence(TemporalCopy.airs(at, now, f.source))
                "${Copy.episode(episode + 1)} airs $phrase"
            }
        return AdvancedFrame(
            eyebrow = Copy.Progress.caughtUp,
            fact = f.watchContext(part, episode),
            support = next,
        )
    }
    val count =
        if (kind is FocusKind.Backlog) Copy.Progress.left(left) else Copy.Progress.behind(left)
    return AdvancedFrame(
        eyebrow = count,
        fact = f.watchContext(part, episode + 1),
        support = if (left == 1) Copy.Progress.caughtUpAfterThisEpisode else null,
    )
}

/**
 * Lower-cases **only** the ordinary adverbs. "Friday", "Aug 28" and "Sun" are proper nouns and a
 * sentence does not get to lower-case them.
 */
private fun midSentence(phrase: String): String {
    val adverbs = listOf("Today", "Tomorrow", "Yesterday")
    val lead = adverbs.firstOrNull { phrase.startsWith(it) } ?: return phrase
    return lead.lowercase() + phrase.substring(lead.length)
}

/**
 * Where-you-are, wordless — the ratio and the string a screen reader hears for it.
 *
 * `null` when nothing is watched or everything is: a full bar and an empty one are both noise. The
 * denominator is the question being asked — what has AIRED for a fresh drop, what is AVAILABLE for
 * a backlog — because "how far behind the broadcast am I" and "how much of this season is left" are
 * two different questions and one denominator answers one of them wrongly.
 *
 * The bar is silent without the string: an unlabelled `ProgressBar` is hidden from the tree, and a
 * label set on a hidden element from the outside is silently dropped — which is how the hero's
 * count came to be spoken to nobody.
 */
private fun heroProgress(
    kind: FocusKind,
    part: FranchisePart,
    committed: Int?,
    now: Long,
    anchor: TimeAnchor,
): Pair<Float, String>? {
    val done = committed ?: part.progress
    val total = when (kind) {
        is FocusKind.Fresh -> part.airedByNow(now, anchor)
        is FocusKind.Backlog -> part.availableEpisodes()
        else -> return null
    }
    if (total <= 0 || done <= 0 || done >= total) return null
    val remaining = maxOf(0, total - done)
    val spoken = when (kind) {
        is FocusKind.Fresh -> Copy.Progress.behind(remaining)
        is FocusKind.Backlog -> Copy.Progress.left(remaining)
        else -> return null
    }
    return (done.toFloat() / total.toFloat()) to spoken
}

/** U+00B7, the separator every fact line in the app uses. */
private const val MIDDLE_DOT = "·"

// -------------------------------------------------------------------------------------
// The frame
// -------------------------------------------------------------------------------------

/**
 * Which photograph the billboard is showing. Equality is on the URL and its shape, because **the
 * art is keyed on the PHOTOGRAPH, not on the franchise id**: the image only has reason to dissolve
 * when the image changes, so two shows sharing a hero asset hand over without a flicker.
 */
@Immutable
data class HeroArt(val url: String?, val portraitSource: Boolean)

/**
 * The billboard's art, cover-first.
 *
 * **Cover first, banner as the fallback** — the inverse of Detail's order. This frame is ~72 % of
 * the screen at ~0.64 w/h, and a ~1900×400 banner filled into it is upscaled ~4.6× to a sliver of
 * itself ("why does it appear so zoomed in?"). The 2:3 cover is within 4 % of the frame's own
 * aspect, so the composite path shows it whole and sharp over its own blurred edges — the Netflix
 * mobile-billboard anatomy.
 */
fun heroArt(f: Franchise?, fallbackCover: String? = null): HeroArt {
    val portrait = f?.portraitArt
    if (!portrait.isNullOrEmpty()) return HeroArt(portrait, portraitSource = true)
    val landscape = f?.landscapeArt
    if (!landscape.isNullOrEmpty()) return HeroArt(landscape, portraitSource = false)
    return HeroArt(fallbackCover, portraitSource = true)
}

/** The same rule for a chart row, which carries no parts to fall back through. */
fun heroArt(item: FranchiseSummary): HeroArt {
    val portrait = item.portraitArt
    if (!portrait.isNullOrEmpty()) return HeroArt(portrait, portraitSource = true)
    return HeroArt(item.landscapeArt, portraitSource = false)
}

/**
 * The billboard's height: 0.72 × the SCREEN, grown by the copy's overflow.
 *
 * 0.72 is measured against Apple TV Home — its hero CTA bottoms out at ~70 % of the screen and the
 * next shelf header sits at ~83 %, so at 0.72 the copy block lands on the same line and the queue's
 * first row peeks above the tab bar as the scroll affordance.
 *
 * The frame grows by the copy's **overflow**, not by a guessed accessibility bump, and there is no
 * layout cycle because the copy's height depends only on the available width, never on this.
 */
@Composable
fun heroHeight(copyHeight: Dp): Dp =
    billboardHeight(
        fraction = Billboard.today,
        copyHeight = copyHeight,
        artBand = if (isAccessibilityTextSize()) HeroArtBandAX else HeroArtBand,
    )

/** The least photograph that must survive above the copy. */
private val HeroArtBand = 132.dp
private val HeroArtBandAX = 210.dp

/**
 * The whole billboard frame: ground, art, copy scrim, the caller's copy, and the top veil.
 *
 * ### Three ordering constraints that are bugs if broken
 *
 * 1. **The persistent ground sits outside the art's own hand-over.** The handoff finishes the
 *    removal before it starts the insertion, which means for ~80 ms there is a gap with nothing in
 *    it — and a 72 %-of-screen frame rendered bare `#09090B` in the middle of the app's signature
 *    moment.
 * 2. **The frame clips.** A card that is leaving keeps the size it had when it left, so during the
 *    recap → focus shrink the outgoing recap card (last laid out at ~880 dp) hung in the vacated
 *    space and drew over `UPCOMING` and the first shelf row for ~130 ms. iOS has to mask one edge
 *    only, because its pull-stretched art must keep drawing *above* this frame; Android's overscroll
 *    stretches the whole scroll container instead (`fidelity-line.md` Q6), so nothing needs to
 *    escape and a plain clip is the native answer.
 * 3. **The top veil is inside the frame**, over the art and under nothing: attached below the
 *    status bar it leaves the clock on bare art with a hard seam under it.
 *
 * The frame does **not** consume the status-bar inset — the window is edge-to-edge and the art
 * bleeds into the bar by simply starting at the top of it, which is what iOS spends a negative top
 * padding to reproduce.
 *
 * @param band the chrome band the top veil holds through: the status bar plus the wordmark row.
 * @param animateHeight `false` for the frame the recap arrives on — it must be the first thing on
 *   screen, not something that grows into place.
 */
@Composable
fun HeroFrame(
    height: Dp,
    art: HeroArt,
    tint: Color?,
    scrimBottom: Float,
    copyHeight: Dp,
    band: Dp,
    reduceMotion: Boolean,
    modifier: Modifier = Modifier,
    animateHeight: Boolean = true,
    overlay: @Composable BoxScope.() -> Unit,
) {
    // The shrink from the recap's floor to the hero's own height is ONE move. It used to be two —
    // the card shrank and settled, and only in that animation's completion did a second animation
    // insert the strip and shove everything under it down ~60 dp on another curve, so the screen
    // appeared to finish and then jumped.
    //
    // Held in an `Animatable` rather than an `animateDpAsState` so the ARRIVAL can snap: the recap
    // must be the first thing on screen, not something that grows into place. (iOS spends a
    // transaction with animations disabled on the same assignment.) The read below re-runs this
    // composable — and only this one — for the length of the shrink; the screen that owns it is
    // untouched.
    val animated = remember { Animatable(height, Dp.VectorConverter) }
    LaunchedEffect(height, animateHeight) {
        if (!animateHeight) animated.snapTo(height) else animated.animateTo(height, ThemeMotion.uiSettle())
    }
    val drawnHeight = animated.value

    Box(
        modifier
            .fillMaxWidth()
            .height(drawnHeight)
            .clipToBounds()
    ) {
        // 1 — the persistent ground. It survives both cards; see the doc above.
        Box(Modifier.matchParentSize().background(tint ?: ArtGround.neutralWarm))

        // 2 — the photograph, handed over on `handoff` when the photograph itself changes.
        AnimatedContent(
            targetState = art,
            transitionSpec = { ThemeMotion.handoff(reduceMotion) },
            label = "heroArt",
        ) { current ->
            StretchingHeroArt(
                art = current,
                height = drawnHeight,
                tint = tint,
                scrimBottom = scrimBottom,
            )
        }

        // 3 — protection behind the copy, sized to the copy's MEASURED height.
        HeroCopyScrim(copyHeight = copyHeight, modifier = Modifier.align(Alignment.BottomStart))

        // 4 — the caller's copy.
        Box(
            Modifier
                .align(Alignment.BottomStart)
                .fillMaxWidth()
                .padding(horizontal = ThemeMetrics.gutter)
                .padding(bottom = if (isAccessibilityTextSize()) ThemeSpace.x5 else ThemeSpace.x4),
            content = overlay,
        )

        HeroTopVeil(band = band, modifier = Modifier.align(Alignment.TopStart))
    }
}

/**
 * The billboard's artwork layer.
 *
 * The name is kept from iOS, where this view grows the art by the pull-down rubber band and is one
 * of only three views permitted to read the scroll offset. **On Android it reads no offset at all,
 * and that is the correct answer** (`fidelity-line.md` Q6): the platform stretches the whole scroll
 * container natively, so intercepting `onPreScroll` to rebuild iOS's curve is exactly the heavy
 * engineering the fidelity line rules out. The billboard keeps its identity through its size, art
 * and copy hierarchy — which is what makes it a billboard — not through a particular rubber band.
 *
 * The **drift** stays, because it is the app's own motion: ~7 % over 24 s, eased, reversing,
 * anchored at the top, off under Reduce Motion, and applied as one transform on one layer so no
 * body re-evaluates for it.
 */
@Composable
private fun StretchingHeroArt(
    art: HeroArt,
    height: Dp,
    tint: Color?,
    scrimBottom: Float,
    modifier: Modifier = Modifier,
) {
    ArtHeader(
        url = art.url,
        height = height,
        modifier = modifier,
        tint = tint,
        // Today's billboard carries a HeroTopVeil of its own and a measured copy scrim, so the
        // fractional scrim is off at both ends — except while the recap is on stage, where its copy
        // fills the frame and the whole image is meant to step back.
        scrimTop = 0f,
        scrimBottom = scrimBottom,
        // Faces live in the upper third of a key visual and in the upper half of a cover; a centred
        // crop of either is a chin.
        focus = Alignment.TopCenter,
        portraitSource = art.portraitSource,
        drift = true,
    )
}

// -------------------------------------------------------------------------------------
// The copy
// -------------------------------------------------------------------------------------

/**
 * The hero's copy block and its one action.
 *
 * The whole copy block is a single button that opens the show, combined into one screen-reader
 * element; the capsule is its own element beside it.
 *
 * @param interactive `false` while a card is still arriving. Without it the hero is a trap: the
 *   committed state clears at 650 ms and the next show's card fades in over ~460 ms with its Mark
 *   button already live and hit-testable at partial opacity, so a user clearing three episodes has
 *   tap 2 swallowed and tap 3 land on a half-faded button belonging to a *different franchise*.
 */
@Composable
fun HeroFocus(
    slate: HeroSlate,
    fullTitle: String,
    committed: Boolean,
    interactive: Boolean,
    onOpen: () -> Unit,
    onMark: () -> Unit,
    onMarkThrough: (Int) -> Unit,
    onMarkAll: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isAX = isAccessibilityTextSize()

    Column(modifier.fillMaxWidth()) {
        Column(
            Modifier
                .fillMaxWidth()
                .clickable(
                    interactionSource = null,
                    indication = PressStyle.overArt,
                    enabled = interactive,
                    onClickLabel = Copy.Accessibility.opensTheShowHint,
                    role = Role.Button,
                    onClick = onOpen,
                )
                // `children: .combine` — pill, headline, show, fact and bar are one utterance.
                .semantics(mergeDescendants = true) {}
        ) {
            OverArtLabel(text = slate.eyebrow, dot = slate.eyebrowDot)

            if (slate.headline != null) {
                // The one amber WORD above the fold, and it is a fact — the clock — never an action.
                NumericLine(
                    text = slate.headline,
                    modifier = Modifier.padding(top = ThemeSpace.x3),
                ) { text ->
                    AutoSizeText(
                        text = text,
                        style = HeadlineStyle,
                        minScale = HeadlineMinimumScale,
                        maxLines = 1,
                    )
                }
            }

            // The show steps DOWN a size when a headline is above it, because the art is already
            // saying its name. The hero may never ellipsize the one name the screen exists to show.
            AutoSizeText(
                text = slate.title,
                style = when {
                    slate.headline != null -> ThemeType.showTitleL
                    isAX -> ThemeType.displayXL
                    else -> ThemeType.heroTitle
                }.copy(color = ThemeColor.textPrimary),
                minScale = TitleMinimumScale,
                maxLines = if (isAX) 3 else 2,
                modifier = Modifier.padding(
                    top = if (slate.headline == null) ThemeSpace.x3 else ThemeSpace.x2,
                ),
            )

            // `textSecondary` on purpose, so the title and "Season 4 · Episode 12" never read as
            // one line.
            NumericLine(
                text = slate.fact,
                modifier = Modifier.padding(top = ThemeMetrics.titleGap),
            ) { text ->
                BasicText(
                    text = text,
                    style = ThemeType.heroMeta,
                    color = ColorProducer { ThemeColor.textSecondary },
                )
            }

            if (slate.progress != null) {
                ProgressBar(
                    value = slate.progress,
                    spoken = slate.progressSpoken,
                    modifier = Modifier
                        .padding(top = ThemeSpace.x2)
                        .then(
                            if (isAX) Modifier.fillMaxWidth() else Modifier.width(HeroProgressWidth),
                        ),
                )
            }

            if (slate.support != null) {
                BasicText(
                    text = slate.support,
                    style = ThemeType.metadata,
                    color = ColorProducer { ThemeColor.textSecondary },
                    modifier = Modifier.padding(top = ThemeSpace.x0_5),
                )
            }
        }

        if (slate.ctaEpisode != null) {
            MarkSplitButton(
                episode = slate.ctaEpisode,
                committed = committed,
                behind = slate.outstanding,
                // The MENU names the show in full: with two number-carrying commands floating free
                // the reader had to reconstruct whose episodes "2–5" are.
                title = fullTitle,
                // The capsule is NOT disabled while a card is arriving — it is the screen's write
                // guard (`handoffInFlight`) that refuses the tap, so the control never renders as a
                // dead object mid-handover and a mark that lands one frame early is simply ignored.
                onMark = onMark,
                onMarkThrough = onMarkThrough,
                onMarkAll = onMarkAll,
                modifier = Modifier
                    .padding(top = if (isAX) ThemeSpace.x5 else ThemeSpace.x4)
                    .fillMaxWidth(),
            )
        }
    }
}

/**
 * **An empty account opens on television.**
 *
 * Apple TV's and Netflix's first screen is never a sentence on a black canvas; it is television
 * with a way in. Same billboard, same slate order, one capsule.
 */
@Composable
fun TrendingFocus(
    item: FranchiseSummary,
    owned: Boolean,
    onOpen: () -> Unit,
    onAdd: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isAX = isAccessibilityTextSize()
    val identity = remember(item.source, item.year) {
        listOfNotNull(item.source.kindWord, item.year?.toString()).joinToString(" $MIDDLE_DOT ")
    }

    Column(modifier.fillMaxWidth()) {
        Column(
            Modifier
                .fillMaxWidth()
                .clickable(
                    interactionSource = null,
                    indication = PressStyle.overArt,
                    onClickLabel = Copy.Accessibility.opensTheShowHint,
                    role = Role.Button,
                    onClick = onOpen,
                )
                .semantics(mergeDescendants = true) {}
        ) {
            OverArtLabel(text = Copy.Label.trending)
            AutoSizeText(
                text = item.title.shelfShortened,
                style = (if (isAX) ThemeType.displayXL else ThemeType.heroTitle)
                    .copy(color = ThemeColor.textPrimary),
                minScale = TitleMinimumScale,
                maxLines = if (isAX) 3 else 2,
                modifier = Modifier.padding(top = ThemeSpace.x3),
            )
            if (identity.isNotEmpty()) {
                BasicText(
                    text = identity,
                    style = ThemeType.heroMeta,
                    color = ColorProducer { ThemeColor.textSecondary },
                    modifier = Modifier.padding(top = ThemeMetrics.titleGap),
                )
            }
        }

        PrimaryButton(
            label = if (owned) Copy.Search.inLibrary else Copy.Search.addToLibrary,
            onClick = onAdd,
            enabled = !owned,
            modifier = Modifier
                .padding(top = if (isAX) ThemeSpace.x5 else ThemeSpace.x4)
                .fillMaxWidth(),
        )
    }
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
private fun NumericLine(
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

/**
 * The clock, at display size, in accent, with tabular figures.
 *
 * Derived here rather than added to the type palette: it is `displayXL` plus iOS's call-site
 * `.monospacedDigit()`, and a counter that re-flows while it counts is a bug you can see.
 */
private val HeadlineStyle = ThemeType.displayXL.copy(
    color = ThemeColor.accent,
    fontFeatureSettings = "tnum",
)

/** iOS `.minimumScaleFactor(0.7)` on the headline, `0.85` on the title. */
private const val HeadlineMinimumScale = 0.7f
private const val TitleMinimumScale = 0.85f

/** The bar is a measurement, not a banner: it stops well short of the gutter at ordinary sizes. */
private val HeroProgressWidth = 200.dp

// -------------------------------------------------------------------------------------
// The palette
// -------------------------------------------------------------------------------------

/**
 * The show's own colour, for the billboard's persistent ground.
 *
 * The decode budget is **not** stated here. `ArtPaletteCache` owns its own 64-px sample
 * (`ArtMaxPixel.PALETTE_SAMPLE`), served from the disk cache or coalesced with the display fetch —
 * a caller-supplied palette size is a second entry into the pipeline, and the pipeline has one.
 * `rememberArtTint` also seeds itself from the cache synchronously, so a re-entered screen paints
 * its ground on frame one rather than opening black and stepping to the real colour.
 *
 * @param onResolved every successful resolve, so the screen can remember the last hero tint across
 *   launches. The loading frame is the first thing a returning user sees and has no artwork yet by
 *   definition, so without it the skeleton's hero band is a black rectangle — and the hero rarely
 *   changes between two opens.
 */
@Composable
fun rememberHeroTint(url: String?, onResolved: (Color) -> Unit = {}): Color? {
    val tint = rememberArtTint(url)
    LaunchedEffect(tint) { if (tint != null) onResolved(tint) }
    return tint
}
