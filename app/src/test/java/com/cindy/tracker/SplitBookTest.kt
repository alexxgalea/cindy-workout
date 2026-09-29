package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SplitBookTest {

    @Test
    fun `a set is timed from the end of the one before`() {
        val book = SplitBook()
        book.start()
        book.movementDone(Exercise.PULLUP, 14_000L, 5, 0)
        book.movementDone(Exercise.PUSHUP, 31_000L, 10, 0)
        assertEquals(listOf(14_000L, 17_000L), book.sets.map { it.ms })
    }

    @Test
    fun `a skipped set is kept but not complete`() {
        val book = SplitBook()
        book.start()
        book.movementDone(Exercise.PULLUP, 9_000L, 2, 0)
        val set = book.sets.single()
        assertEquals(2, set.reps)
        assertFalse(set.complete)
        assertFalse(set.measured)
    }

    @Test
    fun `a complete set with no tapped reps is measured`() {
        val book = SplitBook()
        book.start()
        book.movementDone(Exercise.PULLUP, 14_000L, 5, 0)
        assertTrue(book.sets.single().complete)
        assertTrue(book.sets.single().measured)
    }

    @Test
    fun `tapped reps count per set`() {
        val book = SplitBook()
        book.start()
        book.movementDone(Exercise.PULLUP, 14_000L, 5, 2)
        book.movementDone(Exercise.PUSHUP, 31_000L, 10, 5)
        book.movementDone(Exercise.SQUAT, 50_000L, 15, 5)
        assertEquals(listOf(2, 3, 0), book.sets.map { it.manualReps })
        assertEquals(listOf(false, false, true), book.sets.map { it.measured })
    }

    @Test
    fun `stepping back reopens the set from its original start`() {
        val book = SplitBook()
        book.start()
        book.movementDone(Exercise.PULLUP, 14_000L, 5, 0)
        book.movementDone(Exercise.PUSHUP, 31_000L, 10, 0)
        book.stepBack()
        assertEquals(1, book.sets.size)
        book.movementDone(Exercise.PUSHUP, 40_000L, 10, 0)
        assertEquals(26_000L, book.sets.last().ms)
    }

    @Test
    fun `stepping back over tapped reps restores the manual baseline`() {
        val book = SplitBook()
        book.start()
        book.movementDone(Exercise.PULLUP, 14_000L, 5, 1)
        book.movementDone(Exercise.PUSHUP, 31_000L, 10, 4)
        book.stepBack()
        book.movementDone(Exercise.PUSHUP, 40_000L, 10, 4)
        assertEquals(3, book.sets.last().manualReps)
    }

    @Test
    fun `stepping back with nothing done is a no-op`() {
        val book = SplitBook()
        book.start()
        book.stepBack()
        assertTrue(book.sets.isEmpty())
        book.movementDone(Exercise.PULLUP, 12_000L, 5, 0)
        assertEquals(12_000L, book.sets.single().ms)
    }

    @Test
    fun `start clears everything`() {
        val book = SplitBook()
        book.start()
        book.movementDone(Exercise.PULLUP, 14_000L, 5, 3)
        book.start()
        assertTrue(book.sets.isEmpty())
        book.movementDone(Exercise.PULLUP, 10_000L, 5, 0)
        assertEquals(10_000L, book.sets.single().ms)
        assertEquals(0, book.sets.single().manualReps)
    }
}
