package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** What the session page opens on: the score and the time, and the one line that qualifies them. */
class SessionLeadTest {

    private fun attempt(
        rounds: Int = 7,
        reps: Int = 12,
        durationMs: Long = 20 * 60_000L,
        pausedMs: Long = 0L,
        untrackedMs: Long = 0L,
        manualReps: Int = 0,
        countedReps: Int? = 222,
        profile: CindyProfile? = null
    ) = Attempt(
        rounds = rounds, reps = reps, atMillis = 1L, durationMs = durationMs,
        pausedMs = pausedMs, countedReps = countedReps,
        untrackedMs = untrackedMs, manualReps = manualReps, profile = profile
    )

    private fun lead(a: Attempt, stats: SessionStats? = null) = SessionLead.of(a, stats)

    @Test
    fun `the lead is the score and the time`() {
        val l = lead(attempt())

        assertEquals("7", l.score)
        assertEquals("+12", l.looseReps)
        assertEquals("20:00", l.time)
        assertNull(l.timeNote)
    }

    @Test
    fun `a session with no loose reps has no plus figure`() {
        assertNull(lead(attempt(rounds = 3, reps = 0, countedReps = 90)).looseReps)
    }

    @Test
    fun `the detail is the banked reps and the pace`() {
        assertEquals("222 reps · 11.1 reps/min", lead(attempt()).detail)
    }

    @Test
    fun `one rep is a rep, not reps`() {
        val l = lead(attempt(rounds = 0, reps = 1, durationMs = 11_000L, countedReps = 1))

        assertEquals("0", l.score)
        assertEquals("+1", l.looseReps)
        assertEquals("0:11", l.time)
        assertEquals("1 rep · 5.5 reps/min", l.detail)
    }

    @Test
    fun `the reps are the banked score, not a round tally`() {
        // One round finished with the pull-ups skipped is 25 reps, never 30.
        val l = lead(attempt(rounds = 1, reps = 0, countedReps = 25))
        assertTrue(l.detail, l.detail.startsWith("25 reps"))
    }

    @Test
    fun `a lower bound says at least, for the score and the pace`() {
        val l = lead(attempt(untrackedMs = 60_000L))

        assertEquals("at least 222 reps · at least 11.1 reps/min", l.detail)
        assertTrue(l.speech, l.speech.contains("at least 12 reps into round 8"))
        assertTrue(l.speech, l.speech.contains("at least 222 reps"))
    }

    @Test
    fun `tapped reps are named after the pace`() {
        val l = lead(attempt(manualReps = 12))

        assertEquals("222 reps · 11.1 reps/min · 12 tapped", l.detail)
        assertTrue(l.speech, l.speech.contains("12 of them tapped in"))
    }

    @Test
    fun `a session past the benchmark says so`() {
        val l = lead(attempt(rounds = 28, reps = 0, countedReps = 840, profile = CindyProfile.STANDARD))
        assertTrue(l.detail, l.detail.endsWith("past ${Records.BENCHMARK_NAME}"))
    }

    @Test
    fun `paused time is said beside the clock`() {
        val l = lead(attempt(pausedMs = 65_000L))

        assertEquals("plus 1:05 paused", l.timeNote)
        assertTrue(l.speech, l.speech.contains("20:00 on the clock, plus 1:05 paused"))
    }

    @Test
    fun `the reps into the next round come from the sets when they exist`() {
        val a = Attempt(
            rounds = 1, reps = 0, atMillis = 1L, durationMs = 20 * 60_000L,
            roundSplitsMs = listOf(52_000L), countedReps = 33,
            setSplits = listOf(
                SetSplit(Exercise.PULLUP, 14_000L, 5, 0), SetSplit(Exercise.PUSHUP, 17_000L, 10, 0),
                SetSplit(Exercise.SQUAT, 21_000L, 15, 0)
            )
        )
        val l = lead(a, SessionStats.from(a))

        assertEquals("+3", l.looseReps)
        assertTrue(l.speech, l.speech.startsWith("1 round, plus 3 reps into round 2."))
    }

    @Test
    fun `the speech reads the whole lead as one sentence`() {
        assertEquals(
            "7 rounds, plus 12 reps into round 8. 222 reps, 11.1 reps a minute. 20:00 on the clock.",
            lead(attempt()).speech
        )
    }
}
