import XCTest
import CindyCore

/// Turning Core Motion's rotation matrix into the angles the phone-moved monitor reads.
///
/// Written for the port: Android reads `SensorManager`'s matrix directly. Every pose here is a matrix
/// in Android's layout, from `RotationRig`; what Core Motion would report for it is the same nine
/// numbers transposed, with gravity in the device's axes alongside, so these tests hold that the
/// adapter finds its way back whichever way round the matrix arrives, and that it agrees with gravity
/// on where the camera points.
final class CameraMotionTests: XCTestCase {

    private func floats(_ m: [Double]) -> [Float] { m.map { Float($0) } }

    private func transposed(_ a: [Float]) -> [Float] { [a[0], a[3], a[6], a[1], a[4], a[7], a[2], a[5], a[8]] }

    /// Gravity in the device's axes for a matrix in Android's layout: the world's "up" is its third
    /// row, and gravity is minus that.
    private func gravity(_ a: [Float]) -> CameraMotion.Gravity { (-a[6], -a[7], -a[8]) }

    /// A phone leaning back by five degrees, then turned, tipped, or both.
    private var poses: [[Float]] {
        let at = RotationRig.propped(5)
        let panned = RotationRig.times(RotationRig.turn(0, 0, 1, 12), at)
        let tipped = RotationRig.times(RotationRig.turn(1, 0, 0, 10), at)
        let both = RotationRig.times(RotationRig.turn(0, 0, 1, -35), RotationRig.times(RotationRig.turn(1, 0, 0, -20), at))
        return [at, panned, tipped, both].map(floats)
    }

    /// the poses can tell the two layouts apart
    func testThePosesCanTellTheTwoLayoutsApart() {
        // A pose symmetric about its diagonal reads the same either way, and would prove nothing.
        for pose in poses.dropFirst() {
            XCTAssertNotEqual(pose, transposed(pose))
        }
    }

    /// Core Motion's matrix, the transpose of Android's, comes back as Android's
    func testCoreMotionsMatrixTheTransposeOfAndroidsComesBackAsAndroids() {
        for android in poses {
            XCTAssertEqual(CameraMotion.androidLayout(rowMajor: transposed(android), gravity: gravity(android)), android)
        }
    }

    /// a matrix that already is in Android's layout is left alone
    func testAMatrixThatAlreadyIsInAndroidsLayoutIsLeftAlone() {
        // If Core Motion turns out to write it this way round, gravity says so and nothing is flipped.
        for android in poses {
            XCTAssertEqual(CameraMotion.androidLayout(rowMajor: android, gravity: gravity(android)), android)
        }
    }

    /// the camera's elevation from the matrix agrees with the one from gravity
    func testTheCamerasElevationFromTheMatrixAgreesWithTheOneFromGravity() {
        for android in poses {
            let look = CameraMotion.look(rowMajor: transposed(android), gravity: gravity(android))
            XCTAssertEqual(look.elevation, look.gravityElevation, accuracy: 0.01)
        }
        XCTAssertEqual(CameraMotion.look(rowMajor: transposed(poses[0]), gravity: gravity(poses[0])).elevation,
                       5, accuracy: 0.01)
        XCTAssertEqual(CameraMotion.look(rowMajor: transposed(poses[2]), gravity: gravity(poses[2])).elevation,
                       15, accuracy: 0.01)
    }

    /// turning the phone is the same angle in the heading
    func testTurningThePhoneIsTheSameAngleInTheHeading() {
        let before = CameraMotion.look(rowMajor: transposed(poses[0]), gravity: gravity(poses[0]))
        let after = CameraMotion.look(rowMajor: transposed(poses[1]), gravity: gravity(poses[1]))
        XCTAssertEqual(abs(after.heading - before.heading), 12, accuracy: 0.01)
    }

    /// gravity alone says how far up the back camera looks
    func testGravityAloneSaysHowFarUpTheBackCameraLooks() {
        XCTAssertEqual(CameraMotion.elevation(gravity: (0, -1, 0)), 0, accuracy: 0.001, "standing upright")
        XCTAssertEqual(CameraMotion.elevation(gravity: (0, 0, -1)), -90, accuracy: 0.001, "face up, looking at the floor")
        XCTAssertEqual(CameraMotion.elevation(gravity: (0, 0, 1)), 90, accuracy: 0.001, "face down, looking at the ceiling")
        let lean = Float(5 * 0.017453292519943295)
        XCTAssertEqual(CameraMotion.elevation(gravity: (0, -cos(lean), sin(lean))), 5, accuracy: 0.001)
        XCTAssertEqual(CameraMotion.elevation(gravity: (0, 0, 1.0000001)), 90, accuracy: 0.001, "rounding past 1 is clamped")
    }

    /// the monitor stays quiet through a tremor and reports a real turn, fed from Core Motion's matrix
    func testTheMonitorStaysQuietThroughATremorAndReportsARealTurnFedFromCoreMotionsMatrix() {
        let monitor = CameraStabilityMonitor()
        var clock: Int64 = 0
        func feed(_ android: [Double], _ ms: Int64) {
            let a = floats(android)
            let until = clock + ms
            while clock < until {
                let look = CameraMotion.look(rowMajor: transposed(a), gravity: gravity(a))
                monitor.update(yaw: look.heading, pitch: look.elevation, now: clock)
                clock += 50
            }
        }
        let at = RotationRig.propped(5)
        feed(at, 2_000)
        for (x, y, z) in [(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (1.0, 1.0, 1.0), (1.0, -1.0, 0.0)] {
            feed(RotationRig.times(RotationRig.turn(x, y, z, 1.5), at), 100)
        }
        feed(at, 2_000)
        XCTAssertFalse(monitor.moving)
        XCTAssertFalse(monitor.consumeReframed())

        feed(RotationRig.times(RotationRig.turn(0, 0, 1, 15), at), 3_000)
        XCTAssertTrue(monitor.consumeReframed())
    }
}
