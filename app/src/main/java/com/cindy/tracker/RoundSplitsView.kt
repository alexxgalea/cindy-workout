package com.cindy.tracker

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
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
import androidx.core.content.res.ResourcesCompat
import androidx.core.view.ViewCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import androidx.customview.widget.ExploreByTouchHelper
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/**
 * The round splits: one bar per round, taller meaning slower, each stacked from the bottom into
 * pull-ups, push-ups and squats where the record can say where the time went.
 *
 * The three movements keep the weights they have everywhere else they appear together (see
 * `HelpActivity.workoutCard`), so a segment is read by its brightness and never needs a legend
 * of colours. The earned colour marks only the fastest round. A short tick over a bar is where
 * the comparison's round at the same position ended, so a bar poking above its tick is slower
 * than that session and one under it is faster. The round the clock stopped in is outlined
 * rather than filled, because it is a time so far and not a split.
 *
 * Touch, scrubbing and TalkBack follow [ProgressChartView]: a tap selects the nearest bar, a
 * sideways drag scrubs, a vertical one is left to the scroll view around it, and every bar is
 * its own TalkBack stop.
 */
class RoundSplitsView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0
) : View(context, attrs, defStyle) {

    /** Reports the selection as it changes; null when it is cleared. */
    var onSelect: ((Int?) -> Unit)? = null

    /** The selected bar, or null when the selection is cleared. */
    var selected: Int? = null
        private set

    // The data fields come first: [helper] below reads them, and property initialisers run top
    // to bottom.
    private var bars: List<RoundSplits.Bar> = emptyList()
    private var reference: List<Long?> = emptyList()
    private var fastest = -1
    private var averageMs = 0L
    private var averageLabel: String? = null
    private var describe: (Int) -> String = { "" }
    private var maxMs = 1L

    /** Text built once in [show], so [onDraw] only reads it. */
    private var roundLabels: Array<String> = emptyArray()
    private var repLabels: Array<String?> = emptyArray()

    /** Geometry, rebuilt by [layoutBars]. */
    private val plot = RectF()
    private var slot = 0f

    private var reveal = 1f
    private var revealAnimator: ValueAnimator? = null

    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private var downX = 0f
    private var downY = 0f
    private var dragging = false

    private val colourLabel = context.getColor(R.color.label)
    private val colourSecondary = context.getColor(R.color.label_secondary)
    private val colourTertiary = context.getColor(R.color.label_tertiary)
    private val colourEarned = context.getColor(R.color.achievement)

    /** Pull-ups, push-ups, squats: the weights their 5:10:15 rep scheme gives them. */
    private val segmentColours = intArrayOf(colourLabel, colourSecondary, colourTertiary)

    private val barPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val outlinePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = context.dpf(1.5f)
    }
    private val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = colourEarned
    }
    private val tickPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = colourSecondary
        style = Paint.Style.STROKE
        strokeWidth = context.dpf(2f)
        strokeCap = Paint.Cap.ROUND
    }

    /** Under a tick, so it reads over a bar's own fill as well as over the empty plot. */
    private val tickHaloPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = context.getColor(R.color.bg)
        style = Paint.Style.STROKE
        strokeWidth = context.dpf(4.5f)
        strokeCap = Paint.Cap.ROUND
    }
    private val baselinePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = context.getColor(R.color.hairline)
        style = Paint.Style.STROKE
        strokeWidth = context.hairlinePx().toFloat()
    }
    private val averagePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = colourTertiary
        style = Paint.Style.STROKE
        strokeWidth = context.dpf(1f)
        pathEffect = DashPathEffect(floatArrayOf(context.dpf(4f), context.dpf(5f)), 0f)
    }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = colourTertiary
        textSize = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP, 11f, resources.displayMetrics
        )
        textAlign = Paint.Align.CENTER
        typeface = ResourcesCompat.getFont(context, R.font.manrope_semibold)
        // Round numbers and a rep count change as the athlete scrubs: proportional figures would
        // shuffle them sideways.
        fontFeatureSettings = "tnum"
    }
    private val averageTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = colourTertiary
        textSize = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP, 10f, resources.displayMetrics
        )
        textAlign = Paint.Align.RIGHT
        letterSpacing = 0.05f
        typeface = ResourcesCompat.getFont(context, R.font.manrope_bold)
        fontFeatureSettings = "tnum"
    }

    /** Reused, because a chart on a scrolling screen redraws far more often than it changes. */
    private val barPath = Path()
    private val barRect = RectF()
    private val barRadii = FloatArray(8)

    /** One virtual view per bar, so TalkBack can step through them. */
    private val helper = object : ExploreByTouchHelper(this) {
        override fun getVirtualViewAt(x: Float, y: Float): Int =
            if (bars.isEmpty()) ExploreByTouchHelper.INVALID_ID else nearest(x)

        override fun getVisibleVirtualViews(virtualViewIds: MutableList<Int>) {
            bars.indices.forEach { virtualViewIds.add(it) }
        }

        override fun onPopulateNodeForVirtualView(
            virtualViewId: Int,
            node: AccessibilityNodeInfoCompat
        ) {
            layoutBars()
            node.contentDescription = describe(virtualViewId)
            val half = max(slot / 2f, context.dpf(24f))
            val cx = centreX(virtualViewId)
            // Required by ExploreByTouchHelper even though the setter is deprecated.
            @Suppress("DEPRECATION")
            node.setBoundsInParent(
                Rect((cx - half).toInt(), 0, (cx + half).toInt(), height.coerceAtLeast(1))
            )
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

    /** The number of bars, for tests. */
    internal val barCount: Int get() = bars.size

    /** The x of bar [i], laying out first; for tests. */
    internal fun barCenterX(i: Int): Float {
        layoutBars()
        return centreX(i)
    }

    /**
     * Shows [bars], dropping any selection and replaying the reveal.
     *
     * @param averageLabel what the dashed average line is called, or null to leave it undrawn.
     *   The view holds raw milliseconds and does not format them, so the caller does.
     * @param describe what TalkBack reads for bar `i`.
     */
    fun show(
        bars: List<RoundSplits.Bar>,
        fastest: Int,
        averageMs: Long,
        averageLabel: String?,
        describe: (Int) -> String
    ) {
        this.bars = bars
        this.fastest = fastest
        this.averageMs = averageMs
        this.averageLabel = averageLabel
        this.describe = describe
        this.reference = emptyList()
        roundLabels = Array(bars.size) { "${bars[it].round}" }
        repLabels = Array(bars.size) { i ->
            val b = bars[i]
            // A floor reads "≥12/30": the camera lost the athlete, so the count may be short.
            b.reps?.let { reps -> "${if (b.atLeast) "≥" else ""}$reps/${RoundSplits.ROUND_TARGET}" }
        }
        selected = null
        rescale()
        startReveal()
        helper.invalidateRoot()
        invalidate()
    }

    /**
     * Sets the tick over each bar: [reference] is the comparison's split at that bar's round, or
     * null where it has none. Kept apart from [show] so choosing another comparison moves the
     * ticks without replaying the reveal or losing the selection.
     */
    fun setReference(reference: List<Long?>) {
        this.reference = reference
        rescale()
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

    /** The tallest thing drawn sets the scale, so a tick above every bar is not clipped. */
    private fun rescale() {
        var top = 1L
        for (b in bars) top = max(top, b.ms)
        for (r in reference) if (r != null) top = max(top, r)
        maxMs = top
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

    /** Room above the plot for the fastest round's dot, below it for the round numbers. */
    private fun layoutBars() {
        plot.set(
            paddingLeft.toFloat(),
            paddingTop + context.dpf(16f),
            (width - paddingRight).toFloat(),
            height - paddingBottom - context.dpf(20f)
        )
        slot = if (bars.isEmpty()) 0f else plot.width() / bars.size
    }

    private fun centreX(i: Int): Float = plot.left + slot * (i + 0.5f)

    private fun yFor(ms: Long): Float = plot.bottom - (ms.toFloat() / maxMs) * plot.height()

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        layoutBars()
        if (bars.isEmpty() || plot.width() <= 0f || plot.height() <= 0f) return

        canvas.drawLine(plot.left, plot.bottom, plot.right, plot.bottom, baselinePaint)

        canvas.save()
        canvas.clipRect(0f, 0f, plot.left + plot.width() * reveal + context.dpf(8f), height.toFloat())
        val half = max(context.dpf(2f), slot * 0.66f) / 2f
        for (i in bars.indices) drawBar(canvas, i, half)
        canvas.restore()

        // Drawn last so it reads over the bars: a drift away from the average is the thing the
        // chart is for, and it is hard to see against eighteen bars without a line to see it from.
        averageLabel?.let { text ->
            val y = yFor(averageMs)
            canvas.drawLine(plot.left, y, plot.right, y, averagePaint)
            canvas.drawText(text, plot.right, y - context.dpf(5f), averageTextPaint)
        }
        drawNumbers(canvas)
    }

    private fun drawBar(canvas: Canvas, i: Int, half: Float) {
        val bar = bars[i]
        val cx = centreX(i)
        val top = yFor(bar.ms)
        // With a bar chosen the others recede, so the one being read is the one that stands out.
        val fade = if (selected == null || selected == i) 1f else 0.45f

        when {
            bar.unfinished -> {
                outlinePaint.color = colourSecondary
                outlinePaint.alpha = (Color.alpha(colourSecondary) * fade).toInt()
                val inset = outlinePaint.strokeWidth / 2f
                topRounded(cx - half + inset, top + inset, cx + half - inset, plot.bottom)
                canvas.drawPath(barPath, outlinePaint)
                repLabels[i]?.let { label ->
                    textPaint.color = colourSecondary
                    drawLabel(canvas, label, cx, top - context.dpf(5f))
                }
            }
            bar.sets != null -> drawStack(canvas, bar.sets, cx, half, top, fade)
            else -> {
                barPaint.color = colourLabel
                barPaint.alpha = (PLAIN_ALPHA * fade).toInt()
                topRounded(cx - half, top, cx + half, plot.bottom)
                canvas.drawPath(barPath, barPaint)
            }
        }

        val tick = reference.getOrNull(i)
        val tickY = if (tick == null) Float.NaN else yFor(tick)
        if (tick != null) {
            val reach = half + context.dpf(3f)
            canvas.drawLine(cx - reach, tickY, cx + reach, tickY, tickHaloPaint)
            canvas.drawLine(cx - reach, tickY, cx + reach, tickY, tickPaint)
        }
        if (i == fastest) {
            // Above the tick as well as the bar, so the two never sit on top of each other.
            val clear = if (tickY.isNaN()) top else min(top, tickY)
            canvas.drawCircle(cx, clear - context.dpf(8f), context.dpf(3f), dotPaint)
        }
    }

    /** The bar's own height is its split; the sets are scaled to fill it exactly. */
    private fun drawStack(
        canvas: Canvas,
        sets: List<Long>,
        cx: Float,
        half: Float,
        top: Float,
        fade: Float
    ) {
        // An index loop: a list's sum() would allocate an iterator on every frame.
        var total = 0L
        for (k in sets.indices) total += sets[k]
        val sum = total.coerceAtLeast(1L).toFloat()
        val height = plot.bottom - top
        val gap = context.dpf(1f)
        var floor = plot.bottom
        for (k in sets.indices) {
            val ceiling = if (k == sets.lastIndex) top else floor - height * (sets[k] / sum)
            val c = segmentColours[k]
            barPaint.color = c
            barPaint.alpha = (Color.alpha(c) * fade).toInt()
            if (k == sets.lastIndex) {
                topRounded(cx - half, ceiling, cx + half, floor)
                canvas.drawPath(barPath, barPaint)
            } else {
                // A hairline of the page between sets, so two neighbours of similar weight still
                // read as two.
                barRect.set(cx - half, min(ceiling + gap, floor), cx + half, floor)
                canvas.drawRect(barRect, barPaint)
            }
            floor = ceiling
        }
    }

    /** Round numbers, thinned until they stop touching; the selected one is always named. */
    private fun drawNumbers(canvas: Canvas) {
        val wanted = textPaint.textSize * 2.2f
        val step = max(1, ceil(wanted / slot).toInt())
        val y = height - paddingBottom - context.dpf(4f)
        val chosen = selected
        for (i in bars.indices) {
            val isSelected = i == chosen
            if (!isSelected && i % step != 0) continue
            // A neighbour of the selected number would overlap it.
            if (!isSelected && chosen != null && abs(i - chosen) * slot < wanted) continue
            textPaint.color = if (isSelected) colourLabel else colourTertiary
            canvas.drawText(roundLabels[i], centreX(i), y, textPaint)
        }
    }

    /** Draws [text] centred on [x], moved in if it would leave the view. */
    private fun drawLabel(canvas: Canvas, text: String, x: Float, y: Float) {
        val half = textPaint.measureText(text) / 2f
        val clamped = x.coerceIn(half, max(half, width - half))
        canvas.drawText(text, clamped, y, textPaint)
    }

    /** A bar with only its top corners rounded, built into [barPath]; the foot sits flat. */
    private fun topRounded(left: Float, top: Float, right: Float, bottom: Float) {
        val r = min(context.dpf(3f), max(0f, bottom - top))
        barRadii.fill(0f)
        for (k in 0 until 4) barRadii[k] = r
        barRect.set(left, top, right, bottom)
        barPath.rewind()
        barPath.addRoundRect(barRect, barRadii, Path.Direction.CW)
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (bars.isEmpty()) return false
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = e.x
                downY = e.y
                dragging = false
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = abs(e.x - downX)
                if (!dragging && dx > touchSlop && dx > abs(e.y - downY)) {
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

    /** The bar whose slot [x] falls in, so a finger between two bars still picks one. */
    private fun nearest(x: Float): Int {
        layoutBars()
        if (slot <= 0f) return 0
        return ((x - plot.left) / slot).toInt().coerceIn(0, bars.lastIndex)
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
        /** A round with no per-movement times: a quiet single bar, as before. */
        const val PLAIN_ALPHA = 61
    }
}
