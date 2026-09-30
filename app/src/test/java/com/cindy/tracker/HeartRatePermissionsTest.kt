package com.cindy.tracker

import org.junit.Assert.assertArrayEquals
import org.junit.Test

/** Pure: only [HeartRatePermissions.required] is exercised, since the other two need a real Context. */
class HeartRatePermissionsTest {

    @Test
    fun `sdk 31 and above needs the split Bluetooth permissions`() {
        assertArrayEquals(
            arrayOf("android.permission.BLUETOOTH_SCAN", "android.permission.BLUETOOTH_CONNECT"),
            HeartRatePermissions.required(sdk = 31)
        )
    }

    @Test
    fun `sdk 30 and below needs fine location instead`() {
        assertArrayEquals(
            arrayOf("android.permission.ACCESS_FINE_LOCATION"),
            HeartRatePermissions.required(sdk = 30)
        )
    }
}
