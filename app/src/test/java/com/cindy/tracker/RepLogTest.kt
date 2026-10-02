package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RepLogTest {

    @Test
    fun `a rep appends one mark at the clock it banked`() {
        val log = RepLog()
        log.start()
        log.follow(totalReps = 1, manualReps = 0, movement = Exercise.PULLUP, clockMs = 500L)
        assertEquals(listOf(RepMark(500L, Exercise.PULLUP, manual = false)), log.marks)
    }

    @Test
    fun `the finishing rep is tagged with the movement it left`() {
        val log = RepLog()
        log.start()
        // Reps 1-4 of the pull-ups.
        repeat(4) { i -> log.follow(i + 1, 0, Exercise.PULLUP, 1_000L * (i + 1)) }
        // The 5th rep finishes the movement: the engine has already moved snap.exercise on to
        // push-ups by the time this is read, so the caller passes the movement that was left.
        log.follow(5, 0, Exercise.PULLUP, 5_000L)
        assertEquals(Exercise.PULLUP, log.marks.last().movement)
        assertEquals(5, log.marks.size)
    }

    @Test
    fun `a skip adds nothing`() {
        val log = RepLog()
        log.start()
        log.follow(3, 0, Exercise.PULLUP, 1_000L)
        // SKIP fires EXERCISE_DONE/ROUND_DONE too, but never changes the total.
        log.follow(3, 0, Exercise.PULLUP, 1_500L)
        assertEquals(3, log.marks.size)
    }

    @Test
    fun `undo removes the latest mark, even across a movement boundary`() {
        val log = RepLog()
        log.start()
        repeat(5) { i -> log.follow(i + 1, 0, Exercise.PULLUP, 1_000L * (i + 1)) }
        log.follow(6, 0, Exercise.PUSHUP, 6_000L) // the first push-up
        assertEquals(Exercise.PUSHUP, log.marks.last().movement)

        // Undo steps back into the pull-ups; snap.exercise is PULLUP again by the time it is read.
        log.follow(5, 0, Exercise.PULLUP, 6_500L)

        assertEquals(5, log.marks.size)
        assertEquals(Exercise.PULLUP, log.marks.last().movement)
    }

    @Test
    fun `undo never removes more marks than exist`() {
        val log = RepLog()
        log.start()
        log.follow(1, 0, Exercise.SQUAT, 1_000L)
        log.follow(-4, 0, Exercise.SQUAT, 1_500L) // defensive: the engine never does this
        assertTrue(log.marks.isEmpty())
    }

    @Test
    fun `a tapped rep is flagged manual`() {
        val log = RepLog()
        log.start()
        log.follow(1, 1, Exercise.SQUAT, 1_000L)
        assertTrue(log.marks.single().manual)
    }

    @Test
    fun `a jump of two appends two marks at the same instant`() {
        val log = RepLog()
        log.start()
        // Two reps banked between the frames this log actually saw — a dropped stale snapshot.
        log.follow(2, 0, Exercise.SQUAT, 4_000L)
        assertEquals(listOf(4_000L, 4_000L), log.marks.map { it.clockMs })
        assertEquals(listOf(false, false), log.marks.map { it.manual })
    }

    @Test
    fun `only the newest reps of a jump are flagged manual`() {
        val log = RepLog()
        log.start()
        log.follow(2, 1, Exercise.SQUAT, 4_000L) // two reps banked, the more recent one tapped
        assertEquals(listOf(false, true), log.marks.map { it.manual })
    }

    @Test
    fun `start clears every mark`() {
        val log = RepLog()
        log.start()
        log.follow(3, 0, Exercise.PULLUP, 1_000L)

        log.start()

        assertTrue(log.marks.isEmpty())
        log.follow(1, 0, Exercise.PULLUP, 500L)
        assertEquals(1, log.marks.size)
    }
}
