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

    /// True when the movement is entered from a posture the athlete has to assume first.
    ///
    /// Getting up off the floor after a set of push-ups traces the second half of a squat
    /// exactly: a deep knee bend followed by a climb to full extension. Nothing in the knee angle
    /// alone separates that from a rep, so these movements refuse to score until the athlete has
    /// been seen in the position the movement actually starts from.
    ///
    /// Pull-ups are excluded because their own bar and dead-hang gates already do this.
    public var startsFromPosition: Bool {
        switch self {
        case .pullup: return false
        case .pushup, .squat: return true
        }
    }

    /// Said and shown while that starting position has not been reached.
    public var startCue: String {
        switch self {
        case .pullup: return "Hang from the bar"
        case .pushup: return "Get set on the floor"
        case .squat: return "Stand up to start"
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

    public init(stage: SetupStage, missing: [String], reps: Int, range: Float, needed: Float) {
        self.stage = stage
        self.missing = missing
        self.reps = reps
        self.range = range
        self.needed = needed
    }
}

/// The gate decisions behind the most recently analysed frame.
///
/// This is deliberately public and framework-free: the offline video harness writes it to its
/// reports, making a rejected frame explainable without duplicating any counter decisions.
public struct FrameDiagnostics: Equatable, Sendable {
    public var minimumConfidence: Float = 0
    /// True only when the keypoints used to construct the current exercise signal are usable.
    public var scoringConfidenceAdequate: Bool = false
    /// True when *every* joint the current movement scores from was confidently seen.
    ///
    /// Stricter than `scoringConfidenceAdequate` on purpose. That flag asks whether this frame
    /// could be scored, and the geometry helpers behind it fall back to whichever side of the body
    /// is visible, so it stays true through the single-sided view that precedes a real failure.
    /// This asks the blunter question — how well can the camera read the athlete at all — so that
    /// it degrades *before* counting does. An early warning is worthless if it arrives with the
    /// miscount.
    public var poseLegible: Bool = false
    public var identityStable: Bool = false
    public var barGateOpen: Bool = false
    public var headAboveBar: Bool = false
    public var deadHangSinceLastRep: Bool = false
    public var resetBelowBarSeen: Bool = false
    public var rejectionReason: String?
}

/// The pull-up gate as the overlay draws it: the box both wrists must sit in, and the line the
/// head must drop back below before the next rep can arm.
public struct BarGuide: Equatable, Sendable {
    public let zone: BarZone.Bounds
    public let resetY: Float
    public let gateOpen: Bool
}

/// Turns a stream of keypoints into a Cindy scorecard.
///
/// Only the signal for the *current* exercise is evaluated. That is deliberate: the three
/// movements share joints, and scoring all of them at once lets a push-up lockout leak into the
/// squat counter.
public final class WorkoutEngine {

    /// Consecutive overhead frames before an unknown bar may be learned from a dead hang.
    ///
    /// `PoseGeometry.handsOverhead` answers true when the nose is not confidently seen — on
    /// purpose, so rear-view footage is not locked out — so a *single* dropped nose keypoint was
    /// enough to let a band held at chest height be taught as the bar, which can never recover.
    /// Measured: one frame in sixty did exactly that and cost a whole clip its score.
    private static let overheadHoldFrames = 5
    /// Reps to watch before trusting the learned band.
    private static let calibrationReps = 2
    /// How long to wait for a believable range before calling the setup bad.
    private static let poorAfterMs: Int64 = 20_000
    /// Elbow angle at or above which the arms count as straight, i.e. a dead hang.
    private static let strictDeadHangDegrees: Float = 150
    /// How far below the straightest arms yet seen still reads as a dead hang.
    ///
    /// 150 degrees assumes the camera sees the elbow square on. A phone on the floor looks up at
    /// the athlete and foreshortens the upper arm, so a genuinely locked-out hang can project as
    /// 140 — and a fixed threshold then refuses to arm a single rep for the whole workout. This
    /// is the same argument that made `RepCounter` learn its band instead of trusting fixed
    /// thresholds, applied to the gate in front of it.
    private static let deadHangSlackDegrees: Float = 15
    /// Floor under the derived dead-hang angle.
    ///
    /// Without it the derivation eats itself: an athlete who has only ever been seen with bent
    /// arms teaches a small "extension", which drops the threshold far enough that the bent arms
    /// then qualify as a hang. No camera angle turns a 60-degree elbow into a locked-out one, so
    /// the relaxation stops here.
    private static let deadHangFloorDegrees: Float = 130
    /// Body-scale change past which a learned bar is describing a geometry that has gone.
    ///
    /// The bar's tolerances are multiples of torso length, so an estimate learned while the
    /// athlete stood close to the camera does not fit them hanging further away.
    private static let barScaleChange: Float = 1.6
    /// Straight-armed hangs rejected at that different scale before the bar is abandoned.
    private static let maxBarContradictions = 30
    /// How long hands must hang overhead without moving before their position is taken as the
    /// bar, when no dead hang has managed to establish one.
    ///
    /// Long, on purpose. This is the slow fallback behind the dead-hang route, and stillness is
    /// weaker evidence than a straight-armed hang, so it has to be sustained stillness.
    private static let barSettleMs: Int64 = 3_000
    /// How far the hands may drift, in torso lengths, and still count as held still.
    private static let barSettleDriftTorsos: Float = 0.2
    /// How far below the bar the head must return before another pull-up can arm.
    private static let headResetTorsos: Float = 0.25
    /// Unusable frames tolerated mid-rep before the cycle is abandoned.
    ///
    /// A pull-up occludes its own keypoints exactly where it matters: at the top the head tilts
    /// back and the wrists disappear behind it. Treating the first sub-threshold frame as "left
    /// the bar" threw the rep away at the moment it was earned. Eight frames is a third of a
    /// second at 24fps — long enough to ride out an occlusion or a motion-blurred frame, far too
    /// short to cover someone actually dropping off the bar.
    private static let maxDropoutFrames = 8
    /// How long the starting posture must hold, without extending further, to be taken up.
    ///
    /// Half a second of *stillness*, not half a second of merely being upright. Upright alone was
    /// not enough: people get up off the floor by bringing the torso vertical first and gathering
    /// themselves in a crouch, which is upright for far longer than this — and the drive out of
    /// that crouch was then booked as a rep, which is the bug this exists for.
    private static let startPositionMs: Int64 = 500
    /// Further extension than this, within the dwell, means they are still getting up.
    ///
    /// Deliberately a *change* and not a threshold. An absolute "legs straight" angle is the trap
    /// this engine keeps falling into — a phone on the floor foreshortens a standing body until
    /// full extension reads 145 degrees, under the 158 needed to score, and the athlete is locked
    /// out. How far a joint still has left to travel does not care where the camera is standing.
    private static let startSettleDegrees: Float = 3
    /// Smoothing on the settling signal, so raw jitter does not read as still rising.
    private static let startSettleSmoothing: Float = 0.4

    /// The least a heels-flat squat has to close the knee, in degrees, to be a rep.
    ///
    /// Heels flat on the floor stop the knees travelling forward, so the hips stop higher and the
    /// knee closes less than it does up on the toes: seen from a phone on the floor a good one
    /// travels 35 to 40 degrees where the air squat asks for about 58. Both are correct squats. A
    /// quarter squat seen from chest height travels 30 to 35, so this is the line between them,
    /// and the one number to retune after trying it on a phone: lowered to 33 it lets a good squat
    /// from the floor count at 110 degrees, and a quarter squat from chest height count at 140.
    private static let heelsFlatMinTravel: Float = 35

    /// How much of the learned travel, from the bottom, counts as having gone down.
    ///
    /// Sixty percent where every other movement uses thirty, because the band of someone who mixes
    /// both styles is as deep as their deepest squat, and a heels-flat rep after a deep one would
    /// otherwise never reach its bottom zone. Measured: three deep squats and then ten heels-flat
    /// ones to 125 degrees count 13 of 13 with this, and 8 of 13 at a margin of 50%.
    private static let heelsFlatBottomMargin: Float = 0.6

    /// Where an uncalibrated heels-flat squat has to have got to, in knee degrees.
    ///
    /// The climb from here to the lockout is 38 degrees, just over `heelsFlatMinTravel`, the same
    /// relation the air squat has between its own two numbers (58 against 55). So a counter that
    /// has not calibrated yet can never book a climb the calibrated one would refuse.
    private static let heelsFlatDownBelow: Float = 120

    /// How many reps only the heels-flat counter has to accept, in one block of squats, before
    /// smart squat counting goes over to it.
    ///
    /// Three because one is a rep, and two is a coincidence a single half-hearted squat could
    /// make; it is also few enough that the athlete has lost almost nothing by the time the count
    /// catches up, which it does by crediting all three.
    private static let smartSquatSpotReps = 3

    /// Keeps the engine on one movement for a labelled exercise clip. The application uses the
    /// default Cindy progression; the regression harness uses this mode so a ten-rep push-up
    /// video is not truncated at Cindy's five-pull-up transition.
    private let fixedExercise: Exercise?

    /// The movements this session is counting, fixed before the clock starts.
    ///
    /// Immutable for the life of the engine on purpose: a rep's meaning cannot be allowed to
    /// change halfway through the score it contributes to. Changing movements means a new
    /// session, which is also the only way the history line can stay true.
    public let profile: CindyProfile

    /// Whether an air-squat session may notice heels-flat squats and start counting them as such.
    ///
    /// Off unless the athlete has switched it on: it is being tested, and a counter that changes
    /// its own mind about a movement has to be wanted before it is trusted. Public so the screen
    /// can tell whether the engine it holds was built for the setting as it stands now, and fixed
    /// for the life of the engine like `profile`, for the same reason.
    ///
    /// It acts on the frames of a workout and nowhere else. The app never runs the setup check on
    /// squats, because it calibrates on the pull-up, and it is not meant to: a switch made before
    /// the clock starts would carry into the workout with nobody told.
    public let smartSquats: Bool

    private let counters: [Exercise: RepCounting]

    // minRange is the projected travel below which a swing is not believed to be a rep at all;
    // above it the counter calibrates to the athlete and the fixed numbers stop mattering.
    private static func makeCounters(profile: CindyProfile, smartSquats: Bool,
                                     fixedExercise: Exercise?) -> [Exercise: RepCounting] {
        [
            // All three signals are joint angles in degrees. The pull-up one is negated because a
            // dead hang is the *extended* end of its range, the opposite way round to the others.
            .pullup: RepCounter(downBelow: -140, upAbove: -100, minRepMs: 400, minRange: 40),
            .pushup: RepCounter(downBelow: 100, upAbove: 150, minRepMs: 350, minRange: 45),
            .squat: squatCounter(profile: profile, smartSquats: smartSquats, fixedExercise: fixedExercise)
        ]
    }

    /// The counter for the chosen squat.
    ///
    /// Exhaustive over `SquatVariant` with no `default`, like the Strava mapping, so a new squat has
    /// to be given a counter on purpose. Box and supported squats keep the air squat's. Only the
    /// air squat is ever handed to `SmartSquatCounter`: someone who has chosen heels flat has
    /// already said, and someone on a box has a depth of their own.
    private static func squatCounter(profile: CindyProfile, smartSquats: Bool,
                                     fixedExercise: Exercise?) -> RepCounting {
        switch profile.squat {
        case .heelsFlat:
            return heelsFlatCounter()
        case .airSquat:
            if smartSquats {
                return SmartSquatCounter(
                    air: airSquatCounter(),
                    heelsFlat: heelsFlatCounter(),
                    spotAfter: smartSquatSpotReps,
                    creditCap: fixedExercise == nil ? Exercise.squat.target : Int.max
                )
            }
            return airSquatCounter()
        case .boxSquat, .supportedSquat:
            return airSquatCounter()
        }
    }

    private static func airSquatCounter() -> RepCounter {
        RepCounter(downBelow: 100, upAbove: 158, minRepMs: 350, minRange: 55)
    }

    private static func heelsFlatCounter() -> RepCounter {
        RepCounter(downBelow: heelsFlatDownBelow, upAbove: 158, minRepMs: 350,
                   minRange: heelsFlatMinTravel,
                   bottomMargin: heelsFlatBottomMargin,
                   minTravel: heelsFlatMinTravel)
    }

    public private(set) var exercise: Exercise
    public private(set) var rounds = 0
    /// Human-readable reason the current frame did or did not score.
    public private(set) var hint = "Step into frame"
    public private(set) var bodyVisible = false

    /// Reps tapped in rather than seen, across the whole session.
    ///
    /// Reported with the score because "87 reps" and "87 reps, 12 by hand" are different claims.
    public private(set) var manualReps = 0

    /// How the most recent rep was booked.
    public private(set) var lastRepSource: Tracking = .auto

    /// Details used by the video-regression reports for the most recent frame.
    public private(set) var diagnostics = FrameDiagnostics()

    /// Stable spelling for scenario files; it does not expose `RepCounter`'s implementation enum.
    public var countingState: String {
        switch phase {
        case .unknown: return "idle"
        case .down: return "down"
        case .up: return "up"
        }
    }

    private var movingSince: Int64 = 0
    private let bar = BarZone()
    private var setupInProgress = false
    /// A fresh, on-bar dead hang is required before every pull-up count.
    private var pullupDownSeen = false
    /// Consecutive unusable frames since the last good one, while a cycle is in flight.
    private var pullupDropoutFrames = 0
    /// Straightest elbow angle seen while hanging, which scales the dead-hang test.
    private var pullupExtendedElbow: Float = .nan
    /// Torso length when the current bar estimate was first established.
    private var barTorso: Float = .nan
    /// Consecutive dead hangs a bar learned at a very different scale has refused.
    private var barContradictions = 0
    /// When the current run of still, overhead hands began, or 0 while broken.
    /// Consecutive frames the hands have been overhead, gating what a bar may be learned from.
    private var overheadFrames = 0
    private var barSettleSince: Int64 = 0
    /// Hand position the current still run is measured from, or nil while broken.
    private var barSettleHands: Keypoint?

    /// True once a dead hang has taught the engine where the bar is.
    public var barKnown: Bool { bar.established }

    /// True while waiting for the athlete to take up the current movement's starting position.
    public private(set) var awaitingStart = false

    /// When the current run of correct, no-longer-extending posture began, or 0 while broken.
    private var startPositionSince: Int64 = 0
    /// Smoothed signal while taking up a position, and the value the dwell was measured from.
    private var startSmoothed: Float = .nan
    private var startReference: Float = .nan

    /// True when this frame was refused for a reason the athlete could fix by moving.
    ///
    /// Distinct from simply being mid-rep: "Go down" is not a problem, whereas "Stand up to
    /// start" or "Get on the bar" means nothing is being counted until something changes. The UI
    /// uses it to decide when a hint is worth saying out loud.
    public private(set) var blocked = false

    /// Where to draw the pull-up gate, or nil while no bar is known.
    ///
    /// The overlay exists because the gates that refuse a rep are invisible: "Get on the bar" and
    /// "Return to a dead hang" describe a box and a line the athlete cannot see. This is the
    /// engine's own geometry, not a second estimate of it, so what is drawn is what is tested.
    public private(set) var barGuide: BarGuide?

    public init(fixedExercise: Exercise? = nil, profile: CindyProfile = .standard,
                smartSquats: Bool = false) {
        self.fixedExercise = fixedExercise
        self.profile = profile
        self.smartSquats = smartSquats
        self.exercise = fixedExercise ?? .pullup
        self.counters = Self.makeCounters(profile: profile, smartSquats: smartSquats,
                                          fixedExercise: fixedExercise)
    }

    private var counter: RepCounting { counters[exercise]! }

    /// True once smart squat counting has noticed heels-flat squats and taken over the count.
    ///
    /// Only ever true for an engine built with `smartSquats`, on an air-squat profile. Read by the
    /// screen, which announces it once and tells the results screen.
    public var heelsFlatSpotted: Bool {
        (counters[.squat] as? SmartSquatCounter)?.switched == true
    }

    /// The movements this session was actually counted as.
    ///
    /// `profile` is what the athlete chose and never changes. This is that, unless smart squat
    /// counting took over, in which case the squats were counted as heels-flat squats and the
    /// record has to say so: a rep's meaning must not be different from the one it was scored
    /// under. The whole session is filed that way, not only the squats after the switch, because a
    /// squat on the toes also meets the heels-flat standard, so the label errs the honest way and
    /// never claims more than was done.
    public var countedProfile: CindyProfile {
        guard heelsFlatSpotted else { return profile }
        var counted = profile
        counted.squat = .heelsFlat
        return counted
    }

    /// The score the movement had actually reached when the last event fired.
    ///
    /// The count itself is cleared by `advance` on the way into the next movement, so by the time a
    /// caller reads `reps` after an `.exerciseDone` it is looking at the new movement's zero. The
    /// voice used to work around that by announcing the *target* instead, which was right only
    /// because finishing was the only way to leave a movement. Skipping is the other way, and the
    /// athlete who did three push-ups and skipped is owed "three", not "ten".
    public private(set) var repsAtLastEvent = 0

    /// What each movement of the round in progress actually scored, filled in as each is left.
    ///
    /// Reps used to be inferred from position — "past the push-ups" was taken to mean ten of them
    /// — which is true only while the sole way past a movement is to finish it. SKIP means a round
    /// can be completed with fewer reps in it than its targets, and a tally that keeps crediting
    /// the targets is a tally that reports work nobody did.
    private var bankedThisRound: [Exercise: Int] = [:]

    /// The same, for every round already finished — kept per round rather than summed so that
    /// `undoRep` can step back over a round boundary into the score that was really there.
    private var bankedRounds: [[Exercise: Int]] = []

    public var reps: Int { counter.count }
    public var phase: RepCounter.Phase { counter.phase }
    public var signal: Float { counter.smoothed }
    public var learnedRange: Float { counter.learnedRange }
    public var calibrated: Bool { counter.calibrated }

    /// Reps completed since the start of the current round, across all three movements.
    ///
    /// The movements already left contribute what they actually scored, not what they were asked
    /// for. Those two only differ when something was skipped, which is exactly the case this
    /// figure used to get wrong.
    public var repsThisRound: Int { bankedThisRound.values.reduce(0, +) + reps }

    public var totalReps: Int {
        bankedRounds.reduce(0) { $0 + $1.values.reduce(0, +) } + repsThisRound
    }

    public func reset() {
        counters.values.forEach { $0.reset() }
        exercise = fixedExercise ?? .pullup
        rounds = 0
        hint = "Step into frame"
        bodyVisible = false
        movingSince = 0
        setupInProgress = false
        pullupDownSeen = false
        pullupExtendedElbow = .nan
        barTorso = .nan
        barContradictions = 0
        overheadFrames = 0
        barSettleSince = 0
        barSettleHands = nil
        awaitingStart = false
        startPositionSince = 0
        startSmoothed = .nan
        startReference = .nan
        blocked = false
        manualReps = 0
        lastRepSource = .auto
        repsAtLastEvent = 0
        bankedThisRound.removeAll()
        bankedRounds.removeAll()
        diagnostics = FrameDiagnostics()
        bar.reset()
        barGuide = nil
    }

    /// Advances past the current exercise without finishing it (manual override).
    @discardableResult
    public func skipExercise() -> RepEvent { advance() }

    /// Books one rep by hand, for when the camera angle defeats the detector.
    @discardableResult
    public func manualRep() -> RepEvent {
        counter.forceIncrement()
        manualReps += 1
        lastRepSource = .manual
        return settle()
    }

    /// Takes back a rep the counter should not have scored.
    ///
    /// Steps backwards across movement and round boundaries, so undoing the first push-up of a
    /// round returns you to the fifth pull-up rather than stranding the score at zero.
    @discardableResult
    public func undoRep() -> RepEvent {
        awaitingStart = false
        // Which rep is being taken back is not recorded, so undo assumes it was the last one
        // booked. Wrong only if the athlete taps +1, lets the camera score, then undoes twice —
        // and wrong by one in a figure that exists to be honest about roughly how much was
        // tapped, not to be audited.
        if lastRepSource == .manual, manualReps > 0 {
            manualReps -= 1
            lastRepSource = .auto
        }
        let counter = self.counter
        if counter.count > 0 {
            counter.forceDecrement()
            repsAtLastEvent = counter.count
            return .undo
        }
        if exercise != .pullup {
            exercise = exercise.previous
            stepBackInto(exercise)
            return .undo
        }
        guard rounds > 0 else { return .none }
        rounds -= 1
        // The round being stepped back into is the one whose banked counts were just filed away.
        bankedThisRound.removeAll()
        if let last = bankedRounds.popLast() { bankedThisRound = last }
        exercise = .squat
        stepBackInto(.squat)
        return .undo
    }

    /// Re-enters a movement already left, at one rep below what it actually scored.
    ///
    /// "One below its target" was the old answer, and it silently handed back reps that were never
    /// done to anyone who had skipped the movement — undo would have been a way to invent a score.
    /// What it scored is banked, so that is what it returns to.
    private func stepBackInto(_ movement: Exercise) {
        let banked = bankedThisRound.removeValue(forKey: movement) ?? movement.target
        counters[movement]!.setCount(max(banked - 1, 0))
        repsAtLastEvent = counters[movement]!.count
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
        barGuide = nil
        pullupDownSeen = false
        pullupExtendedElbow = .nan
        barTorso = .nan
        barContradictions = 0
        overheadFrames = 0
        barSettleSince = 0
        barSettleHands = nil
        diagnostics = FrameDiagnostics()
    }

    /// Scores a running-workout frame.
    ///
    /// `identityStable` comes from the camera layer's tracked ROI. A single-pose model cannot
    /// name people, but a lost ROI is the one reliable signal that this is no longer the same
    /// body; treating it as a pause prevents a new person from completing a half-started pull-up.
    @discardableResult
    public func onFrame(_ k: [Keypoint], now: Int64, identityStable: Bool = true) -> RepEvent {
        if setupInProgress {
            hint = "Finish setup first"
            blocked = false
            diagnostics = frameDiagnostics(k, identityStable: identityStable, rejection: hint)
            return .none
        }
        guard let torso = PoseGeometry.torsoLength(k), torso >= 1 else {
            bodyVisible = false
            hint = "Step into frame"
            blocked = true
            if exercise == .pullup { toleratePullupDropout() }
            diagnostics = frameDiagnostics(k, identityStable: identityStable, rejection: hint)
            return .none
        }
        bodyVisible = true

        if exercise == .pullup { return onPullupFrame(k, now: now, identityStable: identityStable) }

        let s = signalFor(k)
        guard !s.isNaN else {
            blocked = true
            diagnostics = frameDiagnostics(k, identityStable: identityStable, rejection: hint)
            return .none
        }

        if awaitingStart {
            // Deliberately not fed to the counter at all. Lying face down reads as a full 180
            // degrees of knee extension, and letting that into the learned band lifts the top of
            // it above anything the athlete can reach standing — which stops every squat
            // counting rather than just the phantom one.
            blocked = true
            hint = exercise.startCue
            takeUpPosition(k, s: s, now: now, counter: counter)
            diagnostics = frameDiagnostics(k, identityStable: identityStable,
                                           scoringConfidenceAdequate: true, rejection: hint)
            return .none
        }

        let counted = counter.update(s, now: now)
        if !counted {
            hint = phase == .down ? "Drive up" : "Go down"
            blocked = false
            diagnostics = frameDiagnostics(k, identityStable: identityStable,
                                           scoringConfidenceAdequate: true, rejection: hint)
            return .none
        }
        blocked = false
        lastRepSource = .auto
        diagnostics = frameDiagnostics(k, identityStable: identityStable,
                                       scoringConfidenceAdequate: true, rejection: nil)
        return settle()
    }

    /// Watches the athlete take up the movement, and opens the gate once they have.
    ///
    /// Two things have to be true together, and neither is sufficient alone. The posture has to
    /// be right — upright for squats, down for push-ups — which is what rules out arriving while
    /// still on the floor. And the joint that scores the movement has to have stopped opening,
    /// which is what rules out arriving halfway up. Getting off the floor satisfies the first for
    /// most of a second before it satisfies the second.
    private func takeUpPosition(_ k: [Keypoint], s: Float, now: Int64, counter: RepCounting) {
        guard inStartPosition(k) else {
            startPositionSince = 0
            startSmoothed = .nan
            startReference = .nan
            return
        }
        startSmoothed = startSmoothed.isNaN
            ? s
            : startSmoothed + Self.startSettleSmoothing * (s - startSmoothed)
        // Any further opening restarts the clock, however slowly it is happening.
        if startPositionSince == 0 || startSmoothed > startReference + Self.startSettleDegrees {
            startPositionSince = now
            startReference = startSmoothed
            return
        }
        guard now - startPositionSince >= Self.startPositionMs else { return }
        awaitingStart = false
        blocked = false
        // Arriving is not the top of a rep. Throwing away the climb that got here is the whole
        // point: otherwise standing up off the floor books one.
        counter.requireFreshDown()
    }

    /// Whether the athlete is standing, or down on the floor, as the current movement requires.
    ///
    /// Only the torso's direction is tested. Both a plank and a standing body have straight legs,
    /// so the knee angle that scores a squat cannot also decide whether the squat has begun.
    private func inStartPosition(_ k: [Keypoint]) -> Bool {
        switch exercise {
        // The bar, head and dead-hang gates already refuse anything that is not a pull-up.
        case .pullup: return true
        case .pushup: return !PoseGeometry.upright(k)
        case .squat: return PoseGeometry.standing(k)
        }
    }

    /// Advances to the next movement if the current one just hit its target.
    private func settle() -> RepEvent {
        if fixedExercise == nil && reps >= exercise.target { return advance() }
        repsAtLastEvent = reps
        return .rep
    }

    private func advance() -> RepEvent {
        // Read before the counter is cleared: this is the number the movement really reached, and
        // after a skip it is the only record that it was not the target.
        repsAtLastEvent = reps
        bankedThisRound[exercise] = reps
        counter.resetCount()
        let wasLast = exercise == .squat
        exercise = exercise.next
        counter.resetCount()
        // Whatever the athlete does to get from the last movement into this one must not score.
        awaitingStart = exercise.startsFromPosition
        startPositionSince = 0
        startSmoothed = .nan
        startReference = .nan
        if wasLast {
            rounds += 1
            bankedRounds.append(bankedThisRound)
            bankedThisRound.removeAll()
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
        barGuide = nil
        setupInProgress = true
        pullupDownSeen = false
        pullupExtendedElbow = .nan
        barTorso = .nan
        barContradictions = 0
        overheadFrames = 0
        barSettleSince = 0
        barSettleHands = nil
        diagnostics = FrameDiagnostics()
    }

    /// Watches a calibration rep and reports whether this camera placement can be worked with.
    ///
    /// The check is just the counter running before the clock does. Calibrating this way seeds
    /// the band from the athlete's own range, so the first rep of the workout is judged against a
    /// real measurement rather than the fallback floor — and a placement that cannot produce a
    /// believable range is caught here, instead of quietly undercounting for twenty minutes.
    @discardableResult
    public func onSetupFrame(_ k: [Keypoint], now: Int64, identityStable: Bool = true) -> Setup {
        let missing = PoseGeometry.missingJoints(k, exercise)
        if !missing.isEmpty {
            movingSince = 0
            if exercise == .pullup { toleratePullupDropout() }
            diagnostics = frameDiagnostics(k, identityStable: identityStable,
                                           rejection: "Missing " + missing.joined(separator: ", "))
            return Setup(stage: .framing, missing: missing, reps: counter.count,
                         range: counter.learnedRange, needed: counter.requiredRange)
        }
        if movingSince == 0 { movingSince = now }

        if exercise == .pullup {
            _ = onPullupFrame(k, now: now, identityStable: identityStable, settleWorkout: false)
        } else {
            let s = signalFor(k)
            if !s.isNaN { counter.update(s, now: now) }
            diagnostics = frameDiagnostics(k, identityStable: identityStable,
                                           scoringConfidenceAdequate: !s.isNaN,
                                           rejection: s.isNaN ? hint : nil)
        }

        let enough = counter.count >= Self.calibrationReps && counter.learnedRange >= counter.requiredRange
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
    public func finishSetup() {
        counter.resetCount()
        setupInProgress = false
        // Setup may have ended at the top of its second calibration rep. A new counted rep still
        // has to begin with a fresh dead hang below the reset line.
        pullupDownSeen = false
        if exercise == .pullup { counter.requireFreshDown() }
    }

    /// Configures a recorded clip's bar from normalised video coordinates.
    ///
    /// This intentionally lives on the production engine, rather than in test-only code, so the
    /// harness still uses the same bar gate as the app. The live camera leaves the bar automatic.
    public func configureManualBar(
        yNormalized: Float, xMinNormalized: Float, xMaxNormalized: Float,
        frameWidth: Int, frameHeight: Int
    ) {
        precondition(frameWidth > 0 && frameHeight > 0, "Frame dimensions must be positive")
        bar.configureManual(y: yNormalized * Float(frameHeight),
                            xMin: xMinNormalized * Float(frameWidth),
                            xMax: xMaxNormalized * Float(frameWidth))
        pullupDownSeen = false
        overheadFrames = 0
        barSettleSince = 0
        barSettleHands = nil
        counters[.pullup]!.requireFreshDown()
    }

    private func signalFor(_ k: [Keypoint]) -> Float {
        switch exercise {
        // Pull-ups are handled by onPullupFrame(), which owns the bar/head/reset gates.
        case .pullup: return .nan
        case .pushup: return pushupSignal(k)
        case .squat: return squatSignal(k)
        }
    }

    // MARK: - signals

    /// Mean elbow angle, negated: about -170 at a dead hang, about -60 with the chin over the bar.
    ///
    /// An earlier version measured how far the shoulders rose toward the hands, divided by torso
    /// length. That undercounted badly for two compounding reasons. Dividing by torso length put
    /// the hip keypoints in the denominator, and hips are the *least* reliable joints on someone
    /// hanging with their knees bent behind them — a hip estimate drifting low inflates the
    /// divisor and shrinks the signal until it no longer reaches the arming threshold. Worse, the
    /// posture guard rejected any frame where the shoulders rose above the hands, which is
    /// exactly what happens at the top of a strong pull-up: the better the rep, the more reliably
    /// it was thrown away.
    ///
    /// An angle needs no normalisation, so nothing about the athlete's build, their distance from
    /// the camera, or where the model thinks their hips are can move the thresholds.
    private struct PullupSample {
        let signal: Float
        let deadHangBelowReset: Bool
        let headAboveBar: Bool
        let barGateOpen: Bool
    }

    /// Scores a pull-up only after the physical gates are true. `RepCounter` remains the only
    /// component which can increment the score; this method only decides whether its input is
    /// meaningful for the current tracked body.
    private func onPullupFrame(
        _ k: [Keypoint], now: Int64, identityStable: Bool, settleWorkout: Bool = true
    ) -> RepEvent {
        guard identityStable else {
            hint = "Tracking…"
            blocked = true
            toleratePullupDropout()
            diagnostics = frameDiagnostics(k, identityStable: false, rejection: hint)
            return .none
        }

        guard let sample = pullupSample(k, now: now) else {
            blocked = true
            toleratePullupDropout()
            diagnostics = frameDiagnostics(k, identityStable: true, rejection: hint)
            return .none
        }

        pullupDropoutFrames = 0

        let counter = counters[.pullup]!

        // Every readable on-bar frame is observed, so the band learns the athlete's real swing
        // even while the gates are shut. Only a frame that clears all of them may book a rep,
        // which is what stops an elbow-only partial from scoring. Withholding the samples
        // instead — the previous approach — left the counter judging reps against a band built
        // from a fraction of the movement.
        let mayCount = !sample.deadHangBelowReset && sample.headAboveBar && pullupDownSeen
        let counted = counter.update(sample.signal, now: now, mayCount: mayCount)

        if sample.deadHangBelowReset {
            // Observing here makes RepCounter's .down phase agree with the physical reset.
            if counter.phase == .down { pullupDownSeen = true }
            // Hanging at the bottom is where a pull-up starts, not a fault worth announcing. But
            // the athlete is told "Ready" off the back of this, and that has to mean the next rep
            // will actually score — which a hang that has not yet armed will not.
            blocked = !pullupDownSeen
            diagnostics = frameDiagnostics(k, identityStable: true, scoringConfidenceAdequate: true,
                                           barGateOpen: sample.barGateOpen,
                                           headAboveBar: sample.headAboveBar)
            return .none
        }

        if !mayCount {
            blocked = true
            if pullupDownSeen {
                hint = "Get your head over the bar"
            } else if requiresDeadHang {
                hint = "Return to a dead hang"
            } else {
                hint = "Lower all the way down"
            }
            diagnostics = frameDiagnostics(k, identityStable: true, scoringConfidenceAdequate: true,
                                           barGateOpen: sample.barGateOpen,
                                           headAboveBar: sample.headAboveBar, rejection: hint)
            return .none
        }

        diagnostics = frameDiagnostics(k, identityStable: true, scoringConfidenceAdequate: true,
                                       barGateOpen: sample.barGateOpen,
                                       headAboveBar: sample.headAboveBar,
                                       rejection: counted ? nil : "Drive up")
        blocked = false
        guard counted else {
            hint = "Drive up"
            return .none
        }

        // A second count cannot inherit this rep: a fresh reset below the bar is required.
        pullupDownSeen = false
        lastRepSource = .auto
        return settleWorkout ? settle() : .none
    }

    /// Validates a pull-up pose without mutating the counter.
    private func pullupSample(_ k: [Keypoint], now: Int64) -> PullupSample? {
        let leftWrist = k[KP.leftWrist]
        let rightWrist = k[KP.rightWrist]
        guard PoseGeometry.ok(leftWrist), PoseGeometry.ok(rightWrist) else {
            hint = "Show both hands"
            return nil
        }
        guard PoseGeometry.hangingFromBar(k) else {
            hint = "Hang from the bar"
            return nil
        }
        // Hands overhead is not enough to call this a hang: an inverted row also puts the wrists
        // above the hips, and every remaining gate then passes. Only the torso's direction
        // separates the families. Measured as (hip.y - shoulder.y) / torso on a progression clip:
        // vertical pulls 0.92–1.00, low/mid rows 0.33–0.86, a HIGH row 0.86–0.98 — so the row
        // family separates, but a steeply inclined high row sits inside the range real hangs
        // occupy and is left unseparated rather than rejected by an invented threshold.
        //
        // Returning nil routes the frame through toleratePullupDropout(), so a brief wobble
        // mid-rep is absorbed by the existing dropout window while a sustained row never arms.
        guard PoseGeometry.upright(k) else {
            hint = "Hang vertically from the bar"
            return nil
        }
        let hands = Keypoint(x: (leftWrist.x + rightWrist.x) / 2, y: (leftWrist.y + rightWrist.y) / 2,
                             score: min(leftWrist.score, rightWrist.score))
        guard let torso = PoseGeometry.torsoLength(k) else {
            hint = "Step into frame"
            return nil
        }
        let elbow = PoseGeometry.bilateralAngle(k, KP.leftShoulder, KP.leftElbow, KP.leftWrist,
                                                KP.rightShoulder, KP.rightElbow, KP.rightWrist)
        guard !elbow.isNaN else {
            hint = "Arms out of frame"
            return nil
        }
        pullupExtendedElbow = pullupExtendedElbow.isNaN ? elbow : max(pullupExtendedElbow, elbow)
        let deadHang = deadHangDegrees()

        // Refinement requires already passing the gate, so a bar learned in the wrong place can
        // otherwise lock the athlete out for the rest of the workout — which is exactly what a
        // clip mis-established during a walk-up did on Android, rejecting 2377 of 2888 frames. A
        // sustained dead hang refused at a very different body scale is evidence that the
        // estimate, not the athlete, is in the wrong place.
        if bar.established, elbow >= deadHang, !bar.holds(left: leftWrist, right: rightWrist, torso: torso) {
            let ratio: Float = (barTorso.isNaN || barTorso <= 0 || torso <= 0)
                ? 1 : max(torso / barTorso, barTorso / torso)
            if ratio > Self.barScaleChange {
                barContradictions += 1
                if barContradictions > Self.maxBarContradictions {
                    bar.reset()
                    barGuide = nil
                    barTorso = .nan
                    barContradictions = 0
        barSettleSince = 0
                    barSettleHands = nil
                }
            }
        } else {
            barContradictions = 0
        }

        // A straight-armed hang establishes an unknown bar. Once known, only observations that
        // are already on that bar may refine it; otherwise someone stepping off the bar could
        // slowly drag the learned line down to the floor.
        //
        // Establishing one from scratch additionally needs the hands *overhead*. Setting up a
        // resistance band means standing there holding it at chest height with straight arms,
        // which satisfies every other test here — hands above the hips, elbows extended — and
        // taught the bar at the athlete's chest, hundreds of pixels below the real one. Every
        // later rep was then refused with "Get on the bar" with no way back, because refinement
        // requires already passing the gate. Strict pull-ups have no such phase, which is why
        // only band footage found it.
        let overhead = PoseGeometry.handsOverhead(k, hands: hands)
        overheadFrames = overhead ? overheadFrames + 1 : 0
        // Seeing the nose below the hands is evidence and is acted on at once; permission inferred
        // from a nose that could *not* be seen is not, and has to persist.
        let learnable = overhead && (PoseGeometry.ok(k[KP.nose]) || overheadFrames >= Self.overheadHoldFrames)
        let mayLearn = bar.established
            ? bar.holds(left: leftWrist, right: rightWrist, torso: torso)
            : learnable
        if elbow >= deadHang, mayLearn {
            let wasEstablished = bar.established
            let half = gripHalfWidth(k) ?? 0
            bar.observeHang(handsX: hands.x, handsY: hands.y, halfGrip: half)
            if !wasEstablished { barTorso = torso }
        }
        if bar.established {
        barSettleSince = 0
            barSettleHands = nil
        } else if overhead {
            settleBar(hands, halfGrip: gripHalfWidth(k) ?? 0, torso: torso, now: now)
        } else {
            // Not a hang, so the stillness of holding a band must not accumulate toward one.
        barSettleSince = 0
            barSettleHands = nil
        }
        let onBar = bar.holds(left: leftWrist, right: rightWrist, torso: torso)
        barGuide = bar.bounds(torso: torso).map {
            BarGuide(zone: $0, resetY: $0.lineY + Self.headResetTorsos * torso, gateOpen: onBar)
        }
        guard onBar else {
            hint = "Get on the bar"
            return nil
        }

        let nose = k[KP.nose]
        guard let barY = bar.lineY, PoseGeometry.ok(nose) else {
            hint = PoseGeometry.ok(nose) ? "Hang from the bar" : "Show your head"
            return nil
        }
        return PullupSample(
            signal: -elbow,
            deadHangBelowReset: (!requiresDeadHang || elbow >= deadHang)
                && nose.y >= barY + Self.headResetTorsos * torso,
            headAboveBar: nose.y < barY,
            barGateOpen: true
        )
    }

    /// Whether the bottom of a rep has to be a straight-armed hang.
    ///
    /// It does for a strict pull-up: that is the movement. It cannot for a band-assisted one —
    /// the band takes enough weight that the arms may never straighten, so requiring it means the
    /// reset never arms and the athlete scores zero all session with the counter working
    /// perfectly behind a gate they cannot open.
    ///
    /// What remains for the assisted variant is the head dropping back below the reset line, and
    /// that is the conjunct worth keeping: it is a torso-scaled offset rather than an angle, so
    /// the camera's viewpoint cannot flatten it, and a head a quarter-torso below the bar is at
    /// the bottom of the movement whatever the elbows are doing. The head still has to clear the
    /// bar to score, and `RepCounter` still requires the athlete's full learned travel, so a
    /// relaxed bottom buys a shallower rep nothing.
    private var requiresDeadHang: Bool { profile.pull == .strictPullUp }

    /// Forget a partial pull-up until a fresh on-bar dead hang is observed.
    ///
    /// This is the hard reset, for when the athlete has genuinely left the bar. A frame that is
    /// merely unreadable goes through `toleratePullupDropout` instead.
    private func invalidatePullupCycle() {
        pullupDownSeen = false
        pullupDropoutFrames = 0
        counters[.pullup]!.requireFreshDown()
    }

    /// Absorbs a frame the pull-up gates could not read.
    ///
    /// A cycle already in flight survives a short run of them; a sustained run is
    /// indistinguishable from having left the bar, so it ends the cycle.
    private func toleratePullupDropout() {
        guard pullupDownSeen else {
            invalidatePullupCycle()
            return
        }
        pullupDropoutFrames += 1
        if pullupDropoutFrames > Self.maxDropoutFrames { invalidatePullupCycle() }
    }

    /// The angle at which the arms read as straight for *this* camera placement.
    ///
    /// Never stricter than `strictDeadHangDegrees`; a foreshortened view relaxes it to whatever
    /// full extension actually projects as.
    private func deadHangDegrees() -> Float {
        guard !pullupExtendedElbow.isNaN else { return Self.strictDeadHangDegrees }
        return min(Self.strictDeadHangDegrees,
                   max(Self.deadHangFloorDegrees, pullupExtendedElbow - Self.deadHangSlackDegrees))
    }

    /// Locates the bar from hands simply held still overhead, when no dead hang has managed to.
    ///
    /// Strictly a fallback. A straight-armed hang still establishes the bar on the frame it
    /// happens, so nothing about a strict pull-up reaches this at all. It exists because the
    /// dead-hang route can never fire for some athletes: an elbow that does not reach
    /// `deadHangFloorDegrees` — limited extension, or a band taking enough weight that the arms
    /// never straighten — leaves the bar unknown, and an unknown bar has no `BarZone.lineY`, so
    /// every pull-up frame is refused before the gates are even consulted. The whole workout then
    /// scores zero under "Hang from the bar". Not being able to *find* the bar is not a movement
    /// standard, it is a lockout: the head and bar gates still have to be satisfied afterwards,
    /// and on the strict variant so does the dead hang.
    ///
    /// Stillness is the evidence rather than the elbow, because stillness is what separates
    /// hanging from the walk-up that previously taught a bar in the wrong place. The same
    /// argument as `takeUpPosition`: a dwell on a position that has stopped changing, rather than
    /// a threshold on an angle that the camera's viewpoint can flatten.
    private func settleBar(_ hands: Keypoint, halfGrip: Float, torso: Float, now: Int64) {
        // Tested as the Kotlin tests it, `distance > limit`, not `distance <= limit` negated: the
        // two read the same for any distance but NaN, and a NaN must not be taken for drift.
        let drifted: Bool
        if let reference = barSettleHands {
            drifted = PoseGeometry.hypot32(hands.x - reference.x, hands.y - reference.y)
                > Self.barSettleDriftTorsos * torso
        } else {
            drifted = true
        }
        if drifted {
            barSettleSince = now
            barSettleHands = hands
            return
        }
        guard now - barSettleSince >= Self.barSettleMs else { return }
        bar.observeHang(handsX: hands.x, handsY: hands.y, halfGrip: halfGrip)
        barTorso = torso
        barSettleSince = 0
        barSettleHands = nil
    }

    /// Half the distance between the hands, for the bar's horizontal span.
    private func gripHalfWidth(_ k: [Keypoint]) -> Float? {
        let l = k[KP.leftWrist], r = k[KP.rightWrist]
        guard PoseGeometry.ok(l), PoseGeometry.ok(r) else { return nil }
        return abs(l.x - r.x) / 2
    }

    /// Mean elbow angle in degrees; small at the bottom of a push-up, ~180 at lockout.
    private func pushupSignal(_ k: [Keypoint]) -> Float {
        // Guard against a pull-up being scored as a push-up, using the same overhead test.
        if PoseGeometry.hangingFromBar(k) {
            hint = "Get on the floor"
            return .nan
        }
        return PoseGeometry.bilateralAngle(k,
                              KP.leftShoulder, KP.leftElbow, KP.leftWrist,
                              KP.rightShoulder, KP.rightElbow, KP.rightWrist)
    }

    /// Mean knee angle in degrees; small in the hole, ~180 standing.
    private func squatSignal(_ k: [Keypoint]) -> Float {
        let a = PoseGeometry.bilateralAngle(k,
                               KP.leftHip, KP.leftKnee, KP.leftAnkle,
                               KP.rightHip, KP.rightKnee, KP.rightAnkle)
        if a.isNaN { hint = "Show your legs to the camera" }
        return a
    }

    private func frameDiagnostics(
        _ k: [Keypoint], identityStable: Bool, scoringConfidenceAdequate: Bool = false,
        barGateOpen: Bool = false, headAboveBar: Bool = false, rejection: String? = nil
    ) -> FrameDiagnostics {
        FrameDiagnostics(
            minimumConfidence: k.map(\.score).min() ?? 0,
            scoringConfidenceAdequate: scoringConfidenceAdequate,
            poseLegible: poseLegible(k),
            identityStable: identityStable,
            barGateOpen: barGateOpen,
            headAboveBar: headAboveBar,
            deadHangSinceLastRep: pullupDownSeen,
            resetBelowBarSeen: pullupDownSeen,
            rejectionReason: rejection
        )
    }

    /// Whether every joint the current movement scores from was confidently seen.
    ///
    /// The joint lists are the ones each signal actually consults: pull-ups and push-ups both run
    /// on the shoulder-elbow-wrist chain with the hips supplying torso scale, and squats on the
    /// hip-knee-ankle chain with the shoulders doing the same. Asking for *all* of them, rather
    /// than enough of them to compute an angle, is what makes this fall before the score does.
    ///
    /// Wrists are the joint that matters most here and the one that goes first: darkening a clip
    /// until it stopped counting left "Show both hands" as the dominant refusal every time, which
    /// is why pull-ups fail so much sooner than the other two movements.
    private func poseLegible(_ k: [Keypoint]) -> Bool {
        let joints: [Int]
        switch exercise {
        case .squat:
            joints = [KP.leftShoulder, KP.rightShoulder, KP.leftHip, KP.rightHip,
                      KP.leftKnee, KP.rightKnee, KP.leftAnkle, KP.rightAnkle]
        default:
            joints = [KP.leftShoulder, KP.rightShoulder, KP.leftElbow, KP.rightElbow,
                      KP.leftWrist, KP.rightWrist, KP.leftHip, KP.rightHip]
        }
        return joints.allSatisfy { PoseGeometry.ok(k[$0]) }
    }
}
