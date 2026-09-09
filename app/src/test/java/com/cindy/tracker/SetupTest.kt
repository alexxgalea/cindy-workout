package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The pre-workout check: is the camera placed somewhere this movement can be read from? */
class SetupTest {

    private var clock = 0L

    private fun WorkoutEngine.setupHold(
        pose: Array<Keypoint>,
        frames: Int = 10,
        stepMs: Long = 100L
    ): Setup {
        var last = onSetupFrame(pose, clock)
        repeat(frames) {
            last = onSetupFrame(pose, clock)
            clock += stepMs
        }
        return last
    }

    private fun engine() = WorkoutEngine().also { it.beginSetup() }

    @Test
    fun `an empty frame names nothing it can see`() {
        val e = engine()
        val s = e.setupHold(PoseFixtures.empty(), frames = 3)
        assertEquals(SetupStage.FRAMING, s.stage)
        assertTrue(s.missing.containsAll(listOf("shoulders", "elbows", "hands", "hips")))
    }

    @Test
    fun `framing complains about the joints that are actually missing`() {
        val e = engine()
        val noHands = PoseFixtures.pullup(170f).copyOf()
        noHands[KP.LEFT_WRIST] = Keypoint(0f, 0f, 0f)
        noHands[KP.RIGHT_WRIST] = Keypoint(0f, 0f, 0f)
        val s = e.setupHold(noHands, frames = 3)
        assertEquals(SetupStage.FRAMING, s.stage)
        assertEquals(listOf("hands"), s.missing)
    }

    @Test
    fun `two calibration reps get the workout going`() {
        val e = engine()
        // Nothing may score while the setup check is still running.
        assertEquals(RepEvent.NONE, e.onFrame(PoseFixtures.pullup(60f), clock))
        assertEquals(0, e.reps)
        var last = e.setupHold(PoseFixtures.pullup(170f))
        assertEquals(SetupStage.MOVING, last.stage)
        repeat(2) {
            e.setupHold(PoseFixtures.pullup(170f))
            last = e.setupHold(PoseFixtures.pullup(60f))
        }
        assertEquals(SetupStage.READY, last.stage)
        assertEquals(2, last.reps)
    }

    @Test
    fun `calibrating from a low phone also gets going`() {
        val e = engine()
        var last: Setup? = null
        repeat(2) {
            e.setupHold(PoseFixtures.pullup(150f))
            last = e.setupHold(PoseFixtures.pullup(90f))
        }
        assertEquals(SetupStage.READY, last!!.stage)
    }

    @Test
    fun `a phone that cannot see the movement is called out rather than tolerated`() {
        val e = engine()
        var last: Setup? = null
        // Twenty-five seconds of a barely-there swing: framing is fine, placement is not.
        repeat(12) {
            e.setupHold(PoseFixtures.pullup(170f))
            last = e.setupHold(PoseFixtures.pullup(155f))
        }
        assertEquals(SetupStage.POOR, last!!.stage)
        assertTrue(last!!.range < last!!.needed)
    }

    @Test
    fun `the band survives setup so the first real rep is judged against it`() {
        val e = engine()
        repeat(2) {
            e.setupHold(PoseFixtures.pullup(170f))
            e.setupHold(PoseFixtures.pullup(55f))
        }
        val learned = e.learnedRange
        assertTrue("expected a learned range, got $learned", learned > 90f)

        e.finishSetup()
        assertEquals(0, e.reps)
        assertTrue("band should outlive the calibration reps", e.learnedRange > 90f)

        // A half rep against a band learned from full ones must not score.
        e.setupHold(PoseFixtures.pullup(170f), frames = 1)
        var event = RepEvent.NONE
        repeat(10) { event = e.onFrame(PoseFixtures.pullup(170f), clock); clock += 100 }
        repeat(10) { event = e.onFrame(PoseFixtures.pullup(120f), clock); clock += 100 }
        assertEquals(0, e.reps)
        assertEquals(RepEvent.NONE, event)
    }

    @Test
    fun `squat setup asks for the leg joints`() {
        val e = WorkoutEngine()
        e.skipExercise()
        e.skipExercise()
        e.beginSetup()
        assertEquals(Exercise.SQUAT, e.exercise)
        val s = e.setupHold(PoseFixtures.empty(), frames = 3)
        assertTrue(s.missing.containsAll(listOf("hips", "knees", "ankles")))
    }
}
