import XCTest
import CindyCore

/// Mirrors `LevelsTest.kt`.
final class LevelsTests: XCTestCase {

    /// a complete Cindy lands at intermediate
    func testACompleteCindyLandsAtIntermediate() {
        XCTAssertEqual(Level.of(10), .intermediate)
        XCTAssertEqual(Level.of(15), .intermediate)
    }

    /// the ladder climbs in order
    func testTheLadderClimbsInOrder() {
        XCTAssertEqual(Level.of(0), .firstSteps)
        XCTAssertEqual(Level.of(5), .novice)
        XCTAssertEqual(Level.of(16), .advanced)
        XCTAssertEqual(Level.of(21), .elite)
        XCTAssertEqual(Level.of(27), .legend)
    }

    /// the top of the ladder is level with the benchmark
    func testTheTopOfTheLadderIsLevelWithTheBenchmark() {
        XCTAssertEqual(Level.legend.minRounds, Records.benchmark.rounds)
        XCTAssertNil(Level.next(after: .legend))
        XCTAssertNil(Level.roundsToNext(30))
    }

    /// thresholds are strictly increasing
    func testThresholdsAreStrictlyIncreasing() {
        let mins = Level.allCases.map { $0.minRounds }
        XCTAssertEqual(mins, mins.sorted())
        XCTAssertEqual(mins.count, Set(mins).count)
    }

    /// rounds to next counts down to the boundary
    func testRoundsToNextCountsDownToTheBoundary() {
        XCTAssertEqual(Level.roundsToNext(0), 5)
        XCTAssertEqual(Level.roundsToNext(9), 1)
        XCTAssertEqual(Level.roundsToNext(10), 6)
    }

    /// progress runs zero to one inside a level
    func testProgressRunsZeroToOneInsideALevel() {
        XCTAssertEqual(Level.progress(10), 0, accuracy: 0.001)
        XCTAssertEqual(Level.progress(27), 1, accuracy: 0.001)
        XCTAssertTrue((0.4...0.6).contains(Level.progress(13)))
    }

    /// a negative score does not fall off the bottom
    func testANegativeScoreDoesNotFallOffTheBottom() {
        XCTAssertEqual(Level.of(0), .firstSteps)
        XCTAssertTrue((0...1).contains(Level.progress(0)))
    }
}
