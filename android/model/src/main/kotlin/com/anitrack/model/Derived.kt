package com.anitrack.model

import com.anitrack.model.copy.Copy
import java.text.BreakIterator
import java.time.DateTimeException
import java.time.LocalDate
import java.time.ZoneOffset

/**
 * # Derived presentation logic — the freshness ladder
 *
 * **"Presentation is derived, not stored."** The server sends raw catalogue facts (counts,
 * timestamps, statuses); this file turns them into every display string, sort key, threshold and
 * boolean the screens read. No screen may re-derive any of this and no screen may store it.
 *
 * Three rules run through the whole file, each with a production bug behind it:
 *
 * 1. **Freshness is derived from `airings`, never from the catalogue's counts.** `airedEpisodes`,
 *    `lastAiredAt` and `nextAiringAt` are advanced by an hourly cron and trail reality by up to an
 *    hour; the per-episode `airings` list in the same payload is precise. A slot in it that has
 *    struck IS an aired episode. Reading only the counts made the one show that had just aired
 *    (Re:ZERO, 6:30 PM) the one show Today could not see for an hour: not fresh (count unchanged),
 *    not waiting (slot passed) — *gone*.
 * 2. **The two-calendar system.** AniList timestamps are real instants read in the device's zone;
 *    TMDB timestamps are date-only facts the server synthesizes at 17:00 UTC, whose only true part
 *    is their UTC calendar day. Reading those locally put every timezone east of UTC+7 a day ahead.
 *    Never branch on `source` at a call site — pass the [TimeAnchor].
 * 3. **`planned` shows are not on the calendar** ([tracksAirings]). A shelved mid-broadcast show
 *    otherwise arrived as "20 episodes behind" with a mark-20 ring — an obligation invented out of
 *    a bookmark.
 *
 * `now` is always passed in explicitly (`Long`, ms since the Unix epoch) so a screen can pin a
 * clock. [isComplete] is the single exception and reads the wall clock itself, because "complete"
 * is a property of the part at the moment it is asked.
 *
 * Ported from `ios/Sources/Models/Models.swift`, `Models+Shared.swift` and `Models+Enrichment.swift`
 * against `docs/android-port/spec/models.md`.
 */

// ---------------------------------------------------------------------------------------------
// 0. The two anchors, named once
// ---------------------------------------------------------------------------------------------

/**
 * A real instant. Read in the device's zone. Also the anchor `now` is ALWAYS read in — `now` IS a
 * real instant whatever calendar the timestamp beside it lives in.
 */
private val LOCAL: TimeAnchor = TimeAnchor.LOCAL

/**
 * A date-only fact carried as a synthesized 17:00 UTC instant, so only its UTC calendar day is
 * real. Its clock must never be rendered and never thresholded on.
 */
private val UTC_DATE: TimeAnchor = TimeAnchor.UTC_DATE

/**
 * `Episode.airDate` only ever comes from TMDB — AniList exposes none — so it is always a date-only
 * fact and must be read in its own UTC day, never the device's, **whatever the franchise's source
 * is**. Deliberately not `source.timeAnchor`.
 */
private val EPISODE_AIR_DATE_ANCHOR: TimeAnchor = UTC_DATE

// ---------------------------------------------------------------------------------------------
// 1. FranchisePart — simple state
// ---------------------------------------------------------------------------------------------

/** Movies are a single binary unit (watched / not watched) — no episode count. */
val FranchisePart.isMovie: Boolean
    get() = kind == PartKind.MOVIE

/**
 * Keyed on the catalogue's status **ALONE**.
 *
 * A catalogue that publishes an announced season's planned episode count (TMDB does) would
 * otherwise fail the old `airedEpisodes == 0` test and the season would masquerade as released —
 * losing its premiere date and inventing a backlog.
 */
val FranchisePart.isUpcoming: Boolean
    get() = status == "NOT_YET_RELEASED"

/** The premiere instant, and only while the part is genuinely announced. */
val FranchisePart.premiereAt: Long?
    get() = if (isUpcoming) nextAiringAt else null

/**
 * The CATALOGUE-COUNT version of "behind", ported verbatim from the server's `format.ts`
 * `episodesBehind`. Fine for the Library's calm captions, where an hour is nothing; every live
 * surface reads [behind] instead.
 */
val FranchisePart.episodesBehind: Int
    get() = if (isReleasing) maxOf(0, airedEpisodes - progress) else 0

val FranchisePart.isBehind: Boolean
    get() = episodesBehind > 0

val FranchisePart.isCaughtUp: Boolean
    get() = isReleasing && episodesBehind == 0

val FranchisePart.isFinished: Boolean
    get() = if (isMovie) progress > 0 else (!isReleasing && totalEpisodes > 0 && progress >= totalEpisodes)

/**
 * How many episodes there are to watch right now.
 *
 * Zero for an announced part: a season that hasn't started has nothing to watch, whatever episode
 * count the catalogue advertises for it.
 */
fun FranchisePart.availableEpisodes(): Int {
    if (isUpcoming) return 0
    return if (airedEpisodes > 0) airedEpisodes else totalEpisodes
}

/**
 * Highest episode number that may be recorded as watched — the season's **SIZE**.
 *
 * A "+1" logging control with no ceiling will happily run progress past the end of a season (a
 * 10-episode season sat at 59/10 because every tap incremented and the progress ring clamped its
 * *visual* at 100 %, so the overrun was invisible).
 *
 * Deliberately the season size rather than [availableEpisodes]: aired counts trail the catalogue by
 * up to an hour, and blocking a legitimate write on stale sync data is worse than allowing a keen
 * viewer to run a few episodes ahead. Unknown size (ongoing AniList shows carry `episodes: null`)
 * leaves it **unbounded** rather than guessing.
 */
val FranchisePart.progressCeiling: Int
    get() {
        if (isUpcoming) return 0
        val size = maxOf(totalEpisodes, airedEpisodes)
        return if (size > 0) size else Int.MAX_VALUE
    }

// ---------------------------------------------------------------------------------------------
// 2. scheduleAirings — the calendar-facts fallback
// ---------------------------------------------------------------------------------------------

/**
 * `airings` when the server sent them; otherwise the two slots every server has always published —
 * the next episode and the latest aired one — so a weekly show still lands on its next date and its
 * last one. Ascending by instant.
 *
 * Against a modern server the fallback is never reached; it exists so an old deployment shows each
 * weekly show once rather than not at all.
 */
val FranchisePart.scheduleAirings: List<Airing>
    get() {
        if (airings.isNotEmpty()) return airings
        val out = ArrayList<Airing>(2)
        val last = lastAiredAt
        if (last != null && last > 0 && airedEpisodes > 0) {
            out.add(Airing(episode = airedEpisodes, at = last))
        }
        val next = nextAiringAt
        if (next != null && next > 0) {
            val ep = nextEpisodeNumber ?: (airedEpisodes + 1)
            if (out.none { it.episode == ep }) out.add(Airing(episode = ep, at = next))
        }
        return out.sortedBy { it.at }
    }

// ---------------------------------------------------------------------------------------------
// 3. Airings-derived freshness — the four functions everything live reads
// ---------------------------------------------------------------------------------------------
//
// `airedEpisodes`, `lastAiredAt` and `nextAiringAt` are the CATALOGUE'S facts, advanced by an
// hourly sync. `airings` is the per-episode calendar the same payload carries, and a slot in it
// that has struck IS an aired episode — the count merely hasn't caught up yet. Reading only the
// counts made the one show that had just aired (Re:ZERO, 6:30 PM) the one show Today could not see
// for up to an hour: not fresh (count unchanged), not waiting (slot passed) — gone. Every "is it
// out yet / when is the next one" question goes through these four. The raw fields stay for sort
// keys and the Library's calm captions, where an hour is nothing.

/**
 * The anchor-aware "has this slot struck" predicate: a real instant once its clock has struck; a
 * date-only slot **the day AFTER** its date (its clock is synthesized, and on the day itself it
 * still reads "today").
 */
internal fun FranchisePart.passedAirings(now: Long, anchor: TimeAnchor = LOCAL): List<Airing> =
    airings.filter { a ->
        if (anchor.isDateOnly) Formatting.dayDiff(a.at, now, anchor) < 0 else a.at <= now
    }

/** How many episodes are out, counting struck slots the catalogue's count has not reached yet. */
fun FranchisePart.airedByNow(now: Long, anchor: TimeAnchor = LOCAL): Int {
    if (!isReleasing) return airedEpisodes
    return maxOf(airedEpisodes, passedAirings(now, anchor).maxOfOrNull { it.episode } ?: 0)
}

/** How many episodes are out and unwatched. The live surfaces' "behind", not [episodesBehind]. */
fun FranchisePart.behind(now: Long, anchor: TimeAnchor = LOCAL): Int =
    if (isReleasing) maxOf(0, airedByNow(now, anchor) - progress) else 0

/**
 * When the most recent episode dropped — the later of the catalogue's field and the latest struck
 * slot. Deliberately **not** gated on `isReleasing`: a season that finished between syncs still
 * aired its last episode.
 */
fun FranchisePart.lastAired(now: Long, anchor: TimeAnchor = LOCAL): Long? =
    listOfNotNull(lastAiredAt, passedAirings(now, anchor).maxOfOrNull { it.at }).maxOrNull()

/**
 * The next slot still AHEAD — **strictly future** for a timed source (a slot that has struck is an
 * episode, not a wait), **today-or-later** for date-only — from the airings first, then the
 * catalogue's single slot. What every "Airs Friday" / countdown reads.
 */
fun FranchisePart.upcomingAiring(now: Long, anchor: TimeAnchor = LOCAL): Long? {
    val ahead = airings
        .filter { a ->
            if (anchor.isDateOnly) Formatting.dayDiff(a.at, now, anchor) >= 0 else a.at > now
        }
        .minOfOrNull { it.at }
    if (ahead != null) return ahead
    val slot = scheduledAiring(now, anchor) ?: return null
    return if (anchor.isDateOnly || slot > now) slot else null
}

/**
 * The catalogue's single next slot, guarded.
 *
 * A `nextAiringAt` in the past is **STALE DATA, not a schedule**: the catalogue simply hasn't
 * advanced the slot yet (an announced premiere whose date has come and gone, a season that ended
 * between syncs). Reading it as a live schedule is what made a week-old timestamp render as "today"
 * every day. **Same-day is kept** — an episode that aired a few hours ago still legitimately reads
 * as "today". A TMDB slot must be judged against its own UTC date or a JST morning keeps
 * yesterday's drop alive as "today"; prefer [Franchise.nextAiring], which can't forget to pass it.
 */
fun FranchisePart.scheduledAiring(now: Long, anchor: TimeAnchor = LOCAL): Long? {
    val next = nextAiringAt ?: return null
    return if (Formatting.dayDiff(next, now, anchor) >= 0) next else null
}

// ---------------------------------------------------------------------------------------------
// 4. The aired / renderable / mark-target ladder
// ---------------------------------------------------------------------------------------------
//
// Three different questions that were repeatedly confused for one another:
//   provenAiredCount      — how many episodes we can PROVE have aired;
//   renderableEpisodeCount — how many rows to draw (plumbing; NEVER shown as a season length);
//   markTarget            — what "mark this season watched" writes.

/**
 * How many episodes we can PROVE have aired.
 *
 * `airedEpisodes` is the server's derivation from catalogue airing data, but a part caught mid-sync
 * can report 0 while its own episode list already carries dates in the past. Trusting that blindly
 * dims every row and collapses [markTarget] onto the user's progress, so a season header renders
 * "watched" purely because there is nothing left to compare against. An episode whose air date has
 * passed HAS aired, so take the higher count.
 *
 * The `dated` term is strictly **BEFORE today**, not "today or earlier": today's slot is the one
 * the catalogue is still counting down to, and swallowing it here would cost the next-to-air row
 * its date badge on every healthy season the moment its drop day arrives.
 *
 * The `struck` term exists because a per-episode slot that has struck is an aired episode too:
 * without it the mark target trailed the catalogue's count by a sync, so the episode Today had just
 * called "out now" could not be marked. For a date-only source this admits the drop day once its
 * synthesized 17:00 UTC instant has passed — TMDB's own date has arrived by then.
 *
 * **Deliberate asymmetry — do not "unify" it.** `struck` uses the raw `at <= now` with **no
 * anchor**, while [passedAirings] requires `dayDiff < 0` for a date-only source; `provenAiredCount`
 * is therefore *more permissive* for TMDB. `dated` uses `dayDiff < 0` at
 * [EPISODE_AIR_DATE_ANCHOR], which is always UTC. Three different passed-ness tests inside one
 * function, each justified above.
 */
fun FranchisePart.provenAiredCount(now: Long): Int {
    if (!isReleasing) return airedEpisodes
    val dated = episodes.fold(0) { acc, ep ->
        val d = ep.airDate
        if (d != null && Formatting.dayDiff(d, now, EPISODE_AIR_DATE_ANCHOR) < 0) maxOf(acc, ep.number) else acc
    }
    val struck = airings.filter { it.at <= now }.maxOfOrNull { it.episode } ?: 0
    return maxOf(airedEpisodes, dated, struck)
}

/**
 * How many episode rows to draw. With a known total, never exceed it. With an unknown total (0)
 * extend one past what has aired so the next-to-air row can carry its date badge.
 *
 * **Row plumbing ONLY: it is a guess, and a guess must never be shown as a season length.**
 */
fun FranchisePart.renderableEpisodeCount(now: Long): Int {
    if (totalEpisodes > 0) return totalEpisodes
    val aired = provenAiredCount(now)
    val nextToAir = if (isReleasing && nextAiringAt != null) aired + 1 else 0
    return maxOf(aired, progress, nextToAir)
}

/** What "mark this season watched" writes. Bounded **again** by [progressCeiling] at the write site. */
fun FranchisePart.markTarget(now: Long): Int =
    if (isReleasing) provenAiredCount(now) else renderableEpisodeCount(now)

/**
 * Reads the wall clock on purpose: "complete" is a property of the part at the moment it is asked,
 * and callers that need a pinned clock use [markTarget] directly.
 */
val FranchisePart.isComplete: Boolean
    get() {
        val target = markTarget(System.currentTimeMillis())
        return target > 0 && progress >= target
    }

// ---------------------------------------------------------------------------------------------
// 5. FranchisePart — labels
// ---------------------------------------------------------------------------------------------

/**
 * The source's OWN label ("Season 4", "Final Season", "Part 2"), trimmed. **Never derived from
 * `sequence`** — `sequence` counts a franchise's members, which is not the number the world uses
 * for a season, and rendering "S5" beside a label that reads "Season 4" is a P0. Empty string when
 * the source gave no label: unknown says unknown, and a fabricated "Season 1" is worse than nothing.
 */
val FranchisePart.canonicalLabel: String
    get() = label.trim()

/**
 * The catalogue relates this part to the work as a spin-off. A spin-off is an extra, never a season
 * of the show, whatever its `kind` says.
 */
val FranchisePart.isSpinOff: Boolean
    get() = relationship?.uppercase() == "SPIN_OFF"

/** "Episode 19" — never "E19", never "Ep 19". */
fun FranchisePart.episodeLabel(n: Int): String = Copy.episode(n)

/**
 * The part-local watch context: a movie is its own label, everything else is
 * "Season 4 · Episode 19" (or a bare "Episode 19" when the source gave no label).
 *
 * Resolves an iOS inconsistency deliberately: the Swift part-local sibling concatenated
 * `canonicalLabel` **raw** while `Franchise.watchContext` routed through `Copy.watchContext`, which
 * compacts "Season 5: Hashira Training Arc" to "Season 5". Two spellings of one fact — Android uses
 * the compacting one on both sides.
 */
fun FranchisePart.watchContext(episode: Int): String =
    if (isMovie) canonicalLabel else Copy.watchContext(canonicalLabel, episode)

/** The catalogue's own premiere slot, formatted in the source's calendar. */
fun FranchisePart.premiereDateLabel(source: MediaSource): String? =
    premiereAt?.let { Formatting.fmtFullDate(it, source.timeAnchor) }

/**
 * [premiereDateLabel] reads the catalogue's own premiere slot, which TMDB frequently leaves null
 * while still dating the season through its first episode. Falling back to the earliest episode air
 * date is the difference between a real date and a bare "TBA".
 */
fun FranchisePart.announcedDateLabel(source: MediaSource): String? {
    premiereDateLabel(source)?.let { return it }
    val earliest = episodes.mapNotNull { it.airDate }.minOrNull() ?: return null
    return Formatting.fmtFullDate(earliest, EPISODE_AIR_DATE_ANCHOR)
}

// ---------------------------------------------------------------------------------------------
// 6. FranchisePart — copy-with helpers (optimistic writes)
// ---------------------------------------------------------------------------------------------

/**
 * **Every optimistic progress write goes through this** so a local mark never drops a field the
 * server sent. The hand-built copy it replaced omitted `airings`, and a marked show left the
 * calendar until the next reload.
 *
 * `data class.copy()` is exactly the mechanism that makes the failure impossible on Android:
 * **never hand-build a [FranchisePart]; always `copy()`.**
 */
fun FranchisePart.withProgress(episodes: Int): FranchisePart = copy(progress = maxOf(0, episodes))

/** Everything else carried verbatim — see [withProgress] for why that matters. */
fun FranchisePart.withEpisodes(episodes: List<Episode>): FranchisePart = copy(episodes = episodes)

/** The detail read's three enrichment fields, everything else carried verbatim. */
fun FranchisePart.with(
    episodes: List<Episode>,
    images: ArtworkSet?,
    videos: List<FranchiseVideo>,
): FranchisePart = copy(episodes = episodes, images = images, videos = videos)

// ---------------------------------------------------------------------------------------------
// 7. Franchise — calendar wrappers
// ---------------------------------------------------------------------------------------------
//
// These exist purely so a call site CANNOT forget the anchor. Prefer them to the part-level
// primitives everywhere a franchise is in hand.

val Franchise.timeAnchor: TimeAnchor
    get() = source.timeAnchor

fun Franchise.dayKey(ts: Long): Long = Formatting.localDayKey(ts, timeAnchor)

fun Franchise.dayDiff(ts: Long, now: Long): Int = Formatting.dayDiff(ts, now, timeAnchor)

/** Anime: "Tomorrow 9:00 PM". TV (date-only): "Tomorrow" / "Thursday" / "May 4" — never a clock. */
fun Franchise.whenLabel(ts: Long, now: Long): String = Formatting.fmtWhen(ts, now, timeAnchor)

/** The next episode still ahead, judged in this franchise's own calendar. */
fun Franchise.nextAiring(now: Long): Long? = releasingPart?.upcomingAiring(now, timeAnchor)

/** The most recent drop, judged in this franchise's own calendar. */
fun Franchise.lastAired(now: Long): Long? = releasingPart?.lastAired(now, timeAnchor)

// ---------------------------------------------------------------------------------------------
// 8. Franchise — the part every live surface operates on
// ---------------------------------------------------------------------------------------------

/**
 * Pick the releasing part, preferring the one with the soonest next airing, else the most recently
 * aired.
 *
 * Reads the **raw** `nextAiringAt` / `lastAiredAt` on purpose — the airings-derived logic is applied
 * *after* the part is chosen.
 */
val Franchise.releasingPart: FranchisePart?
    get() {
        val releasing = parts.filter { it.isReleasing }
        if (releasing.isEmpty()) return null
        val upcoming = releasing
            .filter { it.nextAiringAt != null }
            .sortedBy { it.nextAiringAt ?: Long.MAX_VALUE }
        upcoming.firstOrNull()?.let { return it }
        return releasing.sortedByDescending { it.lastAiredAt ?: 0L }.firstOrNull()
    }

/**
 * No known next airing sorts **last** in an ascending sort. Reuse this rather than re-inlining a
 * `?: Long.MAX_VALUE` sentinel at a call site.
 */
val Franchise.nextAiringSortKey: Long
    get() = releasingPart?.nextAiringAt ?: Long.MAX_VALUE

/**
 * The **CATALOGUE'S** field: fine for the Library's calm shelves, wrong for anything live — sort
 * Today's stack on [lastAired] instead, or tonight's episode loses the hero to a days-old drop.
 * No aired part sorts last in a descending sort.
 */
val Franchise.lastAiredSortKey: Long
    get() = releasingPart?.lastAiredAt ?: 0L

/**
 * The spine, in watch order. A movie is a binary unit and is handled separately; specials and music
 * videos are not part of the spine.
 */
val Franchise.episodicPartsInOrder: List<FranchisePart>
    get() = parts
        .filter { it.kind == PartKind.SEASON || it.kind == PartKind.ONA || it.kind == PartKind.OVA }
        .sortedBy { it.sequence }

/**
 * The SEASONS — what the show page's picker lists and what "Season N" means on that screen: the
 * `SEASON` parts that are not spin-offs. OVAs, ONAs, side stories, spin-offs, specials and films are
 * extras, on the shelf under the episode list. The picker used to list every episodic part in
 * release order — nine entries on Slime, OVAs and specials interleaved ("utterly confusing", 4 Sep);
 * Netflix, Apple TV, Prime and Crunchyroll list seasons only. A work with no season at all (an ONA
 * run) keeps its whole episodic spine, so it still has an Episodes section.
 */
val Franchise.seasonPartsInOrder: List<FranchisePart>
    get() {
        val seasons = episodicPartsInOrder.filter { it.kind == PartKind.SEASON && !it.isSpinOff }
        return seasons.ifEmpty { episodicPartsInOrder }
    }

// ---------------------------------------------------------------------------------------------
// 9. Franchise — resume and backlog
// ---------------------------------------------------------------------------------------------

/**
 * The part the user would actually resume, in watch order: the one they're mid-way through, else
 * the first unstarted part *after* everything they finished, else the earliest part with anything
 * left. Null when there's no backlog anywhere.
 *
 * **Picking by sequence (not by largest backlog) is the point:** a `max()` would resume S3 at 3/10
 * into an untouched S5 just because S5 is longer. With non-sequential progress (S2 untouched, S3
 * half-watched) the mid-watch part still wins — resuming what you're actively watching beats
 * sending you back to a season you skipped.
 */
val Franchise.resumePart: FranchisePart?
    get() {
        val eps = episodicPartsInOrder

        // 1. mid-watch
        eps.firstOrNull { it.progress > 0 && it.progress < it.availableEpisodes() }?.let { return it }

        // 2. the first unstarted part AFTER the highest-sequence completed one. `lastOrNull` over an
        //    ascending list IS the highest-sequence completed part. Note the fall-through: when a
        //    completed part exists but nothing later qualifies, control reaches step 3 rather than
        //    returning null.
        val doneSeq = eps
            .lastOrNull { it.availableEpisodes() > 0 && it.progress >= it.availableEpisodes() }
            ?.sequence
        if (doneSeq != null) {
            eps.firstOrNull { it.sequence > doneSeq && it.availableEpisodes() - it.progress > 0 }
                ?.let { return it }
        }

        // 3. the earliest part with anything left
        return eps.firstOrNull { it.availableEpisodes() - it.progress > 0 }
    }

/** The "Keep watching" count; 0 when nothing is left. */
val Franchise.continueBacklog: Int
    get() {
        val p = resumePart ?: return 0
        return maxOf(0, p.availableEpisodes() - p.progress)
    }

// ---------------------------------------------------------------------------------------------
// 10. Franchise — status and the gating ladder
// ---------------------------------------------------------------------------------------------

/** The library row's status, then the subscription's, then `planned` — a row is never status-less. */
val Franchise.effectiveStatus: WatchStatus
    get() = status ?: subscription?.status ?: WatchStatus.PLANNED

/**
 * A `planned` show is in your library but not in your week. You are not behind on it and you are
 * not waiting on its next episode; it is something you might start. Without this test a
 * mid-broadcast show you had only shelved arrived on Today as "20 episodes behind" and on Schedule
 * with a mark ring whose action was "Mark 20 episodes as watched" — **an obligation invented out of
 * a bookmark**, which is exactly what the urgency pact forbids.
 *
 * Every other status keeps its airings, deliberately: a `completed` show that starts a new season
 * is news, and a `paused` one still has a calendar. Episode notifications and the airing Live
 * Update gate **harder still (`watching` only)** — they interrupt you.
 *
 * The ladder, three tiers: all statuses (Library shelves) ⊃ [tracksAirings] (Schedule, Today's Out
 * now / Airing soon / Now Bar) ⊃ `watching` (episode alerts).
 */
val Franchise.tracksAirings: Boolean
    get() = effectiveStatus != WatchStatus.PLANNED

// ---------------------------------------------------------------------------------------------
// 11. Franchise — current part, completion, labels, snapshot
// ---------------------------------------------------------------------------------------------

val Franchise.currentPart: FranchisePart?
    get() = releasingPart ?: resumePart ?: episodicPartsInOrder.firstOrNull { !it.isComplete }

/**
 * The whole work is finished: every episodic member complete, nothing releasing, and no future
 * installment announced. This is the question the "complete" copy and the series-complete milestone
 * both ask — it lives here so no screen re-derives it.
 */
val Franchise.isSeriesComplete: Boolean
    get() {
        val episodic = episodicPartsInOrder
        return episodic.isNotEmpty() &&
            episodic.all { it.isComplete } &&
            parts.none { it.isReleasing || it.isUpcoming } &&
            upcoming?.isFutureInstallment != true
    }

/**
 * Watched through: every episodic member complete and nothing releasing or upcoming — the
 * series-complete milestone's own test. Unlike [isSeriesComplete] a curated rumour does not count:
 * a rumour is not a season to watch (i4).
 */
val Franchise.isWatchedThrough: Boolean
    get() {
        val episodic = episodicPartsInOrder
        return episodic.isNotEmpty() && episodic.all { it.isComplete } &&
            parts.none { it.isReleasing || it.isUpcoming }
    }

fun Franchise.canonicalPartLabel(mediaId: Int): String =
    parts.firstOrNull { it.mediaId == mediaId }?.canonicalLabel ?: ""

/** "Anime" / "TV". The app never says "AniList" or "TMDB" to a viewer. */
val Franchise.kindWord: String
    get() = source.kindWord

/**
 * `Franchise` is an immutable value, so this is the whole show — parts, progress and status —
 * frozen at the instant of the removal. That is what lets Undo restore instantly, before any
 * network round-trip. It only holds because every model in the graph is an immutable `data class`
 * over immutable lists.
 */
val Franchise.snapshotForUndo: Franchise
    get() = this

/**
 * The title wherever identity is being **recognised** — Today, Library, Schedule, Detail. The raw
 * `title` is kept for exactly two jobs: Search results, where the user is matching what they typed
 * against a catalogue and every character of the source string is evidence, and accessibility
 * labels, which always speak the whole title.
 */
val Franchise.displayTitle: String
    get() = title.shelfShortened

/**
 * THE watch-context rule: "Season 7 · Episode 5" on a multi-part franchise, "Episode 5" on a single
 * one. Today owned this rule privately while Library and Schedule always printed the season and
 * Detail's Next up card never did — one fact, three grammars. Every screen calls this now.
 */
fun Franchise.watchContext(part: FranchisePart, episode: Int): String {
    if (part.isMovie) return part.canonicalLabel
    return if (parts.size > 1) Copy.watchContext(part.canonicalLabel, episode) else Copy.episode(episode)
}

// ---------------------------------------------------------------------------------------------
// 12. Franchise — sections
// ---------------------------------------------------------------------------------------------

/** One kind of member, in the order that kind is listed. */
data class PartSection(val kind: PartKind, val parts: List<FranchisePart>)

/**
 * Seasons are listed **newest-first** (reverse sequence) so the latest season is at the top; other
 * kinds stay chronological. `groupBy` preserves encounter order and the final sort on the unique
 * `sortRank` makes the whole result deterministic.
 *
 * Note the latent defect carried from iOS: `OVA` and `ONA` share a section title but have different
 * `sortRank`s, so a franchise carrying both renders two sections both titled "OVAs". Detail no
 * longer draws a seasons section list, so it is currently unreachable.
 */
val Franchise.sections: List<PartSection>
    get() = parts
        .groupBy { it.kind }
        .map { (kind, members) ->
            val ordered = members.sortedBy { it.sequence }
            PartSection(kind, if (kind == PartKind.SEASON) ordered.reversed() else ordered)
        }
        .sortedBy { it.kind.sortRank }

// ---------------------------------------------------------------------------------------------
// 13. Franchise — enrichment derivations
// ---------------------------------------------------------------------------------------------

/** Featured first, then the show's own, then each part's; de-duplicated by site + id, first wins. */
val Franchise.allVideos: List<FranchiseVideo>
    get() {
        val seen = HashSet<String>()
        val out = ArrayList<FranchiseVideo>()
        for (v in listOfNotNull(featuredVideo) + videos + parts.flatMap { it.videos }) {
            if (seen.add("${v.site}/${v.id}")) out.add(v)
        }
        return out
    }

/**
 * The market's own word, else the adult flag. Nothing when the catalogue says nothing — the server
 * does not substitute another country's rating, so a miss is genuinely a miss.
 */
val Franchise.contentRatingLabel: String?
    get() {
        nonEmptyOrNull(audience?.contentRating?.rating)?.let { return it }
        return if (audience?.isAdult == true) Copy.Label.adultRating else null
    }

/**
 * The catalogue's themes for an anime often ARE its genres, and a fact printed twice on one screen
 * is a defect.
 */
val Franchise.themesBeyondGenres: List<String>
    get() {
        val known = (genres + parts.flatMap { it.genres }).map { it.lowercase() }.toSet()
        return themes.filter { it.lowercase() !in known }
    }

/**
 * True while the server's background enrichment has not reached this row yet. Detail re-reads once
 * on seeing this (after 6 s). Ignores `themes` and each part's `videos` on purpose — those are
 * cheap and arrive earlier.
 */
val Franchise.looksUnenriched: Boolean
    get() = (people?.isEmpty ?: true) && related.isEmpty() && videos.isEmpty() && featuredVideo == null

// ---------------------------------------------------------------------------------------------
// 14. Franchise — grafting the detail read onto the live library copy
// ---------------------------------------------------------------------------------------------

/**
 * The live **LIBRARY** copy (fresh progress and status) with the **DETAIL** fetch's per-episode data
 * and catalogue enrichment grafted on.
 *
 * The library payload carries the enrichment too, but it was read at launch — before the server's
 * stale-while-revalidate pass may have run — so a detail read that came back richer wins, field by
 * field. The market-matched `audience` and the fresher `continueWatching` **always** come from the
 * detail read.
 *
 * The receiver is the library copy. `progress`, `status`, `subscription`, `behind`, `newParts`,
 * `upcoming`, `title`, `synopsis`, `genres`, `year` and `studios` all come from it, untouched.
 */
fun Franchise.grafting(fetched: Franchise): Franchise {
    // A detail read for a different show is not an update. No-op.
    if (fetched.id != id) return this

    // Duplicate mediaId in the fetched parts: FIRST wins.
    val byMedia = LinkedHashMap<Int, FranchisePart>(fetched.parts.size)
    for (p in fetched.parts) if (!byMedia.containsKey(p.mediaId)) byMedia[p.mediaId] = p

    // Mapped over the LIBRARY's parts only — a part the detail read knows about but the library
    // copy does not is dropped.
    val mergedParts = parts.map { p ->
        val d = byMedia[p.mediaId] ?: return@map p
        val eps = if (p.episodes.isEmpty()) d.episodes else p.episodes
        val vids = if (p.videos.isEmpty()) d.videos else p.videos
        val imgs = p.images ?: d.images
        // Identity optimisation: skip the allocation when nothing changed. Compares COUNTS, not
        // contents — deliberately cheap, because it runs per part on every detail read.
        if (eps.size == p.episodes.size && vids.size == p.videos.size && imgs == p.images) p
        else p.with(episodes = eps, images = imgs, videos = vids)
    }

    // Field by field: the library keeps what it already has, the detail read fills what it does not.
    val mergedImages = images ?: fetched.images
    val mergedThemes = if (themes.isEmpty()) fetched.themes else themes
    val mergedFeatured = featuredVideo ?: fetched.featuredVideo
    val mergedVideos = if (videos.isEmpty()) fetched.videos else videos
    // `!= false` is the null-safe spelling of iOS's `(people?.isEmpty ?? true)`.
    val mergedPeople = if (people?.isEmpty != false) fetched.people else people
    val mergedRelated = if (related.isEmpty()) fetched.related else related
    // The market-matched `audience` and the fresher `continueWatching` ALWAYS come from the detail
    // read — the library payload's copies were fetched without a country and before the last mark.
    val mergedAudience = fetched.audience ?: audience
    val mergedContinue = fetched.continueWatching ?: continueWatching

    return copy(
        parts = mergedParts,
        images = mergedImages,
        themes = mergedThemes,
        featuredVideo = mergedFeatured,
        videos = mergedVideos,
        audience = mergedAudience,
        people = mergedPeople,
        related = mergedRelated,
        continueWatching = mergedContinue,
    )
}

// ---------------------------------------------------------------------------------------------
// 15. FranchiseUpcoming — the curated "what's next" note
// ---------------------------------------------------------------------------------------------

/**
 * The order a "Returns …" caption sorts by: `value` is `yyyymmdd`, `precision` breaks ties so a
 * concrete month sorts ahead of a bare year.
 */
data class ReleaseSortKey(val value: Int, val precision: Int) : Comparable<ReleaseSortKey> {
    override fun compareTo(other: ReleaseSortKey): Int =
        compareValuesBy(this, other, { it.value }, { it.precision })

    companion object {
        const val DAY = 3
        const val MONTH = 2
        const val YEAR = 1

        /** What a null key sorts as: **last**, never as 0. */
        val LAST = ReleaseSortKey(Int.MAX_VALUE, 0)
    }
}

/**
 * The badge word. Not in the `Copy` catalogue because it has no live call site — it lives on the
 * model exactly as it does on iOS.
 */
val FranchiseUpcoming.tag: String
    get() = when (status) {
        "airing" -> "Airing now"
        "upcoming_dated" -> "Upcoming"
        "announced", "announced_no_date" -> "Announced"
        "recently_aired" -> "Recently aired"
        "rumored" -> "Rumored"
        "concluded" -> "Complete"
        else -> "Upcoming"
    }

val FranchiseUpcoming.isConcluded: Boolean
    get() = status == "concluded"

/**
 * An unconfirmed report is not a schedule. A rumour is labelled one everywhere the curated fact
 * appears — never a date, never amber.
 */
val FranchiseUpcoming.isRumored: Boolean
    get() = status == "rumored"

val FranchiseUpcoming.isFutureInstallment: Boolean
    get() = status == "upcoming_dated" || status == "announced" ||
        status == "announced_no_date" || status == "rumored"

/** "Jul 5, 2026" / "Oct 2026" / "Summer 2027". Empty when the note states no release at all. */
val FranchiseUpcoming.displayRelease: String
    get() {
        val raw = release
        if (raw == null || raw.isBlank()) return ""
        return Formatting.prettyReleaseString(raw)
    }

/**
 * **The server's** order, not a reading of `release`. Null when the window is genuinely unknown —
 * TBA, prose with no date, *and every rumor*, all of which the server already resolves to
 * `unknown` — so those sort to the end via [ReleaseSortKey.LAST].
 *
 * This used to parse `release` here, and only its ISO forms, which filed "October 2026" and
 * "Summer 2027" under January of their year: a shelf sorted "soonest first" put October 2026 ahead
 * of an August 2026 premiere while its own caption read "Returns Oct 2026". The prose lives in one
 * grammar on the server now.
 */
val FranchiseUpcoming.releaseSortKey: ReleaseSortKey?
    get() {
        val window = releaseWindow ?: return null
        val value = window.sortKey ?: return null
        return when (window.precision) {
            ReleaseWindow.Precision.DAY -> ReleaseSortKey(value, ReleaseSortKey.DAY)
            ReleaseWindow.Precision.MONTH,
            ReleaseWindow.Precision.QUARTER,
            -> ReleaseSortKey(value, ReleaseSortKey.MONTH)
            ReleaseWindow.Precision.YEAR -> ReleaseSortKey(value, ReleaseSortKey.YEAR)
            ReleaseWindow.Precision.UNKNOWN -> null
        }
    }

/**
 * True once a **DAY-dated** release is behind us: the installment is out, or slipped without the
 * catalogue's curated note noticing (its `checked` date is weeks old). Either way "Returns Jul 5"
 * is no longer a fact, and the Library must not file the show under Returning on it — **Mushoku
 * Tensei sat there reading "Returns today" two months into its third season.**
 *
 * Month / quarter / year windows are never "arrived": a month-precision window has no day to have
 * passed. The `yyyymmdd` key is read as a bare UTC calendar date, so it never shifts a day.
 */
fun FranchiseUpcoming.hasArrived(now: Long): Boolean {
    if (!isFutureInstallment) return false
    val key = releaseSortKey ?: return false
    if (key.precision != ReleaseSortKey.DAY) return false
    val ts = try {
        LocalDate.of(key.value / 10_000, (key.value / 100) % 100, key.value % 100)
            .atStartOfDay(ZoneOffset.UTC)
            .toInstant()
            .toEpochMilli()
    } catch (e: DateTimeException) {
        return false      // a key that is not a real calendar date has not "arrived"
    }
    return Formatting.dayDiff(ts, now, UTC_DATE) < 0
}

/** "Season 3 · Jul 5, 2026". Empty for anything that is not a future installment. */
val FranchiseUpcoming.cardBadge: String
    get() {
        if (!isFutureInstallment) return ""
        val what = nonEmptyOrNull(next) ?: "New season"
        val whenText = displayRelease
        // U+00B7 MIDDLE DOT with plain ASCII spaces either side — the app's universal fact separator.
        return if (whenText.isEmpty()) what else what + " · " + whenText
    }

// ---------------------------------------------------------------------------------------------
// 16. The shelf ladder (Today's stack order)
// ---------------------------------------------------------------------------------------------

/** The [order] IS the shelf sort order; the declaration order is the ladder. */
enum class ShelfState(val order: Int) {
    NEW_EPISODE(0),
    BACKLOG(1),
    AIRING_WAIT(2),
    PREMIERE_SOON(3),
}

/** The four windows the live surfaces measure against. */
object ShelfWindows {
    /** "Airing soon" lookahead. */
    const val SOON: Long = 48L * Time.HOUR_MS

    /** How recent an unwatched drop stays "out now". */
    const val OUT_NOW: Long = 7L * Time.DAY_MS

    /** How long the Now Bar keeps a struck airing live. */
    const val NOW_BAR_LIVE: Long = 24L * Time.HOUR_MS

    /** How far ahead an announced premiere earns a shelf. */
    const val PREMIERE_SHELF: Long = 45L * Time.DAY_MS
}

/** The soonest announced premiere still ahead of [now]. */
fun Franchise.nextPremiere(now: Long): Long? =
    parts.mapNotNull { it.premiereAt }.filter { it > now }.minOrNull()

/**
 * Which shelf this show belongs on, or null when it is dormant — caught up with nothing dated.
 *
 * Every test on the ladder reads the airings-derived freshness, never the catalogue's counts: the
 * show that had just aired must appear on the top shelf immediately, not an hourly cron later.
 */
fun Franchise.shelfState(now: Long): ShelfState? {
    val releasing = releasingPart
    if (releasing != null &&
        releasing.behind(now, timeAnchor) > 0 &&
        now - (releasing.lastAired(now, timeAnchor) ?: 0L) <= ShelfWindows.OUT_NOW
    ) {
        return ShelfState.NEW_EPISODE
    }
    if (resumePart != null) return ShelfState.BACKLOG
    if (releasing != null && releasing.isCaughtUp && nextAiring(now) != null) return ShelfState.AIRING_WAIT
    val premiere = nextPremiere(now)
    if (premiere != null && premiere - now <= ShelfWindows.PREMIERE_SHELF) return ShelfState.PREMIERE_SOON
    return null
}

// ---------------------------------------------------------------------------------------------
// 17. Title normalisation
// ---------------------------------------------------------------------------------------------

/**
 * Counts **grapheme clusters**, not UTF-16 code units.
 *
 * Swift's `String.count` is a grapheme count, so a straight `length` would cross
 * [shelfShortened]'s thresholds at a different point for a CJK title with combining marks or an
 * emoji. `BreakIterator` is ICU-backed on Android and its tables move with the API level, so this
 * is one of the values the instrumented corpus replays on both AVDs rather than only on the JVM.
 */
private fun graphemeCount(s: String): Int {
    if (s.isEmpty()) return 0
    val iter = BreakIterator.getCharacterInstance()
    iter.setText(s)
    var n = 0
    while (iter.next() != BreakIterator.DONE) n++
    return n
}

/**
 * The shelf/hero form of a source title.
 *
 * Source titles arrive wrapped in subtitle punctuation ("Re:ZERO -Starting Life in Another World-")
 * and a line that opens on a hyphen reads as a hyphenation bug, not as a title. Stripping the
 * dashes is lossless; what follows the em/en dash or the colon is a subtitle the shelf never had
 * room for anyway. A long "Title: Subtitle" keeps its identity half rather than an ellipsis
 * mid-word.
 */
val String.shelfShortened: String
    get() = shelfShortened(fitting = SHELF_FIT_DEFAULT)

/**
 * [shelfShortened] cut to a surface's budget (i3): a card's title has two lines of about thirteen
 * characters, the lane's caption one of thirty. A title within the budget keeps its subtitle; one
 * past it keeps its identity half, never fewer than [minHead] graphemes.
 */
fun String.shelfShortened(fitting: Int, minHead: Int = 12): String {
    var s = trim()

    // 1. A trailing "-…-" subtitle wrapper. Only when the string ENDS with a hyphen, and the cut
    //    is at the FIRST " -" (space + hyphen).
    if (s.endsWith("-")) {
        val open = s.indexOf(" -")
        if (open >= 0) s = s.substring(0, open)
    }

    // 2. Strip leading/trailing subtitle punctuation: space, hyphen, en dash, em dash, colon.
    s = s.trim { it == ' ' || it == '-' || it == EN_DASH || it == EM_DASH || it == ':' }

    // 3. A long "Title: Subtitle" keeps its identity half. The separators are tried IN ORDER and
    //    the first one that is both found and at least [minHead] graphemes in wins and returns; a
    //    separator found earlier than that does NOT return — the loop moves to the next one, so a
    //    title like "Re: Something very long …" is not cut down to "Re".
    if (graphemeCount(s) > fitting) {
        for (sep in SHELF_SEPARATORS) {
            val r = s.indexOf(sep)
            if (r >= 0 && graphemeCount(s.substring(0, r)) >= minHead) return s.substring(0, r)
        }
    }
    return s
}

/** The property's budget: a hero or a row, where forty graphemes fit. */
private const val SHELF_FIT_DEFAULT = 40

private const val EN_DASH = '–'
private const val EM_DASH = '—'

/**
 * The separators a long title may be cut at, **in priority order**. Colon first, then en dash, em
 * dash, spaced hyphen, and an opening parenthesis last.
 */
private val SHELF_SEPARATORS = listOf(": ", " – ", " — ", " - ", " (")
