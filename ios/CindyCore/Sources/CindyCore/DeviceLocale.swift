import Foundation

/// A language and, optionally, a region: the part of a locale the voice cares about.
///
/// Kotlin passes `java.util.Locale` through the voice code. Foundation's `Locale` is a much larger
/// thing, and what this code asks of it is two strings, so this is those two strings and the
/// language-tag parsing that decides them, kept free of platform types so every rule is testable.
public struct DeviceLocale: Equatable, Sendable {

    /// ISO 639 language, lower case: `es`. Empty when there is none.
    public let language: String
    /// ISO 3166 region, upper case, or empty: `ES`.
    public let country: String

    public init(language: String, country: String = "") {
        self.language = language.lowercased()
        self.country = country.uppercased()
    }

    /// `Locale.forLanguageTag`: BCP 47, subtags separated by `-`, so `es-US` and `ES` both parse
    /// and `es_ES` does not (it is one ill-formed subtag, which Java also reads as no language).
    ///
    /// Only the language and the region are kept. A script (`zh-Hans`) is skipped over and
    /// everything after the region is ignored.
    public init(languageTag tag: String) {
        let parts = tag.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        func letters(_ s: String) -> Bool { !s.isEmpty && s.unicodeScalars.allSatisfy { $0.isASCII && $0.properties.isAlphabetic } }
        func digits(_ s: String) -> Bool { !s.isEmpty && s.unicodeScalars.allSatisfy { $0.isASCII && ("0"..."9").contains($0) } }

        guard let first = parts.first, letters(first),
              (2...3).contains(first.count) || (5...8).contains(first.count) else {
            self.init(language: "")
            return
        }
        var region = ""
        for part in parts.dropFirst() {
            if part.count == 4 && letters(part) && region.isEmpty { continue }   // a script
            if (part.count == 2 && letters(part)) || (part.count == 3 && digits(part)) { region = part }
            break
        }
        self.init(language: first, country: region)
    }

    /// The device's own locale.
    public static var current: DeviceLocale {
        DeviceLocale(language: Locale.current.language.languageCode?.identifier ?? "",
                     country: Locale.current.region?.identifier ?? "")
    }

    /// English as the United States speaks it: what the engine is set to for the default voice.
    public static let us = DeviceLocale(language: "en", country: "US")

    /// `Locale.toLanguageTag`: `es-ES`, or `es` with no region, or `und` with no language.
    public func toLanguageTag() -> String {
        if language.isEmpty { return "und" }
        return country.isEmpty ? language : "\(language)-\(country)"
    }
}
