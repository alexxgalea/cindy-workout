import Foundation

/// Every position hint the voice can be asked to say, keyed by the engine's own English text.
///
/// The engine words its hints in English and keeps doing so. `WorkoutEngine` and `TrackingHealth`
/// are mirrored by the Python port, which compares hint text frame for frame, so translating at the
/// source would break that check for the sake of a voice. The translation happens at the last
/// moment instead, in each `Phrasebook`, and this is what it is keyed by.
///
/// Kept in step with the engine by `VoiceHintsTests`, which reads the engine's sources and fails on
/// any string in them that is neither listed here nor known not to be spoken. So a hint added to
/// the engine cannot reach the voice untranslated: this enum gains a case, and every phrasebook's
/// exhaustive `switch` over it stops compiling until it has words for it.
public enum Hint: CaseIterable, Sendable {
    case stepIntoFrame
    case finishSetupFirst
    case tracking

    // Pull-ups.
    case hangFromBar
    case hangVertically
    case getOnBar
    case showBothHands
    case showYourHead
    case armsOutOfFrame
    case getHeadOverBar
    case returnToDeadHang
    case lowerAllTheWay

    // Push-ups and squats, which start from a position the athlete has to assume first.
    case getSetOnFloor
    case getOnFloor
    case standUpToStart
    case showYourLegs

    // Mid-rep, for a movement that is being counted.
    case driveUp
    case goDown

    // From `TrackingHealth`, when the camera itself is the problem.
    case losingYou
    case tooDark
    case cantSeeYou

    public var english: String {
        switch self {
        case .stepIntoFrame: return "Step into frame"
        case .finishSetupFirst: return "Finish setup first"
        case .tracking: return "Tracking…"
        case .hangFromBar: return "Hang from the bar"
        case .hangVertically: return "Hang vertically from the bar"
        case .getOnBar: return "Get on the bar"
        case .showBothHands: return "Show both hands"
        case .showYourHead: return "Show your head"
        case .armsOutOfFrame: return "Arms out of frame"
        case .getHeadOverBar: return "Get your head over the bar"
        case .returnToDeadHang: return "Return to a dead hang"
        case .lowerAllTheWay: return "Lower all the way down"
        case .getSetOnFloor: return "Get set on the floor"
        case .getOnFloor: return "Get on the floor"
        case .standUpToStart: return "Stand up to start"
        case .showYourLegs: return "Show your legs to the camera"
        case .driveUp: return "Drive up"
        case .goDown: return "Go down"
        case .losingYou: return "Losing you — more light helps"
        case .tooDark: return "Too dark to count — tap +1"
        case .cantSeeYou: return "Can't see you — tap +1"
        }
    }

    private static let byEnglish: [String: Hint] = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0.english, $0) })

    /// The hint the engine's `english` text stands for, or `nil` for text nobody catalogued.
    public static func of(_ english: String) -> Hint? { byEnglish[english] }
}
