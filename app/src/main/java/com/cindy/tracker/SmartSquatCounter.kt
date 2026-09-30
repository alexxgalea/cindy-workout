package com.cindy.tracker

import kotlin.math.min

/**
 * Counts squats two ways at once, and goes over to the looser way once the athlete shows they need it.
 *
 * The air-squat counter asks a squat for about 58 degrees of knee travel. A squat done with the
 * heels flat on the floor does not always give that: the heels hold the knees back, the hips stop
 * higher, and from a phone on the floor a good one travels barely more than half of it. Both are
 * correct squats. An athlete who has not said which they do cannot be asked in the middle of a
 * set, so a heels-flat counter runs beside the air-squat one, fed the same samples, and when it
 * has accepted enough that the air-squat counter refused, the session goes over to it.
 *
 * ### What counts as a rep only the heels-flat counter accepted
 *
 * A rep is one ascent. The two counters book it at the top, but not always on the same frame: the
 * air-squat counter can book an ascent that never quite stood after the heels-flat counter has
 * already booked it. Matching the two bookings by time got that wrong and credited one rep twice,
 * so they are matched by ascent instead. A new one begins when the heels-flat counter's bottom
 * zone is entered, and within it:
 *
 *  - an air-squat booking marks the ascent as counted both ways;
 *  - a heels-flat booking on an ascent the air-squat counter has not counted is *pending*;
 *  - if the air-squat counter books that same ascent afterwards, the pending rep is taken back.
 *
 * ### The switch
 *
 * At [spotAfter] pending reps, in consecutive or alternating squats alike, the heels-flat counter
 * takes over for the rest of the session: rounds included, since what the athlete does with their
 * heels does not change between rounds. It is handed the count the athlete has really reached,
 * which is what the air-squat counter booked plus what it refused, so none of the reps that
 * caused the switch are lost. After that it counts every squat, deep ones too, so nothing done
 * on the toes goes uncounted either.
 *
 * Reps tapped in by hand are the athlete's own word for the count, not something either counter
 * saw, so a tap clears what is pending. That can leave the reps before the tap uncredited; it can
 * never credit one twice. Recalibrating does not: a pause and a resume, a flipped camera or a
 * knocked phone forget the band, but the reps already pending really happened, and the count
 * they are credited to is the one the counters kept.
 */
class SmartSquatCounter(
    private val air: RepCounter,
    private val heelsFlat: RepCounter,
    /** How many reps only the heels-flat counter has accepted, in one block, before it takes over. */
    private val spotAfter: Int,
    /**
     * The most the credit may put on the count: the squat target in a Cindy, unbounded for a clip.
     *
     * Reps tapped in by hand are added to both counters, so the credit could otherwise reach past
     * a target the block was already close to, and bank 16 squats in a round of 15.
     */
    private val creditCap: Int
) : RepCounting {

    /** True once the heels-flat counter has taken over. It stays true until [reset]. */
    var switched = false
        private set

    /** Reps in this block that only the heels-flat counter has accepted so far. */
    private var pending = 0
    private var airThisAscent = false
    private var flatOnlyThisAscent = false

    private val active: RepCounter get() = if (switched) heelsFlat else air

    override val phase: RepCounter.Phase get() = active.phase
    override val count: Int get() = active.count
    override val smoothed: Float get() = active.smoothed
    override val learnedRange: Float get() = active.learnedRange
    override val requiredRange: Float get() = active.requiredRange
    override val calibrated: Boolean get() = active.calibrated

    override fun update(raw: Float, now: Long, mayCount: Boolean): Boolean {
        if (switched) return heelsFlat.update(raw, now, mayCount)

        val wasDown = heelsFlat.phase == RepCounter.Phase.DOWN
        val airBooked = air.update(raw, now, mayCount)
        val flatBooked = heelsFlat.update(raw, now, mayCount)

        if (heelsFlat.phase == RepCounter.Phase.DOWN && !wasDown) {
            airThisAscent = false
            flatOnlyThisAscent = false
        }
        if (airBooked) {
            // The air-squat counter has come round to an ascent the heels-flat one booked first.
            if (flatOnlyThisAscent) {
                pending--
                flatOnlyThisAscent = false
            }
            airThisAscent = true
        }
        if (flatBooked && !airThisAscent) {
            pending++
            flatOnlyThisAscent = true
        }

        if (pending >= spotAfter) {
            switched = true
            // setCount drops the phase and the trough. Harmless here: this is the frame the rep
            // was booked on, at the top, and the next rep has to start from a fresh descent.
            heelsFlat.setCount(min(air.count + pending, creditCap))
            return true
        }
        return airBooked
    }

    override fun forceIncrement() {
        air.forceIncrement()
        heelsFlat.forceIncrement()
        clearPending()
    }

    override fun forceDecrement() {
        air.forceDecrement()
        heelsFlat.forceDecrement()
        clearPending()
    }

    override fun setCount(n: Int) {
        // Once the heels-flat counter is in charge the air-squat one is never read again.
        if (!switched) air.setCount(n)
        heelsFlat.setCount(n)
        clearPending()
    }

    override fun resetBand() {
        air.resetBand()
        heelsFlat.resetBand()
        // The ascent in flight goes with the band. What was already pending does not.
        clearAscent()
    }

    override fun requireFreshDown() {
        air.requireFreshDown()
        heelsFlat.requireFreshDown()
        clearAscent()
    }

    /** Pending reps belong to one block of squats; the switch, once made, belongs to the session. */
    override fun resetCount() {
        air.resetCount()
        heelsFlat.resetCount()
        clearPending()
    }

    override fun reset() {
        air.reset()
        heelsFlat.reset()
        clearPending()
        switched = false
    }

    private fun clearPending() {
        pending = 0
        clearAscent()
    }

    private fun clearAscent() {
        airThisAscent = false
        flatOnlyThisAscent = false
    }
}
