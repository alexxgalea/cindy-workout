import XCTest
import CindyCore

/// The Italian lines where the grammar has something to get wrong: 1, the rest, and the clock.
///
/// Mirrors `PhrasebookItTest.kt`.
final class PhrasebookItTests: XCTestCase {

    private func say(_ line: VoiceLine) -> String { PhrasebookIt().say(line) }

    private func clock(_ mark: ClockMark, _ rounds: Int, _ reps: Int, _ projected: Int?) -> String {
        say(.clock(mark: mark, rounds: rounds, totalReps: reps, projectedRounds: projected))
    }

    /// movements
    func testMovements() {
        XCTAssertEqual(say(.movement(.pullup)), "trazioni")
        XCTAssertEqual(say(.movement(.pushup)), "flessioni")
        XCTAssertEqual(say(.movement(.squat)), "squat")
    }

    /// one is written out and the rest are counted
    func testOneIsWrittenOutAndTheRestAreCounted() {
        XCTAssertEqual(say(.score(rounds: 1, totalReps: 30)), "Un giro, 30 ripetizioni in totale")
        XCTAssertEqual(say(.score(rounds: 6, totalReps: 185)), "6 giri, 185 ripetizioni in totale")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 1)), "Una ripetizione")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 12)), "12 ripetizioni")
    }

    /// durations
    func testDurations() {
        XCTAssertEqual(say(.roundDone(round: 3, splitMs: 80_000)), "Giro 3 in un minuto e 20 secondi")
        XCTAssertEqual(say(.roundDone(round: 1, splitMs: 45_000)), "Giro 1 in 45 secondi")
        XCTAssertEqual(say(.roundDone(round: 2, splitMs: 120_000)), "Giro 2 in 2 minuti")
        XCTAssertEqual(say(.averaging(roundMs: 80_000)), "In media un minuto e 20 secondi a giro")
    }

    /// the clock marks
    func testTheClockMarks() {
        XCTAssertEqual(clock(.fiveMinutesIn, 6, 185, 24), "Cinque minuti. Sei a 6 giri. Ritmo da 24 giri.")
        XCTAssertEqual(clock(.halfway, 0, 0, nil), "Metà tempo. Mantieni il tuo ritmo.")
        XCTAssertEqual(clock(.fiveMinutesLeft, 1, 30, 1),
                       "Mancano cinque minuti. Sei a un giro. Ritmo da un giro.")
        XCTAssertEqual(clock(.twoMinutesLeft, 6, 185, 12),
                       "Due minuti. 6 giri, 185 ripetizioni in totale. Mantieni il ritmo.")
        XCTAssertEqual(clock(.twoMinutesLeft, 0, 12, nil), "Due minuti. 12 ripetizioni. Continua così.")
        XCTAssertEqual(clock(.oneMinuteLeft, 11, 340, 11),
                       "Manca un minuto. Sei a 11 giri. Finisci quello in corso.")
        XCTAssertEqual(clock(.tenSecondsLeft, 6, 185, 12), "Dieci secondi. Dai tutto.")
    }

    /// recording
    func testRecording() {
        XCTAssertEqual(say(.recordingSoon(seconds: 3)), "Registrazione tra 3 secondi")
        XCTAssertEqual(say(.recordingSoon(seconds: 1)), "Registrazione tra un secondo")
        XCTAssertEqual(say(.recordingStarted), "Registrazione in corso")
        XCTAssertEqual(say(.recordingFailed), "Registrazione non riuscita")
    }

    /// a hint is translated and an unknown one falls back to something Italian
    func testAHintIsTranslatedAndAnUnknownOneFallsBackToSomethingItalian() {
        XCTAssertEqual(say(.fault(hint: "Get on the bar")), "Afferra la sbarra")
        XCTAssertEqual(say(.fault(hint: "Something nobody catalogued")), "Controlla la tua posizione")
    }
}
