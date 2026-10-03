import XCTest
import CindyCore

/// What the burned-in recording shows, apart from what the screen shows.
///
/// The setup check used to leave the film reading "ROUND 1" and "0 / 5" over the two calibration
/// pull-ups, because nothing fed the recorder anything else while it ran. These pin every stage's
/// strings, that the count follows `Setup.reps` and never the workout's own count, and the
/// banner's three-second window.
///
/// Mirrors `RecordedHudTest.kt`.
final class RecordedHudTests: XCTestCase {

    private func setup(_ stage: SetupStage, reps: Int = 0) -> Setup {
        Setup(stage: stage, missing: [], reps: reps, range: 20, needed: 40)
    }

    /// framing shows a dash and the movement marked not scored
    func testFramingShowsADashAndTheMovementMarkedNotScored() {
        let hud = RecordedHud().forSetup(now: 0, setup: setup(.framing), label: "PULL-UPS")
        XCTAssertEqual(hud.clock, "SETUP")
        XCTAssertEqual(hud.round, "CALIBRATION")
        XCTAssertEqual(hud.label, "PULL-UPS · NOT SCORED")
        XCTAssertEqual(hud.count, "– / 2")
        XCTAssertNil(hud.banner)
    }

    /// framing shows the dash even once reps have been seen
    func testFramingShowsTheDashEvenOnceRepsHaveBeenSeen() {
        // Framing can recur mid-check (an arm leaves the shot, say) without the two reps already
        // banked disappearing from the engine, but the count still has to read as unknown.
        let hud = RecordedHud().forSetup(now: 0, setup: setup(.framing, reps: 1), label: "PULL-UPS")
        XCTAssertEqual(hud.count, "– / 2")
    }

    /// moving counts the calibration reps against the constant
    func testMovingCountsTheCalibrationRepsAgainstTheConstant() {
        let hud = RecordedHud().forSetup(now: 0, setup: setup(.moving, reps: 1), label: "PULL-UPS")
        XCTAssertEqual(hud.count, "1 / 2")
    }

    /// poor still shows the calibration count
    func testPoorStillShowsTheCalibrationCount() {
        let hud = RecordedHud().forSetup(now: 0, setup: setup(.poor, reps: 0), label: "PULL-UPS")
        XCTAssertEqual(hud.count, "0 / 2")
        XCTAssertEqual(hud.label, "PULL-UPS · NOT SCORED")
    }

    /// ready shows the finished calibration count
    func testReadyShowsTheFinishedCalibrationCount() {
        let hud = RecordedHud().forSetup(now: 0, setup: setup(.ready, reps: 2), label: "PULL-UPS")
        XCTAssertEqual(hud.count, "2 / 2")
    }

    /// a null setup reads the same as framing
    func testANullSetupReadsTheSameAsFraming() {
        // The one frame that can be rendered before the analysis thread has produced its first
        // setup reading.
        let hud = RecordedHud().forSetup(now: 0, setup: nil, label: "PULL-UPS")
        XCTAssertEqual(hud.clock, "SETUP")
        XCTAssertEqual(hud.round, "CALIBRATION")
        XCTAssertEqual(hud.count, "– / 2")
    }

    /// the setup count follows Setup reps, never the workout count
    func testTheSetupCountFollowsSetupRepsNeverTheWorkoutCount() {
        let hud = RecordedHud()
        hud.workout(rounds: 6, reps: 4, target: 5)
        let text = hud.forSetup(now: 0, setup: setup(.moving, reps: 1), label: "PULL-UPS")
        XCTAssertEqual(text.count, "1 / 2")
        XCTAssertEqual(text.round, "CALIBRATION")
    }

    /// workout strings are unchanged
    func testWorkoutStringsAreUnchanged() {
        let hud = RecordedHud()
        hud.workout(rounds: 3, reps: 3, target: 5)
        let text = hud.forWorkout(now: 0, clock: "12:34", label: "PULL-UPS")
        XCTAssertEqual(text.clock, "12:34")
        XCTAssertEqual(text.round, "ROUND 4")
        XCTAssertEqual(text.label, "PULL-UPS")
        XCTAssertEqual(text.count, "3 / 5")
        XCTAssertNil(text.banner)
    }

    /// before any workout score arrives the film defaults the same way the screen does
    func testBeforeAnyWorkoutScoreArrivesTheFilmDefaultsTheSameWayTheScreenDoes() {
        let text = RecordedHud().forWorkout(now: 0, clock: "20:00", label: "PULL-UPS")
        XCTAssertEqual(text.round, "ROUND 1")
        XCTAssertEqual(text.count, "0 / 5")
    }

    /// the calibrated banner is shown for three seconds and then gone
    func testTheCalibratedBannerIsShownForThreeSecondsAndThenGone() {
        let hud = RecordedHud()
        hud.calibrated(now: 1_000)
        XCTAssertEqual(hud.forWorkout(now: 1_000, clock: "20:00", label: "PULL-UPS").banner, "CALIBRATED · 2 REPS")
        XCTAssertEqual(hud.forWorkout(now: 1_000 + 2_999, clock: "20:00", label: "PULL-UPS").banner, "CALIBRATED · 2 REPS")
        XCTAssertNil(hud.forWorkout(now: 1_000 + 3_000, clock: "20:00", label: "PULL-UPS").banner)
    }

    /// the skipped banner reads differently and times out the same way
    func testTheSkippedBannerReadsDifferentlyAndTimesOutTheSameWay() {
        let hud = RecordedHud()
        hud.skipped(now: 0)
        XCTAssertEqual(hud.forWorkout(now: 0, clock: "20:00", label: "PULL-UPS").banner, "CALIBRATION SKIPPED")
        XCTAssertEqual(hud.forWorkout(now: 2_999, clock: "20:00", label: "PULL-UPS").banner, "CALIBRATION SKIPPED")
        XCTAssertNil(hud.forWorkout(now: 3_000, clock: "20:00", label: "PULL-UPS").banner)
    }

    /// a banner showing when the setup HUD is asked for shows there too
    func testABannerShowingWhenTheSetupHUDIsAskedForShowsThereToo() {
        let hud = RecordedHud()
        hud.calibrated(now: 0)
        let text = hud.forSetup(now: 0, setup: setup(.ready, reps: 2), label: "PULL-UPS")
        XCTAssertEqual(text.banner, "CALIBRATED · 2 REPS")
    }

    /// no banner before one is triggered
    func testNoBannerBeforeOneIsTriggered() {
        XCTAssertNil(RecordedHud().forWorkout(now: 0, clock: "20:00", label: "PULL-UPS").banner)
    }
}
