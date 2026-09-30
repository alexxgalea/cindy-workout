package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HeartRateRecorderTest {

    @Test
    fun `nothing is recorded before start`() {
        val rec = HeartRateRecorder()
        rec.offer(100, 0L)
        rec.offer(105, 500L)
        // Long enough after the last offer that starting will not seed from it either — this
        // isolates "not started yet" from the separate seeding behaviour.
        rec.start(atElapsedMs = 10_000L, wallMillis = 0L)
        assertNull(rec.finish(10_000L))
    }

    @Test
    fun `stamps are on the workout clock, not wall time`() {
        val rec = HeartRateRecorder()
        rec.start(atElapsedMs = 50_000L, wallMillis = 9_000_000L)
        rec.offer(120, 51_000L) // clock 1000
        rec.offer(130, 53_500L) // clock 3500, well past the min spacing
        val trace = rec.finish(54_000L)!!
        assertEquals(9_000_000L, trace.startedAtMillis)
        assertEquals(
            listOf(HeartRateSample(1000L, 120), HeartRateSample(3500L, 130)),
            trace.samples
        )
    }

    @Test
    fun `a thirty second pause drops its readings, keeps the clock continuous, and is listed`() {
        val rec = HeartRateRecorder()
        rec.start(atElapsedMs = 0L, wallMillis = 0L)
        rec.offer(140, 1_000L) // clock 1000, recorded
        rec.pause(2_000L) // clock 2000
        rec.offer(999, 2_500L) // during the pause: dropped, only remembered
        rec.resume(32_000L) // 30 s later — far too stale to seed from the 2_500L reading
        rec.offer(150, 33_000L) // clock 2000 + (33000 - 32000) = 3000
        val trace = rec.finish(33_000L)!!

        assertEquals(
            listOf(HeartRatePause(atClockMs = 2000L, lengthMs = 30_000L)),
            trace.pauses
        )
        assertFalse("the paused-time reading must not appear", trace.samples.any { it.bpm == 999 })
        assertEquals(listOf(1000L, 3000L), trace.samples.map { it.clockMs })
    }

    @Test
    fun `a reading 2 s old when start is called seeds the trace at clock zero`() {
        val rec = HeartRateRecorder()
        rec.offer(88, 1_000L)
        rec.start(atElapsedMs = 3_000L, wallMillis = 0L) // 2 s old
        val trace = rec.finish(3_000L)!!
        assertEquals(listOf(HeartRateSample(0L, 88)), trace.samples)
    }

    @Test
    fun `a reading 6 s old when start is called does not seed`() {
        val rec = HeartRateRecorder()
        rec.offer(88, 1_000L)
        rec.start(atElapsedMs = 7_000L, wallMillis = 0L) // 6 s old
        assertNull(rec.finish(7_000L))
    }

    @Test
    fun `a fresh reading seeds the trace again on resume`() {
        val rec = HeartRateRecorder()
        rec.start(atElapsedMs = 0L, wallMillis = 0L)
        rec.pause(1_000L) // clock 1000
        rec.offer(140, 5_500L) // during the pause, 500 ms before resume
        rec.resume(6_000L)
        val trace = rec.finish(6_000L)!!
        assertEquals(listOf(HeartRateSample(1000L, 140)), trace.samples)
    }

    @Test
    fun `finish while paused closes the pause first`() {
        val rec = HeartRateRecorder()
        rec.start(atElapsedMs = 0L, wallMillis = 0L)
        rec.offer(120, 500L) // clock 500, recorded
        rec.pause(1_000L) // clock 1000
        val trace = rec.finish(4_000L)!!
        assertEquals(
            listOf(HeartRatePause(atClockMs = 1000L, lengthMs = 3_000L)),
            trace.pauses
        )
    }

    @Test
    fun `4 Hz input is capped near 1 Hz`() {
        val rec = HeartRateRecorder()
        rec.start(atElapsedMs = 0L, wallMillis = 0L)
        var t = 0L
        repeat(80) { // 20 s of data at 250 ms intervals
            rec.offer(140, t)
            t += 250L
        }
        val trace = rec.finish(t)!!
        assertTrue("expected more than one sample", trace.samples.size > 1)
        trace.samples.zipWithNext().forEach { (a, b) ->
            assertTrue(
                "${b.clockMs - a.clockMs}ms apart, below the minimum spacing",
                b.clockMs - a.clockMs >= HeartRateRecorder.MIN_SPACING_MS
            )
        }
        val elapsedS = (trace.samples.last().clockMs - trace.samples.first().clockMs) / 1000.0
        val hz = (trace.samples.size - 1) / elapsedS
        assertTrue("rate was ${hz}Hz", hz <= 1.2)
    }

    @Test
    fun `finish with no samples yields null`() {
        val rec = HeartRateRecorder()
        rec.start(atElapsedMs = 0L, wallMillis = 0L)
        assertNull(rec.finish(1_000L))
    }

    @Test
    fun `reset clears everything, including the remembered reading`() {
        val rec = HeartRateRecorder()
        rec.offer(100, 0L)
        rec.reset()
        // If the remembered reading had survived, this would be well within MAX_HOLD_MS and seed.
        rec.start(atElapsedMs = 2_000L, wallMillis = 0L)
        assertNull(rec.finish(2_000L))
    }
}
