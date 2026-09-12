package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
    fun `a finished round is never reported as zero reps`() {
        // The bug this exists to stop: the score was read off the reps of the round in
        // progress, which a completed round leaves at zero. One clean round is thirty reps of
        // work and was being announced as none, over a results screen reading thirty.
        val said = coach.score(rounds = 1, totalReps = 30)
        assertTrue(said, said.contains("30 reps"))
        // Word-boundary, because "30 reps" contains "0 reps" as plain text.
        assertFalse(said, Regex("\\b0 reps").containsMatchIn(said))
    }

    @Test
    fun `the rep figure is the whole tally, said as one`() {
        // "and 30 reps" would invite hearing a round plus thirty more. The total includes the
        // round, so the line has to say which of the two it means.
        assertEquals("1 round — 30 reps in total", coach.score(rounds = 1, totalReps = 30))
        assertEquals("6 rounds — 185 reps in total", coach.score(rounds = 6, totalReps = 185))
    }

    @Test
    fun `a score with no round behind it is just the reps`() {
        assertEquals("12 reps", coach.score(rounds = 0, totalReps = 12))
        assertEquals("1 rep", coach.score(rounds = 0, totalReps = 1))
        // An athlete who stopped before anything counted is owed the honest zero.
        assertEquals("0 reps", coach.score(rounds = 0, totalReps = 0))
    }

    @Test
    fun `the clock says the score the same way the ending does`() {
        val said = runTo(2 * 60_000L - 200L, rounds = 1, totalReps = 30).last()
        assertTrue(said, said.startsWith("Two minutes."))
        assertTrue(said, said.contains(coach.score(1, 30)))
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
