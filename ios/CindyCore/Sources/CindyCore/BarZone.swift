import Foundation

/// Where the pull-up bar is, learned from the athlete hanging on it.
///
/// Elbow flexion alone cannot tell a pull-up from someone standing on the floor waving their arms
/// about, and "wrists above the hips" is a weak substitute — it is true of anyone reaching
/// overhead. Knowing roughly where the hands sit when they are actually on the bar turns that into
/// a real test.
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
    private var manual = false

    public init() {}

    /// True once a dead hang has been seen and the zone means something.
    public var established: Bool { !y.isNaN }

    /// The centre line of the bar, in the same pixel coordinate system as the keypoints.
    public var lineY: Float? { established ? y : nil }

    /// The region both wrists must fall inside for `holds` to pass, on a body of this scale.
    ///
    /// The tolerances are private to this class and scale with the athlete, so the only honest
    /// way to draw the gate is to ask the gate itself where it currently is.
    public func bounds(torso: Float) -> Bounds? {
        guard established, torso > 0 else { return nil }
        let pad = manual ? 0 : Self.xPadding * torso
        return Bounds(
            lineY: y,
            left: xMin - pad,
            right: xMax + pad,
            top: y - Self.yTolerance * torso,
            bottom: y + Self.yTolerance * torso
        )
    }

    /// Uses a fixed bar for a recorded regression clip.
    ///
    /// The app normally learns its bar from dead hangs. A labelled offline clip cannot be asked
    /// to perform that calibration on demand, so tests may supply the line and horizontal extent
    /// measured from that clip instead. Production never needs to call this.
    public func configureManual(y: Float, xMin: Float, xMax: Float) {
        precondition(y.isFinite && xMin.isFinite && xMax.isFinite && xMin <= xMax,
                     "Manual bar bounds must be finite and ordered")
        self.y = y
        self.xMin = xMin
        self.xMax = xMax
        manual = true
    }

    /// Records where the hands were during a confirmed dead hang.
    public func observeHang(handsX: Float, handsY: Float, halfGrip: Float) {
        guard !manual else { return }
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

    /// Whether *both* wrists, on a body of this scale, are plausibly on the bar.
    ///
    /// Testing the midpoint lets one hand leave the bar while the other hand keeps a rep alive.
    /// A pull-up needs both grips, so each wrist is tested independently.
    public func holds(left: Keypoint, right: Keypoint, torso: Float) -> Bool {
        // Nothing learned yet: do not block counting.
        guard established, torso > 0 else { return true }
        guard abs(left.y - y) <= Self.yTolerance * torso, abs(right.y - y) <= Self.yTolerance * torso
        else { return false }
        // Scenario bars are explicit regions, so do not silently widen them. Learned bars still
        // need a torso-scaled allowance for a natural regrip along the bar.
        let pad = manual ? 0 : Self.xPadding * torso
        return left.x >= xMin - pad && left.x <= xMax + pad &&
            right.x >= xMin - pad && right.x <= xMax + pad
    }

    /// Forgets the bar — the camera has moved, so its position in the frame is meaningless.
    public func reset() {
        y = .nan
        xMin = .nan
        xMax = .nan
        manual = false
    }

    /// The bar and the box around it that `holds` tests, in keypoint pixels.
    public struct Bounds: Equatable, Sendable {
        public let lineY: Float
        public let left: Float
        public let right: Float
        public let top: Float
        public let bottom: Float
    }
}
