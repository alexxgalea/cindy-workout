package com.cindy.tracker

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * The affine map from the upright analysis frame onto a recorded video buffer.
 *
 * Deliberately free of `android.graphics.Matrix`: this is the calculation that put the whole
 * overlay in a corner at a fraction of its size, and framework classes are unavailable in JVM
 * unit tests, so it could not be checked. In plain Kotlin it can be.
 *
 * Row-major affine, in the order `Matrix.setValues` expects:
 * ```
 * | a c tx |
 * | b d ty |
 * | 0 0  1 |
 * ```
 */
data class Affine(
    val a: Float, val b: Float,
    val c: Float, val d: Float,
    val tx: Float, val ty: Float
) {
    /** Applies this transform, then [next] — the same order as `Matrix.postConcat`. */
    fun then(next: Affine) = Affine(
        a = next.a * a + next.c * b,
        b = next.b * a + next.d * b,
        c = next.a * c + next.c * d,
        d = next.b * c + next.d * d,
        tx = next.a * tx + next.c * ty + next.tx,
        ty = next.b * tx + next.d * ty + next.ty
    )

    fun mapX(x: Float, y: Float) = a * x + c * y + tx
    fun mapY(x: Float, y: Float) = b * x + d * y + ty

    /** In the order `android.graphics.Matrix.setValues` wants. */
    fun values() = floatArrayOf(a, c, tx, b, d, ty, 0f, 0f, 1f)

    companion object {
        val IDENTITY = Affine(1f, 0f, 0f, 1f, 0f, 0f)

        fun scale(sx: Float, sy: Float) = Affine(sx, 0f, 0f, sy, 0f, 0f)

        fun translate(dx: Float, dy: Float) = Affine(1f, 0f, 0f, 1f, dx, dy)

        /** Clockwise in screen coordinates, matching `Matrix.postRotate`. */
        fun rotate(degrees: Float): Affine {
            val r = Math.toRadians(degrees.toDouble())
            // Snap the quarter turns so 90 does not arrive as 6.1e-17.
            val cos = clean(kotlin.math.cos(r).toFloat())
            val sin = clean(kotlin.math.sin(r).toFloat())
            return Affine(cos, sin, -sin, cos, 0f, 0f)
        }

        fun scaleAbout(sx: Float, sy: Float, px: Float, py: Float) =
            translate(-px, -py).then(scale(sx, sy)).then(translate(px, py))

        private fun clean(v: Float) =
            if (abs(v - v.roundToInt()) < 1e-6f) v.roundToInt().toFloat() else v
    }
}

object OverlayTransform {

    /**
     * Builds the map from an upright frame of [srcWidth] x [srcHeight] onto a video buffer of
     * [bufferWidth] x [bufferHeight] that must be turned [rotationDegrees] clockwise to display.
     *
     * The fit is FILL_CENTER, the same as the preview uses, so the recording is framed like the
     * screen and nothing is stretched. [mirror] flips horizontally, for when the keypoints were
     * mirrored for the selfie camera but the recorded buffer was not, or the other way about.
     */
    fun build(
        srcWidth: Int,
        srcHeight: Int,
        bufferWidth: Int,
        bufferHeight: Int,
        rotationDegrees: Int,
        mirror: Boolean
    ): Affine {
        if (srcWidth <= 0 || srcHeight <= 0 || bufferWidth <= 0 || bufferHeight <= 0) {
            return Affine.IDENTITY
        }
        val rotation = ((rotationDegrees % 360) + 360) % 360
        val quarterTurned = rotation % 180 != 0
        // At 90 and 270 the buffer is stored with its axes swapped relative to the display.
        val displayW = if (quarterTurned) bufferHeight.toFloat() else bufferWidth.toFloat()
        val displayH = if (quarterTurned) bufferWidth.toFloat() else bufferHeight.toFloat()

        val scale = max(displayW / srcWidth, displayH / srcHeight)
        var m = Affine.scale(scale, scale)
            .then(
                Affine.translate(
                    (displayW - srcWidth * scale) / 2f,
                    (displayH - srcHeight * scale) / 2f
                )
            )

        if (mirror) m = m.then(Affine.scaleAbout(-1f, 1f, displayW / 2f, displayH / 2f))

        // Out of display orientation and into the buffer's own.
        val turn = Affine.rotate(-rotation.toFloat())
        m = m.then(turn)

        // Rotating about the origin walks the rect off it; bring it back.
        var left = Float.MAX_VALUE
        var top = Float.MAX_VALUE
        for ((x, y) in listOf(0f to 0f, displayW to 0f, 0f to displayH, displayW to displayH)) {
            left = min(left, turn.mapX(x, y))
            top = min(top, turn.mapY(x, y))
        }
        return m.then(Affine.translate(-left, -top))
    }
}
