import XCTest
import CindyCore

/// Mirrors `SessionStatsTest.kt`.
final class SessionStatsTests: XCTestCase {

    private func split(_ movement: Exercise, _ reps: Int, _ ms: Int64 = 10_000, tapped: Int = 0) -> SetSplit {
        SetSplit(movement, ms, reps, tapped)
    }

    private func round(
        pull: Int = 5, push: Int = 10, squat: Int = 15,
        pullMs: Int64 = 14_000, pushMs: Int64 = 17_000, squatMs: Int64 = 21_000
    ) -> [SetSplit] {
        [split(.pullup, pull, pullMs), split(.pushup, push, pushMs), split(.squat, squat, squatMs)]
    }

    /// An attempt whose rounds, counted reps and tapped reps are consistent with its sets.
    private func attempt(
        _ splits: [SetSplit], openReps: Int = 0, openTapped: Int = 0,
        profile: CindyProfile? = CindyProfile.standard, roundSplitsMs: [Int64]? = nil
    ) -> Attempt {
        Attempt(
            rounds: splits.count / 3, reps: 0, atMillis: 1, durationMs: 20 * 60_000,
            roundSplitsMs: roundSplitsMs ?? Array(repeating: 52_000, count: splits.count / 3),
            profile: profile,
            manualReps: splits.reduce(0) { $0 + $1.manualReps } + openTapped,
            countedReps: splits.reduce(0) { $0 + $1.reps } + openReps,
            setSplits: splits)
    }

    private let standard = SessionStats.plurals(CindyProfile.standard)

    /// a standard session is rounds of what was banked, with the unfinished one last
    func testAStandardSessionIsRoundsOfWhatWasBankedWithTheUnfinishedOneLast() {
        let a = attempt(round() + round(), openReps: 3, roundSplitsMs: [50_000, 54_000])
        let stats = SessionStats.from(a)!

        XCTAssertEqual(stats.rounds.map { $0.number }, [1, 2, 3])
        XCTAssertEqual(stats.rounds.map { $0.finished }, [true, true, false])
        XCTAssertEqual(stats.rounds.map { $0.reps }, [30, 30, 3])
        XCTAssertEqual(stats.rounds.map { $0.complete }, [true, true, false])
        XCTAssertEqual(stats.rounds.map { $0.timeMs }, [50_000, 54_000, nil])
        XCTAssertEqual(stats.unfinished?.number, 3)
        XCTAssertEqual(stats.movements.map { $0.reps }, [13, 20, 30])
    }

    /// a full round says what it cost, a part round says what went into it
    func testAFullRoundSaysWhatItCostAPartRoundSaysWhatWentIntoIt() {
        let a = attempt(round() + [split(.pullup, 5)], openReps: 7)
        let stats = SessionStats.from(a)!

        XCTAssertEqual(stats.rounds[0].caption(standard), "Round 1 · 30 of 30 · 0:52")
        XCTAssertEqual(stats.rounds[1].caption(standard),
                       "Round 2 · 12 of 30 · 5 pull-ups, 7 push-ups · unfinished")
    }

    /// a round of a session the camera lost you in says at least
    func testARoundOfASessionTheCameraLostYouInSaysAtLeast() {
        let stats = SessionStats.from(attempt(round() + [split(.pullup, 5)], openReps: 7))!

        XCTAssertEqual(stats.rounds[0].caption(standard, atLeast: true),
                       "Round 1 · at least 30 of 30 · 0:52")
        XCTAssertEqual(stats.rounds[1].caption(standard, atLeast: true),
                       "Round 2 · at least 12 of 30 · 5 pull-ups, 7 push-ups · unfinished")
    }

    /// a skipped set is a finished round worth less than thirty
    func testASkippedSetIsAFinishedRoundWorthLessThanThirty() {
        // Pull-ups skipped at zero: the cycle still moves on, and the round is finished at 25.
        let a = attempt(round(pull: 0, pullMs: 1_000) + round())
        let stats = SessionStats.from(a)!
        let skipped = stats.rounds[0]

        XCTAssertTrue(skipped.finished)
        XCTAssertFalse(skipped.complete)
        XCTAssertEqual(skipped.reps, 25)
        XCTAssertEqual(skipped.caption(standard), "Round 1 · 25 of 30 · 10 push-ups, 15 squats · 0:52")
        XCTAssertEqual(stats.rounds.reduce(0) { $0 + $1.reps }, 55)
        XCTAssertEqual(stats.movements[0].reps, 5)
        XCTAssertEqual(stats.movements[0].completeSets, 1)
        XCTAssertEqual(stats.movements[1].completeSets, 2)
    }

    /// the movement still running at finish is a part-filled round, not a complete one
    func testTheMovementStillRunningAtFinishIsAPartFilledRoundNotACompleteOne() {
        let a = attempt([split(.pullup, 5), split(.pushup, 10)], openReps: 4)
        let stats = SessionStats.from(a)!

        XCTAssertEqual(stats.rounds.count, 1)
        let only = stats.rounds[0]
        XCTAssertFalse(only.finished)
        XCTAssertEqual(only.parts.map { $0.reps }, [5, 10, 4])
        XCTAssertEqual(only.parts.map { $0.reachedTarget }, [true, true, false])
        // Its time is unknown, not zero: no split was ever filed for it.
        XCTAssertNil(stats.movements[2].timeMs)
        XCTAssertEqual(stats.movements[2].reps, 4)
    }

    /// a movement not yet reached in the unfinished round shows as zero
    func testAMovementNotYetReachedInTheUnfinishedRoundShowsAsZero() {
        let a = attempt([split(.pullup, 5)], openReps: 0)
        let stats = SessionStats.from(a)!

        XCTAssertEqual(stats.rounds[0].parts.map { $0.reps }, [5, 0, 0])
    }

    /// an attempt from before set times has no rounds or movements
    func testAnAttemptFromBeforeSetTimesHasNoRoundsOrMovements() {
        var old = Attempt(rounds: 12, reps: 3, atMillis: 1, durationMs: 20 * 60_000)
        XCTAssertNil(SessionStats.from(old))
        // Counted, but never timed set by set: still unknown, not a guess from the round count.
        old.countedReps = 363
        XCTAssertNil(SessionStats.from(old))
    }

    /// a record whose sets disagree with its round count is not trusted
    func testARecordWhoseSetsDisagreeWithItsRoundCountIsNotTrusted() {
        var a = attempt(round() + round())
        a.rounds = 3
        XCTAssertNil(SessionStats.from(a))
        // And one whose sets are not the cycle the engine runs.
        let reordered = attempt([split(.pushup, 10)])
        XCTAssertNil(SessionStats.from(reordered))
    }

    /// tapped reps are read off the sets that closed, per movement
    func testTappedRepsAreReadOffTheSetsThatClosedPerMovement() {
        let a = attempt([split(.pullup, 5, tapped: 2), split(.pushup, 10), split(.squat, 15, tapped: 15)])
        let stats = SessionStats.from(a)!

        XCTAssertEqual(stats.movements.map { $0.tappedReps }, [2, 0, 15])
        XCTAssertEqual(stats.rounds[0].tappedReps, 17)
        XCTAssertEqual(stats.rounds[0].caption(standard), "Round 1 · 30 of 30 · 0:52 · 17 tapped")
    }

    /// the unfinished set's tapped reps are what the totals leave over
    func testTheUnfinishedSetsTappedRepsAreWhatTheTotalsLeaveOver() {
        // Two tapped in the squats still running; the closed sets tapped none.
        let a = attempt(Array(round(squat: 15).prefix(2)), openReps: 7, openTapped: 2)
        let stats = SessionStats.from(a)!

        XCTAssertEqual(stats.movements[2].tappedReps, 2)
        XCTAssertEqual(stats.rounds[0].tappedReps, 2)
    }

    /// tapped reps that cannot be attributed are left unsaid rather than guessed
    func testTappedRepsThatCannotBeAttributedAreLeftUnsaidRatherThanGuessed() {
        // The record says 9 were tapped, but only 3 reps are in the set still running, and the
        // closed sets tapped none: that cannot be right, so no figure is given for that set.
        let a = attempt(Array(round().prefix(2)), openReps: 3, openTapped: 9)
        let stats = SessionStats.from(a)!

        XCTAssertNil(stats.movements[2].tappedReps)
        XCTAssertNil(stats.rounds[0].tappedReps)
        XCTAssertEqual(stats.movements[0].tappedReps, 0)
        XCTAssertFalse(stats.rounds[0].caption(standard).contains("tapped"))
    }

    /// movement times, averages and shares come from finished sets
    func testMovementTimesAveragesAndSharesComeFromFinishedSets() {
        let a = attempt(round() + round(pullMs: 16_000))
        let m = SessionStats.from(a)!.movements

        XCTAssertEqual(m[0].timeMs, 30_000)
        XCTAssertEqual(m[0].averageCompleteSetMs, 15_000)
        XCTAssertEqual(m[1].timeMs, 34_000)
        XCTAssertEqual(m[2].timeMs, 42_000)
        XCTAssertEqual(m.reduce(0.0) { $0 + $1.shareOfClock! }, 1.0, accuracy: 1e-9)
        XCTAssertEqual(m[0].shareOfClock!, 30_000.0 / 106_000.0, accuracy: 1e-9)
    }

    /// a skipped set's time counts toward the movement but not its average
    func testASkippedSetsTimeCountsTowardTheMovementButNotItsAverage() {
        let a = attempt(round() + round(pull: 2, pullMs: 4_000))
        let m = SessionStats.from(a)!.movements

        XCTAssertEqual(m[0].timeMs, 18_000)
        XCTAssertEqual(m[0].completeSets, 1)
        XCTAssertEqual(m[0].averageCompleteSetMs, 14_000)
    }

    /// no share is given until every movement has a complete set
    func testNoShareIsGivenUntilEveryMovementHasACompleteSet() {
        let onlyPullUps = attempt([split(.pullup, 5), split(.pushup, 4)])
        let m = SessionStats.from(onlyPullUps)!.movements

        XCTAssertNil(m[0].shareOfClock)
        XCTAssertNil(m[1].shareOfClock)
        // Its time and average are still real, and shown.
        XCTAssertEqual(m[0].timeMs, 10_000)
        XCTAssertNil(m[1].averageCompleteSetMs)
    }

    /// a mixed profile names only what was changed
    func testAMixedProfileNamesOnlyWhatWasChanged() {
        let adaptive = CindyProfile(pull: .bandAssistedPullUp, push: .kneePushUp)
        let stats = SessionStats.from(attempt(round(), profile: adaptive))!

        XCTAssertEqual(stats.movements.map { $0.label },
                       ["band-assisted pull-ups", "knee push-ups", "squats"])
        XCTAssertEqual(stats.rounds[0].caption(SessionStats.plurals(adaptive)), "Round 1 · 30 of 30 · 0:52")
        XCTAssertEqual(
            SessionStats.from(attempt(round() + [split(.pullup, 5)], openReps: 5, profile: adaptive))!
                .rounds[1].caption(SessionStats.plurals(adaptive)),
            "Round 2 · 10 of 30 · 5 band-assisted pull-ups, 5 knee push-ups · unfinished")
    }

    /// a standard profile uses the plain movement names
    func testAStandardProfileUsesThePlainMovementNames() {
        XCTAssertEqual(SessionStats.plurals(CindyProfile.standard).values, ["pull-ups", "push-ups", "squats"])
        XCTAssertEqual(SessionStats.from(attempt(round()))!.movements.map { $0.label },
                       ["pull-ups", "push-ups", "squats"])
    }

    /// a record from before profiles is the standard movements
    func testARecordFromBeforeProfilesIsTheStandardMovements() {
        XCTAssertEqual(SessionStats.plurals(nil).values, ["pull-ups", "push-ups", "squats"])
    }

    /// pace is reps a minute of the workout clock
    func testPaceIsRepsAMinuteOfTheWorkoutClock() {
        var a = attempt(round() + round())
        XCTAssertEqual(SessionStats.repsPerMinute(a)!, 3.0, accuracy: 1e-9)
        a.durationMs = 0
        XCTAssertNil(SessionStats.repsPerMinute(a))
        XCTAssertNotNil(SessionStats.from(a))
    }
}
