import XCTest
import CindyCore

/// Mirrors `HeartRateTracesTest.kt`.
final class HeartRateTracesTests: XCTestCase {

    /// round trips a trace with pauses
    func testRoundTripsATraceWithPauses() {
        let trace = HeartRateTrace(
            startedAtMillis: 1_700_000_000_000,
            samples: [HeartRateSample(0, 88), HeartRateSample(1000, 140)],
            pauses: [HeartRatePause(atClockMs: 500, lengthMs: 30_000)])
        XCTAssertEqual(HeartRateTraces.decode(HeartRateTraces.encode(trace)), trace)
    }

    /// round trips a trace with no pauses
    func testRoundTripsATraceWithNoPauses() {
        let trace = HeartRateTrace(startedAtMillis: 1000, samples: [HeartRateSample(0, 100)], pauses: [])
        XCTAssertEqual(HeartRateTraces.decode(HeartRateTraces.encode(trace)), trace)
    }

    /// round trips a trace with neither samples nor pauses
    func testRoundTripsATraceWithNeitherSamplesNorPauses() {
        let trace = HeartRateTrace(startedAtMillis: 5, samples: [], pauses: [])
        XCTAssertEqual(HeartRateTraces.decode(HeartRateTraces.encode(trace)), trace)
    }

    /// a malformed line is skipped, not fatal
    func testAMalformedLineIsSkippedNotFatal() {
        let raw = "hr1|1000\n0,88\ngarbage\np|broken\n1000,140"
        let trace = HeartRateTraces.decode(raw)!
        XCTAssertEqual(trace.startedAtMillis, 1000)
        XCTAssertEqual(trace.samples, [HeartRateSample(0, 88), HeartRateSample(1000, 140)])
        XCTAssertEqual(trace.pauses, [])
    }

    /// a missing or unknown header yields null
    func testAMissingOrUnknownHeaderYieldsNull() {
        XCTAssertNil(HeartRateTraces.decode(nil))
        XCTAssertNil(HeartRateTraces.decode(""))
        XCTAssertNil(HeartRateTraces.decode("   "))
        XCTAssertNil(HeartRateTraces.decode("garbage"))
        XCTAssertNil(HeartRateTraces.decode("hr2|1000\n0,88"))
    }

    // MARK: written for the port

    /// a line with more fields than the format has is skipped
    func testALineWithMoreFieldsThanTheFormatHasIsSkipped() {
        let trace = HeartRateTraces.decode("hr1|1000\np|1|2|3\n5,6,7\n10,90\np|4|5")!
        XCTAssertEqual(trace.samples, [HeartRateSample(10, 90)])
        XCTAssertEqual(trace.pauses, [HeartRatePause(atClockMs: 4, lengthMs: 5)])
        XCTAssertNil(HeartRateTraces.decode("hr1|1000|extra\n0,88"))
    }

    /// pauses are written in order, ahead of the samples
    func testPausesAreWrittenInOrderAheadOfTheSamples() {
        let trace = HeartRateTrace(startedAtMillis: 7, samples: [HeartRateSample(1, 90), HeartRateSample(2, 91)],
                                   pauses: [HeartRatePause(atClockMs: 5, lengthMs: 6), HeartRatePause(atClockMs: 8, lengthMs: 9)])
        XCTAssertEqual(HeartRateTraces.encode(trace), "hr1|7\np|5|6\np|8|9\n1,90\n2,91")
    }
}
