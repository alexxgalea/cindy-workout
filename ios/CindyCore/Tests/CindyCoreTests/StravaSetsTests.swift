import XCTest
import CindyCore

/// The set list rebuilt from an attempt's own record.
///
/// Mirrors `StravaSetsTest.kt`, except its last test, which feeds the result through
/// `StravaPayload`'s movement mapping. That is the Strava phase's: it ports with the payload.
/// `StravaSets` itself is here because the round chart and the session page read the same sets.
final class StravaSetsTests: XCTestCase {

    private func split(_ movement: Exercise, _ reps: Int) -> SetSplit {
        SetSplit(movement, 1_000, reps, 0)
    }

    private func attempt(_ setSplits: [SetSplit], countedReps: Int?,
                         profile: CindyProfile? = CindyProfile.standard) -> Attempt {
        Attempt(rounds: 0, reps: 0, atMillis: 0, profile: profile,
                countedReps: countedReps, setSplits: setSplits)
    }

    /// a clean two rounds plus a partial movement gives every set in order
    func testACleanTwoRoundsPlusAPartialMovementGivesEverySetInOrder() {
        let splits = [
            split(.pullup, 5), split(.pushup, 10), split(.squat, 15),
            split(.pullup, 5), split(.pushup, 10), split(.squat, 15)
        ]
        let a = attempt(splits, countedReps: 63)  // two full rounds (60) + 3 pull-ups in progress

        XCTAssertEqual(StravaSets.from(a), [
            WorkoutSet(1, .pullup, 5), WorkoutSet(1, .pushup, 10), WorkoutSet(1, .squat, 15),
            WorkoutSet(2, .pullup, 5), WorkoutSet(2, .pushup, 10), WorkoutSet(2, .squat, 15),
            WorkoutSet(3, .pullup, 3)
        ])
    }

    /// a mid-round skip books what the split actually banked, not its target
    func testAMidRoundSkipBooksWhatTheSplitActuallyBankedNotItsTarget() {
        let splits = [split(.pullup, 5), split(.pushup, 3)]  // push-ups skipped at 3, not 10
        let a = attempt(splits, countedReps: 12)             // 5 + 3 + 4 squats in progress

        XCTAssertEqual(StravaSets.from(a), [
            WorkoutSet(1, .pullup, 5),
            WorkoutSet(1, .pushup, 3),
            WorkoutSet(1, .squat, 4)
        ])
    }

    /// stopping right as a round completes adds no extra zero-rep set
    func testStoppingRightAsARoundCompletesAddsNoExtraZeroRepSet() {
        let splits = [split(.pullup, 5), split(.pushup, 10), split(.squat, 15)]
        let a = attempt(splits, countedReps: 30)  // nothing yet in round two

        XCTAssertEqual(StravaSets.from(a), [
            WorkoutSet(1, .pullup, 5), WorkoutSet(1, .pushup, 10), WorkoutSet(1, .squat, 15)
        ])
    }

    /// no splits at all still gives the pull-ups in progress
    func testNoSplitsAtAllStillGivesThePullUpsInProgress() {
        let a = attempt([], countedReps: 3)
        XCTAssertEqual(StravaSets.from(a), [WorkoutSet(1, .pullup, 3)])
    }

    /// an inferred tally is never uploaded
    func testAnInferredTallyIsNeverUploaded() {
        let a = attempt([split(.pullup, 5)], countedReps: nil)
        XCTAssertNil(StravaSets.from(a))
    }

    /// a split that breaks the engine's cycle is refused
    func testASplitThatBreaksTheEnginesCycleIsRefused() {
        // The very first split should be PULLUP, not PUSHUP.
        let brokenFirst = attempt([split(.pushup, 10)], countedReps: 10)
        XCTAssertNil(StravaSets.from(brokenFirst))

        // The second split should be PUSHUP, not SQUAT.
        let brokenSecond = attempt([split(.pullup, 5), split(.squat, 15)], countedReps: 20)
        XCTAssertNil(StravaSets.from(brokenSecond))
    }

    /// a remainder at or past the in-progress movement's target is refused
    func testARemainderAtOrPastTheInProgressMovementsTargetIsRefused() {
        // Five is PULLUP's target: a movement that reaches it has already advanced and been
        // banked by SplitBook, so it cannot still be "in progress".
        let a = attempt([], countedReps: 5)
        XCTAssertNil(StravaSets.from(a))
    }

    /// a negative remainder is refused
    func testANegativeRemainderIsRefused() {
        // The splits already total 5, but the attempt claims only 3 -- the record disagrees
        // with itself.
        let a = attempt([split(.pullup, 5)], countedReps: 3)
        XCTAssertNil(StravaSets.from(a))
    }

    /// an all-zero attempt has no positive set to upload
    func testAnAllZeroAttemptHasNoPositiveSetToUpload() {
        let a = attempt([], countedReps: 0)
        XCTAssertNil(StravaSets.from(a))
    }
}
