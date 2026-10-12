import XCTest
@testable import CindyCore

/// The tour of the camera screen, laid against a HUD. Port of `HudTourTest.kt`.
///
/// Robolectric inflated the real camera layout and read the views. The HUD cannot be built here, so
/// `Hud` stands in for it: the same two bands on a 1080 by 2400 screen, the top one holding the
/// status line, REC and the menu, the bottom one START, the reps, SKIP and FLIP, each at a size and
/// place like the real ones. What is held is the same: a caption pointing at nothing, a hole cut
/// where a control used to be, a control that is hidden still being lit. Where the caption goes is
/// `SpotlightMathTests`, and that the words are the Kotlin's is `HudTourTests`.
final class SpotlightTourTests: XCTestCase {

    private let bounds = SpotlightRect(x: 0, y: 0, width: 1080, height: 2400)
    private let captionHeight: Float = 300

    /// A stand-in for the inflated HUD: where each control is, and whether it, or the band it is in,
    /// is showing.
    private struct Hud {
        var frames: [HudTour.Target: SpotlightRect] = [
            .status: SpotlightRect(x: 40, y: 140, width: 1000, height: 90),
            .record: SpotlightRect(x: 760, y: 260, width: 120, height: 120),
            .menu: SpotlightRect(x: 900, y: 260, width: 120, height: 120),
            .start: SpotlightRect(x: 340, y: 2150, width: 400, height: 150),
            .reps: SpotlightRect(x: 300, y: 1900, width: 480, height: 200),
            .skip: SpotlightRect(x: 760, y: 2150, width: 150, height: 150),
            .flip: SpotlightRect(x: 930, y: 2150, width: 110, height: 110)
        ]
        var hidden: Set<HudTour.Target> = []
        var bottomBandHidden = false

        static let bottomBand: Set<HudTour.Target> = [.start, .reps, .skip, .flip]

        func frame(_ target: HudTour.Target) -> SpotlightRect? {
            if hidden.contains(target) { return nil }
            if bottomBandHidden && Self.bottomBand.contains(target) { return nil }
            return frames[target]
        }
    }

    private func started(_ hud: Hud = Hud()) -> (SpotlightTour, Hud) {
        var tour = SpotlightTour()
        XCTAssertTrue(tour.start(HudTour.steps, frame: hud.frame))
        return (tour, hud)
    }

    private func hole(_ tour: SpotlightTour, _ hud: Hud) -> SpotlightRect {
        SpotlightTour.window(around: hud.frame(tour.current!.target)!, in: bounds)
    }

    // MARK: the steps against the layout

    /// the tour has a step for each of the seven controls it names
    func testTheTourHasAStepForEachOfTheSevenControlsItNames() {
        let (tour, _) = started()

        XCTAssertTrue(tour.isShowing)
        XCTAssertEqual(tour.stepCount, 7)
        XCTAssertEqual(tour.stepIndex, 0)
    }

    /// every step lights a real window on the screen
    func testEveryStepLightsARealWindowOnTheScreen() {
        let hud = Hud()
        var (tour, _) = started(hud)

        for step in 0..<tour.stepCount {
            let hole = hole(tour, hud)
            XCTAssertTrue(hole.width > 0 && hole.height > 0, "step \(step): empty hole \(hole)")
            XCTAssertTrue(hole.minX >= 0 && hole.minY >= 0 && hole.maxX <= bounds.width && hole.maxY <= bounds.height,
                          "step \(step): hole \(hole) runs off the screen")
            if step < tour.stepCount - 1 { XCTAssertFalse(tour.advance()) }
        }
    }

    /// the hole sits on the control the step is about
    func testTheHoleSitsOnTheControlTheStepIsAbout() {
        let hud = Hud()
        var (tour, _) = started(hud)
        let targets = HudTour.steps.map { $0.target }

        for (step, target) in targets.enumerated() {
            XCTAssertEqual(tour.stepIndex, step)
            let box = hud.frame(target)!
            let hole = hole(tour, hud)
            XCTAssertTrue(hole.minX <= box.minX && hole.minY <= box.minY && hole.maxX >= box.maxX && hole.maxY >= box.maxY,
                          "step \(step): \(hole) does not hold \(box)")
            // Around it, not a screenful: a hole that swallowed the HUD would point at nothing.
            XCTAssertTrue(hole.width < box.width + 100, "step \(step): \(hole) is far bigger than \(box)")
            XCTAssertTrue(hole.height < box.height + 100, "step \(step): \(hole) is far bigger than \(box)")
            if step < targets.count - 1 { _ = tour.advance() }
        }
    }

    /// the caption fits on the screen and stays off the control it is about
    func testTheCaptionFitsOnTheScreenAndStaysOffTheControlItIsAbout() {
        let hud = Hud()
        var (tour, _) = started(hud)

        for step in 0..<tour.stepCount {
            let hole = hole(tour, hud)
            let top = SpotlightTour.captionTop(window: hole, captionHeight: captionHeight, screenHeight: bounds.height)
            let bottom = top + captionHeight
            XCTAssertTrue(top >= 0 && bottom <= bounds.height, "step \(step): card \(top)–\(bottom) runs off the screen")
            let overlaps = top < hole.maxY && bottom > hole.minY
            XCTAssertFalse(overlaps, "step \(step): card \(top)–\(bottom) covers the hole \(hole)")
            if step < tour.stepCount - 1 { _ = tour.advance() }
        }
    }

    /// each step says its title and what it is for
    func testEachStepSaysItsTitleAndWhatItIsFor() {
        var (tour, _) = started()

        for (index, step) in HudTour.steps.enumerated() {
            XCTAssertEqual(tour.current?.title, step.title, "no title for step \(index)")
            XCTAssertEqual(tour.current?.body, step.body, "no body for step \(index)")
            XCTAssertEqual(tour.announcement, "\(step.title). \(step.body)")
            if index < HudTour.steps.count - 1 { _ = tour.advance() }
        }
    }

    // MARK: the flow

    /// the last step says DONE, and finishing calls back once and puts the tour away
    func testTheLastStepSaysDoneAndFinishingCallsBackOnceAndPutsTheTourAway() {
        var (tour, _) = started()
        var done = 0

        for _ in 0..<(tour.stepCount - 1) { if tour.advance() { done += 1 } }
        XCTAssertEqual(tour.nextLabel, "DONE")
        XCTAssertEqual(done, 0)

        if tour.advance() { done += 1 }

        XCTAssertEqual(done, 1)
        XCTAssertFalse(tour.isShowing)
        XCTAssertNil(tour.current)
    }

    /// skipping at any step calls back once
    func testSkippingAtAnyStepCallsBackOnce() {
        var (tour, _) = started()
        var done = 0
        for _ in 0..<3 { _ = tour.advance() }
        XCTAssertEqual(tour.nextLabel, "NEXT")
        XCTAssertEqual(SpotlightTour.skipLabel, "SKIP TOUR")

        if tour.skip() { done += 1 }

        XCTAssertEqual(done, 1)
        XCTAssertFalse(tour.isShowing)
    }

    /// it calls back once however many times it is ended
    func testItCallsBackOnceHoweverManyTimesItIsEnded() {
        var (tour, _) = started()
        var done = 0

        for _ in 0..<3 { if tour.skip() { done += 1 } }
        if tour.advance() { done += 1 }

        XCTAssertEqual(done, 1)
    }

    /// a tap anywhere on the dimmed screen moves on
    func testATapAnywhereOnTheDimmedScreenMovesOn() {
        var (tour, _) = started()

        _ = tour.advance()
        XCTAssertEqual(tour.stepIndex, 1)
        _ = tour.advance()
        XCTAssertEqual(tour.stepIndex, 2)
    }

    /// it takes every touch while it is showing
    func testItTakesEveryTouchWhileItIsShowing() {
        var (tour, _) = started()
        XCTAssertTrue(tour.takesEveryTouch)
        _ = tour.skip()
        XCTAssertFalse(tour.takesEveryTouch)
    }

    // MARK: the screen beneath

    /// while the tour shows, the screen under it is hidden from a screen reader, and back after
    func testWhileTheTourShowsTheScreenUnderItIsHiddenFromAScreenReaderAndBackAfter() {
        var tour = SpotlightTour()
        XCTAssertFalse(tour.hidesScreenBeneath)

        XCTAssertTrue(tour.start(HudTour.steps, frame: Hud().frame))
        XCTAssertTrue(tour.hidesScreenBeneath)

        _ = tour.skip()
        XCTAssertFalse(tour.hidesScreenBeneath)
    }

    /// the hole follows a control that has moved
    func testTheHoleFollowsAControlThatHasMoved() {
        var (tour, hud) = started()
        _ = tour.advance() // the status line
        let before = hole(tour, hud)

        // The status line grows, as it does when its text wraps. The window is a function of where
        // the control is now, so asking again after the screen was laid out again gives the new one.
        hud.frames[.status]!.height = 300
        let after = hole(tour, hud)

        XCTAssertGreaterThan(after.height, before.height, "the hole did not grow with the control: \(before), then \(after)")
        XCTAssertEqual(after.minY, before.minY)
    }

    /// looking again at a control that has not moved changes nothing
    func testLookingAgainAtAControlThatHasNotMovedChangesNothing() {
        let (tour, hud) = started()
        XCTAssertEqual(hole(tour, hud), hole(tour, hud))
    }

    // MARK: what is left out

    /// a control that is not showing is left out of the tour
    func testAControlThatIsNotShowingIsLeftOutOfTheTour() {
        var hud = Hud()
        hud.hidden = [.skip]
        var (tour, _) = started(hud)

        XCTAssertEqual(tour.stepCount, 6)
        var titles: [String] = []
        for i in 0..<6 {
            titles.append(tour.current!.title)
            if i < 5 { _ = tour.advance() }
        }
        XCTAssertFalse(titles.contains("Skip"), "Skip was lit though its control is gone")
        XCTAssertEqual(titles, HudTour.steps.map { $0.title }.filter { $0 != "Skip" })
    }

    /// with nothing to point at it is done at once and never shown
    func testWithNothingToPointAtItIsDoneAtOnceAndNeverShown() {
        var tour = SpotlightTour()
        // A control with no size yet is no better than a hidden one.
        let started = tour.start([HudTour.steps[0]]) { _ in SpotlightRect(x: 0, y: 0, width: 0, height: 0) }

        XCTAssertFalse(started, "the owner is done at once")
        XCTAssertFalse(tour.isShowing)
        XCTAssertTrue(tour.start([], frame: { _ in nil }) == false)
    }

    /// a control whose parent is hidden is left out too
    func testAControlWhoseParentIsHiddenIsLeftOutToo() {
        var hud = Hud()
        hud.bottomBandHidden = true
        let (tour, _) = started(hud)

        // Everything in the bottom band goes with it: start, reps, skip, flip.
        XCTAssertEqual(tour.stepCount, 3)
    }

    /// the camera HUD still inflates with the tour in it
    func testTheCameraHudStillInflatesWithTheTourInIt() {
        let tour = SpotlightTour()
        XCTAssertFalse(tour.isShowing, "the tour starts hidden")
        XCTAssertEqual(tour.stepCount, 0)
        XCTAssertNil(tour.announcement)
        for target in HudTour.Target.allCases { XCTAssertNotNil(Hud().frame(target), "\(target) has no place on the screen") }
    }

    // MARK: not in the Kotlin: the arithmetic

    /// a window is kept on the screen, and a corner is never more than half the shorter side
    func testAWindowIsKeptOnTheScreenAndACornerIsNeverMoreThanHalfTheShorterSide() {
        let edge = SpotlightRect(x: 0, y: 2300, width: 100, height: 100)
        let window = SpotlightTour.window(around: edge, in: bounds)
        XCTAssertEqual(window, SpotlightRect(x: 0, y: 2292, width: 108, height: 108))
        XCTAssertEqual(SpotlightTour.cornerRadius(of: window), 18)
        XCTAssertEqual(SpotlightTour.cornerRadius(of: SpotlightRect(x: 0, y: 0, width: 20, height: 100)), 10)
    }

    /// a control wholly off the screen is lit where it is, as Android does
    func testAControlWhollyOffTheScreenIsLitWhereItIsAsAndroidDoes() {
        let off = SpotlightRect(x: 0, y: 5000, width: 100, height: 100)
        XCTAssertEqual(SpotlightTour.window(around: off, in: bounds), SpotlightRect(x: -8, y: 4992, width: 116, height: 116))
    }
}
