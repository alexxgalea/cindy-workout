package com.cindy.tracker

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

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
}
