import Foundation

/// One connected grant: the tokens, when the access token expires, the scopes Strava actually
/// gave, and the athlete's name for the menu row and the "Connected to Strava as …" line.
///
/// `expiresAtEpochS` is epoch **seconds**, matching Strava's own `expires_at` field, not the
/// millisecond epoch the rest of the app uses for `atMillis`: converting at the one place that
/// reads it (`StravaSession`) is cheaper than a wrong unit compiling silently everywhere else.
public struct StravaGrant: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAtEpochS: Int64
    public let scopes: Set<String>
    public let athleteName: String?

    public init(accessToken: String, refreshToken: String, expiresAtEpochS: Int64,
                scopes: Set<String>, athleteName: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAtEpochS = expiresAtEpochS
        self.scopes = scopes
        self.athleteName = athleteName
    }
}

/// Where the Strava connection keeps what has to survive the app closing: the grant, the OAuth
/// attempt in flight, the two settings the upload reads, and the upload ledger.
///
/// Android keeps all of this in a prefs file named `strava`, excluded by name from every backup,
/// because a token living beside the body weight would mean excluding the body weight too. The
/// iOS store is the Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (P20), which
/// stays out of backups and device transfers for the same reason; this protocol is what the rest
/// of the feature sees of it, and a dictionary stands in for it in the tests.
///
/// `set` must be durable when it returns. Strava rotates the refresh token on every refresh and
/// invalidates the old one at once, so the new one has to be on disk before the access token it
/// came with is used (Android writes with `commit()`, not `apply()`, for the same reason).
public protocol StravaStorage: AnyObject, Sendable {
    func string(forKey key: String) -> String?
    /// Stores `value`, or forgets the key when it is nil.
    func set(_ value: String?, forKey key: String)
    /// Every key held, in no particular order.
    func keys() -> [String]
}

/// A `StravaStorage` that lives and dies with the process: for tests, and for a debug build that
/// replays a session without touching the Keychain.
public final class InMemoryStravaStorage: StravaStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    public init() {}

    public func string(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    public func set(_ value: String?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    public func keys() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(values.keys)
    }
}

/// Everything about the athlete's Strava connection that has to survive the app closing: the
/// grant itself, the OAuth attempt in flight, and the two settings the upload reads.
///
/// The grant is written as **one** item. Android writes five prefs keys in one `commit()`, which is
/// atomic; five Keychain items are not, and a process that died between them could leave a new
/// access token beside the old refresh token, which Strava has already invalidated. One item
/// cannot be half written.
public final class StravaTokenStore: @unchecked Sendable {

    private let storage: StravaStorage

    public init(storage: StravaStorage) {
        self.storage = storage
    }

    /// The current grant, or nil when there isn't one. Setting it to nil is how a grant is
    /// forgotten: see `clearGrant`.
    public var grant: StravaGrant? {
        get {
            guard let raw = storage.string(forKey: Self.keyGrant),
                  let object = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any],
                  let accessToken = object["access_token"] as? String,
                  let refreshToken = object["refresh_token"] as? String
            else { return nil }
            return StravaGrant(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAtEpochS: (object["expires_at"] as? NSNumber)?.int64Value ?? 0,
                scopes: Set((object["scopes"] as? [String]) ?? []),
                athleteName: object["athlete_name"] as? String)
        }
        set {
            guard let value = newValue else {
                storage.set(nil, forKey: Self.keyGrant)
                return
            }
            var object: [String: Any] = [
                "access_token": value.accessToken,
                "refresh_token": value.refreshToken,
                "expires_at": value.expiresAtEpochS,
                "scopes": value.scopes.sorted()
            ]
            if let name = value.athleteName { object["athlete_name"] = name }
            // Strings, a number and an array of strings always encode; if that ever stopped being
            // true, keeping what is stored is better than erasing the only grant there is.
            guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
            storage.set(String(decoding: data, as: UTF8.self), forKey: Self.keyGrant)
        }
    }

    /// Whether there is a grant to upload with. Read before any upload is queued.
    public var connected: Bool { grant != nil }

    /// Forgets the grant. Used on DISCONNECT and when a refresh comes back revoked.
    public func clearGrant() {
        grant = nil
    }

    /// The `state` the app minted right before it opened Strava's consent page, so the redirect
    /// handler can tell a genuine redirect from anything else that might land on the same scheme.
    /// Nil once there is no attempt in flight: see `StravaAuth.parseRedirect`.
    public var pendingState: String? {
        get { storage.string(forKey: Self.keyPendingState) }
        set { storage.set(newValue, forKey: Self.keyPendingState) }
    }

    /// Set when the athlete asked to connect *in order to* upload one particular attempt (from the
    /// results screen) rather than from the menu on its own. The redirect handler enqueues this
    /// attempt once connected, then clears it.
    public var afterConnectUploadAtMillis: Int64? {
        get {
            // `atMillis` is always a positive epoch millisecond, so -1 is a safe "unset" marker.
            storage.string(forKey: Self.keyAfterConnect).flatMap(Records.toLong).flatMap { $0 == -1 ? nil : $0 }
        }
        set { storage.set(newValue.map { String($0) }, forKey: Self.keyAfterConnect) }
    }

    /// Whether a saved attempt uploads on its own. On by default once connected.
    public var autoUpload: Bool {
        get { storage.string(forKey: Self.keyAutoUpload) != "0" }
        set { storage.set(newValue ? "1" : "0", forKey: Self.keyAutoUpload) }
    }

    static let keyGrant = "grant"
    static let keyPendingState = "pending_state"
    static let keyAfterConnect = "after_connect_upload_at_millis"
    static let keyAutoUpload = "auto_upload"
}

/// A lock that can be held across an `await`, which `NSLock` may not be. Waiters are let in one at
/// a time, in the order they arrived.
final class AsyncLock: @unchecked Sendable {

    private let state = NSLock()
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withLock<T>(_ body: () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await body()
    }

    private func acquire() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            state.lock()
            if held {
                waiters.append(continuation)
                state.unlock()
            } else {
                held = true
                state.unlock()
                continuation.resume()
            }
        }
    }

    private func release() {
        state.lock()
        if waiters.isEmpty {
            held = false
            state.unlock()
        } else {
            let next = waiters.removeFirst()
            state.unlock()
            next.resume()
        }
    }
}

/// The live `StravaAccessToken`: reads the stored grant, refreshes it when it is close to expiry,
/// persists the refreshed grant before handing out the access token inside it, and clears the
/// grant when Strava says it is no longer good for anything.
///
/// `clock` returns epoch milliseconds; tests inject one that does not actually wait six hours to
/// reach the refresh window.
///
/// `get` takes a lock shared by every session in the process, not one per `StravaTokenStore`. Two
/// uploads racing to refresh at the same moment would each rotate the refresh token Strava just
/// handed the other one, so the loser's own refresh, started before it could see the winner's
/// write, would persist a token Strava has already invalidated. The lock serialises them: the loser
/// waits, then rereads a grant that is already fresh and returns it without refreshing a second
/// time. Android's `synchronized` becomes an async lock, because a thread lock cannot be held
/// across the network call.
public final class StravaSession: StravaAccessToken, @unchecked Sendable {

    private let store: StravaTokenStore
    private let auth: StravaAuth
    private let clock: @Sendable () -> Int64

    public init(store: StravaTokenStore, auth: StravaAuth,
                clock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.store = store
        self.auth = auth
        self.clock = clock
    }

    public func get() async throws -> String {
        try await Self.lock.withLock {
            // A caller cancelled while it waited (the app was suspended and its background time
            // ran out) must not go on to spend a refresh on the network.
            try Task.checkCancellation()
            guard let grant = store.grant else { throw StravaAuthError() }
            let secondsLeft = grant.expiresAtEpochS - clock() / 1000
            if secondsLeft >= Self.refreshWindowS { return grant.accessToken }

            do {
                let refreshed = try await auth.refresh(grant.refreshToken)
                store.grant = refreshed
                return refreshed.accessToken
            } catch let error as StravaAuthError {
                if error.revoked { store.clearGrant() }
                throw error
            }
        }
    }

    /// Refreshes with ten minutes of headroom, so an upload never races the access token's own
    /// expiry mid-request.
    private static let refreshWindowS: Int64 = 600
    private static let lock = AsyncLock()
}
