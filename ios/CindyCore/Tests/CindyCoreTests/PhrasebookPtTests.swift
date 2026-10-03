import XCTest
import CindyCore

/// The Portuguese lines where the grammar has something to get wrong: 1, 2, nought, and the clock.
///
/// Mirrors `PhrasebookPtTest.kt`.
final class PhrasebookPtTests: XCTestCase {

    private func say(_ line: VoiceLine) -> String { PhrasebookPt().say(line) }

    private func clock(_ mark: ClockMark, _ rounds: Int, _ reps: Int, _ projected: Int?) -> String {
        say(.clock(mark: mark, rounds: rounds, totalReps: reps, projectedRounds: projected))
    }

    /// movements
    func testMovements() {
        XCTAssertEqual(say(.movement(.pullup)), "barras")
        XCTAssertEqual(say(.movement(.pushup)), "flexões")
        XCTAssertEqual(say(.movement(.squat)), "agachamentos")
    }

    /// one and two are written out for the feminine nouns
    func testOneAndTwoAreWrittenOutForTheFeminineNouns() {
        XCTAssertEqual(say(.score(rounds: 1, totalReps: 30)), "Uma rodada, 30 repetições no total")
        XCTAssertEqual(say(.score(rounds: 2, totalReps: 60)), "Duas rodadas, 60 repetições no total")
        XCTAssertEqual(say(.score(rounds: 6, totalReps: 185)), "6 rodadas, 185 repetições no total")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 1)), "Uma repetição")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 2)), "Duas repetições")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 12)), "12 repetições")
    }

    /// nought is singular
    func testNoughtIsSingular() {
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 0)), "0 repetição")
    }

    /// durations
    func testDurations() {
        XCTAssertEqual(say(.roundDone(round: 3, splitMs: 80_000)), "Rodada 3 em um minuto e 20 segundos")
        XCTAssertEqual(say(.roundDone(round: 1, splitMs: 45_000)), "Rodada 1 em 45 segundos")
        XCTAssertEqual(say(.roundDone(round: 2, splitMs: 120_000)), "Rodada 2 em 2 minutos")
        XCTAssertEqual(say(.roundDone(round: 12, splitMs: 61_000)), "Rodada 12 em um minuto e um segundo")
        XCTAssertEqual(say(.averaging(roundMs: 80_000)), "Média de um minuto e 20 segundos por rodada")
    }

    /// the clock marks
    func testTheClockMarks() {
        XCTAssertEqual(clock(.fiveMinutesIn, 6, 185, 24),
                       "Cinco minutos. Você tem 6 rodadas. Ritmo para 24 rodadas.")
        XCTAssertEqual(clock(.halfway, 0, 0, nil), "Metade do tempo. Mantenha o seu ritmo.")
        XCTAssertEqual(clock(.fiveMinutesLeft, 2, 60, 1),
                       "Faltam cinco minutos. Você tem duas rodadas. Ritmo para uma rodada.")
        XCTAssertEqual(clock(.twoMinutesLeft, 6, 185, 12),
                       "Dois minutos. 6 rodadas, 185 repetições no total. Mantenha o ritmo.")
        XCTAssertEqual(clock(.twoMinutesLeft, 0, 12, nil), "Dois minutos. 12 repetições. Continue.")
        XCTAssertEqual(clock(.oneMinuteLeft, 11, 340, 11),
                       "Falta um minuto. Você tem 11 rodadas. Termine a que está fazendo.")
        XCTAssertEqual(clock(.tenSecondsLeft, 6, 185, 12), "Dez segundos. Dê tudo o que tem.")
    }

    /// recording
    func testRecording() {
        XCTAssertEqual(say(.recordingSoon(seconds: 3)), "Gravando em 3 segundos")
        XCTAssertEqual(say(.recordingSoon(seconds: 1)), "Gravando em um segundo")
        XCTAssertEqual(say(.recordingStarted), "Gravando")
        XCTAssertEqual(say(.recordingFailed), "Falha na gravação")
    }

    /// a hint is translated and an unknown one falls back to something Portuguese
    func testAHintIsTranslatedAndAnUnknownOneFallsBackToSomethingPortuguese() {
        XCTAssertEqual(say(.fault(hint: "Get on the bar")), "Segure a barra")
        XCTAssertEqual(say(.fault(hint: "Something nobody catalogued")), "Confira a sua posição")
    }
}
