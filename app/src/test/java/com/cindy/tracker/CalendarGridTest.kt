package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth

class CalendarGridTest {

    /** September 2026 starts on a Tuesday and has 30 days. */
    private val september = YearMonth.of(2026, 9)

    @Test
    fun `a week that starts on Monday leaves one blank before a Tuesday`() {
        assertEquals(1, CalendarGrid.lead(september, DayOfWeek.MONDAY))
    }

    @Test
    fun `a week that starts on Sunday leaves two blanks before a Tuesday`() {
        assertEquals(2, CalendarGrid.lead(september, DayOfWeek.SUNDAY))
    }

    @Test
    fun `cells map to dates with a Monday start`() {
        val first = DayOfWeek.MONDAY
        assertNull(CalendarGrid.dateAt(september, first, 0, 1))
        assertEquals(LocalDate.of(2026, 9, 1), CalendarGrid.dateAt(september, first, 1, 1))
        assertEquals(LocalDate.of(2026, 9, 30), CalendarGrid.dateAt(september, first, 2, 5))
        assertNull(CalendarGrid.dateAt(september, first, 3, 5))
    }

    @Test
    fun `cells map to dates with a Sunday start`() {
        assertEquals(
            LocalDate.of(2026, 9, 1),
            CalendarGrid.dateAt(september, DayOfWeek.SUNDAY, 2, 1)
        )
    }

    @Test
    fun `the weekday header and cells beyond the grid are not dates`() {
        assertNull(CalendarGrid.dateAt(september, DayOfWeek.MONDAY, 1, 0))
        assertNull(CalendarGrid.dateAt(september, DayOfWeek.MONDAY, 7, 1))
        assertNull(CalendarGrid.dateAt(september, DayOfWeek.MONDAY, -1, 1))
    }
}
