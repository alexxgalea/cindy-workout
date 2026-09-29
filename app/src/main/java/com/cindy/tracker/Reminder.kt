package com.cindy.tracker

import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale

/**
 * When the daily reminder fires and what it says.
 *
 * Pure: the clock, the zone and the first day of the week are all parameters, so daylight-saving
 * changes and the "already trained today" rule can be tested without a phone.
 */
object Reminder {
    /** Six in the evening: late enough that a morning session has already cancelled it. */
    const val DEFAULT_MINUTE_OF_DAY = 18 * 60

    /** Delivered later than this, a reminder is about a moment that has passed. */
    const val LATE_LIMIT_MS = 2 * 60 * 60 * 1000L

    /** How early an alarm may arrive and still count as on time. */
    private const val EARLY_LIMIT_MS = 60_000L

    data class Message(val title: String, val body: String)

    /**
     * The next time at [minuteOfDay] strictly after [now], in [now]'s zone.
     *
     * `atZone` already moves a time inside a spring-forward gap to the hour after it, and picks
     * the earlier offset when a fall-back hour happens twice, so no special cases are needed.
     */
    fun nextFire(now: ZonedDateTime, minuteOfDay: Int): ZonedDateTime {
        fun on(date: LocalDate) =
            date.atTime(minuteOfDay / 60, minuteOfDay % 60).atZone(now.zone)
        val today = on(now.toLocalDate())
        return if (today.isAfter(now)) today else on(now.toLocalDate().plusDays(1))
    }

    /** Whether an alarm meant for [targetMillis] is still worth posting at [nowMillis]. */
    fun shouldPost(targetMillis: Long, nowMillis: Long, zone: ZoneId): Boolean {
        if (targetMillis <= 0L) return false
        if (nowMillis - targetMillis !in -EARLY_LIMIT_MS..LATE_LIMIT_MS) return false
        val target = Instant.ofEpochMilli(targetMillis).atZone(zone).toLocalDate()
        val now = Instant.ofEpochMilli(nowMillis).atZone(zone).toLocalDate()
        return target == now
    }

    /** What to say today, or null when today is already trained. */
    fun message(
        attempts: List<Attempt>, today: LocalDate, zone: ZoneId, firstDayOfWeek: DayOfWeek
    ): Message? {
        val days = Streak.daysTrained(attempts, zone)
        // Rule 1: nothing to remind about.
        if (today in days) return null
        // Rule 2: nothing recorded yet.
        val latest = attempts.maxByOrNull { it.atMillis } ?: return Message(
            "Time for your first Cindy",
            "Twenty minutes: 5 pull-ups, 10 push-ups, 15 squats, as many rounds as you can."
        )
        val current = Streak.current(days, today)
        val atRisk = Streak.atRisk(days, today)
        // Rule 3.
        if (atRisk && current >= 2) {
            return Message(
                "Keep your $current-day streak going",
                "Train today and it's ${current + 1}."
            )
        }
        // Rule 4.
        if (atRisk && current == 1) {
            return Message(
                "Make it two days in a row",
                "You trained yesterday. Twenty minutes today starts a streak."
            )
        }
        // Rule 5: only on the last day of the week, so it never nags early in the week.
        val weeks = Streak.weeksTrained(days, firstDayOfWeek)
        if (Streak.weekAtRisk(weeks, today, firstDayOfWeek) &&
            today.plusDays(1).dayOfWeek == firstDayOfWeek
        ) {
            val w = Streak.currentWeeks(weeks, today, firstDayOfWeek)
            return Message(
                "Last day to keep your $w-week streak",
                "One session today and it's ${w + 1} weeks."
            )
        }
        // Rule 6.
        val best = Records.bestIn(attempts, latest.profile) ?: latest
        return Message(
            "Cindy's ready when you are",
            "Your best is ${best.scoreLabel()}. Twenty minutes to chase it."
        )
    }

    /** What a reminder would say today, as if today had not been trained. For TRY IT. */
    fun preview(
        attempts: List<Attempt>, today: LocalDate, zone: ZoneId, firstDayOfWeek: DayOfWeek
    ): Message {
        val untrainedToday = attempts.filter { Progress.localDate(it, zone) != today }
        // Never null in practice, but the type allows it; a fallback beats a crash in a demo.
        return message(untrainedToday, today, zone, firstDayOfWeek)
            ?: Message("Cindy's ready when you are", "Twenty minutes, as many rounds as you can.")
    }

    /** "18:00", or "6:00 PM" on a 12-hour phone. */
    fun formatTime(minuteOfDay: Int, is24Hour: Boolean): String {
        val h = minuteOfDay / 60
        val m = minuteOfDay % 60
        if (is24Hour) return String.format(Locale.US, "%02d:%02d", h, m)
        val hour12 = if (h % 12 == 0) 12 else h % 12
        return String.format(Locale.US, "%d:%02d %s", hour12, m, if (h < 12) "AM" else "PM")
    }
}
