import XCTest
import CindyCore

/// The catalogue the picker is drawn from, and what a stored tag turns back into.
///
/// Mirrors `VoicePacksTest.kt`. Kotlin's `assertSame` on a phrasebook object becomes a check of its
/// type, since a Swift phrasebook is a value.
final class VoicePacksTests: XCTestCase {

    /// English leads and the other ten follow in the order asked for
    func testEnglishLeadsAndTheOtherTenFollowInTheOrderAskedFor() {
        XCTAssertEqual(VoicePacks.all.map { $0.tag },
                       ["en", "es", "fr", "de", "it", "pt", "nl", "pl", "ro", "tr", "ru"])
        XCTAssertEqual(VoicePacks.all.first, VoicePacks.english)
    }

    /// every pack carries its own phrasebook
    func testEveryPackCarriesItsOwnPhrasebook() {
        for pack in VoicePacks.all { XCTAssertEqual(pack.phrasebook.tag, pack.tag) }
    }

    /// tags are unique
    func testTagsAreUnique() {
        XCTAssertEqual(VoicePacks.all.count, Set(VoicePacks.all.map { $0.tag }).count)
    }

    /// every pack can be named to the athlete in both languages
    func testEveryPackCanBeNamedToTheAthleteInBothLanguages() {
        for pack in VoicePacks.all {
            XCTAssertFalse(pack.nativeName.isEmpty, "\(pack.tag) has no native name")
            XCTAssertFalse(pack.englishName.isEmpty, "\(pack.tag) has no English name")
        }
    }

    /// each pack asks the phone for the voice of its own region first
    func testEachPackAsksThePhoneForTheVoiceOfItsOwnRegionFirst() {
        XCTAssertEqual(VoicePacks.english.defaultLocale.toLanguageTag(), "en-US")
        XCTAssertEqual(VoicePacks.of("pt").defaultLocale.toLanguageTag(), "pt-BR")
        for pack in VoicePacks.all {
            XCTAssertEqual(pack.defaultLocale.language, pack.tag)
            XCTAssertEqual(pack.defaultLocale.country, pack.defaultCountry)
        }
    }

    /// a stored tag comes back as its pack
    func testAStoredTagComesBackAsItsPack() {
        XCTAssertTrue(VoicePacks.of("es").phrasebook is PhrasebookEs)
        XCTAssertTrue(VoicePacks.of("ru").phrasebook is PhrasebookRu)
    }

    /// a tag nobody has is English rather than a crash
    func testATagNobodyHasIsEnglishRatherThanACrash() {
        XCTAssertEqual(VoicePacks.of(nil), VoicePacks.english)
        XCTAssertEqual(VoicePacks.of(""), VoicePacks.english)
        XCTAssertEqual(VoicePacks.of("xx"), VoicePacks.english)
    }

    /// a region or a different case still names the language
    func testARegionOrADifferentCaseStillNamesTheLanguage() {
        XCTAssertTrue(VoicePacks.of("es-ES").phrasebook is PhrasebookEs)
        XCTAssertTrue(VoicePacks.of("ES").phrasebook is PhrasebookEs)
        XCTAssertTrue(VoicePacks.of("pt-BR").phrasebook is PhrasebookPt)
        XCTAssertTrue(VoicePacks.of("pt-PT").phrasebook is PhrasebookPt)
    }

    /// a pack refuses another language's phrasebook
    func testAPackRefusesAnotherLanguagesPhrasebook() {
        XCTAssertNil(VoicePack("es", "Español", "Spanish", "ES", PhrasebookFr()))
    }

    // MARK: - what Swift does for itself that Kotlin got from java.util.Locale

    /// the three-letter codes engines report are the ones Java's Locale gives
    func testTheThreeLetterCodesEnginesReportAreTheOnesJavasLocaleGives() {
        XCTAssertEqual(VoicePacks.all.map { $0.iso3 },
                       ["eng", "spa", "fra", "deu", "ita", "por", "nld", "pol", "ron", "tur", "rus"])
    }

    /// language tags parse as Locale.forLanguageTag does
    func testLanguageTagsParseAsLocaleForLanguageTagDoes() {
        XCTAssertEqual(DeviceLocale(languageTag: "es-US"), DeviceLocale(language: "es", country: "US"))
        XCTAssertEqual(DeviceLocale(languageTag: "ES"), DeviceLocale(language: "es"))
        XCTAssertEqual(DeviceLocale(languageTag: "zh-Hans-CN"), DeviceLocale(language: "zh", country: "CN"))
        XCTAssertEqual(DeviceLocale(languageTag: "es-419"), DeviceLocale(language: "es", country: "419"))
        // Underscores are not BCP 47, and Java reads that as no language at all.
        XCTAssertEqual(DeviceLocale(languageTag: "es_ES").language, "")
        XCTAssertEqual(DeviceLocale(languageTag: "").language, "")
        XCTAssertEqual(DeviceLocale(languageTag: "es-ES").toLanguageTag(), "es-ES")
        XCTAssertEqual(DeviceLocale(language: "").toLanguageTag(), "und")
    }
}
