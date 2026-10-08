import CindyCore

/// A main thread and a clock that do only what a test tells them: work posted to it waits for
/// `idle()`, and work scheduled for later waits for `advance(...)`. What Robolectric's looper is to
/// the Kotlin tests (`idle`, `idleFor`).
final class TestLoop {

    /// Milliseconds since the loop began; what a screen's clock reads.
    private(set) var nowMs: Int64 = 0

    private var posted: [() -> Void] = []
    private var timers: [(id: Int, at: Int64, work: () -> Void)] = []
    private var nextId = 0

    /// `Speaker`'s main-thread dispatcher.
    var main: Dispatcher { { [self] work in posted.append(work) } }

    /// A screen's scheduler.
    var scheduler: Scheduler {
        { [self] afterMs, work in
            nextId += 1
            let id = nextId
            timers.append((id, nowMs + afterMs, work))
            return { [self] in timers.removeAll { $0.id == id } }
        }
    }

    /// Runs everything posted, and whatever that posts in turn.
    func idle() {
        while !posted.isEmpty {
            let work = posted.removeFirst()
            work()
        }
    }

    /// Lets `ms` go by, running each timer at its moment and idling after it.
    func advance(_ ms: Int64) {
        let end = nowMs + ms
        idle()
        while let next = timers.filter({ $0.at <= end }).min(by: { ($0.at, $0.id) < ($1.at, $1.id) }) {
            timers.removeAll { $0.id == next.id }
            nowMs = max(nowMs, next.at)
            next.work()
            idle()
        }
        nowMs = end
        idle()
    }

    func advance(seconds: Int64) { advance(seconds * 1_000) }
}
