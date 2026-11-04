package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * When the bar is believed, and when it is let go.
 *
 * The finder is replaced by a script of what it would say, because what is being tested is the
 * decision: how many looks, how much agreement, which hands count, when to forget. The finder's own
 * eyes are tested on pixels in [RailFinderTest].
 */
class RailTrackerTest {

    private val torso = 100f

    /** A body hanging by both hands from a bar the gate puts at y = 200. */
    private fun hanging(wristY: Float = 205f): Array<Keypoint> {
        val k = Array(KP.COUNT) { Keypoint(0f, 0f, 0f) }
        k[KP.LEFT_SHOULDER] = Keypoint(300f, 300f, 0.9f)
        k[KP.RIGHT_SHOULDER] = Keypoint(380f, 300f, 0.9f)
        k[KP.LEFT_HIP] = Keypoint(300f, 400f, 0.9f)
        k[KP.RIGHT_HIP] = Keypoint(380f, 400f, 0.9f)
        k[KP.LEFT_WRIST] = Keypoint(290f, wristY, 0.9f)
        k[KP.RIGHT_WRIST] = Keypoint(390f, wristY, 0.9f)
        return k
    }

    private fun guide(lineY: Float = 200f) = WorkoutEngine.BarGuide(
        zone = BarZone.Bounds(lineY = lineY, left = 220f, right = 460f, top = lineY - 75f, bottom = lineY + 75f),
        resetY = lineY + 100f,
        gateOpen = true
    )

    private val grey = Luma(1, 1, ByteArray(1))

    /** Where the last window the tracker asked for starts, so the script can answer in its pixels. */
    private var originX = 0
    private var originY = 0

    private val window = { x: Int, y: Int, _: Int, _: Int ->
        originX = x
        originY = y
        grey
    }

    /**
     * A finder that sees one real rail, [tilt] degrees, crossing x = 340 at y = 170 in the frame, and
     * answers for whichever window it is shown. [looks] counts the looks.
     */
    private fun says(
        tilt: () -> Float,
        looks: () -> Unit = {}
    ): (Luma, Float, Float, Int, Int, Int) -> RailLine? = { _, wx, _, _, _, _ ->
        looks()
        val slope = RailFinder.slopeOf(tilt())
        val absY = 170f + slope * (wx + originX - 340f)
        RailLine(slope, wx, absY - originY)
    }

    private fun RailTracker.feed(frames: Int, k: Array<Keypoint> = hanging(), g: WorkoutEngine.BarGuide? = guide()) {
        repeat(frames) { observe(k, g, 800, 1000, window) }
    }

    @Test
    fun `no rail is believed from the first look`() {
        val t = RailTracker(says({ 7.4f }))
        t.feed(3)
        assertNull(t.rail)
    }

    @Test
    fun `a rail is believed once the hands agree, and is drawn tilted and near the gate`() {
        val t = RailTracker(says({ 7.4f }))
        t.feed(30)
        val rail = t.rail
        assertNotNull(rail)
        assertEquals(7.4f, rail!!.line.degrees, 0.3f)
        assertTrue("reaches past the hands", rail.xFrom < 290f && rail.xTo > 390f)
    }

    @Test
    fun `one wild look among many does not move it`() {
        var n = 0
        val t = RailTracker(says({ if (++n == 4) 12.5f else 7.5f }))
        t.feed(40)
        assertEquals(7.5f, t.rail!!.line.degrees, 0.3f)
    }

    @Test
    fun `looks that disagree never make a rail`() {
        var n = 0
        val t = RailTracker(says({ if (n++ % 2 == 0) -9f else 11f }))
        t.feed(60)
        assertNull(t.rail)
    }

    @Test
    fun `hands that are not hanging from the bar do not vote`() {
        val t = RailTracker(says({ 7.4f }))
        // Wrists below the shoulders, as when standing at the bar.
        t.feed(40, hanging(wristY = 350f))
        assertNull(t.rail)
        // Wrists a long way from the gate's bar.
        t.feed(40, hanging(wristY = 20f), guide())
        assertNull(t.rail)
    }

    @Test
    fun `nothing is looked for while the gate has no bar`() {
        var looks = 0
        val t = RailTracker(says({ 7.4f }, { looks++ }))
        t.feed(40, g = null)
        assertEquals(0, looks)
    }

    @Test
    fun `once held it is not looked for again`() {
        var looks = 0
        val t = RailTracker(says({ 7.4f }, { looks++ }))
        t.feed(60)
        assertNotNull(t.rail)
        val atBelief = looks
        t.feed(60)
        assertEquals(atBelief, looks)
    }

    @Test
    fun `a moved phone forgets it and the next hang learns it again`() {
        val t = RailTracker(says({ 7.4f }))
        t.feed(30)
        assertNotNull(t.rail)
        t.reset()
        assertNull(t.rail)
        t.feed(30)
        assertNotNull(t.rail)
    }

    @Test
    fun `a gate that has gone to another bar drops the held one`() {
        val t = RailTracker(says({ 7.4f }))
        t.feed(30)
        assertNotNull(t.rail)
        // The gate is now two torsos higher than the held bar.
        t.observe(hanging(wristY = 5f), guide(lineY = 0f), 800, 1000, window)
        assertNull(t.rail)
    }
}
