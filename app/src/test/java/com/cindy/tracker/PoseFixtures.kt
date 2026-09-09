package com.cindy.tracker

import kotlin.math.cos
import kotlin.math.sin

/**
 * Synthetic keypoint bodies, so the rep logic can be exercised on the JVM without a camera.
 *
 * All coordinates are in "pixels" with y growing downward, matching what PoseDetector emits.
 */
object PoseFixtures {

    const val LIMB = 100f
    const val TORSO = 100f

    private fun blank() = Array(KP.COUNT) { Keypoint(0f, 0f, 0f) }

    private fun Array<Keypoint>.put(index: Int, x: Float, y: Float, score: Float = 0.9f) {
        this[index] = Keypoint(x, y, score)
    }

    /** Places both of a bilateral pair at the same spot; the engine averages the two sides. */
    private fun Array<Keypoint>.putPair(left: Int, right: Int, x: Float, y: Float) {
        put(left, x - 10f, y)
        put(right, x + 10f, y)
    }

    private fun rad(deg: Float) = Math.toRadians(deg.toDouble())

    /**
     * A body squatting with the given knee angle. 180 is standing, 90 is below parallel.
     * Knee at the origin, ankle straight below, hip swung out by [kneeDeg].
     */
    fun squat(kneeDeg: Float): Array<Keypoint> {
        val k = blank()
        val hipX = (LIMB * sin(rad(kneeDeg))).toFloat()
        val hipY = (LIMB * cos(rad(kneeDeg))).toFloat()
        k.putPair(KP.LEFT_KNEE, KP.RIGHT_KNEE, 0f, 0f)
        k.putPair(KP.LEFT_ANKLE, KP.RIGHT_ANKLE, 0f, LIMB)
        k.putPair(KP.LEFT_HIP, KP.RIGHT_HIP, hipX, hipY)
        k.putPair(KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, hipX, hipY - TORSO)
        k.put(KP.NOSE, hipX, hipY - TORSO - 30f)
        return k
    }

    /**
     * A body mid push-up with the given elbow angle. 180 is lockout, 90 is chest down.
     * Elbow at the origin, wrist below it, shoulder swung out by [elbowDeg].
     */
    fun pushup(elbowDeg: Float): Array<Keypoint> {
        val k = blank()
        val shX = (LIMB * sin(rad(elbowDeg))).toFloat()
        val shY = (LIMB * cos(rad(elbowDeg))).toFloat()
        k.putPair(KP.LEFT_ELBOW, KP.RIGHT_ELBOW, 0f, 0f)
        k.putPair(KP.LEFT_WRIST, KP.RIGHT_WRIST, 0f, LIMB)
        k.putPair(KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, shX, shY)
        // Hips trail behind the shoulders along the body's long axis, keeping torso length fixed.
        k.putPair(KP.LEFT_HIP, KP.RIGHT_HIP, shX - TORSO, shY)
        k.putPair(KP.LEFT_KNEE, KP.RIGHT_KNEE, shX - TORSO - 80f, shY)
        return k
    }

    /**
     * A body on the bar with the given elbow angle. 170 is a dead hang, 60 is chin over the bar.
     * Elbow at the origin, wrist straight above it on the bar, shoulder swung by [elbowDeg] —
     * so the shoulders rise past the hands at the top, exactly as they do on a real pull-up.
     */
    fun pullup(elbowDeg: Float): Array<Keypoint> {
        val k = blank()
        val shX = (LIMB * sin(rad(elbowDeg))).toFloat()
        val shY = (-LIMB * cos(rad(elbowDeg))).toFloat()
        k.putPair(KP.LEFT_ELBOW, KP.RIGHT_ELBOW, 0f, 0f)
        k.putPair(KP.LEFT_WRIST, KP.RIGHT_WRIST, 0f, -LIMB)
        k.putPair(KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, shX, shY)
        k.putPair(KP.LEFT_HIP, KP.RIGHT_HIP, shX, shY + TORSO)
        // Nose is the head proxy emitted by COCO-17. At the top it must pass the wrist/bar line;
        // at a dead hang it is below the reset line. Keeping that distinction in the shared
        // fixture lets the production head gate be exercised without a camera.
        k.put(KP.NOSE, shX, shY - 120f)
        return k
    }

    /** Nothing confidently detected — the "step into frame" case. */
    fun empty(): Array<Keypoint> = blank()
}
