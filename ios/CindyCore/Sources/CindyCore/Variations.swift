import Foundation

/// The movements the athlete actually performed, and what the app is entitled to call them.
///
/// Cindy prescribes a strict pull-up, a standard push-up and a full-depth air squat. Plenty of
/// people cannot do all three, and an app that only counts those three is an app that tells them
/// to come back when they are fitter. So the movement is a choice made before the clock starts,
/// and the choice travels with the result: into the summary, the history line and the record
/// board.
///
/// The rule the whole file exists to enforce is that a modified movement is *reported as* the
/// modified movement. Not silently counted as the strict one, and not sneered at either — a
/// band-assisted pull-up is a different prescription, not a worse athlete.
///
/// Mirrors `Variations.kt` on Android. There is no shared wire format between the two — each
/// platform persists its own choice locally — so this only needs to agree on behaviour, not on
/// bytes.

/// Whether the camera can be trusted to score a variation, or whether the athlete taps it in.
public enum Tracking: Sendable {
    /// Validated against fixtures: the engine counts it.
    case auto
    /// Counted with the "+1" button.
    ///
    /// Not a lesser option and not a placeholder — for several of these the pose alone genuinely
    /// does not carry the information, and a confident wrong count is worse than an honest tap.
    case manual
}

/// What happened on the bar.
public enum PullVariant: String, CaseIterable, Sendable {
    case strictPullUp = "STRICT_PULL_UP"
    case bandAssistedPullUp = "BAND_ASSISTED_PULL_UP"
    case footAssistedPullUp = "FOOT_ASSISTED_PULL_UP"
    case negativePullUp = "NEGATIVE_PULL_UP"

    public var label: String {
        switch self {
        case .strictPullUp: return "Strict pull-up"
        case .bandAssistedPullUp: return "Band-assisted"
        case .footAssistedPullUp: return "Foot-assisted"
        case .negativePullUp: return "Negatives"
        }
    }

    public var plural: String {
        switch self {
        case .strictPullUp: return "strict pull-ups"
        case .bandAssistedPullUp: return "band-assisted pull-ups"
        case .footAssistedPullUp: return "foot-assisted pull-ups"
        case .negativePullUp: return "negative pull-ups"
        }
    }

    public var tracking: Tracking {
        switch self {
        case .strictPullUp, .bandAssistedPullUp: return .auto
        case .footAssistedPullUp, .negativePullUp: return .manual
        }
    }

    public var setupGuide: String {
        switch self {
        case .strictPullUp:
            return "Hang with straight arms, then pull until your head clears the bar."
        case .bandAssistedPullUp:
            return "Set the band, then pull until your head clears the bar and lower all the way back down."
        case .footAssistedPullUp:
            // "Hands above hips" is what separates a pull-up from a push-up in the pose. On a
            // low bar with the feet down, the hips ride up level with the hands and that test
            // stops meaning anything in either direction, so it cannot simply be loosened.
            return "Set your feet on the floor or a box. Tap +1 for each rep."
        case .negativePullUp:
            // A negative has no return, so there is no oscillation to count: RepCounter books a
            // rep at the top of a climb away from a trough, and a descent never presents one.
            return "Start at the top and lower yourself slowly. Tap +1 for each rep."
        }
    }
}

/// What happened on the floor.
public enum PushVariant: String, CaseIterable, Sendable {
    case standardPushUp = "STANDARD_PUSH_UP"
    case kneePushUp = "KNEE_PUSH_UP"
    case inclinePushUp = "INCLINE_PUSH_UP"

    public var label: String {
        switch self {
        case .standardPushUp: return "Standard"
        case .kneePushUp: return "From knees"
        case .inclinePushUp: return "Incline"
        }
    }

    public var plural: String {
        switch self {
        case .standardPushUp: return "standard push-ups"
        case .kneePushUp: return "knee push-ups"
        case .inclinePushUp: return "incline push-ups"
        }
    }

    public var tracking: Tracking {
        switch self {
        case .standardPushUp, .kneePushUp: return .auto
        case .inclinePushUp: return .manual
        }
    }

    public var setupGuide: String {
        switch self {
        case .standardPushUp:
            return "Hands under your shoulders, body in a line, chest to the floor."
        case .kneePushUp:
            // Counted by exactly the same code as a standard push-up: the signal is the elbow
            // angle and the gate in front of it asks only which way the torso points. Naming it
            // changes nothing about the counting and everything about what history says happened.
            return "Hands under your shoulders, knees on the floor, chest toward the floor."
        case .inclinePushUp:
            // A shallow incline reads as a push-up, but a steep one reads as standing upright and
            // the start gate refuses to open. Where the boundary falls depends on the bench, so
            // the honest answer is to tap it rather than count it sometimes.
            return "Hands on a bench, box or wall. Tap +1 for each rep."
        }
    }
}

/// What happened on the legs.
public enum SquatVariant: String, CaseIterable, Sendable {
    case airSquat = "AIR_SQUAT"
    case boxSquat = "BOX_SQUAT"
    case supportedSquat = "SUPPORTED_SQUAT"

    public var label: String {
        switch self {
        case .airSquat: return "Air squat"
        case .boxSquat: return "To a box"
        case .supportedSquat: return "Supported"
        }
    }

    public var plural: String {
        switch self {
        case .airSquat: return "air squats"
        case .boxSquat: return "box squats"
        case .supportedSquat: return "supported squats"
        }
    }

    public var tracking: Tracking {
        switch self {
        case .airSquat, .boxSquat: return .auto
        case .supportedSquat: return .manual
        }
    }

    public var setupGuide: String {
        switch self {
        case .airSquat:
            return "Stand tall, sit down to depth, stand all the way back up."
        case .boxSquat:
            // RepCounter already learns the range the athlete actually produces and judges reps
            // against that, so a box caps the descent and the band settles around it — no
            // separate calibration step is needed.
            return "Set a box or chair behind you. Sit to it and stand all the way back up."
        case .supportedSquat:
            // Holding a rail puts the hands somewhere the squat gates do not expect, and the
            // support often occludes a leg.
            return "Hold a rail or door frame for balance. Tap +1 for each rep."
        }
    }
}

/// Standard Cindy, or a Cindy with at least one movement changed.
public enum CindyMode: Sendable {
    case standard
    case adaptive

    public var label: String {
        switch self {
        case .standard: return "Cindy"
        case .adaptive: return "Adaptive Cindy"
        }
    }
}

/// The three choices, together.
///
/// `mode` is derived rather than stored, so a profile can never disagree with its own label.
public struct CindyProfile: Equatable, Sendable {
    public var pull: PullVariant
    public var push: PushVariant
    public var squat: SquatVariant

    public init(
        pull: PullVariant = .strictPullUp,
        push: PushVariant = .standardPushUp,
        squat: SquatVariant = .airSquat
    ) {
        self.pull = pull
        self.push = push
        self.squat = squat
    }

    public static let standard = CindyProfile()

    public var mode: CindyMode { self == Self.standard ? .standard : .adaptive }

    public var isStandard: Bool { mode == .standard }

    /// True when every chosen movement is one the camera is trusted to score.
    public var fullyAutomatic: Bool {
        pull.tracking == .auto && push.tracking == .auto && squat.tracking == .auto
    }

    /// The movements this profile expects the athlete to tap in rather than be counted.
    public var manualMovements: [Exercise] {
        var result: [Exercise] = []
        if pull.tracking == .manual { result.append(.pullup) }
        if push.tracking == .manual { result.append(.pushup) }
        if squat.tracking == .manual { result.append(.squat) }
        return result
    }

    public func tracking(for exercise: Exercise) -> Tracking {
        switch exercise {
        case .pullup: return pull.tracking
        case .pushup: return push.tracking
        case .squat: return squat.tracking
        }
    }

    /// "Band-assisted pull-ups · knee push-ups · air squats", naming only what was changed.
    public func changedMovements() -> String {
        var parts: [String] = []
        if pull != Self.standard.pull { parts.append(pull.plural) }
        if push != Self.standard.push { parts.append(push.plural) }
        if squat != Self.standard.squat { parts.append(squat.plural) }
        return parts.joined(separator: " · ")
    }

    /// The full line for a history row: "Adaptive Cindy · knee push-ups".
    public func label() -> String {
        isStandard ? mode.label : "\(mode.label) · \(changedMovements())"
    }
}

/// Persisting the athlete's choice between sessions, via `UserDefaults`.
public enum Variations {

    public static func encode(_ profile: CindyProfile) -> String {
        [profile.pull.rawValue, profile.push.rawValue, profile.squat.rawValue].joined(separator: "|")
    }

    /// Decodes a saved choice, falling back to the standard movement for anything unrecognised.
    ///
    /// Deliberately *unlike* a recorded attempt, where an unknown movement has to stay unknown
    /// rather than be relabelled. This is a preference for a workout that has not happened yet:
    /// nothing is being claimed about the past, and the worst a wrong default does is make the
    /// athlete open the picker they were already heading for.
    public static func decode(_ raw: String?) -> CindyProfile {
        let parts = raw?.components(separatedBy: "|") ?? []
        guard parts.count == 3 else { return .standard }
        return CindyProfile(
            pull: PullVariant(rawValue: parts[0]) ?? CindyProfile.standard.pull,
            push: PushVariant(rawValue: parts[1]) ?? CindyProfile.standard.push,
            squat: SquatVariant(rawValue: parts[2]) ?? CindyProfile.standard.squat
        )
    }
}
