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
}
