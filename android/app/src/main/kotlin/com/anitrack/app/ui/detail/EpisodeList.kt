package com.anitrack.app.ui.detail

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.text.BasicText
import androidx.compose.material3.AlertDialog
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.anitrack.app.AppModel
import com.anitrack.app.data.SessionResets
import com.anitrack.app.data.SyncCenter
import com.anitrack.app.data.UndoState
import com.anitrack.app.design.ContinuousCornerShape
import com.anitrack.app.design.FeedbackToken
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.PreviouslyMaterialBridge
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.artFrame
import com.anitrack.app.design.rememberSymbol
import com.anitrack.app.ui.AutoSizeText
import com.anitrack.app.ui.art.EpisodeArtworkDefaults
import com.anitrack.app.ui.art.EpisodeStill
import com.anitrack.app.ui.control.MarkRing
import com.anitrack.app.ui.control.MarkRingStyle
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.control.TertiaryButton
import com.anitrack.app.ui.control.materialGlyphBox
import com.anitrack.app.ui.control.minimumTapTarget
import com.anitrack.app.ui.negativePadding
import com.anitrack.model.ArtPalette as PaletteMath
import com.anitrack.model.Episode
import com.anitrack.model.Franchise
import com.anitrack.model.FranchisePart
import com.anitrack.model.MediaSource
import com.anitrack.model.OkLab
import com.anitrack.model.TemporalCopy
import com.anitrack.model.Time
import com.anitrack.model.TimeAnchor
import com.anitrack.model.copy.Copy
import com.anitrack.model.stillLandscape
import com.anitrack.model.markTarget
import com.anitrack.model.portraitArt
import com.anitrack.model.progressCeiling
import com.anitrack.model.provenAiredCount
import com.anitrack.model.renderableEpisodeCount
import com.anitrack.model.scheduledAiring
import com.anitrack.model.timeAnchor
import java.util.UUID
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import com.anitrack.app.data.ReceiptHost
import com.anitrack.app.ui.state.ReceiptLine
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.ceil
import com.anitrack.model.lastAired
import com.anitrack.app.design.LocalReduceMotion
import com.anitrack.app.design.ThemeMotion
import com.anitrack.app.ui.control.InlineLinkButton
import com.anitrack.model.Formatting

/*
 * DETAIL SUPPORT — the port of `ios/Sources/Features/FranchiseDetail/DetailSupport.swift`.
 *
 * `EpisodeRow` is **the one episode row anatomy in the app**, shared verbatim by the show page (a
 * six-row window) and by the season screen (the full run). Everything else here is the furniture
 * that row and the show page need: the metrics, the tint conditioner, the title sanitiser, the
 * withheld-still tile, the confirmation prompt, and the two process-scoped ledgers the milestone
 * motions claim through.
 *
 * ## Two rules that decide the shape of this file
 *
 * 1. **The full run must be LAZY.** One Piece Season 1 advertises ~1,140 episodes; eagerly building
 *    every row (each with a palette resolve) is a multi-second freeze on the push transition and a
 *    plausible watchdog termination. So the row is one composable and there are two hosts for it:
 *    [EpisodeListColumn] for the windowed six, and [episodeListItems] — a `LazyListScope` extension
 *    — for the season screen. There is still exactly ONE row.
 *
 * 2. **Every row carries a 120 × 68 tile.** The still, else the season's landscape art, else the
 *    season cover under the episode's number. The list used to drop the art column for any season
 *    under a third illustrated — most anime — and became a column of bare "Episode 12 / Aired 3 Jul"
 *    text (user, 2 Sep: "not there yet"). Never a bare text row, never a glyph.
 */

// =================================================================================================
// MARK: - Metrics
// =================================================================================================

/** Detail's own geometry. Nothing outside this area spends these. */
object DetailMetrics {

    /**
     * The floating toolbar's band below the status bar. Detail draws its own bar over the hero, so
     * the hero's top veil and the docked-title threshold both measure against this.
     */
    val toolbarClearance: Dp = 46.dp

    /** The extra room the floating `SyncBanner` needs, because it is drawn OVER content. */
    private val syncBannerClearance: Dp = 72.dp

    /**
     * The scroll's bottom clearance.
     *
     * A complete "Episode 11" row — tile, title and check — rendered in the strip between the
     * floating pill and the home indicator, and "Episode 10 · Mhysa" was sliced by the pill's edge
     * with its air date entirely covered, because padding inside the stack is not an inset for the
     * scroll view. On Android the honest form is a `LazyColumn` `contentPadding`, or a trailing
     * spacer inside a `verticalScroll` column — both extend the scrollable range, which is the
     * property that matters.
     *
     * It widens while a sync failure is pending: the banner floats over the content rather than
     * insetting it, so the content has to make room for it itself.
     */
    @Composable
    fun bottomClearance(): Dp =
        ThemeMetrics.tabBarClearance +
            if (SyncCenter.failedChanges.isEmpty()) 0.dp else syncBannerClearance

    // --- Glyphs -------------------------------------------------------------------------------
    //
    // Every one at its **iOS point size**; `materialGlyphBox` owns the SF → Material-box conversion
    // and is the one place that ratio may change. They are named here, together, because Detail and
    // the season screen draw the same controls and were spending the same numbers as bare literals
    // at eleven call sites across two files — while every other screen in the app names its glyph
    // set (`ScheduleMetrics.filterGlyph`, `AllTitlesMetrics.barGlyph`, …). A screen spends no
    // literal; a component is where its own anatomy lives.

    /** A floating-toolbar glyph, and a menu row's leading symbol or trailing tick. */
    val barGlyph: Dp = 15.dp

    /** The status chip's caret. Small on purpose: it hangs off a word, it is not a control. */
    val statusCaretGlyph: Dp = 9.dp

    /** The season picker's `unfold_more`. Never a chevron: this chooses in place, it does not push. */
    val pickerGlyph: Dp = 13.dp

    /** The synopsis-level "reveal episode title" toggle, which sits beside `metadata` text. */
    val revealGlyph: Dp = 11.dp

    /** The episode row's reveal eye, which sits in a full tap target of its own. */
    val rowRevealGlyph: Dp = 13.dp

    /** Between a word and the glyph that belongs to it — a picker's caret, a chip's. */
    val glyphGap: Dp = 6.dp

    /** The episode row's own vertical air inside its minimum height. */
    val episodeRowInset: Dp = 6.dp
}

// =================================================================================================
// MARK: - Copy
// =================================================================================================

// The show page's strings live in `Copy.Detail` (`:model`, `copy/CopyDetail.kt`), together with the
// shelf words `DetailShelves.kt` used to keep as file-private constants. Nothing on this track
// spells a sentence at a call site any more.


// =================================================================================================
// MARK: - Milestone ledgers
// =================================================================================================

/**
 * A process-scoped ring buffer of the last [CAPACITY] milestone tokens, so a milestone draws **once**
 * however many times its view is re-created.
 *
 * This cannot be composition state, and the case it exists for is precisely the view being
 * re-created while the milestone is still true: *"a card scrolled off and back, a tab switch or a
 * recycled row RE-CREATES this modifier with `progress` back at 0 and `initial: true` firing again,
 * which would replay the whole 520-ms draw for a milestone the user already saw."*
 *
 * [reset] is called on sign-out — the next account inherits nothing, not even a claimed token.
 */
object SeasonSweepLedger {

    private const val CAPACITY = 32

    private val claimed = ArrayDeque<String>(CAPACITY)

    init {
        // Sessions belong to the account that made them, milestones included: the next sign-in must
        // not inherit a claimed token and silently swallow the first sweep it earns.
        SessionResets.onSignOut { reset() }
    }

    /** True exactly once per token; every later call snaps the animation to done. */
    @Synchronized
    fun claim(token: String?): Boolean {
        if (token == null) return false
        if (claimed.contains(token)) return false
        if (claimed.size >= CAPACITY) claimed.removeFirst()
        claimed.addLast(token)
        return true
    }

    @Synchronized
    fun reset() {
        claimed.clear()
    }
}

/**
 * A one-shot hand-off so the watch-history rail draws a new session's arrival exactly once.
 *
 * *"The rail's new-session choreography … was specified, implemented in the design system and then
 * called from nothing but a `#Preview`: starting a rewatch and opening Watch history showed a fully
 * drawn rail with no arrival at all. The two surfaces are a push apart and neither owns the other's
 * state, so the hand-off is a one-shot token."*
 */
object RewatchArrival {

    private var pending: String? = null

    init {
        SessionResets.onSignOut { synchronized(this) { pending = null } }
    }

    @Synchronized
    fun record(id: String) {
        pending = id
    }

    @Synchronized
    fun claim(id: String): Boolean {
        if (pending != id) return false
        pending = null
        return true
    }
}

// =================================================================================================
// MARK: - DetailTint
// =================================================================================================

/**
 * Re-conditions an extracted palette colour into a **ground under type**.
 *
 * A tile ground is not a swatch: behind a numeral, at 120 × 68, an unquieted extraction reads as a
 * colour sample rather than as the show. In OKLab the chroma is clamped hard, the lightness pinned
 * into a narrow band, and the result mixed a fifth of the way toward `surfaceRaised`.
 *
 * The arithmetic lives in `:model` (`ArtPalette.oklab` / `.srgb`), which is where the whole
 * extraction pipeline lives and where it is unit-tested against the iOS numbers.
 */
object DetailTint {

    /** Chroma ceiling. Above this the ground competes with the type on it. */
    private const val CHROMA_MAX = 0.045

    private const val LIGHTNESS_MIN = 0.40
    private const val LIGHTNESS_MAX = 0.46

    /** How far the result is pulled toward `surfaceRaised`. */
    private const val NEUTRAL_MIX = 0.20f

    fun quiet(tint: Color?): Color? {
        val source = tint ?: return null
        val lab = PaletteMath.oklab(
            source.red.toDouble(),
            source.green.toDouble(),
            source.blue.toDouble(),
        )
        val chroma = hypot(lab.a, lab.b)
        val scale = if (chroma > CHROMA_MAX) CHROMA_MAX / chroma else 1.0
        val rgb = PaletteMath.srgb(
            OkLab(
                l = lab.l.coerceIn(LIGHTNESS_MIN, LIGHTNESS_MAX),
                a = lab.a * scale,
                b = lab.b * scale,
            ),
        )
        val neutral = ThemeColor.surfaceRaised
        return Color(
            red = mix(rgb.r.toFloat(), neutral.red),
            green = mix(rgb.g.toFloat(), neutral.green),
            blue = mix(rgb.b.toFloat(), neutral.blue),
        )
    }

    private fun mix(value: Float, toward: Float): Float =
        (value * (1f - NEUTRAL_MIX) + toward * NEUTRAL_MIX).coerceIn(0f, 1f)

    /**
     * The hardened bar's ink for a show page: the art colour kept as a HUE, dark enough to be a bar
     * (OKLab lightness 0.20–0.26 — canvas is ~0.10, [quiet] sits at 0.40–0.46 for a tile), a little
     * more chroma than a tile so the colour survives the material. Painted at `chromeBarOpacity`
     * over the blur it is the show's own glass; the flat canvas veil read as a black slab over the
     * picture ("too blackish anyway, should be glassish", user, 4 Sep).
     */
    fun chrome(tint: Color?): Color? {
        val source = tint ?: return null
        val lab = PaletteMath.oklab(
            source.red.toDouble(),
            source.green.toDouble(),
            source.blue.toDouble(),
        )
        val chroma = hypot(lab.a, lab.b)
        val scale = if (chroma > CHROME_CHROMA_MAX) CHROME_CHROMA_MAX / chroma else 1.0
        val rgb = PaletteMath.srgb(
            OkLab(
                l = lab.l.coerceIn(CHROME_LIGHTNESS_MIN, CHROME_LIGHTNESS_MAX),
                a = lab.a * scale,
                b = lab.b * scale,
            ),
        )
        return Color(
            red = rgb.r.toFloat().coerceIn(0f, 1f),
            green = rgb.g.toFloat().coerceIn(0f, 1f),
            blue = rgb.b.toFloat().coerceIn(0f, 1f),
        )
    }

    private const val CHROME_CHROMA_MAX = 0.07
    private const val CHROME_LIGHTNESS_MIN = 0.20
    private const val CHROME_LIGHTNESS_MAX = 0.26
}

/**
 * OKLab lightness of a resolved palette colour — the hero bloom's "is this show dark?" test.
 *
 * Measured off the palette colour, **not** off a second decode of the image.
 */
internal fun oklabLightness(color: Color): Double =
    PaletteMath.oklab(color.red.toDouble(), color.green.toDouble(), color.blue.toDouble()).l

// =================================================================================================
// MARK: - EpisodeCopy
// =================================================================================================

/**
 * The episode-title sanitiser. Returns `null` when there is no REAL title.
 *
 * The flagship show's first row read `Episode 1 · Episode  - That Time I Got Reincarnated as a
 * Slime…`: the word "Episode" twice, a double space, a dangling hyphen, the franchise's own title
 * inside its episode title, and then ellipsised.
 *
 * Step 6 is a **prefix** test rather than equality, because AniList's episode-1 slot on that show
 * holds "the show's name, then a *different work*, then a promo tag". Anything that OPENS with the
 * show's own name is a catalogue string, not the name of an episode.
 */
object EpisodeCopy {

    private val whitespaceRun = Regex("\\s+")

    /** A leading "Episode", "Episode 4", "Episode 4 - " and every punctuation shape between. */
    private val episodePrefix = Regex("^[Ee]pisode\\s*\\d*\\s*[-–—:·]?\\s*")

    /** Trimmed from BOTH ends after the prefix strip. */
    private const val EDGE_PUNCTUATION = " -–—:·"

    /** A catalogue string that names a promo rather than an episode. */
    private val promoSuffixes = listOf("trailer", "teaser", "promo", " pv", "preview")

    fun title(raw: String?, franchise: String): String? {
        if (raw == null) return null
        // The double space came from an empty numeral slot in the catalogue's own template.
        var s = whitespaceRun.replace(raw, " ")
        s = episodePrefix.replace(s, "")
        s = s.trim { EDGE_PUNCTUATION.contains(it) }
        if (s.isEmpty()) return null
        val lower = s.lowercase()
        // Guarded on a non-empty title first: `startsWith("")` is always true, and an untitled show
        // would otherwise null every episode title it has.
        if (franchise.isNotEmpty() && lower.startsWith(franchise.lowercase())) return null
        if (lower.startsWith("episode")) return null
        if (promoSuffixes.any { lower.endsWith(it) }) return null
        return s
    }
}

// =================================================================================================
// MARK: - Confirmations
// =================================================================================================

/**
 * A pending write that states its exact blast radius.
 *
 * iOS presents this through `confirmationDialog`; Android's convention is a dialog, so the *strings*
 * port and the *mechanism* is native ([WritePromptDialog]).
 */
@Immutable
data class WritePrompt(
    val title: String,
    val message: String,
    val confirm: String,
    val destructive: Boolean = false,
    val perform: () -> Unit,
) {
    val id: String = UUID.randomUUID().toString()
}

/**
 * The dialog. Wrapped in [PreviouslyMaterialBridge] because `AlertDialog` reads its container colour
 * and two of its type roles from `MaterialTheme`, and this app installs none at its root — an
 * unmapped role there is not a tint error, it is a white slab.
 *
 * **Every colour AND the shape are passed explicitly** — `state/Toast.kt` states the law: "a
 * component that inherits its colour from the scheme is a bug." This one used to pass
 * `containerColor` and no `shape`, so it inherited `AlertDialogDefaults.shape` → a plain
 * `RoundedCornerShape`, and it grounded on `canvasRaised` where every other confirmation in the app
 * grounds on `surfaceFloating`: Detail's and the Season screen's confirmation was a near-black plate
 * with circular corners while Today's, Schedule's and Profile's were a floating plate with
 * squircles. One gesture, two dialogs. The four values below are the same four
 * `DiscardChangesDialog`, `BatchMarkDialog` and Profile's confirmations pass.
 *
 * Both buttons are the app's own [TertiaryButton]: `interactive` ink, or `destructive` where the
 * command destroys something. Neither ever ends in an ellipsis (`Copy.Action`'s
 * `confirmationButtonViolations` must stay empty).
 */
@Composable
fun WritePromptDialog(prompt: WritePrompt?, onDismiss: () -> Unit) {
    if (prompt == null) return
    PreviouslyMaterialBridge {
        AlertDialog(
            onDismissRequest = onDismiss,
            shape = ContinuousCornerShape(ThemeRadius.card),
            containerColor = ThemeColor.surfaceFloating,
            titleContentColor = ThemeColor.textPrimary,
            textContentColor = ThemeColor.textSecondary,
            tonalElevation = 0.dp,
            title = {
                BasicText(
                    text = prompt.title,
                    style = ThemeType.showTitleL.copy(color = ThemeColor.textPrimary),
                )
            },
            text = {
                BasicText(
                    text = prompt.message,
                    style = ThemeType.callout.copy(color = ThemeColor.textSecondary),
                )
            },
            confirmButton = {
                TertiaryButton(
                    label = prompt.confirm,
                    destructive = prompt.destructive,
                    onClick = {
                        onDismiss()
                        prompt.perform()
                    },
                )
            },
            dismissButton = {
                TertiaryButton(label = Copy.Action.cancel, onClick = onDismiss)
            },
        )
    }
}

// =================================================================================================
// MARK: - WithheldStillTile
// =================================================================================================

/**
 * The tile for a still that EXISTS and is being withheld.
 *
 * Distinct from the shared `EpisodeGlyphTile` (`play.rectangle` = there is no still at all): a
 * withheld still is a choice the user can reverse, and `eye.slash` is the glyph on the control that
 * reverses it.
 *
 * No identifier is drawn on it. The tile it replaced printed `S7 · E2` built from `sequence`, which
 * *"on every AniList franchise with an OVA disagreed with the fact line 8 pt away ('Season 4 ·
 * Episode 19' beside 'S5 · E19'), broke the copy table's own notation rule twice over, and was the
 * screenshot attached to the one-star review."*
 */
@Composable
fun WithheldStillTile(tint: Color?, modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(EpisodeArtworkDefaults.slot.width, EpisodeArtworkDefaults.slot.height)
            .artFrame(ThemeRadius.episodeStill)
            .background(tint ?: ThemeColor.surfaceRaised)
            .background(
                Brush.verticalGradient(
                    listOf(Color.Black.copy(alpha = 0.10f), Color.Black.copy(alpha = 0.34f)),
                ),
            )
            .clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) {
        Image(
            imageVector = rememberSymbol(PreviouslyIcons.VisibilityOff),
            contentDescription = null,
            modifier = Modifier.size(materialGlyphBox(withheldGlyph)),
            colorFilter = ColorFilter.tint(ThemeColor.textPrimary.copy(alpha = 0.62f)),
        )
    }
}

// =================================================================================================
// MARK: - How many rows, and which
// =================================================================================================

/**
 * How many episode rows a part draws.
 *
 * `renderableEpisodeCount` is row plumbing and may extend one past what has aired so the next-to-air
 * row can carry its date badge; `progress` and the highest number the catalogue's own episode list
 * carries can each exceed it (a user who marked past the catalogue's count, a catalogue whose
 * episode list runs long).
 */
fun episodeListCount(part: FranchisePart, now: Long): Int = max(
    part.renderableEpisodeCount(now),
    max(part.progress, part.episodes.maxOfOrNull { it.number } ?: 0),
)

/**
 * **The list OPENS WHERE YOU ARE** (6 Sep, chosen on iOS from three photographed directions after
 * "what about the most recent episode? … otherwise it's a bigger scroll", user).
 *
 * A season of [WHOLE_BELOW] rows or fewer is drawn WHOLE — six to twelve rows is a screen and a
 * half, and folding three of Thrones' six to save half a screen is a fold for its own sake. A
 * longer one opens on the NEXT episode with [WINDOW_BEFORE] watched rows above it for context and
 * [WINDOW_AFTER] ahead; everything earlier is one in-place tap up, and the list grows by [GROW_BY]
 * a tap — Mail's "Load Earlier Messages": the list gets longer where it is, nothing is pushed.
 *
 * Measured before the change: Slime S4 (21 of 24 watched) put the next episode 1,842 pt down the
 * list. Plex users file the same thing as a bug when a long season fails to advance to the on-deck
 * episode (plex-media-player #914). Two directions were built, photographed and REJECTED: a whole
 * season from Episode 1 with an in-page "Jump to episode 22" link (the season's first twenty rows
 * are still what the screen opens on), and newest-first (Apple Podcasts' EPISODIC order — but
 * Apple itself puts the first episode at the top for SERIAL shows, and a TV season is serial).
 *
 * A finished season anchors at Episode 1: nothing to continue, so it is a browse.
 */
const val WHOLE_BELOW = 12
const val WINDOW_BEFORE = 3
const val WINDOW_AFTER = 8
const val GROW_BY = 12

/** The episode the list is ABOUT: the one a route asked for, else the next to watch, else the head. */
fun episodeAnchor(progress: Int, total: Int, focus: Int? = null): Int =
    focus ?: if (progress < total) progress + 1 else 1

/** The window a long run opens on, clamped into `1..total`. */
fun episodeWindow(anchor: Int, total: Int): IntRange {
    val a = min(max(1, anchor), max(1, total))
    return clampEpisodes((a - WINDOW_BEFORE)..(a + WINDOW_AFTER), total)
}

fun clampEpisodes(range: IntRange, total: Int): IntRange {
    val n = max(1, total)
    val lower = min(max(1, range.first), n)
    return lower..min(n, max(lower, range.last))
}

/**
 * The row that wears NEW: the newest AIRED episode, while it is still unwatched, on a season that
 * is actually RUNNING and whose latest drop is recent. All three conditions are load-bearing —
 * without the last two, The Witcher's finished 2023 season tagged its Episode 8 "NEW", which is a
 * label for news, not for the end of a list.
 */
fun freshEpisode(part: FranchisePart, total: Int, now: Long, anchor: TimeAnchor): Int? {
    if (!part.isReleasing) return null
    val aired = min(max(part.provenAiredCount(now), part.airedEpisodes), total)
    if (aired <= part.progress || aired < 1) return null
    val at = part.lastAired(now, anchor) ?: return null
    return if (now - at <= FRESH_WINDOW_MS) aired else null
}

/**
 * How long a drop stays news: a fortnight, so a weekly show's newest episode carries the tag until
 * the one after it lands, and a show that stopped mid-cour does not wear NEW for months.
 */
const val FRESH_WINDOW_MS: Long = 14L * 24 * 60 * 60 * 1000

/**
 * One week per episode, anchored on whichever real instant the part carries.
 *
 * Conservative by construction: it never runs forward past an anchor, and it never fires without
 * one — *"an invented date is worse than a blank."*
 */
internal fun derivedAirDate(part: FranchisePart, episode: Int): Long? {
    val week = 7L * Time.DAY_MS
    val next = part.nextAiringAt
    val nextNumber = part.nextEpisodeNumber
    if (next != null && nextNumber != null && nextNumber > episode) {
        return next - (nextNumber - episode).toLong() * week
    }
    val last = part.lastAiredAt
    if (last != null && part.airedEpisodes >= episode) {
        return last - (part.airedEpisodes - episode).toLong() * week
    }
    return null
}

/** `max(totalEpisodes, airedEpisodes)` — the header's total, which is NOT the list's row count. */
internal fun FranchisePart.headerTotal(): Int = max(totalEpisodes, airedEpisodes)

// =================================================================================================
// MARK: - The list's own state
// =================================================================================================

/**
 * The reveal set and the pending confirmation, hoisted out of the row so the season screen can host
 * the same rows inside a `LazyColumn`.
 *
 * **Re-key it on the part's `mediaId`**: a picker change must land on a fresh list rather than rows
 * morphing their numbers in place, and the reveal set belongs to the season that was on screen when
 * the user revealed something.
 */
@Stable
class EpisodeListController internal constructor(private val appModel: AppModel) {

    /** Insert only — **a row cannot be re-hidden.** */
    var revealed: Set<Int> by mutableStateOf(emptySet())
        private set

    var prompt: WritePrompt? by mutableStateOf(null)

    /** The one row whose details are open. Opening a row closes the last. */
    var expanded: Int? by mutableStateOf(null)
        private set

    /** The row whose ring is in its commit beat (accent, the check drawing) before it settles. */
    var committing: Int? by mutableStateOf(null)
        private set

    /**
     * A batch mark plays its discs in order: rows above this number are drawn UNMARKED until the
     * cascade reaches them (the model has already moved).
     */
    var cascadeThrough: Int? by mutableStateOf(null)
        private set

    /** The rows a long run shows; null until an expander is tapped. */
    var shown: IntRange? by mutableStateOf(null)
        private set

    private var commitJob: Job? = null
    private var cascadeJob: Job? = null

    fun reveal(episode: Int) {
        revealed = revealed + episode
    }

    /**
     * **The row OPENS, the ring MARKS.** Tapping a row never writes progress — Apple TV's tile
     * plays and its description opens the episode, Podcasts keeps "Mark as Played" off the row,
     * Reminders completes on the circle alone ("people sometimes are curious to see what the
     * episode details are and unintentionally might mark it as completed", user, 6 Sep).
     */
    fun open(episode: Int, canReveal: Boolean, hasOverview: Boolean) {
        if (canReveal) reveal(episode)
        if (!hasOverview) return
        expanded = if (expanded == episode) null else episode
    }

    /** The list grows in place, in either direction, by [GROW_BY]. */
    fun grow(current: IntRange, total: Int, earlier: Boolean) {
        val next = if (earlier) {
            (current.first - GROW_BY)..current.last
        } else {
            current.first..(current.last + GROW_BY)
        }
        shown = clampEpisodes(next, total)
    }

    /**
     * The commit beat: THIS ring is accent with its check drawing for ~0.55 s, then settles into
     * the show's colour. **The control is the receipt** — no line under the row says it again.
     */
    private fun beginCommit(scope: CoroutineScope, episode: Int, reduceMotion: Boolean) {
        commitJob?.cancel()
        committing = episode
        commitJob = scope.launch {
            delay(if (reduceMotion) 250 else 550)
            committing = null
        }
    }

    fun endCommit() {
        commitJob?.cancel()
        committing = null
    }

    /**
     * A batch plays its discs in order — a row every ~42 ms, at most 14 beats, the accent beat
     * travelling down the column — so twelve checks read as twelve marks made, not a list
     * re-rendered.
     */
    private fun cascade(scope: CoroutineScope, from: Int, through: Int, reduceMotion: Boolean) {
        cascadeJob?.cancel()
        commitJob?.cancel()
        if (through < from || reduceMotion) {
            cascadeThrough = null
            committing = null
            return
        }
        val step = max(1, ceil((through - from + 1) / 14.0).toInt())
        cascadeThrough = from - 1
        cascadeJob = scope.launch {
            var n = from - 1
            while (n < through) {
                delay(42)
                n = min(through, n + step)
                cascadeThrough = n
                committing = n
            }
            delay(450)
            cascadeThrough = null
            committing = null
        }
    }

    fun dispose() {
        commitJob?.cancel()
        cascadeJob?.cancel()
    }

    /**
     * Both the row body and the ring call this, and both are inert when the row is not interactive
     * (not in library, or unaired).
     *
     * Note there is **no local mark timeline** here — no pin, no 650-ms window, no staged check
     * beyond the ring's own: the row's tick draws immediately and the Undo toast is presented at
     * once. The staged timeline belongs to the state block's capsule, which is the control the eye
     * is already on when it fires.
     */
    fun tapped(
        franchise: Franchise,
        part: FranchisePart,
        episode: Int,
        watched: Boolean,
        scope: CoroutineScope,
        reduceMotion: Boolean,
    ) {
        val now = appModel.now
        val progress = part.progress
        when {
            // Un-marking the newest watched episode: immediate, with Undo. No confirmation — it
            // moves progress by exactly one and the toast puts it back.
            // The ring's OWN undo: the last watched episode toggles back — the disc opens into
            // the accent ring again. No confirmation, and no receipt: the control said it.
            watched && episode == progress -> {
                endCommit()
                appModel.setProgress(franchise.id, part.mediaId, episode - 1)
            }

            // Un-marking BACK to a mid point discards more than one episode of progress, so it
            // states its exact blast radius first.
            watched -> {
                endCommit()
                val target = episode - 1
                val count = max(1, abs(progress - target))
                prompt = WritePrompt(
                    title = Copy.Confirm.resetSeasonTitle(count),
                    message = Copy.Confirm.batchMarkMessage(from = progress, to = target),
                    confirm = Copy.Confirm.resetSeasonConfirm(count),
                ) {
                    val state = appModel.markThrough(
                        franchiseId = franchise.id,
                        mediaId = part.mediaId,
                        episode = target,
                        present = false,
                    ) ?: return@WritePrompt
                    appModel.presentUndo(
                        UndoState(
                            mediaId = state.mediaId,
                            franchiseId = state.franchiseId,
                            prevProgress = state.prevProgress,
                            title = state.title,
                            episode = state.episode,
                            count = state.count,
                            customMessage = Copy.Detail.batchMarkedUnwatched(state.count),
                            undoAction = state.undoAction,
                        ),
                    )
                }
            }

            // The next episode: immediate. One haptic for the transaction — `.success` when this
            // mark completes the season, else the light commit.
            episode == progress + 1 -> {
                val completes = episode >= part.markTarget(now) &&
                    !part.isReleasing &&
                    part.totalEpisodes > 0
                val undo = appModel.markNext(
                    franchiseId = franchise.id,
                    mediaId = part.mediaId,
                    haptic = if (completes) FeedbackToken.SUCCESS else FeedbackToken.COMMIT_LIGHT,
                ) ?: return
                beginCommit(scope, episode, reduceMotion)
                // The ONE receipt a single mark still earns: the series finishing ("Series
                // finished · Moved to Watched") — a milestone, said once, in the LANE.
                if (undo.customMessage != null) appModel.presentUndo(undo)
            }

            // Marking FORWARD past the next episode is a batch, and a batch confirms.
            else -> {
                val target = min(episode, part.progressCeiling)
                val count = max(1, target - progress)
                prompt = WritePrompt(
                    title = Copy.Confirm.batchMarkTitle(count),
                    message = Copy.Confirm.batchMarkMessage(from = progress + 1, to = target),
                    confirm = Copy.Confirm.batchMarkConfirm(count),
                ) {
                    val from = progress + 1
                    appModel.markThrough(franchise.id, part.mediaId, target, present = false)
                        // A batch's Undo rides the LANE: the rows are busy being the receipt.
                        ?.let { appModel.presentUndo(it) }
                    cascade(scope, from = from, through = target, reduceMotion = reduceMotion)
                }
            }
        }
    }
}

/** One controller per drawn season. [key] is the part's `mediaId`. */
@Composable
fun rememberEpisodeListController(key: Any?, appModel: AppModel): EpisodeListController =
    remember(key, appModel) { EpisodeListController(appModel) }

// =================================================================================================
// MARK: - The row
// =================================================================================================

/** The tile's own width plus the art gap: where a row's rule starts, at the title's leading edge. */
private val episodeRuleInset: Dp = EpisodeArtworkDefaults.slot.width + ThemeMetrics.artGap

/**
 * Unaired rows recede as a GROUP, one opacity.
 *
 * 0.72 ≈ 5.4:1 against the canvas and still steps back; the value it replaced (0.45) composited
 * `textSecondary` to ≈ 2.64:1 — *"and it was applied to exactly the rows being scanned for a date."*
 */
private const val UNAIRED_ROW_ALPHA = 0.72f

/** An identity title never ellipsises. */
private const val EPISODE_TITLE_MIN_SCALE = 0.92f

/** The withheld-still tile's eye, at its iOS point size. */
private val withheldGlyph = 16.dp

/** The reveal glyph's pull-back, so a hidden title does not sit 30 dp taller than the row beneath. */
private val revealGlyphOverhang = 14.dp

/**
 * ONE episode row. The show page's window and the season screen's full run draw this and nothing
 * else.
 *
 * @param isLast suppresses the bottom rule. It is drawn for every row except the last in the range.
 * @param revealAll the season screen's whole-list spoiler switch.
 */
@Composable
fun EpisodeRow(
    franchise: Franchise,
    part: FranchisePart,
    number: Int,
    now: Long,
    inLibrary: Boolean,
    controller: EpisodeListController,
    tint: Color?,
    isLast: Boolean,
    modifier: Modifier = Modifier,
    revealAll: Boolean = false,
    /** The newest aired episode still unwatched, or null. It wears the amber NEW tag. */
    fresh: Int? = null,
) {
    val scope = rememberCoroutineScope()
    val reduceMotion = LocalReduceMotion.current
    val anchor = franchise.timeAnchor
    val episode: Episode? = part.episodes.firstOrNull { it.number == number }
    val watched = number <= part.progress
    // A batch plays its discs one after another; a row the cascade has not reached is still drawn
    // unmarked (the model has already moved).
    val drawnWatched = watched && (controller.cascadeThrough?.let { number <= it } ?: true)
    val aired = !part.isReleasing ||
        number <= part.provenAiredCount(now) ||
        number <= part.airedEpisodes
    val isNext = number == part.progress + 1 && aired
    val spoilerSafe = watched || isNext || revealAll || controller.revealed.contains(number)
    val interactive = inLibrary && aired
    val cleanTitle = EpisodeCopy.title(episode?.title, franchise.title)
    // Only a REAL title (or a real still) can be revealed: the control used to appear whenever the
    // catalogue held any string at all, including "Episode 19" — so tapping it replaced the fact
    // line with the same words the fact line already carried.
    val canReveal = !spoilerSafe && (cleanTitle != null || !episode?.still.isNullOrEmpty())

    // Apple TV's row: the number is an EYEBROW over the title, never "Episode 10 · Mhysa" on one
    // line ("melting the episode number with the title looks shitty", user, 4 Sep).
    val eyebrow = if (spoilerSafe && cleanTitle != null) Copy.episode(number) else null
    val title = if (spoilerSafe && cleanTitle != null) cleanTitle else Copy.episode(number)
    // A WATCHED row says nothing on its second line: the disc says it, and the air date is a fact
    // about the past (it returns in the row's details).
    val subtitle = if (drawnWatched) {
        null
    } else {
        episodeSubtitle(franchise, part, number, episode, aired, isNext, now, anchor)
    }
    val overview = Formatting.stripHtml(episode?.overview).orEmpty()
    // A row OPENS when it has something to show: an overview to read, or a withheld title to
    // reveal. A bare "Episode 12" row is INERT — a tap that does nothing is honest; a tap that
    // marks is a trap.
    val opens = overview.isNotEmpty() || canReveal
    val isOpen = controller.expanded == number && spoilerSafe && overview.isNotEmpty()

    // A COLUMN, since 6 Sep: the row proper, and under it the details it opens to. It was a Row,
    // and the details laid out BESIDE the row rather than beneath it — the list collapsed to a
    // single row on the first tap (caught on the emulator).
    Column(
        modifier = modifier
            .fillMaxWidth()
            // The receding is ONE opacity on the whole group; the rule is drawn after it, so a
            // receded row still keeps a full-strength hairline — the iOS overlay ordering exactly.
            .alpha(if (aired) 1f else UNAIRED_ROW_ALPHA)
            .drawWithContent {
                drawContent()
                if (!isLast) {
                    val inset = episodeRuleInset.toPx()
                    val thickness = ThemeMetrics.hairline.toPx()
                    val left = if (layoutDirection == LayoutDirection.Ltr) inset else 0f
                    drawRect(
                        color = ThemeColor.separatorQuiet,
                        topLeft = Offset(left, size.height - thickness),
                        size = Size(size.width - inset, thickness),
                    )
                }
            }
            .padding(vertical = DetailMetrics.episodeRowInset),
    ) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = ThemeMetrics.rowEpisode),
        horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            modifier = Modifier
                .weight(1f)
                .clickable(
                    interactionSource = null,
                    indication = PressStyle.row(ThemeRadius.row),
                    // The row opens; it never writes. An inert row takes no press at all.
                    enabled = opens,
                    role = Role.Button,
                    onClick = { controller.open(number, canReveal, overview.isNotEmpty()) },
                )
                .semantics(mergeDescendants = true) {
                    contentDescription = listOfNotNull(title, subtitle?.text).joinToString(", ")
                },
            horizontalArrangement = Arrangement.spacedBy(ThemeMetrics.artGap),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            EpisodeTile(
                franchise = franchise,
                part = part,
                number = number,
                episode = episode,
                spoilerSafe = spoilerSafe,
                aired = aired,
                tint = tint,
            )
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(ThemeMetrics.titleGap),
            ) {
                if (eyebrow != null) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x1),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        BasicText(
                            text = eyebrow.uppercase(),
                            style = ThemeType.sectionLabel.copy(color = ThemeColor.textTertiary),
                            maxLines = 1,
                        )
                        if (number == fresh) NewTag()
                    }
                }
                Row(
                    horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    AutoSizeText(
                        text = title,
                        style = ThemeType.rowTitle.copy(
                            color = if (drawnWatched) ThemeColor.textSecondary else ThemeColor.textPrimary,
                        ),
                        minScale = EPISODE_TITLE_MIN_SCALE,
                        maxLines = if (isOpen) Int.MAX_VALUE else 2,
                        modifier = Modifier.weight(1f, fill = false),
                    )
                    // A row with no title of its own wears the tag beside its number: the title
                    // keeps its characters, and the tag gives way ("Episo… NEW", 6 Sep).
                    if (eyebrow == null && number == fresh) NewTag()
                    // On the title's baseline, inside the title row — **a row has one control
                    // column, not a toolbar.**
                    if (canReveal) RevealGlyph(onClick = { controller.reveal(number) })
                }
                if (subtitle != null) {
                    BasicText(
                        text = subtitle.text,
                        style = if (subtitle.accent) {
                            ThemeType.rowMetaLead.copy(color = ThemeColor.accent)
                        } else {
                            ThemeType.rowMeta.copy(color = ThemeColor.textSecondary)
                        },
                        maxLines = 1,
                    )
                }
            }
        }

        // An unaired row has NO ring at all.
        if (aired) {
            MarkRing(
                marked = drawnWatched,
                onMark = {
                    if (interactive) {
                        controller.tapped(franchise, part, number, watched, scope, reduceMotion)
                    }
                },
                style = MarkRingStyle.Settled,
                // The show's own colour under the check — Reminders fills the circle with the
                // list's colour. The page's palette, not a grey.
                fill = tint,
                committing = controller.committing == number,
                // Down one column: a watched episode is a bare tertiary check with no ring; the
                // NEXT episode is the ONE accent ring, carrying its numeral; every other unwatched
                // aired episode is a quiet idle ring. `.quiet` still put eleven amber rings down one
                // column — history is quiet, and amber goes to the ring that is a next step.
                lead = isNext,
                // NO numeral: the row states the episode 14 dp away ("why does it need to show the
                // episode number on the CTA?", user, 6 Sep). Schedule's and Today's rings keep theirs.
                episode = null,
                label = Copy.episode(number),
                markedLabel = Copy.episode(number),
                stateDescription = if (watched) Copy.Detail.watched else Copy.Detail.notWatched,
                actionHint = when {
                    !interactive -> null
                    watched -> Copy.Detail.marksAsUnwatched
                    else -> Copy.Detail.marksAsWatched
                },
                enabled = interactive,
            )
        }
    }
    // What a row opens to: the runtime and — on a watched row, whose second line is empty by rule
    // — the air date, then the overview. Set under the title column, clear of the ring.
    AnimatedVisibility(
        visible = isOpen,
        enter = fadeIn(ThemeMotion.uiSnappy()) + expandVertically(ThemeMotion.uiSnappy()),
        exit = fadeOut(ThemeMotion.uiSnappy()) + shrinkVertically(ThemeMotion.uiSnappy()),
    ) {
        EpisodeDetails(episode = episode, overview = overview, watched = watched)
    }
    }
}

/**
 * The newest aired episode's tag: amber, the app's one colour for STATE, at the eyebrow's size. A
 * tag rather than a coloured title — the row's ink means watched / not watched.
 */
@Composable
private fun NewTag() {
    BasicText(
        text = Copy.Label.newTag,
        style = ThemeType.sectionLabel.copy(color = ThemeColor.onAccent),
        modifier = Modifier
            .background(ThemeColor.accent, ContinuousCornerShape(3.dp))
            .padding(horizontal = 5.dp, vertical = 1.dp),
        maxLines = 1,
    )
}

@Composable
private fun EpisodeDetails(episode: Episode?, overview: String, watched: Boolean) {
    val facts = buildList {
        episode?.runtime?.takeIf { it > 0 }?.let { add(Copy.minutes(it)) }
        // Only on a WATCHED row, whose second line is empty by rule — the date is a fact about
        // the past, and this is where it returns.
        if (watched) episode?.airDate?.let { add(Formatting.fmtFullDate(it)) }
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(
                start = EpisodeArtworkDefaults.slot.width + ThemeMetrics.artGap,
                end = 44.dp + ThemeSpace.x2,
                bottom = ThemeSpace.x3,
            ),
        verticalArrangement = Arrangement.spacedBy(ThemeSpace.x1),
    ) {
        if (facts.isNotEmpty()) {
            BasicText(
                text = facts.joinToString(" \u00B7 "),
                style = ThemeType.metadata.copy(color = ThemeColor.textTertiary),
            )
        }
        BasicText(
            text = overview,
            style = ThemeType.prose.copy(color = ThemeColor.textSecondary),
        )
    }
}

/**
 * The three tile branches. **Every row gets one.**
 *
 * A still that exists but is being withheld gets [WithheldStillTile] — the glyph on the control that
 * reverses the choice — rather than the fallback chain, which would show the season's own art and
 * quietly claim there had never been a still.
 */
@Composable
private fun EpisodeTile(
    franchise: Franchise,
    part: FranchisePart,
    number: Int,
    episode: Episode?,
    spoilerSafe: Boolean,
    aired: Boolean,
    tint: Color?,
) {
    val hasStill = !episode?.still.isNullOrEmpty()
    when {
        spoilerSafe -> EpisodeStill(
            url = episode?.still,
            poster = part.portraitArt ?: franchise.portraitArt,
            landscape = part.stillLandscape(within = franchise),
            tint = tint,
            number = number,
        )

        aired && hasStill -> WithheldStillTile(tint = tint)

        else -> EpisodeStill(
            url = null,
            poster = part.portraitArt ?: franchise.portraitArt,
            landscape = part.stillLandscape(within = franchise),
            tint = tint,
            number = number,
        )
    }
}

/**
 * The per-row reveal control.
 *
 * The negative padding is what stops a hidden title sitting 30 dp taller than the row beneath it:
 * the target stays 44 dp and draws and hit-tests at full size, while the row's LAYOUT is the title's
 * own.
 */
@Composable
private fun RevealGlyph(onClick: () -> Unit) {
    Box(
        Modifier
            .negativePadding(top = revealGlyphOverhang, bottom = revealGlyphOverhang)
            .clickable(
                interactionSource = null,
                indication = PressStyle.mark,
                role = Role.Button,
                onClick = onClick,
            )
            .semantics(mergeDescendants = true) {
                contentDescription = Copy.Action.revealEpisodeTitle
            }
            .size(minimumTapTarget),
        contentAlignment = Alignment.Center,
    ) {
        Image(
            imageVector = rememberSymbol(PreviouslyIcons.Visibility),
            contentDescription = null,
            modifier = Modifier.size(materialGlyphBox(DetailMetrics.rowRevealGlyph)),
            colorFilter = ColorFilter.tint(ThemeColor.textTertiary),
        )
    }
}

/** A row's one fact, and whether it is a real next step (the only amber a row is allowed). */
@Immutable
private data class EpisodeSubtitle(val text: String, val accent: Boolean)

/**
 * The subtitle ladder, in order. An unaired row that is not the next-to-air says **nothing**:
 * *"'Upcoming' says only what the row's position below the dated ones says."*
 */
private fun episodeSubtitle(
    franchise: Franchise,
    part: FranchisePart,
    number: Int,
    episode: Episode?,
    aired: Boolean,
    isNext: Boolean,
    now: Long,
    anchor: TimeAnchor,
): EpisodeSubtitle? {
    // One rule per row. A WATCHED row says nothing: the check says it, and its air date is a fact
    // about the past. The show page's window used to mix four grammars in six rows (4 Sep).
    if (number <= part.progress) return null
    if (isNext) return EpisodeSubtitle(Copy.Label.nextUp, accent = true)
    if (!aired) {
        val scheduled = part.scheduledAiring(now, anchor)
        if (number == part.airedEpisodes + 1 && scheduled != null) {
            return EpisodeSubtitle(
                TemporalCopy.airs(at = scheduled, now = now, source = franchise.source),
                accent = false,
            )
        }
        return null
    }
    val dated = episode?.airDate
    if (dated != null) {
        // Hard-coded `.tmdb`: `Episode.airDate` only ever comes from TMDB and is date-only, whatever
        // the franchise's own source is. A clock must never be rendered for it.
        return EpisodeSubtitle(
            TemporalCopy.aired(at = dated, now = now, source = MediaSource.TMDB),
            accent = false,
        )
    }
    val derived = derivedAirDate(part, number)
    if (derived != null) {
        return EpisodeSubtitle(
            TemporalCopy.aired(at = derived, now = now, source = franchise.source),
            accent = false,
        )
    }
    // An invented date is worse than a blank.
    return null
}

// =================================================================================================
// MARK: - The two hosts
// =================================================================================================

/**
 * The show page's windowed list: at most six rows, inside the page's own scroll.
 *
 * Non-lazy on purpose — the window is bounded at six, and a nested lazy list inside a scrolling
 * column has no height to measure against.
 */
@Composable
fun EpisodeListColumn(
    franchise: Franchise,
    part: FranchisePart,
    total: Int,
    now: Long,
    inLibrary: Boolean,
    controller: EpisodeListController,
    tint: Color?,
    modifier: Modifier = Modifier,
    /** The episode a route asked for (a Schedule card): the window opens on it. */
    focusEpisode: Int? = null,
) {
    val reduceMotion = LocalReduceMotion.current
    val range = controller.shown?.let { clampEpisodes(it, total) }
        ?: if (total <= WHOLE_BELOW) {
            1..total
        } else {
            episodeWindow(episodeAnchor(part.progress, total, focusEpisode), total)
        }
    val fresh = freshEpisode(part, total, now, franchise.timeAnchor)

    Column(modifier.fillMaxWidth()) {
        if (range.first > 1) {
            EpisodeExpander(Copy.Action.showEarlierEpisodes, up = true) {
                controller.grow(range, total, earlier = true)
            }
        }
        for (n in range) {
            EpisodeRow(
                franchise = franchise,
                part = part,
                number = n,
                now = now,
                inLibrary = inLibrary,
                controller = controller,
                tint = tint,
                isLast = n == range.last,
                fresh = fresh,
            )
        }
        if (range.last < total) {
            EpisodeExpander(Copy.Action.showMoreEpisodes, up = false) {
                controller.grow(range, total, earlier = false)
            }
        }
    }
    // There is NO `ReceiptLine` under a row any more (6 Sep): the ring IS the receipt. "It shows an
    // inline response again showing Episode 7 … what is this trashy UX?" (user).
    LaunchedEffect(reduceMotion) { }
    DisposableEffect(controller) { onDispose { controller.dispose() } }
}

/** A long run's in-place door: a quiet centred link in `interactive` ink, like "Read more". */
@Composable
private fun EpisodeExpander(label: String, @Suppress("UNUSED_PARAMETER") up: Boolean, onClick: () -> Unit) {
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        InlineLinkButton(label = label, onClick = onClick)
    }
}

/**
 * The season screen's full run, as `LazyColumn` items.
 *
 * **Lazy is mandatory**: One Piece Season 1 advertises ~1,140 episodes, and eagerly building every
 * row — each with its own palette resolve — is a multi-second freeze on the push transition and a
 * plausible watchdog termination.
 *
 * Each row is keyed `"ep-$n"`, which is also what the focus jump scrolls to.
 */
fun LazyListScope.episodeListItems(
    franchise: Franchise,
    part: FranchisePart,
    range: IntRange,
    now: Long,
    inLibrary: Boolean,
    controller: EpisodeListController,
    tint: Color?,
    revealAll: Boolean,
    itemModifier: Modifier = Modifier,
) {
    val fresh = freshEpisode(part, range.last, now, franchise.timeAnchor)
    items(
        count = (range.last - range.first + 1).coerceAtLeast(0),
        key = { "ep-${range.first + it}" },
    ) { index ->
        val n = range.first + index
        EpisodeRow(
            franchise = franchise,
            part = part,
            number = n,
            now = now,
            inLibrary = inLibrary,
            controller = controller,
            tint = tint,
            isLast = n == range.last,
            revealAll = revealAll,
            fresh = fresh,
            modifier = itemModifier,
        )
    }
}
