import XCTest
import CindyCore
import CindyFixtures
import ClipScoring

/// What `ScenarioScorer` does with a clip's frames, pinned against what `run_batch.py` does: the
/// same checks, and the same words when one fails.
final class ScenarioScorerTests: XCTestCase {

    private func scenario(_ exercise: String, expected: Int? = nil, setup: String? = nil,
                          state: String? = nil, events: [Int]? = nil, tolerance: Int? = nil,
                          tracking: String? = nil, pull: String? = nil, tags: [String]? = nil) -> Scenario {
        Scenario(id: "clip", video: "clip.mp4", exercise: exercise, expectedReps: expected,
                 expectedSetup: setup, expectedCountingState: state, expectedRepEventsMs: events,
                 countTolerance: tolerance, expectedTracking: tracking, pull: pull, tags: tags)
    }

    private func pushups(_ n: Int) -> [ClipFrame] {
        var clip = ClipBuilder()
        clip.hold(PoseFixtures.pushup(175))
        clip.pushups(n)
        return clip.frames
    }

    func testAnExactCountPasses() {
        let report = ScenarioScorer.score(scenario("pushup", expected: 4), frames: pushups(4))
        XCTAssertEqual(report.observedReps, 4)
        XCTAssertEqual(report.signedError, 0)
        XCTAssertEqual(report.failures, [])
        XCTAssertEqual(report.status, .passed)
        XCTAssertEqual(report.countTimes.count, 4)
        XCTAssertEqual(report.frames.count, pushups(4).count)
    }

    /// the count is the production engine's, whatever it is: a wrong label fails with run_batch's words
    func testAWrongLabelFailsInTheWordsOfTheHarness() {
        let report = ScenarioScorer.score(scenario("pushup", expected: 5), frames: pushups(4))
        XCTAssertEqual(report.failures, ["expected 5 reps, observed 4"])
        XCTAssertEqual(report.signedError, -1)
        XCTAssertEqual(report.status, .failed)
    }

    /// a tolerance is a policy, not a lowered expectation
    func testAToleranceLetsAScenarioPassButTheErrorIsStillReported() {
        let report = ScenarioScorer.score(scenario("pushup", expected: 5, tolerance: 1), frames: pushups(4))
        XCTAssertEqual(report.failures, [])
        XCTAssertEqual(report.signedError, -1)
        XCTAssertTrue(report.withinTolerance)
        let tooFar = ScenarioScorer.score(scenario("pushup", expected: 6, tolerance: 1), frames: pushups(4))
        XCTAssertEqual(tooFar.failures, ["expected 6 reps, observed 4 (tolerance 1)"])
    }

    /// push-ups scored as pull-ups must not count
    func testAMustNotCountClipCountsNothing() {
        let report = ScenarioScorer.score(scenario("pullup", expected: 0, tags: ["must-not-count"]), frames: pushups(6))
        XCTAssertEqual(report.observedReps, 0)
        XCTAssertEqual(report.category, "must-not-count")
        XCTAssertEqual(report.status, .passed)
    }

    func testCategoriesKeepValidAndInvalidClipsApart() {
        func category(_ expected: Int, _ tags: [String]) -> String {
            ScenarioReport(id: "x", exercise: "pullup", expectedReps: expected, tags: tags).category
        }
        XCTAssertEqual(category(0, ["occlusion"]), "must-not-count")
        XCTAssertEqual(category(5, []), "clean-valid")
        XCTAssertEqual(category(5, ["youtube", "pullups"]), "clean-valid")
        for tag in ["occlusion", "camera-cut", "known-gap"] {
            XCTAssertEqual(category(5, [tag]), "difficult-but-valid", tag)
        }
    }

    // MARK: setup

    private func twoPullups() -> [ClipFrame] {
        var clip = ClipBuilder()
        clip.hold(PoseFixtures.pullup(170))
        clip.pullup()
        clip.pullup()
        clip.hold(PoseFixtures.pullup(170))
        return clip.frames
    }

    func testSetupIsCheckedOnItsOwnEngine() {
        let frames = twoPullups()
        for expectation in ["valid", "ready", "VALID"] {
            let report = ScenarioScorer.score(scenario("pullup", expected: 2, setup: expectation), frames: frames)
            XCTAssertEqual(report.setup, "ready", expectation)
            XCTAssertEqual(report.failures.filter { $0.contains("setup") }, [], expectation)
        }
        let framing = ScenarioScorer.score(scenario("pullup", expected: 2, setup: "framing"), frames: frames)
        XCTAssertEqual(framing.failures.filter { $0.contains("setup") },
                       ["expected setup 'framing', observed 'ready'"])
        let nonsense = ScenarioScorer.score(scenario("pullup", expected: 2, setup: "sideways"), frames: frames)
        XCTAssertTrue(nonsense.failures.contains("unsupported expectedSetup 'sideways'"))
    }

    func testAnEmptyClipIsFramingNotReady() {
        var clip = ClipBuilder()
        clip.hold(PoseFixtures.empty(), frames: 20)
        let report = ScenarioScorer.score(scenario("pullup", expected: 0, setup: "framing"), frames: clip.frames)
        XCTAssertEqual(report.setup, "framing")
        XCTAssertEqual(report.failures, [])
    }

    // MARK: the other expectations

    func testTheFinalCountingStateIsChecked() {
        let frames = pushups(2)
        let ok = ScenarioScorer.score(scenario("pushup", expected: 2, state: "up"), frames: frames)
        XCTAssertEqual(ok.failures, [])
        let wrong = ScenarioScorer.score(scenario("pushup", expected: 2, state: "down"), frames: frames)
        XCTAssertEqual(wrong.failures, ["expected final state 'down', observed 'up'"])
    }

    func testCountEventsAreCheckedAgainstTheirTimestamps() {
        let frames = pushups(2)
        let times = ScenarioScorer.score(scenario("pushup", expected: 2), frames: frames).countTimes.map { Int($0) }
        XCTAssertEqual(times.count, 2)
        XCTAssertEqual(ScenarioScorer.score(scenario("pushup", expected: 2, events: times), frames: frames).failures, [])
        XCTAssertEqual(ScenarioScorer.score(scenario("pushup", expected: 2, events: times.map { $0 + 400 }), frames: frames).failures, [])
        XCTAssertEqual(
            ScenarioScorer.score(scenario("pushup", expected: 2, events: [times[0], times[1] + 900]), frames: frames).failures,
            ["event 2: expected about \(times[1] + 900)ms, observed \(times[1])ms"])
        XCTAssertEqual(
            ScenarioScorer.score(scenario("pushup", expected: 2, events: [times[0]]), frames: frames).failures,
            ["expected 1 count events, observed 2"])
    }

    func testTheMonitorsVerdictCanBeAsserted() {
        let report = ScenarioScorer.score(scenario("pushup", expected: 4, tracking: "lost"), frames: pushups(4))
        XCTAssertEqual(report.worstHealth, "GOOD")
        XCTAssertEqual(report.failures, ["expected tracking to reach LOST, observed GOOD"])
    }

    func testUnsupportedThingsAreNamed() {
        XCTAssertEqual(ScenarioScorer.score(scenario("burpee", expected: 1), frames: pushups(1)).failures,
                       ["unsupported exercise 'burpee'"])
        XCTAssertEqual(ScenarioScorer.score(scenario("pullup", expected: 1, pull: "kipping"), frames: pushups(1)).failures,
                       ["unsupported pull variant 'kipping'"])
        XCTAssertEqual(ScenarioScorer.score(scenario("pullup", expected: 1), frames: []).failures,
                       ["no frames were read from the video"])
    }

    func testBothPullVariantsAreAcceptedAndCountACleanSet() {
        // Only the pull-up gate branches on the profile, so the band-assisted variant is the one
        // the harness has a map for. Both must at least run and agree on a clean set.
        var clip = ClipBuilder()
        clip.hold(PoseFixtures.pullup(170))
        for _ in 0..<3 { clip.pullup() }
        clip.hold(PoseFixtures.pullup(170))
        let strict = ScenarioScorer.score(scenario("pullup", expected: 3, pull: "strict"), frames: clip.frames)
        let band = ScenarioScorer.score(scenario("pullups", expected: 3, pull: "band_assisted"), frames: clip.frames)
        XCTAssertEqual(strict.observedReps, 3)
        XCTAssertEqual(band.observedReps, 3)
    }

    func testRejectionsAreTalliedByGateMostFirst() {
        let report = ScenarioScorer.score(scenario("pullup", expected: 0), frames: pushups(3))
        let tally = report.rejectionsByGate
        XCTAssertFalse(tally.isEmpty)
        XCTAssertEqual(tally.map { $0.frames }, tally.map { $0.frames }.sorted(by: >))
        XCTAssertEqual(tally.map { $0.frames }.reduce(0, +), report.frames.count)
    }

    // MARK: the manual bar

    /// The wrists hang at (±10, -100) in the fixture, so shifted by (360, 700) they are at 0.47 of the
    /// frame's height and 0.49 to 0.51 of its width.
    private func pullupsInTheFrame() -> [ClipFrame] {
        var clip = ClipBuilder()
        clip.shift = (360, 700)
        clip.hold(PoseFixtures.pullup(170))
        for _ in 0..<3 { clip.pullup() }
        clip.hold(PoseFixtures.pullup(170))
        return clip.frames
    }

    func testAManualBarIsPassedToTheEngineInNormalisedCoordinates() {
        let frames = pullupsInTheFrame()
        var onTheHands = scenario("pullup", expected: 3)
        onTheHands.bar = .init(mode: "manual", yNormalized: 0.47, xMinNormalized: 0.3, xMaxNormalized: 0.7)
        XCTAssertEqual(ScenarioScorer.score(onTheHands, frames: frames).observedReps, 3)

        var farAway = scenario("pullup", expected: 3)
        farAway.bar = .init(mode: "manual", yNormalized: 0.95, xMinNormalized: 0.3, xMaxNormalized: 0.7)
        XCTAssertEqual(ScenarioScorer.score(farAway, frames: frames).observedReps, 0)

        var offToTheSide = scenario("pullup", expected: 3)
        offToTheSide.bar = .init(mode: "manual", yNormalized: 0.47, xMinNormalized: 0.0, xMaxNormalized: 0.1)
        XCTAssertEqual(ScenarioScorer.score(offToTheSide, frames: frames).observedReps, 0)
    }

    /// a bar that is not manual is the engine's to find
    func testABarThatIsNotManualIsLeftAlone() {
        var auto = scenario("pullup", expected: 3)
        auto.bar = .init(mode: "auto", yNormalized: 0.95, xMinNormalized: 0.0, xMaxNormalized: 0.05)
        XCTAssertEqual(ScenarioScorer.score(auto, frames: pullupsInTheFrame()).observedReps, 3)
    }

    // MARK: tracking health

    /// Shoulders and wrists unseen in the later frames of a push-up set, a share of them.
    private func pushupsLosingTheUpperBody(every hidden: Int) -> [ClipFrame] {
        var clip = ClipBuilder()
        clip.hold(PoseFixtures.pushup(175))
        clip.pushups(8)
        for i in 0..<clip.frames.count where i > clip.frames.count / 3 && i % 3 < hidden {
            for joint in [KP.leftWrist, KP.rightWrist, KP.leftShoulder, KP.rightShoulder] {
                clip.frames[i].keypoints[joint] = .missing
            }
        }
        return clip.frames
    }

    func testTheWorstHealthSeenIsReported() {
        let weak = ScenarioScorer.score(scenario("pushup", expected: 8, tolerance: 8, tracking: "weak"),
                                        frames: pushupsLosingTheUpperBody(every: 1))
        XCTAssertEqual(weak.worstHealth, "WEAK")
        XCTAssertEqual(weak.lostMs, 0)
        XCTAssertEqual(weak.failures, [])

        let lost = ScenarioScorer.score(scenario("pushup", expected: 8, tolerance: 8, tracking: "LOST"),
                                        frames: pushupsLosingTheUpperBody(every: 2))
        XCTAssertEqual(lost.worstHealth, "LOST")
        XCTAssertGreaterThan(lost.lostMs, 0)
        XCTAssertEqual(lost.failures, [])

        let wrong = ScenarioScorer.score(scenario("pushup", expected: 8, tolerance: 8, tracking: "lost"),
                                         frames: pushupsLosingTheUpperBody(every: 1))
        XCTAssertEqual(wrong.failures, ["expected tracking to reach LOST, observed WEAK"])
    }

    /// weak comes first and lost replaces it; weak never replaces lost, and the rows say how it went
    func testTheRowsCarryTheHealthAsItWas() {
        let rows = ScenarioScorer.score(scenario("pushup", expected: 8, tolerance: 8),
                                        frames: pushupsLosingTheUpperBody(every: 2)).frames
        let health = rows.compactMap { row -> String? in if case .string(let h)? = row["health"] { return h } else { return nil } }
        XCTAssertEqual(health.first, "GOOD")
        XCTAssertTrue(health.contains("LOST"))
    }

    /// the engine is told whether the crop was being followed
    func testTheTrackingFlagReachesTheEngineAsIdentity() {
        var clip = ClipBuilder()
        clip.hold(PoseFixtures.pullup(170))
        clip.pullup()
        clip.hold(PoseFixtures.pullup(170))
        XCTAssertEqual(ScenarioScorer.score(scenario("pullup", expected: 1), frames: clip.frames).observedReps, 1)

        // A pull-up is counted only with a stable identity, and a crop that was never followed gives none.
        let unfollowed = clip.frames.map { frame -> ClipFrame in var f = frame; f.trackingStable = false; return f }
        XCTAssertEqual(ScenarioScorer.score(scenario("pullup", expected: 1), frames: unfollowed).observedReps, 0)
    }

    /// lost, then recovered, then weak again: the worst is still lost
    func testALaterWeakSpellDoesNotReplaceLost() {
        var clip = ClipBuilder()
        clip.hold(PoseFixtures.pushup(175))
        clip.pushups(30)
        var frames = clip.frames
        for i in 40..<frames.count {
            // 40 to 90 gone altogether; 90 to 250 back; after that a third of the frames missing.
            let hidden = i < 90 || (i >= 250 && i % 3 < 1)
            if hidden {
                for joint in [KP.leftWrist, KP.rightWrist, KP.leftShoulder, KP.rightShoulder] { frames[i].keypoints[joint] = .missing }
            }
        }
        let report = ScenarioScorer.score(scenario("pushup", expected: 30, tolerance: 30), frames: frames)
        let health = report.frames.compactMap { row -> String? in if case .string(let h)? = row["health"] { return h } else { return nil } }
        XCTAssertEqual(health.reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }, ["GOOD", "LOST", "GOOD", "WEAK"])
        XCTAssertEqual(report.worstHealth, "LOST")
    }

    // MARK: where setup got to

    /// one hang, held, and nothing more: framed and waiting for calibration reps
    func testSetupThatIsMovingIsNeitherReadyNorFraming() {
        var clip = ClipBuilder()
        clip.hold(PoseFixtures.pullup(170), frames: 15)
        func failures(_ expectation: String) -> [String] {
            ScenarioScorer.score(scenario("pullup", expected: 0, setup: expectation), frames: clip.frames).failures
        }
        XCTAssertEqual(ScenarioScorer.score(scenario("pullup", expected: 0), frames: clip.frames).setup, "moving")
        XCTAssertEqual(failures("valid"), [])
        XCTAssertEqual(failures("ready"), ["expected setup 'ready', observed 'moving'"])
        XCTAssertEqual(failures("framing"), ["expected setup 'framing', observed 'moving'"])
        XCTAssertEqual(failures("invalid"), ["expected setup 'invalid', observed 'moving'"])
        XCTAssertEqual(failures("poor"), ["expected setup 'poor', observed 'moving'"])
    }

    /// the setup engine is told whether the crop was followed, as the scoring one is
    func testTheSetupEngineIsToldWhetherTheCropWasFollowed() {
        let followed = twoPullups()
        XCTAssertEqual(ScenarioScorer.score(scenario("pullup", expected: 2), frames: followed).setup, "ready")
        let unfollowed = followed.map { frame -> ClipFrame in var f = frame; f.trackingStable = false; return f }
        XCTAssertNotEqual(ScenarioScorer.score(scenario("pullup", expected: 2), frames: unfollowed).setup, "ready")
    }
}
