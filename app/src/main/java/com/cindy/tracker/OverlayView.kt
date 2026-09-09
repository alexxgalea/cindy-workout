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
 * Draws the detected skeleton, and the pull-up gate, on top of the preview.
 *
 * Keypoints arrive in analysis-frame pixels, which is a different resolution to the view, so
 * the same FILL_CENTER mapping PreviewView applies is recomputed here — otherwise the skeleton
 * drifts away from the body on any device whose preview and analysis aspect ratios differ.
 */
class OverlayView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0
) : View(context, attrs, defStyle) {

    private companion object {
        const val MIN_SCORE = 0.30f
        /** Alpha of the wash inside the bar zone: enough to read as a region, not as a mask. */
        const val ZONE_FILL_ALPHA = 26
    }

    private var pose: Array<Keypoint>? = null
    private var bar: WorkoutEngine.BarGuide? = null
    private var srcW = 0
    private var srcH = 0

    private val accent = ContextCompat.getColor(context, R.color.accent)
    private val warn = ContextCompat.getColor(context, R.color.warn)

    private val bonePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = accent
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
        color = ContextCompat.getColor(context, R.color.on_surface_dim)
        strokeWidth = 3f
        style = Paint.Style.STROKE
        pathEffect = DashPathEffect(floatArrayOf(18f, 14f), 0f)
    }

    /**
     * Publishes one analysed frame. [guide] is the pull-up gate, or null for the movements and
     * the moments that have no bar to show.
     */
    fun setPose(
        keypoints: Array<Keypoint>?,
        sourceWidth: Int,
        sourceHeight: Int,
        guide: WorkoutEngine.BarGuide? = null
    ) {
        pose = keypoints
        bar = guide
        srcW = sourceWidth
        srcH = sourceHeight
        postInvalidateOnAnimation()
    }

    fun clear() = setPose(null, 0, 0, null)

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (srcW == 0 || srcH == 0) return

        // FILL_CENTER: scale up until both axes are covered, then centre the overflow.
        val scale = max(width.toFloat() / srcW, height.toFloat() / srcH)
        val dx = (width - srcW * scale) / 2f
        val dy = (height - srcH * scale) / 2f

        fun sx(x: Float) = x * scale + dx
        fun sy(y: Float) = y * scale + dy

        // Under the skeleton, so the body is never obscured by its own gate.
        bar?.let { guide ->
            val colour = if (guide.gateOpen) accent else warn
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

        val k = pose ?: return
        for ((a, b) in KP.SKELETON) {
            val pa = k[a]
            val pb = k[b]
            if (pa.score < MIN_SCORE || pb.score < MIN_SCORE) continue
            canvas.drawLine(sx(pa.x), sy(pa.y), sx(pb.x), sy(pb.y), bonePaint)
        }
        for (p in k) {
            if (p.score < MIN_SCORE) continue
            canvas.drawCircle(sx(p.x), sy(p.y), 9f, jointPaint)
        }
    }
}
