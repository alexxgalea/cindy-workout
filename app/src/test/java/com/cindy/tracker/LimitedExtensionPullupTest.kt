package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The athlete whose arms never straighten, and the difference between a standard and a lockout.
 *
 * Someone hanging in a band, or with limited elbow extension, may never reach
 * `DEAD_HANG_FLOOR_DEGREES`. Two separate things used to follow from that, and only one of them
 * was a movement standard:
 *
 *  - The bar was never established. An unknown bar has no line, so every pull-up frame was
 *    refused before any gate was consulted, and the whole workout scored zero under "Hang from
 *    the bar" — with no overlay drawn, because the overlay is the bar. That was a lockout.
 *  - The dead-hang reset never armed, so nothing counted. That one *is* the strict standard: a
 *    strict pull-up starts from a dead hang, and an athlete who cannot reach one is not doing
 *    the strict movement. The answer to it is a variation, not a looser strict mode.
 *
 * These tests hold that line: the bar is now findable without a dead hang, and strict counting
 * is exactly as strict as it was.
 */
class LimitedExtensionPullupTest {

    /** As straight as this athlete's arms get — well under the floor a dead hang needs. */
    private val straightest = 120f

    private class Driver(val engine: WorkoutEngine) {
        private var clock = 0L

        fun hold(pose: Array<Keypoint>, frames: Int) = repeat(frames) {
            engine.onFrame(pose, clock)
            clock += 100
        }
    }

    @Test
    fun `hands held still overhead locate the bar when no dead hang ever comes`() {
        val d = Driver(WorkoutEngine(fixedExercise = Exercise.PULLUP))
        val hang = PoseFixtures.pullup(straightest)

        d.hold(hang, frames = 20)
        assertFalse("two seconds is not yet sustained stillness", d.engine.barKnown)

        d.hold(hang, frames = 15)
        assertTrue("a still overhead hang eventually locates the bar", d.engine.barKnown)
    }

    /**
     * The fallback is a fallback: a real dead hang still establishes the bar immediately, so a
     * strict athlete never waits three seconds for an overlay.
     */
    @Test
    fun `a dead hang still locates the bar at once`() {
        val d = Driver(WorkoutEngine(fixedExercise = Exercise.PULLUP))

        d.hold(PoseFixtures.pullup(170f), frames = 1)

        assertTrue("one straight-armed frame is enough", d.engine.barKnown)
    }

    /**
     * Moving hands are not a hang.
     *
     * This is the case the dead-hang requirement was really guarding: someone walking up to the
     * bar with their arms overhead taught a bar in the wrong place and then spent the rest of
     * the clip being refused by it. Drift restarts the dwell, so the walk-up never settles.
     */
    @Test
    fun `hands drifting across the frame do not locate a bar`() {
        val d = Driver(WorkoutEngine(fixedExercise = Exercise.PULLUP))

        repeat(12) { step ->
            val walking = PoseFixtures.pullup(straightest).also { k ->
                val shift = step * 30f
                for (i in intArrayOf(
                    KP.NOSE, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, KP.LEFT_ELBOW, KP.RIGHT_ELBOW,
                    KP.LEFT_WRIST, KP.RIGHT_WRIST, KP.LEFT_HIP, KP.RIGHT_HIP
                )) {
                    k[i] = Keypoint(k[i].x + shift, k[i].y, k[i].score)
                }
            }
            d.hold(walking, frames = 5)
        }

        assertFalse("a walk-up never settles, so it teaches nothing", d.engine.barKnown)
    }

    /**
     * The standard, unchanged.
     *
     * Full range of motion — sixty degrees of elbow travel, head over the bar and back below the
     * reset line — but never a straight arm, so a strict pull-up is not what happened.
     */
    @Test
    fun `strict mode still refuses to score an athlete who never dead hangs`() {
        val d = Driver(WorkoutEngine(fixedExercise = Exercise.PULLUP))

        d.hold(PoseFixtures.pullup(straightest), frames = 35)
        assertTrue("the bar is known, so the refusal is the gate and not the geometry", d.engine.barKnown)

        repeat(5) {
            d.hold(PoseFixtures.pullup(60f), frames = 8)
            d.hold(PoseFixtures.pullup(straightest), frames = 8)
        }

        assertEquals("a strict pull-up starts from a dead hang", 0, d.engine.reps)
    }
}
