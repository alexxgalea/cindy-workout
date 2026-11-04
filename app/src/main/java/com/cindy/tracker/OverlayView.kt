package com.cindy.tracker

import android.content.Context
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.util.AttributeSet
import android.view.View
import androidx.core.content.ContextCompat
import kotlin.math.max

/**
 * Draws the detected skeleton, and the pull-up bar, on top of the live picture.
 *
 * The synced picture draws both into its own frames and this view stays out of the way (see
 * [live]). This view is what draws them when the picture is the live one: the debug readout's
 * live-picture mode, and a phone whose camera could not bind the synced picture.
 *
 * Keypoints arrive in analysis-frame pixels, which is a different resolution to the view, so
 * the same FILL_CENTER mapping PreviewView applies is recomputed here — otherwise the skeleton
 * drifts away from the body on any device whose preview and analysis aspect ratios differ.
 *
 * ### This view is fed from the analysis thread, on purpose
 *
 * Poses are handed straight to [submit] by the analysis thread rather than routed through a
 * `post` to the main thread. A posted runnable is a queue, and a queue with no back-pressure
 * turns a fixed lag into a growing one the moment the main thread falls behind: every pose ever
 * computed eventually gets drawn, each one older than the last. Here the newest pose simply
 * replaces the one before it, so a busy main thread costs frames rather than freshness — which
 * is the same bargain `STRATEGY_KEEP_ONLY_LATEST` already makes upstream.
 */
class OverlayView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0
) : View(context, attrs, defStyle) {

    /** One analysed frame, immutable so the analysis thread can publish it without a lock. */
    private class PoseFrame(
        val keypoints: Array<Keypoint>,
        val srcW: Int,
        val srcH: Int,
        val guide: WorkoutEngine.BarGuide?
    )

    @Volatile
    private var newest: PoseFrame? = null

    /**
     * Whether this view draws the skeleton and the gate. Off while the synced picture is on:
     * that draws both into the picture itself, and a second copy here would be the lagging one.
     */
    @Volatile
    var live: Boolean = true
        set(value) {
            field = value
            postInvalidateOnAnimation()
        }

    /** Draw rate, for the latency readout. Counted here because this is what the athlete sees. */
    val drawRate = RateMeter()

    // The same painter the synced picture and the film use, so the skeleton and the bar look one
    // way wherever they are drawn.
    private val painter = SkeletonPainter(
        boneColor = ContextCompat.getColor(context, R.color.skeleton),
        // Drawn on a canvas scaled up to the view, so these lengths grow with it: about the
        // 18 and 14 px the line has always had on screen.
        resetLinePathEffect = DashPathEffect(floatArrayOf(8f, 6f), 0f)
    )

    /**
     * Publishes one analysed frame. [guide] is the pull-up gate, or null for the movements and
     * the moments that have no bar to show. Called from the analysis thread.
     */
    fun submit(
        keypoints: Array<Keypoint>?,
        sourceWidth: Int,
        sourceHeight: Int,
        guide: WorkoutEngine.BarGuide? = null
    ) {
        newest = keypoints?.let { PoseFrame(it, sourceWidth, sourceHeight, guide) }
        postInvalidateOnAnimation()
    }

    fun clear() = submit(null, 0, 0, null)

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (!live) return
        val pose = newest ?: return
        if (pose.srcW == 0 || pose.srcH == 0) return

        drawRate.mark()

        // FILL_CENTER: scale up until both axes are covered, then centre the overflow.
        val scale = max(width.toFloat() / pose.srcW, height.toFloat() / pose.srcH)
        val dx = (width - pose.srcW * scale) / 2f
        val dy = (height - pose.srcH * scale) / 2f

        // Draw in the analysis frame's own pixels and let the canvas do the mapping, which is
        // what the synced picture and the film do too.
        canvas.save()
        canvas.translate(dx, dy)
        canvas.scale(scale, scale)
        painter.paint(canvas, pose.keypoints, pose.srcH, pose.guide)
        canvas.restore()
    }
}
