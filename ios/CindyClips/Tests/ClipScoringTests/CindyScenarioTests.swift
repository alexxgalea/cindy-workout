import XCTest
import CindyCore
import CindyFixtures
import ClipScoring

/// The `cindy` scenarios: the whole progression, with the athlete's own controls.
final class CindyScenarioTests: XCTestCase {

    private func cindy(by movement: [String: Int], setup: String? = nil,
                       skipTo: [Scenario.SkipTo]? = nil, events: [Int]? = nil) -> Scenario {
        Scenario(id: "cindy", video: "cindy.mp4", exercise: "cindy", expectedRepEventsMs: events,
                 tags: ["youtube"], setup: setup, skipTo: skipTo, expectedRepsByMovement: movement)
    }

    /// One round, with the SKIP button pressed at the start so nothing is spent on calibration.
    private func oneRound() -> [ClipFrame] {
        var clip = ClipBuilder()
        clip.hold(PoseFixtures.pullup(170))
        for _ in 0..<5 { clip.pullup() }
        clip.hold(PoseFixtures.pullup(170))
        clip.hold(PoseFixtures.pushup(175))
        clip.pushups(10)
        clip.hold(PoseFixtures.squat(175))
        clip.squats(15)
        return clip.frames
    }

    func testAWholeRoundIsScoredMovementByMovement() {
        let report = ScenarioScorer.score(cindy(by: ["pullup": 5, "pushup": 10, "squat": 15], setup: "skip"),
                                          frames: oneRound())
        XCTAssertEqual(report.exercise, "cindy")
        XCTAssertEqual(report.perMovement["pullup"]?.observed, 5)
        XCTAssertEqual(report.perMovement["pushup"]?.observed, 10)
        XCTAssertEqual(report.perMovement["squat"]?.observed, 15)
        XCTAssertEqual(report.perMovement["pullup"]?.eventsMs.count, 5)
        XCTAssertEqual(report.expectedReps, 30)
        XCTAssertEqual(report.observedReps, 30)
        XCTAssertEqual(report.failures, [])
        XCTAssertEqual(report.countTimes.count, 30)
    }

    /// the rep that finishes a movement belongs to the movement it finished, not the next one
    func testTheRepThatFinishesAMovementIsCountedToThatMovement() {
        let report = ScenarioScorer.score(cindy(by: [:], setup: "skip"), frames: oneRound())
        let lastPullup = report.perMovement["pullup"]!.eventsMs.last!
        let firstPushup = report.perMovement["pushup"]!.eventsMs.first!
        XCTAssertLessThan(lastPullup, firstPushup)
        XCTAssertEqual(report.perMovement["pullup"]?.observed, 5)
    }

    func testAWrongLabelNamesTheMovement() {
        let report = ScenarioScorer.score(cindy(by: ["pullup": 5, "pushup": 11, "squat": 15], setup: "skip"),
                                          frames: oneRound())
        XCTAssertEqual(report.failures, ["pushup: expected 11 reps, observed 10"])
    }

    /// without the skip, calibration spends the first two pull-ups and the label includes them
    func testCalibrationSpendsTheFirstTwoPullups() {
        var clip = ClipBuilder()
        clip.hold(PoseFixtures.pullup(170))
        for _ in 0..<2 { clip.pullup() }          // calibration
        clip.hold(PoseFixtures.pullup(170))
        for _ in 0..<3 { clip.pullup() }          // the workout's first three
        clip.hold(PoseFixtures.pullup(170))
        let report = ScenarioScorer.score(cindy(by: ["pullup": 5]), frames: clip.frames)
        XCTAssertEqual(report.setup, "ready")
        XCTAssertEqual(report.perMovement["pullup"]?.observed, 3)
        XCTAssertEqual(report.failures, ["pullup: expected 5 reps, observed 3"])
        XCTAssertEqual(ScenarioScorer.score(cindy(by: ["pullup": 3]), frames: clip.frames).failures, [])
    }

    func testASetupThatNeverGetsReadyScoresNothingAndSaysSo() {
        var clip = ClipBuilder()
        clip.hold(PoseFixtures.empty(), frames: 30)
        let report = ScenarioScorer.score(cindy(by: ["pullup": 0]), frames: clip.frames)
        XCTAssertEqual(report.failures, ["setup never reached READY -- no workout frames were scored"])
        XCTAssertEqual(report.observedReps, 0)
        XCTAssertEqual(report.setup, "framing")
        XCTAssertEqual(report.status, .failed)
    }

    /// the athlete taps skip when the app has not moved on by itself
    func testSkipToMovesOnAtTheTimeGiven() {
        var clip = ClipBuilder()
        clip.hold(PoseFixtures.pullup(170))
        clip.pullup()                              // one pull-up, short of five
        clip.hold(PoseFixtures.pullup(170))
        let skipAt = Int(clip.clock)
        clip.hold(PoseFixtures.pushup(175))
        clip.pushups(4)
        let report = ScenarioScorer.score(
            cindy(by: ["pullup": 1, "pushup": 4], setup: "skip",
                  skipTo: [.init(atMs: skipAt, movement: "pushup")]),
            frames: clip.frames)
        XCTAssertEqual(report.perMovement["pullup"]?.observed, 1)
        XCTAssertEqual(report.perMovement["pushup"]?.observed, 4)
        XCTAssertEqual(report.failures, [])
        // Without the skip the engine is still waiting for pull-ups.
        let stuck = ScenarioScorer.score(cindy(by: ["pullup": 1, "pushup": 4], setup: "skip"), frames: clip.frames)
        XCTAssertEqual(stuck.perMovement["pushup"]?.observed, 0)
    }

    /// a movement the engine already reached by itself is left alone
    func testSkipToNeverSkipsAMovementTheEngineAlreadyReached() {
        let report = ScenarioScorer.score(
            cindy(by: ["pullup": 5, "pushup": 10], setup: "skip",
                  skipTo: [.init(atMs: 0, movement: "pullup"), .init(atMs: 1, movement: "pullup")]),
            frames: oneRound())
        XCTAssertEqual(report.perMovement["pullup"]?.observed, 5)
        XCTAssertEqual(report.perMovement["pushup"]?.observed, 10)
    }

    /// skips are taken in the order of their times, whatever order the file lists them in
    func testSkipsAreTakenInTimeOrderWhateverTheOrderListed() {
        var clip = ClipBuilder()
        clip.hold(PoseFixtures.pullup(170))
        clip.pullup()
        clip.hold(PoseFixtures.pullup(170))
        let toPushups = Int(clip.clock)
        clip.hold(PoseFixtures.pushup(175))
        clip.pushups(3)
        clip.hold(PoseFixtures.squat(175))
        let toSquats = Int(clip.clock)
        clip.hold(PoseFixtures.squat(175))
        clip.squats(3)
        let report = ScenarioScorer.score(
            cindy(by: ["pullup": 1, "pushup": 3, "squat": 3], setup: "skip",
                  skipTo: [.init(atMs: toSquats, movement: "squat"), .init(atMs: toPushups, movement: "pushup")]),
            frames: clip.frames)
        XCTAssertEqual(report.failures, [])
        XCTAssertEqual(report.perMovement["pushup"]?.observed, 3)
        XCTAssertEqual(report.perMovement["squat"]?.observed, 3)
    }

    func testAnUnknownSkipTargetIsNamed() {
        let report = ScenarioScorer.score(
            cindy(by: [:], setup: "skip", skipTo: [.init(atMs: 0, movement: "burpee")]), frames: oneRound())
        XCTAssertEqual(report.failures, ["unsupported exercise 'burpee'"])
    }

    func testTheRowsOfACindyReportCarryTheMovementAndIdentity() {
        let report = ScenarioScorer.score(cindy(by: [:], setup: "skip"), frames: oneRound())
        let row = report.frames[0]
        XCTAssertEqual(Set(row.keys), ["timestampMs", "event", "exercise", "count", "state", "signal",
                                       "rejection", "poseLegible", "identityStable", "softGain", "health"])
        XCTAssertEqual(row["exercise"], .string("PULL-UPS"))
    }

    func testTimeSpentLostIsReportedForTheWholeCindy() {
        var clip = ClipBuilder()
        clip.hold(PoseFixtures.pullup(170))
        for _ in 0..<3 { clip.pullup() }
        let seen = clip.frames.count
        clip.hold(PoseFixtures.pullup(170), frames: 150)    // the hands are never seen again
        for i in seen..<clip.frames.count {
            clip.frames[i].keypoints[KP.leftWrist] = .missing
            clip.frames[i].keypoints[KP.rightWrist] = .missing
        }
        let report = ScenarioScorer.score(cindy(by: [:], setup: "skip"), frames: clip.frames)
        XCTAssertEqual(report.worstHealth, "LOST")
        XCTAssertGreaterThan(report.lostMs, 0)
        let expectation = Scenario(id: "c", video: "v", exercise: "cindy", expectedTracking: "good", setup: "skip",
                                   expectedRepsByMovement: [:])
        XCTAssertEqual(ScenarioScorer.score(expectation, frames: clip.frames).failures,
                       ["expected tracking to reach GOOD, observed LOST"])
    }
}
