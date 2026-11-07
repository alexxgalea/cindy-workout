package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class StatTilesTest {

    private fun attempt(
        rounds: Int = 7,
        reps: Int = 12,
        splits: List<Long> = listOf(150_000L, 164_000L, 170_000L, 171_000L, 172_000L, 173_000L, 174_000L),
        pausedMs: Long = 0L,
        untrackedMs: Long = 0L,
        manualReps: Int = 0,
        countedReps: Int? = 222
    ) = Attempt(
        rounds = rounds, reps = reps, atMillis = 1L, durationMs = 20 * 60_000L,
        pausedMs = pausedMs, roundSplitsMs = splits, countedReps = countedReps,
        untrackedMs = untrackedMs, manualReps = manualReps
    )

    private fun byLabel(a: Attempt, stats: SessionStats? = null) =
        SessionTiles.of(a, stats).associateBy { it.label }

    @Test
    fun `three tiles in reading order, the round figures`() {
        assertEquals(
            listOf("AVG", "FASTEST", "SLOWEST"),
            SessionTiles.of(attempt(), null).map { it.label }
        )
    }

    @Test
    fun `the tiles read the rounds`() {
        val t = byLabel(attempt())

        assertEquals("2:30", t.getValue("FASTEST").value)
        assertEquals("round 1", t.getValue("FASTEST").footnote)
        assertEquals("2:54", t.getValue("SLOWEST").value)
        assertEquals("round 7", t.getValue("SLOWEST").footnote)
        assertEquals("over 7 rounds", t.getValue("AVG").footnote)
    }

    @Test
    fun `no complete round leaves no tiles, not a row of dashes`() {
        assertTrue(SessionTiles.of(attempt(rounds = 0, reps = 4, splits = emptyList(), countedReps = 4), null).isEmpty())
    }

    @Test
    fun `a record with rounds but no splits keeps the average and leaves out the extremes`() {
        val t = byLabel(attempt(splits = emptyList()))

        assertEquals(listOf("AVG"), t.keys.toList())
        assertEquals("clock over rounds", t.getValue("AVG").footnote)
    }
}
