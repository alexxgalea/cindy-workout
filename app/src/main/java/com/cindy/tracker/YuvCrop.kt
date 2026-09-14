package com.cindy.tracker

import kotlin.math.max
import kotlin.math.min

/**
 * One camera frame's three planes, as the analyser received them.
 *
 * Plain arrays and strides rather than an `ImageProxy`, so the sampling arithmetic below can be
 * checked on the JVM instead of only on a phone — the same reason [Affine] exists.
 */
class YuvFrame {
    var y: ByteArray = ByteArray(0); private set
    var u: ByteArray = ByteArray(0); private set
    var v: ByteArray = ByteArray(0); private set
    var width = 0; private set
    var height = 0; private set
    var yRowStride = 0; private set
    var yPixelStride = 1; private set
    var uvRowStride = 0; private set
    var uvPixelStride = 1; private set

    /** Reuses the backing arrays when the geometry has not changed, which it never does mid-run. */
    fun set(
        width: Int, height: Int,
        y: ByteArray, yRowStride: Int, yPixelStride: Int,
        u: ByteArray, v: ByteArray, uvRowStride: Int, uvPixelStride: Int
    ) {
        this.width = width; this.height = height
        this.y = y; this.yRowStride = yRowStride; this.yPixelStride = yPixelStride
        this.u = u; this.v = v; this.uvRowStride = uvRowStride; this.uvPixelStride = uvPixelStride
    }

    fun sized(plane: ByteArray, bytes: Int): ByteArray =
        if (plane.size == bytes) plane else ByteArray(bytes)
}

/**
 * Fills the model's input square by reading the camera's YUV planes directly.
 *
 * ### What this replaces
 *
 * The frame used to reach the model through five steps: CameraX converted every one of the
 * 307,200 pixels to RGBA, that became an ARGB bitmap, a `Canvas` drew the tracked crop out of it
 * into a second bitmap, `getPixels` copied that into an int array, and a loop copied the array
 * into the input buffer. All of it to deliver one 256x256 crop — about 8% of the frame's pixels,
 * converted the long way round.
 *
 * This walks the *destination* instead. For each of the 65,536 output pixels it asks which camera
 * pixel feeds it, reads that one, and converts it. The whole-frame conversion never happens,
 * because the pixels outside the crop are never touched.
 *
 * ### Why luma is interpolated and chroma is not
 *
 * The crop is usually a downscale, so point-sampling luma would alias — and luma is where the
 * edges the model reads actually live. Chroma is already stored at half resolution and carries
 * almost nothing MoveNet uses, so it is point-sampled. That is the standard asymmetry, and it
 * buys back most of the cost of interpolating at all.
 *
 * Out-of-bounds reads produce black, which is the same letterbox the `Canvas` path left behind
 * when the tracked crop ran off the edge of the frame.
 */
object YuvCrop {

    /**
     * Writes `size * size` packed 0xRRGGBB ints into [out].
     *
     * [modelToSource] maps a model-square coordinate to a coordinate in the camera's raw buffer —
     * the inverse of the crop-and-rotate the forward path applies.
     */
    fun sample(
        frame: YuvFrame,
        modelToSource: Affine,
        out: IntArray,
        size: Int,
        /**
         * Optional [red, green, blue, lit] accumulator, summed over non-black pixels as they are
         * written. Filling it here saves a second full pass for the low-light gain, which
         * otherwise walks all 65,536 pixels again to work out the same totals.
         */
        tally: LongArray? = null
    ) {
        val w = frame.width
        val h = frame.height
        val yp = frame.y
        val up = frame.u
        val vp = frame.v
        var i = 0
        for (oy in 0 until size) {
            // Affine, so stepping one pixel across is an add rather than a fresh evaluation.
            var sx = modelToSource.mapX(0f, oy.toFloat())
            var sy = modelToSource.mapY(0f, oy.toFloat())
            for (ox in 0 until size) {
                val px = sx
                val py = sy
                sx += modelToSource.a
                sy += modelToSource.b
                if (px < 0f || py < 0f || px >= w || py >= h) {
                    out[i++] = 0
                    continue
                }
                val x0 = px.toInt()
                val y0 = py.toInt()
                val x1 = min(x0 + 1, w - 1)
                val y1 = min(y0 + 1, h - 1)
                val ax = px - x0
                val ay = py - y0

                val r0 = y0 * frame.yRowStride
                val r1 = y1 * frame.yRowStride
                val c0 = x0 * frame.yPixelStride
                val c1 = x1 * frame.yPixelStride
                val y00 = (yp[r0 + c0].toInt() and 0xFF).toFloat()
                val y01 = (yp[r0 + c1].toInt() and 0xFF).toFloat()
                val y10 = (yp[r1 + c0].toInt() and 0xFF).toFloat()
                val y11 = (yp[r1 + c1].toInt() and 0xFF).toFloat()
                val luma = (y00 + (y01 - y00) * ax) + ((y10 + (y11 - y10) * ax) - (y00 + (y01 - y00) * ax)) * ay

                val ci = (y0 shr 1) * frame.uvRowStride + (x0 shr 1) * frame.uvPixelStride
                val cb = (up[ci].toInt() and 0xFF) - 128
                val cr = (vp[ci].toInt() and 0xFF) - 128

                // Full-range BT.601, the conversion Android's own YUV helpers use.
                val r = clamp(luma + 1.402f * cr)
                val g = clamp(luma - 0.344136f * cb - 0.714136f * cr)
                val b = clamp(luma + 1.772f * cb)
                out[i++] = (r shl 16) or (g shl 8) or b
                // Pure black is letterbox or carries nothing; excluded for the same reason the
                // separate pass excludes it, so the two produce identical totals.
                if (tally != null && (r or g or b) != 0) {
                    tally[0] += r.toLong()
                    tally[1] += g.toLong()
                    tally[2] += b.toLong()
                    tally[3]++
                }
            }
        }
    }

    private fun clamp(v: Float): Int = max(0, min(255, (v + 0.5f).toInt()))
}
