package com.cindy.tracker

/**
 * Decides what the voice should say about the athlete's position, and about the clock.
 *
 * Silence is ambiguous. An athlete who has just got on the bar cannot tell "you are in a good
 * position and the next rep will count" from "the app has lost you and is saying nothing about
 * it", and mid-set there is no way to check the screen. So this speaks in both directions: it
 * says what is wrong when something is, and it confirms when the movement is countable again.
 *
 * The clock half is here for the same reason. The time announcements used to be a `when` over
 * seconds-remaining on the camera screen, saying only the time; an athlete mid-Cindy already has
 * the clock in front of them, and what they cannot work out on the bar is whether the pace they
 * are keeping gets them where they wanted to be. So each mark now carries a figure with it.
 *
 * Free of Android types on purpose — the whole value here is in the timing rules and the wording,
 * and those are only worth having if they can be tested. [WorkoutEngine.blocked] supplies the
 * position input; the workout clock supplies the rest.
 */
class Coach {

    private companion object {
        /** How long a fault must stand before it is worth interrupting for. */
        const val FAULT_AFTER_MS = 4_000L
        /** And how often it may be repeated while nothing improves. A coach, not a nag. */
        const val FAULT_EVERY_MS = 12_000L
        /**
         * How long nothing may have been counting before getting going again is worth confirming.
         *
         * Above the gap between two reps of a set, so working through a movement stays silent —
         * the confirmation is for arriving, resting, or recovering from a fault, not for reps.
         */
        const val CONFIRM_AFTER_BLOCKED_MS = 1_500L
        /** How long the good position must hold, so a single lucky frame does not confirm. */
        const val CONFIRM_HOLD_MS = 400L
        const val READY = "Ready"
        /** The length of a Cindy, which is what a pace is projected against. */
        const val WORKOUT_MS = 20 * 60_000L
    }

    /** The movement the last frame belonged to, so a new one earns its own confirmation. */
    private var exercise: Exercise? = null
    /** Set when something has happened that the athlete deserves to hear the end of. */
    private var confirmOwed = false
    private var goodSince = 0L
    /** When anything at all started going wrong, across however many different faults. */
    private var faultingSince = 0L
    /** When *this* fault started, which is what the athlete is given time to fix. */
    private var faultSince = 0L
    private var spokenFault = ""
    private var lastFaultAt = 0L

    /**
     * Feeds one frame of the running workout and returns what to say, or null to stay quiet.
     *
     * [blocked] is the engine's own judgement that this frame could not score for a reason the
     * athlete could fix by moving — as opposed to merely being mid-rep, which is not a fault.
     */
    fun onFrame(exercise: Exercise, blocked: Boolean, hint: String, now: Long): String? {
        if (exercise != this.exercise) {
            this.exercise = exercise
            // Arriving at a movement always earns a confirmation, even if nothing went wrong.
            confirmOwed = true
            goodSince = 0L
            clearFault()
        }
        return if (blocked) fault(hint, now) else confirm(now)
    }

    private fun fault(hint: String, now: Long): String? {
        goodSince = 0L
        if (faultingSince == 0L) faultingSince = now
        // Long enough out of action that getting going again is worth hearing about.
        if (now - faultingSince >= CONFIRM_AFTER_BLOCKED_MS) confirmOwed = true

        // The clock runs per distinct fault: a changing hint is a moving problem, not a standing
        // one, and interrupting for each of them in turn would be noise.
        if (hint != spokenFault) {
            spokenFault = hint
            lastFaultAt = 0L
            faultSince = now
            return null
        }
        if (now - faultSince < FAULT_AFTER_MS) return null
        if (lastFaultAt != 0L && now - lastFaultAt < FAULT_EVERY_MS) return null
        lastFaultAt = now
        return hint
    }

    private fun confirm(now: Long): String? {
        clearFault()
        if (!confirmOwed) return null
        if (goodSince == 0L) {
            goodSince = now
            return null
        }
        if (now - goodSince < CONFIRM_HOLD_MS) return null
        confirmOwed = false
        goodSince = 0L
        return READY
    }

    private fun clearFault() {
        faultingSince = 0L
        faultSince = 0L
        spokenFault = ""
        lastFaultAt = 0L
    }

    // ── the clock ─────────────────────────────────────────────────────────────

    /**
     * The marks the voice speaks at, as milliseconds *remaining*.
     *
     * Counted down rather than up because Cindy is a twenty-minute AMRAP and what an athlete
     * mid-round wants is how much is left, not how much is gone. Chosen so no two land close
     * enough to run together, and so the last one is early enough to still be worth acting on.
     */
    private val marks = listOf(
        15 * 60_000L, 10 * 60_000L, 5 * 60_000L, 2 * 60_000L, 60_000L, 10_000L
    )

    /** Marks already spoken, so a 200ms ticker cannot say one five times. */
    private val spokenMarks = mutableSetOf<Long>()

    /**
     * What to say about the clock, or null between marks.
     *
     * Every line pairs the time with something the athlete has actually done, because the time
     * alone is the half they can already read off the screen. The pace figure is the one a
     * twenty-minute AMRAP turns on: rounds so far, projected forward at the rate they have kept
     * so far, is the number that tells them whether to push or to settle — and it is only worth
     * saying once there is enough of the workout behind them for it to mean anything.
     *
     * Encouragement is attached to a fact rather than issued on its own. "You're doing great" at
     * minute ten is noise; "Halfway. Six rounds — on for twelve" is the same reassurance, earned.
     */
    fun onClock(elapsedMs: Long, remainingMs: Long, rounds: Int, totalReps: Int): String? {
        val mark = marks.firstOrNull { remainingMs <= it && it !in spokenMarks } ?: return null
        spokenMarks += mark
        return when (mark) {
            10_000L -> "Ten seconds. Everything you have."
            60_000L -> "One minute left. ${rounds(rounds)} down — finish the one you're in."
            2 * 60_000L -> "Two minutes. " + push(rounds, totalReps)
            5 * 60_000L -> "Five minutes left. " + pace(elapsedMs, rounds)
            10 * 60_000L -> "Halfway. " + pace(elapsedMs, rounds)
            else -> "Five minutes in. " + pace(elapsedMs, rounds)
        }
    }

    /**
     * Rounds so far, and where that rate lands at twenty minutes.
     *
     * Projected from elapsed time rather than from the round splits, so a workout that started
     * slowly and sped up is described by all of itself. Falls back to the plain count before the
     * first round is in, where a projection off a fraction of a round would be a wild number
     * stated confidently.
     */
    private fun pace(elapsedMs: Long, rounds: Int): String {
        if (rounds < 1 || elapsedMs < 60_000L) return "Keep the pace you're on."
        val projected = (rounds * WORKOUT_MS / elapsedMs).toInt()
        return "${rounds(rounds)} — on for $projected."
    }

    private fun push(rounds: Int, totalReps: Int): String =
        score(rounds, totalReps) + if (rounds < 1) ". Keep going." else ". Hold the pace."

    /**
     * A score in words: the rounds done, and the *whole* rep tally behind them.
     *
     * The rep figure has to be the total, not the part of the round in progress. Those two
     * differ by a whole round's work at exactly the wrong moment — the reps of the current
     * round are zero the instant one completes, so an athlete who stopped having just finished
     * a clean round was told "1 rounds and 0 reps" over a screen reading thirty. Zero is the
     * one number a result must never say about work that was done.
     *
     * "In total" is spelled out because the other reading — a round *and then* thirty more —
     * is the one a listener reaches for, and a score is not worth saying ambiguously.
     */
    fun score(rounds: Int, totalReps: Int): String {
        val reps = "$totalReps rep${if (totalReps == 1) "" else "s"}"
        return if (rounds < 1) reps else "${rounds(rounds)} — $reps in total"
    }

    /** "1 round", "6 rounds" — said often enough to be worth getting right. */
    private fun rounds(rounds: Int): String = "$rounds round${if (rounds == 1) "" else "s"}"

    /**
     * The workout stopped. Nothing said before the break should carry over it, and coming back
     * to the bar afterwards is exactly the moment a confirmation is worth hearing.
     */
    fun interrupted() {
        clearFault()
        goodSince = 0L
        confirmOwed = true
    }

    /** Back to a clean slate, for a workout that has been reset. */
    fun reset() {
        interrupted()
        exercise = null
        confirmOwed = false
        // Not cleared by [interrupted]: a pause is the middle of one workout, and hearing
        // "halfway" a second time on the way back to the bar would be a lie about the clock.
        spokenMarks.clear()
    }
}
