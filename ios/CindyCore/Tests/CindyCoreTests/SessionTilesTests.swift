import XCTest
import CindyCore

/// The six figures under the score. Port of `StatTilesTest.kt` (the tiles; the grid is the screen's).
final class SessionTilesTests: XCTestCase {

    private func attempt(rounds: Int = 7, reps: Int = 12,
                         splits: [Int64] = [150_000, 164_000, 170_000, 171_000, 172_000, 173_000, 174_000],
                         pausedMs: Int64 = 0, untrackedMs: Int64 = 0, manualReps: Int = 0,
                         countedReps: Int? = 222) -> Attempt {
        Attempt(rounds: rounds, reps: reps, atMillis: 1, durationMs: 20 * 60_000, pausedMs: pausedMs,
                roundSplitsMs: splits, manualReps: manualReps, countedReps: countedReps, untrackedMs: untrackedMs)
    }

    private func byLabel(_ a: Attempt, _ stats: SessionStats? = nil) -> [String: StatTile] {
        Dictionary(uniqueKeysWithValues: SessionTiles.of(a, stats).map { ($0.label, $0) })
    }

    /// six tiles in reading order
    func testSixTilesInReadingOrder() {
        XCTAssertEqual(SessionTiles.of(attempt(), nil).map { $0.label }, ["ROUNDS", "REPS", "TIME", "AVG", "FASTEST", "SLOWEST"])
    }

    /// the tiles read the score and the clock
    func testTheTilesReadTheScoreAndTheClock() {
        let t = byLabel(attempt())

        XCTAssertEqual(t["ROUNDS"]!.value, "7")
        XCTAssertEqual(t["ROUNDS"]!.footnote, "+12 reps into round 8")
        XCTAssertEqual(t["REPS"]!.value, "222")
        XCTAssertEqual(t["REPS"]!.footnote, "11.1 reps/min")
        XCTAssertEqual(t["TIME"]!.value, "20:00")
        XCTAssertEqual(t["TIME"]!.footnote, "on the clock")
        XCTAssertEqual(t["FASTEST"]!.value, "2:30")
        XCTAssertEqual(t["FASTEST"]!.footnote, "round 1")
        XCTAssertEqual(t["SLOWEST"]!.value, "2:54")
        XCTAssertEqual(t["SLOWEST"]!.footnote, "round 7")
        XCTAssertEqual(t["AVG"]!.footnote, "over 7 rounds")
    }

    /// reps are the banked score, not a round tally
    func testRepsAreTheBankedScoreNotARoundTally() {
        // One round finished with the pull-ups skipped is 25 reps, never 30.
        let t = byLabel(attempt(rounds: 1, reps: 0, splits: [120_000], countedReps: 25))
        XCTAssertEqual(t["REPS"]!.value, "25")
    }

    /// a lower bound says at least, for the score and the pace
    func testALowerBoundSaysAtLeastForTheScoreAndThePace() {
        let t = byLabel(attempt(untrackedMs: 60_000))

        XCTAssertEqual(t["REPS"]!.footnote, "at least 11.1 reps/min")
        XCTAssertTrue(t["REPS"]!.speech.hasPrefix("Reps: at least 222"), t["REPS"]!.speech)
        XCTAssertTrue(t["REPS"]!.speech.contains("at least 11.1 reps a minute"))
    }

    /// a lower bound says at least over the reps into the next round, spoken too
    func testALowerBoundSaysAtLeastOverTheRepsIntoTheNextRoundSpokenToo() {
        let t = byLabel(attempt(untrackedMs: 60_000))["ROUNDS"]!

        XCTAssertEqual(t.footnote, "at least +12 reps into round 8")
        XCTAssertEqual(t.speech, "Rounds: 7, plus at least 12 reps into round 8")
        XCTAssertEqual(byLabel(attempt())["ROUNDS"]!.speech, "Rounds: 7, plus 12 reps into round 8")
    }

    /// tapped reps are named on the reps tile
    func testTappedRepsAreNamedOnTheRepsTile() {
        let t = byLabel(attempt(manualReps: 12))

        XCTAssertEqual(t["REPS"]!.footnote, "11.1 reps/min · 12 tapped")
        XCTAssertTrue(t["REPS"]!.speech.contains("12 of them tapped in"))
    }

    /// a lower bound with tapped reps keeps the tapped count after the pace
    func testALowerBoundWithTappedRepsKeepsTheTappedCountAfterThePace() {
        let t = byLabel(attempt(untrackedMs: 60_000, manualReps: 12))
        XCTAssertEqual(t["REPS"]!.footnote, "at least 11.1 reps/min · 12 tapped")
    }

    /// the pace is rounded the way Java rounds it: 29 reps in twenty minutes is 1.45, which Java writes 1.5
    func testThePaceIsRoundedTheWayJavaRoundsIt() {
        let t = byLabel(attempt(rounds: 0, reps: 29, splits: [], countedReps: 29))
        XCTAssertEqual(t["REPS"]!.footnote, "1.5 reps/min")   // C would say 1.4
        XCTAssertEqual(t["REPS"]!.speech, "Reps: 29, 1.5 reps a minute")
    }

    /// paused time is said beside the clock
    func testPausedTimeIsSaidBesideTheClock() {
        let t = byLabel(attempt(pausedMs: 65_000))
        XCTAssertEqual(t["TIME"]!.footnote, "plus 1:05 paused")
    }

    /// no complete round is a dash rather than a zero
    func testNoCompleteRoundIsADashRatherThanAZero() {
        let t = byLabel(attempt(rounds: 0, reps: 4, splits: [], countedReps: 4))

        XCTAssertEqual(t["AVG"]!.value, SessionTiles.none)
        XCTAssertEqual(t["FASTEST"]!.value, SessionTiles.none)
        XCTAssertEqual(t["SLOWEST"]!.value, SessionTiles.none)
        XCTAssertEqual(t["ROUNDS"]!.footnote, "+4 reps into round 1")
        XCTAssertEqual(byLabel(attempt(rounds: 0, reps: 0, splits: [], countedReps: 0))["ROUNDS"]!.footnote, "none finished")
    }

    /// the unfinished round comes from the sets when they exist
    func testTheUnfinishedRoundComesFromTheSetsWhenTheyExist() {
        let a = Attempt(rounds: 1, reps: 0, atMillis: 1, durationMs: 20 * 60_000, roundSplitsMs: [52_000], countedReps: 33,
                        setSplits: [SetSplit(.pullup, 14_000, 5, 0), SetSplit(.pushup, 17_000, 10, 0), SetSplit(.squat, 21_000, 15, 0)])
        let t = byLabel(a, SessionStats.from(a))
        XCTAssertEqual(t["ROUNDS"]!.footnote, "+3 reps into round 2")
    }

    /// without round splits the average says it is the clock over the rounds
    func testWithoutRoundSplitsTheAverageSaysItIsTheClockOverTheRounds() {
        let t = byLabel(attempt(splits: []))
        XCTAssertEqual(t["AVG"]!.footnote, "clock over rounds")
    }
}
