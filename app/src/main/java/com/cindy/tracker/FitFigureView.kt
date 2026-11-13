package com.cindy.tracker

import android.content.Context
import android.graphics.Canvas
import android.graphics.Rect
import android.graphics.RectF
import android.text.TextPaint
import android.util.AttributeSet
import android.util.TypedValue
import android.view.View
import android.view.animation.PathInterpolator
import androidx.appcompat.widget.AppCompatTextView
import kotlin.math.abs
import kotlin.math.min

/**
 * One line of text that is as big as its style says, and no bigger than its box is tall, and
 * shrinks when the box is too narrow, so it is whole or smaller, never cut.
 *
 * It is the camera screen's figure ("3/5"). The platform's own auto-sizing cannot do this one's
 * job: it fits the *line* into the box's height, and a line of Inter at 96sp is about 1.2 em tall
 * even with font padding off, so it would settle at about 80sp inside a 96dp zone. The glyphs of
 * a figure sit in the middle of that line and use about 0.73 em, so here the size is simply held
 * to the box's height, one em, and the line's empty ends are clipped.
 *
 * The style's size is the ceiling. On the largest system text that ceiling is also held to the
 * height, so the figure cannot outgrow the band however the athlete has set their type.
 *
 * It can also roll: the digits of the count that changed slide out and in, each in its own cell,
 * while the rest of the figure stands still. The text already holds the new value while it
 * rolls; the roll is only drawn over it, and [ScoreboardFigure] decides when and which way.
 */
class FitFigureView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = android.R.attr.textViewStyle
) : AppCompatTextView(context, attrs, defStyleAttr) {

    /** TextView calls [onTextChanged] from its own constructor, before this class is set up. */
    private var ceiling = 0f
    private val floor = MIN_DP * resources.displayMetrics.density

    init {
        ceiling = textSize
    }

    /** Which way a roll moves the digits: up for a banked rep, down for one taken back. */
    enum class Roll { UP, DOWN }

    /** A digit cell that is rolling: where it is in the text, and what it showed before. */
    private class Cell(val index: Int, val was: Char?)

    private var roll: Roll? = null
    private var cells: List<Cell> = emptyList()
    private var rolled = 0f
    private val digit = Rect()
    private val box = RectF()

    /** Which way the count's digits are rolling, or null while they stand still. */
    val rolling: Roll? get() = roll

    /**
     * Starts rolling the count from [from] to [to], the count the view now shows at the start of
     * its text. Digits line up from the right, so 9 to 10 rolls a 1 in and the 9 over to a 0,
     * and 10 to 9 rolls the 0 over to a 9.
     */
    fun startRoll(from: String, to: String, direction: Roll) {
        cells = to.indices.mapNotNull { i ->
            val was = from.getOrNull(from.length - to.length + i)
            if (was == to[i]) null else Cell(i, was)
        }
        roll = if (cells.isEmpty()) null else direction
        rolled = 0f
        invalidate()
    }

    /** Moves the roll on to [fraction] of its way, 0 to 1, before its easing. */
    fun rollTo(fraction: Float) {
        if (roll == null) return
        rolled = fraction.coerceIn(0f, 1f)
        invalidate()
    }

    /** Ends the roll: the count stands still at the value the text already holds. */
    fun endRoll() {
        if (roll == null) return
        roll = null
        cells = emptyList()
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        val direction = roll
        val layout = layout
        if (direction == null || layout == null || cells.isEmpty()) return super.onDraw(canvas)
        val text = text
        val left = totalPaddingLeft.toFloat()
        val baseline = (totalPaddingTop + layout.getLineBaseline(0)).toFloat()
        // Each cell is one em tall and centred on the digits, so a digit one em off is out of it.
        paint.getTextBounds("0", 0, 1, digit)
        val em = textSize
        val middle = baseline + digit.exactCenterY()
        fun cell(c: Cell): RectF {
            val end = if (c.index + 1 < text.length) layout.getPrimaryHorizontal(c.index + 1) else layout.getLineRight(0)
            box.set(left + layout.getPrimaryHorizontal(c.index), middle - em / 2, left + end, middle + em / 2)
            return box
        }

        // The figure as it stands, without the cells that are rolling.
        canvas.save()
        for (c in cells) {
            val r = cell(c)
            canvas.clipOutRect(r.left, 0f, r.right, height.toFloat())
        }
        super.onDraw(canvas)
        canvas.restore()

        // Each rolling cell: the old digit leaving, the new one arriving behind it.
        val eased = EASE.getInterpolation(rolled)
        val away = if (direction == Roll.UP) -em else em
        paint.color = currentTextColor
        for (c in cells) {
            val r = cell(c)
            canvas.save()
            canvas.clipRect(r)
            val was = c.was
            if (was != null && was != ' ') canvas.drawText(was.toString(), r.left, baseline + eased * away, paint)
            canvas.drawText(text, c.index, c.index + 1, r.left, baseline - (1f - eased) * away, paint)
            canvas.restore()
        }
    }

    /**
     * Sets the size the figure is as big as when it fits, in sp, as the style's own would. The
     * screen draws the figure at 56sp for an athlete at the phone and at 96sp for one at the bar.
     */
    fun ceilingSp(sp: Float) {
        val next = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, sp, resources.displayMetrics)
        if (abs(next - ceiling) < 0.01f) return
        ceiling = next
        fit(width - paddingLeft - paddingRight, height - paddingTop - paddingBottom)
        requestLayout()
    }

    private fun fit(width: Int, height: Int) {
        if (ceiling == 0f || width <= 0) return
        val text = text
        val probe = TextPaint(paint)
        var size = if (height > 0) min(ceiling, height.toFloat()) else ceiling
        while (size > floor) {
            probe.textSize = size
            if (probe.measureText(text, 0, text.length) <= width) break
            size -= resources.displayMetrics.density
        }
        size = size.coerceAtLeast(floor)
        if (abs(textSize - size) > 0.01f) setTextSize(TypedValue.COMPLEX_UNIT_PX, size)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val height =
            if (View.MeasureSpec.getMode(heightMeasureSpec) == View.MeasureSpec.EXACTLY) {
                View.MeasureSpec.getSize(heightMeasureSpec) - paddingTop - paddingBottom
            } else {
                0
            }
        fit(View.MeasureSpec.getSize(widthMeasureSpec) - paddingLeft - paddingRight, height)
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }

    override fun onTextChanged(text: CharSequence?, start: Int, lengthBefore: Int, lengthAfter: Int) {
        super.onTextChanged(text, start, lengthBefore, lengthAfter)
        // A box with a fixed size is not measured again when its text changes, so fit it here.
        fit(width - paddingLeft - paddingRight, height - paddingTop - paddingBottom)
    }

    private companion object {
        const val MIN_DP = 24f

        /** The mock's cubic-bezier(.2, .8, .2, 1): quick off the mark, settling into place. */
        val EASE = PathInterpolator(0.2f, 0.8f, 0.2f, 1f)
    }
}
