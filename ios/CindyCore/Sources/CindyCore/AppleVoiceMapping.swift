import Foundation

/// How a voice the system lists is described to the director.
public enum AppleVoiceQuality: CaseIterable, Sendable {
    /// The compact voice every language ships with.
    case standard
    /// An enhanced voice, downloaded in Settings → Accessibility → Spoken Content → Voices.
    case enhanced
    /// A premium voice, downloaded the same way.
    case premium
}

/// The one place that knows what the system's speech constants mean, as `AndroidTtsEngine` is on
/// Android: pure, so it is held to what it means on any machine, and `AVSpeechTtsEngine` only
/// fetches the facts it is given.
///
/// iOS lists only the voices that are installed, so a voice is never "not fetched" and none runs on
/// a server; the director's states for "downloadable" and "online only" simply do not arise.
public enum AppleVoiceMapping {

    /// The director ranks voices on Android's 100 (very low) to 500 (very high) scale. A compact
    /// voice is ordinary, an enhanced one high, a premium one very high.
    public static func quality(_ quality: AppleVoiceQuality) -> Int {
        switch quality {
        case .standard: return 300
        case .enhanced: return 400
        case .premium: return 500
        }
    }

    /// Every voice answers at the same pace as far as anyone can tell; the field is ranked low to
    /// high on the same scale and only matters between two voices that otherwise tie.
    public static let latency = 200

    /// A voice by its identifier (`com.apple.voice.compact.es-ES.Monica`) and language tag (`es-ES`).
    public static func engineVoice(identifier: String, languageTag: String, quality q: AppleVoiceQuality) -> EngineVoice {
        let locale = DeviceLocale(languageTag: languageTag)
        return EngineVoice(name: identifier, language: locale.language, country: locale.country,
                           installed: true, network: false, quality: quality(q), latency: latency)
    }

    /// Whether the system can speak `locale`, given the language tags of the voices it lists.
    ///
    /// A language is spoken if any voice speaks it, in any region: Spanish is Spanish whether the
    /// voice is from Spain or Mexico. The region only ever picks between voices.
    public static func availability(ofVoiceLanguages tags: [String], for locale: DeviceLocale) -> LanguageAvailability {
        tags.contains { DeviceLocale(languageTag: $0).language == locale.language } ? .available : .notSupported
    }
}
