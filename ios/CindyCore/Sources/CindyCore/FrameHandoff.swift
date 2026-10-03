import Foundation

/// The handoff from the analysis thread to the main thread, which drops what is stale and keeps
/// what is irreplaceable.
///
/// ### The queue that had to go
///
/// Every analysed frame used to become its own posted block. The analysis thread never waits for
/// the main thread, so that is an unbounded queue: when the main thread falls behind — a text
/// layout, a speech call, a sheet arriving with its own window — blocks pile up, and every single
/// one is eventually rendered, each staler than the one before. The lag grows and never recovers,
/// which is a far better fit for "not in real time" than any fixed cost would be.
///
/// ### Why it cannot simply be a latest-value slot
///
/// Keeping only the newest frame fixes that, and would be correct if every frame were *state*.
/// Most are: a rep count, a hint, a status dot, a progress bar — render the newest and the ones
/// skipped never mattered.
///
/// Some are not. A frame carrying a `RepEvent` is the *only* notice that a rep was counted, undone,
/// or that a movement or round finished. Dropping one loses a vibration and a spoken number, and
/// for a finished round it loses that round's split from the session record permanently. Those are
/// events, and an event that is coalesced away has not been deferred, it has been lost.
///
/// So: events queue and are all delivered in order; state is a single slot holding only the
/// newest. Falling behind then costs *frames* rather than *freshness* — the same bargain the
/// camera already makes upstream by discarding late frames — without ever costing a rep.
public final class FrameHandoff<T>: @unchecked Sendable {

    private let lock = NSLock()
    private var events: [T] = []
    private var latest: T?

    public init() {}

    /// What became of a submitted frame, and whether the main thread needs waking for it.
    public enum Outcome: Sendable {
        /// Nothing was already scheduled to collect this: the caller must post a `drain`.
        case schedule

        /// This frame replaced a state frame that had not been rendered yet, and a drain is
        /// already scheduled. The displaced frame is gone — which is the point, and which is also
        /// the measurement: a high share of these says the main thread cannot keep up with the
        /// analysis thread, and so says that the old post-per-frame design was queueing.
        case replacedPending
    }

    /// Offers one frame from the analysis thread.
    public func submit(_ frame: T, isEvent: Bool) -> Outcome {
        lock.lock(); defer { lock.unlock() }
        if isEvent {
            events.append(frame)
            return .schedule
        }
        let wasEmpty = latest == nil
        latest = frame
        return wasEmpty ? .schedule : .replacedPending
    }

    /// Renders everything owed, oldest first: every event in order, then the newest state.
    ///
    /// Safe to call spuriously — a second scheduled drain simply finds nothing and returns, which
    /// is what makes the "should I schedule?" answer above allowed to be conservative. Nothing is
    /// held locked while rendering, so a render may submit.
    public func drain(_ render: (T) -> Void) {
        while true {
            lock.lock()
            let event = events.isEmpty ? nil : events.removeFirst()
            lock.unlock()
            guard let event else { break }
            render(event)
        }
        lock.lock()
        let state = latest
        latest = nil
        lock.unlock()
        if let state { render(state) }
    }

    /// Forgets everything owed. For teardown, and for a camera rebind that invalidates it all.
    public func clear() {
        lock.lock()
        events.removeAll()
        latest = nil
        lock.unlock()
    }
}
