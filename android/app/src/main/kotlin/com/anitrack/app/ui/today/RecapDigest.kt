package com.anitrack.app.ui.today

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.AnimationVector1D
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorProducer
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.anitrack.app.design.PosterSize
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.SurfaceLevel
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeMotion
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.rememberSymbol
import com.anitrack.app.design.surface
import com.anitrack.app.ui.AutoSizeText
import com.anitrack.app.ui.art.PosterSlot
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.control.materialGlyphBox
import com.anitrack.app.ui.control.minimumTapTarget
import com.anitrack.app.ui.section.HeroBadge
import com.anitrack.model.Formatting
import com.anitrack.model.Franchise
import com.anitrack.model.MediaSource
import com.anitrack.model.TemporalCopy
import com.anitrack.model.WatchStatus
import com.anitrack.model.copy.Copy
import com.anitrack.model.effectiveStatus
import com.anitrack.model.episodesBehind
import com.anitrack.model.nextAiring
import com.anitrack.model.portraitArt
import com.anitrack.model.premiereAt
import com.anitrack.model.releasingPart
import com.anitrack.model.resumePart
import com.anitrack.model.watchContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// =====================================================================================
// THE PREVIOUSLY RECAP — the port of `ios/Sources/Features/Today/RecapDigest.swift` and of
// the recap half of `TodayView.swift` (spec/today.md §13).
//
// On arrival after an absence the hero frame is occupied by a full-height digest of what
// changed while you were away, which then SHRINKS into the hero in a single move and leaves
// a one-line strip behind.
//
// **Only genuine CHANGES inside the window belong on it.** `nextUp` — "where you stopped" —
// was a standing state that had not happened since anything, printed directly above the hero
// that says the same thing: the recap's job is what you MISSED, the hero's is what to do
// about it.
// =====================================================================================

// -------------------------------------------------------------------------------------
// The model
// -------------------------------------------------------------------------------------

/** One thing that changed while the user was away. */
@Immutable
data class RecapBeat(
    val franchiseId: String,
    val title: String,
    val cover: String?,
    val source: MediaSource,
    val kind: Kind,
    val score: Int,
) {

    @Immutable
    sealed interface Kind {
        /** [latest] is the highest episode that aired inside the window. */
        @Immutable
        data class EpisodesAired(val count: Int, val latest: Int?) : Kind

        /** A show that has been off the air for a month is coming back inside 48 h. */
        @Immutable
        data class Returning(val at: Long?) : Kind

        /** A completed show has been given a premiere date inside 30 days. */
        @Immutable
        data class ReturnDateAnnounced(val at: Long?) : Kind
    }

    /**
     * Stable identity, used to acknowledge a digest across launches.
     *
     * **A deliberate divergence, taken consciously** (spec §13.1): iOS builds this id out of
     * `label(now: 0)`, so a returning beat's id embeds a *locale-formatted absolute date*
     * ("Returns Oct 2, 2026") — and changing the device language un-acknowledges a digest the user
     * has already seen. The Android id is locale-independent.
     */
    val id: String
        get() = when (kind) {
            is Kind.EpisodesAired -> "$franchiseId/aired/${kind.count}/${kind.latest ?: 0}"
            is Kind.Returning -> "$franchiseId/returning/${kind.at ?: 0}"
            is Kind.ReturnDateAnnounced -> "$franchiseId/announced/${kind.at ?: 0}"
        }

    /** The beat's own line. [beatLabel] refines it against the live library where it can. */
    fun label(now: Long): String = when (kind) {
        is Kind.EpisodesAired ->
            if (kind.count == 1 && kind.latest != null) {
                Copy.Recap.aired(Copy.episode(kind.latest))
            } else {
                Copy.Recap.aired(Copy.episodes(kind.count))
            }
        is Kind.Returning -> TemporalCopy.returns(kind.at, now, source)
        is Kind.ReturnDateAnnounced -> TemporalCopy.returns(kind.at, now, source)
    }
}

/** At most three beats, plus what would not fit and a score the presentation rule reads. */
@Immutable
data class RecapDigest(
    val since: Long,
    val beats: List<RecapBeat>,
    val hiddenBeatCount: Int,
    val score: Int,
) {

    /** What this exact digest is, for acknowledgement. */
    val digestID: String get() = "$since|" + beats.joinToString(",") { it.id }

    enum class Presentation { Full, Strip, None }

    /**
     * How loudly to present it, or not at all.
     *
     * `beats.count >= 2` is the floor: one change is what the hero is already for.
     */
    fun presentation(
        absence: Long,
        lastFullRecapAt: Long?,
        acknowledgedID: String?,
        now: Long,
        enteredByDeepLink: Boolean,
    ): Presentation {
        if (enteredByDeepLink || acknowledgedID == digestID || beats.size < 2) return Presentation.None
        val cooldownOK = lastFullRecapAt?.let { now - it >= FULL_COOLDOWN } ?: true
        if (absence >= FULL_ABSENCE && score >= FULL_SCORE && cooldownOK) return Presentation.Full
        if (absence >= STRIP_ABSENCE && score >= STRIP_SCORE) return Presentation.Strip
        return Presentation.None
    }

    companion object {
        /** Three days away earns the full card. */
        const val FULL_ABSENCE: Long = 72L * Formatting.H

        /** Eight hours away earns the strip. */
        const val STRIP_ABSENCE: Long = 8L * Formatting.H

        /** A full card at most once a week, however long you were away. */
        const val FULL_COOLDOWN: Long = 7L * Formatting.D

        /** How long a show must have been off the air for its return to be news. */
        const val RETURNING_GAP: Long = 30L * Formatting.D

        /** How soon that return has to be. */
        const val RETURNING_WINDOW: Long = 48L * Formatting.H

        /** How far ahead an announced premiere is still news. */
        const val ANNOUNCED_WINDOW: Long = 30L * Formatting.D

        private const val FULL_SCORE = 4
        private const val STRIP_SCORE = 3

        /** Beats above this go to "and N more". */
        private const val MAX_BEATS = 3

        /**
         * Build the digest for the window `since … now`, or `null` when nothing changed.
         *
         * Note that `episodesBehind` / `lastAiredAt` / `airedEpisodes` here are the **raw catalogue
         * fields**, not the airings-derived ones every live surface reads: the digest describes what
         * changed since a past visit, not what is live right now.
         */
        fun build(library: List<Franchise>, since: Long, now: Long): RecapDigest? {
            if (since <= 0 || since >= now) return null

            val beats = mutableListOf<RecapBeat>()
            var newEpisodeTitles = 0

            for (f in library) {
                if (f.effectiveStatus != WatchStatus.WATCHING) continue
                val part = f.releasingPart ?: continue
                val last = part.lastAiredAt
                if (last != null && last > since && part.episodesBehind > 0) {
                    val count = minOf(
                        part.episodesBehind,
                        maxOf(1, part.airedEpisodes - part.progress),
                    )
                    newEpisodeTitles++
                    beats += RecapBeat(
                        franchiseId = f.id,
                        title = f.title,
                        cover = f.portraitArt,
                        source = f.source,
                        kind = RecapBeat.Kind.EpisodesAired(count = count, latest = part.airedEpisodes),
                        // One new episode is the cleanest possible piece of news.
                        score = if (count == 1) 5 else 3,
                    )
                    // At most ONE beat per franchise: a show that aired and is also coming back is
                    // one line in a digest, not two.
                    continue
                }
                val next = f.nextAiring(now)
                if (next != null && next - now <= RETURNING_WINDOW &&
                    last != null && now - last >= RETURNING_GAP
                ) {
                    beats += RecapBeat(
                        franchiseId = f.id,
                        title = f.title,
                        cover = f.portraitArt,
                        source = f.source,
                        kind = RecapBeat.Kind.Returning(next),
                        score = 4,
                    )
                }
            }

            for (f in library) {
                if (f.effectiveStatus != WatchStatus.COMPLETED) continue
                val premiere = f.parts.mapNotNull { it.premiereAt }.filter { it > now }.minOrNull()
                if (premiere != null && premiere - now <= ANNOUNCED_WINDOW) {
                    beats += RecapBeat(
                        franchiseId = f.id,
                        title = f.title,
                        cover = f.portraitArt,
                        source = f.source,
                        kind = RecapBeat.Kind.ReturnDateAnnounced(premiere),
                        score = 3,
                    )
                }
            }

            if (beats.isEmpty()) return null
            val ordered = beats.sortedByDescending { it.score }
            var score = ordered.sumOf { it.score }
            // Two shows dropping at once is a different kind of week from one.
            if (newEpisodeTitles >= 2) score += 4
            return RecapDigest(
                since = since,
                beats = ordered.take(MAX_BEATS),
                hiddenBeatCount = maxOf(0, ordered.size - MAX_BEATS),
                score = score,
            )
        }

        /**
         * DEBUG only — what `recapDemo` shows when the real build yields nothing.
         *
         * The launch argument is documented as *forcing* the full recap so the arrival can be
         * reviewed and captured, and it silently did nothing whenever the signed-in library happened
         * to have no unwatched new episodes — which is most of the time on a well-kept account.
         */
        fun demoDigest(library: List<Franchise>, since: Long, now: Long): RecapDigest? {
            build(library, since, now)?.let { return it }
            val candidates = library.filter { it.effectiveStatus == WatchStatus.WATCHING }
            if (candidates.isEmpty()) return null
            val beats = candidates.take(2).mapIndexed { index, f ->
                RecapBeat(
                    franchiseId = f.id,
                    title = f.title,
                    cover = f.portraitArt,
                    source = f.source,
                    kind = RecapBeat.Kind.EpisodesAired(
                        count = 1,
                        latest = f.resumePart?.let { it.progress + 1 } ?: 1,
                    ),
                    score = if (index == 0) 5 else 4,
                )
            }
            return RecapDigest(
                since = since,
                beats = beats,
                hiddenBeatCount = maxOf(0, candidates.size - beats.size),
                score = 9,
            )
        }
    }
}

// -------------------------------------------------------------------------------------
// Persistence
// -------------------------------------------------------------------------------------

/**
 * The two cross-launch facts the recap keeps, under the **same keys iOS uses** so the two platforms
 * name one user-visible behaviour.
 */
class RecapStore(private val prefs: SharedPreferences) {

    var acknowledgedID: String?
        get() = prefs.getString(KEY_ACKNOWLEDGED, null)
        set(value) = prefs.edit().putString(KEY_ACKNOWLEDGED, value).apply()

    /** 0 reads back as `null` — "never", not "at the epoch". */
    var lastFullRecapAt: Long?
        get() = prefs.getLong(KEY_LAST_FULL, 0L).takeIf { it > 0L }
        set(value) = prefs.edit().putLong(KEY_LAST_FULL, value ?: 0L).apply()

    private companion object {
        const val KEY_ACKNOWLEDGED = "recap.acknowledgedDigestID"
        const val KEY_LAST_FULL = "recap.lastFullRecapAt"
        const val FILE = "previously.recap"
    }

    constructor(context: Context) : this(
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE),
    )
}

@Composable
fun rememberRecapStore(): RecapStore {
    val context = LocalContext.current
    return remember(context) { RecapStore(context) }
}

// -------------------------------------------------------------------------------------
// The state machine
// -------------------------------------------------------------------------------------

/** The timings the arrival's clock is made of. */
object RecapTiming {

    /** A beat after the frame lands, so the reveal is seen rather than folded into the arrival. */
    const val REVEAL_DELAY_MILLIS: Long = 60

    /** Between two beats revealing. Also the reveal component of [holdMillis]. */
    const val BEAT_STAGGER_MILLIS: Long = 120

    /** The floor of the reading hold, before the per-beat allowance. */
    private const val HOLD_BASE_MILLIS = 1_400L
    private const val HOLD_PER_BEAT_MILLIS = 300L
    private const val HOLD_CEILING_MILLIS = 4_500L

    /** Reduce Motion holds LONGER: less movement is not less reading time. */
    private const val REDUCED_EXTRA_MILLIS = 600L

    /**
     * How long the card holds before it hands over, measured **from the last beat's reveal** and
     * scaled by what there is to read.
     *
     * Two accessibility rules the shipped clock had backwards. A screen reader NEVER auto-dismisses
     * — a user got roughly one element spoken before the card was removed from the tree — and
     * Reduce Motion holds longer rather than shorter (it used to cut the hold from 2,000 ms to
     * 1,600): the two settings that most need time were both given less.
     *
     * Worked values with Reduce Motion off: 2 beats → 360 + 2,000 = 2,360 ms; 3 beats → 480 + 2,300
     * = 2,780 ms. With Reduce Motion, 2 beats → 0 + 2,000 + 600 = 2,600 ms.
     */
    fun holdMillis(beatCount: Int, reduceMotion: Boolean): Long {
        val beats = maxOf(1, beatCount)
        val reveal = if (reduceMotion) 0L else BEAT_STAGGER_MILLIS * (beats + 1)
        val read = minOf(HOLD_CEILING_MILLIS, HOLD_BASE_MILLIS + HOLD_PER_BEAT_MILLIS * beats)
        return reveal + read + if (reduceMotion) REDUCED_EXTRA_MILLIS else 0L
    }
}

/**
 * Today's recap state — evaluated once per visit, then driven by its own clock.
 *
 * Held as an object in `remember` rather than as loose screen state so the whole machine has one
 * home and one set of guards; the screen only asks it what to draw.
 */
@Stable
class TodayRecapController internal constructor(
    private val store: RecapStore,
    private val demo: Boolean,
) {

    var digest by mutableStateOf<RecapDigest?>(null)
        private set

    var mode by mutableStateOf(RecapDigest.Presentation.None)
        private set

    /** The card is in the hero frame right now. */
    var onStage by mutableStateOf(false)
        private set

    /** The beats have been told to appear. */
    var revealed by mutableStateOf(false)
        private set

    /**
     * The arrival must be the FIRST thing on screen, not something that grows into place — so the
     * frame it lands in snaps to its height instead of animating to it.
     */
    var arrivesWithoutAnimation by mutableStateOf(false)
        private set

    private var evaluated = false
    private var clockStarted = false

    /** The strip is showing under the hero. */
    val showsStrip: Boolean get() = !onStage && mode == RecapDigest.Presentation.Strip && digest != null

    /**
     * Runs on arrival and whenever `loading` flips false. Once per visit, and never against an empty
     * library — a digest built from nothing is nothing.
     */
    fun evaluate(library: List<Franchise>, prevOpenedAt: Long, now: Long, loading: Boolean) {
        if (loading || evaluated || library.isEmpty()) return
        evaluated = true
        // 400 days, not 30: the flag is DEBUG-only and 30 was not wide enough to guarantee a digest
        // on a library whose latest change is older than that.
        val since = if (demo) now - DEMO_WINDOW_DAYS * Formatting.D else prevOpenedAt
        val built = if (demo) {
            RecapDigest.demoDigest(library, since, now)
        } else {
            RecapDigest.build(library, since, now)
        }
        if (built == null) {
            digest = null
            mode = RecapDigest.Presentation.None
            return
        }
        val resolved = if (demo) {
            RecapDigest.Presentation.Full
        } else {
            built.presentation(
                absence = now - since,
                lastFullRecapAt = store.lastFullRecapAt,
                acknowledgedID = store.acknowledgedID,
                now = now,
                enteredByDeepLink = false,
            )
        }
        digest = built
        mode = resolved
        if (resolved == RecapDigest.Presentation.Full) {
            arrivesWithoutAnimation = true
            onStage = true
            revealed = false
        }
    }

    /** Consumed by the frame once it has snapped to the arrival's height. */
    fun animationsResume() {
        arrivesWithoutAnimation = false
    }

    /** True the first time the clock may start — the surface has to actually be visible. */
    fun shouldStartClock(surfaceReady: Boolean): Boolean =
        onStage && surfaceReady && !clockStarted

    /** Claim the clock, so a recomposition of its effect cannot run the arrival twice. */
    fun noteClockStarted() {
        clockStarted = true
    }

    fun reveal() {
        revealed = true
    }

    /** The strip was tapped: put the card back on stage and re-run its clock. */
    fun stage() {
        revealed = false
        clockStarted = false
        onStage = true
    }

    /**
     * Recap → focus, in **ONE** move.
     *
     * It used to be two: the hero shrank and settled, and only in that animation's completion did a
     * second `withAnimation` insert the 44-pt strip and shove everything under it down ~60 pt on
     * another curve. The screen appeared to finish and then jumped. Only the persistence — which
     * animates nothing — is left for afterwards.
     */
    fun handoff() {
        if (!onStage) return
        onStage = false
        mode = if (mode == RecapDigest.Presentation.Full) {
            RecapDigest.Presentation.Strip
        } else {
            RecapDigest.Presentation.None
        }
        persist()
    }

    /**
     * The ✕. **Dismiss means gone**: no strip, nothing to come back to on this visit. It used to
     * call the continue path, so it demoted the card to the strip and it reappeared 460 ms later.
     */
    fun dismiss() {
        if (!onStage) return
        onStage = false
        mode = RecapDigest.Presentation.None
        persist()
    }

    /** Leaving the screen, backgrounding, or committing a mark all retire the strip. */
    fun clearStrip() {
        if (mode != RecapDigest.Presentation.Strip) return
        persist()
        mode = RecapDigest.Presentation.None
    }

    /** Never under the demo flag — it must fire on every launch. */
    private fun persist() {
        if (demo) return
        val id = digest?.digestID ?: return
        store.acknowledgedID = id
        store.lastFullRecapAt = System.currentTimeMillis()
    }

    private companion object {
        const val DEMO_WINDOW_DAYS = 400L
    }
}

@Composable
fun rememberRecapController(demo: Boolean): TodayRecapController {
    val store = rememberRecapStore()
    return remember(store, demo) { TodayRecapController(store, demo) }
}

// -------------------------------------------------------------------------------------
// Copy
// -------------------------------------------------------------------------------------

/**
 * "5 episodes aired since 23 Jul" / "3 updates since 23 Jul".
 *
 * Only the leading WORD of the temporal phrase is re-cased. Lower-casing the whole phrase produced
 * "1 episode aired since 23 **jul**": a month abbreviation is a proper noun and does not follow the
 * sentence.
 */
fun recapStripText(digest: RecapDigest, now: Long): String {
    val aired = digest.beats.sumOf { beat ->
        (beat.kind as? RecapBeat.Kind.EpisodesAired)?.count ?: 0
    }
    val since = Copy.Recap.sinceFragment(TemporalCopy.since(digest.since, now))
    return if (aired > 0) {
        Copy.Recap.airedSince(aired, since)
    } else {
        Copy.Recap.updatesSince(digest.beats.size + digest.hiddenBeatCount, since)
    }
}

/** Announced when the arrival reveals. */
fun recapSpokenSummary(digest: RecapDigest, now: Long): String =
    "${Copy.Recap.whileYouWereAway}. ${recapStripText(digest, now)}."

/**
 * The beat's line, resolved against the LIVE library where it can be.
 *
 * `RecapBeat.label` prints "Episode 19 aired" with no season, while the hero for that exact episode
 * said "Season 4 · Episode 19" 200 dp above it — one screen, two ways of naming one thing.
 */
fun beatLabel(beat: RecapBeat, library: List<Franchise>, now: Long): String {
    val kind = beat.kind as? RecapBeat.Kind.EpisodesAired ?: return beat.label(now)
    val latest = kind.latest ?: return beat.label(now)
    if (kind.count != 1) return beat.label(now)
    val f = library.firstOrNull { it.id == beat.franchiseId } ?: return beat.label(now)
    val part = f.releasingPart ?: f.resumePart ?: return beat.label(now)
    return Copy.Recap.aired(f.watchContext(part, latest))
}

// The strip's click labels and its overflow count are `Copy.Recap`'s. They were call-site strings
// on iOS too, and were ported that way — but a screen-reader label is user-facing copy, and this
// file held the densest concentration of it in the app.

// -------------------------------------------------------------------------------------
// The arrival
// -------------------------------------------------------------------------------------

/**
 * The full card, in the hero frame.
 *
 * The **whole beats card is the Continue button**; the ✕ beside the eyebrow is the only other
 * control. 22 pt of low-contrast glyph was the only way out of a full-screen takeover before it —
 * and it called the continue path, so dismissing demoted the card to the strip instead of removing
 * it.
 *
 * @param revealed the beats' cue. They rise 6 dp and fade in, staggered, and under Reduce Motion
 *   they do not travel and the stagger is 0.
 */
@Composable
fun RecapArrival(
    digest: RecapDigest,
    library: List<Franchise>,
    now: Long,
    revealed: Boolean,
    reduceMotion: Boolean,
    heroArtUrl: String?,
    tint: Color?,
    onContinue: () -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val rows = digest.beats.size + if (digest.hiddenBeatCount > 0) 1 else 0
    val reveals = remember(digest.digestID, rows) { List(rows) { Animatable(0f) } }
    LaunchedEffect(revealed, reduceMotion, digest.digestID) {
        if (!revealed) {
            reveals.forEach { it.snapTo(0f) }
            return@LaunchedEffect
        }
        reveals.forEachIndexed { index, anim ->
            launch {
                if (!reduceMotion) delay(RecapTiming.BEAT_STAGGER_MILLIS * (index + 1))
                anim.animateTo(1f, ThemeMotion.uiReveal())
            }
        }
    }

    val aired = digest.beats.sumOf { (it.kind as? RecapBeat.Kind.EpisodesAired)?.count ?: 0 }
    val total = digest.beats.size + digest.hiddenBeatCount
    val headline = if (aired > 0) {
        "${Copy.episodes(aired)} aired"
    } else {
        "${Copy.updates(total)} waiting"
    }

    Column(modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            HeroBadge(text = Copy.Recap.whileYouWereAway)
            Spacer(Modifier.width(ThemeSpace.x3))
            Spacer(Modifier.weight(1f))
            DismissDisc(onDismiss)
        }

        AutoSizeText(
            text = headline,
            style = ThemeType.displayL.copy(color = ThemeColor.textPrimary),
            minScale = RECAP_HEADLINE_MIN_SCALE,
            maxLines = 2,
            modifier = Modifier
                .padding(top = ThemeSpace.x3)
                .semantics { heading() },
        )

        // "Since 23 Jul" named a date with no anchor — since what?
        BasicText(
            text = Copy.Recap.sinceYourLastVisit(TemporalCopy.since(digest.since, now)),
            style = ThemeType.metadata,
            color = ColorProducer { ThemeColor.textSecondary },
            modifier = Modifier.padding(top = ThemeSpace.x0_5),
        )

        BeatsCard(
            digest = digest,
            library = library,
            now = now,
            reveals = reveals,
            reduceMotion = reduceMotion,
            showsPoster = showsPoster(digest, heroArtUrl),
            tint = tint,
            onContinue = onContinue,
            modifier = Modifier.padding(top = ThemeSpace.x5),
        )
    }
}

/**
 * A single-title recap laid on that title's own key visual at 440 dp printed the SAME image again at
 * 34 × 51 about 200 dp below it — a postage stamp of the picture above it.
 *
 * In practice this only fires under the demo flag on a one-show library, because `presentation`
 * requires two beats.
 */
private fun showsPoster(digest: RecapDigest, heroArtUrl: String?): Boolean {
    if (digest.beats.size != 1 || digest.hiddenBeatCount != 0) return true
    val cover = digest.beats.first().cover ?: return true
    if (heroArtUrl == null) return true
    return cover != heroArtUrl
}

@Composable
private fun BeatsCard(
    digest: RecapDigest,
    library: List<Franchise>,
    now: Long,
    reveals: List<Animatable<Float, AnimationVector1D>>,
    reduceMotion: Boolean,
    showsPoster: Boolean,
    tint: Color?,
    onContinue: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val labels = remember(digest.digestID, library, now) {
        digest.beats.map { beatLabel(it, library, now) }
    }
    val spoken = remember(digest.digestID, labels) {
        digest.beats.mapIndexed { i, beat -> "${beat.title}, ${labels[i]}" }.joinToString(". ")
    }
    val rise = with(LocalDensity.current) { RECAP_BEAT_RISE.toPx() }

    Column(
        modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = null,
                indication = PressStyle.overArt,
                onClickLabel = Copy.Recap.continuesToWhatIsNext,
                role = Role.Button,
                onClick = onContinue,
            )
            .semantics(mergeDescendants = true) { contentDescription = spoken }
            // The art-adaptive ground with its top-edge hairline and card shadow — never a
            // full-perimeter stroke. The recap was the one surface in the app overriding that rule.
            .surface(SurfaceLevel.Art(tint), ThemeRadius.focusCard)
            .padding(ThemeMetrics.gutter),
        verticalArrangement = Arrangement.spacedBy(ThemeSpace.x3),
    ) {
        digest.beats.forEachIndexed { index, beat ->
            val anim = reveals.getOrNull(index)
            Row(
                Modifier
                    .fillMaxWidth()
                    // A deferred read: the stagger animates a layer, never this column's body.
                    .graphicsLayer {
                        val p = anim?.value ?: 1f
                        alpha = p
                        translationY = if (reduceMotion) 0f else (1f - p) * rise
                    },
                horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x3),
                verticalAlignment = Alignment.Top,
            ) {
                if (showsPoster) PosterSlot(url = beat.cover, slot = PosterSize.Beat)
                Column(
                    Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(ThemeMetrics.titleGap),
                ) {
                    Row(verticalAlignment = Alignment.Top) {
                        // BOTH titles are `textPrimary`: the second used to be secondary and read
                        // as disabled. The aired-vs-upcoming distinction lives in the meta line.
                        BasicText(
                            text = beat.title,
                            style = ThemeType.rowTitle,
                            color = ColorProducer { ThemeColor.textPrimary },
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                            // The title takes the row and the chevron keeps the trailing edge — one
                            // weight, so a long title is never cut at half the row's width.
                            modifier = Modifier.weight(1f),
                        )
                        if (index == 0) {
                            Spacer(Modifier.width(ThemeSpace.x2))
                            Image(
                                imageVector = rememberSymbol(PreviouslyIcons.ChevronRight),
                                contentDescription = null,
                                colorFilter = ColorFilter.tint(ThemeColor.textDisabled),
                                modifier = Modifier.size(materialGlyphBox(RECAP_GLYPH)),
                            )
                        }
                    }
                    BasicText(
                        text = labels[index],
                        style = ThemeType.rowMeta,
                        color = ColorProducer { ThemeColor.textSecondary },
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }

        if (digest.hiddenBeatCount > 0) {
            val anim = reveals.lastOrNull()
            BasicText(
                text = Copy.Recap.andMore(digest.hiddenBeatCount),
                style = ThemeType.metadata,
                color = ColorProducer { ThemeColor.textTertiary },
                modifier = Modifier.graphicsLayer { alpha = anim?.value ?: 1f },
            )
        }
    }
}

/** The ✕ — a 30-dp disc in a 44-dp target. */
@Composable
private fun DismissDisc(onDismiss: () -> Unit) {
    Box(
        Modifier
            .size(minimumTapTarget)
            .clickable(
                interactionSource = null,
                indication = PressStyle.overArt,
                role = Role.Button,
                onClick = onDismiss,
            )
            .semantics { contentDescription = Copy.Action.dismissRecap },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(RECAP_DISMISS_DISC)
                .background(ThemeColor.scrimStrong, CircleShape)
                .border(ThemeMetrics.hairline, ThemeColor.posterEdge, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Image(
                imageVector = rememberSymbol(PreviouslyIcons.Close),
                contentDescription = null,
                colorFilter = ColorFilter.tint(ThemeColor.textPrimary),
                modifier = Modifier.size(materialGlyphBox(RECAP_GLYPH)),
            )
        }
    }
}

// -------------------------------------------------------------------------------------
// The strip
// -------------------------------------------------------------------------------------

/**
 * The residue the arrival leaves behind — **on the canvas, not in a box**.
 *
 * Tucked 12 dp under the hero rather than a full section gap: the line belongs to the hero, and at
 * section distance it floated in the dead zone between the hero and the queue, reading as a stray
 * debug print.
 */
@Composable
fun RecapLine(
    text: String,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = null,
                indication = PressStyle.row(ThemeRadius.row),
                onClickLabel = Copy.Recap.opensWhatYouMissed,
                role = Role.Button,
                onClick = onOpen,
            )
            .semantics(mergeDescendants = true) { contentDescription = text }
            .defaultMinSize(minHeight = minimumTapTarget),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
    ) {
        Image(
            imageVector = rememberSymbol(PreviouslyIcons.History),
            contentDescription = null,
            colorFilter = ColorFilter.tint(ThemeColor.textSecondary),
            modifier = Modifier.size(materialGlyphBox(RECAP_GLYPH)),
        )
        BasicText(
            text = text,
            style = ThemeType.metadataEmphasis,
            color = ColorProducer { ThemeColor.textPrimary },
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Image(
            imageVector = rememberSymbol(PreviouslyIcons.ChevronRight),
            contentDescription = null,
            colorFilter = ColorFilter.tint(ThemeColor.textDisabled),
            modifier = Modifier.size(materialGlyphBox(RECAP_GLYPH)),
        )
    }
}

/** iOS's 13-pt semibold glyph, in the Material box that replaces it. */
private val RECAP_GLYPH = 13.dp

private val RECAP_DISMISS_DISC = 30.dp

/** The beats rise this far as they arrive. Nothing travels under Reduce Motion. */
private val RECAP_BEAT_RISE = 6.dp

private const val RECAP_HEADLINE_MIN_SCALE = 0.85f
