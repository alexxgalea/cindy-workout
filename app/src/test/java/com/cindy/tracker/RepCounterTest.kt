package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RepCounterTest {

    /** Feeds one value repeatedly so the smoother settles, returning how many reps were booked. */
    private fun RepCounter.hold(value: Float, startMs: Long, frames: Int = 10, stepMs: Long = 100L): Int {
        var reps = 0
        for (i in 0 until frames) {
            if (update(value, startMs + i * stepMs)) reps++
        }
        return reps
    }

    @Test
    fun `full travel across the dead zone scores one rep`() {
        val c = RepCounter(downBelow = 100f, upAbove = 150f)
        var t = 0L
        c.hold(80f, t); t += 1000
        val scored = c.hold(170f, t)
        assertEquals(1, scored)
        assertEquals(1, c.count)
    }

    @Test
    fun `jitter inside the dead zone never scores`() {
        val c = RepCounter(downBelow = 100f, upAbove = 150f)
        var t = 0L
        c.hold(80f, t); t += 1000
        for (v in listOf(110f, 140f, 120f, 145f, 105f, 149f)) {
            c.hold(v, t); t += 1000
        }
        assertEquals(0, c.count)
    }

    @Test
    fun `a half rep that never reaches the bottom is not counted`() {
        val c = RepCounter(downBelow = 100f, upAbove = 150f)
        // Starts high, dips only to 120, comes back up: no bottom, so no rep.
        var t = 0L
        c.hold(170f, t); t += 1000
        c.hold(120f, t); t += 1000
        c.hold(170f, t)
        assertEquals(0, c.count)
    }

    @Test
    fun `ten clean cycles score ten reps`() {
        val c = RepCounter(downBelow = 100f, upAbove = 150f)
        var t = 0L
        repeat(10) {
            c.hold(80f, t); t += 1000
            c.hold(170f, t); t += 1000
        }
        assertEquals(10, c.count)
    }

    @Test
    fun `reps faster than the debounce window are rejected`() {
        val c = RepCounter(downBelow = 100f, upAbove = 150f, minRepMs = 5000L, smoothing = 1f)
        var t = 0L
        // Two complete cycles 200 ms apart; the debounce should keep the second one out.
        c.update(80f, t); t += 100
        c.update(170f, t); t += 100
        c.update(80f, t); t += 100
        c.update(170f, t)
        assertEquals(1, c.count)
    }

    @Test
    fun `NaN samples are ignored rather than breaking the smoother`() {
        val c = RepCounter(downBelow = 100f, upAbove = 150f)
        var t = 0L
        c.hold(80f, t); t += 1000
        assertFalse(c.update(Float.NaN, t))
        t += 1000
        c.hold(170f, t)
        assertEquals(1, c.count)
        assertTrue(!c.smoothed.isNaN())
    }

    @Test
    fun `reset clears everything`() {
        val c = RepCounter(downBelow = 100f, upAbove = 150f)
        var t = 0L
        c.hold(80f, t); t += 1000
        c.hold(170f, t)
        assertEquals(1, c.count)
        c.reset()
        assertEquals(0, c.count)
        assertEquals(RepCounter.Phase.UNKNOWN, c.phase)
    }
}
