package com.cindy.tracker

import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** What the menu's first row says, and which session it opens. */
class LastSessionRowTest {

    private val noon7Nov2026 = 1_794_052_800_000L // 2026-11-07T12:00:00Z
    private val day = 24L * 60 * 60 * 1000

    private fun attempt(rounds: Int, reps: Int, at: Long) =
        Attempt(rounds = rounds, reps = reps, atMillis = at)

    private fun row(attempts: List<Attempt>) = LastSessionRow.of(attempts, ZoneOffset.UTC)

    @Test
    fun `with no sessions there is no row`() {
        assertNull(row(emptyList()))
    }

    @Test
    fun `the row opens the most recent session, not the best one`() {
        val best = attempt(rounds = 20, reps = 0, at = noon7Nov2026 - 3 * day)
        val latest = attempt(rounds = 5, reps = 3, at = noon7Nov2026)
        val older = attempt(rounds = 9, reps = 0, at = noon7Nov2026 - 10 * day)
        // The store hands sessions back oldest first or any order: the row must not rely on it.
        assertEquals(latest.atMillis, row(listOf(latest, best, older))!!.atMillis)
        assertEquals(latest.atMillis, row(listOf(best, older, latest))!!.atMillis)
    }

    @Test
    fun `the row shows the date and the score`() {
        val r = row(listOf(attempt(rounds = 5, reps = 3, at = noon7Nov2026)))!!
        assertEquals("Last session", r.title)
        assertEquals("7 Nov 2026 · 5 + 3", r.value)
    }

    @Test
    fun `a score with no reps over the last round is the rounds alone`() {
        val r = row(listOf(attempt(rounds = 27, reps = 0, at = noon7Nov2026)))!!
        assertEquals("7 Nov 2026 · 27", r.value)
    }

    @Test
    fun `the spoken name includes the date and the score`() {
        val r = row(listOf(attempt(rounds = 5, reps = 3, at = noon7Nov2026)))!!
        assertEquals("Last session, 7 Nov 2026, score 5 rounds and 3 reps", r.spokenName)
        val whole = row(listOf(attempt(rounds = 1, reps = 0, at = noon7Nov2026)))!!
        assertEquals("Last session, 7 Nov 2026, score 1 round", whole.spokenName)
    }
}
