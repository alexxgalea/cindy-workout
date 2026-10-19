package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The workout model and its catalog.
 *
 * The catalog holds Cindy only, for now, and Cindy has to be the workout the app already counts:
 * the same movements, reps and clock as the engine and the camera screen, not a second copy of
 * them that could drift.
 */
class WorkoutTest {

    private val cindy = Workouts.CINDY

    @Test
    fun `the catalog holds Cindy and nothing else yet`() {
        assertEquals(listOf(cindy), Workouts.catalog)
    }

    @Test
    fun `Cindy is a twenty-minute AMRAP of five, ten and fifteen, scored in rounds and reps`() {
        assertEquals("cindy", cindy.id)
        assertEquals("Cindy", cindy.name)
        assertEquals(Structure.AMRAP, cindy.structure)
        assertEquals(20 * 60_000L, cindy.timeCapMs)
        assertEquals(Scoring.ROUNDS_AND_REPS, cindy.scoring)
        assertEquals(
            listOf(
                Prescription(Exercise.PULLUP, 5),
                Prescription(Exercise.PUSHUP, 10),
                Prescription(Exercise.SQUAT, 15)
            ),
            cindy.movements
        )
    }

    @Test
    fun `Cindy's movements are the engine's own targets, in the engine's order`() {
        assertEquals(Exercise.entries.toList(), cindy.movements.map { it.movement })
        assertEquals(Exercise.entries.map { it.target }, cindy.movements.map { it.reps })
    }

    @Test
    fun `Cindy's clock agrees with the copies of the twenty minutes the app already keeps`() {
        assertEquals(Records.BENCHMARK.durationMs, cindy.timeCapMs)
        assertEquals(Progress.FULL_SESSION_MS + 1_000L, cindy.timeCapMs)
    }

    @Test
    fun `Cindy is described in one line, from its own round`() {
        assertEquals(
            "Rounds of 5 pull-ups, 10 push-ups and 15 squats, as many as you can.",
            cindy.description
        )
        assertEquals("20-minute AMRAP", cindy.format)
    }

    @Test
    fun `the four structures are known from the start, in the glossary's words`() {
        assertEquals(
            listOf("AMRAP", "EMOM", "For time", "Free"),
            Structure.entries.map { it.label }
        )
    }

    @Test
    fun `a format names the clock the way the structure uses it`() {
        fun workout(structure: Structure, capMs: Long?) = cindy.copy(
            id = "test", structure = structure, timeCapMs = capMs
        )
        assertEquals("10-minute EMOM", workout(Structure.EMOM, 10 * 60_000L).format)
        assertEquals("For time, 15-minute cap", workout(Structure.FOR_TIME, 15 * 60_000L).format)
        assertEquals("For time", workout(Structure.FOR_TIME, null).format)
        assertEquals("Free", workout(Structure.FREE, null).format)
    }

    /**
     * An id is written into the record board's line format, between `|` and `,` separators, and
     * is the one thing about a workout that can never change once a session carries it.
     */
    @Test
    fun `ids are unique and safe to file a session under`() {
        val ids = Workouts.catalog.map { it.id }
        assertEquals(ids.distinct(), ids)
        ids.forEach { assertTrue("unsafe id '$it'", it.matches(Regex("[a-z0-9-]+"))) }
    }

    @Test
    fun `a workout is found by its id, and an id this build does not know finds nothing`() {
        assertSame(cindy, Workouts.byId("cindy"))
        assertNull(Workouts.byId("chelsea"))
        assertNull(Workouts.byId(""))
        assertNull(Workouts.byId(null))
    }
}
