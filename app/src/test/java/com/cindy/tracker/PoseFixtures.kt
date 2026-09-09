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
     * A body face down on the floor at the end of a set of push-ups, legs straight.
     *
     * The knee angle here is a full 180 degrees — the same reading a standing body gives — so
     * this is the pose that proves a squat cannot be gated on leg extension alone. What separates
     * it from standing is the torso, which lies along the floor instead of pointing up.
     */
    fun onTheFloor(): Array<Keypoint> {
        val k = blank()
        k.putPair(KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, 0f, 0f)
        k.putPair(KP.LEFT_HIP, KP.RIGHT_HIP, -TORSO, 0f)
        // Hip, knee and ankle collinear along the floor: the legs are locked out.
        k.putPair(KP.LEFT_KNEE, KP.RIGHT_KNEE, -TORSO - 80f, 0f)
        k.putPair(KP.LEFT_ANKLE, KP.RIGHT_ANKLE, -TORSO - 160f, 0f)
        k.putPair(KP.LEFT_ELBOW, KP.RIGHT_ELBOW, 0f, LIMB)
        k.putPair(KP.LEFT_WRIST, KP.RIGHT_WRIST, 0f, 2f * LIMB)
        k.put(KP.NOSE, 60f, 0f)
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
     * A body mid *knee* push-up with the given elbow angle: hands and knees on the floor, shins
     * folded up behind, and no plank line from shoulder to ankle.
     *
     * Deliberately identical to [pushup] everywhere the push-up path actually looks — the
     * shoulder-elbow-wrist chain and the torso — because that is the finding this fixture
     * exists to pin down. The knees and shins are placed honestly so the fixture describes the
     * real movement, not so the engine can read them: nothing in the push-up path consults them.
     */
    fun kneePushup(elbowDeg: Float): Array<Keypoint> {
        val k = blank()
        val shX = (LIMB * sin(rad(elbowDeg))).toFloat()
        val shY = (LIMB * cos(rad(elbowDeg))).toFloat()
        // The floor is the line the planted hands sit on.
        val floorY = LIMB
        k.putPair(KP.LEFT_ELBOW, KP.RIGHT_ELBOW, 0f, 0f)
        k.putPair(KP.LEFT_WRIST, KP.RIGHT_WRIST, 0f, floorY)
        k.putPair(KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, shX, shY)
        k.putPair(KP.LEFT_HIP, KP.RIGHT_HIP, shX - TORSO, shY)
        // Knees down on the floor rather than trailing the hips, and the shins raised behind.
        k.putPair(KP.LEFT_KNEE, KP.RIGHT_KNEE, shX - TORSO - 40f, floorY)
        k.putPair(KP.LEFT_ANKLE, KP.RIGHT_ANKLE, shX - TORSO - 40f, floorY - 60f)
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
