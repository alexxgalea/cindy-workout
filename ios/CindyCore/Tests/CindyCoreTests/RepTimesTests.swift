import XCTest
import CindyCore

/// Mirrors `RepTimesTest.kt`.
final class RepTimesTests: XCTestCase {

    private func attempt(_ countedReps: Int?, durationMs: Int64 = 20_000) -> Attempt {
        Attempt(rounds: 0, reps: countedReps ?? 0, atMillis: 0, durationMs: durationMs,
                countedReps: countedReps)
    }

    /// round trips a session of marks
    func testRoundTripsASessionOfMarks() {
        let marks = [
            RepMark(1_000, .pullup, manual: false),
            RepMark(2_000, .pullup, manual: true),
            RepMark(5_000, .pushup, manual: false)
        ]
        XCTAssertEqual(RepTimes.decode(RepTimes.encode(marks)), marks)
    }

    /// round trips no marks at all
    func testRoundTripsNoMarksAtAll() {
        XCTAssertEqual(RepTimes.decode(RepTimes.encode([])), [])
    }

    /// a malformed line is skipped, not fatal
    func testAMalformedLineIsSkippedNotFatal() {
        let raw = "reps1\n1000,PULLUP,c\ngarbage\n2000,NOT_A_MOVEMENT,c\n3000,PUSHUP,x\n4000,SQUAT,m"
        let marks = RepTimes.decode(raw)
        XCTAssertEqual(marks, [RepMark(1_000, .pullup, manual: false), RepMark(4_000, .squat, manual: true)])
    }

    /// a missing or unknown header yields null
    func testAMissingOrUnknownHeaderYieldsNull() {
        XCTAssertNil(RepTimes.decode(nil))
        XCTAssertNil(RepTimes.decode(""))
        XCTAssertNil(RepTimes.decode("   "))
        XCTAssertNil(RepTimes.decode("garbage"))
        XCTAssertNil(RepTimes.decode("reps2\n1000,PULLUP,c"))
    }

    /// valid when the count matches, the clock never goes backwards, and nothing runs past it
    func testValidWhenTheCountMatchesTheClockNeverGoesBackwardsAndNothingRunsPastIt() {
        let marks = [
            RepMark(0, .pullup, manual: false),
            RepMark(1_000, .pullup, manual: false),
            RepMark(20_500, .squat, manual: false)
        ]
        XCTAssertTrue(RepTimes.validFor(marks, attempt(3, durationMs: 20_000)))
    }

    /// invalid when the attempt has no counted total
    func testInvalidWhenTheAttemptHasNoCountedTotal() {
        XCTAssertFalse(RepTimes.validFor([RepMark(0, .pullup, manual: false)], attempt(nil)))
    }

    /// invalid when the mark count disagrees with the attempt's counted total
    func testInvalidWhenTheMarkCountDisagreesWithTheAttemptsCountedTotal() {
        XCTAssertFalse(RepTimes.validFor([RepMark(0, .pullup, manual: false)], attempt(2)))
    }

    /// invalid when a mark's clock runs backwards
    func testInvalidWhenAMarksClockRunsBackwards() {
        let marks = [RepMark(2_000, .pullup, manual: false), RepMark(1_000, .pullup, manual: false)]
        XCTAssertFalse(RepTimes.validFor(marks, attempt(2)))
    }

    /// invalid when a mark runs more than a second past the clock
    func testInvalidWhenAMarkRunsMoreThanASecondPastTheClock() {
        XCTAssertFalse(RepTimes.validFor([RepMark(21_001, .pullup, manual: false)],
                                         attempt(1, durationMs: 20_000)))
    }

    /// a mark exactly one second past the clock is still valid
    func testAMarkExactlyOneSecondPastTheClockIsStillValid() {
        XCTAssertTrue(RepTimes.validFor([RepMark(21_000, .pullup, manual: false)],
                                        attempt(1, durationMs: 20_000)))
    }
}
