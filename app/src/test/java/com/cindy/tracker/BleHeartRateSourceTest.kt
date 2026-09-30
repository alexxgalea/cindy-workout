package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The one part of the reconnect logic that is pure: the backoff schedule. Everything else here
 * needs a real [android.bluetooth.BluetoothGatt] callback from the platform, which is what the
 * manual device checklist covers instead.
 */
class BleHeartRateSourceTest {

    @Test
    fun `backs off then caps at ten seconds`() {
        assertEquals(1_000L, BleHeartRateSource.reconnectDelayMs(1))
        assertEquals(2_000L, BleHeartRateSource.reconnectDelayMs(2))
        assertEquals(4_000L, BleHeartRateSource.reconnectDelayMs(3))
        assertEquals(8_000L, BleHeartRateSource.reconnectDelayMs(4))
        assertEquals(10_000L, BleHeartRateSource.reconnectDelayMs(5))
        assertEquals(10_000L, BleHeartRateSource.reconnectDelayMs(9))
    }
}
