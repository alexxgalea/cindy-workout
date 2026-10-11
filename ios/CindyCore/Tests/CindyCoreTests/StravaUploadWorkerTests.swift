import XCTest
import CindyCore

/// The upload's own decisions, over `FakeTransport` and no real waiting between polls.
///
/// Mirrors `StravaUploadWorkerTest.kt` (18). Android runs the worker under `TestListenableWorkerBuilder`;
/// here the same decisions are `StravaUploadRun.run`, with the records, the heart-rate trace and the
/// body handed in as closures.
final class StravaUploadWorkerTests: XCTestCase {

    private let atMillis: Int64 = 1_700_000_000_000
    private let config = StravaConfig(clientId: "12345", clientSecret: "s3cret", applicationId: "com.cindy.tracker")

    private let storage = InMemoryStravaStorage()
    private var tokens: StravaTokenStore { StravaTokenStore(storage: storage) }
    private var ledger: StravaUploads { StravaUploads(storage: storage) }

    private var records: [Int64: Attempt] = [:]
    private var traces: [Int64: HeartRateTrace] = [:]
    private var body = Body(0)

    private var nowS: Int64 { Int64(Date().timeIntervalSince1970) }

    private func connect(expiresInS: Int64 = 3_600) {
        tokens.grant = StravaGrant(accessToken: "tok", refreshToken: "ref", expiresAtEpochS: nowS + expiresInS,
                                   scopes: ["read", "activity:write"], athleteName: "Alex")
    }

    /// A refresh response StravaAuth can parse, far enough out to not need a second refresh.
    private func refreshResponse(_ accessToken: String) -> HttpResponse {
        HttpResponse(200, [:], """
            {"access_token":"\(accessToken)","refresh_token":"r2","expires_at":\(nowS + 3_600),"scope":"read,activity:write"}
            """)
    }

    /// A valid, single-round attempt whose splits already satisfy `StravaSets.from`.
    @discardableResult
    private func saveValidAttempt(at: Int64? = nil) -> Attempt {
        let at = at ?? atMillis
        let attempt = Attempt(
            rounds: 1, reps: 0, atMillis: at, durationMs: 20 * 60 * 1_000, profile: CindyProfile.standard,
            countedReps: 30,
            setSplits: [SetSplit(.pullup, 1_000, 5, 0), SetSplit(.pushup, 1_000, 10, 0), SetSplit(.squat, 1_000, 15, 0)])
        records[at] = attempt
        return attempt
    }

    private func run(_ transport: FakeTransport, at: Int64? = nil) async throws -> StravaRunResult {
        let records = self.records, traces = self.traces, body = self.body
        return try await StravaUploadRun(
            config: config, transport: transport, tokens: tokens, ledger: ledger,
            attempt: { records[$0] }, trace: { traces[$0] }, body: { body },
            utcOffsetSeconds: { _ in 0 },
            sleep: { _ in }  // no real waiting between polls in a test
        ).run(atMillis: at ?? atMillis)
    }

    private func status(_ at: Int64? = nil) -> StravaUploadStatus? { ledger.status(atMillis: at ?? atMillis) }

    private let accepted = HttpResponse(201, [:], #"{"id_str":"555","error":null,"activity_id":null}"#)
    private let processing = HttpResponse(200, [:], #"{"id_str":"555","error":null,"activity_id":null}"#)
    private func ready(_ id: Int) -> HttpResponse { HttpResponse(200, [:], #"{"id_str":"555","error":null,"activity_id":\#(id)}"#) }

    private func boundary(of request: HttpRequest) -> String {
        let type = request.contentType ?? ""
        return String(type[type.range(of: "boundary=")!.upperBound...])
    }

    /// The value of one simple (non-file) multipart field, e.g. "description".
    private func fieldPart(_ request: HttpRequest, _ name: String) -> String {
        let text = String(decoding: request.body ?? Data(), as: UTF8.self)
        let marker = "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
        let start = text.range(of: marker)!.upperBound
        let end = text.range(of: "\r\n--\(boundary(of: request))", range: start..<text.endIndex)!.lowerBound
        return String(text[start..<end])
    }

    /// Parses the "file" part's own body as the JSON payload it is.
    private func payload(of request: HttpRequest) throws -> [String: Any] {
        let text = String(decoding: request.body ?? Data(), as: UTF8.self)
        let marker = "Content-Type: application/json\r\n\r\n"
        let start = text.range(of: marker)!.upperBound
        let end = text.range(of: "\r\n--\(boundary(of: request))", range: start..<text.endIndex)!.lowerBound
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text[start..<end].utf8)) as? [String: Any])
    }

    private func count(_ transport: FakeTransport, _ method: String) -> Int {
        transport.requests.filter { $0.method == method }.count
    }

    // ---- gates before any network call -----------------------------------------------------

    /// not connected asks to reconnect instead of spinning
    func testNotConnectedAsksToReconnectInsteadOfSpinning() async throws {
        saveValidAttempt()
        let result = try await run(FakeTransport())
        XCTAssertEqual(result, .success)
        XCTAssertEqual(status()?.state, .needsReconnect)
    }

    /// an attempt no longer on record is unavailable
    func testAnAttemptNoLongerOnRecordIsUnavailable() async throws {
        connect()
        let result = try await run(FakeTransport())
        XCTAssertEqual(result, .success)
        XCTAssertEqual(status()?.state, .unavailable)
    }

    /// a set list that disagrees with the total is unavailable, not guessed at
    func testASetListThatDisagreesWithTheTotalIsUnavailableNotGuessedAt() async throws {
        connect()
        // countedReps disagrees with both the banked sets (30) and a plausible movement in
        // progress: exactly the sum-mismatch StravaSets.from refuses rather than guesses past.
        records[atMillis] = Attempt(
            rounds: 1, reps: 0, atMillis: atMillis, durationMs: 20 * 60 * 1_000, profile: CindyProfile.standard,
            countedReps: 999,
            setSplits: [SetSplit(.pullup, 1_000, 5, 0), SetSplit(.pushup, 1_000, 10, 0), SetSplit(.squat, 1_000, 15, 0)])

        let result = try await run(FakeTransport())
        XCTAssertEqual(result, .success)
        XCTAssertEqual(status()?.state, .unavailable)
    }

    // ---- the happy path and its polling ------------------------------------------------------

    /// the happy path posts once, polls once, and ends done
    func testTheHappyPathPostsOncePollsOnceAndEndsDone() async throws {
        connect()
        saveValidAttempt()
        let transport = FakeTransport()
        transport.enqueue(accepted)
        transport.enqueue(ready(42))

        let result = try await run(transport)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(status()?.state, .done)
        XCTAssertEqual(status()?.activityId, 42)
        XCTAssertEqual(count(transport, "POST"), 1)
        XCTAssertEqual(count(transport, "GET"), 1)
    }

    // ---- a saved heart-rate trace -------------------------------------------------------------

    /// a saved heart-rate trace rides along as a stream, and the description says so
    func testASavedHeartRateTraceRidesAlongAsAStreamAndTheDescriptionSaysSo() async throws {
        connect()
        body = Body(70, age: 35, sex: .male)
        let attempt = saveValidAttempt()
        let traceStart = attempt.atMillis - attempt.durationMs - 2_000
        // Every 5 s, exactly Calories.MAX_HOLD_MS, covers the whole clock with no gap.
        traces[atMillis] = HeartRateTrace(
            startedAtMillis: traceStart,
            samples: stride(from: Int64(0), to: attempt.durationMs, by: 5_000).map { HeartRateSample($0, 150) },
            pauses: [])
        let transport = FakeTransport()
        transport.enqueue(accepted)
        transport.enqueue(ready(42))

        let result = try await run(transport)
        XCTAssertEqual(result, .success)

        let post = try XCTUnwrap(transport.requests.first { $0.method == "POST" })
        let json = try payload(of: post)
        // 1,700,000,000,000 ms is 2023-11-14T22:13:20Z; the trace began 20 minutes and 2 s before.
        XCTAssertEqual(json["start_time"] as? String, "2023-11-14T21:53:18Z")
        let streams = try XCTUnwrap(json["streams"] as? [String: Any])
        let time = try XCTUnwrap(streams["time"] as? [Int])
        let heartrate = try XCTUnwrap(streams["heartrate"] as? [Int])
        XCTAssertGreaterThan(time.count, 0)
        XCTAssertEqual(time.count, heartrate.count)
        XCTAssertTrue(fieldPart(post, "description").contains("Calories estimated from heart rate"))
    }

    /// without a saved trace the upload is unchanged, carrying no heart-rate stream
    func testWithoutASavedTraceTheUploadIsUnchangedCarryingNoHeartRateStream() async throws {
        connect()
        body = Body(70, age: 35, sex: .male)
        saveValidAttempt()
        let transport = FakeTransport()
        transport.enqueue(accepted)
        transport.enqueue(ready(42))

        let result = try await run(transport)
        XCTAssertEqual(result, .success)

        let post = try XCTUnwrap(transport.requests.first { $0.method == "POST" })
        XCTAssertNil(try payload(of: post)["streams"])
        XCTAssertTrue(fieldPart(post, "description").contains("Calories estimated from body weight"))
    }

    /// polling more than once in one run still posts only once
    func testPollingMoreThanOnceInOneRunStillPostsOnlyOnce() async throws {
        connect()
        saveValidAttempt()
        let transport = FakeTransport()
        transport.enqueue(accepted)
        transport.enqueue(processing)
        transport.enqueue(ready(91))

        let result = try await run(transport)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(count(transport, "POST"), 1)
        XCTAssertEqual(count(transport, "GET"), 2)
        XCTAssertEqual(status()?.state, .done)
    }

    /// a poll that never finishes retries instead of waiting forever
    func testAPollThatNeverFinishesRetriesInsteadOfWaitingForever() async throws {
        connect()
        saveValidAttempt()
        let transport = FakeTransport()
        transport.enqueue(accepted)
        for _ in 0..<10 { transport.enqueue(processing) }

        let result = try await run(transport)

        XCTAssertEqual(result, .retry)
        XCTAssertEqual(status()?.state, .processing)
        XCTAssertEqual(status()?.uploadId, "555")
    }

    // ---- resuming after a process death ------------------------------------------------------

    /// a resumed worker polls instead of posting again
    func testAResumedRunPollsInsteadOfPostingAgain() async throws {
        connect()
        saveValidAttempt()
        // As if a previous run already had this accepted and died before it finished polling.
        ledger.write(atMillis: atMillis, StravaUploadStatus(.processing, uploadId: "555"))
        let transport = FakeTransport()
        transport.enqueue(ready(77))

        let result = try await run(transport)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(count(transport, "POST"), 0, "must never re-POST a file Strava already has")
        XCTAssertEqual(status()?.state, .done)
        XCTAssertEqual(status()?.activityId, 77)
    }

    /// queuing again while Strava is still processing keeps the upload id, so nothing is resent
    func testQueuingAgainWhileStravaIsStillProcessingKeepsTheUploadIdSoNothingIsResent() {
        connect()
        saveValidAttempt()
        ledger.write(atMillis: atMillis, StravaUploadStatus(.processing, uploadId: "555"))

        ledger.queue(atMillis: atMillis)

        XCTAssertEqual(status()?.state, .queued)
        XCTAssertEqual(status()?.uploadId, "555")
    }

    // ---- outcomes other than a clean Ready ---------------------------------------------------

    /// a duplicate upload is treated as done
    func testADuplicateUploadIsTreatedAsDone() async throws {
        connect()
        saveValidAttempt()
        let transport = FakeTransport()
        transport.enqueue(HttpResponse(201, [:], #"{"error":"cindy-\#(atMillis).json duplicate of activity 42"}"#))

        let result = try await run(transport)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(status()?.state, .done)
        XCTAssertEqual(status()?.activityId, 42)
    }

    /// a rejected upload fails without asking to retry
    func testARejectedUploadFailsWithoutAskingToRetry() async throws {
        connect()
        saveValidAttempt()
        let transport = FakeTransport()
        transport.enqueue(HttpResponse(400, [:], #"{"message":"invalid sport_type"}"#))

        let result = try await run(transport)

        XCTAssertEqual(result, .failure)
        XCTAssertEqual(status()?.state, .failed)
        XCTAssertEqual(status()?.message, "invalid sport_type")
    }

    /// a 401 refreshes once and finishes the upload with the new token
    func testA401RefreshesOnceAndFinishesTheUploadWithTheNewToken() async throws {
        connect()
        saveValidAttempt()
        let transport = FakeTransport()
        transport.enqueue(HttpResponse(401, [:], #"{"message":"Unauthorized"}"#))
        transport.enqueue(refreshResponse("freshA"))
        transport.enqueue(HttpResponse(201, [:], #"{"id_str":"9","error":null,"activity_id":100}"#))

        let result = try await run(transport)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(status()?.state, .done)
        XCTAssertEqual(tokens.grant?.accessToken, "freshA")
        // upload, refresh, retried upload -- never a second refresh, never a third upload.
        XCTAssertEqual(transport.requests.count, 3)
    }

    /// a 401 that survives a refresh asks to reconnect
    func testA401ThatSurvivesARefreshAsksToReconnect() async throws {
        connect()
        saveValidAttempt()
        let transport = FakeTransport()
        transport.enqueue(HttpResponse(401, [:], #"{"message":"Unauthorized"}"#))
        transport.enqueue(refreshResponse("freshA"))
        transport.enqueue(HttpResponse(401, [:], #"{"message":"Unauthorized"}"#))

        let result = try await run(transport)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(status()?.state, .needsReconnect)
    }

    /// a 401 whose own refresh is rejected asks to reconnect without a second upload
    func testA401WhoseOwnRefreshIsRejectedAsksToReconnectWithoutASecondUpload() async throws {
        connect()
        saveValidAttempt()
        let transport = FakeTransport()
        transport.enqueue(HttpResponse(401, [:], #"{"message":"Unauthorized"}"#))
        transport.enqueue(HttpResponse(401, [:], #"{"message":"Unauthorized"}"#))  // the refresh itself

        let result = try await run(transport)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(status()?.state, .needsReconnect)
        XCTAssertNil(tokens.grant, "a refresh Strava rejects must clear the grant")
        XCTAssertEqual(transport.requests.count, 2)
    }

    /// a 5xx is worth retrying
    func testA5xxIsWorthRetrying() async throws {
        connect()
        saveValidAttempt()
        let transport = FakeTransport()
        transport.enqueue(HttpResponse(503, [:], "oops"))
        let result = try await run(transport)
        XCTAssertEqual(result, .retry)
    }

    /// rate limiting is worth retrying
    func testRateLimitingIsWorthRetrying() async throws {
        connect()
        saveValidAttempt()
        let transport = FakeTransport()
        transport.enqueue(HttpResponse(429, ["Retry-After": ["30"]], ""))
        let result = try await run(transport)
        XCTAssertEqual(result, .retry)
    }

    /// a network failure is worth retrying
    func testANetworkFailureIsWorthRetrying() async throws {
        connect()
        saveValidAttempt()
        let transport = FakeTransport()
        transport.enqueueFailure(HttpTransportError("no network"))
        let result = try await run(transport)
        XCTAssertEqual(result, .retry)
    }
}
