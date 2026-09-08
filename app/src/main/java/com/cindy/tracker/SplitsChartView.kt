package com.cindy.tracker

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View
import kotlin.math.max

/**
 * A bare bar chart: one bar per value, taller meaning larger.
 *
 * Used for round splits (where shorter is better, so the fastest bar is highlighted) and for
 * score history (where taller is better). No library — it is a dozen rectangles.
 */
class SplitsChartView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0
) : View(context, attrs, defStyle) {

    private val barPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#99FFFFFF")
        textSize = 22f
        textAlign = Paint.Align.CENTER
    }

    private var values: List<Long> = emptyList()
    private var highlight = -1
    private var labels: List<String> = emptyList()

    /** @param highlightIndex bar to paint in the accent colour, or -1 for none. */
    fun setValues(values: List<Long>, highlightIndex: Int = -1, labels: List<String> = emptyList()) {
        this.values = values
        this.highlight = highlightIndex
        this.labels = labels
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (values.isEmpty()) return

        val maxValue = max(values.max().toFloat(), 1f)
        val labelRoom = if (labels.isEmpty()) 0f else 28f
        val plotHeight = height - labelRoom
        val slot = width.toFloat() / values.size
        val barWidth = (slot * 0.66f).coerceAtLeast(2f)

        values.forEachIndexed { i, v ->
            val h = (v / maxValue) * (plotHeight - 6f)
            val cx = slot * (i + 0.5f)
            barPaint.color = if (i == highlight) ACCENT else BAR
            canvas.drawRoundRect(
                RectF(cx - barWidth / 2f, plotHeight - h, cx + barWidth / 2f, plotHeight),
                4f, 4f, barPaint
            )
            labels.getOrNull(i)?.let { canvas.drawText(it, cx, height - 6f, labelPaint) }
        }
    }

    private companion object {
        val ACCENT = Color.parseColor("#00E5A0")
        val BAR = Color.parseColor("#44FFFFFF")
    }
}
