package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Test

/** What a Freestyle session page says, as words, before any view draws them. */
class FreestylePageTest {

    private val sets = listOf(
        FreestyleSet(Exercise.SQUAT, 7, 10_000L, 40_000L),
        FreestyleSet(Exercise.SQUAT, 5, 66_000L, 80_000L),
        FreestyleSet(Exercise.PUSHUP, 4, 95_000L, 100_000L)
    )
    private val attempt = Attempt(
        rounds = 0, reps = 0, atMillis = 0L, durationMs = 125_000L, countedReps = 16,
        workoutId = Workouts.FREESTYLE_ID,
        movementTotals = mapOf(Exercise.SQUAT to 12, Exercise.PUSHUP to 4), freestyleSets = sets
    )

    @Test
    fun `one tile per movement with its reps, time in sets and number of sets`() {
        val tiles = FreestylePage.tiles(attempt)
        assertEquals(listOf("PUSH-UPS", "SQUATS"), tiles.map { it.label })
        assertEquals(listOf("4", "12"), tiles.map { it.value })
        assertEquals(listOf("0:05 in sets · 1 set", "0:44 in sets · 2 sets"), tiles.map { it.footnote })
    }

    @Test
    fun `every set in order with each Rest or Transition and its length`() {
        val rows = FreestylePage.rows(attempt)
        assertEquals(
            listOf(
                "SQUATS|7 reps · 0:10–0:40|0:30",
                "Rest||0:26",
                "SQUATS|5 reps · 1:06–1:20|0:14",
                "Transition||0:15",
                "PUSH-UPS|4 reps · 1:35–1:40|0:05"
            ),
            rows.map { "${it.title}|${it.detail}|${it.length}" }
        )
    }

    @Test
    fun `an attempt filed before sets existed still has tiles from its totals and no set list`() {
        val old = attempt.copy(freestyleSets = emptyList())
        assertEquals(listOf("4", "12"), FreestylePage.tiles(old).map { it.value })
        assertEquals(emptyList<FreestyleRow>(), FreestylePage.rows(old))
    }

    @Test
    fun `a set the athlete changed says so on its row, and each set row knows its place`() {
        val changed = FreestyleSets.relabel(attempt, 2, Exercise.PULLUP)
        val setRows = FreestylePage.rows(changed).filter { it.kind == FreestyleRow.Kind.SET }
        assertEquals(listOf(0, 1, 2), setRows.map { it.setIndex })
        assertEquals("PULL-UPS|4 reps · 1:35–1:40 · changed by you", setRows[2].let { "${it.title}|${it.detail}" })
        assertEquals("5 reps · 1:06–1:20", setRows[1].detail)
    }

    @Test
    fun `after a relabel the tiles and the gaps follow`() {
        val changed = FreestyleSets.relabel(attempt, 2, Exercise.SQUAT)
        assertEquals(listOf("SQUATS"), FreestylePage.tiles(changed).map { it.label })
        assertEquals(
            listOf("Rest", "Rest"),
            FreestylePage.rows(changed).filter { it.kind != FreestyleRow.Kind.SET }.map { it.title }
        )
    }
}
