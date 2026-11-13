package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Which change of the figure is a banked rep, which is a rep taken back, and which is neither.
 *
 * Read off the engine's banked total, never off the count on show: the count drops to 0 when a
 * set is finished and when it is skipped, and only one of those banked a rep.
 */
class FigureMotionTest {

    private fun motion(event: RepEvent, before: Int, after: Int) = FigureMotion.of(event, before, after)

    @Test
    fun `a rep the camera saw or the athlete tapped in is banked`() {
        assertEquals(FigureMotion.BANKED, motion(RepEvent.REP, before = 2, after = 3))
    }

    @Test
    fun `the last rep of a set, and of a round, is banked`() {
        assertEquals(FigureMotion.BANKED, motion(RepEvent.EXERCISE_DONE, before = 4, after = 5))
        assertEquals(FigureMotion.BANKED, motion(RepEvent.ROUND_DONE, before = 29, after = 30))
    }

    @Test
    fun `a skip moves the set on but banks nothing`() {
        assertEquals(FigureMotion.NONE, motion(RepEvent.EXERCISE_DONE, before = 3, after = 3))
        assertEquals(FigureMotion.NONE, motion(RepEvent.ROUND_DONE, before = 12, after = 12))
    }

    @Test
    fun `minus takes a rep back, across a set's edge too`() {
        assertEquals(FigureMotion.TAKEN_BACK, motion(RepEvent.UNDO, before = 3, after = 2))
        assertEquals(FigureMotion.TAKEN_BACK, motion(RepEvent.UNDO, before = 5, after = 4))
    }

    @Test
    fun `a frame with no event never moves the figure`() {
        // A new workout clears the score: that is not a rep taken back.
        assertEquals(FigureMotion.NONE, motion(RepEvent.NONE, before = 37, after = 0))
        // A state frame drawn after the event it was older than: the rep has had its motion.
        assertEquals(FigureMotion.NONE, motion(RepEvent.NONE, before = 2, after = 3))
        assertEquals(FigureMotion.NONE, motion(RepEvent.NONE, before = 3, after = 3))
    }
}
