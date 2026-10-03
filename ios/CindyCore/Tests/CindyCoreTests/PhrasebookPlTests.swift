import XCTest
import CindyCore

/// The Polish lines where the grammar has something to get wrong: the one/few/many forms at the
/// counts where they change (1, 2, 5, 12, 22), written-out 1 and 2, and the accusatives.
///
/// Mirrors `PhrasebookPlTest.kt`.
final class PhrasebookPlTests: XCTestCase {

    private func say(_ line: VoiceLine) -> String { PhrasebookPl().say(line) }

    private func clock(_ mark: ClockMark, _ rounds: Int, _ reps: Int, _ projected: Int?) -> String {
        say(.clock(mark: mark, rounds: rounds, totalReps: reps, projectedRounds: projected))
    }

    /// movements
    func testMovements() {
        XCTAssertEqual(say(.movement(.pullup)), "podciągnięcia")
        XCTAssertEqual(say(.movement(.pushup)), "pompki")
        XCTAssertEqual(say(.movement(.squat)), "przysiady")
    }

    /// rounds take the form their count asks for
    func testRoundsTakeTheFormTheirCountAsksFor() {
        XCTAssertEqual(say(.score(rounds: 1, totalReps: 30)), "Jedna runda, łącznie 30 powtórzeń")
        XCTAssertEqual(say(.score(rounds: 2, totalReps: 60)), "Dwie rundy, łącznie 60 powtórzeń")
        XCTAssertEqual(say(.score(rounds: 3, totalReps: 90)), "3 rundy, łącznie 90 powtórzeń")
        XCTAssertEqual(say(.score(rounds: 5, totalReps: 150)), "5 rund, łącznie 150 powtórzeń")
        XCTAssertEqual(say(.score(rounds: 12, totalReps: 360)), "12 rund, łącznie 360 powtórzeń")
        XCTAssertEqual(say(.score(rounds: 22, totalReps: 660)), "22 rundy, łącznie 660 powtórzeń")
    }

    /// repetitions are neuter and follow the same counts
    func testRepetitionsAreNeuterAndFollowTheSameCounts() {
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 1)), "Jedno powtórzenie")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 2)), "2 powtórzenia")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 5)), "5 powtórzeń")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 12)), "12 powtórzeń")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 22)), "22 powtórzenia")
    }

    /// durations
    func testDurations() {
        XCTAssertEqual(say(.roundDone(round: 3, splitMs: 80_000)), "Runda 3, czas jedna minuta i 20 sekund")
        XCTAssertEqual(say(.roundDone(round: 2, splitMs: 125_000)), "Runda 2, czas dwie minuty i 5 sekund")
        XCTAssertEqual(say(.roundDone(round: 1, splitMs: 45_000)), "Runda 1, czas 45 sekund")
        XCTAssertEqual(say(.roundDone(round: 4, splitMs: 180_000)), "Runda 4, czas 3 minuty")
        XCTAssertEqual(say(.roundDone(round: 5, splitMs: 300_000)), "Runda 5, czas 5 minut")
        XCTAssertEqual(say(.averaging(roundMs: 80_000)), "Średnio jedna minuta i 20 sekund na rundę")
    }

    /// the clock marks
    func testTheClockMarks() {
        XCTAssertEqual(clock(.fiveMinutesIn, 6, 185, 24), "Pięć minut za nami. Ukończone rundy: 6, tempo na 24 rundy.")
        XCTAssertEqual(clock(.halfway, 6, 185, 12), "Połowa czasu. Ukończone rundy: 6, tempo na 12 rund.")
        XCTAssertEqual(clock(.halfway, 0, 0, nil), "Połowa czasu. Utrzymaj swoje tempo.")
        // A single round is accusative after "na".
        XCTAssertEqual(clock(.fiveMinutesLeft, 1, 30, 1),
                       "Zostało pięć minut. Ukończone rundy: 1, tempo na jedną rundę.")
        XCTAssertEqual(clock(.twoMinutesLeft, 6, 185, 12),
                       "Dwie minuty. 6 rund, łącznie 185 powtórzeń. Utrzymaj tempo.")
        XCTAssertEqual(clock(.twoMinutesLeft, 0, 12, nil), "Dwie minuty. 12 powtórzeń. Dalej.")
        XCTAssertEqual(clock(.oneMinuteLeft, 11, 340, 11), "Została minuta. Ukończone rundy: 11, dokończ bieżącą.")
        XCTAssertEqual(clock(.tenSecondsLeft, 6, 185, 12), "Dziesięć sekund. Daj z siebie wszystko.")
    }

    /// recording puts the seconds in the accusative
    func testRecordingPutsTheSecondsInTheAccusative() {
        XCTAssertEqual(say(.recordingSoon(seconds: 3)), "Nagrywanie za 3 sekundy")
        XCTAssertEqual(say(.recordingSoon(seconds: 1)), "Nagrywanie za jedną sekundę")
        XCTAssertEqual(say(.recordingSoon(seconds: 2)), "Nagrywanie za dwie sekundy")
        XCTAssertEqual(say(.recordingSoon(seconds: 5)), "Nagrywanie za 5 sekund")
        XCTAssertEqual(say(.recordingStarted), "Nagrywanie rozpoczęte")
        XCTAssertEqual(say(.recordingFailed), "Nagrywanie nie powiodło się")
    }

    /// the benchmark is a comparison with no case to get wrong
    func testTheBenchmarkIsAComparisonWithNoCaseToGetWrong() {
        XCTAssertEqual(say(.beatBenchmark(name: "Tom Holland")), "Wynik lepszy niż Tom Holland")
    }

    /// a hint is translated and an unknown one falls back to something Polish
    func testAHintIsTranslatedAndAnUnknownOneFallsBackToSomethingPolish() {
        XCTAssertEqual(say(.fault(hint: "Get on the bar")), "Chwyć drążek")
        XCTAssertEqual(say(.fault(hint: "Something nobody catalogued")), "Sprawdź swoją pozycję")
    }
}
