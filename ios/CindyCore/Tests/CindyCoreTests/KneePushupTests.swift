import XCTest
import CindyCore
import CindyFixtures

/// What the push-up path can and cannot see, pinned down.
///
/// These are characterisation tests, not a specification of what *ought* to happen: they record
/// that a knee push-up already scores as a push-up, and why. The push-up signal is the elbow angle
/// alone, and the gate in front of it asks only which way the torso points — so a kneeling athlete
/// passes both. No ankle, knee or shoulder-hip-ankle line is consulted anywhere in the movement,
/// which means there is no strictness rule here to relax for an adaptive mode, and none to tighten
/// without newly excluding people the app currently counts.
///
/// Kept as a permanent fixture: if a future change starts refusing these reps, that is a product
/// decision about who the app is for, and it should have to break a test to make it.
///
/// Mirrors `KneePushupTest.kt`; it replaces the old checks' class of the same subject.
final class KneePushupTests: XCTestCase {

    /// Settles at the top, which is also what satisfies the start gate.
    private func settleAtTop(_ d: Rig, _ pose: (Float) -> [Keypoint]) {
        d.hold(pose(175))
    }

    /// `n` descents and returns. Reps book at the top.
    private func pushups(_ d: Rig, _ n: Int, _ pose: (Float) -> [Keypoint]) {
        for _ in 0..<n {
            d.hold(pose(80))
            d.hold(pose(175))
        }
    }

    private func pullups(_ d: Rig, _ n: Int) {
        for _ in 0..<n {
            d.hold(PoseFixtures.pullup(170))
            d.hold(PoseFixtures.pullup(60))
        }
    }

    /// a knee push-up scores as a push-up
    func testAKneePushUpScoresAsAPushUp() {
        let d = Rig(fixedExercise: .pushup)

        settleAtTop(d, PoseFixtures.kneePushup)
        pushups(d, 3, PoseFixtures.kneePushup)

        XCTAssertEqual(d.engine.reps, 3, "the engine has no rule a knee push-up breaks")
    }

    /// The mechanical reason, stated as an assertion rather than a comment.
    ///
    /// Both fixtures put the same shoulder-elbow-wrist chain in front of the camera; they differ
    /// only below the hips, where nothing looks.
    ///
    /// the engine cannot tell a knee push-up from a standard one
    func testTheEngineCannotTellAKneePushUpFromAStandardOne() {
        let strict = Rig(fixedExercise: .pushup)
        let knees = Rig(fixedExercise: .pushup)

        settleAtTop(strict, PoseFixtures.pushup)
        settleAtTop(knees, PoseFixtures.kneePushup)
        pushups(strict, 4, PoseFixtures.pushup)
        pushups(knees, 4, PoseFixtures.kneePushup)

        XCTAssertEqual(strict.engine.reps, knees.engine.reps)
        XCTAssertEqual(strict.engine.signal, knees.engine.signal, accuracy: 0.01, "same elbow angle, same signal")
    }

    /// The same finding in the real Cindy flow, where push-ups are entered from the start gate
    /// that stops the walk to the floor scoring a rep.
    ///
    /// The start position asks only that the torso is not upright, and a kneeling plank's torso
    /// is horizontal, so the gate opens for a kneeling athlete exactly as it does for a prone one.
    ///
    /// knee push-ups count through the normal round transition
    func testKneePushUpsCountThroughTheNormalRoundTransition() {
        let d = Rig()

        pullups(d, 5)
        XCTAssertEqual(d.engine.exercise, .pushup)
        XCTAssertTrue(d.engine.awaitingStart, "push-ups are entered awaiting the start position")

        settleAtTop(d, PoseFixtures.kneePushup)
        XCTAssertFalse(d.engine.awaitingStart, "kneeling satisfies the start gate")

        pushups(d, 9, PoseFixtures.kneePushup)
        XCTAssertEqual(d.engine.reps, 9, "nine knee push-ups scored")

        pushups(d, 1, PoseFixtures.kneePushup)
        XCTAssertEqual(d.engine.exercise, .squat, "the tenth finishes the block")
    }
}
