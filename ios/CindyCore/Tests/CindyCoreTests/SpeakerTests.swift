import XCTest
import CindyCore

/// Mirrors `SpeakerTest.kt`: the switches, the main thread and the background one.
///
/// The decisions themselves are `VoiceDirectorTests`'. What is held here is what only exists around
/// them: that nothing is said before the engine is ready or while the voice is off, that a
/// language's answer to "where do you stand" reaches the screen on the main thread and only while
/// the screen is still there.
///
/// The last Kotlin test, which drives the real Android engine, has no counterpart: `AVSpeechTtsEngine`
/// needs a device. Its translation is `AppleVoiceMapping`, tested on its own.
final class SpeakerTests: XCTestCase {

    private let engine = FakeTtsEngine()
    private let loop = TestLoop()

    /// A speaker on the fake engine, whose background work runs where it is asked to.
    private func speaker(background: @escaping Dispatcher = { $0() }, now: @escaping () -> Int64 = { 0 }) -> Speaker {
        Speaker(engine: engine, background: background, main: loop.main, now: now)
    }

    // MARK: saying things

    /// nothing is said before the engine is ready
    func testNothingIsSaidBeforeTheEngineIsReady() {
        let speaker = speaker()
        speaker.say(.count(reps: 3))
        XCTAssertEqual(engine.said, [])

        engine.becomeReady()
        speaker.say(.count(reps: 3))
        XCTAssertEqual(engine.said.map { $0.text }, ["3"])
    }

    /// say replaces what is being said and queue waits behind it
    func testSayReplacesWhatIsBeingSaidAndQueueWaitsBehindIt() {
        let speaker = speaker()
        engine.becomeReady()
        speaker.say(.count(reps: 3))
        speaker.queue(.movement(.pushup))
        XCTAssertEqual(engine.said.map { $0.queue }, [.replace, .append])
    }

    /// a voice that is switched off says nothing, except to be previewed
    func testAVoiceThatIsSwitchedOffSaysNothingExceptToBePreviewed() {
        let speaker = speaker()
        engine.becomeReady()
        speaker.enabled = false

        speaker.say(.count(reps: 3))
        speaker.queue(.count(reps: 4))
        XCTAssertEqual(engine.said, [])

        speaker.preview(.volumeCheck)
        XCTAssertEqual(engine.said.map { $0.text }, ["Three"])
    }

    /// the volume is held between nought and one and travels with each utterance
    func testTheVolumeIsHeldBetweenNoughtAndOneAndTravelsWithEachUtterance() {
        let speaker = speaker()
        engine.becomeReady()
        speaker.volume = 3
        speaker.say(.count(reps: 1))
        speaker.volume = -1
        speaker.say(.count(reps: 2))
        XCTAssertEqual(engine.said.map { $0.volume }, [1, 0])
    }

    /// speech starting and stopping reaches whoever is ducking the music
    func testSpeechStartingAndStoppingReachesWhoeverIsDuckingTheMusic() {
        let speaker = speaker()
        var seen: [Bool] = []
        speaker.onSpeakingChanged = { seen.append($0) }
        engine.becomeReady()

        engine.listener!.onStart("a")
        engine.listener!.onDone("a")
        XCTAssertEqual(seen, [true, false])
    }

    /// stopping stops the engine
    func testStoppingStopsTheEngine() {
        let speaker = speaker()
        speaker.stop()
        XCTAssertTrue(engine.calls.contains("stop"))
    }

    // MARK: the language

    /// what is said follows the language chosen
    func testWhatIsSaidFollowsTheLanguageChosen() {
        engine.likeGoogle()
        let speaker = speaker()
        engine.becomeReady()
        speaker.language = "es"

        speaker.say(.movement(.squat))
        XCTAssertEqual(engine.said.last?.text, "sentadillas")
        XCTAssertFalse(speaker.fallingBack)
    }

    /// a language the phone lacks is answered in English, and said to be
    func testALanguageThePhoneLacksIsAnsweredInEnglishAndSaidToBe() {
        engine.likeGoogle()
        let speaker = speaker()
        engine.becomeReady()
        speaker.language = "ru"

        XCTAssertTrue(speaker.fallingBack)
        XCTAssertEqual(speaker.wanted.tag, "ru")
        speaker.say(.movement(.pushup))
        XCTAssertEqual(engine.said.last?.text, "push ups")
    }

    /// refreshing picks up a voice that has arrived
    func testRefreshingPicksUpAVoiceThatHasArrived() {
        engine.likeGoogle()
        let speaker = speaker()
        engine.becomeReady()
        speaker.language = "ru"
        XCTAssertTrue(speaker.fallingBack)

        engine.listed = EngineFixtures.google.map { v in
            var v = v
            if v.name == "ru-ru-x-ruc-local" { v.installed = true }
            return v
        }
        engine.answers["ru-RU"] = .available
        engine.defaults["ru-RU"] = "ru-ru-x-ruc-local"
        speaker.refresh()

        XCTAssertFalse(speaker.fallingBack)
        speaker.say(.movement(.pushup))
        XCTAssertEqual(engine.said.last?.text, "отжимания")
    }

    /// English before the engine answers is not reported as a fall-back
    func testEnglishBeforeTheEngineAnswersIsNotReportedAsAFallBack() {
        engine.likeGoogle()
        let speaker = speaker()
        speaker.language = "es"
        XCTAssertFalse(speaker.fallingBack)
    }

    /// a tag nobody has is English
    func testATagNobodyHasIsEnglish() {
        engine.likeGoogle()
        let speaker = speaker()
        engine.becomeReady()
        speaker.language = "klingon"
        XCTAssertEqual(speaker.language, "en")
        XCTAssertFalse(speaker.fallingBack)
    }

    // MARK: what is on the phone

    /// where each language stands arrives on the main thread
    func testWhereEachLanguageStandsArrivesOnTheMainThread() {
        engine.likeGoogle()
        let speaker = speaker()
        engine.becomeReady()

        var states: PackStates?
        speaker.packStates { states = $0 }
        XCTAssertNil(states, "delivered before the main thread got to it")

        loop.idle()
        XCTAssertNotNil(states)
        XCTAssertEqual(states?["es"], .ready)
        XCTAssertEqual(states?["ru"], .downloadable)
    }

    /// nothing is reported before the engine has answered
    func testNothingIsReportedBeforeTheEngineHasAnswered() {
        // An engine that has not connected lists no voices. Reporting that would say the phone
        // speaks nothing but English, for as long as the engine took to start.
        engine.likeGoogle()
        let speaker = speaker()

        var states: PackStates?
        speaker.packStates { states = $0 }
        loop.idle()
        XCTAssertNil(states)

        engine.becomeReady()
        speaker.packStates { states = $0 }
        loop.idle()
        XCTAssertNotNil(states)
    }

    /// nothing is delivered to a screen that has gone
    func testNothingIsDeliveredToAScreenThatHasGone() {
        engine.likeGoogle()
        let speaker = speaker()
        engine.becomeReady()

        var states: PackStates?
        speaker.packStates { states = $0 }
        speaker.shutdown()
        loop.idle()
        XCTAssertNil(states)

        // And a request made after the screen has gone is not made at all.
        speaker.packStates { states = $0 }
        loop.idle()
        XCTAssertNil(states)
    }

    /// a question is not asked again while the last is still out
    func testAQuestionIsNotAskedAgainWhileTheLastIsStillOut() {
        engine.likeGoogle()
        var queued: [() -> Void] = []
        let speaker = speaker(background: { queued.append($0) })
        engine.becomeReady()

        var delivered = 0
        for _ in 0..<3 { speaker.packStates { _ in delivered += 1 } }
        XCTAssertEqual(queued.count, 1, "three questions asked, one waiting its turn")

        queued.removeFirst()()
        loop.idle()
        XCTAssertEqual(delivered, 1, "only the one that was asked is answered")

        speaker.packStates { _ in delivered += 1 }
        XCTAssertEqual(queued.count, 1, "free to ask again once answered")
    }

    /// an engine that answers nothing at first does not stop the questions after it
    ///
    /// Kotlin's engine could throw from `getVoices`; a Swift `TtsEngine` cannot, so the engine that
    /// "fails" here lists no voices, which is how a failing engine answers.
    func testAnEngineThatAnswersNothingAtFirstDoesNotStopTheQuestionsAfterIt() {
        engine.listed = []
        let speaker = speaker()
        engine.becomeReady()

        var answers: [PackStates] = []
        speaker.packStates { answers.append($0) }
        loop.idle()
        XCTAssertEqual(answers.count, 1)
        XCTAssertEqual(answers[0]["es"], .unsupported)

        engine.likeGoogle()
        speaker.packStates { answers.append($0) }
        loop.idle()
        XCTAssertEqual(answers.count, 2, "the question that came first left the way blocked")
        XCTAssertEqual(answers[1]["es"], .ready)
    }

    /// a download is asked for and timed
    func testADownloadIsAskedForAndTimed() {
        engine.likeGoogle()
        let speaker = speaker()
        engine.becomeReady()
        XCTAssertEqual(speaker.download(VoicePacks.of("ru")), .asked)
        XCTAssertNotNil(speaker.downloadingFor("ru"))
        XCTAssertNil(speaker.downloadingFor("es"))
    }

    /// a download is timed from when it was asked for
    func testADownloadIsTimedFromWhenItWasAskedFor() {
        engine.likeGoogle()
        var clock: Int64 = 1_000
        let speaker = speaker(now: { clock })
        engine.becomeReady()
        _ = speaker.download(VoicePacks.of("ru"))

        clock += 90_000
        XCTAssertEqual(speaker.downloadingFor("ru"), 90_000)
    }

    // MARK: previewing

    /// a language nothing speaks cannot be previewed, and that is said at once
    func testALanguageNothingSpeaksCannotBePreviewedAndThatIsSaidAtOnce() {
        engine.likeGoogle()
        let speaker = speaker()
        engine.becomeReady()

        var failure: SpeechFailure?
        let started = speaker.previewPack(VoicePacks.of("pt")) { failure = $0 }
        XCTAssertEqual(failure, .unavailable)
        XCTAssertFalse(started, "said to have started, with the failure already reported")
    }

    /// a preview before the engine is ready is refused, and that is said at once
    func testAPreviewBeforeTheEngineIsReadyIsRefusedAndThatIsSaidAtOnce() {
        engine.likeGoogle()
        let speaker = speaker()

        var failure: SpeechFailure?
        let started = speaker.previewPack(VoicePacks.of("es")) { failure = $0 }
        XCTAssertEqual(failure, .unavailable)
        XCTAssertFalse(started)
        XCTAssertEqual(engine.said, [])
    }

    /// a preview that fails later says so on the main thread
    func testAPreviewThatFailsLaterSaysSoOnTheMainThread() {
        engine.likeGoogle()
        let speaker = speaker()
        engine.becomeReady()

        var failure: SpeechFailure?
        let started = speaker.previewPack(VoicePacks.of("ru")) { failure = $0 }
        XCTAssertNil(failure)
        XCTAssertTrue(started, "reported as not started, though it was")

        engine.listener!.onError(engine.said.last!.id, .network)
        XCTAssertNil(failure, "reported off the main thread")
        loop.idle()
        XCTAssertEqual(failure, .network)
    }
}
