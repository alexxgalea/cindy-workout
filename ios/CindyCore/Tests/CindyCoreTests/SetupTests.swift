import XCTest
import CindyCore
import CindyFixtures

/// The pre-workout check: is the camera placed somewhere this movement can be read from?
///
/// Mirrors `SetupTest.kt`; it replaces the old checks' "Setup" class, whose scenarios are in it.
final class SetupTests: XCTestCase {

    private var clock: Int64 = 0

    @discardableResult
    private func setupHold(_ e: WorkoutEngine, _ pose: [Keypoint], frames: Int = 10, stepMs: Int64 = 100) -> Setup {
        var last = e.onSetupFrame(pose, now: clock)
        for _ in 0..<frames {
            last = e.onSetupFrame(pose, now: clock)
            clock += stepMs
        }
        return last
    }

    private func engine() -> WorkoutEngine {
        let e = WorkoutEngine()
        e.beginSetup()
        return e
    }

    /// an empty frame names nothing it can see
    func testAnEmptyFrameNamesNothingItCanSee() {
        let e = engine()
        let s = setupHold(e, PoseFixtures.empty(), frames: 3)
        XCTAssertEqual(s.stage, .framing)
        XCTAssertTrue(Set(s.missing).isSuperset(of: ["shoulders", "elbows", "hands", "hips"]))
    }

    /// framing complains about the joints that are actually missing
    func testFramingComplainsAboutTheJointsThatAreActuallyMissing() {
        let e = engine()
        var noHands = PoseFixtures.pullup(170)
        noHands[KP.leftWrist] = .missing
        noHands[KP.rightWrist] = .missing
        let s = setupHold(e, noHands, frames: 3)
        XCTAssertEqual(s.stage, .framing)
        XCTAssertEqual(s.missing, ["hands"])
    }

    /// two calibration reps get the workout going
    func testTwoCalibrationRepsGetTheWorkoutGoing() {
        let e = engine()
        // Nothing may score while the setup check is still running.
        XCTAssertEqual(e.onFrame(PoseFixtures.pullup(60), now: clock), .none)
        XCTAssertEqual(e.reps, 0)
        var last = setupHold(e, PoseFixtures.pullup(170))
        XCTAssertEqual(last.stage, .moving)
        for _ in 0..<2 {
            setupHold(e, PoseFixtures.pullup(170))
            last = setupHold(e, PoseFixtures.pullup(60))
        }
        XCTAssertEqual(last.stage, .ready)
        XCTAssertEqual(last.reps, 2)
    }

    /// calibrating from a low phone also gets going
    func testCalibratingFromALowPhoneAlsoGetsGoing() {
        let e = engine()
        var last: Setup?
        for _ in 0..<2 {
            setupHold(e, PoseFixtures.pullup(150))
            last = setupHold(e, PoseFixtures.pullup(90))
        }
        XCTAssertEqual(last?.stage, .ready)
    }

    /// a phone that cannot see the movement is called out rather than tolerated
    func testAPhoneThatCannotSeeTheMovementIsCalledOutRatherThanTolerated() {
        let e = engine()
        var last: Setup?
        // Twenty-five seconds of a barely-there swing: framing is fine, placement is not.
        for _ in 0..<12 {
            setupHold(e, PoseFixtures.pullup(170))
            last = setupHold(e, PoseFixtures.pullup(155))
        }
        XCTAssertEqual(last?.stage, .poor)
        XCTAssertLessThan(last!.range, last!.needed)
    }

    /// the band survives setup so the first real rep is judged against it
    func testTheBandSurvivesSetupSoTheFirstRealRepIsJudgedAgainstIt() {
        let e = engine()
        for _ in 0..<2 {
            setupHold(e, PoseFixtures.pullup(170))
            setupHold(e, PoseFixtures.pullup(55))
        }
        let learned = e.learnedRange
        XCTAssertGreaterThan(learned, 90, "expected a learned range, got \(learned)")

        e.finishSetup()
        XCTAssertEqual(e.reps, 0)
        XCTAssertGreaterThan(e.learnedRange, 90, "band should outlive the calibration reps")

        // A half rep against a band learned from full ones must not score.
        setupHold(e, PoseFixtures.pullup(170), frames: 1)
        var event = RepEvent.none
        for _ in 0..<10 { event = e.onFrame(PoseFixtures.pullup(170), now: clock); clock += 100 }
        for _ in 0..<10 { event = e.onFrame(PoseFixtures.pullup(120), now: clock); clock += 100 }
        XCTAssertEqual(e.reps, 0)
        XCTAssertEqual(event, .none)
    }

    /// squat setup asks for the leg joints
    func testSquatSetupAsksForTheLegJoints() {
        let e = WorkoutEngine()
        _ = e.skipExercise()
        _ = e.skipExercise()
        e.beginSetup()
        XCTAssertEqual(e.exercise, .squat)
        let s = setupHold(e, PoseFixtures.empty(), frames: 3)
        XCTAssertTrue(Set(s.missing).isSuperset(of: ["hips", "knees", "ankles"]))
    }
}
