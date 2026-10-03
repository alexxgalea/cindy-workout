import XCTest
import CindyCore
import CindyFixtures

/// Carried over from the `CindyCoreChecks` executable: Undo and recalibrate. Every check keeps its original wording as
/// its assertion message.
final class UndoAndRecalibrateTests: XCTestCase {

    func testMinusReportsAnUndo() {
        let r = Rig()
        for _ in 0..<3 { r.pullup() }
        XCTAssertEqual(r.engine.undoRep(), .undo, "minus reports an undo")
        XCTAssertEqual(r.engine.reps, 2, "and drops the count")
    }

    func testMinusStepsBackOverAMovementBoundary() {
        let r = Rig()
        for _ in 0..<5 { r.pullup() }
        _ = r.engine.undoRep()
        XCTAssertEqual(r.engine.exercise, .pullup, "minus steps back over a movement boundary")
        XCTAssertEqual(r.engine.reps, 4, "landing on the last rep of the previous movement")
    }

    func testMinusStepsBackOverARoundBoundary() {
        let r = Rig()
        for _ in 0..<5 { r.pullup() }
        for _ in 0..<10 { r.pushup() }
        for _ in 0..<15 { r.squat() }
        _ = r.engine.undoRep()
        XCTAssertEqual(r.engine.rounds, 0, "minus steps back over a round boundary")
        XCTAssertEqual(r.engine.exercise, .squat, "onto the previous round's squats")
        XCTAssertEqual(r.engine.totalReps, 29, "and the total follows")
    }

    func testMinusAtZeroDoesNothing() {
        let r = Rig()
        XCTAssertEqual(r.engine.undoRep(), RepEvent.none, "minus at zero does nothing")
        XCTAssertEqual(r.engine.totalReps, 0, "and leaves the score alone")
    }

    func testRecalibratingKeepsTheReps() {
        let r = Rig()
        for _ in 0..<3 { r.pullup() }
        r.engine.recalibrate()
        XCTAssertEqual(r.engine.reps, 3, "recalibrating keeps the reps")
        XCTAssertEqual(r.engine.calibrated, false, "but forgets the band")
        for _ in 0..<2 { r.pullup() }
        XCTAssertEqual(r.engine.exercise, .pushup, "and re-learns from the next reps")
    }
}
