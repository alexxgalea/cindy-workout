package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Taking up a movement is not the first rep of it.
 *
 * Getting off the floor after a set of push-ups traces the second half of a squat: knees deeply
 * bent, then driven to full extension. The knee angle cannot tell that apart from a rep — and
 * neither can leg extension on its own, because lying face down with straight legs reads as a
 * perfect 180 too. Only the torso's direction separates them.
 */
class StartPositionTest {

    private var clock = 0L

    private fun WorkoutEngine.hold(pose: Array<Keypoint>, frames: Int = 10): List<RepEvent> {
        val events = mutableListOf<RepEvent>()
        repeat(frames) {
            val e = onFrame(pose, clock)
            if (e != RepEvent.NONE) events += e
            clock += 100
        }
        return events
    }

    private fun WorkoutEngine.doPullup() {
        hold(PoseFixtures.pullup(170f))
        hold(PoseFixtures.pullup(60f))
    }

    private fun WorkoutEngine.doPushup() {
        hold(PoseFixtures.pushup(175f))
        hold(PoseFixtures.pushup(80f))
        hold(PoseFixtures.pushup(175f))
    }

    /** Drives a full block of pull-ups and push-ups, leaving the engine on squats. */
    private fun engineOnSquats(): WorkoutEngine {
        val e = WorkoutEngine()
        repeat(5) { e.doPullup() }
        repeat(10) { e.doPushup() }
        assertEquals(Exercise.SQUAT, e.exercise)
        return e
    }

    @Test
    fun `lying on the floor reads as full leg extension`() {
        // The premise of the whole gate: this is why leg angle alone cannot start a squat.
        val e = WorkoutEngine(fixedExercise = Exercise.SQUAT)
        e.hold(PoseFixtures.onTheFloor())
        val flat = e.signal
        e.hold(PoseFixtures.squat(175f))
        assertEquals("a plank and a stand agree on the knees", flat, e.signal, 8f)
    }

    @Test
    fun `standing up after push-ups does not score a squat`() {
        val e = engineOnSquats()
        assertTrue(e.awaitingStart)

        // Face down at the end of the tenth push-up, then up through a crouch onto the feet.
        e.hold(PoseFixtures.onTheFloor())
        e.hold(PoseFixtures.squat(80f), frames = 3)
        e.hold(PoseFixtures.squat(175f))

        assertEquals("getting up off the floor is not a rep", 0, e.reps)
        assertFalse("but the movement has now started", e.awaitingStart)
    }

    @Test
    fun `real squats count once the athlete is standing`() {
        val e = engineOnSquats()
        e.hold(PoseFixtures.onTheFloor())
        e.hold(PoseFixtures.squat(175f))
        assertEquals(0, e.reps)

        repeat(3) {
            e.hold(PoseFixtures.squat(80f))
            e.hold(PoseFixtures.squat(175f))
        }
        assertEquals(3, e.reps)
    }

    @Test
    fun `the athlete is told what to do and it is worth saying out loud`() {
        val e = engineOnSquats()
        e.hold(PoseFixtures.onTheFloor())
        assertEquals("Stand up to start", e.hint)
        assertTrue("a hint nothing can be counted through is worth announcing", e.blocked)

        e.hold(PoseFixtures.squat(175f))
        assertFalse(e.blocked)
    }

    @Test
    fun `a moment upright on the way up is not enough`() {
        val e = engineOnSquats()
        e.hold(PoseFixtures.onTheFloor())
        // Two frames of vertical torso in passing, then face down again.
        e.hold(PoseFixtures.squat(90f), frames = 2)
        e.hold(PoseFixtures.onTheFloor(), frames = 2)
        assertTrue("half the posture for a fifth of a second starts nothing", e.awaitingStart)
    }

    @Test
    fun `dropping off the bar does not score a push-up`() {
        val e = WorkoutEngine()
        repeat(5) { e.doPullup() }
        assertEquals(Exercise.PUSHUP, e.exercise)
        assertTrue(e.awaitingStart)

        // Still on their feet, arms bending and straightening as they come off the bar.
        e.hold(PoseFixtures.squat(175f))
        e.hold(PoseFixtures.pullup(80f))
        e.hold(PoseFixtures.pullup(170f))
        assertEquals("nothing done standing up is a push-up", 0, e.reps)

        e.doPushup()
        assertEquals(1, e.reps)
    }

    @Test
    fun `stepping back into a movement does not ask for the position again`() {
        val e = engineOnSquats()
        e.hold(PoseFixtures.onTheFloor())
        e.hold(PoseFixtures.squat(175f))
        repeat(2) {
            e.hold(PoseFixtures.squat(80f))
            e.hold(PoseFixtures.squat(175f))
        }
        assertEquals(2, e.reps)

        e.undoRep()
        assertEquals(1, e.reps)
        assertFalse("the athlete is already mid-movement", e.awaitingStart)
    }
}
