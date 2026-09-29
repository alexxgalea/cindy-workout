package com.cindy.tracker

import android.content.Context
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.LocalDate
import java.time.YearMonth
import java.time.temporal.WeekFields
import java.util.Locale

/**
 * Touch handling of the month calendar, on a 700 px wide view (100 px cells).
 *
 * Cells are found with [CalendarGrid] and the locale's first day of the week, exactly as the
 * view does, so the tests hold in any locale: a tap opens a trained day, and only a tap.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class CalendarViewTest {

    private val month = YearMonth.of(2026, 9)
    private val trainedDay = LocalDate.of(2026, 9, 7)
    private val firstDayOfWeek = WeekFields.of(Locale.getDefault()).firstDayOfWeek
    private val cell = 100f

    private fun calendar(): CalendarView {
        val context = ApplicationProvider.getApplicationContext<Context>()
        return CalendarView(context).apply {
            measure(
                View.MeasureSpec.makeMeasureSpec(700, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
            )
            layout(0, 0, measuredWidth, measuredHeight)
            show(month, setOf(trainedDay), LocalDate.of(2026, 9, 9))
        }
    }

    /** The centre of the cell holding [date], in view coordinates. */
    private fun centreOf(date: LocalDate): Pair<Float, Float> {
        val index = CalendarGrid.lead(month, firstDayOfWeek) + date.dayOfMonth - 1
        return cell * ((index % 7) + 0.5f) to cell * ((index / 7 + 1) + 0.5f)
    }

    private fun CalendarView.touch(action: Int, x: Float, y: Float, downTime: Long) {
        val e = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action, x, y, 0)
        dispatchTouchEvent(e)
        e.recycle()
    }

    private fun CalendarView.tap(x: Float, y: Float) {
        val t = SystemClock.uptimeMillis()
        touch(MotionEvent.ACTION_DOWN, x, y, t)
        touch(MotionEvent.ACTION_UP, x, y, t)
    }

    @Test
    fun `a tap on a trained day reports that date`() {
        val view = calendar()
        val received = ArrayList<LocalDate>()
        view.onDayTap = { received.add(it) }

        val (x, y) = centreOf(trainedDay)
        view.tap(x, y)

        assertEquals(listOf(trainedDay), received)
    }

    @Test
    fun `a tap on an untrained day reports nothing`() {
        val view = calendar()
        val received = ArrayList<LocalDate>()
        view.onDayTap = { received.add(it) }

        val (x, y) = centreOf(LocalDate.of(2026, 9, 8))
        view.tap(x, y)

        assertTrue("opened $received", received.isEmpty())
    }

    @Test
    fun `a drag that ends on a trained day reports nothing`() {
        val view = calendar()
        val received = ArrayList<LocalDate>()
        view.onDayTap = { received.add(it) }
        val t = SystemClock.uptimeMillis()

        val (x, y) = centreOf(trainedDay)
        // Down 200 px away, up on the 7th: the slow drag that used to open a sheet.
        view.touch(MotionEvent.ACTION_DOWN, x, y + 200f, t)
        view.touch(MotionEvent.ACTION_UP, x, y, t)
        // And the other way round: down on the 7th, up 200 px away.
        view.touch(MotionEvent.ACTION_DOWN, x, y, t)
        view.touch(MotionEvent.ACTION_UP, x, y + 200f, t)

        assertTrue("opened $received", received.isEmpty())
    }

    @Test
    fun `a tap without a listener does nothing`() {
        val view = calendar()

        val (x, y) = centreOf(trainedDay)
        view.tap(x, y)
    }
}
