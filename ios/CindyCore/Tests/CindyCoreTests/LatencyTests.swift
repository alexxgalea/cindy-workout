import XCTest
@testable import CindyCore

/// The instrument, and its refusals.
///
/// This readout exists to be photographed off a phone and believed, so the thing most worth
/// testing is that it declines to print a number it cannot stand behind — a plausible-looking
/// latency from the wrong clock would be worse than a blank.
///
/// Mirrors `LatencyTest.kt`.
final class LatencyTests: XCTestCase {

    /// capture age is withheld until the camera says which clock it is on
    func testCaptureAgeIsWithheldUntilTheCameraSaysWhichClockItIsOn() {
        let clock = FrameLatency()
        XCTAssertFalse(clock.resolved, "nothing has told it yet")
        XCTAssertNil(clock.sinceCapture(0), "an unresolved domain must not produce a number")
        XCTAssertNil(clock.sinceCapture(monotonicNanos()))
    }

    /// the median ignores a single outlier
    func testTheMedianIgnoresASingleOutlier() {
        let r = Rolling(30)
        for _ in 0..<10 { r.add(20) }
        r.add(4_000)
        XCTAssertEqual(r.median(), 20)
    }

    /// the window forgets
    func testTheWindowForgets() {
        let r = Rolling(4)
        for v: Int64 in [100, 100, 100, 100, 7, 7, 7, 7] { r.add(v) }
        XCTAssertEqual(r.median(), 7, "only the last four remain")
    }

    /// an empty window has no median rather than a zero
    func testAnEmptyWindowHasNoMedianRatherThanAZero() {
        let r = Rolling(4)
        XCTAssertNil(r.median())
        r.add(5)
        r.reset()
        XCTAssertNil(r.median())
    }

    /// the rate meter counts over its window
    func testTheRateMeterCountsOverItsWindow() {
        let m = RateMeter(windowMs: 1_000)
        // Ten marks 100ms apart spans 900ms and nine intervals: ten per second.
        for i in 0...9 { m.mark(nowMs: Int64(i) * 100) }
        XCTAssertEqual(m.perSecond(nowMs: 900)!, 10, accuracy: 0.2)
    }

    /// one mark is not a rate
    func testOneMarkIsNotARate() {
        let m = RateMeter()
        XCTAssertNil(m.perSecond(nowMs: 0))
        m.mark(nowMs: 0)
        XCTAssertNil(m.perSecond(nowMs: 0), "a rate needs two events to have an interval")
    }

    /// the readout says the clock is unavailable rather than printing a figure
    func testTheReadoutSaysTheClockIsUnavailableRatherThanPrintingAFigure() {
        let probe = LatencyProbe()
        probe.analysed(captureAgeMs: nil, convertMs: 12, prepMs: 20, inferMs: 130)
        let line = probe.line(model: "thndr", drawnPerSecond: 60)
        XCTAssertTrue(line.contains("n/a (clock)"), "should name the clock as the reason, was: \(line)")
        XCTAssertTrue(line.contains("inf 130"), "the stages it can measure still show, was: \(line)")
    }

    /// the coalesced share is what the old post-per-frame design would have queued
    func testTheCoalescedShareIsWhatTheOldPostPerFrameDesignWouldHaveQueued() {
        let probe = LatencyProbe()
        // Four frames analysed, three of them superseded before the main thread got to them.
        probe.posted(replacedUnrendered: false)
        for _ in 0..<3 { probe.posted(replacedUnrendered: true) }
        let line = probe.line(model: "thndr", drawnPerSecond: 60)
        XCTAssertTrue(line.contains("75% coalesced"), "expected 75% coalesced, was: \(line)")
    }

    /// the readout is two lines, because the band holds one each
    func testTheReadoutIsTwoLinesBecauseTheBandHoldsOneEach() {
        let probe = LatencyProbe()
        probe.analysed(captureAgeMs: 210, convertMs: 12, prepMs: 20, inferMs: 130)
        let line = probe.line(model: "thndr", drawnPerSecond: 58)
        XCTAssertEqual(line.filter { $0 == "\n" }.count, 1, "exactly one break")
        XCTAssertTrue(line.hasPrefix("age 210ms"), "age leads the first line, was: \(line)")
        XCTAssertTrue(line.contains("\nthndr"), "the model names the second, was: \(line)")
    }

    // MARK: - what Swift does for itself that the Android build got from the platform

    /// a resolved clock reports the age of a frame, and refuses an impossible one
    func testAResolvedClockReportsTheAgeOfAFrameAndRefusesAnImpossibleOne() {
        var now: Int64 = 10_000_000_000
        let clock = FrameLatency(now: { now })
        clock.resolve()
        XCTAssertTrue(clock.resolved)
        XCTAssertEqual(clock.sinceCapture(now - 210_000_000), 210)
        XCTAssertNil(clock.sinceCapture(now + 1_000_000), "captured in the future")
        XCTAssertNil(clock.sinceCapture(now - 5_001_000_000), "older than any frame could be")
        XCTAssertEqual(clock.sinceCapture(now - 5_000_000_000), 5_000)
        now += 50_000_000
        XCTAssertEqual(clock.sinceCapture(now - 210_000_000), 210)
    }

    /// the readout rounds as Java does, half up
    func testTheReadoutRoundsAsJavaDoesHalfUp() {
        XCTAssertEqual(javaFixed(58.5, 0), "59", "C would say 58")
        XCTAssertEqual(javaFixed(0.5, 0), "1")
        XCTAssertEqual(javaFixed(30.25, 1), "30.3", "C would say 30.2")
        XCTAssertEqual(javaFixed(9.96, 1), "10.0", "a carry into the whole part")
        XCTAssertEqual(javaFixed(9.99, 0), "10")
        XCTAssertEqual(javaFixed(0, 1), "0.0")
        XCTAssertEqual(javaFixed(-0.04, 1), "-0.0")
    }

    /// a drawn rate with a half in it prints as the Android build prints it
    func testADrawnRateWithAHalfInItPrintsAsTheAndroidBuildPrintsIt() {
        let probe = LatencyProbe()
        probe.analysed(captureAgeMs: nil, convertMs: 1, prepMs: 1, inferMs: 1)
        XCTAssertTrue(probe.line(model: "m", drawnPerSecond: 58.5).contains("59 drawn"))
    }
}
