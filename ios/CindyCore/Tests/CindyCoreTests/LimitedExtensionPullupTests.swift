import XCTest
import CindyCore
import CindyFixtures

/// An athlete whose arms never straighten into a dead hang — limited extension, or a band taking
/// enough weight — used to never establish the bar at all, since establishing it required a dead
/// hang. Every frame was then refused under "Hang from the bar" and the workout scored zero
/// without ever explaining why. `settleBar` locates the bar from hands simply held still overhead.
///
/// Carried over from the `CindyCoreChecks` executable: Limited extension (bar settle). Every check keeps its original wording as
/// its assertion message.
final class LimitedExtensionPullupTests: XCTestCase {

    let bottom: Float = 120  // as straight as this athlete's arms get, well under a dead hang
    let top: Float = 60

    func testTwoSecondsIsNotYetSustainedStillness() {
        let r = Rig(fixedExercise: .pullup)
        r.hold(PoseFixtures.pullup(bottom), frames: 20)
        XCTAssertEqual(r.engine.barKnown, false, "two seconds is not yet sustained stillness")
        r.hold(PoseFixtures.pullup(bottom), frames: 15)
        XCTAssertEqual(r.engine.barKnown, true, "a still overhead hang eventually locates the bar")
    }

    func testADeadHangStillLocatesTheBarAtOnce() {
        // The fallback is a fallback: a real dead hang still establishes the bar immediately.
        let r = Rig(fixedExercise: .pullup)
        r.hold(PoseFixtures.pullup(170), frames: 1)
        XCTAssertEqual(r.engine.barKnown, true, "a dead hang still locates the bar at once")
    }

    func testAWalkUpNeverSettlesSoItTeachesNothing() {
        // The case the dead-hang requirement was really guarding: a walk-up with arms overhead must
        // not teach a bar in the wrong place. Drift restarts the dwell, so it never settles.
        let r = Rig(fixedExercise: .pullup)
        for step in 0..<12 {
            let shift = Float(step) * 30
            var walking = PoseFixtures.pullup(bottom)
            for i in [KP.nose, KP.leftShoulder, KP.rightShoulder, KP.leftElbow, KP.rightElbow,
                      KP.leftWrist, KP.rightWrist, KP.leftHip, KP.rightHip] {
                walking[i] = Keypoint(x: walking[i].x + shift, y: walking[i].y, score: walking[i].score)
            }
            r.hold(walking, frames: 5)
        }
        XCTAssertEqual(r.engine.barKnown, false, "a walk-up never settles, so it teaches nothing")
    }

    func testTheBarIsKnownSoTheRefusalBelowIsTheGateNotTheGeometry() {
        // The standard, unchanged: full range of motion but never a straight arm is not a strict
        // pull-up, and the bar being findable does not relax that.
        let r = Rig(fixedExercise: .pullup)
        r.hold(PoseFixtures.pullup(bottom), frames: 35)
        XCTAssertEqual(r.engine.barKnown, true, "the bar is known, so the refusal below is the gate, not the geometry")
        for _ in 0..<5 {
            r.hold(PoseFixtures.pullup(top), frames: 8)
            r.hold(PoseFixtures.pullup(bottom), frames: 8)
        }
        XCTAssertEqual(r.engine.reps, 0, "strict mode still refuses to score an athlete who never dead hangs")
    }
}
