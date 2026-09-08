package com.cindy.tracker

/**
 * Counts oscillations of a scalar signal with Schmitt-trigger hysteresis.
 *
 * Callers must orient the signal so that the *bottom* of the movement is the low value and
 * the *top* is the high value. A rep is booked on the DOWN -> UP transition, i.e. at lockout
 * of a push-up, standing out of a squat, chin over the bar on a pull-up.
 *
 * The two-threshold band is what stops a shaking keypoint from machine-gunning reps: the
 * signal has to travel the whole way across the dead zone before anything is counted.
 */
class RepCounter(
    private val downBelow: Float,
    private val upAbove: Float,
    private val minRepMs: Long = 350L,
    private val smoothing: Float = 0.4f
) {
    enum class Phase { UNKNOWN, DOWN, UP }

    private companion object {
        const val NO_REP = Long.MIN_VALUE
    }

    var phase = Phase.UNKNOWN
        private set
    var count = 0
        private set
    var smoothed = Float.NaN
        private set

    /** Sentinel meaning "no rep booked yet", so the debounce cannot gate the first one. */
    private var lastRepAt = NO_REP
    /** True once the signal has visited DOWN, so a half rep on startup is not scored. */
    private var armed = false

    /** @return true if this sample completed a rep. */
    fun update(raw: Float, now: Long): Boolean {
        if (raw.isNaN()) return false
        smoothed = if (smoothed.isNaN()) raw else smoothed + smoothing * (raw - smoothed)
        val s = smoothed

        if (s < downBelow) {
            phase = Phase.DOWN
            armed = true
            return false
        }
        if (s > upAbove) {
            val wasDown = phase == Phase.DOWN
            phase = Phase.UP
            if (wasDown && armed && (lastRepAt == NO_REP || now - lastRepAt >= minRepMs)) {
                lastRepAt = now
                count++
                return true
            }
        }
        return false
    }

    /** Books a rep without a signal crossing — used by the manual "+1" override. */
    fun forceIncrement() {
        count++
        phase = Phase.UNKNOWN
        armed = false
    }

    fun reset() {
        phase = Phase.UNKNOWN
        count = 0
        smoothed = Float.NaN
        lastRepAt = NO_REP
        armed = false
    }

    /** Drops the counted reps but keeps the smoothing state, for moving to the next exercise. */
    fun resetCount() {
        count = 0
        armed = false
        phase = Phase.UNKNOWN
        smoothed = Float.NaN
    }
}
