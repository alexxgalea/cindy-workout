package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RecordsTest {

    private fun attempt(rounds: Int, reps: Int = 0, at: Long = 0L) = Attempt(rounds, reps, at)

    @Test
    fun `total reps counts thirty per round`() {
        assertEquals(30, attempt(1).totalReps)
        assertEquals(822, attempt(27, 12).totalReps)
    }

    @Test
    fun `score reads the way an AMRAP is written`() {
        assertEquals("27", attempt(27).scoreLabel())
        assertEquals("12 + 7", attempt(12, 7).scoreLabel())
    }

    @Test
    fun `the benchmark is Tom Holland at twenty-seven rounds`() {
        assertEquals("Tom Holland", Records.BENCHMARK_NAME)
        assertEquals(27, Records.BENCHMARK.rounds)
        assertEquals(810, Records.BENCHMARK.totalReps)
    }

    @Test
    fun `beating the benchmark needs more than twenty-seven clean rounds`() {
        assertFalse(Records.beatsBenchmark(attempt(27)))
        assertTrue(Records.beatsBenchmark(attempt(27, 1)))
        assertTrue(Records.beatsBenchmark(attempt(28)))
        assertFalse(Records.beatsBenchmark(attempt(26, 29)))
    }

    @Test
    fun `encode and decode round-trip`() {
        val list = listOf(attempt(12, 7, 1000L), attempt(14, 0, 2000L))
        assertEquals(list, Records.decode(Records.encode(list)))
    }

    @Test
    fun `splits and duration survive the round-trip`() {
        val list = listOf(
            Attempt(3, 12, 1000L, 1_200_000L, 45_000L, listOf(60_000L, 71_000L, 68_000L)),
            Attempt(1, 0, 2000L, 90_000L, 0L, listOf(90_000L))
        )
        assertEquals(list, Records.decode(Records.encode(list)))
    }

    @Test
    fun `an attempt with no complete rounds round-trips`() {
        val a = Attempt(0, 9, 5L, 300_000L, 0L, emptyList())
        assertEquals(listOf(a), Records.decode(Records.encode(listOf(a))))
    }

    @Test
    fun `attempts saved before splits existed still load`() {
        val decoded = Records.decode("12,7,1000\n14,0,2000")
        assertEquals(2, decoded.size)
        assertEquals(12, decoded[0].rounds)
        assertEquals(emptyList<Long>(), decoded[0].roundSplitsMs)
        assertEquals(0L, decoded[0].durationMs)
    }

    @Test
    fun `old and new records coexist in one file`() {
        val mixed = "12,7,1000\n" + Records.encode(listOf(Attempt(9, 0, 3000L, 600_000L, 0L, listOf(300_000L))))
        val decoded = Records.decode(mixed)
        assertEquals(2, decoded.size)
        assertEquals(12, decoded[0].rounds)
        assertEquals(listOf(300_000L), decoded[1].roundSplitsMs)
    }

    @Test
    fun `average round prefers the splits over dividing the clock`() {
        val a = Attempt(2, 5, 0L, 1_200_000L, 0L, listOf(100_000L, 140_000L))
        assertEquals(120_000L, a.avgRoundMs)
        assertEquals(100_000L, a.fastestRoundMs)
        assertEquals(140_000L, a.slowestRoundMs)
    }

    @Test
    fun `average round falls back to the clock when splits are missing`() {
        assertEquals(300_000L, Attempt(4, 0, 0L, 1_200_000L).avgRoundMs)
        assertNull(Attempt(0, 5, 0L, 600_000L).avgRoundMs)
        assertNull(Attempt(3, 0, 0L, 0L).avgRoundMs)
    }

    @Test
    fun `real time counts the pauses that the workout clock does not`() {
        val a = Attempt(5, 0, 0L, durationMs = 1_200_000L, pausedMs = 180_000L)
        assertEquals(1_200_000L, a.durationMs)
        assertEquals(1_380_000L, a.realTimeMs)
        // Splits are clock time, so a pause must not inflate the average.
        assertEquals(240_000L, a.avgRoundMs)
    }

    @Test
    fun `an unpaused attempt has real time equal to clock time`() {
        val a = Attempt(3, 0, 0L, durationMs = 900_000L)
        assertEquals(a.durationMs, a.realTimeMs)
    }

    @Test
    fun `durations read as minutes and seconds`() {
        assertEquals("0:00", formatDuration(0L))
        assertEquals("1:05", formatDuration(65_000L))
        assertEquals("20:00", formatDuration(20 * 60 * 1000L))
    }

    @Test
    fun `an attempt carries its level`() {
        assertEquals(Level.INTERMEDIATE, attempt(12).level)
        assertEquals(Level.LEGEND, attempt(27).level)
    }

    @Test
    fun `decoding junk yields nothing rather than crashing`() {
        assertEquals(emptyList<Attempt>(), Records.decode(null))
        assertEquals(emptyList<Attempt>(), Records.decode(""))
        assertEquals(emptyList<Attempt>(), Records.decode("garbage"))
        assertEquals(emptyList<Attempt>(), Records.decode("1,2"))
        assertEquals(emptyList<Attempt>(), Records.decode("a,b,c"))
    }

    @Test
    fun `a corrupt line does not discard the good ones`() {
        val decoded = Records.decode("12,7,1000\nbroken\n14,0,2000")
        assertEquals(2, decoded.size)
        assertEquals(12, decoded[0].rounds)
    }

    @Test
    fun `ranking puts the highest total first`() {
        val ranked = Records.ranked(listOf(attempt(10), attempt(15), attempt(12, 20)))
        assertEquals(15, ranked[0].rounds)
        assertEquals(12, ranked[1].rounds)
        assertEquals(10, ranked[2].rounds)
    }

    @Test
    fun `equal scores rank the more recent attempt first`() {
        val ranked = Records.ranked(listOf(attempt(10, 0, 100L), attempt(10, 0, 500L)))
        assertEquals(500L, ranked[0].atMillis)
    }

    @Test
    fun `best of nothing is nothing`() {
        assertNull(Records.best(emptyList()))
    }

    // ── a score the camera could not stand behind ─────────────────────────────

    @Test
    fun `time the camera was blind survives a round trip`() {
        val a = attempt(12, 7).copy(untrackedMs = 91_000L, countedReps = 367)
        val back = Records.decode(Records.encode(listOf(a))).single()
        assertEquals(91_000L, back.untrackedMs)
        assertEquals(367, back.countedReps)
    }

    @Test
    fun `an attempt recorded before this was measured reads as nothing known missing`() {
        // A v5 line, which is what the previous build wrote. Zero is the right reading: nothing
        // was known to be missed, which is not the same claim as nothing was missed.
        val v5 = "v5|12|7|100|1000|0||STRICT_PULL_UP|STANDARD_PUSH_UP|AIR_SQUAT|0|367"
        val back = Records.decode(v5).single()
        assertEquals(0L, back.untrackedMs)
        assertFalse(back.scoreIsLowerBound)
        assertEquals(367, back.countedReps)
    }

    @Test
    fun `a few seconds of lost tracking does not tarnish a score`() {
        assertFalse(attempt(20).copy(untrackedMs = 12_000L).scoreIsLowerBound)
    }

    @Test
    fun `half a minute of blind camera makes the score a floor`() {
        assertTrue(attempt(20).copy(untrackedMs = 30_000L).scoreIsLowerBound)
    }

    @Test
    fun `a score the camera could not stand behind is not a personal record`() {
        val history = listOf(attempt(10, 0, 100L))
        val degraded = attempt(20, 0, 500L).copy(untrackedMs = 120_000L)
        // Twice the previous best, and still not a record: the number itself is not trustworthy.
        assertTrue(degraded.totalReps > history.single().totalReps)
        assertFalse(Records.isPersonalRecord(history + degraded, degraded))
    }

    @Test
    fun `a clean score still sets a personal record`() {
        val history = listOf(attempt(10, 0, 100L))
        val clean = attempt(20, 0, 500L)
        assertTrue(Records.isPersonalRecord(history + clean, clean))
    }

    @Test
    fun `a degraded session cannot claim the benchmark`() {
        val big = Attempt(30, 0, 0L, untrackedMs = 60_000L)
        assertTrue(big.totalReps > Records.BENCHMARK.totalReps)
        assertFalse(Records.beatsBenchmark(big))
        assertTrue(Records.beatsBenchmark(big.copy(untrackedMs = 0L)))
    }

    @Test
    fun `a degraded session is still kept and still ranked`() {
        // The athlete did at least this much, so withholding it would be its own dishonesty.
        val degraded = attempt(20, 0, 500L).copy(untrackedMs = 120_000L)
        val all = listOf(attempt(10, 0, 100L), degraded)
        assertEquals(20, Records.best(all)?.rounds)
        assertEquals(2, Records.ranked(all).size)
    }

    // ── set splits (record format v7) ─────────────────────────────────────────

    @Test
    fun `set splits survive the round-trip`() {
        val a = attempt(12, 7).copy(
            countedReps = 367,
            setSplits = listOf(
                SetSplit(Exercise.PULLUP, 14_000L, 5, 0),
                SetSplit(Exercise.PUSHUP, 17_000L, 8, 3),
                SetSplit(Exercise.SQUAT, 20_000L, 15, 0)
            )
        )
        assertEquals(listOf(a), Records.decode(Records.encode(listOf(a))))
    }

    @Test
    fun `encode writes the v7 format`() {
        assertTrue(Records.encode(listOf(attempt(12, 7))).startsWith("v7|"))
    }

    @Test
    fun `a v6 line still loads, with no sets`() {
        val v6 = "v6|12|7|100|1000|0||STRICT_PULL_UP|STANDARD_PUSH_UP|AIR_SQUAT|0|367|0"
        val back = Records.decode(v6).single()
        assertEquals(12, back.rounds)
        assertEquals(367, back.countedReps)
        assertEquals(emptyList<SetSplit>(), back.setSplits)
    }

    @Test
    fun `an unknown movement in a v7 line drops only that set`() {
        val sets = "PULLUP:14000:5:0,HANDSTAND:1:1:0,SQUAT:20000:15:0"
        val v7 = "v7|12|7|100|1000|0||STRICT_PULL_UP|STANDARD_PUSH_UP|AIR_SQUAT|0|367|0|$sets"
        val back = Records.decode(v7).single()
        assertEquals(12, back.rounds)
        assertEquals(
            listOf(
                SetSplit(Exercise.PULLUP, 14_000L, 5, 0),
                SetSplit(Exercise.SQUAT, 20_000L, 15, 0)
            ),
            back.setSplits
        )
    }
}
