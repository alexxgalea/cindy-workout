package com.cindy.tracker

/**
 * What a session is measured against on the results screen: the best earlier attempt at the
 * same movements, or the last one.
 *
 * Pure, like [Records] and [Progress]: no Android types and no clock of its own, so the
 * selection can be tested without a phone. "Earlier" is strict — [Attempt.atMillis] before the
 * session's own — so a session is never measured against itself or against something that had
 * not happened yet. After a workout that pool is exactly [Records.personalRecord]'s; in review,
 * it stays frozen at the moment the session being looked at actually happened.
 */
object Comparisons {

    /** Attempts [of] could honestly be measured against: the same movements, strictly before it. */
    fun earlier(attempts: List<Attempt>, of: Attempt): List<Attempt> =
        attempts.filter { it.profile == of.profile && it.atMillis < of.atMillis }

    /** The best of [earlier] — the record [of] was actually chasing. */
    fun best(attempts: List<Attempt>, of: Attempt): Attempt? = Records.best(earlier(attempts, of))

    /** The most recent of [earlier]. */
    fun last(attempts: List<Attempt>, of: Attempt): Attempt? =
        earlier(attempts, of).maxByOrNull { it.atMillis }

    /** Which comparison a chip or card is showing. */
    enum class Kind { BEST, LAST }

    /** One choice on the compare card: which kind it is, the session behind it, and its label. */
    data class Option(val kind: Kind, val attempt: Attempt, val label: String)

    /**
     * BEST then LAST, dropping LAST when it is the same session as BEST — the ordinary case for
     * an athlete with only one earlier attempt, or one who just beat their previous best with
     * their very next one. Empty when there is nothing earlier at all, which is what hides the
     * card: a session cannot be measured against a history it does not have.
     */
    fun options(attempts: List<Attempt>, of: Attempt): List<Option> {
        val b = best(attempts, of) ?: return emptyList()
        val l = last(attempts, of)
        val sameSession = l != null && l.atMillis == b.atMillis
        val out = mutableListOf(
            Option(Kind.BEST, b, if (sameSession) "Your best · also last time" else "Your best")
        )
        if (l != null && !sameSession) out += Option(Kind.LAST, l, "Last time")
        return out
    }

    /** Reps, rounds and average round, [of] minus [reference]; positive is ahead, or faster. */
    data class Delta(val reps: Int, val rounds: Int, val avgRoundMs: Long?)

    fun delta(of: Attempt, reference: Attempt): Delta = Delta(
        reps = of.totalReps - reference.totalReps,
        rounds = of.rounds - reference.rounds,
        avgRoundMs = avgRoundDelta(of, reference)
    )

    /** Positive when [of]'s average round was faster — shorter — than [reference]'s. */
    private fun avgRoundDelta(of: Attempt, reference: Attempt): Long? {
        val mine = of.avgRoundMs ?: return null
        val theirs = reference.avgRoundMs ?: return null
        return theirs - mine
    }
}
