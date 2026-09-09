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
    private var manual = false

    /** True once a dead hang has been seen and the zone means something. */
    val established: Boolean get() = !y.isNaN()

    /** The centre line of the bar, in the same pixel coordinate system as the keypoints. */
    val lineY: Float? get() = y.takeUnless { it.isNaN() }

    /**
     * Uses a fixed bar for a recorded regression clip.
     *
     * The app normally learns its bar from dead hangs. A labelled offline clip cannot be asked
     * to perform that calibration on demand, so tests may supply the line and horizontal extent
     * measured from that clip instead. Production never needs to call this.
     */
    fun configureManual(y: Float, xMin: Float, xMax: Float) {
        require(y.isFinite() && xMin.isFinite() && xMax.isFinite() && xMin <= xMax) {
            "Manual bar bounds must be finite and ordered"
        }
        this.y = y
        this.xMin = xMin
        this.xMax = xMax
        manual = true
    }

    /** Records where the hands were during a confirmed dead hang. */
    fun observeHang(handsX: Float, handsY: Float, halfGrip: Float) {
        if (manual) return
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

    /**
     * Whether *both* wrists, on a body of this scale, are plausibly on the bar.
     *
     * Testing the midpoint lets one hand leave the bar while the other hand keeps a rep alive.
     * A pull-up needs both grips, so each wrist is tested independently.
     */
    fun holds(left: Keypoint, right: Keypoint, torso: Float): Boolean {
        if (!established || torso <= 0f) return true // nothing learned yet: do not block counting
        if (abs(left.y - y) > Y_TOLERANCE * torso || abs(right.y - y) > Y_TOLERANCE * torso) {
            return false
        }
        // Scenario bars are explicit regions, so do not silently widen them. Learned bars still
        // need a torso-scaled allowance for a natural regrip along the bar.
        val pad = if (manual) 0f else X_PADDING * torso
        return left.x >= xMin - pad && left.x <= xMax + pad &&
            right.x >= xMin - pad && right.x <= xMax + pad
    }

    /** Forgets the bar — the camera has moved, so its position in the frame is meaningless. */
    fun reset() {
        y = Float.NaN
        xMin = Float.NaN
        xMax = Float.NaN
        manual = false
    }
}
