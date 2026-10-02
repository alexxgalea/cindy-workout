package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RepTimesTest {

    private fun attempt(countedReps: Int?, durationMs: Long = 20_000L) = Attempt(
        rounds = 0, reps = countedReps ?: 0, atMillis = 0L, durationMs = durationMs,
        countedReps = countedReps
    )

    @Test
    fun `round trips a session of marks`() {
        val marks = listOf(
            RepMark(1_000L, Exercise.PULLUP, manual = false),
            RepMark(2_000L, Exercise.PULLUP, manual = true),
            RepMark(5_000L, Exercise.PUSHUP, manual = false)
        )
        assertEquals(marks, RepTimes.decode(RepTimes.encode(marks)))
    }

    @Test
    fun `round trips no marks at all`() {
        assertEquals(emptyList<RepMark>(), RepTimes.decode(RepTimes.encode(emptyList())))
    }

    @Test
    fun `a malformed line is skipped, not fatal`() {
        val raw = "reps1\n1000,PULLUP,c\ngarbage\n2000,NOT_A_MOVEMENT,c\n3000,PUSHUP,x\n4000,SQUAT,m"
        val marks = RepTimes.decode(raw)!!
        assertEquals(
            listOf(RepMark(1_000L, Exercise.PULLUP, false), RepMark(4_000L, Exercise.SQUAT, true)),
            marks
        )
    }

    @Test
    fun `a missing or unknown header yields null`() {
        assertNull(RepTimes.decode(null))
        assertNull(RepTimes.decode(""))
        assertNull(RepTimes.decode("   "))
        assertNull(RepTimes.decode("garbage"))
        assertNull(RepTimes.decode("reps2\n1000,PULLUP,c"))
    }

    @Test
    fun `valid when the count matches, the clock never goes backwards, and nothing runs past it`() {
        val marks = listOf(
            RepMark(0L, Exercise.PULLUP, false),
            RepMark(1_000L, Exercise.PULLUP, false),
            RepMark(20_500L, Exercise.SQUAT, false)
        )
        assertTrue(RepTimes.validFor(marks, attempt(countedReps = 3, durationMs = 20_000L)))
    }

    @Test
    fun `invalid when the attempt has no counted total`() {
        val marks = listOf(RepMark(0L, Exercise.PULLUP, false))
        assertFalse(RepTimes.validFor(marks, attempt(countedReps = null)))
    }

    @Test
    fun `invalid when the mark count disagrees with the attempt's counted total`() {
        val marks = listOf(RepMark(0L, Exercise.PULLUP, false))
        assertFalse(RepTimes.validFor(marks, attempt(countedReps = 2)))
    }

    @Test
    fun `invalid when a mark's clock runs backwards`() {
        val marks = listOf(
            RepMark(2_000L, Exercise.PULLUP, false),
            RepMark(1_000L, Exercise.PULLUP, false)
        )
        assertFalse(RepTimes.validFor(marks, attempt(countedReps = 2)))
    }

    @Test
    fun `invalid when a mark runs more than a second past the clock`() {
        val marks = listOf(RepMark(21_001L, Exercise.PULLUP, false))
        assertFalse(RepTimes.validFor(marks, attempt(countedReps = 1, durationMs = 20_000L)))
    }

    @Test
    fun `a mark exactly one second past the clock is still valid`() {
        val marks = listOf(RepMark(21_000L, Exercise.PULLUP, false))
        assertTrue(RepTimes.validFor(marks, attempt(countedReps = 1, durationMs = 20_000L)))
    }
}
