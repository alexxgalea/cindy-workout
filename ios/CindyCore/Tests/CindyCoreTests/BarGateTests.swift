import XCTest
import CindyCore
import CindyFixtures

/// Carried over from the `CindyCoreChecks` executable: Bar gate. Every check keeps its original wording as
/// its assertion message.
final class BarGateTests: XCTestCase {

    /// Shifts a whole body, as if the athlete stepped off the bar.
    func moved(_ k: [Keypoint], dx: Float, dy: Float) -> [Keypoint] {
        k.map { $0.score <= 0 ? $0 : Keypoint(x: $0.x + dx, y: $0.y + dy, score: $0.score) }
    }

    func testTheBarIsUnknownUntilSomeoneHangsFromIt() {
        let r = Rig()
        XCTAssertEqual(r.engine.barKnown, false, "the bar is unknown until someone hangs from it")
        r.hold(PoseFixtures.pullup(170))
        XCTAssertEqual(r.engine.barKnown, true, "a dead hang marks the bar")
    }

    func testABentArmedFrameAloneDoesNotMarkIt() {
        let r = Rig()
        r.hold(PoseFixtures.pullup(60))
        XCTAssertEqual(r.engine.barKnown, false, "a bent-armed frame alone does not mark it")
    }

    func testHonestRepsAtTheBarCount() {
        let r = Rig()
        for _ in 0..<2 { r.pullup() }
        XCTAssertEqual(r.engine.reps, 2, "honest reps at the bar count")
        for _ in 0..<6 {
            r.hold(moved(PoseFixtures.pullup(170), dx: 0, dy: 400))
            r.hold(moved(PoseFixtures.pullup(60), dx: 0, dy: 400))
        }
        XCTAssertEqual(r.engine.reps, 2, "the same arm movement off the bar scores nothing")
        XCTAssertEqual(r.engine.hint, "Get on the bar", "and says why")
    }

    func testAndNorDoesTheSameMovementFarToTheSide() {
        let r = Rig()
        for _ in 0..<2 { r.pullup() }
        for _ in 0..<6 {
            r.hold(moved(PoseFixtures.pullup(170), dx: 500, dy: 0))
            r.hold(moved(PoseFixtures.pullup(60), dx: 500, dy: 0))
        }
        XCTAssertEqual(r.engine.reps, 2, "and nor does the same movement far to the side")
    }

    func testSteppingBackOntoTheBarResumesCounting() {
        let r = Rig()
        for _ in 0..<2 { r.pullup() }
        for _ in 0..<2 {
            r.hold(moved(PoseFixtures.pullup(170), dx: 0, dy: 400))
            r.hold(moved(PoseFixtures.pullup(60), dx: 0, dy: 400))
        }
        for _ in 0..<3 { r.pullup() }
        XCTAssertEqual(r.engine.exercise, .pushup, "stepping back onto the bar resumes counting")
    }

    func testASmallShiftAlongTheBarIsStillOnTheBar() {
        let r = Rig()
        for _ in 0..<2 { r.pullup() }
        for _ in 0..<3 {
            r.hold(moved(PoseFixtures.pullup(170), dx: 40, dy: 0))
            r.hold(moved(PoseFixtures.pullup(60), dx: 40, dy: 0))
        }
        XCTAssertEqual(r.engine.exercise, .pushup, "a small shift along the bar is still on the bar")
    }

    func testRecalibratingForgetsTheBar() {
        let r = Rig()
        for _ in 0..<2 { r.pullup() }
        r.engine.recalibrate()
        XCTAssertEqual(r.engine.barKnown, false, "recalibrating forgets the bar")
        for _ in 0..<3 {
            r.hold(moved(PoseFixtures.pullup(170), dx: 0, dy: 400))
            r.hold(moved(PoseFixtures.pullup(60), dx: 0, dy: 400))
        }
        XCTAssertEqual(r.engine.exercise, .pushup, "so a moved camera does not block counting")
    }

    func testSetupLearnsTheBarBeforeTheWorkoutStarts() {
        let r = Rig()
        r.engine.beginSetup()
        for _ in 0..<2 {
            _ = r.setupHold(PoseFixtures.pullup(170))
            _ = r.setupHold(PoseFixtures.pullup(60))
        }
        XCTAssertEqual(r.engine.barKnown, true, "setup learns the bar before the workout starts")
        r.engine.finishSetup()
        XCTAssertEqual(r.engine.barKnown, true, "and it survives into the workout")
    }
}
