import XCTest
import CindyCore

/// Mirrors `HeartRateRecorderTest.kt`.
final class HeartRateRecorderTests: XCTestCase {

    /// nothing is recorded before start
    func testNothingIsRecordedBeforeStart() {
        let rec = HeartRateRecorder()
        rec.offer(bpm: 100, atElapsedMs: 0)
        rec.offer(bpm: 105, atElapsedMs: 500)
        // Long enough after the last offer that starting will not seed from it either: this
        // isolates "not started yet" from the separate seeding behaviour.
        rec.start(atElapsedMs: 10_000, wallMillis: 0)
        XCTAssertNil(rec.finish(atElapsedMs: 10_000))
    }

    /// stamps are on the workout clock, not wall time
    func testStampsAreOnTheWorkoutClockNotWallTime() {
        let rec = HeartRateRecorder()
        rec.start(atElapsedMs: 50_000, wallMillis: 9_000_000)
        rec.offer(bpm: 120, atElapsedMs: 51_000) // clock 1000
        rec.offer(bpm: 130, atElapsedMs: 53_500) // clock 3500, well past the min spacing
        let trace = rec.finish(atElapsedMs: 54_000)!
        XCTAssertEqual(trace.startedAtMillis, 9_000_000)
        XCTAssertEqual(trace.samples, [HeartRateSample(1000, 120), HeartRateSample(3500, 130)])
    }

    /// a thirty second pause drops its readings, keeps the clock continuous, and is listed
    func testAThirtySecondPauseDropsItsReadingsKeepsTheClockContinuousAndIsListed() {
        let rec = HeartRateRecorder()
        rec.start(atElapsedMs: 0, wallMillis: 0)
        rec.offer(bpm: 140, atElapsedMs: 1_000) // clock 1000, recorded
        rec.pause(atElapsedMs: 2_000) // clock 2000
        rec.offer(bpm: 999, atElapsedMs: 2_500) // during the pause: dropped, only remembered
        rec.resume(atElapsedMs: 32_000) // 30 s later: far too stale to seed from the 2_500 reading
        rec.offer(bpm: 150, atElapsedMs: 33_000) // clock 2000 + (33000 - 32000) = 3000
        let trace = rec.finish(atElapsedMs: 33_000)!

        XCTAssertEqual(trace.pauses, [HeartRatePause(atClockMs: 2000, lengthMs: 30_000)])
        XCTAssertFalse(trace.samples.contains { $0.bpm == 999 }, "the paused-time reading must not appear")
        XCTAssertEqual(trace.samples.map { $0.clockMs }, [1000, 3000])
    }

    /// a reading 2 s old when start is called seeds the trace at clock zero
    func testAReading2SOldWhenStartIsCalledSeedsTheTraceAtClockZero() {
        let rec = HeartRateRecorder()
        rec.offer(bpm: 88, atElapsedMs: 1_000)
        rec.start(atElapsedMs: 3_000, wallMillis: 0) // 2 s old
        let trace = rec.finish(atElapsedMs: 3_000)!
        XCTAssertEqual(trace.samples, [HeartRateSample(0, 88)])
    }

    /// a reading 6 s old when start is called does not seed
    func testAReading6SOldWhenStartIsCalledDoesNotSeed() {
        let rec = HeartRateRecorder()
        rec.offer(bpm: 88, atElapsedMs: 1_000)
        rec.start(atElapsedMs: 7_000, wallMillis: 0) // 6 s old
        XCTAssertNil(rec.finish(atElapsedMs: 7_000))
    }

    /// a fresh reading seeds the trace again on resume
    func testAFreshReadingSeedsTheTraceAgainOnResume() {
        let rec = HeartRateRecorder()
        rec.start(atElapsedMs: 0, wallMillis: 0)
        rec.pause(atElapsedMs: 1_000) // clock 1000
        rec.offer(bpm: 140, atElapsedMs: 5_500) // during the pause, 500 ms before resume
        rec.resume(atElapsedMs: 6_000)
        let trace = rec.finish(atElapsedMs: 6_000)!
        XCTAssertEqual(trace.samples, [HeartRateSample(1000, 140)])
    }

    /// finish while paused closes the pause first
    func testFinishWhilePausedClosesThePauseFirst() {
        let rec = HeartRateRecorder()
        rec.start(atElapsedMs: 0, wallMillis: 0)
        rec.offer(bpm: 120, atElapsedMs: 500) // clock 500, recorded
        rec.pause(atElapsedMs: 1_000) // clock 1000
        let trace = rec.finish(atElapsedMs: 4_000)!
        XCTAssertEqual(trace.pauses, [HeartRatePause(atClockMs: 1000, lengthMs: 3_000)])
    }

    /// 4 Hz input is capped near 1 Hz
    func testFourHzInputIsCappedNearOneHz() {
        let rec = HeartRateRecorder()
        rec.start(atElapsedMs: 0, wallMillis: 0)
        var t: Int64 = 0
        for _ in 0..<80 { // 20 s of data at 250 ms intervals
            rec.offer(bpm: 140, atElapsedMs: t)
            t += 250
        }
        let trace = rec.finish(atElapsedMs: t)!
        XCTAssertTrue(trace.samples.count > 1, "expected more than one sample")
        for (a, b) in zip(trace.samples, trace.samples.dropFirst()) {
            XCTAssertTrue(b.clockMs - a.clockMs >= HeartRateRecorder.minSpacingMs,
                          "\(b.clockMs - a.clockMs)ms apart, below the minimum spacing")
        }
        let elapsedS = Double(trace.samples[trace.samples.count - 1].clockMs - trace.samples[0].clockMs) / 1000.0
        let hz = Double(trace.samples.count - 1) / elapsedS
        XCTAssertTrue(hz <= 1.2, "rate was \(hz)Hz")
    }

    /// finish with no samples yields null
    func testFinishWithNoSamplesYieldsNull() {
        let rec = HeartRateRecorder()
        rec.start(atElapsedMs: 0, wallMillis: 0)
        XCTAssertNil(rec.finish(atElapsedMs: 1_000))
    }

    /// reset clears everything, including the remembered reading
    func testResetClearsEverythingIncludingTheRememberedReading() {
        let rec = HeartRateRecorder()
        rec.offer(bpm: 100, atElapsedMs: 0)
        rec.reset()
        // If the remembered reading had survived, this would be well within maxHoldMs and seed.
        rec.start(atElapsedMs: 2_000, wallMillis: 0)
        XCTAssertNil(rec.finish(atElapsedMs: 2_000))
    }

    // MARK: written for the port: edges the Kotlin tests do not reach, found by mutating the source

    /// a reading exactly five seconds old still seeds, and one a millisecond older does not
    func testAReadingExactlyFiveSecondsOldStillSeedsAndOneMillisecondOlderDoesNot() {
        let at = HeartRateRecorder()
        at.offer(bpm: 88, atElapsedMs: 1_000)
        at.start(atElapsedMs: 6_000, wallMillis: 0)
        XCTAssertEqual(at.finish(atElapsedMs: 6_000)?.samples, [HeartRateSample(0, 88)])

        let past = HeartRateRecorder()
        past.offer(bpm: 88, atElapsedMs: 1_000)
        past.start(atElapsedMs: 6_001, wallMillis: 0)
        XCTAssertNil(past.finish(atElapsedMs: 6_001))
    }

    /// two readings exactly 900 ms apart are both kept, and 899 ms apart only the first
    func testTwoReadingsExactlyNineHundredMsApartAreBothKept() {
        let kept = HeartRateRecorder()
        kept.start(atElapsedMs: 0, wallMillis: 0)
        kept.offer(bpm: 100, atElapsedMs: 0)
        kept.offer(bpm: 110, atElapsedMs: 900)
        XCTAssertEqual(kept.finish(atElapsedMs: 900)?.samples.map { $0.clockMs }, [0, 900])

        let dropped = HeartRateRecorder()
        dropped.start(atElapsedMs: 0, wallMillis: 0)
        dropped.offer(bpm: 100, atElapsedMs: 0)
        dropped.offer(bpm: 110, atElapsedMs: 899)
        XCTAssertEqual(dropped.finish(atElapsedMs: 899)?.samples.map { $0.clockMs }, [0])
    }

    /// the clock never runs backward, even when a late callback hands in an earlier time
    func testTheClockNeverRunsBackwardEvenWhenALateCallbackHandsInAnEarlierTime() {
        let rec = HeartRateRecorder()
        rec.start(atElapsedMs: 0, wallMillis: 0)
        rec.offer(bpm: 120, atElapsedMs: 3_000) // clock 3000
        rec.pause(atElapsedMs: 2_000) // a stale time: the clock was already at 3000
        rec.resume(atElapsedMs: 5_000)
        let trace = rec.finish(atElapsedMs: 5_000)!
        XCTAssertEqual(trace.pauses, [HeartRatePause(atClockMs: 3_000, lengthMs: 3_000)])
    }

    /// pause and resume do nothing out of turn
    func testPauseAndResumeDoNothingOutOfTurn() {
        let idle = HeartRateRecorder()
        idle.pause(atElapsedMs: 1_000)   // nothing is running yet
        idle.resume(atElapsedMs: 2_000)  // and nothing is paused
        idle.start(atElapsedMs: 3_000, wallMillis: 0)
        idle.offer(bpm: 100, atElapsedMs: 4_000)
        let trace = idle.finish(atElapsedMs: 4_000)!
        XCTAssertEqual(trace.pauses, [])
        XCTAssertEqual(trace.samples, [HeartRateSample(1_000, 100)])

        let twice = HeartRateRecorder()
        twice.start(atElapsedMs: 0, wallMillis: 0)
        twice.offer(bpm: 100, atElapsedMs: 100)
        twice.pause(atElapsedMs: 1_000)
        twice.pause(atElapsedMs: 2_000)  // already paused: the first stands
        twice.resume(atElapsedMs: 5_000)
        twice.resume(atElapsedMs: 6_000) // already running
        XCTAssertEqual(twice.finish(atElapsedMs: 6_000)?.pauses, [HeartRatePause(atClockMs: 1_000, lengthMs: 4_000)])
    }

    /// nothing is recorded once the trace is finished
    func testNothingIsRecordedOnceTheTraceIsFinished() {
        let rec = HeartRateRecorder()
        rec.start(atElapsedMs: 0, wallMillis: 0)
        rec.offer(bpm: 100, atElapsedMs: 1_000)
        XCTAssertNotNil(rec.finish(atElapsedMs: 2_000))
        rec.offer(bpm: 200, atElapsedMs: 3_000)
        XCTAssertEqual(rec.finish(atElapsedMs: 4_000)?.samples, [HeartRateSample(1_000, 100)])
    }

    /// a second trace starts its clock again
    func testASecondTraceStartsItsClockAgain() {
        let rec = HeartRateRecorder()
        rec.start(atElapsedMs: 0, wallMillis: 0)
        rec.offer(bpm: 100, atElapsedMs: 10_000)
        XCTAssertNotNil(rec.finish(atElapsedMs: 10_000))
        rec.start(atElapsedMs: 100_000, wallMillis: 5)
        rec.offer(bpm: 110, atElapsedMs: 101_000)
        let second = rec.finish(atElapsedMs: 101_000)!
        XCTAssertEqual(second.startedAtMillis, 5)
        XCTAssertEqual(second.samples.last, HeartRateSample(1_000, 110))
    }
}
