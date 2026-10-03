import XCTest
import CindyCore
import CindyFixtures

/// An air-squat session that notices heels-flat squats and goes over to counting them.
///
/// The rule under test is one sentence: when three reps in a block are ones only the heels-flat
/// counter accepted, it takes over, and the count is brought up to what the athlete has really
/// done. Everything here is a way that could go wrong by one rep, or by a whole movement, or by
/// quietly relabelling a session that was fine: crediting a rep twice, losing one, switching for
/// someone who was squatting to full depth, or switching at all when it was never asked for.
///
/// Standing is 175 degrees of knee from a phone at chest height and about 145 from one on the
/// floor, the same placements `HeelsFlatSquatTests` measures against.
///
/// Mirrors `SmartSquatTest.kt`.
final class SmartSquatTests: XCTestCase {

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

    /// A squat engine with smart counting on, stood up the way the athlete is at the start.
    private func smart(_ stand: Float, _ profile: CindyProfile = .standard) -> WorkoutEngine {
        let e = WorkoutEngine(fixedExercise: .squat, profile: profile, smartSquats: true)
        hold(e, PoseFixtures.squat(stand), frames: 12)
        return e
    }

    /// One rep to `bottom` and back to `stand`, and the events it produced.
    @discardableResult
    private func rep(_ e: WorkoutEngine, _ stand: Float, _ bottom: Float) -> [RepEvent] {
        hold(e, PoseFixtures.squat(bottom)) + hold(e, PoseFixtures.squat(stand))
    }

    private func reps(_ e: WorkoutEngine, _ stand: Float, _ bottoms: [Float]) {
        bottoms.forEach { rep(e, stand, $0) }
    }

    private func each(_ n: Int, _ bottom: Float) -> [Float] { Array(repeating: bottom, count: n) }

    // ── switching ─────────────────────────────────────────────────────────────

    /// nothing switches unless smart counting was asked for
    func testNothingSwitchesUnlessSmartCountingWasAskedFor() {
        let e = WorkoutEngine(fixedExercise: .squat)
        hold(e, PoseFixtures.squat(175), frames: 12)
        reps(e, 175, each(10, 125))
        XCTAssertEqual(e.reps, 0, "the air squat counts none of it, as it always has")
        XCTAssertFalse(e.heelsFlatSpotted)
    }

    /// the third heels flat squat switches and credits all three
    func testTheThirdHeelsFlatSquatSwitchesAndCreditsAllThree() {
        let e = smart(175)
        rep(e, 175, 125)
        rep(e, 175, 125)
        XCTAssertEqual(e.reps, 0, "two is not enough")
        XCTAssertFalse(e.heelsFlatSpotted)

        let events = rep(e, 175, 125)

        XCTAssertTrue(e.heelsFlatSpotted)
        XCTAssertEqual(e.reps, 3, "the three that caused it are counted")
        XCTAssertEqual(events, [.rep], "said as one rep, at the number reached")
        XCTAssertEqual(e.repsAtLastEvent, 3)
    }

    /// what was chosen is never rewritten, only what was counted
    func testWhatWasChosenIsNeverRewrittenOnlyWhatWasCounted() {
        let declared = CindyProfile(pull: .bandAssistedPullUp)
        let e = smart(175, declared)
        XCTAssertEqual(e.countedProfile, declared, "before: counted as chosen")

        reps(e, 175, each(3, 125))

        XCTAssertEqual(e.profile, declared, "the choice stands")
        var expected = declared
        expected.squat = .heelsFlat
        XCTAssertEqual(e.countedProfile, expected,
                       "the count is filed as heels flat, everything else as chosen")
    }

    /// it keeps counting every squat after the switch
    func testItKeepsCountingEverySquatAfterTheSwitch() {
        let e = smart(175)
        reps(e, 175, each(10, 125))
        XCTAssertEqual(e.reps, 10)
    }

    /// from a phone on the floor
    func testFromAPhoneOnTheFloor() {
        let e = smart(145)
        reps(e, 145, each(10, 105))
        XCTAssertEqual(e.reps, 10)
        XCTAssertTrue(e.heelsFlatSpotted)
    }

    // ── both styles ───────────────────────────────────────────────────────────

    /// the heels flat reps need not be consecutive
    func testTheHeelsFlatRepsNeedNotBeConsecutive() {
        // Deep, flat, deep, flat, ...: the flat ones are the pending ones, so the third of them
        // is the sixth rep, and the three deep ones before it are credited along with them.
        let e = smart(175)
        reps(e, 175, (0..<10).map { $0 % 2 == 0 ? 80 : 120 })
        XCTAssertTrue(e.heelsFlatSpotted)
        XCTAssertEqual(e.reps, 10)
    }

    /// heels flat squats after deep ones on the toes are all counted
    func testHeelsFlatSquatsAfterDeepOnesOnTheToesAreAllCounted() {
        let e = smart(175)
        reps(e, 175, each(3, 70) + each(10, 120))
        XCTAssertEqual(e.reps, 13, "three deep, then ten heels flat")
        XCTAssertTrue(e.heelsFlatSpotted)
    }

    /// The case time windows got wrong. The air-squat counter books an ascent that never quite
    /// stood a little after the heels-flat counter books it, and matching the two by time took
    /// that for a second rep: this session came out at 11.
    ///
    /// a rep the two counters book at different moments is credited once
    func testARepTheTwoCountersBookAtDifferentMomentsIsCreditedOnce() {
        let e = smart(145)
        reps(e, 145, each(3, 85))
        for _ in 0..<2 {
            hold(e, PoseFixtures.squat(100))
            hold(e, PoseFixtures.squat(130))
        }
        hold(e, PoseFixtures.squat(145))
        reps(e, 145, each(5, 105))
        XCTAssertEqual(e.reps, 10, "three deep, two that stopped short of standing, five heels flat")
    }

    // ── what never switches ───────────────────────────────────────────────────

    /// full depth squats never switch, and count as the air squat always did
    func testFullDepthSquatsNeverSwitchAndCountAsTheAirSquatAlwaysDid() {
        let e = smart(175)
        reps(e, 175, each(10, 80))
        XCTAssertEqual(e.reps, 10)
        XCTAssertFalse(e.heelsFlatSpotted)
        XCTAssertEqual(e.countedProfile, .standard)
    }

    /// quarter squats never switch
    func testQuarterSquatsNeverSwitch() {
        let chest = smart(175)
        reps(chest, 175, each(10, 140))
        XCTAssertEqual(chest.reps, 0)
        XCTAssertFalse(chest.heelsFlatSpotted)

        let floor = smart(145)
        reps(floor, 145, each(10, 120))
        XCTAssertEqual(floor.reps, 0)
        XCTAssertFalse(floor.heelsFlatSpotted)
    }

    /// a few deep squats and then quarter squats do not switch
    func testAFewDeepSquatsAndThenQuarterSquatsDoNotSwitch() {
        let e = smart(175)
        reps(e, 175, each(3, 80) + each(10, 145))
        XCTAssertEqual(e.reps, 3)
        XCTAssertFalse(e.heelsFlatSpotted)
    }

    /// The trade this mode makes, pinned so that changing it is a decision.
    ///
    /// A knee angle cannot tell a tired squat from a heels-flat one that travels the same, so
    /// anything that closes the knee 35 degrees or more counts as one, and three of them after a
    /// set of deep squats switch the session. That is the permissive choice the feature is built
    /// on, and the reason it is a setting that is off until real sessions show it is right.
    ///
    /// tired squats that stop short of full depth are taken for heels flat ones
    func testTiredSquatsThatStopShortOfFullDepthAreTakenForHeelsFlatOnes() {
        let e = smart(175)
        reps(e, 175, each(5, 80))
        XCTAssertFalse(e.heelsFlatSpotted)

        reps(e, 175, each(3, 130))

        XCTAssertTrue(e.heelsFlatSpotted)
        XCTAssertEqual(e.reps, 8)
        XCTAssertEqual(e.countedProfile.squat, .heelsFlat)
    }

    /// it stays out of a choice the athlete already made
    func testItStaysOutOfAChoiceTheAthleteAlreadyMade() {
        let flat = smart(175, CindyProfile(squat: .heelsFlat))
        reps(flat, 175, each(10, 125))
        XCTAssertEqual(flat.reps, 10, "counted as chosen from the first rep")
        XCTAssertFalse(flat.heelsFlatSpotted, "there is nothing to spot")

        for variant in [SquatVariant.boxSquat, .supportedSquat] {
            let e = smart(175, CindyProfile(squat: variant))
            reps(e, 175, each(10, 125))
            XCTAssertEqual(e.reps, 0, variant.rawValue)
            XCTAssertFalse(e.heelsFlatSpotted, variant.rawValue)
        }
    }

    // ── taps, takebacks and targets ───────────────────────────────────────────

    /// a rep tapped in is never credited twice
    func testARepTappedInIsNeverCreditedTwice() {
        let e = smart(175)
        reps(e, 175, each(2, 125))
        e.manualRep()
        XCTAssertEqual(e.reps, 1)

        reps(e, 175, each(3, 125))

        // Two before the tap, the tap, three after: six done, and four counted. A tap drops what
        // was pending, so the two before it are not credited. The count errs low, never high.
        XCTAssertEqual(e.reps, 4)
        XCTAssertTrue(e.heelsFlatSpotted)
    }

    /// taking a rep back forgets what was pending
    func testTakingARepBackForgetsWhatWasPending() {
        let e = WorkoutEngine(smartSquats: true)
        upToSquats(e)

        reps(e, 175, each(2, 125))
        rep(e, 175, 80)
        XCTAssertEqual(e.reps, 1, "one full squat counted, two heels flat pending")

        e.undoRep()
        XCTAssertEqual(e.reps, 0)

        // Two more would have made four pending, and switched, if the two from before the
        // takeback were still being held against them. (A takeback re-arms the air-squat counter,
        // as it always has, so the first rep after it can be counted both ways; nothing here
        // depends on that, only on how long it takes to reach three afterwards.)
        reps(e, 175, each(2, 125))
        XCTAssertFalse(e.heelsFlatSpotted, "what was pending before the takeback is forgotten")

        reps(e, 175, each(2, 125))
        XCTAssertTrue(e.heelsFlatSpotted, "and three counted since the takeback switch it as usual")
    }

    /// recalibrating keeps what was pending, because those reps happened
    func testRecalibratingKeepsWhatWasPendingBecauseThoseRepsHappened() {
        let e = smart(175)
        reps(e, 175, each(2, 125))

        // A pause and a resume, a flipped camera and a knocked phone all do this.
        e.recalibrate()
        hold(e, PoseFixtures.squat(175), frames: 12)
        rep(e, 175, 125)

        XCTAssertTrue(e.heelsFlatSpotted)
        XCTAssertEqual(e.reps, 3, "the two before the pause are credited with the one after")
    }

    /// the credit never passes the target of the squats
    func testTheCreditNeverPassesTheTargetOfTheSquats() {
        let e = WorkoutEngine(smartSquats: true)
        upToSquats(e)

        for _ in 0..<13 { e.manualRep() }
        XCTAssertEqual(e.reps, 13)

        // Thirteen tapped and three seen would be sixteen squats in a round of fifteen.
        let last = rep(e, 175, 125) + rep(e, 175, 125) + rep(e, 175, 125)

        XCTAssertTrue(last.contains(.roundDone))
        XCTAssertEqual(e.rounds, 1)
        XCTAssertEqual(e.totalReps, 30)
    }

    // ── the session ───────────────────────────────────────────────────────────

    private func doPullup(_ e: WorkoutEngine) {
        hold(e, PoseFixtures.pullup(170))
        hold(e, PoseFixtures.pullup(60))
    }

    private func doPushup(_ e: WorkoutEngine) {
        hold(e, PoseFixtures.pushup(175))
        hold(e, PoseFixtures.pushup(80))
        hold(e, PoseFixtures.pushup(175))
    }

    private func upToSquats(_ e: WorkoutEngine) {
        for _ in 0..<5 { doPullup(e) }
        for _ in 0..<10 { doPushup(e) }
        hold(e, PoseFixtures.onTheFloor())
        hold(e, PoseFixtures.squat(175))
    }

    /// a round of ordinary squats is the same with smart counting on
    func testARoundOfOrdinarySquatsIsTheSameWithSmartCountingOn() {
        let e = WorkoutEngine(smartSquats: true)
        upToSquats(e)
        reps(e, 175, each(15, 80))
        XCTAssertEqual(e.rounds, 1)
        XCTAssertEqual(e.totalReps, 30)
        XCTAssertFalse(e.heelsFlatSpotted)
    }

    /// once switched it counts from the first rep of every round
    func testOnceSwitchedItCountsFromTheFirstRepOfEveryRound() {
        let e = WorkoutEngine(smartSquats: true)
        upToSquats(e)
        reps(e, 175, each(15, 125))
        XCTAssertEqual(e.rounds, 1)
        XCTAssertTrue(e.heelsFlatSpotted)

        upToSquats(e)
        rep(e, 175, 125)
        XCTAssertEqual(e.reps, 1, "the first heels flat squat of round two already counts")

        reps(e, 175, each(14, 125))
        XCTAssertEqual(e.rounds, 2)
        XCTAssertEqual(e.totalReps, 60)
    }

    /// recalibrating keeps the switch and forgets the band
    func testRecalibratingKeepsTheSwitchAndForgetsTheBand() {
        let e = WorkoutEngine(smartSquats: true)
        upToSquats(e)
        reps(e, 175, each(6, 125))
        XCTAssertTrue(e.heelsFlatSpotted)

        e.recalibrate()

        XCTAssertTrue(e.heelsFlatSpotted,
                      "what the athlete does with their heels is not a matter of where the phone is")
        XCTAssertEqual(e.reps, 6)
        XCTAssertEqual(e.learnedRange, 0, accuracy: 0.001)
    }

    /// a reset ends it
    func testAResetEndsIt() {
        let e = WorkoutEngine(smartSquats: true)
        upToSquats(e)
        reps(e, 175, each(6, 125))
        XCTAssertTrue(e.heelsFlatSpotted)

        e.reset()

        XCTAssertFalse(e.heelsFlatSpotted)
        XCTAssertEqual(e.countedProfile, .standard)
        XCTAssertEqual(e.exercise, .pullup)
    }
}
