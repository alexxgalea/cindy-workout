package com.cindy.tracker

import java.util.Locale

/**
 * What the session page opens on: the score and the time, then one line that qualifies them.
 *
 * Everything the page used to say twice (the rounds and the clock in the tiles, the reps and
 * the pace in a tile and again under the score) is said here once, so a session too short to have
 * anything else is still a finished page. [speech] is the whole lead as the sentences a screen
 * reader says for it.
 */
data class SessionLead(
    val score: String,
    /** The reps into the next round, as "+12"; null when the last round ended on the dot. */
    val looseReps: String?,
    val time: String,
    /** "plus 1:05 paused"; null when the clock never stopped. */
    val timeNote: String?,
    val detail: String,
    val speech: String
) {
    companion object {
        /**
         * [stats] is optional: without set times (an older record) the loose reps fall back to
         * [Attempt.reps], the same loose count the score has always shown. With them, the
         * unfinished round says what the sets banked.
         */
        fun of(a: Attempt, stats: SessionStats?): SessionLead {
            val leftover = stats?.let { it.unfinished?.reps ?: 0 } ?: a.reps
            // The reps into the next round come from the score, so a floor says "at least" here
            // too, on the page and in the sentence read out for it.
            val atLeast = if (a.scoreIsLowerBound) "at least " else ""
            val pace = SessionStats.repsPerMinute(a)?.let { "%.1f".format(Locale.US, it) }

            val detail = listOfNotNull(
                "$atLeast${a.totalReps} ${reps(a.totalReps)}",
                pace?.let { "$atLeast$it reps/min" },
                if (a.manualReps > 0) "${a.manualReps} tapped" else null,
                if (Records.beatsBenchmark(a)) "past ${Records.BENCHMARK_NAME}" else null
            ).joinToString(" · ")

            val timeNote = if (a.pausedMs > 0L) "plus ${formatDuration(a.pausedMs)} paused" else null
            val clock = formatDuration(a.durationMs)

            val score = buildString {
                append("${a.rounds} ${if (a.rounds == 1) "round" else "rounds"}")
                if (leftover > 0) append(", plus $atLeast$leftover ${reps(leftover)} into round ${a.rounds + 1}")
            }
            val total = buildString {
                append("$atLeast${a.totalReps} ${reps(a.totalReps)}")
                if (pace != null) append(", $atLeast$pace reps a minute")
                if (a.manualReps > 0) append(", ${a.manualReps} of them tapped in")
            }
            val speech = "$score. $total. $clock on the clock" +
                (timeNote?.let { ", $it" } ?: "") + "."

            return SessionLead(
                score = "${a.rounds}",
                looseReps = if (leftover > 0) "+$leftover" else null,
                time = clock,
                timeNote = timeNote,
                detail = detail,
                speech = speech
            )
        }

        private fun reps(n: Int) = if (n == 1) "rep" else "reps"
    }
}
