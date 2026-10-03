import Foundation

/// One rep's moment on the workout clock: when it banked, which movement it belongs to, and how.
public struct RepMark: Equatable, Sendable {
    public let clockMs: Int64
    public let movement: Exercise
    public let manual: Bool

    public init(_ clockMs: Int64, _ movement: Exercise, manual: Bool) {
        self.clockMs = clockMs
        self.movement = movement
        self.manual = manual
    }
}

/// Where every rep of a session landed on the workout clock, for the chart a later screen draws.
///
/// `follow` is handed the engine's own banked `totalReps`, not the `RepEvent` that came with them,
/// and compares that number to what it saw last: risen by n -> n reps just banked, so append n
/// marks; fallen by n -> an undo just took them back, so drop the last n; unchanged -> nothing
/// happened that counts, whatever event fired. A skip is free by construction this way: it moves
/// the exercise on without moving the total.
///
/// That is deliberate rather than switching on the event. A stale *state* frame can be dropped
/// but never a stale *event* one, so in principle the two are equivalent — but a total can also
/// jump by more than one between two calls, exactly when a state frame carrying an intermediate
/// count was the one dropped, and an event-keyed version would have to special-case that instead
/// of simply reading the number that is already correct. Comparing totals also keeps this log
/// unable to disagree with the score the session is actually saved under: a rep here is "banked,
/// never inferred", the same rule `Attempt.countedReps` exists to hold, because it comes from the
/// one number the engine itself commits to rather than from re-deriving a count per event.
public final class RepLog {

    private var log: [RepMark] = []
    private var lastTotal = 0
    private var lastManual = 0

    public init() {}

    public var marks: [RepMark] { log }

    /// Starts a new session: forgets every mark left over from whatever came before.
    public func start() {
        log.removeAll()
        lastTotal = 0
        lastManual = 0
    }

    /// Reconciles `marks` with the engine's latest banked totals.
    ///
    /// `movement` is whichever one the rep that moved the total belongs to — the caller's job, not
    /// this class's, since only the caller knows whether the engine has already advanced past it
    /// (see `Exercise.previous`: the finishing rep of a movement is read after the snapshot has
    /// moved on). When the total has fallen, `movement` is not consulted: an undo only ever
    /// removes the latest mark, whatever it was tagged with.
    public func follow(totalReps: Int, manualReps: Int, movement: Exercise, clockMs: Int64) {
        let delta = totalReps - lastTotal
        if delta > 0 {
            let manualDelta = min(max(manualReps - lastManual, 0), delta)
            for i in 0..<delta {
                log.append(RepMark(clockMs, movement, manual: i >= delta - manualDelta))
            }
        } else if delta < 0 {
            log.removeLast(min(-delta, log.count))
        }
        lastTotal = totalReps
        lastManual = manualReps
    }
}
