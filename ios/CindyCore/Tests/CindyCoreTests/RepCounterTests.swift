import XCTest
import CindyCore
import CindyFixtures

/// Carried over from the `CindyCoreChecks` executable: RepCounter. Every check keeps its original wording as
/// its assertion message.
final class RepCounterTests: XCTestCase {

    private func hold(_ c: RepCounter, _ v: Float, from t: Int64, frames: Int = 10) -> Int {
        var reps = 0
        for i in 0..<frames where c.update(v, now: t + Int64(i) * 100) { reps += 1 }
        return reps
    }

    func testFullTravelScoresOneRep() {
        let c = RepCounter(downBelow: 100, upAbove: 150)
        _ = hold(c, 80, from: 0)
        XCTAssertEqual(hold(c, 170, from: 1000), 1, "full travel scores one rep")
    }

    func testJitterInsideTheDeadZoneNeverScores() {
        let c = RepCounter(downBelow: 100, upAbove: 150)
        _ = hold(c, 80, from: 0)
        var t: Int64 = 1000
        for v: Float in [110, 140, 120, 145, 105, 149] { _ = hold(c, v, from: t); t += 1000 }
        XCTAssertEqual(c.count, 0, "jitter inside the dead zone never scores")
    }

    func testTenCleanCyclesScoreTen() {
        let c = RepCounter(downBelow: 100, upAbove: 150)
        var t: Int64 = 0
        for _ in 0..<10 {
            _ = hold(c, 80, from: t); t += 1000
            _ = hold(c, 170, from: t); t += 1000
        }
        XCTAssertEqual(c.count, 10, "ten clean cycles score ten")
    }

    func testRepsFasterThanTheDebounceAreRejected() {
        let c = RepCounter(downBelow: 100, upAbove: 150, minRepMs: 5000, smoothing: 1)
        _ = c.update(80, now: 0)
        _ = c.update(170, now: 100)
        _ = c.update(80, now: 200)
        _ = c.update(170, now: 300)
        XCTAssertEqual(c.count, 1, "reps faster than the debounce are rejected")
    }

    func testNaNSamplesAreIgnored() {
        let c = RepCounter(downBelow: 100, upAbove: 150)
        _ = hold(c, 80, from: 0)
        XCTAssertEqual(c.update(.nan, now: 1000), false, "NaN samples are ignored")
        _ = hold(c, 170, from: 2000)
        XCTAssertEqual(c.count, 1, "and do not break the smoother")
    }

    func testMinusTakesARepBack() {
        let c = RepCounter(downBelow: 100, upAbove: 150)
        c.forceIncrement(); c.forceIncrement(); c.forceDecrement()
        XCTAssertEqual(c.count, 1, "minus takes a rep back")
        c.forceDecrement(); c.forceDecrement()
        XCTAssertEqual(c.count, 0, "minus stops at zero")
    }

    func testTheBandCalibratesFromAFullRep() {
        let c = RepCounter(downBelow: 100, upAbove: 150, minRange: 40)
        _ = hold(c, 80, from: 0)
        _ = hold(c, 170, from: 1000)
        XCTAssertEqual(c.calibrated, true, "the band calibrates from a full rep")
        c.resetBand()
        XCTAssertEqual(c.count, 1, "recalibration keeps the score")
        XCTAssertEqual(c.calibrated, false, "recalibration forgets the band")
    }
}
