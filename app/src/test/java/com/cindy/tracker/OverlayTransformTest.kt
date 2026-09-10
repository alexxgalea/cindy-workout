package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.hypot

/**
 * The map from the analysis frame onto the recorded buffer.
 *
 * The first version of this put the whole overlay in the lower-left corner at a fraction of its
 * size, so the properties that would have caught it are asserted directly: the frame's corners
 * must land on the buffer's corners, the centre on the centre, and nothing may be stretched.
 */
class OverlayTransformTest {

    private val srcW = 480
    private val srcH = 640

    private fun corners(a: Affine, w: Int, h: Int): List<Pair<Float, Float>> =
        listOf(0f to 0f, w.toFloat() to 0f, w.toFloat() to h.toFloat(), 0f to h.toFloat())
            .map { (x, y) -> a.mapX(x, y) to a.mapY(x, y) }

    private fun assertCoversBuffer(a: Affine, bufW: Int, bufH: Int) {
        val mapped = corners(a, srcW, srcH)
        val xs = mapped.map { it.first }
        val ys = mapped.map { it.second }
        assertEquals("left edge", 0f, xs.min(), 1f)
        assertEquals("top edge", 0f, ys.min(), 1f)
        assertEquals("right edge", bufW.toFloat(), xs.max(), 1f)
        assertEquals("bottom edge", bufH.toFloat(), ys.max(), 1f)
    }

    /** Negative where the transform reflects — which is what flips text. */
    private fun determinant(a: Affine) = a.a * a.d - a.b * a.c

    private fun assertCentred(a: Affine, bufW: Int, bufH: Int) {
        assertEquals(bufW / 2f, a.mapX(srcW / 2f, srcH / 2f), 1f)
        assertEquals(bufH / 2f, a.mapY(srcW / 2f, srcH / 2f), 1f)
    }

    /** A square in the source must stay square: equal side lengths, right angles. */
    private fun assertNotStretched(a: Affine) {
        val side = 100f
        val o = a.mapX(0f, 0f) to a.mapY(0f, 0f)
        val x = a.mapX(side, 0f) to a.mapY(side, 0f)
        val y = a.mapX(0f, side) to a.mapY(0f, side)
        val lenX = hypot(x.first - o.first, x.second - o.second)
        val lenY = hypot(y.first - o.first, y.second - o.second)
        assertEquals("uniform scale", lenX, lenY, 0.01f)
        val dot = (x.first - o.first) * (y.first - o.first) + (x.second - o.second) * (y.second - o.second)
        assertTrue("axes stay perpendicular, got dot=$dot", abs(dot) < 0.01f)
    }

    @Test
    fun `identity when the buffer matches the frame`() {
        val a = OverlayTransform.build(srcW, srcH, srcW, srcH, 0, false)
        assertEquals(0f, a.mapX(0f, 0f), 0.01f)
        assertEquals(0f, a.mapY(0f, 0f), 0.01f)
        assertEquals(srcW.toFloat(), a.mapX(srcW.toFloat(), 0f), 0.01f)
        assertEquals(srcH.toFloat(), a.mapY(0f, srcH.toFloat()), 0.01f)
    }

    @Test
    fun `an unrotated 720p buffer is filled corner to corner`() {
        val a = OverlayTransform.build(srcW, srcH, 720, 960, 0, false)
        assertCoversBuffer(a, 720, 960)
        assertCentred(a, 720, 960)
        assertNotStretched(a)
    }

    @Test
    fun `a quarter-turned buffer is filled corner to corner`() {
        // The usual portrait case: the buffer is landscape and rotated 90 for display.
        val a = OverlayTransform.build(srcW, srcH, 1280, 960, 90, false)
        assertCoversBuffer(a, 1280, 960)
        assertCentred(a, 1280, 960)
        assertNotStretched(a)
    }

    @Test
    fun `270 degrees is filled corner to corner too`() {
        val a = OverlayTransform.build(srcW, srcH, 1280, 960, 270, false)
        assertCoversBuffer(a, 1280, 960)
        assertCentred(a, 1280, 960)
        assertNotStretched(a)
    }

    @Test
    fun `180 degrees is filled corner to corner too`() {
        val a = OverlayTransform.build(srcW, srcH, 720, 960, 180, false)
        assertCoversBuffer(a, 720, 960)
        assertCentred(a, 720, 960)
        assertNotStretched(a)
    }

    @Test
    fun `a quarter turn moves the frame origin off the buffer origin`() {
        // The buffer is stored a quarter turn from how it is shown, so the frame's top-left
        // belongs at the buffer's bottom-left. Turning the buffer 90 clockwise to display it
        // brings that corner back to the top-left, which is the whole point.
        val a = OverlayTransform.build(srcW, srcH, 1280, 960, 90, false)
        assertEquals(0f, a.mapX(0f, 0f), 1f)
        assertEquals(960f, a.mapY(0f, 0f), 1f)
    }

    @Test
    fun `a matching aspect ratio keeps every corner on the buffer`() {
        // 3:4 frame into a 3:4 buffer at every rotation: an exact fit, nothing cropped.
        for (rotation in listOf(0, 90, 180, 270)) {
            val quarterTurned = rotation % 180 != 0
            val bufW = if (quarterTurned) 960 else 720
            val bufH = if (quarterTurned) 720 else 960
            val a = OverlayTransform.build(srcW, srcH, bufW, bufH, rotation, false)
            for ((x, y) in corners(a, srcW, srcH)) {
                assertTrue("x=$x outside 0..$bufW at $rotation", x >= -1f && x <= bufW + 1f)
                assertTrue("y=$y outside 0..$bufH at $rotation", y >= -1f && y <= bufH + 1f)
            }
            assertCoversBuffer(a, bufW, bufH)
            assertNotStretched(a)
        }
    }

    @Test
    fun `mirroring swaps left for right and leaves top alone`() {
        val plain = OverlayTransform.build(srcW, srcH, 720, 960, 0, false)
        val mirrored = OverlayTransform.build(srcW, srcH, 720, 960, 0, true)
        assertEquals(plain.mapX(srcW.toFloat(), 0f), mirrored.mapX(0f, 0f), 1f)
        assertEquals(plain.mapY(0f, 0f), mirrored.mapY(0f, 0f), 1f)
        assertCoversBuffer(mirrored, 720, 960)
    }

    @Test
    fun `only a mirrored transform reverses the picture`() {
        // The HUD rides the unmirrored one: a reflected canvas writes every letter backwards,
        // which is what put a reversed clock and rep count in the recording.
        for (rotation in listOf(0, 90, 180, 270)) {
            val plain = OverlayTransform.build(srcW, srcH, 720, 960, rotation, false)
            assertTrue("reflected at $rotation", determinant(plain) > 0f)
            val mirrored = OverlayTransform.build(srcW, srcH, 720, 960, rotation, true)
            assertTrue("not reflected at $rotation", determinant(mirrored) < 0f)
        }
    }

    @Test
    fun `a taller buffer crops the sides rather than stretching`() {
        // A 9:16 buffer against a 3:4 frame. Filling the height overflows the width, so the
        // sides are cropped and the picture keeps its proportions.
        val a = OverlayTransform.build(srcW, srcH, 1080, 1920, 0, false)
        assertNotStretched(a)
        assertCentred(a, 1080, 1920)
        val xs = corners(a, srcW, srcH).map { it.first }
        val ys = corners(a, srcW, srcH).map { it.second }
        assertTrue("should overflow horizontally, got ${xs.min()}..${xs.max()}", xs.min() < -1f)
        assertEquals("and fit the height exactly", 0f, ys.min(), 1f)
        assertEquals(1920f, ys.max(), 1f)
    }

    @Test
    fun `degenerate sizes fall back to identity instead of exploding`() {
        assertEquals(Affine.IDENTITY, OverlayTransform.build(0, 640, 720, 960, 0, false))
        assertEquals(Affine.IDENTITY, OverlayTransform.build(480, 640, 0, 0, 0, false))
    }

    @Test
    fun `negative and over-wound rotations normalise`() {
        val plain = OverlayTransform.build(srcW, srcH, 1280, 960, 90, false)
        assertEquals(plain, OverlayTransform.build(srcW, srcH, 1280, 960, 450, false))
        assertEquals(plain, OverlayTransform.build(srcW, srcH, 1280, 960, -270, false))
    }


    // --- the safe area -------------------------------------------------------------------
    //
    // The transform was right and the HUD was still off the picture, because FILL_CENTER
    // crops and the HUD was laid out against the frame's own edges. These pin the region
    // that survives.

    /** Maps a source rect through the transform and asserts it lands inside the buffer. */
    private fun assertInsideBuffer(a: Affine, r: SourceRect, bufW: Int, bufH: Int) {
        val pts = listOf(
            r.left to r.top, r.right to r.top,
            r.right to r.bottom, r.left to r.bottom
        ).map { (x, y) -> a.mapX(x, y) to a.mapY(x, y) }
        for ((x, y) in pts) {
            assertTrue("x=$x outside 0..$bufW", x >= -1f && x <= bufW + 1f)
            assertTrue("y=$y outside 0..$bufH", y >= -1f && y <= bufH + 1f)
        }
    }

    @Test
    fun `a 9 by 16 recording keeps only the middle of a 3 by 4 frame`() {
        // The shipping case: a 480x640 analysis frame into 1280x720 shown portrait. Filling
        // the height needs a scale of 2, which makes the frame 960 wide against a 720 buffer,
        // so 120 buffer px go from each side -- 60 of the frame's own 480, or 12.5%.
        val r = OverlayTransform.visibleSource(srcW, srcH, 1280, 720, 90)
        assertEquals("left", 60f, r.left, 0.5f)
        assertEquals("right", 420f, r.right, 0.5f)
        assertEquals("nothing off the top", 0f, r.top, 0.5f)
        assertEquals("nothing off the bottom", 640f, r.bottom, 0.5f)
        assertEquals(360f, r.width, 0.5f)
        assertEquals(640f, r.height, 0.5f)
    }

    @Test
    fun `the safe area is where the HUD used to be laid out, and was not`() {
        // The regression this exists for. The HUD anchored its panels a pad in from the frame,
        // pad being 1.8% of the height; against a frame 480 wide that is x=11.5, which is
        // inside the 60px the crop takes. Against the safe area it is inside the picture.
        val r = OverlayTransform.visibleSource(srcW, srcH, 1280, 720, 90)
        val pad = r.height * 0.018f
        assertTrue("the old anchor should have been cropped", pad < r.left)
        val a = OverlayTransform.build(srcW, srcH, 1280, 720, 90, false)
        assertInsideBuffer(a, SourceRect(r.left + pad, r.top + pad, r.right - pad, r.bottom - pad), 1280, 720)
    }

    @Test
    fun `every corner of the safe area lands on the buffer at every rotation`() {
        for (rotation in listOf(0, 90, 180, 270)) {
            val quarterTurned = rotation % 180 != 0
            val bufW = if (quarterTurned) 1280 else 720
            val bufH = if (quarterTurned) 720 else 1280
            val r = OverlayTransform.visibleSource(srcW, srcH, bufW, bufH, rotation)
            for (mirror in listOf(false, true)) {
                val a = OverlayTransform.build(srcW, srcH, bufW, bufH, rotation, mirror)
                assertInsideBuffer(a, r, bufW, bufH)
            }
        }
    }

    @Test
    fun `a matching aspect ratio crops nothing`() {
        // 3:4 into 3:4: the safe area is the whole frame, so the HUD keeps its old placement.
        val r = OverlayTransform.visibleSource(srcW, srcH, 720, 960, 0)
        assertEquals(0f, r.left, 0.5f)
        assertEquals(0f, r.top, 0.5f)
        assertEquals(srcW.toFloat(), r.right, 0.5f)
        assertEquals(srcH.toFloat(), r.bottom, 0.5f)
    }

    @Test
    fun `a wider buffer crops the top and bottom instead`() {
        // The other way about -- a landscape recording of the portrait frame loses height,
        // not width, and the HUD has to follow that too.
        val r = OverlayTransform.visibleSource(srcW, srcH, 1280, 720, 0)
        assertEquals("full width", 0f, r.left, 0.5f)
        assertEquals("full width", srcW.toFloat(), r.right, 0.5f)
        assertTrue("height should be cropped, got ${r.height}", r.height < srcH - 1f)
        assertEquals("and centred", r.top, srcH - r.bottom, 0.5f)
        assertInsideBuffer(OverlayTransform.build(srcW, srcH, 1280, 720, 0, false), r, 1280, 720)
    }

    @Test
    fun `the safe area is always centred and never bigger than the frame`() {
        for (bufW in listOf(320, 720, 1080, 1920)) {
            for (bufH in listOf(240, 720, 1280, 1920)) {
                val r = OverlayTransform.visibleSource(srcW, srcH, bufW, bufH, 0)
                assertTrue("wider than the frame at ${bufW}x$bufH", r.width <= srcW + 0.5f)
                assertTrue("taller than the frame at ${bufW}x$bufH", r.height <= srcH + 0.5f)
                assertTrue("empty at ${bufW}x$bufH", r.width > 0f && r.height > 0f)
                assertEquals("off centre at ${bufW}x$bufH", r.left, srcW - r.right, 0.5f)
                assertEquals("off centre at ${bufW}x$bufH", r.top, srcH - r.bottom, 0.5f)
            }
        }
    }

    @Test
    fun `degenerate sizes give back the whole frame rather than an empty rect`() {
        val r = OverlayTransform.visibleSource(srcW, srcH, 0, 0, 0)
        assertEquals(0f, r.left, 0.01f)
        assertEquals(srcW.toFloat(), r.right, 0.01f)
        assertEquals(srcH.toFloat(), r.bottom, 0.01f)
    }

    @Test
    fun `the matrix value order matches what Matrix setValues expects`() {
        val a = Affine(a = 2f, b = 3f, c = 4f, d = 5f, tx = 6f, ty = 7f)
        // Matrix order: scaleX, skewX, transX, skewY, scaleY, transY, 0, 0, 1
        assertEquals(listOf(2f, 4f, 6f, 3f, 5f, 7f, 0f, 0f, 1f), a.values().toList())
    }

    @Test
    fun `then composes in the same order as Matrix postConcat`() {
        val scaleThenShift = Affine.scale(2f, 2f).then(Affine.translate(10f, 0f))
        assertEquals(30f, scaleThenShift.mapX(10f, 0f), 0.01f)
        val shiftThenScale = Affine.translate(10f, 0f).then(Affine.scale(2f, 2f))
        assertEquals(40f, shiftThenScale.mapX(10f, 0f), 0.01f)
    }
}
