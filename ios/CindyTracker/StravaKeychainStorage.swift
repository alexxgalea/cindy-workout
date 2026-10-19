import Foundation
import Security
import CindyCore

/// Where the Strava connection is kept: the Keychain, as generic passwords under one service.
///
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` keeps it out of backups and device transfers,
/// as Android keeps its `strava` prefs out of both (a token living beside the body weight would mean
/// excluding the body weight too), and still readable by a background refresh once the phone has been
/// unlocked after a restart.
///
/// Each write is done when `set` returns, which `StravaStorage` asks: a refresh token Strava has
/// rotated must be stored before the access token that came with it is used.
final class StravaKeychainStorage: StravaStorage, @unchecked Sendable {

    private let service: String

    init(service: String = "\(Bundle.main.bundleIdentifier ?? "com.cindy.tracker").strava") {
        self.service = service
    }

    func string(forKey key: String) -> String? {
        var query = base(key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String?, forKey key: String) {
        guard let value = value else {
            SecItemDelete(base(key) as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(base(key) as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = base(key)
            item[kSecValueData] = data
            item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    func keys() -> [String] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let rows = result as? [[String: Any]] else { return [] }
        return rows.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    private func base(_ key: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: key]
    }
}

/// A `StravaStorage` that says when it was written to, so a screen showing the ledger can redraw
/// without asking: the upload changes it from wherever it happens to be running.
final class ObservedStravaStorage: StravaStorage, @unchecked Sendable {

    private let inner: StravaStorage
    private let changed: @Sendable () -> Void

    init(_ inner: StravaStorage, changed: @escaping @Sendable () -> Void) {
        self.inner = inner
        self.changed = changed
    }

    func string(forKey key: String) -> String? { inner.string(forKey: key) }

    func set(_ value: String?, forKey key: String) {
        inner.set(value, forKey: key)
        changed()
    }

    func keys() -> [String] { inner.keys() }
}
