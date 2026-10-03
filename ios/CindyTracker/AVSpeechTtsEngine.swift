import AVFoundation
import CindyCore

/// A `TtsEngine` over `AVSpeechSynthesizer`: the iOS side of what `AndroidTtsEngine` is on Android.
///
/// iOS lists only the voices that are installed, so a language is either there or not offered, and
/// nothing is a network voice; the director's states for "downloadable" and "online only" simply do
/// not arise. A voice is chosen by its identifier.
///
/// Utterance events arrive on the main thread, from the synthesizer's delegate.
final class AVSpeechTtsEngine: NSObject, TtsEngine, AVSpeechSynthesizerDelegate {

    /// Held weakly: the director that listens also owns this engine. Ready is announced when the
    /// listener arrives, because the engine has nothing to connect to and is ready already.
    weak var listener: EngineListener? {
        didSet {
            guard listener != nil else { return }
            DispatchQueue.main.async { [weak self] in self?.listener?.onReady(true) }
        }
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var voice: AVSpeechSynthesisVoice?
    private var ids: [ObjectIdentifier: String] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func voices() -> [EngineVoice] {
        AVSpeechSynthesisVoice.speechVoices().map(Self.engineVoice)
    }

    func availability(_ locale: DeviceLocale) -> LanguageAvailability {
        AVSpeechSynthesisVoice.speechVoices().contains { DeviceLocale(languageTag: $0.language).language == locale.language }
            ? .available : .notSupported
    }

    func setLanguage(_ locale: DeviceLocale) -> Bool {
        guard let chosen = AVSpeechSynthesisVoice(language: locale.toLanguageTag()) else { return false }
        voice = chosen
        return true
    }

    func setVoice(_ name: String) -> Bool {
        guard let chosen = AVSpeechSynthesisVoice(identifier: name) else { return false }
        voice = chosen
        return true
    }

    func currentVoice() -> EngineVoice? { voice.map(Self.engineVoice) }

    func speak(_ text: String, queue: SpeakQueue, volume: Float, utteranceId: String) {
        // A rep number must not fall behind the athlete, so it cuts off what is being said
        // (Android's QUEUE_FLUSH); a cue that must not be dropped waits its turn.
        if queue == .replace { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.volume = volume
        ids[ObjectIdentifier(utterance)] = utteranceId
        synthesizer.speak(utterance)
    }

    func stop() { synthesizer.stopSpeaking(at: .immediate) }

    func shutdown() { synthesizer.stopSpeaking(at: .immediate) }

    private static func engineVoice(_ v: AVSpeechSynthesisVoice) -> EngineVoice {
        let locale = DeviceLocale(languageTag: v.language)
        let quality: Int
        switch v.quality {
        case .premium: quality = 500
        case .enhanced: quality = 400
        default: quality = 300
        }
        return EngineVoice(name: v.identifier, language: locale.language, country: locale.country,
                           installed: true, network: false, quality: quality, latency: 200)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        if let id = ids[ObjectIdentifier(utterance)] { listener?.onStart(id) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if let id = ids.removeValue(forKey: ObjectIdentifier(utterance)) { listener?.onDone(id) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        if let id = ids.removeValue(forKey: ObjectIdentifier(utterance)) { listener?.onStop(id) }
    }
}
