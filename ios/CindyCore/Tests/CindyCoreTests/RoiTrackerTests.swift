import XCTest
import CindyCore

/// The crop that follows the athlete, which `PoseDetector.kt` does inside the model call and so has
/// no test of its own on Android. These are written from what it does: the constants and the
/// order of its decisions, one behaviour at a time.
final class RoiTrackerTests: XCTestCase {

    private let w = 720, h = 1280

    /// A body whose confident keypoints span `box`, with `count` of them confident.
    private func body(_ box: (l: Float, t: Float, r: Float, b: Float), count: Int = 17, score: Float = 0.9) -> [Keypoint] {
        (0..<17).map { i in
            let corner = i % 4
            let x = corner < 2 ? box.l : box.r
            let y = corner % 2 == 0 ? box.t : box.b
            return Keypoint(x: x, y: y, score: i < count ? score : 0)
        }
    }

    private func region(_ t: RoiTracker) -> RoiTracker.Region { t.beginFrame(frameWidth: w, frameHeight: h) }

    /// it starts by looking at the whole frame, as a square
    func testItStartsByLookingAtTheWholeFrameAsASquare() {
        let t = RoiTracker()
        let r = region(t)
        // A portrait frame is letterboxed, not cropped: the square is as tall as the frame is.
        XCTAssertEqual(r, RoiTracker.Region(left: -280, top: 0, right: 1000, bottom: 1280))
        XCTAssertFalse(t.tracking)
        XCTAssertNil(t.roi)
    }

    /// the first crop is the body's box with the margin round it, centred on it
    func testTheFirstCropIsTheBodysBoxWithTheMarginRoundItCentredOnIt() {
        let t = RoiTracker()
        _ = region(t)
        t.update(body((200, 300, 500, 900)), frameWidth: w, frameHeight: h)
        let r = t.roi!
        XCTAssertEqual(r.width, 600 * 1.45, accuracy: 0.01, "the longer side of the box, times the margin")
        XCTAssertEqual(r.height, r.width, accuracy: 0.01, "a square")
        XCTAssertEqual((r.left + r.right) / 2, 350, accuracy: 0.01)
        XCTAssertEqual((r.top + r.bottom) / 2, 600, accuracy: 0.01)
    }

    /// the tracking flag describes the crop the frame was given, not the next one
    func testTheTrackingFlagDescribesTheCropTheFrameWasGivenNotTheNextOne() {
        let t = RoiTracker()
        _ = region(t)
        XCTAssertFalse(t.tracking, "the first frame is searched in full")
        t.update(body((200, 300, 500, 900)), frameWidth: w, frameHeight: h)
        // The first frame's flag is still what it was when it began.
        XCTAssertFalse(t.tracking, "updating after detection does not rewrite the frame just analysed")
        _ = region(t)
        XCTAssertTrue(t.tracking, "the second frame is given the crop")
    }

    /// later crops follow the body at 35% a frame
    func testLaterCropsFollowTheBodyAt35PercentAFrame() {
        let t = RoiTracker()
        _ = region(t)
        t.update(body((200, 300, 500, 900)), frameWidth: w, frameHeight: h)
        let first = t.roi!
        t.update(body((300, 300, 600, 900)), frameWidth: w, frameHeight: h)   // stepped 100 px right
        let second = t.roi!
        XCTAssertEqual(second.left - first.left, 100 * 0.35, accuracy: 0.01)
        XCTAssertEqual(second.right - first.right, 100 * 0.35, accuracy: 0.01)
        XCTAssertEqual(second.top, first.top, accuracy: 0.01, "nothing moved vertically")
        XCTAssertEqual(second.width, first.width, accuracy: 0.01)
    }

    /// four confident keypoints are not enough, five are
    func testFourConfidentKeypointsAreNotEnoughFiveAre() {
        let t = RoiTracker()
        t.update(body((200, 300, 500, 900), count: 4), frameWidth: w, frameHeight: h)
        XCTAssertNil(t.roi)
        t.update(body((200, 300, 500, 900), count: 5), frameWidth: w, frameHeight: h)
        XCTAssertNotNil(t.roi)
    }

    /// a score of 0.30 counts as confident and anything below does not
    func testAScoreOfPoint30CountsAsConfidentAndAnythingBelowDoesNot() {
        let t = RoiTracker()
        t.update(body((200, 300, 500, 900), score: 0.29), frameWidth: w, frameHeight: h)
        XCTAssertNil(t.roi)
        t.update(body((200, 300, 500, 900), score: 0.30), frameWidth: w, frameHeight: h)
        XCTAssertNotNil(t.roi)
    }

    /// a poor frame keeps the crop it had
    func testAPoorFrameKeepsTheCropItHad() {
        let t = RoiTracker()
        t.update(body((200, 300, 500, 900)), frameWidth: w, frameHeight: h)
        let kept = t.roi
        t.update(body((200, 300, 500, 900), count: 2), frameWidth: w, frameHeight: h)
        XCTAssertEqual(t.roi, kept)
    }

    /// five poor frames in a row give the crop up
    func testFivePoorFramesInARowGiveTheCropUp() {
        let t = RoiTracker()
        t.update(body((200, 300, 500, 900)), frameWidth: w, frameHeight: h)
        for _ in 0..<4 { t.update([], frameWidth: w, frameHeight: h) }
        XCTAssertNotNil(t.roi, "four misses are still a crop")
        t.update([], frameWidth: w, frameHeight: h)
        XCTAssertNil(t.roi, "the fifth sends it back to the whole frame")
        XCTAssertFalse(region(t) == t.roi)
        XCTAssertFalse(t.tracking)
    }

    /// a good frame in between starts the count again
    func testAGoodFrameInBetweenStartsTheCountAgain() {
        let t = RoiTracker()
        t.update(body((200, 300, 500, 900)), frameWidth: w, frameHeight: h)
        for _ in 0..<4 { t.update([], frameWidth: w, frameHeight: h) }
        t.update(body((200, 300, 500, 900)), frameWidth: w, frameHeight: h)
        for _ in 0..<4 { t.update([], frameWidth: w, frameHeight: h) }
        XCTAssertNotNil(t.roi, "four misses since the last good frame, not eight")
    }

    /// a tiny body does not shrink the crop below a quarter of the frame
    func testATinyBodyDoesNotShrinkTheCropBelowAQuarterOfTheFrame() {
        let t = RoiTracker()
        t.update(body((350, 600, 370, 640)), frameWidth: w, frameHeight: h)
        XCTAssertEqual(t.roi!.width, 1280 * 0.25, accuracy: 0.01)
    }

    /// a huge body does not grow the crop past the frame's longest side
    func testAHugeBodyDoesNotGrowTheCropPastTheFramesLongestSide() {
        let t = RoiTracker()
        t.update(body((0, 0, 720, 1280)), frameWidth: w, frameHeight: h)
        XCTAssertEqual(t.roi!.width, 1280, accuracy: 0.01)
    }

    /// reset forgets the crop, the misses and the flag
    func testResetForgetsTheCropTheMissesAndTheFlag() {
        let t = RoiTracker()
        t.update(body((200, 300, 500, 900)), frameWidth: w, frameHeight: h)
        _ = region(t)
        XCTAssertTrue(t.tracking)
        t.reset()
        XCTAssertNil(t.roi)
        XCTAssertFalse(t.tracking)
        // Misses were forgotten too: one new crop survives four poor frames.
        t.update(body((200, 300, 500, 900)), frameWidth: w, frameHeight: h)
        for _ in 0..<4 { t.update([], frameWidth: w, frameHeight: h) }
        XCTAssertNotNil(t.roi)
    }
}

/// The flip between the app's pixels and Vision's normalised bottom-left space, and the crop Vision
/// can accept.
final class VisionGeometryTests: XCTestCase {

    private let w = 720, h = 1280

    /// with no crop Vision looks at the whole image
    func testWithNoCropVisionLooksAtTheWholeImage() {
        XCTAssertEqual(VisionGeometry.regionOfInterest(for: nil, frameWidth: w, frameHeight: h), .full)
    }

    /// a crop inside the frame stays square in pixels, with its origin at the bottom left
    func testACropInsideTheFrameStaysSquareInPixelsWithItsOriginAtTheBottomLeft() {
        // 360 px square, 72 px from the left edge and 128 px from the top.
        let r = VisionGeometry.regionOfInterest(
            for: .init(left: 72, top: 128, right: 432, bottom: 488), frameWidth: w, frameHeight: h)
        XCTAssertEqual(r.x, 0.1, accuracy: 1e-9)
        XCTAssertEqual(r.width, 0.5, accuracy: 1e-9)
        XCTAssertEqual(r.height, 360.0 / 1280, accuracy: 1e-9)
        // The top edge is 128 px down the frame, which is 1 - 128/1280 up Vision's: the box's
        // bottom is that minus its height.
        XCTAssertEqual(r.y, 1 - (128 + 360.0) / 1280, accuracy: 1e-9)
        XCTAssertEqual(r.width * Double(w), r.height * Double(h), accuracy: 1e-6, "square in pixels")
    }

    /// a crop that hangs off the frame is slid back inside it
    func testACropThatHangsOffTheFrameIsSlidBackInsideIt() {
        let r = VisionGeometry.regionOfInterest(
            for: .init(left: -100, top: 1100, right: 260, bottom: 1460), frameWidth: w, frameHeight: h)
        XCTAssertEqual(r.x, 0, accuracy: 1e-9)
        XCTAssertEqual(r.y, 0, accuracy: 1e-9, "its bottom edge is the frame's")
        XCTAssertEqual(r.width, 0.5, accuracy: 1e-9, "same size")
        XCTAssertLessThanOrEqual(r.x + r.width, 1)
        XCTAssertLessThanOrEqual(r.y + r.height, 1)
    }

    /// a crop as big as the short side is the whole frame
    func testACropAsBigAsTheShortSideIsTheWholeFrame() {
        XCTAssertEqual(VisionGeometry.regionOfInterest(
            for: .init(left: 0, top: 0, right: 720, bottom: 720), frameWidth: w, frameHeight: h), .full)
        XCTAssertEqual(VisionGeometry.regionOfInterest(
            for: .init(left: -280, top: 0, right: 1000, bottom: 1280), frameWidth: w, frameHeight: h), .full)
    }

    /// a point comes back as frame pixels with y down
    func testAPointComesBackAsFramePixelsWithYDown() {
        // Vision's (0.5, 0.75) is half way across and a quarter of the way down from the top.
        let p = VisionGeometry.pixel(x: 0.5, y: 0.75, roi: .full, frameWidth: w, frameHeight: h)
        XCTAssertEqual(p.x, 360, accuracy: 0.001)
        XCTAssertEqual(p.y, 320, accuracy: 0.001)
    }

    /// a point inside a crop is mapped out through the crop first
    func testAPointInsideACropIsMappedOutThroughTheCropFirst() {
        let roi = NormalisedRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        // The centre of the crop is (0.5, 0.625) of the frame, i.e. 37.5% down from the top.
        let p = VisionGeometry.pixel(x: 0.5, y: 0.5, roi: roi, frameWidth: w, frameHeight: h)
        XCTAssertEqual(p.x, 360, accuracy: 0.001)
        XCTAssertEqual(p.y, Float((1 - 0.625) * 1280), accuracy: 0.001)
    }

    /// a crop and a point in it round-trip to the pixel they started at
    func testACropAndAPointInItRoundTripToThePixelTheyStartedAt() {
        let region = RoiTracker.Region(left: 100, top: 300, right: 500, bottom: 700)
        let roi = VisionGeometry.regionOfInterest(for: region, frameWidth: w, frameHeight: h)
        // The body's centre at pixel (300, 500) is the middle of the crop, which Vision reports as
        // (0.5, 0.5) relative to the crop.
        let p = VisionGeometry.pixel(x: 0.5, y: 0.5, roi: roi, frameWidth: w, frameHeight: h)
        XCTAssertEqual(p.x, 300, accuracy: 0.01)
        XCTAssertEqual(p.y, 500, accuracy: 0.01)
    }
}
