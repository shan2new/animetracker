package com.anitrack.app.data

import kotlinx.coroutines.delay
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The conflation contract of the per-part write lane, which is the one piece of the write policy
 * that reads correct while being wrong.
 *
 * The regression behind it: every mark used to spawn a bare coroutine, so marking 12 then 13 quickly
 * raced two PUTs — when 13's answer landed first and 12's landed last, **the server ended on 12** and
 * the next reload walked the tick back.
 *
 * Every test runs on [UnconfinedTestDispatcher] on purpose. It starts a coroutine eagerly and inline,
 * which is exactly what `Dispatchers.Main.immediate` does in the app; a `StandardTestDispatcher`
 * would let all three marks pile into the mailbox before the drainer ever ran, and would therefore
 * assert a behaviour the app does not have.
 *
 * The lane's scope is the `TestScope` itself — **never `backgroundScope`**, which is what these
 * tests were first written against and why four of them failed on a lane that was correct.
 * `advanceUntilIdle()` does not drive background work to completion: background coroutines are run
 * only as far as is needed to unblock *foreground* work, so the drainer issued its first PUT inline
 * and then simply never resumed from the round-trip `delay`. The symptom — `[12]` where `[12, 14]`
 * was expected — is indistinguishable from the real conflation bug this file exists to catch, so
 * the scope is load-bearing: it is the difference between the suite testing the lane and the suite
 * testing the test framework. The drainer always completes (it breaks when the mailbox empties), so
 * running it in the foreground leaks nothing.
 */
class ProgressLaneTest {

    private companion object {
        const val MEDIA_ID = 21_711

        /** A second part, to prove the lanes are per-part and not global. */
        const val OTHER_MEDIA_ID = 21_712
    }

    private fun write(episodes: Int) = ProgressWrite(
        franchiseId = "f/rezero",
        episodes = episodes,
        command = "Mark as watched",
        title = "Re:ZERO",
    )

    @Test
    fun `a rapid 12 13 14 issues exactly two PUTs and ends on 14`() =
        runTest(UnconfinedTestDispatcher()) {
            val sent = ArrayList<Int>()
            val lane = ProgressLane(this) { _, w ->
                sent += w.episodes
                delay(50)   // the round-trip
            }

            // 12 goes out immediately and is in flight. 13 lands in the one-slot mailbox and is then
            // OVERWRITTEN by 14 — it is dropped without ever being sent.
            lane.send(MEDIA_ID, write(12))
            lane.send(MEDIA_ID, write(13))
            lane.send(MEDIA_ID, write(14))

            advanceUntilIdle()

            assertEquals(listOf(12, 14), sent)
        }

    @Test
    fun `the in-flight write is never cancelled by a newer target`() =
        runTest(UnconfinedTestDispatcher()) {
            val started = ArrayList<Int>()
            val finished = ArrayList<Int>()
            val lane = ProgressLane(this) { _, w ->
                started += w.episodes
                delay(50)
                finished += w.episodes
            }

            lane.send(MEDIA_ID, write(12))
            lane.send(MEDIA_ID, write(14))
            advanceUntilIdle()

            // Both halves matter: a conflated channel that cancelled its collector would leave the
            // server's last word undecided, so 12 must COMPLETE before 14 is issued.
            assertEquals(listOf(12, 14), started)
            assertEquals(listOf(12, 14), finished)
        }

    @Test
    fun `a settled lane frees itself so the next mark starts a new drainer`() =
        runTest(UnconfinedTestDispatcher()) {
            val sent = ArrayList<Int>()
            val lane = ProgressLane(this) { _, w ->
                sent += w.episodes
                delay(50)
            }

            lane.send(MEDIA_ID, write(1))
            advanceUntilIdle()
            lane.send(MEDIA_ID, write(2))
            advanceUntilIdle()

            assertEquals(listOf(1, 2), sent)
        }

    @Test
    fun `lanes are per part`() = runTest(UnconfinedTestDispatcher()) {
        val sent = ArrayList<Pair<Int, Int>>()
        val lane = ProgressLane(this) { mediaId, w ->
            sent += mediaId to w.episodes
            delay(50)
        }

        // Two parts marked in the same frame: neither may wait on the other, and neither may
        // supersede the other.
        lane.send(MEDIA_ID, write(12))
        lane.send(OTHER_MEDIA_ID, write(3))
        advanceUntilIdle()

        assertEquals(setOf(MEDIA_ID to 12, OTHER_MEDIA_ID to 3), sent.toSet())
    }

    @Test
    fun `isQueued reports the target waiting behind the write in flight`() =
        runTest(UnconfinedTestDispatcher()) {
            val queuedDuringFirstPut = ArrayList<Boolean>()
            lateinit var lane: ProgressLane
            lane = ProgressLane(this) { mediaId, _ ->
                delay(50)
                // Read at the moment a failure would be reported: a newer target waiting here means
                // this attempt has nothing to report, because that target decides the outcome.
                queuedDuringFirstPut += lane.isQueued(mediaId)
            }

            lane.send(MEDIA_ID, write(12))
            lane.send(MEDIA_ID, write(14))
            advanceUntilIdle()

            assertEquals(2, queuedDuringFirstPut.size)
            assertTrue("14 was waiting behind 12", queuedDuringFirstPut[0])
            assertFalse("nothing was waiting behind 14", queuedDuringFirstPut[1])
        }

    @Test
    fun `cancelAll drops every pending target`() = runTest(UnconfinedTestDispatcher()) {
        val sent = ArrayList<Int>()
        val lane = ProgressLane(this) { _, w ->
            sent += w.episodes
            delay(50)
        }

        lane.send(MEDIA_ID, write(12))
        lane.send(MEDIA_ID, write(14))
        // Sign-out: the next account must not inherit this one's queued writes.
        lane.cancelAll()
        advanceUntilIdle()

        assertEquals(listOf(12), sent)
        assertFalse(lane.isQueued(MEDIA_ID))
    }
}
