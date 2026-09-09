package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The drawn pull-up gate.
 *
 * An overlay that disagrees with the gate is worse than no overlay: it would have the athlete
 * correcting towards a box that is not the one refusing their reps. These tests pin the drawing
 * to the same geometry [BarZone.holds] tests.
 */
class BarGuideTest {

    private var clock = 0L

    private fun WorkoutEngine.hold(pose: Array<Keypoint>, frames: Int = 10) {
        repeat(frames) {
            onFrame(pose, clock)
            clock += 100
        }
    }

    private fun Array<Keypoint>.moved(dx: Float, dy: Float): Array<Keypoint> =
        Array(size) { i ->
            val p = this[i]
            if (p.score <= 0f) p else Keypoint(p.x + dx, p.y + dy, p.score)
        }

    private fun BarZone.Bounds.holds(p: Keypoint) =
        p.x >= left && p.x <= right && p.y >= top && p.y <= bottom

    @Test
    fun `there is nothing to draw until a dead hang marks the bar`() {
        val e = WorkoutEngine()
        assertNull(e.barGuide)
        e.hold(PoseFixtures.pullup(60f))
        assertNull("bent arms teach nothing about where the bar is", e.barGuide)
        e.hold(PoseFixtures.pullup(170f))
        assertNotNull(e.barGuide)
    }

    @Test
    fun `the box that is drawn is the box that is tested`() {
        val zone = BarZone()
        zone.observeHang(handsX = 0f, handsY = 0f, halfGrip = 20f)
        val torso = 100f
        val bounds = zone.bounds(torso)!!

        var disagreements = 0
        var inside = 0
        for (dx in -300..300 step 25) {
            for (dy in -200..200 step 25) {
                val left = Keypoint(dx - 10f, dy.toFloat(), 0.9f)
                val right = Keypoint(dx + 10f, dy.toFloat(), 0.9f)
                val drawn = bounds.holds(left) && bounds.holds(right)
                if (drawn) inside++
                if (drawn != zone.holds(left, right, torso)) disagreements++
            }
        }
        assertEquals("the drawing and the gate must agree everywhere", 0, disagreements)
        assertTrue("the sweep has to actually cross the boundary", inside in 1 until 25 * 17)
    }

    @Test
    fun `the box grows with the athlete's distance from the camera`() {
        val zone = BarZone()
        zone.observeHang(handsX = 0f, handsY = 0f, halfGrip = 20f)
        val near = zone.bounds(200f)!!
        val far = zone.bounds(50f)!!
        assertTrue(near.bottom - near.top > far.bottom - far.top)
        assertTrue(near.right - near.left > far.right - far.left)
        assertEquals("the bar itself does not move", near.lineY, far.lineY, 0.001f)
    }

    @Test
    fun `the reset line sits a quarter of a torso below the bar`() {
        val e = WorkoutEngine()
        e.hold(PoseFixtures.pullup(170f))
        val guide = e.barGuide!!
        // The fixture's shoulders and hips are exactly one TORSO apart, and the engine's
        // HEAD_RESET_TORSOS is 0.25 — private, so it is restated rather than read.
        assertEquals(
            guide.zone.lineY + 0.25f * PoseFixtures.TORSO,
            guide.resetY,
            0.01f
        )
    }

    @Test
    fun `stepping off the bar shuts the gate without moving it`() {
        val e = WorkoutEngine()
        e.hold(PoseFixtures.pullup(170f))
        val onBar = e.barGuide!!
        assertTrue(onBar.gateOpen)

        // Same body, same scale, well below the bar: the estimate stands, the gate does not.
        e.hold(PoseFixtures.pullup(170f).moved(0f, 400f))
        val offBar = e.barGuide!!
        assertFalse(offBar.gateOpen)
        assertEquals(
            "the athlete has to be able to see where to go back to",
            onBar.zone.lineY, offBar.zone.lineY, 0.01f
        )
    }

    @Test
    fun `a recalibration takes the gate off the screen with the bar`() {
        val e = WorkoutEngine()
        e.hold(PoseFixtures.pullup(170f))
        assertNotNull(e.barGuide)
        e.recalibrate()
        assertNull("the camera moved, so the drawn bar is a lie", e.barGuide)
    }
}
