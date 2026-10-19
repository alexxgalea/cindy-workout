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

    /// A button of the Cindy sheet, found by its label.
    private func sheetButton(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
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
        XCTAssertTrue(app.buttons["MENU"].waitForExistence(timeout: 10))
        app.buttons["MENU"].tap()
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
        XCTAssertTrue(app.buttons["START"].waitForExistence(timeout: 10))
        app.buttons["START"].tap()
        XCTAssertTrue(app.buttons["SKIP"].waitForExistence(timeout: 5))
        app.buttons["SKIP"].tap()
        XCTAssertTrue(app.otherElements["cindySheet"].waitForExistence(timeout: 5))
        capture(app, "question-skip")
        sheetButton(app, "SKIP").tap()

        // Stopping, then keeping going.
        XCTAssertTrue(app.buttons["PAUSE"].waitForExistence(timeout: 5))
        app.buttons["+1"].tap()
        app.buttons["+1"].tap()
        app.buttons["STOP"].tap()
        XCTAssertTrue(app.otherElements["cindySheet"].waitForExistence(timeout: 5))
        capture(app, "question-stop")
        sheetButton(app, "KEEP GOING").tap()

        // Ending, then discarding the saved session.
        XCTAssertTrue(app.buttons["PAUSE"].waitForExistence(timeout: 5))
        app.buttons["STOP"].tap()
        XCTAssertTrue(sheetButton(app, "END").waitForExistence(timeout: 5))
        sheetButton(app, "END").tap()
        XCTAssertTrue(app.buttons["DISCARD"].waitForExistence(timeout: 10))
        app.buttons["DISCARD"].tap()
        XCTAssertTrue(sheetButton(app, "KEEP IT").waitForExistence(timeout: 5))
        capture(app, "question-discard")
    }
}
