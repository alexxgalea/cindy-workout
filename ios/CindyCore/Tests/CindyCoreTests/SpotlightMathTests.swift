import XCTest
import CindyCore

/// Where the tour's caption card sits. Port of `SpotlightMathTest.kt`.
final class SpotlightMathTests: XCTestCase {

    private let gap: Float = 14
    private let margin: Float = 16
    private let screen: Float = 2400
    private let card: Float = 300

    private func top(_ targetTop: Float, _ targetBottom: Float, caption: Float? = nil, height: Float? = nil) -> Float {
        SpotlightMath.captionTop(targetTop: targetTop, targetBottom: targetBottom, captionHeight: caption ?? card,
                                 screenHeight: height ?? screen, gap: gap, margin: margin)
    }

    /// the caption goes below a target near the top, with a gap
    func testTheCaptionGoesBelowATargetNearTheTopWithAGap() {
        XCTAssertEqual(top(100, 200), 200 + gap, accuracy: 0)
    }

    /// it goes above a target too low to have room underneath
    func testItGoesAboveATargetTooLowToHaveRoomUnderneath() {
        // The target ends at 2300, so the card would run off the bottom. Above it instead.
        XCTAssertEqual(top(2200, 2300), 2200 - gap - card, accuracy: 0)
    }

    /// below is kept right up to the last pixel that fits
    func testBelowIsKeptRightUpToTheLastPixelThatFits() {
        let lowest = screen - margin - card
        let fits = lowest - gap          // a target bottom that leaves the card exactly on the margin
        XCTAssertEqual(top(fits - 100, fits), fits + gap, accuracy: 0)
        // One pixel lower and it no longer fits below, so it moves above.
        XCTAssertEqual(top(fits - 99, fits + 1), fits - 99 - gap - card, accuracy: 0)
    }

    /// above is kept right down to the margin
    func testAboveIsKeptRightDownToTheMargin() {
        // A target whose top leaves the card exactly on the top margin.
        let targetTop = margin + card + gap
        XCTAssertEqual(top(targetTop, screen - 10), margin, accuracy: 0)
    }

    /// on a short screen where neither side has room the caption stays on it
    func testOnAShortScreenWhereNeitherSideHasRoomTheCaptionStaysOnIt() {
        // 500 tall: a 300 card fits only between 16 and 184 from the bottom edge.
        let y = top(200, 300, height: 500)
        XCTAssertEqual(y, 500 - margin - card, accuracy: 0)
        XCTAssertTrue(y >= margin)
        XCTAssertTrue(y + card <= 500 - margin)
    }

    /// a caption taller than the screen starts at the margin rather than above it
    func testACaptionTallerThanTheScreenStartsAtTheMarginRatherThanAboveIt() {
        XCTAssertEqual(top(100, 200, caption: 900, height: 600), margin, accuracy: 0)
    }

    /// the caption is never placed off either end of the screen
    func testTheCaptionIsNeverPlacedOffEitherEndOfTheScreen() {
        for targetTop: Float in [0, 50, 400, 1200, 2000, 2350] {
            let y = top(targetTop, targetTop + 100)
            XCTAssertTrue(y >= margin, "top \(targetTop): \(y)")
            XCTAssertTrue(y + card <= screen - margin, "top \(targetTop): \(y + card)")
        }
    }

    /// it never lands on the target when there is room on either side
    func testItNeverLandsOnTheTargetWhenThereIsRoomOnEitherSide() {
        for targetTop: Float in [0, 50, 400, 1200, 1800, 2000, 2300] {
            let targetBottom = targetTop + 100
            let y = top(targetTop, targetBottom)
            let overlaps = y < targetBottom && y + card > targetTop
            XCTAssertTrue(!overlaps, "target \(targetTop)..\(targetBottom), card at \(y)")
        }
    }
}
