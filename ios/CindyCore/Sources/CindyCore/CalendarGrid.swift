import Foundation

/// Where a month's days sit in the calendar grid.
///
/// Drawing a day and finding the day under a finger use the one formula, and the layout can be
/// tested without a canvas. Port of `CalendarGrid.kt`.
public enum CalendarGrid {

    /// Blank cells before the 1st, given where the locale starts its week.
    public static func lead(_ month: YearMonth, firstDayOfWeek: DayOfWeek) -> Int {
        ((month.atDay(1).dayOfWeek.value - firstDayOfWeek.value) + 7) % 7
    }

    /// The date in a cell, or nil for the weekday header (row 0) and the blanks.
    public static func dateAt(_ month: YearMonth, firstDayOfWeek: DayOfWeek, col: Int, row: Int) -> LocalDate? {
        if row < 1 || !(0...6).contains(col) { return nil }
        let day = (row - 1) * 7 + col - lead(month, firstDayOfWeek: firstDayOfWeek) + 1
        return (1...month.lengthOfMonth).contains(day) ? month.atDay(day) : nil
    }
}
