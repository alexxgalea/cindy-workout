import Foundation

/// Where the pull-up bar is, learned from the athlete hanging on it.
///
/// Elbow flexion alone cannot tell a pull-up from someone standing on the floor waving their arms
/// about, and "wrists above the hips" is a weak substitute — it is true of anyone reaching
/// overhead. Knowing roughly where the hands sit when they are on the bar turns that into a real
/// test.
///
/// The zone is derived rather than tapped in: the setup reps already have the athlete hanging, and
/// every dead hang during the workout refines it, so it survives a pause without another
/// calibration step. Tolerances are multiples of torso length, never pixels, so stepping toward or
/// away from the camera does not move the gate.
public final class BarZone {

    /// How fast the estimate follows new observations.
    private static let follow: Float = 0.15
    /// Vertical slack around the bar, in torso lengths.
    private static let yTolerance: Float = 0.75
    /// Horizontal slack beyond the observed grip, in torso lengths.
    private static let xPadding: Float = 0.6

    private var y: Float = .nan
    private var xMin: Float = .nan
    private var xMax: Float = .nan

    public init() {}

    /// True once a dead hang has been seen and the zone means something.
    public var established: Bool { !y.isNaN }

    /// Records where the hands were during a confirmed dead hang.
    public func observeHang(handsX: Float, handsY: Float, halfGrip: Float) {
        let low = handsX - halfGrip
        let high = handsX + halfGrip
        guard established else {
            y = handsY
            xMin = low
            xMax = high
            return
        }
        y += Self.follow * (handsY - y)
        xMin += Self.follow * (min(xMin, low) - xMin)
        xMax += Self.follow * (max(xMax, high) - xMax)
    }

    /// Whether hands at this position, on a body of this scale, are plausibly on the bar.
    public func holds(handsX: Float, handsY: Float, torso: Float) -> Bool {
        // Nothing learned yet: do not block counting.
        guard established, torso > 0 else { return true }
        guard abs(handsY - y) <= Self.yTolerance * torso else { return false }
        let pad = Self.xPadding * torso
        return handsX >= xMin - pad && handsX <= xMax + pad
    }

    /// Forgets the bar — the camera has moved, so its position in the frame is meaningless.
    public func reset() {
        y = .nan
        xMin = .nan
        xMax = .nan
    }
}
