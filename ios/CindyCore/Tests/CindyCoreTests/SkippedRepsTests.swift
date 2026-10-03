import XCTest
import CindyCore

/// What a skipped movement is worth.
///
/// A tester did three push-ups, hit SKIP, and the app recorded ten. The tally was inferred from
/// *position* — past the push-ups meant ten of them — which holds only while finishing is the one
/// way to leave a movement. SKIP is the other way, and these hold the line that it books what was
/// actually done.
///
/// Mirrors `SkippedRepsTest.kt`, except its last two tests, which build an `Attempt` with the
/// `countedReps` the record format carries. That is the records phase's: they port with it.
final class SkippedRepsTests: XCTestCase {

    /// Books `n` reps by hand, which is the same booking path the camera uses.
    @discardableResult
    private func tap(_ engine: WorkoutEngine, _ n: Int) -> [RepEvent] {
        (1...n).map { _ in engine.manualRep() }
    }

    /// skipping a movement books the reps actually done, not its target
    func testSkippingAMovementBooksTheRepsActuallyDoneNotItsTarget() {
        let engine = WorkoutEngine()
        tap(engine, 5)                       // the pull-ups, in full
        tap(engine, 3)                       // three push-ups
        XCTAssertEqual(engine.repsThisRound, 8)

        _ = engine.skipExercise()

        XCTAssertEqual(engine.exercise, .squat)
        XCTAssertEqual(engine.repsThisRound, 8, "three push-ups is three reps, not ten")
        XCTAssertEqual(engine.totalReps, 8)
    }

    /// a skipped movement still completes the round
    func testASkippedMovementStillCompletesTheRound() {
        let engine = WorkoutEngine()
        tap(engine, 5)
        tap(engine, 3)
        _ = engine.skipExercise()
        tap(engine, 15)                      // the squats finish the round

        XCTAssertEqual(engine.rounds, 1, "the round was completed")
        XCTAssertEqual(engine.totalReps, 23)
        XCTAssertEqual(engine.repsThisRound, 0, "a new round starts empty")
    }

    /// the event carries the score the movement reached
    func testTheEventCarriesTheScoreTheMovementReached() {
        let engine = WorkoutEngine()
        tap(engine, 5)
        tap(engine, 3)

        XCTAssertEqual(engine.skipExercise(), .exerciseDone)
        XCTAssertEqual(engine.repsAtLastEvent, 3, "the voice is owed three, not ten")
    }

    /// finishing a movement carries its target, as before
    func testFinishingAMovementCarriesItsTargetAsBefore() {
        let engine = WorkoutEngine()
        let events = tap(engine, 5)
        XCTAssertEqual(events.last, .exerciseDone)
        XCTAssertEqual(engine.repsAtLastEvent, 5)
    }

    /// a rep event carries its own number rather than the movement's count
    func testARepEventCarriesItsOwnNumberRatherThanTheMovementsCount() {
        let engine = WorkoutEngine()
        let spoken = (1...4).map { _ -> Int in
            tap(engine, 1)
            return engine.repsAtLastEvent
        }
        XCTAssertEqual(spoken, [1, 2, 3, 4])
    }

    /// undo steps back into what a skipped movement actually scored
    func testUndoStepsBackIntoWhatASkippedMovementActuallyScored() {
        let engine = WorkoutEngine()
        tap(engine, 5)
        tap(engine, 3)
        _ = engine.skipExercise()            // now on squats, push-ups banked at 3

        XCTAssertEqual(engine.undoRep(), .undo)

        XCTAssertEqual(engine.exercise, .pushup)
        XCTAssertEqual(engine.reps, 2, "undo must not hand back reps that were never done")
        XCTAssertEqual(engine.repsThisRound, 7)
    }

    /// undo steps back over a round boundary into that round's real score
    func testUndoStepsBackOverARoundBoundaryIntoThatRoundsRealScore() {
        let engine = WorkoutEngine()
        tap(engine, 5)
        tap(engine, 3)
        _ = engine.skipExercise()
        tap(engine, 15)
        XCTAssertEqual(engine.rounds, 1)

        _ = engine.undoRep()

        XCTAssertEqual(engine.rounds, 0)
        XCTAssertEqual(engine.exercise, .squat)
        XCTAssertEqual(engine.reps, 14)
        XCTAssertEqual(engine.totalReps, 22, "5 + 3 + 14")
    }

    /// a reset forgets every banked movement
    func testAResetForgetsEveryBankedMovement() {
        let engine = WorkoutEngine()
        tap(engine, 5)
        tap(engine, 3)
        _ = engine.skipExercise()
        tap(engine, 15)

        engine.reset()

        XCTAssertEqual(engine.rounds, 0)
        XCTAssertEqual(engine.totalReps, 0)
        XCTAssertEqual(engine.repsThisRound, 0)
        XCTAssertEqual(engine.exercise, .pullup)
    }

    /// a full unskipped round is still worth thirty
    func testAFullUnskippedRoundIsStillWorthThirty() {
        let engine = WorkoutEngine()
        tap(engine, 5)
        tap(engine, 10)
        tap(engine, 15)

        XCTAssertEqual(engine.rounds, 1)
        XCTAssertEqual(engine.totalReps, 30)
    }
}
