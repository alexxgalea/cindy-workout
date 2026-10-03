import XCTest
import CindyCore

/// Whether `RecordStore.add` actually stored anything.
///
/// A heart-rate trace is about to need this answer: it belongs beside a saved attempt, and a
/// zero-rep attempt never becomes one. `add` used to say nothing about which happened.
///
/// Mirrors `RecordStoreTest.kt`, which Robolectric ran against a fake Android context. This runs
/// against a throwaway `UserDefaults` suite, so nothing here touches the app's own.
final class RecordStoreTests: XCTestCase {

    private var suite: String!

    override func setUp() {
        suite = "cindy.tests.\(UUID().uuidString)"
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
    }

    private func store() -> RecordStore {
        let store = RecordStore(defaults: UserDefaults(suiteName: suite)!)
        store.clear()
        return store
    }

    /// a zero-rep attempt is not stored
    func testAZeroRepAttemptIsNotStored() {
        let store = store()
        let saved = store.add(Attempt(rounds: 0, reps: 0, atMillis: 1000))
        XCTAssertFalse(saved)
        XCTAssertTrue(store.all().isEmpty)
    }

    /// a real attempt is stored
    func testARealAttemptIsStored() {
        let store = store()
        let saved = store.add(Attempt(rounds: 12, reps: 7, atMillis: 1000))
        XCTAssertTrue(saved)
        XCTAssertEqual(store.all().count, 1)
    }

    /// an attempt comes back whole, counted reps and sets included, from a fresh store
    func testAnAttemptComesBackWholeFromAFreshStore() {
        let a = Attempt(rounds: 2, reps: 3, atMillis: 5, countedReps: 61, untrackedMs: 4_000,
                        setSplits: [SetSplit(.pullup, 9_000, 5, 1)])
        store().add(a)
        XCTAssertEqual(RecordStore(defaults: UserDefaults(suiteName: suite)!).all(), [a])
    }

    /// the string lives under Android's key, in Android's format
    func testTheStringLivesUnderAndroidsKeyInAndroidsFormat() {
        let defaults = UserDefaults(suiteName: suite)!
        RecordStore(defaults: defaults).add(Attempt(rounds: 1, reps: 0, atMillis: 9))
        XCTAssertEqual(defaults.string(forKey: "attempts"),
                       Records.encode([Attempt(rounds: 1, reps: 0, atMillis: 9)]))
        XCTAssertTrue(defaults.string(forKey: "attempts")!.hasPrefix("v7|"))
    }
}
