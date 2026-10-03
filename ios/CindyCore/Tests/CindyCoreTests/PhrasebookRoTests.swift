import XCTest
import CindyCore

/// The Romanian lines where the grammar has something to get wrong: "few" up to 19, "de" from 20,
/// and written-out 1 and 2.
///
/// Mirrors `PhrasebookRoTest.kt`.
final class PhrasebookRoTests: XCTestCase {

    private func say(_ line: VoiceLine) -> String { PhrasebookRo().say(line) }

    private func clock(_ mark: ClockMark, _ rounds: Int, _ reps: Int, _ projected: Int?) -> String {
        say(.clock(mark: mark, rounds: rounds, totalReps: reps, projectedRounds: projected))
    }

    /// movements
    func testMovements() {
        XCTAssertEqual(say(.movement(.pullup)), "tracțiuni")
        XCTAssertEqual(say(.movement(.pushup)), "flotări")
        XCTAssertEqual(say(.movement(.squat)), "genuflexiuni")
    }

    /// counts take de from twenty
    func testCountsTakeDeFromTwenty() {
        XCTAssertEqual(say(.score(rounds: 1, totalReps: 30)), "O rundă, 30 de repetări în total")
        XCTAssertEqual(say(.score(rounds: 2, totalReps: 60)), "Două runde, 60 de repetări în total")
        XCTAssertEqual(say(.score(rounds: 6, totalReps: 185)), "6 runde, 185 de repetări în total")
        XCTAssertEqual(say(.score(rounds: 19, totalReps: 570)), "19 runde, 570 de repetări în total")
        XCTAssertEqual(say(.score(rounds: 20, totalReps: 600)), "20 de runde, 600 de repetări în total")
        // 101 to 119 are "few" again, and 3030 is "other" because of its last two digits.
        XCTAssertEqual(say(.score(rounds: 101, totalReps: 3030)), "101 runde, 3030 de repetări în total")
    }

    /// repetitions before a round is in
    func testRepetitionsBeforeARoundIsIn() {
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 1)), "O repetare")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 12)), "12 repetări")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 20)), "20 de repetări")
        // Nought is "few" in Romanian, unlike English, French or Portuguese.
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 0)), "0 repetări")
    }

    /// durations
    func testDurations() {
        XCTAssertEqual(say(.roundDone(round: 3, splitMs: 80_000)), "Runda 3, timp de un minut și 20 de secunde")
        XCTAssertEqual(say(.roundDone(round: 1, splitMs: 45_000)), "Runda 1, timp de 45 de secunde")
        XCTAssertEqual(say(.roundDone(round: 2, splitMs: 120_000)), "Runda 2, timp de două minute")
        XCTAssertEqual(say(.roundDone(round: 5, splitMs: 65_000)), "Runda 5, timp de un minut și 5 secunde")
        XCTAssertEqual(say(.roundDone(round: 6, splitMs: 300_000)), "Runda 6, timp de 5 minute")
        XCTAssertEqual(say(.averaging(roundMs: 80_000)), "În medie un minut și 20 de secunde pe rundă")
    }

    /// the clock marks
    func testTheClockMarks() {
        XCTAssertEqual(clock(.fiveMinutesIn, 6, 185, 24), "Cinci minute. Ai 6 runde. Ritm pentru 24 de runde.")
        XCTAssertEqual(clock(.halfway, 0, 0, nil), "La jumătate. Ține-ți ritmul.")
        XCTAssertEqual(clock(.fiveMinutesLeft, 1, 30, 1), "Mai sunt cinci minute. Ai o rundă. Ritm pentru o rundă.")
        XCTAssertEqual(clock(.twoMinutesLeft, 6, 185, 12),
                       "Două minute. 6 runde, 185 de repetări în total. Ține ritmul.")
        XCTAssertEqual(clock(.twoMinutesLeft, 0, 12, nil), "Două minute. 12 repetări. Continuă.")
        XCTAssertEqual(clock(.oneMinuteLeft, 20, 600, 20), "Mai e un minut. Ai 20 de runde. Termină runda în curs.")
        XCTAssertEqual(clock(.tenSecondsLeft, 6, 185, 12), "Zece secunde. Dă tot ce ai.")
    }

    /// recording contracts a single second
    func testRecordingContractsASingleSecond() {
        XCTAssertEqual(say(.recordingSoon(seconds: 3)), "Înregistrare în 3 secunde")
        XCTAssertEqual(say(.recordingSoon(seconds: 1)), "Înregistrare într-o secundă")
        XCTAssertEqual(say(.recordingSoon(seconds: 20)), "Înregistrare în 20 de secunde")
        XCTAssertEqual(say(.recordingStarted), "Se înregistrează")
        XCTAssertEqual(say(.recordingFailed), "Înregistrarea a eșuat")
    }

    /// the benchmark is a comparison, with no pronoun to agree with the name
    func testTheBenchmarkIsAComparisonWithNoPronounToAgreeWithTheName() {
        // "L-ai depășit pe" would fit a man and be wrong for a woman; the name travels as data.
        XCTAssertEqual(say(.beatBenchmark(name: "Tom Holland")), "Scor mai bun decât Tom Holland")
    }

    /// a hint is translated and an unknown one falls back to something Romanian
    func testAHintIsTranslatedAndAnUnknownOneFallsBackToSomethingRomanian() {
        XCTAssertEqual(say(.fault(hint: "Get on the bar")), "Prinde bara")
        XCTAssertEqual(say(.fault(hint: "Something nobody catalogued")), "Verifică-ți poziția")
    }
}
