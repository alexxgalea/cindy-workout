package com.cindy.tracker

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.TextStyle
import java.time.temporal.WeekFields
import java.util.Locale

/**
 * A month, with the days that were trained filled in.
 *
 * The point is the shape of the thing: a streak reads as a run of filled cells, and a week off
 * reads as a hole, in a way that no number can. No library — it is a grid of circles.
 */
class CalendarView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0
) : View(context, attrs, defStyle) {

    private companion object {
        /** A trained day is filled white; everything else is the label ramp. */
        val ACCENT = Color.WHITE
        val ON_SURFACE = Color.WHITE
        val DIM = Color.parseColor("#9EEBEBF5")
        val FAINT = Color.parseColor("#2EEBEBF5")
        const val WEEKS_SHOWN = 6
    }

    private var month: YearMonth = YearMonth.now()
    private var trained: Set<LocalDate> = emptySet()
    private var today: LocalDate = LocalDate.now()

    /** Monday in most of the world, Sunday in some of it. Ask the locale rather than assume. */
    private val firstDayOfWeek: DayOfWeek =
        WeekFields.of(Locale.getDefault()).firstDayOfWeek

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 2f * resources.displayMetrics.density
    }
    private val dayText = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER
        textSize = 13f * resources.displayMetrics.scaledDensity
    }
    private val headerText = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = DIM
        textAlign = Paint.Align.CENTER
        textSize = 11f * resources.displayMetrics.scaledDensity
    }

    fun show(month: YearMonth, trained: Set<LocalDate>, today: LocalDate = LocalDate.now()) {
        this.month = month
        this.trained = trained
        this.today = today
        contentDescription = describe()
        invalidate()
    }

    private fun describe(): String {
        val name = month.month.getDisplayName(TextStyle.FULL, Locale.getDefault())
        val inMonth = trained.count { YearMonth.from(it) == month }
        return "$name ${month.year}, trained on $inMonth day${if (inMonth == 1) "" else "s"}"
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val cell = width / 7f
        // A header row plus six week rows covers every month layout without reflowing.
        val height = (cell * (WEEKS_SHOWN + 1)).toInt()
        setMeasuredDimension(width, height)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val cell = width / 7f
        val radius = cell * 0.34f

        // Weekday initials, in the locale's own week order.
        for (i in 0 until 7) {
            val day = firstDayOfWeek.plus(i.toLong())
            val label = day.getDisplayName(TextStyle.NARROW, Locale.getDefault())
            canvas.drawText(
                label,
                cell * (i + 0.5f),
                cell * 0.62f,
                headerText
            )
        }

        val first = month.atDay(1)
        // How far into the week the 1st falls, given where this locale starts its weeks.
        val lead = ((first.dayOfWeek.value - firstDayOfWeek.value) + 7) % 7

        for (dayOfMonth in 1..month.lengthOfMonth()) {
            val date = month.atDay(dayOfMonth)
            val index = lead + dayOfMonth - 1
            val cx = cell * ((index % 7) + 0.5f)
            val cy = cell * ((index / 7) + 1) + cell * 0.5f

            val didTrain = trained.contains(date)
            val isToday = date == today

            if (didTrain) {
                fill.color = ACCENT
                canvas.drawCircle(cx, cy, radius, fill)
            } else if (isToday) {
                ring.color = ACCENT
                canvas.drawCircle(cx, cy, radius, ring)
            }

            dayText.color = when {
                didTrain -> Color.BLACK
                isToday -> ACCENT
                date.isAfter(today) -> FAINT
                else -> ON_SURFACE
            }
            dayText.isFakeBoldText = didTrain || isToday
            // Centre the digits on the circle rather than on the text baseline.
            val offset = (dayText.descent() + dayText.ascent()) / 2f
            canvas.drawText("$dayOfMonth", cx, cy - offset, dayText)
        }
    }
}
