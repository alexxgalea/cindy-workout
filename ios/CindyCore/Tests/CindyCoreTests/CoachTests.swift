import XCTest
import CindyCore

/// The voice has to answer two questions, and the second one is the easy one to forget: not only
/// "what am I doing wrong" but "is this position good enough to count?". An athlete on the bar
/// cannot see the screen, and silence on its own does not distinguish a working app from a
/// blind one.
///
/// Mirrors `CoachTest.kt`.
final class CoachTests: XCTestCase {

    private let coach = Coach()
    private var clock: Int64 = 0

    /// Runs the coach for `ms` in the given state, collecting the lines it hands over.
    private func lines(
        _ ms: Int64, blocked: Bool, hint: String = "", exercise: Exercise = .pullup, stepMs: Int64 = 100
    ) -> [VoiceLine] {
        var said: [VoiceLine] = []
        let until = clock + ms
        while clock < until {
            if let line = coach.onFrame(exercise, blocked: blocked, hint: hint, now: clock) { said.append(line) }
            clock += stepMs
        }
        return said
    }

    /// The same, in the English the assertions below are written in.
    private func run(
        _ ms: Int64, blocked: Bool, hint: String = "", exercise: Exercise = .pullup, stepMs: Int64 = 100
    ) -> [String] {
        lines(ms, blocked: blocked, hint: hint, exercise: exercise, stepMs: stepMs).map { PhrasebookEn().say($0) }
    }

    /// arriving at a movement in a good position is confirmed
    func testArrivingAtAMovementInAGoodPositionIsConfirmed() {
        XCTAssertEqual(run(1_000, blocked: false), ["Ready"])
    }

    /// the confirmation is not repeated while the athlete keeps working
    func testTheConfirmationIsNotRepeatedWhileTheAthleteKeepsWorking() {
        _ = run(1_000, blocked: false)
        XCTAssertEqual(run(30_000, blocked: false), [])
    }

    /// a single good frame does not confirm anything
    func testASingleGoodFrameDoesNotConfirmAnything() {
        // The gate flickering open for one frame is not the athlete being in position.
        XCTAssertEqual(run(200, blocked: false), [])
    }

    /// getting back into position after a fault is confirmed
    func testGettingBackIntoPositionAfterAFaultIsConfirmed() {
        _ = run(1_000, blocked: false)
        _ = run(3_000, blocked: true, hint: "Get on the bar")
        XCTAssertEqual(run(1_000, blocked: false), ["Ready"],
                       "the athlete needs to hear that they have fixed it")
    }

    /// a brief interruption mid-set is not worth confirming
    func testABriefInterruptionMidSetIsNotWorthConfirming() {
        _ = run(1_000, blocked: false)
        // One second of lost tracking, shorter than a rest between reps.
        _ = run(1_000, blocked: true, hint: "Tracking…")
        XCTAssertEqual(run(5_000, blocked: false), [],
                       "confirming every flicker would be noise, not coaching")
    }

    /// a standing fault is spoken, but only after it has stood a while
    func testAStandingFaultIsSpokenButOnlyAfterItHasStoodAWhile() {
        XCTAssertEqual(run(3_500, blocked: true, hint: "Get on the bar"), [], "nothing in the first four seconds")
        XCTAssertEqual(run(1_000, blocked: true, hint: "Get on the bar"), ["Get on the bar"])
    }

    /// a standing fault repeats slowly rather than every frame
    func testAStandingFaultRepeatsSlowlyRatherThanEveryFrame() {
        let said = run(30_000, blocked: true, hint: "Return to a dead hang")
        XCTAssertEqual(said.count, 3, "roughly every twelve seconds, not every frame")
        XCTAssertEqual(said, Array(repeating: "Return to a dead hang", count: 3))
    }

    /// a moving problem is not announced once per hint
    func testAMovingProblemIsNotAnnouncedOncePerHint() {
        // Four different faults in quick succession is a moving target, not a standing one.
        let said = ["Get on the bar", "Show both hands", "Show your head", "Tracking…"]
            .flatMap { run(1_000, blocked: true, hint: $0) }
        XCTAssertEqual(said, [])
    }

    /// each movement earns its own confirmation
    func testEachMovementEarnsItsOwnConfirmation() {
        XCTAssertEqual(run(1_000, blocked: false, exercise: .pullup), ["Ready"])
        XCTAssertEqual(run(1_000, blocked: false, exercise: .pushup), ["Ready"])
        XCTAssertEqual(run(1_000, blocked: false, exercise: .squat), ["Ready"])
    }

    /// coming back from a pause is confirmed
    func testComingBackFromAPauseIsConfirmed() {
        _ = run(1_000, blocked: false)
        coach.interrupted()
        XCTAssertEqual(run(1_000, blocked: false), ["Ready"],
                       "the athlete has been away and is asking the same question again")
    }

    /// a fault interrupted by a pause does not resume mid-count
    func testAFaultInterruptedByAPauseDoesNotResumeMidCount() {
        _ = run(3_500, blocked: true, hint: "Get on the bar")
        coach.interrupted()
        XCTAssertEqual(run(3_500, blocked: true, hint: "Get on the bar"), [],
                       "the four seconds start again after the break")
    }

    /// the coach hands over the engine's hint as a line, not a sentence
    func testTheCoachHandsOverTheEnginesHintAsALineNotASentence() {
        // The hint travels as the engine's own text so each phrasebook can translate it; the
        // confirmation is its own line rather than the word "Ready".
        let said = lines(6_000, blocked: true, hint: "Get on the bar") + lines(1_000, blocked: false)
        XCTAssertEqual(said, [.fault(hint: "Get on the bar"), .ready])
    }
}
