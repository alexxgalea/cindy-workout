import Foundation

/// One voice a text-to-speech engine offers, reduced to what choosing between voices needs.
///
/// Free of platform types on purpose, like `Coach`: which voice the app ends up speaking with is
/// the decision that decides whether a Spanish workout is heard in Spanish, and it is only worth
/// making carefully if it can be tested against the shapes real engines return.
public struct EngineVoice: Equatable, Sendable {
    public var name: String
    /// ISO 639 language, lower case: `es`.
    public var language: String
    /// ISO 3166 region, upper case, or empty: `ES`.
    public var country: String
    /// False for a voice the engine lists but has not fetched the data for yet. Such a voice
    /// cannot speak until it has been downloaded, and asking it to fails with "not installed yet".
    public var installed: Bool
    /// True for a voice that synthesises on the engine's servers. It needs a connection for every
    /// utterance, so it is fine to preview and not something to count reps with.
    public var network: Bool
    /// 100 (very low) to 500 (very high).
    public var quality: Int
    /// 100 (very low) to 500 (very high). Lower answers sooner.
    public var latency: Int

    public init(name: String, language: String, country: String, installed: Bool,
                network: Bool, quality: Int, latency: Int) {
        self.name = name
        self.language = language
        self.country = country
        self.installed = installed
        self.network = network
        self.quality = quality
        self.latency = latency
    }

    /// Whether this voice speaks `pack`'s language, in whichever region.
    public func speaks(_ pack: VoicePack) -> Bool { language == pack.tag || language == pack.iso3 }

    /// Whether a workout can be counted with this voice for `pack`: its data is here and it is local.
    public func countsFor(_ pack: VoicePack) -> Bool { speaks(pack) && installed && !network }
}

/// What an engine says when asked, without changing anything, whether it can speak a locale.
public enum LanguageAvailability: Sendable {
    /// Ready to speak.
    case available
    /// Supported, but the voice data has to be fetched first.
    case missingData
    /// Not offered at all.
    case notSupported
}

/// Where a language stands on this phone.
public enum PackState: Sendable {
    /// A voice for it is on the phone and can count a workout.
    case ready
    /// Its voice data has been asked for and has not arrived.
    case downloading
    /// The engine offers it and the voice data can be fetched.
    case downloadable
    /// Only a voice that runs on the engine's servers speaks it: previewable, not usable offline.
    case onlineOnly
    /// The engine does not speak it.
    case unsupported
}

/// Deciding which of an engine's voices speaks a language, and where each language stands.
///
/// The voice list is trusted over the availability codes. Engines disagree about the codes — some
/// answer "available" for a language they only speak over the network, some "missing data" for one
/// that is installed under another region — but a voice is a voice: installed or not, local or
/// not. The codes are the fallback for an engine that lists no voice for a language at all.
public enum VoiceChoice {

    /// Where `pack` stands, given every voice the engine listed.
    ///
    /// `availability` is what the engine answered to its availability check for the pack's default
    /// locale, or `nil` when nobody asked. It is only consulted for a language the engine listed no
    /// local voice for. `downloading` is the app's own knowledge that a download was asked for,
    /// which the engine cannot report.
    public static func stateOf(
        _ pack: VoicePack, _ voices: [EngineVoice], _ availability: LanguageAvailability?,
        downloading: Bool
    ) -> PackState {
        let mine = voices.filter { $0.speaks(pack) }
        let local = mine.filter { !$0.network }

        // A language nobody listed a voice for may still be spoken: the engine says so on request.
        if local.contains(where: { $0.installed }) || (mine.isEmpty && availability == .available) {
            return .ready
        }
        let downloadable = local.contains { !$0.installed } || availability == .missingData
        if downloadable && downloading { return .downloading }
        if downloadable { return .downloadable }
        if mine.contains(where: { $0.network }) { return .onlineOnly }
        return .unsupported
    }

    /// The voice to count `pack`'s workout with, or `nil` if the phone has none. Never a network one.
    public static func bestForWorkout(_ pack: VoicePack, _ voices: [EngineVoice], _ device: DeviceLocale) -> EngineVoice? {
        best(pack, device, voices.filter { $0.countsFor(pack) })
    }

    /// The voice to ask to fetch its data for `pack`, or `nil` if the engine lists none to fetch.
    public static func bestToDownload(_ pack: VoicePack, _ voices: [EngineVoice], _ device: DeviceLocale) -> EngineVoice? {
        best(pack, device, voices.filter { $0.speaks(pack) && !$0.installed && !$0.network })
    }

    /// The voice to preview `pack` with: one that counts a workout if there is one, so a preview
    /// is a true sample of what will be heard, and otherwise a network voice, so that a language
    /// can be heard before it is downloaded.
    public static func bestForPreview(_ pack: VoicePack, _ voices: [EngineVoice], _ device: DeviceLocale) -> EngineVoice? {
        bestForWorkout(pack, voices, device)
            ?? best(pack, device, voices.filter { $0.speaks(pack) && $0.network })
    }

    /// The best of `candidates`, by, in order: the region the phone itself is set to, if it is the
    /// same language (so a phone in Mexico is answered in Mexican Spanish); the region the pack
    /// prefers; the faster voice; the higher quality; and then the name, so the answer is stable.
    private static func best(_ pack: VoicePack, _ device: DeviceLocale, _ candidates: [EngineVoice]) -> EngineVoice? {
        let deviceRegion = device.language == pack.tag ? device.country : ""
        func sameRegion(_ a: String, _ b: String) -> Bool { a.lowercased() == b.lowercased() }
        func key(_ v: EngineVoice) -> [Int] {
            [!deviceRegion.isEmpty && sameRegion(v.country, deviceRegion) ? 0 : 1,
             sameRegion(v.country, pack.defaultCountry) ? 0 : 1,
             v.latency,
             -v.quality]
        }
        var best: EngineVoice?
        for v in candidates {
            guard let current = best else { best = v; continue }
            let (a, b) = (key(v), key(current))
            // Kotlin compares names as UTF-16 strings; for the ASCII names engines use that is
            // the same as Swift's order, but it is spelled out so it cannot drift.
            let earlier = a != b ? a.lexicographicallyPrecedes(b)
                                 : Array(v.name.utf16).lexicographicallyPrecedes(Array(current.name.utf16))
            if earlier { best = v }
        }
        return best
    }
}
