import XCTest
import CindyCore
import CindyFixtures

///
/// A relaxed bottom, and nothing else relaxed: the head still has to clear the bar, the hands
/// still have to be on it, and RepCounter still wants the athlete's whole learned travel.
/// Carried over from the `CindyCoreChecks` executable: Assisted pull-up. Every check keeps its original wording as
/// its assertion message.
final class AssistedPullupTests: XCTestCase {

    func testAssistedPullUp() {
        let bottom: Float = 120
        let top: Float = 60

        func engineFor(_ pull: PullVariant) -> Rig {
            Rig(fixedExercise: .pullup, profile: CindyProfile(pull: pull))
        }

        var r = engineFor(.bandAssistedPullUp)
        r.hold(PoseFixtures.pullup(bottom), frames: 35)
        for _ in 0..<6 {
            r.hold(PoseFixtures.pullup(top), frames: 8)
            r.hold(PoseFixtures.pullup(bottom), frames: 8)
        }
        // The first cycle teaches the counter the athlete's range; the rest score.
        XCTAssertEqual(r.engine.reps, 5, "a band-assisted pull-up counts without a dead hang")

        // The same movement, in the mode that says it is a strict pull-up. Unchanged.
        r = engineFor(.strictPullUp)
        r.hold(PoseFixtures.pullup(bottom), frames: 35)
        for _ in 0..<6 {
            r.hold(PoseFixtures.pullup(top), frames: 8)
            r.hold(PoseFixtures.pullup(bottom), frames: 8)
        }
        XCTAssertEqual(r.engine.reps, 0, "the same reps score nothing in strict mode")

        // The gate that is not relaxed: pulling only partway is not a rep in either mode.
        r = engineFor(.bandAssistedPullUp)
        r.hold(PoseFixtures.pullup(bottom), frames: 35)
        for _ in 0..<6 {
            r.hold(PoseFixtures.pullup(95), frames: 8)
            r.hold(PoseFixtures.pullup(bottom), frames: 8)
        }
        XCTAssertEqual(r.engine.reps, 0, "a band-assisted pull-up still requires the head over the bar")

        // And the bar itself is still a gate: arms overhead a long way from where the bar was
        // learned do not score, assisted or not.
        r = engineFor(.bandAssistedPullUp)
        r.hold(PoseFixtures.pullup(bottom), frames: 35)
        let before = r.engine.reps
        for _ in 0..<6 {
            for angle in [top, bottom] {
                var offBar = PoseFixtures.pullup(angle)
                for i in offBar.indices where offBar[i].score > 0 {
                    offBar[i] = Keypoint(x: offBar[i].x + 900, y: offBar[i].y, score: offBar[i].score)
                }
                r.hold(offBar, frames: 8)
            }
        }
        XCTAssertEqual(r.engine.reps, before, "overhead movement away from the bar does not count")

        // An inverted row satisfies every pull-up gate but one: the wrists are above the hips, the
        // bar can be learned from the hands, the head reaches the bar line and the elbow swings a
        // full range. Only the torso's direction separates the families.
        for variant in [PullVariant.strictPullUp, .bandAssistedPullUp] {
            let rows = engineFor(variant)
            rows.hold(PoseFixtures.pullup(bottom), frames: 35)
            for _ in 0..<6 {
                rows.hold(PoseFixtures.invertedRow(top), frames: 8)
                rows.hold(PoseFixtures.invertedRow(bottom), frames: 8)
            }
            XCTAssertEqual(rows.engine.reps, 0, "inverted rows never count as \(variant.label)")
        }
        let rowBar = engineFor(.strictPullUp)
        for _ in 0..<6 {
            rowBar.hold(PoseFixtures.invertedRow(top), frames: 8)
            rowBar.hold(PoseFixtures.invertedRow(bottom), frames: 8)
        }
        XCTAssertEqual(rowBar.engine.barKnown, false, "and an inverted row teaches no bar")

        // The gate is on orientation, not stillness: a wobble mid-rep is absorbed by the same
        // dropout window that already rides out an occlusion.
        let wobble = engineFor(.bandAssistedPullUp)
        wobble.hold(PoseFixtures.pullup(bottom), frames: 35)
        for _ in 0..<2 {
            wobble.hold(PoseFixtures.pullup(top), frames: 8)
            wobble.hold(PoseFixtures.pullup(bottom), frames: 8)
        }
        let beforeWobble = wobble.engine.reps
        wobble.hold(PoseFixtures.pullup(bottom), frames: 8)
        wobble.hold(PoseFixtures.invertedRow(bottom), frames: 4)
        wobble.hold(PoseFixtures.pullup(top), frames: 8)
        XCTAssertEqual(wobble.engine.reps, beforeWobble + 1, "a brief wobble does not throw away a rep")

        // Setting the band up must not teach a bar. Found on real footage: standing holding the
        // band at chest height satisfies every other condition the bar was learned from, so the bar
        // was fixed at the athlete's chest and every real rep afterwards was refused with "Get on
        // the bar" with no way back, since refinement requires already passing the gate.
        let bandSetup = engineFor(.bandAssistedPullUp)
        bandSetup.hold(PoseFixtures.bandSetup(), frames: 60)
        XCTAssertEqual(bandSetup.engine.barKnown, false, "holding a band at chest height teaches no bar")
        bandSetup.hold(PoseFixtures.pullup(bottom), frames: 35)
        XCTAssertEqual(bandSetup.engine.barKnown, true, "the real hang afterwards still finds it")
        for _ in 0..<6 {
            bandSetup.hold(PoseFixtures.pullup(top), frames: 8)
            bandSetup.hold(PoseFixtures.pullup(bottom), frames: 8)
        }
        XCTAssertEqual(bandSetup.engine.reps, 5, "and the reps score normally after it")

        // Rep provenance: a tapped rep counts, and is remembered as tapped.
        let manual = engineFor(.footAssistedPullUp)
        manual.engine.manualRep()
        XCTAssertEqual(manual.engine.reps, 1, "a manual rep is recorded: reps")
        XCTAssertEqual(manual.engine.manualReps, 1, "a manual rep is recorded: manualReps")
        XCTAssertEqual(manual.engine.lastRepSource == .manual, true, "a manual rep is recorded: source")

        let undoRig = engineFor(.footAssistedPullUp)
        undoRig.engine.manualRep()
        undoRig.engine.manualRep()
        _ = undoRig.engine.undoRep()
        XCTAssertEqual(undoRig.engine.reps, 1, "undoing a tapped rep takes the rep back")
        XCTAssertEqual(undoRig.engine.manualReps, 1, "and takes the tap back too")

        let camera = engineFor(.bandAssistedPullUp)
        camera.hold(PoseFixtures.pullup(bottom), frames: 35)
        for _ in 0..<3 {
            camera.hold(PoseFixtures.pullup(top), frames: 8)
            camera.hold(PoseFixtures.pullup(bottom), frames: 8)
        }
        XCTAssertTrue(camera.engine.reps > 0, "the camera scored at least one")
        XCTAssertEqual(camera.engine.manualReps, 0, "a rep the camera scored is not counted as manual")
        XCTAssertEqual(camera.engine.lastRepSource == .auto, true, "and the source says so")
    }
}
