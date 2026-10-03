import XCTest

/// Drives the real app in the simulator against a scripted body (`ReplayPoseSource`), because the
/// simulator has no camera. This is the whole path a workout takes: the setup check, the clock,
/// the engine, the HUD, saving, and the results screen.
final class CindyTrackerUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchReplaying(_ script: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-CindyReplay", script]
        app.launch()
        return app
    }

    func testReplayedPullUpsAreCountedAndSaved() {
        let app = launchReplaying("pullups")

        let start = app.buttons["START"]
        XCTAssertTrue(start.waitForExistence(timeout: 10), "the camera screen opens with START")
        start.tap()

        // The setup check reads the first two pull-ups as calibration, then starts the workout
        // by itself, which is when START turns into PAUSE.
        XCTAssertTrue(app.buttons["PAUSE"].waitForExistence(timeout: 30),
                      "two calibration reps get the workout going")

        // After calibration the count restarts at zero; a scored pull-up moves it on.
        let reps = app.staticTexts["repCount"]
        XCTAssertTrue(reps.waitForExistence(timeout: 5), "the rep count is on screen")
        let counted = expectation(
            for: NSPredicate(format: "NOT (label BEGINSWITH '0 / ')"),
            evaluatedWith: reps
        )
        wait(for: [counted], timeout: 40)

        app.buttons["STOP"].tap()
        let end = app.buttons["End"]
        XCTAssertTrue(end.waitForExistence(timeout: 5), "stopping asks first")
        end.tap()

        XCTAssertTrue(app.buttons["DONE"].waitForExistence(timeout: 10),
                      "the results screen follows")
    }
}
