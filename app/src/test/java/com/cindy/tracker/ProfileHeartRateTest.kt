package com.cindy.tracker

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ProfileHeartRateTest {

    private val context: Context = ApplicationProvider.getApplicationContext()

    private fun profile(): Profile {
        context.getSharedPreferences("cindy", Context.MODE_PRIVATE).edit().clear().apply()
        return Profile(context)
    }

    @Test
    fun `birth year round trips`() {
        val p = profile()
        assertEquals(0, p.birthYear)
        p.birthYear = 1990
        assertEquals(1990, p.birthYear)
    }

    @Test
    fun `sex round trips`() {
        val p = profile()
        assertNull(p.sex)
        p.sex = Sex.FEMALE
        assertEquals(Sex.FEMALE, p.sex)
        p.sex = Sex.UNSTATED
        assertEquals(Sex.UNSTATED, p.sex)
    }

    @Test
    fun `heart-rate device round trips`() {
        val p = profile()
        assertNull(p.heartRateDevice)
        val device = HeartRateDevice(address = "AA:BB:CC:DD:EE:FF", name = "Polar H10")
        p.heartRateDevice = device
        assertEquals(device, p.heartRateDevice)
    }

    @Test
    fun `clearing the device removes both keys`() {
        val p = profile()
        p.heartRateDevice = HeartRateDevice("AA:BB", "Strap")
        p.heartRateDevice = null
        assertNull(p.heartRateDevice)
        val prefs = context.getSharedPreferences("cindy", Context.MODE_PRIVATE)
        assertFalse(prefs.contains("hr_device_address"))
        assertFalse(prefs.contains("hr_device_name"))
    }

    @Test
    fun `an unknown sex name decodes to null`() {
        profile()
        context.getSharedPreferences("cindy", Context.MODE_PRIVATE).edit()
            .putString("sex", "NONBINARY_FORMULA_FROM_THE_FUTURE").apply()
        assertNull(Profile(context).sex)
    }

    @Test
    fun `age is computed from the birth year`() {
        val p = profile()
        p.birthYear = 1990
        assertEquals(36, p.age(nowYear = 2026))
    }

    @Test
    fun `age is null when the birth year has not been said`() {
        val p = profile()
        assertNull(p.age(nowYear = 2026))
    }

    @Test
    fun `body carries weight, age and sex together`() {
        val p = profile()
        p.bodyWeightKg = 70.0
        p.birthYear = 1990
        p.sex = Sex.MALE
        val body = p.body(nowYear = 2026)
        assertEquals(70.0, body.weightKg, 0.0)
        assertEquals(36, body.age)
        assertEquals(Sex.MALE, body.sex)
    }
}
