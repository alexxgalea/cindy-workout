import XCTest
import CindyCore

/// Mirrors `RecordsTest.kt`: the attempt, its score, and the line format it is saved in.
final class RecordsTests: XCTestCase {

    private func attempt(_ rounds: Int, _ reps: Int = 0, _ at: Int64 = 0) -> Attempt {
        Attempt(rounds: rounds, reps: reps, atMillis: at)
    }

    /// Kotlin's `copy(...)`.
    private func copy(_ a: Attempt, _ change: (inout Attempt) -> Void) -> Attempt {
        var b = a
        change(&b)
        return b
    }

    /// total reps counts thirty per round
    func testTotalRepsCountsThirtyPerRound() {
        XCTAssertEqual(attempt(1).totalReps, 30)
        XCTAssertEqual(attempt(27, 12).totalReps, 822)
    }

    /// score reads the way an AMRAP is written
    func testScoreReadsTheWayAnAMRAPIsWritten() {
        XCTAssertEqual(attempt(27).scoreLabel, "27")
        XCTAssertEqual(attempt(12, 7).scoreLabel, "12 + 7")
    }

    /// the benchmark is Tom Holland at twenty-seven rounds
    func testTheBenchmarkIsTomHollandAtTwentySevenRounds() {
        XCTAssertEqual(Records.benchmarkName, "Tom Holland")
        XCTAssertEqual(Records.benchmark.rounds, 27)
        XCTAssertEqual(Records.benchmark.totalReps, 810)
    }

    /// beating the benchmark needs more than twenty-seven clean rounds
    func testBeatingTheBenchmarkNeedsMoreThanTwentySevenCleanRounds() {
        XCTAssertFalse(Records.beatsBenchmark(attempt(27)))
        XCTAssertTrue(Records.beatsBenchmark(attempt(27, 1)))
        XCTAssertTrue(Records.beatsBenchmark(attempt(28)))
        XCTAssertFalse(Records.beatsBenchmark(attempt(26, 29)))
    }

    /// encode and decode round-trip
    func testEncodeAndDecodeRoundTrip() {
        let list = [attempt(12, 7, 1000), attempt(14, 0, 2000)]
        XCTAssertEqual(Records.decode(Records.encode(list)), list)
    }

    /// splits and duration survive the round-trip
    func testSplitsAndDurationSurviveTheRoundTrip() {
        let list = [
            Attempt(rounds: 3, reps: 12, atMillis: 1000, durationMs: 1_200_000, pausedMs: 45_000,
                    roundSplitsMs: [60_000, 71_000, 68_000]),
            Attempt(rounds: 1, reps: 0, atMillis: 2000, durationMs: 90_000, pausedMs: 0,
                    roundSplitsMs: [90_000])
        ]
        XCTAssertEqual(Records.decode(Records.encode(list)), list)
    }

    /// an attempt with no complete rounds round-trips
    func testAnAttemptWithNoCompleteRoundsRoundTrips() {
        let a = Attempt(rounds: 0, reps: 9, atMillis: 5, durationMs: 300_000, pausedMs: 0,
                        roundSplitsMs: [])
        XCTAssertEqual(Records.decode(Records.encode([a])), [a])
    }

    /// attempts saved before splits existed still load
    func testAttemptsSavedBeforeSplitsExistedStillLoad() {
        let decoded = Records.decode("12,7,1000\n14,0,2000")
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].rounds, 12)
        XCTAssertEqual(decoded[0].roundSplitsMs, [])
        XCTAssertEqual(decoded[0].durationMs, 0)
    }

    /// old and new records coexist in one file
    func testOldAndNewRecordsCoexistInOneFile() {
        let mixed = "12,7,1000\n" + Records.encode([
            Attempt(rounds: 9, reps: 0, atMillis: 3000, durationMs: 600_000, pausedMs: 0,
                    roundSplitsMs: [300_000])
        ])
        let decoded = Records.decode(mixed)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].rounds, 12)
        XCTAssertEqual(decoded[1].roundSplitsMs, [300_000])
    }

    /// average round prefers the splits over dividing the clock
    func testAverageRoundPrefersTheSplitsOverDividingTheClock() {
        let a = Attempt(rounds: 2, reps: 5, atMillis: 0, durationMs: 1_200_000, pausedMs: 0,
                        roundSplitsMs: [100_000, 140_000])
        XCTAssertEqual(a.avgRoundMs, 120_000)
        XCTAssertEqual(a.fastestRoundMs, 100_000)
        XCTAssertEqual(a.slowestRoundMs, 140_000)
    }

    /// average round falls back to the clock when splits are missing
    func testAverageRoundFallsBackToTheClockWhenSplitsAreMissing() {
        XCTAssertEqual(Attempt(rounds: 4, reps: 0, atMillis: 0, durationMs: 1_200_000).avgRoundMs, 300_000)
        XCTAssertNil(Attempt(rounds: 0, reps: 5, atMillis: 0, durationMs: 600_000).avgRoundMs)
        XCTAssertNil(Attempt(rounds: 3, reps: 0, atMillis: 0, durationMs: 0).avgRoundMs)
    }

    /// real time counts the pauses that the workout clock does not
    func testRealTimeCountsThePausesThatTheWorkoutClockDoesNot() {
        let a = Attempt(rounds: 5, reps: 0, atMillis: 0, durationMs: 1_200_000, pausedMs: 180_000)
        XCTAssertEqual(a.durationMs, 1_200_000)
        XCTAssertEqual(a.realTimeMs, 1_380_000)
        // Splits are clock time, so a pause must not inflate the average.
        XCTAssertEqual(a.avgRoundMs, 240_000)
    }

    /// an unpaused attempt has real time equal to clock time
    func testAnUnpausedAttemptHasRealTimeEqualToClockTime() {
        let a = Attempt(rounds: 3, reps: 0, atMillis: 0, durationMs: 900_000)
        XCTAssertEqual(a.durationMs, a.realTimeMs)
    }

    /// durations read as minutes and seconds
    func testDurationsReadAsMinutesAndSeconds() {
        XCTAssertEqual(formatDuration(0), "0:00")
        XCTAssertEqual(formatDuration(65_000), "1:05")
        XCTAssertEqual(formatDuration(20 * 60 * 1000), "20:00")
    }

    /// an attempt carries its level
    func testAnAttemptCarriesItsLevel() {
        XCTAssertEqual(attempt(12).level, .intermediate)
        XCTAssertEqual(attempt(27).level, .legend)
    }

    /// decoding junk yields nothing rather than crashing
    func testDecodingJunkYieldsNothingRatherThanCrashing() {
        XCTAssertEqual(Records.decode(nil), [])
        XCTAssertEqual(Records.decode(""), [])
        XCTAssertEqual(Records.decode("garbage"), [])
        XCTAssertEqual(Records.decode("1,2"), [])
        XCTAssertEqual(Records.decode("a,b,c"), [])
    }

    /// a corrupt line does not discard the good ones
    func testACorruptLineDoesNotDiscardTheGoodOnes() {
        let decoded = Records.decode("12,7,1000\nbroken\n14,0,2000")
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].rounds, 12)
    }

    /// ranking puts the highest total first
    func testRankingPutsTheHighestTotalFirst() {
        let ranked = Records.ranked([attempt(10), attempt(15), attempt(12, 20)])
        XCTAssertEqual(ranked[0].rounds, 15)
        XCTAssertEqual(ranked[1].rounds, 12)
        XCTAssertEqual(ranked[2].rounds, 10)
    }

    /// equal scores rank the more recent attempt first
    func testEqualScoresRankTheMoreRecentAttemptFirst() {
        let ranked = Records.ranked([attempt(10, 0, 100), attempt(10, 0, 500)])
        XCTAssertEqual(ranked[0].atMillis, 500)
    }

    /// best of nothing is nothing
    func testBestOfNothingIsNothing() {
        XCTAssertNil(Records.best([]))
    }

    // MARK: - a score the camera could not stand behind

    /// time the camera was blind survives a round trip
    func testTimeTheCameraWasBlindSurvivesARoundTrip() {
        let a = copy(attempt(12, 7)) { $0.untrackedMs = 91_000; $0.countedReps = 367 }
        let back = Records.decode(Records.encode([a]))[0]
        XCTAssertEqual(back.untrackedMs, 91_000)
        XCTAssertEqual(back.countedReps, 367)
    }

    /// an attempt recorded before this was measured reads as nothing known missing
    func testAnAttemptRecordedBeforeThisWasMeasuredReadsAsNothingKnownMissing() {
        // A v5 line, which is what the previous build wrote. Zero is the right reading: nothing
        // was known to be missed, which is not the same claim as nothing was missed.
        let v5 = "v5|12|7|100|1000|0||STRICT_PULL_UP|STANDARD_PUSH_UP|AIR_SQUAT|0|367"
        let back = Records.decode(v5)[0]
        XCTAssertEqual(back.untrackedMs, 0)
        XCTAssertFalse(back.scoreIsLowerBound)
        XCTAssertEqual(back.countedReps, 367)
    }

    /// a few seconds of lost tracking does not tarnish a score
    func testAFewSecondsOfLostTrackingDoesNotTarnishAScore() {
        XCTAssertFalse(copy(attempt(20)) { $0.untrackedMs = 12_000 }.scoreIsLowerBound)
    }

    /// half a minute of blind camera makes the score a floor
    func testHalfAMinuteOfBlindCameraMakesTheScoreAFloor() {
        XCTAssertTrue(copy(attempt(20)) { $0.untrackedMs = 30_000 }.scoreIsLowerBound)
    }

    /// a score the camera could not stand behind is not a personal record
    func testAScoreTheCameraCouldNotStandBehindIsNotAPersonalRecord() {
        let history = [attempt(10, 0, 100)]
        let degraded = copy(attempt(20, 0, 500)) { $0.untrackedMs = 120_000 }
        // Twice the previous best, and still not a record: the number itself is not trustworthy.
        XCTAssertGreaterThan(degraded.totalReps, history[0].totalReps)
        XCTAssertFalse(Records.isPersonalRecord(history + [degraded], of: degraded))
    }

    /// a clean score still sets a personal record
    func testACleanScoreStillSetsAPersonalRecord() {
        let history = [attempt(10, 0, 100)]
        let clean = attempt(20, 0, 500)
        XCTAssertTrue(Records.isPersonalRecord(history + [clean], of: clean))
    }

    /// a degraded session cannot claim the benchmark
    func testADegradedSessionCannotClaimTheBenchmark() {
        let big = Attempt(rounds: 30, reps: 0, atMillis: 0, untrackedMs: 60_000)
        XCTAssertGreaterThan(big.totalReps, Records.benchmark.totalReps)
        XCTAssertFalse(Records.beatsBenchmark(big))
        XCTAssertTrue(Records.beatsBenchmark(copy(big) { $0.untrackedMs = 0 }))
    }

    /// a degraded session is still kept and still ranked
    func testADegradedSessionIsStillKeptAndStillRanked() {
        // The athlete did at least this much, so withholding it would be its own dishonesty.
        let degraded = copy(attempt(20, 0, 500)) { $0.untrackedMs = 120_000 }
        let all = [attempt(10, 0, 100), degraded]
        XCTAssertEqual(Records.best(all)?.rounds, 20)
        XCTAssertEqual(Records.ranked(all).count, 2)
    }

    // MARK: - set splits (record format v7)

    /// set splits survive the round-trip
    func testSetSplitsSurviveTheRoundTrip() {
        let a = copy(attempt(12, 7)) {
            $0.countedReps = 367
            $0.setSplits = [
                SetSplit(.pullup, 14_000, 5, 0),
                SetSplit(.pushup, 17_000, 8, 3),
                SetSplit(.squat, 20_000, 15, 0)
            ]
        }
        XCTAssertEqual(Records.decode(Records.encode([a])), [a])
    }

    /// encode writes the v7 format
    func testEncodeWritesTheV7Format() {
        XCTAssertTrue(Records.encode([attempt(12, 7)]).hasPrefix("v7|"))
    }

    /// a v6 line still loads, with no sets
    func testAV6LineStillLoadsWithNoSets() {
        let v6 = "v6|12|7|100|1000|0||STRICT_PULL_UP|STANDARD_PUSH_UP|AIR_SQUAT|0|367|0"
        let back = Records.decode(v6)[0]
        XCTAssertEqual(back.rounds, 12)
        XCTAssertEqual(back.countedReps, 367)
        XCTAssertEqual(back.setSplits, [])
    }

    /// an unknown movement in a v7 line drops only that set
    func testAnUnknownMovementInAV7LineDropsOnlyThatSet() {
        let sets = "PULLUP:14000:5:0,HANDSTAND:1:1:0,SQUAT:20000:15:0"
        let v7 = "v7|12|7|100|1000|0||STRICT_PULL_UP|STANDARD_PUSH_UP|AIR_SQUAT|0|367|0|\(sets)"
        let back = Records.decode(v7)[0]
        XCTAssertEqual(back.rounds, 12)
        XCTAssertEqual(back.setSplits, [
            SetSplit(.pullup, 14_000, 5, 0),
            SetSplit(.squat, 20_000, 15, 0)
        ])
    }
}
