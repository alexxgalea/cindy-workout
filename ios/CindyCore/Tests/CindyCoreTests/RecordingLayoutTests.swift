import XCTest
import CindyCore

/// Where the film puts its words. The rule worth a test is the one that failed on Android: text is
/// laid out inside the part of the frame the file keeps, never the frame, whose edges fill-centre
/// cuts off. Android's overlay had no test of its own for this; the safe-area calculation it leans
/// on is in `OverlayTransformTests`.
final class RecordingLayoutTests: XCTestCase {

    /// Ten units a character, so a width is easy to read off.
    private let measure: RecordingLayout.Measure = { text, size in Float(text.count) * size * 0.5 }

    private func hud(banner: String? = nil) -> RecordedHudText {
        RecordedHudText(clock: "19:42", round: "ROUND 2", label: "PUSH-UPS", count: "4 / 10", banner: banner)
    }

    /// the safe area of a 3:4 analysis frame in a 9:16 file: an eighth cut from each side
    private var safe: SourceRect {
        OverlayTransform.visibleSource(srcWidth: 720, srcHeight: 960, bufferWidth: 720, bufferHeight: 1280,
                                       rotationDegrees: 0)
    }

    private func text(_ layout: RecordingLayout, _ words: String) -> RecordingLayout.Text {
        layout.texts.first { $0.text == words }!
    }

    /// the safe area really is narrower than the frame, or none of the rest proves anything
    func testTheSafeAreaIsNarrowerThanTheFrame() {
        XCTAssertEqual(safe.left, 90, accuracy: 0.01)
        XCTAssertEqual(safe.right, 630, accuracy: 0.01)
        XCTAssertEqual(safe.top, 0, accuracy: 0.01)
        XCTAssertEqual(safe.bottom, 960, accuracy: 0.01)
    }

    /// every panel sits inside the safe area, so nothing is cut from the file
    func testEveryPanelSitsInsideTheSafeArea() {
        let layout = RecordingLayout.make(hud: hud(banner: "CALIBRATED · 2 REPS"), safe: safe, measure: measure)
        XCTAssertEqual(layout.panels.count, 4)
        for panel in layout.panels {
            XCTAssertGreaterThanOrEqual(panel.rect.left, safe.left, "a panel reaches the cropped strip on the left")
            XCTAssertLessThanOrEqual(panel.rect.right, safe.right, "a panel reaches the cropped strip on the right")
            XCTAssertGreaterThanOrEqual(panel.rect.top, safe.top)
            XCTAssertLessThanOrEqual(panel.rect.bottom, safe.bottom)
        }
    }

    /// every word's anchor is inside the safe area too
    func testEveryWordIsAnchoredInsideTheSafeArea() {
        let layout = RecordingLayout.make(hud: hud(banner: "CALIBRATION SKIPPED"), safe: safe, measure: measure)
        for word in layout.texts {
            XCTAssertGreaterThanOrEqual(word.x, safe.left, "\(word.text) starts in the cropped strip")
            XCTAssertLessThanOrEqual(word.x, safe.right, "\(word.text) starts in the cropped strip")
        }
    }

    /// the clock is top left, the round top right, the movement and count bottom left
    func testTheCornersHoldWhatTheyAlwaysHeld() {
        let layout = RecordingLayout.make(hud: hud(), safe: safe, measure: measure)
        let clock = text(layout, "19:42"), round = text(layout, "ROUND 2")
        let label = text(layout, "PUSH-UPS"), count = text(layout, "4 / 10")
        XCTAssertEqual(clock.align, .left)
        XCTAssertLessThan(clock.x, safe.left + safe.width / 2)
        XCTAssertLessThan(clock.baseline, safe.top + safe.height / 4)
        XCTAssertEqual(round.align, .right)
        XCTAssertGreaterThan(round.x, safe.left + safe.width / 2)
        XCTAssertLessThan(round.baseline, safe.top + safe.height / 4)
        XCTAssertLessThan(label.x, safe.left + safe.width / 2)
        XCTAssertGreaterThan(label.baseline, safe.top + safe.height * 0.75)
        XCTAssertGreaterThan(count.baseline, label.baseline, "the count sits under its label")
    }

    /// sizes follow the safe area's height, so a taller file does not shrink the words
    func testSizesFollowTheSafeAreasHeight() {
        let layout = RecordingLayout.make(hud: hud(), safe: safe, measure: measure)
        XCTAssertEqual(text(layout, "19:42").size, 960 * 0.045, accuracy: 0.001)
        XCTAssertEqual(text(layout, "ROUND 2").size, 960 * 0.025, accuracy: 0.001)
        XCTAssertEqual(text(layout, "CINDY").size, 960 * 0.030, accuracy: 0.001)
    }

    /// a panel is as wide as its words plus a pad each side
    func testAPanelIsAsWideAsItsWords() {
        let layout = RecordingLayout.make(hud: hud(), safe: safe, measure: measure)
        let pad = safe.height * 0.018
        let clockPanel = layout.panels[0].rect
        XCTAssertEqual(clockPanel.width, pad + measure("19:42", safe.height * 0.045), accuracy: 0.01)
        XCTAssertEqual(clockPanel.left, safe.left + pad, accuracy: 0.01)
    }

    /// the block takes the wider of its two lines
    func testTheBlockTakesTheWiderOfItsTwoLines() {
        let wideLabel = RecordedHudText(clock: "SETUP", round: "CALIBRATION",
                                        label: "PULL-UPS · NOT SCORED", count: "– / 2", banner: nil)
        let layout = RecordingLayout.make(hud: wideLabel, safe: safe, measure: measure)
        let pad = safe.height * 0.018
        let block = layout.panels[2].rect
        XCTAssertEqual(block.width, pad + measure("PULL-UPS · NOT SCORED", safe.height * 0.025), accuracy: 0.01)
    }

    /// no banner, no banner panel: three panels
    func testNoBannerNoPanelForIt() {
        let plain = RecordingLayout.make(hud: hud(), safe: safe, measure: measure)
        XCTAssertEqual(plain.panels.count, 3)
        XCTAssertNil(plain.texts.first { $0.text.contains("CALIBRAT") })
    }

    /// the banner is centred in the safe area, not in the frame
    func testTheBannerIsCentredInTheSafeArea() {
        let layout = RecordingLayout.make(hud: hud(banner: "CALIBRATED · 2 REPS"), safe: safe, measure: measure)
        let banner = text(layout, "CALIBRATED · 2 REPS")
        XCTAssertEqual(banner.align, .center)
        XCTAssertEqual(banner.x, safe.left + safe.width / 2, accuracy: 0.01)
        let panel = layout.panels.last!.rect
        XCTAssertEqual((panel.left + panel.right) / 2, banner.x, accuracy: 0.01)
        XCTAssertLessThan(panel.top, safe.top + safe.height / 2)
        XCTAssertGreaterThan(panel.bottom, safe.top + safe.height / 2)
    }

    /// the watermark is bottom right, the second line under the first
    func testTheWatermarkIsBottomRight() {
        let layout = RecordingLayout.make(hud: hud(), safe: safe, measure: measure)
        let mark = text(layout, "CINDY"), sub = text(layout, "cindy tracker")
        XCTAssertEqual(mark.align, .right)
        XCTAssertEqual(mark.x, sub.x, accuracy: 0.001)
        XCTAssertLessThan(mark.x, safe.right)
        XCTAssertLessThan(mark.baseline, sub.baseline)
        XCTAssertLessThan(sub.baseline, safe.bottom)
        XCTAssertEqual(mark.tone, .accent)
        XCTAssertEqual(sub.tone, .faint)
    }

    /// the stroke fractions are the live overlay's, which the film is held to
    func testTheStrokeIsTheLiveOverlays() {
        XCTAssertEqual(RecordingLayout.boneWidthFraction, 0.0045, accuracy: 1e-6)
        XCTAssertEqual(RecordingLayout.jointRadiusFraction, 0.0055, accuracy: 1e-6)
        XCTAssertEqual(RecordingLayout.minScore, 0.30, accuracy: 1e-6)
    }

    /// laid out on the frame instead of the safe area, the clock would sit in the cropped strip:
    /// the failure this type exists to prevent, shown so the first test above cannot pass by accident
    func testLaidOutOnTheFrameTheClockWouldBeCropped() {
        let frame = SourceRect(left: 0, top: 0, right: 720, bottom: 960)
        let wrong = RecordingLayout.make(hud: hud(), safe: frame, measure: measure)
        XCTAssertLessThan(wrong.panels[0].rect.left, safe.left)
    }
}
