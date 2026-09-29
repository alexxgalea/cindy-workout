package com.cindy.tracker

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId

/** Something the results screen celebrates. [kind] picks the icon. */
data class Celebration(val kind: Kind, val text: String) {
    enum class Kind { FIRST, RECORD, DAILY, WEEKLY }
}

/**
 * The encouraging sentences of the progress report and the results screen.
 *
 * Every line is literally true for the data it is given, and none of them scolds: a lapsed
 * streak is met with an invitation, never a reproach. Pure, so the wording can be tested.
 */
object Cheer {

    private fun unit(n: Int, noun: String): String = if (n == 1) noun else "${noun}s"

    private fun plural(n: Int, noun: String): String = "$n ${unit(n, noun)}"

    /** The line the progress report opens with. Always true; never a guilt trip. */
    fun headline(
        attempts: List<Attempt>, today: LocalDate, zone: ZoneId, firstDayOfWeek: DayOfWeek
    ): String {
        // Rule 1: nothing recorded yet.
        val latest = attempts.maxByOrNull { it.atMillis }
            ?: return "Your first Cindy starts everything."
        val days = Streak.daysTrained(attempts, zone)
        val current = Streak.current(days, today)
        val longest = Streak.longest(days)
        val weeks = Streak.weeksTrained(days, firstDayOfWeek)
        val w = Streak.currentWeeks(weeks, today, firstDayOfWeek)
        val trainedToday = today in days
        val s = Progress.summary(attempts, today, zone, firstDayOfWeek)

        val latestIsToday = Progress.localDate(latest, zone) == today
        if (latestIsToday && Records.isPersonalRecord(attempts, latest)) {
            return "New personal record: ${latest.scoreLabel()}."
        }
        if (trainedToday && Streak.isMilestone(current, Streak.DAILY_MILESTONES)) {
            return "$current days in a row."
        }
        if (trainedToday && current >= 2 && current == longest) {
            return "Longest streak yet: $current days."
        }
        if (Streak.atRisk(days, today) && current >= 1) {
            return "Train today to make it ${current + 1} days."
        }
        if (Streak.weekStart(today, firstDayOfWeek) in weeks && w >= 2) {
            return "$w weeks in a row."
        }
        if (Streak.weekAtRisk(weeks, today, firstDayOfWeek) && w >= 1) {
            return "A session this week makes it ${w + 1} weeks in a row."
        }
        if (s.thisWeek.sessions >= 1 && s.thisWeek.sessions > s.lastWeek.sessions) {
            val diff = s.thisWeek.sessions - s.lastWeek.sessions
            return "${plural(s.thisWeek.sessions, "session")} this week, $diff more than last week."
        }
        val own = Records.inCategory(attempts, latest.profile)
        val first = own.minByOrNull { it.atMillis } ?: latest
        val best = Records.bestIn(attempts, latest.profile) ?: latest
        val delta = best.totalReps - first.totalReps
        if (delta > 0) {
            return "Your best is $delta reps above your first " +
                "${latest.profile?.mode?.label ?: "session"}."
        }
        return "Your best is ${best.scoreLabel()}."
    }

    /** What the next milestone costs, or null. Shown under the streak numbers. */
    fun nextStep(
        attempts: List<Attempt>, today: LocalDate, zone: ZoneId, firstDayOfWeek: DayOfWeek
    ): String? {
        val days = Streak.daysTrained(attempts, zone)
        val current = Streak.current(days, today)
        val weeks = Streak.weeksTrained(days, firstDayOfWeek)
        val w = Streak.currentWeeks(weeks, today, firstDayOfWeek)
        if (current >= 1) {
            Streak.nextMilestone(current, Streak.DAILY_MILESTONES)?.let { m ->
                return "${m - current} more ${unit(m - current, "day")} to a $m-day streak."
            }
        }
        if (w >= 1) {
            Streak.nextMilestone(w, Streak.WEEKLY_MILESTONES)?.let { m ->
                return "${m - w} more ${unit(m - w, "week")} to a $m-week streak."
            }
        }
        return null
    }

    /** Up to two celebrations for the results screen, most important first. */
    fun forResult(
        attempts: List<Attempt>, attempt: Attempt, zone: ZoneId, firstDayOfWeek: DayOfWeek
    ): List<Celebration> {
        // Zero-rep attempts are never stored, so an attempt that is not here was not saved.
        if (attempts.none { it.atMillis == attempt.atMillis }) return emptyList()
        val before = attempts.filter { it.atMillis != attempt.atMillis }
        val day = Progress.localDate(attempt, zone)
        if (before.isEmpty()) {
            return listOf(Celebration(Celebration.Kind.FIRST, "First Cindy on the board."))
        }
        val out = ArrayList<Celebration>()
        if (Records.isPersonalRecord(attempts, attempt)) {
            out += Celebration(Celebration.Kind.RECORD, "New personal record.")
        }
        val daysBefore = Streak.daysTrained(before, zone)
        if (day !in daysBefore) {
            val after = Streak.current(Streak.daysTrained(attempts, zone), day)
            if (Streak.isMilestone(after, Streak.DAILY_MILESTONES)) {
                out += Celebration(Celebration.Kind.DAILY, "$after days in a row.")
            } else if (after >= 2 && after > Streak.longest(daysBefore)) {
                out += Celebration(Celebration.Kind.DAILY, "Longest streak yet: $after days.")
            }
        }
        val weeksBefore = Streak.weeksTrained(daysBefore, firstDayOfWeek)
        if (Streak.weekStart(day, firstDayOfWeek) !in weeksBefore) {
            val weeksAfter = Streak.weeksTrained(Streak.daysTrained(attempts, zone), firstDayOfWeek)
            val wAfter = Streak.currentWeeks(weeksAfter, day, firstDayOfWeek)
            if (Streak.isMilestone(wAfter, Streak.WEEKLY_MILESTONES)) {
                out += Celebration(Celebration.Kind.WEEKLY, "$wAfter weeks in a row.")
            }
        }
        return out.take(2)
    }
}
