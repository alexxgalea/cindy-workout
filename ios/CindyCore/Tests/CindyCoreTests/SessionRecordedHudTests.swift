import XCTest
import CindyCore

/// The session feeds the film's HUD, so the screen has nothing to remember about it. Android did the
/// same from `MainActivity`'s `apply`, `render` and its two ways of ending the setup check; the
/// hud's own wording is in `RecordedHudTests`.
final class SessionRecordedHudTests: XCTestCase {

    /// before anything has happened the film reads as a fresh workout
    func testAFreshSessionReadsAsAFreshWorkout() {
        let session = WorkoutSession()
        let hud = session.recordedHud(now: 1_000)
        XCTAssertEqual(hud.clock, "20:00")
        XCTAssertEqual(hud.round, "ROUND 1")
        XCTAssertEqual(hud.label, Exercise.pullup.label)
        XCTAssertEqual(hud.count, "0 / 5")
        XCTAssertNil(hud.banner)
    }

    /// during the setup check the film says SETUP and marks the movement not scored
    func testTheSetupCheckIsNotScored() {
        let session = WorkoutSession()
        _ = session.enterSetup()
        let hud = session.recordedHud(now: 1_000)
        XCTAssertEqual(hud.clock, "SETUP")
        XCTAssertEqual(hud.round, "CALIBRATION")
        XCTAssertEqual(hud.label, "\(Exercise.pullup.label) · NOT SCORED")
        XCTAssertEqual(hud.count, "– / 2", "before the first reading it reads as framing")
    }

    /// skipping the check starts the workout and the film says so for three seconds
    func testSkippingSaysSoForThreeSeconds() {
        let session = WorkoutSession()
        _ = session.enterSetup()
        _ = session.skipSetup(now: 10_000)
        XCTAssertEqual(session.recordedHud(now: 11_000).banner, "CALIBRATION SKIPPED")
        XCTAssertEqual(session.recordedHud(now: 12_999).banner, "CALIBRATION SKIPPED")
        XCTAssertNil(session.recordedHud(now: 13_000).banner)
        XCTAssertEqual(session.recordedHud(now: 11_000).clock, "20:00", "the workout's own clock is back")
    }

    /// a workout that never had a setup check has no banner
    func testNoBannerWithoutASetupCheck() {
        let session = WorkoutSession()
        _ = session.beginWorkout(calibrated: false, now: 1_000)
        XCTAssertNil(session.recordedHud(now: 1_500).banner)
    }

    /// a manual rep moves the film's count with the screen's
    func testARepMovesTheFilmsCount() {
        let session = WorkoutSession()
        _ = session.beginWorkout(calibrated: false, now: 1_000)
        _ = session.manualRep(now: 2_000)
        _ = session.manualRep(now: 2_100)
        XCTAssertEqual(session.recordedHud(now: 2_200).count, "2 / 5")
        XCTAssertEqual(session.recordedHud(now: 2_200).count, "\(session.repsText) / 5")
    }

    /// finishing a round turns the film's round over, as the screen's does
    func testARoundTurnsTheFilmsRoundOver() {
        let session = WorkoutSession()
        _ = session.beginWorkout(calibrated: false, now: 1_000)
        for i in 0..<30 { _ = session.manualRep(now: 2_000 + Int64(i) * 100) }
        XCTAssertEqual(session.rounds, 1)
        XCTAssertEqual(session.recordedHud(now: 6_000).round, "ROUND 2")
    }

    /// stepping back undoes the film's count as it does the screen's
    func testUndoTakesTheFilmsCountBack() {
        let session = WorkoutSession()
        _ = session.beginWorkout(calibrated: false, now: 1_000)
        _ = session.manualRep(now: 2_000)
        _ = session.undoRep(now: 2_100)
        XCTAssertEqual(session.recordedHud(now: 2_200).count, "0 / 5")
    }

    /// resetting puts the film back to a fresh workout
    func testResetPutsTheFilmBack() {
        let session = WorkoutSession()
        _ = session.beginWorkout(calibrated: false, now: 1_000)
        _ = session.manualRep(now: 2_000)
        _ = session.reset()
        let hud = session.recordedHud(now: 90_000)
        XCTAssertEqual(hud.count, "0 / 5")
        XCTAssertEqual(hud.round, "ROUND 1")
    }
}
