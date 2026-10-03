import XCTest
import CindyCore

/// What the handoff is allowed to throw away.
///
/// The whole point of coalescing is to drop work, and the whole risk of it is dropping the wrong
/// work. A rep that never reaches the main thread is never buzzed, never spoken, and if it closed
/// a round its split never reaches the session record — so "events survive" is not a nicety here,
/// it is the same rule as "reps are banked, not inferred": the app books what happened, it does
/// not reconstruct it afterwards.
///
/// Mirrors `FrameHandoffTest.kt`.
final class FrameHandoffTests: XCTestCase {

    private func drained(_ h: FrameHandoff<String>) -> [String] {
        var out: [String] = []
        h.drain { out.append($0) }
        return out
    }

    /// only the newest state frame survives a backlog
    func testOnlyTheNewestStateFrameSurvivesABacklog() {
        let h = FrameHandoff<String>()
        XCTAssertEqual(h.submit("a", isEvent: false), .schedule)
        XCTAssertEqual(h.submit("b", isEvent: false), .replacedPending)
        XCTAssertEqual(h.submit("c", isEvent: false), .replacedPending)
        XCTAssertEqual(drained(h), ["c"])
    }

    /// every event survives, in order
    func testEveryEventSurvivesInOrder() {
        let h = FrameHandoff<String>()
        _ = h.submit("rep 1", isEvent: true)
        _ = h.submit("rep 2", isEvent: true)
        _ = h.submit("round done", isEvent: true)
        XCTAssertEqual(drained(h), ["rep 1", "rep 2", "round done"])
    }

    /// a flood of state frames cannot bury an event between them
    func testAFloodOfStateFramesCannotBuryAnEventBetweenThem() {
        let h = FrameHandoff<String>()
        for i in 0..<50 { _ = h.submit("state \(i)", isEvent: false) }
        _ = h.submit("rep", isEvent: true)
        for i in 0..<50 { _ = h.submit("state \(i + 50)", isEvent: false) }
        let out = drained(h)
        XCTAssertTrue(out.contains("rep"), "the rep must still be delivered, got \(out)")
        XCTAssertEqual(out.count, 2, "one event plus one surviving state frame")
        XCTAssertEqual(out.first, "rep", "the event is delivered before the newer state")
    }

    /// an event always asks to be scheduled, even behind a pending state frame
    func testAnEventAlwaysAsksToBeScheduledEvenBehindAPendingStateFrame() {
        let h = FrameHandoff<String>()
        _ = h.submit("state", isEvent: false)
        XCTAssertEqual(h.submit("rep", isEvent: true), .schedule,
                       "an event must never rely on someone else's runnable arriving")
    }

    /// draining twice is harmless
    func testDrainingTwiceIsHarmless() {
        let h = FrameHandoff<String>()
        _ = h.submit("rep", isEvent: true)
        _ = h.submit("state", isEvent: false)
        XCTAssertEqual(drained(h), ["rep", "state"])
        XCTAssertEqual(drained(h), [], "a spurious second drain renders nothing")
    }

    /// a drained slot schedules again on the next frame
    func testADrainedSlotSchedulesAgainOnTheNextFrame() {
        let h = FrameHandoff<String>()
        _ = h.submit("a", isEvent: false)
        _ = drained(h)
        XCTAssertEqual(h.submit("b", isEvent: false), .schedule,
                       "nothing is pending any more, so the next frame must post")
    }

    /// clear forgets both
    func testClearForgetsBoth() {
        let h = FrameHandoff<String>()
        _ = h.submit("rep", isEvent: true)
        _ = h.submit("state", isEvent: false)
        h.clear()
        XCTAssertEqual(drained(h), [])
    }

    // MARK: - what Kotlin got from ConcurrentLinkedQueue

    /// frames submitted from many threads at once are all accounted for
    func testFramesSubmittedFromManyThreadsAtOnceAreAllAccountedFor() {
        let h = FrameHandoff<Int>()
        let group = DispatchGroup()
        for t in 0..<8 {
            DispatchQueue.global().async(group: group) {
                for i in 0..<500 { _ = h.submit(t * 1000 + i, isEvent: true) }
            }
        }
        group.wait()
        var seen: [Int] = []
        h.drain { seen.append($0) }
        XCTAssertEqual(seen.count, 4_000, "no event was lost")
        XCTAssertEqual(Set(seen).count, 4_000, "and none was duplicated")
        for t in 0..<8 {
            let mine = seen.filter { $0 / 1000 == t }
            XCTAssertEqual(mine, mine.sorted(), "thread \(t)'s events stayed in order")
        }
    }
}
