import XCTest
import CindyCore

/// Mirrors `RepLogTest.kt`.
final class RepLogTests: XCTestCase {

    /// a rep appends one mark at the clock it banked
    func testARepAppendsOneMarkAtTheClockItBanked() {
        let log = RepLog()
        log.start()
        log.follow(totalReps: 1, manualReps: 0, movement: .pullup, clockMs: 500)
        XCTAssertEqual(log.marks, [RepMark(500, .pullup, manual: false)])
    }

    /// the finishing rep is tagged with the movement it left
    func testTheFinishingRepIsTaggedWithTheMovementItLeft() {
        let log = RepLog()
        log.start()
        // Reps 1-4 of the pull-ups.
        for i in 0..<4 { log.follow(totalReps: i + 1, manualReps: 0, movement: .pullup, clockMs: Int64(1_000 * (i + 1))) }
        // The 5th rep finishes the movement: the engine has already moved snap.exercise on to
        // push-ups by the time this is read, so the caller passes the movement that was left.
        log.follow(totalReps: 5, manualReps: 0, movement: .pullup, clockMs: 5_000)
        XCTAssertEqual(log.marks.last?.movement, .pullup)
        XCTAssertEqual(log.marks.count, 5)
    }

    /// a skip adds nothing
    func testASkipAddsNothing() {
        let log = RepLog()
        log.start()
        log.follow(totalReps: 3, manualReps: 0, movement: .pullup, clockMs: 1_000)
        // SKIP fires EXERCISE_DONE/ROUND_DONE too, but never changes the total.
        log.follow(totalReps: 3, manualReps: 0, movement: .pullup, clockMs: 1_500)
        XCTAssertEqual(log.marks.count, 3)
    }

    /// undo removes the latest mark, even across a movement boundary
    func testUndoRemovesTheLatestMarkEvenAcrossAMovementBoundary() {
        let log = RepLog()
        log.start()
        for i in 0..<5 { log.follow(totalReps: i + 1, manualReps: 0, movement: .pullup, clockMs: Int64(1_000 * (i + 1))) }
        log.follow(totalReps: 6, manualReps: 0, movement: .pushup, clockMs: 6_000)  // the first push-up
        XCTAssertEqual(log.marks.last?.movement, .pushup)

        // Undo steps back into the pull-ups; snap.exercise is PULLUP again by the time it is read.
        log.follow(totalReps: 5, manualReps: 0, movement: .pullup, clockMs: 6_500)

        XCTAssertEqual(log.marks.count, 5)
        XCTAssertEqual(log.marks.last?.movement, .pullup)
    }

    /// undo never removes more marks than exist
    func testUndoNeverRemovesMoreMarksThanExist() {
        let log = RepLog()
        log.start()
        log.follow(totalReps: 1, manualReps: 0, movement: .squat, clockMs: 1_000)
        log.follow(totalReps: -4, manualReps: 0, movement: .squat, clockMs: 1_500)  // defensive: the engine never does this
        XCTAssertTrue(log.marks.isEmpty)
    }

    /// a tapped rep is flagged manual
    func testATappedRepIsFlaggedManual() {
        let log = RepLog()
        log.start()
        log.follow(totalReps: 1, manualReps: 1, movement: .squat, clockMs: 1_000)
        XCTAssertEqual(log.marks.count, 1)
        XCTAssertTrue(log.marks[0].manual)
    }

    /// a jump of two appends two marks at the same instant
    func testAJumpOfTwoAppendsTwoMarksAtTheSameInstant() {
        let log = RepLog()
        log.start()
        // Two reps banked between the frames this log actually saw — a dropped stale snapshot.
        log.follow(totalReps: 2, manualReps: 0, movement: .squat, clockMs: 4_000)
        XCTAssertEqual(log.marks.map { $0.clockMs }, [4_000, 4_000])
        XCTAssertEqual(log.marks.map { $0.manual }, [false, false])
    }

    /// only the newest reps of a jump are flagged manual
    func testOnlyTheNewestRepsOfAJumpAreFlaggedManual() {
        let log = RepLog()
        log.start()
        log.follow(totalReps: 2, manualReps: 1, movement: .squat, clockMs: 4_000)  // two reps banked, the more recent one tapped
        XCTAssertEqual(log.marks.map { $0.manual }, [false, true])
    }

    /// start clears every mark
    func testStartClearsEveryMark() {
        let log = RepLog()
        log.start()
        log.follow(totalReps: 3, manualReps: 0, movement: .pullup, clockMs: 1_000)

        log.start()

        XCTAssertTrue(log.marks.isEmpty)
        log.follow(totalReps: 1, manualReps: 0, movement: .pullup, clockMs: 500)
        XCTAssertEqual(log.marks.count, 1)
    }
}
