package com.cindy.tracker

import kotlin.math.abs

/**
 * Notices that the *phone* moved, as opposed to the athlete.
 *
 * Everything the pull-up gate knows is stored in frame pixels — where the bar is, how wide its
 * zone is, how far below it the head has to return. [WorkoutEngine.recalibrate] already says as
 * much in its own comment: "The bar's position was recorded in frame pixels, so a moved camera
 * invalidates it." Until now nothing called it when the camera actually moved. A phone knocked by
 * a foot, a bag or a gust keeps counting against a bar that is no longer where it thinks, which
 * either refuses every rep for the rest of the workout or accepts a climb that never crossed
 * anything.
 *
 * Deliberately *not* used to count reps. The phone is stationary by design, so its gyroscope says
 * nothing whatever about what the athlete's body is doing; the only question worth asking it is
 * whether the picture the counting rules were calibrated against is still the picture.
 *
 * Free of Android types so the rule can be tested: the caller feeds it whatever its rotation
 * sensor reports.
 */
class CameraStabilityMonitor {

    private companion object {
        /**
         * Rotation, in degrees, past which the framing is a different framing.
         *
         * Generous on purpose. A phone propped on a box vibrates when someone lands a burpee
         * nearby, and a couple of degrees of wobble changes nothing a bar zone cares about — its
         * tolerances are measured in torso lengths. Eight degrees at three metres moves the
         * bar the better part of half a metre through the frame, which no tolerance absorbs.
         */
        const val MOVED_DEGREES = 8f

        /**
         * How still it must then be before the framing is trusted again.
         *
         * Long enough to cover being picked up, adjusted and put down, so the athlete is not
         * handed a fresh calibration halfway through repositioning the phone.
         */
        const val SETTLE_MS = 1_500L
    }

    /** Orientation the current calibration belongs to, or NaN before one is established. */
    private var anchorYaw = Float.NaN
    private var anchorPitch = Float.NaN
    private var stillSince = 0L

    /** True from the moment movement is detected until the phone has been still again. */
    var moving = false
        private set

    /**
     * True for exactly one read, after the phone has moved and then settled.
     *
     * Consumed rather than polled so the caller cannot recalibrate twice off one bump.
     */
    fun consumeReframed(): Boolean {
        if (!reframed) return false
        reframed = false
        return true
    }

    private var reframed = false

    /**
     * Feeds one orientation reading, in degrees.
     *
     * Yaw and pitch only. Roll is ignored: a phone rotating about the axis it is pointing along
     * changes which way up the picture is, and the frame the analysis runs on is already rotated
     * to upright before anything sees it.
     */
    fun update(yaw: Float, pitch: Float, now: Long) {
        if (anchorYaw.isNaN()) {
            anchorYaw = yaw
            anchorPitch = pitch
            stillSince = now
            return
        }

        val moved = maxOf(abs(delta(yaw, anchorYaw)), abs(delta(pitch, anchorPitch)))
        if (moved >= MOVED_DEGREES) {
            moving = true
            // The anchor follows the phone while it is in motion, so what is being measured is
            // "has it stopped", not "how far has it come from where it started". Being carried
            // across a gym would otherwise never settle.
            anchorYaw = yaw
            anchorPitch = pitch
            stillSince = now
            return
        }
        if (!moving) return
        if (now - stillSince < SETTLE_MS) return
        moving = false
        reframed = true
        anchorYaw = yaw
        anchorPitch = pitch
    }

    /** Shortest signed distance between two angles, so 359 and 1 are two degrees apart. */
    private fun delta(a: Float, b: Float): Float {
        var d = (a - b) % 360f
        if (d > 180f) d -= 360f
        if (d < -180f) d += 360f
        return d
    }

    fun reset() {
        anchorYaw = Float.NaN
        anchorPitch = Float.NaN
        stillSince = 0L
        moving = false
        reframed = false
    }
}
