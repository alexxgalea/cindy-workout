import XCTest
import CindyCore

/// The speaker's decisions, driven against an engine that does what real ones do.
///
/// The rule under all of them is that the words and the voice agree: what is said is worded by
/// the phrasebook of the voice actually in use, so a language the phone cannot speak is answered
/// in English, whole, and not in a foreign voice reading the wrong sentences.
///
/// Mirrors `VoiceDirectorTest.kt`.
final class VoiceDirectorTests: XCTestCase {

    private let en = VoicePacks.english
    private let es = VoicePacks.of("es")
    private let ru = VoicePacks.of("ru")
    private let pt = VoicePacks.of("pt")

    private let engine = FakeTtsEngine()
    private var clock: Int64 = 0
    private var director: VoiceDirector!

    override func setUp() {
        director = VoiceDirector(engine: engine, device: { EngineFixtures.britain }, now: { [unowned self] in self.clock })
    }

    private func googlePhone() { engine.likeGoogle() }

    private func saidFor(_ line: VoiceLine) -> String {
        director.speak(line, queue: .append, volume: 1)
        return engine.said.last!.text
    }

    // MARK: - the engine's readiness

    /// nothing is asked of the engine before it is ready
    func testNothingIsAskedOfTheEngineBeforeItIsReady() {
        googlePhone()
        director.choose(es)
        XCTAssertEqual(engine.calls, [])
        XCTAssertFalse(director.ready)
    }

    /// a failed engine is never asked anything
    func testAFailedEngineIsNeverAskedAnything() {
        engine.becomeReady(success: false)
        director.choose(es)
        XCTAssertEqual(engine.calls, [])
        XCTAssertFalse(director.ready)
    }

    /// readiness is passed on
    func testReadinessIsPassedOn() {
        var told: Bool?
        director.whenReady = { told = $0 }
        engine.becomeReady(success: false)
        XCTAssertEqual(told, false)
        engine.becomeReady(success: true)
        XCTAssertEqual(told, true)
    }

    /// English is the engine's own US voice, as it always was
    func testEnglishIsTheEnginesOwnUSVoiceAsItAlwaysWas() {
        googlePhone()
        engine.becomeReady()
        XCTAssertEqual(engine.calls, ["setLanguage:en-US"])
        XCTAssertEqual(director.using, en)
        XCTAssertFalse(director.fallingBack)
    }

    /// English is not a fall-back before the engine has answered
    func testEnglishIsNotAFallBackBeforeTheEngineHasAnswered() {
        // Until then it is only where everything starts. Calling it a fall-back would tell
        // someone whose Spanish voice is installed that it isn't.
        googlePhone()
        director.choose(es)
        XCTAssertFalse(director.fallingBack)

        engine.becomeReady()
        XCTAssertFalse(director.fallingBack)
        XCTAssertEqual(director.using, es)
    }

    /// an engine that never connects is not a fall-back either
    func testAnEngineThatNeverConnectsIsNotAFallBackEither() {
        director.choose(es)
        engine.becomeReady(success: false)
        XCTAssertFalse(director.fallingBack)
    }

    /// a language chosen before the engine is ready is applied when it is
    func testALanguageChosenBeforeTheEngineIsReadyIsAppliedWhenItIs() {
        googlePhone()
        director.choose(es)
        engine.becomeReady()
        XCTAssertEqual(director.using, es)
        XCTAssertEqual(engine.calls, ["setLanguage:es-ES"])
    }

    // MARK: - choosing the voice

    /// the engine's own choice for a language is kept when it can count a workout
    func testTheEnginesOwnChoiceForALanguageIsKeptWhenItCanCountAWorkout() {
        googlePhone()
        engine.becomeReady()
        director.choose(es)
        // Asked for the language and nothing else, so the voice set in the system settings stands.
        XCTAssertEqual(engine.calls, ["setLanguage:en-US", "setLanguage:es-ES"])
        XCTAssertEqual(director.using, es)
        XCTAssertFalse(director.fallingBack)
    }

    /// a network voice the engine defaults to is replaced with a local one
    func testANetworkVoiceTheEngineDefaultsToIsReplacedWithALocalOne() {
        googlePhone()
        engine.defaults["es-ES"] = "es-es-x-eea-network"
        engine.becomeReady()
        director.choose(es)
        XCTAssertEqual(engine.calls,
                       ["setLanguage:en-US", "setLanguage:es-ES", "setVoice:es-es-x-eea-local"])
        XCTAssertEqual(director.using, es)
    }

    /// a voice installed under another region is used when the default region is not
    func testAVoiceInstalledUnderAnotherRegionIsUsedWhenTheDefaultRegionIsNot() {
        engine.listed = [EngineFixtures.voice("es-us-x-sfb-local", "es", "US")]
        engine.answers["es-ES"] = .missingData
        engine.becomeReady()
        director.choose(es)
        XCTAssertEqual(engine.calls.last, "setVoice:es-us-x-sfb-local")
        XCTAssertEqual(director.using, es)
    }

    /// an engine that lists no voices is asked whether it speaks the language
    func testAnEngineThatListsNoVoicesIsAskedWhetherItSpeaksTheLanguage() {
        engine.listed = []
        engine.answers["es-ES"] = .available
        engine.answers["ru-RU"] = .missingData
        engine.becomeReady()

        director.choose(es)
        XCTAssertEqual(director.using, es)
        XCTAssertEqual(engine.calls.last, "setLanguage:es-ES")

        director.choose(ru)
        XCTAssertEqual(director.using, en)
    }

    // MARK: - the words follow the voice

    /// what is said is worded for the voice in use
    func testWhatIsSaidIsWordedForTheVoiceInUse() {
        googlePhone()
        engine.becomeReady()
        director.choose(es)
        let id = director.speak(.movement(.squat), queue: .append, volume: 0.5)
        XCTAssertEqual(engine.said.count, 1)
        XCTAssertEqual(engine.said[0], FakeTtsEngine.Said(text: "sentadillas", queue: .append, volume: 0.5, id: id))
    }

    /// a language the phone cannot speak is answered in English and remembered
    func testALanguageThePhoneCannotSpeakIsAnsweredInEnglishAndRemembered() {
        googlePhone()
        engine.becomeReady()
        director.choose(ru)

        XCTAssertEqual(director.wanted, ru)
        XCTAssertEqual(director.using, en)
        XCTAssertTrue(director.fallingBack)
        // The engine is left on English, not on a Russian voice that cannot speak yet.
        XCTAssertEqual(engine.calls.last, "setLanguage:en-US")
        XCTAssertEqual(saidFor(.movement(.pushup)), "push ups")
    }

    /// it takes over as soon as the voice arrives
    func testItTakesOverAsSoonAsTheVoiceArrives() {
        googlePhone()
        engine.becomeReady()
        director.choose(ru)
        XCTAssertTrue(director.fallingBack)

        engine.listed = EngineFixtures.google.map { v in
            var v = v
            if v.name == "ru-ru-x-ruc-local" { v.installed = true }
            return v
        }
        engine.answers["ru-RU"] = .available
        engine.defaults["ru-RU"] = "ru-ru-x-ruc-local"
        director.refresh()

        XCTAssertEqual(director.using, ru)
        XCTAssertFalse(director.fallingBack)
        XCTAssertEqual(saidFor(.movement(.pushup)), "отжимания")
    }

    /// asking again for the language already spoken costs the engine nothing
    func testAskingAgainForTheLanguageAlreadySpokenCostsTheEngineNothing() {
        googlePhone()
        engine.becomeReady()
        director.choose(es)
        let before = engine.calls
        director.choose(es)
        XCTAssertEqual(engine.calls, before)
    }

    /// asking again for a language that fell back is a retry
    func testAskingAgainForALanguageThatFellBackIsARetry() {
        googlePhone()
        engine.becomeReady()
        director.choose(ru)
        let before = engine.calls.count
        director.choose(ru)
        XCTAssertGreaterThan(engine.calls.count, before, "no retry was made")
    }

    /// refreshing changes nothing when there is nothing to fix
    func testRefreshingChangesNothingWhenThereIsNothingToFix() {
        googlePhone()
        engine.becomeReady()
        director.choose(es)
        let before = engine.calls
        director.refresh()
        XCTAssertEqual(engine.calls, before)
    }

    // MARK: - previewing

    /// a preview is the sample in the language, in a voice for it
    func testAPreviewIsTheSampleInTheLanguageInAVoiceForIt() {
        googlePhone()
        engine.becomeReady()
        director.choose(es)

        XCTAssertTrue(director.preview(ru, volume: 1) { _ in })
        // Russian is not fetched, so the only voice that can play it is the online one.
        XCTAssertEqual(engine.calls.last, "setVoice:ru-ru-x-ruc-network")
        XCTAssertEqual(engine.said.last?.text, "Три. Четыре. Пять. Отжимания.")
        XCTAssertEqual(engine.said.last?.queue, .replace)
    }

    /// a preview uses the local voice when there is one
    func testAPreviewUsesTheLocalVoiceWhenThereIsOne() {
        googlePhone()
        engine.becomeReady()
        XCTAssertTrue(director.preview(es, volume: 1) { _ in })
        XCTAssertEqual(engine.calls.last, "setVoice:es-es-x-eea-local")
    }

    /// a preview leaves the chosen language as it was
    func testAPreviewLeavesTheChosenLanguageAsItWas() {
        googlePhone()
        engine.becomeReady()
        director.choose(es)
        _ = director.preview(ru, volume: 1) { _ in }

        // The next thing the workout says puts the athlete's own voice back first.
        let spoken = saidFor(.movement(.pushup))
        XCTAssertEqual(spoken, "flexiones")
        XCTAssertEqual(engine.calls.last, "setLanguage:es-ES")
        XCTAssertEqual(director.using, es)
    }

    /// a preview that cannot reach the network says so, once, for its own utterance
    func testAPreviewThatCannotReachTheNetworkSaysSoOnceForItsOwnUtterance() {
        googlePhone()
        engine.becomeReady()
        var failure: SpeechFailure?
        _ = director.preview(ru, volume: 1) { failure = $0 }
        let id = engine.said.last!.id

        engine.listener!.onError("someone-else", .network)
        XCTAssertNil(failure)

        engine.listener!.onError(id, .network)
        XCTAssertEqual(failure, .network)

        failure = nil
        engine.listener!.onError(id, .network)
        XCTAssertNil(failure, "reported a second time")
    }

    /// a preview of a language nothing speaks is refused
    func testAPreviewOfALanguageNothingSpeaksIsRefused() {
        googlePhone()
        engine.becomeReady()
        XCTAssertFalse(director.preview(pt, volume: 1) { _ in })
        XCTAssertEqual(engine.said, [])
    }

    /// a refused preview still puts the engine back before the next thing is said
    func testARefusedPreviewStillPutsTheEngineBackBeforeTheNextThingIsSaid() {
        // It cannot be known what a refusal left behind, so the engine is not trusted to still
        // be on the athlete's voice.
        googlePhone()
        engine.becomeReady()
        director.choose(es)
        _ = director.preview(pt, volume: 1) { _ in }
        let before = engine.calls.count

        _ = saidFor(.movement(.squat))
        XCTAssertEqual(engine.calls[before], "setLanguage:es-ES")
    }

    /// a preview that is cut off lets go of its callback
    func testAPreviewThatIsCutOffLetsGoOfItsCallback() {
        googlePhone()
        engine.becomeReady()
        var failure: SpeechFailure?
        _ = director.preview(ru, volume: 1) { failure = $0 }
        let id = engine.said.last!.id

        engine.listener!.onStop(id)
        engine.listener!.onError(id, .network)
        XCTAssertNil(failure, "called after the preview was cut off")
    }

    /// an utterance being cut off does not let the music swell between counts
    func testAnUtteranceBeingCutOffDoesNotLetTheMusicSwellBetweenCounts() {
        var seen: [Bool] = []
        director.whenSpeaking = { seen.append($0) }
        engine.becomeReady()
        engine.listener!.onStart("a")
        engine.listener!.onStop("a")
        engine.listener!.onStart("b")
        XCTAssertEqual(seen, [true, true])
    }

    /// a preview before the engine is ready is refused
    func testAPreviewBeforeTheEngineIsReadyIsRefused() {
        googlePhone()
        XCTAssertFalse(director.preview(es, volume: 1) { _ in })
    }

    // MARK: - downloading

    /// a download asks for the voice that has not been fetched, then puts the engine back
    func testADownloadAsksForTheVoiceThatHasNotBeenFetchedThenPutsTheEngineBack() {
        googlePhone()
        engine.becomeReady()
        director.choose(es)
        clock = 1_000

        XCTAssertEqual(director.download(ru), .asked)

        let calls = engine.calls
        XCTAssertEqual(calls[calls.count - 2], "setVoice:ru-ru-x-ruc-local")
        XCTAssertEqual(calls.last, "setLanguage:es-ES")
        XCTAssertEqual(director.states()["ru"], .downloading)

        clock = 61_000
        XCTAssertEqual(director.downloadingFor("ru"), 60_000)
    }

    /// a download reports success even when the engine says the voice failed to set
    func testADownloadReportsSuccessEvenWhenTheEngineSaysTheVoiceFailedToSet() {
        // Setting a voice whose data is missing is what asks for it, and engines answer "error"
        // while the request goes through.
        googlePhone()
        engine.refused.insert("ru-ru-x-ruc-local")
        engine.becomeReady()
        XCTAssertEqual(director.download(ru), .asked)
        XCTAssertEqual(director.states()["ru"], .downloading)
    }

    /// with no voice to set, the engine's own screen is the only way to ask
    func testWithNoVoiceToSetTheEnginesOwnScreenIsTheOnlyWayToAsk() {
        // The engine says the data is missing but lists nothing to set, and setting a language
        // does not fetch anything. Claiming a download was asked for would leave the athlete
        // watching "downloading" for something nobody requested.
        engine.listed = []
        engine.answers["ru-RU"] = .missingData
        engine.becomeReady()
        let before = engine.calls

        XCTAssertEqual(director.download(ru), .useEngineScreen)
        XCTAssertEqual(engine.calls, before, "the engine was touched")
        XCTAssertNil(director.downloadingFor("ru"))
        XCTAssertEqual(director.states()["ru"], .downloadable)
    }

    /// there is nothing to ask for when the engine does not offer the language
    func testThereIsNothingToAskForWhenTheEngineDoesNotOfferTheLanguage() {
        googlePhone()
        engine.becomeReady()
        XCTAssertEqual(director.download(pt), .notOffered)
        XCTAssertNil(director.downloadingFor("pt"))
    }

    /// a download that has arrived is forgotten
    func testADownloadThatHasArrivedIsForgotten() {
        googlePhone()
        engine.becomeReady()
        _ = director.download(ru)

        engine.listed = EngineFixtures.google.map { v in
            var v = v
            if v.name == "ru-ru-x-ruc-local" { v.installed = true }
            return v
        }
        XCTAssertEqual(director.states()["ru"], .ready)
        XCTAssertNil(director.downloadingFor("ru"))
    }

    // MARK: - what is on the phone

    /// every language is accounted for, in the order they are listed
    func testEveryLanguageIsAccountedForInTheOrderTheyAreListed() {
        googlePhone()
        engine.becomeReady()
        let states = director.states()

        XCTAssertEqual(states.tags, VoicePacks.all.map { $0.tag })
        XCTAssertEqual(states["en"], .ready)
        XCTAssertEqual(states["es"], .ready)
        XCTAssertEqual(states["ru"], .downloadable)
        XCTAssertEqual(states["pl"], .onlineOnly)
        XCTAssertEqual(states["pt"], .unsupported)
    }

    // MARK: - the speaking hooks

    /// speech starting and stopping is passed on
    func testSpeechStartingAndStoppingIsPassedOn() {
        var seen: [Bool] = []
        director.whenSpeaking = { seen.append($0) }
        engine.becomeReady()

        engine.listener!.onStart("a")
        engine.listener!.onDone("a")
        engine.listener!.onStart("b")
        engine.listener!.onError("b", .other)
        XCTAssertEqual(seen, [true, false, true, false])
    }
}
