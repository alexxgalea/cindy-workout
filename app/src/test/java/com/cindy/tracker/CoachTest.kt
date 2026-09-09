package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The voice has to answer two questions, and the second one is the easy one to forget: not only
 * "what am I doing wrong" but "is this position good enough to count?". An athlete on the bar
 * cannot see the screen, and silence on its own does not distinguish a working app from a
 * blind one.
 */
class CoachTest {

    private val coach = Coach()
    private var clock = 0L

    /** Runs the coach for [ms] in the given state, collecting everything it says. */
    private fun run(
        ms: Long,
        blocked: Boolean,
        hint: String = "",
        exercise: Exercise = Exercise.PULLUP,
        stepMs: Long = 100L
    ): List<String> {
        val said = mutableListOf<String>()
        val until = clock + ms
        while (clock < until) {
            coach.onFrame(exercise, blocked, hint, clock)?.let { said += it }
            clock += stepMs
        }
        return said
    }

    @Test
    fun `arriving at a movement in a good position is confirmed`() {
        assertEquals(listOf("Ready"), run(1_000, blocked = false))
    }

    @Test
    fun `the confirmation is not repeated while the athlete keeps working`() {
        run(1_000, blocked = false)
        assertEquals(emptyList<String>(), run(30_000, blocked = false))
    }

    @Test
    fun `a single good frame does not confirm anything`() {
        // The gate flickering open for one frame is not the athlete being in position.
        assertEquals(emptyList<String>(), run(200, blocked = false))
    }

    @Test
    fun `getting back into position after a fault is confirmed`() {
        run(1_000, blocked = false)
        run(3_000, blocked = true, hint = "Get on the bar")
        assertEquals(
            "the athlete needs to hear that they have fixed it",
            listOf("Ready"), run(1_000, blocked = false)
        )
    }

    @Test
    fun `a brief interruption mid-set is not worth confirming`() {
        run(1_000, blocked = false)
        // One second of lost tracking, shorter than a rest between reps.
        run(1_000, blocked = true, hint = "Tracking…")
        assertEquals(
            "confirming every flicker would be noise, not coaching",
            emptyList<String>(), run(5_000, blocked = false)
        )
    }

    @Test
    fun `a standing fault is spoken, but only after it has stood a while`() {
        assertEquals(
            "nothing in the first four seconds", emptyList<String>(),
            run(3_500, blocked = true, hint = "Get on the bar")
        )
        assertEquals(listOf("Get on the bar"), run(1_000, blocked = true, hint = "Get on the bar"))
    }

    @Test
    fun `a standing fault repeats slowly rather than every frame`() {
        val said = run(30_000, blocked = true, hint = "Return to a dead hang")
        assertEquals("roughly every twelve seconds, not every frame", 3, said.size)
        assertEquals(List(3) { "Return to a dead hang" }, said)
    }

    @Test
    fun `a moving problem is not announced once per hint`() {
        // Four different faults in quick succession is a moving target, not a standing one.
        val said = listOf("Get on the bar", "Show both hands", "Show your head", "Tracking…")
            .flatMap { run(1_000, blocked = true, hint = it) }
        assertEquals(emptyList<String>(), said)
    }

    @Test
    fun `each movement earns its own confirmation`() {
        assertEquals(listOf("Ready"), run(1_000, blocked = false, exercise = Exercise.PULLUP))
        assertEquals(listOf("Ready"), run(1_000, blocked = false, exercise = Exercise.PUSHUP))
        assertEquals(listOf("Ready"), run(1_000, blocked = false, exercise = Exercise.SQUAT))
    }

    @Test
    fun `coming back from a pause is confirmed`() {
        run(1_000, blocked = false)
        coach.interrupted()
        assertEquals(
            "the athlete has been away and is asking the same question again",
            listOf("Ready"), run(1_000, blocked = false)
        )
    }

    @Test
    fun `a fault interrupted by a pause does not resume mid-count`() {
        run(3_500, blocked = true, hint = "Get on the bar")
        coach.interrupted()
        assertEquals(
            "the four seconds start again after the break", emptyList<String>(),
            run(3_500, blocked = true, hint = "Get on the bar")
        )
    }
}
