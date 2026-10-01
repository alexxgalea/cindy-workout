package com.cindy.tracker

import android.content.Context
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import androidx.core.view.ViewCompat
import androidx.customview.widget.ExploreByTouchHelper
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The round track on a 1000 pixel wide view: how many pills it draws, what a tap or a drag
 * selects, and that TalkBack gets one stop per round.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class RoundTrackViewTest {

    private val plurals = SessionStats.plurals(CindyProfile.STANDARD)

    private fun split(movement: Exercise, reps: Int) = SetSplit(movement, 10_000L, reps, 0)

    /** [full] finished rounds, plus a pull-up and [open] push-ups in a round the clock ended. */
    private fun rounds(full: Int, open: Int = 0): List<RoundStat> {
        val splits = List(full) {
            listOf(
                split(Exercise.PULLUP, 5), split(Exercise.PUSHUP, 10), split(Exercise.SQUAT, 15)
            )
        }.flatten() + if (open > 0) listOf(split(Exercise.PULLUP, 5)) else emptyList()
        val a = Attempt(
            rounds = full, reps = 0, atMillis = 1L, durationMs = 20 * 60_000L,
            countedReps = splits.sumOf { it.reps } + open, setSplits = splits,
            roundSplitsMs = List(full) { 60_000L }
        )
        return SessionStats.from(a)!!.rounds
    }

    private fun track(rounds: List<RoundStat>): RoundTrackView {
        val context = ApplicationProvider.getApplicationContext<Context>()
        return RoundTrackView(context).apply {
            show(rounds) { rounds[it].caption(plurals) }
            measure(
                View.MeasureSpec.makeMeasureSpec(1000, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
            )
            layout(0, 0, measuredWidth, measuredHeight)
        }
    }

    private fun RoundTrackView.touch(action: Int, x: Float, y: Float, downTime: Long) {
        val e = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action, x, y, 0)
        dispatchTouchEvent(e)
        e.recycle()
    }

    private fun RoundTrackView.tap(i: Int) {
        val (x, y) = pillCentre(i)
        val t = SystemClock.uptimeMillis()
        touch(MotionEvent.ACTION_DOWN, x, y, t)
        touch(MotionEvent.ACTION_UP, x, y, t)
    }

    @Test
    fun `there is a pill for every round, the unfinished one included`() {
        assertEquals(8, track(rounds(7, open = 4)).pillCount)
        assertEquals(7, track(rounds(7)).pillCount)
    }

    @Test
    fun `ten pills to a row, so the height follows the rows`() {
        val one = track(rounds(10)).measuredHeight
        val two = track(rounds(11)).measuredHeight
        val three = track(rounds(21)).measuredHeight

        assertTrue("$one $two", two == one * 2)
        assertTrue("$two $three", three == one * 3)
        // A row is a full 48dp touch target high.
        val density = ApplicationProvider.getApplicationContext<Context>().resources.displayMetrics.density
        assertEquals((48 * density).toInt(), one)
    }

    @Test
    fun `a tap selects that round and reports it`() {
        val data = rounds(7, open = 4)
        val view = track(data)
        val received = ArrayList<Int?>()
        view.onSelect = { received.add(it) }

        view.tap(3)
        assertEquals(3, view.selected)
        view.tap(7)

        assertEquals(7, view.selected)
        assertEquals(listOf<Int?>(3, 7), received)
        assertEquals(
            "Round 8 · 9 of 30 · 5 strict pull-ups, 4 standard push-ups · unfinished",
            data[received.last()!!].caption(plurals)
        )
    }

    @Test
    fun `a second tap clears the selection`() {
        val view = track(rounds(5))

        view.tap(2)
        view.tap(2)

        assertNull(view.selected)
    }

    @Test
    fun `a tap on the second row lands on the second row`() {
        val view = track(rounds(14))

        view.tap(12)

        assertEquals(12, view.selected)
    }

    @Test
    fun `a sideways drag scrubs through the rounds`() {
        val view = track(rounds(10))
        val received = ArrayList<Int?>()
        view.onSelect = { received.add(it) }
        val t = SystemClock.uptimeMillis()
        val (fromX, y) = view.pillCentre(0)
        val (toX, _) = view.pillCentre(5)

        view.touch(MotionEvent.ACTION_DOWN, fromX, y, t)
        var x = fromX
        while (x < toX) {
            x = minOf(x + 10f, toX)
            view.touch(MotionEvent.ACTION_MOVE, x, y, t)
        }
        view.touch(MotionEvent.ACTION_UP, toX, y, t)

        assertEquals(5, view.selected)
        val indices = received.filterNotNull()
        assertTrue("went backwards: $indices", indices.zipWithNext().all { (a, b) -> a <= b })
    }

    @Test
    fun `talkback gets one stop per round, each reading as the round`() {
        val data = rounds(7, open = 4)
        val view = track(data)
        val helper = ViewCompat.getAccessibilityDelegate(view) as ExploreByTouchHelper

        val provider = helper.getAccessibilityNodeProvider(view)!!
        val root = provider.createAccessibilityNodeInfo(View.NO_ID)!!

        assertEquals(8, root.childCount)
        assertEquals(
            data[0].caption(plurals),
            provider.createAccessibilityNodeInfo(0)!!.contentDescription.toString()
        )
    }
}
