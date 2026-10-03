import Foundation

/// How an utterance joins what the engine is already saying.
public enum SpeakQueue: Sendable {
    /// Cuts off whatever is being said: for a rep number, which must not fall behind the athlete.
    case replace
    /// Waits its turn: for a cue that must not be dropped.
    case append
}

/// Why an utterance could not be spoken, as far as anyone can do anything about it.
public enum SpeechFailure: Sendable {
    /// A voice that runs on the engine's servers could not reach them.
    case network
    /// The voice's data is still being fetched.
    case notInstalled
    /// The engine has no voice that speaks the language at all.
    case unavailable
    /// Anything else.
    case other
}

/// What came of asking the engine to fetch a language's voice.
public enum DownloadRequest: Sendable {
    /// A voice the engine lists was set, which is the documented way to ask for its data.
    case asked
    /// The engine says the data is missing but lists no voice to set. Only its own screen can
    /// fetch it, so the caller should send the athlete there.
    case useEngineScreen
    /// The engine does not offer the language, or is not ready, so there is nothing to fetch.
    case notOffered
}

/// What an engine reports back: when it is ready, and how each utterance goes.
public protocol EngineListener: AnyObject {
    /// The engine has connected (`success`) or has failed to and never will.
    func onReady(_ success: Bool)
    func onStart(_ utteranceId: String)
    func onDone(_ utteranceId: String)
    /// Cut off before it finished, by the next utterance or by a stop.
    func onStop(_ utteranceId: String)
    func onError(_ utteranceId: String, _ failure: SpeechFailure)
}

/// What the app needs from a text-to-speech engine, and nothing more.
///
/// The iOS implementation sits over `AVSpeechSynthesizer`. It is a protocol because the interesting
/// part of the speaker — which voice to use, what to do when the chosen one is missing, how a
/// download and a preview leave the engine — has to be tested against the awkward things real
/// engines do, and a synthesizer cannot be made to do them in a test.
///
/// Every call may block on the engine's process, so none is free to make in a loop.
public protocol TtsEngine: AnyObject {

    /// Told about readiness and utterances. Set once, by whoever owns the engine. An engine should
    /// hold it weakly: the director that sets it also holds the engine.
    var listener: EngineListener? { get set }

    /// Every voice the engine lists, or none if it lists none or is not answering.
    func voices() -> [EngineVoice]

    /// Whether the engine can speak `locale`, without changing anything.
    func availability(_ locale: DeviceLocale) -> LanguageAvailability

    /// Puts the engine on `locale`, letting it choose its own default voice for it, which is how
    /// the voice the athlete has set in the system settings is honoured. True if it took.
    @discardableResult
    func setLanguage(_ locale: DeviceLocale) -> Bool

    /// Puts the engine on the voice called `name`, one of those `voices` listed. True if it took.
    /// For a voice whose data is missing this is also what asks the engine to fetch it, and may
    /// report failure while doing so.
    @discardableResult
    func setVoice(_ name: String) -> Bool

    /// The voice the engine would speak with now, if it says.
    func currentVoice() -> EngineVoice?

    func speak(_ text: String, queue: SpeakQueue, volume: Float, utteranceId: String)

    func stop()

    func shutdown()
}
