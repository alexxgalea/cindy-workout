package com.cindy.tracker

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * What the menu's first row says, and which session it opens.
 *
 * The most recent session by the time it was filed, not the best by score and not the last one
 * in the store: the store's order is an implementation detail, and the board's best is already
 * one tap away on Progress. This row exists to answer "how did I just do?".
 *
 * Pure, so that the choice of session and the words can be tested without a screen.
 */
data class LastSessionRow(
    /** The key the session is filed under, which is what the session page is opened by. */
    val atMillis: Long,
    val title: String,
    /** The date and the score, as the row prints them under its title. */
    val value: String,
    /** What TalkBack reads: the date and the score in words, not "5 + 3". */
    val spokenName: String
) {
    companion object {
        const val TITLE = "Last session"

        /** The same date the leaderboard prints beside a session. */
        private val DATE = DateTimeFormatter.ofPattern("d MMM yyyy", Locale.US)

        /** Null when there are no sessions: the row is absent rather than a dead end. */
        fun of(attempts: List<Attempt>, zone: ZoneId = ZoneId.systemDefault()): LastSessionRow? {
            val last = attempts.maxByOrNull { it.atMillis } ?: return null
            val date = DATE.withZone(zone).format(Instant.ofEpochMilli(last.atMillis))
            return LastSessionRow(
                atMillis = last.atMillis,
                title = TITLE,
                value = "$date · ${last.scoreLabel()}",
                spokenName = "$TITLE, $date, score ${spokenScore(last)}"
            )
        }

        private fun spokenScore(a: Attempt): String {
            val rounds = if (a.rounds == 1) "1 round" else "${a.rounds} rounds"
            val reps = if (a.reps == 1) "1 rep" else "${a.reps} reps"
            return when {
                a.reps == 0 -> rounds
                a.rounds == 0 -> reps
                else -> "$rounds and $reps"
            }
        }
    }
}
