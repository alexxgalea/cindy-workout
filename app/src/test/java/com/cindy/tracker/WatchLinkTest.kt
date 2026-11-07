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
    fun `a fresh install is offered a watch at the first start`() {
        assertEquals(
            WatchPrompt.OFFER_TO_PAIR,
            WatchLinks.promptAtStart(WatchLink.NOT_PAIRED, bleAvailable = true, offerSeen = false)
        )
    }

    @Test
    fun `the offer is made once in the app's life, so the second start is not asked`() {
        assertEquals(
            WatchPrompt.NONE,
            WatchLinks.promptAtStart(WatchLink.NOT_PAIRED, bleAvailable = true, offerSeen = true)
        )
    }

    @Test
    fun `an upgrade from a version that already asked is not asked again`() {
        // The old version asked at every start until "Don't ask again", and kept that answer
        // under the key the new one reads as "seen". An athlete who had a session, or had put the
        // placement guide away, was past the question at least once without ticking the box.
        val key = Onboarding.KEY_WATCH_OFFER_SEEN
        assertEquals("watch_offer_silenced", key)
        for ((remembered, history, dismissed) in listOf(
            Triple(true, false, false),
            Triple(false, true, false),
            Triple(false, false, true)
        )) {
            assertEquals(
                WatchPrompt.NONE,
                WatchLinks.promptAtStart(
                    WatchLink.NOT_PAIRED,
                    bleAvailable = true,
                    offerSeen = Onboarding.watchOfferSeen(remembered, history, dismissed)
                )
            )
        }
        assertEquals(
            WatchPrompt.OFFER_TO_PAIR,
            WatchLinks.promptAtStart(
                WatchLink.NOT_PAIRED,
                bleAvailable = true,
                offerSeen = Onboarding.watchOfferSeen(false, false, false)
            )
        )
    }

    @Test
    fun `a phone that cannot talk to a watch is never offered one`() {
        assertEquals(
            WatchPrompt.NONE,
            WatchLinks.promptAtStart(WatchLink.NOT_PAIRED, bleAvailable = false, offerSeen = false)
        )
    }

    @Test
    fun `a silent watch is always asked about, whatever was said about the offer`() {
        for (seen in listOf(false, true)) {
            assertEquals(
                WatchPrompt.ASK_ABOUT_SILENT_WATCH,
                WatchLinks.promptAtStart(WatchLink.SILENT, bleAvailable = true, offerSeen = seen)
            )
        }
    }

    @Test
    fun `a live watch is never interrupted`() {
        assertEquals(
            WatchPrompt.NONE,
            WatchLinks.promptAtStart(WatchLink.LIVE, bleAvailable = true, offerSeen = false)
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
