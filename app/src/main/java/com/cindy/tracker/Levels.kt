package com.cindy.tracker

/**
 * Training levels, ranked by rounds completed in the 20-minute AMRAP.
 *
 * PROVISIONAL. Finishing a full Cindy is pitched as INTERMEDIATE per the brief, with the scaled
 * tiers below it and [Records.BENCHMARK] sitting at the top. The whole ladder is this one table,
 * so retuning it is a matter of editing numbers rather than logic.
 *
 * Rounds are the right axis even though the brief talks about time: in a fixed 20-minute AMRAP,
 * average round time and rounds completed are the same measurement read two ways.
 */
enum class Level(val title: String, val minRounds: Int, val blurb: String) {
    FIRST_STEPS("First Steps", 0, "Moving. Everything starts here."),
    NOVICE("Novice", 5, "Through the workout, finding a pace."),
    INTERMEDIATE("Intermediate", 10, "A complete Cindy. The benchmark most people train toward."),
    ADVANCED("Advanced", 16, "Sustained pace under real fatigue."),
    ELITE("Elite", 21, "Unbroken sets deep into the clock."),
    LEGEND("Legend", 27, "Level with ${Records.BENCHMARK_NAME}.");

    companion object {
        /** The level a score of [rounds] earns. */
        fun of(rounds: Int): Level = entries.last { rounds >= it.minRounds }

        /** The next level up, or null at the top of the ladder. */
        fun next(from: Level): Level? = entries.getOrNull(from.ordinal + 1)

        /** Rounds still needed to rank up, or null if there is nothing above. */
        fun roundsToNext(rounds: Int): Int? =
            next(of(rounds))?.let { (it.minRounds - rounds).coerceAtLeast(0) }

        /** Progress through the current level, 0..1, for a progress bar. */
        fun progress(rounds: Int): Float {
            val level = of(rounds)
            val next = next(level) ?: return 1f
            val span = (next.minRounds - level.minRounds).toFloat()
            if (span <= 0f) return 1f
            return ((rounds - level.minRounds) / span).coerceIn(0f, 1f)
        }
    }
}
