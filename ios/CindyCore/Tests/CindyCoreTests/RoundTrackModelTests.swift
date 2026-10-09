import XCTest
import CindyCore

/// Mirrors `RoundTrackViewTest.kt`: the round track on a 1000 point wide view: how many pills it
/// draws, what a tap or a drag selects, and that a screen reader gets one stop per round.
/// Robolectric's touches are the model's `touchDown`, `touchMove` and `touchUp`.
final class RoundTrackModelTests: XCTestCase {

    private let width = 1000.0
    private let plurals = SessionStats.plurals(CindyProfile.standard)

    private func split(_ movement: Exercise, _ reps: Int) -> SetSplit { SetSplit(movement, 10_000, reps, 0) }

    /// `full` finished rounds, plus a pull-up and `open` push-ups in a round the clock ended.
    private func rounds(_ full: Int, open: Int = 0) -> [RoundStat] {
        var splits: [SetSplit] = []
        for _ in 0..<full { splits += [split(.pullup, 5), split(.pushup, 10), split(.squat, 15)] }
        if open > 0 { splits.append(split(.pullup, 5)) }
        let a = Attempt(rounds: full, reps: 0, atMillis: 1, durationMs: 20 * 60_000,
                        roundSplitsMs: Array(repeating: 60_000, count: full),
                        countedReps: splits.reduce(0) { $0 + $1.reps } + open, setSplits: splits)
        return SessionStats.from(a)!.rounds
    }

    private func track(_ rounds: [RoundStat]) -> RoundTrackModel {
        let model = RoundTrackModel()
        model.show(rounds) { rounds[$0].caption(self.plurals) }
        return model
    }

    private func tap(_ model: RoundTrackModel, _ i: Int) {
        let (x, y) = model.centre(i, in: width)
        model.touchDown(x: x, y: y)
        model.touchUp(x: x, y: y, in: width)
    }

    /// there is a pill for every round, the unfinished one included
    func testThereIsAPillForEveryRoundTheUnfinishedOneIncluded() {
        XCTAssertEqual(track(rounds(7, open: 4)).pillCount, 8)
        XCTAssertEqual(track(rounds(7)).pillCount, 7)
    }

    /// ten pills to a row, so the height follows the rows
    func testTenPillsToARowSoTheHeightFollowsTheRows() {
        let one = track(rounds(10)).height
        let two = track(rounds(11)).height
        let three = track(rounds(21)).height

        XCTAssertEqual(two, one * 2, "\(one) \(two)")
        XCTAssertEqual(three, one * 3, "\(two) \(three)")
        // A row is a full 48 point touch target high.
        XCTAssertEqual(one, 48)
    }

    /// a tap selects that round and reports it
    func testATapSelectsThatRoundAndReportsIt() {
        let data = rounds(7, open: 4)
        let model = track(data)
        var received: [Int?] = []
        model.onSelect = { received.append($0) }

        tap(model, 3)
        XCTAssertEqual(model.selected, 3)
        tap(model, 7)

        XCTAssertEqual(model.selected, 7)
        XCTAssertEqual(received, [3, 7])
        XCTAssertEqual(data[received.last!!].caption(plurals), "Round 8 · 9 of 30 · 5 pull-ups, 4 push-ups · unfinished")
    }

    /// a second tap clears the selection
    func testASecondTapClearsTheSelection() {
        let model = track(rounds(5))

        tap(model, 2)
        tap(model, 2)

        XCTAssertNil(model.selected)
    }

    /// a tap on the second row lands on the second row
    func testATapOnTheSecondRowLandsOnTheSecondRow() {
        let model = track(rounds(14))

        tap(model, 12)

        XCTAssertEqual(model.selected, 12)
    }

    /// a sideways drag scrubs through the rounds
    func testASidewaysDragScrubsThroughTheRounds() {
        let model = track(rounds(10))
        var received: [Int?] = []
        model.onSelect = { received.append($0) }
        let (fromX, y) = model.centre(0, in: width)
        let (toX, _) = model.centre(5, in: width)

        model.touchDown(x: fromX, y: y)
        var x = fromX
        while x < toX {
            x = min(x + 10, toX)
            model.touchMove(x: x, y: y, in: width)
        }
        model.touchUp(x: toX, y: y, in: width)

        XCTAssertEqual(model.selected, 5)
        let indices = received.compactMap { $0 }
        XCTAssertTrue(zip(indices, indices.dropFirst()).allSatisfy { $0 <= $1 }, "went backwards: \(indices)")
    }

    /// talkback gets one stop per round, each reading as the round
    func testTalkbackGetsOneStopPerRoundEachReadingAsTheRound() {
        let data = rounds(7, open: 4)
        let model = track(data)

        XCTAssertEqual(model.stops.count, 8)
        XCTAssertEqual(model.stops[0], data[0].caption(plurals))
        model.activate(stop: 4)
        XCTAssertEqual(model.selected, 4)
    }
}
