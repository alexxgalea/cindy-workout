import XCTest
import CindyCore

/// Discarding one session takes everything filed under it and nothing filed under another.
///
/// A session is not one record: beside the attempt sit a heart-rate trace and the time of every
/// rep, all keyed by the same `atMillis`. These tests hold that the one call removes the lot, so a
/// screen never has to remember how many places a session lives in.
///
/// Mirrors `SessionDiscardTest.kt`, except its third test, which cancels the queued Strava upload
/// and forgets the ledger entry: that needs `StravaUploads`, which arrives in P19, and is ported
/// there.
final class SessionDiscardTests: XCTestCase {

    private var suite: String!
    private var folder: URL!
    private var records: RecordStore!
    private var heartRates: HeartRateStore!
    private var repTimes: RepTimesStore!

    private let gone: Int64 = 1_000
    private let kept: Int64 = 2_000

    private let trace = HeartRateTrace(startedAtMillis: 1_000, samples: [HeartRateSample(0, 120)], pauses: [])
    private let marks = [RepMark(0, .pushup, manual: false)]

    private var discard: SessionDiscard {
        SessionDiscard(records: records, heartRates: heartRates, repTimes: repTimes)
    }

    /// Two sessions filed everywhere.
    override func setUpWithError() throws {
        suite = "cindy.tests.\(UUID().uuidString)"
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        records = RecordStore(defaults: UserDefaults(suiteName: suite)!)
        heartRates = HeartRateStore(directory: folder.appendingPathComponent("heart_rate"))
        repTimes = RepTimesStore(directory: folder.appendingPathComponent("rep_times"))
        for at in [gone, kept] {
            XCTAssertTrue(records.add(Attempt(rounds: 10, reps: 0, atMillis: at)))
            try heartRates.save(atMillis: at, trace)
            try repTimes.save(atMillis: at, marks)
        }
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }

    /// it removes the record and the files beside it, and only that session's
    func testItRemovesTheRecordAndTheFilesBesideItAndOnlyThatSessions() {
        XCTAssertTrue(discard.discard(atMillis: gone))

        XCTAssertEqual(records.all().map { $0.atMillis }, [kept])
        XCTAssertNil(heartRates.load(atMillis: gone))
        XCTAssertNil(repTimes.load(atMillis: gone))
        XCTAssertEqual(heartRates.load(atMillis: kept), trace)
        XCTAssertEqual(repTimes.load(atMillis: kept), marks)
    }

    /// it says it removed nothing for a session that was never saved
    func testItSaysItRemovedNothingForASessionThatWasNeverSaved() {
        XCTAssertFalse(discard.discard(atMillis: 9_999))

        XCTAssertEqual(records.all().map { $0.atMillis }, [gone, kept])
        XCTAssertEqual(heartRates.load(atMillis: gone), trace)
        XCTAssertEqual(repTimes.load(atMillis: kept), marks)
    }
}
