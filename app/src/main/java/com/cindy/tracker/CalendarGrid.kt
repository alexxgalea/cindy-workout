package com.cindy.tracker

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth

/**
 * Where a month's days sit in the calendar grid.
 *
 * Pulled out of [CalendarView] so that drawing a day and finding the day under a finger use the
 * one formula, and so the layout can be tested without a canvas.
 */
object CalendarGrid {

    /** Blank cells before the 1st, given where the locale starts its week. */
    fun lead(month: YearMonth, firstDayOfWeek: DayOfWeek): Int =
        ((month.atDay(1).dayOfWeek.value - firstDayOfWeek.value) + 7) % 7

    /** The date in a cell, or null for the weekday header (row 0) and the blanks. */
    fun dateAt(month: YearMonth, firstDayOfWeek: DayOfWeek, col: Int, row: Int): LocalDate? {
        if (row < 1 || col !in 0..6) return null
        val day = (row - 1) * 7 + col - lead(month, firstDayOfWeek) + 1
        return if (day in 1..month.lengthOfMonth()) month.atDay(day) else null
    }
}
