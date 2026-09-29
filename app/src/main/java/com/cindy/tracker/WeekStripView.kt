package com.cindy.tracker

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.util.AttributeSet
import android.util.TypedValue
import android.view.View
import androidx.core.content.res.ResourcesCompat
import java.time.LocalDate
import java.time.format.TextStyle
import java.util.Locale
import kotlin.math.min

/**
 * One week as seven circles, so the athlete sees at a glance which days they trained.
 *
 * Trained days are filled in the earned colour; a day still to come is a small dot, so a week
 * in progress never reads as a week of failures.
 */
class WeekStripView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0
) : View(context, attrs, defStyle) {

    private var weekStart: LocalDate = LocalDate.now()
    private var trained: Set<LocalDate> = emptySet()
    private var today: LocalDate = LocalDate.now()

    private val initialPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = context.getColor(R.color.label_tertiary)
        textAlign = Paint.Align.CENTER
        textSize = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP, 11f, resources.displayMetrics
        )
        typeface = ResourcesCompat.getFont(context, R.font.manrope_semibold)
    }
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }

    fun show(weekStart: LocalDate, trained: Set<LocalDate>, today: LocalDate) {
        this.weekStart = weekStart
        this.trained = trained
        this.today = today
        contentDescription = describe()
        invalidate()
    }

    private fun describe(): String {
        val days = (0L until 7L).map { weekStart.plusDays(it) }.filter { it in trained }
            .map { it.dayOfWeek.getDisplayName(TextStyle.FULL, Locale.US) }
        return when (days.size) {
            0 -> "This week, no sessions yet"
            1 -> "This week, trained on ${days[0]}"
            else -> "This week, trained on ${days.dropLast(1).joinToString(", ")} " +
                "and ${days.last()}"
        }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), context.dp(56))
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val column = width / 7f
        val radius = min(column * 0.30f, context.dpf(14f))
        val cy = context.dpf(36f)
        for (i in 0 until 7) {
            val date = weekStart.plusDays(i.toLong())
            val cx = column * (i + 0.5f)
            val initial = date.dayOfWeek.getDisplayName(TextStyle.NARROW, Locale.getDefault())
            canvas.drawText(initial, cx, context.dpf(12f), initialPaint)

            val didTrain = date in trained
            when {
                didTrain -> {
                    fill.color = context.getColor(R.color.achievement)
                    canvas.drawCircle(cx, cy, radius, fill)
                }
                date == today -> {
                    ring.color = context.getColor(R.color.label)
                    ring.strokeWidth = context.dpf(2f)
                    canvas.drawCircle(cx, cy, radius, ring)
                }
                date.isBefore(today) -> {
                    ring.color = context.getColor(R.color.label_quaternary)
                    ring.strokeWidth = context.dpf(1.5f)
                    canvas.drawCircle(cx, cy, radius, ring)
                }
                else -> {
                    fill.color = context.getColor(R.color.label_quaternary)
                    canvas.drawCircle(cx, cy, context.dpf(2f), fill)
                }
            }
            // Today, once trained, is marked by a ring around the fill.
            if (didTrain && date == today) {
                ring.color = context.getColor(R.color.label)
                ring.strokeWidth = context.dpf(2f)
                canvas.drawCircle(cx, cy, radius + context.dpf(3f), ring)
            }
        }
    }
}
