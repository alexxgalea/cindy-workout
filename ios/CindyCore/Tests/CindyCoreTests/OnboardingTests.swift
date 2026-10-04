import XCTest
import CindyCore

/// When a new athlete is shown around. Port of `OnboardingTest.kt`, with the flags' own tests: the
/// Kotlin `FirstRun` is Android preferences and had none.
final class OnboardingTests: XCTestCase {

    private func show(seen: Bool = false, history: Bool = false, dismissed: Bool = false, camera: Bool = false) -> Bool {
        Onboarding.shouldShowTutorial(seen: seen, hasHistory: history, placementDismissed: dismissed, cameraGranted: camera)
    }

    /// a new install is shown around
    func testANewInstallIsShownAround() { XCTAssertTrue(show()) }

    /// nobody is shown around twice
    func testNobodyIsShownAroundTwice() { XCTAssertFalse(show(seen: true)) }

    /// someone with a session on record has used the app
    func testSomeoneWithASessionOnRecordHasUsedTheApp() { XCTAssertFalse(show(history: true)) }

    /// someone who dismissed the placement guide has used the app, records or not
    func testSomeoneWhoDismissedThePlacementGuideHasUsedTheAppRecordsOrNot() { XCTAssertFalse(show(dismissed: true)) }

    /// someone who already holds the camera permission has used the app
    func testSomeoneWhoAlreadyHoldsTheCameraPermissionHasUsedTheApp() {
        // A fresh install cannot: it starts without it. An athlete who updated from a version older
        // than these pages has held it since the first time they opened the camera, and may never
        // have finished a session or met the placement guide.
        XCTAssertFalse(show(camera: true))
    }

    /// any one sign that the app is not new is enough, and every combination agrees
    func testAnyOneSignThatTheAppIsNotNewIsEnoughAndEveryCombinationAgrees() {
        for bits in 0..<16 {
            let seen = bits & 1 != 0
            let history = bits & 2 != 0
            let dismissed = bits & 4 != 0
            let camera = bits & 8 != 0
            XCTAssertEqual(show(seen: seen, history: history, dismissed: dismissed, camera: camera), bits == 0,
                           "seen=\(seen) history=\(history) dismissed=\(dismissed) camera=\(camera)")
        }
    }

    /// the keys are the ones already on disk and never collide
    func testTheKeysAreTheOnesAlreadyOnDiskAndNeverCollide() {
        // The placement key is an athlete's existing choice; renaming it would show the guide again.
        XCTAssertEqual(Onboarding.keyPlacementSeen, "placement_guide_dismissed")
        XCTAssertEqual(Set([Onboarding.keyTutorialSeen, Onboarding.keyHudTourPending, Onboarding.keyPlacementSeen]).count, 3)
        XCTAssertEqual(Onboarding.keyTutorialSeen, "tutorial_seen")
        XCTAssertEqual(Onboarding.keyHudTourPending, "hud_tour_pending")
    }

    // MARK: the flags (FirstRun)

    private func defaults() -> UserDefaults {
        let suite = "cindy.firstrun.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        addTeardownBlock { d.removePersistentDomain(forName: suite) }
        return d
    }

    func testAFreshInstallHasNoFlagsSet() {
        let first = FirstRun(defaults: defaults())
        XCTAssertFalse(first.tutorialSeen)
        XCTAssertFalse(first.hudTourPending)
        XCTAssertFalse(first.placementDismissed)
        XCTAssertTrue(first.shouldShowTutorial(hasHistory: false, cameraGranted: false))
    }

    func testFinishingThePagesMarksThemSeenAndQueuesTheTour() {
        let first = FirstRun(defaults: defaults())
        first.finishPages()
        XCTAssertTrue(first.tutorialSeen)
        XCTAssertTrue(first.hudTourPending)
        XCTAssertFalse(first.shouldShowTutorial(hasHistory: false, cameraGranted: false))
    }

    func testTheFlagsSurviveANewObjectOverTheSameDefaults() {
        let d = defaults()
        FirstRun(defaults: d).finishPages()
        let again = FirstRun(defaults: d)
        XCTAssertTrue(again.tutorialSeen)
        again.hudTourPending = false
        XCTAssertFalse(FirstRun(defaults: d).hudTourPending)
        XCTAssertTrue(FirstRun(defaults: d).tutorialSeen)
    }

    func testTheFlagsAreStoredUnderTheKeysAndAPlacementDismissalCountsAsHistory() {
        let d = defaults()
        let first = FirstRun(defaults: d)
        d.set(true, forKey: "placement_guide_dismissed")
        XCTAssertTrue(first.placementDismissed)
        XCTAssertFalse(first.shouldShowTutorial(hasHistory: false, cameraGranted: false))
        first.tutorialSeen = true
        XCTAssertTrue(d.bool(forKey: "tutorial_seen"))
        first.hudTourPending = true
        XCTAssertTrue(d.bool(forKey: "hud_tour_pending"))
    }

    func testHistoryAndCameraPermissionStopThePagesWhateverTheFlagsSay() {
        let first = FirstRun(defaults: defaults())
        XCTAssertFalse(first.shouldShowTutorial(hasHistory: true, cameraGranted: false))
        XCTAssertFalse(first.shouldShowTutorial(hasHistory: false, cameraGranted: true))
    }
}
