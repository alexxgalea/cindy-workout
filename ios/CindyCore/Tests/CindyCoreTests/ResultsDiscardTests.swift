import XCTest
@testable import CindyCore

/// DISCARD on the results page: what it asks, and what confirming it does. Ported from the discard
/// parts of `ScreenSmokeTest.kt` and `StravaScreenTest.kt`, which read the sheet off an inflated
/// screen; here they read it off the `DiscardQuestion` the page asks, and off the stores.
///
/// Which buttons the bar has is held in `ResultsPageTests`. That the question's KEEP IT is the
/// filled button and DISCARD the quiet one in the alert colour, and that confirming closes the
/// page, are the SwiftUI layer's and are held by the UI test.
final class ResultsDiscardTests: XCTestCase {

    private let zone = Zone("Europe/Bucharest")
    private lazy var today = LocalDate(2026, 10, 8)
    private lazy var now = zone.epochMs(today, hour: 12)
    private let day: Int64 = 24 * 60 * 60 * 1000

    private var suite: String!
    private var folder: URL!
    private var records: RecordStore!
    private var heartRates: HeartRateStore!
    private var repTimes: RepTimesStore!

    private var discard: SessionDiscard {
        SessionDiscard(records: records, heartRates: heartRates, repTimes: repTimes)
    }

    override func setUp() {
        suite = "cindy.tests.\(UUID().uuidString)"
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        records = RecordStore(defaults: UserDefaults(suiteName: suite)!)
        heartRates = HeartRateStore(directory: folder.appendingPathComponent("heart_rate"))
        repTimes = RepTimesStore(directory: folder.appendingPathComponent("rep_times"))
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }

    /// A session filed a day ago, as `ScreenSmokeTest.savedSession` files one.
    private func savedSession(at atMillis: Int64? = nil) -> Attempt {
        let attempt = Attempt(rounds: 12, reps: 3, atMillis: atMillis ?? now - day,
                              durationMs: 20 * 60_000, profile: .standard)
        XCTAssertTrue(records.add(attempt))
        return attempt
    }

    private func model(_ attempt: Attempt, reviewing: Bool = true) -> ResultsModel {
        ResultsModel(ResultsInput(attempt: attempt, reviewing: reviewing, records: records.all(), body: Body(0),
                                  zone: zone, firstDayOfWeek: .monday, today: today))
    }

    /// DISCARD asks first, and KEEP IT leaves the session where it was
    func testDISCARDAsksFirstAndKEEPITLeavesTheSessionWhereItWas() {
        let attempt = savedSession()
        let results = model(attempt)

        let question = results.discardQuestion(onStrava: false)

        // Asking is all that has happened, and KEEP IT is the answer that does nothing.
        XCTAssertEqual(question.keep, "KEEP IT")
        XCTAssertEqual(question.discard, "DISCARD")
        XCTAssertEqual(records.all().map { $0.atMillis }, [attempt.atMillis])
    }

    /// confirming DISCARD removes the session and closes its page
    func testConfirmingDISCARDRemovesTheSessionAndClosesItsPage() {
        let attempt = savedSession()
        let results = model(attempt)

        // The page closes whatever the answer is; what is held here is that the session is gone.
        XCTAssertTrue(results.discard(using: discard))

        XCTAssertTrue(records.all().isEmpty)
    }

    /// written for the port: it takes the session the page is about, and no other
    func testItTakesTheSessionThePageIsAboutAndNoOther() throws {
        let shown = savedSession(at: now - 2 * day)
        let other = savedSession(at: now - day)
        try heartRates.save(atMillis: shown.atMillis, HeartRateTrace(startedAtMillis: 1, samples: [HeartRateSample(0, 100)], pauses: []))
        try repTimes.save(atMillis: other.atMillis, [RepMark(0, .squat, manual: false)])

        model(shown).discard(using: discard)

        XCTAssertEqual(records.all().map { $0.atMillis }, [other.atMillis])
        XCTAssertNil(heartRates.load(atMillis: shown.atMillis))
        XCTAssertNotNil(repTimes.load(atMillis: other.atMillis))
    }

    /// written for the port: the session is named by its rep count and its date, in the words Android uses
    func testTheSessionIsNamedByItsRepCountAndItsDateInTheWordsAndroidUses() {
        let question = model(savedSession(at: now - 2 * day)).discardQuestion(onStrava: false)

        XCTAssertEqual(question.title, "Discard this session?")
        XCTAssertEqual(question.subtitle,
                       "363 reps · TUE 6 OCT 2026 · 12:00\n\nIts heart-rate trace and rep times go with it, "
                       + "and so does any badge or record only it earned. This cannot be undone.")
    }

    /// the discard sheet says an upload that already reached Strava stays there
    func testTheDiscardSheetSaysAnUploadThatAlreadyReachedStravaStaysThere() {
        let question = model(savedSession()).discardQuestion(onStrava: true)

        XCTAssertTrue(question.subtitle.contains("stays on Strava"), "the sheet kept quiet about the copy on Strava: \(question.subtitle)")
        XCTAssertTrue(question.subtitle.hasSuffix(" It stays on Strava — remove it there."))
    }

    /// the discard sheet says nothing about Strava while the upload is only queued
    func testTheDiscardSheetSaysNothingAboutStravaWhileTheUploadIsOnlyQueued() {
        let question = model(savedSession()).discardQuestion(onStrava: false)

        XCTAssertFalse(question.subtitle.contains("Strava"), "the sheet warned about a copy that does not exist: \(question.subtitle)")
    }
}
