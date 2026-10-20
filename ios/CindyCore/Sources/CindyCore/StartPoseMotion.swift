import Foundation

/// The motion of the start-position figure: where each joint is at a moment of its loop, how the
/// figure turns, how it is projected into a card, and how depth dims and thins its far limbs. Port
/// of the arithmetic of `StartPoseView.kt`, with the drawing left to the screen.
///
/// ### The rotation
///
/// `StartPoses` stores a z for every joint, so this is a genuine turn rather than a wobble: the pose
/// is rotated about the vertical axis through the figure and projected with a weak perspective.
/// Depth then falls out of it for free: each bone's alpha and stroke width follow its rotated z, so
/// a limb swinging behind the body dims and thins on its own. That is the whole three-dimensional
/// cue; there is no mesh, no model and no renderer beyond a canvas.
///
/// ### The loop
///
/// Poses are interpolated rather than cut, and the target is held for over half the cycle: the two
/// approach frames exist only to say which way to move, so lingering on them would be lingering on
/// the wrong thing. The rewind fades rather than snapping.
public enum StartPoseMotion {
    public static let loopMs: Float = 4000
    public static let yawMs: Float = 5400
    public static let yawDegrees: Float = 15

    /// Fractions of the loop: reach, settle, hold, rewind.
    public static let reachEnd: Float = 0.22
    public static let settleEnd: Float = 0.46
    public static let holdEnd: Float = 0.88

    /// Large enough that the perspective reads as depth rather than as a fish-eye.
    public static let focal: Float = 620

    /// The joints at a moment of the loop, as flat `x, y, z` triples, and the figure's overall alpha.
    public struct Pose: Equatable, Sendable {
        public let joints: [Float]
        public let alpha: Float
    }

    /// The pose `elapsed` milliseconds into the loop, which repeats every `loopMs`.
    ///
    /// The rewind is the only part that fades: cutting from the held position back to the approach
    /// reads as a glitch, whereas dipping through it, to a quarter at its halfway point, reads as
    /// starting over.
    public static func pose(of loop: StartPoses.Loop, atMs elapsed: Float) -> Pose {
        let t = elapsed.truncatingRemainder(dividingBy: loopMs) / loopMs
        let f = loop.frames
        if t < reachEnd {
            return Pose(joints: lerp(f[0], f[1], ease(t / reachEnd)), alpha: 1)
        } else if t < settleEnd {
            return Pose(joints: lerp(f[1], f[2], ease((t - reachEnd) / (settleEnd - reachEnd))), alpha: 1)
        } else if t < holdEnd {
            return Pose(joints: f[2], alpha: 1)
        } else {
            let u = (t - holdEnd) / (1 - holdEnd)
            return Pose(joints: lerp(f[2], f[0], ease(u)),
                        alpha: 0.25 + 0.75 * (2 * u - 1) * (2 * u - 1))
        }
    }

    /// How far the figure has turned about its vertical axis, in degrees.
    public static func yaw(atMs elapsed: Float) -> Float {
        sin(elapsed / yawMs * 2 * Float.pi) * yawDegrees
    }

    /// Joints in view points: where each is drawn, and its rotated depth.
    public struct Projected: Equatable, Sendable {
        public let x: [Float]
        public let y: [Float]
        public let z: [Float]
    }

    /// Rotates `joints` about the figure's own vertical axis and projects them into a view of
    /// `width` by `height`, the loop's box fitted into it and centred.
    ///
    /// Weak perspective: nearer joints grow a little, which is what sells the turn.
    public static func project(_ joints: [Float], loop: StartPoses.Loop, yawDegrees: Float,
                               width: Float, height: Float) -> Projected {
        let scale = min(width / loop.boxWidth, height / loop.boxHeight)
        let offsetX = (width - loop.boxWidth * scale) / 2
        let offsetY = (height - loop.boxHeight * scale) / 2
        let cx = loop.boxWidth / 2
        let cy = loop.boxHeight / 2
        let angle = Double(yawDegrees) * 0.017453292519943295
        let cosA = Float(cos(angle))
        let sinA = Float(sin(angle))

        var xs = [Float](repeating: 0, count: StartPoses.joints)
        var ys = xs
        var zs = xs
        for j in 0..<StartPoses.joints {
            let x = joints[j * 3], y = joints[j * 3 + 1], z = joints[j * 3 + 2]
            let dx = x - cx
            let rx = dx * cosA + z * sinA
            let rz = -dx * sinA + z * cosA
            let p = focal / (focal - rz)
            xs[j] = offsetX + (cx + rx * p) * scale
            ys[j] = offsetY + (cy + (y - cy) * p) * scale
            zs[j] = rz
        }
        return Projected(x: xs, y: ys, z: zs)
    }

    /// Maps a rotated z onto 0 (furthest) to 1 (nearest).
    public static func depthUnit(_ z: Float) -> Float { min(max((z + 9) / 18, 0), 1) }

    /// Nearer bones are brighter. The span is deliberately wide, because it is the only depth cue.
    public static func depthAlpha(_ z: Float) -> Float { 0.30 + 0.70 * depthUnit(z) }

    /// The bone indices, furthest first, so a near limb crosses over a far one rather than under it.
    public static func boneOrder(_ projected: Projected) -> [Int] {
        let depths = StartPoses.bones.map { (projected.z[$0[0]] + projected.z[$0[1]]) / 2 }
        return Array(StartPoses.bones.indices).sorted { depths[$0] < depths[$1] }
    }

    private static func ease(_ x: Float) -> Float {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }

    private static func lerp(_ a: [Float], _ b: [Float], _ u: Float) -> [Float] {
        zip(a, b).map { $0 + ($1 - $0) * u }
    }
}
