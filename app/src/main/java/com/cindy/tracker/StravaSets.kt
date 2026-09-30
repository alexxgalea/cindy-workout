package com.cindy.tracker

/**
 * Rebuilds the Strava set list from an attempt's own record, rather than a second store kept
 * beside it.
 *
 * [Attempt.setSplits] already banks every movement `MainActivity` left behind: `SplitBook`
 * files one on every `EXERCISE_DONE` and `ROUND_DONE`, at the count `WorkoutEngine` had actually
 * reached, and unwinds one with `SplitBook.stepBack()` on an UNDO that crosses a movement
 * boundary. What that record cannot contain is the movement still running when the clock
 * stopped — it never reached an event of its own, so `SplitBook` never filed it. [from] adds
 * that last set back in, and refuses to guess at a set list when the record does not add up to
 * a movement it can actually trust.
 */
object StravaSets {

    /**
     * The attempt's sets, oldest first, or null when the record cannot be trusted.
     *
     * The final set, if there is one, is the movement in progress at finish. Its reps are
     * `a.totalReps - setSplits.sumOf { it.reps }`, and that subtraction is honest only because
     * *both* sides are banks, not a target and a bank: [Attempt.totalReps] is what the engine
     * actually counted from the first rep to the last, and the splits are every movement that
     * same count has already been paid out to. What is left over is exactly the movement still
     * running when the clock stopped — never an inference, which is the line
     * `reps-are-banked-not-inferred` exists to hold.
     */
    fun from(a: Attempt): List<WorkoutSet>? {
        // Null means this attempt predates a counted total (pre-V5) and totalReps falls back to
        // rounds * 30 + reps — an inferred tally, not a bank. Strava never sees one.
        val counted = a.countedReps ?: return null

        // advance() only ever moves PULLUP -> PUSHUP -> SQUAT -> PULLUP..., starting at PULLUP,
        // so this is the one order a genuine set of splits can be in.
        var expected = Exercise.PULLUP
        val sets = mutableListOf<WorkoutSet>()
        for ((index, split) in a.setSplits.withIndex()) {
            // A split that is not the movement its position in the cycle requires means the
            // record it came from was cut short, reordered, or otherwise not the cycle the
            // engine actually ran. Building a set list on top of that would be a guess wearing
            // banked numbers, so nothing is returned instead.
            if (split.movement != expected) return null
            sets += WorkoutSet(index / 3 + 1, split.movement, split.reps)
            expected = expected.next()
        }

        // The movement that follows the last one SplitBook closed off is the one running when
        // the clock stopped — or PULLUP, for an attempt that stopped before its first movement
        // was ever left.
        val inProgress = a.setSplits.lastOrNull()?.movement?.next() ?: Exercise.PULLUP
        val remainder = counted - sets.sumOf { it.reps }
        // A movement that had already reached its target would have advanced and been banked
        // by SplitBook, so it can never still be "in progress" — a remainder at or past the
        // target, or negative, means the splits and the total disagree with each other, which
        // is a broken record rather than an unfinished movement.
        if (remainder !in 0 until inProgress.target) return null
        // A movement in progress at zero reps banked nothing yet, so it is not a set.
        if (remainder > 0) sets += WorkoutSet(a.setSplits.size / 3 + 1, inProgress, remainder)

        // Belt and braces: the arithmetic above is built so neither of these can actually fail,
        // but an upload is exactly the wrong place to find out a later change broke that.
        if (sets.sumOf { it.reps } != a.totalReps) return null
        if (sets.none { it.reps > 0 }) return null

        return sets
    }
}
