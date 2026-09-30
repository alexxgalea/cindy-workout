package com.cindy.tracker

import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class HeartRateStoreTest {

    private fun store(): HeartRateStore = HeartRateStore(ApplicationProvider.getApplicationContext())

    @Test
    fun `save and load round trips`() {
        val store = store()
        val trace = HeartRateTrace(
            startedAtMillis = 1000L,
            samples = listOf(HeartRateSample(0L, 100), HeartRateSample(1000L, 110)),
            pauses = listOf(HeartRatePause(500L, 5000L))
        )
        store.save(atMillis = 42L, trace)
        assertEquals(trace, store.load(42L))
        store.clear()
    }

    @Test
    fun `load of a missing file is null`() {
        assertNull(store().load(999_999L))
    }

    @Test
    fun `clear deletes every saved trace`() {
        val store = store()
        val trace = HeartRateTrace(1000L, listOf(HeartRateSample(0L, 100)), emptyList())
        store.save(1L, trace)
        store.save(2L, trace)
        store.clear()
        assertNull(store.load(1L))
        assertNull(store.load(2L))
    }
}
