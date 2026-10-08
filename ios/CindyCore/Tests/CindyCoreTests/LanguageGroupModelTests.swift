import XCTest
import CindyCore

/// Mirrors `LanguageGroupTest.kt`: the language list, driven the way a thumb drives it: tap a row,
/// tap play, wait, look again.
///
/// The speaker behind it is a real one on a fake engine that behaves like Google's, so what is
/// checked is the list's whole conversation with the phone (what it says while the engine is still
/// answering, what a tap on each kind of row does, how it hears about a voice arriving) and not
/// just how it is drawn. The rows are the model's `Row`s; the Kotlin test found them by their
/// spoken description, and these find them by language and read the same description.
final class LanguageGroupModelTests: XCTestCase {

    private let engine = FakeTtsEngine()
    private let loop = TestLoop()
    private var toasts: [String] = []
    private var installerOpened = 0

    /// How many questions have reached the background thread.
    private var dispatched = 0
    private var delays: [Int64] = []
    private var speaker: Speaker!

    /// A list on a speaker that runs its background work where it is asked to.
    private func group(initial: String = "en", on: TtsEngine? = nil,
                       now: (() -> Int64)? = nil) -> LanguageGroupModel {
        speaker = Speaker(engine: on ?? engine, background: { [unowned self] in dispatched += 1; $0() },
                          main: loop.main, now: now ?? { [unowned self] in loop.nowMs })
        return LanguageGroupModel(
            speaker: speaker, initial: initial, toast: { [unowned self] in toasts.append($0) },
            openEngineScreen: { [unowned self] in installerOpened += 1 },
            elapsedMs: { [unowned self] in loop.nowMs },
            schedule: { [unowned self] ms, work in delays.append(ms); return loop.scheduler(ms, work) })
    }

    /// The phone's engine connects, and the list starts looking.
    private func opened(_ group: LanguageGroupModel) -> LanguageGroupModel {
        engine.becomeReady()
        group.start()
        loop.idle()
        return group
    }

    private func said(_ group: LanguageGroupModel, _ tag: String) -> String { group.row(tag)!.description }

    private func installRussian() {
        engine.listed = EngineFixtures.google.map { v in
            var v = v
            if v.name == "ru-ru-x-ruc-local" { v.installed = true }
            return v
        }
    }

    // MARK: what it says

    /// each row says how its language stands once the engine has answered
    func testEachRowSaysHowItsLanguageStandsOnceTheEngineHasAnswered() {
        engine.likeGoogle()
        let group = opened(group())

        XCTAssertTrue(said(group, "es").contains("Ready"), said(group, "es"))
        XCTAssertTrue(said(group, "ru").contains("Tap to download"), said(group, "ru"))
        XCTAssertTrue(said(group, "pl").contains("Online voice only"), said(group, "pl"))
        XCTAssertTrue(said(group, "pt").contains("Not offered"), said(group, "pt"))
    }

    /// the language it was given is the one ticked
    func testTheLanguageItWasGivenIsTheOneTicked() {
        engine.likeGoogle()
        let group = opened(group(initial: "es"))
        XCTAssertEqual(group.chosen, "es")
        XCTAssertTrue(said(group, "es").hasSuffix("selected"))
        XCTAssertFalse(said(group, "en").hasSuffix("selected"))
    }

    /// an engine that never answers is eventually said not to be
    func testAnEngineThatNeverAnswersIsEventuallySaidNotToBe() {
        let group = group()
        group.start()
        XCTAssertTrue(said(group, "es").contains("Checking"), said(group, "es"))

        loop.advance(seconds: 7)
        XCTAssertTrue(said(group, "es").contains("isn't answering"), said(group, "es"))
        group.stop()
    }

    // MARK: choosing

    /// choosing a language ticks it
    func testChoosingALanguageTicksIt() {
        engine.likeGoogle()
        let group = opened(group())

        group.choose("es")

        XCTAssertEqual(group.chosen, "es")
        XCTAssertTrue(said(group, "es").hasSuffix("selected"))
        XCTAssertFalse(said(group, "en").hasSuffix("selected"))
    }

    /// choosing a language that has to be downloaded asks for it, and shows it under way
    func testChoosingALanguageThatHasToBeDownloadedAsksForItAndShowsItUnderWay() {
        engine.likeGoogle()
        let group = opened(group())

        group.choose("ru")

        XCTAssertTrue(engine.calls.contains("setVoice:ru-ru-x-ruc-local"))
        XCTAssertTrue(toasts.contains("Downloading the Russian voice"), "\(toasts)")
        XCTAssertEqual(group.chosen, "ru")
        loop.idle()
        XCTAssertTrue(said(group, "ru").contains("Downloading"), said(group, "ru"))
    }

    /// a language the engine does not speak cannot be chosen, and the tap says why
    func testALanguageTheEngineDoesNotSpeakCannotBeChosenAndTheTapSaysWhy() {
        engine.likeGoogle()
        let group = opened(group())

        group.choose("pt")

        XCTAssertEqual(group.chosen, "en")
        XCTAssertEqual(toasts.count, 1)
        XCTAssertTrue(toasts[0].contains("doesn't speak Portuguese"), "\(toasts)")
    }

    /// a language tapped before the engine has answered asks for its voice when it does
    func testALanguageTappedBeforeTheEngineHasAnsweredAsksForItsVoiceWhenItDoes() {
        engine.likeGoogle()
        let group = group()
        group.start()

        group.choose("ru")
        XCTAssertEqual(group.chosen, "ru")
        XCTAssertFalse(engine.calls.contains { $0.hasPrefix("setVoice") },
                       "asked before anyone knew it needed asking")

        engine.becomeReady()
        loop.advance(seconds: 1)

        XCTAssertTrue(engine.calls.contains("setVoice:ru-ru-x-ruc-local"))
        XCTAssertTrue(toasts.contains("Downloading the Russian voice"), "\(toasts)")
        XCTAssertTrue(said(group, "ru").contains("Downloading"), said(group, "ru"))
        group.stop()
    }

    /// a language tapped before the engine has answered is undone if the phone cannot speak it
    func testALanguageTappedBeforeTheEngineHasAnsweredIsUndoneIfThePhoneCannotSpeakIt() {
        engine.likeGoogle()
        let group = group()
        group.start()

        group.choose("pt")
        XCTAssertEqual(group.chosen, "pt")

        engine.becomeReady()
        loop.advance(seconds: 1)

        XCTAssertEqual(group.chosen, "en")
        XCTAssertEqual(speaker.language, "en")
        XCTAssertTrue(said(group, "en").hasSuffix("selected"), said(group, "en"))
        XCTAssertFalse(said(group, "pt").hasSuffix("selected"), said(group, "pt"))
        XCTAssertEqual(toasts.count, 1)
        XCTAssertTrue(toasts[0].contains("doesn't speak Portuguese"), "\(toasts)")
        group.stop()
    }

    /// a language that was fine to tap before the engine answered stays chosen
    func testALanguageThatWasFineToTapBeforeTheEngineAnsweredStaysChosen() {
        engine.likeGoogle()
        let group = group()
        group.start()

        group.choose("es")
        engine.becomeReady()
        loop.advance(seconds: 1)

        XCTAssertEqual(group.chosen, "es")
        XCTAssertEqual(speaker.language, "es")
        XCTAssertEqual(toasts, [], "nothing needed saying")
        group.stop()
    }

    /// a download that has gone unanswered for two minutes is asked for again by a tap
    func testADownloadThatHasGoneUnansweredForTwoMinutesIsAskedForAgainByATap() {
        engine.likeGoogle()
        var clock: Int64 = 0
        let group = opened(group(now: { clock }))
        let asks = { self.engine.calls.filter { $0 == "setVoice:ru-ru-x-ruc-local" }.count }

        group.choose("ru")
        XCTAssertEqual(asks(), 1)

        // Fresh, a tap leaves it to finish: asking again would only restart its clock.
        group.choose("ru")
        XCTAssertEqual(asks(), 1)

        clock += VoiceLanguageText.stuckAfterMs
        loop.advance(seconds: 3)
        XCTAssertTrue(said(group, "ru").contains("Tap to retry"), said(group, "ru"))

        group.choose("ru")
        XCTAssertEqual(asks(), 2)
        XCTAssertTrue(said(group, "ru").contains("Downloading"), said(group, "ru"))
        group.stop()
    }

    /// an engine with no voice to set sends the athlete to its own screen
    func testAnEngineWithNoVoiceToSetSendsTheAthleteToItsOwnScreen() {
        engine.listed = []
        engine.answers["ru-RU"] = .missingData
        let group = opened(group())
        XCTAssertTrue(said(group, "ru").contains("Tap to download"), said(group, "ru"))

        group.choose("ru")

        XCTAssertEqual(installerOpened, 1)
        XCTAssertTrue(toasts.last?.hasPrefix("Opening the voice engine") == true, "\(toasts)")
    }

    /// Manage voices opens the engine's screen
    func testManageVoicesOpensTheEnginesScreen() {
        engine.likeGoogle()
        let group = opened(group())
        group.manageVoices()
        XCTAssertEqual(installerOpened, 1)
    }

    // MARK: hearing

    /// the play button plays the language's sample in a voice for it
    func testThePlayButtonPlaysTheLanguagesSampleInAVoiceForIt() {
        engine.likeGoogle()
        let group = opened(group())

        group.preview("es")

        XCTAssertEqual(engine.said.last?.text, "Tres. Cuatro. Cinco. Flexiones.")
        XCTAssertEqual(toasts, [], "nothing needed saying")
    }

    /// a preview of a language that is not on the phone says it is online
    func testAPreviewOfALanguageThatIsNotOnThePhoneSaysItIsOnline() {
        engine.likeGoogle()
        let group = opened(group())

        group.preview("ru")

        XCTAssertEqual(toasts, ["Playing an online preview"])
        XCTAssertEqual(engine.said.last?.text, "Три. Четыре. Пять. Отжимания.")
    }

    /// a preview that cannot reach the network says so
    func testAPreviewThatCannotReachTheNetworkSaysSo() {
        engine.likeGoogle()
        let group = opened(group())
        group.preview("ru")
        toasts.removeAll()

        engine.listener!.onError(engine.said.last!.id, .network)
        loop.idle()

        XCTAssertEqual(toasts, ["The Russian preview needs an internet connection"])
    }

    /// the play button of a language the engine does not speak says so, and plays nothing
    func testThePlayButtonOfALanguageTheEngineDoesNotSpeakSaysSoAndPlaysNothing() {
        engine.likeGoogle()
        let group = opened(group())
        let name = VoicePacks.of("pt").englishName
        XCTAssertEqual(group.row("pt")!.previewDescription, "Hear \(name), not offered by this phone's voice engine")

        group.preview("pt")

        XCTAssertEqual(engine.said, [])
        XCTAssertEqual(toasts.count, 1)
        XCTAssertTrue(toasts[0].contains("doesn't speak \(name)"), "\(toasts)")
    }

    /// the play button before the engine has answered says it is starting
    func testThePlayButtonBeforeTheEngineHasAnsweredSaysItIsStarting() {
        engine.likeGoogle()
        let group = group()
        group.start()

        group.preview("es")

        XCTAssertEqual(toasts, ["The voice engine is still starting. Try again in a moment."])
        XCTAssertEqual(engine.said, [])
        group.stop()
    }

    /// a preview that does not start is not announced as playing
    func testAPreviewThatDoesNotStartIsNotAnnouncedAsPlaying() {
        engine.listed = []
        engine.answers["ru-RU"] = .missingData
        let group = opened(group())

        group.preview("ru")

        XCTAssertEqual(toasts, ["This phone's voice engine can't play Russian"])
        XCTAssertEqual(engine.said, [])
    }

    /// HEAR IT plays whichever language is ticked
    func testHEARITPlaysWhicheverLanguageIsTicked() {
        engine.likeGoogle()
        let group = opened(group())
        group.choose("es")

        group.previewChosen()

        XCTAssertEqual(engine.said.last?.text, "Tres. Cuatro. Cinco. Flexiones.")
    }

    // MARK: keeping up with the phone

    /// a voice that arrives while the list is open shows up by itself
    func testAVoiceThatArrivesWhileTheListIsOpenShowsUpByItself() {
        engine.likeGoogle()
        let group = opened(group())
        XCTAssertTrue(said(group, "ru").contains("Tap to download"), said(group, "ru"))

        installRussian()
        loop.advance(seconds: 3)

        XCTAssertTrue(said(group, "ru").contains("Ready"), said(group, "ru"))
    }

    /// an engine that stays silent is asked less often once it has had its chance
    ///
    /// Kotlin's silent engine threw from `getVoices`; a Swift engine cannot, so this one never
    /// connects, which is how an engine that stays silent looks from outside. What is held is the
    /// pace: every 400 ms for the first six seconds, then every two seconds.
    func testAnEngineThatStaysSilentIsAskedLessOftenOnceItHasHadItsChance() {
        engine.likeGoogle()
        let group = group()
        group.start()

        loop.advance(seconds: 6)
        let early = delays.count
        loop.advance(seconds: 10)
        let later = delays.count - early

        XCTAssertTrue((1...6).contains(later), "asked \(later) times in ten seconds")
        XCTAssertTrue(delays.prefix(15).allSatisfy { $0 == LanguageGroupModel.firstPollMs }, "\(delays)")
        XCTAssertTrue(delays.suffix(later).allSatisfy { $0 == LanguageGroupModel.pollMs }, "\(delays)")
        group.stop()
    }

    /// a list that has been stopped stops reading
    func testAListThatHasBeenStoppedStopsReading() {
        engine.likeGoogle()
        let group = opened(group())
        group.stop()

        installRussian()
        loop.advance(seconds: 10)

        XCTAssertTrue(said(group, "ru").contains("Tap to download"), said(group, "ru"))
    }

    /// a list that has been stopped starts again where it left off
    func testAListThatHasBeenStoppedStartsAgainWhereItLeftOff() {
        engine.likeGoogle()
        let group = opened(group())
        group.stop()
        installRussian()

        group.start()
        loop.idle()

        XCTAssertTrue(said(group, "ru").contains("Ready"), said(group, "ru"))
        XCTAssertEqual(group.rows.count, VoicePacks.all.count)
    }
}
