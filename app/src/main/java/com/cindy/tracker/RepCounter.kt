package com.cindy.tracker

import kotlin.math.max
import kotlin.math.min

/**
 * Counts oscillations of a scalar signal by measuring how far it climbs away from its trough.
 *
 * Callers must orient the signal so that the *bottom* of the movement is the low value and the
 * *top* is the high value. A rep is booked at the top: lockout of a push-up, standing out of a
 * squat, chin over the bar on a pull-up.
 *
 * ### Why the band is learned rather than fixed
 *
 * Fixed thresholds assume the camera sees the movement the same way every time, and it does not.
 * A phone standing on the floor foreshortens everything above it, so the same pull-up projects a
 * visibly smaller swing than it does from chest height — which showed up in testing as the app
 * counting better purely because the phone was raised. Since nobody has a second person holding
 * the camera, the floor is the normal case and the counter has to absorb it.
 *
 * So the thresholds are derived from the range the athlete actually produces, and only the
 * *shape* of the oscillation matters. The first rep of a session is judged against [minRange],
 * the travel below which a wobble is not believed to be a rep at all; after that the band
 * tightens to what the athlete has demonstrated, so half reps stop counting once full ones have
 * set the standard.
 *
 * ### Why a trough rather than a threshold crossing
 *
 * An earlier version armed itself when the signal crossed a fixed low threshold. Under a squashed
 * range it never got that low, so it never armed, and every rep was silently discarded. Tracking
 * the lowest value seen since the last rep removes the ordering problem entirely: it does not
 * matter that the range was still unknown when the athlete was at the bottom of the movement.
 */
class RepCounter(
    private val downBelow: Float,
    private val upAbove: Float,
    private val minRepMs: Long = 350L,
    private val smoothing: Float = 0.4f,
    private val minRange: Float = 0f,
    /**
     * The share of the learned travel, measured up from the lowest value seen, that counts as the
     * bottom of the movement: the zone a rep has to have visited to arm.
     *
     * Thirty percent for every movement but one. A squat done with the heels flat on the floor
     * stops higher than one up on the toes, and both are correct, so a counter that learned its
     * band from deep reps must still arm for the shallower kind. A wider zone is what lets it;
     * [minTravel] is what stops it arming for a wobble.
     */
    private val bottomMargin: Float = MARGIN,
    /**
     * The least a rep must climb off its trough, in signal units, however wide the learned band.
     *
     * Zero for every movement but one, where the band's own share of travel is the whole rule. It
     * is a floor under that share, and it exists because widening [bottomMargin] shrinks the
     * share: at 60% the band asks for only a tenth of its travel, which on a wide band is a few
     * degrees of jitter.
     */
    private val minTravel: Float = 0f
) {
    enum class Phase { UNKNOWN, DOWN, UP }

    private companion object {
        const val NO_REP = Long.MIN_VALUE
        /** Share of the observed travel held back as dead zone at each end. */
        const val MARGIN = 0.30f
        /** How fast a stale extreme is forgotten, in signal units per frame. */
        const val DECAY = 0.05f
    }

    var phase = Phase.UNKNOWN
        private set
    var count = 0
        private set
    var smoothed = Float.NaN
        private set

    private var seenLow = Float.NaN
    private var seenHigh = Float.NaN
    /** Lowest value since the last booked rep — the foot of the climb being measured. */
    private var trough = Float.NaN
    private var lastRepAt = NO_REP
    /**
     * Cleared on each rep and set again only once the signal has genuinely come back down.
     *
     * Without it a single rep books twice: the trough restarts partway up the movement, and the
     * remaining climb to the true top is enough to satisfy the travel test a second time as soon
     * as the debounce expires. It starts true so that the first rep of a session — taken before
     * any range is known — is still countable.
     */
    private var armed = true

    /** Travel observed so far. Zero until samples arrive. */
    val learnedRange: Float
        get() = if (seenLow.isNaN() || seenHigh.isNaN()) 0f else seenHigh - seenLow

    /** Travel the calibration step should see before it trusts the camera placement. */
    val requiredRange: Float get() = minRange

    /** Seeds the band from a calibration rep, so rep one is judged against a real range. */
    fun seedBand(low: Float, high: Float) {
        if (low.isNaN() || high.isNaN() || high <= low) return
        seenLow = low
        seenHigh = high
    }

    /** True once the band is wide enough to set the thresholds itself. */
    val calibrated: Boolean
        get() = minRange > 0f && learnedRange >= minRange

    /**
     * Feeds one sample.
     *
     * [mayCount] separates *observing* the signal from *booking* a rep. The band can only
     * describe the athlete's real swing if the counter sees the whole oscillation, but a caller
     * with its own gates — the pull-up bar and head checks — still needs to withhold the score
     * on frames those gates reject. Passing false keeps the smoothing, band and phase current
     * while guaranteeing no rep is booked.
     *
     * @return true if this sample completed a rep.
     */
    fun update(raw: Float, now: Long, mayCount: Boolean = true): Boolean {
        if (raw.isNaN()) return false
        smoothed = if (smoothed.isNaN()) raw else smoothed + smoothing * (raw - smoothed)
        val s = smoothed

        observe(s)
        trough = if (trough.isNaN()) s else min(trough, s)

        val range = learnedRange
        val useBand = calibrated

        // How far the signal must climb off its trough, and how close to the top it must finish.
        val needed =
            if (useBand) max((1f - bottomMargin - MARGIN) * range, minTravel)
            else upAbove - downBelow
        val topOfBand = if (useBand) seenHigh - MARGIN * range else upAbove
        val bottomOfBand = if (useBand) seenLow + bottomMargin * range else downBelow

        if (s <= bottomOfBand) {
            phase = Phase.DOWN
            armed = true
        } else if (s >= topOfBand) {
            phase = Phase.UP
        }

        val climbed = s - trough
        val atTop = if (useBand) s >= topOfBand else s > upAbove
        if (mayCount && armed && climbed >= needed && atTop &&
            (lastRepAt == NO_REP || now - lastRepAt >= minRepMs)
        ) {
            lastRepAt = now
            count++
            armed = false
            // Restart the measurement from here so the descent establishes the next trough.
            trough = s
            return true
        }
        return false
    }

    private fun observe(s: Float) {
        seenLow = if (seenLow.isNaN()) s else min(seenLow, s)
        seenHigh = if (seenHigh.isNaN()) s else max(seenHigh, s)
        // Let stale extremes fade, but never shrink the band below the range worth trusting.
        if (seenHigh - seenLow > max(minRange, 1f)) {
            seenLow += DECAY
            seenHigh -= DECAY
        }
    }

    /** Books a rep without a signal crossing — used by the manual "+1" override. */
    fun forceIncrement() {
        count++
        phase = Phase.UNKNOWN
        armed = false
        trough = smoothed
    }

    /** Takes a rep back off the score — the "−1" override for a miscount. */
    fun forceDecrement() {
        if (count == 0) return
        count--
        phase = Phase.UNKNOWN
        armed = true
        trough = Float.NaN
    }

    /** Overwrites the score, for stepping back across a movement boundary. */
    fun setCount(n: Int) {
        count = n.coerceAtLeast(0)
        phase = Phase.UNKNOWN
        armed = true
        trough = Float.NaN
    }

    /**
     * Forgets the learned band without touching the score.
     *
     * Used when the camera's view of the athlete changes — a flip, or a pause long enough that
     * the phone or the athlete has moved — because a band learned from the old geometry will
     * quietly mis-score the new one.
     */
    fun resetBand() {
        seenLow = Float.NaN
        seenHigh = Float.NaN
        trough = Float.NaN
        smoothed = Float.NaN
        phase = Phase.UNKNOWN
        armed = true
    }

    /**
     * Discards an in-flight repetition while retaining the learned calibration band.
     *
     * Used when a pull-up loses bar contact or pose identity. The next valid low sample restores
     * the DOWN phase and arms the counter; a recovered top frame cannot finish the old cycle.
     */
    fun requireFreshDown() {
        phase = Phase.UNKNOWN
        trough = Float.NaN
        armed = false
    }

    fun reset() {
        phase = Phase.UNKNOWN
        count = 0
        smoothed = Float.NaN
        lastRepAt = NO_REP
        trough = Float.NaN
        armed = true
        seenLow = Float.NaN
        seenHigh = Float.NaN
    }

    /**
     * Drops the counted reps for the next movement but keeps the learned band — it describes this
     * athlete in front of this camera, which has not changed just because the round has.
     */
    fun resetCount() {
        count = 0
        phase = Phase.UNKNOWN
        smoothed = Float.NaN
        trough = Float.NaN
        armed = true
    }
}
