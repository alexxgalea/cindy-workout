import XCTest
import CindyCore

/// Mirrors `ComparisonsTest.kt`.
final class ComparisonsTests: XCTestCase {

    private func attempt(
        _ rounds: Int, reps: Int = 0, at: Int64 = 0,
        profile: CindyProfile? = CindyProfile.standard,
        roundSplitsMs: [Int64] = [], untrackedMs: Int64 = 0
    ) -> Attempt {
        Attempt(rounds: rounds, reps: reps, atMillis: at, roundSplitsMs: roundSplitsMs,
                profile: profile, untrackedMs: untrackedMs)
    }

    // MARK: - earlier

    /// earlier excludes the session itself and anything after it
    func testEarlierExcludesTheSessionItselfAndAnythingAfterIt() {
        let of = attempt(10, at: 2000)
        let before = attempt(8, at: 1000)
        let same = attempt(9, at: 2000)
        let after = attempt(12, at: 3000)
        XCTAssertEqual(Comparisons.earlier([before, same, after, of], of: of), [before])
    }

    /// earlier excludes other categories
    func testEarlierExcludesOtherCategories() {
        let of = attempt(10, at: 2000, profile: CindyProfile.standard)
        let adaptive = attempt(8, at: 1000, profile: CindyProfile(push: .kneePushUp))
        let unrecognised = attempt(8, at: 1000, profile: nil)
        XCTAssertEqual(Comparisons.earlier([adaptive, unrecognised], of: of), [])
    }

    /// earlier matches two unrecognised sessions to each other
    func testEarlierMatchesTwoUnrecognisedSessionsToEachOther() {
        let of = attempt(10, at: 2000, profile: nil)
        let before = attempt(8, at: 1000, profile: nil)
        XCTAssertEqual(Comparisons.earlier([before], of: of), [before])
    }

    /// nothing earlier than a first session
    func testNothingEarlierThanAFirstSession() {
        let of = attempt(10, at: 1000)
        XCTAssertEqual(Comparisons.earlier([], of: of), [])
    }

    // MARK: - best and last

    /// best is the highest score among earlier sessions
    func testBestIsTheHighestScoreAmongEarlierSessions() {
        let of = attempt(20, at: 4000)
        let weaker = attempt(10, at: 1000)
        let strongest = attempt(15, at: 2000)
        let middling = attempt(12, at: 3000)
        XCTAssertEqual(Comparisons.best([weaker, strongest, middling], of: of), strongest)
    }

    /// last is the most recent earlier session, regardless of score
    func testLastIsTheMostRecentEarlierSessionRegardlessOfScore() {
        let of = attempt(20, at: 4000)
        let better = attempt(15, at: 1000)
        let mostRecent = attempt(10, at: 3000)
        XCTAssertEqual(Comparisons.last([better, mostRecent], of: of), mostRecent)
    }

    /// best and last are null without an earlier session
    func testBestAndLastAreNullWithoutAnEarlierSession() {
        let of = attempt(10, at: 1000)
        XCTAssertNil(Comparisons.best([], of: of))
        XCTAssertNil(Comparisons.last([], of: of))
    }

    // MARK: - a lower-bound attempt is still compared with, never specially excluded

    /// a lower-bound session can still be the best, and still deltas cleanly
    func testALowerBoundSessionCanStillBeTheBestAndStillDeltasCleanly() {
        let of = attempt(20, at: 3000)
        let degraded = attempt(25, at: 1000, untrackedMs: 60_000)
        let clean = attempt(10, at: 2000)
        XCTAssertEqual(Comparisons.best([degraded, clean], of: of), degraded)
        let delta = Comparisons.delta(of, degraded)
        XCTAssertEqual(delta.reps, of.totalReps - degraded.totalReps)
    }

    // MARK: - options: dedupe and the empty case

    /// options offers both best and last when they differ
    func testOptionsOffersBothBestAndLastWhenTheyDiffer() {
        let of = attempt(20, at: 3000)
        let best = attempt(15, at: 1000)
        let last = attempt(5, at: 2000)
        let options = Comparisons.options([best, last], of: of)
        XCTAssertEqual(options.map { $0.kind }, [.best, .last])
        XCTAssertEqual(options[0].label, "Your best")
        XCTAssertEqual(options[0].attempt, best)
        XCTAssertEqual(options[1].label, "Last time")
        XCTAssertEqual(options[1].attempt, last)
    }

    /// options drops last when it is the same session as best
    func testOptionsDropsLastWhenItIsTheSameSessionAsBest() {
        let of = attempt(20, at: 3000)
        let onlyEarlierSession = attempt(15, at: 1000)
        let options = Comparisons.options([onlyEarlierSession], of: of)
        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options[0].kind, .best)
        XCTAssertEqual(options[0].label, "Your best · also last time")
    }

    /// options is empty with no earlier session, which is what hides the card
    func testOptionsIsEmptyWithNoEarlierSessionWhichIsWhatHidesTheCard() {
        let of = attempt(10, at: 1000)
        XCTAssertTrue(Comparisons.options([], of: of).isEmpty)
        XCTAssertTrue(Comparisons.options([attempt(5, at: 2000)], of: of).isEmpty)
    }

    // MARK: - delta

    /// delta reads reps and rounds this session minus the reference
    func testDeltaReadsRepsAndRoundsThisSessionMinusTheReference() {
        let of = attempt(6, reps: 20, at: 2000)
        let reference = attempt(6, at: 1000)
        let d = Comparisons.delta(of, reference)
        XCTAssertEqual(d.reps, of.totalReps - reference.totalReps)
        XCTAssertEqual(d.rounds, 0)
    }

    /// average round delta is positive when this session was faster
    func testAverageRoundDeltaIsPositiveWhenThisSessionWasFaster() {
        let of = attempt(2, at: 2000, roundSplitsMs: [100_000, 100_000])
        let reference = attempt(2, at: 1000, roundSplitsMs: [140_000, 140_000])
        XCTAssertEqual(Comparisons.delta(of, reference).avgRoundMs, 40_000)
        XCTAssertEqual(Comparisons.delta(reference, of).avgRoundMs, -40_000)
    }

    /// average round delta is null when either side has none
    func testAverageRoundDeltaIsNullWhenEitherSideHasNone() {
        let withSplits = attempt(2, at: 2000, roundSplitsMs: [100_000, 100_000])
        let withoutSplits = attempt(0, reps: 5, at: 1000)
        XCTAssertNil(Comparisons.delta(withSplits, withoutSplits).avgRoundMs)
        XCTAssertNil(Comparisons.delta(withoutSplits, withSplits).avgRoundMs)
    }
}
