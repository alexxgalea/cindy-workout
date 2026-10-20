import Foundation

/// The mark on the shutter, which is the run control and nothing else. The word it used to carry is
/// gone: the states it takes are the ones a player already draws, and carrying the longest of five
/// labels is what made the control wide.
public enum ShutterMark: Equatable, Sendable { case play, pause, again }

/// What holds the left of the action row.
public enum LeftSlot: Equatable, Sendable { case flip, end }

/// The controls of the camera screen, and what each is for at this moment. Port of `renderControls`,
/// `primary` and the state changes of `toggleRun` in `MainActivity.kt`.
///
/// The left slot is FLIP before the clock starts and END once it is running. Only one of the two is
/// ever present: they share a position, and showing both crowded the band for no gain, since
/// flipping the camera is not something anyone does mid-Cindy while getting out of a workout is.
///
/// The shutter is the run control and nothing else. It goes inert during the setup check, because
/// there is no workout yet to run or to pause; SKIP is the way out of the check.
///
/// The rest follow one rule: a control keeps its place and dims when it has nothing to act on.
/// Hiding them instead was tried and was worse. A band that empties out does not read as tidy, it
/// reads as a band that has lost its buttons, and you cannot learn where a control lives if it is
/// only there half the time. The left slot is not an exception: it never empties, it changes hands.
public struct HudControls: Equatable, Sendable {
    public let leftSlot: LeftSlot
    /// The editors act on a count, and the count only moves while the clock is running, so a paused
    /// workout dims them too, rather than offering a lit button that quietly does nothing.
    public let editorsEnabled: Bool
    public let shutter: ShutterMark
    public let shutterEnabled: Bool
    public let shutterLabel: String
    /// There is a movement to leave during the check and during the workout, and none before the
    /// clock starts or after it stops.
    public let skipEnabled: Bool
    public let skipLabel: String

    /// How far a control with nothing to act on is dimmed.
    public static let dimmed: Double = 0.3
    public static let flipLabel = "Switch camera"
    public static let endLabel = "End the workout"
    public static let undoLabel = "Take back a rep"
    public static let addLabel = "Add a rep"
    public static let menuLabel = "Menu: records, movements, music, body weight and help"

    public static func of(_ state: WorkoutState) -> HudControls {
        let live = state == .running || state == .paused
        let mark: ShutterMark
        let label: String
        switch state {
        case .idle: mark = .play; label = "Start the workout"
        case .setup: mark = .play; label = "Start — available once the setup check finishes"
        case .running: mark = .pause; label = "Pause"
        case .paused: mark = .play; label = "Resume"
        case .finished: mark = .again; label = "Start again"
        }
        return HudControls(
            leftSlot: live ? .end : .flip,
            editorsEnabled: state == .running,
            shutter: mark,
            shutterEnabled: state != .setup,
            shutterLabel: label,
            skipEnabled: state == .setup || live,
            skipLabel: state == .setup ? "Skip the setup check" : "Skip to the next movement")
    }
}

/// What a screen reader is given for the camera screen's digits. Screen-reader text is English like
/// the rest of the screen; only the voice has languages.
public enum HudSpeech {
    public static let settingUp = "Setting up"

    public static func clock(remainingMs: Int64) -> String {
        "\(PhrasebookEn().duration(remainingMs)) remaining"
    }

    public static func reps(_ reps: Int, of target: Int, movement: String) -> String {
        "\(reps) of \(target) \(movement)"
    }

    public static func setup(reps: Int, of target: Int) -> String {
        "\(reps) of \(target) calibration reps"
    }

    public static func round(_ number: Int) -> String { "Round \(number)" }
}

/// How REC is drawn: red while a count runs or a film rolls, lit only while it films.
public struct RecLook: Equatable, Sendable {
    public let alert: Bool
    public let lit: Bool

    public init(alert: Bool, lit: Bool) {
        self.alert = alert
        self.lit = lit
    }
}

extension FilmFlow {
    /// Red while filming, red but unlit while the countdown runs: the count itself is on the
    /// picture, so the icon only has to say which of the three states REC is in.
    public static func look(for state: FilmState) -> RecLook {
        RecLook(alert: state != .idle, lit: state == .filming)
    }
}
