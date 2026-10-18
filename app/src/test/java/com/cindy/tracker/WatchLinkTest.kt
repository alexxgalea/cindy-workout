package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Test

class WatchLinkTest {

    // A phone that has been up for a day: elapsedRealtime is nowhere near zero.
    private val now = 86_400_000L

    private fun judge(lastReadingAt: Long, paired: Boolean = true) =
        WatchLinks.judge(paired, lastReadingAt, now)

    @Test
    fun `no watch paired is not a silent watch`() {
        assertEquals(WatchLink.NOT_PAIRED, judge(lastReadingAt = 0L, paired = false))
    }

    @Test
    fun `a reading a second ago is live`() {
        assertEquals(WatchLink.LIVE, judge(lastReadingAt = now - 1_000L))
    }

    @Test
    fun `a reading exactly at the limit is still live, one millisecond later is not`() {
        assertEquals(WatchLink.LIVE, judge(lastReadingAt = now - WatchLinks.SILENT_AFTER_MS))
        assertEquals(WatchLink.SILENT, judge(lastReadingAt = now - WatchLinks.SILENT_AFTER_MS - 1L))
    }

    @Test
    fun `a watch that has never sent anything is silent, however recently the app opened`() {
        // No allowance for a link still being made: if nothing is coming in when START is
        // tapped, the session starts without a heart rate.
        assertEquals(WatchLink.SILENT, judge(lastReadingAt = 0L))
    }

    @Test
    fun `a watch that spoke and stopped is silent`() {
        assertEquals(WatchLink.SILENT, judge(lastReadingAt = now - 30_000L))
    }

    @Test
    fun `an unpaired athlete is offered a watch unless they said not to ask again`() {
        assertEquals(
            WatchPrompt.OFFER_TO_PAIR,
            WatchLinks.promptAtStart(WatchLink.NOT_PAIRED, bleAvailable = true, offerSilenced = false)
        )
        assertEquals(
            WatchPrompt.NONE,
            WatchLinks.promptAtStart(WatchLink.NOT_PAIRED, bleAvailable = true, offerSilenced = true)
        )
    }

    @Test
    fun `a phone that cannot talk to a watch is never offered one`() {
        assertEquals(
            WatchPrompt.NONE,
            WatchLinks.promptAtStart(WatchLink.NOT_PAIRED, bleAvailable = false, offerSilenced = false)
        )
    }

    @Test
    fun `a silent watch is always asked about, whatever was said about the offer`() {
        for (silenced in listOf(false, true)) {
            assertEquals(
                WatchPrompt.ASK_ABOUT_SILENT_WATCH,
                WatchLinks.promptAtStart(WatchLink.SILENT, bleAvailable = true, offerSilenced = silenced)
            )
        }
    }

    @Test
    fun `a live watch is never interrupted`() {
        assertEquals(
            WatchPrompt.NONE,
            WatchLinks.promptAtStart(WatchLink.LIVE, bleAvailable = true, offerSilenced = false)
        )
    }

    @Test
    fun `the sheet says why when the reason is known`() {
        assertEquals("Bluetooth is off on this phone.", WatchLinks.why(HeartRateStatus.BLUETOOTH_OFF))
        assertEquals("Cindy is not allowed to use Bluetooth.", WatchLinks.why(HeartRateStatus.NO_PERMISSION))
        assertEquals(
            "It is paired but has sent no heart rate. Is heart-rate broadcast on?",
            WatchLinks.why(HeartRateStatus.WAITING)
        )
    }
}
