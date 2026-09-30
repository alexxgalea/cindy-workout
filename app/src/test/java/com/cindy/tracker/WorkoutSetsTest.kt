package com.cindy.tracker

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

class WorkoutSetsTest {

    @Test
    fun `an empty list round-trips as an empty list`() {
        assertEquals("", WorkoutSets.encode(emptyList()))
        assertEquals(emptyList<WorkoutSet>(), WorkoutSets.decode(""))
    }

    @Test
    fun `null and blank decode as an empty list, meaning nothing was saved yet`() {
        assertEquals(emptyList<WorkoutSet>(), WorkoutSets.decode(null))
        assertEquals(emptyList<WorkoutSet>(), WorkoutSets.decode("   "))
    }

    @Test
    fun `a single set round-trips`() {
        val sets = listOf(WorkoutSet(1, Exercise.PULLUP, 5))
        assertEquals(sets, WorkoutSets.decode(WorkoutSets.encode(sets)))
    }

    @Test
    fun `several sets across rounds round-trip in order`() {
        val sets = listOf(
            WorkoutSet(1, Exercise.PULLUP, 5),
            WorkoutSet(1, Exercise.PUSHUP, 3),
            WorkoutSet(1, Exercise.SQUAT, 4),
            WorkoutSet(2, Exercise.PULLUP, 2)
        )
        assertEquals(sets, WorkoutSets.decode(WorkoutSets.encode(sets)))
    }

    @Test
    fun `a zero-rep set round-trips too, since the engine may report one`() {
        val sets = listOf(WorkoutSet(3, Exercise.SQUAT, 0))
        assertEquals(sets, WorkoutSets.decode(WorkoutSets.encode(sets)))
    }

    @Test
    fun `an unknown exercise name fails the whole list rather than guessing`() {
        assertNull(WorkoutSets.decode("v1|1|BURPEE|5"))
    }

    @Test
    fun `an unknown exercise poisons the whole list even when other lines are fine`() {
        val raw = "v1|1|PULLUP|5\nv1|1|BURPEE|3\nv1|1|SQUAT|4"
        assertNull(WorkoutSets.decode(raw))
    }

    @Test
    fun `garbage with the wrong number of fields decodes as null`() {
        assertNull(WorkoutSets.decode("v1|1|PULLUP"))
        assertNull(WorkoutSets.decode("not even close"))
    }

    @Test
    fun `a non-numeric round or rep count decodes as null`() {
        assertNull(WorkoutSets.decode("v1|one|PULLUP|5"))
        assertNull(WorkoutSets.decode("v1|1|PULLUP|five"))
    }

    @Test
    fun `an unrecognised version prefix decodes as null rather than being guessed at`() {
        assertNull(WorkoutSets.decode("v2|1|PULLUP|5"))
    }
}

/** Separate Robolectric class: only this needs a real [android.content.Context]. */
@RunWith(RobolectricTestRunner::class)
class SetStoreTest {

    private val context = ApplicationProvider.getApplicationContext<Application>()
    private val store = SetStore(context)

    @Test
    fun `a fresh store has nothing for an attempt it has never seen`() {
        assertNull(store.load(111L))
    }

    @Test
    fun `save then load round-trips the sets for that attempt`() {
        val sets = listOf(WorkoutSet(1, Exercise.PULLUP, 5), WorkoutSet(1, Exercise.PUSHUP, 3))
        store.save(111L, sets)
        assertEquals(sets, store.load(111L))
    }

    @Test
    fun `saving again replaces the list whole and leaves no temporary file behind`() {
        store.save(111L, listOf(WorkoutSet(1, Exercise.PULLUP, 5), WorkoutSet(1, Exercise.PUSHUP, 10)))
        store.save(111L, listOf(WorkoutSet(1, Exercise.PULLUP, 3)))

        assertEquals(listOf(WorkoutSet(1, Exercise.PULLUP, 3)), store.load(111L))
        val dir = java.io.File(context.filesDir, "sets")
        assertEquals(listOf("111.sets"), dir.list()!!.toList())
    }

    @Test
    fun `two attempts keep their own sets`() {
        store.save(111L, listOf(WorkoutSet(1, Exercise.PULLUP, 5)))
        store.save(222L, listOf(WorkoutSet(1, Exercise.SQUAT, 15)))

        assertEquals(listOf(WorkoutSet(1, Exercise.PULLUP, 5)), store.load(111L))
        assertEquals(listOf(WorkoutSet(1, Exercise.SQUAT, 15)), store.load(222L))
    }

    @Test
    fun `clear wipes every attempt's sets`() {
        store.save(111L, listOf(WorkoutSet(1, Exercise.PULLUP, 5)))
        store.save(222L, listOf(WorkoutSet(1, Exercise.SQUAT, 15)))

        store.clear()

        assertNull(store.load(111L))
        assertNull(store.load(222L))
    }
}
