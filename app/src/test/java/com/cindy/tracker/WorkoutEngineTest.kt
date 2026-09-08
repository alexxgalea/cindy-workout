package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkoutEngineTest {

    private var clock = 0L

    /** Pushes one posture for several frames, advancing the clock, collecting events. */
    private fun WorkoutEngine.hold(
        pose: Array<Keypoint>,
        frames: Int = 10,
        stepMs: Long = 100L
    ): List<RepEvent> {
        val events = mutableListOf<RepEvent>()
        repeat(frames) {
            val e = onFrame(pose, clock)
            if (e != RepEvent.NONE) events += e
            clock += stepMs
        }
        return events
    }

    private fun WorkoutEngine.doSquat() {
        hold(PoseFixtures.squat(80f))
        hold(PoseFixtures.squat(175f))
    }

    private fun WorkoutEngine.doPushup() {
        hold(PoseFixtures.pushup(80f))
        hold(PoseFixtures.pushup(175f))
    }

    private fun WorkoutEngine.doPullup() {
        hold(PoseFixtures.pullup(riseFromHands = 115f))
        hold(PoseFixtures.pullup(riseFromHands = 25f))
    }

    @Test
    fun `starts on pull-ups with a clean scorecard`() {
        val e = WorkoutEngine()
        assertEquals(Exercise.PULLUP, e.exercise)
        assertEquals(0, e.reps)
        assertEquals(0, e.rounds)
        assertEquals(0, e.totalReps)
    }

    @Test
    fun `an empty frame reports the body as missing and scores nothing`() {
        val e = WorkoutEngine()
        e.hold(PoseFixtures.empty(), frames = 5)
        assertFalse(e.bodyVisible)
        assertEquals(0, e.reps)
        assertEquals("Step into frame", e.hint)
    }

    @Test
    fun `pull-ups count and hand over to push-ups at five`() {
        val e = WorkoutEngine()
        repeat(4) { e.doPullup() }
        assertEquals(Exercise.PULLUP, e.exercise)
        assertEquals(4, e.reps)

        e.doPullup()
        assertEquals(Exercise.PUSHUP, e.exercise)
        assertEquals(0, e.reps)
        assertEquals(5, e.repsThisRound)
    }

    @Test
    fun `push-ups count and hand over to squats at ten`() {
        val e = WorkoutEngine()
        repeat(5) { e.doPullup() }
        repeat(9) { e.doPushup() }
        assertEquals(Exercise.PUSHUP, e.exercise)
        assertEquals(9, e.reps)

        e.doPushup()
        assertEquals(Exercise.SQUAT, e.exercise)
        assertEquals(15, e.repsThisRound)
    }

    @Test
    fun `a full round of Cindy closes and restarts on pull-ups`() {
        val e = WorkoutEngine()
        repeat(5) { e.doPullup() }
        repeat(10) { e.doPushup() }
        repeat(14) { e.doSquat() }
        assertEquals(0, e.rounds)

        e.doSquat()
        assertEquals(1, e.rounds)
        assertEquals(Exercise.PULLUP, e.exercise)
        assertEquals(0, e.reps)
        assertEquals(30, e.totalReps)
    }

    @Test
    fun `three full rounds score ninety reps`() {
        val e = WorkoutEngine()
        repeat(3) {
            repeat(5) { e.doPullup() }
            repeat(10) { e.doPushup() }
            repeat(15) { e.doSquat() }
        }
        assertEquals(3, e.rounds)
        assertEquals(90, e.totalReps)
    }

    @Test
    fun `squatting during the pull-up block scores nothing`() {
        val e = WorkoutEngine()
        repeat(6) { e.doSquat() }
        assertEquals(Exercise.PULLUP, e.exercise)
        assertEquals(0, e.reps)
    }

    @Test
    fun `push-up reps do not leak into the pull-up block`() {
        val e = WorkoutEngine()
        repeat(6) { e.doPushup() }
        assertEquals(Exercise.PULLUP, e.exercise)
        assertEquals(0, e.reps)
        assertTrue(e.hint.isNotEmpty())
    }

    @Test
    fun `hanging on the bar during the push-up block scores nothing`() {
        val e = WorkoutEngine()
        repeat(5) { e.doPullup() }
        assertEquals(Exercise.PUSHUP, e.exercise)
        repeat(6) { e.doPullup() }
        assertEquals(0, e.reps)
        assertEquals(Exercise.PUSHUP, e.exercise)
    }

    @Test
    fun `partial pull-ups that never reach the top score nothing`() {
        val e = WorkoutEngine()
        repeat(5) {
            e.hold(PoseFixtures.pullup(riseFromHands = 115f))
            e.hold(PoseFixtures.pullup(riseFromHands = 95f)) // barely bends the arms
        }
        assertEquals(0, e.reps)
    }

    @Test
    fun `shallow squats above the depth threshold score nothing`() {
        val e = WorkoutEngine()
        repeat(5) { e.doPullup() }
        repeat(10) { e.doPushup() }
        assertEquals(Exercise.SQUAT, e.exercise)
        repeat(5) {
            e.hold(PoseFixtures.squat(175f))
            e.hold(PoseFixtures.squat(130f)) // quarter squat
        }
        assertEquals(0, e.reps)
    }

    @Test
    fun `the manual override books a rep and advances the block`() {
        val e = WorkoutEngine()
        repeat(4) { e.manualRep() }
        assertEquals(4, e.reps)
        assertEquals(Exercise.PULLUP, e.exercise)
        assertEquals(RepEvent.EXERCISE_DONE, e.manualRep())
        assertEquals(Exercise.PUSHUP, e.exercise)
    }

    @Test
    fun `skip jumps to the next movement without scoring reps`() {
        val e = WorkoutEngine()
        assertEquals(RepEvent.EXERCISE_DONE, e.skipExercise())
        assertEquals(Exercise.PUSHUP, e.exercise)
        assertEquals(0, e.reps)
        assertEquals(5, e.repsThisRound)
    }

    @Test
    fun `skipping through squats closes the round`() {
        val e = WorkoutEngine()
        e.skipExercise()
        e.skipExercise()
        assertEquals(Exercise.SQUAT, e.exercise)
        assertEquals(RepEvent.ROUND_DONE, e.skipExercise())
        assertEquals(1, e.rounds)
    }

    @Test
    fun `reset returns the engine to the start of Cindy`() {
        val e = WorkoutEngine()
        repeat(5) { e.doPullup() }
        repeat(3) { e.doPushup() }
        e.reset()
        assertEquals(Exercise.PULLUP, e.exercise)
        assertEquals(0, e.reps)
        assertEquals(0, e.rounds)
        assertEquals(0, e.totalReps)
    }
}
