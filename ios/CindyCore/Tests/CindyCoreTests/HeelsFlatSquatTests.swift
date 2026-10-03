import XCTest
import CindyCore
import CindyFixtures

/// A squat done with the heels flat on the floor is a correct squat, and has to count.
///
/// It stops higher than one up on the toes, because the heels hold the knees back, so seen from a
/// phone on the floor it travels barely more than half what the air squat asks of the knee. The
/// numbers here are the ones measured through the real engine: the shallowest bottom that still
/// counts from each camera height, and the quarter squats and partials that must never.
///
/// Standing is 175 degrees of knee from a phone at chest height and about 145 from one on the
/// floor, which is the placement the README calls normal.
///
/// Mirrors `HeelsFlatSquatTest.kt`.
final class HeelsFlatSquatTests: XCTestCase {

    private var clock: Int64 = 0

    private let flat = CindyProfile(squat: .heelsFlat)

    private func hold(_ e: WorkoutEngine, _ pose: [Keypoint], frames: Int = 10) {
        for _ in 0..<frames { _ = e.onFrame(pose, now: clock); clock += 100 }
    }

    /// An engine on squats alone, stood up the way the athlete is when the set begins.
    private func squatting(stand: Float, profile: CindyProfile? = nil) -> WorkoutEngine {
        let e = WorkoutEngine(fixedExercise: .squat, profile: profile ?? flat)
        hold(e, PoseFixtures.squat(stand), frames: 12)
        return e
    }

    private func rep(_ e: WorkoutEngine, stand: Float, bottom: Float) {
        hold(e, PoseFixtures.squat(bottom))
        hold(e, PoseFixtures.squat(stand))
    }

    /// What the engine counts for one rep to each of `bottoms`, starting and ending at `stand`.
    private func repsOf(stand: Float, _ bottoms: [Float], profile: CindyProfile? = nil) -> Int {
        let e = squatting(stand: stand, profile: profile)
        bottoms.forEach { rep(e, stand: stand, bottom: $0) }
        return e.reps
    }

    private func each(_ n: Int, _ bottom: Float) -> [Float] { Array(repeating: bottom, count: n) }

    // ── what counts ───────────────────────────────────────────────────────────

    /// heels flat squats count from a phone at chest height
    func testHeelsFlatSquatsCountFromAPhoneAtChestHeight() {
        XCTAssertEqual(repsOf(stand: 175, each(10, 125)), 10)
        XCTAssertEqual(repsOf(stand: 175, each(10, 135)), 10)
    }

    /// heels flat squats count from a phone on the floor
    func testHeelsFlatSquatsCountFromAPhoneOnTheFloor() {
        XCTAssertEqual(repsOf(stand: 145, each(10, 105)), 10)
    }

    /// the air squat refuses what a heels flat squat is counted for
    func testTheAirSquatRefusesWhatAHeelsFlatSquatIsCountedFor() {
        // The whole reason for the choice: same body, same movement, and the standard counter
        // books none of it.
        XCTAssertEqual(repsOf(stand: 175, each(10, 125), profile: .standard), 0)
        XCTAssertEqual(repsOf(stand: 145, each(10, 105), profile: .standard), 0)
    }

    /// a full depth squat is a heels flat squat too
    func testAFullDepthSquatIsAHeelsFlatSquatToo() {
        XCTAssertEqual(repsOf(stand: 175, each(10, 80)), 10)
        XCTAssertEqual(repsOf(stand: 145, each(10, 85)), 10)
    }

    /// from chest height the shallowest squat that counts is 135 degrees
    func testFromChestHeightTheShallowestSquatThatCountsIs135Degrees() {
        XCTAssertEqual(repsOf(stand: 175, each(10, 135)), 10)
        XCTAssertEqual(repsOf(stand: 175, each(10, 140)), 0)
    }

    /// The line the whole choice is tuned on. Lowering the minimum travel moves it: a retune that
    /// stops these two agreeing is a retune that changed what counts, and should say so here.
    ///
    /// from the floor the shallowest squat that counts is 105 degrees
    func testFromTheFloorTheShallowestSquatThatCountsIs105Degrees() {
        XCTAssertEqual(repsOf(stand: 145, each(10, 105)), 10)
        XCTAssertEqual(repsOf(stand: 145, each(10, 110)), 0)
    }

    // ── what never counts ─────────────────────────────────────────────────────

    /// quarter squats never count
    func testQuarterSquatsNeverCount() {
        XCTAssertEqual(repsOf(stand: 175, each(10, 140)), 0)
        XCTAssertEqual(repsOf(stand: 175, each(10, 145)), 0)
        XCTAssertEqual(repsOf(stand: 145, each(10, 120)), 0)
    }

    /// partials after heels flat squats stay refused
    func testPartialsAfterHeelsFlatSquatsStayRefused() {
        // Three good ones set the standard; ten that barely bend the knee never meet it.
        XCTAssertEqual(repsOf(stand: 175, each(3, 120) + each(10, 150)), 3)
    }

    /// quarter squats after deep ones stay refused
    func testQuarterSquatsAfterDeepOnesStayRefused() {
        XCTAssertEqual(repsOf(stand: 175, each(3, 80) + each(10, 145)), 3)
    }

    // ── both styles in one session ────────────────────────────────────────────

    /// heels flat squats after deep ones on the toes all count
    func testHeelsFlatSquatsAfterDeepOnesOnTheToesAllCount() {
        // The band a deep squat teaches is as deep as the deepest, and a counter that only armed
        // near the bottom of it would refuse every shallower rep that followed.
        for bottom: Float in [110, 120, 125] {
            XCTAssertEqual(repsOf(stand: 175, each(3, 70) + each(10, bottom)), 13, "to \(bottom)")
        }
    }

    /// the same from a phone on the floor
    func testTheSameFromAPhoneOnTheFloor() {
        XCTAssertEqual(repsOf(stand: 145, each(3, 85) + each(10, 105)), 13)
    }

    /// alternating styles count every rep
    func testAlternatingStylesCountEveryRep() {
        let bottoms: [Float] = (0..<10).map { $0 % 2 == 0 ? 80 : 120 }
        XCTAssertEqual(repsOf(stand: 175, bottoms), 10)
    }

    // ── inside a whole Cindy ──────────────────────────────────────────────────

    private func doPullup(_ e: WorkoutEngine) {
        hold(e, PoseFixtures.pullup(170))
        hold(e, PoseFixtures.pullup(60))
    }

    private func doPushup(_ e: WorkoutEngine) {
        hold(e, PoseFixtures.pushup(175))
        hold(e, PoseFixtures.pushup(80))
        hold(e, PoseFixtures.pushup(175))
    }

    /// a round of Cindy with heels flat squats closes
    func testARoundOfCindyWithHeelsFlatSquatsCloses() {
        let e = WorkoutEngine(profile: flat)
        for _ in 0..<5 { doPullup(e) }
        for _ in 0..<10 { doPushup(e) }
        XCTAssertEqual(e.exercise, .squat)

        // Up off the floor and onto the feet, which opens the squat gate without scoring.
        hold(e, PoseFixtures.onTheFloor())
        hold(e, PoseFixtures.squat(175))
        XCTAssertEqual(e.reps, 0)

        for _ in 0..<15 { rep(e, stand: 175, bottom: 125) }
        XCTAssertEqual(e.rounds, 1)
        XCTAssertEqual(e.exercise, .pullup)
        XCTAssertEqual(e.totalReps, 30)
    }

    /// the choice changes only the squat, never the other two movements
    func testTheChoiceChangesOnlyTheSquatNeverTheOtherTwoMovements() {
        let e = WorkoutEngine(profile: flat)
        for _ in 0..<5 { doPullup(e) }
        XCTAssertEqual(e.exercise, .pushup, "pull-ups still count the same")
        for _ in 0..<10 { doPushup(e) }
        XCTAssertEqual(e.exercise, .squat)
    }

    // ── how it is recorded ────────────────────────────────────────────────────

    /// heels flat squats are a counted choice, not a tapped one
    func testHeelsFlatSquatsAreACountedChoiceNotATappedOne() {
        XCTAssertEqual(SquatVariant.heelsFlat.tracking, .auto)
        XCTAssertTrue(flat.fullyAutomatic)
        XCTAssertTrue(flat.manualMovements.isEmpty)
    }

    /// a session with heels flat squats is an Adaptive Cindy that names them
    func testASessionWithHeelsFlatSquatsIsAnAdaptiveCindyThatNamesThem() {
        XCTAssertEqual(flat.mode, .adaptive)
        XCTAssertFalse(flat.isStandard)
        XCTAssertEqual(flat.changedMovements(), "heels-flat squats")
        XCTAssertEqual(flat.label(), "Adaptive Cindy · heels-flat squats")

        let attempt = Attempt(rounds: 9, reps: 4, atMillis: 1_000, profile: flat)
        XCTAssertEqual(attempt.caption, "Adaptive Cindy · heels-flat squats")
        XCTAssertNil(attempt.level, "no rung on a ladder it did not attempt")
    }

    /// the choice survives being saved and read back
    func testTheChoiceSurvivesBeingSavedAndReadBack() {
        XCTAssertEqual(Variations.decode(Variations.encode(flat)), flat)

        let saved = Records.decode(
            Records.encode([Attempt(rounds: 9, reps: 4, atMillis: 1_000, profile: flat)])
        )
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.profile, flat)
    }

    /// heels flat sessions are ranked against each other and not against air squats
    func testHeelsFlatSessionsAreRankedAgainstEachOtherAndNotAgainstAirSquats() {
        let history = [
            Attempt(rounds: 12, reps: 0, atMillis: 1, profile: .standard),
            Attempt(rounds: 9, reps: 0, atMillis: 2, profile: flat)
        ]
        XCTAssertEqual(Records.bestIn(history, profile: flat)?.rounds, 9)
        XCTAssertEqual(Records.bestIn(history, profile: .standard)?.rounds, 12)
    }
}
