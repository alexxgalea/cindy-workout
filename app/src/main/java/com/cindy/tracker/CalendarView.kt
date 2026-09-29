package com.cindy.tracker

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.AttributeSet
import android.view.MotionEvent
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
    private var streak: Set<LocalDate> = emptySet()

    /** Called with the date of a trained day the athlete taps; other cells do nothing. */
    var onDayTap: ((LocalDate) -> Unit)? = null

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

    /**
     * [streak] is the run of days to paint in the achievement colour; a trained day outside it
     * stays white, so the current run reads apart from the history behind it.
     */
    fun show(
        month: YearMonth,
        trained: Set<LocalDate>,
        today: LocalDate = LocalDate.now(),
        streak: Set<LocalDate> = emptySet()
    ) {
        this.month = month
        this.trained = trained
        this.today = today
        this.streak = streak
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

        // How far into the week the 1st falls, given where this locale starts its weeks.
        val lead = CalendarGrid.lead(month, firstDayOfWeek)

        for (dayOfMonth in 1..month.lengthOfMonth()) {
            val date = month.atDay(dayOfMonth)
            val index = lead + dayOfMonth - 1
            val cx = cell * ((index % 7) + 0.5f)
            val cy = cell * ((index / 7) + 1) + cell * 0.5f

            val didTrain = trained.contains(date)
            val isToday = date == today

            if (didTrain) {
                fill.color =
                    if (streak.contains(date)) context.getColor(R.color.achievement) else ACCENT
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

    /** A tap on a trained day opens it; without a listener the view stays inert. */
    override fun onTouchEvent(e: MotionEvent): Boolean {
        val listener = onDayTap ?: return super.onTouchEvent(e)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> return true
            MotionEvent.ACTION_UP -> {
                val cell = width / 7f
                val date = CalendarGrid.dateAt(
                    month, firstDayOfWeek, (e.x / cell).toInt(), (e.y / cell).toInt()
                )
                if (date != null && trained.contains(date)) {
                    listener(date)
                    performClick()
                }
                return true
            }
        }
        return super.onTouchEvent(e)
    }

    override fun performClick(): Boolean = super.performClick()
}
