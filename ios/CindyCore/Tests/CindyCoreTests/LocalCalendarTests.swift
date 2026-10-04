import XCTest
import CindyCore

/// The calendar types the streaks stand on. No Kotlin test of its own: `java.time` is the JDK's.
/// Written for the port, and the figures in it were checked against `java.time` itself.
final class LocalCalendarTests: XCTestCase {

    func testEpochDayRoundTripsAcrossFourCenturies() {
        var day = LocalDate(1900, 1, 1).epochDay
        let end = LocalDate(2400, 12, 31).epochDay
        while day <= end {
            XCTAssertEqual(LocalDate(epochDay: day).epochDay, day)
            day += 37
        }
        XCTAssertEqual(LocalDate(1970, 1, 1).epochDay, 0)
        XCTAssertEqual(LocalDate(epochDay: 0), LocalDate(1970, 1, 1))
        XCTAssertEqual(LocalDate(1969, 12, 31).epochDay, -1)
        XCTAssertEqual(LocalDate(2026, 9, 9).epochDay, 20_705)
    }

    func testTheDayOfTheWeek() {
        XCTAssertEqual(LocalDate(1970, 1, 1).dayOfWeek, .thursday)
        XCTAssertEqual(LocalDate(2026, 9, 9).dayOfWeek, .wednesday)
        XCTAssertEqual(LocalDate(2026, 9, 1).dayOfWeek, .tuesday)
        XCTAssertEqual(LocalDate(2000, 2, 29).dayOfWeek, .tuesday)
        XCTAssertEqual(LocalDate(1969, 12, 28).dayOfWeek, .sunday)
        XCTAssertEqual(DayOfWeek.monday.value, 1)
        XCTAssertEqual(DayOfWeek.sunday.value, 7)
    }

    func testLeapYears() {
        XCTAssertTrue(YearMonth.isLeap(2024))
        XCTAssertTrue(YearMonth.isLeap(2000))
        XCTAssertFalse(YearMonth.isLeap(1900))
        XCTAssertFalse(YearMonth.isLeap(2026))
        XCTAssertEqual(YearMonth(2024, 2).lengthOfMonth, 29)
        XCTAssertEqual(YearMonth(2026, 2).lengthOfMonth, 28)
        XCTAssertEqual(YearMonth(2026, 4).lengthOfMonth, 30)
        XCTAssertEqual(YearMonth(2026, 12).lengthOfMonth, 31)
    }

    func testAMonthBackKeepsTheDayOrTheLastOfTheMonth() {
        XCTAssertEqual(LocalDate(2026, 3, 31).minusMonths(1), LocalDate(2026, 2, 28))
        XCTAssertEqual(LocalDate(2024, 3, 31).minusMonths(1), LocalDate(2024, 2, 29))
        XCTAssertEqual(LocalDate(2026, 9, 9).minusMonths(1), LocalDate(2026, 8, 9))
        XCTAssertEqual(LocalDate(2026, 1, 31).minusMonths(3), LocalDate(2025, 10, 31))
        XCTAssertEqual(LocalDate(2026, 5, 31).minusMonths(3), LocalDate(2026, 2, 28))
        XCTAssertEqual(LocalDate(2026, 1, 15).minusMonths(1), LocalDate(2025, 12, 15))
        XCTAssertEqual(LocalDate(2024, 2, 29).minusYears(1), LocalDate(2023, 2, 28))
        XCTAssertEqual(LocalDate(2026, 9, 9).minusYears(1), LocalDate(2025, 9, 9))
        XCTAssertEqual(LocalDate(2026, 11, 30).plusMonths(3), LocalDate(2027, 2, 28))
    }

    func testPreviousOrSame() {
        XCTAssertEqual(LocalDate(2026, 9, 9).previousOrSame(.monday), LocalDate(2026, 9, 7))
        XCTAssertEqual(LocalDate(2026, 9, 7).previousOrSame(.monday), LocalDate(2026, 9, 7))
        XCTAssertEqual(LocalDate(2026, 9, 9).previousOrSame(.sunday), LocalDate(2026, 9, 6))
        XCTAssertEqual(LocalDate(2026, 9, 9).previousOrSame(.saturday), LocalDate(2026, 9, 5))
        XCTAssertEqual(LocalDate(2026, 9, 9).previousOrSame(.thursday), LocalDate(2026, 9, 3))
        XCTAssertEqual(LocalDate(2026, 1, 1).previousOrSame(.monday), LocalDate(2025, 12, 29))
    }

    func testParsingAndPrinting() {
        XCTAssertEqual(LocalDate(parse: "2026-09-09"), LocalDate(2026, 9, 9))
        XCTAssertEqual(LocalDate(2026, 9, 9).description, "2026-09-09")
        XCTAssertEqual(LocalDate(2026, 12, 1).description, "2026-12-01")
        for bad in ["", "2026-9-9", "2026-13-01", "2026-02-30", "2026-09", "09-09-2026", "2026/09/09", "abcd-ef-gh"] {
            XCTAssertNil(LocalDate(parse: bad), bad)
        }
    }

    func testOrderingIsByTheCalendar() {
        XCTAssertTrue(LocalDate(2025, 12, 31) < LocalDate(2026, 1, 1))
        XCTAssertTrue(LocalDate(2026, 1, 31).isBefore(LocalDate(2026, 2, 1)))
        XCTAssertTrue(LocalDate(2026, 2, 1).isAfter(LocalDate(2026, 1, 31)))
        XCTAssertTrue(YearMonth(2025, 12) < YearMonth(2026, 1))
        XCTAssertEqual(YearMonth(of: LocalDate(2026, 9, 30)), YearMonth(2026, 9))
        XCTAssertEqual(LocalDate(2026, 9, 9).yearMonth, YearMonth(2026, 9))
    }

    // MARK: zones

    /// 2026-09-09 is in the summer of Bucharest, at +03:00.
    func testAnInstantIsTheLocalDayOfItsZone() {
        let bucharest = Zone("Europe/Bucharest")
        let utc1930 = LocalDate(2026, 9, 8).epochDay * 86_400_000 + (21 * 60 + 30) * 60_000   // 21:30 UTC on the 8th
        XCTAssertEqual(Zone.utc.localDate(epochMs: Int64(utc1930)), LocalDate(2026, 9, 8))
        XCTAssertEqual(bucharest.localDate(epochMs: Int64(utc1930)), LocalDate(2026, 9, 9))   // 00:30 on the 9th
        XCTAssertEqual(bucharest.minuteOfDay(epochMs: Int64(utc1930)), 30)
        XCTAssertEqual(bucharest.offsetSeconds(atEpochMs: Int64(utc1930)), 3 * 3600)
        let winter = bucharest.epochMs(LocalDate(2026, 1, 15), hour: 12)
        XCTAssertEqual(bucharest.offsetSeconds(atEpochMs: winter), 2 * 3600)
    }

    func testALocalTimeIsTheInstantItNames() {
        let bucharest = Zone("Europe/Bucharest")
        let noon = bucharest.epochMs(LocalDate(2026, 9, 9), hour: 12)
        XCTAssertEqual(noon, (Int64(LocalDate(2026, 9, 9).epochDay) * 86_400 + 9 * 3_600) * 1000)   // 09:00 UTC
        XCTAssertEqual(Zone.utc.epochMs(LocalDate(2026, 9, 9)), Int64(LocalDate(2026, 9, 9).epochDay) * 86_400_000)
        XCTAssertEqual(bucharest.localDate(epochMs: bucharest.epochMs(LocalDate(2026, 9, 9), hour: 23, minute: 59)), LocalDate(2026, 9, 9))
        XCTAssertEqual(bucharest.localDate(epochMs: bucharest.epochMs(LocalDate(2026, 9, 9))), LocalDate(2026, 9, 9))
    }

    /// Bucharest sprang forward on 2026-03-29, from 03:00 to 04:00, and fell back on 2026-10-25.
    func testATimeInTheHourAClockSkipsMovesOnByTheGap() {
        let bucharest = Zone("Europe/Bucharest")
        let skipped = bucharest.epochMs(LocalDate(2026, 3, 29), hour: 3, minute: 30)
        XCTAssertEqual(bucharest.minuteOfDay(epochMs: skipped), 4 * 60 + 30)
        XCTAssertEqual(bucharest.offsetSeconds(atEpochMs: skipped), 3 * 3600)
        let before = bucharest.epochMs(LocalDate(2026, 3, 29), hour: 2, minute: 59)
        XCTAssertEqual(bucharest.offsetSeconds(atEpochMs: before), 2 * 3600)
        // 03:30 moved on to 04:30 is 01:30 UTC; 02:59 is 00:59 UTC.
        XCTAssertEqual(skipped - before, 31 * 60_000)
    }

    func testATimeInTheHourAClockRepeatsIsTheEarlierOne() {
        let bucharest = Zone("Europe/Bucharest")
        let repeated = bucharest.epochMs(LocalDate(2026, 10, 25), hour: 3, minute: 30)
        XCTAssertEqual(bucharest.offsetSeconds(atEpochMs: repeated), 3 * 3600)    // summer time, the first 03:30
        XCTAssertEqual(bucharest.minuteOfDay(epochMs: repeated), 3 * 60 + 30)
        let later = repeated + 3_600_000                                         // the second 03:30
        XCTAssertEqual(bucharest.offsetSeconds(atEpochMs: later), 2 * 3600)
        XCTAssertEqual(bucharest.minuteOfDay(epochMs: later), 3 * 60 + 30)
    }

    func testAFixedOffsetZone() {
        let plusFive = Zone(offsetSeconds: 5 * 3600)
        XCTAssertEqual(plusFive.localDate(epochMs: Zone.utc.epochMs(LocalDate(2026, 9, 9), hour: 20)), LocalDate(2026, 9, 10))
        XCTAssertEqual(plusFive.epochMs(LocalDate(2026, 9, 10), hour: 1), Zone.utc.epochMs(LocalDate(2026, 9, 9), hour: 20))
    }

    func testAnInstantBeforeTheEpochHasItsLocalDay() {
        XCTAssertEqual(Zone.utc.localDate(epochMs: -1), LocalDate(1969, 12, 31))
        XCTAssertEqual(Zone.utc.localDate(epochMs: -86_400_000), LocalDate(1969, 12, 31))
        XCTAssertEqual(Zone.utc.localDate(epochMs: -86_400_001), LocalDate(1969, 12, 30))
        XCTAssertEqual(Zone.utc.minuteOfDay(epochMs: -60_000), 23 * 60 + 59)
    }
}
