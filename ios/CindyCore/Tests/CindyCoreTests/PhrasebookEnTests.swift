import XCTest
import CindyCore

/// The words the voice has always said, held byte for byte.
///
/// Every expected string here is what the app said before the voice went through phrasebooks —
/// the literals that lived in the app and in `Coach`. Making the voice multilingual is only safe if
/// English cannot change underneath it, and nothing else would notice: these are lines that are
/// spoken once a workout, over a screen nobody is looking at.
///
/// Mirrors `PhrasebookEnTest.kt`.
final class PhrasebookEnTests: XCTestCase {

    private let book = PhrasebookEn()

    private func say(_ line: VoiceLine) -> String { book.say(line) }

    /// a count is the bare number
    func testACountIsTheBareNumber() {
        XCTAssertEqual(say(.count(reps: 0)), "0")
        XCTAssertEqual(say(.count(reps: 3)), "3")
        XCTAssertEqual(say(.count(reps: 15)), "15")
    }

    /// movements are the names the engine carries
    func testMovementsAreTheNamesTheEngineCarries() {
        XCTAssertEqual(say(.movement(.pullup)), "pull ups")
        XCTAssertEqual(say(.movement(.pushup)), "push ups")
        XCTAssertEqual(say(.movement(.squat)), "squats")
    }

    /// a round names its number and its time
    func testARoundNamesItsNumberAndItsTime() {
        XCTAssertEqual(say(.roundDone(round: 3, splitMs: 80_000)), "Round 3 in 1 minute 20")
        XCTAssertEqual(say(.roundDone(round: 1, splitMs: 45_000)), "Round 1 in 45 seconds")
        XCTAssertEqual(say(.roundDone(round: 12, splitMs: 120_000)), "Round 12 in 2 minutes")
    }

    /// durations are said the way a person says them
    func testDurationsAreSaidTheWayAPersonSaysThem() {
        XCTAssertEqual(book.duration(45_000), "45 seconds")
        XCTAssertEqual(book.duration(60_000), "1 minute")
        XCTAssertEqual(book.duration(120_000), "2 minutes")
        XCTAssertEqual(book.duration(61_000), "1 minute 1")
        XCTAssertEqual(book.duration(150_000), "2 minutes 30")
        // Sub-second remainders are dropped, not rounded up.
        XCTAssertEqual(book.duration(80_999), "1 minute 20")
    }

    /// the fixed announcements
    func testTheFixedAnnouncements() {
        XCTAssertEqual(say(.phoneMoved), "Phone moved. Check the framing.")
        XCTAssertEqual(say(.setUp), "Get in frame, then do two slow pull ups")
        XCTAssertEqual(say(.resume), "Resume")
        XCTAssertEqual(say(.ready), "Ready")
    }

    /// the start says whether the check was passed
    func testTheStartSaysWhetherTheCheckWasPassed() {
        XCTAssertEqual(say(.go(calibrated: true)), "Calibrated. Go.")
        XCTAssertEqual(say(.go(calibrated: false)), "Go. Pull ups")
    }

    /// the end says whether the athlete called it
    func testTheEndSaysWhetherTheAthleteCalledIt() {
        XCTAssertEqual(say(.finished(early: false)), "Time.")
        XCTAssertEqual(say(.finished(early: true)), "Stopped.")
    }

    /// the average round and the benchmark
    func testTheAverageRoundAndTheBenchmark() {
        XCTAssertEqual(say(.averaging(roundMs: 80_000)), "Averaging 1 minute 20 a round")
        XCTAssertEqual(say(.beatBenchmark(name: "Tom Holland")), "You beat Tom Holland")
    }

    /// a fault is the engine's hint, untouched
    func testAFaultIsTheEnginesHintUntouched() {
        XCTAssertEqual(say(.fault(hint: "Get on the bar")), "Get on the bar")
        // Including one nobody has catalogued: English never invents a sentence.
        XCTAssertEqual(say(.fault(hint: "Something new")), "Something new")
    }

    /// a score names the rounds and the whole rep tally
    func testAScoreNamesTheRoundsAndTheWholeRepTally() {
        XCTAssertEqual(say(.score(rounds: 6, totalReps: 185)), "6 rounds — 185 reps in total")
        XCTAssertEqual(say(.score(rounds: 1, totalReps: 30)), "1 round — 30 reps in total")
        // Before a round is in there is nothing to name but the reps.
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 12)), "12 reps")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 1)), "1 rep")
    }

    /// a finished round is never reported as zero reps
    func testAFinishedRoundIsNeverReportedAsZeroReps() {
        // The bug this exists to stop: the score was read off the reps of the round in
        // progress, which a completed round leaves at zero. One clean round is thirty reps of
        // work and was being announced as none, over a results screen reading thirty.
        let said = say(.score(rounds: 1, totalReps: 30))
        XCTAssertTrue(said.contains("30 reps"), said)
        // Word-boundary, because "30 reps" contains "0 reps" as plain text.
        XCTAssertNil(said.range(of: "\\b0 reps", options: .regularExpression), said)
    }

    /// the clock marks
    func testTheClockMarks() {
        func clock(_ mark: ClockMark, _ rounds: Int, _ reps: Int, _ projected: Int?) -> String {
            say(.clock(mark: mark, rounds: rounds, totalReps: reps, projectedRounds: projected))
        }

        XCTAssertEqual(clock(.fiveMinutesIn, 6, 185, 24), "Five minutes in. 6 rounds — on for 24.")
        XCTAssertEqual(clock(.halfway, 6, 185, 12), "Halfway. 6 rounds — on for 12.")
        XCTAssertEqual(clock(.fiveMinutesLeft, 1, 30, 2), "Five minutes left. 1 round — on for 2.")
        XCTAssertEqual(clock(.twoMinutesLeft, 6, 185, 12),
                       "Two minutes. 6 rounds — 185 reps in total. Hold the pace.")
        XCTAssertEqual(clock(.oneMinuteLeft, 11, 340, 11),
                       "One minute left. 11 rounds down — finish the one you're in.")
        XCTAssertEqual(clock(.oneMinuteLeft, 1, 30, 1),
                       "One minute left. 1 round down — finish the one you're in.")
        XCTAssertEqual(clock(.tenSecondsLeft, 6, 185, 12), "Ten seconds. Everything you have.")
    }

    /// the clock has nothing to project before a round is in
    func testTheClockHasNothingToProjectBeforeARoundIsIn() {
        func clock(_ mark: ClockMark) -> String {
            say(.clock(mark: mark, rounds: 0, totalReps: 0, projectedRounds: nil))
        }

        XCTAssertEqual(clock(.halfway), "Halfway. Keep the pace you're on.")
        XCTAssertEqual(clock(.fiveMinutesIn), "Five minutes in. Keep the pace you're on.")
        XCTAssertEqual(clock(.fiveMinutesLeft), "Five minutes left. Keep the pace you're on.")
        XCTAssertEqual(clock(.twoMinutesLeft), "Two minutes. 0 reps. Keep going.")
    }

    /// the menu's samples
    func testTheMenusSamples() {
        XCTAssertEqual(say(.sample), "Three. Four. Five. Push ups.")
        XCTAssertEqual(say(.volumeCheck), "Three")
    }

    /// recording is announced in words, never as a bare number
    func testRecordingIsAnnouncedInWordsNeverAsABareNumber() {
        // Beside the rep counts a lone "3" would be taken for one.
        XCTAssertEqual(say(.recordingSoon(seconds: 3)), "Recording in 3")
        XCTAssertEqual(say(.recordingStarted), "Recording")
        XCTAssertEqual(say(.recordingFailed), "Recording failed")
    }

    /// switching to heels flat squats says so in words
    func testSwitchingToHeelsFlatSquatsSaysSoInWords() {
        XCTAssertEqual(say(.adaptiveHeelsFlat), "Adaptive Cindy activated for heels-flat squats.")
    }

    /// every line is said in words
    func testEveryLineIsSaidInWords() {
        for line in VoiceLineSamples.all {
            XCTAssertFalse(say(line).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(line) was blank")
        }
    }

    /// the samples cover every kind of line
    func testTheSamplesCoverEveryKindOfLine() {
        XCTAssertEqual(
            Set(VoiceLineSamples.all.map { VoiceLineSamples.kind(of: $0) }).count, VoiceLineSamples.kinds,
            "a kind of line has no sample, or KINDS is out of date")
    }
}
