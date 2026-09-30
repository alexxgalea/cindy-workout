package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HeartRateTracesTest {

    @Test
    fun `round trips a trace with pauses`() {
        val trace = HeartRateTrace(
            startedAtMillis = 1_700_000_000_000L,
            samples = listOf(HeartRateSample(0L, 88), HeartRateSample(1000L, 140)),
            pauses = listOf(HeartRatePause(atClockMs = 500L, lengthMs = 30_000L))
        )
        assertEquals(trace, HeartRateTraces.decode(HeartRateTraces.encode(trace)))
    }

    @Test
    fun `round trips a trace with no pauses`() {
        val trace = HeartRateTrace(
            startedAtMillis = 1000L,
            samples = listOf(HeartRateSample(0L, 100)),
            pauses = emptyList()
        )
        assertEquals(trace, HeartRateTraces.decode(HeartRateTraces.encode(trace)))
    }

    @Test
    fun `round trips a trace with neither samples nor pauses`() {
        val trace = HeartRateTrace(startedAtMillis = 5L, samples = emptyList(), pauses = emptyList())
        assertEquals(trace, HeartRateTraces.decode(HeartRateTraces.encode(trace)))
    }

    @Test
    fun `a malformed line is skipped, not fatal`() {
        val raw = "hr1|1000\n0,88\ngarbage\np|broken\n1000,140"
        val trace = HeartRateTraces.decode(raw)!!
        assertEquals(1000L, trace.startedAtMillis)
        assertEquals(listOf(HeartRateSample(0L, 88), HeartRateSample(1000L, 140)), trace.samples)
        assertEquals(emptyList<HeartRatePause>(), trace.pauses)
    }

    @Test
    fun `a missing or unknown header yields null`() {
        assertNull(HeartRateTraces.decode(null))
        assertNull(HeartRateTraces.decode(""))
        assertNull(HeartRateTraces.decode("   "))
        assertNull(HeartRateTraces.decode("garbage"))
        assertNull(HeartRateTraces.decode("hr2|1000\n0,88"))
    }
}
