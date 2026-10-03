import XCTest
import CindyCore
import CindyFixtures

/// The bar gate: elbow flexion only counts when the hands are actually on the bar.
///
/// Mirrors `BarGateTest.kt`; it also stands in for the old checks' "Bar gate" class.
final class BarGateTests: XCTestCase {

    private var clock: Int64 = 0

    private func hold(_ e: WorkoutEngine, _ pose: [Keypoint], frames: Int = 10) {
        for _ in 0..<frames {
            _ = e.onFrame(pose, now: clock)
            clock += 100
        }
    }

    private func doPullup(_ e: WorkoutEngine, hang: Float = 170, top: Float = 60) {
        hold(e, PoseFixtures.pullup(hang))
        hold(e, PoseFixtures.pullup(top))
    }

    /// the bar is unknown until someone hangs from it
    func testTheBarIsUnknownUntilSomeoneHangsFromIt() {
        let e = WorkoutEngine()
        XCTAssertFalse(e.barKnown)
        // A body the tracker has lost is not evidence about where the bar is.
        for _ in 0..<5 {
            _ = e.onFrame(PoseFixtures.pullup(170), now: clock, identityStable: false)
            clock += 100
        }
        XCTAssertFalse(e.barKnown)
        hold(e, PoseFixtures.pullup(170))
        XCTAssertTrue(e.barKnown, "a dead hang should mark the bar")
    }

    /// a bent-armed frame alone does not mark the bar
    func testABentArmedFrameAloneDoesNotMarkTheBar() {
        let e = WorkoutEngine()
        hold(e, PoseFixtures.pullup(60))
        XCTAssertFalse(e.barKnown)
        hold(e, PoseFixtures.pullup(170))

        // Bent elbows are not a rep on their own: the head has to clear the bar.
        var chinBelowBar = PoseFixtures.pullup(60)
        chinBelowBar[KP.nose] = Keypoint(x: 0, y: 0, score: 0.9)
        hold(e, chinBelowBar)
        XCTAssertEqual(e.reps, 0)
        XCTAssertEqual(e.hint, "Get your head over the bar")

        // A pull-up needs both grips, so one hand leaving the bar ends the rep.
        var oneHandOffBar = PoseFixtures.pullup(60)
        let left = oneHandOffBar[KP.leftWrist]
        oneHandOffBar[KP.leftWrist] = Keypoint(x: left.x + 1000, y: left.y, score: left.score)
        hold(e, oneHandOffBar)
        XCTAssertEqual(e.reps, 0)
        XCTAssertEqual(e.hint, "Get on the bar")

        // The invalidated cycle cannot be finished by a recovered top frame; it needs a fresh
        // dead hang first.
        hold(e, PoseFixtures.pullup(60))
        XCTAssertEqual(e.reps, 0)
        hold(e, PoseFixtures.pullup(170))
        hold(e, PoseFixtures.pullup(60))
        XCTAssertEqual(e.reps, 1)
    }

    /// reps at the bar count normally
    func testRepsAtTheBarCountNormally() {
        let e = WorkoutEngine()
        for _ in 0..<5 { doPullup(e) }
        XCTAssertEqual(e.exercise, .pushup)
    }

    /// the same arm movement well below the bar scores nothing
    func testTheSameArmMovementWellBelowTheBarScoresNothing() {
        let e = WorkoutEngine()
        // Learn the bar from two honest reps.
        for _ in 0..<2 { doPullup(e) }
        XCTAssertTrue(e.barKnown)
        XCTAssertEqual(e.reps, 2)

        // Now do the identical elbow movement 400px lower — off the bar, arms overhead.
        for _ in 0..<6 {
            hold(e, PoseFixtures.pullup(170).moved(dx: 0, dy: 400))
            hold(e, PoseFixtures.pullup(60).moved(dx: 0, dy: 400))
        }
        XCTAssertEqual(e.reps, 2, "arm-waving off the bar must not score")
        XCTAssertEqual(e.hint, "Get on the bar")
    }

    /// the same movement far to the side scores nothing
    func testTheSameMovementFarToTheSideScoresNothing() {
        let e = WorkoutEngine()
        for _ in 0..<2 { doPullup(e) }
        for _ in 0..<6 {
            hold(e, PoseFixtures.pullup(170).moved(dx: 500, dy: 0))
            hold(e, PoseFixtures.pullup(60).moved(dx: 500, dy: 0))
        }
        XCTAssertEqual(e.reps, 2)
    }

    /// stepping back onto the bar resumes counting
    func testSteppingBackOntoTheBarResumesCounting() {
        let e = WorkoutEngine()
        for _ in 0..<2 { doPullup(e) }
        for _ in 0..<2 {
            hold(e, PoseFixtures.pullup(170).moved(dx: 0, dy: 400))
            hold(e, PoseFixtures.pullup(60).moved(dx: 0, dy: 400))
        }
        XCTAssertEqual(e.reps, 2)
        for _ in 0..<3 { doPullup(e) }
        XCTAssertEqual(e.exercise, .pushup, "back on the bar, counting continues")
    }

    /// a small shift along the bar is still on the bar
    func testASmallShiftAlongTheBarIsStillOnTheBar() {
        let e = WorkoutEngine()
        for _ in 0..<2 { doPullup(e) }
        // Half a torso sideways is a regrip, not stepping off.
        for _ in 0..<3 {
            hold(e, PoseFixtures.pullup(170).moved(dx: 40, dy: 0))
            hold(e, PoseFixtures.pullup(60).moved(dx: 40, dy: 0))
        }
        XCTAssertEqual(e.exercise, .pushup)
    }

    /// recalibrating forgets the bar so a moved camera does not block counting
    func testRecalibratingForgetsTheBarSoAMovedCameraDoesNotBlockCounting() {
        let e = WorkoutEngine()
        for _ in 0..<2 { doPullup(e) }
        XCTAssertTrue(e.barKnown)
        e.recalibrate()
        XCTAssertFalse(e.barKnown, "a moved camera invalidates the bar's position")

        // The whole scene has shifted; counting must recover rather than stay blocked.
        for _ in 0..<3 {
            hold(e, PoseFixtures.pullup(170).moved(dx: 0, dy: 400))
            hold(e, PoseFixtures.pullup(60).moved(dx: 0, dy: 400))
        }
        XCTAssertEqual(e.exercise, .pushup)
    }

    /// setup learns the bar before the workout starts
    func testSetupLearnsTheBarBeforeTheWorkoutStarts() {
        let e = WorkoutEngine()
        e.beginSetup()
        for _ in 0..<2 {
            for _ in 0..<10 { _ = e.onSetupFrame(PoseFixtures.pullup(170), now: clock); clock += 100 }
            for _ in 0..<10 { _ = e.onSetupFrame(PoseFixtures.pullup(60), now: clock); clock += 100 }
        }
        XCTAssertTrue(e.barKnown, "calibration reps should mark the bar")
        e.finishSetup()
        XCTAssertTrue(e.barKnown, "and it survives into the workout")
    }

    /// off-bar movement at the same scale never re-learns the bar
    func testOffBarMovementAtTheSameScaleNeverReLearnsTheBar() {
        let e = WorkoutEngine()
        doPullup(e)
        XCTAssertEqual(e.reps, 1)

        // A long run of the identical movement on the floor. The body is the same size, so this is
        // someone who stepped down — not evidence that the bar was learned in the wrong place.
        for _ in 0..<10 {
            hold(e, PoseFixtures.pullup(170).moved(dx: 0, dy: 400))
            hold(e, PoseFixtures.pullup(60).moved(dx: 0, dy: 400))
        }
        XCTAssertEqual(e.reps, 1, "floor repetitions must never re-teach the bar")
    }

    /// a brief contradiction at another scale does not abandon the bar
    func testABriefContradictionAtAnotherScaleDoesNotAbandonTheBar() {
        let e = WorkoutEngine()
        hold(e, PoseFixtures.pullup(170))
        // Under the limit of 30 consecutive refused hangs.
        hold(e, PoseFixtures.pullup(170).scaled(0.4), frames: 20)
        hold(e, PoseFixtures.pullup(60).scaled(0.4))
        XCTAssertEqual(e.reps, 0, "the bar must not move on a brief contradiction")
    }

    /// a sustained contradiction at another scale re-learns the bar
    func testASustainedContradictionAtAnotherScaleReLearnsTheBar() {
        let e = WorkoutEngine()
        hold(e, PoseFixtures.pullup(170))
        // Past the limit: the athlete is plainly hanging, at a body scale the learned bar cannot
        // describe, so the estimate rather than the athlete is treated as wrong.
        hold(e, PoseFixtures.pullup(170).scaled(0.4), frames: 40)
        hold(e, PoseFixtures.pullup(60).scaled(0.4))
        XCTAssertEqual(e.reps, 1, "counting must recover once the bar is re-learned")
    }
}
