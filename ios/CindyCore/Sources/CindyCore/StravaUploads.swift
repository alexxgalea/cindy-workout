import Foundation

/// Where an attempt's Strava upload has got to.
public enum StravaUploadState: String, CaseIterable, Sendable {
    case queued = "QUEUED"
    case processing = "PROCESSING"
    case done = "DONE"
    case failed = "FAILED"
    case needsReconnect = "NEEDS_RECONNECT"
    case unavailable = "UNAVAILABLE"
}

/// One ledger entry: the state, plus whatever the upload has learned along the way.
///
/// `uploadId` is set the moment the file is accepted, before anything is polled: it is what stops a
/// retried upload ever sending the same file twice. `activityId` is set once Strava has finished
/// processing it. `message` is only ever `failed`'s reason.
public struct StravaUploadStatus: Equatable, Sendable {
    public let state: StravaUploadState
    public let uploadId: String?
    public let activityId: Int64?
    public let message: String?

    public init(_ state: StravaUploadState, uploadId: String? = nil, activityId: Int64? = nil, message: String? = nil) {
        self.state = state
        self.uploadId = uploadId
        self.activityId = activityId
        self.message = message
    }
}

/// Remembers what happened to each saved attempt's Strava upload, and decides which ones are to be
/// sent.
///
/// This is the state machine and its memory. What Android hands to WorkManager (running the upload
/// when there is a network, backing off, surviving a restart) is the app's to do on iOS, from this
/// ledger: an attempt that is `queued` or `processing` is one still to be sent or checked (P20).
///
/// The ledger lives in the same `StravaStorage` as the grant, and for the same reason: Android
/// excludes it from every kind of backup, and a queued or half-finished upload is exactly the state
/// that must not resurrect itself on a restored backup or a new phone. It is keyed by
/// `Attempt.atMillis`, one entry per attempt, so an upload resumed after a process death can find
/// its own status again rather than starting the attempt over from nothing.
public final class StravaUploads: @unchecked Sendable {

    private let storage: StravaStorage

    public init(storage: StravaStorage) {
        self.storage = storage
    }

    private static let keyPrefix = "upload_"

    /// The unique name for one attempt's upload: one upload per attempt, ever.
    public static func uniqueWorkName(atMillis: Int64) -> String { "strava-upload-\(atMillis)" }

    /// The ledger entry for `atMillis`, or nil when nothing has ever been queued for it.
    public func status(atMillis: Int64) -> StravaUploadStatus? {
        Self.decode(storage.string(forKey: Self.key(atMillis)))
    }

    /// Marks `atMillis` as queued. The caller then makes sure an upload runs for it.
    ///
    /// An upload id already on file is carried over. It means Strava accepted the file on an
    /// earlier run, and the next run has to poll that id rather than send the file again.
    public func queue(atMillis: Int64) {
        let acceptedAs = status(atMillis: atMillis)?.uploadId
        write(atMillis: atMillis, StravaUploadStatus(.queued, uploadId: acceptedAs))
    }

    /// What the app asks after a save: should this attempt go to Strava on its own? When so, it is
    /// queued and the answer is true.
    ///
    /// True only when the feature is available, the athlete is connected, and automatic upload is
    /// switched on. Every reason an attempt might *not* upload on its own lives in this one
    /// decision, so it is testable without a screen, and the screen never has to know any of them.
    public func attemptSaved(atMillis: Int64, config: StravaConfig, tokens: StravaTokenStore) -> Bool {
        if !config.available { return false }
        if !tokens.connected || !tokens.autoUpload { return false }
        queue(atMillis: atMillis)
        return true
    }

    /// Queues every attempt still waiting on a reconnect, oldest first, and returns them. Called
    /// once the athlete has connected again, so the attempts that piled up while disconnected are
    /// not left stranded.
    public func requeueNeedingReconnect() -> [Int64] {
        var requeued: [Int64] = []
        for key in storage.keys() where key.hasPrefix(Self.keyPrefix) {
            guard let atMillis = Records.toLong(String(key.dropFirst(Self.keyPrefix.count))),
                  let status = Self.decode(storage.string(forKey: key)) else { continue }
            if status.state == .needsReconnect { requeued.append(atMillis) }
        }
        requeued.sort()
        for atMillis in requeued { queue(atMillis: atMillis) }
        return requeued
    }

    /// Every attempt with a ledger entry, oldest first, with what is known of it.
    public func entries() -> [(atMillis: Int64, status: StravaUploadStatus)] {
        var found: [(atMillis: Int64, status: StravaUploadStatus)] = []
        for key in storage.keys() where key.hasPrefix(Self.keyPrefix) {
            guard let atMillis = Records.toLong(String(key.dropFirst(Self.keyPrefix.count))),
                  let status = Self.decode(storage.string(forKey: key)) else { continue }
            found.append((atMillis, status))
        }
        return found.sorted { $0.atMillis < $1.atMillis }
    }

    /// Forgets every ledger entry. Called when the record board is cleared, so the app stops asking
    /// Strava about attempts it no longer has on file. Nothing already on Strava is touched: this
    /// is only the app's own memory of what it did.
    public func clear() {
        for key in storage.keys() where key.hasPrefix(Self.keyPrefix) {
            storage.set(nil, forKey: key)
        }
    }

    /// Written by the upload as it learns more; also used by `queue`.
    ///
    /// The upload id has to be on disk before the upload goes on to poll it, or a process death in
    /// between leaves the next run no way to know the file was already accepted, which is what
    /// `StravaStorage.set` being durable is for.
    public func write(atMillis: Int64, _ status: StravaUploadStatus) {
        storage.set(Self.encode(status), forKey: Self.key(atMillis))
    }

    private static func key(_ atMillis: Int64) -> String { "\(keyPrefix)\(atMillis)" }

    // ---- codec ------------------------------------------------------------------------------

    public static func encode(_ status: StravaUploadStatus) -> String {
        [
            status.state.rawValue,
            status.uploadId ?? "",
            status.activityId.map { String($0) } ?? "",
            status.message ?? ""
        ].joined(separator: "|")
    }

    public static func decode(_ raw: String?) -> StravaUploadStatus? {
        guard let raw = raw else { return nil }
        // At most four pieces: a failure message may itself contain a bar.
        let p = raw.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard p.count == 4, let state = StravaUploadState(rawValue: p[0]) else { return nil }
        return StravaUploadStatus(
            state,
            uploadId: p[1].isEmpty ? nil : p[1],
            activityId: Records.toLong(p[2]),
            message: p[3].isEmpty ? nil : p[3])
    }
}
