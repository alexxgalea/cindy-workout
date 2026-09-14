package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the handoff is allowed to throw away.
 *
 * The whole point of coalescing is to drop work, and the whole risk of it is dropping the wrong
 * work. A rep that never reaches the main thread is never buzzed, never spoken, and if it closed
 * a round its split never reaches the session record — so "events survive" is not a nicety here,
 * it is the same rule as [[reps are banked, not inferred]]: the app books what happened, it does
 * not reconstruct it afterwards.
 */
class FrameHandoffTest {

    private fun drained(h: FrameHandoff<String>): List<String> =
        mutableListOf<String>().also { out -> h.drain { out += it } }

    @Test
    fun `only the newest state frame survives a backlog`() {
        val h = FrameHandoff<String>()
        assertEquals(FrameHandoff.Outcome.SCHEDULE, h.submit("a", isEvent = false))
        assertEquals(FrameHandoff.Outcome.REPLACED_PENDING, h.submit("b", isEvent = false))
        assertEquals(FrameHandoff.Outcome.REPLACED_PENDING, h.submit("c", isEvent = false))
        assertEquals(listOf("c"), drained(h))
    }

    @Test
    fun `every event survives, in order`() {
        val h = FrameHandoff<String>()
        h.submit("rep 1", isEvent = true)
        h.submit("rep 2", isEvent = true)
        h.submit("round done", isEvent = true)
        assertEquals(listOf("rep 1", "rep 2", "round done"), drained(h))
    }

    @Test
    fun `a flood of state frames cannot bury an event between them`() {
        val h = FrameHandoff<String>()
        repeat(50) { h.submit("state $it", isEvent = false) }
        h.submit("rep", isEvent = true)
        repeat(50) { h.submit("state ${it + 50}", isEvent = false) }
        val out = drained(h)
        assertTrue("the rep must still be delivered, got $out", out.contains("rep"))
        assertEquals("one event plus one surviving state frame", 2, out.size)
        assertEquals("the event is delivered before the newer state", "rep", out.first())
    }

    @Test
    fun `an event always asks to be scheduled, even behind a pending state frame`() {
        val h = FrameHandoff<String>()
        h.submit("state", isEvent = false)
        assertEquals(
            "an event must never rely on someone else's runnable arriving",
            FrameHandoff.Outcome.SCHEDULE, h.submit("rep", isEvent = true)
        )
    }

    @Test
    fun `draining twice is harmless`() {
        val h = FrameHandoff<String>()
        h.submit("rep", isEvent = true)
        h.submit("state", isEvent = false)
        assertEquals(listOf("rep", "state"), drained(h))
        assertEquals("a spurious second drain renders nothing", emptyList<String>(), drained(h))
    }

    @Test
    fun `a drained slot schedules again on the next frame`() {
        val h = FrameHandoff<String>()
        h.submit("a", isEvent = false)
        drained(h)
        assertEquals(
            "nothing is pending any more, so the next frame must post",
            FrameHandoff.Outcome.SCHEDULE, h.submit("b", isEvent = false)
        )
    }

    @Test
    fun `clear forgets both`() {
        val h = FrameHandoff<String>()
        h.submit("rep", isEvent = true)
        h.submit("state", isEvent = false)
        h.clear()
        assertEquals(emptyList<String>(), drained(h))
    }
}
