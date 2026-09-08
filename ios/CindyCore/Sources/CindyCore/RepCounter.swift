import Foundation

/// Counts oscillations of a scalar signal by measuring how far it climbs away from its trough.
///
/// Callers must orient the signal so the *bottom* of the movement is the low value and the *top*
/// is the high value. A rep is booked at the top: lockout of a push-up, standing out of a squat,
/// chin over the bar on a pull-up.
///
/// ### Why the band is learned rather than fixed
///
/// Fixed thresholds assume the camera sees the movement the same way every time, and it does not.
/// A phone standing on the floor foreshortens everything above it, so the same pull-up projects a
/// visibly smaller swing than it does from chest height. Since nobody has a second person holding
/// the camera, the floor is the normal case and the counter has to absorb it.
///
/// So the thresholds come from the range the athlete actually produces, and only the *shape* of
/// the oscillation matters. The first rep is judged against `minRange`, the travel below which a
/// wobble is not believed to be a rep; after that the band tightens to what has been demonstrated.
///
/// ### Why a trough rather than a threshold crossing
///
/// Arming on a fixed low threshold fails under a squashed range: the signal never gets low enough,
/// so it never arms and every rep is silently discarded. Tracking the lowest value since the last
/// rep removes the ordering problem — the range is allowed to still be unknown while the athlete
/// is at the bottom of the movement.
public final class RepCounter {

    public enum Phase { case unknown, down, up }

    /// Share of the observed travel held back as dead zone at each end.
    private static let margin: Float = 0.30
    /// How fast a stale extreme is forgotten, in signal units per frame.
    private static let decay: Float = 0.05

    private let downBelow: Float
    private let upAbove: Float
    private let minRepMs: Int64
    private let smoothing: Float
    private let minRange: Float

    public private(set) var phase: Phase = .unknown
    public private(set) var count = 0
    public private(set) var smoothed: Float = .nan

    private var seenLow: Float = .nan
    private var seenHigh: Float = .nan
    /// Lowest value since the last booked rep — the foot of the climb being measured.
    private var trough: Float = .nan
    private var lastRepAt: Int64?
    /// Cleared on each rep, set again only once the signal has genuinely come back down.
    /// Starts true so the first rep of a session, taken before any range is known, can count.
    private var armed = true

    public init(
        downBelow: Float,
        upAbove: Float,
        minRepMs: Int64 = 350,
        smoothing: Float = 0.4,
        minRange: Float = 0
    ) {
        self.downBelow = downBelow
        self.upAbove = upAbove
        self.minRepMs = minRepMs
        self.smoothing = smoothing
        self.minRange = minRange
    }

    /// Travel observed so far. Zero until samples arrive.
    public var learnedRange: Float {
        (seenLow.isNaN || seenHigh.isNaN) ? 0 : seenHigh - seenLow
    }

    /// Whether the band is wide enough to set the thresholds itself.
    public var calibrated: Bool { minRange > 0 && learnedRange >= minRange }

    /// Travel the calibration step should see before it trusts the camera placement.
    public var requiredRange: Float { minRange }

    /// - Returns: true if this sample completed a rep.
    @discardableResult
    public func update(_ raw: Float, now: Int64) -> Bool {
        guard !raw.isNaN else { return false }
        smoothed = smoothed.isNaN ? raw : smoothed + smoothing * (raw - smoothed)
        let s = smoothed

        observe(s)
        trough = trough.isNaN ? s : min(trough, s)

        let range = learnedRange
        let useBand = calibrated
        let needed = useBand ? (1 - 2 * Self.margin) * range : upAbove - downBelow
        let topOfBand = useBand ? seenHigh - Self.margin * range : upAbove
        let bottomOfBand = useBand ? seenLow + Self.margin * range : downBelow

        if s <= bottomOfBand {
            phase = .down
            armed = true
        } else if s >= topOfBand {
            phase = .up
        }

        let climbed = s - trough
        let atTop = useBand ? s >= topOfBand : s > upAbove
        let debounced = lastRepAt.map { now - $0 >= minRepMs } ?? true
        if armed && climbed >= needed && atTop && debounced {
            lastRepAt = now
            count += 1
            armed = false
            // Restart the measurement from here so the descent establishes the next trough.
            trough = s
            return true
        }
        return false
    }

    private func observe(_ s: Float) {
        seenLow = seenLow.isNaN ? s : min(seenLow, s)
        seenHigh = seenHigh.isNaN ? s : max(seenHigh, s)
        // Let stale extremes fade, but never shrink the band below the range worth trusting.
        if seenHigh - seenLow > max(minRange, 1) {
            seenLow += Self.decay
            seenHigh -= Self.decay
        }
    }

    /// Overwrites the score, for stepping back across a movement boundary.
    public func setCount(_ n: Int) {
        count = max(0, n)
        phase = .unknown
        armed = true
        trough = .nan
    }

    /// Takes a rep back off the score — the "-1" override for a miscount.
    public func forceDecrement() {
        guard count > 0 else { return }
        count -= 1
        phase = .unknown
        armed = true
        trough = .nan
    }

    /// Forgets the learned band without touching the score.
    ///
    /// Used when the camera's view of the athlete changes — a flip, or a pause long enough that
    /// the phone or the athlete has moved — because a band learned from the old geometry will
    /// quietly mis-score the new one.
    public func resetBand() {
        seenLow = .nan
        seenHigh = .nan
        trough = .nan
        smoothed = .nan
        phase = .unknown
        armed = true
    }

    /// Books a rep without a signal crossing — used by the manual "+1" override.
    public func forceIncrement() {
        count += 1
        phase = .unknown
        armed = false
        trough = smoothed
    }

    public func reset() {
        phase = .unknown
        count = 0
        smoothed = .nan
        lastRepAt = nil
        trough = .nan
        armed = true
        seenLow = .nan
        seenHigh = .nan
    }

    /// Drops the counted reps for the next movement but keeps the learned band — it describes
    /// this athlete in front of this camera, which has not changed because the round has.
    public func resetCount() {
        count = 0
        phase = .unknown
        smoothed = .nan
        trough = .nan
        armed = true
    }
}
