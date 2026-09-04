package com.anitrack.model

import java.time.DateTimeException
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.chrono.IsoChronology
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeFormatterBuilder
import java.time.format.FormatStyle
import java.time.format.TextStyle
import java.util.Locale
import java.util.TimeZone
import kotlin.math.roundToInt

// Time/date formatting. Timestamps are milliseconds since epoch (Long), matching the API
// contract; the conversion to/from an Instant happens here and nowhere else.
//
// TWO CALENDARS, not one. Every helper below takes a [Formatting.TimeAnchor] (defaulting to
// LOCAL) saying which calendar a timestamp must be read in:
//
//   • LOCAL    — a real instant. AniList dates episodes to the minute, so its timestamps carry a
//                genuine broadcast moment and are read in the device's zone.
//   • UTC_DATE — a DATE-ONLY fact. TMDB ships air dates with no clock and the server synthesizes
//                them at 17:00 UTC (docs/api-contract.md), so the only true part of the
//                timestamp is its UTC calendar day. Breaking it down locally pushes every
//                timezone east of UTC+7 one day forward — a Sunday drop read "Monday" in JST.
//
// Two consequences the anchor enforces rather than documents:
//   (a) day labels, day diffs and day bucketing use the timestamp's OWN calendar day;
//   (b) a UTC_DATE timestamp NEVER yields a clock time or an hour-precision countdown —
//       fmtTime returns "" and fmtCountdown degrades to day precision.
//
// All human-facing month/weekday names and clock times come from the platform's own pattern
// provider, never from hand-built tables: a device set to 24-Hour Time must read "21:00", not
// "9:00 PM".

/**
 * The platform's date/time *patterns*, injected because `:model` is a pure Kotlin module and the
 * only Android API that honours the system 24-hour toggle needs a `Context`.
 *
 * The Android implementation (installed once at app start, before any screen composes) is:
 *
 * ```
 * class AndroidDateTimePatterns(private val context: Context) : DateTimePatterns {
 *     // Recomputed by the broadcast receiver, not read per call — see [stamp].
 *     @Volatile private var is24Hour = DateFormat.is24HourFormat(context)
 *     fun reload() { is24Hour = DateFormat.is24HourFormat(context); Formatting.invalidate() }
 *
 *     override val stamp: String get() = if (is24Hour) "24h" else "12h"
 *     override fun best(skeleton: String, locale: Locale): String =
 *         DateFormat.getBestDateTimePattern(locale, skeleton)
 *     override fun shortTime(locale: Locale): String =
 *         DateFormat.getBestDateTimePattern(locale, if (is24Hour) "Hm" else "hm")
 * }
 * ```
 *
 * `DateTimeFormatter.ofLocalizedTime(SHORT)` **ignores** the user's 24-hour toggle, which would
 * break the single most visible formatting rule in the app ("a device set to 24-Hour Time must
 * read 21:00, not 9:00 PM"), so the clock pattern must be chosen by
 * `android.text.format.DateFormat.is24HourFormat(context)` and nothing else. [stamp] is what tells
 * the formatter cache the toggle moved — neither the locale nor the zone changes when it does.
 */
interface DateTimePatterns {
    /**
     * Everything the patterns depend on that is NOT the locale or the time zone, as one string.
     * The formatter cache is dropped whenever this changes.
     *
     * **This is read on every call into [Formatting], so it must be cheap** — cache the answer and
     * refresh it from a `ContentObserver` on `Settings.System.TIME_12_24`, or simply call
     * [Formatting.invalidate] from the receiver and return a constant here.
     */
    val stamp: String

    /** Locale-ordered pattern for a Unicode date-format skeleton ("MMMd" -> "MMM d" / "d MMM"). */
    fun best(skeleton: String, locale: Locale): String

    /** The device's SHORT time pattern, honouring the system 24-hour toggle. */
    fun shortTime(locale: Locale): String
}

/**
 * The pure-JVM pattern provider: the default, and what unit tests run against.
 *
 * It derives field order from the locale's own MEDIUM date pattern rather than hard-coding
 * English, so `MMMd` reads "May 4" on en-US and "4 May" on en-GB. It is deliberately a small
 * table and not an ICU skeleton resolver — on a device, [DateTimePatterns] is replaced by the
 * Android implementation, which delegates to ICU's `getBestDateTimePattern`.
 */
object JvmDateTimePatterns : DateTimePatterns {

    override val stamp: String = "jvm"

    override fun best(skeleton: String, locale: Locale): String {
        val dayFirst = dayBeforeMonth(locale)
        return when (skeleton) {
            "MMMd" -> if (dayFirst) "d MMM" else "MMM d"
            "MMMdyyyy" -> if (dayFirst) "d MMM y" else "MMM d, y"
            "MMMyyyy" -> "MMM y"
            "EEEEMMMMd" -> if (dayFirst) "EEEE d MMMM" else "EEEE, MMMM d"
            "EEEEMMMd" -> if (dayFirst) "EEEE d MMM" else "EEEE, MMM d"
            // An unknown skeleton is already a pattern by the time it reaches here; ICU would
            // resolve it, and the JVM fallback passes it through rather than inventing an order.
            else -> skeleton
        }
    }

    override fun shortTime(locale: Locale): String =
        DateTimeFormatterBuilder.getLocalizedDateTimePattern(
            null, FormatStyle.SHORT, IsoChronology.INSTANCE, locale,
        )

    /** Quoted literals ("d 'de' MMM 'de' y") carry letters that are not fields — strip them first. */
    private val QUOTED = Regex("'[^']*'")

    private fun dayBeforeMonth(locale: Locale): Boolean {
        val medium = QUOTED.replace(
            DateTimeFormatterBuilder.getLocalizedDateTimePattern(
                FormatStyle.MEDIUM, null, IsoChronology.INSTANCE, locale,
            ),
            "",
        )
        val day = medium.indexOfFirst { it == 'd' }
        val month = medium.indexOfFirst { it == 'M' || it == 'L' }
        return day >= 0 && (month < 0 || day < month)
    }
}

/** A compact two-line date badge for a date-only release. */
data class DayBadge(val top: String, val bottom: String)

/** Calendar/clock parts of a timestamp, read in one anchor's calendar. */
data class LocalParts(
    val y: Int,
    /** 1-12 */
    val mo: Int,
    val d: Int,
    /** 0-23 */
    val hour: Int,
    val minute: Int,
    /** 0 = Sunday .. 6 = Saturday */
    val wd: Int,
)

/**
 * The anchor, at the top level.
 *
 * The type is declared inside [Formatting] because that is where the two calendars live and how
 * the iOS source names it (`Formatting.TimeAnchor`); this alias is what every caller actually
 * writes, because an anchor is passed through half the model layer and `Formatting.TimeAnchor` at
 * every one of those sites is noise.
 */
typealias TimeAnchor = Formatting.TimeAnchor

/**
 * Which calendar a source's timestamps must be read in.
 *
 * TMDB air dates are DATE-ONLY facts the server carries as a synthesized 17:00 UTC instant, so
 * only their UTC calendar day is real; reading them locally put every timezone east of UTC+7 a day
 * ahead. AniList ships true instants.
 *
 * **Never branch on `source` at a formatting call site — pass this.** It lives here rather than on
 * `MediaSource` because it is a fact about calendars, not about catalogues, and because the one
 * place that decides it must be the one place that implements it.
 *
 * Note that `Episode.airDate` does NOT use it: an episode air date is date-only whatever the
 * franchise's source is (see `EPISODE_AIR_DATE_ANCHOR` in `Derived.kt`).
 */
val MediaSource.timeAnchor: TimeAnchor
    get() = if (this == MediaSource.TMDB) TimeAnchor.UTC_DATE else TimeAnchor.LOCAL

object Formatting {

    // Millisecond constants mirroring format.ts (D = 86400e3, H = 3600e3). One source of truth
    // with the wire-level substrate in Time.kt.
    const val D: Long = Time.DAY_MS
    const val H: Long = Time.HOUR_MS
    const val MINUTE_MS: Long = Time.MINUTE_MS

    /**
     * Which calendar a timestamp's day (and clock, if it has one) must be read in.
     * Derive it from a `MediaSource` via `source.timeAnchor` — never guess.
     */
    enum class TimeAnchor {
        /** A real instant: device-local calendar and clock. */
        LOCAL,

        /** A date-only fact carried as a synthesized 17:00 UTC instant — only its UTC day is real. */
        UTC_DATE;

        /** True when the timestamp has no meaningful clock, only a day. */
        val isDateOnly: Boolean get() = this == UTC_DATE

        /**
         * The zone this anchor reads in. [Formatting] uses its own cached copy of the device zone
         * rather than this accessor on the hot path; the property exists for callers that need the
         * zone directly.
         */
        val zoneId: ZoneId get() = if (this == UTC_DATE) ZoneOffset.UTC else ZoneId.systemDefault()
    }

    // MARK: - Caches (performance-load-bearing)
    //
    // The device zone and every formatter are built ONCE per (zone, locale, platform-pattern)
    // triple and reused. `localParts` building a calendar on every call cost 2.2 µs on iOS, and
    // the Schedule feed calls it 22 days × 2 passes × every airing show × ~30 times per render.
    // The cache re-keys itself when the zone, the locale or the 24-hour toggle changes, so a
    // travelling user never keeps yesterday's calendar and nobody keeps "9:00 PM" after flipping
    // the 24-Hour Time switch.

    private val lock = Any()
    private val cache = HashMap<String, DateTimeFormatter>()
    private var patternsRef: DateTimePatterns = JvmDateTimePatterns
    private var localZone: ZoneId = ZoneId.systemDefault()
    private var localeRef: Locale = Locale.getDefault()

    // The cache key, held as its three parts rather than one concatenated string: [refresh] runs
    // on every single call into this file, and building a String there would allocate on the
    // Schedule feed's hottest path for nothing.
    private var lastLocale: Locale? = null
    private var lastZoneId: String = ""
    private var lastPatternStamp: String = ""

    /** A zone id no platform can produce, so setting it forces the next [refresh] to rebuild. */
    private const val FORCE_REFRESH = "\u0000"

    /**
     * The platform pattern provider. Install the Android implementation once at app start, before
     * any screen composes; setting it drops every cached formatter.
     */
    var patterns: DateTimePatterns
        get() = synchronized(lock) { patternsRef }
        set(value) {
            synchronized(lock) {
                patternsRef = value
                lastZoneId = FORCE_REFRESH
                cache.clear()
            }
        }

    /**
     * Drop every cached zone and formatter. Call from the receiver for `ACTION_TIME_CHANGED`,
     * `ACTION_TIMEZONE_CHANGED` and `ACTION_LOCALE_CHANGED`. Changes to the default locale or zone
     * are also detected on their own; this is the escape hatch for anything that is not.
     */
    fun invalidate() {
        synchronized(lock) {
            lastZoneId = FORCE_REFRESH
            cache.clear()
        }
    }

    /** Current wall-clock time in ms since epoch. */
    fun nowMs(): Long = System.currentTimeMillis()

    /** Must be called under [lock]. */
    private fun refresh() {
        val loc = Locale.getDefault()
        val tz = TimeZone.getDefault()
        val patternStamp = patternsRef.stamp
        if (loc != lastLocale || tz.id != lastZoneId || patternStamp != lastPatternStamp) {
            lastLocale = loc
            lastZoneId = tz.id
            lastPatternStamp = patternStamp
            localZone = tz.toZoneId()
            localeRef = loc
            cache.clear()
        }
    }

    private fun zone(anchor: TimeAnchor): ZoneId = synchronized(lock) {
        refresh()
        if (anchor.isDateOnly) ZoneOffset.UTC else localZone
    }

    private fun locale(): Locale = synchronized(lock) {
        refresh()
        localeRef
    }

    /**
     * `skeleton` is a Unicode date-format template ("MMMd"); the empty string means the locale's
     * SHORT TIME pattern, which is what honours the 24-Hour Time setting.
     */
    private fun formatter(skeleton: String, anchor: TimeAnchor): DateTimeFormatter =
        synchronized(lock) {
            refresh()
            val z = if (anchor.isDateOnly) ZoneOffset.UTC else localZone
            val key = "$skeleton|${z.id}"
            cache.getOrPut(key) {
                val pattern =
                    if (skeleton.isEmpty()) patternsRef.shortTime(localeRef)
                    else patternsRef.best(skeleton, localeRef)
                DateTimeFormatter.ofPattern(pattern, localeRef).withZone(z)
            }
        }

    private fun string(ts: Long, skeleton: String, anchor: TimeAnchor): String =
        formatter(skeleton, anchor).format(Instant.ofEpochMilli(ts))

    private fun zoned(ts: Long, anchor: TimeAnchor): ZonedDateTime =
        Instant.ofEpochMilli(ts).atZone(zone(anchor))

    // MARK: - Calendar / parts

    /**
     * Break a ms-epoch timestamp into calendar/clock parts, read in [anchor]'s calendar.
     * [LocalParts.hour]/[LocalParts.minute] are only meaningful for [TimeAnchor.LOCAL] — a
     * UTC_DATE timestamp always reports the synthesized 17:00 and must never be shown or
     * thresholded on.
     */
    fun localParts(ts: Long, anchor: TimeAnchor = TimeAnchor.LOCAL): LocalParts {
        val z = zoned(ts, anchor)
        return LocalParts(
            y = z.year,
            mo = z.monthValue,
            d = z.dayOfMonth,
            hour = z.hour,
            minute = z.minute,
            // java.time's DayOfWeek is 1=Monday..7=Sunday; the app's `wd` is 0=Sun..6=Sat, so the
            // (col + 1) % 7 arithmetic everywhere below ports verbatim from iOS.
            wd = z.dayOfWeek.value % 7,
        )
    }

    /**
     * A UTC instant marking midnight of the calendar day containing [ts], read in [anchor].
     * Normalized into one shared space so day keys are comparable across anchors: the key of a
     * TMDB date-only timestamp (its UTC day) subtracts cleanly from the key of "now" (local day).
     */
    fun localDayKey(ts: Long, anchor: TimeAnchor = TimeAnchor.LOCAL): Long =
        zoned(ts, anchor).toLocalDate().toEpochDay() * D

    /** Midnight-UTC ms-epoch for a bare (y, mo, d) triple — the day-key builder. */
    private fun utcTimestamp(y: Int, mo: Int, d: Int): Long? = try {
        // Swift resolves the triple through Calendar.date(from:), which is LENIENT: a Feb 30 rolls
        // into March rather than failing. Adding the day count reproduces that, so a malformed
        // curated release string produces the same text on both platforms.
        LocalDate.of(y, mo, 1)
            .plusDays((d - 1).toLong())
            .atStartOfDay(ZoneOffset.UTC)
            .toInstant()
            .toEpochMilli()
    } catch (unparseable: DateTimeException) {
        null
    }

    /** Monday-first weekday index (0=Mon .. 6=Sun). */
    fun localMondayCol(ts: Long, anchor: TimeAnchor = TimeAnchor.LOCAL): Int =
        (localParts(ts, anchor).wd + 6) % 7

    // MARK: - Weekday names
    //
    // Names depend on the LOCALE only, never the time zone, so they always come off the device
    // locale regardless of which anchor the day itself was computed in.

    private fun weekdayName(wd: Int, style: TextStyle): String {
        if (wd !in 0..6) return ""
        // wd 0=Sun maps to DayOfWeek 7; 1..6 map to 1..6.
        return DayOfWeek.of(if (wd == 0) 7 else wd).getDisplayName(style, locale())
    }

    /** "Wed" */
    fun weekdayShort(wd: Int): String = weekdayName(wd, TextStyle.SHORT_STANDALONE)

    /** "Wed" for a Monday-first column (the day strip's and the day header's calendar). */
    fun weekdayShortMonFirst(col: Int): String = weekdayShort((col + 1) % 7)

    /**
     * "W" for a Monday-first column — the locale's own one-letter form, not the first character
     * of a name that has no reason to be Latin.
     */
    fun weekdayLetterMonFirst(col: Int): String =
        weekdayName((col + 1) % 7, TextStyle.NARROW_STANDALONE)

    private fun weekdayFull(wd: Int): String = weekdayName(wd, TextStyle.FULL_STANDALONE)

    /** col 0=Mon .. 6=Sun */
    fun weekdayNameMonFirst(col: Int): String = weekdayFull((col + 1) % 7)

    // MARK: - Countdown / clock (hour precision — LOCAL only)

    /**
     * Minute-precise wait ("2d 4h" / "31m" / "now"). A UTC_DATE timestamp has no clock to count
     * down to, so it degrades to the day-precision span instead of inventing hours.
     */
    fun fmtCountdown(target: Long, now: Long, anchor: TimeAnchor = TimeAnchor.LOCAL): String {
        if (anchor.isDateOnly) return fmtRelSpanShort(target, now, anchor)
        var s = maxOf(0L, target - now)
        if (s < MINUTE_MS) return "now"
        val d = s / D
        s -= d * D
        val h = s / H
        s -= h * H
        val m = s / MINUTE_MS
        if (d > 0) return "${d}d ${h}h"
        if (h > 0) return "${h}h ${m}m"
        return "${m}m"
    }

    /**
     * Locale-correct clock time ("9:00 PM", or "21:00" on a 24-hour device).
     * Empty for a UTC_DATE timestamp: its clock is synthesized, so there is no time to print.
     */
    fun fmtTime(ts: Long, anchor: TimeAnchor = TimeAnchor.LOCAL): String {
        if (anchor.isDateOnly) return ""
        return string(ts, "", anchor)
    }

    /**
     * Elapsed time since [ts]. Minute/hour precision for a real instant; a UTC_DATE timestamp
     * degrades to whole days ("today" / "3d ago") because its hours are fabricated.
     */
    fun fmtAgo(ts: Long, now: Long, anchor: TimeAnchor = TimeAnchor.LOCAL): String {
        if (anchor.isDateOnly) {
            val d = -dayDiff(ts, now, anchor)
            return if (d <= 0) "today" else "${d}d ago"
        }
        val s = maxOf(0L, now - ts)
        val m = s / MINUTE_MS
        if (m < 1) return "just now"
        if (m < 60) return "${m}m ago"
        val h = m / 60
        if (h < 24) return "${h}h ago"
        return "${h / 24}d ago"
    }

    // MARK: - Day words / day spans

    /**
     * Whole-DAY difference between two instants: 0 = same day, +1 = tomorrow, −1 = yesterday.
     * [ts] is read in [anchor]'s calendar; [now] is ALWAYS the device's local day (it *is* a real
     * instant). The single definition every day-word/day-span helper below is built on.
     */
    fun dayDiff(ts: Long, now: Long, anchor: TimeAnchor = TimeAnchor.LOCAL): Int {
        val a = localDayKey(ts, anchor)
        val b = localDayKey(now, TimeAnchor.LOCAL)
        // Both keys are exact multiples of a UTC day, so the quotient is exact even across a 23-
        // or 25-hour local day; the rounding is belt-and-braces, carried over from iOS.
        return ((a - b).toDouble() / D.toDouble()).roundToInt()
    }

    /** "Today" / "Tomorrow" / "Yesterday" / short weekday. */
    fun fmtDay(ts: Long, now: Long, anchor: TimeAnchor = TimeAnchor.LOCAL): String {
        val diff = dayDiff(ts, now, anchor)
        if (diff == 0) return "Today"
        if (diff == 1) return "Tomorrow"
        if (diff == -1) return "Yesterday"
        // NOTE: a date 30 days out reads "Thu". This function never produces a month-day.
        return weekdayShort(localParts(ts, anchor).wd)
    }

    /**
     * Day-only ("date, not time") word: Today / Tomorrow / Yesterday / full weekday within a week,
     * else "May 4". The long-weekday sibling of [fmtDay], and the only day label a date-only (TV)
     * release should ever use.
     *
     * The asymmetry is deliberate and load-bearing: **only FUTURE weekdays are named.** Every past
     * day from −2 back falls through to the month-day, which is why `TemporalCopy.aired` renders
     * "Aired Sep 2" (not "Aired Wednesday") and why `Copy.elapsedWord` fetches the past weekday
     * itself through [weekdayNameMonFirst].
     */
    fun fmtDayLong(ts: Long, now: Long, anchor: TimeAnchor = TimeAnchor.LOCAL): String {
        val diff = dayDiff(ts, now, anchor)
        if (diff == 0) return "Today"
        if (diff == 1) return "Tomorrow"
        if (diff == -1) return "Yesterday"
        if (diff > 1 && diff < 7) return weekdayFull(localParts(ts, anchor).wd)
        return fmtMonthDay(ts, anchor)
    }

    /**
     * The one "when does this land" label. Anime gets day + clock ("Tomorrow 9:00 PM"); a
     * date-only release gets a day word alone ("Tomorrow" / "Thursday" / "May 4").
     */
    fun fmtWhen(ts: Long, now: Long, anchor: TimeAnchor = TimeAnchor.LOCAL): String {
        if (anchor.isDateOnly) return fmtDayLong(ts, now, anchor)
        return "${fmtDay(ts, now, anchor)} ${fmtTime(ts, anchor)}"
    }

    /**
     * Relative day/week/month span for date-only releases — day precision only, never minutes:
     * "today" / "in 3d" / "in 2wk" / "in 2mo". The TV analogue of the anime [fmtCountdown].
     * Empty for a date already in the past: there is no span left to count down.
     */
    fun fmtRelSpan(ts: Long, now: Long, anchor: TimeAnchor = TimeAnchor.LOCAL): String {
        val short = fmtRelSpanShort(ts, now, anchor)
        if (short.isEmpty() || short == "today") return short
        return "in $short"
    }

    /**
     * Bare day-precision span with no "in " prefix — "today" / "1d" / "3d" / "2wk" / "2mo".
     * For trailing accents that supply their own context.
     *
     * A date in the PAST returns "" rather than "today". These spans describe a wait, and a
     * timestamp we have already passed describes none — a stale `nextAiringAt` that the source
     * hasn't advanced yet used to render as a permanent "today" (a week-old Saturday slot read
     * "Sat · today" every day since). Callers treat "" as "nothing to say".
     */
    fun fmtRelSpanShort(ts: Long, now: Long, anchor: TimeAnchor = TimeAnchor.LOCAL): String {
        val d = dayDiff(ts, now, anchor)
        if (d < 0) return ""
        if (d == 0) return "today"
        if (d < 7) return "${d}d"
        // Integer division rounding to nearest by adding half the divisor. Kotlin's Int division
        // truncates exactly as Swift's does, so this ports verbatim.
        if (d < 30) return "${(d + 3) / 7}wk"
        return "${maxOf(1, (d + 15) / 30)}mo"
    }

    /**
     * A compact two-line date badge for a date-only (TV) release — e.g. ("Sun", "in 4d"),
     * ("May 4", "in 2wk"), ("Today", "today").
     */
    fun fmtDayBadge(ts: Long, now: Long, anchor: TimeAnchor = TimeAnchor.LOCAL): DayBadge {
        val diff = dayDiff(ts, now, anchor)
        // Past dates have no countdown to give — "Jul 29 / today" would be a lie.
        if (diff < 0) return DayBadge("Aired", fmtMonthDay(ts, anchor))
        val top = when {
            diff == 0 -> "Today"
            diff == 1 -> "Tomorrow"
            diff > 1 && diff < 7 -> weekdayShort(localParts(ts, anchor).wd)
            else -> fmtMonthDay(ts, anchor)
        }
        return DayBadge(top, fmtRelSpan(ts, now, anchor))
    }

    // MARK: - Dates

    /** "May 4" — locale-ordered (a device set to en_GB reads "4 May"). */
    fun fmtMonthDay(ts: Long, anchor: TimeAnchor = TimeAnchor.LOCAL): String =
        string(ts, "MMMd", anchor)

    /** "Jun 24, 2026" — a year-qualified date, used for premieres that can be far in the future. */
    fun fmtFullDate(ts: Long, anchor: TimeAnchor = TimeAnchor.LOCAL): String =
        string(ts, "MMMdyyyy", anchor)

    /** "Oct 2026" — a month-precision date: Library's Returning captions and its month headers. */
    fun fmtMonthYear(ts: Long, anchor: TimeAnchor = TimeAnchor.LOCAL): String =
        string(ts, "MMMyyyy", anchor)

    /**
     * Prettify a curated release string from FranchiseUpcoming. A bare ISO date or year-month
     * becomes a friendly label ("2026-07-05" -> "Jul 5, 2026", "2026-10" -> "Oct 2026");
     * anything else (already-human windows like "October 2026", "2027", "TBA") passes through.
     * Parsed as a bare calendar date, so it is formatted in UTC and never shifts a day.
     */
    fun prettyReleaseString(raw: String): String {
        val s = raw.trim()
        // Swift's split(separator:) drops empty subsequences; Kotlin's keeps them, so filter.
        val parts = s.split("-").filter { it.isNotEmpty() }
        if (parts.size < 2) return s
        val y = parts[0].toIntOrNull() ?: return s
        val m = parts[1].toIntOrNull() ?: return s
        if (y !in 1000..9999 || m !in 1..12) return s
        if (parts.size >= 3) {
            val d = parts[2].toIntOrNull()
            if (d != null && d in 1..31) {
                val ts = utcTimestamp(y, m, d)
                if (ts != null) return fmtFullDate(ts, TimeAnchor.UTC_DATE)
            }
            return s
        }
        val ts = utcTimestamp(y, m, 1) ?: return s
        return string(ts, "MMMyyyy", TimeAnchor.UTC_DATE)
    }

    /** "Sunday, July 19" — the device's own today, so always local. */
    fun fmtTodayDate(now: Long): String = string(now, "EEEEMMMMd", TimeAnchor.LOCAL)

    /** Short-month "today" line for the Today header: "Sunday, Jul 19". */
    fun fmtTodayDateShort(now: Long): String = string(now, "EEEEMMMd", TimeAnchor.LOCAL)

    /**
     * The app's single definition of when "tonight"/"evening" starts, shared by the greeting,
     * Library's day-part label, and Schedule's hero eyebrow.
     */
    fun isEvening(hour: Int): Boolean = hour >= 18

    fun greetingFor(now: Long): String {
        val h = localParts(now, TimeAnchor.LOCAL).hour
        if (h < 5) return "Late night"
        if (h < 12) return "Good morning"
        if (!isEvening(h)) return "Good afternoon"
        return "Good evening"
    }

    // MARK: - Text

    private val TAG_RE = Regex("<[^>]+>")

    /**
     * The Unicode `White_Space=Yes` set, written out.
     *
     * The requirement is unchanged: `\s` must match what `NSRegularExpression`'s `\s` matches —
     * **including U+00A0**, which AniList descriptions are full of — where Java's bare `\s` is the
     * six ASCII characters and would leave a non-breaking space sitting in the middle of a
     * collapsed run.
     *
     * The obvious spelling, `(?U)\s+` (UNICODE_CHARACTER_CLASS), is a **JVM-only inline flag**.
     * Android's regex is ICU-backed and rejects it outright — `PatternSyntaxException: Syntax error
     * in regexp pattern near index 3` — thrown from this file's static initializer, so the first
     * screen that formatted a synopsis took the process down with an `ExceptionInInitializerError`.
     * It compiles clean in `:model`'s JVM tests, which is exactly why it reached a device.
     *
     * Enumerating the set is not a workaround, it is the portable statement of the same intent: one
     * literal class both engines read identically, with no dependency on flag support.
     */
    private const val UNICODE_WHITESPACE =
        "\\u0009-\\u000D\\u0020\\u0085\\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000"

    private val WHITESPACE_RE = Regex("[$UNICODE_WHITESPACE]+")

    private val NUMERIC_ENTITY_RE = Regex("&#(x[0-9A-Fa-f]+|[0-9]+);")

    /**
     * The HTML entities that actually occur in AniList descriptions, in decode order.
     * `&amp;` MUST stay last so `&amp;lt;` yields `&lt;`, not `<`.
     */
    private val NAMED_ENTITIES = listOf(
        "&lt;" to "<",
        "&gt;" to ">",
        "&quot;" to "\"",
        "&apos;" to "'",
        "&nbsp;" to " ", // a plain space, deliberately NOT U+00A0
        "&mdash;" to "—",
        "&ndash;" to "–",
        "&hellip;" to "…",
        "&lsquo;" to "‘",
        "&rsquo;" to "’",
        "&ldquo;" to "“",
        "&rdquo;" to "”",
        "&amp;" to "&", // must stay last
    )

    /**
     * Strip HTML tags and decode entities from a synopsis. Returns the FULL cleaned text —
     * visual clamping (maxLines + "Read more") is the view's job, not a data-layer truncation.
     *
     * Do NOT substitute `HtmlCompat.fromHtml`: it decodes a different entity set, emits a Spanned
     * with paragraph breaks, and does not collapse whitespace the same way.
     */
    fun stripHtml(s: String?): String {
        if (s.isNullOrEmpty()) return ""
        val noTags = TAG_RE.replace(s, "")
        val decoded = decodeHtmlEntities(noTags)
        val collapsed = WHITESPACE_RE.replace(decoded, " ")
        // Kotlin's Char.isWhitespace() reports false for U+00A0; Swift's .whitespacesAndNewlines
        // includes it, so trim it explicitly.
        return collapsed.trim { it.isWhitespace() || it == '\u00A0' }
    }

    /** Decode numeric character references first, then the named list in its fixed order. */
    fun decodeHtmlEntities(s: String): String {
        if (!s.contains('&')) return s
        var out = decodeNumericEntities(s)
        for ((entity, char) in NAMED_ENTITIES) {
            out = out.replace(entity, char)
        }
        return out
    }

    /** Decode `&#8217;` / `&#x2019;` style references. An invalid scalar drops the reference. */
    private fun decodeNumericEntities(s: String): String {
        if (!s.contains("&#")) return s
        return NUMERIC_ENTITY_RE.replace(s) { m ->
            val code = m.groupValues[1]
            val value =
                if (code.startsWith("x")) code.drop(1).toLongOrNull(16) else code.toLongOrNull()
            if (value != null && value <= 0x10FFFFL && value !in 0xD800L..0xDFFFL) {
                String(Character.toChars(value.toInt()))
            } else {
                ""
            }
        }
    }
}
