import XCTest
import CindyCore
import CindyFixtures

/// The athlete whose arms never straighten, and the difference between a standard and a lockout.
///
/// Someone hanging in a band, or with limited elbow extension, may never reach the dead-hang
/// floor. Two separate things used to follow from that, and only one of them was a movement
/// standard:
///
///  - The bar was never established. An unknown bar has no line, so every pull-up frame was
///    refused before any gate was consulted, and the whole workout scored zero under "Hang from
///    the bar" — with no overlay drawn, because the overlay is the bar. That was a lockout.
///  - The dead-hang reset never armed, so nothing counted. That one *is* the strict standard: a
///    strict pull-up starts from a dead hang, and an athlete who cannot reach one is not doing
///    the strict movement. The answer to it is a variation, not a looser strict mode.
///
/// These tests hold that line: the bar is now findable without a dead hang, and strict counting
/// is exactly as strict as it was.
///
/// Mirrors `LimitedExtensionPullupTest.kt`; it replaces the old checks' class of the same subject.
final class LimitedExtensionPullupTests: XCTestCase {

    /// As straight as this athlete's arms get — well under the floor a dead hang needs.
    private let straightest: Float = 120

    /// hands held still overhead locate the bar when no dead hang ever comes
    func testHandsHeldStillOverheadLocateTheBarWhenNoDeadHangEverComes() {
        let d = Rig(fixedExercise: .pullup)
        let hang = PoseFixtures.pullup(straightest)

        d.hold(hang, frames: 20)
        XCTAssertFalse(d.engine.barKnown, "two seconds is not yet sustained stillness")

        d.hold(hang, frames: 15)
        XCTAssertTrue(d.engine.barKnown, "a still overhead hang eventually locates the bar")
    }

    /// The fallback is a fallback: a real dead hang still establishes the bar immediately, so a
    /// strict athlete never waits three seconds for an overlay.
    ///
    /// a dead hang still locates the bar at once
    func testADeadHangStillLocatesTheBarAtOnce() {
        let d = Rig(fixedExercise: .pullup)

        d.hold(PoseFixtures.pullup(170), frames: 1)

        XCTAssertTrue(d.engine.barKnown, "one straight-armed frame is enough")
    }

    /// Moving hands are not a hang.
    ///
    /// This is the case the dead-hang requirement was really guarding: someone walking up to the
    /// bar with their arms overhead taught a bar in the wrong place and then spent the rest of the
    /// clip being refused by it. Drift restarts the dwell, so the walk-up never settles.
    ///
    /// hands drifting across the frame do not locate a bar
    func testHandsDriftingAcrossTheFrameDoNotLocateABar() {
        let d = Rig(fixedExercise: .pullup)

        for step in 0..<12 {
            var walking = PoseFixtures.pullup(straightest)
            let shift = Float(step) * 30
            for i in [KP.nose, KP.leftShoulder, KP.rightShoulder, KP.leftElbow, KP.rightElbow,
                      KP.leftWrist, KP.rightWrist, KP.leftHip, KP.rightHip] {
                walking[i] = Keypoint(x: walking[i].x + shift, y: walking[i].y, score: walking[i].score)
            }
            d.hold(walking, frames: 5)
        }

        XCTAssertFalse(d.engine.barKnown, "a walk-up never settles, so it teaches nothing")
    }

    /// The standard, unchanged.
    ///
    /// Full range of motion — sixty degrees of elbow travel, head over the bar and back below the
    /// reset line — but never a straight arm, so a strict pull-up is not what happened.
    ///
    /// strict mode still refuses to score an athlete who never dead hangs
    func testStrictModeStillRefusesToScoreAnAthleteWhoNeverDeadHangs() {
        let d = Rig(fixedExercise: .pullup)

        d.hold(PoseFixtures.pullup(straightest), frames: 35)
        XCTAssertTrue(d.engine.barKnown, "the bar is known, so the refusal is the gate and not the geometry")

        for _ in 0..<5 {
            d.hold(PoseFixtures.pullup(60), frames: 8)
            d.hold(PoseFixtures.pullup(straightest), frames: 8)
        }

        XCTAssertEqual(d.engine.reps, 0, "a strict pull-up starts from a dead hang")
    }
}
