package com.cindy.tracker

import android.content.Context
import android.text.TextPaint
import android.util.AttributeSet
import android.util.TypedValue
import android.view.View
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
    }
}
