import AVFoundation
import Combine
import Foundation
import UIKit
import CindyCore

/// What the screen shows of a workout, and what it does about what `WorkoutSession` decides.
///
/// The session owns every decision (the clock, the setup check, what is said and when, what an undo
/// unwinds, what is saved); this owns the plumbing: a timer, a speaker, a vibration motor, the
/// record store and the crop of the camera. It copies what the session shows into published
/// properties after every call, and performs the effects the call returned.
@MainActor
final class WorkoutViewModel: ObservableObject {

    enum Phase { case idle, setup, running, paused, finished }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var clockText = "20:00"
    @Published private(set) var exerciseText = Exercise.pullup.label
    @Published private(set) var repsText = "0"
    @Published private(set) var targetText = "/5"
    @Published private(set) var rounds = 0
    @Published private(set) var status = "Tap to set up"
    @Published private(set) var dot: StatusDot = .neutral
    @Published private(set) var repProgress = 0
    @Published private(set) var coachShowing: Exercise?
    /// A line shown briefly: a round's time, or why the count is in English.
    @Published private(set) var toast: String?
    /// The attempt the results sheet is showing. Settable because `.sheet(item:)` clears it when
    /// the sheet is dismissed.
    @Published var finished: Attempt?
    @Published var voiceEnabled = true {
        didSet {
            speaker.enabled = voiceEnabled
            if !voiceEnabled { speaker.stop() }
        }
    }

    /// Asks the camera to forget the crop that was following the athlete.
    var onResetCrop: (() -> Void)?

    /// The language saved for the count, as a `VoicePacks` tag.
    var voiceLanguage: String { VoicePacks.of(defaults.string(forKey: Self.languageKey)).tag }

    /// Saves the language chosen in the sheet. Until it is saved, choosing only changes what the
    /// speaker previews in, so a sheet dismissed without saving is put back with `restoreLanguage`.
    func saveLanguage(_ tag: String) {
        let pack = VoicePacks.of(tag)
        defaults.set(pack.tag, forKey: Self.languageKey)
        speaker.language = pack.tag
    }

    /// Puts the speaker back on the saved language.
    func restoreLanguage() { speaker.language = voiceLanguage }

    private static let profileKey = "cindy.movementProfile"
    private static let languageKey = "voice_language"
    private let defaults = UserDefaults.standard

    /// Rebuilt rather than mutated when the movements change: a session's profile is immutable for
    /// its life on purpose, because a rep's meaning must not change halfway through the score it
    /// contributes to.
    private var session: WorkoutSession
    private let records = RecordStore()
    private let repTimes = RepTimesStore(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("rep_times", isDirectory: true))
    /// The voice. Held for the sheet that chooses its language too: both talk to the same engine.
    let speaker = Speaker(engine: AVSpeechTtsEngine())

    private var timer: Timer?
    private var stopWasRunning = false
    /// A stop that is waiting for the athlete's answer, with the clock parked behind it.
    private(set) var stopPending = false

    init() {
        session = WorkoutSession(
            profile: Variations.decode(UserDefaults.standard.string(forKey: WorkoutViewModel.profileKey)))
        speaker.language = VoicePacks.of(defaults.string(forKey: Self.languageKey)).tag
        sync()
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

    var statusIsWarning: Bool { dot == .alert }
    var inWorkout: Bool { phase == .running || phase == .paused }

    /// What the debug readout says about the counter.
    var counterReadout: String { session.counterReadout }

    /// Whether a readout is on the screen, so the demonstrator card stands down.
    var debugReadout: Bool {
        get { session.debugReadout }
        set { session.debugReadout = newValue }
    }

    /// The movements this session is counting.
    var profile: CindyProfile { session.profile }

    // MARK: - time

    /// Monotonic milliseconds: what every duration here is measured on.
    private var now: Int64 { Int64(ProcessInfo.processInfo.systemUptime * 1000) }
    private var wallClockMs: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    // MARK: - frames

    /// Feeds one analysed frame in. `tracking` is for this same frame: whether the crop it was
    /// analysed in was a tracked one.
    func onFrame(_ frame: PoseFrame) {
        let effects: [SessionEffect]
        switch phase {
        case .setup: effects = session.onSetupFrame(frame.keypoints, now: now, tracking: frame.tracking)
        case .running: effects = session.onFrame(frame.keypoints, now: now, tracking: frame.tracking)
        default: return
        }
        perform(effects)
    }

    // MARK: - controls

    /// START, PAUSE, RESUME or RESET. The setup check's SKIP goes through `skipSetup` once the
    /// athlete has been told what it costs.
    func primaryAction() {
        switch phase {
        case .idle: enterSetup()
        case .setup: break
        case .running, .paused: perform(session.togglePause(now: now)); stopTimerIfParked()
        case .finished: reset()
        }
        if phase == .running { startTimer() }
    }

    func enterSetup() {
        // A voice fetched since the screen last resumed is picked up here, before the first thing
        // is said; if the athlete's language is still not on the phone they are told why the count
        // is in English rather than left to wonder whether the setting took.
        speaker.refresh()
        if voiceEnabled && speaker.fallingBack {
            show("The \(speaker.wanted.englishName) voice isn't on this phone yet. Counting in English.")
        }
        perform(session.enterSetup())
    }

    func skipSetup() {
        perform(session.skipSetup(now: now))
        startTimer()
    }

    func manualRep() { perform(session.manualRep(now: now)) }
    func undoRep() { perform(session.undoRep(now: now)) }
    func skipExercise() { perform(session.skipExercise(now: now)) }

    /// The camera's view of the athlete changed (a flip), so the learned band is stale.
    func recalibrate() { session.recalibrate() }

    /// STOP: parks the clock while the question is up, as the Android screen does.
    func requestStop() {
        stopPending = true
        stopWasRunning = phase == .running
        if stopWasRunning { primaryAction() }
    }

    /// The athlete said KEEP GOING, or dismissed the question: the clock carries on.
    func cancelStop() {
        guard stopPending else { return }
        stopPending = false
        if stopWasRunning { primaryAction() }
    }

    func stopEarly() {
        stopPending = false
        finish(session.finish(stoppedEarly: true, now: now, wallClockMs: wallClockMs))
    }

    private func reset() {
        finished = nil
        perform(session.reset())
    }

    /// Changes the movements for the next workout. Refused mid-session: a rep's meaning cannot
    /// change halfway through the score it contributes to.
    @discardableResult
    func setMovementProfile(_ chosen: CindyProfile) -> Bool {
        guard phase == .idle || phase == .finished else { return false }
        defaults.set(Variations.encode(chosen), forKey: Self.profileKey)
        session = WorkoutSession(profile: chosen)
        sync()
        return true
    }

    // MARK: - the clock

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTimerIfParked() {
        if phase != .running { timer?.invalidate(); timer = nil }
    }

    private func tick() {
        let result = session.tick(now: now, wallClockMs: wallClockMs)
        perform(result.effects)
        if let done = result.finished { finish(done) }
        stopTimerIfParked()
    }

    private func finish(_ done: FinishedWorkout) {
        timer?.invalidate()
        timer = nil
        // A workout with nothing counted is someone opening the app and letting the clock run out,
        // so the store drops it; the rep times belong beside a saved attempt and only one.
        if records.add(done.attempt) {
            try? repTimes.save(atMillis: done.attempt.atMillis, done.marks)
        }
        finished = done.attempt
        perform(done.effects)
    }

    // MARK: - effects

    private func perform(_ effects: [SessionEffect]) {
        for effect in effects {
            switch effect {
            case .say(let line): speak(line, queue: .replace)
            case .queue(let line): speak(line, queue: .append)
            case .stopSpeaking: speaker.stop()
            case .buzz(let ms): buzz(ms)
            case .toast(let text): show(text)
            case .resetCrop: onResetCrop?()
            case .liveWorkout(let live): LiveWorkout.active = live
            case .calibratedBanner: break   // the recording's banner: filming is a later phase
            }
        }
        sync()
    }

    private func speak(_ line: VoiceLine, queue: SpeakQueue) {
        // Silent while VoiceOver runs, as the Android screen is under TalkBack: two voices at once
        // is worse than one.
        guard voiceEnabled, !UIAccessibility.isVoiceOverRunning else { return }
        switch queue {
        case .replace: speaker.say(line)
        case .append: speaker.queue(line)
        }
    }

    /// Short per rep, longer per movement, longest per round.
    private func buzz(_ ms: Int) {
        switch ms {
        case ..<40: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case ..<100: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case ..<300: UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        default: UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func show(_ text: String) {
        toast = text
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self?.toast == text { self?.toast = nil }
        }
    }

    private func sync() {
        switch session.state {
        case .idle: phase = .idle
        case .setup: phase = .setup
        case .running: phase = .running
        case .paused: phase = .paused
        case .finished: phase = .finished
        }
        clockText = session.clockText
        exerciseText = session.exerciseText
        repsText = session.repsText
        targetText = session.targetText
        rounds = session.rounds
        status = session.status
        dot = session.dot
        repProgress = session.repProgress
        coachShowing = session.coachShowing
    }
}
