import XCTest
@testable import CindyCore

/// Mirrors `ProgressChartViewTest.kt`: touch handling of the progress chart, on a 1000 by 600 view.
/// Geometry is read back through `pointCentreX` rather than restated, so the tests keep passing when
/// the plot's padding changes; what they pin down is the behaviour: a tap selects, a second tap
/// clears, a sideways drag scrubs. The rest is written for the port: what is drawn where.
final class ProgressChartModelTests: XCTestCase {

    private let day: Int64 = 24 * 60 * 60_000
    private let width = 1000.0
    private let height = 600.0

    private func withLine() -> ProgressChartModel {
        let m = ProgressChartModel()
        m.showLine(
            points: [ProgressPoint(atMillis: 0, value: 100.0), ProgressPoint(atMillis: day, value: 120.0, record: true),
                     ProgressPoint(atMillis: 2 * day, value: 110.0)],
            best: [100.0, 120.0, 120.0], xStart: 0, xEnd: 2 * day, invertY: false, edgeLabels: ("1 Sep", "3 Sep"),
            axisLabel: { String(Int($0)) }, describe: { "Point \($0)" })
        return m
    }

    private func tap(_ m: ProgressChartModel, _ x: Double) {
        m.touchDown(x: x, y: 300)
        m.touchUp(x: x, y: 300, width: width, height: height)
    }

    /// a tap selects the nearest point
    func testATapSelectsTheNearestPoint() {
        let m = withLine()
        var received: [Int?] = []
        m.onSelect = { received.append($0) }

        tap(m, m.pointCentreX(1, width: width, height: height))

        XCTAssertEqual(m.selected, 1)
        XCTAssertEqual(received, [1])
    }

    /// tapping the selected point clears it
    func testTappingTheSelectedPointClearsIt() {
        let m = withLine()

        tap(m, m.pointCentreX(1, width: width, height: height))
        tap(m, m.pointCentreX(1, width: width, height: height))

        XCTAssertNil(m.selected)
    }

    /// a sideways drag scrubs through the points
    func testASidewaysDragScrubsThroughThePoints() {
        let m = withLine()
        var received: [Int?] = []
        m.onSelect = { received.append($0) }
        let from = m.pointCentreX(0, width: width, height: height)
        let to = m.pointCentreX(2, width: width, height: height)

        m.touchDown(x: from, y: 300)
        var x = from
        while x < to {
            x = min(x + 20, to)
            m.touchMove(x: x, y: 300, width: width, height: height)
        }
        m.touchUp(x: to, y: 300, width: width, height: height)

        XCTAssertEqual(m.selected, 2)
        let indices = received.compactMap { $0 }
        XCTAssertFalse(indices.isEmpty, "nothing was reported")
        XCTAssertTrue(zip(indices, indices.dropFirst()).allSatisfy { $0 <= $1 }, "went backwards: \(indices)")
        XCTAssertEqual(indices.last, 2)
    }

    /// bars take a point each
    func testBarsTakeAPointEach() {
        let m = ProgressChartModel()
        m.showBars(points: (0..<5).map { ProgressPoint(atMillis: Int64($0) * 7 * day, value: Double($0 * 100), sessions: $0) },
                   edgeLabels: ("1 Sep", "29 Sep"), axisLabel: { String(Int($0)) }, describe: { "Week \($0)" })

        XCTAssertEqual(m.pointCount, 5)
        tap(m, m.pointCentreX(4, width: width, height: height))

        XCTAssertEqual(m.selected, 4)
    }

    // MARK: written for the port

    /// A scrub ticks on each new point and not between them.
    func testAScrubTicksOnEachNewPoint() {
        let m = withLine()
        var ticks = 0
        m.onTick = { ticks += 1 }
        let from = m.pointCentreX(0, width: width, height: height)
        m.touchDown(x: from, y: 300)
        m.touchMove(x: from + 20, y: 300, width: width, height: height)
        m.touchMove(x: from + 22, y: 300, width: width, height: height)
        XCTAssertEqual(ticks, 1)
        m.touchMove(x: m.pointCentreX(2, width: width, height: height), y: 300, width: width, height: height)
        XCTAssertEqual(ticks, 2)
    }

    /// A vertical gesture never becomes a drag, so the scroll view around the chart keeps it.
    func testAVerticalGestureNeverScrubs() {
        let m = withLine()
        m.touchDown(x: 500, y: 300)
        m.touchMove(x: 505, y: 500, width: width, height: height)
        XCTAssertNil(m.selected)
    }

    /// Showing new data drops the selection without reporting it.
    func testShowingNewDataDropsTheSelection() {
        let m = withLine()
        tap(m, m.pointCentreX(1, width: width, height: height))
        var received: [Int?] = []
        m.onSelect = { received.append($0) }

        m.showBars(points: [ProgressPoint(atMillis: 0, value: 5)], edgeLabels: ("a", "b"), axisLabel: { _ in "" },
                   describe: { _ in "" })

        XCTAssertNil(m.selected)
        XCTAssertTrue(received.isEmpty)
    }

    /// With nothing to draw a touch selects nothing.
    func testNothingIsSelectableWithNoPoints() {
        let m = ProgressChartModel()
        tap(m, 500)
        XCTAssertNil(m.selected)
        XCTAssertEqual(m.pointCount, 0)
    }

    /// Every point is its own screen reader stop, reading what the page says for it, and activating
    /// one selects it.
    func testEveryPointIsAScreenReaderStopThatSelectsIt() {
        let m = withLine()
        XCTAssertEqual(m.stops, ["Point 0", "Point 1", "Point 2"])
        m.activate(stop: 2)
        XCTAssertEqual(m.selected, 2)
    }

    /// The line spreads its points over the time between its two ends, and clamps what lies outside.
    func testTheLineSpreadsItsPointsOverTheRange() {
        let m = ProgressChartModel()
        m.showLine(points: [ProgressPoint(atMillis: -day, value: 1), ProgressPoint(atMillis: day, value: 2),
                            ProgressPoint(atMillis: 5 * day, value: 3)],
                   best: [], xStart: 0, xEnd: 2 * day, invertY: false, edgeLabels: ("", ""),
                   axisLabel: { _ in "" }, describe: { _ in "" })
        let plot = m.plot(width: width, height: height)
        let xs = m.xs(width: width, height: height)

        XCTAssertEqual(xs[0], plot.left)
        XCTAssertEqual(xs[1], plot.centreX, accuracy: 1e-9)
        XCTAssertEqual(xs[2], plot.right)
        XCTAssertEqual(plot.right, width - ProgressChartModel.rightInset)
    }

    /// With no span at all the points sit in the middle.
    func testWithNoSpanThePointsSitInTheMiddle() {
        let m = ProgressChartModel()
        m.showLine(points: [ProgressPoint(atMillis: day, value: 1)], best: [], xStart: day, xEnd: day, invertY: false,
                   edgeLabels: ("", ""), axisLabel: { _ in "" }, describe: { _ in "" })
        XCTAssertEqual(m.pointCentreX(0, width: width, height: height), m.plot(width: width, height: height).centreX)
    }

    /// A bigger value sits higher, and on an inverted axis (pace) a smaller one does.
    func testBiggerSitsHigherAndPaceIsInverted() {
        let m = withLine()
        let ys = m.ys(width: width, height: height)
        XCTAssertTrue(ys[1] < ys[2] && ys[2] < ys[0], "\(ys)")

        let pace = ProgressChartModel()
        pace.showLine(points: [ProgressPoint(atMillis: 0, value: 60), ProgressPoint(atMillis: day, value: 50)],
                      best: [], xStart: 0, xEnd: day, invertY: true, edgeLabels: ("", ""), axisLabel: { _ in "" },
                      describe: { _ in "" })
        let p = pace.ys(width: width, height: height)
        XCTAssertTrue(p[1] < p[0], "the faster round (fewer seconds) sits higher: \(p)")
    }

    /// The best-so-far line holds each value until the next point, steps there, and runs to the edge.
    func testTheBestLineStepsAtEachPointAndRunsToTheEdge() {
        let m = withLine()
        let plot = m.plot(width: width, height: height)
        let xs = m.xs(width: width, height: height)
        let steps = m.bestSteps(width: width, height: height)

        XCTAssertEqual(steps.count, 6)
        XCTAssertEqual(steps[0].x, xs[0])
        XCTAssertEqual(steps[1].x, xs[1])
        XCTAssertEqual(steps[1].y, steps[0].y, "held until the next point")
        XCTAssertTrue(steps[2].y < steps[1].y, "then steps up")
        XCTAssertEqual(steps[5].x, plot.right)
        XCTAssertEqual(steps[5].y, steps[4].y)
    }

    /// There is no best line unless there is one best for each point.
    func testThereIsNoBestLineWithoutABestForEveryPoint() {
        let m = ProgressChartModel()
        m.showLine(points: [ProgressPoint(atMillis: 0, value: 1), ProgressPoint(atMillis: day, value: 2)], best: [1.0],
                   xStart: 0, xEnd: day, invertY: false, edgeLabels: ("", ""), axisLabel: { _ in "" }, describe: { _ in "" })
        XCTAssertTrue(m.bestSteps(width: width, height: height).isEmpty)
    }

    /// A floor is a hollow ring, which wins over a record; a record is the earned colour.
    func testAFloorIsARingAndARecordIsEarned() {
        let m = ProgressChartModel()
        m.showLine(points: [ProgressPoint(atMillis: 0, value: 1, record: true, lowerBound: true),
                            ProgressPoint(atMillis: day, value: 2, record: true), ProgressPoint(atMillis: 2 * day, value: 3)],
                   best: [], xStart: 0, xEnd: 2 * day, invertY: false, edgeLabels: ("", ""), axisLabel: { _ in "" },
                   describe: { _ in "" })
        XCTAssertEqual([m.mark(0), m.mark(1), m.mark(2)], [.ring, .record, .plain])
    }

    /// The tallest week (the latest on a tie) is the best, and a run of empty weeks has none.
    func testTheTallestWeekIsTheBestAndTheLatestWinsATie() {
        let m = ProgressChartModel()
        m.showBars(points: [100, 300, 200, 300].enumerated().map { ProgressPoint(atMillis: Int64($0.offset) * day, value: $0.element) },
                   edgeLabels: ("", ""), axisLabel: { _ in "" }, describe: { _ in "" })
        XCTAssertEqual(m.bestBar, 3)

        m.showBars(points: [0, 0, 0].map { ProgressPoint(atMillis: 0, value: $0) }, edgeLabels: ("", ""),
                   axisLabel: { _ in "" }, describe: { _ in "" })
        XCTAssertEqual(m.bestBar, -1)
    }

    /// A bar is coloured for what it is, an empty week has no bar, and the corners are the smaller of
    /// three and the bar's own height.
    func testBarsAreColouredForWhatTheyAreAndAnEmptyWeekHasNone() {
        let m = ProgressChartModel()
        m.showBars(points: [0, 300, 100].enumerated().map { ProgressPoint(atMillis: Int64($0.offset) * day, value: Double($0.element)) },
                   edgeLabels: ("", ""), axisLabel: { _ in "" }, describe: { _ in "" })
        m.select(2)
        let bars = m.bars(width: width, height: height)
        let plot = m.plot(width: width, height: height)

        XCTAssertNil(bars[0])
        XCTAssertEqual(bars[1]?.tone, .best)
        XCTAssertEqual(bars[2]?.tone, .selected)
        XCTAssertEqual(bars[1]?.bottom, plot.bottom)
        XCTAssertEqual(bars[1]?.radius, 3)
        // Three bars across a 956-point plot: slots of 318.7, each bar 62% of its slot.
        XCTAssertEqual(bars[1]!.right - bars[1]!.left, plot.width / 3 * 0.62, accuracy: 1e-9)
    }

    /// The bars start at nothing, and the axis ticks come from the values.
    func testTheBarAxisStartsAtNothing() {
        let m = ProgressChartModel()
        m.showBars(points: [ProgressPoint(atMillis: 0, value: 250), ProgressPoint(atMillis: day, value: 80)],
                   edgeLabels: ("1 Sep", "8 Sep"), axisLabel: { "\(Int($0)) reps" }, describe: { _ in "" })
        XCTAssertEqual(m.ticks.first, 0)
        XCTAssertTrue(m.ticks.last! >= 250)
        XCTAssertEqual(m.label(forTick: 100), "100 reps")
        XCTAssertEqual(m.edgeLabels.first, "1 Sep")
        XCTAssertEqual(m.edgeLabels.second, "8 Sep")
    }
}
