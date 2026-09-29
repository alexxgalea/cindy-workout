package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HeartRateMeasurementTest {

    private fun parse(vararg bytes: Int): HeartRateReading? =
        HeartRateMeasurement.parse(bytes.map { it.toByte() }.toByteArray())

    @Test
    fun `a plain uint8 reading with the contact bit clear reports unsupported`() {
        val r = parse(0x00, 0x48)!!
        assertEquals(72, r.bpm)
        assertEquals(SensorContact.UNSUPPORTED, r.contact)
    }

    @Test
    fun `bit 0 set means a uint16 little-endian reading`() {
        val r = parse(0x01, 0x9A, 0x00)!!
        assertEquals(154, r.bpm)
    }

    @Test
    fun `contact bit set and detected`() {
        val r = parse(0x06, 0x50)!!
        assertEquals(SensorContact.DETECTED, r.contact)
    }

    @Test
    fun `contact bit set and not detected`() {
        val r = parse(0x04, 0x50)!!
        assertEquals(SensorContact.NOT_DETECTED, r.contact)
    }

    @Test
    fun `energy expended and RR bits are ignored, and nothing past the HR byte is read`() {
        val r = parse(0x18, 0x50, 0x10, 0x00, 0x00, 0x04)!!
        assertEquals(80, r.bpm)
    }

    @Test
    fun `too short to hold a reading yields null`() {
        assertNull(HeartRateMeasurement.parse(byteArrayOf()))
        assertNull(parse(0x00))
        assertNull(parse(0x01, 0x9A))
    }

    @Test
    fun `plausible rejects sensor junk, never effort`() {
        assertFalse(HeartRateMeasurement.plausible(HeartRateReading(0, SensorContact.UNSUPPORTED)))
        assertFalse(HeartRateMeasurement.plausible(HeartRateReading(29, SensorContact.UNSUPPORTED)))
        assertFalse(HeartRateMeasurement.plausible(HeartRateReading(231, SensorContact.UNSUPPORTED)))
        assertFalse(HeartRateMeasurement.plausible(HeartRateReading(120, SensorContact.NOT_DETECTED)))

        assertTrue(HeartRateMeasurement.plausible(HeartRateReading(30, SensorContact.UNSUPPORTED)))
        assertTrue(HeartRateMeasurement.plausible(HeartRateReading(230, SensorContact.UNSUPPORTED)))
        assertTrue(HeartRateMeasurement.plausible(HeartRateReading(120, SensorContact.UNSUPPORTED)))
    }
}
