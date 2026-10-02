package com.cindy.tracker

import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.roundToInt

/** What the progress chart can plot. */
enum class ProgressMetric(val label: String) { SCORE("Score"), PACE("Pace"), VOLUME("Volume") }

/** How far back the chart looks. */
enum class ProgressRange(val label: String) {
    MONTH("1M"), QUARTER("3M"), YEAR("1Y"), ALL("All");

    /** The first local date inside the range, or null for everything. */
    fun start(today: LocalDate): LocalDate? = when (this) {
        MONTH -> today.minusMonths(1)
        QUARTER -> today.minusMonths(3)
        YEAR -> today.minusYears(1)
        ALL -> null
    }
}

/** One plotted value. */
data class ProgressPoint(
    /** The attempt's time, or local midnight at the start of the week for a volume bar. */
    val atMillis: Long,
    /** Reps (score), seconds per round (pace) or reps in the week (volume). */
    val value: Double,
    /** A personal record at the moment it was set. */
    val record: Boolean = false,
    val lowerBound: Boolean = false,
    /** The attempt behind a line point; null for a volume bar. */
    val attempt: Attempt? = null,
    /** Sessions in the week, for a volume bar. */
    val sessions: Int = 0
)

/** Points plus the best-so-far value at each of them, measured over the whole history. */
data class Series(
    val points: List<ProgressPoint>,
    val best: List<Double>,
    val lowerIsBetter: Boolean
)

/** Totals over a stretch of days. */
data class Period(val sessions: Int, val reps: Int, val clockMs: Long)

data class WeekSummary(val thisWeek: Period, val lastWeek: Period, val thisMonth: Period)

/**
 * The numbers behind the progress chart and the "this week" card.
 *
 * Pure: no clock, no zone of its own. Scores are only ever compared within one category, and a
 * lower-bound attempt is plotted but never claims a record, as in [Records].
 */
object Progress {
    /**
     * A session that ran the whole clock. Only these can set a pace, which fresh rounds would
     * flatter. Twenty minutes less a second of slack; Coach's companion is private.
     */
    const val FULL_SESSION_MS = 20 * 60_000L - 1_000L

    fun isFullSession(a: Attempt): Boolean = a.durationMs >= FULL_SESSION_MS

    fun localDate(a: Attempt, zone: ZoneId): LocalDate =
        Instant.ofEpochMilli(a.atMillis).atZone(zone).toLocalDate()

    /** Every category trained, most recently used first. */
    fun categories(attempts: List<Attempt>): List<CindyProfile?> =
        attempts.sortedByDescending { it.atMillis }.map { it.profile }.distinct()

    /** The category of the latest attempt — what the athlete is training now. */
    fun defaultCategory(attempts: List<Attempt>): CindyProfile? =
        attempts.maxByOrNull { it.atMillis }?.profile

    /**
     * Reps per attempt in one category. A lower-bound score does raise the bar, because the
     * true score was at least that, exactly as [Records.personalRecord] treats it.
     */
    fun scoreSeries(
        attempts: List<Attempt>, category: CindyProfile?, from: LocalDate?, zone: ZoneId
    ): Series {
        val own = attempts.filter { it.profile == category }.sortedBy { it.atMillis }
        var best = Int.MIN_VALUE
        val points = ArrayList<ProgressPoint>()
        val bests = ArrayList<Double>()
        val dates = ArrayList<LocalDate>()
        for (a in own) {
            val record = !a.scoreIsLowerBound && a.totalReps > 0 && a.totalReps > best
            best = max(best, a.totalReps)
            points += ProgressPoint(
                a.atMillis, a.totalReps.toDouble(), record, a.scoreIsLowerBound, a
            )
            bests += best.toDouble()
            dates += localDate(a, zone)
        }
        return cut(points, bests, dates, from, lowerIsBetter = false)
    }

    /**
     * Seconds per round, full sessions only, where faster is better. A lower-bound pace never
     * sets the bar, because unlike a score it says nothing about how fast the athlete really
     * was. It is still plotted, and before any exact attempt its own value stands in for the
     * displayed best so the line stays finite.
     */
    fun paceSeries(
        attempts: List<Attempt>, category: CindyProfile?, from: LocalDate?, zone: ZoneId
    ): Series {
        val own = attempts
            .filter { it.profile == category && isFullSession(it) && it.avgRoundMs != null }
            .sortedBy { it.atMillis }
        var best = Double.MAX_VALUE
        val points = ArrayList<ProgressPoint>()
        val bests = ArrayList<Double>()
        val dates = ArrayList<LocalDate>()
        for (a in own) {
            val seconds = (a.avgRoundMs ?: continue) / 1000.0
            val record = !a.scoreIsLowerBound && seconds < best
            if (!a.scoreIsLowerBound) best = minOf(best, seconds)
            points += ProgressPoint(a.atMillis, seconds, record, a.scoreIsLowerBound, a)
            bests += if (best == Double.MAX_VALUE) seconds else best
            dates += localDate(a, zone)
        }
        return cut(points, bests, dates, from, lowerIsBetter = true)
    }

    /** Drops points (and their best-so-far entries together) dated before [from]. */
    private fun cut(
        points: List<ProgressPoint>, bests: List<Double>, dates: List<LocalDate>,
        from: LocalDate?, lowerIsBetter: Boolean
    ): Series {
        val keep = points.indices.filter { from == null || !dates[it].isBefore(from) }
        return Series(keep.map { points[it] }, keep.map { bests[it] }, lowerIsBetter)
    }

    /**
     * Reps per week, across all categories — volume is work done, not a comparison. Weeks with
     * no session are kept so that a week off shows as a gap.
     */
    fun weeklyVolume(
        attempts: List<Attempt>, from: LocalDate?, today: LocalDate, zone: ZoneId,
        firstDayOfWeek: DayOfWeek
    ): List<ProgressPoint> {
        if (attempts.isEmpty()) return emptyList()
        val dated = attempts.map { localDate(it, zone) to it }
        val first = from ?: dated.minOf { it.first }
        val last = Streak.weekStart(today, firstDayOfWeek)
        val out = ArrayList<ProgressPoint>()
        var week = Streak.weekStart(first, firstDayOfWeek)
        while (!week.isAfter(last)) {
            val end = week.plusDays(7)
            val inWeek = dated.filter { !it.first.isBefore(week) && it.first.isBefore(end) }
            out += ProgressPoint(
                atMillis = week.atStartOfDay(zone).toInstant().toEpochMilli(),
                value = inWeek.sumOf { it.second.totalReps }.toDouble(),
                sessions = inWeek.size
            )
            week = end
        }
        return out
    }

    fun summary(
        attempts: List<Attempt>, today: LocalDate, zone: ZoneId, firstDayOfWeek: DayOfWeek
    ): WeekSummary {
        val thisStart = Streak.weekStart(today, firstDayOfWeek)
        val lastStart = thisStart.minusDays(7)
        val month = YearMonth.from(today)
        val dated = attempts.map { localDate(it, zone) to it }
        fun period(match: (LocalDate) -> Boolean): Period {
            val hit = dated.filter { match(it.first) }.map { it.second }
            return Period(hit.size, hit.sumOf { it.totalReps }, hit.sumOf { it.durationMs })
        }
        return WeekSummary(
            thisWeek = period { !it.isBefore(thisStart) && it.isBefore(thisStart.plusDays(7)) },
            lastWeek = period { !it.isBefore(lastStart) && it.isBefore(thisStart) },
            thisMonth = period { YearMonth.from(it) == month }
        )
    }

    /** Round axis values in 1-2-5 steps that cover [min]..[max]. */
    fun niceTicks(min: Double, max: Double, maxTicks: Int = 4): List<Double> {
        if (max - min < 1e-9) {
            val pad = max(1.0, abs(min) * 0.05)
            return niceTicks(min - pad, max + pad, maxTicks)
        }
        val raw = (max - min) / maxTicks
        val mag = 10.0.pow(floor(log10(raw)))
        val norm = raw / mag
        val step = mag * when {
            norm <= 1 -> 1.0
            norm <= 2 -> 2.0
            norm <= 5 -> 5.0
            else -> 10.0
        }
        val lo = floor(min / step) * step
        val hi = ceil(max / step) * step
        val out = ArrayList<Double>()
        var i = 0
        while (lo + i * step <= hi + step * 1e-9) {
            out += lo + i * step
            i++
        }
        return out
    }

    /** Index of the value in ascending [xs] closest to [x]; a tie goes to the lower index. */
    fun nearestIndex(xs: List<Float>, x: Float): Int {
        if (xs.isEmpty()) return -1
        var lo = 0
        var hi = xs.size
        while (lo < hi) {
            val mid = (lo + hi) ushr 1
            if (xs[mid] < x) lo = mid + 1 else hi = mid
        }
        if (lo == 0) return 0
        if (lo == xs.size) return xs.size - 1
        return if (x - xs[lo - 1] <= xs[lo] - x) lo - 1 else lo
    }

    private fun plural(n: Int, word: String) = "$n $word${if (n == 1) "" else "s"}"

    private fun shortDate(atMillis: Long, zone: ZoneId): String =
        DateTimeFormatter.ofPattern("d MMM", Locale.US)
            .format(Instant.ofEpochMilli(atMillis).atZone(zone))

    private fun pace(seconds: Double): String = formatDuration((seconds * 1000).toLong())

    /** What the readout says about point [i]: a headline and a detail line. */
    fun describe(
        metric: ProgressMetric, points: List<ProgressPoint>, i: Int, zone: ZoneId
    ): Pair<String, String> {
        val p = points[i]
        val before = points.getOrNull(i - 1)
        val date = shortDate(p.atMillis, zone)
        val parts = ArrayList<String>()
        return when (metric) {
            ProgressMetric.SCORE -> {
                val label = p.attempt?.scoreLabel() ?: "${p.value.roundToInt()}"
                parts += "${p.value.roundToInt()} reps"
                if (p.record) parts += "personal record"
                if (p.lowerBound) parts += "at least — camera lost you"
                parts += if (before == null) "first in this range" else {
                    val d = p.value.roundToInt() - before.value.roundToInt()
                    when {
                        d > 0 -> "+$d on the session before"
                        d < 0 -> "${-d} below the session before"
                        else -> "level with the session before"
                    }
                }
                "$date · $label" to parts.joinToString(" · ")
            }
            ProgressMetric.PACE -> {
                if (p.record) parts += "fastest yet"
                parts += if (before == null) "first in this range" else {
                    // Seconds per round: a smaller number is faster.
                    val d = (before.value - p.value).roundToInt()
                    when {
                        d > 0 -> "${d}s faster than the session before"
                        d < 0 -> "${-d}s slower than the session before"
                        else -> "same pace as the session before"
                    }
                }
                "$date · ${pace(p.value)} a round" to parts.joinToString(" · ")
            }
            ProgressMetric.VOLUME ->
                "Week of $date" to
                    "${formatReps(p.value.roundToInt())} reps · " +
                    plural(p.sessions, "session")
        }
    }

    /** What the readout says when nothing is selected. */
    fun overview(metric: ProgressMetric, points: List<ProgressPoint>): Pair<String, String> {
        if (points.isEmpty()) return "No sessions in this range" to ""
        return when (metric) {
            ProgressMetric.SCORE -> {
                val pool = points.filter { !it.lowerBound }.ifEmpty { points }
                val top = pool.maxByOrNull { it.value }!!
                val label = top.attempt?.scoreLabel() ?: "${top.value.roundToInt()}"
                "Best $label" to "${plural(points.size, "session")} in this range"
            }
            ProgressMetric.PACE -> {
                val top = points.minByOrNull { it.value }!!
                "Best ${pace(top.value)} a round" to
                    "${plural(points.size, "full session")} in this range"
            }
            ProgressMetric.VOLUME -> {
                val reps = points.sumOf { it.value }.roundToInt()
                "${formatReps(reps)} reps" to
                    "${plural(points.sumOf { it.sessions }, "session")} in this range"
            }
        }
    }

    fun formatReps(n: Int): String = String.format(Locale.US, "%,d", n)

    /** "42 min", or "1 h 02 min" from an hour up; minutes rounded down. */
    fun formatClock(ms: Long): String {
        val minutes = ms / 60_000L
        return if (minutes < 60) "$minutes min"
        else String.format(Locale.US, "%d h %02d min", minutes / 60, minutes % 60)
    }

    /** "+3" or "−3" (U+2212); null when nothing changed. */
    fun formatDelta(n: Int): String? = when {
        n > 0 -> "+$n"
        n < 0 -> "−${-n}"
        else -> null
    }
}
