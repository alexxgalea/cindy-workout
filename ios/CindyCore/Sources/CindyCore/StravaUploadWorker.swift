import Foundation

/// How one run of the upload ended, in WorkManager's three words.
public enum StravaRunResult: Equatable, Sendable {
    /// Done with, whatever the ledger now says: uploaded, or waiting on the athlete, or unavailable.
    case success
    /// Not done, and worth another go later.
    case retry
    /// Refused for good.
    case failure
}

/// Sends one saved attempt to Strava, and keeps polling until it knows what happened.
///
/// The body of Android's `StravaUploadWorker.doWork`. Every branch ends by writing the ledger and
/// returning a `StravaRunResult`, never both retrying *and* leaving the ledger saying something
/// that retry might contradict. What WorkManager gave Android (running it when there is a network,
/// again after a delay) is `StravaUploadQueue`'s and the app's; this is only the decisions, with
/// the transport, the records, the clock and the waiting handed in.
public struct StravaUploadRun: Sendable {

    private let config: StravaConfig
    private let transport: HttpTransport
    private let tokens: StravaTokenStore
    private let ledger: StravaUploads
    private let attempt: @Sendable (Int64) -> Attempt?
    private let trace: @Sendable (Int64) -> HeartRateTrace?
    private let body: @Sendable () -> Body
    private let utcOffsetSeconds: @Sendable (Int64) -> Int
    private let sleep: @Sendable (Int64) async -> Void
    private let clock: @Sendable () -> Int64

    /// - Parameters:
    ///   - attempt: the saved attempt filed at that `atMillis`, or nil when the board no longer has it.
    ///   - trace: the heart-rate trace saved beside it.
    ///   - body: what the athlete told the app about themselves, for the calorie estimate.
    ///   - utcOffsetSeconds: the phone's offset from UTC at that epoch millisecond.
    ///   - sleep: waits that many milliseconds between polls; a test hands in one that returns at once.
    public init(
        config: StravaConfig, transport: HttpTransport, tokens: StravaTokenStore, ledger: StravaUploads,
        attempt: @escaping @Sendable (Int64) -> Attempt?,
        trace: @escaping @Sendable (Int64) -> HeartRateTrace?,
        body: @escaping @Sendable () -> Body,
        utcOffsetSeconds: @escaping @Sendable (Int64) -> Int,
        sleep: @escaping @Sendable (Int64) async -> Void = { ms in try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000) },
        clock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.config = config
        self.transport = transport
        self.tokens = tokens
        self.ledger = ledger
        self.attempt = attempt
        self.trace = trace
        self.body = body
        self.utcOffsetSeconds = utcOffsetSeconds
        self.sleep = sleep
        self.clock = clock
    }

    /// Anything that is not a network failure, an unreadable reply or a lost connection to Strava
    /// escapes, as it does Android's worker: it is a bug, and retrying would repeat it.
    public func run(atMillis: Int64) async throws -> StravaRunResult {
        // The work must not spin waiting for a reconnect that has to come from the athlete.
        if !tokens.connected {
            ledger.write(atMillis: atMillis, StravaUploadStatus(.needsReconnect))
            return .success
        }

        let saved = attempt(atMillis)
        let sets = saved.flatMap(StravaSets.from)
        guard let attempt = saved, let sets = sets else {
            ledger.write(atMillis: atMillis, StravaUploadStatus(.unavailable))
            return .success
        }

        let auth = StravaAuth(transport: transport, config: config)
        let session = StravaSession(store: tokens, auth: auth, clock: clock)
        let api = StravaApi(transport: transport, token: session)

        let saveTrace = trace(atMillis)
        let startMillis = saveTrace?.startedAtMillis ?? startMillisOf(attempt)

        func send() async throws -> UploadOutcome {
            if let existingId = ledger.status(atMillis: atMillis)?.uploadId {
                return try await api.status(existingId)
            }
            let composed = try StravaComposer.compose(
                attempt, sets, startMillis: startMillis, utcOffsetSeconds: utcOffsetSeconds(startMillis),
                trace: saveTrace, body: body())
            return try await api.upload(json: composed.payload, name: composed.name,
                                        description: composed.description, externalId: "cindy-\(atMillis)")
        }

        do {
            var outcome = try await send()
            // A token that looked valid a moment ago can still be refused. One forced refresh and
            // one retry is worth it before asking the athlete to reconnect over what may just have
            // been a token that expired between the check above and the request.
            if outcome == .unauthorized {
                outcome = try await session.forceRefresh() ? try await send() : .unauthorized
            }
            return try await handle(atMillis, outcome, api)
        } catch is StravaAuthError {
            ledger.write(atMillis: atMillis, StravaUploadStatus(.needsReconnect))
            return .success
        } catch is HttpTransportError {
            // A refresh or a call that failed on the network, with no Strava semantics in it at
            // all -- always worth retrying.
            return .retry
        } catch is StravaResponseError {
            return .retry
        }
    }

    /// Writes the ledger for `outcome` and says whether to go again.
    private func handle(_ atMillis: Int64, _ outcome: UploadOutcome, _ api: StravaApi) async throws -> StravaRunResult {
        switch outcome {
        case .processing(let uploadId):
            // Persisted before anything else: the next run must see this uploadId even if the
            // process dies before this call returns, or a retry would re-POST a file Strava has.
            ledger.write(atMillis: atMillis, StravaUploadStatus(.processing, uploadId: uploadId))
            return try await poll(atMillis, uploadId, api)
        case .ready(let activityId):
            ledger.write(atMillis: atMillis, StravaUploadStatus(.done, activityId: activityId))
            return .success
        case .duplicate(let activityId):
            ledger.write(atMillis: atMillis, StravaUploadStatus(.done, activityId: activityId))
            return .success
        case .rejected(let message):
            ledger.write(atMillis: atMillis, StravaUploadStatus(.failed, message: message))
            return .failure
        case .unauthorized:
            ledger.write(atMillis: atMillis, StravaUploadStatus(.needsReconnect))
            return .success
        case .rateLimited, .transient:
            return .retry
        }
    }

    /// Polls `uploadId` at 1 s, 2 s, 3 s … until it stops processing or about `pollBudgetMs` has
    /// passed, whichever comes first. Strava's own docs put mean processing under two seconds, so
    /// this is generous rather than expected to run out; when it does, the run retries and the
    /// *next* one resumes the poll: the ledger already has the uploadId, so that run never POSTs
    /// again.
    private func poll(_ atMillis: Int64, _ uploadId: String, _ api: StravaApi) async throws -> StravaRunResult {
        var waitMs: Int64 = 1_000
        var elapsedMs: Int64 = 0
        while elapsedMs < Self.pollBudgetMs {
            await sleep(waitMs)
            elapsedMs += waitMs
            let outcome = try await api.status(uploadId)
            if case .processing = outcome { waitMs += 1_000; continue }
            return try await handle(atMillis, outcome, api)
        }
        return .retry
    }

    private static let pollBudgetMs: Int64 = 30_000
}

/// What is still to be sent, and when each retry is due.
///
/// Android hands this to WorkManager: a unique work per attempt, run when there is a network, and
/// again after an exponential backoff from 30 seconds. iOS has no such scheduler for an app that
/// is not running, so the ledger is the persisted queue (an attempt that is `queued` or
/// `processing` is one still to be sent or checked) and this drains it whenever the app is able
/// to: right after a session, when it comes forward, when a network appears, and when a background
/// refresh runs. An upload may therefore wait until the app is next opened.
///
/// One drain runs at a time, so an attempt is never sent twice at once.
public final class StravaUploadQueue: @unchecked Sendable {

    /// What a drain left behind.
    public struct Drained: Equatable, Sendable {
        /// Attempts run this time.
        public let ran: [Int64]
        /// The soonest a retry falls due, or nil when nothing is waiting on one.
        public let nextDueMs: Int64?
    }

    private let ledger: StravaUploads
    private let run: @Sendable (Int64) async throws -> StravaRunResult
    private let clock: @Sendable () -> Int64

    private let state = NSLock()
    private var retries: [Int64: (failures: Int, notBefore: Int64)] = [:]
    private static let lock = AsyncLock()

    public init(ledger: StravaUploads,
                run: @escaping @Sendable (Int64) async throws -> StravaRunResult,
                clock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.ledger = ledger
        self.run = run
        self.clock = clock
    }

    /// The attempts still to be sent or checked, oldest first.
    public func pending() -> [Int64] {
        ledger.entries().filter { $0.status.state == .queued || $0.status.state == .processing }.map(\.atMillis)
    }

    /// WorkManager's backoff: 30 s, doubling, never more than five hours.
    public static func backoffMs(failures: Int) -> Int64 {
        let doublings = min(max(failures - 1, 0), 20)
        return min(30_000 * (Int64(1) << Int64(doublings)), 5 * 60 * 60 * 1_000)
    }

    /// Runs what is pending. `force` runs the attempts whose retry is not yet due too, as a new
    /// network or the app coming forward should; without it they wait for their time.
    public func drain(force: Bool) async -> Drained {
        await Self.lock.withLock {
            var ran: [Int64] = []
            for atMillis in pending() {
                let now = clock()
                if !force, let retry = retry(atMillis), retry.notBefore > now { continue }
                ran.append(atMillis)
                do {
                    switch try await run(atMillis) {
                    case .success, .failure: forget(atMillis)
                    case .retry: failed(atMillis, now: clock())
                    }
                } catch {
                    // A bug in what was sent, not the network's doing: retrying would repeat it for
                    // ever, so the attempt is marked failed where the athlete can see it.
                    ledger.write(atMillis: atMillis, StravaUploadStatus(.failed, message: "Couldn't prepare this upload"))
                    forget(atMillis)
                }
            }
            return Drained(ran: ran, nextDueMs: nextDue())
        }
    }

    private func retry(_ atMillis: Int64) -> (failures: Int, notBefore: Int64)? {
        state.lock()
        defer { state.unlock() }
        return retries[atMillis]
    }

    private func forget(_ atMillis: Int64) {
        state.lock()
        defer { state.unlock() }
        retries[atMillis] = nil
    }

    private func failed(_ atMillis: Int64, now: Int64) {
        state.lock()
        defer { state.unlock() }
        let failures = (retries[atMillis]?.failures ?? 0) + 1
        retries[atMillis] = (failures, now + Self.backoffMs(failures: failures))
    }

    private func nextDue() -> Int64? {
        let waiting = Set(pending())
        state.lock()
        defer { state.unlock() }
        return retries.filter { waiting.contains($0.key) }.map(\.value.notBefore).min()
    }
}
