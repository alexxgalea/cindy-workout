import XCTest
import CindyCore
import CindyFixtures

/// Carried over from the `CindyCoreChecks` executable: Levels. Every check keeps its original wording as
/// its assertion message.
final class LevelsTests: XCTestCase {

    func testLevels() {
        XCTAssertEqual(Level.of(10), .intermediate, "a complete Cindy lands at intermediate")
        XCTAssertEqual(Level.of(0), .firstSteps, "the ladder starts at first steps")
        XCTAssertEqual(Level.of(5), .novice, "climbs to novice")
        XCTAssertEqual(Level.of(16), .advanced, "then advanced")
        XCTAssertEqual(Level.of(21), .elite, "then elite")
        XCTAssertEqual(Level.of(27), .legend, "then legend")
        XCTAssertEqual(Level.legend.minRounds, Records.benchmark.rounds, "legend is level with the benchmark")
        XCTAssertEqual(Level.next(after: .legend) == nil, true, "nothing above legend")
        XCTAssertEqual(Level.roundsToNext(9), 1, "one round short of intermediate")
        XCTAssertEqual(Level.progress(10), 0, accuracy: 0.001, "progress starts at zero in a level")
        XCTAssertEqual(Level.progress(27), 1, accuracy: 0.001, "and is full at the top")

        let mins = Level.allCases.map(\.minRounds)
        XCTAssertEqual(mins, mins.sorted(), "thresholds are increasing")
        XCTAssertEqual(mins.count, Set(mins).count, "and distinct")
    }
}
