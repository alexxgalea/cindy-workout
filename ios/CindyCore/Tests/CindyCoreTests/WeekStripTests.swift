import XCTest
@testable import CindyCore

/// The week of seven circles, written for the port: `WeekStripView` has no test of its own, so each
/// one holds a line of it.
final class WeekStripTests: XCTestCase {

    private let monday = LocalDate(2026, 10, 5)

    /// Trained days are named in order, joined the way a person would say them.
    func testTheTrainedDaysAreNamedInOrder() {
        XCTAssertEqual(WeekStrip.describe(weekStart: monday, trained: []), "This week, no sessions yet")
        XCTAssertEqual(WeekStrip.describe(weekStart: monday, trained: [monday.plusDays(2)]),
                       "This week, trained on Wednesday")
        XCTAssertEqual(WeekStrip.describe(weekStart: monday, trained: [monday, monday.plusDays(2)]),
                       "This week, trained on Monday and Wednesday")
        XCTAssertEqual(WeekStrip.describe(weekStart: monday, trained: [monday.plusDays(4), monday, monday.plusDays(2)]),
                       "This week, trained on Monday, Wednesday and Friday")
    }

    /// Days outside the week are not counted.
    func testDaysOutsideTheWeekAreNotCounted() {
        XCTAssertEqual(WeekStrip.describe(weekStart: monday, trained: [monday.minusDays(1), monday.plusDays(7)]),
                       "This week, no sessions yet")
    }

    /// A week in progress never reads as a week of failures: what is still to come is a dot.
    func testADayStillToComeIsADotAndAMissedDayIsARing() {
        let days = WeekStrip.days(weekStart: monday, trained: [monday, monday.plusDays(3)], today: monday.plusDays(3))

        XCTAssertEqual(days.map { $0.date }, (0..<7).map { monday.plusDays($0) })
        XCTAssertEqual(days.map { $0.state }, [.trained(today: false), .missed, .missed, .trained(today: true),
                                               .coming, .coming, .coming])
    }

    /// Today, not yet trained, is its own state.
    func testTodayNotYetTrainedIsItsOwnState() {
        let days = WeekStrip.days(weekStart: monday, trained: [], today: monday.plusDays(1))
        XCTAssertEqual(days.map { $0.state }, [.missed, .today, .coming, .coming, .coming, .coming, .coming])
    }

    /// A week that has not started yet is all dots, and one that is over is all rings.
    func testAFutureWeekIsAllDotsAndAPastWeekAllRings() {
        XCTAssertTrue(WeekStrip.days(weekStart: monday, trained: [], today: monday.minusDays(1))
            .allSatisfy { $0.state == .coming })
        XCTAssertTrue(WeekStrip.days(weekStart: monday, trained: [], today: monday.plusDays(10))
            .allSatisfy { $0.state == .missed })
    }
}
