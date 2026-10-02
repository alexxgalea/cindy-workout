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
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The zone bar on a 1000-wide view. Geometry is read back through `centreOf`, so what is pinned
 * down is the behaviour: a tap holds the zone under it, a second tap lets it go, a sideways drag
 * walks across the zones, and a zone with no time is neither drawn nor a stop.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ZoneBarViewTest {

    /** Z2 has no time. The rest are 1, 2, 3 and 4 minutes. */
    private val zones = listOf(
        ZoneTime(HeartZone.WARM_UP, 60_000L, null, 112),
        ZoneTime(HeartZone.EASY, 0L, 113, 130),
        ZoneTime(HeartZone.AEROBIC, 120_000L, 131, 149),
        ZoneTime(HeartZone.THRESHOLD, 180_000L, 150, 168),
        ZoneTime(HeartZone.MAXIMUM, 240_000L, 169, null)
    )
    private val said = zones.map { "${it.zone.label} says" }

    private fun view(): ZoneBarView {
        val context = ApplicationProvider.getApplicationContext<Context>()
        return ZoneBarView(context)
    }

    private fun ZoneBarView.lay(): ZoneBarView = apply {
        measure(
            View.MeasureSpec.makeMeasureSpec(1000, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
        layout(0, 0, measuredWidth, measuredHeight)
    }

    private fun ZoneBarView.touch(action: Int, x: Float, downTime: Long) {
        val e = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action, x, 20f, 0)
        dispatchTouchEvent(e)
        e.recycle()
    }

    private fun ZoneBarView.tap(x: Float) {
        val t = SystemClock.uptimeMillis()
        touch(MotionEvent.ACTION_DOWN, x, t)
        touch(MotionEvent.ACTION_UP, x, t)
    }

    private fun ZoneBarView.drawOnce() {
        draw(Canvas(Bitmap.createBitmap(measuredWidth, measuredHeight, Bitmap.Config.ARGB_8888)))
    }

    private fun loaded() = view().apply { setZones(zones, said) }.lay()

    @Test
    fun `it lays out at a finger's height and draws`() {
        val v = loaded()

        assertTrue("height ${v.measuredHeight}", v.measuredHeight >= 48 * v.resources.displayMetrics.density)
        v.drawOnce()
    }

    @Test
    fun `a tap holds the zone under it and reports it`() {
        val v = loaded()
        val received = ArrayList<Int?>()
        v.onSelect = { received.add(it) }

        v.tap(v.centreOf(3))

        assertEquals(3, v.selected)
        assertEquals(listOf<Int?>(3), received)
        v.drawOnce()
    }

    @Test
    fun `tapping the held zone again lets it go`() {
        val v = loaded()

        v.tap(v.centreOf(3))
        v.tap(v.centreOf(3))

        assertNull(v.selected)
    }

    @Test
    fun `a tap on empty bar beside a zone with no time picks the nearest zone that has some`() {
        val v = loaded()

        v.tap(v.centreOf(1))

        // Z2 has no width, so its centre is the edge Z1 and Z3 share; either neighbour is right,
        // but never Z2 itself.
        assertTrue("picked ${v.selected}", v.selected == 0 || v.selected == 2)
    }

    @Test
    fun `a sideways drag walks across the zones in order`() {
        val v = loaded()
        val received = ArrayList<Int?>()
        v.onSelect = { received.add(it) }
        val t = SystemClock.uptimeMillis()
        val from = v.centreOf(0)
        val to = v.centreOf(4)

        v.touch(MotionEvent.ACTION_DOWN, from, t)
        var x = from
        while (x < to) {
            x = minOf(x + 20f, to)
            v.touch(MotionEvent.ACTION_MOVE, x, t)
        }
        v.touch(MotionEvent.ACTION_UP, to, t)

        val seen = received.filterNotNull()
        assertEquals(listOf(0, 2, 3, 4), seen)
        assertEquals(4, v.selected)
    }

    @Test
    fun `talkback gets a stop for each zone that has time, and says what it was given`() {
        val v = loaded()

        assertEquals(4, v.stopCount)
        val helper = ViewCompat.getAccessibilityDelegate(v) as ExploreByTouchHelper
        val provider = helper.getAccessibilityNodeProvider(v)!!
        val root = provider.createAccessibilityNodeInfo(View.NO_ID)!!
        assertEquals(4, root.childCount)
        assertEquals("Warm-up says", provider.createAccessibilityNodeInfo(0)!!.contentDescription.toString())
        // The empty zone is skipped, so the second stop is the third zone.
        assertEquals("Aerobic says", provider.createAccessibilityNodeInfo(1)!!.contentDescription.toString())
    }

    @Test
    fun `a bar with no time draws nothing and takes no touch`() {
        val v = view().apply {
            setZones(zones.map { it.copy(ms = 0L) }, said)
        }.lay()
        val received = ArrayList<Int?>()
        v.onSelect = { received.add(it) }

        v.drawOnce()
        v.tap(500f)

        assertEquals(0, v.stopCount)
        assertTrue(received.isEmpty())
        assertNull(v.selected)
    }

    @Test
    fun `new data keeps a held zone that still has time and drops one that lost it`() {
        val v = loaded()
        v.select(3)

        v.setZones(zones, said)
        assertEquals(3, v.selected)

        v.setZones(zones.map { if (it.zone == HeartZone.THRESHOLD) it.copy(ms = 0L) else it }, said)
        assertNull(v.selected)
    }

    @Test
    fun `a zone with no time cannot be selected`() {
        val v = loaded()

        v.select(1)

        assertNull(v.selected)
    }
}
