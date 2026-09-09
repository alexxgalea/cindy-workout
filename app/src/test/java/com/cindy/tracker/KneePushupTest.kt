package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the push-up path can and cannot see, pinned down.
 *
 * These are characterisation tests, not a specification of what *ought* to happen: they record
 * that a knee push-up already scores as a push-up, and why. The push-up signal is the elbow
 * angle alone, and the gate in front of it asks only which way the torso points — so a kneeling
 * athlete passes both. No ankle, knee or shoulder-hip-ankle line is consulted anywhere in the
 * movement, which means there is no strictness rule here to relax for an adaptive mode, and
 * none to tighten without newly excluding people the app currently counts.
 *
 * Kept as a permanent fixture: if a future change starts refusing these reps, that is a product
 * decision about who the app is for, and it should have to break a test to make it.
 */
class KneePushupTest {

    /** Drives one engine on its own clock, so two can be compared frame for frame. */
    private class Driver(val engine: WorkoutEngine) {
        private var clock = 0L

        fun hold(pose: Array<Keypoint>, frames: Int = 10) {
            repeat(frames) {
                engine.onFrame(pose, clock)
                clock += 100
            }
        }

        /** Settles at the top, which is also what satisfies the start gate. */
        fun settleAtTop(pose: (Float) -> Array<Keypoint>) = hold(pose(175f))

        /** [n] descents and returns. Reps book at the top. */
        fun pushups(n: Int, pose: (Float) -> Array<Keypoint>) = repeat(n) {
            hold(pose(80f))
            hold(pose(175f))
        }

        fun pullups(n: Int) = repeat(n) {
            hold(PoseFixtures.pullup(170f))
            hold(PoseFixtures.pullup(60f))
        }
    }

    @Test
    fun `a knee push-up scores as a push-up`() {
        val d = Driver(WorkoutEngine(fixedExercise = Exercise.PUSHUP))

        d.settleAtTop(PoseFixtures::kneePushup)
        d.pushups(3, PoseFixtures::kneePushup)

        assertEquals("the engine has no rule a knee push-up breaks", 3, d.engine.reps)
    }

    /**
     * The mechanical reason, stated as an assertion rather than a comment.
     *
     * Both fixtures put the same shoulder-elbow-wrist chain in front of the camera; they differ
     * only below the hips, where nothing looks.
     */
    @Test
    fun `the engine cannot tell a knee push-up from a standard one`() {
        val strict = Driver(WorkoutEngine(fixedExercise = Exercise.PUSHUP))
        val knees = Driver(WorkoutEngine(fixedExercise = Exercise.PUSHUP))

        strict.settleAtTop(PoseFixtures::pushup)
        knees.settleAtTop(PoseFixtures::kneePushup)
        strict.pushups(4, PoseFixtures::pushup)
        knees.pushups(4, PoseFixtures::kneePushup)

        assertEquals(strict.engine.reps, knees.engine.reps)
        assertEquals("same elbow angle, same signal", strict.engine.signal, knees.engine.signal, 0.01f)
    }

    /**
     * The same finding in the real Cindy flow, where push-ups are entered from the start gate
     * that stops the walk to the floor scoring a rep.
     *
     * `inStartPosition` asks only `!upright`, and a kneeling plank's torso is horizontal, so the
     * gate opens for a kneeling athlete exactly as it does for a prone one.
     */
    @Test
    fun `knee push-ups count through the normal round transition`() {
        val d = Driver(WorkoutEngine())

        d.pullups(5)
        assertEquals(Exercise.PUSHUP, d.engine.exercise)
        assertTrue("push-ups are entered awaiting the start position", d.engine.awaitingStart)

        d.settleAtTop(PoseFixtures::kneePushup)
        assertFalse("kneeling satisfies the start gate", d.engine.awaitingStart)

        d.pushups(9, PoseFixtures::kneePushup)
        assertEquals("nine knee push-ups scored", 9, d.engine.reps)

        d.pushups(1, PoseFixtures::kneePushup)
        assertEquals("the tenth finishes the block", Exercise.SQUAT, d.engine.exercise)
    }
}
