package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LevelsTest {

    @Test
    fun `a complete Cindy lands at intermediate`() {
        assertEquals(Level.INTERMEDIATE, Level.of(10))
        assertEquals(Level.INTERMEDIATE, Level.of(15))
    }

    @Test
    fun `the ladder climbs in order`() {
        assertEquals(Level.FIRST_STEPS, Level.of(0))
        assertEquals(Level.NOVICE, Level.of(5))
        assertEquals(Level.ADVANCED, Level.of(16))
        assertEquals(Level.ELITE, Level.of(21))
        assertEquals(Level.LEGEND, Level.of(27))
    }

    @Test
    fun `the top of the ladder is level with the benchmark`() {
        assertEquals(Level.LEGEND.minRounds, Records.BENCHMARK.rounds)
        assertNull(Level.next(Level.LEGEND))
        assertNull(Level.roundsToNext(30))
    }

    @Test
    fun `thresholds are strictly increasing`() {
        val mins = Level.entries.map { it.minRounds }
        assertEquals(mins.sorted(), mins)
        assertEquals(mins.distinct(), mins)
    }

    @Test
    fun `rounds to next counts down to the boundary`() {
        assertEquals(5, Level.roundsToNext(0))
        assertEquals(1, Level.roundsToNext(9))
        assertEquals(6, Level.roundsToNext(10))
    }

    @Test
    fun `progress runs zero to one inside a level`() {
        assertEquals(0f, Level.progress(10), 0.001f)
        assertEquals(1f, Level.progress(27), 0.001f)
        assertTrue(Level.progress(13) in 0.4f..0.6f)
    }

    @Test
    fun `a negative score does not fall off the bottom`() {
        assertEquals(Level.FIRST_STEPS, Level.of(0))
        assertTrue(Level.progress(0) in 0f..1f)
    }
}
