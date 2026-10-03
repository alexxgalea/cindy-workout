import Foundation

/// Notices that the *phone* moved, as opposed to the athlete.
///
/// Everything the pull-up gate knows is stored in frame pixels — where the bar is, how wide its
/// zone is, how far below it the head has to return. `WorkoutEngine.recalibrate` says as much in its
/// own comment: "The bar's position was recorded in frame pixels, so a moved camera invalidates
/// it." Without this nothing calls it when the camera actually moves. A phone knocked by a foot, a
/// bag or a gust keeps counting against a bar that is no longer where it thinks, which either
/// refuses every rep for the rest of the workout or accepts a climb that never crossed anything.
///
/// Deliberately *not* used to count reps. The phone is stationary by design, so its gyroscope says
/// nothing whatever about what the athlete's body is doing; the only question worth asking it is
/// whether the picture the counting rules were calibrated against is still the picture.
///
/// Free of CoreMotion so the rule can be tested: the caller feeds it whatever its attitude reports.
public final class CameraStabilityMonitor {

    /// Rotation, in degrees, past which the framing is a different framing.
    ///
    /// Generous on purpose. A phone propped on a box vibrates when someone lands a burpee nearby,
    /// and a couple of degrees of wobble changes nothing a bar zone cares about — its tolerances
    /// are measured in torso lengths. Eight degrees at three metres moves the bar the better part
    /// of half a metre through the frame, which no tolerance absorbs.
    private static let movedDegrees: Float = 8

    /// How still it must then be before the framing is trusted again.
    ///
    /// Long enough to cover being picked up, adjusted and put down, so the athlete is not handed a
    /// fresh calibration halfway through repositioning the phone.
    private static let settleMs: Int64 = 1_500

    /// Orientation the current calibration belongs to, or NaN before one is established.
    private var anchorYaw: Float = .nan
    private var anchorPitch: Float = .nan
    private var stillSince: Int64 = 0

    /// True from the moment movement is detected until the phone has been still again.
    public private(set) var moving = false

    private var reframed = false

    public init() {}

    /// True for exactly one read, after the phone has moved and then settled.
    ///
    /// Consumed rather than polled so the caller cannot recalibrate twice off one bump.
    public func consumeReframed() -> Bool {
        guard reframed else { return false }
        reframed = false
        return true
    }

    /// Feeds one orientation reading, in degrees.
    ///
    /// Yaw and pitch only. Roll is ignored: a phone rotating about the axis it is pointing along
    /// changes which way up the picture is, and the frame the analysis runs on is already rotated
    /// to upright before anything sees it.
    public func update(yaw: Float, pitch: Float, now: Int64) {
        if anchorYaw.isNaN {
            anchorYaw = yaw
            anchorPitch = pitch
            stillSince = now
            return
        }

        let moved = max(abs(delta(yaw, anchorYaw)), abs(delta(pitch, anchorPitch)))
        if moved >= Self.movedDegrees {
            moving = true
            // The anchor follows the phone while it is in motion, so what is being measured is
            // "has it stopped", not "how far has it come from where it started". Being carried
            // across a gym would otherwise never settle.
            anchorYaw = yaw
            anchorPitch = pitch
            stillSince = now
            return
        }
        if !moving { return }
        if now - stillSince < Self.settleMs { return }
        moving = false
        reframed = true
        anchorYaw = yaw
        anchorPitch = pitch
    }

    /// Shortest signed distance between two angles, so 359 and 1 are two degrees apart.
    private func delta(_ a: Float, _ b: Float) -> Float {
        // Kotlin's `%` on a Float keeps the sign of the dividend, which is what this does.
        var d = (a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    public func reset() {
        anchorYaw = .nan
        anchorPitch = .nan
        stillSince = 0
        moving = false
        reframed = false
    }
}
