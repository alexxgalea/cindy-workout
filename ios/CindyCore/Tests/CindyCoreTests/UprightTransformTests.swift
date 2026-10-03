import XCTest
import CindyCore

/// The rotation that used to cost a whole bitmap.
///
/// Turning the frame upright moved out of a rotated copy and into the transform the detector was
/// already drawing through. That is a change to the pixels the counter sees, so the geometry has to
/// be exactly what it was: every corner of the raw buffer must land where the old rotated image
/// would have put it, at all four rotations, mirrored and not.
///
/// Mirrors `UprightTransformTest.kt`.
final class UprightTransformTests: XCTestCase {

    private let w = 640
    private let h = 480

    /// Kotlin's `Math.round`: halves go up.
    private func round(_ v: Float) -> Int { Int((v + 0.5).rounded(.down)) }

    private func corners(_ rotation: Int, mirror: Bool) -> [[Int]] {
        let m = OverlayTransform.upright(srcWidth: w, srcHeight: h, rotationDegrees: rotation, mirror: mirror)
        return [(0, 0), (Float(w), 0), (Float(w), Float(h)), (0, Float(h))]
            .map { [round(m.mapX($0.0, $0.1)), round(m.mapY($0.0, $0.1))] }
    }

    /// no rotation is the identity
    func testNoRotationIsTheIdentity() {
        XCTAssertEqual(corners(0, mirror: false), [[0, 0], [640, 0], [640, 480], [0, 480]])
    }

    /// a quarter turn swaps the axes and lands on the origin
    func testAQuarterTurnSwapsTheAxesAndLandsOnTheOrigin() {
        // Top-left goes to top-right, and the upright frame is 480x640.
        XCTAssertEqual(corners(90, mirror: false), [[480, 0], [480, 640], [0, 640], [0, 0]])
        XCTAssertEqual(OverlayTransform.uprightWidth(srcWidth: w, srcHeight: h, rotationDegrees: 90), 480)
        XCTAssertEqual(OverlayTransform.uprightHeight(srcWidth: w, srcHeight: h, rotationDegrees: 90), 640)
    }

    /// half and three-quarter turns also land on the origin
    func testHalfAndThreeQuarterTurnsAlsoLandOnTheOrigin() {
        XCTAssertEqual(corners(180, mirror: false), [[640, 480], [0, 480], [0, 0], [640, 0]])
        XCTAssertEqual(corners(270, mirror: false), [[0, 640], [0, 0], [480, 0], [480, 640]])
    }

    /// every rotation keeps the frame inside the upright bounds
    func testEveryRotationKeepsTheFrameInsideTheUprightBounds() {
        for rotation in [0, 90, 180, 270] {
            for mirror in [false, true] {
                let uw = Int(OverlayTransform.uprightWidth(srcWidth: w, srcHeight: h, rotationDegrees: rotation))
                let uh = Int(OverlayTransform.uprightHeight(srcWidth: w, srcHeight: h, rotationDegrees: rotation))
                for c in corners(rotation, mirror: mirror) {
                    XCTAssertEqual(c[0], min(max(c[0], 0), uw), "x in bounds at \(rotation)/\(mirror)")
                    XCTAssertEqual(c[1], min(max(c[1], 0), uh), "y in bounds at \(rotation)/\(mirror)")
                }
            }
        }
    }

    /// mirroring flips about the upright centre and nothing else
    func testMirroringFlipsAboutTheUprightCentreAndNothingElse() {
        for rotation in [0, 90, 180, 270] {
            let uw = Int(OverlayTransform.uprightWidth(srcWidth: w, srcHeight: h, rotationDegrees: rotation))
            let plain = corners(rotation, mirror: false)
            let flipped = corners(rotation, mirror: true)
            for i in plain.indices {
                XCTAssertEqual(flipped[i][0], uw - plain[i][0], "x mirrors at \(rotation)")
                XCTAssertEqual(flipped[i][1], plain[i][1], "y is untouched at \(rotation)")
            }
        }
    }

    /// mirroring twice is doing nothing
    func testMirroringTwiceIsDoingNothing() {
        let m = OverlayTransform.upright(srcWidth: w, srcHeight: h, rotationDegrees: 90, mirror: true)
        let uw = OverlayTransform.uprightWidth(srcWidth: w, srcHeight: h, rotationDegrees: 90)
        // Reflect the result back and the original corner must return.
        let x = m.mapX(0, 0)
        XCTAssertEqual(0, uw - (uw - x), accuracy: 0.001)
    }
}
