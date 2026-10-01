package com.cindy.tracker

import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class StatTilesTest {

    private fun attempt(
        rounds: Int = 7,
        reps: Int = 12,
        splits: List<Long> = listOf(150_000L, 164_000L, 170_000L, 171_000L, 172_000L, 173_000L, 174_000L),
        pausedMs: Long = 0L,
        untrackedMs: Long = 0L,
        manualReps: Int = 0,
        countedReps: Int? = 222
    ) = Attempt(
        rounds = rounds, reps = reps, atMillis = 1L, durationMs = 20 * 60_000L,
        pausedMs = pausedMs, roundSplitsMs = splits, countedReps = countedReps,
        untrackedMs = untrackedMs, manualReps = manualReps
    )

    private fun byLabel(a: Attempt, stats: SessionStats? = null) =
        SessionTiles.of(a, stats).associateBy { it.label }

    @Test
    fun `six tiles in reading order`() {
        assertEquals(
            listOf("ROUNDS", "REPS", "TIME", "AVG", "FASTEST", "SLOWEST"),
            SessionTiles.of(attempt(), null).map { it.label }
        )
    }

    @Test
    fun `the tiles read the score and the clock`() {
        val t = byLabel(attempt())

        assertEquals("7", t.getValue("ROUNDS").value)
        assertEquals("+12 reps into round 8", t.getValue("ROUNDS").footnote)
        assertEquals("222", t.getValue("REPS").value)
        assertEquals("11.1 reps/min", t.getValue("REPS").footnote)
        assertEquals("20:00", t.getValue("TIME").value)
        assertEquals("on the clock", t.getValue("TIME").footnote)
        assertEquals("2:30", t.getValue("FASTEST").value)
        assertEquals("round 1", t.getValue("FASTEST").footnote)
        assertEquals("2:54", t.getValue("SLOWEST").value)
        assertEquals("round 7", t.getValue("SLOWEST").footnote)
        assertEquals("over 7 rounds", t.getValue("AVG").footnote)
    }

    @Test
    fun `reps are the banked score, not a round tally`() {
        // One round finished with the pull-ups skipped is 25 reps, never 30.
        val t = byLabel(attempt(rounds = 1, reps = 0, splits = listOf(120_000L), countedReps = 25))
        assertEquals("25", t.getValue("REPS").value)
    }

    @Test
    fun `a lower bound says at least, for the score and the pace`() {
        val t = byLabel(attempt(untrackedMs = 60_000L))

        assertEquals("at least 11.1 reps/min", t.getValue("REPS").footnote)
        assertTrue(t.getValue("REPS").speech, t.getValue("REPS").speech.startsWith("Reps: at least 222"))
        assertTrue(t.getValue("REPS").speech.contains("at least 11.1 reps a minute"))
    }

    @Test
    fun `a lower bound says at least over the reps into the next round, spoken too`() {
        val t = byLabel(attempt(untrackedMs = 60_000L)).getValue("ROUNDS")

        assertEquals("at least +12 reps into round 8", t.footnote)
        assertEquals("Rounds: 7, plus at least 12 reps into round 8", t.speech)
        assertEquals("Rounds: 7, plus 12 reps into round 8", byLabel(attempt()).getValue("ROUNDS").speech)
    }

    @Test
    fun `tapped reps are named on the reps tile`() {
        val t = byLabel(attempt(manualReps = 12))

        assertEquals("11.1 reps/min · 12 tapped", t.getValue("REPS").footnote)
        assertTrue(t.getValue("REPS").speech.contains("12 of them tapped in"))
    }

    @Test
    fun `a lower bound with tapped reps keeps the tapped count after the pace`() {
        val t = byLabel(attempt(untrackedMs = 60_000L, manualReps = 12))
        assertEquals("at least 11.1 reps/min · 12 tapped", t.getValue("REPS").footnote)
    }

    @Test
    fun `paused time is said beside the clock`() {
        val t = byLabel(attempt(pausedMs = 65_000L))
        assertEquals("plus 1:05 paused", t.getValue("TIME").footnote)
    }

    @Test
    fun `no complete round is a dash rather than a zero`() {
        val t = byLabel(attempt(rounds = 0, reps = 4, splits = emptyList(), countedReps = 4))

        assertEquals(SessionTiles.NONE, t.getValue("AVG").value)
        assertEquals(SessionTiles.NONE, t.getValue("FASTEST").value)
        assertEquals(SessionTiles.NONE, t.getValue("SLOWEST").value)
        assertEquals("+4 reps into round 1", t.getValue("ROUNDS").footnote)
        assertEquals(
            "none finished",
            byLabel(attempt(rounds = 0, reps = 0, splits = emptyList(), countedReps = 0))
                .getValue("ROUNDS").footnote
        )
    }

    @Test
    fun `the unfinished round comes from the sets when they exist`() {
        val a = Attempt(
            rounds = 1, reps = 0, atMillis = 1L, durationMs = 20 * 60_000L,
            roundSplitsMs = listOf(52_000L), countedReps = 33,
            setSplits = listOf(
                SetSplit(Exercise.PULLUP, 14_000L, 5, 0), SetSplit(Exercise.PUSHUP, 17_000L, 10, 0),
                SetSplit(Exercise.SQUAT, 21_000L, 15, 0)
            )
        )
        val t = byLabel(a, SessionStats.from(a))
        assertEquals("+3 reps into round 2", t.getValue("ROUNDS").footnote)
    }

    @Test
    fun `without round splits the average says it is the clock over the rounds`() {
        val t = byLabel(attempt(splits = emptyList()))
        assertEquals("clock over rounds", t.getValue("AVG").footnote)
    }

    /** The figure view of every tile in the grid: the TextView after each tile's eyebrow. */
    private fun valueViews(grid: View): List<TextView> {
        val tiles = mutableListOf<ViewGroup>()
        fun walk(v: View) {
            if (v is ViewGroup && v.contentDescription != null) tiles += v
            else if (v is ViewGroup) for (i in 0 until v.childCount) walk(v.getChildAt(i))
        }
        walk(grid)
        return tiles.map { it.getChildAt(1) as TextView }
    }

    @Test
    fun `the figures of a row of tiles start level at a large font scale`() {
        RuntimeEnvironment.setFontScale(1.5f)
        val context = ApplicationProvider.getApplicationContext<Context>()
        val a = attempt()
        val grid = context.statTileGrid(SessionTiles.of(a, null))
        grid.measure(
            View.MeasureSpec.makeMeasureSpec(context.dp(328), View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
        grid.layout(0, 0, grid.measuredWidth, grid.measuredHeight)

        val values = valueViews(grid)
        assertEquals(6, values.size)
        for (row in values.chunked(3)) {
            val tops = row.map { (it.parent as View).top + it.top }
            assertTrue("figures start at $tops", tops.max() - tops.min() <= 1)
        }
    }
}
