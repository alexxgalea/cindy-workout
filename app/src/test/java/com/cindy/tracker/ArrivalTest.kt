package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Arriving in a movement's position is not the top of a rep.
 *
 * A fixed-movement engine never arms its start gate, so something that moves the athlete between
 * movements has to tell it when they have arrived again. [WorkoutEngine.dropClimbOnArrival] does
 * that and nothing more: it throws away the climb in flight, with no start gate. A start gate
 * loses whole sets on a head-on camera (the squat gate needs a still moment that continuous
 * squatting never gives), and the position rules of the recogniser already decide that the athlete
 * has arrived.
 */
class ArrivalTest {

    private var clock = 0L

    private fun WorkoutEngine.hold(pose: Array<Keypoint>, frames: Int = 10): Int {
        var reps = 0
        repeat(frames) {
            if (onFrame(pose, clock) == RepEvent.REP) reps++
            clock += 100
        }
        return reps
    }

    @Test
    fun `a squat climb in flight when the athlete arrives is not booked`() {
        val e = WorkoutEngine(fixedExercise = Exercise.SQUAT)
        e.hold(PoseFixtures.squat(80f))
        e.dropClimbOnArrival()
        assertEquals("the top of a climb that began before arriving", 0, e.hold(PoseFixtures.squat(175f)))
        assertEquals(0, e.reps)
    }

    @Test
    fun `without it the same climb is booked, so the test above proves something`() {
        val e = WorkoutEngine(fixedExercise = Exercise.SQUAT)
        e.hold(PoseFixtures.squat(80f))
        assertEquals(1, e.hold(PoseFixtures.squat(175f)))
    }

    @Test
    fun `a squat rep after arriving counts, with no still moment and no standing test asked for`() {
        val e = WorkoutEngine(fixedExercise = Exercise.SQUAT)
        e.hold(PoseFixtures.squat(80f))
        e.dropClimbOnArrival()
        e.hold(PoseFixtures.squat(175f))
        e.hold(PoseFixtures.squat(80f))
        assertEquals(1, e.hold(PoseFixtures.squat(175f)))
        assertEquals(1, e.reps)
    }

    @Test
    fun `a push-up climb in flight when the athlete arrives is not booked, and the next rep is`() {
        val e = WorkoutEngine(fixedExercise = Exercise.PUSHUP)
        e.hold(PoseFixtures.pushup(80f))
        e.dropClimbOnArrival()
        assertEquals(0, e.hold(PoseFixtures.pushup(175f)))
        e.hold(PoseFixtures.pushup(80f))
        assertEquals(1, e.hold(PoseFixtures.pushup(175f)))
    }

    @Test
    fun `it does not arm the start gate`() {
        val e = WorkoutEngine(fixedExercise = Exercise.PUSHUP)
        e.dropClimbOnArrival()
        assertEquals(false, e.awaitingStart)
    }

    private fun assistedPullupEngineOnTheBar(): WorkoutEngine {
        val e = WorkoutEngine(
            fixedExercise = Exercise.PULLUP,
            profile = CindyProfile(pull = PullVariant.BAND_ASSISTED_PULL_UP)
        )
        // Long enough for the 3 s settle to learn the bar without a dead hang.
        e.hold(PoseFixtures.pullup(170f), frames = 35)
        return e
    }

    @Test
    fun `a pull-up rep from a hang counts`() {
        val e = assistedPullupEngineOnTheBar()
        e.hold(PoseFixtures.pullup(170f))
        assertEquals(1, e.hold(PoseFixtures.pullup(60f)))
    }

    @Test
    fun `a pull-up climb in flight when the athlete arrives is not booked`() {
        val e = assistedPullupEngineOnTheBar()
        e.hold(PoseFixtures.pullup(170f))
        e.dropClimbOnArrival()
        assertEquals(0, e.hold(PoseFixtures.pullup(60f)))
        assertEquals(0, e.reps)
    }
}
