import XCTest
import CindyCore

/// The French lines where the grammar has something to get wrong: nought and one, and the clock.
///
/// Mirrors `PhrasebookFrTest.kt`.
final class PhrasebookFrTests: XCTestCase {

    private func say(_ line: VoiceLine) -> String { PhrasebookFr().say(line) }

    private func clock(_ mark: ClockMark, _ rounds: Int, _ reps: Int, _ projected: Int?) -> String {
        say(.clock(mark: mark, rounds: rounds, totalReps: reps, projectedRounds: projected))
    }

    /// movements
    func testMovements() {
        XCTAssertEqual(say(.movement(.pullup)), "tractions")
        XCTAssertEqual(say(.movement(.pushup)), "pompes")
        XCTAssertEqual(say(.movement(.squat)), "squats")
    }

    /// nought and one are both singular
    func testNoughtAndOneAreBothSingular() {
        XCTAssertEqual(say(.score(rounds: 1, totalReps: 30)), "Un tour, 30 répétitions au total")
        XCTAssertEqual(say(.score(rounds: 2, totalReps: 60)), "2 tours, 60 répétitions au total")
        XCTAssertEqual(say(.score(rounds: 6, totalReps: 185)), "6 tours, 185 répétitions au total")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 1)), "Une répétition")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 0)), "0 répétition")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 12)), "12 répétitions")
    }

    /// durations
    func testDurations() {
        XCTAssertEqual(say(.roundDone(round: 3, splitMs: 80_000)), "Tour 3 en une minute et 20 secondes")
        XCTAssertEqual(say(.roundDone(round: 1, splitMs: 45_000)), "Tour 1 en 45 secondes")
        XCTAssertEqual(say(.roundDone(round: 2, splitMs: 120_000)), "Tour 2 en 2 minutes")
        XCTAssertEqual(say(.roundDone(round: 12, splitMs: 61_000)), "Tour 12 en une minute et une seconde")
        XCTAssertEqual(say(.averaging(roundMs: 80_000)), "En moyenne, une minute et 20 secondes par tour")
    }

    /// the clock marks
    func testTheClockMarks() {
        XCTAssertEqual(clock(.fiveMinutesIn, 6, 185, 24), "Cinq minutes. Tu en es à 6 tours. Rythme pour 24 tours.")
        XCTAssertEqual(clock(.halfway, 0, 0, nil), "À mi-parcours. Garde ton rythme.")
        XCTAssertEqual(clock(.fiveMinutesLeft, 1, 30, 1),
                       "Il reste cinq minutes. Tu en es à un tour. Rythme pour un tour.")
        XCTAssertEqual(clock(.twoMinutesLeft, 6, 185, 12),
                       "Deux minutes. 6 tours, 185 répétitions au total. Garde le rythme.")
        XCTAssertEqual(clock(.twoMinutesLeft, 0, 12, nil), "Deux minutes. 12 répétitions. Continue.")
        XCTAssertEqual(clock(.oneMinuteLeft, 11, 340, 11),
                       "Il reste une minute. Tu en es à 11 tours. Termine celui en cours.")
        XCTAssertEqual(clock(.tenSecondsLeft, 6, 185, 12), "Dix secondes. Donne tout.")
    }

    /// recording
    func testRecording() {
        XCTAssertEqual(say(.recordingSoon(seconds: 3)), "Enregistrement dans 3 secondes")
        XCTAssertEqual(say(.recordingSoon(seconds: 1)), "Enregistrement dans une seconde")
        XCTAssertEqual(say(.recordingStarted), "Enregistrement en cours")
        XCTAssertEqual(say(.recordingFailed), "L'enregistrement a échoué")
    }

    /// a hint is translated and an unknown one falls back to something French
    func testAHintIsTranslatedAndAnUnknownOneFallsBackToSomethingFrench() {
        XCTAssertEqual(say(.fault(hint: "Get on the bar")), "Attrape la barre")
        XCTAssertEqual(say(.fault(hint: "Something nobody catalogued")), "Vérifie ta position")
    }
}
