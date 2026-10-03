import XCTest
import CindyCore

/// The German lines where the grammar has something to get wrong: 1, the dative, and the clock.
///
/// Mirrors `PhrasebookDeTest.kt`.
final class PhrasebookDeTests: XCTestCase {

    private func say(_ line: VoiceLine) -> String { PhrasebookDe().say(line) }

    private func clock(_ mark: ClockMark, _ rounds: Int, _ reps: Int, _ projected: Int?) -> String {
        say(.clock(mark: mark, rounds: rounds, totalReps: reps, projectedRounds: projected))
    }

    /// movements
    func testMovements() {
        XCTAssertEqual(say(.movement(.pullup)), "Klimmzüge")
        XCTAssertEqual(say(.movement(.pushup)), "Liegestütze")
        XCTAssertEqual(say(.movement(.squat)), "Kniebeugen")
    }

    /// one is written out and the rest are counted
    func testOneIsWrittenOutAndTheRestAreCounted() {
        XCTAssertEqual(say(.score(rounds: 1, totalReps: 30)), "Eine Runde, 30 Wiederholungen insgesamt")
        XCTAssertEqual(say(.score(rounds: 6, totalReps: 185)), "6 Runden, 185 Wiederholungen insgesamt")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 1)), "Eine Wiederholung")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 12)), "12 Wiederholungen")
    }

    /// a round's time follows Zeit so the count stays nominative
    func testARoundsTimeFollowsZeitSoTheCountStaysNominative() {
        XCTAssertEqual(say(.roundDone(round: 3, splitMs: 80_000)), "Runde 3, Zeit eine Minute und 20 Sekunden")
        XCTAssertEqual(say(.roundDone(round: 1, splitMs: 45_000)), "Runde 1, Zeit 45 Sekunden")
        XCTAssertEqual(say(.roundDone(round: 2, splitMs: 120_000)), "Runde 2, Zeit 2 Minuten")
        XCTAssertEqual(say(.averaging(roundMs: 80_000)), "Im Schnitt eine Minute und 20 Sekunden pro Runde")
    }

    /// the clock marks
    func testTheClockMarks() {
        XCTAssertEqual(clock(.fiveMinutesIn, 6, 185, 24),
                       "Fünf Minuten sind um. 6 Runden geschafft. Tempo für 24 Runden.")
        XCTAssertEqual(clock(.halfway, 0, 0, nil), "Halbzeit. Halte dein Tempo.")
        XCTAssertEqual(clock(.fiveMinutesLeft, 1, 30, 1),
                       "Noch fünf Minuten. Eine Runde geschafft. Tempo für eine Runde.")
        XCTAssertEqual(clock(.twoMinutesLeft, 6, 185, 12),
                       "Zwei Minuten. 6 Runden, 185 Wiederholungen insgesamt. Halte das Tempo.")
        XCTAssertEqual(clock(.twoMinutesLeft, 0, 12, nil), "Zwei Minuten. 12 Wiederholungen. Weiter so.")
        XCTAssertEqual(clock(.oneMinuteLeft, 1, 30, 1),
                       "Noch eine Minute. Eine Runde geschafft. Beende die laufende Runde.")
        XCTAssertEqual(clock(.tenSecondsLeft, 6, 185, 12), "Zehn Sekunden. Gib alles.")
    }

    /// recording puts a single second in the dative
    func testRecordingPutsASingleSecondInTheDative() {
        XCTAssertEqual(say(.recordingSoon(seconds: 3)), "Aufnahme in 3 Sekunden")
        XCTAssertEqual(say(.recordingSoon(seconds: 1)), "Aufnahme in einer Sekunde")
        XCTAssertEqual(say(.recordingStarted), "Aufnahme läuft")
        XCTAssertEqual(say(.recordingFailed), "Aufnahme fehlgeschlagen")
    }

    /// a hint is translated and an unknown one falls back to something German
    func testAHintIsTranslatedAndAnUnknownOneFallsBackToSomethingGerman() {
        XCTAssertEqual(say(.fault(hint: "Get on the bar")), "Greif die Stange")
        XCTAssertEqual(say(.fault(hint: "Something nobody catalogued")), "Prüfe deine Position")
    }
}
