import XCTest
import CindyCore

/// The Russian lines where the grammar has something to get wrong: the one/few/many forms at the
/// counts where they change (1, 2, 5, 11, 21, 22), written-out 1 and 2, and the accusative.
///
/// Mirrors `PhrasebookRuTest.kt`.
final class PhrasebookRuTests: XCTestCase {

    private func say(_ line: VoiceLine) -> String { PhrasebookRu().say(line) }

    private func clock(_ mark: ClockMark, _ rounds: Int, _ reps: Int, _ projected: Int?) -> String {
        say(.clock(mark: mark, rounds: rounds, totalReps: reps, projectedRounds: projected))
    }

    /// movements
    func testMovements() {
        XCTAssertEqual(say(.movement(.pullup)), "подтягивания")
        XCTAssertEqual(say(.movement(.pushup)), "отжимания")
        XCTAssertEqual(say(.movement(.squat)), "приседания")
    }

    /// rounds take the form their count asks for
    func testRoundsTakeTheFormTheirCountAsksFor() {
        XCTAssertEqual(say(.score(rounds: 1, totalReps: 30)), "1 раунд, всего 30 повторений")
        XCTAssertEqual(say(.score(rounds: 2, totalReps: 60)), "2 раунда, всего 60 повторений")
        XCTAssertEqual(say(.score(rounds: 5, totalReps: 150)), "5 раундов, всего 150 повторений")
        // Eleven is not "one" and twenty-one is: the last two digits decide.
        XCTAssertEqual(say(.score(rounds: 11, totalReps: 330)), "11 раундов, всего 330 повторений")
        XCTAssertEqual(say(.score(rounds: 21, totalReps: 630)), "21 раунд, всего 630 повторений")
        XCTAssertEqual(say(.score(rounds: 22, totalReps: 660)), "22 раунда, всего 660 повторений")
    }

    /// repetitions are neuter and follow the same counts
    func testRepetitionsAreNeuterAndFollowTheSameCounts() {
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 1)), "Одно повторение")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 2)), "2 повторения")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 5)), "5 повторений")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 11)), "11 повторений")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 21)), "21 повторение")
    }

    /// durations
    func testDurations() {
        XCTAssertEqual(say(.roundDone(round: 3, splitMs: 80_000)), "Раунд 3, время одна минута и 20 секунд")
        XCTAssertEqual(say(.roundDone(round: 2, splitMs: 125_000)), "Раунд 2, время две минуты и 5 секунд")
        XCTAssertEqual(say(.roundDone(round: 1, splitMs: 45_000)), "Раунд 1, время 45 секунд")
        XCTAssertEqual(say(.roundDone(round: 4, splitMs: 180_000)), "Раунд 4, время 3 минуты")
        XCTAssertEqual(say(.roundDone(round: 5, splitMs: 300_000)), "Раунд 5, время 5 минут")
        XCTAssertEqual(say(.roundDone(round: 6, splitMs: 21_000)), "Раунд 6, время 21 секунда")
        XCTAssertEqual(say(.averaging(roundMs: 80_000)), "В среднем одна минута и 20 секунд на раунд")
    }

    /// the benchmark is a comparison in the present tense
    func testTheBenchmarkIsAComparisonInThePresentTense() {
        // No "побил" or "побила": the sentence is true whoever is listening.
        XCTAssertEqual(say(.beatBenchmark(name: "Tom Holland")), "Результат лучше, чем у Tom Holland")
    }

    /// the clock marks
    func testTheClockMarks() {
        XCTAssertEqual(clock(.fiveMinutesIn, 6, 185, 24), "Прошло пять минут. Раундов: 6, темп на 24 раунда.")
        XCTAssertEqual(clock(.halfway, 6, 185, 12), "Половина времени. Раундов: 6, темп на 12 раундов.")
        XCTAssertEqual(clock(.halfway, 0, 0, nil), "Половина времени. Держи свой темп.")
        XCTAssertEqual(clock(.fiveMinutesLeft, 1, 30, 1), "Осталось пять минут. Раундов: 1, темп на 1 раунд.")
        XCTAssertEqual(clock(.twoMinutesLeft, 6, 185, 12),
                       "Две минуты. 6 раундов, всего 185 повторений. Держи темп.")
        XCTAssertEqual(clock(.twoMinutesLeft, 0, 12, nil), "Две минуты. 12 повторений. Продолжай.")
        XCTAssertEqual(clock(.oneMinuteLeft, 11, 340, 11), "Осталась минута. Раундов: 11, закончи текущий.")
        XCTAssertEqual(clock(.tenSecondsLeft, 6, 185, 12), "Десять секунд. Выложись полностью.")
    }

    /// recording puts the seconds in the accusative
    func testRecordingPutsTheSecondsInTheAccusative() {
        XCTAssertEqual(say(.recordingSoon(seconds: 1)), "Запись через одну секунду")
        XCTAssertEqual(say(.recordingSoon(seconds: 2)), "Запись через две секунды")
        XCTAssertEqual(say(.recordingSoon(seconds: 3)), "Запись через 3 секунды")
        XCTAssertEqual(say(.recordingSoon(seconds: 5)), "Запись через 5 секунд")
        XCTAssertEqual(say(.recordingSoon(seconds: 21)), "Запись через 21 секунду")
        XCTAssertEqual(say(.recordingStarted), "Идёт запись")
        XCTAssertEqual(say(.recordingFailed), "Запись не удалась")
    }

    /// a hint is translated and an unknown one falls back to something Russian
    func testAHintIsTranslatedAndAnUnknownOneFallsBackToSomethingRussian() {
        XCTAssertEqual(say(.fault(hint: "Get on the bar")), "Возьмись за перекладину")
        XCTAssertEqual(say(.fault(hint: "Something nobody catalogued")), "Проверь своё положение")
    }
}
