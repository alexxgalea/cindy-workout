import XCTest
import CindyCore
import CindyFixtures

/// Occlusion handling on the bar.
///
/// A pull-up hides its own keypoints exactly where the rep is decided: at the top the head tilts
/// back and the wrists pass behind it. The engine used to treat the first unreadable frame as
/// "left the bar" and throw the cycle away, which cost nine of every ten reps on real footage.
/// These tests pin the replacement rule — a short blackout is ridden out, a long one is not —
/// without loosening what it means to be on the bar.
///
/// Mirrors `PullupOcclusionTest.kt`.
final class PullupOcclusionTests: XCTestCase {

    private var clock: Int64 = 0

    private func hold(_ e: WorkoutEngine, _ pose: [Keypoint], frames: Int = 10) {
        for _ in 0..<frames {
            _ = e.onFrame(pose, now: clock)
            clock += 100
        }
    }

    /// a brief head dropout at the top does not lose the rep
    func testABriefHeadDropoutAtTheTopDoesNotLoseTheRep() {
        let e = WorkoutEngine()
        hold(e, PoseFixtures.pullup(170))
        // The nose vanishes for a few frames just as the chin clears the bar.
        hold(e, PoseFixtures.pullup(60).hiding(KP.nose), frames: 4)
        hold(e, PoseFixtures.pullup(60))
        XCTAssertEqual(e.reps, 1, "a four-frame blackout must not cancel the rep")
    }

    /// a brief wrist dropout at the top does not lose the rep
    func testABriefWristDropoutAtTheTopDoesNotLoseTheRep() {
        let e = WorkoutEngine()
        hold(e, PoseFixtures.pullup(170))
        hold(e, PoseFixtures.pullup(60).hiding(KP.leftWrist), frames: 4)
        hold(e, PoseFixtures.pullup(60))
        XCTAssertEqual(e.reps, 1)
    }

    /// a sustained dropout ends the cycle
    func testASustainedDropoutEndsTheCycle() {
        let e = WorkoutEngine()
        hold(e, PoseFixtures.pullup(170))
        // Long enough to be indistinguishable from having dropped off the bar.
        hold(e, PoseFixtures.pullup(60).hiding(KP.nose), frames: 20)
        hold(e, PoseFixtures.pullup(60))
        XCTAssertEqual(e.reps, 0, "a long blackout must not be ridden out")
    }

    /// a cycle killed by a long dropout recovers on the next dead hang
    func testACycleKilledByALongDropoutRecoversOnTheNextDeadHang() {
        let e = WorkoutEngine()
        hold(e, PoseFixtures.pullup(170))
        hold(e, PoseFixtures.pullup(60).hiding(KP.nose), frames: 20)
        hold(e, PoseFixtures.pullup(60))
        XCTAssertEqual(e.reps, 0)

        hold(e, PoseFixtures.pullup(170))
        hold(e, PoseFixtures.pullup(60))
        XCTAssertEqual(e.reps, 1, "the athlete is not locked out after one bad rep")
    }

    /// push-up motion under the bar never scores a pull-up
    func testPushUpMotionUnderTheBarNeverScoresAPullUp() {
        let e = WorkoutEngine()
        // Same elbow swing, but the hands are on the floor rather than overhead.
        for _ in 0..<6 {
            hold(e, PoseFixtures.pushup(170))
            hold(e, PoseFixtures.pushup(70))
        }
        XCTAssertEqual(e.reps, 0)
    }

    /// one clean rep then leaving the bar still counts one
    func testOneCleanRepThenLeavingTheBarStillCountsOne() {
        let e = WorkoutEngine()
        hold(e, PoseFixtures.pullup(170))
        hold(e, PoseFixtures.pullup(60))
        XCTAssertEqual(e.reps, 1)

        // Steps down and repeats the identical arm movement on the floor.
        for _ in 0..<4 {
            hold(e, PoseFixtures.pullup(170).moved(dx: 0, dy: 400))
            hold(e, PoseFixtures.pullup(60).moved(dx: 0, dy: 400))
        }
        XCTAssertEqual(e.reps, 1, "off-bar repetitions must not add to the score")
    }

    /// partial reps whose chin never crosses the bar do not count
    func testPartialRepsWhoseChinNeverCrossesTheBarDoNotCount() {
        let e = WorkoutEngine()
        for _ in 0..<5 {
            hold(e, PoseFixtures.pullup(170))
            hold(e, PoseFixtures.pullup(120))
        }
        XCTAssertEqual(e.reps, 0)
    }

    /// a dropout while off the bar cannot revive the cycle
    func testADropoutWhileOffTheBarCannotReviveTheCycle() {
        let e = WorkoutEngine()
        // Learn the bar from one honest rep.
        hold(e, PoseFixtures.pullup(170))
        hold(e, PoseFixtures.pullup(60))
        XCTAssertEqual(e.reps, 1)

        // Drop off the bar, then go unreadable there. The blackout must not be treated as a
        // continuation of an on-bar cycle.
        hold(e, PoseFixtures.pullup(170).moved(dx: 0, dy: 400))
        hold(e, PoseFixtures.pullup(60).moved(dx: 0, dy: 400).hiding(KP.nose), frames: 4)
        hold(e, PoseFixtures.pullup(60).moved(dx: 0, dy: 400))
        XCTAssertEqual(e.reps, 1)
    }

    /// exactly the dropout limit keeps the cycle armed
    func testExactlyTheDropoutLimitKeepsTheCycleArmed() {
        let e = WorkoutEngine()
        hold(e, PoseFixtures.pullup(170))
        // The limit is eight frames; the cycle ends only on the frame *after* it.
        hold(e, PoseFixtures.pullup(60).hiding(KP.nose), frames: 8)
        hold(e, PoseFixtures.pullup(60))
        XCTAssertEqual(e.reps, 1, "eight frames is the documented limit, not one past it")
    }

    /// one frame past the dropout limit clears the cycle
    func testOneFramePastTheDropoutLimitClearsTheCycle() {
        let e = WorkoutEngine()
        hold(e, PoseFixtures.pullup(170))
        hold(e, PoseFixtures.pullup(60).hiding(KP.nose), frames: 9)
        hold(e, PoseFixtures.pullup(60))
        XCTAssertEqual(e.reps, 0, "the ninth consecutive blackout ends the cycle")
    }

    /// the band keeps learning while the head gate is shut
    func testTheBandKeepsLearningWhileTheHeadGateIsShut() {
        let e = WorkoutEngine()
        hold(e, PoseFixtures.pullup(170))
        let atHang = e.learnedRange

        // Pulls up, but the chin stays below the bar. Nothing may score, yet the movement is still
        // evidence of this athlete's range — that is the mayCount contract.
        hold(e, PoseFixtures.pullup(120))
        XCTAssertEqual(e.reps, 0)
        XCTAssertGreaterThan(e.learnedRange, atHang,
                             "observations must widen the band even when no rep can book")
    }

    /// a frame refused outside the bar zone names that gate
    func testAFrameRefusedOutsideTheBarZoneNamesThatGate() {
        let e = WorkoutEngine()
        hold(e, PoseFixtures.pullup(170))
        hold(e, PoseFixtures.pullup(60).moved(dx: 0, dy: 400))
        XCTAssertEqual(e.hint, "Get on the bar")
        XCTAssertFalse(e.diagnostics.barGateOpen)
    }
}
