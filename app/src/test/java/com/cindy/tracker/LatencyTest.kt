package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The instrument, and its refusals.
 *
 * This readout exists to be photographed off a phone and believed, so the thing most worth
 * testing is that it declines to print a number it cannot stand behind — a plausible-looking
 * latency from the wrong clock would be worse than a blank.
 */
class LatencyTest {

    @Test
    fun `capture age is withheld until the camera says which clock it is on`() {
        val clock = FrameLatency()
        assertTrue("nothing has told it yet", !clock.resolved)
        assertNull("an unresolved domain must not produce a number", clock.sinceCapture(0L))
        assertNull(clock.sinceCapture(System.nanoTime()))
    }

    @Test
    fun `the median ignores a single outlier`() {
        val r = Rolling(30)
        repeat(10) { r.add(20L) }
        r.add(4_000L)
        assertEquals(20L, r.median())
    }

    @Test
    fun `the window forgets`() {
        val r = Rolling(4)
        listOf(100L, 100L, 100L, 100L, 7L, 7L, 7L, 7L).forEach(r::add)
        assertEquals("only the last four remain", 7L, r.median())
    }

    @Test
    fun `an empty window has no median rather than a zero`() {
        val r = Rolling(4)
        assertNull(r.median())
        r.add(5L)
        r.reset()
        assertNull(r.median())
    }

    @Test
    fun `the rate meter counts over its window`() {
        val m = RateMeter(windowMs = 1_000L)
        // Ten marks 100ms apart spans 900ms and nine intervals: ten per second.
        for (i in 0..9) m.mark(i * 100L)
        assertEquals(10f, m.perSecond(900L)!!, 0.2f)
    }

    @Test
    fun `one mark is not a rate`() {
        val m = RateMeter()
        assertNull(m.perSecond(0L))
        m.mark(0L)
        assertNull("a rate needs two events to have an interval", m.perSecond(0L))
    }

    @Test
    fun `the readout says the clock is unavailable rather than printing a figure`() {
        val probe = LatencyProbe()
        probe.analysed(captureAgeMs = null, convertMs = 12L, prepMs = 20L, inferMs = 130L)
        val line = probe.line("thndr", 60f)
        assertTrue("should name the clock as the reason, was: $line", line.contains("n/a (clock)"))
        assertTrue("the stages it can measure still show, was: $line", line.contains("inf 130"))
    }

    @Test
    fun `the coalesced share is what the old post-per-frame design would have queued`() {
        val probe = LatencyProbe()
        // Four frames analysed, three of them superseded before the main thread got to them.
        probe.posted(replacedUnrendered = false)
        repeat(3) { probe.posted(replacedUnrendered = true) }
        val line = probe.line("thndr", 60f)
        assertTrue("expected 75% coalesced, was: $line", line.contains("75% coalesced"))
    }

    @Test
    fun `the readout is two lines, because the band holds one each`() {
        val probe = LatencyProbe()
        probe.analysed(captureAgeMs = 210L, convertMs = 12L, prepMs = 20L, inferMs = 130L)
        val line = probe.line("thndr", 58f)
        assertEquals("exactly one break", 1, line.count { it == '\n' })
        assertTrue("age leads the first line, was: $line", line.startsWith("age 210ms"))
        assertTrue("the model names the second, was: $line", line.contains("\nthndr"))
    }
}
