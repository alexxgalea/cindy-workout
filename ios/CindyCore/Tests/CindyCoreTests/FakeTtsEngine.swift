import CindyCore

/// A text-to-speech engine that does what tests tell it to and remembers what it was asked.
///
/// It behaves like the real ones in the ways that matter here: asking for a language it can
/// speak picks that language's default voice; asking for one it cannot changes nothing; asking
/// for a voice by name sets it unless it is on the refused list; and every call is written down,
/// in order, so a test can say not only what ended up set but how the engine was walked there.
///
/// Mirrors `FakeTtsEngine.kt`.
final class FakeTtsEngine: TtsEngine {

    /// Held weakly, as an engine should: the director that listens also owns the engine.
    weak var listener: EngineListener?

    /// What `voices()` returns.
    var listed: [EngineVoice] = []

    /// What the engine answers when asked about a locale, by language tag. Anything else is not supported.
    var answers: [String: LanguageAvailability] = [:]

    /// The voice the engine picks as the default for a locale, by language tag.
    var defaults: [String: String] = [:]

    /// Voices that `setVoice` declines.
    var refused: Set<String> = []

    /// The voice the engine is set to now.
    var current: String?

    /// Every call that changes something, in order: `setLanguage:es-ES`, `setVoice:name`, `stop`.
    var calls: [String] = []

    struct Said: Equatable {
        let text: String
        let queue: SpeakQueue
        let volume: Float
        let id: String
    }

    var said: [Said] = []

    func voices() -> [EngineVoice] { listed }

    func availability(_ locale: DeviceLocale) -> LanguageAvailability {
        answers[locale.toLanguageTag()] ?? .notSupported
    }

    func setLanguage(_ locale: DeviceLocale) -> Bool {
        calls.append("setLanguage:\(locale.toLanguageTag())")
        if availability(locale) != .available { return false }
        current = defaults[locale.toLanguageTag()]
        return true
    }

    func setVoice(_ name: String) -> Bool {
        calls.append("setVoice:\(name)")
        if refused.contains(name) { return false }
        current = name
        return true
    }

    func currentVoice() -> EngineVoice? { listed.first { $0.name == current } }

    func speak(_ text: String, queue: SpeakQueue, volume: Float, utteranceId: String) {
        said.append(Said(text: text, queue: queue, volume: volume, id: utteranceId))
    }

    func stop() { calls.append("stop") }

    func shutdown() { calls.append("shutdown") }

    /// The engine connects, or fails to.
    func becomeReady(success: Bool = true) {
        listener?.onReady(success)
    }

    /// A phone with Google's voices: English and Spanish work, Russian is offered but its data
    /// has to be fetched, Polish is only spoken over the network, Portuguese not at all.
    func likeGoogle() {
        listed = EngineFixtures.google
        answers["en-US"] = .available
        answers["es-ES"] = .available
        answers["ru-RU"] = .missingData
        defaults["en-US"] = "en-us-x-tpd-local"
        defaults["es-ES"] = "es-es-x-eea-local"
    }
}
