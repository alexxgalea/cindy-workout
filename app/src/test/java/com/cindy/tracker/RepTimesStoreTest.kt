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
class RepTimesStoreTest {

    private fun store(): RepTimesStore = RepTimesStore(ApplicationProvider.getApplicationContext())

    @Test
    fun `save and load round trips`() {
        val store = store()
        val marks = listOf(
            RepMark(0L, Exercise.PULLUP, manual = false),
            RepMark(1_000L, Exercise.PULLUP, manual = true)
        )
        store.save(atMillis = 42L, marks)
        assertEquals(marks, store.load(42L))
        store.clear()
    }

    @Test
    fun `load of a missing file is null`() {
        assertNull(store().load(999_999L))
    }

    @Test
    fun `clear deletes every saved file`() {
        val store = store()
        val marks = listOf(RepMark(0L, Exercise.SQUAT, manual = false))
        store.save(1L, marks)
        store.save(2L, marks)
        store.clear()
        assertNull(store.load(1L))
        assertNull(store.load(2L))
    }
}
