import XCTest
import CindyCore
import CindyFixtures

/// The Cindy progression end to end: the three movements in turn, rounds, the manual overrides,
/// takebacks and recalibration.
///
/// Mirrors `WorkoutEngineTest.kt`. It also stands in for the two classes the old checks became,
/// `WorkoutEngineTests` and `UndoAndRecalibrateTests`, whose scenarios are all in it.
final class WorkoutEngineTests: XCTestCase {

    private var clock: Int64 = 0

    /// Pushes one posture for several frames, advancing the clock, collecting events.
    @discardableResult
    private func hold(_ e: WorkoutEngine, _ pose: [Keypoint], frames: Int = 10, stepMs: Int64 = 100) -> [RepEvent] {
        var events: [RepEvent] = []
        for _ in 0..<frames {
            let event = e.onFrame(pose, now: clock)
            if event != .none { events.append(event) }
            clock += stepMs
        }
        return events
    }

    /// One rep, starting and finishing in the position the movement is held in.
    ///
    /// The leading frames matter: a squat begins standing and a push-up begins at lockout, and the
    /// engine will not score either until it has seen the athlete get there. Starting these
    /// helpers at the bottom instead described an athlete who materialises mid-rep, and let the
    /// climb up out of the previous movement count as the first rep of this one.
    private func doSquat(_ e: WorkoutEngine) {
        hold(e, PoseFixtures.squat(175))
        hold(e, PoseFixtures.squat(80))
        hold(e, PoseFixtures.squat(175))
    }

    private func doPushup(_ e: WorkoutEngine) {
        hold(e, PoseFixtures.pushup(175))
        hold(e, PoseFixtures.pushup(80))
        hold(e, PoseFixtures.pushup(175))
    }

    private func doPullup(_ e: WorkoutEngine, hang: Float = 170, top: Float = 60) {
        hold(e, PoseFixtures.pullup(hang))
        hold(e, PoseFixtures.pullup(top))
    }

    /// starts on pull-ups with a clean scorecard
    func testStartsOnPullUpsWithACleanScorecard() {
        let e = WorkoutEngine()
        XCTAssertEqual(e.exercise, .pullup)
        XCTAssertEqual(e.reps, 0)
        XCTAssertEqual(e.rounds, 0)
        XCTAssertEqual(e.totalReps, 0)
    }

    /// an empty frame reports the body as missing and scores nothing
    func testAnEmptyFrameReportsTheBodyAsMissingAndScoresNothing() {
        let e = WorkoutEngine()
        hold(e, PoseFixtures.empty(), frames: 5)
        XCTAssertFalse(e.bodyVisible)
        XCTAssertEqual(e.reps, 0)
        XCTAssertEqual(e.hint, "Step into frame")
    }

    /// pull-ups count and hand over to push-ups at five
    func testPullUpsCountAndHandOverToPushUpsAtFive() {
        let e = WorkoutEngine()
        for _ in 0..<4 { doPullup(e) }
        XCTAssertEqual(e.exercise, .pullup)
        XCTAssertEqual(e.reps, 4)

        doPullup(e)
        XCTAssertEqual(e.exercise, .pushup)
        XCTAssertEqual(e.reps, 0)
        XCTAssertEqual(e.repsThisRound, 5)
    }

    /// push-ups count and hand over to squats at ten
    func testPushUpsCountAndHandOverToSquatsAtTen() {
        let e = WorkoutEngine()
        for _ in 0..<5 { doPullup(e) }
        for _ in 0..<9 { doPushup(e) }
        XCTAssertEqual(e.exercise, .pushup)
        XCTAssertEqual(e.reps, 9)

        doPushup(e)
        XCTAssertEqual(e.exercise, .squat)
        XCTAssertEqual(e.repsThisRound, 15)
    }

    /// a full round of Cindy closes and restarts on pull-ups
    func testAFullRoundOfCindyClosesAndRestartsOnPullUps() {
        let e = WorkoutEngine()
        for _ in 0..<5 { doPullup(e) }
        for _ in 0..<10 { doPushup(e) }
        for _ in 0..<14 { doSquat(e) }
        XCTAssertEqual(e.rounds, 0)

        doSquat(e)
        XCTAssertEqual(e.rounds, 1)
        XCTAssertEqual(e.exercise, .pullup)
        XCTAssertEqual(e.reps, 0)
        XCTAssertEqual(e.totalReps, 30)
    }

    /// three full rounds score ninety reps
    func testThreeFullRoundsScoreNinetyReps() {
        let e = WorkoutEngine()
        for _ in 0..<3 {
            for _ in 0..<5 { doPullup(e) }
            for _ in 0..<10 { doPushup(e) }
            for _ in 0..<15 { doSquat(e) }
        }
        XCTAssertEqual(e.rounds, 3)
        XCTAssertEqual(e.totalReps, 90)
    }

    /// squatting during the pull-up block scores nothing
    func testSquattingDuringThePullUpBlockScoresNothing() {
        let e = WorkoutEngine()
        for _ in 0..<6 { doSquat(e) }
        XCTAssertEqual(e.exercise, .pullup)
        XCTAssertEqual(e.reps, 0)
    }

    /// push-up reps do not leak into the pull-up block
    func testPushUpRepsDoNotLeakIntoThePullUpBlock() {
        let e = WorkoutEngine()
        for _ in 0..<6 { doPushup(e) }
        XCTAssertEqual(e.exercise, .pullup)
        XCTAssertEqual(e.reps, 0)
        XCTAssertFalse(e.hint.isEmpty)
    }

    /// hanging on the bar during the push-up block scores nothing
    func testHangingOnTheBarDuringThePushUpBlockScoresNothing() {
        let e = WorkoutEngine()
        for _ in 0..<5 { doPullup(e) }
        XCTAssertEqual(e.exercise, .pushup)
        for _ in 0..<6 { doPullup(e) }
        XCTAssertEqual(e.reps, 0)
        XCTAssertEqual(e.exercise, .pushup)
    }

    /// a squat seen from a low phone still counts
    func testASquatSeenFromALowPhoneStillCounts() {
        let e = WorkoutEngine()
        _ = e.skipExercise(); _ = e.skipExercise()
        XCTAssertEqual(e.exercise, .squat)
        // Stand up into the movement first; from a low phone that is only 145 degrees.
        hold(e, PoseFixtures.squat(145))
        for _ in 0..<6 {
            hold(e, PoseFixtures.squat(85))
            hold(e, PoseFixtures.squat(145))
        }
        XCTAssertEqual(e.reps, 6)
    }

    /// pull-ups that barely bend the arms score nothing
    func testPullUpsThatBarelyBendTheArmsScoreNothing() {
        let e = WorkoutEngine()
        for _ in 0..<5 {
            hold(e, PoseFixtures.pullup(170))
            hold(e, PoseFixtures.pullup(145)) // 25 degrees of travel: a twitch, not a rep
        }
        XCTAssertEqual(e.reps, 0)
    }

    /// a pull-up seen from a low phone still counts despite the squashed range
    func testAPullUpSeenFromALowPhoneStillCountsDespiteTheSquashedRange() {
        // A phone on the floor foreshortens everything above it, so the same rep projects a much
        // smaller elbow swing. The counter should calibrate to it rather than miss it.
        let e = WorkoutEngine()
        for _ in 0..<5 { doPullup(e, hang: 150, top: 90) }
        XCTAssertEqual(e.exercise, .pushup)
        XCTAssertEqual(e.repsThisRound, 5)
    }

    /// an even harsher camera angle still counts
    func testAnEvenHarsherCameraAngleStillCounts() {
        let e = WorkoutEngine()
        for _ in 0..<4 { doPullup(e, hang: 140, top: 95) }
        XCTAssertEqual(e.reps, 4)
    }

    /// once full reps set the standard, partial ones stop counting
    func testOnceFullRepsSetTheStandardPartialOnesStopCounting() {
        let e = WorkoutEngine()
        for _ in 0..<2 { doPullup(e, hang: 170, top: 55) }
        XCTAssertEqual(e.reps, 2)
        // Half-height reps against a band learned from full ones.
        for _ in 0..<4 { doPullup(e, hang: 170, top: 120) }
        XCTAssertEqual(e.reps, 2)
    }

    /// the shoulders rising above the hands does not void the rep
    func testTheShouldersRisingAboveTheHandsDoesNotVoidTheRep() {
        // The old signal rejected exactly this frame, so the best reps were the ones it lost.
        let e = WorkoutEngine()
        for _ in 0..<5 { doPullup(e, hang: 175, top: 45) }
        XCTAssertEqual(e.exercise, .pushup)
    }

    /// shallow squats above the depth threshold score nothing
    func testShallowSquatsAboveTheDepthThresholdScoreNothing() {
        let e = WorkoutEngine()
        for _ in 0..<5 { doPullup(e) }
        for _ in 0..<10 { doPushup(e) }
        XCTAssertEqual(e.exercise, .squat)
        for _ in 0..<5 {
            hold(e, PoseFixtures.squat(175))
            hold(e, PoseFixtures.squat(130)) // quarter squat
        }
        XCTAssertEqual(e.reps, 0)
    }

    /// the manual override books a rep and advances the block
    func testTheManualOverrideBooksARepAndAdvancesTheBlock() {
        let e = WorkoutEngine()
        for _ in 0..<4 { _ = e.manualRep() }
        XCTAssertEqual(e.reps, 4)
        XCTAssertEqual(e.exercise, .pullup)
        XCTAssertEqual(e.manualRep(), .exerciseDone)
        XCTAssertEqual(e.exercise, .pushup)
    }

    /// skip jumps to the next movement and banks what was actually done
    func testSkipJumpsToTheNextMovementAndBanksWhatWasActuallyDone() {
        let e = WorkoutEngine()
        XCTAssertEqual(e.skipExercise(), .exerciseDone)
        XCTAssertEqual(e.exercise, .pushup)
        XCTAssertEqual(e.reps, 0)
        // Skipped from zero, so zero. This used to credit the movement's full target, which is the
        // bug a tester found by doing three push-ups and being recorded for ten.
        XCTAssertEqual(e.repsThisRound, 0)
    }

    /// skipping through squats closes the round
    func testSkippingThroughSquatsClosesTheRound() {
        let e = WorkoutEngine()
        _ = e.skipExercise()
        _ = e.skipExercise()
        XCTAssertEqual(e.exercise, .squat)
        XCTAssertEqual(e.skipExercise(), .roundDone)
        XCTAssertEqual(e.rounds, 1)
    }

    /// minus takes a rep back
    func testMinusTakesARepBack() {
        let e = WorkoutEngine()
        for _ in 0..<3 { doPullup(e) }
        XCTAssertEqual(e.undoRep(), .undo)
        XCTAssertEqual(e.reps, 2)
    }

    /// minus steps back over a movement boundary
    func testMinusStepsBackOverAMovementBoundary() {
        let e = WorkoutEngine()
        for _ in 0..<5 { doPullup(e) }
        XCTAssertEqual(e.exercise, .pushup)
        XCTAssertEqual(e.undoRep(), .undo)
        XCTAssertEqual(e.exercise, .pullup)
        XCTAssertEqual(e.reps, 4)
    }

    /// minus steps back over a round boundary
    func testMinusStepsBackOverARoundBoundary() {
        let e = WorkoutEngine()
        for _ in 0..<5 { doPullup(e) }
        for _ in 0..<10 { doPushup(e) }
        for _ in 0..<15 { doSquat(e) }
        XCTAssertEqual(e.rounds, 1)
        XCTAssertEqual(e.undoRep(), .undo)
        XCTAssertEqual(e.rounds, 0)
        XCTAssertEqual(e.exercise, .squat)
        XCTAssertEqual(e.reps, 14)
        XCTAssertEqual(e.totalReps, 29)
    }

    /// minus at the very start does nothing
    func testMinusAtTheVeryStartDoesNothing() {
        let e = WorkoutEngine()
        XCTAssertEqual(e.undoRep(), .none)
        XCTAssertEqual(e.totalReps, 0)
        XCTAssertEqual(e.exercise, .pullup)
    }

    /// plus then minus leaves the score where it started
    func testPlusThenMinusLeavesTheScoreWhereItStarted() {
        let e = WorkoutEngine()
        for _ in 0..<2 { doPullup(e) }
        _ = e.manualRep()
        XCTAssertEqual(e.reps, 3)
        _ = e.undoRep()
        XCTAssertEqual(e.reps, 2)
    }

    /// recalibrating keeps the reps but forgets the band
    func testRecalibratingKeepsTheRepsButForgetsTheBand() {
        let e = WorkoutEngine()
        for _ in 0..<3 { doPullup(e) }
        XCTAssertTrue(e.calibrated)
        e.recalibrate()
        XCTAssertEqual(e.reps, 3)
        XCTAssertFalse(e.calibrated)
        XCTAssertEqual(e.learnedRange, 0, accuracy: 0.001)
    }

    /// a recalibrated counter re-learns from the next reps
    func testARecalibratedCounterReLearnsFromTheNextReps() {
        let e = WorkoutEngine()
        for _ in 0..<3 { doPullup(e) }
        e.recalibrate()
        for _ in 0..<2 { doPullup(e) }
        XCTAssertEqual(e.exercise, .pushup)
    }

    /// recalibrating mid-round does not disturb the round count
    func testRecalibratingMidRoundDoesNotDisturbTheRoundCount() {
        let e = WorkoutEngine()
        for _ in 0..<5 { doPullup(e) }
        for _ in 0..<4 { doPushup(e) }
        e.recalibrate()
        XCTAssertEqual(e.rounds, 0)
        XCTAssertEqual(e.exercise, .pushup)
        XCTAssertEqual(e.repsThisRound, 9)
    }

    /// reset returns the engine to the start of Cindy
    func testResetReturnsTheEngineToTheStartOfCindy() {
        let e = WorkoutEngine()
        for _ in 0..<5 { doPullup(e) }
        for _ in 0..<3 { doPushup(e) }
        e.reset()
        XCTAssertEqual(e.exercise, .pullup)
        XCTAssertEqual(e.reps, 0)
        XCTAssertEqual(e.rounds, 0)
        XCTAssertEqual(e.totalReps, 0)
    }
}
