import XCTest
import CindyCore

/// The question the camera screen puts to an athlete before START, about a heart-rate watch that is
/// missing or silent. Mirrors `WatchLinkTest.kt`.
final class WatchLinkTests: XCTestCase {

    // A phone that has been up for a day: the monotonic clock is nowhere near zero.
    private let now: Int64 = 86_400_000

    private func judge(lastReadingAt: Int64, paired: Bool = true) -> WatchLink {
        WatchLinks.judge(paired: paired, lastReadingAt: lastReadingAt, now: now)
    }

    /// no watch paired is not a silent watch
    func testNoWatchPairedIsNotASilentWatch() {
        XCTAssertEqual(judge(lastReadingAt: 0, paired: false), .notPaired)
    }

    /// a reading a second ago is live
    func testAReadingASecondAgoIsLive() {
        XCTAssertEqual(judge(lastReadingAt: now - 1_000), .live)
    }

    /// a reading exactly at the limit is still live, one millisecond later is not
    func testAReadingExactlyAtTheLimitIsStillLiveOneMillisecondLaterIsNot() {
        XCTAssertEqual(judge(lastReadingAt: now - WatchLinks.silentAfterMs), .live)
        XCTAssertEqual(judge(lastReadingAt: now - WatchLinks.silentAfterMs - 1), .silent)
    }

    /// a watch that has never sent anything is silent, however recently the app opened
    func testAWatchThatHasNeverSentAnythingIsSilentHoweverRecentlyTheAppOpened() {
        // No allowance for a link still being made: if nothing is coming in when START is tapped,
        // the session starts without a heart rate.
        XCTAssertEqual(judge(lastReadingAt: 0), .silent)
    }

    /// a watch that spoke and stopped is silent
    func testAWatchThatSpokeAndStoppedIsSilent() {
        XCTAssertEqual(judge(lastReadingAt: now - 30_000), .silent)
    }

    /// an unpaired athlete is offered a watch unless they said not to ask again
    func testAnUnpairedAthleteIsOfferedAWatchUnlessTheySaidNotToAskAgain() {
        XCTAssertEqual(WatchLinks.promptAtStart(.notPaired, bleAvailable: true, offerSilenced: false), .offerToPair)
        XCTAssertEqual(WatchLinks.promptAtStart(.notPaired, bleAvailable: true, offerSilenced: true), WatchPrompt.none)
    }

    /// a phone that cannot talk to a watch is never offered one
    func testAPhoneThatCannotTalkToAWatchIsNeverOfferedOne() {
        XCTAssertEqual(WatchLinks.promptAtStart(.notPaired, bleAvailable: false, offerSilenced: false), WatchPrompt.none)
    }

    /// a silent watch is always asked about, whatever was said about the offer
    func testASilentWatchIsAlwaysAskedAboutWhateverWasSaidAboutTheOffer() {
        for silenced in [false, true] {
            XCTAssertEqual(WatchLinks.promptAtStart(.silent, bleAvailable: true, offerSilenced: silenced),
                           .askAboutSilentWatch)
        }
    }

    /// a live watch is never interrupted
    func testALiveWatchIsNeverInterrupted() {
        XCTAssertEqual(WatchLinks.promptAtStart(.live, bleAvailable: true, offerSilenced: false), WatchPrompt.none)
    }

    /// the sheet says why when the reason is known
    func testTheSheetSaysWhyWhenTheReasonIsKnown() {
        XCTAssertEqual(WatchLinks.why(.bluetoothOff), "Bluetooth is off on this phone.")
        XCTAssertEqual(WatchLinks.why(.noPermission), "Cindy is not allowed to use Bluetooth.")
        XCTAssertEqual(WatchLinks.why(.waiting), "It is paired but has sent no heart rate. Is heart-rate broadcast on?")
    }
}
