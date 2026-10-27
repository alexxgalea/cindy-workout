package com.cindy.tracker

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View
import androidx.core.content.ContextCompat
import kotlin.math.max

/**
 * Draws the detected skeleton, and the pull-up gate, on top of the live picture.
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

    private companion object {
        /** Alpha of the wash inside the bar zone: enough to read as a region, not as a mask. */
        const val ZONE_FILL_ALPHA = 26
    }

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

    // The gate's two states, and nothing else on this canvas is coloured. The skeleton used to
    // be drawn in the accent — the same colour as titles, chips, streaks and scores — so seeing
    // green on screen told the athlete nothing at all. Now it means one thing: this would count.
    private val ok = ContextCompat.getColor(context, R.color.state_ok)
    private val alert = ContextCompat.getColor(context, R.color.state_alert)

    private val bonePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ContextCompat.getColor(context, R.color.label)
        strokeWidth = 7f
        strokeCap = Paint.Cap.ROUND
        style = Paint.Style.STROKE
    }
    private val jointPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.FILL
    }
    private val zonePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        strokeWidth = 3f
        style = Paint.Style.STROKE
    }
    private val zoneFillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    private val barPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        strokeWidth = 8f
        strokeCap = Paint.Cap.ROUND
        style = Paint.Style.STROKE
    }
    private val resetPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ContextCompat.getColor(context, R.color.label_secondary)
        strokeWidth = 3f
        style = Paint.Style.STROKE
        pathEffect = DashPathEffect(floatArrayOf(18f, 14f), 0f)
    }

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

        fun sx(x: Float) = x * scale + dx
        fun sy(y: Float) = y * scale + dy

        // Under the skeleton, so the body is never obscured by its own gate.
        pose.guide?.let { guide ->
            val colour = if (guide.gateOpen) ok else alert
            val left = sx(guide.zone.left)
            val right = sx(guide.zone.right)
            zoneFillPaint.color = colour
            zoneFillPaint.alpha = ZONE_FILL_ALPHA
            canvas.drawRect(left, sy(guide.zone.top), right, sy(guide.zone.bottom), zoneFillPaint)
            zonePaint.color = colour
            canvas.drawRect(left, sy(guide.zone.top), right, sy(guide.zone.bottom), zonePaint)
            barPaint.color = colour
            canvas.drawLine(left, sy(guide.zone.lineY), right, sy(guide.zone.lineY), barPaint)
            // Where the head has to come back to before the next rep can arm.
            canvas.drawLine(left, sy(guide.resetY), right, sy(guide.resetY), resetPaint)
        }

        val k = pose.keypoints
        for ((a, b) in KP.SKELETON) {
            if (!PoseGeometry.ok(k[a]) || !PoseGeometry.ok(k[b])) continue
            canvas.drawLine(sx(k[a].x), sy(k[a].y), sx(k[b].x), sy(k[b].y), bonePaint)
        }
        for (i in 0 until KP.COUNT) {
            if (!PoseGeometry.ok(k[i])) continue
            canvas.drawCircle(sx(k[i].x), sy(k[i].y), 9f, jointPaint)
        }
    }
}
