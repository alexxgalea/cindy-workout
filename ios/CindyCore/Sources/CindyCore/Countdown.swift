import Foundation

/// The countdown that stands between tapping REC and the camera rolling.
///
/// The thing that can go wrong here is not drawing but *timing*: a callback that fires twice starts
/// two recordings, a callback that fires early films the athlete still holding the phone, and a
/// cancelled countdown that fires anyway records a session nobody asked to record. So the timing is
/// a pure type with the clock handed in, and the view only draws what it says.
public final class Countdown {

    public static let defaultSeconds = 3

    private var endAt: Int64 = 0
    private var onFinished: (() -> Void)?
    public private(set) var seconds = Countdown.defaultSeconds

    public init() {}

    /// True from `start` until it finishes or is cancelled.
    public var isRunning: Bool { onFinished != nil }

    /// What the screen reader is told when it begins.
    public var announcement: String { "Recording in \(seconds)" }

    /// What the view's accessibility description says while it counts.
    public var accessibilityLabel: String { "Recording starts in \(seconds) seconds" }

    /// Starts counting down from `fromSeconds` (at least one). Starting again calls the first off.
    public func start(fromSeconds: Int = Countdown.defaultSeconds, now: Int64, onFinished: @escaping () -> Void) {
        cancel()
        seconds = max(fromSeconds, 1)
        endAt = now + Int64(seconds) * 1000
        self.onFinished = onFinished
    }

    /// Calls it off. Tapping again during the count cancels rather than restarting, because a
    /// countdown you cannot stop is a recording you cannot refuse.
    public func cancel() {
        onFinished = nil
    }

    /// Moves the count to `now`, and finishes it, once, if its time is up. Called every frame.
    public func tick(now: Int64) {
        guard isRunning, now >= endAt else { return }
        let done = onFinished
        onFinished = nil
        done?()
    }

    /// The digit to show: the whole seconds left, rounded up, and never below one. `nil` when not running.
    public func digit(now: Int64) -> Int? {
        guard isRunning else { return nil }
        let left = max(endAt - now, 0)
        return max(Int((Double(left) / 1000).rounded(.up)), 1)
    }

    /// How far through the current second it is, 0 to 1: the ring sweeps `1 - into`, and the digit
    /// pops and fades in over its first fifth. `nil` when not running.
    public func into(now: Int64) -> Float? {
        guard isRunning, let digit = digit(now: now) else { return nil }
        let left = max(endAt - now, 0)
        return 1 - Float(left - Int64(digit - 1) * 1000) / 1000
    }
}
