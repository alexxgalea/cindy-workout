package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The calorie line of the session timeline: how it is cut into measured and estimated stretches,
 * and what it says at a moment, for a round and in the legend. The line itself is
 * [Calories.timeline]'s, tested beside it; the points here are written out so each number can be
 * read off.
 */
class SessionTimelineCaloriesTest {

    private fun attempt(untracked: Long = 0L) = Attempt(
        rounds = 2, reps = 3, atMillis = 1_000L, durationMs = 120_000L,
        roundSplitsMs = listOf(60_000L, 50_000L), countedReps = 63,
        // No set times, so no reps line: what is under test here is the calorie words alone.
        setSplits = emptyList(),
        untrackedMs = untracked
    )

    private fun timeline(points: List<CaloriePoint>, untracked: Long = 0L) =
        SessionTimeline.of(attempt(untracked), marks = null, trace = null, calories = points)

    /** Reps only: the origin and the end, one estimated stretch, 120 kcal over two minutes. */
    private val estimatedOnly = listOf(
        CaloriePoint(0L, 0.0, false), CaloriePoint(120_000L, 120.0, false)
    )

    /** Estimated for the first half minute, measured to the minute, then estimated again. */
    private val mixed = listOf(
        CaloriePoint(0L, 0.0, false),
        CaloriePoint(30_000L, 30.0, false),
        CaloriePoint(60_000L, 60.0, true),
        CaloriePoint(120_000L, 100.0, false)
    )

    // ── runs ────────────────────────────────────────────────────────────────

    @Test
    fun `no points, or only the origin, draw no line`() {
        assertTrue(timeline(emptyList()).calorieRuns.isEmpty())
        assertTrue(timeline(listOf(CaloriePoint(0L, 0.0, false))).calorieRuns.isEmpty())
    }

    @Test
    fun `an estimate with no watch is one estimated run`() {
        val runs = timeline(estimatedOnly).calorieRuns
        assertEquals(1, runs.size)
        assertTrue(runs[0].estimated)
        assertEquals(estimatedOnly, runs[0].points)
    }

    @Test
    fun `runs change where the source changes and share the point they meet at`() {
        val runs = timeline(mixed).calorieRuns
        assertEquals(listOf(true, false, true), runs.map { it.estimated })
        assertEquals(listOf(0L, 30_000L), runs[0].points.map { it.clockMs })
        assertEquals(listOf(30_000L, 60_000L), runs[1].points.map { it.clockMs })
        assertEquals(listOf(60_000L, 120_000L), runs[2].points.map { it.clockMs })
    }

    @Test
    fun `neighbouring stretches of one kind are one run`() {
        val points = listOf(
            CaloriePoint(0L, 0.0, false),
            CaloriePoint(10_000L, 10.0, true),
            CaloriePoint(20_000L, 20.0, true),
            CaloriePoint(30_000L, 30.0, false)
        )
        val runs = timeline(points).calorieRuns
        assertEquals(listOf(false, true), runs.map { it.estimated })
        assertEquals(listOf(0L, 10_000L, 20_000L), runs[0].points.map { it.clockMs })
        assertEquals(listOf(20_000L, 30_000L), runs[1].points.map { it.clockMs })
    }

    // ── the moment ──────────────────────────────────────────────────────────

    @Test
    fun `a moment reads the line between its two points, not the last one`() {
        val t = timeline(mixed)
        assertEquals(0, t.at(0L).kcal)
        assertEquals(15, t.at(15_000L).kcal)
        assertEquals(80, t.at(90_000L).kcal)
        assertEquals(100, t.at(120_000L).kcal)
    }

    @Test
    fun `without a calorie line there is no figure to say`() {
        val t = timeline(emptyList())
        assertNull(t.at(60_000L).kcal)
        assertFalse(t.readout(t.at(60_000L)).detail.orEmpty().contains("kcal"))
    }

    @Test
    fun `the readout says estimated every time`() {
        val t = timeline(mixed)
        assertTrue(t.readout(t.at(90_000L)).detail!!.contains("80 kcal (est.)"))
        assertTrue(t.readout(t.at(15_000L)).detail!!.contains("15 kcal (est.)"))
    }

    @Test
    fun `a lower-bound score says at least wherever the figure leans on the reps`() {
        val t = timeline(mixed, untracked = Records.UNTRACKED_TOLERANCE_MS)
        // The first half minute is the reps' estimate: missing reps can only have lowered it.
        assertTrue(t.readout(t.at(15_000L)).detail!!.contains("at least 15 kcal (est.)"))
        assertTrue(t.readout(t.at(90_000L)).detail!!.contains("at least 80 kcal (est.)"))
    }

    @Test
    fun `a lower-bound score does not floor a figure the watch measured`() {
        val measured = listOf(CaloriePoint(0L, 0.0, false), CaloriePoint(60_000L, 60.0, true))
        val t = timeline(measured, untracked = Records.UNTRACKED_TOLERANCE_MS)
        // The first stretch's flag is the one ending at 60 s: heart-rate measured, no floor.
        assertFalse(t.readout(t.at(60_000L)).detail!!.contains("at least"))
    }

    @Test
    fun `a score that is not a lower bound never says at least`() {
        assertFalse(timeline(mixed).readout(timeline(mixed).at(90_000L)).detail!!.contains("at least"))
    }

    // ── TalkBack ────────────────────────────────────────────────────────────

    @Test
    fun `a round says its estimated calories by its end`() {
        val t = timeline(mixed)
        assertEquals(
            "Round 1, 0:00 to 1:00, 1 minute, 60 kilocalories, estimated, by its end",
            t.describeRound(t.rounds[0]).replace(Regex(", \\d+ reps? by its end"), "")
        )
    }

    @Test
    fun `a lower-bound round says at least`() {
        val t = timeline(mixed, untracked = Records.UNTRACKED_TOLERANCE_MS)
        assertTrue(t.describeRound(t.rounds[1]).contains("at least 93 kilocalories, estimated, by its end"))
    }

    // ── the legend ──────────────────────────────────────────────────────────

    @Test
    fun `no calorie line leaves the legend as it was`() {
        assertNull(timeline(emptyList()).legend())
    }

    @Test
    fun `the legend says the line is an estimate and what its dashes are`() {
        assertEquals(
            "KCAL is an estimate from your reps. The Calories (est.) row below says how.",
            timeline(estimatedOnly).legend()
        )
        assertEquals(
            "KCAL is an estimate; its dashed stretches come from your reps, not your heart rate. " +
                "The Calories (est.) row below says how.",
            timeline(mixed).legend()
        )
        val measured = listOf(CaloriePoint(0L, 0.0, false), CaloriePoint(60_000L, 60.0, true))
        assertEquals(
            "KCAL is an estimate from your heart rate. The Calories (est.) row below says how.",
            timeline(measured).legend()
        )
    }

    @Test
    fun `the legend says why a lower-bound score reads at least`() {
        assertTrue(
            timeline(mixed, untracked = Records.UNTRACKED_TOLERANCE_MS).legend()!!
                .contains("since some reps may be missing")
        )
    }
}
