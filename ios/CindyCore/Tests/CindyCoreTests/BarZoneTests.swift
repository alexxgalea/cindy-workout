import XCTest
import CindyCore

/// What a bar is learned from.
///
/// Mirrors `BarZoneTest.kt`. A grip is about a shoulder's width and a shoulder is about one torso
/// wide: on the recorded sessions the wrists of a real hang were 0.6 to 1.0 torso apart. Four of them
/// learned their bar at a moment when one wrist was read on top of the other, 3 to 6 px apart, which
/// put the centre of the bar on one hand and left the other hand outside it for the rest of the
/// session (see `StuckCalibrationTests`).
final class BarZoneTests: XCTestCase {

    private func wrist(_ x: Float, _ y: Float = 300) -> Keypoint { Keypoint(x: x, y: y, score: 0.9) }

    /// a bar learned while one wrist was read on top of the other still holds the real grip
    func testABarLearnedWhileOneWristWasReadOnTopOfTheOtherStillHoldsTheRealGrip() {
        let zone = BarZone()
        // The hands' midpoint is where the wrists were read: both at x = 360, 1.5 px either side.
        zone.observeHang(handsX: 360, handsY: 300, halfGrip: 1.5, torso: 80)

        // The real grip: a shoulder's width, 0.8 of a torso, with the left hand off to the left.
        XCTAssertTrue(zone.holds(left: wrist(360 - 0.8 * 80), right: wrist(360), torso: 80))
    }

    /// the allowance for such a grip scales with the athlete
    func testTheAllowanceForSuchAGripScalesWithTheAthlete() {
        let zone = BarZone()
        zone.observeHang(handsX: 360, handsY: 300, halfGrip: 1.5, torso: 40)

        XCTAssertTrue(zone.holds(left: wrist(360 - 0.8 * 40), right: wrist(360), torso: 40),
                      "the same grip on an athlete half as big")
        XCTAssertFalse(zone.holds(left: wrist(100), right: wrist(140), torso: 40),
                       "but not a hand on the far side of the frame")
    }

    /// a grip that was seen wide is not widened further
    func testAGripThatWasSeenWideIsNotWidenedFurther() {
        let zone = BarZone()
        zone.observeHang(handsX: 360, handsY: 300, halfGrip: 60, torso: 80)

        XCTAssertTrue(zone.holds(left: wrist(300), right: wrist(420), torso: 80))
        // 60 px of grip and 0.6 of a torso either side: a hand 120 px out is past the bar.
        XCTAssertFalse(zone.holds(left: wrist(240), right: wrist(480), torso: 80))
    }
}
