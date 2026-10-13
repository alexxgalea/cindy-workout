import Foundation

/// Turns what Core Motion reports into the two angles `CameraStabilityMonitor` is fed.
///
/// `CameraLook` reads Android's rotation matrix, whose layout is documented there. Core Motion's
/// `CMAttitude.rotationMatrix` is the same rotation written the other way round: it carries a vector
/// from the reference frame to the device, so its transpose is Android's. That is what Apple's
/// documentation says as far as it says anything, and there is no iPhone at hand to read it off.
/// So the layout is not taken on trust: gravity, which `CMDeviceMotion` reports in the device's own
/// axes with no convention to get wrong, says which of the two readings of the matrix puts the
/// world's "up" where gravity says it is, and that one is used.
///
/// Free of Core Motion, like the rest of this package: the matrix comes in as nine numbers, row by
/// row, `m11 m12 m13 m21 …`, as the struct declares them.
public enum CameraMotion {

    /// Gravity in the device's axes, in units of g, as `CMDeviceMotion.gravity` reports it.
    public typealias Gravity = (x: Float, y: Float, z: Float)

    /// Where the camera points, read two ways.
    public struct Look: Equatable, Sendable {
        /// Compass bearing of the camera's axis from `CameraLook`, in an arbitrary north: only the
        /// difference between two of them means anything.
        public let heading: Float
        /// Degrees above the horizon, from the matrix.
        public let elevation: Float
        /// The same elevation worked out from gravity alone. The two should agree to a degree or so;
        /// when they do not, the matrix is being misread and the debug readout shows it.
        public let gravityElevation: Float
    }

    /// The matrix in Android's layout (row-major, columns the device's axes in the world's
    /// east, north and up), whichever way round `rowMajor` was written.
    ///
    /// In Android's layout the third row is the world's "up" in the device's axes, which is gravity
    /// turned round. Of the matrix as given and its transpose, the one whose third row is nearer
    /// that wins; the transpose, which is what Core Motion's documentation implies, on a tie. A tie
    /// is harmless: the two then agree on every number the monitor reads.
    public static func androidLayout(rowMajor m: [Float], gravity g: Gravity) -> [Float] {
        precondition(m.count == 9, "a rotation matrix has nine numbers")
        let transposed = [m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]]
        return distanceFromGravity(transposed, g) <= distanceFromGravity(m, g) ? transposed : m
    }

    /// The camera's heading and elevation for one Core Motion reading.
    public static func look(rowMajor m: [Float], gravity g: Gravity) -> Look {
        let android = androidLayout(rowMajor: m, gravity: g)
        return Look(heading: CameraLook.heading(android), elevation: CameraLook.elevation(android),
                    gravityElevation: elevation(gravity: g))
    }

    /// Degrees above the horizon that the back camera looks, from gravity alone.
    ///
    /// The camera looks out of the back along the device's -Z, and the world's "up" is minus gravity,
    /// so the sine of the elevation is gravity's Z: a phone standing upright reads 0 and one lying
    /// face up, looking at the floor, reads -90.
    public static func elevation(gravity g: Gravity) -> Float {
        Float(asin(min(max(Double(g.z), -1), 1)) * 57.29577951308232)
    }

    private static func distanceFromGravity(_ android: [Float], _ g: Gravity) -> Float {
        let dx = g.x + android[6]
        let dy = g.y + android[7]
        let dz = g.z + android[8]
        return dx * dx + dy * dy + dz * dz
    }
}
