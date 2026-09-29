package com.cindy.tracker

import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters

/**
 * Which days were trained, and how many of them ran back to back.
 *
 * Days are local days, not 24-hour blocks: a workout at 23:50 and one at 00:10 are two days
 * apart by the calendar the athlete lives in, which is the one that matters for a streak.
 *
 * Free of Android types so the boundary rules — and they are all boundary rules — can be tested.
 */
object Streak {

    /** The distinct local dates on which any attempt was recorded. */
    fun daysTrained(attempts: List<Attempt>, zone: ZoneId): Set<LocalDate> =
        attempts.mapTo(mutableSetOf()) {
            Instant.ofEpochMilli(it.atMillis).atZone(zone).toLocalDate()
        }

    /**
     * The run of consecutive days ending today, or yesterday.
     *
     * Yesterday counts because a streak should not be reported as broken by a day the athlete
     * has not finished living yet — at nine in the morning, "3 days" is the truth and "0" is
     * a lie that would also be undone by training that afternoon.
     */
    fun current(days: Set<LocalDate>, today: LocalDate): Int {
        val from = when {
            days.contains(today) -> today
            days.contains(today.minusDays(1)) -> today.minusDays(1)
            else -> return 0
        }
        var count = 0
        var day = from
        while (days.contains(day)) {
            count++
            day = day.minusDays(1)
        }
        return count
    }

    /** The longest run of consecutive days ever recorded. */
    fun longest(days: Set<LocalDate>): Int {
        if (days.isEmpty()) return 0
        var best = 0
        for (day in days) {
            // Count each run once, from the end that has no day before it.
            if (days.contains(day.minusDays(1))) continue
            var length = 0
            var cursor = day
            while (days.contains(cursor)) {
                length++
                cursor = cursor.plusDays(1)
            }
            if (length > best) best = length
        }
        return best
    }

    /** True when training today would extend the current streak rather than start a new one. */
    fun atRisk(days: Set<LocalDate>, today: LocalDate): Boolean =
        !days.contains(today) && days.contains(today.minusDays(1))

    /** Streak lengths worth saying out loud, in days. */
    val DAILY_MILESTONES = listOf(3, 7, 14, 21, 30, 50, 75, 100, 150, 200, 365)

    /** The same for the weekly streak, in weeks. */
    val WEEKLY_MILESTONES = listOf(2, 4, 8, 12, 26, 52)

    /** The first day of the week [date] falls in, where the locale says weeks start. */
    fun weekStart(date: LocalDate, firstDayOfWeek: DayOfWeek): LocalDate =
        date.with(TemporalAdjusters.previousOrSame(firstDayOfWeek))

    /** The start of every week in which any day was trained. */
    fun weeksTrained(days: Set<LocalDate>, firstDayOfWeek: DayOfWeek): Set<LocalDate> =
        days.mapTo(mutableSetOf()) { weekStart(it, firstDayOfWeek) }

    /**
     * The run of consecutive trained weeks ending this week, or last week.
     *
     * Last week counts for the same reason yesterday does in [current]: this week is not over, so
     * a run that reached last week is not broken yet, merely not extended.
     */
    fun currentWeeks(weeks: Set<LocalDate>, today: LocalDate, firstDayOfWeek: DayOfWeek): Int {
        val thisWeek = weekStart(today, firstDayOfWeek)
        val from = when {
            weeks.contains(thisWeek) -> thisWeek
            weeks.contains(thisWeek.minusWeeks(1)) -> thisWeek.minusWeeks(1)
            else -> return 0
        }
        var count = 0
        var week = from
        while (weeks.contains(week)) {
            count++
            week = week.minusWeeks(1)
        }
        return count
    }

    /** The longest run of consecutive trained weeks ever recorded. */
    fun longestWeeks(weeks: Set<LocalDate>): Int {
        var best = 0
        for (week in weeks) {
            // Count each run once, from the end that has no week before it.
            if (weeks.contains(week.minusWeeks(1))) continue
            var length = 0
            var cursor = week
            while (weeks.contains(cursor)) {
                length++
                cursor = cursor.plusWeeks(1)
            }
            if (length > best) best = length
        }
        return best
    }

    /** True when this week has no session yet but last week did. */
    fun weekAtRisk(weeks: Set<LocalDate>, today: LocalDate, firstDayOfWeek: DayOfWeek): Boolean {
        val thisWeek = weekStart(today, firstDayOfWeek)
        return !weeks.contains(thisWeek) && weeks.contains(thisWeek.minusWeeks(1))
    }

    /** The days of the current daily streak (see [current]), for painting; empty if none. */
    fun currentRun(days: Set<LocalDate>, today: LocalDate): Set<LocalDate> {
        val from = when {
            days.contains(today) -> today
            days.contains(today.minusDays(1)) -> today.minusDays(1)
            else -> return emptySet()
        }
        val run = mutableSetOf<LocalDate>()
        var day = from
        while (days.contains(day)) {
            run.add(day)
            day = day.minusDays(1)
        }
        return run
    }

    /** First and last day of the longest daily run; the most recent one on a tie; null if none. */
    fun longestRun(days: Set<LocalDate>): ClosedRange<LocalDate>? {
        var best: ClosedRange<LocalDate>? = null
        var bestLength = 0L
        for (day in days.sorted()) {
            if (days.contains(day.minusDays(1))) continue
            var end = day
            while (days.contains(end.plusDays(1))) end = end.plusDays(1)
            val length = ChronoUnit.DAYS.between(day, end) + 1
            // Sorted oldest first, so >= lets a later run win a tie.
            if (length >= bestLength) {
                best = day..end
                bestLength = length
            }
        }
        return best
    }

    /** First and last week start of the longest weekly run; most recent on a tie; null if none. */
    fun longestWeeksRun(weeks: Set<LocalDate>): ClosedRange<LocalDate>? {
        var best: ClosedRange<LocalDate>? = null
        var bestLength = 0L
        for (week in weeks.sorted()) {
            if (weeks.contains(week.minusWeeks(1))) continue
            var end = week
            while (weeks.contains(end.plusWeeks(1))) end = end.plusWeeks(1)
            val length = ChronoUnit.WEEKS.between(week, end) + 1
            if (length >= bestLength) {
                best = week..end
                bestLength = length
            }
        }
        return best
    }

    /** The first milestone above [current], or null past the last one. */
    fun nextMilestone(current: Int, milestones: List<Int>): Int? =
        milestones.firstOrNull { it > current }

    /** Whether [current] lands exactly on a milestone. */
    fun isMilestone(current: Int, milestones: List<Int>): Boolean = current in milestones
}
