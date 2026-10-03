import XCTest
import CindyCore

/// What the voice says about the clock.
///
/// The ticker runs five times a second, so the first thing these hold is that a mark is spoken
/// once. The second is that every line carries a figure the athlete cannot read off the screen —
/// the time alone is already in front of them.
///
/// Mirrors `CoachClockTest.kt`.
final class CoachClockTests: XCTestCase {

    private let coach = Coach()

    /// Runs the clock down to `remainingMs`, ticking as the workout does, collecting the lines.
    private func linesTo(_ remainingMs: Int64, rounds: Int = 0, totalReps: Int = 0) -> [VoiceLine] {
        var said: [VoiceLine] = []
        var remaining: Int64 = 20 * 60_000
        while remaining > remainingMs {
            remaining -= 200
            if let line = coach.onClock(elapsedMs: 20 * 60_000 - remaining, remainingMs: remaining,
                                        rounds: rounds, totalReps: totalReps) { said.append(line) }
        }
        return said
    }

    /// The same, in the English the assertions below are written in.
    private func runTo(_ remainingMs: Int64, rounds: Int = 0, totalReps: Int = 0) -> [String] {
        linesTo(remainingMs, rounds: rounds, totalReps: totalReps).map { PhrasebookEn().say($0) }
    }

    /// A score in English words, which is how the assertions below are written.
    private func score(_ rounds: Int, _ totalReps: Int) -> String {
        PhrasebookEn().say(.score(rounds: rounds, totalReps: totalReps))
    }

    /// a mark is spoken once, not on every tick
    func testAMarkIsSpokenOnceNotOnEveryTick() {
        let said = runTo(9 * 60_000, rounds: 6)
        XCTAssertEqual(said.count, 2, "fifteen and ten minutes, once each")
    }

    /// halfway carries the pace, not just the time
    func testHalfwayCarriesThePaceNotJustTheTime() {
        let said = runTo(10 * 60_000 - 200, rounds: 6)
        let halfway = said.last!
        XCTAssertTrue(halfway.hasPrefix("Halfway."), halfway)
        // Six rounds in ten minutes projects to twelve over the twenty.
        XCTAssertTrue(halfway.contains("6 rounds"), halfway)
        XCTAssertTrue(halfway.contains("on for 12"), halfway)
    }

    /// a pace is not projected before there is a round to project from
    func testAPaceIsNotProjectedBeforeThereIsARoundToProjectFrom() {
        let said = runTo(15 * 60_000 - 200, rounds: 0)
        XCTAssertEqual(said.count, 1)
        XCTAssertTrue(said[0].contains("Keep the pace"), said[0])
    }

    /// the last minute names the score rather than projecting it
    func testTheLastMinuteNamesTheScoreRatherThanProjectingIt() {
        let said = runTo(60_000 - 200, rounds: 11, totalReps: 340)
        let lastMinute = said.last!
        XCTAssertTrue(lastMinute.hasPrefix("One minute left."), lastMinute)
        XCTAssertTrue(lastMinute.contains("11 rounds"), lastMinute)
    }

    /// a finished round is never reported as zero reps
    func testAFinishedRoundIsNeverReportedAsZeroReps() {
        // The bug this exists to stop: the score was read off the reps of the round in
        // progress, which a completed round leaves at zero. One clean round is thirty reps of
        // work and was being announced as none, over a results screen reading thirty.
        let said = score(1, 30)
        XCTAssertTrue(said.contains("30 reps"), said)
        // Word-boundary, because "30 reps" contains "0 reps" as plain text.
        XCTAssertNil(said.range(of: "\\b0 reps", options: .regularExpression), said)
    }

    /// the rep figure is the whole tally, said as one
    func testTheRepFigureIsTheWholeTallySaidAsOne() {
        // "and 30 reps" would invite hearing a round plus thirty more. The total includes the
        // round, so the line has to say which of the two it means.
        XCTAssertEqual(score(1, 30), "1 round — 30 reps in total")
        XCTAssertEqual(score(6, 185), "6 rounds — 185 reps in total")
    }

    /// a score with no round behind it is just the reps
    func testAScoreWithNoRoundBehindItIsJustTheReps() {
        XCTAssertEqual(score(0, 12), "12 reps")
        XCTAssertEqual(score(0, 1), "1 rep")
        // An athlete who stopped before anything counted is owed the honest zero.
        XCTAssertEqual(score(0, 0), "0 reps")
    }

    /// the clock says the score the same way the ending does
    func testTheClockSaysTheScoreTheSameWayTheEndingDoes() {
        let said = runTo(2 * 60_000 - 200, rounds: 1, totalReps: 30).last!
        XCTAssertTrue(said.hasPrefix("Two minutes."), said)
        XCTAssertTrue(said.contains(score(1, 30)), said)
    }

    /// nothing is said between marks
    func testNothingIsSaidBetweenMarks() {
        _ = coach.onClock(elapsedMs: 60_000, remainingMs: 19 * 60_000, rounds: 0, totalReps: 0)
        XCTAssertNil(coach.onClock(elapsedMs: 61_000, remainingMs: 19 * 60_000 - 1_000, rounds: 0, totalReps: 0))
    }

    /// a reset lets the next workout hear its marks again
    func testAResetLetsTheNextWorkoutHearItsMarksAgain() {
        let first = runTo(10 * 60_000 - 200, rounds: 6)
        XCTAssertEqual(first.count, 2)

        coach.reset()

        let second = runTo(10 * 60_000 - 200, rounds: 6)
        XCTAssertEqual(second.count, 2, "a new workout gets its own marks")
    }

    /// a pause does not replay the marks already spoken
    func testAPauseDoesNotReplayTheMarksAlreadySpoken() {
        let before = runTo(10 * 60_000 - 200, rounds: 6)
        XCTAssertEqual(before.count, 2)

        coach.interrupted()

        // Back on the bar at the same point in the clock: halfway has been and gone.
        XCTAssertNil(coach.onClock(elapsedMs: 10 * 60_000, remainingMs: 10 * 60_000 - 200, rounds: 6, totalReps: 180))
    }

    /// a mark is a line carrying the facts, not the words
    func testAMarkIsALineCarryingTheFactsNotTheWords() {
        // What the phrasebooks are handed. The coach decides when and what about; how it sounds
        // belongs to whichever language ends up speaking.
        XCTAssertEqual(
            linesTo(10 * 60_000 - 200, rounds: 6, totalReps: 185),
            [
                .clock(mark: .fiveMinutesIn, rounds: 6, totalReps: 185, projectedRounds: 24),
                .clock(mark: .halfway, rounds: 6, totalReps: 185, projectedRounds: 12)
            ])
    }

    /// every mark arrives in the order of the clock
    func testEveryMarkArrivesInTheOrderOfTheClock() {
        let marks: [ClockMark] = linesTo(0, rounds: 6, totalReps: 185).compactMap {
            if case .clock(let mark, _, _, _) = $0 { return mark }
            return nil
        }
        XCTAssertEqual(marks, [.fiveMinutesIn, .halfway, .fiveMinutesLeft, .twoMinutesLeft,
                               .oneMinuteLeft, .tenSecondsLeft])
    }

    /// nothing is projected before there is a round to project from
    func testNothingIsProjectedBeforeThereIsARoundToProjectFrom() {
        guard case .clock(_, _, _, let projected)? = linesTo(15 * 60_000 - 200, rounds: 0).first
        else { return XCTFail("no mark was spoken") }
        XCTAssertNil(projected)
        // Nor in the first minute, when one early round would project to a wild number.
        let early = Coach().onClock(elapsedMs: 30_000, remainingMs: 15 * 60_000, rounds: 1, totalReps: 30)
        guard case .clock(_, _, _, let earlyProjected)? = early else { return XCTFail("no mark was spoken") }
        XCTAssertNil(earlyProjected)
    }
}
