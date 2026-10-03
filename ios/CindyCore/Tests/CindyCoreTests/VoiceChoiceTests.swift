import XCTest
import CindyCore

/// Choosing a voice against the shapes real engines return.
///
/// The fixtures (`EngineFixtures`) are modelled on what the engines on Android phones actually
/// list: Google's lists hundreds of voices, installed and not, local and network, several per
/// language; Samsung's lists what is installed and little else; and some engines list nothing and
/// answer only when asked whether a language is available.
///
/// Mirrors `VoiceChoiceTest.kt`.
final class VoiceChoiceTests: XCTestCase {

    private let es = VoicePacks.of("es")
    private let ru = VoicePacks.of("ru")
    private let pl = VoicePacks.of("pl")
    private let pt = VoicePacks.of("pt")

    private let britain = EngineFixtures.britain
    private let google = EngineFixtures.google

    private func voice(
        _ name: String, _ language: String, _ country: String = "",
        installed: Bool = true, network: Bool = false, quality: Int = 400, latency: Int = 200
    ) -> EngineVoice {
        EngineFixtures.voice(name, language, country, installed: installed, network: network,
                             quality: quality, latency: latency)
    }

    // MARK: - where each language stands

    /// an installed local voice makes a language ready
    func testAnInstalledLocalVoiceMakesALanguageReady() {
        XCTAssertEqual(VoiceChoice.stateOf(es, google, nil, downloading: false), .ready)
    }

    /// a language whose local voice is not fetched can be downloaded
    func testALanguageWhoseLocalVoiceIsNotFetchedCanBeDownloaded() {
        XCTAssertEqual(VoiceChoice.stateOf(ru, google, nil, downloading: false), .downloadable)
    }

    /// a download that was asked for shows as under way until the voice arrives
    func testADownloadThatWasAskedForShowsAsUnderWayUntilTheVoiceArrives() {
        XCTAssertEqual(VoiceChoice.stateOf(ru, google, nil, downloading: true), .downloading)
        // Once it is installed the request no longer matters.
        let arrived = google.map { v -> EngineVoice in
            var v = v
            if v.name == "ru-ru-x-ruc-local" { v.installed = true }
            return v
        }
        XCTAssertEqual(VoiceChoice.stateOf(ru, arrived, nil, downloading: true), .ready)
    }

    /// a language spoken only over the network is online only
    func testALanguageSpokenOnlyOverTheNetworkIsOnlineOnly() {
        XCTAssertEqual(VoiceChoice.stateOf(pl, google, nil, downloading: false), .onlineOnly)
    }

    /// a language nobody lists is unsupported
    func testALanguageNobodyListsIsUnsupported() {
        XCTAssertEqual(VoiceChoice.stateOf(pt, google, nil, downloading: false), .unsupported)
        XCTAssertEqual(VoiceChoice.stateOf(pt, [], nil, downloading: false), .unsupported)
    }

    /// a voice list is trusted over the availability codes
    func testAVoiceListIsTrustedOverTheAvailabilityCodes() {
        // The engine claims Polish is available because it can reach a network voice. It is not
        // something to count a workout with.
        XCTAssertEqual(VoiceChoice.stateOf(pl, google, .available, downloading: false), .onlineOnly)
    }

    /// an engine that lists no voice for a language is asked instead
    func testAnEngineThatListsNoVoiceForALanguageIsAskedInstead() {
        let listsNothing = [voice("en-US-language", "en", "US")]
        XCTAssertEqual(VoiceChoice.stateOf(es, listsNothing, .available, downloading: false), .ready)
        XCTAssertEqual(VoiceChoice.stateOf(es, listsNothing, .missingData, downloading: false), .downloadable)
        XCTAssertEqual(VoiceChoice.stateOf(es, listsNothing, .missingData, downloading: true), .downloading)
        XCTAssertEqual(VoiceChoice.stateOf(es, listsNothing, .notSupported, downloading: false), .unsupported)
        XCTAssertEqual(VoiceChoice.stateOf(es, listsNothing, nil, downloading: false), .unsupported)
    }

    // MARK: - which voice counts a workout

    /// a workout is counted with an installed local voice
    func testAWorkoutIsCountedWithAnInstalledLocalVoice() {
        XCTAssertEqual(VoiceChoice.bestForWorkout(es, google, britain)?.name, "es-es-x-eea-local")
    }

    /// a network voice never counts a workout
    func testANetworkVoiceNeverCountsAWorkout() {
        XCTAssertNil(VoiceChoice.bestForWorkout(pl, google, britain))
    }

    /// a voice that has not been fetched never counts a workout
    func testAVoiceThatHasNotBeenFetchedNeverCountsAWorkout() {
        XCTAssertNil(VoiceChoice.bestForWorkout(ru, google, britain))
    }

    /// nothing is chosen from an engine that lists nothing
    func testNothingIsChosenFromAnEngineThatListsNothing() {
        XCTAssertNil(VoiceChoice.bestForWorkout(es, [], britain))
    }

    /// the phone's own region wins when it is the same language
    func testThePhonesOwnRegionWinsWhenItIsTheSameLanguage() {
        // A phone set to Spanish in the United States is answered in that voice, not Spain's.
        let spanishInTheUs = DeviceLocale(languageTag: "es-US")
        XCTAssertEqual(VoiceChoice.bestForWorkout(es, google, spanishInTheUs)?.name, "es-us-x-sfb-local")
    }

    /// the pack's own region is next
    func testThePacksOwnRegionIsNext() {
        XCTAssertEqual(VoiceChoice.bestForWorkout(es, google, britain)?.country, "ES")
    }

    /// a phone set to another language does not sway the choice
    func testAPhoneSetToAnotherLanguageDoesNotSwayTheChoice() {
        // A Russian phone with a Spanish workout: its region is not a hint about Spanish.
        XCTAssertEqual(VoiceChoice.bestForWorkout(es, google, DeviceLocale(languageTag: "ru-RU"))?.country, "ES")
    }

    /// then the faster voice, then the better one, then the name
    func testThenTheFasterVoiceThenTheBetterOneThenTheName() {
        let fast = voice("es-es-b", "es", "ES", quality: 300, latency: 100)
        let slow = voice("es-es-a", "es", "ES", quality: 500, latency: 300)
        XCTAssertEqual(VoiceChoice.bestForWorkout(es, [slow, fast], britain)?.name, "es-es-b")

        let better = voice("es-es-b", "es", "ES", quality: 500)
        let worse = voice("es-es-a", "es", "ES", quality: 300)
        XCTAssertEqual(VoiceChoice.bestForWorkout(es, [worse, better], britain)?.name, "es-es-b")

        let second = voice("es-es-b", "es", "ES")
        let first = voice("es-es-a", "es", "ES")
        XCTAssertEqual(VoiceChoice.bestForWorkout(es, [second, first], britain)?.name, "es-es-a")
    }

    /// regions compare without regard to case
    func testRegionsCompareWithoutRegardToCase() {
        let lower = voice("es-es-x", "es", "es")
        XCTAssertEqual(VoiceChoice.bestForWorkout(es, [lower], britain)?.name, "es-es-x")
    }

    /// a three letter language code is still Spanish
    func testAThreeLetterLanguageCodeIsStillSpanish() {
        let samsung = voice("spa-ESP-language", "spa", "ESP")
        XCTAssertEqual(VoiceChoice.bestForWorkout(es, [samsung], britain)?.name, "spa-ESP-language")
    }

    /// English is chosen like any other language
    func testEnglishIsChosenLikeAnyOtherLanguage() {
        XCTAssertEqual(VoiceChoice.bestForWorkout(VoicePacks.english, google, britain)?.name, "en-us-x-tpd-local")
    }

    // MARK: - which voice to fetch, and which to preview with

    /// the voice to fetch is a local one that has not been
    func testTheVoiceToFetchIsALocalOneThatHasNotBeen() {
        XCTAssertEqual(VoiceChoice.bestToDownload(ru, google, britain)?.name, "ru-ru-x-ruc-local")
        XCTAssertEqual(VoiceChoice.bestToDownload(es, google, britain)?.name, "es-us-x-esc-local")
    }

    /// there is nothing to fetch for a language that is only online or not offered
    func testThereIsNothingToFetchForALanguageThatIsOnlyOnlineOrNotOffered() {
        XCTAssertNil(VoiceChoice.bestToDownload(pl, google, britain))
        XCTAssertNil(VoiceChoice.bestToDownload(pt, google, britain))
    }

    /// a preview uses the voice a workout would, if there is one
    func testAPreviewUsesTheVoiceAWorkoutWouldIfThereIsOne() {
        XCTAssertEqual(VoiceChoice.bestForPreview(es, google, britain)?.name, "es-es-x-eea-local")
    }

    /// a preview falls back to a network voice so a language can be heard before it is fetched
    func testAPreviewFallsBackToANetworkVoiceSoALanguageCanBeHeardBeforeItIsFetched() {
        XCTAssertEqual(VoiceChoice.bestForPreview(ru, google, britain)?.name, "ru-ru-x-ruc-network")
        XCTAssertEqual(VoiceChoice.bestForPreview(pl, google, britain)?.name, "pl-pl-x-oda-network")
    }

    /// a language nothing speaks cannot be previewed
    func testALanguageNothingSpeaksCannotBePreviewed() {
        XCTAssertNil(VoiceChoice.bestForPreview(pt, google, britain))
    }
}
