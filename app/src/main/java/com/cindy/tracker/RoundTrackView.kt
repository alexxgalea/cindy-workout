package com.cindy.tracker

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.os.Bundle
import android.util.AttributeSet
import android.view.HapticFeedbackConstants
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.accessibility.AccessibilityEvent
import android.view.animation.DecelerateInterpolator
import androidx.core.view.ViewCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import androidx.customview.widget.ExploreByTouchHelper
import kotlin.math.abs

/**
 * One pill per round, ten to a row, each split into pull-ups, push-ups and squats in the 5:10:15
 * proportion of the scheme and filled by how much of each the athlete reached.
 *
 * What was not done stays an outline, so a skipped pull-up set is a hollow stretch at the front of
 * its pill rather than a round that quietly looks complete, and the round the clock ran out on
 * is simply the last, part-filled one. A filled segment is never longer than the reps behind it.
 *
 * Drawn by hand and touched like [ProgressChartView]: a tap selects (a second tap clears), a
 * sideways drag scrubs while a vertical one is left to the parent scroll view, and each round is
 * its own TalkBack stop through [ExploreByTouchHelper]. What a selection says is the caller's to
 * show, through [onSelect]; what TalkBack says for a round comes from [show]'s `describe`.
 */
class RoundTrackView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0
) : View(context, attrs, defStyle) {

    /** Reports the selection as it changes; null when it is cleared. */
    var onSelect: ((Int?) -> Unit)? = null

    /** The selected round's index, or null when none is. */
    var selected: Int? = null
        private set

    // Data first: [helper] below reads it, and property initialisers run top to bottom.
    private var rounds: List<RoundStat> = emptyList()
    private var describe: (Int) -> String = { "" }

    private var reveal = 1f
    private var revealAnimator: ValueAnimator? = null

    private val slop = ViewConfiguration.get(context).scaledTouchSlop
    private var downX = 0f
    private var downY = 0f
    private var dragging = false

    private val cellHeight = context.dpf(48f)
    private val pillHeight = context.dpf(32f)
    private val pillGap = context.dpf(4f)
    private val corner = context.dpf(8f)

    /** One brightness per movement, in cycle order, resolved once rather than per frame. */
    private val segmentColours = IntArray(Exercise.entries.size) {
        context.getColor(movementColourRes(Exercise.entries[it]))
    }
    private val schemeTotal = Exercise.entries.sumOf { it.target }.toFloat()

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val outlinePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = context.getColor(R.color.label_quaternary)
        style = Paint.Style.STROKE
        strokeWidth = context.dpf(1.5f)
    }
    private val dividerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = context.getColor(R.color.bg)
        style = Paint.Style.STROKE
        strokeWidth = context.dpf(1.5f)
    }
    private val selectedPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = context.getColor(R.color.label)
        style = Paint.Style.STROKE
        strokeWidth = context.dpf(2f)
    }

    /** Reused, because the page this sits on redraws far more often than a round changes. */
    private val pill = RectF()
    private val cellRect = RectF()
    private val pillPath = Path()

    private val helper = object : ExploreByTouchHelper(this) {
        override fun getVirtualViewAt(x: Float, y: Float): Int =
            if (rounds.isEmpty()) ExploreByTouchHelper.INVALID_ID else nearest(x, y)

        override fun getVisibleVirtualViews(virtualViewIds: MutableList<Int>) {
            rounds.indices.forEach { virtualViewIds.add(it) }
        }

        override fun onPopulateNodeForVirtualView(
            virtualViewId: Int,
            node: AccessibilityNodeInfoCompat
        ) {
            node.contentDescription = describe(virtualViewId)
            val cell = cellBounds(virtualViewId)
            // Required by ExploreByTouchHelper even though the setter is deprecated.
            @Suppress("DEPRECATION")
            node.setBoundsInParent(
                Rect(cell.left.toInt(), cell.top.toInt(), cell.right.toInt(), cell.bottom.toInt())
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

    /** The number of pills, for tests. */
    internal val pillCount: Int get() = rounds.size

    /** The centre of pill [i], for tests. */
    internal fun pillCentre(i: Int): Pair<Float, Float> {
        val cell = cellBounds(i)
        return cell.centerX() to cell.centerY()
    }

    /** Shows [rounds], clearing any selection. [describe] is what TalkBack says for round `i`. */
    fun show(rounds: List<RoundStat>, describe: (Int) -> String) {
        this.rounds = rounds
        this.describe = describe
        selected = null
        requestLayout()
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

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val rows = (rounds.size + COLUMNS - 1) / COLUMNS
        val wanted = (paddingTop + paddingBottom + rows * cellHeight).toInt()
        setMeasuredDimension(
            getDefaultSize(suggestedMinimumWidth, widthMeasureSpec),
            resolveSize(wanted, heightMeasureSpec)
        )
    }

    private fun cellWidth(): Float = (width - paddingLeft - paddingRight) / COLUMNS.toFloat()

    /** The whole touch target of round [i]: a full row high, so it clears 48dp. */
    private fun cellBounds(i: Int): RectF {
        val w = cellWidth()
        val left = paddingLeft + (i % COLUMNS) * w
        val top = paddingTop + (i / COLUMNS) * cellHeight
        cellRect.set(left, top, left + w, top + cellHeight)
        return cellRect
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (rounds.isEmpty() || width <= 0) return
        canvas.save()
        canvas.clipRect(0f, 0f, width * reveal, height.toFloat())
        for (i in rounds.indices) drawPill(canvas, i)
        canvas.restore()
    }

    private fun drawPill(canvas: Canvas, i: Int) {
        val cell = cellBounds(i)
        val inset = pillGap / 2f
        val top = cell.centerY() - pillHeight / 2f
        pill.set(cell.left + inset, top, cell.right - inset, top + pillHeight)
        pillPath.rewind()
        pillPath.addRoundRect(pill, corner, corner, Path.Direction.CW)

        val parts = rounds[i].parts
        canvas.save()
        canvas.clipPath(pillPath)
        var x = pill.left
        for (k in parts.indices) {
            val part = parts[k]
            val segment = pill.width() * part.movement.target / schemeTotal
            val reached = (part.reps.toFloat() / part.movement.target).coerceIn(0f, 1f)
            if (reached > 0f) {
                fillPaint.color = segmentColours[k]
                canvas.drawRect(x, pill.top, x + segment * reached, pill.bottom, fillPaint)
            }
            // The seam between two movements, so a part-filled segment still reads as its own.
            if (k > 0) canvas.drawLine(x, pill.top, x, pill.bottom, dividerPaint)
            x += segment
        }
        canvas.restore()
        canvas.drawPath(pillPath, outlinePaint)
        if (i == selected) canvas.drawPath(pillPath, selectedPaint)
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (rounds.isEmpty()) return false
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
                if (dragging) scrubTo(e.x, e.y)
                return true
            }
            MotionEvent.ACTION_UP -> {
                if (!dragging) {
                    val i = nearest(e.x, e.y)
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

    private fun scrubTo(x: Float, y: Float) {
        val i = nearest(x, y)
        if (i != selected) {
            select(i)
            performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
        }
    }

    /** The round under a point, clamped to the grid so a touch in the margin still lands. */
    private fun nearest(x: Float, y: Float): Int {
        val rows = (rounds.size + COLUMNS - 1) / COLUMNS
        val column = ((x - paddingLeft) / cellWidth().coerceAtLeast(1f)).toInt().coerceIn(0, COLUMNS - 1)
        val row = ((y - paddingTop) / cellHeight).toInt().coerceIn(0, rows - 1)
        return (row * COLUMNS + column).coerceAtMost(rounds.size - 1)
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
        const val COLUMNS = 10
    }
}
