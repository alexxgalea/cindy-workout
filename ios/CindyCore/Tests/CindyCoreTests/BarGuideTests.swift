import XCTest
import CindyCore
import CindyFixtures

/// The drawn pull-up gate.
///
/// An overlay that disagrees with the gate is worse than no overlay: it would have the athlete
/// correcting towards a box that is not the one refusing their reps. These tests pin the drawing
/// to the same geometry `BarZone.holds` tests.
///
/// Mirrors `BarGuideTest.kt`.
final class BarGuideTests: XCTestCase {

    private var clock: Int64 = 0

    private func hold(_ e: WorkoutEngine, _ pose: [Keypoint], frames: Int = 10) {
        for _ in 0..<frames {
            _ = e.onFrame(pose, now: clock)
            clock += 100
        }
    }

    private func holds(_ b: BarZone.Bounds, _ p: Keypoint) -> Bool {
        p.x >= b.left && p.x <= b.right && p.y >= b.top && p.y <= b.bottom
    }

    /// there is nothing to draw until a dead hang marks the bar
    func testThereIsNothingToDrawUntilADeadHangMarksTheBar() {
        let e = WorkoutEngine()
        XCTAssertNil(e.barGuide)
        hold(e, PoseFixtures.pullup(60))
        XCTAssertNil(e.barGuide, "bent arms teach nothing about where the bar is")
        hold(e, PoseFixtures.pullup(170))
        XCTAssertNotNil(e.barGuide)
    }

    /// the box that is drawn is the box that is tested
    func testTheBoxThatIsDrawnIsTheBoxThatIsTested() {
        let zone = BarZone()
        zone.observeHang(handsX: 0, handsY: 0, halfGrip: 20)
        let torso: Float = 100
        let bounds = zone.bounds(torso: torso)!

        var disagreements = 0
        var inside = 0
        for dx in stride(from: -300, through: 300, by: 25) {
            for dy in stride(from: -200, through: 200, by: 25) {
                let left = Keypoint(x: Float(dx) - 10, y: Float(dy), score: 0.9)
                let right = Keypoint(x: Float(dx) + 10, y: Float(dy), score: 0.9)
                let drawn = holds(bounds, left) && holds(bounds, right)
                if drawn { inside += 1 }
                if drawn != zone.holds(left: left, right: right, torso: torso) { disagreements += 1 }
            }
        }
        XCTAssertEqual(disagreements, 0, "the drawing and the gate must agree everywhere")
        XCTAssertTrue((1..<25 * 17).contains(inside), "the sweep has to actually cross the boundary")
    }

    /// the box grows with the athlete's distance from the camera
    func testTheBoxGrowsWithTheAthletesDistanceFromTheCamera() {
        let zone = BarZone()
        zone.observeHang(handsX: 0, handsY: 0, halfGrip: 20)
        let near = zone.bounds(torso: 200)!
        let far = zone.bounds(torso: 50)!
        XCTAssertGreaterThan(near.bottom - near.top, far.bottom - far.top)
        XCTAssertGreaterThan(near.right - near.left, far.right - far.left)
        XCTAssertEqual(near.lineY, far.lineY, accuracy: 0.001, "the bar itself does not move")
    }

    /// the reset line sits a quarter of a torso below the bar
    func testTheResetLineSitsAQuarterOfATorsoBelowTheBar() {
        let e = WorkoutEngine()
        hold(e, PoseFixtures.pullup(170))
        let guide = e.barGuide!
        // The fixture's shoulders and hips are exactly one torso apart, and the engine's
        // head-reset share is 0.25 — private, so it is restated rather than read.
        XCTAssertEqual(guide.resetY, guide.zone.lineY + 0.25 * PoseFixtures.torso, accuracy: 0.01)
    }

    /// stepping off the bar shuts the gate without moving it
    func testSteppingOffTheBarShutsTheGateWithoutMovingIt() {
        let e = WorkoutEngine()
        hold(e, PoseFixtures.pullup(170))
        let onBar = e.barGuide!
        XCTAssertTrue(onBar.gateOpen)

        // Same body, same scale, well below the bar: the estimate stands, the gate does not.
        hold(e, PoseFixtures.pullup(170).moved(dx: 0, dy: 400))
        let offBar = e.barGuide!
        XCTAssertFalse(offBar.gateOpen)
        XCTAssertEqual(offBar.zone.lineY, onBar.zone.lineY, accuracy: 0.01,
                       "the athlete has to be able to see where to go back to")
    }

    /// a recalibration takes the gate off the screen with the bar
    func testARecalibrationTakesTheGateOffTheScreenWithTheBar() {
        let e = WorkoutEngine()
        hold(e, PoseFixtures.pullup(170))
        XCTAssertNotNil(e.barGuide)
        e.recalibrate()
        XCTAssertNil(e.barGuide, "the camera moved, so the drawn bar is a lie")
    }
}
