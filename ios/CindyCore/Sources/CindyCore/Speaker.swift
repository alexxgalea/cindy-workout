import Foundation

/// Runs a piece of work somewhere else: on the main thread, or on the one background thread.
///
/// Injected so a test can decide when "later" is, as `SpeakerTest` does with its executor and
/// Robolectric's looper.
public typealias Dispatcher = (@escaping () -> Void) -> Void

/// Speaks rep counts and cues.
///
/// Rep numbers are spoken with `.replace` so the voice tracks the athlete rather than falling a
/// queue behind during a fast set; cues that must not be dropped are queued after.
///
/// What is said arrives as a `VoiceLine` and is worded here, by the phrasebook of the voice that
/// is actually speaking. Which voice that is, what to do when the language the athlete chose is
/// not on the phone, and how downloads and previews leave the engine are `VoiceDirector`'s
/// business. This is the thin end of it: the switches, the main thread, the background thread,
/// and the engine. Port of `Speaker.kt`.
public final class Speaker: @unchecked Sendable {

    private let engine: TtsEngine
    private let director: VoiceDirector
    private let background: Dispatcher
    private let main: Dispatcher
    private let lock = NSLock()

    /// Set on `shutdown`, so nothing the background thread finishes late reaches a dead screen.
    private var closed = false

    /// True from the moment a question is handed to the background thread until it has been answered.
    private var asking = false

    public var enabled = true

    private var _volume: Float = 1

    /// How loud the voice speaks, 0...1, against whatever the phone's media volume is.
    ///
    /// Applied per utterance rather than once at start-up, because a synthesizer has no volume of
    /// its own to set: it is a property of each request. Changing this therefore takes effect on
    /// the next thing said, which for a rep count is the next rep, and is what makes the menu's
    /// slider audible while it is being dragged.
    public var volume: Float {
        get { _volume }
        set { _volume = min(max(newValue, 0), 1) }
    }

    /// Raised while speech is audible, so background music can duck out of the way.
    public var onSpeakingChanged: ((Bool) -> Void)?

    /// `background` and `main` default to a serial queue of its own and the main queue.
    public init(
        engine: TtsEngine,
        background: Dispatcher? = nil,
        main: @escaping Dispatcher = { work in DispatchQueue.main.async(execute: work) },
        now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.engine = engine
        self.main = main
        if let background {
            self.background = background
        } else {
            let queue = DispatchQueue(label: "cindy.speaker")
            self.background = { work in queue.async(execute: work) }
        }
        director = VoiceDirector(engine: engine, now: now)
        director.whenSpeaking = { [weak self] speaking in self?.onSpeakingChanged?(speaking) }
    }

    // MARK: - the language

    /// The language to speak, as a `VoicePacks` tag.
    ///
    /// Asking for one the phone cannot speak is fine: the workout is counted in English and
    /// `fallingBack` says so, and the language takes over the moment its voice turns up.
    public var language: String {
        get { director.wanted.tag }
        set { director.choose(VoicePacks.of(newValue)) }
    }

    /// The language asked for, whether or not the phone can speak it yet.
    public var wanted: VoicePack { director.wanted }

    /// True while the athlete is being answered in English because their language is not ready.
    /// Only once the engine has answered; before that English is simply where everything starts.
    public var fallingBack: Bool { director.fallingBack }

    /// Tries the language again if it is not the one being spoken, in case its voice has arrived.
    /// Cheap when nothing is wrong, so safe at every moment that might be the moment.
    public func refresh() { director.refresh() }

    // MARK: - saying things

    /// Interrupts anything in progress: used for rep numbers.
    public func say(_ line: VoiceLine) { speak(line, .replace) }

    /// Queues behind whatever is speaking: used for cues that must be heard.
    public func queue(_ line: VoiceLine) { speak(line, .append) }

    /// Says `line` regardless of `enabled`, for previewing the voice from the menu.
    ///
    /// The callers are the volume slider and HEAR IT, where refusing to speak because the voice
    /// is switched off would leave the athlete adjusting a number against silence.
    public func preview(_ line: VoiceLine) { speak(line, .replace, ignoreEnabled: true) }

    /// Words the line only once the voice is going to say it. Rep counts arrive on the analysis
    /// path at camera rate, and with the voice switched off there is no reason to build a
    /// sentence for each one.
    private func speak(_ line: VoiceLine, _ queue: SpeakQueue, ignoreEnabled: Bool = false) {
        if (!enabled && !ignoreEnabled) || !director.ready { return }
        director.speak(line, queue: queue, volume: volume)
    }

    // MARK: - what is on the phone

    /// Where every language stands on this phone, delivered on the main thread.
    ///
    /// Asked of the engine on a background thread, because listing its voices is a call into
    /// another process that can take a noticeable time, and nothing is delivered once the speaker
    /// has been shut down.
    ///
    /// Nothing is delivered before the engine has connected, either. An engine that has not
    /// answered yet lists no voices, and reporting that would tell the athlete their phone speaks
    /// nothing but English for as long as it took to start. The caller keeps whatever it was
    /// showing and asks again.
    ///
    /// Asked again while the last question is still out, nothing is queued and `onResult` is not
    /// called: an engine that is slow to answer is not helped by a line of identical questions
    /// behind the first, whose answers would only arrive stale, one after another.
    public func packStates(_ onResult: @escaping (PackStates) -> Void) {
        lock.lock()
        let stop = closed || !director.ready || asking
        if !stop { asking = true }
        lock.unlock()
        if stop { return }
        background { [self] in
            let states = director.states()
            lock.lock(); asking = false; lock.unlock()
            main { [self] in
                lock.lock(); let gone = closed; lock.unlock()
                if !gone { onResult(states) }
            }
        }
    }

    /// Asks the engine to fetch `pack`'s voice, and says what came of it: asked, or an engine
    /// that can only be asked through its own screen, or nothing to ask. See `DownloadRequest`.
    public func download(_ pack: VoicePack) -> DownloadRequest { director.download(pack) }

    /// Milliseconds since `tag`'s download was asked for, or nil if it has not been.
    public func downloadingFor(_ tag: String) -> Int64? { director.downloadingFor(tag) }

    /// Plays `pack`'s sample, in an online voice if that is the only one, without changing the
    /// language chosen. A failure (no connection, data still arriving, no voice at all) arrives
    /// on the main thread through `onFailure`.
    ///
    /// Returns whether the engine took it. When it did not, `onFailure` has already been called,
    /// so a caller that has something to say about a preview that is playing can wait for this.
    @discardableResult
    public func previewPack(_ pack: VoicePack, onFailure: @escaping (SpeechFailure) -> Void) -> Bool {
        let started = director.preview(pack, volume: volume) { [self] failure in
            main { [self] in
                lock.lock(); let gone = closed; lock.unlock()
                if !gone { onFailure(failure) }
            }
        }
        if !started { onFailure(.unavailable) }
        return started
    }

    public func stop() { engine.stop() }

    public func shutdown() {
        lock.lock(); closed = true; lock.unlock()
        engine.shutdown()
    }
}
