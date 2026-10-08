import XCTest
import CindyCore

/// Written for the port. `AndroidTtsEngineTest` holds the translation of Android's constants
/// (voice features, availability codes, error codes) with Robolectric's engine; on iOS the same
/// translation is `AppleVoiceMapping`, held to what it means here. The engine around it,
/// `AVSpeechTtsEngine`, needs a device and is built by the macOS job.
final class AppleVoiceMappingTests: XCTestCase {

    /// a voice is described by its identifier, language and region
    func testAVoiceIsDescribedByItsIdentifierLanguageAndRegion() {
        let v = AppleVoiceMapping.engineVoice(identifier: "com.apple.voice.compact.es-ES.Monica",
                                              languageTag: "es-ES", quality: .standard)
        XCTAssertEqual(v, EngineVoice(name: "com.apple.voice.compact.es-ES.Monica", language: "es",
                                      country: "ES", installed: true, network: false, quality: 300,
                                      latency: AppleVoiceMapping.latency))
    }

    /// no voice is listed unless it is installed, and none runs online
    func testNoVoiceIsListedUnlessItIsInstalledAndNoneRunsOnline() {
        for q in AppleVoiceQuality.allCases {
            let v = AppleVoiceMapping.engineVoice(identifier: "x", languageTag: "en-GB", quality: q)
            XCTAssertTrue(v.installed)
            XCTAssertFalse(v.network)
        }
    }

    /// better voices rank higher
    func testBetterVoicesRankHigher() {
        XCTAssertTrue(AppleVoiceMapping.quality(.standard) < AppleVoiceMapping.quality(.enhanced))
        XCTAssertTrue(AppleVoiceMapping.quality(.enhanced) < AppleVoiceMapping.quality(.premium))
        XCTAssertTrue((100...500).contains(AppleVoiceMapping.quality(.standard)))
        XCTAssertTrue((100...500).contains(AppleVoiceMapping.quality(.premium)))
    }

    /// a language with no region, or with a script, is still the language
    func testALanguageWithNoRegionOrWithAScriptIsStillTheLanguage() {
        XCTAssertEqual(AppleVoiceMapping.engineVoice(identifier: "a", languageTag: "es", quality: .standard).country, "")
        let v = AppleVoiceMapping.engineVoice(identifier: "b", languageTag: "zh-Hans-CN", quality: .standard)
        XCTAssertEqual(v.language, "zh")
        XCTAssertEqual(v.country, "CN")
    }

    /// availability comes down to the language, in any region
    func testAvailabilityComesDownToTheLanguageInAnyRegion() {
        let tags = ["es-ES", "en-US"]
        XCTAssertEqual(AppleVoiceMapping.availability(ofVoiceLanguages: tags, for: DeviceLocale(languageTag: "es-ES")), .available)
        // The language without that region is still the language.
        XCTAssertEqual(AppleVoiceMapping.availability(ofVoiceLanguages: tags, for: DeviceLocale(languageTag: "es-MX")), .available)
        XCTAssertEqual(AppleVoiceMapping.availability(ofVoiceLanguages: tags, for: DeviceLocale(languageTag: "ru-RU")), .notSupported)
        XCTAssertEqual(AppleVoiceMapping.availability(ofVoiceLanguages: [], for: DeviceLocale(languageTag: "en-US")), .notSupported)
    }
}
