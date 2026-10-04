import Foundation

/// Where a workout is: the five states `MainActivity` keeps.
public enum WorkoutState: Sendable { case idle, setup, running, paused, finished }

/// The status dot's three readings. The dot carries whether a rep would count right now, because a
/// sentence that changes colour as you read it is harder to read than a dot.
public enum StatusDot: Sendable { case neutral, ok, alert }

/// What the screen has to *do* about a decision the session made.
///
/// The session decides and the screen performs: this is the whole of the boundary. Nothing here
/// touches a speaker, a vibration motor or a camera, so every decision is testable without one.
public enum SessionEffect: Equatable, Sendable {
    /// Speak now, cutting off whatever is being said: a rep count, which must not fall behind.
    case say(VoiceLine)
    /// Speak after what is being said: a cue that must not be dropped, and must not cut a count short.
    case queue(VoiceLine)
    /// Stop speaking: the clock stopped, and nothing said before it should arrive after.
    case stopSpeaking
    /// A haptic tap of this many milliseconds: short per rep, longer per movement, longest per round.
    case buzz(Int)
    /// A line to show briefly.
    case toast(String)
    /// The camera's view of the athlete may have changed: forget the crop that was following them.
    case resetCrop
    /// A workout is on the clock (or not), so a reminder cannot (or can) interrupt it.
    case liveWorkout(Bool)
    /// The setup check passed, for the banner the recording shows.
    case calibratedBanner
}

/// Everything a finished workout leaves behind, for the screen to save and show.
public struct FinishedWorkout: Equatable, Sendable {
    public let attempt: Attempt
    /// Every rep's moment on the workout clock, for a later screen's timeline. Worth saving only
    /// beside an attempt that was saved.
    public let marks: [RepMark]
    public let stoppedEarly: Bool
    /// The session was switched over to heels-flat squats by smart counting.
    public let heelsFlatSpotted: Bool
    public let effects: [SessionEffect]
}

/// The orchestration of a Cindy: the clock, the setup check, what the voice says and when, and what
/// is saved.
///
/// The decision half of Android's `MainActivity`, which also does the plumbing (CameraX, views,
/// dialogs, permission prompts) that stays on the screen. Everything in here is a decision or a
/// piece of bookkeeping: when the clock ticks and stops, when the athlete is told to recalibrate,
/// which set a finished movement belongs to and how an undo unwinds it, what the status line says,
/// and what an attempt is made of. Time is always handed in, in monotonic milliseconds, so a test
/// can move it.
///
/// Main thread only, like the screen that owns it.
public final class WorkoutSession {

    /// A Cindy is twenty minutes.
    public static let workoutMs: Int64 = 20 * 60 * 1000

    /// How long a movement must stay un-startable before the demonstrator is worth showing.
    ///
    /// The demonstrator waits this out rather than appearing the instant a gate shuts: between reps
    /// of a set the gate closes and reopens constantly, and a figure that flashes up each time
    /// would be worse than no figure at all.
    public static let coachAfterMs: Int64 = 1_200

    public private(set) var state: WorkoutState = .idle
    public private(set) var remainingMs: Int64 = workoutMs
    public private(set) var elapsedMs: Int64 = 0
    public private(set) var pausedMs: Int64 = 0

    // What the screen shows.
    public private(set) var exercise: Exercise = .pullup
    /// "SET UP" while the check runs, else the movement's name.
    public private(set) var exerciseText = Exercise.pullup.label
    public private(set) var repsText = "0"
    /// "/5", or "" where there is no target to count against.
    public private(set) var targetText = "/5"
    public private(set) var rounds = 0
    public private(set) var status = "Tap to set up"
    public private(set) var dot: StatusDot = .neutral
    /// 0 to 100: how far through the movement's target, readable from the bar when digits are not.
    public private(set) var repProgress = 0
    /// The movement whose start position the demonstrator should show, or `nil` for none.
    public private(set) var coachShowing: Exercise?

    /// A readout is on the status line instead of coaching, so the coach card stands down.
    public var debugReadout = false

    private let engine: WorkoutEngine
    private let coach = Coach()
    private let tracking = TrackingHealthMonitor()
    private let sets = SplitBook()
    private let repLog = RepLog()

    private var roundSplits: [Int64] = []
    private var roundStartedAtElapsed: Int64 = 0
    private var lastTickAt: Int64 = 0
    private var pauseStartedAt: Int64 = 0
    private var blockedSince: Int64 = 0
    private var heelsFlatAnnounced = false

    public init(profile: CindyProfile = .standard) {
        engine = WorkoutEngine(profile: profile)
        render(RepEvent.none)
    }

    public var profile: CindyProfile { engine.profile }

    /// Whether the clock has started, whether or not it is ticking right now.
    public var inWorkout: Bool { state == .running || state == .paused }

    /// "20:00" down to "00:00", rounding up so the last second reads 00:01 until it is gone.
    public var clockText: String {
        let total = (remainingMs + 999) / 1000
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// What the counter is doing, for the debug readout: the signal it follows, the band it has
    /// learned, whether it is calibrated and where it is in the movement.
    public var counterReadout: String {
        let phase = engine.awaitingStart ? "start" : "\(engine.phase)"
        return String(format: "sig %.0f · rng %.0f · %@ · %@", engine.signal, engine.learnedRange,
                      engine.calibrated ? "cal" : "warm", phase)
    }

    // MARK: - setup

    public func enterSetup() -> [SessionEffect] {
        state = .setup
        engine.beginSetup()
        exerciseText = "SET UP"
        repsText = "—"
        targetText = ""
        dot = .neutral
        status = "Get in frame"
        return [.resetCrop, .say(.setUp)]
    }

    /// Feeds one frame of the setup check.
    public func onSetupFrame(_ keypoints: [Keypoint], now: Int64, tracking identityStable: Bool = true) -> [SessionEffect] {
        guard state == .setup else { return [] }
        return applySetup(engine.onSetupFrame(keypoints, now: now, identityStable: identityStable), now: now)
    }

    private func applySetup(_ setup: Setup, now: Int64) -> [SessionEffect] {
        switch setup.stage {
        case .framing:
            repsText = "—"
            targetText = ""
            dot = .alert
            status = "Can't see your " + setup.missing.joined(separator: ", ")
        case .moving:
            repsText = "\(setup.reps)"
            targetText = "/\(RecordedHud.calibrationReps)"
            dot = .neutral
            status = "Do 2 slow pull-ups to calibrate"
        case .poor:
            repsText = "\(setup.reps)"
            targetText = "/\(RecordedHud.calibrationReps)"
            dot = .alert
            status = "Movement barely registers — raise the phone or step back"
        case .ready:
            // The banner belongs to the moment the check ends, not to beginWorkout(), which also
            // runs for a workout that skipped the check altogether.
            return [.calibratedBanner] + beginWorkout(calibrated: true, now: now)
        }
        return []
    }

    /// The athlete chose to skip the check, after being told what that costs.
    public func skipSetup(now: Int64) -> [SessionEffect] {
        guard state == .setup else { return [] }
        return beginWorkout(calibrated: false, now: now)
    }

    /// Starts the clock. `calibrated` only changes what is announced.
    public func beginWorkout(calibrated: Bool, now: Int64) -> [SessionEffect] {
        engine.finishSetup()
        state = .running
        lastTickAt = now
        roundStartedAtElapsed = 0
        roundSplits.removeAll()
        sets.start()
        repLog.start()
        elapsedMs = 0
        pausedMs = 0
        remainingMs = Self.workoutMs
        dot = .neutral
        status = "Counting…"
        var effects: [SessionEffect] = [.liveWorkout(true), .say(.go(calibrated: calibrated))]
        effects += apply(snapshot(event: .none), now: now)
        return effects
    }

    // MARK: - control

    /// Pause, or resume. Pausing parks the clock; resuming recalibrates, because the phone or the
    /// athlete may have moved while it was stopped and the band learned before no longer describes
    /// what the camera is seeing.
    public func togglePause(now: Int64) -> [SessionEffect] {
        switch state {
        case .running:
            state = .paused
            coach.interrupted()
            pauseStartedAt = now
            status = "Paused"
            return [.stopSpeaking]
        case .paused:
            state = .running
            if pauseStartedAt != 0 {
                pausedMs += now - pauseStartedAt
                pauseStartedAt = 0
            }
            lastTickAt = now
            engine.recalibrate()
            tracking.reframe()
            status = "Recalibrating…"
            return [.resetCrop, .say(.resume)]
        default:
            return []
        }
    }

    /// The camera's view of the athlete changed (a flip), so the learned band is stale.
    public func recalibrate() {
        engine.recalibrate()
        tracking.reframe()
    }

    /// Skips the movement being worked on, banking the reps it reached.
    public func skipExercise(now: Int64) -> [SessionEffect] {
        guard inWorkout else { return [] }
        return apply(snapshot(event: engine.skipExercise()), now: now)
    }

    public func manualRep(now: Int64) -> [SessionEffect] {
        guard state == .running else { return [] }
        return apply(snapshot(event: engine.manualRep()), now: now)
    }

    /// Takes back a rep the counter should not have scored.
    public func undoRep(now: Int64) -> [SessionEffect] {
        guard state == .running else { return [] }
        let roundsBefore = engine.rounds
        let movementBefore = engine.exercise
        let snap = snapshot(event: engine.undoRep())
        // Stepping back over a round boundary un-books that round's split too.
        if snap.rounds < roundsBefore, let last = roundSplits.popLast() {
            roundStartedAtElapsed = elapsedMs - last
        }
        // Stepping back into the previous movement reopens the set that had just finished.
        if snap.exercise != movementBefore { sets.stepBack() }
        return apply(snap, now: now)
    }

    /// Back to the start, ready for another workout.
    public func reset() -> [SessionEffect] {
        state = .idle
        remainingMs = Self.workoutMs
        roundSplits.removeAll()
        sets.start()
        elapsedMs = 0
        pausedMs = 0
        pauseStartedAt = 0
        blockedSince = 0
        coachShowing = nil
        engine.reset()
        heelsFlatAnnounced = false
        tracking.reset()
        coach.reset()
        dot = .neutral
        status = "Tap to set up"
        _ = apply(snapshot(event: .none), now: 0)
        return [.liveWorkout(false), .resetCrop]
    }

    // MARK: - frames and the clock

    /// Feeds one frame of the running workout.
    ///
    /// `tracking` is whether the crop this frame was analysed in was a tracked one, read for this
    /// same frame, which the engine uses to decide whether the person it sees is still the one it
    /// was following. `softGain` is how much the picture had to be brightened, which is evidence
    /// for whether a frame the camera could not read was dark or merely empty.
    public func onFrame(_ keypoints: [Keypoint], now: Int64, tracking identityStable: Bool = true,
                        softGain: Float = 1) -> [SessionEffect] {
        guard state == .running else { return [] }
        let event = engine.onFrame(keypoints, now: now, identityStable: identityStable)
        // Judged on the legibility captured with this frame.
        tracking.update(exercise: engine.exercise, legible: engine.diagnostics.poseLegible,
                        softGain: softGain, now: now)
        return apply(snapshot(event: event), now: now)
    }

    /// What `tick` found: the clock moved, or time ran out.
    public struct Tick: Equatable, Sendable {
        public let effects: [SessionEffect]
        /// Set when the clock reached 00:00: the workout is over and this is what it left.
        public let finished: FinishedWorkout?
    }

    /// Advances the clock to `now`. Called about five times a second while running.
    public func tick(now: Int64, wallClockMs: Int64) -> Tick {
        guard state == .running else { return Tick(effects: [], finished: nil) }
        let step = now - lastTickAt
        remainingMs -= step
        elapsedMs += step
        lastTickAt = now
        if remainingMs <= 0 {
            remainingMs = 0
            return Tick(effects: [], finished: finish(stoppedEarly: false, now: now, wallClockMs: wallClockMs))
        }
        // Queued, so a mark that lands on a rep waits its turn behind the count instead of cutting
        // the number in half. The wording and the timing both belong to the coach.
        let line = coach.onClock(elapsedMs: elapsedMs, remainingMs: remainingMs,
                                 rounds: engine.rounds, totalReps: engine.totalReps)
        return Tick(effects: line.map { [.queue($0)] } ?? [], finished: nil)
    }

    /// Ends the workout: at 00:00, or when the athlete ends it early.
    public func finish(stoppedEarly: Bool, now: Int64, wallClockMs: Int64) -> FinishedWorkout {
        state = .finished
        if pauseStartedAt != 0 {
            pausedMs += now - pauseStartedAt
            pauseStartedAt = 0
        }
        let snap = snapshot(event: .none)
        repLog.follow(totalReps: snap.totalReps, manualReps: snap.manualReps, movement: snap.exercise, clockMs: elapsedMs)
        let attempt = Attempt(
            rounds: snap.rounds, reps: snap.repsThisRound, atMillis: wallClockMs,
            durationMs: elapsedMs, pausedMs: pausedMs, roundSplitsMs: roundSplits,
            profile: engine.countedProfile, manualReps: snap.manualReps,
            countedReps: snap.totalReps, untrackedMs: tracking.lostMs, setSplits: sets.sets)

        dot = .neutral
        status = "\(attempt.scoreLabel) · \(attempt.caption)"
        coachShowing = nil
        var effects: [SessionEffect] = [.liveWorkout(false), .buzz(600)]
        effects.append(.say(.finished(early: stoppedEarly)))
        effects.append(.queue(.score(rounds: snap.rounds, totalReps: snap.totalReps)))
        if let average = attempt.avgRoundMs { effects.append(.queue(.averaging(roundMs: average))) }
        if Records.beatsBenchmark(attempt) { effects.append(.queue(.beatBenchmark(name: Records.benchmarkName))) }
        return FinishedWorkout(attempt: attempt, marks: repLog.marks, stoppedEarly: stoppedEarly,
                               heelsFlatSpotted: snap.heelsFlatSpotted, effects: effects)
    }

    // MARK: - the engine's answer

    /// What the engine says after a frame or a button: one frame's worth of numbers, read at once.
    private struct Snapshot {
        let exercise: Exercise
        let reps: Int
        let rounds: Int
        let repsThisRound: Int
        let totalReps: Int
        let hint: String
        let event: RepEvent
        let eventReps: Int
        let calibrated: Bool
        let bodyVisible: Bool
        let blocked: Bool
        let manualReps: Int
        let heelsFlatSpotted: Bool
        let health: TrackingHealth
        let advice: String?
    }

    private func snapshot(event: RepEvent) -> Snapshot {
        Snapshot(exercise: engine.exercise, reps: engine.reps, rounds: engine.rounds,
                 repsThisRound: engine.repsThisRound, totalReps: engine.totalReps, hint: engine.hint,
                 event: event, eventReps: engine.repsAtLastEvent, calibrated: engine.calibrated,
                 bodyVisible: engine.bodyVisible, blocked: engine.blocked, manualReps: engine.manualReps,
                 heelsFlatSpotted: engine.heelsFlatSpotted, health: tracking.health, advice: tracking.advice)
    }

    private func render(_ event: RepEvent) { _ = apply(snapshot(event: event), now: 0) }

    private func apply(_ snap: Snapshot, now: Int64) -> [SessionEffect] {
        exercise = snap.exercise
        if state != .setup {
            exerciseText = snap.exercise.label
            repsText = "\(snap.reps)"
            targetText = "/\(snap.exercise.target)"
        }
        rounds = snap.rounds
        repProgress = snap.reps * 100 / max(snap.exercise.target, 1)

        var effects: [SessionEffect] = []
        if state == .running {
            // Said first, and instead of the engine's own hint. When the light goes the engine
            // refuses frames for "Show both hands" and then "Step into frame" — which tells someone
            // hanging on the bar in front of the camera that they are not there, and sends them to
            // fix their position instead of the light.
            if let advice = snap.advice { status = advice }
            else if !snap.calibrated { status = "Recalibrating…" }
            else { status = snap.hint }
            // Say plainly whether a rep would count right now, rather than only complaining.
            if snap.health == .lost || !snap.bodyVisible { dot = .alert }
            else if snap.health == .weak || snap.blocked { dot = .neutral }
            else { dot = .ok }
            effects += speakAboutPosition(snap, now: now)
        }
        updateCoach(snap, now: now)

        switch snap.event {
        case .none:
            break
        case .rep:
            effects += [.buzz(35), .say(.count(reps: snap.eventReps))]
        case .undo:
            effects += [.buzz(20), .say(.count(reps: snap.eventReps))]
        case .exerciseDone:
            if inWorkout {
                sets.movementDone(snap.exercise.previous, atMs: elapsedMs, reps: snap.eventReps, manualTotal: snap.manualReps)
            }
            // The count the movement reached, which a skip makes different from its target.
            effects += [.buzz(90), .say(.count(reps: snap.eventReps)), .queue(.movement(snap.exercise))]
        case .roundDone:
            if inWorkout {
                sets.movementDone(snap.exercise.previous, atMs: elapsedMs, reps: snap.eventReps, manualTotal: snap.manualReps)
            }
            let split = elapsedMs - roundStartedAtElapsed
            roundSplits.append(split)
            roundStartedAtElapsed = elapsedMs
            effects += [.buzz(220), .say(.count(reps: snap.eventReps)),
                        .queue(.roundDone(round: snap.rounds, splitMs: split)),
                        .toast("Round \(snap.rounds) · \(formatDuration(split))")]
        }

        // The rep log follows the engine's own banked totals rather than this event, so a skip
        // (which changes the movement without changing the total) costs it nothing to see.
        if inWorkout {
            let repMovement: Exercise
            switch snap.event {
            case .exerciseDone, .roundDone: repMovement = snap.exercise.previous
            default: repMovement = snap.exercise
            }
            repLog.follow(totalReps: snap.totalReps, manualReps: snap.manualReps, movement: repMovement, clockMs: elapsedMs)
        }

        // After the count, not before: a rep is said with a flush, which would cut a line queued
        // ahead of it short, and the rep that caused the switch has just been said above.
        if snap.heelsFlatSpotted && inWorkout && !heelsFlatAnnounced {
            heelsFlatAnnounced = true
            effects += [.queue(.adaptiveHeelsFlat), .toast("Adaptive Cindy activated for heels-flat squats")]
        }
        return effects
    }

    /// Speaks about the athlete's position, in both directions.
    ///
    /// Mid-set nobody is looking at the phone. A rep that will not count is otherwise lost in silence
    /// until the summary screen — and, just as bad, an athlete who has got themselves into a good
    /// position has no way to know the app agrees. Queued, so it never cuts off a count mid-number.
    private func speakAboutPosition(_ snap: Snapshot, now: Int64) -> [SessionEffect] {
        let line = coach.onFrame(
            snap.exercise,
            // Losing the athlete is a fault whether or not the current frame was refused: the whole
            // failure is that individual frames keep looking survivable while the score quietly
            // drains away.
            blocked: snap.blocked || snap.health != .good,
            hint: snap.advice ?? snap.hint,
            now: now)
        return line.map { [.queue($0)] } ?? []
    }

    /// Shows the start-position demonstrator once a movement has stayed un-startable long enough.
    private func updateCoach(_ snap: Snapshot, now: Int64) {
        let eligible = state == .running && snap.blocked && snap.bodyVisible && !debugReadout
        if !eligible { blockedSince = 0 } else if blockedSince == 0 { blockedSince = now }
        let show = eligible && now - blockedSince >= Self.coachAfterMs
        coachShowing = show ? snap.exercise : nil
    }
}
