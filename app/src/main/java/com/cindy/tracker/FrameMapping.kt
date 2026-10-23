package com.cindy.tracker

import android.graphics.Matrix
import androidx.camera.effects.Frame

/**
 * Maps the upright analysis frame onto an effect's buffer, which is where the film and the
 * synced picture both draw.
 *
 * It needs only what every effect frame reports for itself, its size and how far it has to turn
 * to be shown upright, plus the analysis frame's own dimensions. The fit is the FILL_CENTER the
 * preview uses, so nothing is stretched. [mirror] flips the result for keypoints that were
 * mirrored when the buffer was not, or the other way round.
 */
fun analysisToBuffer(frame: Frame, srcWidth: Int, srcHeight: Int, mirror: Boolean): Matrix {
    val affine = OverlayTransform.build(
        srcWidth = srcWidth,
        srcHeight = srcHeight,
        bufferWidth = frame.size.width,
        bufferHeight = frame.size.height,
        rotationDegrees = frame.rotationDegrees,
        mirror = mirror
    )
    return Matrix().apply { setValues(affine.values()) }
}
