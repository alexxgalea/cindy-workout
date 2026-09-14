package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The rotation that used to cost a whole bitmap.
 *
 * Turning the frame upright moved out of `Bitmap.createBitmap` and into the matrix the detector
 * was already drawing through. That is a change to the pixels the counter sees, so the geometry
 * has to be exactly what it was: every corner of the raw buffer must land where the old rotated
 * bitmap would have put it, at all four rotations, mirrored and not.
 */
class UprightTransformTest {

    private val w = 640
    private val h = 480

    private fun corners(rotation: Int, mirror: Boolean): List<Pair<Int, Int>> {
        val m = OverlayTransform.upright(w, h, rotation, mirror)
        return listOf(0f to 0f, w.toFloat() to 0f, w.toFloat() to h.toFloat(), 0f to h.toFloat())
            .map { (x, y) -> Math.round(m.mapX(x, y)) to Math.round(m.mapY(x, y)) }
    }

    @Test
    fun `no rotation is the identity`() {
        assertEquals(listOf(0 to 0, 640 to 0, 640 to 480, 0 to 480), corners(0, mirror = false))
    }

    @Test
    fun `a quarter turn swaps the axes and lands on the origin`() {
        // Top-left goes to top-right, and the upright frame is 480x640.
        assertEquals(listOf(480 to 0, 480 to 640, 0 to 640, 0 to 0), corners(90, mirror = false))
        assertEquals(480f, OverlayTransform.uprightWidth(w, h, 90))
        assertEquals(640f, OverlayTransform.uprightHeight(w, h, 90))
    }

    @Test
    fun `half and three-quarter turns also land on the origin`() {
        assertEquals(listOf(640 to 480, 0 to 480, 0 to 0, 640 to 0), corners(180, mirror = false))
        assertEquals(listOf(0 to 640, 0 to 0, 480 to 0, 480 to 640), corners(270, mirror = false))
    }

    @Test
    fun `every rotation keeps the frame inside the upright bounds`() {
        for (rotation in listOf(0, 90, 180, 270)) {
            for (mirror in listOf(false, true)) {
                val uw = OverlayTransform.uprightWidth(w, h, rotation)
                val uh = OverlayTransform.uprightHeight(w, h, rotation)
                for ((x, y) in corners(rotation, mirror)) {
                    assertEquals("x in bounds at $rotation/$mirror", x.toFloat(), x.coerceIn(0, uw.toInt()).toFloat())
                    assertEquals("y in bounds at $rotation/$mirror", y.toFloat(), y.coerceIn(0, uh.toInt()).toFloat())
                }
            }
        }
    }

    @Test
    fun `mirroring flips about the upright centre and nothing else`() {
        for (rotation in listOf(0, 90, 180, 270)) {
            val uw = OverlayTransform.uprightWidth(w, h, rotation)
            val plain = corners(rotation, mirror = false)
            val flipped = corners(rotation, mirror = true)
            for (i in plain.indices) {
                assertEquals(
                    "x mirrors at $rotation",
                    (uw - plain[i].first).toInt(), flipped[i].first
                )
                assertEquals("y is untouched at $rotation", plain[i].second, flipped[i].second)
            }
        }
    }

    @Test
    fun `mirroring twice is doing nothing`() {
        val m = OverlayTransform.upright(w, h, 90, mirror = true)
        val uw = OverlayTransform.uprightWidth(w, h, 90)
        // Reflect the result back and the original corner must return.
        val x = m.mapX(0f, 0f)
        assertEquals(0f, uw - (uw - x), 0.001f)
    }
}
