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
}
