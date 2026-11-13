package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Which changes of the scoreboard bring the next set over the figure, and how soon.
 *
 * The movement changes when a set is finished and when it is skipped. Finishing banked the set's
 * last rep, whose roll and pulse play first; a skip banked nothing, so there is nothing to wait for.
 */
class NextSetTest {

    private fun after(event: RepEvent, before: Int, after: Int, running: Boolean = true, now: Exercise) =
        NextSet.after(event, FigureMotion.of(event, before, after), running, now)

    @Test
    fun `the last rep of a set brings the next set about 450 ms later`() {
        assertEquals(NextSet(Exercise.PUSHUP, inMs = 450), after(RepEvent.EXERCISE_DONE, 4, 5, now = Exercise.PUSHUP))
    }

    @Test
    fun `the last rep of a round brings the next round's first set`() {
        assertEquals(NextSet(Exercise.PULLUP, inMs = 450), after(RepEvent.ROUND_DONE, 29, 30, now = Exercise.PULLUP))
    }

    @Test
    fun `a skip while the clock runs brings the next set at once`() {
        assertEquals(NextSet(Exercise.SQUAT, inMs = 0), after(RepEvent.EXERCISE_DONE, 8, 8, now = Exercise.SQUAT))
        assertEquals(NextSet(Exercise.PULLUP, inMs = 0), after(RepEvent.ROUND_DONE, 8, 8, now = Exercise.PULLUP))
    }

    @Test
    fun `a rep, a rep taken back and a frame with no event leave the movement where it is`() {
        assertNull(after(RepEvent.REP, 2, 3, now = Exercise.PULLUP))
        assertNull(after(RepEvent.UNDO, 5, 4, now = Exercise.PULLUP))
        assertNull(after(RepEvent.NONE, 5, 5, now = Exercise.PUSHUP))
    }

    @Test
    fun `with the clock stopped the athlete is at the phone, and nothing takes the figure's place`() {
        // A skip on a pause moves the set on, and the band is drawn for the phone, not the bar.
        assertNull(after(RepEvent.EXERCISE_DONE, 3, 3, running = false, now = Exercise.PUSHUP))
    }

    @Test
    fun `the next set reads as its target over the movement's name in capitals, with no slash`() {
        val next = NextSet(Exercise.PUSHUP, inMs = 0)
        assertEquals("10", next.figure)
        assertEquals("PUSH-UPS", next.name)
        assertEquals("Next set: 10 push-ups", next.spoken)
    }
}
