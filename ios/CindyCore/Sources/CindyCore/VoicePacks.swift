import Foundation

/// A language the voice can speak: what to call it, which voice it prefers, and its words.
///
/// "Pack" because the athlete adds it: the phrases ship with the app (a few kilobytes each), and
/// what has to be fetched, on request, is the phone's own voice for the language.
public struct VoicePack: Sendable {
    /// The language tag, such as `es`. It is also the `Phrasebook`'s tag and what is stored.
    public let tag: String
    /// The language in itself, as the picker's row is headed: "Español".
    public let nativeName: String
    /// And in English, for the line beneath it: "Spanish".
    public let englishName: String
    /// The region whose voice is preferred when the phone offers more than one for the language,
    /// as an ISO 3166 code: `ES` for Spanish, `BR` for Portuguese.
    public let defaultCountry: String
    public let phrasebook: any Phrasebook

    /// `nil` when `phrasebook` is another language's: a pack that carried the wrong words would
    /// say them in the right voice, which is the one thing this whole design exists to prevent.
    public init?(_ tag: String, _ nativeName: String, _ englishName: String,
                 _ defaultCountry: String, _ phrasebook: any Phrasebook) {
        guard tag == phrasebook.tag else { return nil }
        self.tag = tag
        self.nativeName = nativeName
        self.englishName = englishName
        self.defaultCountry = defaultCountry
        self.phrasebook = phrasebook
    }

    /// The voice this pack asks the phone for first.
    public var defaultLocale: DeviceLocale { DeviceLocale(language: tag, country: defaultCountry) }

    /// The three-letter form of `tag`, for the engines that report a voice's language that way.
    ///
    /// ISO 639-2/T, as `java.util.Locale.getISO3Language` answers: the eleven languages are known,
    /// and Foundation has no table of its own to ask.
    public var iso3: String {
        switch tag {
        case "en": return "eng"
        case "es": return "spa"
        case "fr": return "fra"
        case "de": return "deu"
        case "it": return "ita"
        case "pt": return "por"
        case "nl": return "nld"
        case "pl": return "pol"
        case "ro": return "ron"
        case "tr": return "tur"
        case "ru": return "rus"
        default: return ""
        }
    }
}

/// Two packs are the same pack when they speak the same language: tags are unique, and a
/// phrasebook is not something that can be compared.
extension VoicePack: Equatable {
    public static func == (a: VoicePack, b: VoicePack) -> Bool { a.tag == b.tag }
}

/// Every language the voice speaks, in the order the picker lists them.
///
/// English first, because it is the default and what the voice falls back to; the rest in the
/// order the app was asked for. Adding a language is a phrasebook, a row here, and the tests that
/// hold for every pack.
public enum VoicePacks {

    public static let english = VoicePack("en", "English", "English", "US", PhrasebookEn())!

    public static let all: [VoicePack] = [
        english,
        VoicePack("es", "Español", "Spanish", "ES", PhrasebookEs())!,
        VoicePack("fr", "Français", "French", "FR", PhrasebookFr())!,
        VoicePack("de", "Deutsch", "German", "DE", PhrasebookDe())!,
        VoicePack("it", "Italiano", "Italian", "IT", PhrasebookIt())!,
        VoicePack("pt", "Português (Brasil)", "Portuguese (Brazil)", "BR", PhrasebookPt())!,
        VoicePack("nl", "Nederlands", "Dutch", "NL", PhrasebookNl())!,
        VoicePack("pl", "Polski", "Polish", "PL", PhrasebookPl())!,
        VoicePack("ro", "Română", "Romanian", "RO", PhrasebookRo())!,
        VoicePack("tr", "Türkçe", "Turkish", "TR", PhrasebookTr())!,
        VoicePack("ru", "Русский", "Russian", "RU", PhrasebookRu())!
    ]

    /// The pack for a stored `tag`, or English for one nobody has, such as a language removed in a
    /// later version. A preference makes no claim the app has to honour; an unknown one is
    /// English, not a crash.
    ///
    /// Matched on the language alone, so `es`, `ES` and `es-ES` are all Spanish. The app stores
    /// the bare tag, but a value that came from a `Locale` or another version of the app carries
    /// a region or a different case, and the athlete who picked Spanish should not be answered in
    /// English because of how somebody spelled it.
    public static func of(_ tag: String?) -> VoicePack {
        guard let tag, !Records.isBlank(tag) else { return english }
        let language = DeviceLocale(languageTag: tag).language
        return all.first { $0.tag == language } ?? english
    }
}
