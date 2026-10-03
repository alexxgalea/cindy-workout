import XCTest
import CindyCore
import CindyFixtures

/// The band-assisted pull-up: a relaxed bottom, and nothing else relaxed.
///
/// The band takes enough weight that the arms may never straighten, so requiring a dead hang means
/// the reset never arms and the session scores zero with the counter working perfectly behind a
/// gate the athlete cannot open. What replaces it is the head dropping back below the reset line —
/// a torso-scaled offset the camera's viewpoint cannot flatten, and a position you cannot be in at
/// the top of a rep.
///
/// Everything else still applies, and these tests say so: the head still has to clear the bar, the
/// hands still have to be on it, and `RepCounter` still wants the athlete's whole learned travel. A
/// relaxed bottom buys a shallow rep nothing.
///
/// Mirrors `AssistedPullupTest.kt`; it replaces the old checks' "Assisted pull-up" class.
final class AssistedPullupTests: XCTestCase {

    /// As straight as this athlete gets, hanging in a band. Well under a dead hang.
    private let bottom: Float = 120
    private let top: Float = 60

    /// Long enough for the settle fallback to find the bar without a dead hang.
    private func findBar(_ d: Rig, _ angle: Float) {
        d.hold(PoseFixtures.pullup(angle), frames: 35)
    }

    private func cycles(_ d: Rig, _ n: Int, _ bottom: Float, _ top: Float) {
        for _ in 0..<n {
            d.hold(PoseFixtures.pullup(top), frames: 8)
            d.hold(PoseFixtures.pullup(bottom), frames: 8)
        }
    }

    private func engineFor(_ pull: PullVariant) -> Rig {
        Rig(fixedExercise: .pullup, profile: CindyProfile(pull: pull))
    }

    /// a band-assisted pull-up counts without a dead hang
    func testABandAssistedPullUpCountsWithoutADeadHang() {
        let d = engineFor(.bandAssistedPullUp)

        findBar(d, bottom)
        XCTAssertTrue(d.engine.barKnown)
        cycles(d, 6, bottom, top)

        // The first cycle teaches the counter the athlete's range; the rest score.
        XCTAssertEqual(d.engine.reps, 5)
    }

    /// The same movement, in the mode that says it is a strict pull-up. Unchanged.
    ///
    /// the same reps score nothing in strict mode
    func testTheSameRepsScoreNothingInStrictMode() {
        let d = engineFor(.strictPullUp)

        findBar(d, bottom)
        cycles(d, 6, bottom, top)

        XCTAssertEqual(d.engine.reps, 0)
    }

    /// The gate that is *not* relaxed.
    ///
    /// Pulling only partway, so the head never clears the bar, is not a rep in either mode. This is
    /// the check that the relaxed bottom did not quietly become a relaxed rep.
    ///
    /// a band-assisted pull-up still requires the head over the bar
    func testABandAssistedPullUpStillRequiresTheHeadOverTheBar() {
        let d = engineFor(.bandAssistedPullUp)

        findBar(d, bottom)
        // 95 degrees leaves the head below the bar line: a genuine partial.
        cycles(d, 6, bottom, 95)

        XCTAssertEqual(d.engine.reps, 0)
    }

    /// And the bar itself is still a gate: arms waving overhead away from where the bar was learned
    /// do not score, assisted or not.
    ///
    /// overhead movement away from the bar does not count
    func testOverheadMovementAwayFromTheBarDoesNotCount() {
        let d = engineFor(.bandAssistedPullUp)

        findBar(d, bottom)
        let before = d.engine.reps
        for _ in 0..<6 {
            for angle in [top, bottom] {
                // Same movement, done a long way to the side of the learned bar.
                let offBar = PoseFixtures.pullup(angle).map {
                    Keypoint(x: $0.x + 900, y: $0.y, score: $0.score)
                }
                d.hold(offBar, frames: 8)
            }
        }

        XCTAssertEqual(d.engine.reps, before)
    }

    /// Setting the band up must not teach a bar.
    ///
    /// Found on real footage: standing on a box holding the band at chest height satisfies every
    /// other condition the bar used to be learned from — hands above the hips, elbows extended — so
    /// the bar was fixed at the athlete's chest, and every real rep afterwards was refused with
    /// "Get on the bar" with no way back, because refinement requires already passing the gate.
    ///
    /// holding a band at chest height does not teach a bar
    func testHoldingABandAtChestHeightDoesNotTeachABar() {
        let d = engineFor(.bandAssistedPullUp)

        d.hold(PoseFixtures.bandSetup(), frames: 60)

        XCTAssertFalse(d.engine.barKnown, "the hands are below the head, so this is not a hang")
    }

    /// And a single frame of the head going missing must not teach one either.
    ///
    /// The guard that stops the band setup teaching a bar asks whether the hands are above the nose,
    /// and deliberately answers *yes* when the nose is not confidently seen — otherwise rear-view
    /// and occluded footage, which already counts, would be locked out. That turns a missing
    /// keypoint into permission, and one dropped frame is all it takes: found on the band fixture at
    /// one light level, where the nose fell below confidence on a single frame in sixty, a false bar
    /// was taught at the chest, and the whole clip then scored zero with 401 of 532 frames refused
    /// for "Get on the bar".
    ///
    /// one dropped head keypoint during the band setup does not teach a bar
    func testOneDroppedHeadKeypointDuringTheBandSetupDoesNotTeachABar() {
        let d = engineFor(.bandAssistedPullUp)
        var blind = PoseFixtures.bandSetup()
        blind[KP.nose] = Keypoint(x: blind[KP.nose].x, y: blind[KP.nose].y, score: 0.1)

        d.hold(PoseFixtures.bandSetup(), frames: 30)
        d.hold(blind, frames: 1)
        d.hold(PoseFixtures.bandSetup(), frames: 30)

        XCTAssertFalse(d.engine.barKnown, "one unseen nose is not evidence of a hang")
    }

    /// A rear view, where the head is never seen at all, still finds its bar — just not instantly.
    ///
    /// The counterweight to the test above: the relaxation exists for footage filmed from behind,
    /// and tightening it must not cost that. So the permission is still granted, it merely has to be
    /// *held* rather than taken from a single frame. A real dead hang lasts seconds and clears this
    /// without trying; the stray frame that taught a false bar never could.
    ///
    /// a hang filmed from behind still teaches the bar once it is held
    func testAHangFilmedFromBehindStillTeachesTheBarOnceItIsHeld() {
        var headless = PoseFixtures.pullup(175)
        headless[KP.nose] = Keypoint(x: headless[KP.nose].x, y: headless[KP.nose].y, score: 0.1)

        let brief = engineFor(.strictPullUp)
        brief.hold(headless, frames: 2)
        XCTAssertFalse(brief.engine.barKnown, "two frames is a dropout, not a hang")

        let held = engineFor(.strictPullUp)
        held.hold(headless, frames: 6)
        XCTAssertTrue(held.engine.barKnown, "a sustained hang with no visible head is still a hang")
    }

    /// A hang with the head plainly visible is believed at once, as it always was.
    ///
    /// a dead hang with the head in shot still teaches the bar on the first frame
    func testADeadHangWithTheHeadInShotStillTeachesTheBarOnTheFirstFrame() {
        let d = engineFor(.strictPullUp)

        d.hold(PoseFixtures.pullup(175), frames: 1)

        XCTAssertTrue(d.engine.barKnown, "seeing the head below the hands is evidence, not an absence")
    }

    /// And the bar the athlete then actually hangs from is still found normally.
    ///
    /// a hang after the band setup still finds the bar
    func testAHangAfterTheBandSetupStillFindsTheBar() {
        let d = engineFor(.bandAssistedPullUp)

        d.hold(PoseFixtures.bandSetup(), frames: 60)
        findBar(d, bottom)

        XCTAssertTrue(d.engine.barKnown, "the real hang teaches it")
        cycles(d, 6, bottom, top)
        XCTAssertEqual(d.engine.reps, 5, "and the reps score")
    }

    // ── the row is a different movement ───────────────────────────────────────
    //
    // An inverted row satisfies every pull-up gate but one: the wrists are above the hips, the bar
    // can be learned from the hands, the head reaches the bar line and the elbow swings a full
    // range. Only the torso's direction separates the families.

    /// inverted rows never count as strict pull-ups
    func testInvertedRowsNeverCountAsStrictPullUps() {
        let d = engineFor(.strictPullUp)

        findBar(d, bottom)
        for _ in 0..<6 {
            d.hold(PoseFixtures.invertedRow(top), frames: 8)
            d.hold(PoseFixtures.invertedRow(bottom), frames: 8)
        }

        XCTAssertEqual(d.engine.reps, 0)
        XCTAssertEqual(d.engine.hint, "Hang vertically from the bar", "and says which way to hang")
    }

    /// inverted rows never count as band-assisted pull-ups either
    func testInvertedRowsNeverCountAsBandAssistedPullUpsEither() {
        let d = engineFor(.bandAssistedPullUp)

        findBar(d, bottom)
        for _ in 0..<6 {
            d.hold(PoseFixtures.invertedRow(top), frames: 8)
            d.hold(PoseFixtures.invertedRow(bottom), frames: 8)
        }

        XCTAssertEqual(d.engine.reps, 0, "relaxing the bottom does not relax which movement it is")
    }

    /// A row must not teach a bar either, or it would poison the next real hang.
    ///
    /// an inverted row does not establish a bar
    func testAnInvertedRowDoesNotEstablishABar() {
        let d = engineFor(.strictPullUp)

        for _ in 0..<6 {
            d.hold(PoseFixtures.invertedRow(top), frames: 8)
            d.hold(PoseFixtures.invertedRow(bottom), frames: 8)
        }

        XCTAssertFalse(d.engine.barKnown)
    }

    /// The gate is on orientation, not on stillness: a wobble mid-rep is absorbed by the same
    /// dropout window that already rides out an occlusion, so a real pull-up survives it.
    ///
    /// a brief non-vertical wobble does not throw away a valid pull-up
    func testABriefNonVerticalWobbleDoesNotThrowAwayAValidPullUp() {
        let d = engineFor(.bandAssistedPullUp)

        findBar(d, bottom)
        cycles(d, 2, bottom, top)
        let before = d.engine.reps

        // Armed at the bottom, then four unusable frames — well inside the dropout limit — before
        // driving to the top. The cycle is in flight across the wobble.
        d.hold(PoseFixtures.pullup(bottom), frames: 8)
        d.hold(PoseFixtures.invertedRow(bottom), frames: 4)
        d.hold(PoseFixtures.pullup(top), frames: 8)

        XCTAssertEqual(d.engine.reps, before + 1, "the cycle across the wobble still scores")
    }

    // ── rep provenance ────────────────────────────────────────────────────────

    /// A tapped rep counts, and is remembered as tapped.
    ///
    /// The score is the athlete's either way; the *claim* about how it was arrived at is the app's,
    /// and it is not entitled to the stronger one.
    ///
    /// a manual rep is recorded as manual
    func testAManualRepIsRecordedAsManual() {
        let engine = engineFor(.footAssistedPullUp).engine

        _ = engine.manualRep()

        XCTAssertEqual(engine.reps, 1)
        XCTAssertEqual(engine.manualReps, 1)
        XCTAssertEqual(engine.lastRepSource, .manual)
    }

    /// undoing a tapped rep takes the tap back too
    func testUndoingATappedRepTakesTheTapBackToo() {
        let engine = engineFor(.footAssistedPullUp).engine

        _ = engine.manualRep()
        _ = engine.manualRep()
        _ = engine.undoRep()

        XCTAssertEqual(engine.reps, 1)
        XCTAssertEqual(engine.manualReps, 1)
    }

    /// a rep the camera scored is not counted as manual
    func testARepTheCameraScoredIsNotCountedAsManual() {
        let d = engineFor(.bandAssistedPullUp)

        findBar(d, bottom)
        cycles(d, 3, bottom, top)

        XCTAssertGreaterThan(d.engine.reps, 0, "the camera scored at least one")
        XCTAssertEqual(d.engine.manualReps, 0)
        XCTAssertEqual(d.engine.lastRepSource, .auto)
    }
}
