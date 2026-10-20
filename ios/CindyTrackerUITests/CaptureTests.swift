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

    /// The camera screen in each of its states. The countdown is not here: it needs a camera that can
    /// film and the athlete's answer from Photos, which the simulator has neither of.
    func testCamera() {
        // The launch view is held up by a debug argument, and given time to draw its whole.
        var app = XCUIApplication()
        app.launchArguments = ["-CindyReplay", "nohands", "-placement_guide_dismissed", "YES",
                               "-tutorial_seen", "YES", "-hud_tour_pending", "NO",
                               "-CindyHoldLaunch", "YES"]
        app.launch()
        let launchView = app.descendants(matching: .any).matching(identifier: "launchView").firstMatch
        XCTAssertTrue(launchView.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2.5)
        capture(app, "camera-launch")
        app.terminate()

        app = launch("nohands")
        XCTAssertTrue(hud(app, "btnStart", labelled: "Start the workout").waitForExistence(timeout: 10))
        capture(app, "camera-idle")

        hud(app, "btnStart").tap()
        XCTAssertTrue(hud(app, "btnStart", labelled: "Start — available once the setup check finishes")
            .waitForExistence(timeout: 5))
        capture(app, "camera-setup")

        hud(app, "btnSkipExercise").tap()
        XCTAssertTrue(sheetButton(app, "SKIP").waitForExistence(timeout: 5))
        sheetButton(app, "SKIP").tap()
        XCTAssertTrue(hud(app, "btnStart", labelled: "Pause").waitForExistence(timeout: 5))
        capture(app, "camera-running")

        // A body in frame but not in position is shown how, on a card that stands in for the status line.
        let card = app.descendants(matching: .any).matching(identifier: "coachCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1.5)
        capture(app, "camera-coach")

        hud(app, "btnStart").tap()
        XCTAssertTrue(hud(app, "btnStart", labelled: "Resume").waitForExistence(timeout: 5))
        capture(app, "camera-paused")
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

    /// Starts a workout without calibrating, adds `reps` by hand, ends it, and leaves the session
    /// page up.
    private func finishSession(_ app: XCUIApplication, reps: Int) {
        let start = hud(app, "btnStart", labelled: "Start the workout")
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        XCTAssertTrue(hud(app, "btnSkipExercise").waitForExistence(timeout: 5))
        hud(app, "btnSkipExercise").tap()
        XCTAssertTrue(sheetButton(app, "SKIP").waitForExistence(timeout: 5))
        sheetButton(app, "SKIP").tap()
        XCTAssertTrue(hud(app, "btnStart", labelled: "Pause").waitForExistence(timeout: 5))
        for _ in 0..<reps { hud(app, "btnAddRep").tap() }
        hud(app, "btnEnd").tap()
        XCTAssertTrue(sheetButton(app, "END").waitForExistence(timeout: 5))
        sheetButton(app, "END").tap()
        XCTAssertTrue(app.buttons["DONE"].waitForExistence(timeout: 10))
    }

    /// The session page: one ended with nothing counted, then one with reps that has the first to be
    /// compared with. The heart-rate block needs a watch's trace, which the simulator cannot give.
    func testSessionPage() {
        let app = launch("nohands")
        finishSession(app, reps: 0)
        capture(app, "session-stopped")
        app.buttons["DONE"].tap()

        let again = hud(app, "btnStart", labelled: "Start again")
        XCTAssertTrue(again.waitForExistence(timeout: 10))
        again.tap()
        finishSession(app, reps: 2)
        capture(app, "session-finished")

        let compared = app.staticTexts["COMPARED WITH"]
        var swipes = 0
        while !compared.exists && swipes < 12 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(compared.exists, "the second session offers a comparison")
        let open = app.buttons["compareCard"]
        XCTAssertTrue(open.waitForExistence(timeout: 5), "the comparison card is a button")
        open.tap()
        XCTAssertTrue(app.buttons["DONE"].waitForExistence(timeout: 5))
        capture(app, "session-reopened-compared")
    }

    /// Opens Progress from the menu, over the camera screen.
    private func openProgress(_ app: XCUIApplication) {
        XCTAssertTrue(hud(app, "btnMenu").waitForExistence(timeout: 10))
        hud(app, "btnMenu").tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Progress'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the menu has a Progress row")
        row.tap()
        XCTAssertTrue(app.staticTexts["Progress"].waitForExistence(timeout: 5), "Progress opens")
    }

    /// The Progress screen with nothing on the board, then with history, a chart point selected and
    /// a day opened. The empty board is a launch of its own, because the launch argument that empties
    /// it holds for the whole launch.
    func testProgress() {
        let empty = XCUIApplication()
        empty.launchArguments = ["-CindyReplay", "nohands", "-placement_guide_dismissed", "YES",
                                 "-tutorial_seen", "YES", "-hud_tour_pending", "NO", "-attempts", ""]
        empty.launch()
        openProgress(empty)
        XCTAssertTrue(empty.staticTexts["LEADERBOARD"].waitForExistence(timeout: 5))
        capture(empty, "progress-empty")
        empty.terminate()

        let app = launch("nohands")
        for round in 0..<2 {
            finishSession(app, reps: 2)
            app.buttons["DONE"].tap()
            let again = hud(app, "btnStart", labelled: "Start again")
            XCTAssertTrue(again.waitForExistence(timeout: 10))
            if round == 0 { again.tap() }
        }
        openProgress(app)
        capture(app, "progress-history")

        // A point of the chart: the chart's stops are spoken as a session before or the first in the
        // range, which no other control's label says.
        let heading = app.staticTexts["PROGRESS"]
        var swipes = 0
        while !heading.exists && swipes < 12 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(heading.exists, "the chart card is there")
        let stop = app.buttons.matching(NSPredicate(
            format: "label CONTAINS 'session before' OR label CONTAINS 'first in this range'")).firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 5), "the chart has points")
        // The chart is drawn: a point is selected by a touch near it, so the chart's area is tried
        // across until OPEN appears beside the readout.
        let chart = stop.frame
        let selected = app.tapAcross(chart, columns: 7, rows: 3, first: [(6, 1), (6, 0), (6, 2)]) {
            app.buttons["OPEN"].waitForExistence(timeout: 0.4)
        }
        XCTAssertTrue(selected, "a selected point offers OPEN; the chart's frame is \(chart)")
        capture(app, "progress-point")

        let trained = app.buttons.matching(NSPredicate(format: "label ENDSWITH ', trained' OR label CONTAINS ', trained,'")).firstMatch
        swipes = 0
        while !(trained.exists && trained.isHittable) && swipes < 12 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(trained.exists, "the calendar has a trained day")
        let grid = trained.frame
        let body = CGRect(x: grid.minX, y: grid.minY + grid.height / 7, width: grid.width, height: grid.height * 6 / 7)
        let today = XCUIApplication.todaysCell()
        let opened = app.tapAcross(body, columns: 7, rows: 6, first: [(today.column, today.row)]) {
            sheetButton(app, "DONE").waitForExistence(timeout: 0.4)
        }
        XCTAssertTrue(opened, "the day opens a sheet; the calendar's frame is \(grid)")
        capture(app, "progress-day")
    }
}
