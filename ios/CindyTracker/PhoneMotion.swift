import CoreMotion
import CindyCore

/// Watches the phone itself, to notice when it is knocked or turned: the bar zone and the band the
/// counter has learned are kept in frame pixels, so a phone that has moved is counting against a
/// picture that is no longer there. Port of `MainActivity`'s rotation-vector listener.
///
/// Deliberately not used to count anything. The phone stands still by design; the only question put
/// to its sensors is whether the framing the count was calibrated against is still the framing.
/// `CameraStabilityMonitor` decides that, from the heading and elevation of the axis the camera
/// looks along (`CameraMotion` works those out); this only feeds it and passes on its verdict.
///
/// Device motion needs no permission. The simulator has none to give, so there nothing happens.
@MainActor
final class PhoneMotion {

    /// Called once when the phone has been moved and has settled again.
    var onMoved: (() -> Void)?

    /// Called, a couple of times a second and only while `readoutEnabled`, with the debug line.
    var onReadout: ((String) -> Void)?
    var readoutEnabled = false

    /// 16 readings a second: the slowest rate that still catches a knock, as Android's
    /// `SENSOR_DELAY_UI` is. A bumped phone is not a subtle signal, and this runs for the whole of a
    /// twenty minute workout.
    private static let intervalSeconds = 1.0 / 16.0
    private static let readoutEvery = 8

    private let manager = CMMotionManager()
    private let monitor = CameraStabilityMonitor()
    private var readings = 0

    /// Starts listening. A second call while it is already listening does nothing.
    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = Self.intervalSeconds
        // North is arbitrary in either frame, and only the difference between two headings is used.
        // The corrected one stops the heading drifting over twenty minutes, which would otherwise
        // look like a slow turn; Android's rotation vector is corrected by the compass the same way.
        let frame: CMAttitudeReferenceFrame = CMMotionManager.availableAttitudeReferenceFrames()
            .contains(.xArbitraryCorrectedZVertical) ? .xArbitraryCorrectedZVertical : .xArbitraryZVertical
        manager.startDeviceMotionUpdates(using: frame, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            MainActor.assumeIsolated { self.feed(motion) }
        }
    }

    /// Stops listening and forgets where the phone was, so the next screen starts from where the
    /// phone is then. The three seconds of walking to the bar are not a knock.
    func stop() {
        manager.stopDeviceMotionUpdates()
        monitor.reset()
        readings = 0
    }

    private func feed(_ motion: CMDeviceMotion) {
        let r = motion.attitude.rotationMatrix
        let g = motion.gravity
        let look = CameraMotion.look(
            rowMajor: [r.m11, r.m12, r.m13, r.m21, r.m22, r.m23, r.m31, r.m32, r.m33].map { Float($0) },
            gravity: (Float(g.x), Float(g.y), Float(g.z)))
        // The same monotonic clock as the workout's, so a reading and a tick are on one timeline.
        monitor.update(yaw: look.heading, pitch: look.elevation, now: Int64(ProcessInfo.processInfo.systemUptime * 1000))
        if monitor.consumeReframed() { onMoved?() }

        readings += 1
        if readoutEnabled && readings % Self.readoutEvery == 0 {
            // Two elevations that disagree by more than a degree or so mean the matrix is misread.
            onReadout?(String(format: "look %.0f° · up %.0f° (gravity %.0f°)%@", look.heading, look.elevation,
                              look.gravityElevation, monitor.moving ? " · moving" : ""))
        }
    }
}
