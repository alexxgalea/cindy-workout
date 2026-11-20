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
     * The bottom of a squat as it is really done: [squat]'s legs, with the torso leaning 60 degrees
     * forward over the knees instead of standing straight above the hips.
     *
     * The shoulders sit only half a torso above the hips, so the body is not upright. The shins
     * are still a full shin's length under the knees, which is the only thing that says the athlete
     * is on their feet.
     */
    fun leaningSquat(kneeDeg: Float): Array<Keypoint> {
        val k = squat(kneeDeg)
        val hipX = (LIMB * sin(rad(kneeDeg))).toFloat()
        val hipY = (LIMB * cos(rad(kneeDeg))).toFloat()
        val lean = rad(60f)
        val shoulderX = hipX - (TORSO * sin(lean)).toFloat()
        val shoulderY = hipY - (TORSO * cos(lean)).toFloat()
        k.putPair(KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, shoulderX, shoulderY)
        k.put(KP.NOSE, shoulderX - 20f, shoulderY - 25f)
        return k
    }

    /**
     * [squat] with the hands behind the head, the way the owner squats in the gym: the wrists sit
     * [handsTorsos] of a torso above the shoulders and the elbows stand out beside the ears.
     * Filmed, the wrists never went past about 0.35 of a torso, so the default is a third.
     */
    fun squatHandsBehindHead(kneeDeg: Float, handsTorsos: Float = 0.3f): Array<Keypoint> {
        val k = squat(kneeDeg)
        val hipX = (LIMB * sin(rad(kneeDeg))).toFloat()
        val hipY = (LIMB * cos(rad(kneeDeg))).toFloat()
        val shoulderY = hipY - TORSO
        k.putPair(KP.LEFT_ELBOW, KP.RIGHT_ELBOW, hipX, shoulderY - 10f)
        k.putPair(KP.LEFT_WRIST, KP.RIGHT_WRIST, hipX, shoulderY - handsTorsos * TORSO)
        return k
    }

    /**
     * A plank filmed from in front, the way a phone propped on the floor sees push-ups: the
     * foreshortened torso points up the picture, so the shoulders sit well above the hips.
     *
     * Knees are a long way below the hips and the ankles are up beside the knees, so today's
     * start test ([PoseGeometry.standing]) reads this as standing. No shin stands under a knee,
     * and the hands are on the floor under the shoulders, which is what says it is not.
     */
    fun headOnPlank(): Array<Keypoint> {
        val k = blank()
        k.putPair(KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, 0f, 0f)
        k.putPair(KP.LEFT_HIP, KP.RIGHT_HIP, 0f, 80f)
        k.putPair(KP.LEFT_KNEE, KP.RIGHT_KNEE, 0f, 140f)
        k.putPair(KP.LEFT_ANKLE, KP.RIGHT_ANKLE, 0f, 150f)
        k.putPair(KP.LEFT_ELBOW, KP.RIGHT_ELBOW, 0f, 70f)
        k.putPair(KP.LEFT_WRIST, KP.RIGHT_WRIST, 0f, 160f)
        k.put(KP.NOSE, 0f, -30f)
        return k
    }

    /** Standing and walking: [squat]'s straight-legged stand, [dx] pixels to the side of where it was. */
    fun walking(dx: Float): Array<Keypoint> {
        val k = squat(175f)
        for (i in k.indices) {
            if (k[i].score > 0f) k[i] = Keypoint(k[i].x + dx, k[i].y, k[i].score)
        }
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

    /**
     * A body on the bar with its legs in frame: [pullup] plus knees and ankles hanging straight
     * below the hips, a thigh and a shin of [LIMB] each.
     *
     * A hang is upright with straight legs, so everything that reads *standing* is true of it.
     * The hands on the bar are the only thing that says otherwise, which is the whole reason a
     * hang has to be read before standing is.
     */
    fun hangWithLegs(elbowDeg: Float): Array<Keypoint> {
        val k = pullup(elbowDeg)
        val hipX = (LIMB * sin(rad(elbowDeg))).toFloat()
        val hipY = (-LIMB * cos(rad(elbowDeg))).toFloat() + TORSO
        k.putPair(KP.LEFT_KNEE, KP.RIGHT_KNEE, hipX, hipY + LIMB)
        k.putPair(KP.LEFT_ANKLE, KP.RIGHT_ANKLE, hipX, hipY + 2f * LIMB)
        return k
    }

    /**
     * Kneeling up, torso upright and hips a thigh above the knees, with the ankles seen with full
     * confidence [ankleBehind] pixels behind the knee and on the floor with it.
     *
     * What kneeling looks like to a pose model that is sure of itself: the shin lies along the
     * floor, so the ankle sits level with the knee (a twentieth of a thigh below it, the worst the
     * Cindy clip ever showed) instead of a shin's length under it. The torso is upright and the
     * knees are far below the hips, so [PoseGeometry.standing] reads this as standing; only the
     * shins say it is not.
     */
    fun kneelingUp(ankleBehind: Float): Array<Keypoint> {
        val k = blank()
        k.putPair(KP.LEFT_KNEE, KP.RIGHT_KNEE, 0f, 0f)
        k.putPair(KP.LEFT_ANKLE, KP.RIGHT_ANKLE, -ankleBehind, 0.05f * LIMB)
        k.putPair(KP.LEFT_HIP, KP.RIGHT_HIP, 0f, -LIMB)
        k.putPair(KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, 0f, -LIMB - TORSO)
        k.put(KP.NOSE, 0f, -LIMB - TORSO - 30f)
        return k
    }

    /**
     * A body mid *inverted row* with the given elbow angle: hands on a low bar overhead, body
     * running away horizontally instead of hanging below.
     *
     * The arm chain is exactly [pullup]'s, because that is the point — the elbow swings through
     * the same range, the wrists sit above the hips, and the head reaches the bar line. Every
     * pull-up gate except the torso's direction is satisfied by a row, which is how three of
     * them scored as pull-ups on a real progression clip.
     */
    fun invertedRow(elbowDeg: Float): Array<Keypoint> {
        val k = blank()
        val shX = (LIMB * sin(rad(elbowDeg))).toFloat()
        val shY = (-LIMB * cos(rad(elbowDeg))).toFloat()
        k.putPair(KP.LEFT_ELBOW, KP.RIGHT_ELBOW, 0f, 0f)
        k.putPair(KP.LEFT_WRIST, KP.RIGHT_WRIST, 0f, -LIMB)
        k.putPair(KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, shX, shY)
        // The whole difference from a pull-up: the body runs out sideways from the shoulders
        // rather than hanging under them, so the torso is horizontal.
        k.putPair(KP.LEFT_HIP, KP.RIGHT_HIP, shX + TORSO, shY)
        k.putPair(KP.LEFT_KNEE, KP.RIGHT_KNEE, shX + TORSO + 80f, shY)
        k.putPair(KP.LEFT_ANKLE, KP.RIGHT_ANKLE, shX + TORSO + 160f, shY)
        k.put(KP.NOSE, shX, shY - 120f)
        return k
    }

    /**
     * Standing on the floor holding a resistance band at chest height, arms straight.
     *
     * The posture that taught a bar in the wrong place on real band footage: the hands are above
     * the hips and the elbows are extended, so every test the bar used to be learned from passes
     * — but the hands are below the head, because the band is being held in front of the chest
     * rather than gripped overhead.
     */
    fun bandSetup(): Array<Keypoint> {
        val k = blank()
        k.putPair(KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, 0f, 0f)
        k.putPair(KP.LEFT_HIP, KP.RIGHT_HIP, 0f, TORSO)
        // Arm hanging forward and down onto the band: shoulder, elbow and wrist near-collinear,
        // so the elbow reads as extended.
        k.putPair(KP.LEFT_ELBOW, KP.RIGHT_ELBOW, 0f, 0.2f * TORSO)
        k.putPair(KP.LEFT_WRIST, KP.RIGHT_WRIST, 0f, 0.4f * TORSO)
        // The head is above the hands, which is the whole difference from a hang.
        k.put(KP.NOSE, 0f, -0.4f * TORSO)
        k.putPair(KP.LEFT_KNEE, KP.RIGHT_KNEE, 0f, 2f * TORSO)
        k.putPair(KP.LEFT_ANKLE, KP.RIGHT_ANKLE, 0f, 3f * TORSO)
        return k
    }

    /** Nothing confidently detected — the "step into frame" case. */
    fun empty(): Array<Keypoint> = blank()
}
