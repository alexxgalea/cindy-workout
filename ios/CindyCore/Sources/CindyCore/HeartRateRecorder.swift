import Foundation

/// Puts heart-rate readings from a `HeartRateSource` onto the workout clock.
///
/// Pure and main-thread-only, with every time injected rather than read from the system, for the same
/// reason `WorkoutEngine` is: a clock that reads itself cannot be driven by a test. The clock it keeps
/// is the workout clock (the same one behind `Attempt.durationMs` and `Attempt.roundSplitsMs`), not
/// wall time, so a trace and its attempt agree about when things happened without any translation.
///
/// A watch does not stop broadcasting just because the workout has not started, is paused, or has
/// finished. `offer` is therefore always safe to call; what changes with the recorder's state is only
/// whether a reading gets *recorded*, or merely remembered as the most recent one seen. The latter is
/// what lets a reading from just before `start` or `resume` seed the trace instead of leaving an
/// honest gap at the very beginning of a segment where a real bpm was in fact known. Port of
/// `HeartRateRecorder.kt`.
public final class HeartRateRecorder {

    private enum State { case idle, running, paused, finished }

    private var state = State.idle

    private var startedAtMillis: Int64 = 0
    /// The clock value the current running segment started from.
    private var clockBase: Int64 = 0
    /// The elapsed time the current running segment started from.
    private var runningSince: Int64 = 0
    /// The clock never runs backward, even if a delayed callback hands `offer` a stale time.
    private var clockHighWaterMs: Int64 = 0

    private var pausedClockMs: Int64 = 0
    private var pausedAtElapsedMs: Int64 = 0

    private var lastRecordedClockMs: Int64?

    /// The most recent reading `offer` has seen, in any state: the seed for the next segment.
    private var lastReadingBpm: Int?
    private var lastReadingAtElapsedMs: Int64 = 0

    private var samples: [HeartRateSample] = []
    private var pauses: [HeartRatePause] = []

    public static let minSpacingMs: Int64 = 900

    public init() {}

    /// Starts a fresh trace. `wallMillis` is stamped as `HeartRateTrace.startedAtMillis`.
    public func start(atElapsedMs: Int64, wallMillis: Int64) {
        state = .running
        startedAtMillis = wallMillis
        clockBase = 0
        runningSince = atElapsedMs
        clockHighWaterMs = 0
        lastRecordedClockMs = nil
        samples.removeAll()
        pauses.removeAll()
        seedFromRememberedReading(atElapsedMs)
    }

    /// Freezes the clock. Readings still arrive, through `offer`, but stop being recorded.
    public func pause(atElapsedMs: Int64) {
        if state != .running { return }
        pausedClockMs = clockAt(atElapsedMs)
        pausedAtElapsedMs = atElapsedMs
        state = .paused
    }

    /// Resumes the clock where `pause` left it, and closes the pause that `pause` opened.
    ///
    /// Seeds from the remembered reading exactly as `start` does: a strap kept broadcasting the whole
    /// time the clock was frozen, so the reading it sent just before this call is as good a seed for
    /// the new segment as one sent just before the workout began.
    public func resume(atElapsedMs: Int64) {
        if state != .paused { return }
        pauses.append(HeartRatePause(atClockMs: pausedClockMs, lengthMs: atElapsedMs - pausedAtElapsedMs))
        clockBase = pausedClockMs
        runningSince = atElapsedMs
        state = .running
        seedFromRememberedReading(atElapsedMs)
    }

    /// A reading arrived. Recorded only while the clock is running; otherwise just remembered, so a
    /// later `start` or `resume` can seed from it. Does nothing at all once `finish` has run.
    public func offer(bpm: Int, atElapsedMs: Int64) {
        if state == .finished { return }
        lastReadingBpm = bpm
        lastReadingAtElapsedMs = atElapsedMs
        if state == .running {
            record(clockAt(atElapsedMs), bpm)
        }
    }

    /// Closes the trace. While paused, the open pause is closed first (the same thing the workout
    /// already does with `pausedMs`), so a workout that ends mid-pause does not lose the time it spent there.
    ///
    /// Nil when nothing was ever recorded: an empty trace is not useful to `HeartRateStore` or to
    /// `Calories.estimate`, both of which already treat "no trace" as "use the MET model".
    public func finish(atElapsedMs: Int64) -> HeartRateTrace? {
        if state == .paused {
            pauses.append(HeartRatePause(atClockMs: pausedClockMs, lengthMs: atElapsedMs - pausedAtElapsedMs))
        }
        state = .finished
        if samples.isEmpty { return nil }
        return HeartRateTrace(startedAtMillis: startedAtMillis, samples: samples, pauses: pauses)
    }

    /// Back to nothing, including the remembered reading: a fresh `start` seeds from nothing.
    public func reset() {
        state = .idle
        startedAtMillis = 0
        clockBase = 0
        runningSince = 0
        clockHighWaterMs = 0
        lastRecordedClockMs = nil
        lastReadingBpm = nil
        lastReadingAtElapsedMs = 0
        samples.removeAll()
        pauses.removeAll()
    }

    private func seedFromRememberedReading(_ atElapsedMs: Int64) {
        guard let bpm = lastReadingBpm else { return }
        if atElapsedMs - lastReadingAtElapsedMs <= Calories.maxHoldMs {
            record(clockAt(atElapsedMs), bpm)
        }
    }

    private func clockAt(_ atElapsedMs: Int64) -> Int64 {
        let computed = clockBase + (atElapsedMs - runningSince)
        let clamped = max(computed, clockHighWaterMs)
        clockHighWaterMs = clamped
        return clamped
    }

    /// Caps the rate for straps that notify at 2 to 4 Hz; a sensor closer to 1 Hz passes untouched.
    private func record(_ clockMs: Int64, _ bpm: Int) {
        if let last = lastRecordedClockMs, clockMs - last < Self.minSpacingMs { return }
        samples.append(HeartRateSample(clockMs, bpm))
        lastRecordedClockMs = clockMs
    }
}
