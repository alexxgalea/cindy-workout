import XCTest
import CindyCore

/// The Spanish lines where the grammar has something to get wrong: 1, the rest, and the clock.
///
/// Mirrors `PhrasebookEsTest.kt`.
final class PhrasebookEsTests: XCTestCase {

    private func say(_ line: VoiceLine) -> String { PhrasebookEs().say(line) }

    /// movements
    func testMovements() {
        XCTAssertEqual(say(.movement(.pullup)), "dominadas")
        XCTAssertEqual(say(.movement(.pushup)), "flexiones")
        XCTAssertEqual(say(.movement(.squat)), "sentadillas")
    }

    /// one is written out and the rest are counted
    func testOneIsWrittenOutAndTheRestAreCounted() {
        XCTAssertEqual(say(.score(rounds: 1, totalReps: 30)), "Una ronda, 30 repeticiones en total")
        XCTAssertEqual(say(.score(rounds: 6, totalReps: 185)), "6 rondas, 185 repeticiones en total")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 1)), "Una repetición")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 12)), "12 repeticiones")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 0)), "0 repeticiones")
    }

    /// durations
    func testDurations() {
        XCTAssertEqual(say(.roundDone(round: 3, splitMs: 80_000)), "Ronda 3 en un minuto y 20 segundos")
        XCTAssertEqual(say(.roundDone(round: 1, splitMs: 45_000)), "Ronda 1 en 45 segundos")
        XCTAssertEqual(say(.roundDone(round: 2, splitMs: 120_000)), "Ronda 2 en 2 minutos")
        XCTAssertEqual(say(.roundDone(round: 12, splitMs: 61_000)), "Ronda 12 en un minuto y un segundo")
        XCTAssertEqual(say(.averaging(roundMs: 80_000)), "De media, un minuto y 20 segundos por ronda")
    }

    /// the clock marks
    func testTheClockMarks() {
        func clock(_ mark: ClockMark, _ rounds: Int, _ reps: Int, _ projected: Int?) -> String {
            say(.clock(mark: mark, rounds: rounds, totalReps: reps, projectedRounds: projected))
        }

        XCTAssertEqual(clock(.fiveMinutesIn, 6, 185, 24), "Cinco minutos. Llevas 6 rondas. Ritmo para 24 rondas.")
        XCTAssertEqual(clock(.halfway, 0, 0, nil), "A mitad de camino. Mantén tu ritmo.")
        XCTAssertEqual(clock(.fiveMinutesLeft, 1, 30, 1), "Quedan cinco minutos. Llevas una ronda. Ritmo para una ronda.")
        XCTAssertEqual(clock(.twoMinutesLeft, 6, 185, 12),
                       "Dos minutos. 6 rondas, 185 repeticiones en total. Mantén el ritmo.")
        XCTAssertEqual(clock(.twoMinutesLeft, 0, 12, nil), "Dos minutos. 12 repeticiones. Sigue así.")
        XCTAssertEqual(clock(.oneMinuteLeft, 11, 340, 11),
                       "Queda un minuto. Llevas 11 rondas. Termina la que estás haciendo.")
        XCTAssertEqual(clock(.tenSecondsLeft, 6, 185, 12), "Diez segundos. Todo lo que tengas.")
    }

    /// recording
    func testRecording() {
        XCTAssertEqual(say(.recordingSoon(seconds: 3)), "Grabando en 3 segundos")
        XCTAssertEqual(say(.recordingSoon(seconds: 1)), "Grabando en un segundo")
        XCTAssertEqual(say(.recordingStarted), "Grabando")
        XCTAssertEqual(say(.recordingFailed), "Falló la grabación")
    }

    /// a hint is translated and an unknown one falls back to something Spanish
    func testAHintIsTranslatedAndAnUnknownOneFallsBackToSomethingSpanish() {
        XCTAssertEqual(say(.fault(hint: "Get on the bar")), "Agárrate a la barra")
        XCTAssertEqual(say(.fault(hint: "Something nobody catalogued")), "Revisa tu posición")
    }
}
