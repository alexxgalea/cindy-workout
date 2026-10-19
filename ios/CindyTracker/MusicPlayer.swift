import AVFoundation
import CindyCore

/// Loops one user-chosen track for the length of the workout.
///
/// The track is picked from Files rather than bundled, so the app ships no audio of its own and plays
/// whatever the athlete already owns. Choosing it is the menu's job and remembering it is
/// `Profile`'s; this class only plays what it is handed, and the workout is the only thing that
/// starts and stops it. `MusicFlow` decides when, and how loud.
final class MusicPlayer {

    private var player: AVAudioPlayer?
    /// Held open while a track is loaded, because the player reads the file as it plays.
    private var scoped: URL?
    private var ducked = false

    /// How loud the track plays before ducking takes anything off it. Held here and not written
    /// straight through, so that a volume chosen with nothing loaded survives until something is.
    var volume: Float = 1 {
        didSet {
            volume = MusicFlow.clamp(volume)
            apply()
        }
    }

    /// What is loaded, as the profile keeps it, so the workout can tell whether the chosen track is
    /// the one playing and skip a reload. Nil when nothing is loaded.
    private(set) var track: String?

    /// Whether the track loaded and is ready to play.
    func load(_ stored: String) -> Bool {
        release()
        guard let url = MusicLibrary.resolve(stored) else { return false }
        if url.startAccessingSecurityScopedResource() { scoped = url }
        do {
            let next = try AVAudioPlayer(contentsOf: url)
            next.numberOfLoops = -1
            guard next.prepareToPlay() else { release(); return false }
            player = next
            track = stored
            apply()
            return true
        } catch {
            release()
            return false
        }
    }

    func play() {
        guard let player, !player.isPlaying else { return }
        // Playback, so the track carries on when the ringer switch is down, as the voice does.
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
    }

    func pause() {
        guard let player, player.isPlaying else { return }
        player.pause()
    }

    /// Held, and back at the top for the next workout.
    func stop() {
        guard let player else { return }
        if player.isPlaying { player.pause() }
        player.currentTime = 0
    }

    /// Drops the volume while something is being spoken over the top.
    func duck(_ on: Bool) {
        guard ducked != on else { return }
        ducked = on
        apply()
    }

    func release() {
        player?.stop()
        player = nil
        if let scoped { scoped.stopAccessingSecurityScopedResource() }
        scoped = nil
        track = nil
        ducked = false
    }

    private func apply() {
        player?.volume = MusicFlow.level(volume: volume, ducked: ducked)
    }

    deinit { release() }
}
