import XCTest
import CindyCore

/// The access token the API asks for: fresh, refreshed, revoked, absent, and raced.
///
/// Mirrors `StravaSessionTest.kt`, which is a Robolectric test only because its store is Android's
/// `SharedPreferences`. Here the store sits on an in-memory `StravaStorage`, so it runs with the
/// rest. It is in this phase rather than the next one because `StravaSession` is.
final class StravaSessionTests: XCTestCase {

    private let config = StravaConfig(clientId: "12345", clientSecret: "s3cret", applicationId: "com.cindy.tracker")
    private let nowMs: Int64 = 1_700_000_000_000
    private var nowS: Int64 { nowMs / 1000 }

    private var store: StravaTokenStore!

    override func setUp() {
        store = StravaTokenStore(storage: InMemoryStravaStorage())
    }

    private func grant(_ accessToken: String, _ refreshToken: String, expiresAtEpochS: Int64) -> StravaGrant {
        StravaGrant(accessToken: accessToken, refreshToken: refreshToken, expiresAtEpochS: expiresAtEpochS,
                    scopes: ["read", "activity:write"], athleteName: "Alex")
    }

    private func session(_ transport: HttpTransport) -> StravaSession {
        let now = nowMs
        return StravaSession(store: store, auth: StravaAuth(transport: transport, config: config), clock: { now })
    }

    private func refreshReply(_ access: String, _ refresh: String) -> HttpResponse {
        HttpResponse(200, [:], """
            {"access_token":"\(access)","refresh_token":"\(refresh)","expires_at":\(nowS + 3600),
             "scope":"read,activity:write"}
            """)
    }

    /// a token with plenty of life left is returned without touching the network
    func testATokenWithPlentyOfLifeLeftIsReturnedWithoutTouchingTheNetwork() async throws {
        store.grant = grant("fresh", "r1", expiresAtEpochS: nowS + 3600)
        let transport = FakeTransport()  // nothing scripted: any call throws immediately.

        let token = try await session(transport).get()

        XCTAssertEqual(token, "fresh")
        XCTAssertTrue(transport.requests.isEmpty, "no refresh should have been attempted")
    }

    /// a token near expiry is refreshed, and the rotated grant is persisted before get returns
    func testATokenNearExpiryIsRefreshedAndTheRotatedGrantIsPersistedBeforeGetReturns() async throws {
        store.grant = grant("stale", "staleRefresh", expiresAtEpochS: nowS + 100)
        let transport = FakeTransport()
        transport.enqueue(refreshReply("freshA", "freshR"))

        let token = try await session(transport).get()

        XCTAssertEqual(token, "freshA")
        XCTAssertEqual(store.grant?.refreshToken, "freshR", "the rotated refresh token must already be on disk")
        XCTAssertEqual(store.grant?.accessToken, "freshA")
        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertTrue(String(decoding: try XCTUnwrap(sent.body), as: UTF8.self).contains("refresh_token=staleRefresh"))
    }

    /// a 401 on refresh clears the stored grant and throws a revoked exception
    func testA401OnRefreshClearsTheStoredGrantAndThrowsARevokedError() async {
        store.grant = grant("stale", "staleRefresh", expiresAtEpochS: nowS + 100)
        let transport = FakeTransport()
        transport.enqueue(HttpResponse(401, [:], #"{"message":"Unauthorized"}"#))

        let error = await thrownError { _ = try await session(transport).get() }

        XCTAssertEqual((error as? StravaAuthError)?.revoked, true)
        XCTAssertNil(store.grant, "the grant must be gone once Strava says it is revoked")
    }

    /// a 500 on refresh leaves the stored grant alone
    func testA500OnRefreshLeavesTheStoredGrantAlone() async {
        store.grant = grant("stale", "staleRefresh", expiresAtEpochS: nowS + 100)
        let transport = FakeTransport()
        transport.enqueue(HttpResponse(500, [:], "oops"))

        let error = await thrownError { _ = try await session(transport).get() }

        XCTAssertEqual((error as? StravaAuthError)?.revoked, false)
        XCTAssertEqual(store.grant?.accessToken, "stale", "a transient failure must not disconnect the athlete")
    }

    /// get throws when there is no grant at all
    func testGetThrowsWhenThereIsNoGrantAtAll() async {
        let error = await thrownError { _ = try await session(FakeTransport()).get() }
        XCTAssertEqual((error as? StravaAuthError)?.revoked, false)
    }

    /// Opens once, and lets everything waiting on it through.
    private actor Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            for waiter in waiters { waiter.resume() }
            waiters = []
        }
    }

    /// A transport that holds its first call at a gate, so a second one can queue behind it.
    private final class GatedTransport: HttpTransport, @unchecked Sendable {
        let entered = Gate()
        let release = Gate()
        private let lock = NSLock()
        private var count = 0
        let reply: HttpResponse

        init(reply: HttpResponse) { self.reply = reply }

        var calls: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }

        private func bump() {
            lock.lock()
            count += 1
            lock.unlock()
        }

        func execute(_ request: HttpRequest) async throws -> HttpResponse {
            bump()
            await entered.open()
            await release.wait()
            return reply
        }
    }

    /// two calls racing a near-expiry token refresh only once
    func testTwoCallsRacingANearExpiryTokenRefreshOnlyOnce() async throws {
        store.grant = grant("stale", "staleRefresh", expiresAtEpochS: nowS + 100)
        let transport = GatedTransport(reply: refreshReply("freshA", "freshR"))
        let session = session(transport)

        let first = Task { try await session.get() }
        await transport.entered.wait()  // the first call is on the network, holding the lock

        let second = Task { try await session.get() }
        // Gives the second call a moment to actually queue up on the lock before it is freed,
        // rather than start after the first has already finished.
        try await Task.sleep(nanoseconds: 100_000_000)
        await transport.release.open()

        let results = [try await first.value, try await second.value]
        XCTAssertEqual(results, ["freshA", "freshA"])
        XCTAssertEqual(transport.calls, 1, "only the loser should have found nothing to refresh")
    }

    // ---- beyond the Kotlin ----------------------------------------------------------------

    /// exactly the refresh window is not enough life, and one second more is
    func testExactlyTheRefreshWindowIsEnoughLifeAndOneSecondLessIsNot() async throws {
        // Ten minutes of headroom: 600 s left is kept, 599 s left is refreshed.
        store.grant = grant("edge", "r", expiresAtEpochS: nowS + 600)
        let kept = FakeTransport()
        let keptToken = try await session(kept).get()
        XCTAssertEqual(keptToken, "edge")
        XCTAssertTrue(kept.requests.isEmpty)

        store.grant = grant("edge", "r", expiresAtEpochS: nowS + 599)
        let refreshed = FakeTransport()
        refreshed.enqueue(refreshReply("new", "newR"))
        let refreshedToken = try await session(refreshed).get()
        XCTAssertEqual(refreshedToken, "new")
    }

    /// an unreadable refresh reply leaves the grant alone and is not mistaken for a revocation
    func testAnUnreadableRefreshReplyLeavesTheGrantAloneAndIsNotMistakenForARevocation() async {
        store.grant = grant("stale", "staleRefresh", expiresAtEpochS: nowS + 100)
        let transport = FakeTransport()
        transport.enqueue(HttpResponse(200, [:], "<html>"))

        let error = await thrownError { _ = try await session(transport).get() }

        XCTAssertNotNil(error as? StravaResponseError)
        XCTAssertEqual(store.grant?.refreshToken, "staleRefresh")
    }

    /// a network failure during refresh leaves the grant alone
    func testANetworkFailureDuringRefreshLeavesTheGrantAlone() async {
        store.grant = grant("stale", "staleRefresh", expiresAtEpochS: nowS + 100)
        let transport = FakeTransport()
        transport.enqueueFailure(HttpTransportError("offline"))

        let error = await thrownError { _ = try await session(transport).get() }

        XCTAssertEqual(error as? HttpTransportError, HttpTransportError("offline"))
        XCTAssertEqual(store.grant?.accessToken, "stale")
    }
}
