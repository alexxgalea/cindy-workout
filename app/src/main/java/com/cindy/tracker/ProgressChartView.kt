package com.cindy.tracker

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.os.Bundle
import android.util.AttributeSet
import android.util.TypedValue
import android.view.HapticFeedbackConstants
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.accessibility.AccessibilityEvent
import android.view.animation.DecelerateInterpolator
import androidx.core.content.res.ResourcesCompat
import androidx.core.view.ViewCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import androidx.customview.widget.ExploreByTouchHelper
import kotlin.math.abs
import kotlin.math.max

/**
 * The progress chart: a line of attempts with a step line for the best so far, or one bar per
 * week. Drawn by hand, like its neighbours, because it is a path and a dozen rectangles.
 *
 * Touch selects the nearest point (tap) or scrubs through them (a sideways drag); the parent is
 * a vertical scroll view, so a vertical gesture is left alone. Each point is also its own
 * TalkBack stop, through [ExploreByTouchHelper], because a canvas has no children to focus.
 *
 * The earned colour is used only for what the athlete earned: the best-so-far line, a record
 * point, the best week.
 */
class ProgressChartView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0
) : View(context, attrs, defStyle) {

    private enum class Mode { LINE, BARS }

    /** Reports the selection as it changes; null when it is cleared. */
    var onSelect: ((Int?) -> Unit)? = null

    /** The selected index, or null when the selection is cleared. */
    var selected: Int? = null
        private set

    // The data fields come first: [helper] below reads them, and property initialisers run top
    // to bottom.
    private var mode = Mode.LINE
    private var points: List<ProgressPoint> = emptyList()
    private var best: List<Double> = emptyList()
    private var xStart = 0L
    private var xEnd = 0L
    private var invertY = false
    private var edgeLabels: Pair<String, String> = "" to ""
    private var axisLabel: (Double) -> String = { "" }
    private var describe: (Int) -> String = { "" }
    private var ticks: List<Double> = emptyList()
    private var bestBar = -1

    /** Geometry, rebuilt by [layoutPoints]. */
    private val plot = RectF()
    private val xs = ArrayList<Float>()
    private var ys = FloatArray(0)

    private var reveal = 1f
    private var revealAnimator: ValueAnimator? = null

    private val slop = ViewConfiguration.get(context).scaledTouchSlop
    private var downX = 0f
    private var downY = 0f
    private var dragging = false

    private val colourLabel = context.getColor(R.color.label)
    private val colourSecondary = context.getColor(R.color.label_secondary)
    private val colourTertiary = context.getColor(R.color.label_tertiary)
    private val colourQuaternary = context.getColor(R.color.label_quaternary)
    private val colourEarned = context.getColor(R.color.achievement)

    private val gridPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = context.getColor(R.color.hairline)
        style = Paint.Style.STROKE
        strokeWidth = context.hairlinePx().toFloat()
    }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = colourTertiary
        textSize = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP, 11f, resources.displayMetrics
        )
        typeface = ResourcesCompat.getFont(context, R.font.manrope_semibold)
    }
    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = colourLabel
        style = Paint.Style.STROKE
        strokeWidth = context.dpf(2f)
        strokeJoin = Paint.Join.ROUND
        strokeCap = Paint.Cap.ROUND
    }
    private val bestPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = colourEarned
        style = Paint.Style.STROKE
        strokeWidth = context.dpf(1.5f)
        strokeJoin = Paint.Join.ROUND
        strokeCap = Paint.Cap.ROUND
    }
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val barPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = context.dpf(1.5f)
        color = colourSecondary
    }
    private val cursorPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = colourTertiary
        style = Paint.Style.STROKE
        strokeWidth = context.dpf(1f)
    }
    private val haloPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = context.getColor(R.color.bg)
        style = Paint.Style.STROKE
        strokeWidth = context.dpf(2f)
    }

    /** Reused, because a chart on a scrolling screen redraws far more often than it changes. */
    private val linePath = Path()
    private val fillPath = Path()
    private val bestPath = Path()
    private val barPath = Path()
    private val barRect = RectF()
    private val barRadii = FloatArray(8)

    /** One virtual view per point, so TalkBack can step through them. */
    private val helper = object : ExploreByTouchHelper(this) {
        override fun getVirtualViewAt(x: Float, y: Float): Int =
            if (points.isEmpty()) ExploreByTouchHelper.INVALID_ID else nearest(x)

        override fun getVisibleVirtualViews(virtualViewIds: MutableList<Int>) {
            points.indices.forEach { virtualViewIds.add(it) }
        }

        override fun onPopulateNodeForVirtualView(
            virtualViewId: Int,
            node: AccessibilityNodeInfoCompat
        ) {
            layoutPoints()
            node.contentDescription = describe(virtualViewId)
            val half = context.dp(24)
            val cx = xs.getOrElse(virtualViewId) { 0f }.toInt()
            // Required by ExploreByTouchHelper even though the setter is deprecated.
            @Suppress("DEPRECATION")
            node.setBoundsInParent(Rect(cx - half, 0, cx + half, height.coerceAtLeast(1)))
            node.addAction(AccessibilityNodeInfoCompat.ACTION_CLICK)
            node.isSelected = virtualViewId == selected
        }

        override fun onPerformActionForVirtualView(
            virtualViewId: Int,
            action: Int,
            arguments: Bundle?
        ): Boolean {
            if (action != AccessibilityNodeInfoCompat.ACTION_CLICK) return false
            select(virtualViewId)
            return true
        }
    }

    init {
        ViewCompat.setAccessibilityDelegate(this, helper)
    }

    /** The number of points, for tests. */
    internal val pointCount: Int get() = points.size

    /** The x of point [i], laying out first; for tests. */
    internal fun pointCenterX(i: Int): Float {
        layoutPoints()
        return xs[i]
    }

    /** One line of attempts. [best] is drawn as a step line in the earned colour. */
    fun showLine(
        points: List<ProgressPoint>,
        best: List<Double>,
        xStart: Long,
        xEnd: Long,
        invertY: Boolean,
        edgeLabels: Pair<String, String>,
        axisLabel: (Double) -> String,
        describe: (Int) -> String
    ) {
        val values = points.map { it.value } + best
        this.mode = Mode.LINE
        this.points = points
        this.best = best
        this.xStart = xStart
        this.xEnd = xEnd
        this.invertY = invertY
        this.bestBar = -1
        this.ticks = if (values.isEmpty()) emptyList()
        else Progress.niceTicks(values.min(), values.max())
        adopt(edgeLabels, axisLabel, describe)
    }

    /** One bar per week; the tallest (latest on a tie) in the earned colour. */
    fun showBars(
        points: List<ProgressPoint>,
        edgeLabels: Pair<String, String>,
        axisLabel: (Double) -> String,
        describe: (Int) -> String
    ) {
        val top = points.maxOfOrNull { it.value } ?: 0.0
        this.mode = Mode.BARS
        this.points = points
        this.best = emptyList()
        this.invertY = false
        // A run of empty weeks has no best week to celebrate.
        this.bestBar = if (top > 0.0) points.indexOfLast { it.value == top } else -1
        this.ticks = Progress.niceTicks(0.0, max(top, 1.0))
        adopt(edgeLabels, axisLabel, describe)
    }

    /** What every [showLine] and [showBars] call has in common. */
    private fun adopt(
        edgeLabels: Pair<String, String>,
        axisLabel: (Double) -> String,
        describe: (Int) -> String
    ) {
        this.edgeLabels = edgeLabels
        this.axisLabel = axisLabel
        this.describe = describe
        selected = null
        rebuildShader()
        startReveal()
        helper.invalidateRoot()
        invalidate()
    }

    /** Selects [index] (null clears), redraws, reports it and announces it. */
    fun select(index: Int?) {
        selected = index
        invalidate()
        onSelect?.invoke(index)
        if (index != null) {
            helper.sendEventForVirtualView(index, AccessibilityEvent.TYPE_VIEW_SELECTED)
        }
    }

    /** The system's animator-duration scale covers reduced motion. */
    private fun startReveal() {
        revealAnimator?.cancel()
        reveal = 0f
        revealAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 650L
            interpolator = DecelerateInterpolator()
            addUpdateListener {
                reveal = it.animatedValue as Float
                invalidate()
            }
            start()
        }
    }

    override fun onDetachedFromWindow() {
        revealAnimator?.cancel()
        reveal = 1f
        super.onDetachedFromWindow()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        rebuildShader()
    }

    /** The fill's gradient depends on the plot's height only: built here, not per frame. */
    private fun rebuildShader() {
        if (width <= 0 || height <= 0) return
        layoutPoints()
        val rgb = colourLabel and 0x00FFFFFF
        fillPaint.shader = LinearGradient(
            0f, plot.top, 0f, plot.bottom, (0x2E shl 24) or rgb, rgb,
            Shader.TileMode.CLAMP
        )
    }

    /** Plot rectangle, and the x and y of every point. Cheap; every draw and touch calls it. */
    private fun layoutPoints() {
        plot.set(
            paddingLeft.toFloat(),
            paddingTop + context.dpf(10f),
            width - paddingRight - context.dpf(44f),
            height - paddingBottom - context.dpf(22f)
        )
        val n = points.size
        xs.clear()
        if (ys.size != n) ys = FloatArray(n)
        val lo = ticks.firstOrNull() ?: 0.0
        val hi = ticks.lastOrNull() ?: 1.0
        for (i in 0 until n) {
            xs.add(if (mode == Mode.BARS) barCentre(i, n) else lineX(points[i].atMillis))
            ys[i] = yFor(points[i].value, lo, hi)
        }
    }

    private fun lineX(atMillis: Long): Float {
        if (xEnd <= xStart) return plot.centerX()
        val f = ((atMillis - xStart).toDouble() / (xEnd - xStart)).coerceIn(0.0, 1.0)
        return plot.left + f.toFloat() * plot.width()
    }

    private fun barCentre(i: Int, n: Int): Float = plot.left + plot.width() / n * (i + 0.5f)

    /** Bars grow from the bottom; on an inverted axis a smaller value sits higher. */
    private fun yFor(value: Double, lo: Double, hi: Double): Float {
        val f = if (hi - lo < 1e-9) 0.5f else ((value - lo) / (hi - lo)).toFloat()
        return if (invertY) plot.top + f * plot.height() else plot.bottom - f * plot.height()
    }

    private fun bestY(value: Double): Float =
        yFor(value, ticks.firstOrNull() ?: 0.0, ticks.lastOrNull() ?: 1.0)

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        layoutPoints()
        if (points.isEmpty() || plot.width() <= 0f || plot.height() <= 0f) return

        drawAxes(canvas)

        canvas.save()
        val clipRight = plot.left + plot.width() * reveal + context.dpf(8f)
        canvas.clipRect(0f, 0f, clipRight, height.toFloat())
        if (mode == Mode.LINE) drawLine(canvas) else drawBars(canvas)
        canvas.restore()

        val s = selected
        if (mode == Mode.LINE && s != null && s in points.indices) {
            val x = xs[s]
            canvas.drawLine(x, plot.top, x, plot.bottom, cursorPaint)
            dotPaint.color = colourLabel
            canvas.drawCircle(x, ys[s], context.dpf(6f), dotPaint)
            canvas.drawCircle(x, ys[s], context.dpf(6f), haloPaint)
        }
    }

    private fun drawAxes(canvas: Canvas) {
        val lo = ticks.firstOrNull() ?: 0.0
        val hi = ticks.lastOrNull() ?: 1.0
        textPaint.textAlign = Paint.Align.RIGHT
        for (t in ticks) {
            val y = yFor(t, lo, hi)
            canvas.drawLine(plot.left, y, plot.right, y, gridPaint)
            canvas.drawText(
                axisLabel(t), (width - paddingRight).toFloat(), y + textPaint.textSize * 0.35f,
                textPaint
            )
        }
        val baseline = height - paddingBottom - context.dpf(4f)
        textPaint.textAlign = Paint.Align.LEFT
        canvas.drawText(edgeLabels.first, plot.left, baseline, textPaint)
        textPaint.textAlign = Paint.Align.RIGHT
        canvas.drawText(edgeLabels.second, plot.right, baseline, textPaint)
    }

    private fun drawLine(canvas: Canvas) {
        val n = points.size
        if (!invertY && n > 1) {
            fillPath.rewind()
            fillPath.moveTo(xs[0], plot.bottom)
            for (i in 0 until n) fillPath.lineTo(xs[i], ys[i])
            fillPath.lineTo(xs[n - 1], plot.bottom)
            fillPath.close()
            canvas.drawPath(fillPath, fillPaint)
        }
        if (n > 1) {
            linePath.rewind()
            linePath.moveTo(xs[0], ys[0])
            for (i in 1 until n) linePath.lineTo(xs[i], ys[i])
            canvas.drawPath(linePath, linePaint)
        }
        if (best.size == n && n > 0) {
            bestPath.rewind()
            bestPath.moveTo(xs[0], bestY(best[0]))
            for (i in 1 until n) {
                bestPath.lineTo(xs[i], bestY(best[i - 1]))
                bestPath.lineTo(xs[i], bestY(best[i]))
            }
            bestPath.lineTo(plot.right, bestY(best[n - 1]))
            canvas.drawPath(bestPath, bestPaint)
        }
        for (i in 0 until n) {
            val p = points[i]
            when {
                p.lowerBound ->
                    canvas.drawCircle(xs[i], ys[i], context.dpf(3.5f), ringPaint)
                p.record -> {
                    dotPaint.color = colourEarned
                    canvas.drawCircle(xs[i], ys[i], context.dpf(4.5f), dotPaint)
                }
                else -> {
                    dotPaint.color = colourLabel
                    canvas.drawCircle(xs[i], ys[i], context.dpf(3f), dotPaint)
                }
            }
        }
    }

    private fun drawBars(canvas: Canvas) {
        val n = points.size
        val slot = plot.width() / n
        val half = max(context.dpf(2f), slot * 0.62f) / 2f
        val corner = context.dpf(3f)
        for (i in 0 until n) {
            val top = ys[i]
            if (plot.bottom - top < 1f) continue
            barPaint.color = when (i) {
                selected -> colourLabel
                bestBar -> colourEarned
                else -> colourTertiary
            }
            // Only the top corners are rounded; the foot sits flat on the axis.
            val r = minOf(corner, plot.bottom - top)
            barRadii.fill(0f)
            for (k in 0 until 4) barRadii[k] = r
            barRect.set(xs[i] - half, top, xs[i] + half, plot.bottom)
            barPath.rewind()
            barPath.addRoundRect(barRect, barRadii, Path.Direction.CW)
            canvas.drawPath(barPath, barPaint)
        }
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (points.isEmpty()) return false
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = e.x
                downY = e.y
                dragging = false
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = abs(e.x - downX)
                if (!dragging && dx > slop && dx > abs(e.y - downY)) {
                    dragging = true
                    parent?.requestDisallowInterceptTouchEvent(true)
                }
                if (dragging) scrubTo(e.x)
                return true
            }
            MotionEvent.ACTION_UP -> {
                if (!dragging) {
                    val i = nearest(e.x)
                    select(if (i == selected) null else i)
                    performClick()
                }
                dragging = false
                parent?.requestDisallowInterceptTouchEvent(false)
                return true
            }
            MotionEvent.ACTION_CANCEL -> {
                dragging = false
                return true
            }
        }
        return super.onTouchEvent(e)
    }

    override fun performClick(): Boolean {
        super.performClick()
        return true
    }

    private fun scrubTo(x: Float) {
        val i = nearest(x)
        if (i != selected) {
            select(i)
            performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
        }
    }

    private fun nearest(x: Float): Int {
        layoutPoints()
        return Progress.nearestIndex(xs, x)
    }

    override fun dispatchHoverEvent(event: MotionEvent): Boolean =
        helper.dispatchHoverEvent(event) || super.dispatchHoverEvent(event)

    override fun dispatchKeyEvent(event: KeyEvent): Boolean =
        helper.dispatchKeyEvent(event) || super.dispatchKeyEvent(event)

    override fun onFocusChanged(gain: Boolean, direction: Int, previous: Rect?) {
        super.onFocusChanged(gain, direction, previous)
        helper.onFocusChanged(gain, direction, previous)
    }
}
