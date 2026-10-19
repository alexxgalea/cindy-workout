import Foundation

/// What the player is told to do with the track.
public enum MusicAction: Equatable, Sendable {
    case play
    /// Held where it is, to be picked up again.
    case pause
    /// Paused and put back at the top, for the next workout.
    case stop
}

/// What to do about the chosen track when the camera screen comes back from the menu.
public enum MusicLoad: Equatable, Sendable {
    /// Nothing is chosen: drop whatever is loaded.
    case release
    /// The chosen track is the one loaded. A reload is a decode, and a seek back to the top of a
    /// track that may be playing.
    case keep
    case load
}

/// The decisions behind the music: how loud, when it plays, what to do with the choice, and what the
/// sheet says. Port of `MusicPlayer`'s volume rules and of `MainActivity`'s `syncMusic` and the
/// places that start and stop it; the player itself is the platform's.
///
/// One track the athlete already owns, looped for the length of the workout. The app ships no audio
/// of its own and uploads none.
public enum MusicFlow {

    /// What share of the chosen level survives while the voice is speaking over it.
    public static let duckedShare: Float = 0.18

    /// How loud the track plays. Ducking multiplies rather than replaces: a track already turned
    /// down to a third should not get *louder* because the voice started talking, which is what a
    /// fixed ducked level does.
    public static func level(volume: Float, ducked: Bool) -> Float {
        let v = clamp(volume)
        return ducked ? v * duckedShare : v
    }

    /// A level kept inside 0 to 1. Held apart from the player so that a volume chosen with nothing
    /// loaded survives until something is, and so that ducking has a level to return to.
    public static func clamp(_ volume: Float) -> Float { min(max(volume, 0), 1) }

    // MARK: - when it plays

    /// What to do with the track when the workout moves from one state to the next, or `nil` for
    /// nothing.
    ///
    /// It starts with the clock and when a pause ends, if the athlete has it on; a pause holds it
    /// where it is, whether or not it is on; and the end of a workout, however it ends, and a reset
    /// put it back at the top.
    public static func onWorkout(from old: WorkoutState, to new: WorkoutState, musicOn: Bool) -> MusicAction? {
        guard old != new else { return nil }
        switch new {
        case .running: return musicOn ? .play : nil
        case .paused: return .pause
        case .finished, .idle: return .stop
        case .setup: return nil
        }
    }

    /// What to do when the menu may have changed the setting: play if it is on and the clock is
    /// running, else hold.
    public static func onSync(musicOn: Bool, running: Bool) -> MusicAction {
        musicOn && running ? .play : .pause
    }

    // MARK: - the choice

    /// What to do about the chosen track on returning from the menu.
    public static func plan(chosen: String?, loaded: String?) -> MusicLoad {
        guard let chosen else { return .release }
        return chosen == loaded ? .keep : .load
    }

    /// What is said when the chosen track will not load. Its grant has lapsed (deleted, or the app
    /// reinstalled out from under it), and the choice is cleared rather than retried on every
    /// return, so that the menu stops offering a track that cannot play.
    public static let lapsedText = "That track can no longer be played"

    /// What to call a track, without opening it: the file's name without its last extension, the way
    /// `substringBeforeLast('.')` takes it. A name with no dot is kept whole.
    public static func displayName(fileName: String) -> String {
        guard let dot = fileName.lastIndex(of: ".") else { return fileName }
        return String(fileName[..<dot])
    }

    // MARK: - the sheet

    public static let sheetTitle = "Music"

    public static let sheetSubtitle =
        "One track, looped for the whole twenty minutes. It drops in volume while the voice is " +
        "counting, and stops when the clock does."

    // iOS: the picker is Files, not the file picker.
    public static let sheetNote = "Anything in Files the picker can open. Nothing is uploaded."

    public static let playLabel = "Play during the workout"
    public static let volumeLabel = "Volume"

    /// The card at the top of the sheet. A name that cannot be read means the grant behind the track
    /// has gone, which is said here and not discovered mid-workout.
    public static func trackLine(chosen: String?, name: String?) -> String {
        name ?? (chosen == nil ? "No track chosen" : "That track can no longer be opened")
    }

    public static func primaryLabel(chosen: String?) -> String { chosen == nil ? "CHOOSE A TRACK" : "CHANGE TRACK" }
    public static func secondaryLabel(chosen: String?) -> String { chosen == nil ? "CANCEL" : "LISTEN" }

    /// What the toast says once a track has been taken.
    public static func adoptedText(name: String?) -> String { "Music: \(name ?? "track chosen")" }
}
