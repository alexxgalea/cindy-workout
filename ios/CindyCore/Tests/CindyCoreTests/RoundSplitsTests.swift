import XCTest
import CindyCore

/// Mirrors `RoundSplitsTest.kt`.
final class RoundSplitsTests: XCTestCase {

    /// A counted total spelled "not kept": Kotlin passes `counted = null`, and Swift needs to tell
    /// that from "left to its default", which is thirty a round.
    private let notKept: Int?? = .some(nil)

    private func set(_ movement: Exercise, _ ms: Int64, reps: Int? = nil, manual: Int = 0) -> SetSplit {
        SetSplit(movement, ms, reps ?? movement.target, manual)
    }

    /// One round's three sets, in order, summing to the times given.
    private func round(_ pull: Int64, _ push: Int64, _ squat: Int64) -> [SetSplit] {
        [set(.pullup, pull), set(.pushup, push), set(.squat, squat)]
    }

    private func attempt(
        _ splits: [Int64], _ sets: [SetSplit] = [],
        durationMs: Int64? = nil, counted: Int?? = nil, at: Int64 = 1_000,
        profile: CindyProfile? = CindyProfile.standard, untrackedMs: Int64 = 0
    ) -> Attempt {
        Attempt(
            rounds: splits.count, reps: 0, atMillis: at, durationMs: durationMs ?? splits.reduce(0, +),
            roundSplitsMs: splits, profile: profile, countedReps: counted ?? splits.count * 30,
            untrackedMs: untrackedMs, setSplits: sets)
    }

    private func readout(_ a: Attempt, _ selected: Int?, _ ref: Attempt? = nil,
                         _ kind: Comparisons.Kind? = nil) -> RoundSplits.Readout {
        RoundSplits.readout(a, RoundSplits.of(a)!, selected: selected, reference: ref, kind: kind)
    }

    // MARK: - the bars

    /// a round whose sets are in order and add up is broken down by movement
    func testARoundWhoseSetsAreInOrderAndAddUpIsBrokenDownByMovement() {
        let a = attempt([168_000], round(41_000, 52_000, 75_000))

        let split = RoundSplits.of(a)!

        XCTAssertEqual(split.bars.count, 1)
        XCTAssertEqual(split.bars[0].sets, [41_000, 52_000, 75_000])
        XCTAssertTrue(split.hasBreakdown)
    }

    /// a round with no set times is a plain bar
    func testARoundWithNoSetTimesIsAPlainBar() {
        let split = RoundSplits.of(attempt([168_000, 170_000]))!

        XCTAssertEqual(split.bars.map { $0.sets }, [nil, nil])
        XCTAssertFalse(split.hasBreakdown)
    }

    /// a misordered round falls back to a plain bar without touching its neighbours
    func testAMisorderedRoundFallsBackToAPlainBarWithoutTouchingItsNeighbours() {
        let sets = round(10_000, 20_000, 30_000)
            + [set(.pushup, 10_000), set(.pullup, 20_000), set(.squat, 30_000)]
            + round(10_000, 20_000, 30_000)
        let a = attempt([60_000, 60_000, 60_000], sets)

        let bars = RoundSplits.of(a)!.bars

        XCTAssertNotNil(bars[0].sets)
        XCTAssertNil(bars[1].sets)
        XCTAssertNotNil(bars[2].sets)
    }

    /// a round missing some of its sets falls back to a plain bar
    func testARoundMissingSomeOfItsSetsFallsBackToAPlainBar() {
        let a = attempt([60_000, 60_000], round(10_000, 20_000, 30_000) + [set(.pullup, 5_000)])

        XCTAssertEqual(RoundSplits.of(a)!.bars.map { $0.sets != nil }, [true, false])
    }

    /// sets that do not add up to the round are not believed
    func testSetsThatDoNotAddUpToTheRoundAreNotBelieved() {
        let a = attempt([120_000], round(10_000, 20_000, 30_000))

        XCTAssertNil(RoundSplits.of(a)!.bars[0].sets)
    }

    /// a round that skipped a movement still has its breakdown
    func testARoundThatSkippedAMovementStillHasItsBreakdown() {
        let sets = [set(.pullup, 10_000), set(.pushup, 12_000, reps: 4), set(.squat, 30_000)]

        let bar = RoundSplits.of(attempt([52_000], sets, counted: 24))!.bars[0]

        XCTAssertEqual(bar.sets, [10_000, 12_000, 30_000])
    }

    /// a round with a tapped in set says so
    func testARoundWithATappedInSetSaysSo() {
        let sets = [set(.pullup, 10_000, manual: 2), set(.pushup, 20_000), set(.squat, 30_000)]

        XCTAssertTrue(RoundSplits.of(attempt([60_000], sets))!.bars[0].byHand)
    }

    /// no complete round is no chart
    func testNoCompleteRoundIsNoChart() {
        XCTAssertNil(RoundSplits.of(attempt([], durationMs: 90_000)))
    }

    /// the fastest round is the first of the shortest, and the average covers finished rounds only
    func testTheFastestRoundIsTheFirstOfTheShortestAndTheAverageCoversFinishedRoundsOnly() {
        let a = attempt([170_000, 131_000, 131_000, 200_000], durationMs: 800_000)

        let split = RoundSplits.of(a)!

        XCTAssertEqual(split.fastest, 1)
        XCTAssertEqual(split.averageMs, 158_000)
    }

    // MARK: - the round still going

    /// the round in progress is last, with its time so far and the reps banked in it
    func testTheRoundInProgressIsLastWithItsTimeSoFarAndTheRepsBankedInIt() {
        // Two rounds, then 5 pull-ups and 3 of 10 push-ups of the third.
        let sets = round(40_000, 50_000, 70_000) + round(40_000, 50_000, 70_000) + [set(.pullup, 38_000)]
        let a = attempt([160_000, 160_000], sets, durationMs: 400_000, counted: 68)

        let open = RoundSplits.of(a)!.bars.last!

        XCTAssertTrue(open.unfinished)
        XCTAssertEqual(open.round, 3)
        XCTAssertEqual(open.ms, 80_000)
        XCTAssertEqual(open.sets, [38_000])
        XCTAssertEqual(open.reps, 8)
    }

    /// an unfinished round with no counted total keeps its time but not its reps
    func testAnUnfinishedRoundWithNoCountedTotalKeepsItsTimeButNotItsReps() {
        let a = attempt([160_000], round(40_000, 50_000, 70_000), durationMs: 200_000, counted: notKept)

        let open = RoundSplits.of(a)!.bars.last!

        XCTAssertTrue(open.unfinished)
        XCTAssertEqual(open.ms, 40_000)
        XCTAssertNil(open.reps)
    }

    /// an unfinished round whose record does not add up reads no reps
    func testAnUnfinishedRoundWhoseRecordDoesNotAddUpReadsNoReps() {
        // 40 counted reps cannot be one round of 30 plus a movement still under its target.
        let a = attempt([160_000], round(40_000, 50_000, 70_000), durationMs: 200_000, counted: 80)

        XCTAssertNil(RoundSplits.of(a)!.bars.last!.reps)
    }

    /// a sliver of clock after the last round is not a round in progress
    func testASliverOfClockAfterTheLastRoundIsNotARoundInProgress() {
        let a = attempt([160_000], durationMs: 160_400)

        XCTAssertFalse(RoundSplits.of(a)!.hasUnfinished)
    }

    /// an unfinished round with no sets banked yet reads its reps from the movement under way
    func testAnUnfinishedRoundWithNoSetsBankedYetReadsItsRepsFromTheMovementUnderWay() {
        let a = attempt([160_000], round(40_000, 50_000, 70_000), durationMs: 190_000, counted: 32)

        let open = RoundSplits.of(a)!.bars.last!

        XCTAssertEqual(open.sets, [])
        XCTAssertEqual(open.reps, 2)
    }

    /// an unfinished round of a lower bound score is a floor
    func testAnUnfinishedRoundOfALowerBoundScoreIsAFloor() {
        let sets = round(40_000, 50_000, 70_000) + [set(.pullup, 38_000)]
        let a = attempt([160_000], sets, durationMs: 240_000, counted: 36,
                        untrackedMs: Records.untrackedToleranceMs)

        let open = RoundSplits.of(a)!.bars.last!

        XCTAssertTrue(open.atLeast)
        XCTAssertEqual(open.reps, 6)
        XCTAssertTrue(readout(a, 1).detail.hasPrefix("at least 6 of 30 reps"))
    }

    /// an unfinished round of a trusted score is not a floor
    func testAnUnfinishedRoundOfATrustedScoreIsNotAFloor() {
        let sets = round(40_000, 50_000, 70_000) + [set(.pullup, 38_000)]
        let a = attempt([160_000], sets, durationMs: 240_000, counted: 36)

        XCTAssertFalse(RoundSplits.of(a)!.bars.last!.atLeast)
        XCTAssertTrue(readout(a, 1).detail.hasPrefix("6 of 30 reps"))
    }

    /// a lower bound with no reps to quote does not claim a floor
    func testALowerBoundWithNoRepsToQuoteDoesNotClaimAFloor() {
        let a = attempt([160_000], durationMs: 240_000, counted: notKept,
                        untrackedMs: Records.untrackedToleranceMs)

        XCTAssertFalse(RoundSplits.of(a)!.bars.last!.atLeast)
    }

    /// a floor of zero reps is left out of an unfinished round
    func testAFloorOfZeroRepsIsLeftOutOfAnUnfinishedRound() {
        let a = attempt([160_000], round(40_000, 50_000, 70_000), durationMs: 240_000, counted: 30,
                        untrackedMs: Records.untrackedToleranceMs)

        let open = RoundSplits.of(a)!.bars.last!

        XCTAssertEqual(open.reps, 0)
        XCTAssertNil(open.repsToQuote)
        XCTAssertEqual(readout(a, 1).detail, "not a finished round")
    }

    /// zero reps of a trusted score are still said
    func testZeroRepsOfATrustedScoreAreStillSaid() {
        let a = attempt([160_000], round(40_000, 50_000, 70_000), durationMs: 240_000, counted: 30)

        XCTAssertEqual(RoundSplits.of(a)!.bars.last!.repsToQuote, 0)
        XCTAssertEqual(readout(a, 1).detail, "0 of 30 reps · not a finished round")
    }

    // MARK: - the comparison

    /// the reference is the comparison's split at the same round, null past its last
    func testTheReferenceIsTheComparisonsSplitAtTheSameRoundNullPastItsLast() {
        let a = attempt([160_000, 150_000, 140_000])
        let ref = attempt([170_000, 145_000])

        XCTAssertEqual(RoundSplits.reference(RoundSplits.of(a)!, ref), [170_000, 145_000, nil])
    }

    /// the unfinished round has no reference
    func testTheUnfinishedRoundHasNoReference() {
        let a = attempt([160_000], durationMs: 200_000)
        let ref = attempt([170_000, 145_000])

        XCTAssertEqual(RoundSplits.reference(RoundSplits.of(a)!, ref), [170_000, nil])
    }

    /// no comparison is no reference
    func testNoComparisonIsNoReference() {
        let a = attempt([160_000])

        XCTAssertEqual(RoundSplits.reference(RoundSplits.of(a)!, nil), [nil])
    }

    // MARK: - the words

    /// nothing selected names the fastest round and the average
    func testNothingSelectedNamesTheFastestRoundAndTheAverage() {
        let a = attempt([171_000, 131_000, 211_000], durationMs: 513_000)

        XCTAssertEqual(readout(a, nil).title, "Fastest: round 2 at 2:11 · average 2:51")
    }

    /// a single round has no average worth quoting
    func testASingleRoundHasNoAverageWorthQuoting() {
        let a = attempt([131_000], durationMs: 131_000)

        XCTAssertEqual(readout(a, nil).title, "Fastest: round 1 at 2:11")
    }

    /// a selected round gives its time and each movement's, in the athlete's own words
    func testASelectedRoundGivesItsTimeAndEachMovementsInTheAthletesOwnWords() {
        let a = attempt([168_000], round(41_000, 52_000, 75_000))

        let r = readout(a, 0)

        XCTAssertEqual(r.title, "Round 1 · 2:48")
        XCTAssertEqual(r.detail, "Pull-ups 0:41 · push-ups 0:52 · squats 1:15")
        XCTAssertNil(r.versus)
    }

    /// an adaptive session names its own movements
    func testAnAdaptiveSessionNamesItsOwnMovements() {
        let profile = CindyProfile(push: .kneePushUp)
        let a = attempt([168_000], round(41_000, 52_000, 75_000), profile: profile)

        XCTAssertEqual(readout(a, 0).detail, "Pull-ups 0:41 · knee push-ups 0:52 · squats 1:15")
    }

    /// a session of unrecognised movements falls back to the plain names
    func testASessionOfUnrecognisedMovementsFallsBackToThePlainNames() {
        XCTAssertEqual(RoundSplits.movementNames(nil), ["pull-ups", "push-ups", "squats"])
    }

    /// a plain bar says it has no movement times
    func testAPlainBarSaysItHasNoMovementTimes() {
        let r = readout(attempt([168_000]), 0)

        XCTAssertEqual(r.detail, "No per-movement times for this round")
    }

    /// a tapped in round says so
    func testATappedInRoundSaysSo() {
        let sets = [set(.pullup, 41_000, manual: 1), set(.pushup, 52_000), set(.squat, 75_000)]

        XCTAssertTrue(readout(attempt([168_000], sets), 0).detail
            .hasSuffix("Some reps in this round were added by hand"))
    }

    /// faster than your best is said with the gap and flagged faster
    func testFasterThanYourBestIsSaidWithTheGapAndFlaggedFaster() {
        let a = attempt([168_000])
        let best = attempt([177_000])

        let v = readout(a, 0, best, .best).versus!

        XCTAssertEqual(v.text, "9 s faster than your best's round 1")
        XCTAssertEqual(v.faster, true)
    }

    /// slower than last time is flagged slower, and a minute or more is a time
    func testSlowerThanLastTimeIsFlaggedSlowerAndAMinuteOrMoreIsATime() {
        let a = attempt([168_000])
        let last = attempt([100_000])

        let v = readout(a, 0, last, .last).versus!

        XCTAssertEqual(v.text, "1:08 slower than round 1 last time")
        XCTAssertEqual(v.faster, false)
    }

    /// within half a second is level
    func testWithinHalfASecondIsLevel() {
        let a = attempt([168_000])
        let best = attempt([168_300])

        let v = readout(a, 0, best, .best).versus!

        XCTAssertEqual(v.text, "Level with your best's round 1")
        XCTAssertNil(v.faster)
    }

    /// a comparison without that round says nothing about it
    func testAComparisonWithoutThatRoundSaysNothingAboutIt() {
        let a = attempt([168_000, 160_000], durationMs: 328_000)
        let best = attempt([177_000])

        XCTAssertNil(readout(a, 1, best, .best).versus)
    }

    /// the round in progress is not compared and says how far it got
    func testTheRoundInProgressIsNotComparedAndSaysHowFarItGot() {
        let a = attempt([160_000], round(40_000, 50_000, 70_000) + [set(.pullup, 38_000)],
                        durationMs: 240_000, counted: 36)
        let best = attempt([170_000, 150_000])

        let r = readout(a, 1, best, .best)

        XCTAssertEqual(r.title, "Round 2 · 1:20 so far")
        XCTAssertEqual(r.detail, "6 of 30 reps · not a finished round. Pull-ups 0:38")
        XCTAssertNil(r.versus)
    }

    /// an unfinished round with unknown reps does not make up a count
    func testAnUnfinishedRoundWithUnknownRepsDoesNotMakeUpACount() {
        let a = attempt([160_000], durationMs: 240_000, counted: notKept)

        XCTAssertEqual(readout(a, 1).detail, "not a finished round")
    }

    /// the spoken form joins title detail and versus
    func testTheSpokenFormJoinsTitleDetailAndVersus() {
        let a = attempt([168_000])
        let best = attempt([177_000])

        XCTAssertEqual(
            readout(a, 0, best, .best).spoken(),
            "Round 1 · 2:48. No per-movement times for this round. 9 s faster than your best's round 1")
    }
}
