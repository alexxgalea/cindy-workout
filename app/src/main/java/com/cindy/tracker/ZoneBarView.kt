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
 * One bar split by how long the heart rate spent in each [HeartZone], in the heart colour at five
 * rising opacities: the harder the zone, the stronger the pink, so the bar reads as effort without
 * a second hue to learn. Drawn by hand like [ProgressChartView], whose idiom this follows: paints
 * and paths are fields, nothing is allocated while drawing, the first data reveals left to right,
 * a tap selects a zone and a sideways drag scrubs across them while a vertical one is left to the
 * scroll view.
 *
 * A zone with no time has no width, and so no stop for TalkBack and nothing to select; the rows
 * under the bar still name all five, so a missing sliver is never a missing zone.
 */
class ZoneBarView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0
) : View(context, attrs, defStyle) {

    /** Reports the selected zone's index as it changes; null when it is cleared. */
    var onSelect: ((Int?) -> Unit)? = null

    /** The selected zone's index into the list given to [setZones], or null for none. */
    var selected: Int? = null
        private set

    // The data fields come first: [helper] below reads them, and property initialisers run top
    // to bottom.
    private var ms = LongArray(0)
    private var total = 0L
    private var descriptions: List<String> = emptyList()

    /** The zones with any time, in order: the bar's segments and TalkBack's stops. */
    private var shown = IntArray(0)

    /** Geometry, rebuilt by [layoutBar]. */
    private val bar = RectF()
    private var segLeft = FloatArray(0)
    private var segRight = FloatArray(0)
    private val clip = Path()
    private val segment = RectF()
    private var clipBuiltFor = 0f

    private var reveal = 1f
    private var revealAnimator: ValueAnimator? = null

    private val slop = ViewConfiguration.get(context).scaledTouchSlop
    private var downX = 0f
    private var downY = 0f
    private var dragging = false

    private val heart = context.getColor(R.color.heart)

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val gapPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = context.getColor(R.color.bg)
        style = Paint.Style.STROKE
        strokeWidth = context.dpf(GAP_DP)
    }

    /** One virtual view per zone that has time in it. */
    private val helper = object : ExploreByTouchHelper(this) {
        override fun getVirtualViewAt(x: Float, y: Float): Int {
            if (shown.isEmpty()) return ExploreByTouchHelper.INVALID_ID
            layoutBar()
            val zone = zoneAt(x)
            return shown.indexOf(zone)
        }

        override fun getVisibleVirtualViews(virtualViewIds: MutableList<Int>) {
            shown.indices.forEach { virtualViewIds.add(it) }
        }

        override fun onPopulateNodeForVirtualView(
            virtualViewId: Int,
            node: AccessibilityNodeInfoCompat
        ) {
            val zone = shown.getOrNull(virtualViewId)
            if (zone == null) {
                node.contentDescription = ""
                @Suppress("DEPRECATION")
                node.setBoundsInParent(Rect(0, 0, 1, 1))
                return
            }
            layoutBar()
            node.contentDescription = descriptions.getOrElse(zone) { "" }
            // A sliver of a zone is still a stop, so it is given the room a finger needs.
            val half = context.dp(24)
            val cx = ((segLeft[zone] + segRight[zone]) / 2f).toInt()
            val left = minOf(segLeft[zone].toInt(), cx - half)
            val right = maxOf(segRight[zone].toInt(), cx + half)
            // Required by ExploreByTouchHelper even though the setter is deprecated.
            @Suppress("DEPRECATION")
            node.setBoundsInParent(Rect(left, 0, right, height.coerceAtLeast(1)))
            node.addAction(AccessibilityNodeInfoCompat.ACTION_CLICK)
            node.isSelected = selected == zone
        }

        override fun onPerformActionForVirtualView(
            virtualViewId: Int,
            action: Int,
            arguments: Bundle?
        ): Boolean {
            if (action != AccessibilityNodeInfoCompat.ACTION_CLICK) return false
            val zone = shown.getOrNull(virtualViewId) ?: return false
            select(zone)
            return true
        }
    }

    init {
        ViewCompat.setAccessibilityDelegate(this, helper)
    }

    /** The number of stops, for tests. */
    internal val stopCount: Int get() = shown.size

    /** The x at the middle of [zone]'s segment, laying out first; for tests. */
    internal fun centreOf(zone: Int): Float {
        layoutBar()
        return (segLeft[zone] + segRight[zone]) / 2f
    }

    /**
     * Replaces everything drawn. [zones] are the five in order; [descriptions] is what TalkBack
     * says for each, by the same index. A selection that still has time in it is kept.
     */
    fun setZones(zones: List<ZoneTime>, descriptions: List<String>) {
        val firstData = total == 0L && zones.any { it.ms > 0L }
        ms = LongArray(zones.size) { zones[it].ms }
        total = ms.sum()
        this.descriptions = descriptions
        shown = ms.indices.filter { ms[it] > 0L }.toIntArray()
        segLeft = FloatArray(zones.size)
        segRight = FloatArray(zones.size)
        if (selected?.let { it !in ms.indices || ms[it] == 0L } == true) selected = null
        if (firstData) startReveal() else reveal = 1f
        helper.invalidateRoot()
        invalidate()
    }

    /** Selects [zone] (null clears), redraws, reports it and announces it. */
    fun select(zone: Int?) {
        selected = zone?.takeIf { it in ms.indices && ms[it] > 0L }
        invalidate()
        onSelect?.invoke(selected)
        val s = selected ?: return
        helper.sendEventForVirtualView(shown.indexOf(s), AccessibilityEvent.TYPE_VIEW_SELECTED)
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
        setMeasuredDimension(
            getDefaultSize(suggestedMinimumWidth, widthMeasureSpec),
            resolveSize(paddingTop + paddingBottom + context.dp(TOUCH_DP), heightMeasureSpec)
        )
    }

    /** The bar and every segment's span. Cheap; every draw and touch calls it. */
    private fun layoutBar() {
        val barHeight = context.dpf(BAR_DP)
        val top = paddingTop + ((height - paddingTop - paddingBottom) - barHeight) / 2f
        bar.set(paddingLeft.toFloat(), top, (width - paddingRight).toFloat(), top + barHeight)
        if (total <= 0L) return
        var x = bar.left
        for (z in ms.indices) {
            segLeft[z] = x
            x += bar.width() * ms[z] / total
            segRight[z] = x
        }
        // Only rebuilt when the bar's size changed, so a frame of a reveal allocates nothing.
        val key = bar.width() * 31f + bar.height()
        if (key != clipBuiltFor) {
            clipBuiltFor = key
            clip.rewind()
            val r = bar.height() / 2f
            clip.addRoundRect(bar, r, r, Path.Direction.CW)
        }
    }

    /** The zone under [x]: the one whose segment holds it, else the nearest that has time. */
    private fun zoneAt(x: Float): Int {
        var best = -1
        var bestDistance = Float.MAX_VALUE
        for (i in shown.indices) {
            val z = shown[i]
            val d = when {
                x < segLeft[z] -> segLeft[z] - x
                x > segRight[z] -> x - segRight[z]
                else -> 0f
            }
            if (d < bestDistance) {
                bestDistance = d
                best = z
            }
        }
        return best
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        layoutBar()
        if (total <= 0L || bar.width() <= 0f) return

        canvas.save()
        canvas.clipPath(clip)
        canvas.clipRect(0f, 0f, bar.left + bar.width() * reveal, height.toFloat())
        val chosen = selected
        for (i in shown.indices) {
            val z = shown[i]
            // Everything else steps back while one zone is held, so the held one is what is read.
            val dim = if (chosen == null || chosen == z) 1f else DIM
            fillPaint.color = heart
            fillPaint.alpha = (ALPHA[z.coerceIn(0, ALPHA.lastIndex)] * dim * 255f).toInt()
            segment.set(segLeft[z], bar.top, segRight[z], bar.bottom)
            canvas.drawRect(segment, fillPaint)
            // A thin gap in the page's own black between neighbours, so five tints stay five.
            if (i > 0) canvas.drawLine(segLeft[z], bar.top, segLeft[z], bar.bottom, gapPaint)
        }
        canvas.restore()
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (total <= 0L) return false
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
                    layoutBar()
                    val zone = zoneAt(e.x)
                    // A second tap on the held zone lets it go, as a second tap on a point does.
                    select(if (zone == selected) null else zone)
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
        layoutBar()
        val zone = zoneAt(x)
        if (zone == selected) return
        select(zone)
        performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
    }

    override fun dispatchHoverEvent(event: MotionEvent): Boolean =
        helper.dispatchHoverEvent(event) || super.dispatchHoverEvent(event)

    override fun dispatchKeyEvent(event: KeyEvent): Boolean =
        helper.dispatchKeyEvent(event) || super.dispatchKeyEvent(event)

    override fun onFocusChanged(gain: Boolean, direction: Int, previous: Rect?) {
        super.onFocusChanged(gain, direction, previous)
        helper.onFocusChanged(gain, direction, previous)
    }

    internal companion object {
        const val BAR_DP = 28f
        const val GAP_DP = 2f

        /** The height a finger is given, whatever the bar's own. */
        const val TOUCH_DP = 48

        /** How far the unheld zones step back while one is held. */
        const val DIM = 0.4f

        /**
         * The heart colour's opacity in each zone, lowest to highest. The first is still plainly
         * visible against black; the steps are even enough to be told apart side by side.
         */
        val ALPHA = floatArrayOf(0.26f, 0.42f, 0.6f, 0.8f, 1f)
    }
}
