package com.cindy.tracker

import kotlin.math.roundToLong

/**
 * What one movement of one round banked: its reps, and how many of them were tapped in.
 *
 * [tappedReps] is null when the record cannot say. Only the set still running at finish can be in
 * that position (see [SessionStats.from]); a set the athlete left behind carries its own figure.
 */
data class RoundPart(val movement: Exercise, val reps: Int, val tappedReps: Int?) {
    /** Reached its target, rather than being skipped or still running when the clock stopped. */
    val reachedTarget: Boolean get() = reps >= movement.target
}

/**
 * One round as it was actually performed.
 *
 * [parts] always holds the three movements in cycle order, a movement the athlete never got to
 * showing as zero, so a caller can lay every round out the same way. [finished] is whether the
 * athlete left all three behind: a round with a skipped pull-up set is finished and worth less
 * than thirty, which is the whole reason this is read off the sets and never off a target.
 */
data class RoundStat(
    val number: Int,
    val parts: List<RoundPart>,
    val finished: Boolean,
    /** Clock time of the round, when it was finished and the record timed it. */
    val timeMs: Long?
) {
    val reps: Int get() = parts.sumOf { it.reps }

    /** Every movement reached its target: a full round, thirty reps for the standard scheme. */
    val complete: Boolean get() = parts.all { it.reachedTarget }

    /** Reps tapped in across the round, or null if any part of it cannot say. */
    val tappedReps: Int?
        get() = if (parts.any { it.tappedReps == null }) null else parts.sumOf { it.tappedReps!! }

    /**
     * "Round 8 · 12 of 30 · 5 pull-ups, 7 push-ups · unfinished", or
     * "Round 3 · 30 of 30 · 2:44".
     *
     * A full round says what it cost; anything less says what went into it, because "25 of 30"
     * alone cannot tell a skipped set from a round the clock ran out on. Tapped reps are named
     * rather than folded in. [plurals] is the session's own movement words, so a knee push-up
     * session never reads "push-ups". [atLeast] is for a session the camera lost the athlete in:
     * what was banked is a floor, so the round says "at least" before its reps.
     */
    fun caption(plurals: Map<Exercise, String>, atLeast: Boolean = false): String = buildString {
        val target = parts.sumOf { it.movement.target }
        append("Round $number · ${if (atLeast) "at least " else ""}$reps of $target")
        if (!complete) {
            val done = parts.filter { it.reps > 0 }
                .joinToString(", ") { "${it.reps} ${plurals.getValue(it.movement)}" }
            if (done.isNotEmpty()) append(" · $done")
        }
        if (!finished) append(" · unfinished")
        else timeMs?.let { append(" · ${formatDuration(it)}") }
        tappedReps?.takeIf { it > 0 }?.let { append(" · $it tapped") }
    }
}

/** One movement across the whole session. */
data class MovementStat(
    val movement: Exercise,
    /** The session's own plural: "knee push-ups", never the standard movement's name. */
    val label: String,
    val reps: Int,
    /** Clock time spent in its finished sets; null when none was ever finished. */
    val timeMs: Long?,
    /** Its part of the finished sets' time; null unless every movement has a complete set. */
    val shareOfClock: Double?,
    val completeSets: Int,
    val averageCompleteSetMs: Long?,
    /** Reps tapped in; null when the record cannot say (the set still running at finish). */
    val tappedReps: Int?
)

/**
 * The session as rounds and movements, read off the sets the record banked.
 *
 * Every figure here comes from [StravaSets.from], which is the one place that knows how to read
 * [Attempt.setSplits] together with [Attempt.countedReps] and to refuse when they disagree. A
 * session worth `rounds * 30` is exactly the inference this exists to avoid: a skipped pull-up
 * set still advances the cycle, so its round is finished at 25 reps and the rounds say nothing
 * about it.
 */
data class SessionStats(
    val rounds: List<RoundStat>,
    val movements: List<MovementStat>
) {
    /** The round still running when the clock stopped, if there was one. */
    val unfinished: RoundStat? get() = rounds.lastOrNull { !it.finished }

    companion object {

        /**
         * The session's rounds and movements, or null when the record cannot be trusted to give
         * them: it predates counted reps or set times (so the detail is simply unknown), or its
         * sets do not add up to its own round count. A caller shows nothing then; the tiles that
         * need only the attempt's own totals still work without this.
         */
        fun from(a: Attempt): SessionStats? {
            val sets = StravaSets.from(a) ?: return null
            val closed = a.setSplits
            val finishedRounds = closed.size / 3
            // The engine's own round count and the sets it filed are two banks of the same fact.
            // A record where they differ was cut or edited somewhere, and a track drawn from it
            // would show rounds the score does not have.
            if (finishedRounds != a.rounds) return null

            // What the set still running at finish tapped in: the same bank-minus-bank sum
            // StravaSets uses for its reps. Out of range means the record does not add up, and
            // saying nothing is better than guessing a figure.
            val openSet = if (sets.size > closed.size) sets.last() else null
            val openTapped = (a.manualReps - closed.sumOf { it.manualReps })
                .takeIf { it >= 0 && it <= (openSet?.reps ?: 0) }

            val rounds = sets.withIndex().groupBy { it.value.round }.map { (number, inRound) ->
                val parts = Exercise.entries.map { movement ->
                    val entry = inRound.firstOrNull { it.value.exercise == movement }
                    when {
                        entry == null -> RoundPart(movement, 0, 0)
                        entry.index >= closed.size ->
                            RoundPart(movement, entry.value.reps, openTapped)
                        else -> RoundPart(movement, entry.value.reps, closed[entry.index].manualReps)
                    }
                }
                val finished = number <= finishedRounds
                RoundStat(
                    number, parts, finished,
                    if (finished) a.roundSplitsMs.getOrNull(number - 1) else null
                )
            }

            return SessionStats(rounds, movementStats(a, sets, closed, openSet, openTapped))
        }

        private fun movementStats(
            a: Attempt,
            sets: List<WorkoutSet>,
            closed: List<SetSplit>,
            openSet: WorkoutSet?,
            openTapped: Int?
        ): List<MovementStat> {
            val plurals = plurals(a.profile)
            val timedMs = closed.sumOf { it.ms }
            // A share of the finished sets' time is only a share of anything once all three
            // movements have a complete set to stand on; without that, one movement's 100%
            // would be an artefact of the others not having happened yet.
            val everyMovementComplete = Exercise.entries.all { m ->
                closed.any { it.movement == m && it.complete }
            }
            return Exercise.entries.map { movement ->
                val mine = closed.filter { it.movement == movement }
                val complete = mine.filter { it.complete }
                val ms = mine.takeIf { it.isNotEmpty() }?.sumOf { it.ms }
                val inOpenSet = openSet?.exercise == movement
                MovementStat(
                    movement = movement,
                    label = plurals.getValue(movement),
                    reps = sets.filter { it.exercise == movement }.sumOf { it.reps },
                    timeMs = ms,
                    shareOfClock = if (everyMovementComplete && ms != null && timedMs > 0L) {
                        ms.toDouble() / timedMs
                    } else {
                        null
                    },
                    completeSets = complete.size,
                    averageCompleteSetMs = complete.takeIf { it.isNotEmpty() }
                        ?.let { (it.sumOf { s -> s.ms } / it.size.toDouble()).roundToLong() },
                    tappedReps = if (inOpenSet && openTapped == null) null
                    else mine.sumOf { it.manualReps } + if (inOpenSet) openTapped!! else 0
                )
            }
        }

        /**
         * The session's own movement words in cycle order, from its profile. A null profile is a
         * record written before profiles existed, which was the standard movements.
         */
        fun plurals(profile: CindyProfile?): Map<Exercise, String> = mapOf(
            Exercise.PULLUP to (profile?.pull?.plural ?: "pull-ups"),
            Exercise.PUSHUP to (profile?.push?.plural ?: "push-ups"),
            Exercise.SQUAT to (profile?.squat?.plural ?: "squats")
        )

        /**
         * Reps a minute of workout clock, or null before the clock ran. Pauses are not in the
         * clock, so a paused session is not slowed by them. Derived from the score, so it is a
         * floor exactly when [Attempt.scoreIsLowerBound] is.
         */
        fun repsPerMinute(a: Attempt): Double? =
            if (a.durationMs > 0L) a.totalReps * 60_000.0 / a.durationMs else null
    }
}
