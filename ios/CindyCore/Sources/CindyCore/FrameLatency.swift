import Foundation

/// A monotonic clock in nanoseconds: the one durations are measured on.
///
/// Not a wall clock, which can step sideways when it is corrected. It is also the clock iOS stamps
/// camera frames with (the host time clock), which is what makes `FrameLatency` a subtraction here.
public func monotonicNanos() -> Int64 { Int64(DispatchTime.now().uptimeNanoseconds) }

/// How old a frame is by the time it reaches the screen, and the arithmetic that makes the answer
/// trustworthy.
///
/// ### Why this is not just a subtraction on Android, and what is left of that here
///
/// On Android a camera's frame timestamps come from one of two clocks, and the device says which,
/// so the source is read once when the camera binds and a reading whose domain was never resolved
/// is reported as unavailable rather than guessed at. An iPhone stamps every frame with the host
/// time clock, so there is one domain and nothing to choose between. The shape is kept all the
/// same: nothing is reported until the camera has been bound and `resolve` called, and a reading
/// that is negative or implausibly old is withheld, because a plausible-looking number in a debug
/// readout is worse than no number: it will be believed.
public final class FrameLatency: @unchecked Sendable {

    private static let implausibleMs: Int64 = 5_000

    private let now: () -> Int64
    private let lock = NSLock()
    private var _resolved = false

    public init(now: @escaping () -> Int64 = monotonicNanos) {
        self.now = now
    }

    /// True once the camera has been bound and its timestamps are known to be on this clock.
    public var resolved: Bool {
        lock.lock(); defer { lock.unlock() }
        return _resolved
    }

    /// Call when a camera binds. Safe to call on every bind.
    public func resolve() {
        lock.lock(); _resolved = true; lock.unlock()
    }

    /// Milliseconds since `captureNanos` was stamped by the sensor, or `nil` when that cannot be
    /// stated honestly — either the clock is unresolved, or the arithmetic produced something
    /// impossible, which is the signature of having guessed the domain wrong.
    public func sinceCapture(_ captureNanos: Int64) -> Int64? {
        if !resolved { return nil }
        let ms = (now() - captureNanos) / 1_000_000
        // A frame cannot have been captured in the future, and one older than this arrived from a
        // clock we are not actually on. Either way the number would be a fiction.
        return ms < 0 || ms > Self.implausibleMs ? nil : ms
    }
}

/// A short window of recent samples, summarised by its median.
///
/// The median rather than the mean because the thing being measured is a phone doing several jobs
/// at once: a single pause or a bound scheduler decision drags a mean somewhere no frame actually
/// was, and a debug readout that swings on one bad frame cannot be read off a screen from across
/// the room — which is the only way anyone will read this one.
public final class Rolling {

    private let size: Int
    private var samples: [Int64]
    private var count = 0
    private var next = 0

    public init(_ size: Int = 30) {
        self.size = size
        samples = Array(repeating: 0, count: size)
    }

    public func add(_ sample: Int64) {
        samples[next] = sample
        next = (next + 1) % size
        if count < size { count += 1 }
    }

    public func reset() {
        count = 0
        next = 0
    }

    /// Median of the window, or `nil` until anything has been recorded.
    public func median() -> Int64? {
        if count == 0 { return nil }
        let window = samples[0..<count].sorted()
        return window[count / 2]
    }
}

/// Frames per second, counted over a rolling wall-clock window rather than derived from an
/// interval, so a stall shows up as the rate falling instead of one long gap being averaged away.
public final class RateMeter: @unchecked Sendable {

    private let windowMs: Int64
    private let lock = NSLock()
    private var stamps: [Int64] = []

    public init(windowMs: Int64 = 2_000) {
        self.windowMs = windowMs
    }

    /// A monotonic reading rather than a wall clock: this measures durations.
    private func nowMs() -> Int64 { monotonicNanos() / 1_000_000 }

    private func trim(_ nowMs: Int64) {
        while let first = stamps.first, nowMs - first > windowMs { stamps.removeFirst() }
    }

    public func mark(nowMs: Int64? = nil) {
        let now = nowMs ?? self.nowMs()
        lock.lock(); defer { lock.unlock() }
        stamps.append(now)
        trim(now)
    }

    public func reset() {
        lock.lock(); stamps.removeAll(); lock.unlock()
    }

    /// Rate over the window, or `nil` before there is enough to divide by.
    public func perSecond(nowMs: Int64? = nil) -> Float? {
        let now = nowMs ?? self.nowMs()
        lock.lock(); defer { lock.unlock() }
        trim(now)
        if stamps.count < 2 { return nil }
        let span = stamps.last! - stamps.first!
        if span <= 0 { return nil }
        return Float(stamps.count - 1) * 1000 / Float(span)
    }
}

/// Every number needed to say where the skeleton's lag comes from, and the one line that reports
/// them.
///
/// ### Why this is a screen readout and not a log
///
/// The app reaches a phone as a build and the only channel back is what the athlete can see and
/// photograph. So the measurement has to survive being read off a band, which is why it is medians
/// of a short window rather than a stream, and why it is worded rather than packed.
public final class LatencyProbe: @unchecked Sendable {

    public let clock: FrameLatency
    public let analysisRate = RateMeter()

    private let age = Rolling()
    private let convert = Rolling()
    private let prep = Rolling()
    private let infer = Rolling()
    private let uiDelay = Rolling()

    private var posted = 0
    private var coalesced = 0

    public init(clock: FrameLatency = FrameLatency()) {
        self.clock = clock
    }

    public func reset() {
        age.reset(); convert.reset(); prep.reset(); infer.reset(); uiDelay.reset()
        analysisRate.reset()
        posted = 0
        coalesced = 0
    }

    /// One completed analysis pass. `captureAgeMs` is `nil` when the clock is unresolved.
    public func analysed(captureAgeMs: Int64?, convertMs: Int64, prepMs: Int64, inferMs: Int64) {
        if let captureAgeMs { age.add(captureAgeMs) }
        convert.add(convertMs)
        prep.add(prepMs)
        infer.add(inferMs)
        analysisRate.mark()
    }

    /// A snapshot handed to the main thread, and whether it replaced one not yet rendered.
    public func posted(replacedUnrendered: Bool) {
        posted += 1
        if replacedUnrendered { coalesced += 1 }
    }

    public func uiRan(delayMs: Int64) { uiDelay.add(delayMs) }

    /// Share of snapshots that were superseded before the main thread rendered them.
    ///
    /// This is the evidence for whether the main thread can keep up with the analysis thread: a
    /// high number here means it could not, which a post-per-frame arrangement would not have
    /// dropped anything for — it would have drawn every one of them, late and getting later.
    private func coalescedShare() -> Int? {
        posted == 0 ? nil : coalesced * 100 / posted
    }

    /// Two lines, because one row will not hold this and still be readable.
    public func line(model: String, drawnPerSecond: Float?) -> String {
        let ageText: String
        if let median = age.median() { ageText = "age \(median)ms" }
        else { ageText = clock.resolved ? "age —" : "age n/a (clock)" }
        let analysis = analysisRate.perSecond()
        func text(_ v: Int64?) -> String { v.map { String($0) } ?? "—" }

        var out = ageText
        out += " · cvt \(text(convert.median()))"
        out += " · pre \(text(prep.median()))"
        out += " · inf \(text(infer.median()))"
        out += " · ui \(text(uiDelay.median()))"
        out += "\n"
        out += model
        out += " · " + (analysis.map { javaFixed(Double($0), 1) } ?? "—") + " in"
        out += " · " + (drawnPerSecond.map { javaFixed(Double($0), 0) } ?? "—") + " drawn"
        if let share = coalescedShare() { out += " · \(share)% coalesced" }
        return out
    }
}

/// `String.format(Locale.US, "%.Nf", value)`, as Java writes it. See `JavaText.fixed`.
func javaFixed(_ value: Double, _ decimals: Int) -> String { JavaText.fixed(value, decimals) }
