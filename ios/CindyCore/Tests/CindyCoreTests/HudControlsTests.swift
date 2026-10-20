import XCTest
import CindyCore

/// What each control of the camera screen is at each moment, from `renderControls`, `primary` and
/// `toggleRun` in `MainActivity.kt`, and the sentences a screen reader is given in their place.
final class HudControlsTests: XCTestCase {

    private let states: [WorkoutState] = [.idle, .setup, .running, .paused, .finished]

    /// the shutter is a mark that follows the state
    func testTheShutterIsAMarkThatFollowsTheState() {
        XCTAssertEqual(states.map { HudControls.of($0).shutter },
                       [.play, .play, .pause, .play, .again])
    }

    /// the shutter says what it does, and is inert only during the setup check
    func testTheShutterNamesWhatItDoes() {
        XCTAssertEqual(states.map { HudControls.of($0).shutterLabel },
                       ["Start the workout", "Start — available once the setup check finishes",
                        "Pause", "Resume", "Start again"])
        XCTAssertEqual(states.map { HudControls.of($0).shutterEnabled },
                       [true, false, true, true, true])
    }

    /// FLIP and END share a place: one of them at a time
    func testTheLeftSlotChangesHands() {
        XCTAssertEqual(states.map { HudControls.of($0).leftSlot },
                       [.flip, .flip, .end, .end, .flip])
    }

    /// the editors act on a count, which only moves while the clock runs
    func testTheEditorsActOnlyWhileTheClockRuns() {
        XCTAssertEqual(states.map { HudControls.of($0).editorsEnabled },
                       [false, false, true, false, false])
    }

    /// there is a movement to leave during the check and during the workout, and none otherwise
    func testSkipIsThereInTheCheckAndInTheWorkout() {
        XCTAssertEqual(states.map { HudControls.of($0).skipEnabled },
                       [false, true, true, true, false])
        XCTAssertEqual(HudControls.of(.setup).skipLabel, "Skip the setup check")
        for state in [WorkoutState.idle, .running, .paused, .finished] {
            XCTAssertEqual(HudControls.of(state).skipLabel, "Skip to the next movement")
        }
    }

    /// the names that never change
    func testTheFixedNames() {
        XCTAssertEqual(HudControls.flipLabel, "Switch camera")
        XCTAssertEqual(HudControls.endLabel, "End the workout")
        XCTAssertEqual(HudControls.undoLabel, "Take back a rep")
        XCTAssertEqual(HudControls.addLabel, "Add a rep")
        XCTAssertEqual(HudControls.menuLabel, "Menu: records, movements, music, body weight and help")
        XCTAssertEqual(HudControls.dimmed, 0.3)
    }
}

/// The sentences the camera screen's digits are given for a screen reader, which cannot say a
/// glyph like "2 / 5" or "20:00" well.
final class HudSpeechTests: XCTestCase {

    func testTheClockIsSaidAsTheTimeLeft() {
        XCTAssertEqual(HudSpeech.clock(remainingMs: 1_200_000),
                       PhrasebookEn().duration(1_200_000) + " remaining")
        XCTAssertEqual(HudSpeech.clock(remainingMs: 80_000),
                       PhrasebookEn().duration(80_000) + " remaining")
    }

    func testTheCountIsSaidAgainstItsTarget() {
        XCTAssertEqual(HudSpeech.reps(2, of: 5, movement: "pull-ups"), "2 of 5 pull-ups")
    }

    func testTheSetupCheckCountsCalibrationReps() {
        XCTAssertEqual(HudSpeech.setup(reps: 1, of: 2), "1 of 2 calibration reps")
        XCTAssertEqual(HudSpeech.settingUp, "Setting up")
    }

    func testTheRoundIsNamed() {
        XCTAssertEqual(HudSpeech.round(3), "Round 3")
    }
}
