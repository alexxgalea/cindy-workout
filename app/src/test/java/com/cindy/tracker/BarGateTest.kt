package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The bar gate: elbow flexion only counts when the hands are actually on the bar. */
class BarGateTest {

    private var clock = 0L

    private fun WorkoutEngine.hold(pose: Array<Keypoint>, frames: Int = 10) {
        repeat(frames) {
            onFrame(pose, clock)
            clock += 100
        }
    }

    private fun WorkoutEngine.doPullup(hang: Float = 170f, top: Float = 60f) {
        hold(PoseFixtures.pullup(hang))
        hold(PoseFixtures.pullup(top))
    }

    /** Shrinks a body about the origin, as if the athlete were much further from the camera. */
    private fun Array<Keypoint>.scaled(factor: Float): Array<Keypoint> =
        Array(size) { i ->
            val p = this[i]
            if (p.score <= 0f) p else Keypoint(p.x * factor, p.y * factor, p.score)
        }

    /** Shifts a whole body sideways and down, as if the athlete stepped off the bar. */
    private fun Array<Keypoint>.moved(dx: Float, dy: Float): Array<Keypoint> =
        Array(size) { i ->
            val p = this[i]
            if (p.score <= 0f) p else Keypoint(p.x + dx, p.y + dy, p.score)
        }

    @Test
    fun `the bar is unknown until someone hangs from it`() {
        val e = WorkoutEngine()
        assertFalse(e.barKnown)
        // A body the tracker has lost is not evidence about where the bar is.
        repeat(5) {
            e.onFrame(PoseFixtures.pullup(170f), clock, identityStable = false)
            clock += 100
        }
        assertFalse(e.barKnown)
        e.hold(PoseFixtures.pullup(170f))
        assertTrue("a dead hang should mark the bar", e.barKnown)
    }

    @Test
    fun `a bent-armed frame alone does not mark the bar`() {
        val e = WorkoutEngine()
        e.hold(PoseFixtures.pullup(60f))
        assertFalse(e.barKnown)
        e.hold(PoseFixtures.pullup(170f))

        // Bent elbows are not a rep on their own: the head has to clear the bar.
        val chinBelowBar = PoseFixtures.pullup(60f).copyOf()
        chinBelowBar[KP.NOSE] = Keypoint(0f, 0f, 0.9f)
        e.hold(chinBelowBar)
        assertEquals(0, e.reps)
        assertEquals("Get your head over the bar", e.hint)

        // A pull-up needs both grips, so one hand leaving the bar ends the rep.
        val oneHandOffBar = PoseFixtures.pullup(60f).copyOf()
        oneHandOffBar[KP.LEFT_WRIST] = oneHandOffBar[KP.LEFT_WRIST].let {
            Keypoint(it.x + 1000f, it.y, it.score)
        }
        e.hold(oneHandOffBar)
        assertEquals(0, e.reps)
        assertEquals("Get on the bar", e.hint)

        // The invalidated cycle cannot be finished by a recovered top frame; it needs a fresh
        // dead hang first.
        e.hold(PoseFixtures.pullup(60f))
        assertEquals(0, e.reps)
        e.hold(PoseFixtures.pullup(170f))
        e.hold(PoseFixtures.pullup(60f))
        assertEquals(1, e.reps)
    }

    @Test
    fun `reps at the bar count normally`() {
        val e = WorkoutEngine()
        repeat(5) { e.doPullup() }
        assertEquals(Exercise.PUSHUP, e.exercise)
    }

    @Test
    fun `the same arm movement well below the bar scores nothing`() {
        val e = WorkoutEngine()
        // Learn the bar from two honest reps.
        repeat(2) { e.doPullup() }
        assertTrue(e.barKnown)
        assertEquals(2, e.reps)

        // Now do the identical elbow movement 400px lower — off the bar, arms overhead.
        repeat(6) {
            e.hold(PoseFixtures.pullup(170f).moved(0f, 400f))
            e.hold(PoseFixtures.pullup(60f).moved(0f, 400f))
        }
        assertEquals("arm-waving off the bar must not score", 2, e.reps)
        assertEquals("Get on the bar", e.hint)
    }

    @Test
    fun `the same movement far to the side scores nothing`() {
        val e = WorkoutEngine()
        repeat(2) { e.doPullup() }
        repeat(6) {
            e.hold(PoseFixtures.pullup(170f).moved(500f, 0f))
            e.hold(PoseFixtures.pullup(60f).moved(500f, 0f))
        }
        assertEquals(2, e.reps)
    }

    @Test
    fun `stepping back onto the bar resumes counting`() {
        val e = WorkoutEngine()
        repeat(2) { e.doPullup() }
        repeat(2) {
            e.hold(PoseFixtures.pullup(170f).moved(0f, 400f))
            e.hold(PoseFixtures.pullup(60f).moved(0f, 400f))
        }
        assertEquals(2, e.reps)
        repeat(3) { e.doPullup() }
        assertEquals("back on the bar, counting continues", Exercise.PUSHUP, e.exercise)
    }

    @Test
    fun `a small shift along the bar is still on the bar`() {
        val e = WorkoutEngine()
        repeat(2) { e.doPullup() }
        // Half a torso sideways is a regrip, not stepping off.
        repeat(3) {
            e.hold(PoseFixtures.pullup(170f).moved(40f, 0f))
            e.hold(PoseFixtures.pullup(60f).moved(40f, 0f))
        }
        assertEquals(Exercise.PUSHUP, e.exercise)
    }

    @Test
    fun `recalibrating forgets the bar so a moved camera does not block counting`() {
        val e = WorkoutEngine()
        repeat(2) { e.doPullup() }
        assertTrue(e.barKnown)
        e.recalibrate()
        assertFalse("a moved camera invalidates the bar's position", e.barKnown)

        // The whole scene has shifted; counting must recover rather than stay blocked.
        repeat(3) {
            e.hold(PoseFixtures.pullup(170f).moved(0f, 400f))
            e.hold(PoseFixtures.pullup(60f).moved(0f, 400f))
        }
        assertEquals(Exercise.PUSHUP, e.exercise)
    }

    @Test
    fun `setup learns the bar before the workout starts`() {
        val e = WorkoutEngine()
        e.beginSetup()
        repeat(2) {
            repeat(10) { e.onSetupFrame(PoseFixtures.pullup(170f), clock); clock += 100 }
            repeat(10) { e.onSetupFrame(PoseFixtures.pullup(60f), clock); clock += 100 }
        }
        assertTrue("calibration reps should mark the bar", e.barKnown)
        e.finishSetup()
        assertTrue("and it survives into the workout", e.barKnown)
    }

    @Test
    fun `off-bar movement at the same scale never re-learns the bar`() {
        val e = WorkoutEngine()
        e.doPullup()
        assertEquals(1, e.reps)

        // A long run of the identical movement on the floor. The body is the same size, so this
        // is someone who stepped down — not evidence that the bar was learned in the wrong place.
        repeat(10) {
            e.hold(PoseFixtures.pullup(170f).moved(0f, 400f))
            e.hold(PoseFixtures.pullup(60f).moved(0f, 400f))
        }
        assertEquals("floor repetitions must never re-teach the bar", 1, e.reps)
    }

    @Test
    fun `a brief contradiction at another scale does not abandon the bar`() {
        val e = WorkoutEngine()
        e.hold(PoseFixtures.pullup(170f))
        // Under MAX_BAR_CONTRADICTIONS (30) consecutive refused hangs.
        e.hold(PoseFixtures.pullup(170f).scaled(0.4f), frames = 20)
        e.hold(PoseFixtures.pullup(60f).scaled(0.4f))
        assertEquals("the bar must not move on a brief contradiction", 0, e.reps)
    }

    @Test
    fun `a sustained contradiction at another scale re-learns the bar`() {
        val e = WorkoutEngine()
        e.hold(PoseFixtures.pullup(170f))
        // Past the limit: the athlete is plainly hanging, at a body scale the learned bar cannot
        // describe, so the estimate rather than the athlete is treated as wrong.
        e.hold(PoseFixtures.pullup(170f).scaled(0.4f), frames = 40)
        e.hold(PoseFixtures.pullup(60f).scaled(0.4f))
        assertEquals("counting must recover once the bar is re-learned", 1, e.reps)
    }
}
