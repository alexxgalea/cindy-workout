package com.cindy.tracker

import android.content.Context
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Touch handling and accessibility of the round splits, on a 1000 by 600 view.
 *
 * Geometry is read back through `barCenterX` rather than restated, so the tests keep passing
 * when the plot's padding changes; what they pin down is the behaviour.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class RoundSplitsViewTest {

    private fun view(): RoundSplitsView {
        val context = ApplicationProvider.getApplicationContext<Context>()
        return RoundSplitsView(context).apply {
            measure(
                View.MeasureSpec.makeMeasureSpec(1000, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(600, View.MeasureSpec.EXACTLY)
            )
            layout(0, 0, 1000, 600)
        }
    }

    private fun stacked(round: Int, ms: Long) =
        RoundSplits.Bar(round, ms, listOf(ms / 4, ms / 4, ms / 2))

    /** Three finished rounds (the middle one with no movement times) and one still open. */
    private fun RoundSplitsView.withBars(): RoundSplitsView = apply {
        show(
            bars = listOf(
                stacked(1, 168_000L),
                RoundSplits.Bar(2, 150_000L, null),
                stacked(3, 160_000L),
                RoundSplits.Bar(4, 70_000L, listOf(30_000L), unfinished = true, reps = 12)
            ),
            fastest = 1, averageMs = 159_000L, averageLabel = "AVG 2:39",
            describe = { "Round ${it + 1}" }
        )
    }

    private fun RoundSplitsView.touch(action: Int, x: Float, downTime: Long) {
        val e = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action, x, 300f, 0)
        dispatchTouchEvent(e)
        e.recycle()
    }

    private fun RoundSplitsView.tap(x: Float) {
        val t = SystemClock.uptimeMillis()
        touch(MotionEvent.ACTION_DOWN, x, t)
        touch(MotionEvent.ACTION_UP, x, t)
    }

    @Test
    fun `there is a bar for every round, the open one included`() {
        assertEquals(4, view().withBars().barCount)
    }

    @Test
    fun `a tap selects the bar under it and reports it`() {
        val view = view().withBars()
        val received = ArrayList<Int?>()
        view.onSelect = { received.add(it) }

        view.tap(view.barCenterX(2))

        assertEquals(2, view.selected)
        assertEquals(listOf<Int?>(2), received)
    }

    @Test
    fun `a tap between two bars still picks one, and one past the end picks the last`() {
        val view = view().withBars()

        view.tap(view.barCenterX(3) + 200f)

        assertEquals(3, view.selected)
    }

    @Test
    fun `tapping the selected bar clears it`() {
        val view = view().withBars()
        val received = ArrayList<Int?>()
        view.onSelect = { received.add(it) }

        view.tap(view.barCenterX(1))
        view.tap(view.barCenterX(1))

        assertNull(view.selected)
        assertEquals(listOf<Int?>(1, null), received)
    }

    @Test
    fun `a sideways drag scrubs through the bars`() {
        val view = view().withBars()
        val received = ArrayList<Int?>()
        view.onSelect = { received.add(it) }
        val t = SystemClock.uptimeMillis()
        val from = view.barCenterX(0)
        val to = view.barCenterX(3)

        view.touch(MotionEvent.ACTION_DOWN, from, t)
        var x = from
        while (x < to) {
            x = minOf(x + 20f, to)
            view.touch(MotionEvent.ACTION_MOVE, x, t)
        }
        view.touch(MotionEvent.ACTION_UP, to, t)

        assertEquals(3, view.selected)
        val indices = received.filterNotNull()
        assertTrue("nothing was reported", indices.isNotEmpty())
        assertTrue("went backwards: $indices", indices.zipWithNext().all { (a, b) -> a <= b })
        assertEquals(3, indices.last())
    }

    @Test
    fun `choosing another comparison keeps the selection`() {
        val view = view().withBars()
        view.tap(view.barCenterX(0))

        view.setReference(listOf(170_000L, null, 140_000L, null))

        assertEquals(0, view.selected)
    }

    @Test
    fun `showing new bars clears the selection`() {
        val view = view().withBars()
        view.tap(view.barCenterX(0))

        view.withBars()

        assertNull(view.selected)
    }

    @Test
    fun `nothing is drawn or selectable with no bars`() {
        val view = view()
        view.tap(500f)

        assertNull(view.selected)
        assertEquals(0, view.barCount)
    }

    @Test
    fun `every bar is its own screen reader stop, reading what the page says for it`() {
        val view = view().withBars()
        val provider = view.accessibilityNodeProvider!!

        val host = provider.createAccessibilityNodeInfo(View.NO_ID)!!

        assertEquals(4, host.childCount)
        val text = provider.createAccessibilityNodeInfo(2)!!.contentDescription
        assertEquals("Round 3", text.toString())
    }

    @Test
    fun `a screen reader can select a bar`() {
        val view = view().withBars()
        val provider = view.accessibilityNodeProvider!!

        provider.performAction(1, AccessibilityNodeInfo.ACTION_CLICK, null)

        assertEquals(1, view.selected)
    }
}
