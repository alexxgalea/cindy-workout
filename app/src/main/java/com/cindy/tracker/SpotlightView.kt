package com.cindy.tracker

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.graphics.Rect
import android.graphics.RectF
import android.util.AttributeSet
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.view.ViewCompat
import kotlin.math.min

/**
 * A tour of the camera screen: the screen dimmed, one control left bright, and a card that says
 * what it is for.
 *
 * It exists because the HUD is icons, and an icon is a thing you have to already know. The pages
 * before the camera say what Cindy is; this says what each button on the screen does, pointing at
 * the real one rather than describing it, so there is no mapping from a picture of a control to the
 * control to get wrong. It is taken once, on the first run, and again whenever Help is asked.
 *
 * It is a view over the camera screen and not a screen of its own, because the camera is what it
 * points at and a separate activity would have to put the HUD back on the picture. While it is
 * showing it takes every touch: a tap anywhere moves on, so nothing it highlights can be pressed
 * by accident, START least of all.
 *
 * Where the card goes is [SpotlightMath]'s decision, so that it can be tested.
 */
class SpotlightView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : FrameLayout(context, attrs) {

    /** One control to point at, and what to say about it. */
    class Step(val target: View, val title: String, val body: String)

    private companion object {
        /** The dimming: dark enough to hold the eye on one control, light enough to see the room. */
        val DIM = 0xC8000000.toInt()
    }

    private var steps: List<Step> = emptyList()
    private var index = 0
    private var onDone: (() -> Unit)? = null

    private val hole = RectF()
    private val cutout = Path()
    private val dim = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = DIM }
    private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = context.getColor(R.color.label)
        strokeWidth = context.dpf(2f)
    }

    private val title: TextView
    private val body: TextView
    private val next: TextView
    private val skip: TextView
    private val card: LinearLayout

    init {
        setWillNotDraw(false)
        visibility = GONE
        // Swallows every touch while showing, and a tap on the dimmed screen moves on.
        isClickable = true
        setOnClickListener { advance() }

        title = context.styledText(R.style.Cindy_Headline)
        body = context.styledText(R.style.Cindy_Callout).apply {
            setTextColor(context.getColor(R.color.label_body))
            setPadding(0, context.dp(6), 0, 0)
        }
        skip = context.styledText(R.style.Cindy_Eyebrow, "SKIP TOUR").apply {
            setTextColor(context.getColor(R.color.label_secondary))
            gravity = Gravity.CENTER_VERTICAL
            minHeight = context.dp(48)
            setOnClickListener { finish() }
            describeAsButton("Skip the tour")
        }
        next = context.styledText(R.style.Cindy_Button_Small, "NEXT").apply {
            setTextColor(context.getColor(R.color.on_primary))
            setBackgroundResource(R.drawable.btn_primary)
            gravity = Gravity.CENTER
            minWidth = context.dp(96)
            setPadding(context.dp(22), 0, context.dp(22), 0)
            setOnClickListener { advance() }
            describeAsButton()
        }
        val footer = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, context.dp(8), 0, 0)
            addView(skip, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(next, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, context.dp(44)))
        }
        card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundResource(R.drawable.glass_panel)
            setPadding(context.dp(20), context.dp(18), context.dp(20), context.dp(10))
            // Part of the dimmed screen as far as touch goes: a tap on the text moves on too.
            isClickable = true
            setOnClickListener { advance() }
            ViewCompat.setAccessibilityPaneTitle(this, "Tour")
            addView(title)
            addView(body)
            addView(footer)
        }
        addView(card, LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            marginStart = context.dp(16)
            marginEnd = context.dp(16)
        })
    }

    /** Whether the tour is on the screen. */
    val isShowing: Boolean get() = onDone != null

    /** How many controls the tour is pointing at, once any that are not showing are left out. */
    val stepCount: Int get() = steps.size

    /** The control it is pointing at now, from zero. */
    val stepIndex: Int get() = index

    /** The bright window around the current control, in this view's own coordinates. */
    val holeBounds: RectF get() = RectF(hole)

    /** Where the card sits, in this view's own coordinates. */
    val captionBounds: Rect get() = Rect(card.left, card.top, card.right, card.bottom)

    /**
     * Starts the tour at the first of [candidates] that is showing. [done] is called once, when
     * the tour is finished or skipped, and immediately if nothing is left to point at.
     *
     * A control that is hidden, or that has no size yet, is left out rather than lit as an empty
     * hole: the tour is for what the athlete can see.
     */
    fun start(candidates: List<Step>, done: () -> Unit) {
        val showing = candidates.filter { isShowable(it.target) }
        if (showing.isEmpty()) {
            done()
            return
        }
        steps = showing
        index = 0
        onDone = done
        visibility = VISIBLE
        render()
    }

    /** Ends the tour where it is. */
    fun skip() = finish()

    private fun advance() {
        if (index < steps.lastIndex) {
            index++
            render()
        } else {
            finish()
        }
    }

    private fun finish() {
        val done = onDone ?: return
        onDone = null
        steps = emptyList()
        visibility = GONE
        done()
    }

    private fun render() {
        val step = steps[index]
        title.text = step.title
        body.text = step.body
        next.text = if (index == steps.lastIndex) "DONE" else "NEXT"
        requestLayout()
        invalidate()
        // Said rather than left to be found: a screen reader cannot see where the light has gone.
        announceForAccessibility("${step.title}. ${step.body}")
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        super.onLayout(changed, l, t, r, b)
        if (steps.isEmpty()) return
        val width = (r - l).toFloat()
        val height = (b - t).toFloat()

        val target = steps[index].target
        val origin = originIn(parent as? View ?: return, target)
        val pad = context.dpf(8f)
        hole.set(
            origin.x - l - pad,
            origin.y - t - pad,
            origin.x - l + target.width + pad,
            origin.y - t + target.height + pad
        )
        hole.intersect(0f, 0f, width, height)

        val top = SpotlightMath.captionTop(
            hole.top, hole.bottom, card.measuredHeight.toFloat(), height,
            gap = context.dpf(14f), margin = context.dpf(16f)
        ).toInt()
        card.layout(card.left, top, card.right, top + card.measuredHeight)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (steps.isEmpty()) return
        // Everything but the hole: two shapes, filled where exactly one of them is.
        cutout.reset()
        cutout.fillType = Path.FillType.EVEN_ODD
        cutout.addRect(0f, 0f, width.toFloat(), height.toFloat(), Path.Direction.CW)
        val radius = min(context.dpf(18f), min(hole.width(), hole.height()) / 2f)
        cutout.addRoundRect(hole, radius, radius, Path.Direction.CW)
        canvas.drawPath(cutout, dim)
        canvas.drawRoundRect(hole, radius, radius, ring)
    }

    /**
     * Where [view] is inside [ancestor], by adding up the offsets between them.
     *
     * Not `getLocationInWindow`, which answers 0, 0 for a view that is not attached to a window
     * and so could not be tested, and which would be answering a different question besides:
     * this view fills its parent, so its coordinates are the parent's.
     */
    private fun originIn(ancestor: View, view: View): PointF {
        var x = 0f
        var y = 0f
        var current: View = view
        while (current !== ancestor) {
            val above = current.parent as? View ?: break
            x += current.left + current.translationX - above.scrollX
            y += current.top + current.translationY - above.scrollY
            current = above
        }
        return PointF(x, y)
    }

    /** Whether [target] and everything above it is visible, and it has been given a size. */
    private fun isShowable(target: View): Boolean {
        var current: View? = target
        while (current != null) {
            if (current.visibility != View.VISIBLE) return false
            current = current.parent as? View
        }
        return target.width > 0 && target.height > 0
    }
}
