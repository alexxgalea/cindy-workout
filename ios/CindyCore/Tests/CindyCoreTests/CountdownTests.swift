import XCTest
import CindyCore

/// The countdown that stands between tapping REC and the camera rolling.
///
/// Worth a test of its own because the thing that can go wrong here is not drawing but *timing*: a
/// callback that fires twice starts two recordings, a callback that fires early films the athlete
/// still holding the phone, and a cancelled countdown that fires anyway records a session nobody
/// asked to record. The clock is handed in, so all three are checkable without waiting three real
/// seconds.
///
/// Mirrors `CountdownTest.kt`, which ran Robolectric's paused looper against the view.
final class CountdownTests: XCTestCase {

    private var now: Int64 = 5_000

    /// Runs frames of 16 ms, as the display does, for `ms`.
    private func advance(_ countdown: Countdown, _ ms: Int64) {
        let until = now + ms
        while now < until {
            now = min(now + 16, until)
            countdown.tick(now: now)
        }
    }

    /// the callback fires once, after the full count
    func testTheCallbackFiresOnceAfterTheFullCount() {
        let countdown = Countdown()
        var fired = 0
        countdown.start(fromSeconds: 3, now: now) { fired += 1 }
        XCTAssertTrue(countdown.isRunning, "the countdown should be running")

        advance(countdown, 2_900)
        XCTAssertEqual(fired, 0, "recording started before the count was up")

        advance(countdown, 200)
        XCTAssertEqual(fired, 1, "recording did not start when the count ran out")
        XCTAssertFalse(countdown.isRunning, "it kept running past zero")

        // Nothing is left scheduled that could fire the callback a second time.
        advance(countdown, 5_000)
        XCTAssertEqual(fired, 1, "the callback fired more than once")
    }

    /// a cancelled countdown never fires
    func testACancelledCountdownNeverFires() {
        let countdown = Countdown()
        var fired = 0
        countdown.start(fromSeconds: 3, now: now) { fired += 1 }

        advance(countdown, 1_200)
        countdown.cancel()

        XCTAssertFalse(countdown.isRunning)
        advance(countdown, 5_000)
        XCTAssertEqual(fired, 0, "a cancelled countdown still started a recording")
    }

    /// it draws at every point of the count
    func testItDrawsAtEveryPointOfTheCount() {
        // Drawing is where the digit is worked out, so it has to survive every frame of a count.
        let countdown = Countdown()
        countdown.start(fromSeconds: 3, now: now) {}
        var digits: [Int] = []
        for _ in 0..<30 {
            let digit = countdown.digit(now: now)!
            let into = countdown.into(now: now)!
            XCTAssertTrue((1...3).contains(digit), "digit \(digit)")
            XCTAssertTrue((0...1).contains(into), "into \(into)")
            digits.append(digit)
            advance(countdown, 100)
        }
        XCTAssertEqual(digits.first, 3)
        XCTAssertEqual(digits.last, 1)
        XCTAssertEqual(digits, digits.sorted(by: >), "it only counts down")
        // A frame past zero: the count ends on the first frame after its deadline, which is up to
        // one frame late by design rather than on the stroke of it.
        advance(countdown, 32)
        XCTAssertFalse(countdown.isRunning, "the count should have finished")
        // Asking when it is not running is a no-op rather than a crash.
        XCTAssertNil(countdown.digit(now: now))
        XCTAssertNil(countdown.into(now: now))
    }

    // MARK: - what the view relies on

    /// starting again calls the first count off, and a count is never shorter than a second
    func testStartingAgainCallsTheFirstCountOffAndACountIsNeverShorterThanASecond() {
        let countdown = Countdown()
        var first = 0, second = 0
        countdown.start(fromSeconds: 3, now: now) { first += 1 }
        advance(countdown, 1_000)
        countdown.start(fromSeconds: 0, now: now) { second += 1 }
        XCTAssertEqual(countdown.seconds, 1)
        advance(countdown, 1_100)
        XCTAssertEqual(first, 0, "the first count was called off")
        XCTAssertEqual(second, 1)
    }

    /// it says what is happening to a screen reader
    func testItSaysWhatIsHappeningToAScreenReader() {
        let countdown = Countdown()
        countdown.start(fromSeconds: 3, now: now) {}
        XCTAssertEqual(countdown.announcement, "Recording in 3")
        XCTAssertEqual(countdown.accessibilityLabel, "Recording starts in 3 seconds")
    }
}
