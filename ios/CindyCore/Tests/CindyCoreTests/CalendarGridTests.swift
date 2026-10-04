import XCTest
import CindyCore

/// Where a month's days sit in the grid. Port of `CalendarGridTest.kt`.
final class CalendarGridTests: XCTestCase {

    /// September 2026 starts on a Tuesday and has 30 days.
    private let september = YearMonth(2026, 9)

    /// a week that starts on Monday leaves one blank before a Tuesday
    func testAWeekThatStartsOnMondayLeavesOneBlankBeforeATuesday() {
        XCTAssertEqual(CalendarGrid.lead(september, firstDayOfWeek: .monday), 1)
    }

    /// a week that starts on Sunday leaves two blanks before a Tuesday
    func testAWeekThatStartsOnSundayLeavesTwoBlanksBeforeATuesday() {
        XCTAssertEqual(CalendarGrid.lead(september, firstDayOfWeek: .sunday), 2)
    }

    /// cells map to dates with a Monday start
    func testCellsMapToDatesWithAMondayStart() {
        let first = DayOfWeek.monday
        XCTAssertNil(CalendarGrid.dateAt(september, firstDayOfWeek: first, col: 0, row: 1))
        XCTAssertEqual(CalendarGrid.dateAt(september, firstDayOfWeek: first, col: 1, row: 1), LocalDate(2026, 9, 1))
        XCTAssertEqual(CalendarGrid.dateAt(september, firstDayOfWeek: first, col: 2, row: 5), LocalDate(2026, 9, 30))
        XCTAssertNil(CalendarGrid.dateAt(september, firstDayOfWeek: first, col: 3, row: 5))
    }

    /// cells map to dates with a Sunday start
    func testCellsMapToDatesWithASundayStart() {
        XCTAssertEqual(CalendarGrid.dateAt(september, firstDayOfWeek: .sunday, col: 2, row: 1), LocalDate(2026, 9, 1))
    }

    /// the weekday header and cells beyond the grid are not dates
    func testTheWeekdayHeaderAndCellsBeyondTheGridAreNotDates() {
        XCTAssertNil(CalendarGrid.dateAt(september, firstDayOfWeek: .monday, col: 1, row: 0))
        XCTAssertNil(CalendarGrid.dateAt(september, firstDayOfWeek: .monday, col: 7, row: 1))
        XCTAssertNil(CalendarGrid.dateAt(september, firstDayOfWeek: .monday, col: -1, row: 1))
    }

    /// the first column is a column: a month that starts on the first day of the week fills it
    func testTheFirstColumnIsAColumn() {
        // June 2026 starts on a Monday.
        let june = YearMonth(2026, 6)
        XCTAssertEqual(CalendarGrid.lead(june, firstDayOfWeek: .monday), 0)
        XCTAssertEqual(CalendarGrid.dateAt(june, firstDayOfWeek: .monday, col: 0, row: 1), LocalDate(2026, 6, 1))
        XCTAssertEqual(CalendarGrid.dateAt(june, firstDayOfWeek: .monday, col: 6, row: 1), LocalDate(2026, 6, 7))
    }
}
