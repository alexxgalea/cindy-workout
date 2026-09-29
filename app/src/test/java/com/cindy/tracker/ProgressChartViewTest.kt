package com.cindy.tracker

import android.content.Context
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Touch handling of the progress chart, on a 1000 by 600 view.
 *
 * Geometry is read back through `pointCenterX` rather than restated, so the tests keep passing
 * when the plot's padding changes; what they pin down is the behaviour: a tap selects, a second
 * tap clears, a sideways drag scrubs.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ProgressChartViewTest {

    private val day = 24 * 60 * 60_000L

    private fun chart(): ProgressChartView {
        val context = ApplicationProvider.getApplicationContext<Context>()
        return ProgressChartView(context).apply {
            measure(
                View.MeasureSpec.makeMeasureSpec(1000, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(600, View.MeasureSpec.EXACTLY)
            )
            layout(0, 0, 1000, 600)
        }
    }

    private fun ProgressChartView.withLine(): ProgressChartView = apply {
        showLine(
            points = listOf(
                ProgressPoint(0L, 100.0),
                ProgressPoint(day, 120.0, record = true),
                ProgressPoint(2 * day, 110.0)
            ),
            best = listOf(100.0, 120.0, 120.0),
            xStart = 0L, xEnd = 2 * day, invertY = false,
            edgeLabels = "1 Sep" to "3 Sep",
            axisLabel = { it.toInt().toString() },
            describe = { "Point $it" }
        )
    }

    private fun ProgressChartView.touch(action: Int, x: Float, downTime: Long) {
        val e = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action, x, 300f, 0)
        dispatchTouchEvent(e)
        e.recycle()
    }

    private fun ProgressChartView.tap(x: Float) {
        val t = SystemClock.uptimeMillis()
        touch(MotionEvent.ACTION_DOWN, x, t)
        touch(MotionEvent.ACTION_UP, x, t)
    }

    @Test
    fun `a tap selects the nearest point`() {
        val view = chart().withLine()
        val received = ArrayList<Int?>()
        view.onSelect = { received.add(it) }

        view.tap(view.pointCenterX(1))

        assertEquals(1, view.selected)
        assertEquals(listOf<Int?>(1), received)
    }

    @Test
    fun `tapping the selected point clears it`() {
        val view = chart().withLine()

        view.tap(view.pointCenterX(1))
        view.tap(view.pointCenterX(1))

        assertNull(view.selected)
    }

    @Test
    fun `a sideways drag scrubs through the points`() {
        val view = chart().withLine()
        val received = ArrayList<Int?>()
        view.onSelect = { received.add(it) }
        val t = SystemClock.uptimeMillis()
        val from = view.pointCenterX(0)
        val to = view.pointCenterX(2)

        view.touch(MotionEvent.ACTION_DOWN, from, t)
        var x = from
        while (x < to) {
            x = minOf(x + 20f, to)
            view.touch(MotionEvent.ACTION_MOVE, x, t)
        }
        view.touch(MotionEvent.ACTION_UP, to, t)

        assertEquals(2, view.selected)
        val indices = received.filterNotNull()
        assertTrue("nothing was reported", indices.isNotEmpty())
        assertTrue("went backwards: $indices", indices.zipWithNext().all { (a, b) -> a <= b })
        assertEquals(2, indices.last())
    }

    @Test
    fun `bars take a point each`() {
        val view = chart()
        view.showBars(
            points = List(5) { ProgressPoint(it * 7 * day, (it * 100).toDouble(), sessions = it) },
            edgeLabels = "1 Sep" to "29 Sep",
            axisLabel = { it.toInt().toString() },
            describe = { "Week $it" }
        )

        assertEquals(5, view.pointCount)
        view.tap(view.pointCenterX(4))

        assertEquals(4, view.selected)
    }
}
