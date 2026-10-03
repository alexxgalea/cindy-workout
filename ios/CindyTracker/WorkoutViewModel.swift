import AVFoundation
import Combine
import Foundation
import CindyCore

/// Drives a Cindy attempt: the clock, the setup check, the score and the voice.
@MainActor
final class WorkoutViewModel: ObservableObject {

    enum Phase { case idle, setup, running, paused, finished }

    private static let workoutMs: Int64 = 20 * 60 * 1000

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var remainingMs: Int64 = workoutMs
    @Published private(set) var exercise: Exercise = .pullup
    @Published private(set) var reps = 0
    @Published private(set) var rounds = 0
    @Published private(set) var status = "Press START to set up"
    @Published private(set) var statusIsWarning = false
    /// The attempt the results sheet is showing. Settable because `.sheet(item:)` clears it when
    /// the sheet is dismissed.
    @Published var finished: Attempt?
    @Published var voiceEnabled = true

    private static let profileKey = "cindy.movementProfile"
    private let defaults = UserDefaults.standard

    /// Rebuilt rather than mutated when the movements change.
    ///
    /// `WorkoutEngine.profile` is immutable for the life of an engine on purpose: a rep's meaning
    /// must not change halfway through the score it contributes to. There is no UI yet to choose
    /// anything but the standard movements — this only makes sure the choice, once there is a way
    /// to make it, is saved, scored and reported honestly rather than silently defaulting.
    private var engine = WorkoutEngine(
        profile: Variations.decode(UserDefaults.standard.string(forKey: WorkoutViewModel.profileKey))
    )
    private let records = RecordStore()
    private let speech = AVSpeechSynthesizer()

    private var timer: Timer?
    private var elapsedMs: Int64 = 0
    private var pausedMs: Int64 = 0
    private var pauseStartedAt: Date?
    private var roundStartedAtElapsed: Int64 = 0
    private var splits: [Int64] = []
    private var lastTick = Date()
    private var lastAnnouncedSecond: Int64 = -1

    var clockText: String {
        let total = (remainingMs + 999) / 1000
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var startButtonTitle: String {
        switch phase {
        case .idle: return "START"
        case .setup: return "SKIP"
        case .running: return "PAUSE"
        case .paused: return "RESUME"
        case .finished: return "RESET"
        }
    }

    var inWorkout: Bool { phase == .running || phase == .paused }

    /// Feeds a frame in. Returns whether the camera's crop should be reset.
    func onFrame(_ keypoints: [Keypoint]) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        switch phase {
        case .setup:
            applySetup(engine.onSetupFrame(keypoints, now: now))
        case .running:
            apply(engine.onFrame(keypoints, now: now))
        default:
            break
        }
    }

    // MARK: - controls

    func primaryAction() {
        switch phase {
        case .idle: enterSetup()
        case .setup: begin(calibrated: false)
        case .running: pause()
        case .paused: resume()
        case .finished: reset()
        }
    }

    func manualRep() {
        guard phase == .running else { return }
        apply(engine.manualRep())
    }

    func undoRep() {
        guard phase == .running else { return }
        let before = engine.rounds
        let event = engine.undoRep()
        // Stepping back over a round boundary un-books that round's split too.
        if engine.rounds < before, let last = splits.popLast() {
            roundStartedAtElapsed = elapsedMs - last
        }
        apply(event)
    }

    func skipExercise() {
        guard phase == .running else { return }
        apply(engine.skipExercise())
    }

    /// The camera's view of the athlete changed, so the learned bands no longer describe it.
    func recalibrate() {
        engine.recalibrate()
    }

    /// The movements this session is counting, for a future "make Cindy yours" screen to read.
    var profile: CindyProfile { engine.profile }

    /// Changes the movements for the next workout. Refused mid-session: a rep's meaning cannot
    /// change halfway through the score it contributes to.
    @discardableResult
    func setMovementProfile(_ chosen: CindyProfile) -> Bool {
        guard phase == .idle || phase == .finished else { return false }
        defaults.set(Variations.encode(chosen), forKey: Self.profileKey)
        engine = WorkoutEngine(profile: chosen)
        render()
        return true
    }

    private func enterSetup() {
        phase = .setup
        engine.beginSetup()
        status = "Get in frame"
        say("Get in frame, then do two slow pull ups")
    }

    private func begin(calibrated: Bool) {
        engine.finishSetup()
        phase = .running
        elapsedMs = 0
        pausedMs = 0
        splits = []
        roundStartedAtElapsed = 0
        lastAnnouncedSecond = -1
        lastTick = Date()
        status = "Counting…"
        say(calibrated ? "Calibrated. Go." : "Go. Pull ups")
        startTimer()
    }

    private func pause() {
        phase = .paused
        pauseStartedAt = Date()
        timer?.invalidate()
        status = "Paused"
    }

    private func resume() {
        if let started = pauseStartedAt {
            pausedMs += Int64(Date().timeIntervalSince(started) * 1000)
            pauseStartedAt = nil
        }
        phase = .running
        lastTick = Date()
        // The phone or the athlete may have moved while the clock was stopped.
        engine.recalibrate()
        status = "Recalibrating…"
        say("Resume")
        startTimer()
    }

    func stopEarly() {
        finish(stoppedEarly: true)
    }

    private func reset() {
        phase = .idle
        remainingMs = Self.workoutMs
        elapsedMs = 0
        pausedMs = 0
        splits = []
        engine.reset()
        finished = nil
        status = "Press START to set up"
        render()
    }

    // MARK: - clock

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard phase == .running else { return }
        let now = Date()
        let step = Int64(now.timeIntervalSince(lastTick) * 1000)
        lastTick = now
        remainingMs -= step
        elapsedMs += step
        if remainingMs <= 0 {
            remainingMs = 0
            finish(stoppedEarly: false)
        } else {
            announceTime()
        }
    }

    private func announceTime() {
        let second = remainingMs / 1000
        guard second != lastAnnouncedSecond else { return }
        lastAnnouncedSecond = second
        switch second {
        case 600: say("Ten minutes remaining")
        case 300: say("Five minutes remaining")
        case 60: say("One minute")
        case 10: say("Ten seconds")
        default: break
        }
    }

    private func finish(stoppedEarly: Bool) {
        if let started = pauseStartedAt {
            pausedMs += Int64(Date().timeIntervalSince(started) * 1000)
            pauseStartedAt = nil
        }
        phase = .finished
        timer?.invalidate()

        let attempt = Attempt(
            rounds: engine.rounds,
            reps: engine.repsThisRound,
            atMillis: Int64(Date().timeIntervalSince1970 * 1000),
            durationMs: elapsedMs,
            pausedMs: pausedMs,
            roundSplitsMs: splits,
            profile: engine.profile,
            manualReps: engine.manualReps
        )
        records.add(attempt)
        finished = attempt

        say(stoppedEarly ? "Stopped." : "Time.")
        say("\(attempt.rounds) rounds and \(attempt.reps) reps")
    }

    // MARK: - engine plumbing

    private func applySetup(_ setup: Setup) {
        switch setup.stage {
        case .framing:
            statusIsWarning = true
            status = "Can't see your " + setup.missing.joined(separator: ", ")
        case .moving:
            statusIsWarning = false
            status = "Do 2 slow pull-ups to calibrate"
            reps = setup.reps
        case .poor:
            statusIsWarning = true
            status = "Movement barely registers — raise the phone or step back"
        case .ready:
            statusIsWarning = false
            begin(calibrated: true)
        }
    }

    private func apply(_ event: RepEvent) {
        switch event {
        case .none:
            break
        case .rep:
            say("\(engine.reps)")
        case .undo:
            say("\(engine.reps)")
        case .exerciseDone:
            say(engine.exercise.spoken)
        case .roundDone:
            let split = elapsedMs - roundStartedAtElapsed
            splits.append(split)
            roundStartedAtElapsed = elapsedMs
            say("Round \(engine.rounds + 1)")
        }
        render()
        if phase == .running {
            statusIsWarning = !engine.bodyVisible
            status = engine.calibrated ? engine.hint : "Recalibrating…"
        }
    }

    private func render() {
        exercise = engine.exercise
        reps = engine.reps
        rounds = engine.rounds
    }

    private func say(_ text: String) {
        guard voiceEnabled else { return }
        speech.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        speech.speak(utterance)
    }
}
