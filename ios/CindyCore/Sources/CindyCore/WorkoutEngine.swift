import Foundation

/// One round of Cindy: 5 pull-ups, 10 push-ups, 15 air squats.
public enum Exercise: Int, CaseIterable, Sendable {
    case pullup, pushup, squat

    public var label: String {
        switch self {
        case .pullup: return "PULL-UPS"
        case .pushup: return "PUSH-UPS"
        case .squat: return "SQUATS"
        }
    }

    public var spoken: String {
        switch self {
        case .pullup: return "pull ups"
        case .pushup: return "push ups"
        case .squat: return "squats"
        }
    }

    public var target: Int {
        switch self {
        case .pullup: return 5
        case .pushup: return 10
        case .squat: return 15
        }
    }

    public var next: Exercise {
        Exercise(rawValue: (rawValue + 1) % Exercise.allCases.count)!
    }

    public var previous: Exercise {
        Exercise(rawValue: (rawValue + Exercise.allCases.count - 1) % Exercise.allCases.count)!
    }
}

/// What the last analysed frame produced.
public enum RepEvent { case none, rep, undo, exerciseDone, roundDone }

/// How the pre-workout check is getting on.
public enum SetupStage {
    /// Joints this movement needs are not all in shot.
    case framing
    /// Framing is good; waiting for calibration reps.
    case moving
    /// Calibrated — the workout can start.
    case ready
    /// Framing is good but the movement barely registers, so the phone is badly placed.
    case poor
}

/// A frame's worth of pre-workout check.
public struct Setup {
    public let stage: SetupStage
    public let missing: [String]
    public let reps: Int
    public let range: Float
    public let needed: Float
}

/// Turns a stream of keypoints into a Cindy scorecard.
///
/// Only the signal for the *current* exercise is evaluated. That is deliberate: the three
/// movements share joints, and scoring all of them at once lets a push-up lockout leak into the
/// squat counter.
public final class WorkoutEngine {

    /// MoveNet/Vision confidence below which a keypoint is treated as unseen.
    private static let minScore: Float = 0.30
    /// Reps to watch before trusting the learned band.
    private static let calibrationReps = 2
    /// How long to wait for a believable range before calling the setup bad.
    private static let poorAfterMs: Int64 = 20_000
    /// Elbow angle at or above which the arms count as straight, i.e. a dead hang.
    private static let deadHangDegrees: Float = 150

    // minRange is the projected travel below which a swing is not believed to be a rep at all;
    // above it the counter calibrates to the athlete and the fixed numbers stop mattering.
    private var counters: [Exercise: RepCounter] = [
        // All three signals are joint angles in degrees. The pull-up one is negated because a
        // dead hang is the *extended* end of its range, the opposite way round to the others.
        .pullup: RepCounter(downBelow: -140, upAbove: -100, minRepMs: 400, minRange: 40),
        .pushup: RepCounter(downBelow: 100, upAbove: 150, minRepMs: 350, minRange: 45),
        .squat: RepCounter(downBelow: 100, upAbove: 158, minRepMs: 350, minRange: 55)
    ]

    public private(set) var exercise: Exercise = .pullup
    public private(set) var rounds = 0
    /// Human-readable reason the current frame did or did not score.
    public private(set) var hint = "Step into frame"
    public private(set) var bodyVisible = false

    private var movingSince: Int64 = 0
    private let bar = BarZone()

    /// True once a dead hang has taught the engine where the bar is.
    public var barKnown: Bool { bar.established }

    public init() {}

    private var counter: RepCounter { counters[exercise]! }

    public var reps: Int { counter.count }
    public var phase: RepCounter.Phase { counter.phase }
    public var signal: Float { counter.smoothed }
    public var learnedRange: Float { counter.learnedRange }
    public var calibrated: Bool { counter.calibrated }

    /// Reps completed since the start of the current round, across all three movements.
    public var repsThisRound: Int {
        Exercise.allCases.prefix(exercise.rawValue).reduce(0) { $0 + $1.target } + reps
    }

    public var totalReps: Int { rounds * 30 + repsThisRound }

    public func reset() {
        counters.values.forEach { $0.reset() }
        exercise = .pullup
        rounds = 0
        hint = "Step into frame"
        bodyVisible = false
        movingSince = 0
        bar.reset()
    }

    /// Advances past the current exercise without finishing it (manual override).
    @discardableResult
    public func skipExercise() -> RepEvent { advance() }

    /// Books one rep by hand, for when the camera angle defeats the detector.
    @discardableResult
    public func manualRep() -> RepEvent {
        counter.forceIncrement()
        return settle()
    }

    /// Takes back a rep the counter should not have scored.
    ///
    /// Steps backwards across movement and round boundaries, so undoing the first push-up of a
    /// round returns you to the fifth pull-up rather than stranding the score at zero.
    @discardableResult
    public func undoRep() -> RepEvent {
        if counter.count > 0 {
            counter.forceDecrement()
            return .undo
        }
        if exercise != .pullup {
            let previous = exercise.previous
            exercise = previous
            counter.setCount(previous.target - 1)
            return .undo
        }
        guard rounds > 0 else { return .none }
        rounds -= 1
        exercise = .squat
        counter.setCount(Exercise.squat.target - 1)
        return .undo
    }

    /// Forgets every learned band, keeping the score.
    ///
    /// The bands describe this athlete as seen from where the phone was standing. A flip, or a
    /// pause long enough for either to have moved, invalidates that without invalidating the reps
    /// already counted.
    public func recalibrate() {
        counters.values.forEach { $0.resetBand() }
        // The bar's position was recorded in frame pixels, so a moved camera invalidates it.
        bar.reset()
    }

    @discardableResult
    public func onFrame(_ k: [Keypoint], now: Int64) -> RepEvent {
        guard let torso = torsoLength(k), torso >= 1 else {
            bodyVisible = false
            hint = "Step into frame"
            return .none
        }
        bodyVisible = true

        let s = signalFor(k)
        guard !s.isNaN else { return .none }

        guard counter.update(s, now: now) else {
            hint = phase == .down ? "Drive up" : "Go down"
            return .none
        }
        return settle()
    }

    /// Advances to the next movement if the current one just hit its target.
    private func settle() -> RepEvent {
        reps >= exercise.target ? advance() : .rep
    }

    private func advance() -> RepEvent {
        counter.resetCount()
        let wasLast = exercise == .squat
        exercise = exercise.next
        counter.resetCount()
        if wasLast {
            rounds += 1
            return .roundDone
        }
        return .exerciseDone
    }

    // MARK: - pre-workout check

    /// Starts the check for the current movement, discarding any band learned earlier.
    public func beginSetup() {
        counter.reset()
        movingSince = 0
        bar.reset()
    }

    /// Watches a calibration rep and reports whether this camera placement can be worked with.
    ///
    /// The check is just the counter running before the clock does. Calibrating this way seeds
    /// the band from the athlete's own range, so the first rep of the workout is judged against a
    /// real measurement rather than the fallback floor — and a placement that cannot produce a
    /// believable range is caught here instead of quietly undercounting for twenty minutes.
    public func onSetupFrame(_ k: [Keypoint], now: Int64) -> Setup {
        let missing = missingJoints(k)
        guard missing.isEmpty else {
            movingSince = 0
            return Setup(stage: .framing, missing: missing, reps: counter.count,
                         range: counter.learnedRange, needed: counter.requiredRange)
        }
        if movingSince == 0 { movingSince = now }

        let s = signalFor(k)
        if !s.isNaN { counter.update(s, now: now) }

        let enough = counter.count >= Self.calibrationReps
            && counter.learnedRange >= counter.requiredRange
        let stage: SetupStage
        if enough {
            stage = .ready
        } else if now - movingSince > Self.poorAfterMs {
            stage = .poor
        } else {
            stage = .moving
        }
        return Setup(stage: stage, missing: [], reps: counter.count,
                     range: counter.learnedRange, needed: counter.requiredRange)
    }

    /// Zeroes the calibration reps but keeps the band they taught.
    public func finishSetup() { counter.resetCount() }

    /// Joints the current movement cannot be judged without, named for a human.
    private func missingJoints(_ k: [Keypoint]) -> [String] {
        let needed: [(String, (Int, Int))]
        switch exercise {
        case .pullup, .pushup:
            needed = [
                ("shoulders", (KP.leftShoulder, KP.rightShoulder)),
                ("elbows", (KP.leftElbow, KP.rightElbow)),
                ("hands", (KP.leftWrist, KP.rightWrist)),
                ("hips", (KP.leftHip, KP.rightHip))
            ]
        case .squat:
            needed = [
                ("shoulders", (KP.leftShoulder, KP.rightShoulder)),
                ("hips", (KP.leftHip, KP.rightHip)),
                ("knees", (KP.leftKnee, KP.rightKnee)),
                ("ankles", (KP.leftAnkle, KP.rightAnkle))
            ]
        }
        // midpoint accepts either side, so a joint counts as seen if one of the pair is.
        return needed.filter { midpoint(k, $0.1.0, $0.1.1) == nil }.map { $0.0 }
    }

    private func signalFor(_ k: [Keypoint]) -> Float {
        switch exercise {
        case .pullup: return pullupSignal(k)
        case .pushup: return pushupSignal(k)
        case .squat: return squatSignal(k)
        }
    }

    // MARK: - signals

    /// Mean elbow angle, negated: about -170 at a dead hang, about -60 with the chin over the bar.
    ///
    /// Measuring the elbow rather than how far the shoulders rise keeps the hips — the least
    /// reliable joints on someone hanging with their knees bent behind them — out of the
    /// measurement entirely, and an angle needs no normalisation at all.
    private func pullupSignal(_ k: [Keypoint]) -> Float {
        guard hangingFromBar(k) else {
            hint = "Hang from the bar"
            return .nan
        }
        guard let hands = midpoint(k, KP.leftWrist, KP.rightWrist),
              let torso = torsoLength(k) else { return .nan }

        // Elbow flexion on its own counts anyone waving their arms overhead as a pull-up.
        guard bar.holds(handsX: hands.x, handsY: hands.y, torso: torso) else {
            hint = "Get on the bar"
            return .nan
        }

        let elbow = bilateralAngle(k,
                                   KP.leftShoulder, KP.leftElbow, KP.leftWrist,
                                   KP.rightShoulder, KP.rightElbow, KP.rightWrist)
        guard !elbow.isNaN else {
            hint = "Arms out of frame"
            return .nan
        }

        // A straight-armed hang is the one posture that reliably marks where the bar is.
        if elbow >= Self.deadHangDegrees {
            bar.observeHang(handsX: hands.x, handsY: hands.y, halfGrip: gripHalfWidth(k) ?? 0)
        }
        return -elbow
    }

    /// Half the distance between the hands, for the bar's horizontal span.
    private func gripHalfWidth(_ k: [Keypoint]) -> Float? {
        let l = k[KP.leftWrist], r = k[KP.rightWrist]
        guard ok(l), ok(r) else { return nil }
        return abs(l.x - r.x) / 2
    }

    /// Hands overhead, tested against the hips rather than the shoulders.
    ///
    /// The shoulders climb past the hands at the top of a good rep, so gating on them rejects the
    /// peak of the movement. The hips stay well below the hands throughout.
    private func hangingFromBar(_ k: [Keypoint]) -> Bool {
        guard let hip = midpoint(k, KP.leftHip, KP.rightHip),
              let wrist = midpoint(k, KP.leftWrist, KP.rightWrist) else { return false }
        return wrist.y < hip.y
    }

    /// Mean elbow angle in degrees; small at the bottom of a push-up, ~180 at lockout.
    private func pushupSignal(_ k: [Keypoint]) -> Float {
        // Guard against a pull-up being scored as a push-up, using the same overhead test.
        if hangingFromBar(k) {
            hint = "Get on the floor"
            return .nan
        }
        return bilateralAngle(k,
                              KP.leftShoulder, KP.leftElbow, KP.leftWrist,
                              KP.rightShoulder, KP.rightElbow, KP.rightWrist)
    }

    /// Mean knee angle in degrees; small in the hole, ~180 standing.
    private func squatSignal(_ k: [Keypoint]) -> Float {
        let a = bilateralAngle(k,
                               KP.leftHip, KP.leftKnee, KP.leftAnkle,
                               KP.rightHip, KP.rightKnee, KP.rightAnkle)
        if a.isNaN { hint = "Show your legs to the camera" }
        return a
    }

    // MARK: - geometry

    private func ok(_ p: Keypoint) -> Bool { p.score >= Self.minScore }

    private func midpoint(_ k: [Keypoint], _ a: Int, _ b: Int) -> Keypoint? {
        let pa = k[a], pb = k[b]
        if ok(pa) && ok(pb) {
            return Keypoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2, score: min(pa.score, pb.score))
        }
        if ok(pa) { return pa }
        if ok(pb) { return pb }
        return nil
    }

    private func torsoLength(_ k: [Keypoint]) -> Float? {
        guard let sh = midpoint(k, KP.leftShoulder, KP.rightShoulder),
              let hip = midpoint(k, KP.leftHip, KP.rightHip) else { return nil }
        return hypotf(sh.x - hip.x, sh.y - hip.y)
    }

    /// Averages the same joint angle on both sides, using whichever sides are confidently seen.
    private func bilateralAngle(_ k: [Keypoint],
                                _ la: Int, _ lb: Int, _ lc: Int,
                                _ ra: Int, _ rb: Int, _ rc: Int) -> Float {
        let l = angle(k[la], k[lb], k[lc])
        let r = angle(k[ra], k[rb], k[rc])
        if !l.isNaN && !r.isNaN { return (l + r) / 2 }
        if !l.isNaN { return l }
        if !r.isNaN { return r }
        return .nan
    }

    /// Interior angle at `b`, in degrees, or NaN if any vertex is not confidently seen.
    private func angle(_ a: Keypoint, _ b: Keypoint, _ c: Keypoint) -> Float {
        guard ok(a), ok(b), ok(c) else { return .nan }
        let abx = a.x - b.x, aby = a.y - b.y
        let cbx = c.x - b.x, cby = c.y - b.y
        let mag = hypotf(abx, aby) * hypotf(cbx, cby)
        guard mag >= 1e-4 else { return .nan }
        let cosine = max(-1, min(1, (abx * cbx + aby * cby) / mag))
        return acosf(cosine) * 180 / .pi
    }
}
