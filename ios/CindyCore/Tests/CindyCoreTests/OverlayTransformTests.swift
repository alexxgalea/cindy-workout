import XCTest
import CindyCore

/// The map from the analysis frame onto the recorded buffer.
///
/// The first version of this put the whole overlay in the lower-left corner at a fraction of its
/// size, so the properties that would have caught it are asserted directly: the frame's corners
/// must land on the buffer's corners, the centre on the centre, and nothing may be stretched.
///
/// Mirrors `OverlayTransformTest.kt`.
final class OverlayTransformTests: XCTestCase {

    private let srcW = 480
    private let srcH = 640

    private func build(_ bufW: Int, _ bufH: Int, _ rotation: Int, _ mirror: Bool = false) -> Affine {
        OverlayTransform.build(srcWidth: srcW, srcHeight: srcH, bufferWidth: bufW, bufferHeight: bufH,
                               rotationDegrees: rotation, mirror: mirror)
    }

    private func corners(_ a: Affine, _ w: Int, _ h: Int) -> [(Float, Float)] {
        [(0, 0), (Float(w), 0), (Float(w), Float(h)), (0, Float(h))].map { (a.mapX($0.0, $0.1), a.mapY($0.0, $0.1)) }
    }

    private func assertCoversBuffer(_ a: Affine, _ bufW: Int, _ bufH: Int, line: UInt = #line) {
        let mapped = corners(a, srcW, srcH)
        let xs = mapped.map { $0.0 }, ys = mapped.map { $0.1 }
        XCTAssertEqual(xs.min()!, 0, accuracy: 1, "left edge", line: line)
        XCTAssertEqual(ys.min()!, 0, accuracy: 1, "top edge", line: line)
        XCTAssertEqual(xs.max()!, Float(bufW), accuracy: 1, "right edge", line: line)
        XCTAssertEqual(ys.max()!, Float(bufH), accuracy: 1, "bottom edge", line: line)
    }

    /// Negative where the transform reflects — which is what flips text.
    private func determinant(_ a: Affine) -> Float { a.a * a.d - a.b * a.c }

    private func assertCentred(_ a: Affine, _ bufW: Int, _ bufH: Int, line: UInt = #line) {
        XCTAssertEqual(a.mapX(Float(srcW) / 2, Float(srcH) / 2), Float(bufW) / 2, accuracy: 1, line: line)
        XCTAssertEqual(a.mapY(Float(srcW) / 2, Float(srcH) / 2), Float(bufH) / 2, accuracy: 1, line: line)
    }

    /// A square in the source must stay square: equal side lengths, right angles.
    private func assertNotStretched(_ a: Affine, line: UInt = #line) {
        let side: Float = 100
        let o = (a.mapX(0, 0), a.mapY(0, 0))
        let x = (a.mapX(side, 0), a.mapY(side, 0))
        let y = (a.mapX(0, side), a.mapY(0, side))
        let lenX = hypotf(x.0 - o.0, x.1 - o.1)
        let lenY = hypotf(y.0 - o.0, y.1 - o.1)
        XCTAssertEqual(lenX, lenY, accuracy: 0.01, "uniform scale", line: line)
        let dot = (x.0 - o.0) * (y.0 - o.0) + (x.1 - o.1) * (y.1 - o.1)
        XCTAssertLessThan(abs(dot), 0.01, "axes stay perpendicular, got dot=\(dot)", line: line)
    }

    /// identity when the buffer matches the frame
    func testIdentityWhenTheBufferMatchesTheFrame() {
        let a = build(srcW, srcH, 0)
        XCTAssertEqual(a.mapX(0, 0), 0, accuracy: 0.01)
        XCTAssertEqual(a.mapY(0, 0), 0, accuracy: 0.01)
        XCTAssertEqual(a.mapX(Float(srcW), 0), Float(srcW), accuracy: 0.01)
        XCTAssertEqual(a.mapY(0, Float(srcH)), Float(srcH), accuracy: 0.01)
    }

    /// an unrotated 720p buffer is filled corner to corner
    func testAnUnrotated720pBufferIsFilledCornerToCorner() {
        let a = build(720, 960, 0)
        assertCoversBuffer(a, 720, 960)
        assertCentred(a, 720, 960)
        assertNotStretched(a)
    }

    /// a quarter-turned buffer is filled corner to corner
    func testAQuarterTurnedBufferIsFilledCornerToCorner() {
        // The usual portrait case: the buffer is landscape and rotated 90 for display.
        let a = build(1280, 960, 90)
        assertCoversBuffer(a, 1280, 960)
        assertCentred(a, 1280, 960)
        assertNotStretched(a)
    }

    /// 270 degrees is filled corner to corner too
    func test270DegreesIsFilledCornerToCornerToo() {
        let a = build(1280, 960, 270)
        assertCoversBuffer(a, 1280, 960)
        assertCentred(a, 1280, 960)
        assertNotStretched(a)
    }

    /// 180 degrees is filled corner to corner too
    func test180DegreesIsFilledCornerToCornerToo() {
        let a = build(720, 960, 180)
        assertCoversBuffer(a, 720, 960)
        assertCentred(a, 720, 960)
        assertNotStretched(a)
    }

    /// a quarter turn moves the frame origin off the buffer origin
    func testAQuarterTurnMovesTheFrameOriginOffTheBufferOrigin() {
        // The buffer is stored a quarter turn from how it is shown, so the frame's top-left
        // belongs at the buffer's bottom-left. Turning the buffer 90 clockwise to display it
        // brings that corner back to the top-left, which is the whole point.
        let a = build(1280, 960, 90)
        XCTAssertEqual(a.mapX(0, 0), 0, accuracy: 1)
        XCTAssertEqual(a.mapY(0, 0), 960, accuracy: 1)
    }

    /// a matching aspect ratio keeps every corner on the buffer
    func testAMatchingAspectRatioKeepsEveryCornerOnTheBuffer() {
        // 3:4 frame into a 3:4 buffer at every rotation: an exact fit, nothing cropped.
        for rotation in [0, 90, 180, 270] {
            let quarterTurned = rotation % 180 != 0
            let bufW = quarterTurned ? 960 : 720
            let bufH = quarterTurned ? 720 : 960
            let a = build(bufW, bufH, rotation)
            for (x, y) in corners(a, srcW, srcH) {
                XCTAssertTrue(x >= -1 && x <= Float(bufW) + 1, "x=\(x) outside 0..\(bufW) at \(rotation)")
                XCTAssertTrue(y >= -1 && y <= Float(bufH) + 1, "y=\(y) outside 0..\(bufH) at \(rotation)")
            }
            assertCoversBuffer(a, bufW, bufH)
            assertNotStretched(a)
        }
    }

    /// mirroring swaps left for right and leaves top alone
    func testMirroringSwapsLeftForRightAndLeavesTopAlone() {
        let plain = build(720, 960, 0)
        let mirrored = build(720, 960, 0, true)
        XCTAssertEqual(plain.mapX(Float(srcW), 0), mirrored.mapX(0, 0), accuracy: 1)
        XCTAssertEqual(plain.mapY(0, 0), mirrored.mapY(0, 0), accuracy: 1)
        assertCoversBuffer(mirrored, 720, 960)
    }

    /// only a mirrored transform reverses the picture
    func testOnlyAMirroredTransformReversesThePicture() {
        // The HUD rides the unmirrored one: a reflected canvas writes every letter backwards,
        // which is what put a reversed clock and rep count in the recording.
        for rotation in [0, 90, 180, 270] {
            XCTAssertGreaterThan(determinant(build(720, 960, rotation)), 0, "reflected at \(rotation)")
            XCTAssertLessThan(determinant(build(720, 960, rotation, true)), 0, "not reflected at \(rotation)")
        }
    }

    /// a taller buffer crops the sides rather than stretching
    func testATallerBufferCropsTheSidesRatherThanStretching() {
        // A 9:16 buffer against a 3:4 frame. Filling the height overflows the width, so the
        // sides are cropped and the picture keeps its proportions.
        let a = build(1080, 1920, 0)
        assertNotStretched(a)
        assertCentred(a, 1080, 1920)
        let xs = corners(a, srcW, srcH).map { $0.0 }
        let ys = corners(a, srcW, srcH).map { $0.1 }
        XCTAssertLessThan(xs.min()!, -1, "should overflow horizontally, got \(xs.min()!)..\(xs.max()!)")
        XCTAssertEqual(ys.min()!, 0, accuracy: 1, "and fit the height exactly")
        XCTAssertEqual(ys.max()!, 1920, accuracy: 1)
    }

    /// degenerate sizes fall back to identity instead of exploding
    func testDegenerateSizesFallBackToIdentityInsteadOfExploding() {
        XCTAssertEqual(OverlayTransform.build(srcWidth: 0, srcHeight: 640, bufferWidth: 720, bufferHeight: 960,
                                              rotationDegrees: 0, mirror: false), .identity)
        XCTAssertEqual(OverlayTransform.build(srcWidth: 480, srcHeight: 640, bufferWidth: 0, bufferHeight: 0,
                                              rotationDegrees: 0, mirror: false), .identity)
    }

    /// negative and over-wound rotations normalise
    func testNegativeAndOverWoundRotationsNormalise() {
        let plain = build(1280, 960, 90)
        XCTAssertEqual(build(1280, 960, 450), plain)
        XCTAssertEqual(build(1280, 960, -270), plain)
    }

    // MARK: - the safe area
    //
    // The transform was right and the HUD was still off the picture, because fill-centre crops and
    // the HUD was laid out against the frame's own edges. These pin the region that survives.

    /// Maps a source rect through the transform and asserts it lands inside the buffer.
    private func assertInsideBuffer(_ a: Affine, _ r: SourceRect, _ bufW: Int, _ bufH: Int, line: UInt = #line) {
        let pts = [(r.left, r.top), (r.right, r.top), (r.right, r.bottom), (r.left, r.bottom)]
            .map { (a.mapX($0.0, $0.1), a.mapY($0.0, $0.1)) }
        for (x, y) in pts {
            XCTAssertTrue(x >= -1 && x <= Float(bufW) + 1, "x=\(x) outside 0..\(bufW)", line: line)
            XCTAssertTrue(y >= -1 && y <= Float(bufH) + 1, "y=\(y) outside 0..\(bufH)", line: line)
        }
    }

    private func visible(_ bufW: Int, _ bufH: Int, _ rotation: Int) -> SourceRect {
        OverlayTransform.visibleSource(srcWidth: srcW, srcHeight: srcH, bufferWidth: bufW, bufferHeight: bufH,
                                       rotationDegrees: rotation)
    }

    /// a 9 by 16 recording keeps only the middle of a 3 by 4 frame
    func testA9By16RecordingKeepsOnlyTheMiddleOfA3By4Frame() {
        // The shipping case: a 480x640 analysis frame into 1280x720 shown portrait. Filling
        // the height needs a scale of 2, which makes the frame 960 wide against a 720 buffer,
        // so 120 buffer px go from each side -- 60 of the frame's own 480, or 12.5%.
        let r = visible(1280, 720, 90)
        XCTAssertEqual(r.left, 60, accuracy: 0.5, "left")
        XCTAssertEqual(r.right, 420, accuracy: 0.5, "right")
        XCTAssertEqual(r.top, 0, accuracy: 0.5, "nothing off the top")
        XCTAssertEqual(r.bottom, 640, accuracy: 0.5, "nothing off the bottom")
        XCTAssertEqual(r.width, 360, accuracy: 0.5)
        XCTAssertEqual(r.height, 640, accuracy: 0.5)
    }

    /// the safe area is where the HUD used to be laid out, and was not
    func testTheSafeAreaIsWhereTheHUDUsedToBeLaidOutAndWasNot() {
        // The regression this exists for. The HUD anchored its panels a pad in from the frame,
        // pad being 1.8% of the height; against a frame 480 wide that is x=11.5, which is
        // inside the 60px the crop takes. Against the safe area it is inside the picture.
        let r = visible(1280, 720, 90)
        let pad = r.height * 0.018
        XCTAssertLessThan(pad, r.left, "the old anchor should have been cropped")
        let a = build(1280, 720, 90)
        assertInsideBuffer(a, SourceRect(left: r.left + pad, top: r.top + pad, right: r.right - pad, bottom: r.bottom - pad), 1280, 720)
    }

    /// every corner of the safe area lands on the buffer at every rotation
    func testEveryCornerOfTheSafeAreaLandsOnTheBufferAtEveryRotation() {
        for rotation in [0, 90, 180, 270] {
            let quarterTurned = rotation % 180 != 0
            let bufW = quarterTurned ? 1280 : 720
            let bufH = quarterTurned ? 720 : 1280
            let r = visible(bufW, bufH, rotation)
            for mirror in [false, true] {
                assertInsideBuffer(build(bufW, bufH, rotation, mirror), r, bufW, bufH)
            }
        }
    }

    /// a matching aspect ratio crops nothing
    func testAMatchingAspectRatioCropsNothing() {
        // 3:4 into 3:4: the safe area is the whole frame, so the HUD keeps its old placement.
        let r = visible(720, 960, 0)
        XCTAssertEqual(r.left, 0, accuracy: 0.5)
        XCTAssertEqual(r.top, 0, accuracy: 0.5)
        XCTAssertEqual(r.right, Float(srcW), accuracy: 0.5)
        XCTAssertEqual(r.bottom, Float(srcH), accuracy: 0.5)
    }

    /// a wider buffer crops the top and bottom instead
    func testAWiderBufferCropsTheTopAndBottomInstead() {
        // The other way about -- a landscape recording of the portrait frame loses height,
        // not width, and the HUD has to follow that too.
        let r = visible(1280, 720, 0)
        XCTAssertEqual(r.left, 0, accuracy: 0.5, "full width")
        XCTAssertEqual(r.right, Float(srcW), accuracy: 0.5, "full width")
        XCTAssertLessThan(r.height, Float(srcH) - 1, "height should be cropped, got \(r.height)")
        XCTAssertEqual(r.top, Float(srcH) - r.bottom, accuracy: 0.5, "and centred")
        assertInsideBuffer(build(1280, 720, 0), r, 1280, 720)
    }

    /// the safe area is always centred and never bigger than the frame
    func testTheSafeAreaIsAlwaysCentredAndNeverBiggerThanTheFrame() {
        for bufW in [320, 720, 1080, 1920] {
            for bufH in [240, 720, 1280, 1920] {
                let r = visible(bufW, bufH, 0)
                XCTAssertLessThanOrEqual(r.width, Float(srcW) + 0.5, "wider than the frame at \(bufW)x\(bufH)")
                XCTAssertLessThanOrEqual(r.height, Float(srcH) + 0.5, "taller than the frame at \(bufW)x\(bufH)")
                XCTAssertTrue(r.width > 0 && r.height > 0, "empty at \(bufW)x\(bufH)")
                XCTAssertEqual(r.left, Float(srcW) - r.right, accuracy: 0.5, "off centre at \(bufW)x\(bufH)")
                XCTAssertEqual(r.top, Float(srcH) - r.bottom, accuracy: 0.5, "off centre at \(bufW)x\(bufH)")
            }
        }
    }

    /// degenerate sizes give back the whole frame rather than an empty rect
    func testDegenerateSizesGiveBackTheWholeFrameRatherThanAnEmptyRect() {
        let r = visible(0, 0, 0)
        XCTAssertEqual(r.left, 0, accuracy: 0.01)
        XCTAssertEqual(r.right, Float(srcW), accuracy: 0.01)
        XCTAssertEqual(r.bottom, Float(srcH), accuracy: 0.01)
    }

    /// the matrix value order matches what Matrix setValues expects
    func testTheMatrixValueOrderMatchesWhatMatrixSetValuesExpects() {
        let a = Affine(a: 2, b: 3, c: 4, d: 5, tx: 6, ty: 7)
        // Matrix order: scaleX, skewX, transX, skewY, scaleY, transY, 0, 0, 1
        XCTAssertEqual(a.values(), [2, 4, 6, 3, 5, 7, 0, 0, 1])
    }

    /// then composes in the same order as Matrix postConcat
    func testThenComposesInTheSameOrderAsMatrixPostConcat() {
        let scaleThenShift = Affine.scale(2, 2).then(.translate(10, 0))
        XCTAssertEqual(scaleThenShift.mapX(10, 0), 30, accuracy: 0.01)
        let shiftThenScale = Affine.translate(10, 0).then(.scale(2, 2))
        XCTAssertEqual(shiftThenScale.mapX(10, 0), 40, accuracy: 0.01)
    }
}
