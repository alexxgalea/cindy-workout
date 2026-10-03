import XCTest
import CindyCore

/// Mirrors `SplitBookTest.kt`.
final class SplitBookTests: XCTestCase {

    /// a set is timed from the end of the one before
    func testASetIsTimedFromTheEndOfTheOneBefore() {
        let book = SplitBook()
        book.start()
        book.movementDone(.pullup, atMs: 14_000, reps: 5, manualTotal: 0)
        book.movementDone(.pushup, atMs: 31_000, reps: 10, manualTotal: 0)
        XCTAssertEqual(book.sets.map { $0.ms }, [14_000, 17_000])
    }

    /// a skipped set is kept but not complete
    func testASkippedSetIsKeptButNotComplete() {
        let book = SplitBook()
        book.start()
        book.movementDone(.pullup, atMs: 9_000, reps: 2, manualTotal: 0)
        let set = book.sets[0]
        XCTAssertEqual(book.sets.count, 1)
        XCTAssertEqual(set.reps, 2)
        XCTAssertFalse(set.complete)
        XCTAssertFalse(set.measured)
    }

    /// a complete set with no tapped reps is measured
    func testACompleteSetWithNoTappedRepsIsMeasured() {
        let book = SplitBook()
        book.start()
        book.movementDone(.pullup, atMs: 14_000, reps: 5, manualTotal: 0)
        XCTAssertTrue(book.sets[0].complete)
        XCTAssertTrue(book.sets[0].measured)
    }

    /// tapped reps count per set
    func testTappedRepsCountPerSet() {
        let book = SplitBook()
        book.start()
        book.movementDone(.pullup, atMs: 14_000, reps: 5, manualTotal: 2)
        book.movementDone(.pushup, atMs: 31_000, reps: 10, manualTotal: 5)
        book.movementDone(.squat, atMs: 50_000, reps: 15, manualTotal: 5)
        XCTAssertEqual(book.sets.map { $0.manualReps }, [2, 3, 0])
        XCTAssertEqual(book.sets.map { $0.measured }, [false, false, true])
    }

    /// stepping back reopens the set from its original start
    func testSteppingBackReopensTheSetFromItsOriginalStart() {
        let book = SplitBook()
        book.start()
        book.movementDone(.pullup, atMs: 14_000, reps: 5, manualTotal: 0)
        book.movementDone(.pushup, atMs: 31_000, reps: 10, manualTotal: 0)
        book.stepBack()
        XCTAssertEqual(book.sets.count, 1)
        book.movementDone(.pushup, atMs: 40_000, reps: 10, manualTotal: 0)
        XCTAssertEqual(book.sets.last?.ms, 26_000)
    }

    /// stepping back over tapped reps restores the manual baseline
    func testSteppingBackOverTappedRepsRestoresTheManualBaseline() {
        let book = SplitBook()
        book.start()
        book.movementDone(.pullup, atMs: 14_000, reps: 5, manualTotal: 1)
        book.movementDone(.pushup, atMs: 31_000, reps: 10, manualTotal: 4)
        book.stepBack()
        book.movementDone(.pushup, atMs: 40_000, reps: 10, manualTotal: 4)
        XCTAssertEqual(book.sets.last?.manualReps, 3)
    }

    /// stepping back with nothing done is a no-op
    func testSteppingBackWithNothingDoneIsANoOp() {
        let book = SplitBook()
        book.start()
        book.stepBack()
        XCTAssertTrue(book.sets.isEmpty)
        book.movementDone(.pullup, atMs: 12_000, reps: 5, manualTotal: 0)
        XCTAssertEqual(book.sets[0].ms, 12_000)
    }

    /// start clears everything
    func testStartClearsEverything() {
        let book = SplitBook()
        book.start()
        book.movementDone(.pullup, atMs: 14_000, reps: 5, manualTotal: 3)
        book.start()
        XCTAssertTrue(book.sets.isEmpty)
        book.movementDone(.pullup, atMs: 10_000, reps: 5, manualTotal: 0)
        XCTAssertEqual(book.sets.count, 1)
        XCTAssertEqual(book.sets[0].ms, 10_000)
        XCTAssertEqual(book.sets[0].manualReps, 0)
    }
}
