import XCTest
import CindyCore

/// What is sent when, now that no WorkManager sends it: the ledger is the queue, and a drain runs
/// what is pending. No Kotlin test: WorkManager's own scheduling is what Android leans on, and these
/// hold the part iOS writes in its place.
final class StravaUploadQueueTests: XCTestCase {

    private let storage = InMemoryStravaStorage()
    private var ledger: StravaUploads { StravaUploads(storage: storage) }

    /// A clock the test moves, and a record of what ran.
    private final class Script: @unchecked Sendable {
        private let lock = NSLock()
        private var _now: Int64 = 1_000_000
        private var _ran: [Int64] = []
        var results: [Int64: [StravaRunResult]] = [:]
        var failing: Set<Int64> = []

        var now: Int64 {
            get { lock.lock(); defer { lock.unlock() }; return _now }
            set { lock.lock(); defer { lock.unlock() }; _now = newValue }
        }
        var ran: [Int64] { lock.lock(); defer { lock.unlock() }; return _ran }

        func next(_ at: Int64) throws -> StravaRunResult {
            lock.lock()
            defer { lock.unlock() }
            _ran.append(at)
            if failing.contains(at) { throw HttpRequestRefused(url: "x") }
            return results[at]?.isEmpty == false ? results[at]!.removeFirst() : .success
        }
    }

    private let script = Script()

    private func queue() -> StravaUploadQueue {
        let script = self.script
        return StravaUploadQueue(ledger: ledger, run: { try script.next($0) }, clock: { script.now })
    }

    /// pending is what is queued or processing, oldest first
    func testPendingIsWhatIsQueuedOrProcessingOldestFirst() {
        ledger.write(atMillis: 300, StravaUploadStatus(.queued))
        ledger.write(atMillis: 100, StravaUploadStatus(.processing, uploadId: "5"))
        ledger.write(atMillis: 200, StravaUploadStatus(.done, activityId: 1))
        ledger.write(atMillis: 400, StravaUploadStatus(.failed, message: "no"))
        ledger.write(atMillis: 500, StravaUploadStatus(.needsReconnect))
        ledger.write(atMillis: 600, StravaUploadStatus(.unavailable))
        XCTAssertEqual(queue().pending(), [100, 300])
    }

    /// a drain runs each pending attempt once, in order
    func testADrainRunsEachPendingAttemptOnceInOrder() async {
        ledger.queue(atMillis: 2)
        ledger.queue(atMillis: 1)
        let drained = await queue().drain(force: false)
        XCTAssertEqual(drained.ran, [1, 2])
        XCTAssertEqual(script.ran, [1, 2])
        XCTAssertNil(drained.nextDueMs)
    }

    /// a retry waits out its backoff, unless the drain is forced
    func testARetryWaitsOutItsBackoffUnlessTheDrainIsForced() async {
        ledger.queue(atMillis: 1)
        script.results[1] = [.retry, .success]
        let queue = queue()

        let first = await queue.drain(force: false)
        XCTAssertEqual(first.ran, [1])
        XCTAssertEqual(first.nextDueMs, 1_000_000 + 30_000)

        script.now += 29_999
        let early = await queue.drain(force: false)
        XCTAssertEqual(early.ran, [], "not due yet")
        XCTAssertEqual(early.nextDueMs, 1_030_000)

        script.now += 1
        let due = await queue.drain(force: false)
        XCTAssertEqual(due.ran, [1])
        XCTAssertNil(due.nextDueMs)
    }

    /// a forced drain runs a retry that is not yet due
    func testAForcedDrainRunsARetryThatIsNotYetDue() async {
        ledger.queue(atMillis: 1)
        script.results[1] = [.retry, .success]
        let queue = queue()
        _ = await queue.drain(force: false)

        let forced = await queue.drain(force: true)

        XCTAssertEqual(forced.ran, [1])
        XCTAssertEqual(script.ran, [1, 1])
    }

    /// each failure doubles the wait, from thirty seconds to five hours
    func testEachFailureDoublesTheWaitFromThirtySecondsToFiveHours() {
        XCTAssertEqual(StravaUploadQueue.backoffMs(failures: 1), 30_000)
        XCTAssertEqual(StravaUploadQueue.backoffMs(failures: 2), 60_000)
        XCTAssertEqual(StravaUploadQueue.backoffMs(failures: 3), 120_000)
        XCTAssertEqual(StravaUploadQueue.backoffMs(failures: 10), 15_360_000)
        XCTAssertEqual(StravaUploadQueue.backoffMs(failures: 11), 18_000_000)
        XCTAssertEqual(StravaUploadQueue.backoffMs(failures: 500), 18_000_000)
        XCTAssertEqual(StravaUploadQueue.backoffMs(failures: 0), 30_000)
    }

    /// repeated failures back off further each time
    func testRepeatedFailuresBackOffFurtherEachTime() async {
        ledger.queue(atMillis: 1)
        script.results[1] = [.retry, .retry]
        let queue = queue()
        _ = await queue.drain(force: false)
        script.now += 30_000
        let second = await queue.drain(force: false)
        XCTAssertEqual(second.nextDueMs, 1_030_000 + 60_000)
    }

    /// a refused upload and a finished one leave the queue, though the ledger decides what is pending
    func testARefusedUploadAndAFinishedOneLeaveTheQueue() async {
        ledger.queue(atMillis: 1)
        ledger.queue(atMillis: 2)
        script.results[1] = [.failure]
        // Run 2 does what a real run does when it finishes: the ledger no longer says pending.
        let ledger = self.ledger
        let script = self.script
        let queue = StravaUploadQueue(ledger: ledger, run: { at in
            let result = try script.next(at)
            if at == 2 { ledger.write(atMillis: 2, StravaUploadStatus(.done, activityId: 9)) }
            if at == 1 { ledger.write(atMillis: 1, StravaUploadStatus(.failed, message: "no")) }
            return result
        }, clock: { script.now })

        let drained = await queue.drain(force: false)

        XCTAssertEqual(drained.ran, [1, 2])
        XCTAssertNil(drained.nextDueMs)
        XCTAssertEqual(queue.pending(), [])
    }

    /// an upload that cannot be prepared is marked failed, not retried for ever
    func testAnUploadThatCannotBePreparedIsMarkedFailedNotRetriedForEver() async {
        ledger.queue(atMillis: 1)
        ledger.queue(atMillis: 2)
        script.failing = [1]

        let drained = await queue().drain(force: false)

        XCTAssertEqual(drained.ran, [1, 2], "one broken upload does not stop the next")
        XCTAssertEqual(ledger.status(atMillis: 1)?.state, .failed)
        XCTAssertEqual(ledger.status(atMillis: 1)?.message, "Couldn't prepare this upload")
        XCTAssertNil(drained.nextDueMs)
    }

    /// two drains at once never run the same attempt at the same time
    func testTwoDrainsAtOnceNeverRunTheSameAttemptAtTheSameTime() async {
        ledger.queue(atMillis: 1)
        let ledger = self.ledger
        let script = self.script
        let queue = StravaUploadQueue(ledger: ledger, run: { at in
            _ = try script.next(at)
            try? await Task.sleep(nanoseconds: 50_000_000)
            ledger.write(atMillis: at, StravaUploadStatus(.done, activityId: 1))
            return .success
        }, clock: { script.now })

        async let a = queue.drain(force: true)
        async let b = queue.drain(force: true)
        _ = await (a, b)

        XCTAssertEqual(script.ran, [1], "the second drain finds it done")
    }

    /// the run's own errors that are not the network's escape it, and a lost grant mid-poll asks to reconnect
    func testARefusedRequestEscapesTheRunAndALostGrantMidPollAsksToReconnect() async throws {
        let config = StravaConfig(clientId: "1", clientSecret: "s", applicationId: "com.cindy.tracker")
        let tokens = StravaTokenStore(storage: storage)
        tokens.grant = StravaGrant(accessToken: "a", refreshToken: "r",
                                   expiresAtEpochS: Int64(Date().timeIntervalSince1970) + 3_600, scopes: [], athleteName: nil)
        let attempt = Attempt(
            rounds: 1, reps: 0, atMillis: 7, durationMs: 20 * 60 * 1_000, profile: CindyProfile.standard, countedReps: 30,
            setSplits: [SetSplit(.pullup, 1_000, 5, 0), SetSplit(.pushup, 1_000, 10, 0), SetSplit(.squat, 1_000, 15, 0)])
        func run(_ transport: HttpTransport) -> StravaUploadRun {
            StravaUploadRun(config: config, transport: transport, tokens: tokens, ledger: ledger,
                            attempt: { _ in attempt }, trace: { _ in nil }, body: { Body(0) },
                            utcOffsetSeconds: { _ in 0 }, sleep: { _ in })
        }

        struct Refusing: HttpTransport {
            func execute(_ request: HttpRequest) async throws -> HttpResponse { throw HttpRequestRefused(url: request.url) }
        }
        do {
            _ = try await run(Refusing()).run(atMillis: 7)
            XCTFail("a refused request is a bug, and should not look like a retry")
        } catch is HttpRequestRefused {}

        // Accepted, then the grant is revoked before the first poll: the poll cannot ask for a token.
        let transport = FakeTransport()
        transport.enqueue(HttpResponse(201, [:], #"{"id_str":"9","error":null,"activity_id":null}"#))
        let revoking = StravaUploadRun(config: config, transport: transport, tokens: tokens, ledger: ledger,
                                       attempt: { _ in attempt }, trace: { _ in nil }, body: { Body(0) },
                                       utcOffsetSeconds: { _ in 0 }, sleep: { _ in tokens.clearGrant() })
        let result = try await revoking.run(atMillis: 7)
        XCTAssertEqual(result, .success)
        XCTAssertEqual(ledger.status(atMillis: 7)?.state, .needsReconnect)
    }
}
