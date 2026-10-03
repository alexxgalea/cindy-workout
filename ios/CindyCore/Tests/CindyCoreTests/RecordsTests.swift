import XCTest
import CindyCore
import CindyFixtures

/// Carried over from the `CindyCoreChecks` executable: Records. Every check keeps its original wording as
/// its assertion message.
final class RecordsTests: XCTestCase {

    func testRecords() {
        XCTAssertEqual(Attempt(rounds: 27, reps: 0, atMillis: 0).scoreLabel, "27", "score reads as rounds")
        XCTAssertEqual(Attempt(rounds: 12, reps: 7, atMillis: 0).scoreLabel, "12 + 7", "and rounds plus reps")
        XCTAssertEqual(Records.benchmarkName, "Tom Holland", "the benchmark is Tom Holland")
        XCTAssertEqual(Records.benchmark.totalReps, 810, "at 27 rounds")

        let list = [
            Attempt(rounds: 3, reps: 12, atMillis: 1000, durationMs: 1_200_000,
                    pausedMs: 45_000, roundSplitsMs: [60_000, 71_000, 68_000]),
            Attempt(rounds: 1, reps: 0, atMillis: 2000, durationMs: 90_000,
                    pausedMs: 0, roundSplitsMs: [90_000])
        ]
        XCTAssertEqual(Records.decode(Records.encode(list)), list, "splits and pauses round-trip")

        let legacy = Records.decode("12,7,1000\n14,0,2000")
        XCTAssertEqual(legacy.count, 2, "records saved before splits existed still load")
        XCTAssertEqual(legacy[0].roundSplitsMs, [], "with no splits")

        XCTAssertEqual(Records.decode(nil).count, 0, "nil decodes to nothing")
        XCTAssertEqual(Records.decode("garbage").count, 0, "junk decodes to nothing")

        let paused = Attempt(rounds: 5, reps: 0, atMillis: 0,
                             durationMs: 1_200_000, pausedMs: 180_000)
        XCTAssertEqual(paused.realTimeMs, 1_380_000, "real time counts the pauses")
        XCTAssertEqual(paused.avgRoundMs, 240_000, "the average round does not")

        XCTAssertEqual(Records.ranked([
            Attempt(rounds: 10, reps: 0, atMillis: 0),
            Attempt(rounds: 15, reps: 0, atMillis: 0)
        ])[0].rounds, 15, "ranking puts the highest first")

        XCTAssertEqual(formatDuration(65_000), "1:05", "durations read as minutes and seconds")
        XCTAssertEqual(formatDuration(20 * 60 * 1000), "20:00", "including twenty minutes")
    }
}
