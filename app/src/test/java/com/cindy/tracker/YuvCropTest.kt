package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Reading the model's input straight out of the camera's planes.
 *
 * This is the one change in the latency work that alters the numbers the counter sees, so the
 * properties that matter are pinned here: grey stays grey, colour converts by the standard
 * formula, off-frame reads letterbox to black exactly as the `Canvas` path did, and the crop
 * lands on the source pixel the forward transform says it should.
 */
class YuvCropTest {

    private val w = 64
    private val h = 48

    /** A frame where every pixel carries the same Y, U and V. */
    private fun flat(yVal: Int, uVal: Int = 128, vVal: Int = 128): YuvFrame {
        val f = YuvFrame()
        val y = ByteArray(w * h) { yVal.toByte() }
        val u = ByteArray((w / 2) * (h / 2)) { uVal.toByte() }
        val v = ByteArray((w / 2) * (h / 2)) { vVal.toByte() }
        f.set(w, h, y, w, 1, u, v, w / 2, 1)
        return f
    }

    /** Luma rising with x, so a sample's source column can be read back off its brightness. */
    private fun ramp(): YuvFrame {
        val f = YuvFrame()
        val y = ByteArray(w * h)
        for (row in 0 until h) for (col in 0 until w) y[row * w + col] = (col * 4).toByte()
        val u = ByteArray((w / 2) * (h / 2)) { 128.toByte() }
        val v = ByteArray((w / 2) * (h / 2)) { 128.toByte() }
        f.set(w, h, y, w, 1, u, v, w / 2, 1)
        return f
    }

    private fun sample(f: YuvFrame, map: Affine, size: Int): IntArray {
        val out = IntArray(size * size)
        YuvCrop.sample(f, map, out, size)
        return out
    }

    private fun r(p: Int) = (p shr 16) and 0xFF
    private fun g(p: Int) = (p shr 8) and 0xFF
    private fun b(p: Int) = p and 0xFF

    @Test
    fun `neutral chroma is grey, and luma passes straight through`() {
        val out = sample(flat(128), Affine.IDENTITY, 16)
        for (p in out) {
            assertEquals(128, r(p)); assertEquals(128, g(p)); assertEquals(128, b(p))
        }
    }

    @Test
    fun `black and white survive the conversion without wrapping`() {
        for ((luma, expected) in listOf(0 to 0, 255 to 255)) {
            val out = sample(flat(luma), Affine.IDENTITY, 8)
            assertEquals(expected, r(out[0]))
            assertEquals(expected, g(out[0]))
            assertEquals(expected, b(out[0]))
        }
    }

    @Test
    fun `chroma moves the channels the way BT601 says`() {
        // V above neutral is the red-difference channel: red up, green down, blue unmoved.
        val out = sample(flat(128, uVal = 128, vVal = 200), Affine.IDENTITY, 8)[0]
        assertTrue("red should rise, was ${r(out)}", r(out) > 200)
        assertTrue("green should fall, was ${g(out)}", g(out) < 100)
        assertEquals("blue is untouched by V", 128, b(out))

        // U above neutral is the blue-difference channel.
        val out2 = sample(flat(128, uVal = 200, vVal = 128), Affine.IDENTITY, 8)[0]
        assertTrue("blue should rise, was ${b(out2)}", b(out2) > 240)
        assertEquals("red is untouched by U", 128, r(out2))
    }

    @Test
    fun `off-frame samples letterbox to black, as the canvas did`() {
        // Shift the source far to the right: the whole square reads outside the frame.
        val out = sample(flat(200), Affine.translate(1000f, 1000f), 8)
        for (p in out) assertEquals(0, p)
    }

    @Test
    fun `a half-outside crop is black on exactly the outside half`() {
        val size = 16
        // Source x runs -8..8 across the square, so the left half is off-frame.
        val map = Affine.translate(-(size / 2).toFloat(), 0f)
        val out = sample(flat(180), map, size)
        for (row in 0 until size) {
            for (col in 0 until size) {
                val p = out[row * size + col]
                if (col < size / 2) assertEquals("($col,$row) should be letterbox", 0, p)
                else assertTrue("($col,$row) should carry picture", r(p) > 0)
            }
        }
    }

    @Test
    fun `the sample lands on the source pixel the map names`() {
        val f = ramp()
        // Point each output column at source column 2*ox, so brightness should be 8*ox.
        val out = sample(f, Affine.scale(2f, 1f), 16)
        for (ox in 0 until 16) {
            assertEquals("column $ox", (ox * 8).coerceAtMost(255).toDouble(), r(out[ox]).toDouble(), 1.0)
        }
    }

    @Test
    fun `luma is interpolated rather than snapped`() {
        val f = ramp()
        // Half-pixel offset must land between two ramp steps, not on one of them.
        val out = sample(f, Affine.translate(0.5f, 0f), 8)
        assertEquals("halfway between 0 and 4", 2, r(out[0]))
    }

    @Test
    fun `semi-planar chroma strides are honoured`() {
        // NV21-style: U and V interleaved in one plane, pixelStride 2.
        val f = YuvFrame()
        val y = ByteArray(w * h) { 128.toByte() }
        val inter = ByteArray(w * h / 2)
        for (i in inter.indices step 2) { inter[i] = 200.toByte(); inter[i + 1] = 128.toByte() }
        f.set(w, h, y, w, 1, inter, inter, w, 2)
        val out = sample(f, Affine.IDENTITY, 8)[0]
        // Reading U=200 through a stride of 2 must lift blue, not smear it into noise.
        assertTrue("blue should rise, was ${b(out)}", b(out) > 240)
    }

    @Test
    fun `the tally matches a separate pass over the pixels it wrote`() {
        // The low-light gain used to be computed by walking the finished square a second time.
        // Sampling now counts as it writes, and the two must agree exactly or the brightness
        // correction drifts from the Python engine that mirrors it.
        val cases = listOf(
            flat(128) to Affine.IDENTITY,                       // every pixel lit
            flat(200) to Affine.translate(-8f, 0f),             // half letterboxed to black
            ramp() to Affine.scale(2f, 1f),                     // a column of true black at x=0
            flat(0) to Affine.IDENTITY                          // nothing lit at all
        )
        for ((i, case) in cases.withIndex()) {
            val (frame, map) = case
            val size = 16
            val out = IntArray(size * size)
            val tally = LongArray(4)
            YuvCrop.sample(frame, map, out, size, tally)

            var red = 0L; var green = 0L; var blue = 0L; var lit = 0L
            for (p in out) {
                val r = (p shr 16) and 0xFF
                val g = (p shr 8) and 0xFF
                val b = p and 0xFF
                if (r or g or b == 0) continue
                red += r; green += g; blue += b; lit++
            }
            assertEquals("case $i red", red, tally[0])
            assertEquals("case $i green", green, tally[1])
            assertEquals("case $i blue", blue, tally[2])
            assertEquals("case $i lit", lit, tally[3])
        }
    }

    @Test
    fun `sampling without a tally still writes the same pixels`() {
        val f = ramp()
        val a = IntArray(256); val b = IntArray(256)
        YuvCrop.sample(f, Affine.IDENTITY, a, 16)
        YuvCrop.sample(f, Affine.IDENTITY, b, 16, LongArray(4))
        assertTrue("the optional accumulator must not change the output", a.contentEquals(b))
    }

    @Test
    fun `inverting a crop-and-rotate returns the original point`() {
        val upright = OverlayTransform.upright(640, 480, 90, mirror = true)
        val forward = upright
            .then(Affine.scale(0.4f, 0.4f))
            .then(Affine.translate(-12f, -30f))
        val back = forward.invert()!!
        for ((x, y) in listOf(0f to 0f, 640f to 0f, 320f to 240f, 0f to 480f)) {
            assertEquals(x, back.mapX(forward.mapX(x, y), forward.mapY(x, y)), 0.01f)
            assertEquals(y, back.mapY(forward.mapX(x, y), forward.mapY(x, y)), 0.01f)
        }
    }
}
