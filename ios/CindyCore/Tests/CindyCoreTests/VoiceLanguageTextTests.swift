import XCTest
import CindyCore

/// What the language list tells the athlete about their phone, and when.
///
/// Mirrors `VoiceLanguageTextTest.kt`.
final class VoiceLanguageTextTests: XCTestCase {

    private let es = VoicePacks.of("es")
    private let minute: Int64 = 60_000

    /// every state says something different
    func testEveryStateSaysSomethingDifferent() {
        let said = PackState.allCases.map { VoiceLanguageText.caption($0, downloadingMs: nil, waitedMs: 0) }
        XCTAssertEqual(said.count, Set(said).count)
        for s in said { XCTAssertFalse(s.isEmpty) }
    }

    /// a language nobody has heard back about is being checked
    func testALanguageNobodyHasHeardBackAboutIsBeingChecked() {
        XCTAssertEqual(VoiceLanguageText.caption(nil, downloadingMs: nil, waitedMs: 0), "Checking…")
        XCTAssertEqual(VoiceLanguageText.caption(nil, downloadingMs: nil, waitedMs: 5_999), "Checking…")
    }

    /// an engine that never answers is said not to be answering
    func testAnEngineThatNeverAnswersIsSaidNotToBeAnswering() {
        XCTAssertEqual(
            VoiceLanguageText.caption(nil, downloadingMs: nil, waitedMs: VoiceLanguageText.noAnswerAfterMs),
            "This phone's voice engine isn't answering")
    }

    /// a download is under way until it has gone on suspiciously long
    func testADownloadIsUnderWayUntilItHasGoneOnSuspiciouslyLong() {
        XCTAssertEqual(VoiceLanguageText.caption(.downloading, downloadingMs: 0, waitedMs: 0), "Downloading…")
        XCTAssertEqual(VoiceLanguageText.caption(.downloading, downloadingMs: 2 * minute - 1, waitedMs: 0), "Downloading…")
        XCTAssertEqual(VoiceLanguageText.caption(.downloading, downloadingMs: 2 * minute, waitedMs: 0),
                       "Still waiting. The voice engine may need Wi-Fi. Tap to retry.")
    }

    /// an online-only language says counting stays in English
    func testAnOnlineOnlyLanguageSaysCountingStaysInEnglish() {
        XCTAssertTrue(VoiceLanguageText.caption(.onlineOnly, downloadingMs: nil, waitedMs: 0).contains("English"))
    }

    /// only a language the engine does not speak cannot be chosen
    func testOnlyALanguageTheEngineDoesNotSpeakCannotBeChosen() {
        for state in PackState.allCases {
            XCTAssertEqual(VoiceLanguageText.selectable(state), state != .unsupported)
        }
        // Unknown is choosable: the engine being slow should not make the list unusable.
        XCTAssertTrue(VoiceLanguageText.selectable(nil))
    }

    /// choosing a language asks for its voice when there is none, or a request has gone stale
    func testChoosingALanguageAsksForItsVoiceWhenThereIsNoneOrARequestHasGoneStale() {
        XCTAssertTrue(VoiceLanguageText.asksForDownload(.downloadable, downloadingMs: nil))
        // Fresh, it is left to finish: asking again would only restart the clock.
        XCTAssertFalse(VoiceLanguageText.asksForDownload(.downloading, downloadingMs: 0))
        XCTAssertFalse(VoiceLanguageText.asksForDownload(.downloading, downloadingMs: 2 * minute - 1))
        // Stale, asking again is the only way out.
        XCTAssertTrue(VoiceLanguageText.asksForDownload(.downloading, downloadingMs: 2 * minute))
    }

    /// choosing a language that needs no voice asks for none
    func testChoosingALanguageThatNeedsNoVoiceAsksForNone() {
        XCTAssertFalse(VoiceLanguageText.asksForDownload(.ready, downloadingMs: nil))
        XCTAssertFalse(VoiceLanguageText.asksForDownload(.onlineOnly, downloadingMs: nil))
        XCTAssertFalse(VoiceLanguageText.asksForDownload(.unsupported, downloadingMs: nil))
        // Nobody knows yet; the choice is settled once somebody does.
        XCTAssertFalse(VoiceLanguageText.asksForDownload(nil, downloadingMs: nil))
    }

    /// the stale wait is the same one the caption reports
    func testTheStaleWaitIsTheSameOneTheCaptionReports() {
        // The row that says "Tap to retry" is the row that retries, and no other.
        for state in PackState.allCases {
            for waited in [0, 2 * minute - 1, 2 * minute, 10 * minute] as [Int64] {
                let offersRetry = VoiceLanguageText.caption(state, downloadingMs: waited, waitedMs: 0)
                    .contains("Tap to retry")
                XCTAssertEqual(offersRetry,
                               state == .downloading && VoiceLanguageText.asksForDownload(state, downloadingMs: waited),
                               "\(state) after \(waited) ms")
            }
        }
    }

    /// a preview is labelled online unless the voice is on the phone
    func testAPreviewIsLabelledOnlineUnlessTheVoiceIsOnThePhone() {
        XCTAssertNil(VoiceLanguageText.previewNote(.ready))
        XCTAssertNil(VoiceLanguageText.previewNote(nil))
        XCTAssertEqual(VoiceLanguageText.previewNote(.downloadable), "Playing an online preview")
        XCTAssertEqual(VoiceLanguageText.previewNote(.onlineOnly), "Playing an online preview")
        XCTAssertEqual(VoiceLanguageText.previewNote(.downloading), "Playing an online preview")
    }

    /// a language the engine does not speak has no preview to label
    func testALanguageTheEngineDoesNotSpeakHasNoPreviewToLabel() {
        XCTAssertNil(VoiceLanguageText.previewNote(.unsupported))
    }

    /// every way a preview can fail is said in words the athlete can act on
    func testEveryWayAPreviewCanFailIsSaidInWordsTheAthleteCanActOn() {
        XCTAssertEqual(VoiceLanguageText.previewFailure(.network, es), "The Spanish preview needs an internet connection")
        XCTAssertEqual(VoiceLanguageText.previewFailure(.notInstalled, es), "The Spanish voice is still downloading")
        XCTAssertEqual(VoiceLanguageText.previewFailure(.unavailable, es), "This phone's voice engine can't play Spanish")
        XCTAssertEqual(VoiceLanguageText.previewFailure(.other, es), "The preview didn't play")
        for failure in SpeechFailure.allCases {
            XCTAssertFalse(VoiceLanguageText.previewFailure(failure, es).isEmpty)
        }
    }

    /// an engine that has not answered is starting, and then is not answering
    func testAnEngineThatHasNotAnsweredIsStartingAndThenIsNotAnswering() {
        XCTAssertEqual(VoiceLanguageText.engineSilent(waitedMs: 0),
                       "The voice engine is still starting. Try again in a moment.")
        XCTAssertEqual(VoiceLanguageText.engineSilent(waitedMs: VoiceLanguageText.noAnswerAfterMs - 1),
                       "The voice engine is still starting. Try again in a moment.")
        // The same words the rows use, so the sheet does not say two things about one engine.
        XCTAssertEqual(
            VoiceLanguageText.caption(nil, downloadingMs: nil, waitedMs: VoiceLanguageText.noAnswerAfterMs),
            VoiceLanguageText.engineSilent(waitedMs: VoiceLanguageText.noAnswerAfterMs))
    }

    /// a screen reader hears the language, how it stands, and whether it is chosen
    func testAScreenReaderHearsTheLanguageHowItStandsAndWhetherItIsChosen() {
        XCTAssertEqual(VoiceLanguageText.description(es, "Ready", chosen: false), "Español, Spanish, Ready")
        XCTAssertEqual(VoiceLanguageText.description(es, "Ready", chosen: true), "Español, Spanish, Ready, selected")
        XCTAssertEqual(VoiceLanguageText.previewDescription(es, .ready), "Hear Spanish")
        XCTAssertEqual(VoiceLanguageText.previewDescription(es, nil), "Hear Spanish")
    }

    /// the preview button of a language that is not offered does not sound like one that works
    func testThePreviewButtonOfALanguageThatIsNotOfferedDoesNotSoundLikeOneThatWorks() {
        XCTAssertEqual(VoiceLanguageText.previewDescription(es, .unsupported),
                       "Hear Spanish, not offered by this phone's voice engine")
    }

    /// a language that cannot be chosen says why and what might help
    func testALanguageThatCannotBeChosenSaysWhyAndWhatMightHelp() {
        let said = VoiceLanguageText.unsupportedNotice(es)
        XCTAssertTrue(said.contains("Spanish"), said)
        XCTAssertTrue(said.contains("speech settings"), said)
    }
}
