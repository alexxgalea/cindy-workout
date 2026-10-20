import XCTest

/// Photographs the states a screen was rebuilt for, under the names of their Android references
/// in `ios/ui-parity/android/`, so a capture and its reference can be laid side by side. These
/// check only that each state can be reached; the comparing is done by eye on the `ios-captures`
/// artifact the macOS job uploads.
final class CaptureTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ script: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-CindyReplay", script, "-placement_guide_dismissed", "YES",
                               "-tutorial_seen", "YES", "-hud_tour_pending", "NO"]
        app.launch()
        return app
    }

    /// Adds the screen to the test's results under `name`, kept whether the test passes or not.
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A control of the camera screen, found by the Android view's id, since the controls are marks
    /// with no word to find them by. `labelled` narrows it by its spoken name, which is how a state
    /// of the shutter is told from another.
    private func hud(_ app: XCUIApplication, _ id: String, labelled label: String? = nil) -> XCUIElement {
        var query = app.buttons.matching(identifier: id)
        if let label { query = query.matching(NSPredicate(format: "label == %@", label)) }
        return query.firstMatch
    }

    /// A button of the Cindy sheet, found by its label among the sheet's own two buttons: the
    /// controls beneath it can share a label (SKIP, DISCARD) and are still in the tree while it slides in.
    private func sheetButton(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "identifier IN {'sheetPrimary', 'sheetSecondary'} AND label == %@", label)).firstMatch
    }

    /// Swipes the screen up until something with this label is there, at most eight times.
    private func scroll(_ app: XCUIApplication, toLabelBeginning text: String) {
        let target = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
        var swipes = 0
        while !(target.exists && target.isHittable) && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(target.exists, "Help has \(text)")
    }

    func testHelp() {
        let app = launch("pullups")
        XCTAssertTrue(hud(app, "btnMenu").waitForExistence(timeout: 10))
        hud(app, "btnMenu").tap()
        let help = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Help'")).firstMatch
        XCTAssertTrue(help.waitForExistence(timeout: 5), "the menu has a Help row")
        help.tap()
        XCTAssertTrue(app.buttons["DONE"].waitForExistence(timeout: 5))

        scroll(app, toLabelBeginning: "Elite")
        capture(app, "help-tiers")
        scroll(app, toLabelBeginning: "Privacy policy")
        capture(app, "help-links")
    }

    func testQuestions() {
        // Skipping the setup check.
        var app = launch("nohands")
        XCTAssertTrue(hud(app, "btnStart", labelled: "Start the workout").waitForExistence(timeout: 10))
        hud(app, "btnStart", labelled: "Start the workout").tap()
        XCTAssertTrue(hud(app, "btnSkipExercise").waitForExistence(timeout: 5))
        hud(app, "btnSkipExercise").tap()
        XCTAssertTrue(sheetButton(app, "SKIP").waitForExistence(timeout: 5))
        capture(app, "question-skip")
        sheetButton(app, "SKIP").tap()

        // Stopping, then keeping going.
        XCTAssertTrue(hud(app, "btnStart", labelled: "Pause").waitForExistence(timeout: 5))
        hud(app, "btnAddRep").tap()
        hud(app, "btnAddRep").tap()
        hud(app, "btnEnd").tap()
        XCTAssertTrue(sheetButton(app, "END").waitForExistence(timeout: 5))
        capture(app, "question-stop")
        sheetButton(app, "KEEP GOING").tap()

        // Ending, then discarding the saved session.
        XCTAssertTrue(hud(app, "btnStart", labelled: "Pause").waitForExistence(timeout: 5))
        hud(app, "btnEnd").tap()
        XCTAssertTrue(sheetButton(app, "END").waitForExistence(timeout: 5))
        sheetButton(app, "END").tap()
        XCTAssertTrue(app.buttons["DISCARD"].waitForExistence(timeout: 10))
        app.buttons["DISCARD"].tap()
        XCTAssertTrue(sheetButton(app, "KEEP IT").waitForExistence(timeout: 5))
        capture(app, "question-discard")
    }
}
