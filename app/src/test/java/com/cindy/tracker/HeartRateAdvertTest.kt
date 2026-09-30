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
    fun `connected devices come first, then the rest in the order first heard`() {
        val watch = FoundDevice("AA", "fenix 7X", rssi = null, connected = true)
        val strap = FoundDevice("BB", "HRM-Pro", rssi = -80)
        val near = FoundDevice("CC", "Polar H10", rssi = -50)
        assertEquals(listOf(watch, strap, near), HeartRateAdvert.merge(listOf(watch), listOf(strap, near)))
    }

    @Test
    fun `a stronger packet does not move a device up the list`() {
        val first = FoundDevice("BB", "HRM-Pro", rssi = -80)
        val second = FoundDevice("CC", "Polar H10", rssi = -70)
        val before = HeartRateAdvert.merge(emptyList(), listOf(first, second))
        val after = HeartRateAdvert.merge(emptyList(), listOf(first.copy(rssi = -85), second.copy(rssi = -40)))
        assertEquals(before.map { it.address }, after.map { it.address })
    }

    @Test
    fun `a name once heard is kept when a later packet has none`() {
        val named = HeartRateAdvert.heard(null, "AA", "fenix 7X", -60)
        val next = HeartRateAdvert.heard(named, "AA", null, -62)
        assertEquals(FoundDevice("AA", "fenix 7X", -62), next)
    }

    @Test
    fun `an unnamed device is called a heart-rate sensor until it names itself`() {
        val unnamed = HeartRateAdvert.heard(null, "AA", null, -60)
        assertEquals(HeartRateAdvert.UNNAMED, unnamed.name)
        assertEquals("fenix 7X", HeartRateAdvert.heard(unnamed, "AA", "fenix 7X", -60).name)
    }

    @Test
    fun `a signal change keeps the rows, anything else rebuilds them`() {
        val watch = FoundDevice("AA", "fenix 7X", rssi = -60)
        val strap = FoundDevice("BB", "HRM-Pro", rssi = -80)
        val shown = listOf(watch, strap)
        assertTrue(HeartRateAdvert.sameRows(shown, listOf(watch.copy(rssi = -90), strap.copy(rssi = -40))))
        assertTrue(HeartRateAdvert.sameRows(emptyList(), emptyList()))
        assertFalse(HeartRateAdvert.sameRows(shown, listOf(watch)))
        assertFalse(HeartRateAdvert.sameRows(shown, listOf(strap, watch)))
        assertFalse(HeartRateAdvert.sameRows(shown, listOf(watch.copy(name = "fenix"), strap)))
        assertFalse(HeartRateAdvert.sameRows(shown, listOf(watch.copy(connected = true), strap)))
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
