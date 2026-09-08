package com.cindy.tracker

import kotlin.math.acos
import kotlin.math.hypot

/** One round of Cindy: 5 pull-ups, 10 push-ups, 15 air squats. */
enum class Exercise(val label: String, val spoken: String, val target: Int) {
    PULLUP("PULL-UPS", "pull ups", 5),
    PUSHUP("PUSH-UPS", "push ups", 10),
    SQUAT("SQUATS", "squats", 15);

    fun next(): Exercise = entries[(ordinal + 1) % entries.size]
}

/** What the last analysed frame produced. */
enum class RepEvent { NONE, REP, EXERCISE_DONE, ROUND_DONE }

/**
 * Turns a stream of keypoints into a Cindy scorecard.
 *
 * Only the signal for the *current* exercise is evaluated. That is deliberate: the three
 * movements share joints, and scoring all of them at once lets a push-up lockout leak into
 * the squat counter.
 */
class WorkoutEngine {

    private companion object {
        /** MoveNet confidence below which a keypoint is treated as unseen. */
        const val MIN_SCORE = 0.30f
    }

    private val counters = mapOf(
        // All three signals are joint angles in degrees. The pull-up one is negated because a
        // dead hang is the *extended* end of its range, the opposite way round to the others.
        // minRange is the projected travel below which a swing is not believed to be a rep at
        // all; above it the counter calibrates to the athlete and the fixed numbers stop mattering.
        Exercise.PULLUP to RepCounter(-140f, -100f, minRepMs = 400L, minRange = 40f),
        Exercise.PUSHUP to RepCounter(100f, 150f, minRepMs = 350L, minRange = 45f),
        Exercise.SQUAT to RepCounter(100f, 158f, minRepMs = 350L, minRange = 55f)
    )

    var exercise = Exercise.PULLUP
        private set
    var rounds = 0
        private set
    /** Human-readable reason the current frame did or did not score. */
    var hint = "Step into frame"
        private set
    var bodyVisible = false
        private set

    val reps: Int get() = counters.getValue(exercise).count
    val phase: RepCounter.Phase get() = counters.getValue(exercise).phase
    val signal: Float get() = counters.getValue(exercise).smoothed
    val learnedRange: Float get() = counters.getValue(exercise).learnedRange
    val calibrated: Boolean get() = counters.getValue(exercise).calibrated

    /** Reps completed since the start of the current round, across all three movements. */
    val repsThisRound: Int
        get() = Exercise.entries.take(exercise.ordinal).sumOf { it.target } + reps

    val totalReps: Int get() = rounds * 30 + repsThisRound

    fun reset() {
        counters.values.forEach { it.reset() }
        exercise = Exercise.PULLUP
        rounds = 0
        hint = "Step into frame"
        bodyVisible = false
    }

    /** Advances past the current exercise without finishing it (manual override). */
    fun skipExercise(): RepEvent = advance()

    /** Books one rep by hand, for when the camera angle defeats the detector. */
    fun manualRep(): RepEvent {
        counters.getValue(exercise).forceIncrement()
        return settle()
    }

    fun onFrame(k: Array<Keypoint>, now: Long): RepEvent {
        val torso = torsoLength(k)
        if (torso == null || torso < 1f) {
            bodyVisible = false
            hint = "Step into frame"
            return RepEvent.NONE
        }
        bodyVisible = true

        val s = when (exercise) {
            Exercise.PULLUP -> pullupSignal(k)
            Exercise.PUSHUP -> pushupSignal(k)
            Exercise.SQUAT -> squatSignal(k)
        }

        if (s.isNaN()) return RepEvent.NONE

        val counted = counters.getValue(exercise).update(s, now)
        if (!counted) {
            hint = if (phase == RepCounter.Phase.DOWN) "Drive up" else "Go down"
            return RepEvent.NONE
        }
        return settle()
    }

    /** Advances to the next movement if the current one just hit its target. */
    private fun settle(): RepEvent =
        if (reps >= exercise.target) advance() else RepEvent.REP

    private fun advance(): RepEvent {
        counters.getValue(exercise).resetCount()
        val wasLast = exercise == Exercise.SQUAT
        exercise = exercise.next()
        counters.getValue(exercise).resetCount()
        return if (wasLast) {
            rounds++
            RepEvent.ROUND_DONE
        } else {
            RepEvent.EXERCISE_DONE
        }
    }

    // ── signals ───────────────────────────────────────────────────────────────

    /**
     * Mean elbow angle, negated: about -170 at a dead hang, about -60 with the chin over the bar.
     *
     * An earlier version measured how far the shoulders rose toward the hands, divided by torso
     * length. That undercounted badly for two compounding reasons. Dividing by torso length put
     * the hip keypoints in the denominator, and hips are the *least* reliable joints on someone
     * hanging with their knees bent behind them — a hip estimate drifting low inflates the
     * divisor and shrinks the signal until it no longer reaches the arming threshold. Worse, the
     * posture guard rejected any frame where the shoulders rose above the hands, which is
     * exactly what happens at the top of a strong pull-up: the better the rep, the more reliably
     * it was thrown away.
     *
     * An angle needs no normalisation, so nothing about the athlete's build, their distance from
     * the camera, or where MoveNet thinks their hips are can move the thresholds.
     */
    private fun pullupSignal(k: Array<Keypoint>): Float {
        if (!hangingFromBar(k)) {
            hint = "Hang from the bar"
            return Float.NaN
        }
        val elbow = bilateralAngle(
            k,
            KP.LEFT_SHOULDER, KP.LEFT_ELBOW, KP.LEFT_WRIST,
            KP.RIGHT_SHOULDER, KP.RIGHT_ELBOW, KP.RIGHT_WRIST
        )
        if (elbow.isNaN()) hint = "Arms out of frame"
        return -elbow
    }

    /**
     * Hands overhead, tested against the hips rather than the shoulders.
     *
     * The shoulders climb past the hands at the top of a good rep, so gating on them rejects the
     * peak of the movement. The hips stay well below the hands throughout, which separates
     * hanging from a push-up without discarding the reps worth counting.
     */
    private fun hangingFromBar(k: Array<Keypoint>): Boolean {
        val hip = midpoint(k, KP.LEFT_HIP, KP.RIGHT_HIP) ?: return false
        val wr = midpoint(k, KP.LEFT_WRIST, KP.RIGHT_WRIST) ?: return false
        return wr.y < hip.y
    }

    /** Mean elbow angle in degrees; small at the bottom of a push-up, ~180 at lockout. */
    private fun pushupSignal(k: Array<Keypoint>): Float {
        // Guard against a pull-up being scored as a push-up, using the same overhead test.
        if (hangingFromBar(k)) {
            hint = "Get on the floor"
            return Float.NaN
        }
        return bilateralAngle(
            k,
            KP.LEFT_SHOULDER, KP.LEFT_ELBOW, KP.LEFT_WRIST,
            KP.RIGHT_SHOULDER, KP.RIGHT_ELBOW, KP.RIGHT_WRIST
        )
    }

    /** Mean knee angle in degrees; small in the hole, ~180 standing. */
    private fun squatSignal(k: Array<Keypoint>): Float = bilateralAngle(
        k,
        KP.LEFT_HIP, KP.LEFT_KNEE, KP.LEFT_ANKLE,
        KP.RIGHT_HIP, KP.RIGHT_KNEE, KP.RIGHT_ANKLE
    ).also { if (it.isNaN()) hint = "Show your legs to the camera" }

    // ── geometry helpers ──────────────────────────────────────────────────────

    private fun ok(p: Keypoint) = p.score >= MIN_SCORE

    private fun midpoint(k: Array<Keypoint>, a: Int, b: Int): Keypoint? {
        val pa = k[a]
        val pb = k[b]
        return when {
            ok(pa) && ok(pb) -> Keypoint((pa.x + pb.x) / 2f, (pa.y + pb.y) / 2f, minOf(pa.score, pb.score))
            ok(pa) -> pa
            ok(pb) -> pb
            else -> null
        }
    }

    private fun torsoLength(k: Array<Keypoint>): Float? {
        val sh = midpoint(k, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER) ?: return null
        val hp = midpoint(k, KP.LEFT_HIP, KP.RIGHT_HIP) ?: return null
        return hypot(sh.x - hp.x, sh.y - hp.y)
    }

    /** Averages the same joint angle on both sides, using whichever sides are confidently seen. */
    private fun bilateralAngle(
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
    private fun angle(a: Keypoint, b: Keypoint, c: Keypoint): Float {
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
}
