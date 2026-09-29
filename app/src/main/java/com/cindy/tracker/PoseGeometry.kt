package com.cindy.tracker

import kotlin.math.acos
import kotlin.math.hypot

/**
 * Pure pose-geometry reads shared by [WorkoutEngine] and `AthleteLock`.
 *
 * Everything here is a stateless function of a keypoint array (and, where the answer depends on
 * it, the [Exercise] in question): no learned thresholds, no hold counters, nothing that depends
 * on frames seen before this one. [WorkoutEngine] keeps every stateful gate — the learned bar, a
 * hold counter such as `OVERHEAD_HOLD_FRAMES`, the calibrated band — itself, and calls in here
 * only for the geometry underneath them.
 */
internal object PoseGeometry {
    /** MoveNet confidence below which a keypoint is treated as unseen. */
    const val MIN_SCORE = 0.30f

    /**
     * How far the shoulders must sit above the hips, in torso lengths, to call the athlete
     * upright.
     *
     * A plank and a standing body both have straight legs, so the knee angle cannot tell
     * them apart — only the direction the torso is pointing can. A vertical torso scores
     * 1.0 and a horizontal one 0.0; the threshold leaves room for the forward lean of a
     * real squat and for a phone standing on the floor looking up.
     */
    const val UPRIGHT_TORSOS = 0.7f

    /**
     * How far the knees must sit below the hips, in torso lengths, to call the athlete stood
     * up rather than gathered in a crouch.
     *
     * A vertical torso is not standing. People get up off the floor by bringing the torso
     * upright first and collecting themselves on their haunches, which reads as upright for
     * most of a second — long enough to open a gate waiting only for that, after which the
     * drive out of the crouch scored as a rep. Standing carries the hips a whole thigh above
     * the knees; a crouch puts them level with, or below, them.
     *
     * An offset rather than a knee angle, on purpose: an angle threshold is what locked out
     * the athlete whose foreshortened full extension only read 145 degrees.
     */
    const val STANDING_TORSOS = 0.5f

    fun ok(p: Keypoint) = p.score >= MIN_SCORE

    fun midpoint(k: Array<Keypoint>, a: Int, b: Int): Keypoint? {
        val pa = k[a]
        val pb = k[b]
        return when {
            ok(pa) && ok(pb) -> Keypoint((pa.x + pb.x) / 2f, (pa.y + pb.y) / 2f, minOf(pa.score, pb.score))
            ok(pa) -> pa
            ok(pb) -> pb
            else -> null
        }
    }

    fun torsoLength(k: Array<Keypoint>): Float? {
        val sh = midpoint(k, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER) ?: return null
        val hp = midpoint(k, KP.LEFT_HIP, KP.RIGHT_HIP) ?: return null
        return hypot(sh.x - hp.x, sh.y - hp.y)
    }

    /** Averages the same joint angle on both sides, using whichever sides are confidently seen. */
    fun bilateralAngle(
        k: Array<Keypoint>,
        la: Int, lb: Int, lc: Int,
        ra: Int, rb: Int, rc: Int
    ): Float {
        val l = angle(k[la], k[lb], k[lc])
        val r = angle(k[ra], k[rb], k[rc])
        return when {
            !l.isNaN() && !r.isNaN() -> (l + r) / 2f
            !l.isNaN() -> l
            !r.isNaN() -> r
            else -> Float.NaN
        }
    }

    /** Interior angle at [b], in degrees, or NaN if any vertex is not confidently seen. */
    fun angle(a: Keypoint, b: Keypoint, c: Keypoint): Float {
        if (!ok(a) || !ok(b) || !ok(c)) return Float.NaN
        val abx = a.x - b.x
        val aby = a.y - b.y
        val cbx = c.x - b.x
        val cby = c.y - b.y
        val mag = hypot(abx, aby) * hypot(cbx, cby)
        if (mag < 1e-4f) return Float.NaN
        val cos = ((abx * cbx + aby * cby) / mag).coerceIn(-1f, 1f)
        return Math.toDegrees(acos(cos).toDouble()).toFloat()
    }

    /**
     * True when the shoulders sit well above the hips: torso vertical, not lying down.
     *
     * Shared by both movement families, and the only thing that tells them apart. It decides
     * whether a push-up has been taken up from the floor, and whether a pull is a hang rather
     * than an inverted row. Signed on purpose — it asks that the shoulders are above the hips,
     * not merely that the torso is vertical, so an upside-down body fails it too.
     */
    fun upright(k: Array<Keypoint>): Boolean {
        val sh = midpoint(k, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER) ?: return false
        val hp = midpoint(k, KP.LEFT_HIP, KP.RIGHT_HIP) ?: return false
        val torso = hypot(sh.x - hp.x, sh.y - hp.y)
        if (torso < 1f) return false
        return (hp.y - sh.y) >= UPRIGHT_TORSOS * torso
    }

    /** Upright *and* stood up on the legs, rather than folded over them in a crouch. */
    fun standing(k: Array<Keypoint>): Boolean {
        if (!upright(k)) return false
        val hp = midpoint(k, KP.LEFT_HIP, KP.RIGHT_HIP) ?: return false
        val kn = midpoint(k, KP.LEFT_KNEE, KP.RIGHT_KNEE) ?: return false
        val torso = torsoLength(k) ?: return false
        return (kn.y - hp.y) >= STANDING_TORSOS * torso
    }

    /**
     * Hands overhead, tested against the hips rather than the shoulders.
     *
     * The shoulders climb past the hands at the top of a good rep, so gating on them rejects the
     * peak of the movement. The hips stay well below the hands throughout, which separates
     * hanging from a push-up without discarding the reps worth counting.
     */
    fun hangingFromBar(k: Array<Keypoint>): Boolean {
        val hip = midpoint(k, KP.LEFT_HIP, KP.RIGHT_HIP) ?: return false
        val wr = midpoint(k, KP.LEFT_WRIST, KP.RIGHT_WRIST) ?: return false
        return wr.y < hip.y
    }

    /**
     * Whether the hands are above the head, which is what separates hanging from a grip that
     * merely happens to sit above the hips.
     *
     * At a dead hang the arms are overhead by definition, so the hands are clearly above the
     * nose; holding a band, a rope or a towel in front of the chest puts them clearly below it.
     * Only used to decide whether an *unknown* bar may be learned from this frame — once a bar
     * exists, [BarZone.holds] already constrains what may refine it.
     *
     * A head that cannot be seen does not block anything. Refusing to learn a bar whenever the
     * nose is missing would lock out the rear-view and occluded footage that already counts, and
     * this test exists to reject a specific wrong posture, not to demand a clear view of the face.
     */
    fun handsOverhead(k: Array<Keypoint>, hands: Keypoint): Boolean {
        val nose = k[KP.NOSE]
        return !ok(nose) || hands.y < nose.y
    }

    /** Joints the given movement cannot be judged without, named for a human. */
    fun missingJoints(k: Array<Keypoint>, exercise: Exercise): List<String> {
        val needed = when (exercise) {
            Exercise.PULLUP, Exercise.PUSHUP -> listOf(
                "shoulders" to (KP.LEFT_SHOULDER to KP.RIGHT_SHOULDER),
                "elbows" to (KP.LEFT_ELBOW to KP.RIGHT_ELBOW),
                "hands" to (KP.LEFT_WRIST to KP.RIGHT_WRIST),
                "hips" to (KP.LEFT_HIP to KP.RIGHT_HIP)
            )
            Exercise.SQUAT -> listOf(
                "shoulders" to (KP.LEFT_SHOULDER to KP.RIGHT_SHOULDER),
                "hips" to (KP.LEFT_HIP to KP.RIGHT_HIP),
                "knees" to (KP.LEFT_KNEE to KP.RIGHT_KNEE),
                "ankles" to (KP.LEFT_ANKLE to KP.RIGHT_ANKLE)
            )
        }
        // midpoint() accepts either side, so a joint counts as seen if one of the pair is.
        return needed.filter { midpoint(k, it.second.first, it.second.second) == null }.map { it.first }
    }
}
