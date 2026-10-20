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
        XCTAssertTrue(app.buttons["musicChoose"].waitForExistence(timeout: 5), "the sheet offers CHOOSE A TRACK")
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
