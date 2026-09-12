package com.cindy.tracker

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The bar zone is stored in frame pixels, so the question this answers is not "did the phone
 * move" for its own sake but "is the calibration still describing the picture".
 */
class CameraStabilityTest {

    private val monitor = CameraStabilityMonitor()
    private var clock = 0L

    private fun hold(ms: Long, yaw: Float, pitch: Float = 0f, stepMs: Long = 50L) {
        val until = clock + ms
        while (clock < until) {
            monitor.update(yaw, pitch, clock)
            clock += stepMs
        }
    }

    @Test
    fun `a phone standing still never asks for a recalibration`() {
        hold(10_000, yaw = 90f)
        assertFalse(monitor.moving)
        assertFalse(monitor.consumeReframed())
    }

    @Test
    fun `the wobble of a propped phone is not a camera move`() {
        hold(2_000, yaw = 90f)
        // Someone lands a burpee next to the box.
        hold(500, yaw = 93f)
        hold(2_000, yaw = 90f)
        assertFalse(monitor.moving)
        assertFalse(monitor.consumeReframed())
    }

    @Test
    fun `a knock is noticed straight away and reported once it settles`() {
        hold(2_000, yaw = 90f)
        hold(200, yaw = 115f)
        assertTrue("a 25 degree knock should register", monitor.moving)
        // Still mid-move, so nothing is recalibrated against a framing that is still changing.
        assertFalse(monitor.consumeReframed())

        hold(2_000, yaw = 115f)
        assertFalse(monitor.moving)
        assertTrue(monitor.consumeReframed())
    }

    @Test
    fun `one bump recalibrates once`() {
        hold(2_000, yaw = 90f)
        hold(200, yaw = 115f)
        hold(2_000, yaw = 115f)
        assertTrue(monitor.consumeReframed())
        assertFalse("a second read must not recalibrate again", monitor.consumeReframed())
        hold(5_000, yaw = 115f)
        assertFalse(monitor.consumeReframed())
    }

    @Test
    fun `being carried does not settle until it is put down`() {
        hold(2_000, yaw = 90f)
        // Swept through a wide arc a few degrees at a time; each step is under the threshold on
        // its own but the anchor follows, so what is measured is whether it has stopped.
        var yaw = 90f
        repeat(20) {
            yaw += 10f
            hold(200, yaw = yaw)
        }
        assertTrue(monitor.moving)
        assertFalse(monitor.consumeReframed())
        hold(2_000, yaw = yaw)
        assertTrue(monitor.consumeReframed())
    }

    @Test
    fun `pitch is watched as well as yaw`() {
        hold(2_000, yaw = 90f, pitch = 10f)
        hold(200, yaw = 90f, pitch = 30f)
        assertTrue(monitor.moving)
    }

    @Test
    fun `the compass wrapping past north is not a twenty degree turn`() {
        hold(2_000, yaw = 359f)
        hold(2_000, yaw = 2f)
        assertFalse("359 and 2 are three degrees apart", monitor.moving)
    }
}
