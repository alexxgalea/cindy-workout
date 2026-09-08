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
        // Elbow/knee angles are degrees; the pull-up signal is shoulder rise in torso-lengths.
        Exercise.PULLUP to RepCounter(downBelow = -0.85f, upAbove = -0.45f, minRepMs = 400L),
        Exercise.PUSHUP to RepCounter(downBelow = 100f, upAbove = 150f, minRepMs = 350L),
        Exercise.SQUAT to RepCounter(downBelow = 100f, upAbove = 158f, minRepMs = 350L)
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
            Exercise.PULLUP -> pullupSignal(k, torso)
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
     * Shoulder height relative to the hands, in torso-lengths, negated so that a dead hang is
     * the low value and chin-over-bar is the high one.
     *
     * Measuring the body rising toward the hands — rather than elbow flexion — is what makes
     * this a pull-up counter and not an arm-bend counter.
     */
    private fun pullupSignal(k: Array<Keypoint>, torso: Float): Float {
        val sh = midpoint(k, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER) ?: return Float.NaN
        val wr = midpoint(k, KP.LEFT_WRIST, KP.RIGHT_WRIST) ?: run {
            hint = "Hands out of frame"
            return Float.NaN
        }
        // Image y grows downward, so hands overhead means wr.y < sh.y.
        if (wr.y > sh.y) {
            hint = "Hang from the bar"
            return Float.NaN
        }
        return (wr.y - sh.y) / torso
    }

    /** Mean elbow angle in degrees; small at the bottom of a push-up, ~180 at lockout. */
    private fun pushupSignal(k: Array<Keypoint>): Float {
        val sh = midpoint(k, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER) ?: return Float.NaN
        val wr = midpoint(k, KP.LEFT_WRIST, KP.RIGHT_WRIST)
        // Guard against a pull-up being scored as a push-up.
        if (wr != null && wr.y < sh.y) {
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
