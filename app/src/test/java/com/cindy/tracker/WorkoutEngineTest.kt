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

    private fun WorkoutEngine.doPullup(hang: Float = 170f, top: Float = 60f) {
        hold(PoseFixtures.pullup(hang))
        hold(PoseFixtures.pullup(top))
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
    fun `a squat seen from a low phone still counts`() {
        val e = WorkoutEngine()
        e.skipExercise(); e.skipExercise()
        assertEquals(Exercise.SQUAT, e.exercise)
        repeat(6) {
            e.hold(PoseFixtures.squat(85f))
            e.hold(PoseFixtures.squat(145f))
        }
        assertEquals(6, e.reps)
    }

    @Test
    fun `pull-ups that barely bend the arms score nothing`() {
        val e = WorkoutEngine()
        repeat(5) {
            e.hold(PoseFixtures.pullup(170f))
            e.hold(PoseFixtures.pullup(145f)) // 25 degrees of travel: a twitch, not a rep
        }
        assertEquals(0, e.reps)
    }

    @Test
    fun `a pull-up seen from a low phone still counts despite the squashed range`() {
        // A phone on the floor foreshortens everything above it, so the same rep projects a
        // much smaller elbow swing. The counter should calibrate to it rather than miss it.
        val e = WorkoutEngine()
        repeat(5) { e.doPullup(hang = 150f, top = 90f) }
        assertEquals(Exercise.PUSHUP, e.exercise)
        assertEquals(5, e.repsThisRound)
    }

    @Test
    fun `an even harsher camera angle still counts`() {
        val e = WorkoutEngine()
        repeat(4) { e.doPullup(hang = 140f, top = 95f) }
        assertEquals(4, e.reps)
    }

    @Test
    fun `once full reps set the standard, partial ones stop counting`() {
        val e = WorkoutEngine()
        repeat(2) { e.doPullup(hang = 170f, top = 55f) }
        assertEquals(2, e.reps)
        // Half-height reps against a band learned from full ones.
        repeat(4) { e.doPullup(hang = 170f, top = 120f) }
        assertEquals(2, e.reps)
    }

    @Test
    fun `the shoulders rising above the hands does not void the rep`() {
        // The old signal rejected exactly this frame, so the best reps were the ones it lost.
        val e = WorkoutEngine()
        repeat(5) { e.doPullup(hang = 175f, top = 45f) }
        assertEquals(Exercise.PUSHUP, e.exercise)
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
    fun `minus takes a rep back`() {
        val e = WorkoutEngine()
        repeat(3) { e.doPullup() }
        assertEquals(RepEvent.UNDO, e.undoRep())
        assertEquals(2, e.reps)
    }

    @Test
    fun `minus steps back over a movement boundary`() {
        val e = WorkoutEngine()
        repeat(5) { e.doPullup() }
        assertEquals(Exercise.PUSHUP, e.exercise)
        assertEquals(RepEvent.UNDO, e.undoRep())
        assertEquals(Exercise.PULLUP, e.exercise)
        assertEquals(4, e.reps)
    }

    @Test
    fun `minus steps back over a round boundary`() {
        val e = WorkoutEngine()
        repeat(5) { e.doPullup() }
        repeat(10) { e.doPushup() }
        repeat(15) { e.doSquat() }
        assertEquals(1, e.rounds)
        assertEquals(RepEvent.UNDO, e.undoRep())
        assertEquals(0, e.rounds)
        assertEquals(Exercise.SQUAT, e.exercise)
        assertEquals(14, e.reps)
        assertEquals(29, e.totalReps)
    }

    @Test
    fun `minus at the very start does nothing`() {
        val e = WorkoutEngine()
        assertEquals(RepEvent.NONE, e.undoRep())
        assertEquals(0, e.totalReps)
        assertEquals(Exercise.PULLUP, e.exercise)
    }

    @Test
    fun `plus then minus leaves the score where it started`() {
        val e = WorkoutEngine()
        repeat(2) { e.doPullup() }
        e.manualRep()
        assertEquals(3, e.reps)
        e.undoRep()
        assertEquals(2, e.reps)
    }

    @Test
    fun `recalibrating keeps the reps but forgets the band`() {
        val e = WorkoutEngine()
        repeat(3) { e.doPullup() }
        assertTrue(e.calibrated)
        e.recalibrate()
        assertEquals(3, e.reps)
        assertFalse(e.calibrated)
        assertEquals(0f, e.learnedRange, 0.001f)
    }

    @Test
    fun `a recalibrated counter re-learns from the next reps`() {
        val e = WorkoutEngine()
        repeat(3) { e.doPullup() }
        e.recalibrate()
        repeat(2) { e.doPullup() }
        assertEquals(Exercise.PUSHUP, e.exercise)
    }

    @Test
    fun `recalibrating mid-round does not disturb the round count`() {
        val e = WorkoutEngine()
        repeat(5) { e.doPullup() }
        repeat(4) { e.doPushup() }
        e.recalibrate()
        assertEquals(0, e.rounds)
        assertEquals(Exercise.PUSHUP, e.exercise)
        assertEquals(9, e.repsThisRound)
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
