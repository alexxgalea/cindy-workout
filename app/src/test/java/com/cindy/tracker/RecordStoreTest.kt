package com.cindy.tracker

import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Whether [RecordStore.add] actually stored anything.
 *
 * A heart-rate trace is about to need this answer: it belongs beside a saved attempt, and a
 * zero-rep attempt never becomes one. `add` used to say nothing about which happened.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class RecordStoreTest {

    private fun store(): RecordStore {
        val store = RecordStore(ApplicationProvider.getApplicationContext())
        store.clear()
        return store
    }

    @Test
    fun `a zero-rep attempt is not stored`() {
        val store = store()
        val saved = store.add(Attempt(rounds = 0, reps = 0, atMillis = 1000L))
        assertFalse(saved)
        assertTrue(store.all().isEmpty())
    }

    @Test
    fun `a real attempt is stored`() {
        val store = store()
        val saved = store.add(Attempt(rounds = 12, reps = 7, atMillis = 1000L))
        assertTrue(saved)
        assertEquals(1, store.all().size)
    }
}
