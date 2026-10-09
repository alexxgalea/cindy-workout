import XCTest
import CindyCore

/// Mirrors `RoundSplitsViewTest.kt`: touch handling and accessibility of the round splits, on a
/// 1000 by 600 view. Geometry is read back through `centreX` rather than restated, so the tests
/// keep passing when the plot's padding changes; what they pin down is the behaviour.
final class RoundSplitsChartModelTests: XCTestCase {

    private let width = 1000.0

    private func stacked(_ round: Int, _ ms: Int64) -> RoundSplits.Bar {
        RoundSplits.Bar(round: round, ms: ms, sets: [ms / 4, ms / 4, ms / 2])
    }

    /// Three finished rounds (the middle one with no movement times) and one still open.
    private func withBars() -> RoundSplitsChartModel {
        let model = RoundSplitsChartModel()
        show(model)
        return model
    }

    private func show(_ model: RoundSplitsChartModel) {
        model.show(
            bars: [stacked(1, 168_000), RoundSplits.Bar(round: 2, ms: 150_000, sets: nil), stacked(3, 160_000),
                   RoundSplits.Bar(round: 4, ms: 70_000, sets: [30_000], unfinished: true, reps: 12)],
            fastest: 1, averageMs: 159_000, averageLabel: "AVG 2:39", describe: { "Round \($0 + 1)" })
    }

    private func tap(_ model: RoundSplitsChartModel, _ x: Double) {
        model.touchDown(x: x, y: 300)
        model.touchUp(x: x, y: 300, width: width)
    }

    /// there is a bar for every round, the open one included
    func testThereIsABarForEveryRoundTheOpenOneIncluded() {
        XCTAssertEqual(withBars().barCount, 4)
    }

    /// a tap selects the bar under it and reports it
    func testATapSelectsTheBarUnderItAndReportsIt() {
        let model = withBars()
        var received: [Int?] = []
        model.onSelect = { received.append($0) }

        tap(model, model.centreX(2, width: width))

        XCTAssertEqual(model.selected, 2)
        XCTAssertEqual(received, [2])
    }

    /// a tap between two bars still picks one, and one past the end picks the last
    func testATapBetweenTwoBarsStillPicksOneAndOnePastTheEndPicksTheLast() {
        let model = withBars()

        tap(model, model.centreX(3, width: width) + 200)

        XCTAssertEqual(model.selected, 3)
    }

    /// tapping the selected bar clears it
    func testTappingTheSelectedBarClearsIt() {
        let model = withBars()
        var received: [Int?] = []
        model.onSelect = { received.append($0) }

        tap(model, model.centreX(1, width: width))
        tap(model, model.centreX(1, width: width))

        XCTAssertNil(model.selected)
        XCTAssertEqual(received, [1, nil])
    }

    /// a sideways drag scrubs through the bars
    func testASidewaysDragScrubsThroughTheBars() {
        let model = withBars()
        var received: [Int?] = []
        model.onSelect = { received.append($0) }
        let from = model.centreX(0, width: width)
        let to = model.centreX(3, width: width)

        model.touchDown(x: from, y: 300)
        var x = from
        while x < to {
            x = min(x + 20, to)
            model.touchMove(x: x, y: 300, width: width)
        }
        model.touchUp(x: to, y: 300, width: width)

        XCTAssertEqual(model.selected, 3)
        let indices = received.compactMap { $0 }
        XCTAssertFalse(indices.isEmpty, "nothing was reported")
        XCTAssertTrue(zip(indices, indices.dropFirst()).allSatisfy { $0 <= $1 }, "went backwards: \(indices)")
        XCTAssertEqual(indices.last, 3)
    }

    /// choosing another comparison keeps the selection
    func testChoosingAnotherComparisonKeepsTheSelection() {
        let model = withBars()
        tap(model, model.centreX(0, width: width))

        model.setReference([170_000, nil, 140_000, nil])

        XCTAssertEqual(model.selected, 0)
    }

    /// showing new bars clears the selection
    func testShowingNewBarsClearsTheSelection() {
        let model = withBars()
        tap(model, model.centreX(0, width: width))

        show(model)

        XCTAssertNil(model.selected)
    }

    /// nothing is drawn or selectable with no bars
    func testNothingIsDrawnOrSelectableWithNoBars() {
        let model = RoundSplitsChartModel()
        tap(model, 500)

        XCTAssertNil(model.selected)
        XCTAssertEqual(model.barCount, 0)
    }

    /// every bar is its own screen reader stop, reading what the page says for it
    func testEveryBarIsItsOwnScreenReaderStopReadingWhatThePageSaysForIt() {
        let model = withBars()

        XCTAssertEqual(model.stops.count, 4)
        XCTAssertEqual(model.stops[2], "Round 3")
    }

    /// a screen reader can select a bar
    func testAScreenReaderCanSelectABar() {
        let model = withBars()

        model.activate(stop: 1)

        XCTAssertEqual(model.selected, 1)
    }
}
