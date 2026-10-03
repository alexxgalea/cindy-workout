import XCTest
import CindyCore
import CindyFixtures

/// Carried over from the `CindyCoreChecks` executable: WorkoutEngine. Every check keeps its original wording as
/// its assertion message.
final class WorkoutEngineTests: XCTestCase {

    func testStartsOnPullUps() {
        let r = Rig()
        XCTAssertEqual(r.engine.exercise, .pullup, "starts on pull-ups")
    }

    func testAnEmptyFrameIsNotABody() {
        let r = Rig()
        r.hold(PoseFixtures.empty(), frames: 5)
        XCTAssertEqual(r.engine.bodyVisible, false, "an empty frame is not a body")
        XCTAssertEqual(r.engine.hint, "Step into frame", "and says so")
    }

    func testPullUpsCount() {
        let r = Rig()
        for _ in 0..<4 { r.pullup() }
        XCTAssertEqual(r.engine.reps, 4, "pull-ups count")
        r.pullup()
        XCTAssertEqual(r.engine.exercise, .pushup, "and hand over at five")
    }

    func testAFullRoundCloses() {
        let r = Rig()
        for _ in 0..<5 { r.pullup() }
        for _ in 0..<10 { r.pushup() }
        for _ in 0..<15 { r.squat() }
        XCTAssertEqual(r.engine.rounds, 1, "a full round closes")
        XCTAssertEqual(r.engine.exercise, .pullup, "and restarts on pull-ups")
        XCTAssertEqual(r.engine.totalReps, 30, "thirty reps to the round")
    }

    func testAPullUpFromALowPhoneStillCounts() {
        let r = Rig()
        for _ in 0..<5 { r.pullup(hang: 150, top: 90) }
        XCTAssertEqual(r.engine.exercise, .pushup, "a pull-up from a low phone still counts")
    }

    func testShouldersAboveTheHandsDoesNotVoidTheRep() {
        let r = Rig()
        for _ in 0..<5 { r.pullup(hang: 175, top: 45) }
        XCTAssertEqual(r.engine.exercise, .pushup, "shoulders above the hands does not void the rep")
    }

    func testBarelyBendingTheArmsScoresNothing() {
        let r = Rig()
        for _ in 0..<5 {
            r.hold(PoseFixtures.pullup(170))
            r.hold(PoseFixtures.pullup(145))
        }
        XCTAssertEqual(r.engine.reps, 0, "barely bending the arms scores nothing")
    }

    func testFullRepsSetTheStandardForPartialOnes() {
        let r = Rig()
        for _ in 0..<2 { r.pullup(hang: 170, top: 55) }
        for _ in 0..<4 { r.pullup(hang: 170, top: 120) }
        XCTAssertEqual(r.engine.reps, 2, "full reps set the standard for partial ones")
    }

    func testPushUpsDoNotLeakIntoThePullUpBlock() {
        let r = Rig()
        for _ in 0..<6 { r.pushup() }
        XCTAssertEqual(r.engine.reps, 0, "push-ups do not leak into the pull-up block")
    }
}
