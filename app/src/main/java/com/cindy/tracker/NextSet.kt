package com.cindy.tracker

import java.util.Locale

/**
 * The next set, as the scoreboard shows it over the figure for a moment when the movement
 * changes while the clock runs: the set's target over the movement's name, "10" over
 * "PUSH-UPS". Two rows and no slash, so it cannot be read as a count.
 *
 * [inMs] is how long after the change it appears. Finishing a set banked its last rep, whose roll
 * and green pulse play first; a skip banked nothing, so it appears at once.
 */
data class NextSet(val movement: Exercise, val inMs: Long) {

    /** The set's target, the upper row. */
    val figure: String get() = movement.target.toString()

    /** The movement's name in capitals, the lower row: the engine's labels already are. */
    val name: String get() = movement.label

    /** What a screen reader says for the two rows. */
    val spoken: String get() = "Next set: $figure ${movement.label.lowercase(Locale.ROOT)}"

    companion object {
        /** The last rep's roll (150 ms) and pulse (300 ms), as the mock times them. */
        const val AFTER_REP_MS = 450L

        /** How long the next set stays over the figure. */
        const val SHOWN_MS = 1_500L

        /**
         * The next set brought by the frame that carried [event], or null when the movement did
         * not change or the clock is stopped. [motion] says whether the change banked a rep;
         * [now] is the movement the engine has moved on to.
         */
        fun after(event: RepEvent, motion: FigureMotion, running: Boolean, now: Exercise): NextSet? {
            if (!running) return null
            if (event != RepEvent.EXERCISE_DONE && event != RepEvent.ROUND_DONE) return null
            return NextSet(now, inMs = if (motion == FigureMotion.BANKED) AFTER_REP_MS else 0L)
        }
    }
}
