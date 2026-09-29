package com.cindy.tracker

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.os.Bundle
import android.util.AttributeSet
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import androidx.core.view.ViewCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import androidx.customview.widget.ExploreByTouchHelper
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.time.temporal.WeekFields
import java.util.Locale
import kotlin.math.hypot

/**
 * A month, with the days that were trained filled in.
 *
 * The point is the shape of the thing: a streak reads as a run of filled cells, and a week off
 * reads as a hole, in a way that no number can. No library — it is a grid of circles.
 *
 * Each trained day is also its own TalkBack stop, through [ExploreByTouchHelper], because a
 * canvas has no children to focus; the id of a virtual view is the day of the month.
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
        val SPOKEN_DATE: DateTimeFormatter = DateTimeFormatter.ofPattern("EEEE d MMMM", Locale.US)
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

    private val slop = ViewConfiguration.get(context).scaledTouchSlop
    private var downX = 0f
    private var downY = 0f

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

    /** One virtual view per trained day of the shown month, so TalkBack can open it. */
    private val helper = object : ExploreByTouchHelper(this) {
        override fun getVirtualViewAt(x: Float, y: Float): Int {
            val cell = width / 7f
            val date = CalendarGrid.dateAt(
                month, firstDayOfWeek, (x / cell).toInt(), (y / cell).toInt()
            )
            return if (date != null && trained.contains(date)) {
                date.dayOfMonth
            } else {
                ExploreByTouchHelper.INVALID_ID
            }
        }

        override fun getVisibleVirtualViews(virtualViewIds: MutableList<Int>) {
            trained.filter { YearMonth.from(it) == month }
                .sorted()
                .forEach { virtualViewIds.add(it.dayOfMonth) }
        }

        override fun onPopulateNodeForVirtualView(
            virtualViewId: Int,
            node: AccessibilityNodeInfoCompat
        ) {
            val date = month.atDay(virtualViewId)
            val spoken = SPOKEN_DATE.format(date) + ", trained" +
                if (streak.contains(date)) ", in your current streak" else ""
            node.contentDescription = spoken
            node.className = "android.widget.Button"
            val cell = width / 7f
            val index = CalendarGrid.lead(month, firstDayOfWeek) + virtualViewId - 1
            val left = (cell * (index % 7)).toInt()
            val top = (cell * (index / 7 + 1)).toInt()
            // Required by ExploreByTouchHelper even though the setter is deprecated.
            @Suppress("DEPRECATION")
            node.setBoundsInParent(Rect(left, top, (left + cell).toInt(), (top + cell).toInt()))
            if (onDayTap != null) node.addAction(AccessibilityNodeInfoCompat.ACTION_CLICK)
        }

        override fun onPerformActionForVirtualView(
            virtualViewId: Int,
            action: Int,
            arguments: Bundle?
        ): Boolean {
            if (action != AccessibilityNodeInfoCompat.ACTION_CLICK) return false
            val listener = onDayTap ?: return false
            listener(month.atDay(virtualViewId))
            return true
        }
    }

    init {
        ViewCompat.setAccessibilityDelegate(this, helper)
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
        helper.invalidateRoot()
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

    /**
     * A tap on a trained day opens it; without a listener the view stays inert. A finger that
     * travelled further than the touch slop was a drag, not a tap, so it opens nothing.
     */
    override fun onTouchEvent(e: MotionEvent): Boolean {
        val listener = onDayTap ?: return super.onTouchEvent(e)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = e.x
                downY = e.y
                return true
            }
            MotionEvent.ACTION_UP -> {
                if (hypot(e.x - downX, e.y - downY) >= slop) return true
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
            MotionEvent.ACTION_CANCEL -> return true
        }
        return super.onTouchEvent(e)
    }

    override fun performClick(): Boolean = super.performClick()
    override fun dispatchHoverEvent(event: MotionEvent): Boolean =
        helper.dispatchHoverEvent(event) || super.dispatchHoverEvent(event)

    override fun dispatchKeyEvent(event: KeyEvent): Boolean =
        helper.dispatchKeyEvent(event) || super.dispatchKeyEvent(event)

    override fun onFocusChanged(gain: Boolean, direction: Int, previous: Rect?) {
        super.onFocusChanged(gain, direction, previous)
        helper.onFocusChanged(gain, direction, previous)
    }
}
