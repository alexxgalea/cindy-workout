import XCTest
@testable import CindyCore

/// The first-launch pages: that they build on every page, that they lead where they should, and
/// that the two flags move only when the pages end. Port of `TutorialScreenTest.kt`.
///
/// Whether to show them at all is `OnboardingTests`. Robolectric read the pages off inflated views
/// and pressed buttons; here the same facts are read off what `TutorialModel` returns for the screen
/// to draw, and the buttons are its methods. Where a Kotlin test is about Android's layout pass
/// ("lays out at phone size") the counterpart checks that every page has something to lay out.
final class TutorialPagesTests: XCTestCase {

    private func firstRun() -> FirstRun {
        let suite = "cindy.tutorial.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return FirstRun(defaults: defaults)
    }

    private func fresh() -> Profile {
        let suite = "cindy.tutorial.profile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return Profile(defaults: defaults)
    }

    /// Presses NEXT until the page the pages end on.
    private func toLastPage(_ model: inout TutorialModel) {
        for _ in 0..<(TutorialModel.pageCount - 1) { XCTAssertNil(model.next()) }
    }

    private func page(_ model: TutorialModel, strava: Bool = false) -> TutorialPage { model.page(stravaAvailable: strava) }

    private func contains(_ model: TutorialModel, _ part: String, strava: Bool = false) -> Bool {
        page(model, strava: strava).texts.contains { $0.contains(part) }
    }

    // MARK: the pages

    /// the first page welcomes, with no way back and the way on
    func testTheFirstPageWelcomesWithNoWayBackAndTheWayOn() {
        let model = TutorialModel(replay: false)
        XCTAssertEqual(page(model).title, "Cindy, counted for you")
        XCTAssertTrue(page(model).texts.contains("Cindy, counted for you"))
        XCTAssertNil(model.backLabel)
        XCTAssertEqual(model.nextLabel, "NEXT")
        XCTAssertEqual(model.dotsDescription, "Page 1 of 5")
        XCTAssertEqual(page(model).blocks.first, .mark)
    }

    /// each page builds and lays out at phone size
    func testEachPageBuildsAndHasSomethingToLayOut() {
        var model = TutorialModel(replay: false)
        var titles: [String] = []
        for i in 0..<TutorialModel.pageCount {
            let p = page(model)
            XCTAssertEqual(p.index, i)
            XCTAssertFalse(p.title.isEmpty, "page \(i + 1) has no title")
            XCTAssertFalse(p.texts.isEmpty, "page \(i + 1) says nothing")
            XCTAssertEqual(p.blocks.filter { if case .title = $0 { return true } else { return false } }.count, 1,
                           "page \(i + 1) has one title")
            titles.append(p.title)
            if i < TutorialModel.pageCount - 1 { _ = model.next() }
        }
        XCTAssertEqual(titles, TutorialModel.titles)
        XCTAssertEqual(Set(titles).count, TutorialModel.pageCount)
    }

    /// NEXT four times reaches the last page, where the button says LET'S GO
    func testNextFourTimesReachesTheLastPageWhereTheButtonSaysLetsGo() {
        var model = TutorialModel(replay: false)

        toLastPage(&model)

        XCTAssertEqual(page(model).title, "Nothing leaves your phone")
        XCTAssertEqual(model.nextLabel, "LET'S GO")
        XCTAssertEqual(model.backLabel, "BACK")
        XCTAssertEqual(model.dotsDescription, "Page 5 of 5")
        XCTAssertTrue(model.isLast)
    }

    /// the dots say which page this is
    func testTheDotsSayWhichPageThisIs() {
        var model = TutorialModel(replay: false)
        _ = model.next()
        XCTAssertEqual(model.dotsDescription, "Page 2 of 5")
        model.back()
        XCTAssertEqual(model.dotsDescription, "Page 1 of 5")
    }

    // MARK: the pages ending

    /// nothing is marked until the pages end
    func testNothingIsMarkedUntilThePagesEnd() {
        let flags = firstRun()
        var model = TutorialModel(replay: false)
        toLastPage(&model)

        XCTAssertFalse(flags.tutorialSeen)
        XCTAssertFalse(flags.hudTourPending)
    }

    /// LET'S GO ends the pages, marks them seen, queues the tour and says OK
    func testLetsGoEndsThePagesMarksThemSeenAndQueuesTheTour() {
        let flags = firstRun()
        var model = TutorialModel(replay: false)
        toLastPage(&model)

        XCTAssertEqual(model.next(), .dismiss)
        XCTAssertEqual(model.finish(flags), .dismiss)

        XCTAssertTrue(flags.tutorialSeen)
        XCTAssertTrue(flags.hudTourPending)
    }

    /// SKIP does the same from any page
    func testSkipDoesTheSameFromAnyPage() {
        let flags = firstRun()
        var model = TutorialModel(replay: false)
        _ = model.next()

        // SKIP does not move the page: it ends them where they are.
        XCTAssertEqual(model.index, 1)
        XCTAssertEqual(model.finish(flags), .dismiss)

        XCTAssertTrue(flags.tutorialSeen)
        XCTAssertTrue(flags.hudTourPending)
        XCTAssertEqual(TutorialModel.skipDescription, "Skip the introduction")
    }

    /// once the pages have ended they are not shown to that install again
    func testOnceThePagesHaveEndedTheyAreNotShownToThatInstallAgain() {
        let flags = firstRun()
        XCTAssertTrue(flags.shouldShowTutorial(hasHistory: false, cameraGranted: false))

        _ = TutorialModel(replay: false).finish(flags)

        XCTAssertFalse(flags.shouldShowTutorial(hasHistory: false, cameraGranted: false))
    }

    /// back steps back a page, and out of the first page ends the pages
    func testBackStepsBackAPageAndOutOfTheFirstPageEndsThePages() {
        var model = TutorialModel(replay: false)
        _ = model.next()
        XCTAssertEqual(page(model).title, "Your Cindy, your movements")

        XCTAssertNil(model.systemBack())
        XCTAssertEqual(page(model).title, "Cindy, counted for you")

        XCTAssertEqual(model.systemBack(), .dismiss)
        // Ending is `finish`'s: the flags are marked there, as for SKIP.
        let flags = firstRun()
        XCTAssertEqual(model.finish(flags), .dismiss)
        XCTAssertTrue(flags.tutorialSeen)
    }

    /// BACK goes back a page
    func testBackGoesBackAPage() {
        var model = TutorialModel(replay: false)
        _ = model.next()
        _ = model.next()

        model.back()

        XCTAssertEqual(page(model).title, "Your Cindy, your movements")
    }

    // MARK: swiping

    /// a swipe to the left turns to the next page and one to the right comes back
    func testASwipeToTheLeftTurnsToTheNextPageAndOneToTheRightComesBack() {
        var model = TutorialModel(replay: false)

        model.swipe(dx: 300 - 800, dy: 520 - 500)
        XCTAssertEqual(page(model).title, "Your Cindy, your movements")

        model.swipe(dx: 800 - 300, dy: 480 - 500)
        XCTAssertEqual(page(model).title, "Cindy, counted for you")
    }

    /// a scroll up or down is not a swipe, and neither is a tap
    func testAScrollUpOrDownIsNotASwipeAndNeitherIsATap() {
        var model = TutorialModel(replay: false)

        model.swipe(dx: 480 - 500, dy: 300 - 1200)
        model.swipe(dx: 0, dy: 0)
        // Mostly up, a little across: a scroll that wandered.
        model.swipe(dx: 300 - 600, dy: 300 - 1200)

        XCTAssertEqual(page(model).title, "Cindy, counted for you")
        // The edges of the rule: exactly the distance is not far enough, and exactly twice is not more.
        XCTAssertNil(TutorialModel.swipeStep(dx: -64, dy: 0))
        XCTAssertNil(TutorialModel.swipeStep(dx: -100, dy: 50))
        XCTAssertEqual(TutorialModel.swipeStep(dx: -100, dy: 49), 1)
    }

    /// swiping past either end stays where it is
    func testSwipingPastEitherEndStaysWhereItIs() {
        var model = TutorialModel(replay: false)
        model.swipe(dx: 500, dy: 0)
        XCTAssertEqual(page(model).title, "Cindy, counted for you")

        toLastPage(&model)
        model.swipe(dx: -500, dy: 0)
        XCTAssertEqual(page(model).title, "Nothing leaves your phone")
    }

    // MARK: what each page says

    /// the second page says what counts, what is tapped in, and how to choose
    func testTheSecondPageSaysWhatCountsWhatIsTappedInAndHowToChoose() {
        var model = TutorialModel(replay: false)
        _ = model.next()
        let blocks = page(model).blocks

        guard case .movements(let rows)? = blocks.first(where: { if case .movements = $0 { return true } else { return false } })
        else { return XCTFail("no movements") }
        XCTAssertEqual(rows.map { $0.spoken }, [
            "Band-assisted pull-ups, counted",
            "Push-ups from the knees, counted",
            "Heels-flat, on-toes or box squats, counted",
            // "+1" is said as words, as the movement sheet says it.
            "Inverted rows, incline push-ups and more, you tap plus one"
        ])
        XCTAssertEqual(rows.map { $0.status }, ["counted", "counted", "counted", "you tap +1"])
        XCTAssertTrue(contains(model, "Spot heels-flat squats"))
        XCTAssertTrue(contains(model, "Sessions with other movements are saved as an Adaptive Cindy"))
        XCTAssertTrue(blocks.contains(.chooseMovements))
    }

    /// CHOOSE MY MOVEMENTS opens the movement sheet, and saving reports the choice
    func testChoosingMovementsKeepsTheChoiceAndReportsIt() {
        let profile = fresh()
        let toast = TutorialModel.choose(CindyProfile.standard, in: profile)

        // Nothing was changed in the sheet, so what is saved and said is the standard Cindy.
        XCTAssertEqual(toast, "Cindy")
        XCTAssertEqual(profile.movements, CindyProfile.standard)

        let adaptive = CindyProfile(pull: .bandAssistedPullUp, push: .kneePushUp, squat: .airSquat)
        XCTAssertEqual(TutorialModel.choose(adaptive, in: profile), adaptive.label())
        XCTAssertEqual(profile.movements, adaptive)
    }

    /// the third page shows where to stand, in a picture and in three facts
    func testTheThirdPageShowsWhereToStandInAPictureAndInThreeFacts() {
        var model = TutorialModel(replay: false)
        _ = model.next()
        _ = model.next()
        let p = page(model)

        XCTAssertEqual(p.title, "Where to stand")
        XCTAssertTrue(p.blocks.contains(.placementDiagram), "no placement diagram")
        XCTAssertTrue(p.texts.contains("Stand the phone up rather than laying it flat."))
        XCTAssertTrue(p.texts.contains("Keep your head and your feet both in shot."))
        XCTAssertTrue(contains(model, "moving it mid-workout resets what it has learned"))
    }

    /// the fourth page says what happens before the clock starts
    func testTheFourthPageSaysWhatHappensBeforeTheClockStarts() {
        var model = TutorialModel(replay: false)
        for _ in 0..<3 { _ = model.next() }

        XCTAssertEqual(page(model).title, "Before the clock starts")
        XCTAssertTrue(contains(model, "START checks your framing"))
        XCTAssertTrue(contains(model, "The dot on the status line turns green"))
        XCTAssertTrue(contains(model, "fix a miscount any time"))
        // iOS: there is no SKIP button on the camera screen; holding +1 is what moves on.
        XCTAssertTrue(contains(model, "Hold +1 to move on to the next movement."))
        XCTAssertFalse(contains(model, "SKIP moves on"))
    }

    /// the last page says nothing leaves the phone, and on a first run that the camera is next
    func testTheLastPageSaysNothingLeavesThePhoneAndOnAFirstRunThatTheCameraIsNext() {
        var model = TutorialModel(replay: false)
        toLastPage(&model)

        XCTAssertTrue(contains(model, "The picture is never uploaded"))
        XCTAssertTrue(contains(model, "REC films only when you tap it"))
        XCTAssertTrue(page(model).texts.contains("Next, iOS asks to use the camera."))
        XCTAssertEqual(TutorialModel.cameraFootnote, "Next, iOS asks to use the camera.")
    }

    // MARK: a replay

    /// the last page mentions Strava only in a build that has it
    func testTheLastPageMentionsStravaOnlyInABuildThatHasIt() {
        var model = TutorialModel(replay: false)
        toLastPage(&model)

        XCTAssertTrue(contains(model, "Strava stays off until you connect it in the menu", strava: true))
        XCTAssertFalse(contains(model, "Strava", strava: false), "a build without Strava talks about it")
        // No other page mentions it either, in a build without it.
        var every = TutorialModel(replay: false)
        for _ in 0..<TutorialModel.pageCount {
            XCTAssertFalse(contains(every, "Strava", strava: false))
            _ = every.next()
        }
    }

    /// a replay ends on DONE, without the camera footnote
    func testAReplayEndsOnDoneWithoutTheCameraFootnote() {
        var model = TutorialModel(replay: true)
        toLastPage(&model)

        XCTAssertEqual(model.nextLabel, "DONE")
        XCTAssertNotEqual(model.nextLabel, "LET'S GO")
        XCTAssertFalse(page(model).texts.contains("Next, iOS asks to use the camera."))
    }

    /// finishing a replay brings the camera screen back to the front
    func testFinishingAReplayBringsTheCameraScreenBackToTheFront() {
        let flags = firstRun()
        var model = TutorialModel(replay: true)
        toLastPage(&model)

        // Not a second camera screen: the existing one, closing the menu and the help above it.
        XCTAssertEqual(model.next(), .returnToCamera)
        XCTAssertEqual(model.finish(flags), .returnToCamera)
        XCTAssertTrue(flags.hudTourPending)
    }

    // MARK: Help

    private func help(features: HelpFeatures = []) -> HelpPage {
        HelpBuilder.build(HelpInput(attempts: [], features: features, versionName: "1.0", versionCode: "1"))
    }

    /// Help offers the tour first, and opens the pages as a replay
    func testHelpOffersTheTourFirstAndOpensThePagesAsAReplay() throws {
        let page = help()

        guard case .rows(let rows)? = page.blocks.first else { return XCTFail("the tour is not first") }
        let row = try XCTUnwrap(rows.first)
        XCTAssertTrue(row.spoken.hasPrefix("Take the tour"))
        XCTAssertEqual(row.action, .takeTour)
        // The action is a replay: it is the model's `replay` flag the screen sets.
        XCTAssertTrue(TutorialModel(replay: true).replay)
    }

    /// the tour row comes before the first heading
    func testTheTourRowComesBeforeTheFirstHeading() throws {
        let all = help().texts
        let tour = try XCTUnwrap(all.firstIndex(of: "Take the tour"))
        let workout = try XCTUnwrap(all.firstIndex(of: "THE WORKOUT"))
        XCTAssertTrue(tour < workout)
    }

    /// Help still builds and lays out with the row in it
    func testHelpStillBuildsWithTheRowInIt() {
        for features in [HelpFeatures(), HelpFeatures.all] {
            let page = help(features: features)
            XCTAssertFalse(page.blocks.isEmpty)
            XCTAssertTrue(page.text.contains("Take the tour"))
        }
    }

    // MARK: the pieces

    /// the placement facts are three rows
    func testThePlacementFactsAreThreeRows() {
        var model = TutorialModel(replay: false)
        _ = model.next()
        _ = model.next()
        guard case .placementFacts(let facts)? = page(model).blocks.first(where: {
            if case .placementFacts = $0 { return true } else { return false }
        }) else { return XCTFail("no facts") }
        XCTAssertEqual(facts.count, 3)
        XCTAssertEqual(facts.map { $0.text }, [
            "Stand the phone up rather than laying it flat.",
            "Keep your head and your feet both in shot.",
            "Then leave it there — moving it mid-workout resets what it has learned."
        ])
    }

    /// the flags start off and move one at a time
    func testTheFlagsStartOffAndMoveOneAtATime() {
        let flags = firstRun()
        XCTAssertFalse(flags.tutorialSeen)
        XCTAssertFalse(flags.hudTourPending)
        XCTAssertFalse(flags.placementDismissed)

        flags.tutorialSeen = true
        XCTAssertTrue(flags.tutorialSeen)
        XCTAssertFalse(flags.hudTourPending)

        flags.hudTourPending = true
        flags.hudTourPending = false
        XCTAssertFalse(flags.hudTourPending)
    }

    /// dismissing the placement guide is enough to be treated as a returning athlete
    func testDismissingThePlacementGuideIsEnoughToBeTreatedAsAReturningAthlete() {
        let suite = "cindy.tutorial.placement.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: Onboarding.keyPlacementSeen)

        let flags = FirstRun(defaults: defaults)
        XCTAssertTrue(flags.placementDismissed)
        XCTAssertFalse(flags.shouldShowTutorial(hasHistory: false, cameraGranted: false))
    }

    /// a session on record is enough too
    func testASessionOnRecordIsEnoughToo() {
        XCTAssertFalse(firstRun().shouldShowTutorial(hasHistory: true, cameraGranted: false))
    }

    /// so is a camera permission that is already held
    func testSoIsACameraPermissionThatIsAlreadyHeld() {
        XCTAssertFalse(firstRun().shouldShowTutorial(hasHistory: false, cameraGranted: true))
    }

    // MARK: not in the Kotlin: the model's own edges

    /// a screen restored mid-pages comes back to the page it was on, kept inside the pages
    func testAScreenRestoredMidPagesComesBackToThePageItWasOnKeptInsideThePages() {
        XCTAssertEqual(TutorialModel(replay: false, index: 3).index, 3)
        XCTAssertEqual(TutorialModel(replay: false, index: -2).index, 0)
        XCTAssertEqual(TutorialModel(replay: false, index: 99).index, TutorialModel.pageCount - 1)
    }

    /// the direction of the last move is kept, for the page to slide in from the right side
    func testTheDirectionOfTheLastMoveIsKept() {
        var model = TutorialModel(replay: false)
        _ = model.next()
        XCTAssertTrue(model.forward)
        model.back()
        XCTAssertFalse(model.forward)
        model.back() // already at the start: not a move
        XCTAssertFalse(model.forward)
    }

    /// each page change is announced by its title
    func testEachPageChangeIsAnnouncedByItsTitle() {
        var model = TutorialModel(replay: false)
        for title in TutorialModel.titles {
            XCTAssertEqual(model.announcement, title)
            _ = model.next()
        }
    }
}
