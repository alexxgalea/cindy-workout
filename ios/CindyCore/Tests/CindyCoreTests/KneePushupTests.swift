import XCTest
import CindyCore
import CindyFixtures

/// Characterisation, not a spec of what ought to happen: the push-up signal is the elbow angle
/// alone and the gate in front of it asks only which way the torso points, so a kneeling athlete
/// already passes both. No ankle, knee or shoulder-hip-ankle line is consulted anywhere in the
/// movement, so there is no strictness rule here to relax for an adaptive mode.
///
/// Carried over from the `CindyCoreChecks` executable: Knee push-up. Every check keeps its original wording as
/// its assertion message.
final class KneePushupTests: XCTestCase {

    func testAKneePushUpScoresAsAPushUpTheEngineHasNoRuleItBreaks() {
        let r = Rig(fixedExercise: .pushup)
        r.hold(PoseFixtures.kneePushup(175))
        for _ in 0..<3 {
            r.hold(PoseFixtures.kneePushup(80))
            r.hold(PoseFixtures.kneePushup(175))
        }
        XCTAssertEqual(r.engine.reps, 3, "a knee push-up scores as a push-up: the engine has no rule it breaks")

        // Both fixtures put the same shoulder-elbow-wrist chain in front of the camera; they differ
        // only below the hips, where nothing looks.
        let strict = Rig(fixedExercise: .pushup)
        let knees = Rig(fixedExercise: .pushup)
        strict.hold(PoseFixtures.pushup(175))
        knees.hold(PoseFixtures.kneePushup(175))
        for _ in 0..<4 {
            strict.hold(PoseFixtures.pushup(80)); strict.hold(PoseFixtures.pushup(175))
            knees.hold(PoseFixtures.kneePushup(80)); knees.hold(PoseFixtures.kneePushup(175))
        }
        XCTAssertEqual(strict.engine.reps, knees.engine.reps, "the engine cannot tell a knee push-up from a standard one")
        XCTAssertEqual(strict.engine.signal, knees.engine.signal, accuracy: 0.01, "same elbow angle, same signal")
    }

    func testHandsOverToPushUpsAtFive() {
        // The same finding through the normal Cindy flow, where push-ups are entered from the start
        // gate that stops the walk to the floor from scoring a rep. `inStartPosition` asks only
        // `!upright`, and a kneeling plank's torso is horizontal, so the gate opens for a kneeling
        // athlete exactly as it does for a prone one.
        let r = Rig()
        for _ in 0..<5 { r.pullup() }
        XCTAssertEqual(r.engine.exercise, .pushup, "hands over to push-ups at five")
        XCTAssertEqual(r.engine.awaitingStart, true, "push-ups are entered awaiting the start position")
        r.hold(PoseFixtures.kneePushup(175))
        XCTAssertEqual(r.engine.awaitingStart, false, "kneeling satisfies the start gate")
        for _ in 0..<9 {
            r.hold(PoseFixtures.kneePushup(80))
            r.hold(PoseFixtures.kneePushup(175))
        }
        XCTAssertEqual(r.engine.reps, 9, "nine knee push-ups scored")
        r.hold(PoseFixtures.kneePushup(80))
        r.hold(PoseFixtures.kneePushup(175))
        XCTAssertEqual(r.engine.exercise, .squat, "the tenth finishes the block")
    }
}
