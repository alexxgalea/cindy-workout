import Foundation

/// Takes one session out of the app, with everything filed beside it. Port of `SessionDiscard.kt`.
///
/// A session is not one record. The attempt on the board has a heart-rate trace, the time of every
/// rep and (from P19) a Strava ledger entry with its queued upload, each in a different place and
/// all keyed by `Attempt.atMillis`. They live here as a single call so a screen never has to
/// remember how many places a session is in; the next thing filed under a session is added here,
/// once.
///
/// Badges, the streak and records are worked out from the attempts on the board each time they are
/// shown, so removing the attempt takes whatever it earned with it and there is nothing separate to
/// remove.
public struct SessionDiscard {

    private let records: RecordStore
    private let heartRates: HeartRateStore
    private let repTimes: RepTimesStore

    /// The defaults are the app's own: `UserDefaults.standard` and the two folders in Application
    /// Support. A test passes throwaway ones.
    public init(records: RecordStore = RecordStore(),
                heartRates: HeartRateStore = HeartRateStore(),
                repTimes: RepTimesStore = RepTimesStore()) {
        self.records = records
        self.heartRates = heartRates
        self.repTimes = repTimes
    }

    /// Removes the session at `atMillis`, and says whether it was on the board.
    ///
    /// The attempt goes first. If the process dies half way, what is left is a file with no attempt
    /// to belong to, which nothing reads; the other order would leave an attempt that had lost its
    /// heart-rate trace, which looks like a session that never had one.
    @discardableResult
    public func discard(atMillis: Int64) -> Bool {
        let removed = records.remove(atMillis: atMillis)
        heartRates.remove(atMillis: atMillis)
        repTimes.remove(atMillis: atMillis)
        return removed
    }
}
