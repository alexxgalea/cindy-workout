import XCTest
import CindyCore
import CindyFixtures

/// Taking up a movement is not the first rep of it.
///
/// Getting off the floor after a set of push-ups traces the second half of a squat: knees deeply
/// bent, then driven to full extension. The knee angle cannot tell that apart from a rep — and
/// neither can leg extension on its own, because lying face down with straight legs reads as a
/// perfect 180 too. Only the torso's direction separates them.
///
/// Mirrors `StartPositionTest.kt`.
final class StartPositionTests: XCTestCase {

    private var clock: Int64 = 0

    @discardableResult
    private func hold(_ e: WorkoutEngine, _ pose: [Keypoint], frames: Int = 10) -> [RepEvent] {
        var events: [RepEvent] = []
        for _ in 0..<frames {
            let event = e.onFrame(pose, now: clock)
            if event != .none { events.append(event) }
            clock += 100
        }
        return events
    }

    private func doPullup(_ e: WorkoutEngine) {
        hold(e, PoseFixtures.pullup(170))
        hold(e, PoseFixtures.pullup(60))
    }

    private func doPushup(_ e: WorkoutEngine) {
        hold(e, PoseFixtures.pushup(175))
        hold(e, PoseFixtures.pushup(80))
        hold(e, PoseFixtures.pushup(175))
    }

    /// Drives a full block of pull-ups and push-ups, leaving the engine on squats.
    private func engineOnSquats() -> WorkoutEngine {
        let e = WorkoutEngine()
        for _ in 0..<5 { doPullup(e) }
        for _ in 0..<10 { doPushup(e) }
        XCTAssertEqual(e.exercise, .squat)
        return e
    }

    /// The way people actually get up off the floor.
    ///
    /// Not a jump from prone to standing: the torso comes vertical first, while the knees are still
    /// folded, and the athlete gathers themselves in that crouch before driving up. Both halves
    /// matter — the crouch is upright, and the drive out of it is a knee extension.
    private func getUpOffTheFloor(_ e: WorkoutEngine) {
        hold(e, PoseFixtures.onTheFloor(), frames: 8)
        // Upright, but still folded up: on the knees or in a deep crouch, gathering.
        hold(e, PoseFixtures.squat(70), frames: 8)
        // Then the legs drive out over about two thirds of a second.
        for knee: Float in [90, 110, 130, 150, 165] { hold(e, PoseFixtures.squat(knee), frames: 2) }
        hold(e, PoseFixtures.squat(175), frames: 8)
    }

    /// lying on the floor reads as full leg extension
    func testLyingOnTheFloorReadsAsFullLegExtension() {
        // The premise of the whole gate: this is why leg angle alone cannot start a squat.
        let e = WorkoutEngine(fixedExercise: .squat)
        hold(e, PoseFixtures.onTheFloor())
        let flat = e.signal
        hold(e, PoseFixtures.squat(175))
        XCTAssertEqual(e.signal, flat, accuracy: 8, "a plank and a stand agree on the knees")
    }

    /// standing up after push-ups does not score a squat
    func testStandingUpAfterPushUpsDoesNotScoreASquat() {
        let e = engineOnSquats()
        XCTAssertTrue(e.awaitingStart)

        // Face down at the end of the tenth push-up, then up through a crouch onto the feet.
        hold(e, PoseFixtures.onTheFloor())
        hold(e, PoseFixtures.squat(80), frames: 3)
        hold(e, PoseFixtures.squat(175))

        XCTAssertEqual(e.reps, 0, "getting up off the floor is not a rep")
        XCTAssertFalse(e.awaitingStart, "but the movement has now started")
    }

    /// gathering in a crouch before standing is still not a squat
    func testGatheringInACrouchBeforeStandingIsStillNotASquat() {
        let e = engineOnSquats()
        getUpOffTheFloor(e)
        XCTAssertEqual(e.reps, 0, "pausing on the way up must not buy a rep")
    }

    /// real squats count once the athlete is standing
    func testRealSquatsCountOnceTheAthleteIsStanding() {
        let e = engineOnSquats()
        hold(e, PoseFixtures.onTheFloor())
        hold(e, PoseFixtures.squat(175))
        XCTAssertEqual(e.reps, 0)

        for _ in 0..<3 {
            hold(e, PoseFixtures.squat(80))
            hold(e, PoseFixtures.squat(175))
        }
        XCTAssertEqual(e.reps, 3)
    }

    /// the athlete is told what to do and it is worth saying out loud
    func testTheAthleteIsToldWhatToDoAndItIsWorthSayingOutLoud() {
        let e = engineOnSquats()
        hold(e, PoseFixtures.onTheFloor())
        XCTAssertEqual(e.hint, "Stand up to start")
        XCTAssertTrue(e.blocked, "a hint nothing can be counted through is worth announcing")

        hold(e, PoseFixtures.squat(175))
        XCTAssertFalse(e.blocked)
    }

    /// a moment upright on the way up is not enough
    func testAMomentUprightOnTheWayUpIsNotEnough() {
        let e = engineOnSquats()
        hold(e, PoseFixtures.onTheFloor())
        // Two frames of vertical torso in passing, then face down again.
        hold(e, PoseFixtures.squat(90), frames: 2)
        hold(e, PoseFixtures.onTheFloor(), frames: 2)
        XCTAssertTrue(e.awaitingStart, "half the posture for a fifth of a second starts nothing")
    }

    /// dropping off the bar does not score a push-up
    func testDroppingOffTheBarDoesNotScoreAPushUp() {
        let e = WorkoutEngine()
        for _ in 0..<5 { doPullup(e) }
        XCTAssertEqual(e.exercise, .pushup)
        XCTAssertTrue(e.awaitingStart)

        // Still on their feet, arms bending and straightening as they come off the bar.
        hold(e, PoseFixtures.squat(175))
        hold(e, PoseFixtures.pullup(80))
        hold(e, PoseFixtures.pullup(170))
        XCTAssertEqual(e.reps, 0, "nothing done standing up is a push-up")

        doPushup(e)
        XCTAssertEqual(e.reps, 1)
    }

    /// a crouch is not standing, however long it is held
    func testACrouchIsNotStandingHoweverLongItIsHeld() {
        let e = engineOnSquats()
        hold(e, PoseFixtures.onTheFloor())
        // Sat on the haunches for three seconds: torso vertical the whole time, and perfectly
        // still, so neither posture-alone nor stillness-alone would hold the gate shut.
        hold(e, PoseFixtures.squat(75), frames: 30)
        XCTAssertTrue(e.awaitingStart, "the hips are still down by the knees")

        hold(e, PoseFixtures.squat(175))
        XCTAssertFalse(e.awaitingStart)
        XCTAssertEqual(e.reps, 0)
    }

    /// the floor does not poison the learned squat range
    func testTheFloorDoesNotPoisonTheLearnedSquatRange() {
        // Lying face down reads as 180 degrees of knee extension. Letting that into the band would
        // lift its top above anything this athlete reaches standing, and then *no* squat would
        // ever count -- the opposite failure, and a quieter one.
        let e = engineOnSquats()
        hold(e, PoseFixtures.onTheFloor(), frames: 20)
        hold(e, PoseFixtures.squat(70), frames: 5)
        // A phone on the floor foreshortens this athlete: standing only projects as 145 degrees.
        hold(e, PoseFixtures.squat(145))
        XCTAssertFalse(e.awaitingStart)

        // Twelve, not a token few: the band's decay heals the pollution eventually, so a short set
        // cannot tell the two behaviours apart. Feeding the floor in scores 3 of these 12.
        for _ in 0..<12 {
            hold(e, PoseFixtures.squat(85))
            hold(e, PoseFixtures.squat(145))
        }
        XCTAssertEqual(e.reps, 12, "every real squat counts")
    }

    /// the second round asks for the position again
    func testTheSecondRoundAsksForThePositionAgain() {
        let e = engineOnSquats()
        hold(e, PoseFixtures.onTheFloor())
        hold(e, PoseFixtures.squat(175))
        for _ in 0..<15 {
            hold(e, PoseFixtures.squat(80))
            hold(e, PoseFixtures.squat(175))
        }
        XCTAssertEqual(e.rounds, 1)
        XCTAssertEqual(e.exercise, .pullup)

        // Round two: back through the bar and the floor, and the squat gate must be armed again.
        for _ in 0..<5 { doPullup(e) }
        for _ in 0..<10 { doPushup(e) }
        XCTAssertEqual(e.exercise, .squat)
        XCTAssertTrue(e.awaitingStart, "a new round cannot inherit a started movement")
        getUpOffTheFloor(e)
        XCTAssertEqual(e.reps, 0, "and getting up still does not score")
    }

    /// a body the tracker cannot read does not open the gate
    func testABodyTheTrackerCannotReadDoesNotOpenTheGate() {
        let e = engineOnSquats()
        hold(e, PoseFixtures.empty(), frames: 20)
        XCTAssertTrue(e.awaitingStart)
        XCTAssertEqual(e.reps, 0)
    }

    /// stepping back into a movement does not ask for the position again
    func testSteppingBackIntoAMovementDoesNotAskForThePositionAgain() {
        let e = engineOnSquats()
        hold(e, PoseFixtures.onTheFloor())
        hold(e, PoseFixtures.squat(175))
        for _ in 0..<2 {
            hold(e, PoseFixtures.squat(80))
            hold(e, PoseFixtures.squat(175))
        }
        XCTAssertEqual(e.reps, 2)

        _ = e.undoRep()
        XCTAssertEqual(e.reps, 1)
        XCTAssertFalse(e.awaitingStart, "the athlete is already mid-movement")
    }
}
