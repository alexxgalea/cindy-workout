import XCTest
import CindyCore

/// The bar zone is stored in frame pixels, so the question this answers is not "did the phone move"
/// for its own sake but "is the calibration still describing the picture".
///
/// Mirrors `CameraStabilityTest.kt`.
final class CameraStabilityTests: XCTestCase {

    private let monitor = CameraStabilityMonitor()
    private var clock: Int64 = 0

    private func hold(_ ms: Int64, yaw: Float, pitch: Float = 0, stepMs: Int64 = 50) {
        let until = clock + ms
        while clock < until {
            monitor.update(yaw: yaw, pitch: pitch, now: clock)
            clock += stepMs
        }
    }

    /// a phone standing still never asks for a recalibration
    func testAPhoneStandingStillNeverAsksForARecalibration() {
        hold(10_000, yaw: 90)
        XCTAssertFalse(monitor.moving)
        XCTAssertFalse(monitor.consumeReframed())
    }

    /// the wobble of a propped phone is not a camera move
    func testTheWobbleOfAProppedPhoneIsNotACameraMove() {
        hold(2_000, yaw: 90)
        // Someone lands a burpee next to the box.
        hold(500, yaw: 93)
        hold(2_000, yaw: 90)
        XCTAssertFalse(monitor.moving)
        XCTAssertFalse(monitor.consumeReframed())
    }

    /// a knock is noticed straight away and reported once it settles
    func testAKnockIsNoticedStraightAwayAndReportedOnceItSettles() {
        hold(2_000, yaw: 90)
        hold(200, yaw: 115)
        XCTAssertTrue(monitor.moving, "a 25 degree knock should register")
        // Still mid-move, so nothing is recalibrated against a framing that is still changing.
        XCTAssertFalse(monitor.consumeReframed())

        hold(2_000, yaw: 115)
        XCTAssertFalse(monitor.moving)
        XCTAssertTrue(monitor.consumeReframed())
    }

    /// one bump recalibrates once
    func testOneBumpRecalibratesOnce() {
        hold(2_000, yaw: 90)
        hold(200, yaw: 115)
        hold(2_000, yaw: 115)
        XCTAssertTrue(monitor.consumeReframed())
        XCTAssertFalse(monitor.consumeReframed(), "a second read must not recalibrate again")
        hold(5_000, yaw: 115)
        XCTAssertFalse(monitor.consumeReframed())
    }

    /// being carried does not settle until it is put down
    func testBeingCarriedDoesNotSettleUntilItIsPutDown() {
        hold(2_000, yaw: 90)
        // Swept through a wide arc a few degrees at a time; each step is under the threshold on its
        // own but the anchor follows, so what is measured is whether it has stopped.
        var yaw: Float = 90
        for _ in 0..<20 {
            yaw += 10
            hold(200, yaw: yaw)
        }
        XCTAssertTrue(monitor.moving)
        XCTAssertFalse(monitor.consumeReframed())
        hold(2_000, yaw: yaw)
        XCTAssertTrue(monitor.consumeReframed())
    }

    /// pitch is watched as well as yaw
    func testPitchIsWatchedAsWellAsYaw() {
        hold(2_000, yaw: 90, pitch: 10)
        hold(200, yaw: 90, pitch: 30)
        XCTAssertTrue(monitor.moving)
    }

    /// the compass wrapping past north is not a twenty degree turn
    func testTheCompassWrappingPastNorthIsNotATwentyDegreeTurn() {
        hold(2_000, yaw: 359)
        hold(2_000, yaw: 2)
        XCTAssertFalse(monitor.moving, "359 and 2 are three degrees apart")
    }
}
