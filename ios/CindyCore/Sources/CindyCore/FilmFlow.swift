import Foundation

/// REC in its three states: counting down, filming, and neither.
public enum FilmState: Equatable, Sendable {
    case idle
    /// A tap bought a countdown, not a recording.
    case counting
    case filming
}

/// Whether the app may add a film to Photos. Add-only access is all it ever asks for: it needs to
/// put a film there and has no business reading what else is.
public enum FilmAccess: Equatable, Sendable {
    /// Not asked yet.
    case undecided
    /// Allowed, in full or limited: both let a film be added.
    case allowed
    /// Refused, or kept from the athlete by a restriction.
    case refused
}

/// What a tap on REC does.
public enum FilmStep: Equatable, Sendable {
    /// Photos has not been asked. Ask, then tap again with the answer.
    case askAccess
    /// Nothing to do but say so.
    case say(toast: String)
    /// Count down, and say it too: the countdown is there so the athlete can walk to the bar, which
    /// is turning away from the only screen that says filming is about to begin.
    case countdown(seconds: Int, voice: VoiceLine)
    /// The count was called off.
    case cancelCountdown(toast: String)
    /// Filming stops, and what it caught is saved.
    case stopFilming
}

/// What the screen does once the countdown has run out and the camera has been asked to roll.
public struct FilmStart: Equatable, Sendable {
    public let toast: String?
    public let voice: VoiceLine

    public init(toast: String?, voice: VoiceLine) {
        self.toast = toast
        self.voice = voice
    }
}

/// What the screen does once filming has ended.
public struct FilmEnd: Equatable, Sendable {
    public let toast: String
    public let voice: VoiceLine?

    public init(toast: String, voice: VoiceLine?) {
        self.toast = toast
        self.voice = voice
    }
}

/// The decisions behind REC. Port of `MainActivity`'s `toggleRecording`, `beginRecording` and the
/// finish callback, with Photos in place of `Movies/Cindy`.
///
/// Only decisions: the camera, the countdown's clock, the speech and the toasts are the screen's.
public enum FilmFlow {

    /// Long enough to put the phone down and turn round; short enough not to be a wait.
    public static let countdownSeconds = Countdown.defaultSeconds

    /// How long the vibration at the far side of the countdown lasts.
    public static let startBuzzMs = 40

    public static let cancelledText = "Recording cancelled"
    public static let unavailableText = "Recording is not available on this camera"
    public static let couldNotStartText = "Could not start recording"
    public static let failedText = "Recording failed"
    public static let savedText = "Saved to Photos"
    public static let refusedText = "Allow Cindy to add to Photos in Settings to film your workout"

    /// What a tap does. The order is the Android screen's: a count in progress is called off, a
    /// film in progress is stopped, a camera that cannot film says so, and only then does a tap buy a
    /// countdown, once Photos has agreed to keep what comes of it.
    ///
    /// Photos is asked before the count and not after the film, because a film that cannot be saved
    /// is a workout filmed for nothing.
    public static func tap(state: FilmState, canFilm: Bool, access: FilmAccess) -> FilmStep {
        switch state {
        case .counting: return .cancelCountdown(toast: cancelledText)
        case .filming: return .stopFilming
        case .idle:
            guard canFilm else { return .say(toast: unavailableText) }
            switch access {
            case .undecided: return .askAccess
            case .refused: return .say(toast: refusedText)
            case .allowed: return .countdown(seconds: countdownSeconds, voice: .recordingSoon(seconds: countdownSeconds))
            }
        }
    }

    /// The far side of the countdown, once the camera has been asked to roll.
    public static func started(_ ok: Bool) -> FilmStart {
        ok ? FilmStart(toast: nil, voice: .recordingStarted)
           : FilmStart(toast: couldNotStartText, voice: .recordingFailed)
    }

    /// Filming ended, and `saved` is whether the film is in Photos. A failure is reported later than
    /// the start and to someone facing the bar rather than the screen, so the toast alone would
    /// leave them believing they are being filmed: it is said as well.
    public static func ended(saved: Bool) -> FilmEnd {
        saved ? FilmEnd(toast: savedText, voice: nil) : FilmEnd(toast: failedText, voice: .recordingFailed)
    }

    /// The athlete left the screen: a count is dropped without a word, and a film is stopped so that
    /// what it caught is kept.
    public static func interrupted(_ state: FilmState) -> FilmStep? {
        switch state {
        case .idle: return nil
        case .counting: return .cancelCountdown(toast: cancelledText)
        case .filming: return .stopFilming
        }
    }

    /// What a screen reader says of the REC control.
    public static func label(for state: FilmState) -> String {
        switch state {
        case .counting: return "Recording is about to start, tap to cancel"
        case .filming: return "Stop recording"
        case .idle: return "Record this workout"
        }
    }

    /// What the control says on screen. Lit while filming, plain otherwise: the count itself is on
    /// the picture, so the control only has to say which of the three states REC is in.
    public static func title(for state: FilmState) -> String { state == .filming ? "● REC" : "REC" }

    /// A film's name in the working folder, before the container is added: `cindy-` and the moment
    /// it was started, to the second.
    public static func fileName(atMillis: Int64, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                        from: Date(timeIntervalSince1970: Double(atMillis) / 1000))
        return String(format: "cindy-%04d-%02d-%02d-%02d%02d%02d",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}
