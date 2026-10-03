import XCTest
import CindyCore
import CindyFixtures

/// Carried over from the `CindyCoreChecks` executable: Setup. Every check keeps its original wording as
/// its assertion message.
final class SetupTests: XCTestCase {

    func testAnEmptyFrameStaysAtFraming() {
        let r = Rig()
        r.engine.beginSetup()
        let s = r.setupHold(PoseFixtures.empty(), frames: 3)
        XCTAssertEqual(s.stage, .framing, "an empty frame stays at framing")
        XCTAssertEqual(s.missing.contains("hands"), true, "and names the hands as missing")
    }

    func testAFramedBodyMovesOnToCalibration() {
        let r = Rig()
        r.engine.beginSetup()
        var s = r.setupHold(PoseFixtures.pullup(170))
        XCTAssertEqual(s.stage, .moving, "a framed body moves on to calibration")
        for _ in 0..<2 {
            _ = r.setupHold(PoseFixtures.pullup(170))
            s = r.setupHold(PoseFixtures.pullup(60))
        }
        XCTAssertEqual(s.stage, .ready, "two calibration reps get the workout going")
    }

    func testAPhoneThatCannotSeeTheMovementIsCalledOut() {
        let r = Rig()
        r.engine.beginSetup()
        var s: Setup!
        for _ in 0..<12 {
            _ = r.setupHold(PoseFixtures.pullup(170))
            s = r.setupHold(PoseFixtures.pullup(155))
        }
        XCTAssertEqual(s.stage, .poor, "a phone that cannot see the movement is called out")
    }

    func testSetupRepsDoNotCountTowardTheWorkout() {
        let r = Rig()
        r.engine.beginSetup()
        for _ in 0..<2 {
            _ = r.setupHold(PoseFixtures.pullup(170))
            _ = r.setupHold(PoseFixtures.pullup(55))
        }
        r.engine.finishSetup()
        XCTAssertEqual(r.engine.reps, 0, "setup reps do not count toward the workout")
        XCTAssertTrue(r.engine.learnedRange > 90, "but the band they taught survives")
    }
}
