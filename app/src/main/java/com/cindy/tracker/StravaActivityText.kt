package com.cindy.tracker

import java.util.Locale

/**
 * What produced an attempt's calorie figure, said in the same words as [ResultsActivity.energy].
 *
 * [NONE] means no figure exists at all (no body weight on file), so [StravaActivityText] writes
 * nothing rather than a line about a number that was never computed.
 */
enum class CalorieBasis { NONE, BODY_WEIGHT, HEART_RATE }

/**
 * The name and description Strava shows for a finished Cindy — plain text, reusing exactly the
 * words [ResultsActivity] already uses for the same facts, because the upload should read like
 * confirmation of that screen, not a second opinion written in different language.
 *
 * Pure, and free of Android types, so every line is JVM-testable without Robolectric.
 */
object StravaActivityText {

    /**
     * Mirrors `MainActivity.WORKOUT_MS`, which is private to that file and outside this phase's
     * file set. [Records.BENCHMARK] already carries the same 20-minute literal for the same
     * reason: the workout length is a fixed fact of Cindy, not a value worth wiring a shared
     * constant through files this phase does not touch for.
     */
    private const val WORKOUT_MS = 20 * 60 * 1000L

    /** "Cindy — 17 + 12", "Adaptive Cindy — 9", "Cindy — at least 14 + 3". */
    fun name(a: Attempt): String {
        val mode = a.profile?.mode?.label ?: "Cindy"
        val prefix = if (a.scoreIsLowerBound) "at least " else ""
        return "$mode — $prefix${a.scoreLabel()}"
    }

    /**
     * One fact per line, in the order the athlete would want to read them: the score, what was
     * actually done, the pace, the honesty caveats, and how the calorie figure was reached.
     */
    fun description(a: Attempt, calorieBasis: CalorieBasis): String {
        val lines = mutableListOf<String>()

        val roundsPart =
            if (a.reps == 0) count(a.rounds, "round") else "${count(a.rounds, "round")} + ${count(a.reps, "rep")}"
        val stoppedSuffix = if (a.durationMs < WORKOUT_MS) " — stopped early" else ""
        lines += "$roundsPart · ${count(a.totalReps, "rep")} in ${formatDuration(a.durationMs)}$stoppedSuffix"

        val profile = a.profile
        lines += if (profile != null && !profile.isStandard) profile.changedMovements() else a.caption

        if (a.roundSplitsMs.isNotEmpty()) {
            lines += "Average round ${formatDuration(a.avgRoundMs!!)} · " +
                "fastest ${formatDuration(a.fastestRoundMs!!)} · slowest ${formatDuration(a.slowestRoundMs!!)}"
        }

        if (a.pausedMs > 0L) {
            lines += "Paused ${formatDuration(a.pausedMs)} · ${formatDuration(a.realTimeMs)} real time"
        }

        if (a.manualReps > 0) {
            lines += "${a.manualReps} of the ${a.totalReps} reps were added by hand"
        }

        if (a.scoreIsLowerBound) {
            lines += "The camera lost you for ${formatDuration(a.untrackedMs)}, so the score is a lower bound"
        }

        when (calorieBasis) {
            CalorieBasis.NONE -> Unit
            CalorieBasis.BODY_WEIGHT -> lines += String.format(
                Locale.US,
                "Calories estimated from body weight (≈ %.1f METs)",
                Calories.met(a.totalReps, a.durationMs)
            )
            CalorieBasis.HEART_RATE -> lines += "Calories estimated from heart rate"
        }

        lines += "Counted by Cindy Tracker"

        return lines.joinToString("\n")
    }

    /** "1 round", "6 rounds": the same care [Coach] takes, since this is read as often as heard. */
    private fun count(n: Int, noun: String): String = "$n $noun${if (n == 1) "" else "s"}"
}
