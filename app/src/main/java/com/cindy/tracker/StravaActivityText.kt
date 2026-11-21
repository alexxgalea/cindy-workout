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
     * Mirrors `MainActivity.WORKOUT_MS`, which is private to that screen. [Records.BENCHMARK]
     * already carries the same 20-minute literal for the same reason: the workout length is a
     * fixed fact of Cindy, not a value worth widening an activity's companion to share.
     */
    private const val WORKOUT_MS = 20 * 60 * 1000L

    /**
     * "Cindy — 17 + 12", "Adaptive Cindy — 9", "Cindy — at least 14 + 3": the activity takes the
     * workout's name. Only a Cindy says Adaptive Cindy, because that mode is Cindy's; any other
     * workout is called by its own name, and one this build does not know is called a workout.
     */
    fun name(a: Attempt): String {
        // A Freestyle has no score to put after its name: the description carries what was done.
        if (a.workoutId == Workouts.FREESTYLE_ID) return Workouts.FREESTYLE.name
        val title = if (a.isCindy) a.profile?.mode?.label ?: Workouts.CINDY.name
        else a.workout?.name ?: "Workout"
        val prefix = if (a.scoreIsLowerBound) "at least " else ""
        return "$title — $prefix${a.scoreLabel()}"
    }

    /**
     * One fact per line, in the order the athlete would want to read them: the score, what was
     * actually done, the pace, the honesty caveats, and how the calorie figure was reached.
     *
     * [heartRateMs] only matters when [calorieBasis] is [CalorieBasis.HEART_RATE]: it is the
     * workout-clock time a watch actually covered, out of [Attempt.durationMs]. Less than the
     * full clock says so, rather than letting "estimated from heart rate" quietly claim more
     * coverage than there was.
     */
    fun description(a: Attempt, calorieBasis: CalorieBasis, heartRateMs: Long? = null): String {
        if (a.workoutId == Workouts.FREESTYLE_ID) return freestyleDescription(a, calorieBasis, heartRateMs)
        val lines = mutableListOf<String>()

        val roundsPart =
            if (a.reps == 0) count(a.rounds, "round") else "${count(a.rounds, "round")} + ${count(a.reps, "rep")}"
        // Early against the workout's own clock; a workout with no cap cannot stop early.
        val cap = if (a.isCindy) WORKOUT_MS else a.workout?.timeCapMs
        val stoppedSuffix = if (cap != null && a.durationMs < cap) " — stopped early" else ""
        lines += "$roundsPart · ${count(a.totalReps, "rep")} in ${formatDuration(a.durationMs)}$stoppedSuffix"

        val profile = a.profile
        lines += if (profile != null && !profile.isStandard) profile.changedMovements() else a.caption

        if (a.roundSplitsMs.isNotEmpty()) {
            lines += "Average round ${formatDuration(a.avgRoundMs!!)} · " +
                "fastest ${formatDuration(a.fastestRoundMs!!)} · slowest ${formatDuration(a.slowestRoundMs!!)}"
        }

        lines += caveats(a, calorieBasis, heartRateMs)

        lines += "Counted by Cindy Tracker"

        return lines.joinToString("\n")
    }

    /**
     * What a Freestyle shows (spec #188): the reps and time, the totals per movement, then the
     * sets in order. Only movements and rep counts: no clock time of any set leaves the phone,
     * and nothing here is data a Cindy upload does not already send.
     */
    private fun freestyleDescription(a: Attempt, calorieBasis: CalorieBasis, heartRateMs: Long?): String {
        val lines = mutableListOf("${count(a.totalReps, "rep")} in ${formatDuration(a.durationMs)}")
        val totals = a.freestyleSets.groupBy { it.movement }.mapValues { (_, s) -> s.sumOf { it.reps } }
        val byMovement = Exercise.entries.filter { (totals[it] ?: 0) > 0 }
        if (byMovement.isNotEmpty()) lines += byMovement.joinToString(" · ") { "${named(it)} ${totals.getValue(it)}" }
        val sets = a.freestyleSets.filter { it.reps > 0 }
        if (sets.isNotEmpty()) lines += "Sets: " + sets.joinToString(", ") { "${named(it.movement)} ${it.reps}" }

        val profile = a.profile
        lines += if (profile != null && !profile.isStandard) "${Workouts.FREESTYLE.name} · ${profile.changedMovements()}"
        else Workouts.FREESTYLE.name
        lines += caveats(a, calorieBasis, heartRateMs)
        lines += "Counted by Cindy Tracker"
        return lines.joinToString("\n")
    }

    /** "Pull-ups": the movement's label in the sentence case the rest of the description uses. */
    private fun named(e: Exercise): String = e.label.lowercase().replaceFirstChar { it.uppercase() }

    /** The honesty and calorie lines both kinds of description share, in their order. */
    private fun caveats(a: Attempt, calorieBasis: CalorieBasis, heartRateMs: Long?): List<String> {
        val lines = mutableListOf<String>()
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
            CalorieBasis.HEART_RATE -> lines += if (heartRateMs != null && heartRateMs < a.durationMs) {
                "Calories from heart rate for ${formatDuration(heartRateMs)} of " +
                    "${formatDuration(a.durationMs)}, body weight for the rest"
            } else {
                "Calories estimated from heart rate"
            }
        }
        return lines
    }

    /** "1 round", "6 rounds": the same care [Coach] takes, since this is read as often as heard. */
    private fun count(n: Int, noun: String): String = "$n $noun${if (n == 1) "" else "s"}"
}
