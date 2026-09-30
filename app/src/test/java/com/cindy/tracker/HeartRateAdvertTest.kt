package com.cindy.tracker

import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The pure half of "FIND MY WATCH": which advertisements count, and the order the sheet lists. */
class HeartRateAdvertTest {

    private val battery = UUID.fromString("0000180f-0000-1000-8000-00805f9b34fb")

    @Test
    fun `an advert listing the heart rate service matches`() {
        assertTrue(HeartRateAdvert.matches(listOf(battery, HeartRateGatt.SERVICE), emptyList()))
    }

    @Test
    fun `a garmin advert matches without the service listed`() {
        assertTrue(HeartRateAdvert.matches(null, listOf(HeartRateAdvert.GARMIN_COMPANY_ID)))
    }

    @Test
    fun `anything else does not`() {
        assertFalse(HeartRateAdvert.matches(listOf(battery), listOf(0x004C)))
        assertFalse(HeartRateAdvert.matches(null, emptyList()))
    }

    @Test
    fun `connected devices come first, then the rest strongest first`() {
        val watch = FoundDevice("AA", "fenix 7X", rssi = null, connected = true)
        val strap = FoundDevice("BB", "HRM-Pro", rssi = -80)
        val near = FoundDevice("CC", "Polar H10", rssi = -50)
        assertEquals(listOf(watch, near, strap), HeartRateAdvert.merge(listOf(watch), listOf(strap, near)))
    }

    @Test
    fun `a connected device also heard advertising is listed once with its signal`() {
        val watch = FoundDevice("AA", "fenix 7X", rssi = null, connected = true)
        val heard = FoundDevice("AA", "fenix 7X", rssi = -55)
        assertEquals(
            listOf(watch.copy(rssi = -55)),
            HeartRateAdvert.merge(listOf(watch), listOf(heard))
        )
    }
}
