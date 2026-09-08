package com.cindy.tracker

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Where the pull-up bar is, learned from the athlete hanging on it.
 *
 * Elbow flexion alone cannot tell a pull-up from someone standing on the floor waving their arms
 * about, and "wrists above the hips" is a weak substitute — it is true of anyone reaching
 * overhead. Knowing roughly where the hands sit when they are actually on the bar turns that into
 * a real test.
 *
 * The zone is derived rather than tapped in: the setup reps already have the athlete hanging, and
 * every dead hang during the workout refines it, so it survives a pause without another
 * calibration step. Tolerances are multiples of torso length, never pixels, so stepping toward or
 * away from the camera does not move the gate.
 */
class BarZone {

    private companion object {
        /** How fast the estimate follows new observations. */
        const val FOLLOW = 0.15f
        /** Vertical slack around the bar, in torso lengths. */
        const val Y_TOLERANCE = 0.75f
        /** Horizontal slack beyond the observed grip, in torso lengths. */
        const val X_PADDING = 0.6f
    }

    private var y = Float.NaN
    private var xMin = Float.NaN
    private var xMax = Float.NaN

    /** True once a dead hang has been seen and the zone means something. */
    val established: Boolean get() = !y.isNaN()

    /** Records where the hands were during a confirmed dead hang. */
    fun observeHang(handsX: Float, handsY: Float, halfGrip: Float) {
        val low = handsX - halfGrip
        val high = handsX + halfGrip
        if (!established) {
            y = handsY
            xMin = low
            xMax = high
            return
        }
        y += FOLLOW * (handsY - y)
        xMin += FOLLOW * (min(xMin, low) - xMin)
        xMax += FOLLOW * (max(xMax, high) - xMax)
    }

    /** Whether hands at this position, on a body of this scale, are plausibly on the bar. */
    fun holds(handsX: Float, handsY: Float, torso: Float): Boolean {
        if (!established || torso <= 0f) return true // nothing learned yet: do not block counting
        if (abs(handsY - y) > Y_TOLERANCE * torso) return false
        val pad = X_PADDING * torso
        return handsX >= xMin - pad && handsX <= xMax + pad
    }

    /** Forgets the bar — the camera has moved, so its position in the frame is meaningless. */
    fun reset() {
        y = Float.NaN
        xMin = Float.NaN
        xMax = Float.NaN
    }
}
