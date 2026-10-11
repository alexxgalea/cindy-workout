import XCTest
import CindyCore

/// The music's decisions. Android has no test of `MusicPlayer` or of `syncMusic`: they ran against a
/// `MediaPlayer`. These are new, and hold what the Kotlin's doc comments promise.
final class MusicFlowTests: XCTestCase {

    // MARK: how loud

    /// the voice leaves 18% of the level
    func testTheVoiceLeavesEighteenPercent() {
        XCTAssertEqual(MusicFlow.duckedShare, 0.18, accuracy: 1e-6)
        XCTAssertEqual(MusicFlow.level(volume: 1, ducked: true), 0.18, accuracy: 1e-6)
    }

    /// ducking multiplies: a track turned down to a third does not get louder when the voice starts
    func testDuckingMultipliesAndNeverRaises() {
        let third: Float = 1.0 / 3
        XCTAssertEqual(MusicFlow.level(volume: third, ducked: true), third * 0.18, accuracy: 1e-6)
        XCTAssertLessThan(MusicFlow.level(volume: third, ducked: true), MusicFlow.level(volume: third, ducked: false))
        for v: Float in [0, 0.1, 0.5, 0.7, 1] {
            XCTAssertLessThanOrEqual(MusicFlow.level(volume: v, ducked: true), v)
        }
    }

    /// not ducked, the level is the chosen one
    func testNotDuckedTheLevelIsTheChosenOne() {
        XCTAssertEqual(MusicFlow.level(volume: 0.7, ducked: false), 0.7, accuracy: 1e-6)
    }

    /// a level outside 0 to 1 is held inside it
    func testALevelIsHeldInsideZeroToOne() {
        XCTAssertEqual(MusicFlow.clamp(1.5), 1)
        XCTAssertEqual(MusicFlow.clamp(-0.2), 0)
        XCTAssertEqual(MusicFlow.level(volume: 3, ducked: false), 1)
        XCTAssertEqual(MusicFlow.level(volume: -1, ducked: true), 0)
    }

    // MARK: when it plays

    /// it starts with the clock if it is on, and not otherwise
    func testItStartsWithTheClockIfItIsOn() {
        XCTAssertEqual(MusicFlow.onWorkout(from: .setup, to: .running, musicOn: true), .play)
        XCTAssertNil(MusicFlow.onWorkout(from: .setup, to: .running, musicOn: false))
        // A workout that skipped the check goes straight from idle or setup: the same.
        XCTAssertEqual(MusicFlow.onWorkout(from: .idle, to: .running, musicOn: true), .play)
    }

    /// a pause holds the track where it is, on or off
    func testAPauseHoldsTheTrack() {
        XCTAssertEqual(MusicFlow.onWorkout(from: .running, to: .paused, musicOn: true), .pause)
        XCTAssertEqual(MusicFlow.onWorkout(from: .running, to: .paused, musicOn: false), .pause)
    }

    /// the end of a pause picks it up again if it is on
    func testTheEndOfAPausePicksItUp() {
        XCTAssertEqual(MusicFlow.onWorkout(from: .paused, to: .running, musicOn: true), .play)
        XCTAssertNil(MusicFlow.onWorkout(from: .paused, to: .running, musicOn: false))
    }

    /// the end of a workout, however it ends, and a reset put the track back at the top
    func testTheEndAndAResetPutItBackAtTheTop() {
        XCTAssertEqual(MusicFlow.onWorkout(from: .running, to: .finished, musicOn: true), .stop)
        XCTAssertEqual(MusicFlow.onWorkout(from: .paused, to: .finished, musicOn: true), .stop)
        XCTAssertEqual(MusicFlow.onWorkout(from: .finished, to: .idle, musicOn: true), .stop)
    }

    /// nothing changing means nothing to do, and the setup check is silent
    func testNothingChangingMeansNothingToDo() {
        XCTAssertNil(MusicFlow.onWorkout(from: .running, to: .running, musicOn: true))
        XCTAssertNil(MusicFlow.onWorkout(from: .idle, to: .setup, musicOn: true))
    }

    /// back from the menu it plays only if it is on and the clock is running
    func testBackFromTheMenuItPlaysOnlyIfOnAndRunning() {
        XCTAssertEqual(MusicFlow.onSync(musicOn: true, running: true), .play)
        XCTAssertEqual(MusicFlow.onSync(musicOn: true, running: false), .pause)
        XCTAssertEqual(MusicFlow.onSync(musicOn: false, running: true), .pause)
        XCTAssertEqual(MusicFlow.onSync(musicOn: false, running: false), .pause)
    }

    // MARK: the choice

    /// no choice drops whatever is loaded; the loaded track is kept; a different one is loaded
    func testThePlanForTheChosenTrack() {
        XCTAssertEqual(MusicFlow.plan(chosen: nil, loaded: nil), .release)
        XCTAssertEqual(MusicFlow.plan(chosen: nil, loaded: "a"), .release)
        XCTAssertEqual(MusicFlow.plan(chosen: "a", loaded: "a"), .keep)
        XCTAssertEqual(MusicFlow.plan(chosen: "b", loaded: "a"), .load)
        XCTAssertEqual(MusicFlow.plan(chosen: "a", loaded: nil), .load)
    }

    /// a track is named by its file without the last extension
    func testATrackIsNamedWithoutTheLastExtension() {
        XCTAssertEqual(MusicFlow.displayName(fileName: "Eye of the Tiger.mp3"), "Eye of the Tiger")
        XCTAssertEqual(MusicFlow.displayName(fileName: "mix.v2.m4a"), "mix.v2")
        XCTAssertEqual(MusicFlow.displayName(fileName: "no extension"), "no extension")
        XCTAssertEqual(MusicFlow.displayName(fileName: ".hidden"), "")
    }

    // MARK: the sheet

    /// the card names the track, or says why it cannot
    func testTheCardNamesTheTrackOrSaysWhy() {
        XCTAssertEqual(MusicFlow.trackLine(chosen: "x", name: "Song"), "Song")
        XCTAssertEqual(MusicFlow.trackLine(chosen: nil, name: nil), "No track chosen")
        XCTAssertEqual(MusicFlow.trackLine(chosen: "x", name: nil), "That track can no longer be opened")
    }

    /// the buttons follow whether there is a track
    func testTheButtonsFollowWhetherThereIsATrack() {
        XCTAssertEqual(MusicFlow.primaryLabel(chosen: nil), "CHOOSE A TRACK")
        XCTAssertEqual(MusicFlow.secondaryLabel(chosen: nil), "CANCEL")
        XCTAssertEqual(MusicFlow.primaryLabel(chosen: "x"), "CHANGE TRACK")
        XCTAssertEqual(MusicFlow.secondaryLabel(chosen: "x"), "LISTEN")
    }

    /// the sheet says the track loops, ducks and stops, and that nothing is uploaded
    func testTheSheetSaysWhatTheTrackDoes() {
        XCTAssertTrue(MusicFlow.sheetSubtitle.contains("looped for the whole twenty minutes"))
        XCTAssertTrue(MusicFlow.sheetSubtitle.contains("drops in volume while the voice is counting"))
        XCTAssertTrue(MusicFlow.sheetNote.contains("Nothing is uploaded"))
        XCTAssertEqual(MusicFlow.lapsedText, "That track can no longer be played")
        XCTAssertEqual(MusicFlow.adoptedText(name: "Song"), "Music: Song")
        XCTAssertEqual(MusicFlow.adoptedText(name: nil), "Music: track chosen")
    }

    /// the menu row agrees with the sheet about a track that cannot be opened
    func testTheMenuRowAgreesWithTheSheet() {
        let profile = Profile(defaults: UserDefaults(suiteName: "MusicFlowTests.\(UUID().uuidString)")!)
        profile.musicTrack = "gone"
        let page = MenuBuilder.build(MenuInput(profile: profile, attempts: [], zone: Zone("UTC"),
                                               firstDayOfWeek: .monday, today: LocalDate(2026, 10, 9),
                                               is24Hour: true, hasPhoto: false, workoutLive: false,
                                               trackName: { _ in nil }))
        let row = page.rows.first { $0.id == .music }
        XCTAssertEqual(row?.subtitle, MusicFlow.trackLine(chosen: "gone", name: nil))
    }
}
