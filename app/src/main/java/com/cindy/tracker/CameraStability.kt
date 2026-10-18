package com.cindy.tracker

import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.atan2

/**
 * Where the camera is pointing, read from the rotation matrix `SensorManager` fills in.
 *
 * Not `SensorManager.getOrientation`. Its azimuth is the compass bearing of the phone's *top
 * edge*, and a phone propped up to film a workout is standing on its end: the top edge points at
 * the ceiling, and a bearing of something pointing straight up is not defined. A phone leaning
 * back by five degrees still has a top edge that is only nine per cent horizontal, so the
 * tremor of a squat landing nearby turns a degree or two of real movement into tens of degrees
 * of azimuth. The axis the camera looks along does not have that problem for a phone filming
 * the horizon, and it is the thing the bar zone is measured against anyway.
 *
 * The matrix is row-major, as `SensorManager` writes it: its columns are the device's axes in
 * East, North, Up, so the camera, which looks out of the back along the device's -Z, is the
 * negated third column. A front camera looks the opposite way, which shifts every heading by half
 * a turn and changes no difference between two of them, the only thing the monitor uses.
 */
object CameraLook {
    /** Compass bearing of the camera's axis, in degrees from -180 to 180. */
    fun heading(matrix: FloatArray): Float =
        Math.toDegrees(atan2(-matrix[2].toDouble(), -matrix[5].toDouble())).toFloat()

    /** Angle of the camera's axis above the horizon, in degrees: positive looks up. */
    fun elevation(matrix: FloatArray): Float =
        Math.toDegrees(asin((-matrix[8]).toDouble().coerceIn(-1.0, 1.0))).toFloat()
}

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
     * Feeds one reading, in degrees: the heading and the elevation of the axis the camera points
     * along, from [CameraLook].
     *
     * Roll does not appear: a phone rotating about the axis it is pointing along changes which
     * way up the picture is, and the frame the analysis runs on is already rotated to upright
     * before anything sees it.
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
