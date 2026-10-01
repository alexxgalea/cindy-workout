package com.cindy.tracker

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import androidx.core.view.ViewCompat
import androidx.customview.widget.ExploreByTouchHelper
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Touch handling and layout of the session timeline, on a 1000-wide view over a twenty-minute
 * clock. Geometry is read back through `xOf` rather than restated, as [ProgressChartViewTest]
 * does, so what is pinned down is the behaviour: a tap selects an instant, a second tap on it
 * clears it, a sideways drag scrubs.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SessionTimelineViewTest {

    private val duration = 20 * 60_000L

    private fun view(): SessionTimelineView {
        val context = ApplicationProvider.getApplicationContext<Context>()
        return SessionTimelineView(context)
    }

    private fun SessionTimelineView.lay(): SessionTimelineView = apply {
        measure(
            View.MeasureSpec.makeMeasureSpec(1000, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
        layout(0, 0, measuredWidth, measuredHeight)
    }

    private fun repsLane(withComparison: Boolean = false) = TimelineLane(
        label = "REPS",
        colour = 0xFFFFFFFF.toInt(),
        runs = listOf(
            TimelineRun((0..20).map { TimelinePoint(it * 60_000L, it * 10.0) })
        ),
        comparison = if (withComparison) (0..18).map { TimelinePoint(it * 60_000L, it * 9.0) }
        else emptyList(),
        format = { it.toInt().toString() },
        stepped = true,
        zeroBased = true,
        heightDp = 132
    )

    private fun heartLane() = TimelineLane(
        label = "HEART RATE",
        colour = 0xFFFF375F.toInt(),
        runs = listOf(
            TimelineRun((0..100).map { TimelinePoint(it * 1_000L, 100.0 + it) }),
            TimelineRun((200..300).map { TimelinePoint(it * 1_000L, 140.0) })
        ),
        format = { it.toInt().toString() },
        holdMs = Calories.MAX_HOLD_MS,
        heightDp = 88
    )

    private fun kcalLane() = TimelineLane(
        label = "KCAL (EST.)",
        colour = 0xFFAAAAAA.toInt(),
        runs = listOf(
            TimelineRun(listOf(TimelinePoint(0L, 0.0), TimelinePoint(300_000L, 40.0)), dashed = true),
            TimelineRun(listOf(TimelinePoint(300_000L, 40.0), TimelinePoint(900_000L, 130.0))),
            TimelineRun(listOf(TimelinePoint(900_000L, 130.0), TimelinePoint(duration, 180.0)), dashed = true)
        ),
        format = { it.toInt().toString() },
        zeroBased = true,
        interpolate = true,
        heightDp = 88
    )

    private fun stops() = (0 until 5).map {
        TimelineStop(it * 240_000L, (it + 1) * 240_000L, "Round ${it + 1}")
    }

    private fun SessionTimelineView.touch(action: Int, x: Float, downTime: Long) {
        val e = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action, x, 100f, 0)
        dispatchTouchEvent(e)
        e.recycle()
    }

    private fun SessionTimelineView.tap(x: Float) {
        val t = SystemClock.uptimeMillis()
        touch(MotionEvent.ACTION_DOWN, x, t)
        touch(MotionEvent.ACTION_UP, x, t)
    }

    private fun SessionTimelineView.drawOnce() {
        draw(Canvas(Bitmap.createBitmap(measuredWidth, measuredHeight, Bitmap.Config.ARGB_8888)))
    }

    @Test
    fun `one lane lays out and draws`() {
        val v = view()
        v.setLanes(listOf(repsLane()), duration, listOf(240_000L, 480_000L), stops())
        v.lay()

        assertEquals(1, v.laneCount)
        assertTrue("no height was asked for", v.measuredHeight > 0)
        v.drawOnce()
    }

    @Test
    fun `two lanes are taller than one and both draw, with a comparison and a gap in the heart`() {
        val one = view().apply { setLanes(listOf(repsLane()), duration) }.lay()
        val two = view().apply {
            setLanes(listOf(repsLane(withComparison = true), heartLane()), duration, listOf(240_000L), stops())
        }.lay()

        assertEquals(2, two.laneCount)
        assertTrue(two.measuredHeight > one.measuredHeight)
        two.select(130_000L)
        two.drawOnce()
    }

    @Test
    fun `a calorie lane of solid and dashed runs adds a lane and draws with a cursor on every run`() {
        val v = view().apply {
            setLanes(listOf(repsLane(), heartLane(), kcalLane()), duration, listOf(240_000L), stops())
        }.lay()

        assertEquals(3, v.laneCount)
        // One instant inside each run: the cursor looks the lane's value up in whichever run holds it.
        for (at in listOf(150_000L, 600_000L, 1_000_000L, duration)) {
            v.select(at)
            v.drawOnce()
        }
    }

    @Test
    fun `a taller stack of lanes is measured taller`() {
        val two = view().apply { setLanes(listOf(repsLane(), heartLane()), duration) }.lay()
        val three = view().apply { setLanes(listOf(repsLane(), heartLane(), kcalLane()), duration) }.lay()

        assertTrue(three.measuredHeight > two.measuredHeight)
    }

    @Test
    fun `a tap selects the instant under it, and reports it`() {
        val v = view().apply { setLanes(listOf(repsLane(), heartLane()), duration, stops = stops()) }.lay()
        val received = ArrayList<Long?>()
        v.onSelect = { received.add(it) }

        v.tap(v.xOf(600_000L))

        val picked = v.selectedMs!!
        assertTrue("picked $picked", kotlin.math.abs(picked - 600_000L) < 5_000L)
        assertEquals(listOf<Long?>(picked), received)
    }

    @Test
    fun `tapping the cursor again clears it`() {
        val v = view().apply { setLanes(listOf(repsLane()), duration, stops = stops()) }.lay()

        v.tap(v.xOf(600_000L))
        v.tap(v.xOf(600_000L))

        assertNull(v.selectedMs)
    }

    @Test
    fun `a sideways drag scrubs forward through the session`() {
        val v = view().apply { setLanes(listOf(repsLane(), heartLane()), duration, stops = stops()) }.lay()
        val received = ArrayList<Long?>()
        v.onSelect = { received.add(it) }
        val t = SystemClock.uptimeMillis()
        val from = v.xOf(100_000L)
        val to = v.xOf(900_000L)

        v.touch(MotionEvent.ACTION_DOWN, from, t)
        var x = from
        while (x < to) {
            x = minOf(x + 20f, to)
            v.touch(MotionEvent.ACTION_MOVE, x, t)
        }
        v.touch(MotionEvent.ACTION_UP, to, t)

        val clocks = received.filterNotNull()
        assertTrue("nothing was reported", clocks.isNotEmpty())
        assertTrue("went backwards: $clocks", clocks.zipWithNext().all { (a, b) -> a <= b })
        assertTrue(kotlin.math.abs(clocks.last() - 900_000L) < 5_000L)
        assertEquals(clocks.last(), v.selectedMs)
    }

    @Test
    fun `a cursor at the very ends stays on the clock`() {
        val v = view().apply { setLanes(listOf(repsLane()), duration, stops = stops()) }.lay()

        v.select(-10L)
        assertEquals(0L, v.selectedMs)
        v.select(duration + 99_999L)
        assertEquals(duration, v.selectedMs)
    }

    @Test
    fun `a selection survives swapping the lanes, as a comparison change does`() {
        val v = view().apply { setLanes(listOf(repsLane()), duration, stops = stops()) }.lay()
        v.select(300_000L)

        v.setLanes(listOf(repsLane(withComparison = true)), duration, stops = stops())

        assertEquals(300_000L, v.selectedMs)
    }

    @Test
    fun `talkback gets one stop per round`() {
        val v = view().apply { setLanes(listOf(repsLane(), heartLane()), duration, stops = stops()) }.lay()

        assertEquals(5, v.stopCount)
        val helper = ViewCompat.getAccessibilityDelegate(v) as ExploreByTouchHelper
        val provider = helper.getAccessibilityNodeProvider(v)!!
        val root = provider.createAccessibilityNodeInfo(View.NO_ID)!!
        assertEquals(5, root.childCount)
        val second = provider.createAccessibilityNodeInfo(1)!!
        assertEquals("Round 2", second.contentDescription.toString())
    }

    @Test
    fun `no lanes does not crash, draws nothing and takes no touch`() {
        val v = view().apply { setLanes(emptyList(), 0L) }.lay()
        val received = ArrayList<Long?>()
        v.onSelect = { received.add(it) }

        v.drawOnce()
        v.tap(100f)

        assertEquals(0, v.laneCount)
        assertEquals(0, v.stopCount)
        assertTrue(received.isEmpty())
        assertNull(v.selectedMs)
    }

    @Test
    fun `a lane with nothing in it does not crash`() {
        val empty = TimelineLane(
            label = "HEART RATE", colour = 0xFFFF375F.toInt(), runs = emptyList(),
            format = { it.toInt().toString() }
        )
        val v = view().apply { setLanes(listOf(empty), duration) }.lay()

        v.select(10_000L)
        v.drawOnce()
        assertNotNull(v.selectedMs)
        assertFalse(v.laneCount == 0)
    }

    @Test
    fun `a heart run of one reading still draws`() {
        val lone = TimelineLane(
            label = "HEART RATE", colour = 0xFFFF375F.toInt(),
            runs = listOf(TimelineRun(listOf(TimelinePoint(30_000L, 120.0)))),
            format = { it.toInt().toString() }, holdMs = Calories.MAX_HOLD_MS
        )
        val v = view().apply { setLanes(listOf(lone), duration) }.lay()

        v.select(31_000L)
        v.drawOnce()
    }
}
