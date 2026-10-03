import Foundation

/// Where every language stands, in the order the picker lists them.
///
/// Kotlin returns an insertion-ordered map; a Swift dictionary has no order, and the picker's order
/// is the point.
public struct PackStates: Sendable {
    public let entries: [(tag: String, state: PackState)]

    public var tags: [String] { entries.map { $0.tag } }

    public subscript(_ tag: String) -> PackState? { entries.first { $0.tag == tag }?.state }
}

/// Decides which voice the workout is spoken in, and looks after the engine while it does.
///
/// The one rule the whole thing serves: **the words and the voice always agree.** A Spanish
/// sentence in an English voice is unintelligible and an English sentence in a Spanish voice is
/// worse, so what is said is worded by the phrasebook of the voice actually in use. If the athlete
/// asks for a language the phone cannot speak — the voice has not been fetched, or the engine
/// doesn't have it — the workout carries on in English and says so, rather than failing or
/// mumbling. `wanted` keeps what they asked for, so the moment the voice arrives it takes over.
///
/// Free of platform types, so all of that is testable against a fake engine.
///
/// **Threads.** Everything here is for the main thread — that is where the workout's rep counts
/// are spoken from, since the analysis thread only posts a frame for the screen to render — with
/// two exceptions that are safe elsewhere: `states()`, which only reads, and the `EngineListener`
/// callbacks, which the engine delivers from its own threads. So the state the main thread owns is
/// not locked, and what both sides touch (readiness, the download clocks, the preview in flight,
/// the utterance counter) is behind one lock. `download` and `preview`, which list the engine's
/// voices, block for as long as that takes. They answer a tap, never a rep.
public final class VoiceDirector: EngineListener, @unchecked Sendable {

    private let engine: TtsEngine
    private let device: () -> DeviceLocale
    private let now: () -> Int64

    /// Guards what the engine's threads and the main thread both touch.
    private let lock = NSLock()
    private var _ready = false
    private var ids = 0
    /// When each language's download was asked for. The engine cannot say; only the app knows.
    private var downloads: [String: Int64] = [:]
    private var previewId: String?
    private var onPreviewFailure: ((SpeechFailure) -> Void)?

    /// True once the engine has connected. Nothing is asked of it before that.
    public var ready: Bool {
        lock.lock(); defer { lock.unlock() }
        return _ready
    }

    /// The language the athlete asked for.
    public private(set) var wanted: VoicePack = VoicePacks.english

    /// The language actually being spoken: `wanted`, or English when the phone cannot.
    public private(set) var using: VoicePack = VoicePacks.english

    /// Words for the voice in use.
    public var phrasebook: any Phrasebook { using.phrasebook }

    /// True while the athlete is being answered in English because their language is not ready.
    ///
    /// Never true before the engine has connected: until then English is only where everything
    /// starts, and reporting it as a fall-back would tell someone whose Spanish voice is installed
    /// that it isn't. It is also never true for an engine that failed to connect at all, which is
    /// a different problem with nothing to say about languages.
    public var fallingBack: Bool { ready && using != wanted }

    /// Told when the engine's readiness is known.
    public var whenReady: ((Bool) -> Void)?

    /// Told when speech starts and stops, so music can duck out of its way.
    public var whenSpeaking: ((Bool) -> Void)?

    /// The pack whose voice the engine is set to now, or `nil` when something else — a preview, a
    /// download request — has moved it, so that the next thing said puts it back first.
    private var applied: VoicePack?

    public init(
        engine: TtsEngine,
        device: @escaping () -> DeviceLocale = { DeviceLocale.current },
        now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.engine = engine
        self.device = device
        self.now = now
        engine.listener = self
    }

    // MARK: - which language

    /// Asks for `pack`. Takes effect now if the engine is ready, and as soon as it is if not.
    ///
    /// Asking for what is already being spoken costs the engine nothing, so this can be called
    /// every time the screen comes back. Asking again for a language that had to fall back to
    /// English is a retry, which is how a voice that has just been fetched gets picked up.
    public func choose(_ pack: VoicePack) {
        let unchanged = pack == wanted
        wanted = pack
        if ready && (!unchanged || fallingBack) { apply() }
    }

    /// Tries again, if the language asked for is not the one being spoken.
    ///
    /// Cheap when nothing is wrong, so it is safe to call at every moment a voice might have
    /// arrived: coming back to the screen, and starting a workout.
    public func refresh() {
        if fallingBack { apply() }
    }

    private func apply() {
        if applyTo(wanted) {
            using = wanted
        } else {
            _ = applyTo(VoicePacks.english)
            using = VoicePacks.english
        }
        applied = using
    }

    /// Puts the engine on `pack`'s voice. False if the phone has none that can count a workout.
    private func applyTo(_ pack: VoicePack) -> Bool {
        if pack.tag == VoicePacks.english.tag {
            // Exactly what the app did before it had languages: the engine's own US voice.
            engine.setLanguage(.us)
            return true
        }
        let voices = engine.voices()
        guard let best = VoiceChoice.bestForWorkout(pack, voices, device()) else {
            // An engine that lists no voice for a language may still speak it, and says so
            // only when asked. What it lists is otherwise believed over what it says.
            return !voices.contains { $0.speaks(pack) }
                && engine.availability(pack.defaultLocale) == .available
                && engine.setLanguage(pack.defaultLocale)
        }
        // Ask for the language first, so the engine picks the voice the athlete has chosen in
        // the system settings, and only take the choice out of its hands if that voice is not
        // one a workout can be counted with — a network voice, or one whose data is missing.
        if engine.setLanguage(pack.defaultLocale), engine.currentVoice()?.countsFor(pack) == true {
            return true
        }
        return engine.setVoice(best.name)
    }

    // MARK: - speaking

    /// Says `line` in the voice in use and returns the utterance's id.
    ///
    /// Puts the engine back on the athlete's voice first if a preview has moved it, and only then
    /// words the line, because putting it back can turn out to fall back to English.
    @discardableResult
    public func speak(_ line: VoiceLine, queue: SpeakQueue, volume: Float) -> String {
        if applied != using { apply() }
        let id = "cindy-\(nextId())"
        engine.speak(phrasebook.say(line), queue: queue, volume: volume, utteranceId: id)
        return id
    }

    /// Plays `pack`'s sample in a voice for it, without changing which language is chosen.
    ///
    /// Uses the voice a workout would if the phone has one, so the preview is a true sample, and
    /// an online voice otherwise, so a language can be heard before it is downloaded. Returns
    /// false if nothing on the engine speaks it. A failure once it is playing — no connection,
    /// data still arriving — comes back through `onFailure`, from whatever thread the engine uses.
    public func preview(_ pack: VoicePack, volume: Float, onFailure: @escaping (SpeechFailure) -> Void) -> Bool {
        if !ready { return false }
        let voice = VoiceChoice.bestForPreview(pack, engine.voices(), device())
        // Whatever comes of it, the engine may no longer be on the athlete's voice.
        applied = nil
        let accepted: Bool
        if let voice {
            accepted = engine.setVoice(voice.name)
        } else if pack.tag == VoicePacks.english.tag {
            accepted = engine.setLanguage(.us)
        } else if engine.availability(pack.defaultLocale) == .available {
            accepted = engine.setLanguage(pack.defaultLocale)
        } else {
            accepted = false
        }
        if !accepted { return false }

        let id = "preview-\(nextId())"
        lock.lock()
        previewId = id
        onPreviewFailure = onFailure
        lock.unlock()
        engine.speak(pack.phrasebook.say(.sample), queue: .replace, volume: volume, utteranceId: id)
        return true
    }

    // MARK: - what is on the phone

    /// Where every language stands, keyed by tag. Blocks on the engine, so not for the main thread.
    ///
    /// A finished download is forgotten here, since a language that is ready needs no reminder
    /// that it was once asked for.
    public func states() -> PackStates {
        let voices = engine.voices()
        var entries: [(tag: String, state: PackState)] = []
        for pack in VoicePacks.all {
            // Only ask an engine what it can speak when its own list gives no answer.
            let availability: LanguageAvailability? =
                voices.contains { $0.countsFor(pack) } ? nil : engine.availability(pack.defaultLocale)
            lock.lock()
            let downloading = downloads[pack.tag] != nil
            lock.unlock()
            let state = VoiceChoice.stateOf(pack, voices, availability, downloading: downloading)
            if state == .ready {
                lock.lock(); downloads[pack.tag] = nil; lock.unlock()
            }
            entries.append((pack.tag, state))
        }
        return PackStates(entries: entries)
    }

    /// Asks the engine to fetch `pack`'s voice, and says what came of it.
    ///
    /// The only documented way to ask is to set a voice whose data is missing, so that is all
    /// this claims to have done: `DownloadRequest.asked`. An engine that says the data is missing
    /// without listing a voice to set cannot be asked from here, and pretending otherwise would
    /// leave the athlete watching "downloading" for something nobody requested. That is
    /// `DownloadRequest.useEngineScreen`, for the caller to send them to the engine's own
    /// installer.
    ///
    /// The engine reports no progress, so a request only starts the clock: `states()` shows the
    /// language as downloading until its voice turns up, and `downloadingFor` says for how long,
    /// which is the only way to tell a slow download from one that is waiting for Wi-Fi.
    public func download(_ pack: VoicePack) -> DownloadRequest {
        if !ready { return .notOffered }
        guard let voice = VoiceChoice.bestToDownload(pack, engine.voices(), device()) else {
            return engine.availability(pack.defaultLocale) == .missingData ? .useEngineScreen : .notOffered
        }

        // Asking moves the engine onto a voice that cannot speak yet, and a voice whose data is
        // missing may answer "error" while the request goes through, so the answer is not used.
        applied = nil
        engine.setVoice(voice.name)
        lock.lock(); downloads[pack.tag] = now(); lock.unlock()
        apply()
        return .asked
    }

    /// Milliseconds since `tag`'s download was asked for, or `nil` if it has not been.
    public func downloadingFor(_ tag: String) -> Int64? {
        lock.lock()
        let asked = downloads[tag]
        lock.unlock()
        return asked.map { now() - $0 }
    }

    // MARK: - the engine's side

    public func onReady(_ success: Bool) {
        lock.lock(); _ready = success; lock.unlock()
        if success { apply() }
        whenReady?(success)
    }

    public func onStart(_ utteranceId: String) {
        whenSpeaking?(true)
    }

    public func onDone(_ utteranceId: String) {
        whenSpeaking?(false)
        if utteranceId == currentPreviewId() { forgetPreview() }
    }

    public func onStop(_ utteranceId: String) {
        // Cut off by the next thing said, or by stop(). Not "done" as far as the music is
        // concerned — a rep count flushing the last one would otherwise let it swell between
        // every pair of numbers — but a preview that was cut off is over, and its callback,
        // which holds on to a screen, should not outlive it.
        if utteranceId == currentPreviewId() { forgetPreview() }
    }

    public func onError(_ utteranceId: String, _ failure: SpeechFailure) {
        whenSpeaking?(false)
        if utteranceId == currentPreviewId() {
            lock.lock()
            let report = onPreviewFailure
            lock.unlock()
            forgetPreview()
            report?(failure)
        }
    }

    // MARK: - bookkeeping

    private func nextId() -> Int {
        lock.lock(); defer { lock.unlock() }
        ids += 1
        return ids
    }

    private func currentPreviewId() -> String? {
        lock.lock(); defer { lock.unlock() }
        return previewId
    }

    private func forgetPreview() {
        lock.lock()
        previewId = nil
        onPreviewFailure = nil
        lock.unlock()
    }
}
