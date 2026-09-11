package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * What a skipped movement is worth.
 *
 * A tester did three push-ups, hit SKIP, and the app recorded ten. The tally was inferred from
 * *position* — past the push-ups meant ten of them — which holds only while finishing is the one
 * way to leave a movement. SKIP is the other way, and these hold the line that it books what was
 * actually done.
 */
class SkippedRepsTest {

    private var clock = 0L

    /** Books [n] reps by hand, which is the same booking path the camera uses. */
    private fun WorkoutEngine.tap(n: Int): List<RepEvent> = (1..n).map {
        clock += 500L
        manualRep()
    }

    @Test
    fun `skipping a movement books the reps actually done, not its target`() {
        val engine = WorkoutEngine()
        engine.tap(5)                       // the pull-ups, in full
        engine.tap(3)                       // three push-ups
        assertEquals(8, engine.repsThisRound)

        engine.skipExercise()

        assertEquals(Exercise.SQUAT, engine.exercise)
        assertEquals("three push-ups is three reps, not ten", 8, engine.repsThisRound)
        assertEquals(8, engine.totalReps)
    }

    @Test
    fun `a skipped movement still completes the round`() {
        val engine = WorkoutEngine()
        engine.tap(5)
        engine.tap(3)
        engine.skipExercise()
        engine.tap(15)                      // the squats finish the round

        assertEquals("the round was completed", 1, engine.rounds)
        assertEquals(23, engine.totalReps)
        assertEquals("a new round starts empty", 0, engine.repsThisRound)
    }

    @Test
    fun `the event carries the score the movement reached`() {
        val engine = WorkoutEngine()
        engine.tap(5)
        engine.tap(3)

        assertEquals(RepEvent.EXERCISE_DONE, engine.skipExercise())
        assertEquals("the voice is owed three, not ten", 3, engine.repsAtLastEvent)
    }

    @Test
    fun `finishing a movement carries its target, as before`() {
        val engine = WorkoutEngine()
        val events = engine.tap(5)
        assertEquals(RepEvent.EXERCISE_DONE, events.last())
        assertEquals(5, engine.repsAtLastEvent)
    }

    @Test
    fun `a rep event carries its own number rather than the movement's count`() {
        val engine = WorkoutEngine()
        val spoken = (1..4).map { engine.tap(1); engine.repsAtLastEvent }
        assertEquals(listOf(1, 2, 3, 4), spoken)
    }

    @Test
    fun `undo steps back into what a skipped movement actually scored`() {
        val engine = WorkoutEngine()
        engine.tap(5)
        engine.tap(3)
        engine.skipExercise()               // now on squats, push-ups banked at 3

        assertEquals(RepEvent.UNDO, engine.undoRep())

        assertEquals(Exercise.PUSHUP, engine.exercise)
        assertEquals("undo must not hand back reps that were never done", 2, engine.reps)
        assertEquals(7, engine.repsThisRound)
    }

    @Test
    fun `undo steps back over a round boundary into that round's real score`() {
        val engine = WorkoutEngine()
        engine.tap(5)
        engine.tap(3)
        engine.skipExercise()
        engine.tap(15)
        assertEquals(1, engine.rounds)

        engine.undoRep()

        assertEquals(0, engine.rounds)
        assertEquals(Exercise.SQUAT, engine.exercise)
        assertEquals(14, engine.reps)
        assertEquals("5 + 3 + 14", 22, engine.totalReps)
    }

    @Test
    fun `a reset forgets every banked movement`() {
        val engine = WorkoutEngine()
        engine.tap(5)
        engine.tap(3)
        engine.skipExercise()
        engine.tap(15)

        engine.reset()

        assertEquals(0, engine.rounds)
        assertEquals(0, engine.totalReps)
        assertEquals(0, engine.repsThisRound)
        assertEquals(Exercise.PULLUP, engine.exercise)
    }

    @Test
    fun `a full unskipped round is still worth thirty`() {
        val engine = WorkoutEngine()
        engine.tap(5)
        engine.tap(10)
        engine.tap(15)

        assertEquals(1, engine.rounds)
        assertEquals(30, engine.totalReps)
    }

    @Test
    fun `an attempt reports the reps it counted rather than its round tally`() {
        val skipped = Attempt(
            rounds = 2, reps = 4, atMillis = 0L, countedReps = 47
        )
        assertEquals(47, skipped.totalReps)

        val old = Attempt(rounds = 2, reps = 4, atMillis = 0L)
        assertEquals("an old record keeps saying what it always said", 64, old.totalReps)
    }

    @Test
    fun `the counted total survives a round trip through the record store`() {
        val attempt = Attempt(
            rounds = 3, reps = 7, atMillis = 1_700_000_000_000L,
            durationMs = 1_200_000L, countedReps = 82
        )
        val back = Records.decode(Records.encode(listOf(attempt))).single()
        assertEquals(82, back.countedReps)
        assertEquals(82, back.totalReps)
    }
}
