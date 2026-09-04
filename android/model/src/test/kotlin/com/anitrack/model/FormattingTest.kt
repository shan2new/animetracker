package com.anitrack.model

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale
import java.util.TimeZone

/**
 * The time substrate's safety net.
 *
 * Every screen in the app asks this layer "when did this happen" and renders the answer as a
 * sentence; get a threshold wrong and every surface lies about time at once. The cases below are
 * the ones that have actually shipped bugs on iOS: the day boundary, DST, and above all the
 * two-calendar anchor — a TMDB slot judged in the device's calendar reads a day late east of
 * UTC+7, and counts as "aired" hours before its own day is over west of it.
 *
 * These mutate the JVM's default zone and locale, so they must not run concurrently with another
 * suite that does the same (Gradle runs one fork by default).
 */
class FormattingTest {

    private lateinit var savedZone: TimeZone
    private lateinit var savedLocale: Locale

    @Before
    fun setUp() {
        savedZone = TimeZone.getDefault()
        savedLocale = Locale.getDefault()
        use(NY)
    }

    @After
    fun tearDown() {
        TimeZone.setDefault(savedZone)
        Locale.setDefault(savedLocale)
        Formatting.invalidate()
    }

    // MARK: - Fixtures

    private companion object {
        const val NY = "America/New_York"
        const val TOKYO = "Asia/Tokyo"
        const val LA = "America/Los_Angeles"
        const val LONDON = "Europe/London"
    }

    private fun use(zone: String, locale: Locale = Locale.US) {
        TimeZone.setDefault(TimeZone.getTimeZone(zone))
        Locale.setDefault(locale)
        Formatting.invalidate()
    }

    private fun ms(zone: String, y: Int, mo: Int, d: Int, h: Int = 0, mi: Int = 0): Long =
        ZonedDateTime.of(y, mo, d, h, mi, 0, 0, ZoneId.of(zone)).toInstant().toEpochMilli()

    /** A TMDB-shaped date-only fact: the server synthesizes the day at 17:00 UTC. */
    private fun dateOnly(y: Int, mo: Int, d: Int): Long = ms("UTC", y, mo, d, 17)

    private fun plusDays(base: Long, days: Int, zone: String): Long =
        Instant.ofEpochMilli(base).atZone(ZoneId.of(zone)).plusDays(days.toLong())
            .toInstant().toEpochMilli()

    // MARK: - Day keys and dayDiff

    @Test
    fun dayKeyIsUtcMidnightOfTheDayTheAnchorReads() {
        use(NY)
        val lateEvening = ms(NY, 2026, 9, 4, 23, 30)
        assertEquals(
            LocalDate.of(2026, 9, 4).toEpochDay() * Formatting.D,
            Formatting.localDayKey(lateEvening),
        )
        // The same instant read as a UTC day is already the 5th — which is exactly why the two
        // keys live in one normalised space and can be subtracted from each other.
        assertEquals(
            LocalDate.of(2026, 9, 5).toEpochDay() * Formatting.D,
            Formatting.localDayKey(lateEvening, TimeAnchor.UTC_DATE),
        )
    }

    @Test
    fun dayDiffAcrossTheLocalMidnight() {
        use(NY)
        val now = ms(NY, 2026, 9, 4, 23, 59)
        assertEquals(0, Formatting.dayDiff(now, now))
        assertEquals(0, Formatting.dayDiff(ms(NY, 2026, 9, 4, 0, 1), now))
        assertEquals(1, Formatting.dayDiff(ms(NY, 2026, 9, 5, 0, 1), now))
        assertEquals(-1, Formatting.dayDiff(ms(NY, 2026, 9, 3, 23, 59), now))
    }

    @Test
    fun todayAt2359AndAt0001() {
        use(NY)
        // 23:59 — a slot two minutes later is TOMORROW, not "still tonight".
        val late = ms(NY, 2026, 9, 4, 23, 59)
        assertEquals("Today", Formatting.fmtDayLong(late, late))
        assertEquals("Tomorrow", Formatting.fmtDayLong(ms(NY, 2026, 9, 5, 0, 1), late))

        // 00:01 — the whole of the evening just gone is YESTERDAY, and the day ahead is TODAY.
        val early = ms(NY, 2026, 9, 4, 0, 1)
        assertEquals("Today", Formatting.fmtDayLong(early, early))
        assertEquals("Yesterday", Formatting.fmtDayLong(ms(NY, 2026, 9, 3, 23, 59), early))
        assertEquals("Today", Formatting.fmtDayLong(ms(NY, 2026, 9, 4, 23, 59), early))
    }

    // MARK: - DST

    @Test
    fun dayDiffSurvivesSpringForward() {
        // 2026-03-08 is a 23-HOUR day in America/New_York (clocks jump 02:00 -> 03:00).
        use(NY)
        val start = ms(NY, 2026, 3, 8, 0, 30)
        val end = ms(NY, 2026, 3, 8, 23, 30)
        val dayBefore = ms(NY, 2026, 3, 7, 12)
        val dayAfter = ms(NY, 2026, 3, 9, 12)

        assertEquals(0, Formatting.dayDiff(start, end))
        assertEquals(0, Formatting.dayDiff(end, start))
        assertEquals(-1, Formatting.dayDiff(dayBefore, start))
        assertEquals(1, Formatting.dayDiff(start, dayBefore))
        assertEquals(1, Formatting.dayDiff(dayAfter, end))
        assertEquals("Today", Formatting.fmtDayLong(end, start))
    }

    @Test
    fun dayDiffSurvivesFallBack() {
        // 2026-11-01 is a 25-HOUR day in America/New_York (clocks repeat 01:00-02:00). 00:30 and
        // 23:30 are a FULL 24 h apart in real time, so a naive (ts - now) / D would call the
        // evening "tomorrow" — the whole reason day keys exist.
        use(NY)
        val start = ms(NY, 2026, 11, 1, 0, 30)
        val end = ms(NY, 2026, 11, 1, 23, 30)
        assertTrue("the 25-hour day must span a full 24 h", end - start >= Formatting.D)
        assertEquals(1, ((end - start) / Formatting.D).toInt()) // what the naive maths would say
        assertEquals(0, Formatting.dayDiff(end, start)) // what the app says
        assertEquals("Today", Formatting.fmtDayLong(end, start))

        assertEquals(1, Formatting.dayDiff(ms(NY, 2026, 11, 2, 0, 30), start))
        assertEquals(-1, Formatting.dayDiff(ms(NY, 2026, 10, 31, 23, 30), start))
    }

    // MARK: - The two-calendar anchor

    @Test
    fun aSourceResolvesToExactlyOneAnchor() {
        // The one place `source` is allowed to decide a calendar. Everything downstream takes the
        // anchor, never the source.
        assertEquals(TimeAnchor.LOCAL, MediaSource.ANILIST.timeAnchor)
        assertEquals(TimeAnchor.UTC_DATE, MediaSource.TMDB.timeAnchor)
        assertFalse(MediaSource.ANILIST.timeAnchor.isDateOnly)
        assertTrue(MediaSource.TMDB.timeAnchor.isDateOnly)

        // The MediaSource overloads are the anchor implementations, not a second ladder.
        use(TOKYO)
        val slot = dateOnly(2026, 9, 6)
        val now = ms(TOKYO, 2026, 9, 6, 10)
        assertEquals(
            TemporalCopy.airs(slot, now, TimeAnchor.UTC_DATE),
            TemporalCopy.airs(slot, now, MediaSource.TMDB),
        )
        assertEquals(
            TemporalCopy.aired(slot, now, TimeAnchor.LOCAL),
            TemporalCopy.aired(slot, now, MediaSource.ANILIST),
        )
    }

    @Test
    fun dateOnlySlotIsJudgedOnItsUtcDayNotTheDeviceDay() {
        use(TOKYO)
        // A TMDB Sunday drop, synthesized at 17:00 UTC on 2026-09-06. In JST that instant is
        // Monday the 7th at 02:00; read locally, a Sunday drop reads "Monday".
        val slot = dateOnly(2026, 9, 6)
        val now = ms(TOKYO, 2026, 9, 6, 10)

        assertEquals(0, Formatting.dayDiff(slot, now, TimeAnchor.UTC_DATE))
        assertEquals(1, Formatting.dayDiff(slot, now, TimeAnchor.LOCAL)) // the bug the anchor prevents

        assertEquals("Today", TemporalCopy.airs(slot, now, TimeAnchor.UTC_DATE))
        assertTrue(TemporalCopy.airs(slot, now, TimeAnchor.LOCAL).startsWith("Tomorrow at "))

        val parts = Formatting.localParts(slot, TimeAnchor.UTC_DATE)
        assertEquals(6, parts.d)
        assertEquals(0, parts.wd) // Sunday
        assertEquals(7, Formatting.localParts(slot, TimeAnchor.LOCAL).d)
    }

    @Test
    fun dateOnlySlotCountsAsPassedOnlyTheDayAfterEastOfUtc() {
        use(TOKYO)
        val slot = dateOnly(2026, 9, 6)
        val early = ms(TOKYO, 2026, 9, 6, 0, 5)
        val late = ms(TOKYO, 2026, 9, 6, 23, 55)
        val nextDay = ms(TOKYO, 2026, 9, 7, 0, 5)

        assertEquals(0, Formatting.dayDiff(slot, early, TimeAnchor.UTC_DATE))
        assertEquals(0, Formatting.dayDiff(slot, late, TimeAnchor.UTC_DATE))
        assertEquals(-1, Formatting.dayDiff(slot, nextDay, TimeAnchor.UTC_DATE))

        assertEquals("today", Formatting.fmtRelSpanShort(slot, late, TimeAnchor.UTC_DATE))
        assertEquals("", Formatting.fmtRelSpanShort(slot, nextDay, TimeAnchor.UTC_DATE))

        assertEquals("Today", TemporalCopy.airsCompact(slot, late, TimeAnchor.UTC_DATE))
        assertEquals("Aired yesterday", TemporalCopy.aired(slot, nextDay, TimeAnchor.UTC_DATE))
    }

    @Test
    fun dateOnlySlotWestOfUtcIsNotPassedUntilTheDayTurns() {
        use(LA)
        // 17:00 UTC on the 6th is 10:00 PDT on the 6th, so the INSTANT is long gone by the
        // evening — but the DAY is not, and a date-only fact only has a day.
        val slot = dateOnly(2026, 9, 6)
        val evening = ms(LA, 2026, 9, 6, 23, 55)
        val nextDay = ms(LA, 2026, 9, 7, 0, 5)

        assertTrue("the synthesized instant has already passed", evening > slot)
        assertEquals(0, Formatting.dayDiff(slot, evening, TimeAnchor.UTC_DATE))
        assertEquals("Today", TemporalCopy.airsCompact(slot, evening, TimeAnchor.UTC_DATE))
        assertEquals("Aired today", TemporalCopy.aired(slot, evening, TimeAnchor.UTC_DATE))

        assertEquals(-1, Formatting.dayDiff(slot, nextDay, TimeAnchor.UTC_DATE))
        assertEquals("Aired yesterday", TemporalCopy.aired(slot, nextDay, TimeAnchor.UTC_DATE))
    }

    @Test
    fun aDateOnlySlotNeverGrowsAClock() {
        use(TOKYO)
        val slot = dateOnly(2026, 9, 6)
        val now = ms(TOKYO, 2026, 9, 1, 9)

        assertEquals("", Formatting.fmtTime(slot, TimeAnchor.UTC_DATE))
        // The countdown degrades to a day-precision span rather than inventing hours.
        assertEquals("5d", Formatting.fmtCountdown(slot, now, TimeAnchor.UTC_DATE))

        val phrases = listOf(
            TemporalCopy.airs(slot, now, TimeAnchor.UTC_DATE),
            TemporalCopy.airsCompact(slot, now, TimeAnchor.UTC_DATE),
            Formatting.fmtWhen(slot, now, TimeAnchor.UTC_DATE),
            TemporalCopy.returns(slot, now, TimeAnchor.UTC_DATE),
        )
        for (phrase in phrases) {
            assertFalse(phrase, phrase.contains(":"))
            assertFalse(phrase, phrase.contains(" at "))
        }
    }

    @Test
    fun dateOnlyPartsStillReportTheSynthesizedSeventeenHundred() {
        use(TOKYO)
        val slot = dateOnly(2026, 9, 6)
        // The hour is the server's synthetic, which is precisely why fmtTime refuses to print it
        // and why nothing may threshold on it.
        assertEquals(17, Formatting.localParts(slot, TimeAnchor.UTC_DATE).hour)
        assertEquals("", Formatting.fmtTime(slot, TimeAnchor.UTC_DATE))
    }

    // MARK: - airs / airsCompact

    @Test
    fun airsNamesTheMinutesInsideTheHour() {
        use(NY)
        val now = ms(NY, 2026, 9, 4, 19)
        assertEquals(
            "Airs in 27 min",
            TemporalCopy.airs(now + 27 * Formatting.MINUTE_MS, now, TimeAnchor.LOCAL),
        )
        // max(1, …) — a slot 30 seconds out never says "Airs in 0 min".
        assertEquals("Airs in 1 min", TemporalCopy.airs(now + 30_000, now, TimeAnchor.LOCAL))
        // Exactly an hour out leaves the relative band and joins the day ladder.
        val hourOut = now + 60 * Formatting.MINUTE_MS
        assertEquals(
            "Today at ${Formatting.fmtTime(hourOut)}",
            TemporalCopy.airs(hourOut, now, TimeAnchor.LOCAL),
        )
    }

    @Test
    fun airsDayLadder() {
        use(NY)
        val now = ms(NY, 2026, 9, 4, 9) // Friday 4 September 2026
        fun at(days: Int) = ms(NY, 2026, 9, 4, 20, 30).let { plusDays(it, days, NY) }

        assertEquals("Today at ${Formatting.fmtTime(at(0))}", TemporalCopy.airs(at(0), now, TimeAnchor.LOCAL))
        assertEquals("Tomorrow at ${Formatting.fmtTime(at(1))}", TemporalCopy.airs(at(1), now, TimeAnchor.LOCAL))
        assertEquals("Sunday at ${Formatting.fmtTime(at(2))}", TemporalCopy.airs(at(2), now, TimeAnchor.LOCAL))
        assertEquals("Thursday at ${Formatting.fmtTime(at(6))}", TemporalCopy.airs(at(6), now, TimeAnchor.LOCAL))
        // Day 7 leaves the weekday band and states the date.
        assertEquals("Sep 11 at ${Formatting.fmtTime(at(7))}", TemporalCopy.airs(at(7), now, TimeAnchor.LOCAL))
    }

    @Test
    fun compactDropsTheClockButNeverTheDayWord() {
        use(NY)
        val now = ms(NY, 2026, 9, 4, 9)
        val sunday = ms(NY, 2026, 9, 6, 20, 30)
        assertEquals("Sunday", TemporalCopy.airsCompact(sunday, now, TimeAnchor.LOCAL))
        assertEquals(
            "Sunday at ${Formatting.fmtTime(sunday)}",
            TemporalCopy.airs(sunday, now, TimeAnchor.LOCAL),
        )
        // The two ladders are the same ladder, day for day, so they can never drift again.
        for (d in -2..8) {
            val t = plusDays(now, d, NY)
            val full = TemporalCopy.airs(t, now, TimeAnchor.LOCAL)
            val compact = TemporalCopy.airsCompact(t, now, TimeAnchor.LOCAL)
            assertEquals("day offset $d", "$compact at ${Formatting.fmtTime(t)}", full)
        }
    }

    // MARK: - aired / since

    @Test
    fun airedLadderFallsThroughToAMonthDay() {
        use(NY)
        val now = ms(NY, 2026, 9, 4, 20)
        assertEquals(
            "Aired just now",
            TemporalCopy.aired(now - 4 * Formatting.MINUTE_MS, now, TimeAnchor.LOCAL),
        )
        assertEquals(
            "Aired 27 min ago",
            TemporalCopy.aired(now - 27 * Formatting.MINUTE_MS, now, TimeAnchor.LOCAL),
        )
        assertEquals("Aired 10h ago", TemporalCopy.aired(ms(NY, 2026, 9, 4, 10), now, TimeAnchor.LOCAL))
        assertEquals("Aired yesterday", TemporalCopy.aired(ms(NY, 2026, 9, 3, 20), now, TimeAnchor.LOCAL))
        // fmtDayLong does not name PAST weekdays, so 2-6 days ago is a month-day. The iOS doc
        // comment promises "Aired Wednesday"; the shipped code emits this, and the code wins.
        assertEquals("Aired Sep 2", TemporalCopy.aired(ms(NY, 2026, 9, 2, 20), now, TimeAnchor.LOCAL))
        assertEquals("Aired Aug 19", TemporalCopy.aired(ms(NY, 2026, 8, 19, 20), now, TimeAnchor.LOCAL))
        assertEquals(
            "Aired Aug 19, 2025",
            TemporalCopy.aired(ms(NY, 2025, 8, 19, 20), now, TimeAnchor.LOCAL),
        )
    }

    @Test
    fun sinceLadder() {
        use(NY)
        val now = ms(NY, 2026, 9, 4, 20)
        assertEquals("Since earlier today", TemporalCopy.since(ms(NY, 2026, 9, 4, 8), now))
        assertEquals("Since yesterday", TemporalCopy.since(ms(NY, 2026, 9, 3, 8), now))
        // Same past-weekday fall-through as `aired`.
        assertEquals("Since Sep 1", TemporalCopy.since(ms(NY, 2026, 9, 1, 8), now))
        assertEquals("Since Jul 23", TemporalCopy.since(ms(NY, 2026, 7, 23, 8), now))
    }

    // MARK: - returns

    @Test
    fun returnsLadderIncludingThePastBranch() {
        use(NY)
        val now = ms(NY, 2026, 9, 4, 12)
        assertEquals("No date announced", TemporalCopy.returns(null, now, TimeAnchor.LOCAL))
        // A curated note outlives its premiere by weeks; every past day used to read "Returns today".
        assertEquals("Returned Jul 5", TemporalCopy.returns(ms(NY, 2026, 7, 5, 12), now, TimeAnchor.LOCAL))
        assertEquals("Returns today", TemporalCopy.returns(ms(NY, 2026, 9, 4, 23), now, TimeAnchor.LOCAL))
        assertEquals("Returns tomorrow", TemporalCopy.returns(ms(NY, 2026, 9, 5, 12), now, TimeAnchor.LOCAL))
        assertEquals("Returns Sunday", TemporalCopy.returns(ms(NY, 2026, 9, 6, 12), now, TimeAnchor.LOCAL))
        assertEquals("Returns Oct 2", TemporalCopy.returns(ms(NY, 2026, 10, 2, 12), now, TimeAnchor.LOCAL))
        assertEquals(
            "Returns Oct 2, 2027",
            TemporalCopy.returns(ms(NY, 2027, 10, 2, 12), now, TimeAnchor.LOCAL),
        )
        assertEquals("Premieres Oct 2", TemporalCopy.premieres("Oct 2"))
    }

    // MARK: - dateWord / dateRange

    @Test
    fun dateWordAddsTheYearOnlyOutsideThisOne() {
        use(NY)
        val now = ms(NY, 2026, 9, 4, 12)
        assertEquals("Aug 28", TemporalCopy.dateWord(ms(NY, 2026, 8, 28, 12), now, TimeAnchor.LOCAL))
        assertEquals(
            "Aug 28, 2027",
            TemporalCopy.dateWord(ms(NY, 2027, 8, 28, 12), now, TimeAnchor.LOCAL),
        )
    }

    @Test
    fun dateRangeStatesBothYearsWhenItLeavesThisOne() {
        use(NY)
        val now = ms(NY, 2026, 9, 4, 12)
        assertEquals(
            "May 24 – Jul 29",
            TemporalCopy.dateRange(ms(NY, 2026, 5, 24), ms(NY, 2026, 7, 29), now),
        )
        assertEquals(
            "Dec 10, 2024 – Feb 3, 2025",
            TemporalCopy.dateRange(ms(NY, 2024, 12, 10), ms(NY, 2025, 2, 3), now),
        )
        // A span wholly inside another year still states it — "24 May – 29 Jul" with no year at
        // all sat two rows from "10 Dec, 2024" in the shipped build.
        assertEquals(
            "May 24, 2025 – Jul 29, 2025",
            TemporalCopy.dateRange(ms(NY, 2025, 5, 24), ms(NY, 2025, 7, 29), now),
        )
    }

    // MARK: - Locale

    @Test
    fun dateOrderFollowsTheLocale() {
        use(LONDON, Locale.UK)
        val gb = ms(LONDON, 2026, 5, 4, 21)
        assertEquals("4 May", Formatting.fmtMonthDay(gb))
        assertEquals("4 May 2026", Formatting.fmtFullDate(gb))

        use(NY, Locale.US)
        val us = ms(NY, 2026, 5, 4, 21)
        assertEquals("May 4", Formatting.fmtMonthDay(us))
        assertEquals("May 4, 2026", Formatting.fmtFullDate(us))
        assertEquals("May 2026", Formatting.fmtMonthYear(us))
    }

    @Test
    fun clockFollowsTheDeviceHourCycle() {
        use(LONDON, Locale.UK)
        assertEquals("21:00", Formatting.fmtTime(ms(LONDON, 2026, 5, 4, 21)))

        use(NY, Locale.US)
        val twelveHour = Formatting.fmtTime(ms(NY, 2026, 5, 4, 21))
        assertTrue(twelveHour, twelveHour.startsWith("9:00"))
        assertTrue(twelveHour, twelveHour.contains("PM"))
    }

    @Test
    fun zoneChangeIsDetectedWithoutAnExplicitInvalidate() {
        use("Pacific/Auckland", Locale.US)
        val instant = ms("UTC", 2026, 5, 4, 12)
        assertEquals("May 5", Formatting.fmtMonthDay(instant)) // NZST, already the next day
        // A travelling user must never keep yesterday's calendar: the cache re-keys itself off
        // the default zone, with no explicit invalidation.
        TimeZone.setDefault(TimeZone.getTimeZone(LA))
        assertEquals("May 4", Formatting.fmtMonthDay(instant))
    }

    // MARK: - Spans, countdowns, ago

    @Test
    fun relativeSpanTable() {
        use(NY)
        val now = ms(NY, 2026, 9, 4, 12)
        fun span(days: Int) = Formatting.fmtRelSpanShort(plusDays(now, days, NY), now)

        // A date already passed describes no wait at all — callers read "" as "nothing to say".
        assertEquals("", span(-1))
        assertEquals("today", span(0))
        assertEquals("1d", span(1))
        assertEquals("6d", span(6))
        assertEquals("1wk", span(7))
        assertEquals("2wk", span(11))
        assertEquals("4wk", span(29))
        assertEquals("1mo", span(30))
        assertEquals("2mo", span(45))

        assertEquals("in 2wk", Formatting.fmtRelSpan(plusDays(now, 11, NY), now))
        assertEquals("today", Formatting.fmtRelSpan(now, now))
        assertEquals("", Formatting.fmtRelSpan(plusDays(now, -1, NY), now))
    }

    @Test
    fun countdownTable() {
        use(NY)
        val now = ms(NY, 2026, 9, 4, 12)
        assertEquals("now", Formatting.fmtCountdown(now + 59_000, now))
        assertEquals("now", Formatting.fmtCountdown(now - Formatting.H, now)) // clamped at zero
        assertEquals("31m", Formatting.fmtCountdown(now + 31 * Formatting.MINUTE_MS, now))
        assertEquals(
            "3h 12m",
            Formatting.fmtCountdown(now + 3 * Formatting.H + 12 * Formatting.MINUTE_MS, now),
        )
        assertEquals(
            "2d 4h",
            Formatting.fmtCountdown(now + 2 * Formatting.D + 4 * Formatting.H, now),
        )
    }

    @Test
    fun agoTable() {
        use(NY)
        val now = ms(NY, 2026, 9, 4, 12)
        assertEquals("just now", Formatting.fmtAgo(now - 30_000, now))
        assertEquals("42m ago", Formatting.fmtAgo(now - 42 * Formatting.MINUTE_MS, now))
        assertEquals("9h ago", Formatting.fmtAgo(now - 9 * Formatting.H, now))
        assertEquals("4d ago", Formatting.fmtAgo(now - 4 * Formatting.D, now))
        // A date-only fact has fabricated hours, so it degrades to whole days.
        assertEquals("3d ago", Formatting.fmtAgo(dateOnly(2026, 9, 1), now, TimeAnchor.UTC_DATE))
        assertEquals("today", Formatting.fmtAgo(dateOnly(2026, 9, 4), now, TimeAnchor.UTC_DATE))
    }

    // MARK: - Day words

    @Test
    fun fmtDayNeverProducesAMonthDay() {
        use(NY)
        val now = ms(NY, 2026, 9, 4, 12)
        assertEquals("Today", Formatting.fmtDay(now, now))
        assertEquals("Tomorrow", Formatting.fmtDay(plusDays(now, 1, NY), now))
        assertEquals("Yesterday", Formatting.fmtDay(plusDays(now, -1, NY), now))
        // 30 days out still reads "Sun" — this function has no month-day branch, deliberately.
        assertEquals("Sun", Formatting.fmtDay(plusDays(now, 30, NY), now))
    }

    @Test
    fun fmtDayLongNamesFutureWeekdaysOnly() {
        use(NY)
        val now = ms(NY, 2026, 9, 4, 12)
        assertEquals("Sunday", Formatting.fmtDayLong(plusDays(now, 2, NY), now))
        assertEquals("Thursday", Formatting.fmtDayLong(plusDays(now, 6, NY), now))
        assertEquals("Sep 11", Formatting.fmtDayLong(plusDays(now, 7, NY), now))
        // The asymmetry: the past never gets its weekday named here.
        assertEquals("Sep 2", Formatting.fmtDayLong(plusDays(now, -2, NY), now))
        assertEquals("Aug 29", Formatting.fmtDayLong(plusDays(now, -6, NY), now))
    }

    @Test
    fun fmtWhenGivesTheClockOnlyToARealInstant() {
        use(NY)
        val now = ms(NY, 2026, 9, 4, 12)
        val instant = ms(NY, 2026, 9, 5, 21)
        assertEquals("Tomorrow ${Formatting.fmtTime(instant)}", Formatting.fmtWhen(instant, now))
        assertEquals("Tomorrow", Formatting.fmtWhen(dateOnly(2026, 9, 5), now, TimeAnchor.UTC_DATE))
    }

    @Test
    fun dayBadgeTable() {
        use(NY)
        val now = ms(NY, 2026, 9, 4, 12)
        assertEquals(DayBadge("Today", "today"), Formatting.fmtDayBadge(now, now))
        assertEquals(DayBadge("Tomorrow", "in 1d"), Formatting.fmtDayBadge(plusDays(now, 1, NY), now))
        assertEquals(DayBadge("Sun", "in 2d"), Formatting.fmtDayBadge(plusDays(now, 2, NY), now))
        assertEquals(DayBadge("Oct 4", "in 1mo"), Formatting.fmtDayBadge(plusDays(now, 30, NY), now))
        // A past date has no countdown to give — "Sep 3 / today" would be a lie.
        assertEquals(DayBadge("Aired", "Sep 3"), Formatting.fmtDayBadge(plusDays(now, -1, NY), now))
    }

    // MARK: - Weekday helpers

    @Test
    fun weekdayHelpersUseTheMondayFirstColumn() {
        use(NY, Locale.US)
        val friday = ms(NY, 2026, 9, 4, 12)
        assertEquals(5, Formatting.localParts(friday).wd) // 0=Sun .. 6=Sat
        assertEquals(4, Formatting.localMondayCol(friday)) // 0=Mon .. 6=Sun

        assertEquals("Fri", Formatting.weekdayShort(5))
        assertEquals("Fri", Formatting.weekdayShortMonFirst(4))
        assertEquals("Monday", Formatting.weekdayNameMonFirst(0))
        assertEquals("Friday", Formatting.weekdayNameMonFirst(4))
        assertEquals("Sunday", Formatting.weekdayNameMonFirst(6))
        assertEquals("F", Formatting.weekdayLetterMonFirst(4))

        // Out of range answers with an empty string rather than crashing a row.
        assertEquals("", Formatting.weekdayShort(7))
        assertEquals("", Formatting.weekdayShort(-1))

        // Copy.elapsedWord names a PAST weekday itself, precisely because fmtDayLong will not.
        val wednesday = ms(NY, 2026, 9, 2, 12)
        assertEquals(
            "Wednesday",
            Formatting.weekdayNameMonFirst(Formatting.localMondayCol(wednesday)),
        )
    }

    // MARK: - Curated release strings

    @Test
    fun prettyReleaseStringNeverShiftsADay() {
        // A zone ten hours west of UTC: a bare calendar date parsed locally would read a day early.
        use("Pacific/Honolulu", Locale.US)
        assertEquals("Jul 5, 2026", Formatting.prettyReleaseString("2026-07-05"))
        assertEquals("Jul 5, 2026", Formatting.prettyReleaseString("  2026-07-05  "))
        assertEquals("Oct 2026", Formatting.prettyReleaseString("2026-10"))

        // Already-human windows pass through untouched.
        assertEquals("October 2026", Formatting.prettyReleaseString("October 2026"))
        assertEquals("2027", Formatting.prettyReleaseString("2027"))
        assertEquals("TBA", Formatting.prettyReleaseString("TBA"))
        assertEquals("2026-10-99", Formatting.prettyReleaseString("2026-10-99"))
        assertEquals("2026-13", Formatting.prettyReleaseString("2026-13"))
        assertEquals("26-10-05", Formatting.prettyReleaseString("26-10-05"))
    }

    // MARK: - Greeting

    @Test
    fun greetingAndTheOneDefinitionOfEvening() {
        use(NY)
        assertEquals("Late night", Formatting.greetingFor(ms(NY, 2026, 9, 4, 3)))
        assertEquals("Good morning", Formatting.greetingFor(ms(NY, 2026, 9, 4, 9)))
        assertEquals("Good afternoon", Formatting.greetingFor(ms(NY, 2026, 9, 4, 14)))
        assertEquals("Good evening", Formatting.greetingFor(ms(NY, 2026, 9, 4, 20)))
        assertFalse(Formatting.isEvening(17))
        assertTrue(Formatting.isEvening(18))
    }

    // MARK: - Text

    @Test
    fun stripHtmlCleansASynopsisWithoutTruncatingIt() {
        assertEquals("", Formatting.stripHtml(null))
        assertEquals("", Formatting.stripHtml(""))
        assertEquals(
            "Subaru is summoned.",
            Formatting.stripHtml("<p>Subaru   is\n<i>summoned</i>.</p>"),
        )
        assertEquals("R&D", Formatting.stripHtml("R&amp;D"))
        assertEquals("a b", Formatting.stripHtml("a  b"))
        assertEquals("a b", Formatting.stripHtml("  a&nbsp;b  "))
    }

    /**
     * The whitespace class must be the Unicode `White_Space` set, not Java's ASCII-only `\s`.
     *
     * AniList descriptions carry raw U+00A0, U+2009 and friends; `NSRegularExpression`'s `\s`
     * collapses them, so the port has to as well or an Android synopsis keeps hard spaces iOS
     * removed. The spelling that expressed this as an inline `(?U)` flag compiled here and threw
     * `PatternSyntaxException` on Android's ICU engine at class-init time — a crash a JVM test
     * cannot reproduce, so this test pins the *behaviour* the flag was there for instead.
     */
    @Test
    fun stripHtmlCollapsesUnicodeWhitespaceNotJustAscii() {
        assertEquals("a b", Formatting.stripHtml("a\u00A0b"))
        assertEquals("a b", Formatting.stripHtml("a\u2009\u2009b"))
        assertEquals("a b", Formatting.stripHtml("a\u3000b"))
        assertEquals("a b", Formatting.stripHtml("a\u202F\u205Fb"))
        assertEquals("a b", Formatting.stripHtml("a\u00A0 \t\nb"))
        // And a Unicode-space edge is trimmed, as .whitespacesAndNewlines does.
        assertEquals("a", Formatting.stripHtml("\u00A0a\u2000"))
    }

    @Test
    fun htmlEntitiesDecodeInTheRightOrder() {
        // &amp; decodes LAST, so &amp;lt; yields &lt; rather than <.
        assertEquals("&lt;", Formatting.decodeHtmlEntities("&amp;lt;"))
        assertEquals("it’s", Formatting.decodeHtmlEntities("it&#8217;s"))
        assertEquals("it’s", Formatting.decodeHtmlEntities("it&#x2019;s"))
        assertEquals("a—b", Formatting.decodeHtmlEntities("a&mdash;b"))
        assertEquals("a–b", Formatting.decodeHtmlEntities("a&ndash;b"))
        assertEquals("“q”", Formatting.decodeHtmlEntities("&ldquo;q&rdquo;"))
        // An invalid scalar (a lone surrogate) makes the reference disappear.
        assertEquals("ab", Formatting.decodeHtmlEntities("a&#xD800;b"))
        assertEquals("plain", Formatting.decodeHtmlEntities("plain"))
    }
}
