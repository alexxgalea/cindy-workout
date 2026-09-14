package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * The bounds on the predicted skeleton.
 *
 * Prediction exists to hide pipeline latency, and the way it goes wrong is by drawing a joint
 * where the body never went. Every test here is a bound on that: the cases assert what the
 * predictor *refuses* to do at least as often as what it does.
 *
 * The reversal case is the one that matters. At the top of a pull-up the athlete stops rising and
 * starts falling, and that is the frame they are watching to see whether the rep counted.
 */
class PosePredictionTest {

    private val ms = 1_000_000L

    /** A body spanning 200px, so the shift ceiling is a round 30px. */
    private fun body(x: Float, y: Float, score: Float = 0.9f): Array<Keypoint> =
        Array(KP.COUNT) { i ->
            when (i) {
                KP.LEFT_WRIST -> Keypoint(x, y, score)
                // Two fixed joints 200px apart give bodySpan something to measure.
                KP.LEFT_ANKLE -> Keypoint(0f, 200f, 0.9f)
                KP.NOSE -> Keypoint(0f, 0f, 0.9f)
                else -> Keypoint(0f, 0f, 0f)
            }
        }

    private fun resolve(
        oldest: Array<Keypoint>,
        previous: Array<Keypoint>,
        newest: Array<Keypoint>,
        gapMs: Long = 100L,
        aheadMs: Long = 50L,
        pipelineAgeMs: Float = 0f
    ): FloatArray {
        val out = FloatArray(KP.COUNT * 2)
        val t0 = 0L
        val t1 = gapMs * ms
        val t2 = 2 * gapMs * ms
        PosePrediction.resolve(
            newest = newest, newestNanos = t2,
            previous = previous, previousNanos = t1,
            oldest = oldest, oldestNanos = t0,
            nowNanos = t2 + aheadMs * ms,
            pipelineAgeMs = pipelineAgeMs,
            out = out
        )
        return out
    }

    private fun wristY(out: FloatArray) = out[KP.LEFT_WRIST * 2 + 1]
    private fun wristX(out: FloatArray) = out[KP.LEFT_WRIST * 2]

    @Test
    fun `the horizon covers the lag the pose arrived with, not just the redraw gap`() {
        // The bug this replaced: the horizon was measured from when the pose was PUBLISHED, so a
        // skeleton 200ms behind the body was carried forward by the tens of milliseconds since
        // the last redraw and stayed 200ms behind. Rising 10px per 100ms, 150ms of pipeline lag
        // plus 50ms since publication is 200ms of ground to make up: 20px, not 5px.
        val out = resolve(
            body(0f, 120f), body(0f, 110f), body(0f, 100f),
            gapMs = 100, aheadMs = 50, pipelineAgeMs = 150f
        )
        assertEquals(80f, wristY(out), 0.001f)
    }

    @Test
    fun `pipeline lag is still bounded by the cap`() {
        val absurd = resolve(
            body(0f, 120f), body(0f, 110f), body(0f, 100f),
            gapMs = 100, aheadMs = 50, pipelineAgeMs = 9_000f
        )
        val capped = resolve(
            body(0f, 120f), body(0f, 110f), body(0f, 100f),
            gapMs = 100, aheadMs = 0, pipelineAgeMs = PosePrediction.MAX_AHEAD_MS
        )
        assertEquals(wristY(capped), wristY(absurd), 0.001f)
    }

    @Test
    fun `a decelerating joint fades out before it has to be cut off`() {
        // Slowing from 30px per 100ms to 10px: still rising, so the sign rule allows it, but the
        // ramp scales it down. Without the ramp this would be a full 5px and then a hard drop to
        // zero on the frame the direction flipped — a visible snap at the top of every rep.
        val ramped = resolve(body(0f, 140f), body(0f, 110f), body(0f, 100f))
        val steady = resolve(body(0f, 120f), body(0f, 110f), body(0f, 100f))
        val rampedShift = 100f - wristY(ramped)
        val steadyShift = 100f - wristY(steady)
        assertTrue("the ramp must still predict something, got $rampedShift", rampedShift > 0f)
        assertTrue(
            "a slowing joint must predict less than a steady one: $rampedShift vs $steadyShift",
            rampedShift < steadyShift
        )
    }

    @Test
    fun `an accelerating joint is not damped past constant velocity`() {
        // Speeding up from 10px to 30px per 100ms. The ramp is clamped at 1, so this predicts
        // exactly the constant-velocity answer and never more — magnitude is only ever allowed
        // to make this more conservative.
        val out = resolve(body(0f, 140f), body(0f, 130f), body(0f, 100f))
        assertEquals("30px per 100ms carried 50ms", 85f, wristY(out), 0.001f)
    }

    @Test
    fun `without history the newest pose is drawn exactly`() {
        val out = FloatArray(KP.COUNT * 2)
        val newest = body(40f, 90f)
        PosePrediction.resolve(
            newest = newest, newestNanos = 0L,
            previous = null, previousNanos = 0L,
            oldest = null, oldestNanos = 0L,
            nowNanos = 500 * ms,
            pipelineAgeMs = 200f,
            out = out
        )
        assertEquals(40f, wristX(out), 0.001f)
        assertEquals(90f, wristY(out), 0.001f)
    }

    @Test
    fun `a joint moving steadily is carried forward along its velocity`() {
        // Rising 10px per 100ms; half a gap ahead should be 5px further up.
        val out = resolve(body(0f, 120f), body(0f, 110f), body(0f, 100f), gapMs = 100, aheadMs = 50)
        assertEquals(95f, wristY(out), 0.001f)
    }

    @Test
    fun `a reversal predicts nothing, which is the top of a pull-up`() {
        // Up 10px, then down 10px: the athlete has turned around.
        val out = resolve(body(0f, 110f), body(0f, 100f), body(0f, 110f), gapMs = 100, aheadMs = 50)
        assertEquals(
            "a joint that just changed direction must be drawn where it was last seen",
            110f, wristY(out), 0.001f
        )
    }

    @Test
    fun `one axis reversing does not freeze the other`() {
        // Sliding steadily right while turning around vertically.
        val out = resolve(body(0f, 110f), body(10f, 100f), body(20f, 110f), gapMs = 100, aheadMs = 50)
        assertEquals("x is still rising and carries on", 25f, wristX(out), 0.001f)
        assertEquals("y reversed and holds", 110f, wristY(out), 0.001f)
    }

    @Test
    fun `a joint that was still is not set moving`() {
        val out = resolve(body(0f, 100f), body(0f, 100f), body(0f, 90f), gapMs = 100, aheadMs = 50)
        assertEquals(90f, wristY(out), 0.001f)
    }

    @Test
    fun `a wild velocity is clamped to a share of the body`() {
        // 400px in 100ms, extrapolated 50ms, would be 200px — a wrist across the whole picture.
        val out = resolve(body(0f, 900f), body(0f, 500f), body(0f, 100f), gapMs = 100, aheadMs = 50)
        val span = PosePrediction.bodySpan(body(0f, 100f))
        val limit = span * PosePrediction.MAX_SHIFT_SHARE
        assertTrue("limit should be a real number, was $limit", limit > 0f)
        assertEquals(100f - limit, wristY(out), 0.001f)
    }

    @Test
    fun `prediction never reaches further ahead than the cap`() {
        // Asking 5 seconds ahead must give the same answer as asking at the cap.
        val far = resolve(body(0f, 120f), body(0f, 110f), body(0f, 100f), gapMs = 100, aheadMs = 5_000)
        val capped = resolve(
            body(0f, 120f), body(0f, 110f), body(0f, 100f),
            gapMs = 100, aheadMs = PosePrediction.MAX_AHEAD_MS.toLong()
        )
        assertEquals(wristY(capped), wristY(far), 0.001f)
    }

    @Test
    fun `a stall is not a frame interval`() {
        // A gap longer than MAX_GAP_MS says the pipeline stopped, not that the body moved slowly.
        val out = resolve(body(0f, 120f), body(0f, 110f), body(0f, 100f), gapMs = 600, aheadMs = 50)
        assertEquals(100f, wristY(out), 0.001f)
    }

    @Test
    fun `a joint unseen in any of the three poses is not predicted`() {
        val faded = body(0f, 110f, score = 0.1f)
        val out = resolve(faded, body(0f, 105f), body(0f, 100f), gapMs = 100, aheadMs = 50)
        assertEquals(100f, wristY(out), 0.001f)
    }

    @Test
    fun `every predicted joint stays within the cap of where it was seen`() {
        // The property behind the individual cases: whatever the input, nothing moves far.
        val span = PosePrediction.bodySpan(body(0f, 100f))
        val limit = span * PosePrediction.MAX_SHIFT_SHARE
        for (dy in listOf(-900f, -37f, -1f, 0f, 1f, 37f, 900f)) {
            for (dx in listOf(-900f, -12f, 0f, 12f, 900f)) {
                val out = resolve(
                    body(-2 * dx, 100f - 2 * dy),
                    body(-dx, 100f - dy),
                    body(0f, 100f),
                    gapMs = 100, aheadMs = 120
                )
                assertTrue(
                    "dx=$dx dy=$dy moved x by ${abs(wristX(out))}",
                    abs(wristX(out) - 0f) <= limit + 0.001f
                )
                assertTrue(
                    "dx=$dx dy=$dy moved y by ${abs(wristY(out) - 100f)}",
                    abs(wristY(out) - 100f) <= limit + 0.001f
                )
            }
        }
    }
}
