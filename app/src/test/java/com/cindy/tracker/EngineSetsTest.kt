package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * [WorkoutEngine.sets] must always sum to [WorkoutEngine.totalReps] — the same invariant
 * [SkippedRepsTest] holds for the plain rep count, extended to the per-movement breakdown a
 * Strava upload needs.
 */
class EngineSetsTest {

    private fun WorkoutEngine.tap(n: Int) = repeat(n) { manualRep() }

    private fun WorkoutEngine.assertSetsSumToTotal() =
        assertEquals(totalReps, sets.sumOf { it.reps })

    @Test
    fun `a fresh engine has one set, for the movement in progress, at zero`() {
        val e = WorkoutEngine()
        e.assertSetsSumToTotal()
        assertEquals(listOf(WorkoutSet(1, Exercise.PULLUP, 0)), e.sets)
    }

    @Test
    fun `sets sum to the total mid-round, after a skip books what was actually done`() {
        val e = WorkoutEngine()
        e.tap(5)                 // pull-ups, in full
        e.tap(3)                 // three push-ups
        e.skipExercise()         // banks three, not the target of ten
        e.tap(4)                 // four squats so far

        e.assertSetsSumToTotal()
        assertEquals(
            listOf(
                WorkoutSet(1, Exercise.PULLUP, 5),
                WorkoutSet(1, Exercise.PUSHUP, 3),
                WorkoutSet(1, Exercise.SQUAT, 4)
            ),
            e.sets
        )
    }

    @Test
    fun `a completed round files its sets under that round, and the next round starts its own`() {
        val e = WorkoutEngine()
        e.tap(5); e.tap(10); e.tap(15)
        e.tap(2)                  // two pull-ups into round two

        assertEquals(1, e.rounds)
        e.assertSetsSumToTotal()
        assertEquals(
            listOf(
                WorkoutSet(1, Exercise.PULLUP, 5),
                WorkoutSet(1, Exercise.PUSHUP, 10),
                WorkoutSet(1, Exercise.SQUAT, 15),
                WorkoutSet(2, Exercise.PULLUP, 2)
            ),
            e.sets
        )
    }

    @Test
    fun `undo across a movement boundary keeps the sets honest`() {
        val e = WorkoutEngine()
        e.tap(5); e.tap(3)
        e.skipExercise()          // three push-ups banked, now on squats
        e.undoRep()                // steps back into push-ups, at two

        assertEquals(Exercise.PUSHUP, e.exercise)
        e.assertSetsSumToTotal()
        assertEquals(
            listOf(WorkoutSet(1, Exercise.PULLUP, 5), WorkoutSet(1, Exercise.PUSHUP, 2)),
            e.sets
        )
    }

    @Test
    fun `undo across a round boundary restores that round's own sets`() {
        val e = WorkoutEngine()
        e.tap(5); e.tap(3)
        e.skipExercise()
        e.tap(15)                  // closes round one at 5, 3, 15
        e.undoRep()                 // steps back into round one's squats, at 14

        assertEquals(0, e.rounds)
        assertEquals(Exercise.SQUAT, e.exercise)
        e.assertSetsSumToTotal()
        assertEquals(
            listOf(
                WorkoutSet(1, Exercise.PULLUP, 5),
                WorkoutSet(1, Exercise.PUSHUP, 3),
                WorkoutSet(1, Exercise.SQUAT, 14)
            ),
            e.sets
        )
    }

    @Test
    fun `undo all the way back to zero still sums correctly`() {
        val e = WorkoutEngine()
        e.tap(1)
        e.undoRep()
        e.assertSetsSumToTotal()
        assertEquals(listOf(WorkoutSet(1, Exercise.PULLUP, 0)), e.sets)
    }

    @Test
    fun `three full rounds still sum, with every round's sets kept separate`() {
        val e = WorkoutEngine()
        repeat(3) { e.tap(5); e.tap(10); e.tap(15) }

        assertEquals(3, e.rounds)
        e.assertSetsSumToTotal()
        assertEquals(90, e.sets.sumOf { it.reps })
        assertEquals(setOf(1, 2, 3, 4), e.sets.map { it.round }.toSet())
    }
}
