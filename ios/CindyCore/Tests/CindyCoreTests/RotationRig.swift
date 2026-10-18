import Foundation

/// Rotation matrices a phone propped up to film would report, in Android's layout: nine numbers,
/// row-major, whose columns are the device's axes in the world's East, North and Up. Shared by the
/// tests of `CameraLook`, of the monitor it feeds, and of the Core Motion adapter.
enum RotationRig {

    /// Row-major 3x3 product.
    static func times(_ a: [Double], _ b: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: 9)
        for i in 0..<9 {
            let row = i / 3 * 3
            let column = i % 3
            var sum = 0.0
            for k in 0..<3 { sum += a[row + k] * b[k * 3 + column] }
            out[i] = sum
        }
        return out
    }

    /// Rotation by `degrees` about a world axis (East, North, Up), by Rodrigues' formula.
    static func turn(_ x: Double, _ y: Double, _ z: Double, _ degrees: Double) -> [Double] {
        let n: Double = (x * x + y * y + z * z).squareRoot()
        let ux: Double = x / n
        let uy: Double = y / n
        let uz: Double = z / n
        let a: Double = degrees * 0.017453292519943295
        let s: Double = sin(a)
        let c: Double = cos(a)
        let t: Double = 1 - c
        // Rodrigues' formula, row by row, with each product named so the type checker can follow.
        let xx: Double = t * ux * ux + c
        let xy: Double = t * ux * uy - s * uz
        let xz: Double = t * ux * uz + s * uy
        let yx: Double = t * ux * uy + s * uz
        let yy: Double = t * uy * uy + c
        let yz: Double = t * uy * uz - s * ux
        let zx: Double = t * ux * uz - s * uy
        let zy: Double = t * uy * uz + s * ux
        let zz: Double = t * uz * uz + c
        return [xx, xy, xz, yx, yy, yz, zx, zy, zz]
    }

    /// A phone standing on its end facing north: top edge up, camera along the horizon.
    static let upright: [Double] = [1, 0, 0, 0, 0, -1, 0, 1, 0]

    /// Leaning back against a box by `tiltBack` degrees, so the camera looks that far up.
    static func propped(_ tiltBack: Double) -> [Double] { times(turn(1, 0, 0, tiltBack), upright) }
}
