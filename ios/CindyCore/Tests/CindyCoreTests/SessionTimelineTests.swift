import XCTest
@testable import CindyCore

/// Mirrors `SessionTimelineTest.kt`.
///
/// The session timeline's numbers, on a two-round session whose every instant is easy to read:
///
///     round 1  0:00 pull-ups 5 (10 s) · push-ups 10 (20 s) · squats 15 (30 s)   ends 1:00
///     round 2  1:00 pull-ups 5 (8 s)  · push-ups 10 (17 s) · squats 15 (25 s)   ends 1:50
///     then     pull-ups, 3 reps in, when the clock stops at 2:00 (63 reps)
final class SessionTimelineTests: XCTestCase {

    private let sets = [
        SetSplit(.pullup, 10_000, 5, 0),
        SetSplit(.pushup, 20_000, 10, 0),
        SetSplit(.squat, 30_000, 15, 0),
        SetSplit(.pullup, 8_000, 5, 0),
        SetSplit(.pushup, 17_000, 10, 0),
        SetSplit(.squat, 25_000, 15, 0)
    ]

    private func attempt(at: Int64 = 1_000, splits: [SetSplit]? = nil, roundSplits: [Int64] = [60_000, 50_000],
                         counted: Int? = 63, durationMs: Int64 = 120_000, manual: Int = 0,
                         untracked: Int64 = 0) -> Attempt {
        Attempt(rounds: roundSplits.count, reps: 3, atMillis: at, durationMs: durationMs,
                roundSplitsMs: roundSplits, manualReps: manual, countedReps: counted,
                untrackedMs: untracked, setSplits: splits ?? sets)
    }

    /// One mark a second inside every set, ending on the set's own end, as the engine files them.
    private func marks(_ a: Attempt, manualFrom: Int = Int.max) -> [RepMark] {
        var out: [RepMark] = []
        var start: Int64 = 0
        for s in a.setSplits {
            for k in 1...s.reps {
                out.append(RepMark(start + s.ms * Int64(k) / Int64(s.reps), s.movement, manual: out.count >= manualFrom))
            }
            start += s.ms
        }
        let running = (a.countedReps ?? 0) - out.count
        if running >= 1 {
            for k in 1...running {
                out.append(RepMark(start + Int64(k) * 1_000, .pullup, manual: out.count >= manualFrom))
            }
        }
        return out
    }

    private func trace(_ samples: (Int64, Int)...) -> HeartRateTrace {
        HeartRateTrace(startedAtMillis: 0, samples: samples.map { HeartRateSample($0.0, $0.1) }, pauses: [])
    }

    // MARK: reps: exact versus per set

    /// with valid marks the reps are one step per rep
    func testWithValidMarksTheRepsAreOneStepPerRep() {
        let a = attempt()
        let t = SessionTimeline.of(a, marks: marks(a), trace: nil)

        let series = t.reps!
        XCTAssertTrue(series.exact)
        XCTAssertEqual(series.points.count, 64)
        XCTAssertEqual(series.points[0], RepPoint(0, 0, 0))
        XCTAssertEqual(series.points[series.points.count - 1].reps, 63)
    }

    /// an exact count is the marks at or before the instant
    func testAnExactCountIsTheMarksAtOrBeforeTheInstant() {
        let a = attempt()
        let t = SessionTimeline.of(a, marks: marks(a), trace: nil)

        // The first pull-up banks at 2 s, the fifth at 10 s.
        XCTAssertEqual(t.at(1_999).reps, 0)
        XCTAssertEqual(t.at(2_000).reps, 1)
        XCTAssertEqual(t.at(10_000).reps, 5)
        XCTAssertEqual(t.at(10_001).reps, 5)
        XCTAssertEqual(t.at(120_000).reps, 63)
    }

    /// without marks the reps are per set and snap to the last finished set
    func testWithoutMarksTheRepsArePerSetAndSnapToTheLastFinishedSet() {
        let a = attempt()
        let t = SessionTimeline.of(a, marks: nil, trace: nil)

        let series = t.reps!
        XCTAssertFalse(series.exact)
        // The origin, six finished sets, and the clock stopping on the total counted by then.
        XCTAssertEqual(series.points.map { $0.clockMs }, [0, 10_000, 30_000, 60_000, 68_000, 85_000, 110_000, 120_000])
        XCTAssertEqual(series.points.map { $0.reps }, [0, 5, 15, 30, 35, 45, 60, 63])
        XCTAssertEqual(t.at(9_999).reps, 0)
        XCTAssertEqual(t.at(25_000).reps, 5)
        XCTAssertEqual(t.at(67_999).reps, 30)
        XCTAssertEqual(t.at(120_000).reps, 63)
    }

    /// marks that do not add up to what was counted fall back to the sets
    func testMarksThatDoNotAddUpToWhatWasCountedFallBackToTheSets() {
        let a = attempt()
        let short = Array(marks(a).dropLast())

        let t = SessionTimeline.of(a, marks: short, trace: nil)

        XCTAssertFalse(t.reps!.exact)
    }

    /// marks running past the clock fall back to the sets
    func testMarksRunningPastTheClockFallBackToTheSets() {
        let a = attempt()
        let late = Array(marks(a).dropLast()) + [RepMark(125_000, .pullup, manual: false)]

        XCTAssertFalse(SessionTimeline.of(a, marks: late, trace: nil).reps!.exact)
    }

    /// a record from before rep times and set times has no reps line at all
    func testARecordFromBeforeRepTimesAndSetTimesHasNoRepsLineAtAll() {
        let old = attempt(splits: [], counted: nil)
        let t = SessionTimeline.of(old, marks: nil, trace: nil)

        XCTAssertNil(t.reps)
        XCTAssertNil(t.at(60_000).reps)
        XCTAssertFalse(t.hasData)
    }

    /// a set record that disagrees with the total is not plotted
    func testASetRecordThatDisagreesWithTheTotalIsNotPlotted() {
        let a = attempt(counted: 40)

        XCTAssertNil(SessionTimeline.of(a, marks: nil, trace: nil).reps)
    }

    /// a session with nothing banked has no reps line
    func testASessionWithNothingBankedHasNoRepsLine() {
        let a = attempt(splits: [], roundSplits: [], counted: 0)

        XCTAssertNil(SessionTimeline.of(a, marks: [], trace: nil).reps)
    }

    /// reps tapped in are counted apart from the rest
    func testRepsTappedInAreCountedApartFromTheRest() {
        let a = attempt(manual: 4)
        let t = SessionTimeline.of(a, marks: marks(a, manualFrom: 59), trace: nil)

        let end = t.at(120_000)
        XCTAssertEqual(end.reps, 63)
        XCTAssertEqual(end.manualReps, 4)
        XCTAssertEqual(t.at(60_000).manualReps, 0)
        XCTAssertTrue(t.readout(end).detail!.hasPrefix("63 reps, 4 by hand"))
    }

    /// a score the camera could not stand behind says at least
    func testAScoreTheCameraCouldNotStandBehindSaysAtLeast() {
        let a = attempt(untracked: 60_000)
        let t = SessionTimeline.of(a, marks: marks(a), trace: nil)

        XCTAssertTrue(a.scoreIsLowerBound)
        XCTAssertTrue(t.readout(t.at(120_000)).detail!.hasPrefix("at least 63 reps"))
        XCTAssertTrue(t.describeRound(t.rounds[1]).contains("at least 60 reps by its end"))
    }

    // MARK: rounds and sets

    /// round ends are the running total of the splits, and the unfinished round has a span
    func testRoundEndsAreTheRunningTotalOfTheSplitsAndTheUnfinishedRoundHasASpan() {
        let t = SessionTimeline.of(attempt(), marks: nil, trace: nil)

        XCTAssertEqual(t.roundEnds, [60_000, 110_000])
        XCTAssertEqual(t.rounds, [
            RoundSpan(number: 1, startMs: 0, endMs: 60_000, complete: true),
            RoundSpan(number: 2, startMs: 60_000, endMs: 110_000, complete: true),
            RoundSpan(number: 3, startMs: 110_000, endMs: 120_000, complete: false)
        ])
    }

    /// sets carry their round, and the one still running follows the last finished
    func testSetsCarryTheirRoundAndTheOneStillRunningFollowsTheLastFinished() {
        let t = SessionTimeline.of(attempt(), marks: nil, trace: nil)

        XCTAssertEqual(t.sets.count, 7)
        XCTAssertEqual(t.sets[0], SetSpan(startMs: 0, endMs: 10_000, movement: .pullup, round: 1, inProgress: false))
        XCTAssertEqual(t.sets[t.sets.count - 1],
                       SetSpan(startMs: 110_000, endMs: 120_000, movement: .pullup, round: 3, inProgress: true))
    }

    /// the round in progress, and its movement, follow the cursor
    func testTheRoundInProgressAndItsMovementFollowTheCursor() {
        let t = SessionTimeline.of(attempt(), marks: nil, trace: nil)

        XCTAssertEqual(t.at(0).round, 1)
        XCTAssertEqual(t.at(0).movement, .pullup)
        XCTAssertEqual(t.at(20_000).movement, .pushup)
        XCTAssertEqual(t.at(59_000).round, 1)
        // The instant a round ends it is still that round, and its last set.
        XCTAssertEqual(t.at(60_000).round, 1)
        XCTAssertEqual(t.at(60_000).movement, .squat)
        XCTAssertEqual(t.at(60_001).round, 2)
        XCTAssertEqual(t.at(60_001).movement, .pullup)
        // After the last finished round the clock was running on a third.
        XCTAssertEqual(t.at(115_000).round, 3)
        XCTAssertEqual(t.at(120_000).round, 3)
    }

    /// a session that ends exactly on a round does not invent another
    func testASessionThatEndsExactlyOnARoundDoesNotInventAnother() {
        let a = attempt(splits: sets, roundSplits: [60_000, 50_000], durationMs: 110_000)
        let t = SessionTimeline.of(a, marks: nil, trace: nil)

        XCTAssertEqual(t.rounds.count, 2)
        XCTAssertEqual(t.at(110_000).round, 2)
    }

    /// an instant outside the clock is held to it
    func testAnInstantOutsideTheClockIsHeldToIt() {
        let t = SessionTimeline.of(attempt(), marks: nil, trace: nil)

        XCTAssertEqual(t.at(-5).clockMs, 0)
        XCTAssertEqual(t.at(999_999).clockMs, 120_000)
    }

    // MARK: heart rate

    /// heart rate is cut into runs wherever the watch fell silent for longer than a hold
    func testHeartRateIsCutIntoRunsWhereverTheWatchFellSilentForLongerThanAHold() {
        let t = SessionTimeline.of(attempt(), marks: nil, trace: trace(
            (0, 90), (1_000, 95), (6_000, 100),       // exactly one hold apart: still joined
            (20_000, 120), (21_000, 122)))            // a long silence before this

        XCTAssertEqual(t.heartRuns.count, 2)
        XCTAssertEqual(t.heartRuns[0].count, 3)
        XCTAssertEqual(t.heartRuns[1].map { $0.bpm }, [120, 122])
    }

    /// samples outside the clock, or not a plausible heart rate, are not drawn
    func testSamplesOutsideTheClockOrNotAPlausibleHeartRateAreNotDrawn() {
        let t = SessionTimeline.of(attempt(), marks: nil, trace:
            trace((-1_000, 90), (1_000, 20), (2_000, 130), (120_000, 140), (130_000, 150)))

        XCTAssertEqual(t.heartRuns.map { run in run.map { $0.bpm } }, [[130]])
    }

    /// the bpm is the latest reading, held no longer than the hold
    func testTheBpmIsTheLatestReadingHeldNoLongerThanTheHold() {
        let t = SessionTimeline.of(attempt(), marks: nil, trace: trace((10_000, 130), (12_000, 140)))

        XCTAssertNil(t.at(9_999).bpm)
        XCTAssertEqual(t.at(10_000).bpm, 130)
        XCTAssertEqual(t.at(11_999).bpm, 130)
        XCTAssertEqual(t.at(12_000).bpm, 140)
        XCTAssertEqual(t.at(17_000).bpm, 140)
        XCTAssertNil(t.at(17_001).bpm)
    }

    /// with no trace there is no bpm and no heart runs
    func testWithNoTraceThereIsNoBpmAndNoHeartRuns() {
        let t = SessionTimeline.of(attempt(), marks: nil, trace: nil)

        XCTAssertTrue(t.heartRuns.isEmpty)
        XCTAssertNil(t.at(30_000).bpm)
    }

    /// a trace alone is enough to have something to draw
    func testATraceAloneIsEnoughToHaveSomethingToDraw() {
        let old = attempt(splits: [], counted: nil)
        let t = SessionTimeline.of(old, marks: nil, trace: trace((1_000, 100)))

        XCTAssertTrue(t.hasData)
        XCTAssertNil(t.reps)
    }

    /// a round's average bpm is the mean of the samples inside it
    func testARoundsAverageBpmIsTheMeanOfTheSamplesInsideIt() {
        let t = SessionTimeline.of(attempt(), marks: nil, trace: trace((10_000, 100), (20_000, 120), (70_000, 160)))

        XCTAssertEqual(t.averageBpm(0, 60_000), 110)
        XCTAssertEqual(t.averageBpm(60_000, 110_000), 160)
        XCTAssertNil(t.averageBpm(110_000, 120_000))
    }

    // MARK: against the reference

    /// Slower in round one (70 s), level after: 1:10 then 2:00, against 1:00 and 1:50.
    private func slower(at: Int64 = 500) -> Attempt {
        attempt(at: at, splits: [], roundSplits: [70_000, 50_000], counted: nil)
    }

    /// ahead is the reference's round end minus ours, positive when we were faster
    func testAheadIsTheReferencesRoundEndMinusOursPositiveWhenWeWereFaster() {
        let t = SessionTimeline.of(attempt(), marks: nil, trace: nil, reference: slower(),
                                   referenceKind: .best, referenceMarks: nil)

        // Both have finished round one by 1:10; we were ten seconds quicker.
        XCTAssertEqual(t.at(70_000).aheadMs, 10_000)
        XCTAssertEqual(t.at(70_000).aheadRound, 1)
        // Round two ended at 1:50 for us and 2:00 for them.
        XCTAssertEqual(t.at(120_000).aheadMs, 10_000)
        XCTAssertEqual(t.at(120_000).aheadRound, 2)
    }

    /// ahead is only said once both sessions have finished the round
    func testAheadIsOnlySaidOnceBothSessionsHaveFinishedTheRound() {
        let t = SessionTimeline.of(attempt(), marks: nil, trace: nil, reference: slower(), referenceKind: .best)

        // We finished round one at 1:00; they had not. Nothing to compare yet, and no guess at it.
        XCTAssertNil(t.at(60_000).aheadMs)
        XCTAssertNil(t.at(69_999).aheadMs)
        XCTAssertNil(t.at(10_000).aheadMs)
    }

    /// behind is negative
    func testBehindIsNegative() {
        let faster = attempt(at: 500, roundSplits: [50_000, 50_000])
        let t = SessionTimeline.of(attempt(), marks: nil, trace: nil, reference: faster, referenceKind: .last)

        XCTAssertEqual(t.at(60_000).aheadMs, -10_000)
        XCTAssertEqual(t.at(110_000).aheadMs, -10_000)
    }

    /// a reference with fewer rounds is compared on the last round they share
    func testAReferenceWithFewerRoundsIsComparedOnTheLastRoundTheyShare() {
        let shorter = attempt(at: 500, splits: [], roundSplits: [65_000], counted: nil, durationMs: 100_000)
        let t = SessionTimeline.of(attempt(), marks: nil, trace: nil, reference: shorter, referenceKind: .best)

        XCTAssertEqual(t.at(65_000).aheadMs, 5_000)
        // Their second round never happened, so ours is not measured against it.
        XCTAssertEqual(t.at(115_000).aheadRound, 1)
        XCTAssertEqual(t.at(115_000).aheadMs, 5_000)
        XCTAssertNil(t.aheadOfReference(2))
    }

    /// no reference means no comparison anywhere
    func testNoReferenceMeansNoComparisonAnywhere() {
        let a = attempt()
        let t = SessionTimeline.of(a, marks: marks(a), trace: nil)

        XCTAssertNil(t.at(100_000).aheadMs)
        XCTAssertNil(t.reference)
        XCTAssertNil(t.legend())
    }

    /// the reference's marks are checked against the reference, not this session
    func testTheReferencesMarksAreCheckedAgainstTheReferenceNotThisSession() {
        let a = attempt()
        let ref = attempt(at: 500, splits: [], roundSplits: [70_000], counted: 60)
        // Valid for the reviewed session (63 marks), wrong for the reference (counted 60).
        let t = SessionTimeline.of(a, marks: marks(a), trace: nil, reference: ref, referenceKind: .best,
                                   referenceMarks: marks(a))

        XCTAssertTrue(t.reps!.exact)
        XCTAssertNil(t.reference!.reps)
    }

    /// each side is exact or per set on its own
    func testEachSideIsExactOrPerSetOnItsOwn() {
        let a = attempt()
        let ref = attempt(at: 500)
        let t = SessionTimeline.of(a, marks: marks(a), trace: nil, reference: ref, referenceKind: .best,
                                   referenceMarks: nil)

        XCTAssertTrue(t.reps!.exact)
        XCTAssertFalse(t.reference!.reps!.exact)
        XCTAssertEqual(t.legend(), "Dashed: your best. Reps are plotted per set for your best.")
    }

    // MARK: the words

    /// the idle readout is the whole session in a line
    func testTheIdleReadoutIsTheWholeSessionInALine() {
        XCTAssertEqual(SessionTimeline.of(attempt(), marks: nil, trace: nil).idleReadout().title, "2:00 · 2 rounds + 3")
        var flat = attempt()
        flat.rounds = 1
        flat.reps = 0
        XCTAssertEqual(SessionTimeline.of(flat, marks: nil, trace: nil).idleReadout().title, "2:00 · 1 round")
    }

    /// a scrubbed instant reads as a title and a detail
    func testAScrubbedInstantReadsAsATitleAndADetail() {
        let a = attempt()
        let t = SessionTimeline.of(a, marks: marks(a), trace: trace((0, 150), (70_000, 158)),
                                   reference: slower(), referenceKind: .best)

        let r = t.readout(t.at(72_000))

        XCTAssertEqual(r.title, "1:12 · Round 2 · Push-ups")
        XCTAssertEqual(r.detail, "37 reps · 158 bpm · round 1: 10 s ahead of your best")
    }

    /// behind and level are said as such, and a last session is named as last time
    func testBehindAndLevelAreSaidAsSuchAndALastSessionIsNamedAsLastTime() {
        let a = attempt()
        let faster = attempt(at: 500, roundSplits: [50_000, 50_000])
        let level = attempt(at: 400)

        let behind = SessionTimeline.of(a, marks: nil, trace: nil, reference: faster, referenceKind: .last)
        XCTAssertTrue(behind.readout(behind.at(60_000)).detail!.hasSuffix("round 1: 10 s behind last time"))
        let same = SessionTimeline.of(a, marks: nil, trace: nil, reference: level, referenceKind: .best)
        XCTAssertTrue(same.readout(same.at(60_000)).detail!.hasSuffix("round 1: level with your best"))
    }

    /// a record with nothing but a clock still reads as a title
    func testARecordWithNothingButAClockStillReadsAsATitle() {
        let old = attempt(splits: [], counted: nil)
        let t = SessionTimeline.of(old, marks: nil, trace: nil)

        let r = t.readout(t.at(30_000))
        XCTAssertEqual(r.title, "0:30 · Round 1")
        XCTAssertNil(r.detail)
    }

    /// a movement is named in the session's own plural
    func testAMovementIsNamedInTheSessionsOwnPlural() {
        var adaptive = attempt()
        adaptive.profile = CindyProfile(push: .kneePushUp)
        let t = SessionTimeline.of(adaptive, marks: nil, trace: nil)

        XCTAssertEqual(t.readout(t.at(15_000)).title, "0:15 · Round 1 · Knee push-ups")
    }

    /// talkback hears a round the way the spec describes it
    func testTalkbackHearsARoundTheWayTheSpecDescribesIt() {
        let a = attempt()
        let t = SessionTimeline.of(a, marks: marks(a), trace: trace((62_000, 150), (100_000, 166)),
                                   reference: slower(), referenceKind: .best)

        XCTAssertEqual(t.describeRound(t.rounds[1]),
                       "Round 2, 1:00 to 1:50, 50 seconds, 60 reps by its end, 158 beats per minute on average, "
                       + "10 seconds ahead of your best")
    }

    /// talkback says the unfinished round is unfinished, and compares nothing
    func testTalkbackSaysTheUnfinishedRoundIsUnfinishedAndComparesNothing() {
        let a = attempt()
        let t = SessionTimeline.of(a, marks: marks(a), trace: nil, reference: slower(), referenceKind: .best)

        XCTAssertEqual(t.describeRound(t.rounds[2]), "Round 3, in progress, 1:50 to the end at 2:00, 63 reps by the end")
    }

    /// a minute and a second are spoken as such
    func testAMinuteAndASecondAreSpokenAsSuch() {
        XCTAssertEqual(SessionTimeline.spokenSeconds(61), "1 minute 1 second")
        XCTAssertEqual(SessionTimeline.spokenSeconds(120), "2 minutes")
        XCTAssertEqual(SessionTimeline.spokenSeconds(38), "38 seconds")
        XCTAssertEqual(SessionTimeline.shortSeconds(65), "1 min 5 s")
    }

    /// the legend names the dashed line and says when reps are per set
    func testTheLegendNamesTheDashedLineAndSaysWhenRepsArePerSet() {
        let a = attempt()
        let ref = attempt(at: 500)
        let exact = SessionTimeline.of(a, marks: marks(a), trace: nil, reference: ref, referenceKind: .last,
                                       referenceMarks: marks(ref))
        XCTAssertEqual(exact.legend(), "Dashed: last time.")

        let perSet = SessionTimeline.of(a, marks: nil, trace: nil, reference: ref, referenceKind: .best)
        XCTAssertEqual(perSet.legend(), "Dashed: your best. Reps are plotted per set for both sessions.")
        XCTAssertNotNil(perSet.reps)
    }

    // MARK: written for the port: edges the Kotlin tests do not reach, found by mutating the source

    /// a movement is named in the session's own plural, for each of the three
    func testAMovementIsNamedInTheSessionsOwnPluralForEachOfTheThree() {
        var a = attempt()
        a.profile = CindyProfile(pull: .invertedRow, push: .standardPushUp, squat: .boxSquat)
        let t = SessionTimeline.of(a, marks: nil, trace: nil)
        XCTAssertEqual(t.readout(t.at(5_000)).title, "0:05 · Round 1 · Inverted rows")
        XCTAssertEqual(t.readout(t.at(20_000)).title, "0:20 · Round 1 · Push-ups")
        XCTAssertEqual(t.readout(t.at(45_000)).title, "0:45 · Round 1 · Box squats")

        var standardPull = attempt()
        standardPull.profile = CindyProfile(pull: .strictPullUp, push: .kneePushUp, squat: .airSquat)
        let s = SessionTimeline.of(standardPull, marks: nil, trace: nil)
        XCTAssertEqual(s.readout(s.at(5_000)).title, "0:05 · Round 1 · Pull-ups")
        XCTAssertEqual(s.readout(s.at(45_000)).title, "0:45 · Round 1 · Squats")

        var unknown = attempt()
        unknown.profile = nil
        let u = SessionTimeline.of(unknown, marks: nil, trace: nil)
        XCTAssertEqual(u.readout(u.at(5_000)).title, "0:05 · Round 1 · Pull-ups")
    }

    /// one rep is said in the singular, and a hand count of nought is not mentioned
    func testOneRepIsSaidInTheSingularAndAHandCountOfNoughtIsNotMentioned() {
        let a = attempt()
        let t = SessionTimeline.of(a, marks: marks(a), trace: nil)
        XCTAssertEqual(t.readout(t.at(2_000)).detail, "1 rep")
        XCTAssertEqual(t.readout(t.at(4_000)).detail, "2 reps")
    }

    /// a gap between the two sessions is rounded to the nearest second, halves away from zero
    func testAGapBetweenTheTwoSessionsIsRoundedToTheNearestSecond() {
        func gap(_ ms: Int64) -> String? {
            let a = attempt(roundSplits: [60_000, 50_000])
            let ref = attempt(at: 500, splits: [], roundSplits: [60_000 + ms, 50_000], counted: nil)
            let t = SessionTimeline.of(a, marks: nil, trace: nil, reference: ref, referenceKind: .best)
            return t.readout(t.at(60_000 + max(ms, 0) + 1)).detail?.components(separatedBy: " · ").last
        }
        XCTAssertEqual(gap(10_600), "round 1: 11 s ahead of your best")
        XCTAssertEqual(gap(10_400), "round 1: 10 s ahead of your best")
        XCTAssertEqual(gap(500), "round 1: 1 s ahead of your best")
        XCTAssertEqual(gap(499), "round 1: level with your best")
        XCTAssertEqual(gap(-499), "round 1: level with your best")
        XCTAssertEqual(gap(-501), "round 1: 1 s behind your best")
    }

    /// rounds that run past the clock are cut at it
    func testRoundsThatRunPastTheClockAreCutAtIt() {
        let a = attempt(roundSplits: [60_000, 70_000])
        let t = SessionTimeline.of(a, marks: nil, trace: nil)
        XCTAssertEqual(t.roundEnds, [60_000, 120_000])
        XCTAssertEqual(t.rounds.count, 2)
    }

    /// sets that run past the clock are cut at it, and none is left in progress
    func testSetsThatRunPastTheClockAreCutAtItAndNoneIsLeftInProgress() {
        let a = attempt(roundSplits: [], counted: nil, durationMs: 50_000)
        let t = SessionTimeline.of(a, marks: nil, trace: nil)
        XCTAssertEqual(t.sets.map { $0.endMs }, [10_000, 30_000, 50_000, 50_000, 50_000, 50_000])
        XCTAssertFalse(t.sets.contains { $0.inProgress })
    }

    /// a mark a hair past the clock is drawn on it
    func testAMarkAHairPastTheClockIsDrawnOnIt() {
        let a = attempt(splits: [], roundSplits: [], counted: 2, durationMs: 10_000)
        let late = [RepMark(5_000, .pullup, manual: false), RepMark(10_500, .pullup, manual: false)]
        let t = SessionTimeline.of(a, marks: late, trace: nil)
        XCTAssertTrue(t.reps!.exact)
        XCTAssertEqual(t.reps!.points.map { $0.clockMs }, [0, 5_000, 10_000])
    }

    /// sets that add up to exactly what was counted are plotted, with no extra point at the stop
    func testSetsThatAddUpToExactlyWhatWasCountedArePlottedWithNoExtraPointAtTheStop() {
        let a = attempt(counted: 60)
        let series = SessionTimeline.of(a, marks: nil, trace: nil).reps!
        XCTAssertFalse(series.exact)
        XCTAssertEqual(series.points.last, RepPoint(110_000, 60, 0))
    }

    /// the hand count at the stop never exceeds the total counted
    func testTheHandCountAtTheStopNeverExceedsTheTotalCounted() {
        let a = attempt(manual: 100)
        let series = SessionTimeline.of(a, marks: nil, trace: nil).reps!
        XCTAssertEqual(series.points.last, RepPoint(120_000, 63, 63))
    }

    /// sets with no reps in them draw no line
    func testSetsWithNoRepsInThemDrawNoLine() {
        let empty = [SetSplit(.pullup, 10_000, 0, 0), SetSplit(.pushup, 10_000, 0, 0)]
        let a = attempt(splits: empty, roundSplits: [], counted: nil)
        XCTAssertNil(SessionTimeline.of(a, marks: nil, trace: nil).reps)
    }

    /// a round's average counts the samples on both of its edges
    func testARoundsAverageCountsTheSamplesOnBothOfItsEdges() {
        let t = SessionTimeline.of(attempt(), marks: nil, trace: trace((0, 100), (60_000, 120), (110_000, 140)))
        XCTAssertEqual(t.averageBpm(0, 60_000), 110)
        XCTAssertEqual(t.averageBpm(60_000, 110_000), 130)
    }

    /// a mean that ends in a half rounds up
    func testAMeanThatEndsInAHalfRoundsUp() {
        let t = SessionTimeline.of(attempt(), marks: nil, trace: trace((1_000, 100), (2_000, 101)))
        XCTAssertEqual(t.averageBpm(0, 60_000), 101)
    }

    /// seconds under a minute are said as seconds, and a whole minute as a minute
    func testSecondsUnderAMinuteAreSaidAsSecondsAndAWholeMinuteAsAMinute() {
        XCTAssertEqual(SessionTimeline.shortSeconds(59), "59 s")
        XCTAssertEqual(SessionTimeline.shortSeconds(60), "1 min 0 s")
    }

    /// a stretch that starts at the cursor is not before it
    func testAStretchThatStartsAtTheCursorIsNotBeforeIt() {
        let points = [CaloriePoint(0, 0.0, fromHeartRate: false), CaloriePoint(60_000, 60.0, fromHeartRate: true),
                      CaloriePoint(120_000, 100.0, fromHeartRate: false)]
        let a = Attempt(rounds: 2, reps: 3, atMillis: 1_000, durationMs: 120_000, roundSplitsMs: [60_000, 50_000],
                        countedReps: 63, untrackedMs: Records.untrackedToleranceMs, setSplits: [])
        let t = SessionTimeline.of(a, marks: nil, trace: nil, calories: points)
        // By 1:00 only the measured stretch is behind it: no "at least". A moment later the
        // estimated one has begun.
        XCTAssertFalse(t.readout(t.at(60_000)).detail!.contains("at least"))
        XCTAssertTrue(t.readout(t.at(60_001)).detail!.contains("at least"))
    }

    /// the calories at a moment are rounded to the nearest, not cut
    func testTheCaloriesAtAMomentAreRoundedToTheNearestNotCut() {
        let points = [CaloriePoint(0, 0.0, fromHeartRate: false), CaloriePoint(120_000, 100.0, fromHeartRate: false)]
        let a = Attempt(rounds: 0, reps: 0, atMillis: 1_000, durationMs: 120_000, setSplits: [])
        let t = SessionTimeline.of(a, marks: nil, trace: nil, calories: points)
        XCTAssertEqual(t.at(75_000).kcal, 63)   // 62.5
    }
}
