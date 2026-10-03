import XCTest
import CindyCore

/// The Turkish lines: no plural to get wrong, so what is pinned is the shape of each sentence.
///
/// Mirrors `PhrasebookTrTest.kt`.
final class PhrasebookTrTests: XCTestCase {

    private func say(_ line: VoiceLine) -> String { PhrasebookTr().say(line) }

    private func clock(_ mark: ClockMark, _ rounds: Int, _ reps: Int, _ projected: Int?) -> String {
        say(.clock(mark: mark, rounds: rounds, totalReps: reps, projectedRounds: projected))
    }

    /// movements
    func testMovements() {
        XCTAssertEqual(say(.movement(.pullup)), "barfiks")
        XCTAssertEqual(say(.movement(.pushup)), "şınav")
        XCTAssertEqual(say(.movement(.squat)), "squat")
    }

    /// a noun stays singular after a numeral
    func testANounStaysSingularAfterANumeral() {
        XCTAssertEqual(say(.score(rounds: 1, totalReps: 30)), "1 tur, toplam 30 tekrar")
        XCTAssertEqual(say(.score(rounds: 6, totalReps: 185)), "6 tur, toplam 185 tekrar")
        XCTAssertEqual(say(.score(rounds: 0, totalReps: 12)), "12 tekrar")
    }

    /// durations
    func testDurations() {
        XCTAssertEqual(say(.roundDone(round: 3, splitMs: 80_000)), "Tur 3, süre 1 dakika 20 saniye")
        XCTAssertEqual(say(.roundDone(round: 1, splitMs: 45_000)), "Tur 1, süre 45 saniye")
        XCTAssertEqual(say(.roundDone(round: 2, splitMs: 120_000)), "Tur 2, süre 2 dakika")
        XCTAssertEqual(say(.averaging(roundMs: 80_000)), "Tur başına ortalama 1 dakika 20 saniye")
    }

    /// the benchmark keeps the name as it is
    func testTheBenchmarkKeepsTheNameAsItIs() {
        // The possessive lands on "skor", so no suffix has to attach to the athlete's name.
        XCTAssertEqual(say(.beatBenchmark(name: "Tom Holland")), "Tom Holland skorunu geçtin")
    }

    /// the clock marks
    func testTheClockMarks() {
        XCTAssertEqual(clock(.fiveMinutesIn, 6, 185, 24), "Beş dakika geçti. 6 tur tamamlandı. Bu tempoyla 24 tur.")
        XCTAssertEqual(clock(.halfway, 0, 0, nil), "Yarı yol. Tempoyu koru.")
        XCTAssertEqual(clock(.twoMinutesLeft, 6, 185, 12), "İki dakika. 6 tur, toplam 185 tekrar. Tempoyu koru.")
        XCTAssertEqual(clock(.twoMinutesLeft, 0, 12, nil), "İki dakika. 12 tekrar. Devam et.")
        XCTAssertEqual(clock(.oneMinuteLeft, 11, 340, 11), "Bir dakika kaldı. 11 tur tamamlandı. Başladığın turu bitir.")
        XCTAssertEqual(clock(.fiveMinutesLeft, 0, 0, nil), "Beş dakika kaldı. Tempoyu koru.")
        XCTAssertEqual(clock(.tenSecondsLeft, 6, 185, 12), "On saniye. Bütün gücünle.")
    }

    /// recording
    func testRecording() {
        XCTAssertEqual(say(.recordingSoon(seconds: 3)), "Kayıt 3 saniye sonra başlıyor")
        XCTAssertEqual(say(.recordingStarted), "Kayıt başladı")
        XCTAssertEqual(say(.recordingFailed), "Kayıt başarısız")
    }

    /// a hint is translated and an unknown one falls back to something Turkish
    func testAHintIsTranslatedAndAnUnknownOneFallsBackToSomethingTurkish() {
        XCTAssertEqual(say(.fault(hint: "Get on the bar")), "Çubuğu tut")
        // The bar is the çubuk; "barfiks" is the exercise, and hanging "on the pull-up" is not a thing.
        XCTAssertEqual(say(.fault(hint: "Hang from the bar")), "Çubuğa asıl")
        XCTAssertEqual(say(.fault(hint: "Something nobody catalogued")), "Pozisyonunu kontrol et")
    }
}
