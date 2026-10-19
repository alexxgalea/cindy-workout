import XCTest
import CindyCore

/// The decisions behind REC. Android's `toggleRecording` and `beginRecording` ran inside the
/// activity and were covered only by the countdown's own test, so these are new: they pin the order
/// the Android screen answers a tap in, and what Photos adds to it.
final class FilmFlowTests: XCTestCase {

    // MARK: a tap

    /// a tap during the count calls it off
    func testATapDuringTheCountCallsItOff() {
        XCTAssertEqual(FilmFlow.tap(state: .counting, canFilm: true, access: .allowed),
                       .cancelCountdown(toast: "Recording cancelled"))
    }

    /// a count is called off even if Photos has since been refused: the way out is never closed
    func testACountCanAlwaysBeCalledOff() {
        XCTAssertEqual(FilmFlow.tap(state: .counting, canFilm: false, access: .refused),
                       .cancelCountdown(toast: "Recording cancelled"))
    }

    /// a tap while filming stops it, whatever Photos says now
    func testATapWhileFilmingStopsIt() {
        XCTAssertEqual(FilmFlow.tap(state: .filming, canFilm: true, access: .allowed), .stopFilming)
        XCTAssertEqual(FilmFlow.tap(state: .filming, canFilm: true, access: .refused), .stopFilming)
    }

    /// a camera that cannot film says so, before Photos is asked about anything
    func testACameraThatCannotFilmSaysSo() {
        for access in [FilmAccess.undecided, .allowed, .refused] {
            XCTAssertEqual(FilmFlow.tap(state: .idle, canFilm: false, access: access),
                           .say(toast: "Recording is not available on this camera"))
        }
    }

    /// Photos is asked before the count, so a film that cannot be saved is never made
    func testPhotosIsAskedBeforeTheCount() {
        XCTAssertEqual(FilmFlow.tap(state: .idle, canFilm: true, access: .undecided), .askAccess)
    }

    /// a refusal is told plainly and nothing counts down
    func testARefusalIsToldAndNothingCountsDown() {
        let step = FilmFlow.tap(state: .idle, canFilm: true, access: .refused)
        XCTAssertEqual(step, .say(toast: FilmFlow.refusedText))
        XCTAssertTrue(FilmFlow.refusedText.contains("Photos"), "it should name the place the film goes")
    }

    /// with Photos agreed, a tap buys three seconds and says so out loud
    func testATapBuysThreeSecondsAndSaysSo() {
        XCTAssertEqual(FilmFlow.tap(state: .idle, canFilm: true, access: .allowed),
                       .countdown(seconds: 3, voice: .recordingSoon(seconds: 3)))
        XCTAssertEqual(FilmFlow.countdownSeconds, 3)
    }

    // MARK: the far side

    /// a film that starts says "Recording", with nothing on the toast
    func testAFilmThatStartsSaysRecording() {
        XCTAssertEqual(FilmFlow.started(true), FilmStart(toast: nil, voice: .recordingStarted))
    }

    /// a film that cannot start says so, aloud as well as on the screen
    func testAFilmThatCannotStartSaysSo() {
        XCTAssertEqual(FilmFlow.started(false),
                       FilmStart(toast: "Could not start recording", voice: .recordingFailed))
    }

    /// a saved film is a toast and no voice: the athlete is at the bar and has not asked
    func testASavedFilmIsAToastAndNoVoice() {
        XCTAssertEqual(FilmFlow.ended(saved: true), FilmEnd(toast: "Saved to Photos", voice: nil))
    }

    /// a film that fails to save says so aloud, because the toast alone leaves them believing they are filmed
    func testAFailureIsSaidAloud() {
        XCTAssertEqual(FilmFlow.ended(saved: false), FilmEnd(toast: "Recording failed", voice: .recordingFailed))
    }

    // MARK: leaving

    /// leaving mid-count drops it, and leaving mid-film stops it so that what it caught is kept
    func testLeavingDropsACountAndStopsAFilm() {
        XCTAssertNil(FilmFlow.interrupted(.idle))
        XCTAssertEqual(FilmFlow.interrupted(.counting), .cancelCountdown(toast: "Recording cancelled"))
        XCTAssertEqual(FilmFlow.interrupted(.filming), .stopFilming)
    }

    // MARK: what the control says

    /// the control says which of its three states it is in, to a screen reader and on screen
    func testTheControlSaysWhichStateItIsIn() {
        XCTAssertEqual(FilmFlow.label(for: .idle), "Record this workout")
        XCTAssertEqual(FilmFlow.label(for: .counting), "Recording is about to start, tap to cancel")
        XCTAssertEqual(FilmFlow.label(for: .filming), "Stop recording")
        XCTAssertEqual(FilmFlow.title(for: .idle), "REC")
        XCTAssertEqual(FilmFlow.title(for: .counting), "REC")
        XCTAssertEqual(FilmFlow.title(for: .filming), "● REC")
    }

    // MARK: the name

    /// a film is named for the moment it started, to the second, in the zone it was filmed in
    func testAFilmIsNamedForTheMomentItStarted() {
        // 2026-03-07 09:05:03 UTC
        let millis: Int64 = 1_772_874_303_000
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(FilmFlow.fileName(atMillis: millis, timeZone: utc), "cindy-2026-03-07-090503")
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(FilmFlow.fileName(atMillis: millis, timeZone: tokyo), "cindy-2026-03-07-180503")
    }

    /// the vibration at the far side of the count is the one Android gives it
    func testTheVibrationIsTheOneAndroidGivesIt() {
        XCTAssertEqual(FilmFlow.startBuzzMs, 40)
    }
}
