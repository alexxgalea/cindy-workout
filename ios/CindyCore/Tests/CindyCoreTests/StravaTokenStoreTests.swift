import XCTest
import CindyCore

/// What the Strava connection keeps between launches.
///
/// No Kotlin test: Android's store is `SharedPreferences`, exercised only through the screens that
/// use it (`StravaScreenTest`, in P20). The store here is the seam the Keychain plugs into, so what
/// it writes and reads back is pinned on its own.
final class StravaTokenStoreTests: XCTestCase {

    private let storage = InMemoryStravaStorage()
    private var store: StravaTokenStore { StravaTokenStore(storage: storage) }

    private let grant = StravaGrant(accessToken: "a", refreshToken: "r", expiresAtEpochS: 1_700_003_600,
                                    scopes: ["read", "activity:write"], athleteName: "Alex G")

    /// nothing stored is not connected
    func testNothingStoredIsNotConnected() {
        XCTAssertNil(store.grant)
        XCTAssertFalse(store.connected)
    }

    /// a grant round-trips whole, scopes and name included
    func testAGrantRoundTripsWholeScopesAndNameIncluded() {
        store.grant = grant
        XCTAssertEqual(store.grant, grant)
        XCTAssertTrue(store.connected)

        let nameless = StravaGrant(accessToken: "a", refreshToken: "r", expiresAtEpochS: 5, scopes: [], athleteName: nil)
        store.grant = nameless
        XCTAssertEqual(store.grant, nameless)
    }

    /// the grant is one item, so it cannot be half written
    func testTheGrantIsOneItemSoItCannotBeHalfWritten() {
        store.grant = grant
        XCTAssertEqual(storage.keys(), ["grant"])
    }

    /// clearing forgets the grant and leaves the settings
    func testClearingForgetsTheGrantAndLeavesTheSettings() {
        store.grant = grant
        store.autoUpload = false
        store.pendingState = "s"
        store.clearGrant()
        XCTAssertNil(store.grant)
        XCTAssertFalse(store.autoUpload)
        XCTAssertEqual(store.pendingState, "s")
    }

    /// a grant missing a token is no grant
    func testAGrantMissingATokenIsNoGrant() {
        storage.set(#"{"access_token":"a"}"#, forKey: "grant")
        XCTAssertNil(store.grant)
        storage.set("not json", forKey: "grant")
        XCTAssertNil(store.grant)
    }

    /// a grant with no expiry or scopes written reads as expired with no scopes
    func testAGrantWithNoExpiryOrScopesWrittenReadsAsExpiredWithNoScopes() {
        storage.set(#"{"access_token":"a","refresh_token":"r"}"#, forKey: "grant")
        XCTAssertEqual(store.grant, StravaGrant(accessToken: "a", refreshToken: "r", expiresAtEpochS: 0,
                                                scopes: [], athleteName: nil))
    }

    /// the pending state is kept until it is cleared
    func testThePendingStateIsKeptUntilItIsCleared() {
        XCTAssertNil(store.pendingState)
        store.pendingState = "abc"
        XCTAssertEqual(store.pendingState, "abc")
        store.pendingState = nil
        XCTAssertNil(store.pendingState)
    }

    /// the attempt to upload after connecting is kept until it is cleared
    func testTheAttemptToUploadAfterConnectingIsKeptUntilItIsCleared() {
        XCTAssertNil(store.afterConnectUploadAtMillis)
        store.afterConnectUploadAtMillis = 1_700_000_000_000
        XCTAssertEqual(store.afterConnectUploadAtMillis, 1_700_000_000_000)
        store.afterConnectUploadAtMillis = nil
        XCTAssertNil(store.afterConnectUploadAtMillis)
    }

    /// automatic upload is on until it is switched off
    func testAutomaticUploadIsOnUntilItIsSwitchedOff() {
        XCTAssertTrue(store.autoUpload)
        store.autoUpload = false
        XCTAssertFalse(store.autoUpload)
        store.autoUpload = true
        XCTAssertTrue(store.autoUpload)
    }
}
