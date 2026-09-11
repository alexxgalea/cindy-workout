package com.cindy.tracker

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.DashPathEffect
import android.util.AttributeSet
import android.view.View
import androidx.core.content.res.ResourcesCompat
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
        color = Color.parseColor("#9EEBEBF5")
        textSize = 22f
        textAlign = Paint.Align.CENTER
        typeface = ResourcesCompat.getFont(context, R.font.manrope_semibold)
    }
    private val meanPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#33EBEBF5")
        style = Paint.Style.STROKE
        strokeWidth = 2f
        pathEffect = DashPathEffect(floatArrayOf(8f, 10f), 0f)
    }
    private val meanLabelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#57EBEBF5")
        textSize = 19f
        textAlign = Paint.Align.RIGHT
        letterSpacing = 0.05f
        typeface = ResourcesCompat.getFont(context, R.font.manrope_bold)
    }

    /** Reused, because a chart on a scrolling screen redraws far more often than it changes. */
    private val bar = RectF()

    private var values: List<Long> = emptyList()
    private var highlight = -1
    private var labels: List<String> = emptyList()
    private var meanLabel: String? = null

    /**
     * @param highlightIndex bar to paint white, or -1 for none.
     * @param meanLabel what the average line should be called, or null to leave it undrawn. The
     *   view holds raw numbers and cannot know whether they are milliseconds or reps, so the
     *   caller formats it.
     */
    fun setValues(
        values: List<Long>,
        highlightIndex: Int = -1,
        labels: List<String> = emptyList(),
        meanLabel: String? = null
    ) {
        this.values = values
        this.highlight = highlightIndex
        this.labels = labels
        this.meanLabel = meanLabel
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
            bar.set(cx - barWidth / 2f, plotHeight - h, cx + barWidth / 2f, plotHeight)
            canvas.drawRoundRect(bar, 4f, 4f, barPaint)
            labels.getOrNull(i)?.let { canvas.drawText(it, cx, height - 6f, labelPaint) }
        }

        // Drawn last so it reads over the bars: a drift away from the average is the thing the
        // chart is for, and it is hard to see against eighteen bars without a line to see it from.
        meanLabel?.let { text ->
            val mean = values.sum().toFloat() / values.size
            val y = plotHeight - (mean / maxValue) * (plotHeight - 6f)
            canvas.drawLine(0f, y, width.toFloat(), y, meanPaint)
            canvas.drawText(text, width.toFloat(), y - 8f, meanLabelPaint)
        }
    }

    private companion object {
        /** The highlighted bar is white; the rest recede, so the shape reads before the detail. */
        val ACCENT = Color.WHITE
        val BAR = Color.parseColor("#3DEBEBF5")
    }
}
