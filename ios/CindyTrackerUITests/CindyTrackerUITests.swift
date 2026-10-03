import XCTest

/// Drives the real app in the simulator against a scripted body (`ReplayPoseSource`), because the
/// simulator has no camera. This is the whole path a workout takes: the placement guide, the setup
/// check and its outcomes, the clock, the engine, the HUD, the buttons, saving, and the results
/// screen.
final class CindyTrackerUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// `seenGuide` skips the placement guide, which one test looks at on its own.
    private func launchReplaying(_ script: String, seenGuide: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-CindyReplay", script, "-placementGuideSeen", seenGuide ? "YES" : "NO"]
        app.launch()
        return app
    }

    private func repCount(_ app: XCUIApplication) -> XCUIElement { app.staticTexts["repCount"] }
    private func exercise(_ app: XCUIApplication) -> XCUIElement { app.staticTexts["exerciseLabel"] }
    private func status(_ app: XCUIApplication) -> XCUIElement { app.staticTexts["status"] }

    /// Waits for `element`'s label to satisfy `format`.
    private func waitForLabel(_ element: XCUIElement, _ format: String, timeout: TimeInterval = 10,
                              file: StaticString = #filePath, line: UInt = #line) {
        let ok = expectation(for: NSPredicate(format: format), evaluatedWith: element)
        wait(for: [ok], timeout: timeout)
    }

    /// Starts a workout without calibrating: the setup check, then SKIP and its confirmation.
    /// Reps are then tapped in, which does not depend on what the body is doing.
    private func startSkippingSetup(_ app: XCUIApplication) {
        let start = app.buttons["START"]
        XCTAssertTrue(start.waitForExistence(timeout: 10), "the camera screen opens with START")
        start.tap()
        let skip = app.buttons["SKIP"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5), "START becomes SKIP during the setup check")
        skip.tap()
        // The confirmation has a SKIP of its own, on top of the HUD's.
        let sure = app.buttons.matching(NSPredicate(format: "label == 'SKIP'")).allElementsBoundByIndex.last!
        sure.tap()
        XCTAssertTrue(app.buttons["PAUSE"].waitForExistence(timeout: 5), "skipping starts the clock")
    }

    // MARK: - a whole session

    func testReplayedPullUpsAreCountedAndSaved() {
        let app = launchReplaying("pullups")

        let start = app.buttons["START"]
        XCTAssertTrue(start.waitForExistence(timeout: 10), "the camera screen opens with START")
        start.tap()

        // The setup check reads the first two pull-ups as calibration, then starts the workout
        // by itself, which is when SKIP turns into PAUSE.
        XCTAssertTrue(app.buttons["PAUSE"].waitForExistence(timeout: 30),
                      "two calibration reps get the workout going")

        // After calibration the count restarts at zero; a scored pull-up moves it on.
        XCTAssertTrue(repCount(app).waitForExistence(timeout: 5), "the rep count is on screen")
        waitForLabel(repCount(app), "NOT (label BEGINSWITH '0 / ')", timeout: 40)

        app.buttons["STOP"].tap()
        let end = app.buttons["End"]
        XCTAssertTrue(end.waitForExistence(timeout: 5), "stopping asks first")
        end.tap()

        XCTAssertTrue(app.buttons["DONE"].waitForExistence(timeout: 10),
                      "the results screen follows")
    }

    // MARK: - the placement guide

    func testThePlacementGuideComesFirstAndCanBeTurnedOff() {
        let app = launchReplaying("nohands", seenGuide: false)
        app.buttons["START"].tap()
        XCTAssertTrue(app.otherElements["placementGuide"].waitForExistence(timeout: 5)
                      || app.staticTexts["Where to put the phone"].waitForExistence(timeout: 5),
                      "the guide opens before the first setup check")
        XCTAssertTrue(app.staticTexts["Stand the phone up rather than laying it flat."].exists)
        app.buttons["CONTINUE"].tap()
        XCTAssertTrue(app.buttons["SKIP"].waitForExistence(timeout: 5), "and then the check begins")
    }

    // MARK: - the setup check's outcomes

    func testTheSetupCheckNamesWhatItCannotSee() {
        let app = launchReplaying("nohands")
        app.buttons["START"].tap()
        XCTAssertTrue(status(app).waitForExistence(timeout: 10))
        waitForLabel(status(app), "label CONTAINS[c] \"Can't see your\"")
        XCTAssertEqual(exercise(app).label, "SET UP")
    }

    func testTheSetupCheckSaysWhenTheMovementBarelyRegisters() {
        let app = launchReplaying("barely")
        app.buttons["START"].tap()
        waitForLabel(status(app), "label CONTAINS 'barely registers'", timeout: 60)
    }

    func testTheSetupCheckCanBeSkippedAfterBeingTold() {
        let app = launchReplaying("nohands")
        app.buttons["START"].tap()
        XCTAssertTrue(app.buttons["SKIP"].waitForExistence(timeout: 5))
        app.buttons["SKIP"].tap()
        XCTAssertTrue(app.staticTexts["Skip the setup check?"].waitForExistence(timeout: 5)
                      || app.buttons["KEEP CHECKING"].waitForExistence(timeout: 5),
                      "it says what skipping costs before doing it")
        app.buttons["KEEP CHECKING"].tap()
        XCTAssertTrue(app.buttons["SKIP"].exists, "keeping on checking leaves the check running")
        XCTAssertFalse(app.buttons["PAUSE"].exists)
    }

    // MARK: - the buttons

    func testPlusOneCountsARepAndMinusOneTakesItBack() {
        let app = launchReplaying("nohands")
        startSkippingSetup(app)
        XCTAssertTrue(repCount(app).label.hasPrefix("0 / 5"))
        app.buttons["+1"].tap()
        waitForLabel(repCount(app), "label BEGINSWITH '1 / 5'")
        app.buttons["−1"].tap()
        waitForLabel(repCount(app), "label BEGINSWITH '0 / 5'")
    }

    func testMinusOneStepsBackAcrossAMovementBoundary() {
        let app = launchReplaying("nohands")
        startSkippingSetup(app)
        for _ in 0..<5 { app.buttons["+1"].tap() }
        waitForLabel(exercise(app), "label == 'PUSH-UPS'")
        XCTAssertTrue(repCount(app).label.hasPrefix("0 / 10"))
        app.buttons["−1"].tap()
        waitForLabel(exercise(app), "label == 'PULL-UPS'")
        waitForLabel(repCount(app), "label BEGINSWITH '4 / 5'")
    }

    func testALongPressOnPlusOneSkipsToTheNextMovement() {
        let app = launchReplaying("nohands")
        startSkippingSetup(app)
        app.buttons["+1"].tap()
        app.buttons["+1"].press(forDuration: 1.2)
        waitForLabel(exercise(app), "label == 'PUSH-UPS'")
    }

    func testPausingParksTheClockAndResumingRestartsIt() {
        let app = launchReplaying("nohands")
        startSkippingSetup(app)
        app.buttons["PAUSE"].tap()
        XCTAssertTrue(app.buttons["RESUME"].waitForExistence(timeout: 5))
        waitForLabel(status(app), "label == 'Paused'")
        app.buttons["RESUME"].tap()
        XCTAssertTrue(app.buttons["PAUSE"].waitForExistence(timeout: 5))
        waitForLabel(status(app), "label != 'Paused'")
    }

    func testKeepingGoingAfterStopLetsTheClockRunAgain() {
        let app = launchReplaying("nohands")
        startSkippingSetup(app)
        app.buttons["STOP"].tap()
        XCTAssertTrue(app.buttons["Keep going"].waitForExistence(timeout: 5))
        app.buttons["Keep going"].tap()
        XCTAssertTrue(app.buttons["PAUSE"].waitForExistence(timeout: 5),
                      "the clock that was parked behind the question is running again")
    }
}
