package com.cindy.tracker

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
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
import androidx.annotation.ColorInt
import androidx.core.content.res.ResourcesCompat
import androidx.core.view.ViewCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import androidx.customview.widget.ExploreByTouchHelper
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToLong

/** One value on a lane at one instant of the workout clock. */
data class TimelinePoint(val clockMs: Long, val value: Double)

/**
 * One unbroken stretch of a lane's own series. Two runs are never joined, which is how a gap in a
 * heart-rate trace stays a gap; and a run is the unit of style, so a lane whose series is partly
 * measured and partly estimated is several runs, some of them [dashed].
 */
class TimelineRun(val points: List<TimelinePoint>, val dashed: Boolean = false)

/**
 * One band of the timeline, stacked above or below the others on a shared clock axis.
 *
 * Nothing here is about reps or heart rate: a lane is a label, a colour, some runs and a way to
 * write a value, which is what lets a third kind be one more entry in the list rather than
 * another special case in the drawing or in the TalkBack text.
 */
class TimelineLane(
    /** Said above the band, in capitals. */
    val label: String,
    @ColorInt val colour: Int,
    val runs: List<TimelineRun>,
    /** The session being measured against, drawn dashed behind [runs]; empty for none. */
    val comparison: List<TimelinePoint> = emptyList(),
    /** Writes an axis value. */
    val format: (Double) -> String,
    /**
     * True for a value that is banked and then holds, like reps: the line steps up at each
     * point and runs flat between them. False joins the points directly.
     */
    val stepped: Boolean = false,
    /** True to start the axis at zero rather than at the lowest value. */
    val zeroBased: Boolean = false,
    /**
     * How long after a point the cursor still reports its value for the cursor's dot, or
     * [Long.MAX_VALUE] for as long as nothing newer has arrived.
     */
    val holdMs: Long = Long.MAX_VALUE,
    /** Draw a dot at each point, for a series whose points are all there is. */
    val markPoints: Boolean = false,
    val heightDp: Int = 96
)

/** One TalkBack stop: the stretch of the clock it covers, and what it says. */
class TimelineStop(val startMs: Long, val endMs: Long, val description: String)

/**
 * Lanes of one session against a shared clock: cumulative reps, heart rate, and whatever is added
 * next. Drawn by hand like [ProgressChartView], whose idiom this follows: paints and paths are
 * fields, nothing is allocated while drawing, the first data reveals left to right, a tap selects
 * and a sideways drag scrubs while a vertical one is left to the scroll view.
 *
 * Unlike that chart, the selection is an instant on the clock rather than one of its points: the
 * cursor crosses every lane at once, and each lane puts a dot where its own series stood. A
 * scrub ticks the haptic as it passes each of the first lane's points and each round end, not
 * at every pixel, so a drag through two hundred reps feels like two hundred reps.
 */
class SessionTimelineView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0
) : View(context, attrs, defStyle) {

    /** Reports the selected clock as it changes; null when it is cleared. */
    var onSelect: ((Long?) -> Unit)? = null

    /** The selected instant on the workout clock, or null when the selection is cleared. */
    var selectedMs: Long? = null
        private set

    // The data fields come first: [helper] below reads them, and property initialisers run top
    // to bottom.
    private var lanes: List<TimelineLane> = emptyList()
    private var durationMs = 0L
    private var roundEnds: List<Long> = emptyList()
    private var stops: List<TimelineStop> = emptyList()
    private var snapClocks = LongArray(0)
    private var laneLo = DoubleArray(0)
    private var laneHi = DoubleArray(0)
    private var laneTicks: List<List<Double>> = emptyList()

    /** Geometry, rebuilt by [layoutLanes]. */
    private val plot = RectF()
    private var laneTop = FloatArray(0)
    private var laneBottom = FloatArray(0)

    private var reveal = 1f
    private var revealAnimator: ValueAnimator? = null

    private val slop = ViewConfiguration.get(context).scaledTouchSlop
    private var downX = 0f
    private var downY = 0f
    private var dragging = false
    private var lastSnap = -1
    private var lastStop = -1

    private val colourTertiary = context.getColor(R.color.label_tertiary)

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
        fontFeatureSettings = "tnum"
    }
    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = context.dpf(2f)
        strokeJoin = Paint.Join.ROUND
        strokeCap = Paint.Cap.ROUND
    }
    private val dashPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = context.dpf(2f)
        strokeJoin = Paint.Join.ROUND
        strokeCap = Paint.Cap.ROUND
        pathEffect = DashPathEffect(floatArrayOf(context.dpf(5f), context.dpf(4f)), 0f)
    }
    private val comparisonPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = colourTertiary
        style = Paint.Style.STROKE
        strokeWidth = context.dpf(1.5f)
        strokeJoin = Paint.Join.ROUND
        pathEffect = DashPathEffect(floatArrayOf(context.dpf(5f), context.dpf(4f)), 0f)
    }
    private val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
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
    private val path = Path()

    /** One virtual view per [TimelineStop], so TalkBack can step through the rounds. */
    private val helper = object : ExploreByTouchHelper(this) {
        override fun getVirtualViewAt(x: Float, y: Float): Int {
            if (stops.isEmpty()) return ExploreByTouchHelper.INVALID_ID
            layoutLanes()
            return stopAt(clockFor(x))
        }

        override fun getVisibleVirtualViews(virtualViewIds: MutableList<Int>) {
            stops.indices.forEach { virtualViewIds.add(it) }
        }

        override fun onPopulateNodeForVirtualView(
            virtualViewId: Int,
            node: AccessibilityNodeInfoCompat
        ) {
            val stop = stops.getOrNull(virtualViewId)
            if (stop == null) {
                node.contentDescription = ""
                @Suppress("DEPRECATION")
                node.setBoundsInParent(Rect(0, 0, 1, 1))
                return
            }
            layoutLanes()
            node.contentDescription = stop.description
            val half = context.dp(24)
            val cx = ((xFor(stop.startMs) + xFor(stop.endMs)) / 2f).toInt()
            // Required by ExploreByTouchHelper even though the setter is deprecated.
            @Suppress("DEPRECATION")
            node.setBoundsInParent(Rect(cx - half, 0, cx + half, height.coerceAtLeast(1)))
            node.addAction(AccessibilityNodeInfoCompat.ACTION_CLICK)
            val s = selectedMs
            node.isSelected = s != null && stopAt(s) == virtualViewId
        }

        override fun onPerformActionForVirtualView(
            virtualViewId: Int,
            action: Int,
            arguments: Bundle?
        ): Boolean {
            if (action != AccessibilityNodeInfoCompat.ACTION_CLICK) return false
            val stop = stops.getOrNull(virtualViewId) ?: return false
            select(stop.endMs)
            return true
        }
    }

    init {
        ViewCompat.setAccessibilityDelegate(this, helper)
    }

    /** The number of lanes, for tests. */
    internal val laneCount: Int get() = lanes.size

    /** The number of TalkBack stops, for tests. */
    internal val stopCount: Int get() = stops.size

    /** The x of [clockMs], laying out first; for tests. */
    internal fun xOf(clockMs: Long): Float {
        layoutLanes()
        return xFor(clockMs)
    }

    /**
     * Replaces everything drawn. [durationMs] is the shared axis; [roundEndsMs] are hairlines
     * through every lane; [stops] are what TalkBack steps through, in clock order. A selection
     * that is still on the clock is kept, so swapping the dashed comparison does not lose the
     * place the athlete was looking at — the caller reads [selectedMs] to redraw its own readout.
     */
    fun setLanes(
        lanes: List<TimelineLane>,
        durationMs: Long,
        roundEndsMs: List<Long> = emptyList(),
        stops: List<TimelineStop> = emptyList()
    ) {
        val firstData = this.lanes.isEmpty() && lanes.isNotEmpty()
        this.lanes = lanes
        this.durationMs = durationMs
        this.roundEnds = roundEndsMs
        this.stops = stops
        laneLo = DoubleArray(lanes.size)
        laneHi = DoubleArray(lanes.size)
        laneTicks = lanes.mapIndexed { i, lane ->
            val values = lane.runs.flatMap { r -> r.points.map { it.value } } +
                lane.comparison.map { it.value }
            val lo = if (lane.zeroBased) 0.0 else values.minOrNull() ?: 0.0
            val ticks = Progress.niceTicks(lo, max(values.maxOrNull() ?: 1.0, lo + 1.0))
            laneLo[i] = ticks.first()
            laneHi[i] = ticks.last()
            ticks
        }
        snapClocks = snapPoints(lanes.firstOrNull(), roundEndsMs)
        if (selectedMs?.let { it > durationMs } == true) selectedMs = null
        if (firstData) startReveal() else reveal = 1f
        requestLayout()
        helper.invalidateRoot()
        invalidate()
    }

    /** The instants a scrub ticks on: the first lane's own points and the round ends, in order. */
    private fun snapPoints(first: TimelineLane?, ends: List<Long>): LongArray {
        val clocks = ArrayList<Long>()
        // A line of samples a second apart would tick on every one of them, which is a buzz and
        // not a texture; a stepped lane's points are events, and each of those is worth a tick.
        var lastKept = Long.MIN_VALUE
        first?.runs?.forEach { r ->
            r.points.forEach {
                if (first.stepped || it.clockMs - lastKept >= SNAP_GAP_MS) {
                    clocks.add(it.clockMs)
                    lastKept = it.clockMs
                }
            }
        }
        clocks.addAll(ends)
        clocks.sort()
        return clocks.distinct().toLongArray()
    }

    /** Selects the instant [clockMs] (null clears), redraws, reports it and announces its round. */
    fun select(clockMs: Long?) {
        selectedMs = clockMs?.coerceIn(0L, durationMs)
        if (selectedMs == null) lastStop = -1
        invalidate()
        onSelect?.invoke(selectedMs)
        val at = selectedMs ?: return
        val stop = stopAt(at)
        if (stop >= 0 && stop != lastStop) {
            helper.sendEventForVirtualView(stop, AccessibilityEvent.TYPE_VIEW_SELECTED)
        }
        lastStop = stop
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

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        var wanted = paddingTop + paddingBottom + context.dp(AXIS_DP)
        lanes.forEachIndexed { i, lane ->
            wanted += context.dp(lane.heightDp) + if (i > 0) context.dp(GAP_DP) else 0
        }
        setMeasuredDimension(
            getDefaultSize(suggestedMinimumWidth, widthMeasureSpec),
            resolveSize(wanted, heightMeasureSpec)
        )
    }

    /** Plot rectangle, and the top and bottom of every lane. Cheap; every draw and touch calls it. */
    private fun layoutLanes() {
        plot.set(
            paddingLeft.toFloat(), 0f, width - paddingRight - context.dpf(44f), 0f
        )
        val n = lanes.size
        if (laneTop.size != n) {
            laneTop = FloatArray(n)
            laneBottom = FloatArray(n)
        }
        var y = paddingTop.toFloat()
        for (i in 0 until n) {
            laneTop[i] = y + context.dpf(LABEL_DP)
            laneBottom[i] = y + context.dpf(lanes[i].heightDp.toFloat())
            y = laneBottom[i] + context.dpf(GAP_DP.toFloat())
        }
    }

    private fun xFor(clockMs: Long): Float {
        if (durationMs <= 0L) return plot.left
        return plot.left + (clockMs.toDouble() / durationMs).toFloat() * plot.width()
    }

    private fun clockFor(x: Float): Long {
        if (plot.width() <= 0f) return 0L
        val f = ((x - plot.left) / plot.width()).coerceIn(0f, 1f)
        return (f.toDouble() * durationMs).roundToLong()
    }

    private fun yFor(lane: Int, value: Double): Float {
        val lo = laneLo[lane]
        val hi = laneHi[lane]
        val f = if (hi - lo < 1e-9) 0.5f else ((value - lo) / (hi - lo)).toFloat()
        return laneBottom[lane] - f * (laneBottom[lane] - laneTop[lane])
    }

    /** The stop covering [clockMs], or -1 for none. A stop covers its own end, as a round does. */
    private fun stopAt(clockMs: Long): Int {
        for (i in stops.indices) if (clockMs <= stops[i].endMs) return i
        return if (stops.isEmpty()) -1 else stops.lastIndex
    }

    /** How many snap instants are at or before [clockMs]. */
    private fun snapIndex(clockMs: Long): Int {
        var lo = 0
        var hi = snapClocks.size
        while (lo < hi) {
            val mid = (lo + hi) ushr 1
            if (snapClocks[mid] <= clockMs) lo = mid + 1 else hi = mid
        }
        return lo
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        layoutLanes()
        if (lanes.isEmpty() || durationMs <= 0L || plot.width() <= 0f) return

        for (i in lanes.indices) drawAxes(canvas, i)
        drawEdgeLabels(canvas)

        canvas.save()
        val clipRight = minOf(
            plot.left + plot.width() * reveal + context.dpf(8f), plot.right + context.dpf(1f)
        )
        canvas.clipRect(0f, 0f, clipRight, height.toFloat())
        for (i in lanes.indices) drawLane(canvas, i)
        canvas.restore()

        val s = selectedMs
        if (s != null) drawCursor(canvas, s)
    }

    private fun drawAxes(canvas: Canvas, i: Int) {
        val lane = lanes[i]
        val top = laneTop[i]
        val bottom = laneBottom[i]
        textPaint.textAlign = Paint.Align.LEFT
        canvas.drawText(lane.label, plot.left, top - context.dpf(5f), textPaint)

        for (t in laneTicks[i]) {
            val y = yFor(i, t)
            canvas.drawLine(plot.left, y, plot.right, y, gridPaint)
        }
        textPaint.textAlign = Paint.Align.RIGHT
        // Only the first and last tick are named: a short band with four labels is all labels.
        val ticks = laneTicks[i]
        canvas.drawText(
            lane.format(ticks.last()), (width - paddingRight).toFloat(),
            yFor(i, ticks.last()) + textPaint.textSize * 0.35f, textPaint
        )
        if (ticks.size > 1) {
            canvas.drawText(
                lane.format(ticks.first()), (width - paddingRight).toFloat(),
                yFor(i, ticks.first()) + textPaint.textSize * 0.35f, textPaint
            )
        }
        for (k in roundEnds.indices) {
            val x = xFor(roundEnds[k])
            canvas.drawLine(x, top, x, bottom, gridPaint)
        }
    }

    private fun drawEdgeLabels(canvas: Canvas) {
        val baseline = height - paddingBottom - context.dpf(4f)
        textPaint.textAlign = Paint.Align.LEFT
        canvas.drawText("0:00", plot.left, baseline, textPaint)
        textPaint.textAlign = Paint.Align.RIGHT
        canvas.drawText(formatDuration(durationMs), plot.right, baseline, textPaint)
    }

    private fun drawLane(canvas: Canvas, i: Int) {
        val lane = lanes[i]
        if (lane.comparison.size > 1) {
            drawSeries(canvas, i, lane.comparison, lane.stepped, false, comparisonPaint)
        }
        for (r in lane.runs.indices) {
            val run = lane.runs[r]
            val paint = if (run.dashed) dashPaint else linePaint
            paint.color = lane.colour
            // A step line holds its last value to the end of the clock: reps do not un-bank.
            val hold = lane.stepped && r == lane.runs.lastIndex
            drawSeries(canvas, i, run.points, lane.stepped, hold, paint)
            if (lane.markPoints || run.points.size == 1) {
                dotPaint.color = lane.colour
                for (p in run.points.indices) {
                    val point = run.points[p]
                    canvas.drawCircle(
                        xFor(point.clockMs), yFor(i, point.value), context.dpf(2.5f), dotPaint
                    )
                }
            }
        }
    }

    private fun drawSeries(
        canvas: Canvas,
        lane: Int,
        points: List<TimelinePoint>,
        stepped: Boolean,
        holdToEnd: Boolean,
        paint: Paint
    ) {
        val n = points.size
        if (n == 0) return
        path.rewind()
        path.moveTo(xFor(points[0].clockMs), yFor(lane, points[0].value))
        for (k in 1 until n) {
            val x = xFor(points[k].clockMs)
            if (stepped) path.lineTo(x, yFor(lane, points[k - 1].value))
            path.lineTo(x, yFor(lane, points[k].value))
        }
        if (holdToEnd) path.lineTo(plot.right, yFor(lane, points[n - 1].value))
        canvas.drawPath(path, paint)
    }

    private fun drawCursor(canvas: Canvas, clockMs: Long) {
        if (lanes.isEmpty()) return
        val x = xFor(clockMs)
        canvas.drawLine(x, laneTop[0], x, laneBottom[lanes.lastIndex], cursorPaint)
        for (i in lanes.indices) {
            val lane = lanes[i]
            val theirs = valueAt(lane.comparison, clockMs, lane.stepped, lane.holdMs)
            if (!theirs.isNaN()) drawDot(canvas, x, yFor(i, theirs), colourTertiary, 4f)
            val mine = valueAtRuns(lane, clockMs)
            if (!mine.isNaN()) drawDot(canvas, x, yFor(i, mine), lane.colour, 5.5f)
        }
    }

    private fun drawDot(canvas: Canvas, x: Float, y: Float, colour: Int, radiusDp: Float) {
        dotPaint.color = colour
        canvas.drawCircle(x, y, context.dpf(radiusDp), dotPaint)
        canvas.drawCircle(x, y, context.dpf(radiusDp), haloPaint)
    }

    /** NaN for none: the value is wanted every frame of a scrub, and a null would box it. */
    private fun valueAtRuns(lane: TimelineLane, clockMs: Long): Double {
        for (r in lane.runs.indices.reversed()) {
            val run = lane.runs[r]
            if (run.points.isNotEmpty() && run.points[0].clockMs <= clockMs) {
                return valueAt(run.points, clockMs, lane.stepped, lane.holdMs)
            }
        }
        return Double.NaN
    }

    /**
     * The latest point at or before [clockMs] — never a position between two — or NaN when there
     * is none, or for a lane with a hold when it is older than that.
     */
    private fun valueAt(
        points: List<TimelinePoint>,
        clockMs: Long,
        stepped: Boolean,
        holdMs: Long
    ): Double {
        var lo = 0
        var hi = points.size
        while (lo < hi) {
            val mid = (lo + hi) ushr 1
            if (points[mid].clockMs <= clockMs) lo = mid + 1 else hi = mid
        }
        if (lo == 0) return Double.NaN
        val p = points[lo - 1]
        if (!stepped && clockMs - p.clockMs > holdMs) return Double.NaN
        return p.value
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (lanes.isEmpty()) return false
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
                    layoutLanes()
                    val current = selectedMs
                    // A second tap on the cursor puts it away, as a second tap on a point does.
                    if (current != null && abs(xFor(current) - e.x) <= context.dpf(24f)) {
                        select(null)
                    } else {
                        lastSnap = snapIndex(clockFor(e.x))
                        select(clockFor(e.x))
                    }
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
        layoutLanes()
        val at = clockFor(x)
        if (at == selectedMs) return
        select(at)
        val snap = snapIndex(at)
        if (snap != lastSnap) {
            lastSnap = snap
            performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
        }
    }

    override fun dispatchHoverEvent(event: MotionEvent): Boolean =
        helper.dispatchHoverEvent(event) || super.dispatchHoverEvent(event)

    override fun dispatchKeyEvent(event: KeyEvent): Boolean =
        helper.dispatchKeyEvent(event) || super.dispatchKeyEvent(event)

    override fun onFocusChanged(gain: Boolean, direction: Int, previous: Rect?) {
        super.onFocusChanged(gain, direction, previous)
        helper.onFocusChanged(gain, direction, previous)
    }

    private companion object {
        /** The row above each lane that names it. */
        const val LABEL_DP = 18f
        const val GAP_DP = 10
        /** The row under the last lane that carries the clock's two ends. */
        const val AXIS_DP = 22

        /** The closest two ticks of a scrub may be along a line of samples. */
        const val SNAP_GAP_MS = 5_000L
    }
}
