import XCTest

/// Drives the real app in the simulator against a scripted body (`ReplayPoseSource`), because the
/// simulator has no camera. This is the whole path a workout takes: the placement guide, the setup
/// check and its outcomes, the clock, the engine, the HUD, the buttons, saving, and the results
/// screen.
final class CindyTrackerUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// `seenGuide` skips the placement guide, which one test looks at on its own. The launch
    /// arguments stand in for the defaults of a used install, because the simulator keeps what
    /// earlier tests left: the first-launch pages are not shown, and nor is the tour that follows
    /// them, unless `tour` asks for it.
    private func launchReplaying(_ script: String, seenGuide: Bool = true, tour: Bool = false,
                                 strava: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-CindyReplay", script, "-placement_guide_dismissed", seenGuide ? "YES" : "NO",
                         "-tutorial_seen", "YES"]
        // A debug build believes it was given Strava credentials; without this none is, as in CI.
        if strava { arguments += ["-CindyStrava"] }
        if !tour { arguments += ["-hud_tour_pending", "NO"] }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    /// A new install: nothing seen, nothing on record, the placement guide never dismissed.
    private func launchNewInstall() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-CindyReplay", "pullups", "-attempts", "",
                               "-placement_guide_dismissed", "NO", "-tutorial_seen", "NO"]
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
    /// A control of the camera screen, found by the Android view's id, since the controls are marks
    /// with no word to find them by. `labelled` narrows it by its spoken name, which is how a state
    /// of the shutter is told from another.
    private func hud(_ app: XCUIApplication, _ id: String, labelled label: String? = nil) -> XCUIElement {
        var query = app.buttons.matching(identifier: id)
        if let label { query = query.matching(NSPredicate(format: "label == %@", label)) }
        return query.firstMatch
    }

    /// A button of the Cindy sheet, found by its label: the sheet gives its two buttons identifiers
    /// of their own, and a button with an identifier is not found by its label alone.
    private func sheetButton(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "identifier IN {'sheetPrimary', 'sheetSecondary'} AND label == %@", label)).firstMatch
    }

    private func startSkippingSetup(_ app: XCUIApplication) {
        let start = hud(app, "btnStart", labelled: "Start the workout")
        XCTAssertTrue(start.waitForExistence(timeout: 10), "the camera screen opens with START")
        start.tap()
        let skip = hud(app, "btnSkipExercise")
        XCTAssertTrue(skip.waitForExistence(timeout: 5), "START becomes SKIP during the setup check")
        skip.tap()
        // The question has a SKIP of its own, on the sheet that covers the HUD's.
        XCTAssertTrue(sheetButton(app, "SKIP").waitForExistence(timeout: 5), "skipping asks first")
        sheetButton(app, "SKIP").tap()
        XCTAssertTrue(hud(app, "btnStart", labelled: "Pause").waitForExistence(timeout: 5), "skipping starts the clock")
    }

    // MARK: - a whole session

    func testReplayedPullUpsAreCountedAndSaved() {
        let app = launchReplaying("pullups")

        let start = hud(app, "btnStart", labelled: "Start the workout")
        XCTAssertTrue(start.waitForExistence(timeout: 10), "the camera screen opens with START")
        start.tap()

        // The setup check reads the first two pull-ups as calibration, then starts the workout
        // by itself, which is when SKIP turns into PAUSE.
        XCTAssertTrue(hud(app, "btnStart", labelled: "Pause").waitForExistence(timeout: 30),
                      "two calibration reps get the workout going")

        // After calibration the count restarts at zero; a scored pull-up moves it on.
        XCTAssertTrue(repCount(app).waitForExistence(timeout: 5), "the rep count is on screen")
        waitForLabel(repCount(app), "NOT (label BEGINSWITH '0 of ')", timeout: 40)

        hud(app, "btnEnd").tap()
        let end = sheetButton(app, "END")
        XCTAssertTrue(end.waitForExistence(timeout: 5), "stopping asks first")
        end.tap()

        XCTAssertTrue(app.buttons["DONE"].waitForExistence(timeout: 10),
                      "the results screen follows")
    }

    // MARK: - discarding a session

    func testASessionCanBeDiscardedFromItsPage() {
        let app = launchReplaying("nohands")
        startSkippingSetup(app)
        hud(app, "btnAddRep").tap()
        hud(app, "btnAddRep").tap()
        hud(app, "btnEnd").tap()
        XCTAssertTrue(sheetButton(app, "END").waitForExistence(timeout: 5), "stopping asks first")
        sheetButton(app, "END").tap()

        // Two counted reps are a session on the board, so its page offers DISCARD beside DONE.
        let discard = app.buttons["DISCARD"]
        XCTAssertTrue(discard.waitForExistence(timeout: 10), "a saved session can be discarded")
        XCTAssertTrue(app.buttons["DONE"].exists)

        // KEEP IT is the answer that does nothing: the page is still there.
        discard.tap()
        XCTAssertTrue(sheetButton(app, "KEEP IT").waitForExistence(timeout: 5), "DISCARD asks first")
        sheetButton(app, "KEEP IT").tap()
        XCTAssertTrue(app.buttons["DONE"].waitForExistence(timeout: 5), "keeping the session closed its page")

        // The question has a DISCARD of its own, on the sheet over the page's.
        discard.tap()
        XCTAssertTrue(sheetButton(app, "KEEP IT").waitForExistence(timeout: 5))
        sheetButton(app, "DISCARD").tap()

        // The toast is short-lived and the simulator slow, so it is waited for first.
        let toast = app.staticTexts["toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 10), "the screen underneath says what happened")
        XCTAssertEqual(toast.label, "Session discarded")
        // A finished workout leaves the camera screen on RESET, discarded or not.
        XCTAssertTrue(hud(app, "btnStart", labelled: "Start again").waitForExistence(timeout: 10), "discarding closes the page")
    }

    // MARK: - the session page

    /// A session of two hand-added reps, ended: its page is up when this returns.
    private func finishTwoRepSession(_ app: XCUIApplication) {
        startSkippingSetup(app)
        hud(app, "btnAddRep").tap()
        hud(app, "btnAddRep").tap()
        hud(app, "btnEnd").tap()
        XCTAssertTrue(sheetButton(app, "END").waitForExistence(timeout: 5), "stopping asks first")
        sheetButton(app, "END").tap()
        XCTAssertTrue(app.buttons["DONE"].waitForExistence(timeout: 10), "the session page follows")
    }

    func testTheSessionPageIsFullScreenAndClosesWithDone() {
        let app = launchReplaying("nohands")
        finishTwoRepSession(app)

        // A sheet would go with a swipe down; a full-screen page leaves by DONE alone.
        let top = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        top.press(forDuration: 0.05, thenDragTo: app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        XCTAssertTrue(app.buttons["DONE"].exists, "swiping down left the session page")

        app.buttons["DONE"].tap()
        XCTAssertTrue(hud(app, "btnStart", labelled: "Start again").waitForExistence(timeout: 10),
                      "DONE returns to the camera")
    }

    func testDoneCanBeReachedAtTheLargestText() {
        let app = XCUIApplication()
        app.launchArguments = ["-CindyReplay", "nohands", "-placement_guide_dismissed", "YES",
                               "-tutorial_seen", "YES", "-hud_tour_pending", "NO",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        finishTwoRepSession(app)

        let done = app.buttons["DONE"]
        var swipes = 0
        while !done.isHittable && swipes < 12 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(done.isHittable, "DONE can be scrolled to and hit")
        done.tap()
        XCTAssertTrue(hud(app, "btnStart", labelled: "Start again").waitForExistence(timeout: 10))
    }

    func testTheSessionPageNamesItsSectionsInAndroidsWords() {
        let app = launchReplaying("nohands")
        finishTwoRepSession(app)

        for title in ["ROUND BY ROUND", "MOVEMENTS", "DETAILS"] {
            let heading = app.staticTexts[title]
            var swipes = 0
            while !heading.exists && swipes < 12 {
                app.swipeUp()
                swipes += 1
            }
            XCTAssertTrue(heading.exists, "the page has a \(title) section")
        }
    }

    func testAComparedSessionOpensOverThePageAndDoneComesBackToIt() {
        let app = launchReplaying("nohands")
        finishTwoRepSession(app)
        app.buttons["DONE"].tap()
        XCTAssertTrue(hud(app, "btnStart", labelled: "Start again").waitForExistence(timeout: 10))
        hud(app, "btnStart", labelled: "Start again").tap()
        finishTwoRepSession(app)

        // The second session has the first to be compared with: the card opens it.
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

        // The earlier session's page is on top: its headline is its date, not STOPPED.
        let dated = app.staticTexts.matching(NSPredicate(format: "label MATCHES[c] '.*[0-9]{4} · .*'")).firstMatch
        XCTAssertTrue(dated.waitForExistence(timeout: 5), "the reopened page is headed by its date")

        // DONE ends a page, so it is on screen only once the page is scrolled to it. A covered page
        // stays in the queries, so the DONE that can be hit is the top page's.
        let dones = app.buttons.matching(NSPredicate(format: "label == 'DONE'"))
        func scrolledToDone() -> XCUIElement? {
            for _ in 0..<12 {
                if let done = dones.allElementsBoundByIndex.first(where: { $0.isHittable }) { return done }
                app.swipeUp()
            }
            return dones.allElementsBoundByIndex.first(where: { $0.isHittable })
        }
        guard let done = scrolledToDone() else { return XCTFail("the reopened page has a DONE") }
        done.tap()

        // Back on the page it was opened from: the second session, stopped, with its own DONE, and
        // not the camera.
        XCTAssertTrue(app.staticTexts["STOPPED"].waitForExistence(timeout: 5), "DONE returns to the second page")
        XCTAssertFalse(dated.exists, "the reopened page is gone")
        XCTAssertNotNil(scrolledToDone(), "the second page still has its DONE")
    }

    // MARK: - the Progress screen

    /// Opens Progress from the menu, over the camera screen.
    private func openProgress(_ app: XCUIApplication) {
        XCTAssertTrue(hud(app, "btnMenu").waitForExistence(timeout: 10))
        hud(app, "btnMenu").tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Progress'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the menu has a Progress row")
        row.tap()
        XCTAssertTrue(app.staticTexts["Progress"].waitForExistence(timeout: 5), "Progress opens")
    }

    /// The `DONE` of the page on top, scrolled to: covered pages stay in the queries, and a query
    /// cannot filter on `isHittable`, so the hittable one is chosen here.
    private func scrolledToTopDone(_ app: XCUIApplication) -> XCUIElement? {
        let dones = app.buttons.matching(NSPredicate(format: "label == 'DONE'"))
        for _ in 0..<12 {
            if let done = dones.allElementsBoundByIndex.first(where: { $0.isHittable }) { return done }
            app.swipeUp()
        }
        return dones.allElementsBoundByIndex.first(where: { $0.isHittable })
    }

    func testProgressHasItsTitleAndAPinnedDone() {
        let app = launchReplaying("nohands")
        // With a session on the board the page is longer than the screen, so DONE is within reach only
        // if it is pinned below the scroll and not at the foot of it.
        finishTwoRepSession(app)
        app.buttons["DONE"].tap()
        XCTAssertTrue(hud(app, "btnStart", labelled: "Start again").waitForExistence(timeout: 10))
        openProgress(app)

        XCTAssertTrue(app.staticTexts["Cindy — AMRAP 20:00"].exists, "the line under the title")
        XCTAssertEqual(app.navigationBars.count, 0, "the system's bar is hidden: the screen has its own title")
        XCTAssertTrue(app.buttons["DONE"].isHittable, "DONE is within reach")
        app.buttons["DONE"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Progress'")).firstMatch
            .waitForExistence(timeout: 5), "DONE returns to the menu")
    }

    func testAnEmptyBoardHasOnlyTheLeaderboard() {
        let app = XCUIApplication()
        app.launchArguments = ["-CindyReplay", "nohands", "-placement_guide_dismissed", "YES",
                               "-tutorial_seen", "YES", "-hud_tour_pending", "NO", "-attempts", ""]
        app.launch()
        openProgress(app)

        XCTAssertTrue(app.staticTexts["LEADERBOARD"].waitForExistence(timeout: 5), "the benchmark is always there")
        XCTAssertTrue(app.staticTexts["No attempts yet. Finish a 20-minute Cindy and it lands here."].exists)
        XCTAssertFalse(app.buttons["Previous month"].exists, "the calendar needs a session")
        for absent in ["THIS WEEK", "PROGRESS", "PEAKS"] {
            XCTAssertFalse(app.staticTexts[absent].exists, "\(absent) needs a session")
        }
    }

    func testATrainedDayOpensItsSessionAndDoneComesBackToProgress() {
        let app = launchReplaying("nohands")
        finishTwoRepSession(app)
        app.buttons["DONE"].tap()
        XCTAssertTrue(hud(app, "btnStart", labelled: "Start again").waitForExistence(timeout: 10))
        openProgress(app)

        // The calendar's trained days are its buttons, spoken "<date>, trained".
        let trained = app.buttons.matching(NSPredicate(format: "label ENDSWITH ', trained' OR label CONTAINS ', trained,'")).firstMatch
        var swipes = 0
        while !(trained.exists && trained.isHittable) && swipes < 12 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(trained.exists, "the calendar has a trained day")
        app.scrollGridIntoView(trained)

        // The calendar is a drawn grid: its stops are buttons for a screen reader, tapped here at the
        // middle of the whole grid. A day is opened by a touch on its own cell, so the cells below the
        // weekday row are tried in turn; an untrained day opens nothing.
        let grid = trained.frame
        let body = CGRect(x: grid.minX, y: grid.minY + grid.height / 7, width: grid.width, height: grid.height * 6 / 7)
        let today = XCUIApplication.todaysCell()
        let opened = app.tapAcross(body, columns: 7, rows: 6, first: [(today.column, today.row)]) {
            sheetButton(app, "DONE").waitForExistence(timeout: 0.4)
        }

        // The day lists its sessions in a Cindy sheet; a row opens its session.
        XCTAssertTrue(opened, "the day opens a sheet; the calendar's frame is \(grid)")
        let row = app.descendants(matching: .any).matching(identifier: "daySession").firstMatch
        let found = row.waitForExistence(timeout: 5)
        let seen = app.buttons.allElementsBoundByIndex.map { "\($0.identifier)|\($0.label)" }.joined(separator: " ; ")
        let tree = app.descendants(matching: .any)["cindySheet"].debugDescription
            .replacingOccurrences(of: "\n", with: " ⏎ ").prefix(2500)
        XCTAssertTrue(found, "the sheet lists the day's sessions; the buttons are: \(seen); the sheet holds: \(tree)")
        row.tap()

        let dated = app.staticTexts.matching(NSPredicate(format: "label MATCHES[c] '.*[0-9]{4} · .*'")).firstMatch
        XCTAssertTrue(dated.waitForExistence(timeout: 5), "the session opens, headed by its date")
        guard let done = scrolledToTopDone(app) else { return XCTFail("the session page has a DONE") }
        done.tap()

        // Back on Progress: its title can be hit again (a covered page stays in the queries, but not
        // hittable), and the session page is gone.
        let title = app.staticTexts["Progress"]
        var back = false
        for _ in 0..<10 {
            if title.exists && title.isHittable { back = true; break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(back, "DONE returns to Progress")
        // The date's text can match a row on Progress itself, so the page is told by its DISCARD.
        XCTAssertFalse(app.buttons["DISCARD"].waitForExistence(timeout: 2), "the session page is gone")
    }

    func testDiscardingASessionOpenedFromProgressSaysSoAndRemovesItsRow() {
        let app = launchReplaying("nohands")
        finishTwoRepSession(app)
        app.buttons["DONE"].tap()
        XCTAssertTrue(hud(app, "btnStart", labelled: "Start again").waitForExistence(timeout: 10))
        openProgress(app)

        let rows = app.buttons.matching(identifier: "leaderRow")
        var swipes = 0
        while !(rows.firstMatch.exists && rows.firstMatch.isHittable) && swipes < 12 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(rows.firstMatch.exists, "the leaderboard lists the athlete's sessions")
        let before = rows.count
        rows.firstMatch.tap()

        // The reopened session offers DISCARD at the foot of its page.
        let discard = app.buttons["DISCARD"]
        swipes = 0
        while !(discard.exists && discard.isHittable) && swipes < 12 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(discard.exists, "a saved session can be discarded from its page")
        discard.tap()
        XCTAssertTrue(sheetButton(app, "DISCARD").waitForExistence(timeout: 5), "DISCARD asks first")
        sheetButton(app, "DISCARD").tap()

        XCTAssertTrue(app.staticTexts["Session discarded"].waitForExistence(timeout: 10),
                      "Progress says what happened under the page that closed")
        var gone = false
        for _ in 0..<10 {
            if rows.count == before - 1 { gone = true; break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(gone, "the board is built again without the session: \(before) rows before, \(rows.count) after")
    }

    func testProgressNamesItsCardsInAndroidsWords() {
        let app = launchReplaying("nohands")
        finishTwoRepSession(app)
        app.buttons["DONE"].tap()
        XCTAssertTrue(hud(app, "btnStart", labelled: "Start again").waitForExistence(timeout: 10))
        hud(app, "btnStart", labelled: "Start again").tap()
        finishTwoRepSession(app)
        app.buttons["DONE"].tap()
        XCTAssertTrue(hud(app, "btnStart", labelled: "Start again").waitForExistence(timeout: 10))
        openProgress(app)

        // Two sessions on the board: every card is there.
        let titles = ["THIS WEEK", "PROGRESS", "PEAKS", "LEADERBOARD"]
        for title in titles {
            let heading = app.staticTexts[title]
            var swipes = 0
            while !heading.exists && swipes < 12 {
                app.swipeUp()
                swipes += 1
            }
            XCTAssertTrue(heading.exists, "Progress has a \(title) section")
        }
        // The page is not lazy, so every heading has a place at once, and the places run down the page
        // in the Kotlin's order.
        let places = titles.map { app.staticTexts[$0].frame.minY }
        XCTAssertEqual(places, places.sorted(), "THIS WEEK, PROGRESS, PEAKS, LEADERBOARD, top to bottom: \(places)")
    }

    func testTheStreaksAndDoneSurviveTheLargestText() {
        let app = XCUIApplication()
        app.launchArguments = ["-CindyReplay", "nohands", "-placement_guide_dismissed", "YES",
                               "-tutorial_seen", "YES", "-hud_tour_pending", "NO",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        finishTwoRepSession(app)
        // The session page's DONE is at the foot of its scroll view.
        guard let done = scrolledToTopDone(app) else { return XCTFail("the session page has a DONE") }
        done.tap()
        XCTAssertTrue(hud(app, "btnStart", labelled: "Start again").waitForExistence(timeout: 10))
        openProgress(app)

        let streak = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Daily streak'")).firstMatch
        XCTAssertTrue(streak.waitForExistence(timeout: 5), "the daily streak is on the page")
        XCTAssertTrue(app.buttons["DONE"].isHittable, "the pinned DONE stays within reach")
    }

    // MARK: - the questions

    func testSwipingTheStopQuestionAwayKeepsTheWorkoutGoing() {
        let app = launchReplaying("nohands")
        startSkippingSetup(app)
        hud(app, "btnAddRep").tap()
        hud(app, "btnEnd").tap()
        XCTAssertTrue(sheetButton(app, "END").waitForExistence(timeout: 5), "stopping asks first")
        // A swipe that starts on the sheet's own words.
        app.staticTexts["End the workout?"].swipeDown()
        XCTAssertFalse(sheetButton(app, "END").waitForExistence(timeout: 2), "the swipe closed the question")
        XCTAssertTrue(hud(app, "btnStart", labelled: "Pause").waitForExistence(timeout: 5), "a swipe is KEEP GOING")
    }

    func testTheCameraIsHiddenWhileAQuestionIsUp() {
        let app = launchReplaying("nohands")
        startSkippingSetup(app)
        hud(app, "btnEnd").tap()
        XCTAssertTrue(sheetButton(app, "END").waitForExistence(timeout: 5))
        // A view hidden from accessibility stays in the test's queries, so what is asked is whether
        // it can be touched, which the dim over it settles. That a screen reader no longer finds it
        // is owed on a phone.
        let plusOne = hud(app, "btnAddRep")
        let unreachable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == false"),
                                                    object: plusOne)
        XCTAssertEqual(XCTWaiter().wait(for: [unreachable], timeout: 5), .completed,
                       "the controls beneath cannot be reached while the question is up")
        sheetButton(app, "KEEP GOING").tap()
        XCTAssertTrue(hud(app, "btnAddRep").waitForExistence(timeout: 5))
    }

    func testTheStopQuestionKeepsEndWithinReachAtTheLargestText() {
        let app = XCUIApplication()
        app.launchArguments = ["-CindyReplay", "nohands", "-placement_guide_dismissed", "YES",
                               "-tutorial_seen", "YES", "-hud_tour_pending", "NO",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        startSkippingSetup(app)
        hud(app, "btnEnd").tap()
        let end = sheetButton(app, "END")
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        XCTAssertTrue(end.isHittable)
    }

    // MARK: - the launch view

    func testTheLaunchViewGivesWayToTheCamera() {
        let app = launchReplaying("nohands")
        let launch = app.descendants(matching: .any).matching(identifier: "launchView").firstMatch
        XCTAssertTrue(launch.waitForNonExistence(timeout: 15), "the arcs go once the camera has a frame")
        XCTAssertTrue(hud(app, "btnStart").isHittable, "and the camera screen is under them")
    }

    // MARK: - the start-position coach

    func testTheCoachHangsFromTheBandAndTheStatusLineKeepsItsRoom() {
        let app = launchReplaying("nohands")
        startSkippingSetup(app)
        let roomBefore = status(app).frame.minY
        let card = app.descendants(matching: .any).matching(identifier: "coachCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "a body in frame but not in position is shown how")
        // The line steps aside for the card, so the cue is not given twice, but it keeps its room so
        // that nothing jumps. Whether a screen reader still finds it cannot be asked of a UI test,
        // which keeps views hidden from accessibility in its queries; that is owed on a phone.
        // Its top, not its whole frame: the words change as the check ends, and the width follows them.
        XCTAssertEqual(status(app).frame.minY, roomBefore, accuracy: 1, "the status line has not moved")
        XCTAssertGreaterThanOrEqual(card.frame.minY, status(app).frame.maxY, "the card hangs below the band")
    }

    // MARK: - the placement guide

    func testThePlacementGuideComesFirstAndCanBeTurnedOff() {
        let app = launchReplaying("nohands", seenGuide: false)
        hud(app, "btnStart", labelled: "Start the workout").tap()
        XCTAssertTrue(app.otherElements["placementGuide"].waitForExistence(timeout: 5)
                      || app.staticTexts["Where to put the phone"].waitForExistence(timeout: 5),
                      "the guide opens before the first setup check")
        XCTAssertTrue(app.staticTexts["Stand the phone up rather than laying it flat."].exists)
        app.buttons["CONTINUE"].tap()
        XCTAssertTrue(hud(app, "btnSkipExercise").waitForExistence(timeout: 5), "and then the check begins")
    }

    // MARK: - the setup check's outcomes

    func testTheSetupCheckNamesWhatItCannotSee() {
        let app = launchReplaying("nohands")
        hud(app, "btnStart", labelled: "Start the workout").tap()
        XCTAssertTrue(status(app).waitForExistence(timeout: 10))
        waitForLabel(status(app), "label CONTAINS[c] \"Can't see your\"")
        XCTAssertEqual(exercise(app).label, "SET UP")
    }

    func testTheSetupCheckSaysWhenTheMovementBarelyRegisters() {
        let app = launchReplaying("barely")
        hud(app, "btnStart", labelled: "Start the workout").tap()
        waitForLabel(status(app), "label CONTAINS 'barely registers'", timeout: 60)
    }

    func testTheSetupCheckCanBeSkippedAfterBeingTold() {
        let app = launchReplaying("nohands")
        hud(app, "btnStart", labelled: "Start the workout").tap()
        XCTAssertTrue(hud(app, "btnSkipExercise").waitForExistence(timeout: 5))
        hud(app, "btnSkipExercise").tap()
        XCTAssertTrue(app.staticTexts["Skip the setup check?"].waitForExistence(timeout: 5)
                      || sheetButton(app, "KEEP CHECKING").waitForExistence(timeout: 5),
                      "it says what skipping costs before doing it")
        sheetButton(app, "KEEP CHECKING").tap()
        XCTAssertTrue(hud(app, "btnSkipExercise").waitForExistence(timeout: 5), "keeping on checking leaves the check running")
        XCTAssertFalse(hud(app, "btnStart", labelled: "Pause").exists)
    }

    // MARK: - the buttons

    func testPlusOneCountsARepAndMinusOneTakesItBack() {
        let app = launchReplaying("nohands")
        startSkippingSetup(app)
        XCTAssertTrue(repCount(app).label.hasPrefix("0 of 5"))
        hud(app, "btnAddRep").tap()
        waitForLabel(repCount(app), "label BEGINSWITH '1 of 5'")
        hud(app, "btnUndo").tap()
        waitForLabel(repCount(app), "label BEGINSWITH '0 of 5'")
    }

    func testMinusOneStepsBackAcrossAMovementBoundary() {
        let app = launchReplaying("nohands")
        startSkippingSetup(app)
        for _ in 0..<5 { hud(app, "btnAddRep").tap() }
        waitForLabel(exercise(app), "label == 'PUSH-UPS'")
        XCTAssertTrue(repCount(app).label.hasPrefix("0 of 10"))
        hud(app, "btnUndo").tap()
        waitForLabel(exercise(app), "label == 'PULL-UPS'")
        waitForLabel(repCount(app), "label BEGINSWITH '4 of 5'")
    }

    func testSkipLeavesTheMovementAndTheEditorsAreDimmedBeforeTheClockStarts() {
        let app = launchReplaying("nohands")
        XCTAssertTrue(hud(app, "btnSkipExercise").waitForExistence(timeout: 10), "SKIP is there before the clock")
        XCTAssertFalse(hud(app, "btnSkipExercise").isEnabled, "and dimmed, with no movement to leave")
        XCTAssertFalse(hud(app, "btnAddRep").isEnabled, "the editors wait for the clock")
        startSkippingSetup(app)
        XCTAssertTrue(hud(app, "btnAddRep").isEnabled)
        XCTAssertTrue(hud(app, "btnSkipExercise").isEnabled)
        hud(app, "btnAddRep").tap()
        hud(app, "btnSkipExercise").tap()
        waitForLabel(exercise(app), "label == 'PUSH-UPS'")
    }

    func testTheLeftSlotChangesHands() {
        let app = launchReplaying("nohands")
        XCTAssertTrue(hud(app, "btnFlip").waitForExistence(timeout: 10), "FLIP before the clock")
        XCTAssertFalse(hud(app, "btnEnd").exists)
        startSkippingSetup(app)
        XCTAssertTrue(hud(app, "btnEnd").waitForExistence(timeout: 5), "END once it runs")
        XCTAssertTrue(hud(app, "btnFlip").waitForNonExistence(timeout: 5))
        hud(app, "btnEnd").tap()
        sheetButton(app, "END").tap()
        XCTAssertTrue(hud(app, "btnFlip").waitForExistence(timeout: 10), "and FLIP again once it is over")
    }

    func testTheShutterNamesTheState() {
        let app = launchReplaying("nohands")
        XCTAssertTrue(hud(app, "btnStart", labelled: "Start the workout").waitForExistence(timeout: 10))
        hud(app, "btnStart").tap()
        let inCheck = hud(app, "btnStart", labelled: "Start — available once the setup check finishes")
        XCTAssertTrue(inCheck.waitForExistence(timeout: 5), "the shutter says why it is inert")
        XCTAssertFalse(inCheck.isEnabled)
        hud(app, "btnSkipExercise").tap()
        sheetButton(app, "SKIP").tap()
        XCTAssertTrue(hud(app, "btnStart", labelled: "Pause").waitForExistence(timeout: 5))
        hud(app, "btnStart").tap()
        XCTAssertTrue(hud(app, "btnStart", labelled: "Resume").waitForExistence(timeout: 5))
    }

    func testTheBandsKeepTheControlsReachableAtTheLargestText() {
        let app = XCUIApplication()
        app.launchArguments = ["-CindyReplay", "nohands", "-placement_guide_dismissed", "YES",
                               "-tutorial_seen", "YES", "-hud_tour_pending", "NO",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let start = hud(app, "btnStart")
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(start.isHittable, "the shutter is on screen")
        XCTAssertTrue(hud(app, "btnMenu").isHittable)
        let count = repCount(app)
        XCTAssertTrue(count.isHittable, "so is the count")
        XCTAssertTrue(hud(app, "btnSkipExercise").isHittable, "SKIP too")
        XCTAssertFalse(count.frame.intersects(start.frame), "and the two do not overlap")
        XCTAssertLessThanOrEqual(app.staticTexts["status"].frame.maxY, exercise(app).frame.minY,
                                 "the bands do not run into each other")
    }

    func testALongStatusLineDoesNotLoseTheClock() {
        let app = XCUIApplication()
        app.launchArguments = ["-CindyReplay", "barely", "-placement_guide_dismissed", "YES",
                               "-tutorial_seen", "YES", "-hud_tour_pending", "NO",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(hud(app, "btnStart").waitForExistence(timeout: 10))
        hud(app, "btnStart").tap()
        waitForLabel(status(app), "label CONTAINS 'barely registers'", timeout: 60)
        XCTAssertTrue(app.staticTexts["clock"].isHittable, "the clock is still on its band")
    }

    func testPausingParksTheClockAndResumingRestartsIt() {
        let app = launchReplaying("nohands")
        startSkippingSetup(app)
        hud(app, "btnStart", labelled: "Pause").tap()
        XCTAssertTrue(hud(app, "btnStart", labelled: "Resume").waitForExistence(timeout: 5))
        waitForLabel(status(app), "label == 'Paused'")
        hud(app, "btnStart", labelled: "Resume").tap()
        XCTAssertTrue(hud(app, "btnStart", labelled: "Pause").waitForExistence(timeout: 5))
        waitForLabel(status(app), "label != 'Paused'")
    }

    func testKeepingGoingAfterStopLetsTheClockRunAgain() {
        let app = launchReplaying("nohands")
        startSkippingSetup(app)
        hud(app, "btnEnd").tap()
        XCTAssertTrue(sheetButton(app, "KEEP GOING").waitForExistence(timeout: 5))
        sheetButton(app, "KEEP GOING").tap()
        XCTAssertTrue(hud(app, "btnStart", labelled: "Pause").waitForExistence(timeout: 5),
                      "the clock that was parked behind the question is running again")
    }

    // MARK: - the first run

    /// The tour's NEXT (DONE on the last step), tapped where it is. The accessibility tree reports it
    /// as not hittable on some steps, where the card sits against the bottom edge, though the same
    /// card's SKIP TOUR is; a tap anywhere on the dimmed screen also moves on, so the flow is
    /// what is under test, not that query.
    private func tapTourNext(_ app: XCUIApplication) {
        let next = app.buttons["tourNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "the tour has a NEXT")
        next.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// NEXT, or LET'S GO on the last page: found by what it says, as a person would.
    private func tutorialNext(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == 'NEXT' OR label BEGINSWITH 'LET'")).firstMatch
    }

    func testANewInstallIsShownFivePagesAndThenTheTourOfTheCameraScreen() {
        let app = launchNewInstall()

        XCTAssertTrue(app.staticTexts["Cindy, counted for you"].waitForExistence(timeout: 10),
                      "a new install opens on the first page")
        XCTAssertFalse(app.buttons["BACK"].exists, "the first page has no way back")
        for title in ["Your Cindy, your movements", "Where to stand", "Before the clock starts",
                      "Nothing leaves your phone"] {
            tutorialNext(app).tap()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5), "page: \(title)")
        }
        XCTAssertTrue(app.staticTexts["Next, iOS asks to use the camera."].exists,
                      "the last page of a first run says the camera is next")
        XCTAssertTrue(app.buttons["LET'S GO"].exists)
        tutorialNext(app).tap()

        // The pages are done, and the tour of the controls comes next: it opens on the first
        // control and ends on the last, one step per control the screen has, SKIP's included even
        // though it is dimmed before the clock starts. Read from what is on the screen, so that it
        // holds the order and the end and not how many taps it took to get there.
        let expected = ["Start", "What Cindy sees", "Your reps", "Skip", "Record", "Menu", "Flip"]
        let steps = expected.count
        let skip = app.buttons["Skip the tour"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "the tour opens")
        XCTAssertTrue(app.staticTexts["tourTitle"].waitForExistence(timeout: 5), "the tour has a title")
        XCTAssertEqual(app.staticTexts["tourTitle"].label, "Start", "it opens on the first control")
        // NEXT is what takes the athlete through it, and the end of the tour is what it is for:
        // so count the taps it takes to put the tour away. One per step, and not one fewer: a NEXT
        // that does nothing leaves the tour up, and one that skips steps ends it early.
        var taps = 0
        var titles: [String] = []
        while skip.exists && taps < steps + 3 {
            titles.append(app.staticTexts["tourTitle"].label)
            tapTourNext(app)
            taps += 1
            _ = skip.waitForNonExistence(timeout: 1.5)
        }
        XCTAssertFalse(skip.exists, "the tour was still up after \(taps) taps on NEXT")
        XCTAssertEqual(taps, steps, "one tap on NEXT for each of the \(steps) controls")
        XCTAssertEqual(titles, expected, "the tour says each control in its order")
        XCTAssertTrue(hud(app, "btnStart", labelled: "Start the workout").waitForExistence(timeout: 5), "the camera screen is back")
        XCTAssertFalse(app.buttons["Skip the tour"].exists)
    }

    func testTheTourCanBeSkippedAndDoesNotComeBack() {
        let app = launchNewInstall()
        XCTAssertTrue(app.buttons["Skip the introduction"].waitForExistence(timeout: 10))
        app.buttons["Skip the introduction"].tap()

        let skip = app.buttons["Skip the tour"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "skipping the pages still leads to the tour")
        skip.tap()
        XCTAssertTrue(hud(app, "btnStart", labelled: "Start the workout").waitForExistence(timeout: 5))

        // The same install again: what was written when the pages and the tour ended is all there is.
        app.terminate()
        app.launchArguments = ["-CindyReplay", "pullups", "-placement_guide_dismissed", "NO"]
        app.launch()
        XCTAssertTrue(hud(app, "btnStart", labelled: "Start the workout").waitForExistence(timeout: 10),
                      "neither the pages nor the tour come back for the same install")
        XCTAssertFalse(app.buttons["Skip the tour"].exists)
    }

    func testHelpTakesTheTourAgainAndReturnsToTheCameraWithTheTourNext() {
        let app = launchReplaying("pullups", tour: true)
        XCTAssertTrue(hud(app, "btnMenu").waitForExistence(timeout: 10))
        // A tour left pending by an earlier test is taken first: it would swallow the tap.
        if app.buttons["Skip the tour"].waitForExistence(timeout: 3) { app.buttons["Skip the tour"].tap() }
        hud(app, "btnMenu").tap()

        let help = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Help'")).firstMatch
        XCTAssertTrue(help.waitForExistence(timeout: 5), "the menu has a Help row")
        help.tap()

        let tour = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Take the tour'")).firstMatch
        XCTAssertTrue(tour.waitForExistence(timeout: 5), "Help offers the tour first")
        tour.tap()
        XCTAssertTrue(app.staticTexts["Cindy, counted for you"].waitForExistence(timeout: 5))

        // A replay ends back on the camera screen, closing the menu and Help over it.
        app.buttons["Skip the introduction"].tap()
        let skip = app.buttons["Skip the tour"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "the tour follows the replayed pages")
        skip.tap()
        XCTAssertTrue(hud(app, "btnStart", labelled: "Start the workout").waitForExistence(timeout: 5))
    }

    // MARK: - the menu

    func testTheMenuHasItsTitleAndAPinnedDone() {
        let app = launchReplaying("nohands")
        XCTAssertTrue(hud(app, "btnMenu").waitForExistence(timeout: 10))
        hud(app, "btnMenu").tap()

        XCTAssertTrue(app.staticTexts["Menu"].waitForExistence(timeout: 5), "the menu has its title")
        XCTAssertTrue(app.staticTexts["Everything that isn't needed mid-workout"].exists, "and the line under it")
        // DONE sits below the rows, outside their scroll, so it is within reach without scrolling.
        let done = app.buttons["DONE"]
        XCTAssertTrue(done.waitForExistence(timeout: 5) && done.isHittable, "DONE is pinned")
        done.tap()
        XCTAssertTrue(hud(app, "btnMenu").waitForExistence(timeout: 5) && hud(app, "btnMenu").isHittable,
                      "DONE returns to the camera")
    }

    func testTheMenuOverALiveWorkoutRefusesMovementsAndSaysWhy() {
        let app = launchReplaying("nohands")
        startSkippingSetup(app)
        hud(app, "btnMenu").tap()

        XCTAssertTrue(app.staticTexts["Movements can only be changed between workouts — they have to mean one thing for the whole score."]
            .waitForExistence(timeout: 5), "the menu says why Movements is refused")
        let movements = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Movements'")).firstMatch
        XCTAssertTrue(movements.exists)
        movements.tap()
        XCTAssertTrue(app.staticTexts["Reset the workout first to change movements"].waitForExistence(timeout: 5),
                      "tapping it says the same in a toast")

        app.buttons["DONE"].tap()
        // Android pauses a running workout when the menu opens (its screen goes to the background);
        // here the clock runs on under the menu, as it did under the sheet.
        XCTAssertTrue(hud(app, "btnStart", labelled: "Pause").waitForExistence(timeout: 5),
                      "the workout kept its clock")
    }

    func testTheMenuKeepsItsRowsAtTheLargestText() {
        let app = XCUIApplication()
        app.launchArguments = ["-CindyReplay", "nohands", "-placement_guide_dismissed", "YES",
                               "-tutorial_seen", "YES", "-hud_tour_pending", "NO",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(hud(app, "btnMenu").waitForExistence(timeout: 10))
        hud(app, "btnMenu").tap()

        let progress = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Progress'")).firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 5), "the Progress row is there")
        XCTAssertTrue(app.buttons["DONE"].isHittable, "the pinned DONE stays within reach")
    }

    // MARK: - the You screen

    /// A phone with nothing on it: no sessions, and no name for this launch (a name an earlier test
    /// saved is shadowed by the empty argument).
    private func launchEmptyHanded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-CindyReplay", "nohands", "-placement_guide_dismissed", "YES",
                               "-tutorial_seen", "YES", "-hud_tour_pending", "NO", "-attempts", "",
                               "-display_name", ""]
        app.launch()
        return app
    }

    /// Opens the You screen from the menu's profile row, over the camera screen.
    private func openYou(_ app: XCUIApplication) {
        XCTAssertTrue(hud(app, "btnMenu").waitForExistence(timeout: 10))
        hud(app, "btnMenu").tap()
        let profile = app.buttons["You, Add your name and photo"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5), "the menu's profile row invites the athlete in")
        profile.tap()
        XCTAssertTrue(app.staticTexts["You"].firstMatch.waitForExistence(timeout: 5), "the You screen opens")
    }

    func testTheYouScreenHasItsTitleAndAPinnedDone() {
        let app = launchEmptyHanded()
        openYou(app)

        XCTAssertTrue(app.staticTexts["Your name, photo and badges. They stay on this phone."].exists,
                      "the line under the title says what the screen is")
        let dones = app.buttons.matching(NSPredicate(format: "label == 'DONE'")).allElementsBoundByIndex
        XCTAssertTrue(dones.contains(where: { $0.isHittable }), "DONE is pinned, within reach without scrolling")
    }

    func testAYouScreenWithNothingInItInvitesAndLocksEveryBadge() {
        let app = launchEmptyHanded()
        openYou(app)

        XCTAssertTrue(app.buttons["Add a photo"].exists, "the header invites a photo")
        XCTAssertTrue(app.buttons["Add your name"].exists, "and a name")
        XCTAssertTrue(app.staticTexts["Finish a session and your badges start here."].exists,
                      "the training line says the badges start with the first session")
        let title = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'BADGES · 0 OF'")).firstMatch
        XCTAssertTrue(title.exists, "no badge is earned yet")
        let tiles = app.buttons.matching(NSPredicate(format: "label CONTAINS ', locked'"))
        XCTAssertGreaterThan(tiles.count, 0, "the badges are all there, locked")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS ', earned '")).count, 0,
                       "and none is earned")
    }

    func testABadgeOpensACindySheetAndDoneClosesIt() {
        let app = launchEmptyHanded()
        openYou(app)

        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS ', locked'")).firstMatch
        var swipes = 0
        while !(tile.exists && tile.isHittable) && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(tile.isHittable, "a badge can be tapped")
        tile.tap()

        // The Cindy sheet's own DONE has an identifier; the screen's has none.
        let done = sheetButton(app, "DONE")
        XCTAssertTrue(done.waitForExistence(timeout: 5), "a badge opens a Cindy sheet, not the system's")
        done.tap()
        var gone = false
        for _ in 0..<10 {
            if !sheetButton(app, "DONE").exists { gone = true; break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(gone, "DONE closes the sheet")
        XCTAssertTrue(app.staticTexts["You"].firstMatch.exists, "and the You screen is still there")
    }

    func testTheYouScreenKeepsItsBadgesAndDoneAtTheLargestText() {
        let app = XCUIApplication()
        app.launchArguments = ["-CindyReplay", "nohands", "-placement_guide_dismissed", "YES",
                               "-tutorial_seen", "YES", "-hud_tour_pending", "NO", "-attempts", "",
                               "-display_name", "",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        openYou(app)

        let dones = app.buttons.matching(NSPredicate(format: "label == 'DONE'")).allElementsBoundByIndex
        XCTAssertTrue(dones.contains(where: { $0.isHittable }), "the pinned DONE stays within reach")
        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'First Cindy, locked'")).firstMatch
        var swipes = 0
        while !(tile.exists && tile.isHittable) && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(tile.isHittable, "a badge can be reached by scrolling")
    }

    func testTheYouScreenGoesBackWithASwipeFromTheEdge() {
        let app = launchEmptyHanded()
        openYou(app)

        // The screen draws its own title and DONE with the system's bar hidden; the swipe back stays.
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        from.press(forDuration: 0.1, thenDragTo: to)
        XCTAssertTrue(app.staticTexts["Everything that isn't needed mid-workout"].waitForExistence(timeout: 5),
                      "the menu is back")
        let leaves = NSPredicate(format: "exists == false")
        let gone = expectation(for: leaves, evaluatedWith: app.staticTexts["Add your name"], handler: nil)
        wait(for: [gone], timeout: 5)
    }

    // MARK: - the profile sheets

    /// Opens the menu over the camera and taps the row that begins with `title`.
    private func openMenuRow(_ app: XCUIApplication, _ title: String) {
        XCTAssertTrue(hud(app, "btnMenu").waitForExistence(timeout: 10))
        hud(app, "btnMenu").tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the menu has a \(title) row")
        row.tap()
    }

    /// A tap on the dim above a Cindy sheet, which closes it as CANCEL does.
    private func tapTheDim(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
    }

    func testBodyWeightIsACindySheetAndARefusedSaveKeepsIt() {
        let app = launchReplaying("pullups")
        openMenuRow(app, "Body weight")

        XCTAssertTrue(sheetButton(app, "SAVE").waitForExistence(timeout: 5), "the weight is asked for on a Cindy sheet")
        XCTAssertTrue(sheetButton(app, "CANCEL").exists)
        let field = app.textFields["sheetField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the sheet has its field")
        field.typeText("5")
        // With the keyboard up, SAVE is still within reach.
        XCTAssertTrue(sheetButton(app, "SAVE").isHittable, "SAVE stays above the keyboard")
        sheetButton(app, "SAVE").tap()

        // 5 kg is not a weight: the sheet says so and stays, where Android would have closed it.
        let refusal = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Enter a weight between'")).firstMatch
        XCTAssertTrue(refusal.waitForExistence(timeout: 5), "the refusal is said under the field")
        XCTAssertTrue(sheetButton(app, "SAVE").exists, "and the sheet is still up")

        sheetButton(app, "CANCEL").tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Body weight'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Not set"), "nothing was saved: \(row.label)")
    }

    func testMovementsChoosesAcrossThreeGroupsAndDismissingSavesNothing() {
        let app = launchReplaying("pullups")
        openMenuRow(app, "Movements")

        XCTAssertTrue(sheetButton(app, "SAVE").waitForExistence(timeout: 5), "movements are chosen on a Cindy sheet")
        for heading in ["PULL", "PUSH", "SQUAT"] {
            XCTAssertTrue(app.staticTexts[heading].exists, "the sheet has the \(heading) group")
        }
        XCTAssertTrue(app.switches["Spot heels-flat squats"].exists, "and the heels-flat setting")
        let strict = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Strict pull-up'")).firstMatch
        XCTAssertTrue(strict.isSelected, "the standard pull-up is chosen to begin with")

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Band-assisted'")).firstMatch.tap()
        tapTheDim(app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Movements'")).firstMatch
            .waitForExistence(timeout: 5), "the menu is back")

        // The tap on the dim was CANCEL: the choice went with the sheet.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Movements'")).firstMatch.tap()
        XCTAssertTrue(sheetButton(app, "SAVE").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Strict pull-up'")).firstMatch.isSelected,
                      "dismissing the sheet kept the old choice")
        sheetButton(app, "CANCEL").tap()
    }

    func testTheNameSheetOpensWithItsFieldAndCancelSavesNothing() {
        let app = launchEmptyHanded()
        openYou(app)

        app.buttons["Add your name"].tap()
        XCTAssertTrue(sheetButton(app, "SAVE").waitForExistence(timeout: 5), "the name is asked for on a Cindy sheet")
        XCTAssertTrue(sheetButton(app, "CANCEL").exists)
        XCTAssertTrue(app.textFields["sheetField"].exists, "the sheet has its field")

        sheetButton(app, "CANCEL").tap()
        XCTAssertTrue(app.buttons["Add your name"].waitForExistence(timeout: 5), "no name was saved")
        XCTAssertFalse(app.textFields["sheetField"].exists, "and the sheet is gone")
    }

    func testThePhotoSheetOffersChooseAndCancel() {
        let app = launchEmptyHanded()
        openYou(app)

        app.buttons["Add a photo"].tap()
        XCTAssertTrue(sheetButton(app, "CHOOSE PHOTO").waitForExistence(timeout: 5), "the photo is offered on a Cindy sheet")
        XCTAssertTrue(sheetButton(app, "CANCEL").exists, "with nothing to remove, CANCEL")
        sheetButton(app, "CANCEL").tap()
        XCTAssertTrue(app.buttons["Add a photo"].waitForExistence(timeout: 5))
    }

    // MARK: - the voice

    /// Turns a sheet's switch over by its own end: the middle of the row is the label, which does not.
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    func testTheVoiceSheetListsLanguagesAndDismissingKeepsTheOldSettings() {
        let app = launchReplaying("pullups")
        openMenuRow(app, "Voice")

        XCTAssertTrue(sheetButton(app, "SAVE").waitForExistence(timeout: 5), "the voice is set on a Cindy sheet")
        XCTAssertTrue(sheetButton(app, "HEAR IT").exists, "with HEAR IT beside SAVE")
        XCTAssertTrue(app.staticTexts["Volume"].exists)
        XCTAssertTrue(app.staticTexts["LANGUAGE"].exists, "the language list is under its heading")
        let counting = app.switches["Count reps out loud"]
        XCTAssertTrue(counting.exists)
        let before = counting.value as? String

        flip(counting)
        tapTheDim(app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Voice'")).firstMatch
            .waitForExistence(timeout: 5), "the menu is back")

        // The tap on the dim was CANCEL: the switch went back with it.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Voice'")).firstMatch.tap()
        XCTAssertTrue(sheetButton(app, "SAVE").waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["Count reps out loud"].value as? String, before, "dismissing kept the old setting")
        sheetButton(app, "CANCEL").exists ? sheetButton(app, "CANCEL").tap() : tapTheDim(app)
    }

    func testTheVoiceSheetKeepsSaveReachableAtTheLargestText() {
        let app = XCUIApplication()
        app.launchArguments = ["-CindyReplay", "pullups", "-placement_guide_dismissed", "YES",
                               "-tutorial_seen", "YES", "-hud_tour_pending", "NO",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        openMenuRow(app, "Voice")

        XCTAssertTrue(sheetButton(app, "SAVE").waitForExistence(timeout: 5), "the voice sheet opens")
        XCTAssertTrue(sheetButton(app, "SAVE").isHittable, "SAVE stays within reach however long the list is")
    }

    // MARK: - heart rate

    func testTheMenuOffersHeartRateAndTheSheetSaysHowToFindAWatch() {
        let app = launchReplaying("pullups")
        XCTAssertTrue(hud(app, "btnMenu").waitForExistence(timeout: 10))
        hud(app, "btnMenu").tap()

        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Heart rate'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the menu has a Heart rate row")
        XCTAssertTrue(row.label.contains("No watch paired"), row.label)
        row.tap()

        // Not tapped: looking for a watch asks iOS for Bluetooth, and the simulator has none.
        XCTAssertTrue(app.buttons["findMyWatch"].waitForExistence(timeout: 5), "the sheet offers FIND MY WATCH")
        let advice = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Broadcast Heart Rate'")).firstMatch
        XCTAssertTrue(advice.exists, "the sheet says to turn the broadcast on first")
    }

    // MARK: - filming

    func testRecSaysWhenThereIsNoCameraToFilmWith() {
        // A replayed body has no picture, as a camera that cannot film has none: the tap is answered
        // at once and no count starts. Nothing here asks Photos for anything.
        let app = launchReplaying("pullups")
        let rec = hud(app, "btnRec", labelled: "Record this workout")
        XCTAssertTrue(rec.waitForExistence(timeout: 10), "REC is on the camera screen")
        rec.tap()

        let toast = app.staticTexts["toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 5), "the tap is answered")
        XCTAssertEqual(toast.label, "Recording is not available on this camera")
        XCTAssertTrue(hud(app, "btnRec", labelled: "Record this workout").exists, "REC is still offering to record")
        XCTAssertFalse(hud(app, "btnRec", labelled: "Recording is about to start, tap to cancel").exists, "no count started")
    }

    // MARK: - music

    func testTheMenuOffersMusicAndTheSheetSaysWhatTheTrackDoes() {
        let app = launchReplaying("pullups")
        XCTAssertTrue(hud(app, "btnMenu").waitForExistence(timeout: 10))
        hud(app, "btnMenu").tap()

        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Music'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the menu has a Music row")
        XCTAssertTrue(row.label.contains("No track chosen"), row.label)
        row.tap()

        // Not tapped: choosing a track opens the system's file picker, which the test cannot drive.
        XCTAssertTrue(sheetButton(app, "CHOOSE A TRACK").waitForExistence(timeout: 5), "the sheet offers CHOOSE A TRACK")
        XCTAssertTrue(sheetButton(app, "CANCEL").exists, "and CANCEL, with no track to listen to")
        let advice = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'drops in volume while the voice'")).firstMatch
        XCTAssertTrue(advice.exists, "the sheet says the track ducks under the voice")
        XCTAssertEqual(app.staticTexts["musicTrack"].label, "No track chosen")
    }

    // MARK: - reminder

    func testTheMenuOffersTheDailyReminderAndTheSheetSaysWhatItDoes() {
        let app = launchReplaying("pullups")
        XCTAssertTrue(hud(app, "btnMenu").waitForExistence(timeout: 10))
        hud(app, "btnMenu").tap()

        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Daily reminder'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the menu has a Daily reminder row")
        XCTAssertTrue(row.label.contains("Off"), row.label)
        row.tap()

        // Nothing is switched on: that asks iOS for notifications, which the simulator would answer
        // with a dialog the test does not drive.
        XCTAssertTrue(app.switches["Remind me"].waitForExistence(timeout: 5), "the sheet has the switch")
        XCTAssertTrue(app.buttons["reminderTry"].exists, "and TRY IT")
        let note = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "none on days you've already trained")).firstMatch
        XCTAssertTrue(note.exists, "the sheet says it stays quiet on a day already trained")
    }

    // MARK: - strava

    func testABuildWithNoStravaCredentialsHasNoStravaAnywhereOnTheMenu() {
        let app = launchReplaying("pullups")
        XCTAssertTrue(hud(app, "btnMenu").waitForExistence(timeout: 10))
        hud(app, "btnMenu").tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Heart rate'")).firstMatch
            .waitForExistence(timeout: 5), "the menu is up")

        let strava = NSPredicate(format: "label CONTAINS 'Strava'")
        XCTAssertFalse(app.buttons.matching(strava).firstMatch.exists, "a row says Strava")
        XCTAssertFalse(app.staticTexts.matching(strava).firstMatch.exists, "some menu text says Strava")
    }

    func testTheStravaRowAsksFirstAndNOTNOWStartsNothing() {
        let app = launchReplaying("pullups", strava: true)
        XCTAssertTrue(hud(app, "btnMenu").waitForExistence(timeout: 10))
        hud(app, "btnMenu").tap()

        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Strava'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the menu has a Strava row")
        XCTAssertTrue(row.label.contains("Not connected"), row.label)
        row.tap()

        // The sheet that says what is sent comes first, with Strava's own button and the safe one.
        let promise = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Nothing is sent until you connect.'")).firstMatch
        XCTAssertTrue(promise.waitForExistence(timeout: 5), "the consent sheet says nothing is sent until you connect")
        XCTAssertTrue(app.buttons["Connect with Strava"].exists, "Strava's own button")
        let notNow = app.buttons["NOT NOW"]
        XCTAssertTrue(notNow.exists)
        notNow.tap()

        // Back on the menu, still not connected: nothing was started.
        XCTAssertTrue(promise.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Strava, Not connected'")).firstMatch.exists)
    }
}
