import XCTest
import CindyCore

/// Mirrors `RepTimesStoreTest.kt`, which Robolectric ran against a fake Android context. This runs
/// against a folder of its own, so nothing here touches the app's.
final class RepTimesStoreTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rep_times_\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func store() -> RepTimesStore { RepTimesStore(directory: directory) }

    /// save and load round trips
    func testSaveAndLoadRoundTrips() throws {
        let store = store()
        let marks = [RepMark(0, .pullup, manual: false), RepMark(1_000, .pullup, manual: true)]
        try store.save(atMillis: 42, marks)
        XCTAssertEqual(store.load(atMillis: 42), marks)
        store.clear()
    }

    /// load of a missing file is null
    func testLoadOfAMissingFileIsNull() {
        XCTAssertNil(store().load(atMillis: 999_999))
    }

    /// clear deletes every saved file
    func testClearDeletesEverySavedFile() throws {
        let store = store()
        let marks = [RepMark(0, .squat, manual: false)]
        try store.save(atMillis: 1, marks)
        try store.save(atMillis: 2, marks)
        store.clear()
        XCTAssertNil(store.load(atMillis: 1))
        XCTAssertNil(store.load(atMillis: 2))
    }

    /// saving again over the same attempt replaces the file rather than failing
    func testSavingAgainReplacesTheFile() throws {
        let store = store()
        try store.save(atMillis: 7, [RepMark(0, .pullup, manual: false)])
        try store.save(atMillis: 7, [RepMark(5, .squat, manual: true)])
        XCTAssertEqual(store.load(atMillis: 7), [RepMark(5, .squat, manual: true)])
    }

    /// a file left by a crash mid-write is not an attempt's marks
    func testAHalfWrittenFileDoesNotDecodeAsMarks() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not a header\n1,PULLUP,c".utf8)
            .write(to: directory.appendingPathComponent("9.reps"))
        XCTAssertNil(store().load(atMillis: 9))
    }
}
