import XCTest
@testable import CindyCore

/// The corners of the Progress models that the ported tests and `ProgressDetailTests` do not reach,
/// each found by changing the line that decides it and seeing every other test still pass.
final class ProgressEdgeTests: XCTestCase {

    private let zone = Zone("Europe/Bucharest")
    private lazy var today = LocalDate(2026, 10, 8)
    private lazy var now = zone.epochMs(today, hour: 12)
    private let day: Int64 = 24 * 60 * 60 * 1000
    private let width = 1000.0
    private let height = 600.0

    private func attempt(_ rounds: Int, at: Int64, profile: CindyProfile? = .standard) -> Attempt {
        Attempt(rounds: rounds, reps: 0, atMillis: at, durationMs: 20 * 60_000,
                roundSplitsMs: Array(repeating: 60_000, count: rounds), profile: profile)
    }

    private func input(_ attempts: [Attempt]) -> ProgressInput {
        ProgressInput(attempts: attempts, today: today, nowMs: now, zone: zone, firstDayOfWeek: .monday)
    }

    // MARK: the chart

    /// The axis is drawn from the values, so a point sits inside the plot.
    func testTheLineAxisIsDrawnFromTheValues() {
        let m = ProgressChartModel()
        m.showLine(points: [ProgressPoint(atMillis: 0, value: 100), ProgressPoint(atMillis: day, value: 120)],
                   best: [], xStart: 0, xEnd: day, invertY: false, edgeLabels: ("", ""), axisLabel: { _ in "" },
                   describe: { _ in "" })
        let plot = m.plot(width: width, height: height)

        XCTAssertTrue(m.ticks.first! <= 100 && m.ticks.last! >= 120, "\(m.ticks)")
        XCTAssertTrue(m.ys(width: width, height: height).allSatisfy { $0 >= plot.top && $0 <= plot.bottom })
    }

    /// A run of empty weeks still has an axis to stand on.
    func testARunOfEmptyWeeksStillHasAnAxis() {
        let m = ProgressChartModel()
        m.showBars(points: (0..<3).map { ProgressPoint(atMillis: Int64($0) * day, value: 0) }, edgeLabels: ("", ""),
                   axisLabel: { _ in "" }, describe: { _ in "" })
        XCTAssertEqual(m.ticks, Progress.niceTicks(0.0, 1.0))
        XCTAssertTrue(m.bars(width: width, height: height).allSatisfy { $0 == nil })
    }

    /// The selected bar wins over the best one.
    func testTheSelectedBarWinsOverTheBestOne() {
        let m = ProgressChartModel()
        m.showBars(points: [100, 300].enumerated().map { ProgressPoint(atMillis: Int64($0.offset) * day, value: Double($0.element)) },
                   edgeLabels: ("", ""), axisLabel: { _ in "" }, describe: { _ in "" })
        XCTAssertEqual(m.bars(width: width, height: height)[1]?.tone, .best)
        m.select(1)
        XCTAssertEqual(m.bars(width: width, height: height)[1]?.tone, .selected)
    }

    /// A bar shorter than its corner is rounded no further than its own height.
    func testABarShorterThanItsCornerIsRoundedNoFurtherThanItsHeight() {
        let m = ProgressChartModel()
        m.showBars(points: [1000, 5].enumerated().map { ProgressPoint(atMillis: Int64($0.offset) * day, value: Double($0.element)) },
                   edgeLabels: ("", ""), axisLabel: { _ in "" }, describe: { _ in "" })
        let bar = m.bars(width: width, height: height)[1]!

        XCTAssertTrue(bar.bottom - bar.top < 3 && bar.bottom - bar.top >= 1)
        XCTAssertEqual(bar.radius, bar.bottom - bar.top, accuracy: 1e-9)
    }

    // MARK: the page

    /// A tile that did not move is not "up".
    func testATileThatDidNotMoveIsNotUp() {
        let a = [attempt(12, at: now - 7 * day), attempt(12, at: now)]
        let tiles = ProgressModel(input(a)).page.thisWeek!.tiles
        XCTAssertNil(tiles[0].change)
        XCTAssertFalse(tiles[0].up)
    }

    /// With one kind of Cindy there is nothing to choose between.
    func testWithOneKindOfCindyThereAreNoCategoryChips() {
        XCTAssertNil(ProgressModel(input([attempt(12, at: now - day), attempt(13, at: now)])).page.progress?.categoryLabels)
    }

    /// The calendar never shows a month the athlete cannot page to: not one past now, not one
    /// before the first session.
    func testTheCalendarNeverShowsAMonthTheAthleteCannotPageTo() {
        let a = [attempt(12, at: zone.epochMs(LocalDate(2026, 9, 3), hour: 12)), attempt(13, at: now)]
        let i = input(a)
        func shown(_ m: YearMonth) -> YearMonth? {
            ProgressPageBuilder.build(i, metric: .score, range: .all, category: .standard, month: m).calendar?.month
        }
        XCTAssertEqual(shown(YearMonth(2027, 1)), YearMonth(2026, 10))
        XCTAssertEqual(shown(YearMonth(2026, 1)), YearMonth(2026, 9))
        XCTAssertEqual(shown(YearMonth(2026, 9)), YearMonth(2026, 9))
    }

    /// When the board shrinks, a calendar paged back past what is left comes forward.
    func testACalendarPagedBackComesForwardWhenTheBoardShrinks() {
        let old = attempt(12, at: zone.epochMs(LocalDate(2026, 8, 3), hour: 12))
        let m = ProgressModel(input([old, attempt(13, at: now)]))
        m.showPreviousMonth()
        m.showPreviousMonth()
        XCTAssertEqual(m.shownMonth, YearMonth(2026, 8))

        m.reload([attempt(13, at: now), attempt(14, at: now - day)])

        XCTAssertEqual(m.shownMonth, YearMonth(2026, 10))
        XCTAssertEqual(m.page.calendar?.month, YearMonth(2026, 10))
    }

    /// An arrow that is disabled builds nothing; so does choosing what is already chosen.
    func testADisabledArrowAndAnUnchangedChipBuildNothing() {
        let m = ProgressModel(input([attempt(12, at: now - day), attempt(13, at: now)]))
        var builds = 0
        m.onChange = { builds += 1 }

        m.showNextMonth()        // already on the latest month
        m.showPreviousMonth()    // already on the earliest
        m.chooseMetric(0)
        m.chooseRange(3)
        m.chooseMetric(9)
        m.chooseRange(-1)

        XCTAssertEqual(builds, 0)
        XCTAssertEqual(m.shownMonth, YearMonth(2026, 10))
    }
}
