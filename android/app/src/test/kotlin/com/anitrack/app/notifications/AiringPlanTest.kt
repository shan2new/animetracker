package com.anitrack.app.notifications

import com.anitrack.model.Airing
import com.anitrack.model.Franchise
import com.anitrack.model.FranchisePart
import com.anitrack.model.MediaSource
import com.anitrack.model.Time
import com.anitrack.model.WatchStatus
import com.anitrack.model.tracksAirings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The two halves of the airing schedule that have no UI and therefore no other way of being seen:
 * **which alerts the plan holds** (`EpisodeNotifications.buildPlan`) and **which alarms that plan
 * wants armed** ([armTargets]).
 *
 * Three properties are load-bearing and none is visible in a type signature.
 *
 * * **Round-robin.** Every show keeps its soonest episode before any show gets its second. iOS needs
 *   it because the platform caps an app at 64 pending notification requests; Android has no such
 *   cap, and the property is kept anyway so both ports fire the same alerts. It is only observable
 *   once the plan truncates — which is exactly when it matters.
 * * **The gate.** `watching` AND AniList: harder than `tracksAirings`, because an alert interrupts
 *   you, and because a TMDB air date is a DATE the server synthesizes at 17:00 UTC, so a
 *   minute-precise "out now" fired off it would be fiction.
 * * **One alarm per air-time minute, ≤ 8 of them, and never before the episode.** The bucket key is
 *   floor-rounded because `AiringReceiver` matches on it; the alarm FIRES at the latest instant in
 *   the bucket, because "Episode 12 is out now" said before it is out is the one failure this
 *   feature cannot afford.
 */
class AiringPlanTest {

    private companion object {
        /**
         * A fixed wall clock, **minute-aligned on purpose** — every fixture instant is a whole
         * number of hours from it, so [airingBucket] is the identity on them and the one test that
         * cares about ragged instants states its own.
         */
        const val NOW: Long = 1_779_999_960_000L

        fun hours(n: Long): Long = NOW + n * Time.HOUR_MS
    }

    // -----------------------------------------------------------------------------------------
    // Fixtures
    // -----------------------------------------------------------------------------------------

    private fun show(
        id: String,
        mediaId: Int,
        slots: List<Pair<Int, Long>>,
        source: MediaSource = MediaSource.ANILIST,
        status: WatchStatus? = WatchStatus.WATCHING,
        title: String = "Show $id",
        airedEpisodes: Int = 0,
        nextEpisodeNumber: Int? = null,
        nextAiringAt: Long? = null,
        lastAiredAt: Long? = null,
    ) = Franchise(
        id = id,
        source = source,
        title = title,
        status = status,
        parts = listOf(
            FranchisePart(
                mediaId = mediaId,
                label = "Season 1",
                title = title,
                isReleasing = true,
                airedEpisodes = airedEpisodes,
                nextEpisodeNumber = nextEpisodeNumber,
                nextAiringAt = nextAiringAt,
                lastAiredAt = lastAiredAt,
                airings = slots.map { (episode, at) -> Airing(episode = episode, at = at) },
            ),
        ),
    )

    /** Three weekly slots starting `firstHours` from now, an hour apart. */
    private fun weekly(id: String, mediaId: Int, firstHours: Long) = show(
        id = id,
        mediaId = mediaId,
        slots = listOf(
            1 to hours(firstHours),
            2 to hours(firstHours + 1),
            3 to hours(firstHours + 2),
        ),
    )

    private fun alert(id: String, mediaId: Int, episode: Int, at: Long) = PlannedAiring(
        atMillis = at,
        franchiseId = id,
        title = "Show $id",
        mediaId = mediaId,
        episode = episode,
    )

    private fun plan(vararg airings: PlannedAiring) =
        AiringPlan(builtAt = NOW, airings = airings.toList())

    // =========================================================================================
    // 1. The plan — round-robin
    // =========================================================================================

    @Test
    fun `every show's soonest alert precedes any show's second`() {
        // A, B and C are early and clustered; D is late. A global time sort would put A's SECOND and
        // THIRD episodes ahead of D's first — which is the starvation this ordering exists to stop.
        val library = listOf(
            weekly("a", 1, firstHours = 1),
            weekly("b", 2, firstHours = 2),
            weekly("c", 3, firstHours = 3),
            weekly("d", 4, firstHours = 20),
        )

        val airings = EpisodeNotifications.buildPlan(library, NOW).airings

        val firstIndexOf = HashMap<String, Int>()
        val secondIndexOf = HashMap<String, Int>()
        airings.forEachIndexed { index, airing ->
            val id = airing.franchiseId
            if (!firstIndexOf.containsKey(id)) firstIndexOf[id] = index
            else secondIndexOf.putIfAbsent(id, index)
        }

        // Every show is represented, D included, even though its episode is 17 hours behind C's third.
        assertEquals(setOf("a", "b", "c", "d"), firstIndexOf.keys)

        val lastFirst = firstIndexOf.values.max()
        for ((id, index) in secondIndexOf) {
            assertTrue(
                "$id's second alert at $index precedes a show's first at $lastFirst",
                index > lastFirst,
            )
        }
    }

    @Test
    fun `each rank block is internally sorted by instant`() {
        val library = listOf(
            weekly("c", 3, firstHours = 5),
            weekly("a", 1, firstHours = 1),
            weekly("b", 2, firstHours = 3),
        )

        val airings = EpisodeNotifications.buildPlan(library, NOW).airings

        // Rank 0 for all three (soonest first), then rank 1, then rank 2 — never a global time sort.
        assertEquals(
            listOf("a", "b", "c", "a", "b", "c", "a", "b", "c"),
            airings.map { it.franchiseId },
        )
        assertTrue(airings.take(3).zipWithNext().all { (l, r) -> l.atMillis < r.atMillis })
        assertTrue(airings.drop(3).take(3).zipWithNext().all { (l, r) -> l.atMillis < r.atMillis })
    }

    @Test
    fun `truncation drops thirds before firsts`() {
        val library = (1..20).map { weekly("f$it", it, firstHours = it.toLong()) }

        val airings = EpisodeNotifications.buildPlan(library, NOW).airings

        // 20 shows x 3 slots = 60 candidates, capped at 48 = 20 firsts + 20 seconds + 8 thirds.
        assertEquals(EpisodeNotifications.MAX_PENDING, airings.size)
        assertEquals(20, airings.take(20).map { it.franchiseId }.toSet().size)
        assertEquals(20, airings.drop(20).take(20).map { it.franchiseId }.toSet().size)
        assertEquals(8, airings.drop(40).size)
    }

    @Test
    fun `a show contributes at most three alerts`() {
        val library = listOf(show("a", 1, (1..8).map { it to hours(it.toLong()) }))

        val airings = EpisodeNotifications.buildPlan(library, NOW).airings

        assertEquals(EpisodeNotifications.PER_SHOW, airings.size)
        assertEquals(listOf(1, 2, 3), airings.map { it.episode })
    }

    // =========================================================================================
    // 2. The plan — the gate
    // =========================================================================================

    @Test
    fun `only watching AniList shows are alerted`() {
        val slots = listOf(1 to hours(2))
        val library = listOf(
            show("watching", 1, slots),
            show("tmdb", 1_000_000_042, slots, source = MediaSource.TMDB),
            show("planned", 3, slots, status = WatchStatus.PLANNED),
            show("paused", 4, slots, status = WatchStatus.PAUSED),
            show("completed", 5, slots, status = WatchStatus.COMPLETED),
            show("dropped", 6, slots, status = WatchStatus.DROPPED),
            // No status and no subscription — `effectiveStatus` falls back to `planned`.
            show("statusless", 7, slots, status = null),
        )

        val airings = EpisodeNotifications.buildPlan(library, NOW).airings

        assertEquals(listOf("watching"), airings.map { it.franchiseId })
    }

    @Test
    fun `an alerted show is always on the calendar — the ladder's middle tier`() {
        val library = listOf(
            show("a", 1, listOf(1 to hours(2))),
            show("b", 2, listOf(1 to hours(2)), status = WatchStatus.PLANNED),
            show("tv", 1_000_000_042, listOf(4 to hours(3)), source = MediaSource.TMDB),
        )

        val alerted = EpisodeNotifications.buildPlan(library, NOW).airings
            .map { it.franchiseId }
            .toSet()

        for (id in alerted) {
            val franchise = library.single { it.id == id }
            assertTrue("$id is armed for alerts but is not on the calendar", franchise.tracksAirings)
        }
        // The TV show keeps its calendar; only the timed ALERT is withheld from it.
        assertTrue(library.single { it.id == "tv" }.tracksAirings)
        assertTrue("tv" !in alerted)
    }

    // =========================================================================================
    // 3. The plan — what has passed, and the server that predates per-episode airings
    // =========================================================================================

    @Test
    fun `an episode that has already aired is not an alert`() {
        val library = listOf(
            show(
                id = "a",
                mediaId = 1,
                slots = listOf(1 to hours(-2), 2 to hours(2)),
                airedEpisodes = 1,
                lastAiredAt = hours(-2),
            ),
        )

        val airings = EpisodeNotifications.buildPlan(library, NOW).airings
        assertEquals(listOf(2), airings.map { it.episode })
    }

    @Test
    fun `an empty airings list still yields one alert from the catalogue slot`() {
        val library = listOf(
            show(
                id = "a",
                mediaId = 21_711,
                slots = emptyList(),
                airedEpisodes = 11,
                nextEpisodeNumber = 12,
                nextAiringAt = hours(6),
                lastAiredAt = hours(-162),
            ),
        )

        val alert = EpisodeNotifications.buildPlan(library, NOW).airings.single()

        assertEquals(12, alert.episode)
        assertEquals(hours(6), alert.atMillis)
        assertEquals("episode-21711-12", alert.tag)
    }

    @Test
    fun `a show with nothing ahead contributes nothing`() {
        val library = listOf(
            show("a", 1, listOf(1 to hours(-4)), airedEpisodes = 1, lastAiredAt = hours(-4)),
        )

        assertTrue(EpisodeNotifications.buildPlan(library, NOW).airings.isEmpty())
    }

    // =========================================================================================
    // 4. The alarms — one per air-time minute, at most eight
    // =========================================================================================

    @Test
    fun `a simulcast cluster is one alarm carrying every show`() {
        val slot = hours(4)
        val library = (1..12).map { show("f$it", it, listOf(7 to slot)) }
        val built = EpisodeNotifications.buildPlan(library, NOW)

        val targets = built.armTargets(NOW)

        assertEquals("twelve shows, one alarm", 1, targets.size)
        assertEquals(slot, targets.single().bucketAt)
        assertEquals(12, built.airings.count { airingBucket(it.atMillis) == slot })
    }

    @Test
    fun `at most eight alarms are armed however long the plan is`() {
        val airings = (1..30).map { alert("f$it", it, 1, hours(it.toLong())) }

        val targets = plan(*airings.toTypedArray()).armTargets(NOW)

        assertEquals(AlarmScheduler.MAX_BUCKETS, targets.size)
        assertEquals(hours(1), targets.first().bucketAt)
        assertEquals(hours(8), targets.last().bucketAt)
        assertEquals(targets.map { it.bucketAt }.sorted(), targets.map { it.bucketAt })
    }

    @Test
    fun `the horizon is a budget, not a cut-off`() {
        // Inside the horizon: only what is inside it is armed.
        val mixed = plan(
            alert("a", 1, 1, hours(47)),
            alert("b", 2, 1, hours(60)),
        )
        assertEquals(listOf(hours(47)), mixed.armTargets(NOW).map { it.bucketAt })

        // Nothing inside it: the soonest is armed ANYWAY. An alarm is what re-arms the next alarm,
        // so a device left untouched for three days must not end up with none.
        val distant = plan(
            alert("b", 2, 1, hours(60)),
            alert("c", 3, 1, hours(72)),
        )
        assertEquals(listOf(hours(60)), distant.armTargets(NOW).map { it.bucketAt })
    }

    @Test
    fun `the bucket that just fired is not re-armed`() {
        val fired = hours(1)
        val built = plan(
            alert("a", 1, 1, fired),
            alert("b", 2, 1, hours(2)),
        )

        val targets = built.armTargets(NOW, firedBucketAt = fired)

        assertEquals(listOf(hours(2)), targets.map { it.bucketAt })
        // Without the exclusion, an alarm arriving a hair early re-arms itself and announces every
        // episode in that bucket twice.
        assertEquals(2, built.armTargets(NOW).size)
    }

    @Test
    fun `an alarm never fires before the episode it announces`() {
        // Two shows inside one minute, neither on the boundary: the bucket key floors to the minute
        // (which is what the receiver matches on) while the alarm fires at the LATER of the two.
        val minute = hours(3)
        val early = minute + 10_000L
        val late = minute + 50_000L
        val built = plan(alert("a", 1, 1, early), alert("b", 2, 1, late))

        val target = built.armTargets(NOW).single()

        assertEquals("the key the receiver matches on", minute, target.bucketAt)
        assertEquals(late, target.triggerAt)
        assertTrue("the alarm would announce b before b aired", target.triggerAt >= late)
        assertTrue(target.triggerAt >= early)
    }

    @Test
    fun `an episode inside the current minute is still armed`() {
        // Its bucket is already in the past — testing the BUCKET instead of the instant would drop
        // the one alert most worth arming.
        val soon = NOW + 20_000L
        val targets = plan(alert("a", 1, 5, soon)).armTargets(NOW)

        assertEquals(1, targets.size)
        assertEquals(NOW, targets.single().bucketAt)
        assertEquals(soon, targets.single().triggerAt)
    }

    @Test
    fun `an empty plan arms nothing`() {
        assertTrue(AiringPlan(builtAt = NOW).armTargets(NOW).isEmpty())
        assertTrue(plan(alert("a", 1, 1, hours(-1))).armTargets(NOW).isEmpty())
    }

    // =========================================================================================
    // 5. armTargets is the ONLY bucket selector
    // =========================================================================================

    @Test
    fun `the armed buckets are ascending, distinct and strictly ahead`() {
        val library = listOf(
            weekly("a", 1, firstHours = 1),
            weekly("b", 2, firstHours = 1),
            weekly("c", 3, firstHours = 4),
        )
        val built = EpisodeNotifications.buildPlan(library, NOW)

        val buckets = built.armTargets(NOW).map { it.bucketAt }

        assertEquals(buckets.sorted(), buckets)
        assertEquals(buckets.distinct(), buckets)
        assertTrue(buckets.all { it >= NOW })
        assertEquals(listOf(1L, 2L, 3L, 4L, 5L, 6L).map { hours(it) }, buckets)
    }

    @Test
    fun `arming ignores what has passed`() {
        val built = plan(
            alert("a", 1, 1, hours(-3)),
            alert("a", 1, 2, hours(3)),
        )

        assertEquals(listOf(hours(3)), built.armTargets(NOW).map { it.bucketAt })
        assertNull(built.armTargets(hours(9)).firstOrNull())
    }

    @Test
    fun `a firing re-arms what it could not announce`() {
        // The receiver excludes the bucket it POSTED, and nothing else. A bucket armed for an
        // instant that had not quite arrived posts nothing, so it must survive the re-arm — the
        // exclusion used to be `maxOf(window.armed, …)`, which took the bucket out permanently and
        // those episodes were never announced at all.
        val built = plan(
            alert("a", 1, 1, hours(1)),
            alert("b", 2, 1, hours(2)),
        )

        val stillArmed = built.armTargets(now = NOW, firedBucketAt = null).map { it.bucketAt }
        assertEquals(listOf(hours(1), hours(2)), stillArmed)
    }
}
