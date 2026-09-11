package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the voice says about the clock.
 *
 * The ticker runs five times a second, so the first thing these hold is that a mark is spoken
 * once. The second is that every line carries a figure the athlete cannot read off the screen —
 * the time alone is already in front of them.
 */
class CoachClockTest {

    private val coach = Coach()

    /** Runs the clock down to [remainingMs], ticking as the workout does, collecting what is said. */
    private fun runTo(remainingMs: Long, rounds: Int = 0, totalReps: Int = 0): List<String> {
        val said = mutableListOf<String>()
        var remaining = 20 * 60_000L
        while (remaining > remainingMs) {
            remaining -= 200L
            coach.onClock(20 * 60_000L - remaining, remaining, rounds, totalReps)?.let { said += it }
        }
        return said
    }

    @Test
    fun `a mark is spoken once, not on every tick`() {
        val said = runTo(9 * 60_000L, rounds = 6)
        assertEquals("fifteen and ten minutes, once each", 2, said.size)
    }

    @Test
    fun `halfway carries the pace, not just the time`() {
        val said = runTo(10 * 60_000L - 200L, rounds = 6)
        val halfway = said.last()
        assertTrue(halfway, halfway.startsWith("Halfway."))
        // Six rounds in ten minutes projects to twelve over the twenty.
        assertTrue(halfway, halfway.contains("6 rounds"))
        assertTrue(halfway, halfway.contains("on for 12"))
    }

    @Test
    fun `a pace is not projected before there is a round to project from`() {
        val said = runTo(15 * 60_000L - 200L, rounds = 0)
        assertEquals(1, said.size)
        assertTrue(said.single(), said.single().contains("Keep the pace"))
    }

    @Test
    fun `the last minute names the score rather than projecting it`() {
        val said = runTo(60_000L - 200L, rounds = 11, totalReps = 340)
        val lastMinute = said.last()
        assertTrue(lastMinute, lastMinute.startsWith("One minute left."))
        assertTrue(lastMinute, lastMinute.contains("11 rounds"))
    }

    @Test
    fun `nothing is said between marks`() {
        coach.onClock(60_000L, 19 * 60_000L, 0, 0)
        assertNull(coach.onClock(61_000L, 19 * 60_000L - 1_000L, 0, 0))
    }

    @Test
    fun `a reset lets the next workout hear its marks again`() {
        val first = runTo(10 * 60_000L - 200L, rounds = 6)
        assertEquals(2, first.size)

        coach.reset()

        val second = runTo(10 * 60_000L - 200L, rounds = 6)
        assertEquals("a new workout gets its own marks", 2, second.size)
    }

    @Test
    fun `a pause does not replay the marks already spoken`() {
        val before = runTo(10 * 60_000L - 200L, rounds = 6)
        assertEquals(2, before.size)

        coach.interrupted()

        // Back on the bar at the same point in the clock: halfway has been and gone.
        assertNull(coach.onClock(10 * 60_000L, 10 * 60_000L - 200L, 6, 180))
    }
}
