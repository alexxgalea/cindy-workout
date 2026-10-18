package com.cindy.tracker

import kotlin.math.abs
import kotlin.math.atan2
import org.junit.Assert.assertEquals
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

    // The monitor is only as good as the angles it is fed. These build the rotation matrix
    // SensorManager would report for a phone propped up to film, and read the camera's
    // direction from it the way MainActivity does.

    /** Row-major 3x3 product. */
    private fun times(a: DoubleArray, b: DoubleArray) = DoubleArray(9) { i ->
        (0..2).sumOf { k -> a[i / 3 * 3 + k] * b[k * 3 + i % 3] }
    }

    /** Rotation by [degrees] about a world axis (East, North, Up), by Rodrigues' formula. */
    private fun turn(x: Double, y: Double, z: Double, degrees: Double): DoubleArray {
        val n = Math.sqrt(x * x + y * y + z * z)
        val ux = x / n
        val uy = y / n
        val uz = z / n
        val a = Math.toRadians(degrees)
        val s = Math.sin(a)
        val c = Math.cos(a)
        val t = 1 - c
        return doubleArrayOf(
            t * ux * ux + c, t * ux * uy - s * uz, t * ux * uz + s * uy,
            t * ux * uy + s * uz, t * uy * uy + c, t * uy * uz - s * ux,
            t * ux * uz - s * uy, t * uy * uz + s * ux, t * uz * uz + c
        )
    }

    /** A phone standing on its end facing north: top edge up, camera along the horizon. */
    private val upright = doubleArrayOf(1.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0)

    /** Leaning back against a box by [tiltBack] degrees, so the camera looks that far up. */
    private fun propped(tiltBack: Double) = times(turn(1.0, 0.0, 0.0, tiltBack), upright)

    private fun DoubleArray.matrix() = FloatArray(9) { this[it].toFloat() }

    private fun heading(m: DoubleArray) = CameraLook.heading(m.matrix())

    private fun elevation(m: DoubleArray) = CameraLook.elevation(m.matrix())

    /** What `SensorManager.getOrientation` reported before: the bearing of the top edge. */
    private fun azimuth(m: DoubleArray) = Math.toDegrees(atan2(m[1], m[4])).toFloat()

    private fun apart(a: Float, b: Float): Float {
        var d = (a - b) % 360f
        if (d > 180f) d -= 360f
        if (d < -180f) d += 360f
        return abs(d)
    }

    private fun feed(m: DoubleArray, ms: Long, stepMs: Long = 50L) {
        val until = clock + ms
        while (clock < until) {
            monitor.update(heading(m), elevation(m), clock)
            clock += stepMs
        }
    }

    private val tremor = listOf(
        Triple(1.0, 0.0, 0.0), Triple(0.0, 1.0, 0.0), Triple(0.0, 0.0, 1.0), Triple(1.0, 1.0, 0.0),
        Triple(1.0, 0.0, 1.0), Triple(0.0, 1.0, 1.0), Triple(1.0, 1.0, 1.0), Triple(1.0, -1.0, 0.0),
        Triple(1.0, 0.0, -1.0), Triple(0.0, 1.0, -1.0)
    )

    @Test
    fun `a tremor barely moves where the camera points though it sends the compass round`() {
        val at = propped(5.0)
        var compass = 0f
        for ((x, y, z) in tremor) {
            val shaken = times(turn(x, y, z, 1.5), at)
            assertTrue("heading moved ${apart(heading(shaken), heading(at))}",
                apart(heading(shaken), heading(at)) < 2f)
            assertTrue("elevation moved ${apart(elevation(shaken), elevation(at))}",
                apart(elevation(shaken), elevation(at)) < 2f)
            compass = maxOf(compass, apart(azimuth(shaken), azimuth(at)))
        }
        // The reading this replaces: the same one and a half degrees, through the top edge of a
        // phone that is nearly vertical, is well past the eight degrees that count as a move.
        assertTrue("azimuth moved only $compass", compass > 8f)
    }

    @Test
    fun `turning the phone is the same angle in the camera heading`() {
        val at = propped(5.0)
        val panned = times(turn(0.0, 0.0, 1.0, 12.0), at)
        assertEquals(12f, apart(heading(panned), heading(at)), 0.01f)
    }

    @Test
    fun `tilting the phone up is its elevation`() {
        val at = propped(5.0)
        val tipped = times(turn(1.0, 0.0, 0.0, 10.0), at)
        assertEquals(5f, elevation(at), 0.01f)
        assertEquals(15f, elevation(tipped), 0.01f)
    }

    @Test
    fun `the monitor stays quiet through a tremor and reports a real turn`() {
        val at = propped(5.0)
        feed(at, 2_000)
        repeat(20) { i ->
            val (x, y, z) = tremor[i % tremor.size]
            feed(times(turn(x, y, z, 1.5), at), 100)
        }
        feed(at, 2_000)
        assertFalse(monitor.moving)
        assertFalse(monitor.consumeReframed())

        feed(times(turn(0.0, 0.0, 1.0, 15.0), at), 3_000)
        assertTrue(monitor.consumeReframed())
    }
}
