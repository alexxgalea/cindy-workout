package com.cindy.tracker

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** A relabel saved through the filed session: the stored attempt is rewritten in place. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class FreestyleRelabelTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @After
    fun clear() {
        RecordStore(context).clear()
    }

    private fun free(at: Long) = Attempt(
        rounds = 0, reps = 0, atMillis = at, durationMs = 100_000L, countedReps = 12,
        workoutId = Workouts.FREESTYLE_ID,
        movementTotals = mapOf(Exercise.PUSHUP to 5, Exercise.SQUAT to 7),
        freestyleSets = listOf(
            FreestyleSet(Exercise.SQUAT, 7, 10_000L, 40_000L),
            FreestyleSet(Exercise.PUSHUP, 5, 55_000L, 70_000L)
        )
    )

    @Test
    fun `replacing a filed session rewrites only that one, in its place`() {
        val store = RecordStore(context).apply { clear() }
        store.add(free(5L))
        store.add(free(9L))
        val changed = FreestyleSets.relabel(free(9L), 0, Exercise.PULLUP)
        assertTrue(store.replace(changed))
        assertEquals(listOf(5L, 9L), store.all().map { it.atMillis })
        assertEquals(free(5L), store.all().first())
        assertEquals(changed, store.all().last())
    }

    @Test
    fun `replacing a session that is not filed files nothing`() {
        val store = RecordStore(context).apply { clear() }
        assertFalse(store.replace(free(3L)))
        assertEquals(emptyList<Attempt>(), store.all())
    }
}
