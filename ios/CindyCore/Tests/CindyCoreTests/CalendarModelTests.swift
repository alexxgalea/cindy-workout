import XCTest
@testable import CindyCore

/// Mirrors `CalendarViewTest.kt`: touch handling of the month calendar, on a 700 point wide view
/// (100 point cells). Cells are found with `CalendarGrid` and the week's first day, exactly as the
/// model does, so the tests hold whichever day the week starts on: a tap opens a trained day, and
/// only a tap. The rest is written for the port: the cells, the stops and the words.
final class CalendarModelTests: XCTestCase {

    private let month = YearMonth(2026, 9)
    private let trainedDay = LocalDate(2026, 9, 7)
    private let cell = 100.0
    private let width = 700.0

    private func calendar(_ first: DayOfWeek = .monday, streak: Set<LocalDate> = []) -> CalendarModel {
        let m = CalendarModel(firstDayOfWeek: first)
        m.show(month, trained: [trainedDay], today: LocalDate(2026, 9, 9), streak: streak)
        return m
    }

    /// The centre of the cell holding `date`, in view coordinates.
    private func centre(_ m: CalendarModel, _ date: LocalDate) -> (Double, Double) {
        let index = CalendarGrid.lead(month, firstDayOfWeek: m.firstDayOfWeek) + date.day - 1
        return (cell * (Double(index % 7) + 0.5), cell * (Double(index / 7 + 1) + 0.5))
    }

    private func tap(_ m: CalendarModel, _ x: Double, _ y: Double) {
        m.touchDown(x: x, y: y)
        m.touchUp(x: x, y: y, width: width)
    }

    /// a tap on a trained day reports that date
    func testATapOnATrainedDayReportsThatDate() {
        for first in [DayOfWeek.monday, .sunday] {
            let m = calendar(first)
            var received: [LocalDate] = []
            m.onDayTap = { received.append($0) }

            let (x, y) = centre(m, trainedDay)
            tap(m, x, y)

            XCTAssertEqual(received, [trainedDay], "week starting \(first)")
        }
    }

    /// a tap on an untrained day reports nothing
    func testATapOnAnUntrainedDayReportsNothing() {
        let m = calendar()
        var received: [LocalDate] = []
        m.onDayTap = { received.append($0) }

        let (x, y) = centre(m, LocalDate(2026, 9, 8))
        tap(m, x, y)

        XCTAssertTrue(received.isEmpty, "opened \(received)")
    }

    /// a drag that ends on a trained day reports nothing
    func testADragThatEndsOnATrainedDayReportsNothing() {
        let m = calendar()
        var received: [LocalDate] = []
        m.onDayTap = { received.append($0) }

        let (x, y) = centre(m, trainedDay)
        // Down 200 away, up on the 7th: the slow drag that used to open a sheet.
        m.touchDown(x: x, y: y + 200)
        m.touchUp(x: x, y: y, width: width)
        // And the other way round: down on the 7th, up 200 away.
        m.touchDown(x: x, y: y)
        m.touchUp(x: x, y: y + 200, width: width)

        XCTAssertTrue(received.isEmpty, "opened \(received)")
    }

    /// a tap without a listener does nothing
    func testATapWithoutAListenerDoesNothing() {
        let m = calendar()
        let (x, y) = centre(m, trainedDay)
        tap(m, x, y)
    }

    // MARK: written for the port

    /// A finger that wandered less than the slop is still a tap, and one at the slop is not.
    func testAFingerBelowTheSlopIsStillATap() {
        let m = calendar()
        var received: [LocalDate] = []
        m.onDayTap = { received.append($0) }
        let (x, y) = centre(m, trainedDay)

        m.touchDown(x: x, y: y)
        m.touchUp(x: x + 7.9, y: y, width: width)
        XCTAssertEqual(received, [trainedDay])

        m.touchDown(x: x, y: y)
        m.touchUp(x: x + 8, y: y, width: width)
        XCTAssertEqual(received, [trainedDay])
    }

    /// The header row is a row of its own: a tap on it opens nothing, and nor does one past the grid.
    func testTheHeaderRowAndTheMarginOpenNothing() {
        let m = calendar()
        var received: [LocalDate] = []
        m.onDayTap = { received.append($0) }

        tap(m, 50, 50)
        tap(m, -30, -30)
        tap(m, 5_000, 5_000)

        XCTAssertTrue(received.isEmpty)
    }

    /// The grid is a header and six weeks of seven cells.
    func testTheGridIsAHeaderAndSixWeeks() {
        let m = calendar()
        XCTAssertEqual(m.cellSize(width: 700), 100)
        XCTAssertEqual(m.height(width: 700), 700)
        XCTAssertEqual(m.headerDays().map { $0.rawValue }, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(calendar(.sunday).headerDays().map { $0.rawValue }, [7, 1, 2, 3, 4, 5, 6])
    }

    /// Each cell says what it is: trained inside the streak, trained outside it, today, to come, or past.
    func testEachCellSaysWhatItIs() {
        let m = calendar(streak: [LocalDate(2026, 9, 7)])
        m.show(month, trained: [trainedDay, LocalDate(2026, 9, 1)], today: LocalDate(2026, 9, 9), streak: [trainedDay])
        let states = Dictionary(uniqueKeysWithValues: m.cells().map { ($0.day, $0.state) })

        XCTAssertEqual(m.cells().count, 30)
        XCTAssertEqual(states[7], .streak)
        XCTAssertEqual(states[1], .trained)
        XCTAssertEqual(states[9], .today)
        XCTAssertEqual(states[10], .future)
        XCTAssertEqual(states[8], .past)
        XCTAssertTrue(m.cells().first { $0.day == 9 }!.isToday)
        // September 2026 starts on a Tuesday: the second column of a week that starts on Monday.
        let first = m.cells().first { $0.day == 1 }!
        XCTAssertEqual([first.column, first.row], [1, 1])
    }

    /// A trained day that is today is trained, and still bold.
    func testATrainedTodayIsTrainedAndBold() {
        let m = CalendarModel(firstDayOfWeek: .monday)
        m.show(month, trained: [LocalDate(2026, 9, 9)], today: LocalDate(2026, 9, 9))
        let c = m.cells().first { $0.day == 9 }!
        XCTAssertEqual(c.state, .trained)
        XCTAssertTrue(c.isToday)
    }

    /// Every trained day of the shown month is a stop, in order, saying whether it is in the streak.
    func testEveryTrainedDayOfTheMonthIsAStop() {
        let m = CalendarModel(firstDayOfWeek: .monday)
        m.show(month, trained: [LocalDate(2026, 9, 21), trainedDay, LocalDate(2026, 8, 31)],
               today: LocalDate(2026, 9, 22), streak: [LocalDate(2026, 9, 21)])

        XCTAssertEqual(m.stops.map { $0.spoken }, ["Monday 7 September, trained",
                                                   "Monday 21 September, trained, in your current streak"])
        var opened: [LocalDate] = []
        m.onDayTap = { opened.append($0) }
        m.activate(stop: 1)
        m.activate(stop: 7)
        XCTAssertEqual(opened, [LocalDate(2026, 9, 21)])
    }

    /// The month is described by its name, its year and how many days were trained.
    func testTheMonthIsDescribed() {
        let m = calendar()
        XCTAssertEqual(m.summary, "September 2026, trained on 1 day")
        m.show(month, trained: [trainedDay, LocalDate(2026, 9, 8)], today: LocalDate(2026, 9, 9))
        XCTAssertEqual(m.summary, "September 2026, trained on 2 days")
        m.show(YearMonth(2026, 8), trained: [trainedDay], today: LocalDate(2026, 9, 9))
        XCTAssertEqual(m.summary, "August 2026, trained on 0 days")
    }

    /// Without a listener the stops do nothing either.
    func testWithoutAListenerAStopDoesNothing() {
        calendar().activate(stop: 0)
    }
}
