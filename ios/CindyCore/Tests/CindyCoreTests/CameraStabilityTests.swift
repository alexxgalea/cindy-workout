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

    // The monitor is only as good as the angles it is fed. These build the rotation matrix a phone
    // propped up to film would report, and read the camera's direction from it the way the app does.

    private func times(_ a: [Double], _ b: [Double]) -> [Double] { RotationRig.times(a, b) }

    private func turn(_ x: Double, _ y: Double, _ z: Double, _ degrees: Double) -> [Double] {
        RotationRig.turn(x, y, z, degrees)
    }

    private func propped(_ tiltBack: Double) -> [Double] { RotationRig.propped(tiltBack) }

    private func matrix(_ m: [Double]) -> [Float] { m.map { Float($0) } }
    private func heading(_ m: [Double]) -> Float { CameraLook.heading(matrix(m)) }
    private func elevation(_ m: [Double]) -> Float { CameraLook.elevation(matrix(m)) }

    /// What `SensorManager.getOrientation` reported before: the bearing of the top edge.
    private func azimuth(_ m: [Double]) -> Float { Float(atan2(m[1], m[4]) * 57.29577951308232) }

    private func apart(_ a: Float, _ b: Float) -> Float {
        var d = (a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return abs(d)
    }

    private func feed(_ m: [Double], _ ms: Int64, stepMs: Int64 = 50) {
        let until = clock + ms
        while clock < until {
            monitor.update(yaw: heading(m), pitch: elevation(m), now: clock)
            clock += stepMs
        }
    }

    private let tremor: [(Double, Double, Double)] = [
        (1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 1, 0), (1, 0, 1), (0, 1, 1), (1, 1, 1), (1, -1, 0),
        (1, 0, -1), (0, 1, -1),
    ]

    /// a tremor barely moves where the camera points though it sends the compass round
    func testATremorBarelyMovesWhereTheCameraPointsThoughItSendsTheCompassRound() {
        let at = propped(5)
        var compass: Float = 0
        for (x, y, z) in tremor {
            let shaken = times(turn(x, y, z, 1.5), at)
            XCTAssertTrue(apart(heading(shaken), heading(at)) < 2,
                          "heading moved \(apart(heading(shaken), heading(at)))")
            XCTAssertTrue(apart(elevation(shaken), elevation(at)) < 2,
                          "elevation moved \(apart(elevation(shaken), elevation(at)))")
            compass = max(compass, apart(azimuth(shaken), azimuth(at)))
        }
        // The reading this replaces: the same one and a half degrees, through the top edge of a
        // phone that is nearly vertical, is well past the eight degrees that count as a move.
        XCTAssertTrue(compass > 8, "azimuth moved only \(compass)")
    }

    /// turning the phone is the same angle in the camera heading
    func testTurningThePhoneIsTheSameAngleInTheCameraHeading() {
        let at = propped(5)
        let panned = times(turn(0, 0, 1, 12), at)
        XCTAssertEqual(12, apart(heading(panned), heading(at)), accuracy: 0.01)
    }

    /// tilting the phone up is its elevation
    func testTiltingThePhoneUpIsItsElevation() {
        let at = propped(5)
        let tipped = times(turn(1, 0, 0, 10), at)
        XCTAssertEqual(5, elevation(at), accuracy: 0.01)
        XCTAssertEqual(15, elevation(tipped), accuracy: 0.01)
    }

    /// the monitor stays quiet through a tremor and reports a real turn
    func testTheMonitorStaysQuietThroughATremorAndReportsARealTurn() {
        let at = propped(5)
        feed(at, 2_000)
        for i in 0..<20 {
            let (x, y, z) = tremor[i % tremor.count]
            feed(times(turn(x, y, z, 1.5), at), 100)
        }
        feed(at, 2_000)
        XCTAssertFalse(monitor.moving)
        XCTAssertFalse(monitor.consumeReframed())

        feed(times(turn(0, 0, 1, 15), at), 3_000)
        XCTAssertTrue(monitor.consumeReframed())
    }
}
