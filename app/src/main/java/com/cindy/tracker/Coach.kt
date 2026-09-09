package com.cindy.tracker

/**
 * Decides what the voice should say about the athlete's position.
 *
 * Silence is ambiguous. An athlete who has just got on the bar cannot tell "you are in a good
 * position and the next rep will count" from "the app has lost you and is saying nothing about
 * it", and mid-set there is no way to check the screen. So this speaks in both directions: it
 * says what is wrong when something is, and it confirms when the movement is countable again.
 *
 * Free of Android types on purpose — the whole value here is in the timing rules, and those are
 * only worth having if they can be tested. [WorkoutEngine.blocked] supplies the input.
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
    }
}
