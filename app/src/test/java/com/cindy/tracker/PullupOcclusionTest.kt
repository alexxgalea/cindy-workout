package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Occlusion handling on the bar.
 *
 * A pull-up hides its own keypoints exactly where the rep is decided: at the top the head tilts
 * back and the wrists pass behind it. The engine used to treat the first unreadable frame as
 * "left the bar" and throw the cycle away, which cost nine of every ten reps on real footage.
 * These tests pin the replacement rule — a short blackout is ridden out, a long one is not —
 * without loosening what it means to be on the bar.
 */
class PullupOcclusionTest {

    private var clock = 0L

    private fun WorkoutEngine.hold(pose: Array<Keypoint>, frames: Int = 10) {
        repeat(frames) {
            onFrame(pose, clock)
            clock += 100
        }
    }

    /** Blanks one keypoint, the way MoveNet reports a joint it cannot see. */
    private fun Array<Keypoint>.hiding(index: Int): Array<Keypoint> =
        copyOf().also { it[index] = Keypoint(0f, 0f, 0f) }

    /** Shifts a whole body, as if the athlete stepped off the bar. */
    private fun Array<Keypoint>.moved(dx: Float, dy: Float): Array<Keypoint> =
        Array(size) { i ->
            val p = this[i]
            if (p.score <= 0f) p else Keypoint(p.x + dx, p.y + dy, p.score)
        }

    @Test
    fun `a brief head dropout at the top does not lose the rep`() {
        val e = WorkoutEngine()
        e.hold(PoseFixtures.pullup(170f))
        // The nose vanishes for a few frames just as the chin clears the bar.
        e.hold(PoseFixtures.pullup(60f).hiding(KP.NOSE), frames = 4)
        e.hold(PoseFixtures.pullup(60f))
        assertEquals("a four-frame blackout must not cancel the rep", 1, e.reps)
    }

    @Test
    fun `a brief wrist dropout at the top does not lose the rep`() {
        val e = WorkoutEngine()
        e.hold(PoseFixtures.pullup(170f))
        e.hold(PoseFixtures.pullup(60f).hiding(KP.LEFT_WRIST), frames = 4)
        e.hold(PoseFixtures.pullup(60f))
        assertEquals(1, e.reps)
    }

    @Test
    fun `a sustained dropout ends the cycle`() {
        val e = WorkoutEngine()
        e.hold(PoseFixtures.pullup(170f))
        // Long enough to be indistinguishable from having dropped off the bar.
        e.hold(PoseFixtures.pullup(60f).hiding(KP.NOSE), frames = 20)
        e.hold(PoseFixtures.pullup(60f))
        assertEquals("a long blackout must not be ridden out", 0, e.reps)
    }

    @Test
    fun `a cycle killed by a long dropout recovers on the next dead hang`() {
        val e = WorkoutEngine()
        e.hold(PoseFixtures.pullup(170f))
        e.hold(PoseFixtures.pullup(60f).hiding(KP.NOSE), frames = 20)
        e.hold(PoseFixtures.pullup(60f))
        assertEquals(0, e.reps)

        e.hold(PoseFixtures.pullup(170f))
        e.hold(PoseFixtures.pullup(60f))
        assertEquals("the athlete is not locked out after one bad rep", 1, e.reps)
    }

    @Test
    fun `push-up motion under the bar never scores a pull-up`() {
        val e = WorkoutEngine()
        // Same elbow swing, but the hands are on the floor rather than overhead.
        repeat(6) {
            e.hold(PoseFixtures.pushup(170f))
            e.hold(PoseFixtures.pushup(70f))
        }
        assertEquals(0, e.reps)
    }

    @Test
    fun `one clean rep then leaving the bar still counts one`() {
        val e = WorkoutEngine()
        e.hold(PoseFixtures.pullup(170f))
        e.hold(PoseFixtures.pullup(60f))
        assertEquals(1, e.reps)

        // Steps down and repeats the identical arm movement on the floor.
        repeat(4) {
            e.hold(PoseFixtures.pullup(170f).moved(0f, 400f))
            e.hold(PoseFixtures.pullup(60f).moved(0f, 400f))
        }
        assertEquals("off-bar repetitions must not add to the score", 1, e.reps)
    }

    @Test
    fun `partial reps whose chin never crosses the bar do not count`() {
        val e = WorkoutEngine()
        repeat(5) {
            e.hold(PoseFixtures.pullup(170f))
            e.hold(PoseFixtures.pullup(120f))
        }
        assertEquals(0, e.reps)
    }

    @Test
    fun `a dropout while off the bar cannot revive the cycle`() {
        val e = WorkoutEngine()
        // Learn the bar from one honest rep.
        e.hold(PoseFixtures.pullup(170f))
        e.hold(PoseFixtures.pullup(60f))
        assertEquals(1, e.reps)

        // Drop off the bar, then go unreadable there. The blackout must not be treated as a
        // continuation of an on-bar cycle.
        e.hold(PoseFixtures.pullup(170f).moved(0f, 400f))
        e.hold(PoseFixtures.pullup(60f).moved(0f, 400f).hiding(KP.NOSE), frames = 4)
        e.hold(PoseFixtures.pullup(60f).moved(0f, 400f))
        assertEquals(1, e.reps)
    }
}
