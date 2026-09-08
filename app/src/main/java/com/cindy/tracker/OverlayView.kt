package com.cindy.tracker

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View
import kotlin.math.max

/**
 * Draws the detected skeleton on top of the preview.
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
    }

    private var pose: Array<Keypoint>? = null
    private var srcW = 0
    private var srcH = 0

    private val bonePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#00E5A0")
        strokeWidth = 7f
        strokeCap = Paint.Cap.ROUND
        style = Paint.Style.STROKE
    }
    private val jointPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.FILL
    }

    fun setPose(keypoints: Array<Keypoint>?, sourceWidth: Int, sourceHeight: Int) {
        pose = keypoints
        srcW = sourceWidth
        srcH = sourceHeight
        postInvalidateOnAnimation()
    }

    fun clear() = setPose(null, 0, 0)

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val k = pose ?: return
        if (srcW == 0 || srcH == 0) return

        // FILL_CENTER: scale up until both axes are covered, then centre the overflow.
        val scale = max(width.toFloat() / srcW, height.toFloat() / srcH)
        val dx = (width - srcW * scale) / 2f
        val dy = (height - srcH * scale) / 2f

        fun px(p: Keypoint) = p.x * scale + dx
        fun py(p: Keypoint) = p.y * scale + dy

        for ((a, b) in KP.SKELETON) {
            val pa = k[a]
            val pb = k[b]
            if (pa.score < MIN_SCORE || pb.score < MIN_SCORE) continue
            canvas.drawLine(px(pa), py(pa), px(pb), py(pb), bonePaint)
        }
        for (p in k) {
            if (p.score < MIN_SCORE) continue
            canvas.drawCircle(px(p), py(p), 9f, jointPaint)
        }
    }
}
