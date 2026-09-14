package com.cindy.tracker

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sign

/**
 * Where to draw each joint *now*, given poses that were computed some time ago.
 *
 * ### Why draw anything other than the last pose
 *
 * The skeleton is an honest report of a frame that has already happened. Between the camera and
 * the screen sit a bitmap conversion, a crop, a brightness pass and a model, and the athlete has
 * kept moving through all of it — so a faithful drawing of the last completed pose is, by
 * construction, a drawing of where the body was, not where it is.
 *
 * Carrying each joint forward along the velocity it was last seen moving at trades that lag for a
 * different error: the skeleton is now a guess, and a guess can be wrong in a way a late-but-true
 * drawing never is. The whole design here is about bounding that wrongness.
 *
 * ### The three bounds, and the one that matters
 *
 * 1. **Three poses, and a joint confident in all of them.** Two poses give a velocity but no way
 *    to see a direction change. A joint that has just appeared has no history to carry.
 *
 * 2. **A reversal stops it dead.** If a joint's last two velocities disagree in sign on an axis,
 *    it is turning around, and prediction on that axis drops to zero for the frame.
 *
 *    This is the bound that earns the feature. The top of a pull-up is a hard direction reversal,
 *    and it is the exact instant the athlete is looking at the screen to see whether the rep
 *    counted — the worst possible moment to draw them somewhere they are not. Sign agreement
 *    rather than a magnitude test on purpose: at the frame rates this runs at, velocity
 *    *magnitudes* off noisy keypoints are far less trustworthy than their *direction*.
 *
 * 3. **A hard cap on the shift**, as a share of the body's own size on screen, so one mis-tracked
 *    frame cannot fling a wrist across the picture.
 *
 * Display only. The counting engine never sees these numbers — it scores the true keypoints, and
 * nothing here is ported to the Python or Swift engines or touched by the parity check.
 */
object PosePrediction {

    /**
     * Furthest ahead of the *capture* a joint may ever be drawn.
     *
     * Sized against the measured pipeline: ~190-212ms from sensor to published pose on the test
     * handset. A cap below that cannot close the gap it exists to close, which is precisely the
     * mistake the first version made.
     */
    const val MAX_AHEAD_MS = 250f
    /** Gaps longer than this are a stall, not a frame interval; a velocity from one is fiction. */
    const val MAX_GAP_MS = 500f
    /** Ceiling on a predicted shift, as a share of the body's larger dimension. */
    const val MAX_SHIFT_SHARE = 0.15f
    /** Below this a keypoint is treated as unseen, matching the overlay and the engine. */
    const val MIN_SCORE = 0.30f

    /**
     * Fills [out] — `KP.COUNT * 2` floats, x then y per joint — with frame-pixel positions.
     *
     * Passing null for [previous] or [oldest] means "no prediction", which is how the caller
     * switches the feature off and what happens for the first two frames of every workout.
     */
    fun resolve(
        newest: Array<Keypoint>,
        newestNanos: Long,
        previous: Array<Keypoint>?,
        previousNanos: Long,
        oldest: Array<Keypoint>?,
        oldestNanos: Long,
        nowNanos: Long,
        pipelineAgeMs: Float,
        out: FloatArray
    ) {
        for (i in 0 until KP.COUNT) {
            out[i * 2] = newest[i].x
            out[i * 2 + 1] = newest[i].y
        }
        if (previous == null || oldest == null) return

        val recentGap = (newestNanos - previousNanos) / 1_000_000f
        val earlierGap = (previousNanos - oldestNanos) / 1_000_000f
        if (recentGap <= 0f || earlierGap <= 0f) return
        if (recentGap > MAX_GAP_MS || earlierGap > MAX_GAP_MS) return

        // THE HORIZON IS MEASURED FROM CAPTURE, NOT FROM PUBLICATION.
        //
        // The first version of this got it wrong and the mistake is worth keeping written down,
        // because the reasoning that produced it was half right. Poses are stamped when they are
        // published — after the bitmap conversion, the crop, the brightness pass and the model —
        // and those stamps are the correct basis for VELOCITY, because only the intervals between
        // them matter and those intervals track the intervals between captures.
        //
        // They are the wrong basis for the HORIZON. A pose published now describes where the body
        // was when the shutter opened, which on the measured handset is 190-212ms ago. Extrapolating
        // from the publish stamp corrected for the gap between redraws — tens of milliseconds —
        // and left the entire pipeline lag untouched. Switched on, it looked *worse* than off,
        // because the redraw loop also cost analysis frame rate, so the underlying pose was
        // staler than before and barely moved forward to compensate.
        val ahead = min((nowNanos - newestNanos) / 1_000_000f + pipelineAgeMs, MAX_AHEAD_MS)
        if (ahead <= 0f) return

        val limit = bodySpan(newest) * MAX_SHIFT_SHARE
        if (limit <= 0f) return

        for (i in 0 until KP.COUNT) {
            val a = oldest[i]
            val b = previous[i]
            val c = newest[i]
            if (a.score < MIN_SCORE || b.score < MIN_SCORE || c.score < MIN_SCORE) continue

            out[i * 2] += shift((b.x - a.x) / earlierGap, (c.x - b.x) / recentGap, ahead, limit)
            out[i * 2 + 1] += shift((b.y - a.y) / earlierGap, (c.y - b.y) / recentGap, ahead, limit)
        }
    }

    /**
     * One axis of one joint: carry it forward unless it is turning around, and never far.
     *
     * Two guards, in order of how much they are trusted:
     *
     * **Sign, not magnitude.** A joint that was rising and is now falling gets nothing, and so
     * does one that was still — a velocity of exactly zero agrees with no direction, which is the
     * conservative reading and the one that cannot invent movement.
     *
     * **Then a deceleration ramp.** A hard cut at the reversal leaves a visible snap: mid-stroke
     * the skeleton sits on the body, and the frame the direction flips it drops back by the whole
     * prediction. Scaling by how much the joint has slowed removes the step, because a joint
     * approaching the top of a rep is decelerating for several frames before it actually turns —
     * the prediction fades out before it would have to be cut off.
     *
     * This uses velocity magnitude, which the sign rule above deliberately does not trust. It is
     * allowed here because it is clamped to 1: a noisy magnitude can only ever make this *more*
     * conservative than plain constant velocity, never less.
     */
    fun shift(earlier: Float, recent: Float, aheadMs: Float, limit: Float): Float {
        if (sign(earlier) != sign(recent)) return 0f
        if (abs(earlier) < 1e-6f) return 0f
        val damp = min(1f, abs(recent) / abs(earlier))
        val moved = recent * damp * aheadMs
        return if (abs(moved) > limit) limit * sign(moved) else moved
    }

    /** The body's larger dimension in frame pixels, which is what a shift is judged against. */
    fun bodySpan(k: Array<Keypoint>): Float {
        var left = Float.MAX_VALUE
        var top = Float.MAX_VALUE
        var right = -Float.MAX_VALUE
        var bottom = -Float.MAX_VALUE
        var seen = 0
        for (p in k) {
            if (p.score < MIN_SCORE) continue
            left = min(left, p.x); right = max(right, p.x)
            top = min(top, p.y); bottom = max(bottom, p.y)
            seen++
        }
        if (seen < 2) return 0f
        return max(right - left, bottom - top)
    }
}
