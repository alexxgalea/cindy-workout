package com.cindy.tracker

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** One trophy. [rank] 1..3 picks the medal. */
data class Peak(val title: String, val value: String, val detail: String, val rank: Int)

/**
 * The personal-best board, built only from what is already recorded.
 *
 * Pure: no clock, no zone of its own. Scores, rounds and paces are compared within one category
 * and never from a lower-bound attempt, which only says "at least". Streaks and weekly volume
 * are work done rather than a comparison, so they look at every attempt.
 */
object Peaks {
    private val dateFormat = DateTimeFormatter.ofPattern("d MMM yyyy", Locale.US)

    /** Every trophy, in display order. Empty when there are no attempts. */
    fun of(
        attempts: List<Attempt>, category: CindyProfile?, today: LocalDate, zone: ZoneId,
        firstDayOfWeek: DayOfWeek
    ): List<Peak> {
        val out = ArrayList<Peak>()
        val clean = attempts.filter { it.profile == category && !it.scoreIsLowerBound }
        fun date(a: Attempt) = dateFormat.format(Progress.localDate(a, zone))

        val titles = listOf("Best score", "2nd best", "3rd best")
        Records.ranked(clean).take(3).forEachIndexed { i, a ->
            out += Peak(
                titles[i], a.scoreLabel(),
                "${date(a)} · ${Progress.formatReps(a.totalReps)} reps", i + 1
            )
        }

        // Newest first, so minByOrNull keeps the more recent attempt on a tie.
        val newestFirst = clean.sortedByDescending { it.atMillis }
        var fastest: Pair<Attempt, Int>? = null
        for (a in newestFirst) {
            val ms = a.fastestRoundMs ?: continue
            val best = fastest?.let { it.first.roundSplitsMs[it.second] }
            if (best == null || ms < best) fastest = a to a.roundSplitsMs.indexOf(ms)
        }
        fastest?.let { (a, index) ->
            out += Peak(
                "Fastest round", formatDuration(a.roundSplitsMs[index]),
                "${date(a)} · round ${index + 1}", 1
            )
        }

        newestFirst
            .filter { Progress.isFullSession(it) && it.avgRoundMs != null }
            .minByOrNull { it.avgRoundMs!! }
            ?.let { a ->
                out += Peak(
                    "Best average round", formatDuration(a.avgRoundMs!!),
                    "${date(a)} · ${a.rounds} rounds", 1
                )
            }

        // The fastest set of each movement, only where the camera saw every rep: a tapped or
        // skipped set is not a time the app can stand behind. There is no set peak without a
        // category, because the title names the movement being timed.
        if (category != null) {
            for (movement in Exercise.entries) {
                val plural = when (movement) {
                    Exercise.PULLUP -> category.pull.plural
                    Exercise.PUSHUP -> category.push.plural
                    Exercise.SQUAT -> category.squat.plural
                }
                // Newest first and a strict comparison, so a tie keeps the more recent set.
                var best: Pair<Attempt, Long>? = null
                for (a in newestFirst) {
                    val ms = a.setSplits.filter { it.movement == movement && it.measured }
                        .minOfOrNull { it.ms } ?: continue
                    if (best == null || ms < best.second) best = a to ms
                }
                best?.let { (a, ms) ->
                    out += Peak(
                        "Fastest ${movement.target} $plural", formatDuration(ms), date(a), 1
                    )
                }
            }
        }

        val days = Streak.daysTrained(attempts, zone)
        Streak.longestRun(days)?.let { run ->
            val length = run.endInclusive.toEpochDay() - run.start.toEpochDay() + 1
            if (length >= 2) {
                val running = run.endInclusive == today || run.endInclusive == today.minusDays(1)
                out += Peak(
                    "Longest daily streak", "$length days",
                    if (running) "Running now" else "Ended ${dateFormat.format(run.endInclusive)}",
                    1
                )
            }
        }

        val weeks = Streak.weeksTrained(days, firstDayOfWeek)
        Streak.longestWeeksRun(weeks)?.let { run ->
            val length = (run.endInclusive.toEpochDay() - run.start.toEpochDay()) / 7 + 1
            if (length >= 2) {
                val thisWeek = Streak.weekStart(today, firstDayOfWeek)
                val running = run.endInclusive == thisWeek ||
                    run.endInclusive == thisWeek.minusWeeks(1)
                out += Peak(
                    "Longest weekly streak", "$length weeks",
                    if (running) "Running now"
                    else "Ended week of ${dateFormat.format(run.endInclusive)}",
                    1
                )
            }
        }

        val byWeek = attempts.groupBy {
            Streak.weekStart(Progress.localDate(it, zone), firstDayOfWeek)
        }
        // Newest week first, so maxByOrNull keeps the more recent week on a tie.
        val weekList = byWeek.entries.sortedByDescending { it.key }
        weekList.maxByOrNull { it.value.size }?.let { (week, list) ->
            if (list.size >= 2) {
                out += Peak(
                    "Biggest week", "${list.size} sessions",
                    "Week of ${dateFormat.format(week)}", 1
                )
            }
        }
        if (weekList.size >= 2) {
            weekList.maxByOrNull { e -> e.value.sumOf { it.totalReps } }?.let { (week, list) ->
                out += Peak(
                    "Most reps in a week",
                    "${Progress.formatReps(list.sumOf { it.totalReps })} reps",
                    "Week of ${dateFormat.format(week)}", 1
                )
            }
        }
        return out
    }
}
