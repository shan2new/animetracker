package com.anitrack.model

import org.junit.AfterClass
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.util.TimeZone

/**
 * Regression suite for `Derived.kt` — the freshness ladder.
 *
 * Every test named `…_regression…` (and most of the rest) reproduces a bug that shipped. The names
 * and comments carry the incident, because the formulas below look arbitrary without it.
 *
 * The default time zone is pinned to **Asia/Tokyo (UTC+9)** for the whole class: it is the zone
 * every two-calendar bug in this file was reported from ("a JST morning keeps yesterday's drop
 * alive as today", "every timezone east of UTC+7 read a day ahead"), and pinning it makes the
 * local-anchor assertions deterministic on any build machine. One test flips the zone to UTC on
 * purpose, to show the deliberate asymmetry inside `provenAiredCount`.
 */
class DerivedTest {

    companion object {
        private val JST: ZoneId = ZoneId.of("Asia/Tokyo")
        private var savedZone: TimeZone? = null

        @BeforeClass
        @JvmStatic
        fun pinZone() {
            savedZone = TimeZone.getDefault()
            TimeZone.setDefault(TimeZone.getTimeZone("Asia/Tokyo"))
        }

        @AfterClass
        @JvmStatic
        fun restoreZone() {
            savedZone?.let { TimeZone.setDefault(it) }
        }
    }

    // -----------------------------------------------------------------------------------------
    // Fixtures
    // -----------------------------------------------------------------------------------------

    /** A real AniList broadcast instant, stated in the zone the class pins. */
    private fun jst(y: Int, mo: Int, d: Int, h: Int = 12, mi: Int = 0): Long =
        ZonedDateTime.of(y, mo, d, h, mi, 0, 0, JST).toInstant().toEpochMilli()

    /** What the server writes for a TMDB date-only fact: 17:00 UTC on that calendar day. */
    private fun tmdbSlot(y: Int, mo: Int, d: Int): Long =
        LocalDate.of(y, mo, d).atTime(17, 0).toInstant(ZoneOffset.UTC).toEpochMilli()

    /** UTC midnight of a calendar day — how an `Episode.airDate` is keyed. */
    private fun utcDay(y: Int, mo: Int, d: Int): Long =
        LocalDate.of(y, mo, d).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()

    private inline fun <T> withDefaultZone(id: String, body: () -> T): T {
        val prev = TimeZone.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone(id))
        try {
            return body()
        } finally {
            TimeZone.setDefault(prev)
        }
    }

    private fun part(
        mediaId: Int = 1,
        kind: PartKind = PartKind.SEASON,
        sequence: Int = 1,
        label: String = "Season 1",
        status: String? = null,
        isReleasing: Boolean = false,
        totalEpisodes: Int = 0,
        airedEpisodes: Int = 0,
        nextEpisodeNumber: Int? = null,
        nextAiringAt: Long? = null,
        lastAiredAt: Long? = null,
        progress: Int = 0,
        genres: List<String> = emptyList(),
        episodes: List<Episode> = emptyList(),
        airings: List<Airing> = emptyList(),
        images: ArtworkSet? = null,
        videos: List<FranchiseVideo> = emptyList(),
    ) = FranchisePart(
        mediaId = mediaId,
        kind = kind,
        sequence = sequence,
        label = label,
        status = status,
        isReleasing = isReleasing,
        totalEpisodes = totalEpisodes,
        airedEpisodes = airedEpisodes,
        nextEpisodeNumber = nextEpisodeNumber,
        nextAiringAt = nextAiringAt,
        lastAiredAt = lastAiredAt,
        progress = progress,
        genres = genres,
        episodes = episodes,
        airings = airings,
        images = images,
        videos = videos,
    )

    private fun franchise(
        id: String = "f1",
        source: MediaSource = MediaSource.ANILIST,
        title: String = "Test Show",
        parts: List<FranchisePart> = emptyList(),
        status: WatchStatus? = null,
        subscription: Subscription? = null,
        upcoming: FranchiseUpcoming? = null,
        genres: List<String> = emptyList(),
        themes: List<String> = emptyList(),
        images: ArtworkSet? = null,
        videos: List<FranchiseVideo> = emptyList(),
        featuredVideo: FranchiseVideo? = null,
        audience: AudienceInfo? = null,
        people: FranchisePeople? = null,
        related: List<RelatedTitle> = emptyList(),
        continueWatching: ContinueWatching? = null,
    ) = Franchise(
        id = id,
        source = source,
        title = title,
        parts = parts,
        status = status,
        subscription = subscription,
        upcoming = upcoming,
        genres = genres,
        themes = themes,
        images = images,
        videos = videos,
        featuredVideo = featuredVideo,
        audience = audience,
        people = people,
        related = related,
        continueWatching = continueWatching,
    )

    // =========================================================================================
    // 1. Freshness comes from `airings`, never from the catalogue's counts
    // =========================================================================================

    /**
     * **Re:ZERO, 6:30 PM.** The hourly cron had not advanced `airedEpisodes` yet, so the one show
     * that had just aired was the one show Today could not see: not fresh (count unchanged), not
     * waiting (slot passed) — gone.
     */
    @Test
    fun airedByNow_regression_countsAStruckSlotTheHourlyCronHasNotReached() {
        val p = part(
            isReleasing = true,
            airedEpisodes = 11,             // the catalogue, one sync behind
            airings = listOf(Airing(episode = 12, at = jst(2026, 9, 4, 18, 30))),
        )
        val justBefore = jst(2026, 9, 4, 18, 15)
        val justAfter = jst(2026, 9, 4, 18, 45)

        assertEquals(11, p.airedByNow(justBefore, TimeAnchor.LOCAL))
        assertEquals(12, p.airedByNow(justAfter, TimeAnchor.LOCAL))
        // The catalogue-count derivation would still say 11 an hour later — that is the whole bug.
        assertEquals(11, p.airedEpisodes)
    }

    @Test
    fun behind_regression_readsTheAiringsNotTheCatalogueCount() {
        val p = part(
            isReleasing = true,
            airedEpisodes = 11,
            progress = 11,
            airings = listOf(Airing(episode = 12, at = jst(2026, 9, 4, 18, 30))),
        )
        val now = jst(2026, 9, 4, 19, 0)

        assertEquals(1, p.behind(now, TimeAnchor.LOCAL))
        // `episodesBehind` is the calm-caption version and is deliberately still 0 here.
        assertEquals(0, p.episodesBehind)
    }

    @Test
    fun behind_isZeroWhenTheSeasonIsNotReleasing() {
        val p = part(isReleasing = false, airedEpisodes = 12, progress = 0)
        assertEquals(0, p.behind(jst(2026, 9, 4), TimeAnchor.LOCAL))
        assertEquals(12, p.airedByNow(jst(2026, 9, 4), TimeAnchor.LOCAL))
    }

    @Test
    fun lastAired_regression_prefersTheStruckSlotOverTheStaleCatalogueField() {
        val p = part(
            isReleasing = true,
            airedEpisodes = 11,
            lastAiredAt = jst(2026, 8, 28, 18, 30),         // a week old, per the cron
            airings = listOf(Airing(episode = 12, at = jst(2026, 9, 4, 18, 30))),
        )
        val now = jst(2026, 9, 4, 19, 0)

        // `lastAiredSortKey` still reads the raw field — fine for the Library's calm shelves, wrong
        // for anything live, which is exactly why the two are separate accessors.
        assertEquals(jst(2026, 9, 4, 18, 30), p.lastAired(now, TimeAnchor.LOCAL))
    }

    @Test
    fun lastAired_isNotGatedOnIsReleasing() {
        // A season that finished between syncs still aired its last episode.
        val p = part(
            isReleasing = false,
            lastAiredAt = jst(2026, 9, 1, 18, 30),
            airings = listOf(Airing(episode = 12, at = jst(2026, 9, 4, 18, 30))),
        )
        assertEquals(jst(2026, 9, 4, 18, 30), p.lastAired(jst(2026, 9, 4, 19, 0), TimeAnchor.LOCAL))
    }

    @Test
    fun passedAirings_aTimedSlotCountsTheMomentItsClockStrikes() {
        val slot = jst(2026, 9, 4, 18, 30)
        val p = part(isReleasing = true, airings = listOf(Airing(episode = 12, at = slot)))

        assertEquals(0, p.passedAirings(slot - 1, TimeAnchor.LOCAL).size)
        assertEquals(1, p.passedAirings(slot, TimeAnchor.LOCAL).size)       // `at <= now`
    }

    /**
     * A date-only slot counts **the day AFTER** its date: its clock is synthesized, and on the day
     * itself it still reads "today".
     */
    @Test
    fun passedAirings_aDateOnlySlotCountsOnlyTheDayAfterItsUtcDate() {
        val p = part(
            isReleasing = true,
            airings = listOf(Airing(episode = 5, at = tmdbSlot(2026, 9, 4))),
        )

        // Still 4 September in JST — the drop day itself.
        assertEquals(0, p.passedAirings(jst(2026, 9, 4, 20, 0), TimeAnchor.UTC_DATE).size)
        // 5 September in JST — the day after the slot's own UTC day.
        assertEquals(1, p.passedAirings(jst(2026, 9, 5, 9, 0), TimeAnchor.UTC_DATE).size)
    }

    @Test
    fun upcomingAiring_isStrictlyFutureForATimedSource() {
        val slot = jst(2026, 9, 4, 18, 30)
        val p = part(isReleasing = true, airings = listOf(Airing(episode = 12, at = slot)))

        assertEquals(slot, p.upcomingAiring(slot - 1, TimeAnchor.LOCAL))
        // A slot that has struck is an episode, not a wait.
        assertNull(p.upcomingAiring(slot, TimeAnchor.LOCAL))
    }

    /**
     * A date-only slot stays "ahead" for the whole of its own UTC day, because its 17:00 clock is
     * synthesized and is not a fact. Run in UTC so the local day and the slot's day agree, which is
     * the only way to see the two rules disagree on the same instant.
     */
    @Test
    fun upcomingAiring_isTodayOrLaterForADateOnlySourceButStrictlyFutureForATimedOne() =
        withDefaultZone("UTC") {
            val slot = tmdbSlot(2026, 9, 4)                     // 2026-09-04 17:00 UTC
            val p = part(isReleasing = true, airings = listOf(Airing(episode = 5, at = slot)))
            val justAfter = slot + 30 * Time.MINUTE_MS          // still 4 September

            assertEquals(slot, p.upcomingAiring(justAfter, TimeAnchor.UTC_DATE))
            assertNull(p.upcomingAiring(justAfter, TimeAnchor.LOCAL))

            // Once the day turns over there is nothing ahead under either rule.
            assertNull(p.upcomingAiring(slot + Time.DAY_MS, TimeAnchor.UTC_DATE))
        }

    @Test
    fun upcomingAiring_takesTheSoonestSlotAhead() {
        val p = part(
            isReleasing = true,
            airings = listOf(
                Airing(episode = 14, at = jst(2026, 9, 18, 18, 30)),
                Airing(episode = 12, at = jst(2026, 9, 4, 18, 30)),
                Airing(episode = 13, at = jst(2026, 9, 11, 18, 30)),
            ),
        )
        assertEquals(
            jst(2026, 9, 11, 18, 30),
            p.upcomingAiring(jst(2026, 9, 5, 12, 0), TimeAnchor.LOCAL),
        )
    }

    @Test
    fun upcomingAiring_fallsBackToTheCatalogueSlotWhenThereAreNoAirings() {
        val p = part(isReleasing = true, nextAiringAt = jst(2026, 9, 11, 18, 30))
        assertEquals(
            jst(2026, 9, 11, 18, 30),
            p.upcomingAiring(jst(2026, 9, 4, 12, 0), TimeAnchor.LOCAL),
        )
    }

    /**
     * A `nextAiringAt` in the past is **stale data, not a schedule** — the catalogue simply hasn't
     * advanced the slot. Reading it as a live schedule is what made a week-old timestamp render as
     * "today" every day.
     */
    @Test
    fun scheduledAiring_regression_aPastNextAiringAtIsStaleDataNotASchedule() {
        val p = part(isReleasing = true, nextAiringAt = jst(2026, 8, 28, 18, 30))
        assertNull(p.scheduledAiring(jst(2026, 9, 4, 12, 0), TimeAnchor.LOCAL))
    }

    @Test
    fun scheduledAiring_keepsSameDay() {
        // An episode that aired a few hours ago still legitimately reads as "today".
        val p = part(isReleasing = true, nextAiringAt = jst(2026, 9, 4, 8, 0))
        assertEquals(
            jst(2026, 9, 4, 8, 0),
            p.scheduledAiring(jst(2026, 9, 4, 20, 0), TimeAnchor.LOCAL),
        )
    }

    /**
     * "A TMDB slot must be judged against its own UTC date or a JST morning keeps yesterday's drop
     * alive as 'today'." Same data, two anchors, two answers — which is why the franchise-level
     * wrapper exists and the part-level primitive should never be called bare.
     */
    @Test
    fun scheduledAiring_regression_aJstMorningKeepsYesterdaysTmdbDropAliveUnderTheWrongAnchor() {
        val p = part(isReleasing = true, nextAiringAt = tmdbSlot(2026, 9, 3))
        val jstMorning = jst(2026, 9, 4, 9, 0)      // = 2026-09-04 00:00 UTC

        // Wrong: read locally, the 17:00 UTC instant is 02:00 JST on the 4th — "today".
        assertEquals(tmdbSlot(2026, 9, 3), p.scheduledAiring(jstMorning, TimeAnchor.LOCAL))
        // Right: its own UTC day is the 3rd, which is yesterday. Stale.
        assertNull(p.scheduledAiring(jstMorning, TimeAnchor.UTC_DATE))
    }

    /**
     * The franchise-level wrappers exist so a call site *cannot forget the anchor*. Same part, same
     * instant, two sources, two answers.
     */
    @Test
    fun franchiseWrappers_passTheAnchorSoACallSiteCannotForgetIt() {
        val p = part(isReleasing = true, nextAiringAt = tmdbSlot(2026, 9, 4))
        val tv = franchise(source = MediaSource.TMDB, parts = listOf(p))
        val anime = franchise(source = MediaSource.ANILIST, parts = listOf(p))
        val now = jst(2026, 9, 5, 1, 0)          // 2026-09-04 16:00 UTC — 1 a.m. the next day in Tokyo

        assertEquals(TimeAnchor.UTC_DATE, tv.timeAnchor)
        assertEquals(TimeAnchor.LOCAL, anime.timeAnchor)
        // Its own UTC day (the 4th) is behind the viewer's local day (the 5th) — the slot is stale.
        assertNull(tv.nextAiring(now))
        // Read as a real instant, 17:00 UTC is still an hour ahead.
        assertEquals(tmdbSlot(2026, 9, 4), anime.nextAiring(now))
    }

    // =========================================================================================
    // 2. `planned` shows are not on the calendar
    // =========================================================================================

    /**
     * A shelved mid-broadcast show arrived on Today as "20 episodes behind" with a mark ring whose
     * action was "Mark 20 episodes as watched" — **an obligation invented out of a bookmark.**
     */
    @Test
    fun tracksAirings_regression_aPlannedShowIsInYourLibraryButNotInYourWeek() {
        val midBroadcast = part(isReleasing = true, airedEpisodes = 20, progress = 0)
        val shelved = franchise(parts = listOf(midBroadcast), status = WatchStatus.PLANNED)

        assertFalse(shelved.tracksAirings)
        // The part-level fact is unchanged — the gate is at the franchise, which is the level the
        // user's intent lives at.
        assertEquals(20, midBroadcast.behind(jst(2026, 9, 4), TimeAnchor.LOCAL))
    }

    @Test
    fun tracksAirings_everyOtherStatusKeepsItsAirings() {
        // A `completed` show that starts a new season is news, and a `paused` one still has a
        // calendar.
        for (s in listOf(
            WatchStatus.WATCHING,
            WatchStatus.COMPLETED,
            WatchStatus.PAUSED,
            WatchStatus.DROPPED,
        )) {
            assertTrue(s.name, franchise(status = s).tracksAirings)
        }
    }

    @Test
    fun effectiveStatus_fallsFromTheLibraryRowToTheSubscriptionToPlanned() {
        assertEquals(WatchStatus.WATCHING, franchise(status = WatchStatus.WATCHING).effectiveStatus)
        assertEquals(
            WatchStatus.PAUSED,
            franchise(subscription = Subscription(status = WatchStatus.PAUSED)).effectiveStatus,
        )
        assertEquals(WatchStatus.PLANNED, franchise().effectiveStatus)
        // The library row wins over the subscription.
        assertEquals(
            WatchStatus.WATCHING,
            franchise(
                status = WatchStatus.WATCHING,
                subscription = Subscription(status = WatchStatus.PLANNED),
            ).effectiveStatus,
        )
    }

    // =========================================================================================
    // 3. `progressCeiling` is the season SIZE, and `isUpcoming` keys on status alone
    // =========================================================================================

    /**
     * A 10-episode season sat at **59/10** because a "+1" control had no ceiling and the ring
     * clamped its *visual* at 100 %, so the overrun was invisible.
     */
    @Test
    fun progressCeiling_regression_boundsAPlusOneControlAtTheSeasonSize() {
        assertEquals(10, part(totalEpisodes = 10, airedEpisodes = 10).progressCeiling)
    }

    /**
     * Deliberately the season SIZE, not `availableEpisodes()`: aired counts trail the catalogue by
     * up to an hour, and blocking a legitimate write on stale sync data is worse than letting a
     * keen viewer run a few episodes ahead.
     */
    @Test
    fun progressCeiling_isTheSizeNotWhatHasAired() {
        val p = part(isReleasing = true, totalEpisodes = 24, airedEpisodes = 11)
        assertEquals(24, p.progressCeiling)
        assertEquals(11, p.availableEpisodes())
    }

    /** Unknown size (ongoing AniList shows carry `episodes: null`) stays unbounded, not guessed. */
    @Test
    fun progressCeiling_isUnboundedWhenTheSizeIsUnknown() {
        assertEquals(Int.MAX_VALUE, part(isReleasing = true, totalEpisodes = 0, airedEpisodes = 0).progressCeiling)
    }

    @Test
    fun progressCeiling_isZeroForAnAnnouncedSeason() {
        val announced = part(status = "NOT_YET_RELEASED", totalEpisodes = 12)
        assertEquals(0, announced.progressCeiling)
    }

    /**
     * TMDB publishes an announced season's planned episode count. Under the old
     * `airedEpisodes == 0` test that season masqueraded as released — losing its premiere date and
     * inventing a backlog.
     */
    @Test
    fun isUpcoming_regression_keysOnStatusAloneSoAPlannedEpisodeCountCannotInventABacklog() {
        val announced = part(
            status = "NOT_YET_RELEASED",
            totalEpisodes = 12,             // TMDB advertises the whole season up front
            airedEpisodes = 0,
            nextAiringAt = tmdbSlot(2026, 10, 2),
        )
        assertTrue(announced.isUpcoming)
        assertEquals(0, announced.availableEpisodes())
        assertEquals(tmdbSlot(2026, 10, 2), announced.premiereAt)

        // The same row without the status is a released season with 12 episodes to watch.
        val released = announced.copy(status = "FINISHED")
        assertFalse(released.isUpcoming)
        assertEquals(12, released.availableEpisodes())
        assertNull(released.premiereAt)
    }

    @Test
    fun availableEpisodes_prefersTheAiredCountAndFallsBackToTheTotal() {
        assertEquals(11, part(airedEpisodes = 11, totalEpisodes = 24).availableEpisodes())
        assertEquals(24, part(airedEpisodes = 0, totalEpisodes = 24).availableEpisodes())
        assertEquals(0, part(airedEpisodes = 0, totalEpisodes = 0).availableEpisodes())
    }

    // =========================================================================================
    // 4. `withProgress` must copy EVERY field
    // =========================================================================================

    /**
     * The hand-built copy this replaced dropped `airings`, so one local mark took a show off the
     * calendar until the next reload. `data class.copy()` is what makes that impossible.
     */
    @Test
    fun withProgress_regression_carriesEveryFieldIncludingAirings() {
        val original = part(
            mediaId = 42,
            isReleasing = true,
            totalEpisodes = 24,
            airedEpisodes = 12,
            nextEpisodeNumber = 13,
            nextAiringAt = jst(2026, 9, 11, 18, 30),
            lastAiredAt = jst(2026, 9, 4, 18, 30),
            progress = 11,
            airings = listOf(
                Airing(episode = 12, at = jst(2026, 9, 4, 18, 30)),
                Airing(episode = 13, at = jst(2026, 9, 11, 18, 30)),
            ),
            episodes = listOf(Episode(number = 12), Episode(number = 13)),
        )

        val marked = original.withProgress(12)

        assertEquals(12, marked.progress)
        assertEquals(original.airings, marked.airings)          // the show stays on the calendar
        assertEquals(original.episodes, marked.episodes)
        assertEquals(original.nextAiringAt, marked.nextAiringAt)
        assertEquals(original.lastAiredAt, marked.lastAiredAt)
        assertEquals(original.nextEpisodeNumber, marked.nextEpisodeNumber)
        assertEquals(original.copy(progress = 12), marked)      // literally everything else
    }

    @Test
    fun withProgress_clampsANegativeMarkToZero() {
        assertEquals(0, part(progress = 3).withProgress(-1).progress)
    }

    // =========================================================================================
    // 5. The aired / renderable / mark-target ladder
    // =========================================================================================

    /**
     * A part caught mid-sync can report `airedEpisodes = 0` while its own episode list already
     * carries dates in the past. Trusting that blindly dims every row and collapses `markTarget`
     * onto the user's progress, so a season header renders "watched" purely because there is
     * nothing left to compare against.
     */
    @Test
    fun provenAiredCount_regression_anEpisodeWhoseAirDateHasPassedHasAired() {
        val p = part(
            isReleasing = true,
            airedEpisodes = 0,                          // mid-sync
            episodes = listOf(
                Episode(number = 1, airDate = utcDay(2026, 8, 21)),
                Episode(number = 2, airDate = utcDay(2026, 8, 28)),
                Episode(number = 3, airDate = utcDay(2026, 9, 11)),   // still ahead
            ),
        )
        assertEquals(2, p.provenAiredCount(jst(2026, 9, 4, 12, 0)))
    }

    /**
     * Strictly **BEFORE today**, not "today or earlier": today's slot is the one the catalogue is
     * still counting down to, and swallowing it here would cost the next-to-air row its date badge
     * on every healthy season the moment its drop day arrives.
     */
    @Test
    fun provenAiredCount_regression_aDatedEpisodeMustBeStrictlyBeforeToday() {
        val p = part(
            isReleasing = true,
            airedEpisodes = 0,
            episodes = listOf(Episode(number = 7, airDate = utcDay(2026, 9, 4))),
        )
        // 4 September JST — the episode's own UTC day. Not yet proven.
        assertEquals(0, p.provenAiredCount(jst(2026, 9, 4, 23, 0)))
        assertEquals(7, p.provenAiredCount(jst(2026, 9, 5, 1, 0)))
    }

    /**
     * Without the struck-slot term the mark target trailed the catalogue's count by a sync, so the
     * episode Today had just called "out now" could not be marked.
     */
    @Test
    fun provenAiredCount_regression_admitsASlotThatHasStruck() {
        val p = part(
            isReleasing = true,
            airedEpisodes = 11,
            airings = listOf(Airing(episode = 12, at = jst(2026, 9, 4, 18, 30))),
        )
        assertEquals(12, p.provenAiredCount(jst(2026, 9, 4, 18, 31)))
        assertEquals(12, p.markTarget(jst(2026, 9, 4, 18, 31)))
    }

    /**
     * **The deliberate asymmetry.** `provenAiredCount`'s `struck` term uses the raw `at <= now`
     * with **no anchor**, while `passedAirings` requires `dayDiff < 0` for a date-only source — so
     * `provenAiredCount` is *more permissive* for TMDB: it admits the drop day once the synthesized
     * 17:00 UTC instant has passed, because TMDB's own date has arrived by then. Do not unify them.
     */
    @Test
    fun provenAiredCount_isMorePermissiveThanAiredByNowForADateOnlySource() = withDefaultZone("UTC") {
        val slot = tmdbSlot(2026, 9, 4)                 // 2026-09-04 17:00 UTC
        val p = part(isReleasing = true, airedEpisodes = 4, airings = listOf(Airing(episode = 5, at = slot)))
        val now = slot + 30 * Time.MINUTE_MS            // 17:30 UTC, still 4 September in UTC

        assertEquals(5, p.provenAiredCount(now))                        // raw `at <= now`
        assertEquals(4, p.airedByNow(now, TimeAnchor.UTC_DATE))         // needs the day to turn over
    }

    @Test
    fun provenAiredCount_returnsTheCatalogueCountWhenNotReleasing() {
        val p = part(
            isReleasing = false,
            airedEpisodes = 12,
            episodes = listOf(Episode(number = 24, airDate = utcDay(2020, 1, 1))),
        )
        assertEquals(12, p.provenAiredCount(jst(2026, 9, 4)))
    }

    @Test
    fun renderableEpisodeCount_neverExceedsAKnownTotal() {
        val p = part(isReleasing = true, totalEpisodes = 24, airedEpisodes = 30, progress = 30)
        assertEquals(24, p.renderableEpisodeCount(jst(2026, 9, 4)))
    }

    /**
     * With an unknown total, extend exactly one past what has aired so the next-to-air row can
     * carry its date badge. Row plumbing ONLY — a guess must never be shown as a season length.
     */
    @Test
    fun renderableEpisodeCount_extendsOnePastAiredWhenTheTotalIsUnknown() {
        val p = part(
            isReleasing = true,
            totalEpisodes = 0,
            airedEpisodes = 11,
            nextAiringAt = jst(2026, 9, 11, 18, 30),
        )
        assertEquals(12, p.renderableEpisodeCount(jst(2026, 9, 4)))

        // With nothing dated ahead there is no next-to-air row to draw.
        assertEquals(11, p.copy(nextAiringAt = null).renderableEpisodeCount(jst(2026, 9, 4)))
    }

    @Test
    fun renderableEpisodeCount_neverDrawsFewerRowsThanTheUserHasWatched() {
        val p = part(isReleasing = false, totalEpisodes = 0, airedEpisodes = 0, progress = 7)
        assertEquals(7, p.renderableEpisodeCount(jst(2026, 9, 4)))
    }

    @Test
    fun markTarget_isProvenAiredWhileReleasingAndTheWholeRunOnceFinished() {
        val now = jst(2026, 9, 4, 19, 0)
        val releasing = part(
            isReleasing = true,
            totalEpisodes = 24,
            airedEpisodes = 11,
            airings = listOf(Airing(episode = 12, at = jst(2026, 9, 4, 18, 30))),
        )
        assertEquals(12, releasing.markTarget(now))
        assertEquals(24, releasing.copy(isReleasing = false).markTarget(now))
    }

    @Test
    fun isComplete_comparesProgressAgainstTheMarkTarget() {
        val finished = part(isReleasing = false, totalEpisodes = 12, progress = 12)
        assertTrue(finished.isComplete)
        assertFalse(finished.copy(progress = 11).isComplete)
        // Nothing to compare against is not "complete".
        assertFalse(part(isReleasing = false, totalEpisodes = 0, progress = 0).isComplete)
    }

    // =========================================================================================
    // 6. `scheduleAirings` — the calendar-facts fallback
    // =========================================================================================

    @Test
    fun scheduleAirings_returnsTheServersListUntouchedWhenItHasOne() {
        val list = listOf(Airing(episode = 12, at = jst(2026, 9, 4, 18, 30)))
        assertEquals(list, part(airings = list, nextAiringAt = jst(2026, 9, 11)).scheduleAirings)
    }

    /**
     * Against a modern server this is never reached; it exists so an old deployment shows each
     * weekly show once rather than not at all. Ascending by instant.
     */
    @Test
    fun scheduleAirings_fallsBackToTheTwoLegacySlotsInAscendingOrder() {
        val p = part(
            isReleasing = true,
            airedEpisodes = 11,
            lastAiredAt = jst(2026, 8, 28, 18, 30),
            nextEpisodeNumber = 12,
            nextAiringAt = jst(2026, 9, 4, 18, 30),
        )
        assertEquals(
            listOf(
                Airing(episode = 11, at = jst(2026, 8, 28, 18, 30)),
                Airing(episode = 12, at = jst(2026, 9, 4, 18, 30)),
            ),
            p.scheduleAirings,
        )
    }

    @Test
    fun scheduleAirings_derivesTheNextEpisodeNumberWhenTheServerOmitsIt() {
        val p = part(isReleasing = true, airedEpisodes = 11, nextAiringAt = jst(2026, 9, 4, 18, 30))
        assertEquals(listOf(Airing(episode = 12, at = jst(2026, 9, 4, 18, 30))), p.scheduleAirings)
    }

    @Test
    fun scheduleAirings_neverEmitsTheSameEpisodeTwice() {
        val p = part(
            isReleasing = true,
            airedEpisodes = 11,
            lastAiredAt = jst(2026, 8, 28, 18, 30),
            nextEpisodeNumber = 11,                 // the catalogue disagrees with itself
            nextAiringAt = jst(2026, 9, 4, 18, 30),
        )
        assertEquals(1, p.scheduleAirings.size)
    }

    @Test
    fun scheduleAirings_ignoresZeroTimestamps() {
        val p = part(isReleasing = true, airedEpisodes = 5, lastAiredAt = 0L, nextAiringAt = 0L)
        assertTrue(p.scheduleAirings.isEmpty())
    }

    // =========================================================================================
    // 7. `resumePart` and `continueBacklog`
    // =========================================================================================

    @Test
    fun resumePart_prefersThePartTheUserIsMidWayThrough() {
        val f = franchise(
            parts = listOf(
                part(mediaId = 1, sequence = 1, totalEpisodes = 12, airedEpisodes = 12, progress = 12),
                part(mediaId = 2, sequence = 2, totalEpisodes = 12, airedEpisodes = 12, progress = 5),
                part(mediaId = 3, sequence = 3, totalEpisodes = 12, airedEpisodes = 12, progress = 0),
            ),
        )
        assertEquals(2, f.resumePart?.mediaId)
        assertEquals(7, f.continueBacklog)
    }

    /**
     * **Picking by sequence, not by largest backlog, is the point:** a `max()` would resume S3 at
     * 3/10 into an untouched S5 just because S5 is longer.
     */
    @Test
    fun resumePart_regression_picksBySequenceNotByLargestBacklog() {
        val f = franchise(
            parts = listOf(
                part(mediaId = 3, sequence = 3, totalEpisodes = 10, airedEpisodes = 10, progress = 3),
                part(mediaId = 5, sequence = 5, totalEpisodes = 25, airedEpisodes = 25, progress = 0),
            ),
        )
        assertEquals(3, f.resumePart?.mediaId)
    }

    /**
     * With non-sequential progress (S2 untouched, S3 half-watched) the mid-watch part still wins —
     * resuming what you're actively watching beats sending you back to a season you skipped.
     */
    @Test
    fun resumePart_midWatchBeatsASkippedEarlierSeason() {
        val f = franchise(
            parts = listOf(
                part(mediaId = 2, sequence = 2, totalEpisodes = 12, airedEpisodes = 12, progress = 0),
                part(mediaId = 3, sequence = 3, totalEpisodes = 12, airedEpisodes = 12, progress = 6),
            ),
        )
        assertEquals(3, f.resumePart?.mediaId)
    }

    @Test
    fun resumePart_takesTheFirstUnstartedPartAfterTheHighestCompletedOne() {
        val f = franchise(
            parts = listOf(
                part(mediaId = 1, sequence = 1, totalEpisodes = 12, airedEpisodes = 12, progress = 12),
                part(mediaId = 2, sequence = 2, totalEpisodes = 12, airedEpisodes = 12, progress = 12),
                part(mediaId = 3, sequence = 3, totalEpisodes = 12, airedEpisodes = 12, progress = 0),
            ),
        )
        assertEquals(3, f.resumePart?.mediaId)
    }

    /**
     * Step 2 must FALL THROUGH to step 3, not return null: a completed part exists but nothing
     * later qualifies, and there is still an earlier season with everything left on it.
     */
    @Test
    fun resumePart_fallsThroughToTheEarliestPartWithAnythingLeft() {
        val f = franchise(
            parts = listOf(
                part(mediaId = 1, sequence = 1, totalEpisodes = 12, airedEpisodes = 12, progress = 0),
                part(mediaId = 2, sequence = 2, totalEpisodes = 12, airedEpisodes = 12, progress = 12),
            ),
        )
        assertEquals(1, f.resumePart?.mediaId)
    }

    @Test
    fun resumePart_isNullWhenThereIsNoBacklogAnywhere() {
        val f = franchise(
            parts = listOf(part(mediaId = 1, totalEpisodes = 12, airedEpisodes = 12, progress = 12)),
        )
        assertNull(f.resumePart)
        assertEquals(0, f.continueBacklog)
    }

    @Test
    fun resumePart_ignoresAnAnnouncedSeasonBecauseItHasNothingToWatch() {
        val f = franchise(
            parts = listOf(
                part(mediaId = 1, sequence = 1, totalEpisodes = 12, airedEpisodes = 12, progress = 12),
                part(mediaId = 2, sequence = 2, status = "NOT_YET_RELEASED", totalEpisodes = 12),
            ),
        )
        assertNull(f.resumePart)
    }

    @Test
    fun episodicPartsInOrder_isTheSpineOnlyAndSortedBySequence() {
        val f = franchise(
            parts = listOf(
                part(mediaId = 4, kind = PartKind.MOVIE, sequence = 1),
                part(mediaId = 5, kind = PartKind.SPECIAL, sequence = 1),
                part(mediaId = 6, kind = PartKind.MUSIC, sequence = 1),
                part(mediaId = 2, kind = PartKind.OVA, sequence = 2),
                part(mediaId = 1, kind = PartKind.SEASON, sequence = 1),
                part(mediaId = 3, kind = PartKind.ONA, sequence = 3),
            ),
        )
        assertEquals(listOf(1, 2, 3), f.episodicPartsInOrder.map { it.mediaId })
    }

    // =========================================================================================
    // 8. `releasingPart` and the centralised sort-key sentinels
    // =========================================================================================

    @Test
    fun releasingPart_prefersTheSoonestNextAiring() {
        val f = franchise(
            parts = listOf(
                part(mediaId = 1, isReleasing = true, nextAiringAt = jst(2026, 9, 18, 18, 30)),
                part(mediaId = 2, isReleasing = true, nextAiringAt = jst(2026, 9, 5, 18, 30)),
                part(mediaId = 3, isReleasing = false, nextAiringAt = jst(2026, 9, 1, 18, 30)),
            ),
        )
        assertEquals(2, f.releasingPart?.mediaId)
    }

    @Test
    fun releasingPart_fallsBackToTheMostRecentlyAired() {
        val f = franchise(
            parts = listOf(
                part(mediaId = 1, isReleasing = true, lastAiredAt = jst(2026, 8, 1, 18, 30)),
                part(mediaId = 2, isReleasing = true, lastAiredAt = jst(2026, 9, 1, 18, 30)),
            ),
        )
        assertEquals(2, f.releasingPart?.mediaId)
    }

    @Test
    fun releasingPart_isNullWhenNothingIsReleasing() {
        assertNull(franchise(parts = listOf(part(isReleasing = false))).releasingPart)
    }

    /** Reuse these rather than re-inlining a `?: Long.MAX_VALUE` / `?: 0` sentinel at a call site. */
    @Test
    fun sortKeys_carryTheSentinelsSoNoScreenReInlinesThem() {
        val none = franchise()
        assertEquals(Long.MAX_VALUE, none.nextAiringSortKey)
        assertEquals(0L, none.lastAiredSortKey)

        val live = franchise(
            parts = listOf(
                part(
                    isReleasing = true,
                    nextAiringAt = jst(2026, 9, 11, 18, 30),
                    lastAiredAt = jst(2026, 9, 4, 18, 30),
                ),
            ),
        )
        assertEquals(jst(2026, 9, 11, 18, 30), live.nextAiringSortKey)
        assertEquals(jst(2026, 9, 4, 18, 30), live.lastAiredSortKey)
    }

    /**
     * `lastAiredSortKey` is the CATALOGUE'S field on purpose — fine for the Library's calm shelves,
     * wrong for anything live, where a days-old drop would take the hero from tonight's episode.
     */
    @Test
    fun lastAiredSortKey_isTheRawFieldWhileLastAiredIsTheLiveOne() {
        val f = franchise(
            parts = listOf(
                part(
                    isReleasing = true,
                    lastAiredAt = jst(2026, 8, 28, 18, 30),
                    airings = listOf(Airing(episode = 12, at = jst(2026, 9, 4, 18, 30))),
                ),
            ),
        )
        assertEquals(jst(2026, 8, 28, 18, 30), f.lastAiredSortKey)
        assertEquals(jst(2026, 9, 4, 18, 30), f.lastAired(jst(2026, 9, 4, 19, 0)))
    }

    // =========================================================================================
    // 9. `sections`
    // =========================================================================================

    @Test
    fun sections_listSeasonsNewestFirstAndEveryOtherKindChronologically() {
        val f = franchise(
            parts = listOf(
                part(mediaId = 1, kind = PartKind.SEASON, sequence = 1),
                part(mediaId = 2, kind = PartKind.SEASON, sequence = 2),
                part(mediaId = 3, kind = PartKind.SEASON, sequence = 3),
                part(mediaId = 10, kind = PartKind.MOVIE, sequence = 2),
                part(mediaId = 11, kind = PartKind.MOVIE, sequence = 1),
            ),
        )
        val seasons = f.sections.first { it.kind == PartKind.SEASON }
        val movies = f.sections.first { it.kind == PartKind.MOVIE }

        assertEquals(listOf(3, 2, 1), seasons.parts.map { it.mediaId })
        assertEquals(listOf(11, 10), movies.parts.map { it.mediaId })
    }

    @Test
    fun sections_areOrderedBySortRankRegardlessOfPartOrder() {
        val f = franchise(
            parts = listOf(
                part(mediaId = 1, kind = PartKind.MUSIC),
                part(mediaId = 2, kind = PartKind.SPECIAL),
                part(mediaId = 3, kind = PartKind.MOVIE),
                part(mediaId = 4, kind = PartKind.SEASON),
            ),
        )
        assertEquals(
            listOf(PartKind.SEASON, PartKind.MOVIE, PartKind.SPECIAL, PartKind.MUSIC),
            f.sections.map { it.kind },
        )
    }

    // =========================================================================================
    // 10. `grafting` — the detail read onto the live library copy
    // =========================================================================================

    @Test
    fun grafting_isANoOpForADifferentShow() {
        val library = franchise(id = "a", parts = listOf(part(mediaId = 1, progress = 5)))
        val other = franchise(id = "b", parts = listOf(part(mediaId = 1, progress = 0)))
        assertSame(library, library.grafting(other))
    }

    /**
     * The library payload carries the enrichment too, but it was read at launch — before the
     * server's stale-while-revalidate pass may have run — so a detail read that came back richer
     * wins, field by field. The user's progress never does.
     */
    @Test
    fun grafting_keepsTheLibrarysProgressAndTakesTheDetailsEpisodes() {
        val library = franchise(
            parts = listOf(part(mediaId = 1, progress = 11, airings = listOf(Airing(episode = 12, at = 1L)))),
            status = WatchStatus.WATCHING,
        )
        val detail = franchise(
            parts = listOf(
                part(
                    mediaId = 1,
                    progress = 0,                                   // the detail read has no user data
                    episodes = listOf(Episode(number = 1), Episode(number = 2)),
                ),
            ),
        )

        val merged = library.grafting(detail)

        assertEquals(11, merged.parts[0].progress)
        assertEquals(2, merged.parts[0].episodes.size)
        assertEquals(1, merged.parts[0].airings.size)               // the library's calendar survives
        assertEquals(WatchStatus.WATCHING, merged.status)
    }

    @Test
    fun grafting_dropsAPartTheLibraryCopyDoesNotKnowAbout() {
        val library = franchise(parts = listOf(part(mediaId = 1)))
        val detail = franchise(parts = listOf(part(mediaId = 1), part(mediaId = 2)))
        assertEquals(listOf(1), library.grafting(detail).parts.map { it.mediaId })
    }

    @Test
    fun grafting_firstWinsForADuplicateMediaIdInTheDetailRead() {
        val library = franchise(parts = listOf(part(mediaId = 1)))
        val detail = franchise(
            parts = listOf(
                part(mediaId = 1, episodes = listOf(Episode(number = 1))),
                part(mediaId = 1, episodes = listOf(Episode(number = 1), Episode(number = 2))),
            ),
        )
        assertEquals(1, library.grafting(detail).parts[0].episodes.size)
    }

    @Test
    fun grafting_alwaysTakesTheMarketMatchedAudienceAndTheFresherContinueWatching() {
        val libraryAudience = AudienceInfo(contentRating = ContentRating(country = "US", rating = "TV-14"))
        val detailAudience = AudienceInfo(contentRating = ContentRating(country = "IN", rating = "U/A 16+"))
        val library = franchise(
            audience = libraryAudience,
            continueWatching = ContinueWatching(mediaId = 1, partLabel = "Season 1", episode = Episode(number = 3)),
        )
        val detail = franchise(
            audience = detailAudience,
            continueWatching = ContinueWatching(mediaId = 1, partLabel = "Season 4", episode = Episode(number = 12)),
        )

        val merged = library.grafting(detail)

        assertEquals(detailAudience, merged.audience)
        assertEquals(12, merged.continueWatching?.episode?.number)
    }

    @Test
    fun grafting_keepsTheLibrarysEnrichmentWhenItAlreadyHasSome() {
        val library = franchise(themes = listOf("Time loop"), images = ArtworkSet(portrait = "lib.jpg"))
        val detail = franchise(themes = listOf("Isekai"), images = ArtworkSet(portrait = "detail.jpg"))
        val merged = library.grafting(detail)

        assertEquals(listOf("Time loop"), merged.themes)
        assertEquals("lib.jpg", merged.images?.portrait)
    }

    @Test
    fun grafting_takesTheDetailsEnrichmentWhenTheLibraryCopyHasNone() {
        val library = franchise()
        val detail = franchise(themes = listOf("Isekai"), images = ArtworkSet(portrait = "detail.jpg"))
        val merged = library.grafting(detail)

        assertEquals(listOf("Isekai"), merged.themes)
        assertEquals("detail.jpg", merged.images?.portrait)
    }

    @Test
    fun grafting_doesNotAllocateAPartCopyWhenNothingChanged() {
        val p = part(mediaId = 1, episodes = listOf(Episode(number = 1)))
        val library = franchise(parts = listOf(p))
        val detail = franchise(parts = listOf(p))
        assertSame(p, library.grafting(detail).parts[0])
    }

    // =========================================================================================
    // 11. `FranchiseUpcoming` — the curated note goes stale
    // =========================================================================================

    /**
     * The curated note's `checked` date is weeks old, so a day-dated release that has passed is no
     * longer a fact. **Mushoku Tensei sat under the Library's Returning shelf reading "Returns
     * today" two months into its third season.**
     */
    @Test
    fun hasArrived_regression_aDayDatedReleaseThatIsBehindUsIsNoLongerAFact() {
        val note = FranchiseUpcoming(
            status = "upcoming_dated",
            next = "Season 3",
            release = "2026-07-05",
            releaseWindow = ReleaseWindow(
                date = "2026-07-05",
                precision = ReleaseWindow.Precision.DAY,
                sortKey = 20260705,
            ),
        )
        assertTrue(note.hasArrived(jst(2026, 9, 4)))
        assertFalse(note.hasArrived(jst(2026, 7, 1)))
    }

    @Test
    fun hasArrived_isFalseOnTheDayItself() {
        val note = FranchiseUpcoming(
            status = "upcoming_dated",
            releaseWindow = ReleaseWindow(
                date = "2026-09-04",
                precision = ReleaseWindow.Precision.DAY,
                sortKey = 20260904,
            ),
        )
        // "Returns today" is still true on the day.
        assertFalse(note.hasArrived(jst(2026, 9, 4, 23, 0)))
        assertTrue(note.hasArrived(jst(2026, 9, 5, 1, 0)))
    }

    /** A month-precision window has no day to have passed, so it is never "arrived". */
    @Test
    fun hasArrived_isFalseForEveryWindowCoarserThanADay() {
        for (precision in listOf(
            ReleaseWindow.Precision.MONTH,
            ReleaseWindow.Precision.QUARTER,
            ReleaseWindow.Precision.YEAR,
            ReleaseWindow.Precision.UNKNOWN,
        )) {
            val note = FranchiseUpcoming(
                status = "announced",
                releaseWindow = ReleaseWindow(date = "2020-01-01", precision = precision, sortKey = 20200101),
            )
            assertFalse(precision.name, note.hasArrived(jst(2026, 9, 4)))
        }
    }

    @Test
    fun hasArrived_isFalseForANoteThatIsNotAFutureInstallment() {
        val note = FranchiseUpcoming(
            status = "concluded",
            releaseWindow = ReleaseWindow(
                date = "2020-01-01",
                precision = ReleaseWindow.Precision.DAY,
                sortKey = 20200101,
            ),
        )
        assertFalse(note.hasArrived(jst(2026, 9, 4)))
    }

    /** A `yyyymmdd` key that is not a real calendar date has not "arrived"; it must not throw. */
    @Test
    fun hasArrived_isFalseForAnImpossibleKeyRatherThanThrowing() {
        val note = FranchiseUpcoming(
            status = "upcoming_dated",
            releaseWindow = ReleaseWindow(
                precision = ReleaseWindow.Precision.DAY,
                sortKey = 20260230,          // 30 February
            ),
        )
        assertFalse(note.hasArrived(jst(2026, 9, 4)))
    }

    /**
     * This used to parse `release` here, and only its ISO forms, which filed "October 2026" and
     * "Summer 2027" under January of their year: a shelf sorted "soonest first" put October 2026
     * ahead of an August 2026 premiere while its own caption read "Returns Oct 2026".
     */
    @Test
    fun releaseSortKey_regression_isTheServersOrderAndBreaksTiesByPrecision() {
        fun key(p: ReleaseWindow.Precision, sortKey: Int) = FranchiseUpcoming(
            status = "announced",
            releaseWindow = ReleaseWindow(precision = p, sortKey = sortKey),
        ).releaseSortKey

        assertEquals(ReleaseSortKey(20260805, ReleaseSortKey.DAY), key(ReleaseWindow.Precision.DAY, 20260805))
        assertEquals(ReleaseSortKey(20261001, ReleaseSortKey.MONTH), key(ReleaseWindow.Precision.MONTH, 20261001))
        assertEquals(ReleaseSortKey(20270701, ReleaseSortKey.MONTH), key(ReleaseWindow.Precision.QUARTER, 20270701))
        assertEquals(ReleaseSortKey(20260901, ReleaseSortKey.YEAR), key(ReleaseWindow.Precision.YEAR, 20260901))

        // An August premiere sorts ahead of an October window, which is the bug this key fixed.
        val august = key(ReleaseWindow.Precision.DAY, 20260805)!!
        val october = key(ReleaseWindow.Precision.MONTH, 20261001)!!
        assertTrue(august < october)

        // A concrete month sorts ahead of a bare year on the same value.
        assertTrue(key(ReleaseWindow.Precision.MONTH, 20260901)!! > key(ReleaseWindow.Precision.YEAR, 20260901)!!)
    }

    /** TBA, prose with no date, **and every rumor** resolve to `unknown` and must sort last. */
    @Test
    fun releaseSortKey_isNullForAnUnknownWindowSoItSortsLastNotAsZero() {
        val unknown = FranchiseUpcoming(
            status = "rumored",
            release = "TBA",
            releaseWindow = ReleaseWindow(precision = ReleaseWindow.Precision.UNKNOWN, sortKey = 20260101),
        )
        assertNull(unknown.releaseSortKey)
        assertNull(FranchiseUpcoming(status = "announced").releaseSortKey)

        val sorted = listOf(
            "b" to null,
            "a" to ReleaseSortKey(20261001, ReleaseSortKey.MONTH),
        ).sortedBy { it.second ?: ReleaseSortKey.LAST }
        assertEquals(listOf("a", "b"), sorted.map { it.first })
    }

    @Test
    fun isFutureInstallment_coversTheFourForwardLookingStatuses() {
        for (s in listOf("upcoming_dated", "announced", "announced_no_date", "rumored")) {
            assertTrue(s, FranchiseUpcoming(status = s).isFutureInstallment)
        }
        for (s in listOf("airing", "recently_aired", "concluded", null, "something_new")) {
            assertFalse(s ?: "null", FranchiseUpcoming(status = s).isFutureInstallment)
        }
    }

    @Test
    fun upcomingStatus_isAnOpenStringSoAnUnseenValueDegradesRatherThanFailing() {
        assertEquals("Upcoming", FranchiseUpcoming(status = "some_future_status").tag)
        assertEquals("Rumored", FranchiseUpcoming(status = "rumored").tag)
        assertTrue(FranchiseUpcoming(status = "rumored").isRumored)
        assertTrue(FranchiseUpcoming(status = "concluded").isConcluded)
    }

    @Test
    fun displayRelease_isEmptyWhenTheNoteStatesNoReleaseAtAll() {
        assertEquals("", FranchiseUpcoming(status = "announced").displayRelease)
        assertEquals("", FranchiseUpcoming(status = "announced", release = "   ").displayRelease)
    }

    // =========================================================================================
    // 12. The shelf ladder
    // =========================================================================================

    /**
     * The top shelf must react to the airings, not the hourly cron: the show that had just aired is
     * exactly the show that must be at the top, and a count-based ladder filed it as dormant.
     */
    @Test
    fun shelfState_regression_newEpisodeUsesAiringsDerivedFreshness() {
        val now = jst(2026, 9, 4, 19, 0)
        val f = franchise(
            status = WatchStatus.WATCHING,
            parts = listOf(
                part(
                    isReleasing = true,
                    totalEpisodes = 24,
                    airedEpisodes = 11,            // the cron has not caught up
                    progress = 11,
                    lastAiredAt = jst(2026, 8, 28, 18, 30),
                    airings = listOf(Airing(episode = 12, at = jst(2026, 9, 4, 18, 30))),
                ),
            ),
        )
        assertEquals(ShelfState.NEW_EPISODE, f.shelfState(now))
    }

    @Test
    fun shelfState_newEpisodeExpiresAfterTheOutNowWindow() {
        val now = jst(2026, 9, 4, 19, 0)
        val stale = franchise(
            status = WatchStatus.WATCHING,
            parts = listOf(
                part(
                    isReleasing = true,
                    totalEpisodes = 24,
                    airedEpisodes = 12,
                    progress = 11,
                    lastAiredAt = now - ShelfWindows.OUT_NOW - Time.DAY_MS,
                ),
            ),
        )
        // Still behind, but the drop is older than a week — it is a backlog, not news.
        assertEquals(ShelfState.BACKLOG, stale.shelfState(now))
    }

    @Test
    fun shelfState_airingWaitNeedsToBeCaughtUpAndDated() {
        val now = jst(2026, 9, 5, 12, 0)
        val f = franchise(
            status = WatchStatus.WATCHING,
            parts = listOf(
                part(
                    isReleasing = true,
                    totalEpisodes = 24,
                    airedEpisodes = 11,
                    progress = 11,
                    airings = listOf(Airing(episode = 12, at = jst(2026, 9, 11, 18, 30))),
                ),
            ),
        )
        assertEquals(ShelfState.AIRING_WAIT, f.shelfState(now))
    }

    @Test
    fun shelfState_premiereSoonOnlyInsideItsWindow() {
        val now = jst(2026, 9, 4, 12, 0)
        fun withPremiere(at: Long) = franchise(
            status = WatchStatus.COMPLETED,
            parts = listOf(
                part(mediaId = 1, sequence = 1, totalEpisodes = 12, airedEpisodes = 12, progress = 12),
                part(mediaId = 2, sequence = 2, status = "NOT_YET_RELEASED", nextAiringAt = at),
            ),
        )
        assertEquals(ShelfState.PREMIERE_SOON, withPremiere(now + 10 * Time.DAY_MS).shelfState(now))
        assertNull(withPremiere(now + 60 * Time.DAY_MS).shelfState(now))
    }

    @Test
    fun shelfState_isNullForADormantShow() {
        val f = franchise(
            status = WatchStatus.COMPLETED,
            parts = listOf(part(totalEpisodes = 12, airedEpisodes = 12, progress = 12)),
        )
        assertNull(f.shelfState(jst(2026, 9, 4)))
    }

    /** The declaration order IS the shelf sort order. */
    @Test
    fun shelfState_orderIsTheLadder() {
        assertEquals(
            listOf(0, 1, 2, 3),
            listOf(
                ShelfState.NEW_EPISODE,
                ShelfState.BACKLOG,
                ShelfState.AIRING_WAIT,
                ShelfState.PREMIERE_SOON,
            ).map { it.order },
        )
        assertEquals(ShelfState.entries.map { it.ordinal }, ShelfState.entries.map { it.order })
    }

    @Test
    fun shelfWindows_carryTheDocumentedValues() {
        assertEquals(172_800_000L, ShelfWindows.SOON)
        assertEquals(604_800_000L, ShelfWindows.OUT_NOW)
        assertEquals(86_400_000L, ShelfWindows.NOW_BAR_LIVE)
        assertEquals(45L * Time.DAY_MS, ShelfWindows.PREMIERE_SHELF)
    }

    @Test
    fun nextPremiere_isTheSoonestAnnouncedPartStillAhead() {
        val now = jst(2026, 9, 4, 12, 0)
        val f = franchise(
            parts = listOf(
                part(mediaId = 1, status = "NOT_YET_RELEASED", nextAiringAt = now + 30 * Time.DAY_MS),
                part(mediaId = 2, status = "NOT_YET_RELEASED", nextAiringAt = now + 10 * Time.DAY_MS),
                part(mediaId = 3, status = "NOT_YET_RELEASED", nextAiringAt = now - Time.DAY_MS),
                part(mediaId = 4, status = "FINISHED", nextAiringAt = now + Time.DAY_MS),
            ),
        )
        assertEquals(now + 10 * Time.DAY_MS, f.nextPremiere(now))
    }

    // =========================================================================================
    // 13. Title normalisation
    // =========================================================================================

    @Test
    fun shelfShortened_stripsATrailingSubtitleWrapper() {
        assertEquals("Re:ZERO", "Re:ZERO -Starting Life in Another World-".shelfShortened)
    }

    @Test
    fun shelfShortened_cutsAtTheFirstSpaceHyphenNotTheLast() {
        assertEquals("Alpha", "Alpha -Beta- -Gamma-".shelfShortened)
    }

    @Test
    fun shelfShortened_onlyUnwrapsWhenTheTitleActuallyEndsInAHyphen() {
        assertEquals("Alpha -Beta", "Alpha -Beta".shelfShortened)
    }

    /** A line that opens on a hyphen reads as a hyphenation bug, not as a title. */
    @Test
    fun shelfShortened_trimsSubtitlePunctuationFromBothEnds() {
        assertEquals("Attack on Titan", "- Attack on Titan:".shelfShortened)
        assertEquals("Attack on Titan", "— Attack on Titan –".shelfShortened)
    }

    @Test
    fun shelfShortened_leavesAShortTitleAlone() {
        assertEquals(
            "Mobile Suit Gundam: The Witch",
            "Mobile Suit Gundam: The Witch".shelfShortened,
        )
    }

    /** A long "Title: Subtitle" keeps its identity half rather than an ellipsis mid-word. */
    @Test
    fun shelfShortened_keepsTheIdentityHalfOfALongTitle() {
        assertEquals(
            "Mobile Suit Gundam",
            "Mobile Suit Gundam: The Witch from Mercury Season Two Special".shelfShortened,
        )
    }

    /**
     * A separator found earlier than 12 graphemes does **not** return — the loop moves on to the
     * next separator, so "Re: …" is never cut down to "Re".
     */
    @Test
    fun shelfShortened_skipsASeparatorFoundBeforeTwelveGraphemes() {
        assertEquals(
            "Re: Zero kara Hajimeru Isekai Seikatsu",
            "Re: Zero kara Hajimeru Isekai Seikatsu - Directors Cut".shelfShortened,
        )
    }

    /**
     * Swift counts **grapheme clusters**; Kotlin's `String.length` counts UTF-16 units. A title of
     * 32 clusters but 44 UTF-16 units must not cross the 40 gate.
     */
    @Test
    fun shelfShortened_countsGraphemeClustersNotUtf16Units() {
        val title = "Mobile Suit Gundam: " + "🎬".repeat(12)
        assertTrue(title.length > 40)                       // 44 UTF-16 units
        assertEquals(title, title.shelfShortened)           // 32 grapheme clusters — under the gate
    }

    /** The `>= 12` threshold is a grapheme distance too, not a UTF-16 offset. */
    @Test
    fun shelfShortened_measuresTheTwelveGraphemeGateInClusters() {
        val title = "🎬".repeat(8) + ": The Second Season of a Very Long Show"
        assertTrue(title.length > 40)
        // 8 clusters (16 UTF-16 units) before the colon — under the gate, so no cut is made.
        assertEquals(title, title.shelfShortened)
    }

    @Test
    fun displayTitle_isTheShelfShortenedTitle() {
        val f = franchise(title = "Re:ZERO -Starting Life in Another World-")
        assertEquals("Re:ZERO", f.displayTitle)
        // The raw title survives for Search and accessibility.
        assertEquals("Re:ZERO -Starting Life in Another World-", f.title)
    }

    // =========================================================================================
    // 14. Labels, completion, snapshots and enrichment
    // =========================================================================================

    /**
     * `sequence` counts a franchise's members, which is not the number the world uses for a season:
     * rendering "S5" beside a label reading "Season 4" was a P0. Unknown says unknown — a fabricated
     * "Season 1" is worse than nothing.
     */
    @Test
    fun canonicalLabel_isTheSourcesOwnWordsAndNeverDerivedFromSequence() {
        assertEquals("Season 4", part(sequence = 5, label = "  Season 4  ").canonicalLabel)
        assertEquals("", part(sequence = 5, label = "").canonicalLabel)
    }

    @Test
    fun watchContext_forAMovieIsJustItsLabel() {
        val movie = part(mediaId = 9, kind = PartKind.MOVIE, label = "The Movie")
        val f = franchise(parts = listOf(part(mediaId = 1), movie))
        assertEquals("The Movie", f.watchContext(movie, 1))
        assertEquals("The Movie", movie.watchContext(1))
    }

    @Test
    fun isSeriesComplete_needsEveryMemberDoneAndNothingAnnounced() {
        val done = part(totalEpisodes = 12, progress = 12)
        assertTrue(franchise(parts = listOf(done)).isSeriesComplete)

        assertFalse(franchise(parts = listOf(done, part(mediaId = 2, isReleasing = true))).isSeriesComplete)
        assertFalse(
            franchise(parts = listOf(done, part(mediaId = 2, status = "NOT_YET_RELEASED"))).isSeriesComplete,
        )
        assertFalse(
            franchise(
                parts = listOf(done),
                upcoming = FranchiseUpcoming(status = "announced"),
            ).isSeriesComplete,
        )
        // Nothing episodic at all is not a complete series.
        assertFalse(franchise(parts = listOf(part(kind = PartKind.MOVIE, progress = 1))).isSeriesComplete)
    }

    @Test
    fun currentPart_prefersTheReleasingPartThenTheResumePart() {
        val releasing = part(mediaId = 2, sequence = 2, isReleasing = true, airedEpisodes = 3)
        val f = franchise(
            parts = listOf(part(mediaId = 1, sequence = 1, totalEpisodes = 12, progress = 4), releasing),
        )
        assertEquals(2, f.currentPart?.mediaId)
        assertEquals(1, franchise(parts = f.parts.filter { !it.isReleasing }).currentPart?.mediaId)
    }

    @Test
    fun canonicalPartLabel_answersEmptyForAnUnknownMediaId() {
        val f = franchise(parts = listOf(part(mediaId = 7, label = "Final Season")))
        assertEquals("Final Season", f.canonicalPartLabel(7))
        assertEquals("", f.canonicalPartLabel(8))
    }

    /**
     * The whole show — parts, progress and status — frozen at the instant of the removal, which is
     * what lets Undo restore before any network round-trip. It only holds because every model in
     * the graph is an immutable `data class`.
     */
    @Test
    fun snapshotForUndo_freezesTheWholeGraph() {
        val original = franchise(parts = listOf(part(progress = 11)), status = WatchStatus.WATCHING)
        val snapshot = original.snapshotForUndo
        val afterMark = original.copy(parts = listOf(original.parts[0].withProgress(12)))

        assertEquals(11, snapshot.parts[0].progress)
        assertEquals(12, afterMark.parts[0].progress)
    }

    /**
     * True while the server's background enrichment has not reached this row. Ignores `themes` and
     * each part's `videos` on purpose — those are cheap and arrive earlier.
     */
    @Test
    fun looksUnenriched_isTrueUntilThePeopleRelatedOrVideosArrive() {
        assertTrue(franchise().looksUnenriched)
        assertTrue(franchise(themes = listOf("Isekai")).looksUnenriched)
        assertFalse(franchise(related = listOf(RelatedTitle(title = "Sequel"))).looksUnenriched)
        assertFalse(
            franchise(people = FranchisePeople(directors = listOf(CatalogPerson(name = "A Director"))))
                .looksUnenriched,
        )
    }

    /** A fact printed twice on one screen is a defect. */
    @Test
    fun themesBeyondGenres_dropsAnythingTheGenresAlreadySay() {
        val f = franchise(
            genres = listOf("Action"),
            themes = listOf("action", "Time loop"),
            parts = listOf(part(genres = listOf("Drama"))),
        )
        assertEquals(listOf("Time loop"), f.themesBeyondGenres)
        assertEquals(
            listOf("Time loop"),
            f.copy(themes = listOf("drama", "Time loop")).themesBeyondGenres,
        )
    }

    /**
     * The server does not substitute another country's rating, so a miss is `nil`, never "US".
     */
    @Test
    fun contentRatingLabel_isTheMarketsOwnWordAndNothingWhenTheCatalogueIsSilent() {
        val rated = franchise(
            audience = AudienceInfo(contentRating = ContentRating(country = "IN", rating = "U/A 16+")),
        )
        assertEquals("U/A 16+", rated.contentRatingLabel)
        assertNull(franchise().contentRatingLabel)
        assertNull(franchise(audience = AudienceInfo(isAdult = false)).contentRatingLabel)
    }
}
