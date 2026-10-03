import XCTest
import CindyCore

/// The Dutch lines where the grammar has something to get wrong: 1, the rest, and the clock.
///
/// Mirrors `PhrasebookNlTest.kt`.
final class PhrasebookNlTests: XCTestCase {

    private func say(_ line: VoiceLine) -> String { PhrasebookNl().say(line) }

    private func clock(_ mark: ClockMark, _ rounds: Int, _ reps: Int, _ projected: Int?) -> String {
        say(.clock(mark: mark, rounds: rounds, totalReps: reps, projectedRounds: projected))
    }

    /// movements
    func testMovements() {
        XCTAssertEqual(say(.movement(.pullup)), "optrekken")
        XCTAssertEqual(say(.movement(.pushup)), "opdrukken")
        XCTAssertEqual(say(.movement(.squat)), "squats")
    }

    /// one is written out and the rest are counted
    func testOneIsWrittenOutAndTheRestAreCounted() {
        XCTAssertEqual(say(.score(rounds: 1, totalReps: 30)), "Een ronde, 30 herhalingen in totaal")
        XCTAssertEqual(say(.score(rounds: 6, totalReps: 185)), "6 rondes, 185 herhalingen in totaal")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 1)), "Een herhaling")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 12)), "12 herhalingen")
    }

    /// durations
    func testDurations() {
        XCTAssertEqual(say(.roundDone(round: 3, splitMs: 80_000)), "Ronde 3 in een minuut en 20 seconden")
        XCTAssertEqual(say(.roundDone(round: 1, splitMs: 45_000)), "Ronde 1 in 45 seconden")
        XCTAssertEqual(say(.roundDone(round: 2, splitMs: 120_000)), "Ronde 2 in 2 minuten")
        XCTAssertEqual(say(.averaging(roundMs: 80_000)), "Gemiddeld een minuut en 20 seconden per ronde")
    }

    /// the clock marks
    func testTheClockMarks() {
        XCTAssertEqual(clock(.fiveMinutesIn, 6, 185, 24),
                       "Vijf minuten bezig. Je hebt 6 rondes. Tempo voor 24 rondes.")
        XCTAssertEqual(clock(.halfway, 0, 0, nil), "Halverwege. Houd je tempo vast.")
        XCTAssertEqual(clock(.fiveMinutesLeft, 1, 30, 1),
                       "Nog vijf minuten. Je hebt een ronde. Tempo voor een ronde.")
        XCTAssertEqual(clock(.twoMinutesLeft, 6, 185, 12),
                        "Twee minuten. 6 rondes, 185 herhalingen in totaal. Houd het tempo vast.")
        XCTAssertEqual(clock(.twoMinutesLeft, 0, 12, nil), "Twee minuten. 12 herhalingen. Ga door.")
        XCTAssertEqual(clock(.oneMinuteLeft, 11, 340, 11),
                       "Nog een minuut. Je hebt 11 rondes. Maak de huidige ronde af.")
        XCTAssertEqual(clock(.tenSecondsLeft, 6, 185, 12), "Tien seconden. Geef alles.")
    }

    /// recording
    func testRecording() {
        XCTAssertEqual(say(.recordingSoon(seconds: 3)), "Opname over 3 seconden")
        XCTAssertEqual(say(.recordingSoon(seconds: 1)), "Opname over een seconde")
        XCTAssertEqual(say(.recordingStarted), "Opname gestart")
        XCTAssertEqual(say(.recordingFailed), "Opname mislukt")
    }

    /// a hint is translated and an unknown one falls back to something Dutch
    func testAHintIsTranslatedAndAnUnknownOneFallsBackToSomethingDutch() {
        XCTAssertEqual(say(.fault(hint: "Get on the bar")), "Pak de stang")
        XCTAssertEqual(say(.fault(hint: "Something nobody catalogued")), "Controleer je positie")
    }
}
