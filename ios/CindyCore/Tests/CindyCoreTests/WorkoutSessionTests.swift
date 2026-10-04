import XCTest
import CindyCore
import CindyFixtures

/// The decisions behind a Cindy: when the clock ticks and stops, what the voice says and when, what
/// a pause and an undo do to the bookkeeping, and what a finished workout is made of.
///
/// `MainActivity` has no test of its own (it is an activity, and its smoke test only inflates the
/// layout), so these are written from what it does, one behaviour at a time, and the pure session
/// is where that behaviour now lives.
final class WorkoutSessionTests: XCTestCase {

    private let session = WorkoutSession()
    private var clock: Int64 = 1_000
    private var said: [SessionEffect] = []

    /// Keeps every effect the session hands back, so a test can ask what was said.
    @discardableResult
    private func take(_ effects: [SessionEffect]) -> [SessionEffect] {
        said += effects
        return effects
    }

    private func hold(_ pose: [Keypoint], frames: Int = 10, stepMs: Int64 = 100) {
        for _ in 0..<frames {
            switch session.state {
            case .setup: take(session.onSetupFrame(pose, now: clock))
            default: take(session.onFrame(pose, now: clock))
            }
            clock += stepMs
        }
    }

    private func calibrate() {
        take(session.enterSetup())
        hold(PoseFixtures.pullup(170))
        for _ in 0..<2 {
            hold(PoseFixtures.pullup(170))
            hold(PoseFixtures.pullup(60))
        }
    }

    /// A workout that has started without the camera, so that reps can be tapped in.
    private func begin(calibrated: Bool = false) {
        take(session.enterSetup())
        take(session.skipSetup(now: clock))
        _ = calibrated
    }

    private func tap(_ n: Int) {
        for _ in 0..<n {
            take(session.manualRep(now: clock))
            clock += 400
        }
    }

    private func finished(early: Bool = false) -> FinishedWorkout {
        let f = session.finish(stoppedEarly: early, now: clock, wallClockMs: 1_700_000_000_000)
        take(f.effects)
        return f
    }

    // MARK: - the setup check

    /// entering setup says so, on screen and aloud, and aims the camera afresh
    func testEnteringSetupSaysSoOnScreenAndAloudAndAimsTheCameraAfresh() {
        let effects = session.enterSetup()
        XCTAssertEqual(session.state, .setup)
        XCTAssertEqual(session.exerciseText, "SET UP")
        XCTAssertEqual(session.repsText, "—")
        XCTAssertEqual(session.targetText, "")
        XCTAssertEqual(session.status, "Get in frame")
        XCTAssertEqual(session.dot, .neutral)
        XCTAssertEqual(effects, [.resetCrop, .say(.setUp)])
    }

    /// framing names the joints that are missing, and the dot is red
    func testFramingNamesTheJointsThatAreMissingAndTheDotIsRed() {
        take(session.enterSetup())
        var noHands = PoseFixtures.pullup(170)
        noHands[KP.leftWrist] = .missing
        noHands[KP.rightWrist] = .missing
        hold(noHands, frames: 3)
        XCTAssertEqual(session.status, "Can't see your hands")
        XCTAssertEqual(session.dot, .alert)
    }

    /// calibrating counts the two slow reps against two
    func testCalibratingCountsTheTwoSlowRepsAgainstTwo() {
        take(session.enterSetup())
        hold(PoseFixtures.pullup(170))
        XCTAssertEqual(session.status, "Do 2 slow pull-ups to calibrate")
        XCTAssertEqual(session.targetText, "/2")
        hold(PoseFixtures.pullup(60))
        hold(PoseFixtures.pullup(170))
        hold(PoseFixtures.pullup(60))
        XCTAssertEqual(session.state, .running, "two reps and the workout starts")
    }

    /// passing the check starts the clock, with the banner and the calibrated word
    func testPassingTheCheckStartsTheClockWithTheBannerAndTheCalibratedWord() {
        calibrate()
        XCTAssertEqual(session.state, .running)
        XCTAssertTrue(said.contains(.calibratedBanner))
        XCTAssertTrue(said.contains(.liveWorkout(true)))
        XCTAssertTrue(said.contains(.say(.go(calibrated: true))))
        // "Counting…" only until the first frame's own hint replaces it, which is immediate.
        XCTAssertNotEqual(session.status, "Get in frame")
        XCTAssertEqual(session.clockText, "20:00")
    }

    /// skipping the check starts the clock without the banner, and says so
    func testSkippingTheCheckStartsTheClockWithoutTheBannerAndSaysSo() {
        begin()
        XCTAssertEqual(session.state, .running)
        XCTAssertFalse(said.contains(.calibratedBanner))
        XCTAssertTrue(said.contains(.say(.go(calibrated: false))))
    }

    /// a phone that cannot see the movement is told to raise it or step back
    func testAPhoneThatCannotSeeTheMovementIsToldToRaiseItOrStepBack() {
        take(session.enterSetup())
        for _ in 0..<12 {
            hold(PoseFixtures.pullup(170))
            hold(PoseFixtures.pullup(150))
        }
        XCTAssertEqual(session.status, "Movement barely registers — raise the phone or step back")
        XCTAssertEqual(session.dot, .alert)
    }

    /// frames fed in the wrong state do nothing
    func testFramesFedInTheWrongStateDoNothing() {
        XCTAssertEqual(session.onFrame(PoseFixtures.pullup(60), now: 0), [])
        XCTAssertEqual(session.onSetupFrame(PoseFixtures.pullup(60), now: 0), [])
        begin()
        XCTAssertEqual(session.onSetupFrame(PoseFixtures.pullup(60), now: 0), [])
    }

    /// skipping the check is only possible during it
    func testSkippingTheCheckIsOnlyPossibleDuringIt() {
        XCTAssertEqual(session.skipSetup(now: 0), [])
        XCTAssertEqual(session.state, .idle)
    }

    // MARK: - counting

    /// a tapped rep is said with a flush and buzzes briefly
    func testATappedRepIsSaidWithAFlushAndBuzzesBriefly() {
        begin()
        said = []
        tap(1)
        XCTAssertEqual(said, [.buzz(35), .say(.count(reps: 1))])
        XCTAssertEqual(session.repsText, "1")
        XCTAssertEqual(session.targetText, "/5")
        XCTAssertEqual(session.repProgress, 20)
    }

    /// finishing a movement buzzes longer, says the count and queues the next movement
    func testFinishingAMovementBuzzesLongerSaysTheCountAndQueuesTheNextMovement() {
        begin()
        tap(4)
        said = []
        tap(1)
        XCTAssertEqual(said, [.buzz(90), .say(.count(reps: 5)), .queue(.movement(.pushup))])
        XCTAssertEqual(session.exercise, .pushup)
        XCTAssertEqual(session.exerciseText, "PUSH-UPS")
    }

    /// finishing a round buzzes longest, queues its split and shows it
    func testFinishingARoundBuzzesLongestQueuesItsSplitAndShowsIt() {
        begin()
        tap(29)
        said = []
        tap(1)
        XCTAssertEqual(said.count, 4)
        XCTAssertEqual(said[0], .buzz(220))
        XCTAssertEqual(said[1], .say(.count(reps: 15)))
        guard case .queue(.roundDone(let round, let split)) = said[2] else { return XCTFail("\(said[2])") }
        XCTAssertEqual(round, 1)
        XCTAssertEqual(said[3], .toast("Round 1 · \(formatDuration(split))"))
        XCTAssertEqual(session.rounds, 1)
        XCTAssertEqual(session.exercise, .pullup)
    }

    /// an undo takes a rep back and says the count it came back to
    func testAnUndoTakesARepBackAndSaysTheCountItCameBackTo() {
        begin()
        tap(3)
        said = []
        take(session.undoRep(now: clock))
        XCTAssertEqual(said, [.buzz(20), .say(.count(reps: 2))])
    }

    /// an undo across a round boundary un-books that round and reopens its last set
    func testAnUndoAcrossARoundBoundaryUnBooksThatRoundAndReopensItsLastSet() {
        begin()
        tap(30)
        XCTAssertEqual(session.rounds, 1)
        take(session.undoRep(now: clock))
        XCTAssertEqual(session.rounds, 0)
        XCTAssertEqual(session.exercise, .squat)
        tap(1)   // the squat finishes again, and so does the round
        let f = finished()
        XCTAssertEqual(f.attempt.roundSplitsMs.count, 1, "one round, booked once")
        XCTAssertEqual(f.attempt.setSplits.map { $0.movement }, [.pullup, .pushup, .squat])
        XCTAssertEqual(f.attempt.countedReps, 30)
    }

    /// stepping back into the previous movement reopens its set from where it began
    func testSteppingBackIntoThePreviousMovementReopensItsSetFromWhereItBegan() {
        begin()
        let start = clock
        _ = session.tick(now: start + 10_000, wallClockMs: 0)
        tap(5)                                     // the pull-ups, done at ten seconds
        tap(1)                                     // one push-up
        take(session.undoRep(now: clock))          // back to none of them
        take(session.undoRep(now: clock))          // and back into the pull-ups
        XCTAssertEqual(session.exercise, .pullup)
        _ = session.tick(now: start + 30_000, wallClockMs: 0)
        tap(1)                                     // the pull-ups finish again, at thirty
        let f = finished()
        XCTAssertEqual(f.attempt.setSplits.count, 1)
        XCTAssertEqual(f.attempt.setSplits[0].ms, 30_000, "timed from the original start, not from the undo")
    }

    /// skipping a movement banks the reps it reached and moves on
    func testSkippingAMovementBanksTheRepsItReachedAndMovesOn() {
        begin()
        tap(3)
        said = []
        take(session.skipExercise(now: clock))
        XCTAssertEqual(said, [.buzz(90), .say(.count(reps: 3)), .queue(.movement(.pushup))])
        XCTAssertEqual(session.exercise, .pushup)
        let f = finished()
        XCTAssertEqual(f.attempt.countedReps, 3, "three reps, not five")
        XCTAssertEqual(f.attempt.setSplits.map { $0.reps }, [3])
    }

    /// taps and undos do nothing off the clock
    func testTapsAndUndosDoNothingOffTheClock() {
        XCTAssertEqual(session.manualRep(now: 0), [])
        XCTAssertEqual(session.undoRep(now: 0), [])
        XCTAssertEqual(session.skipExercise(now: 0), [])
    }

    // MARK: - the clock

    /// the clock counts down and rounds up
    func testTheClockCountsDownAndRoundsUp() {
        begin()
        let start = clock
        _ = session.tick(now: start + 1_000, wallClockMs: 0)
        XCTAssertEqual(session.remainingMs, 20 * 60_000 - 1_000)
        XCTAssertEqual(session.clockText, "19:59")
        _ = session.tick(now: start + 1_001, wallClockMs: 0)
        XCTAssertEqual(session.clockText, "19:59", "a thousandth of a second in is still 19:59")
    }

    /// the marks on the clock are queued behind whatever is being said
    func testTheMarksOnTheClockAreQueuedBehindWhateverIsBeingSaid() {
        begin()
        tap(30)
        let start = clock
        let tick = session.tick(now: start + 5 * 60_000 + 1, wallClockMs: 0)
        XCTAssertEqual(tick.effects, [.queue(.clock(mark: .fiveMinutesIn, rounds: 1, totalReps: 30, projectedRounds: 3))])
    }

    /// at 00:00 the workout ends with what it counted
    func testAt0000TheWorkoutEndsWithWhatItCounted() {
        begin()
        tap(35)
        let tick = session.tick(now: clock + 20 * 60_000, wallClockMs: 1_700_000_000_000)
        let f = tick.finished!
        XCTAssertEqual(session.state, .finished)
        XCTAssertEqual(session.remainingMs, 0)
        XCTAssertEqual(session.clockText, "00:00")
        XCTAssertEqual(f.attempt.rounds, 1)
        XCTAssertEqual(f.attempt.reps, 5)
        XCTAssertEqual(f.attempt.totalReps, 35)
        XCTAssertEqual(f.attempt.atMillis, 1_700_000_000_000)
        XCTAssertFalse(f.stoppedEarly)
    }

    /// ending says how it ended, then the score, then the average round
    func testEndingSaysHowItEndedThenTheScoreThenTheAverageRound() {
        begin()
        tap(30)
        let f = finished(early: true)
        XCTAssertEqual(f.effects.first, .liveWorkout(false))
        XCTAssertTrue(f.effects.contains(.buzz(600)))
        XCTAssertTrue(f.effects.contains(.say(.finished(early: true))))
        XCTAssertTrue(f.effects.contains(.queue(.score(rounds: 1, totalReps: 30))))
        XCTAssertTrue(f.effects.contains { if case .queue(.averaging) = $0 { return true } else { return false } })
        XCTAssertFalse(f.effects.contains { if case .queue(.beatBenchmark) = $0 { return true } else { return false } })
        XCTAssertEqual(session.status, "1 · \(Level.firstSteps.title)", "the score and the rung it earns")
    }

    /// nothing ticks once it is over
    func testNothingTicksOnceItIsOver() {
        begin()
        _ = finished()
        let tick = session.tick(now: clock + 5_000, wallClockMs: 0)
        XCTAssertEqual(tick.effects, [])
        XCTAssertNil(tick.finished)
    }

    // MARK: - pausing

    /// pausing stops the voice, parks the clock, and says so
    func testPausingStopsTheVoiceParksTheClockAndSaysSo() {
        begin()
        let start = clock
        XCTAssertEqual(session.togglePause(now: start), [.stopSpeaking])
        XCTAssertEqual(session.state, .paused)
        XCTAssertEqual(session.status, "Paused")
        _ = session.tick(now: start + 10_000, wallClockMs: 0)
        XCTAssertEqual(session.remainingMs, 20 * 60_000, "a paused clock does not run")
    }

    /// resuming recalibrates, resets the crop and says so
    func testResumingRecalibratesResetsTheCropAndSaysSo() {
        begin()
        _ = session.togglePause(now: clock)
        let effects = session.togglePause(now: clock + 30_000)
        XCTAssertEqual(session.state, .running)
        XCTAssertEqual(effects, [.resetCrop, .say(.resume)])
        XCTAssertEqual(session.status, "Recalibrating…")
        XCTAssertEqual(session.pausedMs, 30_000)
    }

    /// time spent paused is kept apart from the clock
    func testTimeSpentPausedIsKeptApartFromTheClock() {
        begin()
        let start = clock
        _ = session.tick(now: start + 60_000, wallClockMs: 0)
        _ = session.togglePause(now: start + 60_000)
        _ = session.togglePause(now: start + 100_000)
        _ = session.tick(now: start + 160_000, wallClockMs: 0)
        let f = session.finish(stoppedEarly: true, now: start + 160_000, wallClockMs: 0)
        XCTAssertEqual(f.attempt.durationMs, 120_000, "two minutes on the clock")
        XCTAssertEqual(f.attempt.pausedMs, 40_000)
        XCTAssertEqual(f.attempt.realTimeMs, 160_000)
    }

    /// ending while paused counts the pause that was still going
    func testEndingWhilePausedCountsThePauseThatWasStillGoing() {
        begin()
        let start = clock
        _ = session.togglePause(now: start + 10_000)
        let f = session.finish(stoppedEarly: true, now: start + 25_000, wallClockMs: 0)
        XCTAssertEqual(f.attempt.pausedMs, 15_000)
    }

    /// frames fed while paused are ignored
    func testFramesFedWhilePausedAreIgnored() {
        begin()
        _ = session.togglePause(now: clock)
        XCTAssertEqual(session.onFrame(PoseFixtures.pullup(60), now: clock), [])
    }

    /// pausing and resuming only work on a workout
    func testPausingAndResumingOnlyWorkOnAWorkout() {
        XCTAssertEqual(session.togglePause(now: 0), [])
        take(session.enterSetup())
        XCTAssertEqual(session.togglePause(now: 0), [])
        XCTAssertEqual(session.state, .setup)
    }

    // MARK: - what a finished workout is made of

    /// the attempt carries the counted reps, the sets and the rounds, and the marks match the count
    func testTheAttemptCarriesTheCountedRepsTheSetsAndTheRoundsAndTheMarksMatchTheCount() {
        begin()
        tap(47)
        let f = finished()
        let a = f.attempt
        XCTAssertEqual(a.countedReps, 47)
        XCTAssertEqual(a.rounds, 1)
        XCTAssertEqual(a.reps, 17)
        XCTAssertEqual(a.manualReps, 47, "every rep was tapped in")
        XCTAssertEqual(a.roundSplitsMs.count, 1)
        XCTAssertEqual(a.setSplits.map { $0.movement }, [.pullup, .pushup, .squat, .pullup, .pushup])
        XCTAssertEqual(a.profile, CindyProfile.standard)
        XCTAssertEqual(f.marks.count, 47)
        XCTAssertTrue(f.marks.allSatisfy { $0.manual })
        XCTAssertTrue(RepTimes.validFor(f.marks, a), "the marks are honestly this attempt's")
    }

    /// a workout with nothing in it is still handed back, for the screen to decide not to keep
    func testAWorkoutWithNothingInItIsStillHandedBackForTheScreenToDecideNotToKeep() {
        begin()
        let f = finished()
        XCTAssertEqual(f.attempt.totalReps, 0)
        XCTAssertEqual(f.marks, [])
    }

    // MARK: - reset

    /// resetting puts everything back, and lets reminders post again
    func testResettingPutsEverythingBackAndLetsRemindersPostAgain() {
        begin()
        tap(35)
        _ = finished()
        let effects = session.reset()
        XCTAssertEqual(effects, [.liveWorkout(false), .resetCrop])
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.clockText, "20:00")
        XCTAssertEqual(session.status, "Tap to set up")
        XCTAssertEqual(session.exercise, .pullup)
        XCTAssertEqual(session.rounds, 0)
        XCTAssertEqual(session.repsText, "0")
        // And the next workout starts from nothing.
        begin()
        tap(2)
        XCTAssertEqual(finished().attempt.countedReps, 2)
    }

    // MARK: - what the camera feeds it

    /// a rep the camera counts is said, buzzed and logged like a tapped one
    func testARepTheCameraCountsIsSaidBuzzedAndLoggedLikeATappedOne() {
        calibrate()
        said = []
        hold(PoseFixtures.pullup(170))
        hold(PoseFixtures.pullup(60))
        XCTAssertTrue(said.contains(.buzz(35)), "\(said)")
        XCTAssertTrue(said.contains { if case .say(.count) = $0 { return true } else { return false } })
        XCTAssertEqual(session.repsText, "1")
        let f = finished()
        XCTAssertEqual(f.marks.count, f.attempt.countedReps)
        XCTAssertEqual(f.attempt.manualReps, 0)
    }

    /// the dot says whether a rep would count right now
    func testTheDotSaysWhetherARepWouldCountRightNow() {
        calibrate()
        hold(PoseFixtures.pullup(170))
        XCTAssertEqual(session.dot, .ok)
        hold(PoseFixtures.empty(), frames: 3)
        XCTAssertEqual(session.dot, .alert, "nobody in shot")
    }

    /// a fault that stands is spoken, queued behind the count
    func testAFaultThatStandsIsSpokenQueuedBehindTheCount() {
        begin()
        tap(5)                                  // on to the push-ups, which start from the floor
        said = []
        hold(PoseFixtures.pullup(170), frames: 60)   // hanging from a bar, not on the floor
        XCTAssertTrue(said.contains { if case .queue(.fault) = $0 { return true } else { return false } }, "\(said)")
    }

    /// the start-position figure appears only after the movement has stayed unstartable a while
    func testTheStartPositionFigureAppearsOnlyAfterTheMovementHasStayedUnstartableAWhile() {
        begin()
        tap(5)
        hold(PoseFixtures.pullup(170), frames: 5)
        XCTAssertNil(session.coachShowing, "half a second is a gate flickering, not a problem")
        hold(PoseFixtures.pullup(170), frames: 20)
        XCTAssertEqual(session.coachShowing, .pushup)
        session.debugReadout = true
        hold(PoseFixtures.pullup(170), frames: 2)
        XCTAssertNil(session.coachShowing, "a readout on the status line stands the figure down")
    }
}
