package com.cindy.tracker

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View

/**
 * PROTOTYPE #140, never merged. Four drawn corners that mark the real zone when the bands are
 * gone: the rectangle today's bands leave bright. Touches nothing, takes no touches.
 */
class ZoneCornersView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    private val density = resources.displayMetrics.density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 3f * density
        strokeCap = Paint.Cap.ROUND
        color = Color.argb(215, 255, 255, 255)
    }

    /** The zone in this view's own pixels; set from the bands' measured edges. */
    var zoneTop = 0f
        set(value) { field = value; invalidate() }
    var zoneBottom = 0f
        set(value) { field = value; invalidate() }

    init {
        isClickable = false
        isFocusable = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    override fun onDraw(canvas: Canvas) {
        if (zoneBottom <= zoneTop) return
        val inset = 12f * density
        val arm = 30f * density
        val l = inset
        val r = width - inset
        val t = zoneTop + inset
        val b = zoneBottom - inset
        // top-left, top-right, bottom-left, bottom-right
        canvas.drawLine(l, t, l + arm, t, paint); canvas.drawLine(l, t, l, t + arm, paint)
        canvas.drawLine(r, t, r - arm, t, paint); canvas.drawLine(r, t, r, t + arm, paint)
        canvas.drawLine(l, b, l + arm, b, paint); canvas.drawLine(l, b, l, b - arm, paint)
        canvas.drawLine(r, b, r - arm, b, paint); canvas.drawLine(r, b, r, b - arm, paint)
    }
}
