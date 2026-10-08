import XCTest
import CindyCore

/// Mirrors `HeartRateStoreTest.kt`, which Robolectric ran against a fake Android context. This runs
/// against a folder of its own, so nothing here touches the app's.
final class HeartRateStoreTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("heart_rate_\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func store() -> HeartRateStore { HeartRateStore(directory: directory) }

    /// save and load round trips
    func testSaveAndLoadRoundTrips() throws {
        let store = store()
        let trace = HeartRateTrace(
            startedAtMillis: 1000,
            samples: [HeartRateSample(0, 100), HeartRateSample(1000, 110)],
            pauses: [HeartRatePause(atClockMs: 500, lengthMs: 5000)])
        try store.save(atMillis: 42, trace)
        XCTAssertEqual(store.load(atMillis: 42), trace)
        store.clear()
    }

    /// load of a missing file is null
    func testLoadOfAMissingFileIsNull() {
        XCTAssertNil(store().load(atMillis: 999_999))
    }

    /// clear deletes every saved trace
    func testClearDeletesEverySavedTrace() throws {
        let store = store()
        let trace = HeartRateTrace(startedAtMillis: 1000, samples: [HeartRateSample(0, 100)], pauses: [])
        try store.save(atMillis: 1, trace)
        try store.save(atMillis: 2, trace)
        store.clear()
        XCTAssertNil(store.load(atMillis: 1))
        XCTAssertNil(store.load(atMillis: 2))
    }
}
